[CmdletBinding()]
param([Parameter(Mandatory)][string]$ArchivePath, [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [Parameter(Mandatory)][string]$BuildRoot)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$staging = Join-Path $BuildRoot ('launcher-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($staging) | Out-Null
$zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
try {
    # Compile both source and build recipe from the requested archive, never HEAD.
    foreach ($path in @('scripts/route-recorder/Build-PlayerRouteRecorder.ps1',
        'scripts/route-recorder/windows/PlayerRouteRecorderLauncher.cs')) {
        $entry = $zip.GetEntry("$Prefix/$path")
        if ($null -eq $entry) { throw "Missing archived launcher input: $path" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $staging ([IO.Path]::GetFileName($path))))
    }
} finally { $zip.Dispose() }
$executable = Join-Path $staging 'PlayerRouteRecorder.exe'
$result = & (Join-Path $staging 'Build-PlayerRouteRecorder.ps1') `
    -SourcePath (Join-Path $staging 'PlayerRouteRecorderLauncher.cs') -OutputPath $executable
$zip = [IO.Compression.ZipFile]::Open($ArchivePath, [IO.Compression.ZipArchiveMode]::Update)
try {
    $identity = $zip.CreateEntry("$Prefix/package-identity.json")
    $writer = [IO.StreamWriter]::new($identity.Open(), [Text.UTF8Encoding]::new($false))
    try { $writer.Write((@{ schemaVersion = 1; commit = $Commit } | ConvertTo-Json -Compress)) }
    finally { $writer.Dispose() }
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $executable,
        "$Prefix/PlayerRouteRecorder.exe", [IO.Compression.CompressionLevel]::Optimal) | Out-Null
} finally { $zip.Dispose() }
$result
