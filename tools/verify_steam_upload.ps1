# Run immediately before using the generated app_5482410.vdf. Never uploads.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PreparedDirectory)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $PreparedDirectory).Path
$report=Get-Content -LiteralPath (Join-Path $root 'pack_check.json') -Raw | ConvertFrom-Json
$manifest=Get-Content -LiteralPath (Join-Path $root 'release_manifest.json') -Raw | ConvertFrom-Json
if (-not $report.public_config_ok -or @($report.problems).Count -ne 0 -or -not $manifest.public_config_ok) { throw 'PCK check has not passed.' }
foreach ($config in $manifest.steam_configs) {
    if ($config.file -notin @('app_5482410.vdf','depot_5482411.vdf')) { throw 'Unexpected Steam config.' }
    if ((Get-FileHash -LiteralPath (Join-Path $root $config.file) -Algorithm SHA256).Hash -ne $config.sha256) { throw 'Steam config changed after preparation.' }
}
$content=Join-Path $root 'content'
$actual=@(Get-ChildItem -LiteralPath $content -Force)
if ($actual.Count -ne @($manifest.files).Count -or @($actual | Where-Object PSIsContainer).Count) { throw 'Unexpected upload content.' }
$depot=Get-Content -LiteralPath (Join-Path $root 'depot_5482411.vdf') -Raw
if (-not $depot.Contains('"contentroot" "'+$content.Replace('\','/')+'"') -or $depot.Contains('"LocalPath" "*"')) { throw 'Depot content root or mappings changed.' }
foreach ($entry in $manifest.files) {
    if ([IO.Path]::GetFileName($entry.file) -ne $entry.file) { throw 'Unsafe manifest filename.' }
    if ((Get-FileHash -LiteralPath (Join-Path $content $entry.file) -Algorithm SHA256).Hash -ne $entry.sha256) { throw "Content changed after validation: $($entry.file)" }
    if (-not $depot.Contains('"LocalPath" "'+$entry.file+'" "DepotPath" "'+$entry.file+'" "recursive" "0"')) { throw 'Depot mapping changed.' }
}
$app=Get-Content -LiteralPath (Join-Path $root 'app_5482410.vdf') -Raw
if (-not $app.Contains('"5482411" "'+$root.Replace('\','/')+'/depot_5482411.vdf"') -or -not $app.Contains('"appid" "5482410"')) { throw 'App depot configuration changed.' }
Write-Output "STEAM_UPLOAD_CHECK_OK files=$($actual.Count) hashes_match=true uploads=0"
