# 体験版（Makers & Challengers Demo、AppID 5521380）の Steam アップロードの準備だけをする（2026-10-28）。
# SteamCMD は実行しない。製品版（AppID 5482410）の設定・スクリプト（prepare_steam_release.ps1 など）には触れない。
#
# 使い方（Windows PowerShell 5.1 / PowerShell 7 のどちらでも動く）:
#   1. 体験版を書き出す（Git Bash）:  bash tools/build_release_windows.sh <書き出し先> demo
#   2. アップロード用のフォルダを作る:
#        powershell -NoProfile -File tools/prepare_steam_demo_upload.ps1 -SourceDirectory <書き出し先> -OutputDirectory <新しいフォルダ>
#   3. アップロードの直前に、もう一度確かめる（中身が変わっていないか）:
#        powershell -NoProfile -File tools/prepare_steam_demo_upload.ps1 -OutputDirectory <2のフォルダ> -VerifyOnly
#   4. （人が実行する）steamcmd +login <アカウント> +run_app_build "<2のフォルダ>/app_build_5521380.vdf" +quit
#
# 確かめること: 書き出しの pck の確認（pack_check.json）が通っている・pck に体験版の機能タグ "demo" が入っている
# （製品版の pck を体験版として上げない）・上げるのは実行に要る4つのファイルだけ（開発用の設定・ログ・steam_appid.txt は入れない）。
[CmdletBinding()]
param(
    [string]$SourceDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    # Steamworks が体験版のアプリに作った既定のデポ（AppID + 1）。Steamworks の「デポ」画面の番号と同じか確かめる。
    [string]$DepotId = '5521381',
    [switch]$VerifyOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AppId = '5521380'
$FullAppId = '5482410'
$ExeName = 'MakersAndChallengers.exe'
$PackName = 'MakersAndChallengers.pck'
$Required = @($ExeName, $PackName, 'libgodotsteam.windows.template_release.x86_64.dll', 'steam_api64.dll')
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-Sha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

function Test-DemoFeature([string]$PackPath) {
    # 書き出しのプリセットの Custom Features は pck の project.binary に "_custom_features" として入る。
    $bytes = [IO.File]::ReadAllBytes($PackPath)
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $at = $text.IndexOf('_custom_features')
    while ($at -ge 0) {
        $window = $text.Substring($at, [Math]::Min(64, $text.Length - $at))
        if ($window -match 'demo') { return $true }
        $at = $text.IndexOf('_custom_features', $at + 1)
    }
    return $false
}

function Get-Vdfs([string]$Root) {
    $content = (Join-Path $Root 'content').Replace('\', '/')
    $mapping = ($Required | ForEach-Object { "    `"FileMapping`" { `"LocalPath`" `"$_`" `"DepotPath`" `"$_`" `"recursive`" `"0`" }" }) -join "`n"
    $depot = "`"DepotBuildConfig`"`n{`n    `"DepotID`" `"$DepotId`"`n    `"contentroot`" `"$content`"`n$mapping`n}`n"
    $app = "`"appbuild`"`n{`n    `"appid`" `"$AppId`"`n    `"desc`" `"Makers & Challengers Demo (Windows x64)`"`n    `"buildoutput`" `"$($Root.Replace('\', '/'))/steam_build_logs`"`n    `"setlive`" `"`"`n    `"preview`" `"0`"`n    `"depots`" { `"$DepotId`" `"$($Root.Replace('\', '/'))/depot_build_$DepotId.vdf`" }`n}`n"
    return @{ depot = $depot; app = $app }
}

if ($VerifyOnly) {
    $root = (Resolve-Path -LiteralPath $OutputDirectory).Path
    $manifest = Get-Content -LiteralPath (Join-Path $root 'demo_upload_manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.appid -ne $AppId -or $manifest.depot -ne $DepotId) { throw 'Manifest AppID/depot does not match the trial.' }
    $actual = @(Get-ChildItem -LiteralPath (Join-Path $root 'content') -Force)
    if ($actual.Count -ne $Required.Count -or @($actual | Where-Object PSIsContainer).Count) { throw 'Unexpected upload content.' }
    foreach ($entry in $manifest.files) {
        if ((Get-Sha256 (Join-Path $root "content/$($entry.file)")) -ne $entry.sha256) { throw "Content changed after preparation: $($entry.file)" }
    }
    $expected = Get-Vdfs $root
    if ([IO.File]::ReadAllText((Join-Path $root "depot_build_$DepotId.vdf")) -ne $expected.depot) { throw 'Depot config changed.' }
    if ([IO.File]::ReadAllText((Join-Path $root "app_build_$AppId.vdf")) -ne $expected.app) { throw 'App build config changed.' }
    if (-not (Test-DemoFeature (Join-Path $root "content/$PackName"))) { throw 'The pack is not a trial build.' }
    Write-Output "STEAM_DEMO_UPLOAD_CHECK_OK appid=$AppId depot=$DepotId files=$($actual.Count) uploads=0"
    exit 0
}

if (-not $SourceDirectory) { throw '-SourceDirectory is required.' }
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'OutputDirectory must be new; existing folders are never overwritten.' }
if ($output.StartsWith($source + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $output -eq $source) { throw 'Output must be outside the build folder.' }
foreach ($name in $Required) { if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) { throw "Missing runtime file: $name" } }
$check = Join-Path $source 'pack_check.json'
if (-not (Test-Path -LiteralPath $check)) { throw 'pack_check.json is missing; build with tools/build_release_windows.sh <out> demo.' }
$report = Get-Content -LiteralPath $check -Raw | ConvertFrom-Json
if (@($report.problems).Count -ne 0 -or -not $report.public_config_ok) { throw 'The pack check has not passed.' }
if (-not (Test-DemoFeature (Join-Path $source $PackName))) { throw 'The pack has no "demo" feature tag: this is not a trial build (never upload the full version to the trial app).' }

New-Item -ItemType Directory -Path $output | Out-Null
$content = Join-Path $output 'content'
New-Item -ItemType Directory -Path $content | Out-Null
$files = @()
foreach ($name in $Required) {
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $content $name)
    $hash = Get-Sha256 (Join-Path $content $name)
    if ($hash -ne (Get-Sha256 (Join-Path $source $name))) { throw "Copy changed: $name" }
    $files += [ordered]@{ file = $name; sha256 = $hash }
}
$vdfs = Get-Vdfs $output
[IO.File]::WriteAllText((Join-Path $output "depot_build_$DepotId.vdf"), $vdfs.depot, $Utf8)
[IO.File]::WriteAllText((Join-Path $output "app_build_$AppId.vdf"), $vdfs.app, $Utf8)
$manifest = [ordered]@{ appid = $AppId; depot = $DepotId; full_version_appid_untouched = $FullAppId; source = $source; files = $files; demo_feature = $true; steam_upload_performed = $false }
[IO.File]::WriteAllText((Join-Path $output 'demo_upload_manifest.json'), ($manifest | ConvertTo-Json -Depth 4), $Utf8)
Write-Output "STEAM_DEMO_PREPARED appid=$AppId depot=$DepotId files=$($files.Count) uploads=0 output=$output"
Write-Output "Next (run by a person, not by this script): steamcmd +login <account> +run_app_build `"$($output.Replace('\', '/'))/app_build_$AppId.vdf`" +quit"
