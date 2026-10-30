# Prepare only. This script never invokes SteamCMD or changes the source build.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$WorkDirectory,
    [switch]$RepairMissingPublicConfig,
    [string]$ConfigFile,
    [string]$Godot = 'C:/src/tools/godot/Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
$work = [IO.Path]::GetFullPath($WorkDirectory)
if (Test-Path -LiteralPath $output) { throw 'OutputDirectory must be new; existing builds are never overwritten.' }
if (Test-Path -LiteralPath $work) { throw 'WorkDirectory must be new.' }
if ($output.StartsWith($source + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $output -eq $source) { throw 'Output must be outside the source build.' }
foreach ($pair in @(@($work,$source), @($work,$output), @($output,$work))) {
    if ($pair[0] -eq $pair[1] -or $pair[0].StartsWith($pair[1]+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Source, output and work directories must not overlap.' }
}
$packs = @(Get-ChildItem -LiteralPath $source -Filter '*.pck' -File)
if ($packs.Count -ne 1) { throw 'Exactly one standalone PCK is required.' }
$packName = $packs[0].Name
$exeName = $packs[0].BaseName + '.exe'
$required = @($exeName, $packName, 'libgodotsteam.windows.template_release.x86_64.dll', 'steam_api64.dll')
foreach ($name in $required) { if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) { throw "Missing runtime file: $name" } }

function Read-Pack([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $r = [IO.BinaryReader]::new($stream)
    try {
        if ($r.ReadUInt32() -ne 0x43504447 -or $r.ReadUInt32() -ne 4) { throw 'Only Godot PCK v4 is supported.' }
        $major=$r.ReadUInt32(); $minor=$r.ReadUInt32(); $patch=$r.ReadUInt32()
        if ("$major.$minor.$patch" -ne '4.7.2') { throw 'PCK must be Godot 4.7.2.' }
        if ($r.ReadUInt32() -ne 2) { throw 'Only unencrypted, relative-base PCKs are supported.' }
        $base=$r.ReadUInt64(); $directory=$r.ReadUInt64()
        if ($directory -ge $stream.Length) { throw 'Invalid PCK directory.' }
        $stream.Position=$directory
        $count=$r.ReadUInt32()
        if ($count -gt 100000) { throw 'Invalid PCK file count.' }
        $items=[Collections.Generic.List[object]]::new()
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        for ($i=0; $i -lt $count; $i++) {
            $length=$r.ReadUInt32()
            if ($length -lt 1 -or $length -gt 4096) { throw 'Invalid PCK path length.' }
            $pathBytes=$r.ReadBytes($length)
            $name=[Text.Encoding]::UTF8.GetString($pathBytes).TrimEnd([char]0)
            if (-not $seen.Add($name) -or $name.Contains('..') -or $name.StartsWith('/')) { throw 'Unsafe or duplicate PCK path.' }
            $offset=$r.ReadUInt64(); $size=$r.ReadUInt64(); $md5=$r.ReadBytes(16); $flags=$r.ReadUInt32()
            if ($flags -ne 0 -or $offset + $base + $size -gt $directory) { throw 'Unsupported or invalid PCK entry.' }
            $items.Add([pscustomobject]@{Name=$name;PathBytes=$pathBytes;Offset=$offset;Size=$size;MD5=$md5;Flags=$flags})
        }
        return [pscustomobject]@{Base=$base;Directory=$directory;Items=$items;DirectoryEnd=$stream.Position}
    } finally { $r.Dispose() }
}

function Read-Entry([string]$Path, $Pack, $Entry) {
    if ($Entry.Size -gt [int]::MaxValue) { throw 'PCK entry too large.' }
    $stream=[IO.File]::OpenRead($Path)
    $r=[IO.BinaryReader]::new($stream)
    try { $stream.Position=$Pack.Base+$Entry.Offset; return ,$r.ReadBytes([int]$Entry.Size) }
    finally { $r.Dispose() }
}

$basePack=Read-Pack $packs[0].FullName
$publicEntries=@($basePack.Items | Where-Object Name -eq 'supabase_public.env')
if ($RepairMissingPublicConfig -and $publicEntries.Count -ne 0) { throw 'Repair is only for a PCK missing public config.' }
New-Item -ItemType Directory -Path $work | Out-Null
$content=Join-Path $output 'content'
New-Item -ItemType Directory -Path $content | Out-Null
foreach ($name in $required) { Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $content $name) }
$targetPack=Join-Path $content $packName

if ($RepairMissingPublicConfig) {
    # Use the existing generator and validator in a minimal isolated project.
    $mini=Join-Path $work 'config-project'
    New-Item -ItemType Directory -Path $mini | Out-Null
    [IO.File]::WriteAllText((Join-Path $mini 'project.godot'), "config_version=5`n[application]`nconfig/name=`"ReleaseConfig`"`n")
    Copy-Item -LiteralPath (Join-Path $repo 'src/bossmaker/online/rbm_supabase_config.gd') -Destination $mini
    Copy-Item -LiteralPath (Join-Path $repo 'tools/make_supabase_public_config.gd') -Destination $mini
    if ($ConfigFile) {
        $publicLines=@(Get-Content -LiteralPath $ConfigFile | Where-Object { $_ -match '^\s*SUPABASE_(URL|PUBLISHABLE_KEY)\s*=' })
        [IO.File]::WriteAllLines((Join-Path $mini 'supabase_poc.local.env'),[string[]]$publicLines)
    }
    & $Godot --headless --path $mini --editor --import --quit *> (Join-Path $work 'config_import.log')
    if ($LASTEXITCODE -ne 0) { throw 'Config project import failed.' }
    & $Godot --headless --path $mini -s res://make_supabase_public_config.gd *> (Join-Path $work 'config_generate.log')
    if ($LASTEXITCODE -ne 0) { throw 'Public config generation failed; values are not logged.' }
    & $Godot --headless --path $mini -s res://make_supabase_public_config.gd -- --check *> (Join-Path $work 'config_check.log')
    if ($LASTEXITCODE -ne 0) { throw 'Public config validation failed.' }
    $bytes=[IO.File]::ReadAllBytes((Join-Path $mini 'supabase_public.env'))
    # Append one file and a replacement directory. Existing resource bytes and offsets stay unchanged.
    $stream=[IO.File]::Open($targetPack, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite)
    $w=[IO.BinaryWriter]::new($stream)
    try {
        $stream.Position=$stream.Length
        while ($stream.Position % 16) { $w.Write([byte]0) }
        $offset=[uint64]($stream.Position-$basePack.Base)
        $w.Write($bytes)
        while ($stream.Position % 16) { $w.Write([byte]0) }
        $directory=[uint64]$stream.Position
        $w.Write([uint32]($basePack.Items.Count+1))
        foreach ($e in $basePack.Items) { $w.Write([uint32]$e.PathBytes.Length);$w.Write([byte[]]$e.PathBytes);$w.Write([uint64]$e.Offset);$w.Write([uint64]$e.Size);$w.Write([byte[]]$e.MD5);$w.Write([uint32]$e.Flags) }
        $pathBytes=[Text.Encoding]::UTF8.GetBytes('supabase_public.env')
        $padded=[byte[]]::new([int]([Math]::Ceiling($pathBytes.Length/4.0)*4))
        [Array]::Copy($pathBytes,$padded,$pathBytes.Length)
        $w.Write([uint32]$padded.Length);$w.Write($padded);$w.Write($offset);$w.Write([uint64]$bytes.Length);$w.Write([Security.Cryptography.MD5]::HashData($bytes));$w.Write([uint32]0)
        $stream.Position=32; $w.Write($directory)
    } finally { $w.Dispose() }
}

$newPack=Read-Pack $targetPack
$newPublic=@($newPack.Items | Where-Object Name -eq 'supabase_public.env')
if ($newPublic.Count -ne 1) { throw 'PCK has no unique public config; upload preparation refused.' }
$publicText=[Text.Encoding]::UTF8.GetString((Read-Entry $targetPack $newPack $newPublic[0]))
$values=@{}
foreach ($line in ($publicText -split "`n")) {
    $line=$line.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    if ($line -notmatch '^(SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY)=(.+)$' -or $values.ContainsKey($matches[1])) { throw 'Public config has unexpected/duplicate fields.' }
    $values[$matches[1]]=$matches[2]
}
if ($values.Count -ne 2 -or -not $values['SUPABASE_URL'].StartsWith('https://')) { throw 'Invalid public config.' }
$key=$values['SUPABASE_PUBLISHABLE_KEY']
$isPublic=$key.StartsWith('sb_publishable_') -and $key.Length -gt 15
if (-not $isPublic -and $key.Split('.').Count -eq 3) {
    try { $payload=$key.Split('.')[1].Replace('-','+').Replace('_','/');while($payload.Length%4){$payload+='='};$isPublic=([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))|ConvertFrom-Json).role -eq 'anon' } catch { $isPublic=$false }
}
if (-not $isPublic) { throw 'Only a publishable/anon key may ship.' }
$preserved=0
foreach ($e in $basePack.Items) {
    $new=@($newPack.Items | Where-Object Name -eq $e.Name)
    if ($new.Count -ne 1) { throw 'Original PCK resource missing.' }
    $before=Read-Entry $packs[0].FullName $basePack $e
    $after=Read-Entry $targetPack $newPack $new[0]
    if ($e.Name -match '(?i)(\.env($|\.)|steam(_dev)?_appid.*\.txt$)' -and $e.Name -ne 'supabase_public.env') { throw 'Development config found in PCK.' }
    $text=[Text.Encoding]::UTF8.GetString($after)
    if ($text -match 'sb_secret_[A-Za-z0-9_-]{16,}') { throw 'Secret key material found in PCK.' }
    foreach ($token in [regex]::Matches($text, 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')) {
        try { $payload=$token.Value.Split('.')[1].Replace('-','+').Replace('_','/');while($payload.Length%4){$payload+='='};$role=([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))|ConvertFrom-Json).role } catch { continue }
        if ($role -eq 'service_role') { throw 'Service-role JWT found in PCK.' }
    }
    $hash=[Security.Cryptography.MD5]::HashData($after)
    if ([Convert]::ToHexString($hash) -ne [Convert]::ToHexString($e.MD5) -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($before)) -ne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($after))) { throw 'Original resource content changed or is corrupt.' }
    $preserved++
}
if ($newPack.Items.Count -ne $basePack.Items.Count + [int]$RepairMissingPublicConfig.IsPresent) { throw 'Unexpected PCK additions.' }
# Verify with the existing Godot PCK checker. Resolve external DLLs beside an isolated editor copy.
$runner=Join-Path $work 'runner'
New-Item -ItemType Directory -Path $runner | Out-Null
$runnerGodot=Join-Path $runner ([IO.Path]::GetFileName($Godot))
Copy-Item -LiteralPath $Godot -Destination $runnerGodot
if ($Godot.EndsWith('_console.exe')) {
    $gui=$Godot.Substring(0,$Godot.Length-'_console.exe'.Length)+'.exe'
    Copy-Item -LiteralPath $gui -Destination (Join-Path $runner ([IO.Path]::GetFileName($gui)))
}
foreach ($dll in $required | Where-Object { $_.EndsWith('.dll') }) { Copy-Item -LiteralPath (Join-Path $content $dll) -Destination $runner }
$debugDllDir=Join-Path $runner 'addons/godotsteam/win64'
New-Item -ItemType Directory -Path $debugDllDir -Force | Out-Null
foreach ($dll in @('libgodotsteam.windows.template_debug.x86_64.dll','steam_api64.dll')) {
    Copy-Item -LiteralPath (Join-Path $repo "addons/godotsteam/win64/$dll") -Destination $debugDllDir
}
$report=Join-Path $output 'pack_check.json'
& $runnerGodot --headless --path $runner --main-pack $targetPack -s (Join-Path $repo 'tools/check_release_pack.gd') --log-file (Join-Path $work 'pack_check.log') -- "--report=$report" *> (Join-Path $work 'pack_check_console.log')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $report)) { throw 'Godot PCK check failed.' }
if (Select-String -LiteralPath (Join-Path $work 'pack_check_console.log') -Pattern 'ERROR:|SCRIPT ERROR:' -Quiet) { throw 'Godot reported an engine/script error during PCK validation.' }
$check=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
if (@($check.problems).Count -ne 0 -or -not $check.public_config_ok) { throw 'PCK check refused upload preparation.' }
$hashes=@(foreach ($name in $required) {
    $h=(Get-FileHash -LiteralPath (Join-Path $content $name) -Algorithm SHA256).Hash
    $original=(Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA256).Hash
    if ($name -ne $packName -and $h -ne $original) { throw 'Runtime binary changed.' }
    [pscustomobject]@{file=$name;sha256=$h;source_sha256=$original}
})
[ordered]@{mode=$(if($RepairMissingPublicConfig){'public-config-only-repair'}else{'validate-and-prepare'});source=$source;preserved_resources=$preserved;added_resources=[int]$RepairMissingPublicConfig.IsPresent;files=$hashes;public_config_ok=$true;steam_upload_performed=$false} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'release_manifest.json') -Encoding utf8
# Exact file mappings exclude reports, configs outside the PCK, and temporary files.
$mapping=($required | ForEach-Object { "    `"FileMapping`" { `"LocalPath`" `"$_`" `"DepotPath`" `"$_`" `"recursive`" `"0`" }" }) -join "`n"
@"
"DepotBuildConfig"
{
    "DepotID" "5482411"
    "contentroot" "$($content.Replace('\','/'))"
$mapping
}
"@ | Set-Content -LiteralPath (Join-Path $output 'depot_5482411.vdf') -Encoding utf8NoBOM
@"
"appbuild"
{
    "appid" "5482410"
    "desc" "Windows x64 public config repair"
    "buildoutput" "$($output.Replace('\','/'))/steam_build_logs"
    "setlive" ""
    "preview" "0"
    "depots" { "5482411" "$($output.Replace('\','/'))/depot_5482411.vdf" }
}
"@ | Set-Content -LiteralPath (Join-Path $output 'app_5482410.vdf') -Encoding utf8NoBOM
$manifestPath=Join-Path $output 'release_manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest | Add-Member -NotePropertyName steam_configs -NotePropertyValue @(foreach ($name in @('app_5482410.vdf','depot_5482411.vdf')) { [pscustomobject]@{file=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $output $name) -Algorithm SHA256).Hash} })
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
& (Join-Path $repo 'tools/verify_steam_upload.ps1') -PreparedDirectory $output
Write-Output "STEAM_PREPARED preserved_resources=$preserved public_config_ok=true uploads=0 output=$output"
