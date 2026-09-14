#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-RecorderPackageRoot {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if ([IO.File]::Exists((Join-Path $root 'recorder.json'))) { return $root }
    return (Join-Path $root 'standalone/route-recorder')
}

function Assert-RecorderPathIsDirect([string]$Path) {
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Choose the actual Game folder, not a symbolic link or junction.'
        }
        $item = if ($item -is [IO.DirectoryInfo]) { $item.Parent } else { $item.Directory }
    }
}

function Get-RecorderBridgePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GameDirectory)
    $root = (Resolve-Path -LiteralPath $GameDirectory -ErrorAction Stop).Path
    if (-not [IO.Directory]::Exists($root)) { throw 'Choose the folder containing AAEmu.Game.exe.' }
    Assert-RecorderPathIsDirect $root
    foreach ($file in @('AAEmu.Game.exe', 'AAEmu.Game.dll', 'AAEmu.Game.deps.json',
        'AAEmu.Game.runtimeconfig.json', 'Scripts/Commands/GetPosition.cs')) {
        $path = Join-Path $root $file
        if (-not [IO.File]::Exists($path)) {
            throw "This is not a built Game server folder: missing $file. Select the AAEmu.Game.exe you normally run, not the source project folder."
        }
        Assert-RecorderPathIsDirect $path
    }
    $package = Get-RecorderPackageRoot
    $manifest = Get-Content -LiteralPath (Join-Path $package 'recorder.json') -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.requiresPlayerBots -ne $false -or
        $manifest.host.commit -ne '62e3eb1d87da01194802ac886cd500134facad28' -or
        $manifest.bridge.source -ne 'server/PlayerRoutePositionCommand.cs' -or
        $manifest.bridge.destination -ne 'Scripts/Commands/PlayerRoutePositionCommand.cs') {
        throw 'The standalone recorder manifest is invalid. Extract the complete ZIP again.'
    }
    $source = Join-Path $package 'server/PlayerRoutePositionCommand.cs'
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if ($hash -ne $manifest.bridge.sha256) { throw 'The recorder extension does not match its package checksum. Re-extract the ZIP.' }
    $scripts = Join-Path $root 'Scripts'
    # Do not follow redirected script folders while inspecting or installing.
    $folders = [Collections.Generic.Queue[string]]::new()
    $folders.Enqueue($scripts)
    $commandPaths = [Collections.Generic.List[string]]::new()
    while ($folders.Count -gt 0) {
        $folder = $folders.Dequeue()
        Assert-RecorderPathIsDirect $folder
        foreach ($item in Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'The server Scripts folder contains a link. Use an ordinary Game folder for this installer.'
            }
            if ($item.PSIsContainer) { $folders.Enqueue($item.FullName); continue }
            if ($item.Extension -ne '.cs') { continue }
            if ([IO.File]::ReadAllText($item.FullName) -match '(?i)\bplayerrouteposition\b|\bPlayerRoutePositionCommand\b') {
                $commandPaths.Add($item.FullName)
            }
        }
    }
    if ($commandPaths.Count -gt 1) { throw 'Multiple recorder commands already exist under Scripts. Keep the files intact and ask the server owner to resolve the duplicate.' }
    $destination = Join-Path $root 'Scripts/Commands/PlayerRoutePositionCommand.cs'
    $state = 'ready'
    if ($commandPaths.Count -eq 1) {
        if ((Get-FileHash -LiteralPath $commandPaths[0] -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) {
            throw 'A different recorder command is already installed. It was preserved. Ask the server owner to review the existing version before updating.'
        }
        $state = 'installed'
        $destination = $commandPaths[0]
    }
    elseif ([IO.File]::Exists($destination)) { throw 'The destination file already exists and is unrelated. It was preserved.' }
    return [pscustomobject]@{ State = $state; GameDirectory = $root; Source = $source
        Destination = $destination; Sha256 = $hash; Version = [string]$manifest.version
        Compatibility = 'Baseline: AAEmu 1.2 r208022. Other builds are experimental; Check connection verifies the position command. Folder layout does not identify the server or client revision.' }
}

function Assert-RecorderServerStopped([string]$GameDirectory) {
    $expected = Join-Path $GameDirectory 'AAEmu.Game.exe'
    foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name = 'AAEmu.Game.exe' OR Name = 'dotnet.exe'" -ErrorAction Stop)) {
        if ($process.Name -ieq 'AAEmu.Game.exe' -and
            ([string]::IsNullOrWhiteSpace($process.ExecutablePath) -or $process.ExecutablePath -ieq $expected)) {
            throw 'Close this Game server through its normal shutdown command, then install the extension. The recorder will not stop it for you.'
        }
        if ($process.Name -ieq 'dotnet.exe' -and [string]$process.CommandLine -match '(?i)AAEmu\.Game\.dll') {
            throw 'A Game server is running through dotnet. Close it normally before installing the extension.'
        }
    }
}

function Install-RecorderBridge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GameDirectory)
    $plan = Get-RecorderBridgePlan -GameDirectory $GameDirectory
    if ($plan.State -eq 'installed') { return $plan }
    Assert-RecorderServerStopped $plan.GameDirectory
    # Recheck after the process check, then use a no-overwrite copy.
    $plan = Get-RecorderBridgePlan -GameDirectory $GameDirectory
    if ($plan.State -eq 'installed') { return $plan }
    [IO.File]::Copy($plan.Source, $plan.Destination, $false)
    if ((Get-FileHash -LiteralPath $plan.Destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $plan.Sha256) {
        throw 'The installed copy did not verify. It was retained for inspection; do not start this Game server until it is reviewed.'
    }
    $plan.State = 'installed'
    return $plan
}

Export-ModuleMember -Function Get-RecorderPackageRoot, Get-RecorderBridgePlan, Install-RecorderBridge
