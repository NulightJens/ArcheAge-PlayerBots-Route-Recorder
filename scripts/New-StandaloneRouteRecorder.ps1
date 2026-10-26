#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory, [string]$Ref = 'HEAD')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Split-Path -Parent $PSScriptRoot
$status = @(& git -C $root status --porcelain=v1)
if ($LASTEXITCODE -ne 0 -or $status.Count -gt 0) { throw 'Commit the intended source before packaging.' }
$commit = (& git -C $root rev-parse "$Ref^{commit}").Trim()
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') { throw 'The requested ref is not a commit.' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($output) | Out-Null
$staging = Join-Path $output ('build-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($staging) | Out-Null
$sourceZip = Join-Path $staging 'source.zip'
& git -C $root archive --format=zip "--output=$sourceZip" $commit -- README.md FAMILY.md CHANGELOG.md LICENSE.md START-HERE.html FIELD-NOTES.txt recorder.json docs server scripts/route-recorder LICENSE.GPL LICENSE.MIT
if ($LASTEXITCODE -ne 0) { throw 'Could not archive the requested standalone source.' }
$sourceRoot = Join-Path $staging 'source'
[IO.Compression.ZipFile]::ExtractToDirectory($sourceZip, $sourceRoot)
$standalone = $sourceRoot
$metadata = Get-Content -LiteralPath (Join-Path $standalone 'recorder.json') -Raw | ConvertFrom-Json
if ($metadata.version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$' -or $metadata.requiresPlayerBots -ne $false) {
    throw 'Invalid standalone package metadata in the requested ref.'
}
$baseName = 'archeage-route-recorder-standalone-' + $metadata.version + '-' + $commit.Substring(0, 7)
$archive = Join-Path $output ($baseName + '.zip')
$manifestPath = Join-Path $output ($baseName + '.manifest.json')
$checksumPath = Join-Path $output ($baseName + '.sha256')
foreach ($path in @($archive, $manifestPath, $checksumPath)) {
    if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite existing artifact: $path" }
}
$package = Join-Path $staging 'package/archeage-route-recorder'
[IO.Directory]::CreateDirectory($package) | Out-Null
foreach ($entry in @('START-HERE.html', 'README.md', 'FAMILY.md', 'CHANGELOG.md', 'LICENSE.md', 'recorder.json', 'FIELD-NOTES.txt', 'docs', 'server')) {
    Copy-Item -LiteralPath (Join-Path $standalone $entry) -Destination $package -Recurse
}
foreach ($license in @('LICENSE.GPL', 'LICENSE.MIT')) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot $license) -Destination $package
}
$scripts = Join-Path $package 'scripts/route-recorder'
[IO.Directory]::CreateDirectory($scripts) | Out-Null
foreach ($entry in @('Start-PlayerRouteRecorder.ps1', 'RecorderWindow.ps1', 'PlayerRouteTools.psm1',
    'PlayerRouteNetwork.ps1', 'RecorderBridge.psm1', 'Install-RecorderBridge.ps1', 'Export-PlayerRoute.ps1', 'Merge-PlayerRoutes.ps1', 'schemas',
    'StreetView.psm1', 'NativeScreenshot.psm1', 'QuickMarks.psm1', 'Export-StreetView.ps1', 'street-view')) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot ('scripts/route-recorder/' + $entry)) -Destination $scripts -Recurse
}
[IO.Directory]::CreateDirectory((Join-Path $scripts 'windows')) | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceRoot 'scripts/route-recorder/windows/GameWindowCapture.cs') -Destination (Join-Path $scripts 'windows')
$bridgeHash = (Get-FileHash -LiteralPath (Join-Path $package 'server/PlayerRoutePositionCommand.cs')).Hash.ToLowerInvariant()
if ($bridgeHash -ne $metadata.bridge.sha256) { throw 'The archived recorder extension does not match recorder.json.' }
$launcherSource = Join-Path $sourceRoot 'scripts/route-recorder/windows/PlayerRouteRecorderLauncher.cs'
$buildRecipe = Join-Path $sourceRoot 'scripts/route-recorder/Build-PlayerRouteRecorder.ps1'
$built = & $buildRecipe -SourcePath $launcherSource -OutputPath (Join-Path $package 'PlayerRouteRecorder.exe')
$files = @(Get-ChildItem -LiteralPath $package -Recurse -File | Sort-Object FullName | ForEach-Object {
    [ordered]@{ path = $_.FullName.Substring($package.Length + 1).Replace('\', '/')
        sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant(); bytes = $_.Length }
})
$identity = [ordered]@{ schemaVersion = 1; name = $metadata.name; version = $metadata.version
    commit = $commit; requiresPlayerBots = $false; host = $metadata.host; files = $files
    launcherInputs = @($launcherSource, $buildRecipe | ForEach-Object {
        [ordered]@{ path = $_.Substring($sourceRoot.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant() }
    }) }
[IO.File]::WriteAllText((Join-Path $package 'package-identity.json'),
    ($identity | ConvertTo-Json -Depth 8) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
# .NET Framework's directory helper uses backslashes in ZIP entries. Write the
# portable names explicitly so Windows PowerShell and newer PowerShell agree.
$packageParent = Join-Path $staging 'package'
$archiveStream = [IO.File]::Open($archive, [IO.FileMode]::CreateNew)
try {
    $archiveWriter = [IO.Compression.ZipArchive]::new($archiveStream, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($file in @(Get-ChildItem -LiteralPath $packageParent -Recurse -File | Sort-Object FullName)) {
            $entryName = $file.FullName.Substring($packageParent.Length + 1).Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archiveWriter, $file.FullName, $entryName, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $archiveWriter.Dispose() }
} finally { $archiveStream.Dispose() }
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    $entries = @($zip.Entries | ForEach-Object FullName)
    foreach ($required in @('PlayerRouteRecorder.exe', 'START-HERE.html', 'server/PlayerRoutePositionCommand.cs',
        'scripts/route-recorder/PlayerRouteNetwork.ps1', 'scripts/route-recorder/RecorderBridge.psm1', 'scripts/route-recorder/NativeScreenshot.psm1', 'scripts/route-recorder/QuickMarks.psm1', 'scripts/route-recorder/windows/GameWindowCapture.cs',
        'scripts/route-recorder/street-view/index.html', 'scripts/route-recorder/street-view/viewer.js', 'package-identity.json')) {
        if ('archeage-route-recorder/' + $required -notin $entries) { throw "Missing packaged file: $required" }
    }
    if ($entries | Where-Object { $_ -match '(^|/)(src|sql|tests|modules|compatibility|ops|working-recordings|exports)/|playerbots\.module\.json$' }) {
        throw 'The standalone ZIP contains an unexpected module or private file.'
    }
    $entryCount = $entries.Count
} finally { $zip.Dispose() }
$hash = (Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant()
$manifest = [ordered]@{ schemaVersion = 1; name = $metadata.name; version = $metadata.version; commit = $commit
    requiresPlayerBots = $false; host = $metadata.host; bridge = $metadata.bridge
    archive = [ordered]@{ file = [IO.Path]::GetFileName($archive); sha256 = $hash; bytes = (Get-Item -LiteralPath $archive).Length; entries = $entryCount }
    executable = [ordered]@{ path = 'PlayerRouteRecorder.exe'; sha256 = $built.Sha256; bytes = $built.Bytes } }
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($checksumPath, "$hash *$([IO.Path]::GetFileName($archive))" + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Archive = $archive; Manifest = $manifestPath; Checksum = $checksumPath
    Commit = $commit; Sha256 = $hash; ExtractedPackage = $package; Bytes = $manifest.archive.bytes; Entries = $entryCount }
