#requires -Version 5.1
Set-StrictMode -Version Latest
$script:PhotoUtf8 = [Text.UTF8Encoding]::new($false)

function Initialize-GamePhotoCapture {
    if ('PlayerBots.RouteRecorder.GameWindowCapture' -as [type]) { return }
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $refs = @([Drawing.Bitmap].Assembly.Location, [Windows.Forms.Screen].Assembly.Location, [ComponentModel.Win32Exception].Assembly.Location)
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $refs += @('Microsoft.Win32.Primitives', 'System.Drawing.Primitives', 'System.ComponentModel.Primitives', 'System.Diagnostics.Process', 'System.Collections', 'System.Runtime.InteropServices')
        $refs += @(Get-ChildItem -LiteralPath $PSHOME -Filter 'System.Private.Windows.*.dll' | ForEach-Object FullName)
    }
    Add-Type -Path (Join-Path $PSScriptRoot 'windows/GameWindowCapture.cs') -ReferencedAssemblies $refs
}

function New-StreetViewSession {
    param([string]$RawPath, [guid]$RecordingId, [int]$IntervalSeconds = 5, [long]$BudgetBytes = 536870912, [int]$MaximumWidth = 1600,
        [ValidateSet('foreground-game-client-rectangle','game-screenshot-key-and-folder')][string]$CaptureMethod='foreground-game-client-rectangle')
    if ($IntervalSeconds -lt 1 -or $IntervalSeconds -gt 60 -or $BudgetBytes -lt 1 -or $MaximumWidth -lt 640 -or $MaximumWidth -gt 2560) { throw 'Invalid photo settings.' }
    $directory = [IO.Path]::ChangeExtension([IO.Path]::GetFullPath($RawPath), 'photos')
    if (Test-Path -LiteralPath $directory) { throw 'This photo session already exists.' }
    [IO.Directory]::CreateDirectory((Join-Path $directory 'images')) | Out-Null
    $header = [ordered]@{ schema = 'archeage-street-view-session-v1'; recordingId = $RecordingId.ToString();
        intervalSeconds = $IntervalSeconds; maximumWidth = $MaximumWidth; budgetBytes = $BudgetBytes;
        projection = 'perspective'; cameraOrientation = 'unknown'; captureMethod = $CaptureMethod;
        createdUtc = [DateTimeOffset]::UtcNow.ToString('O') }
    [IO.File]::WriteAllText((Join-Path $directory 'session.json'), ($header | ConvertTo-Json), $script:PhotoUtf8)
    [IO.File]::WriteAllText((Join-Path $directory 'frames.jsonl'), '', $script:PhotoUtf8)
    return [pscustomobject]@{ Directory = $directory; Count = 0; Bytes = 0L; SourceBytes = 0L; CaptureMethod=$CaptureMethod; BudgetBytes = $BudgetBytes; MaximumWidth = $MaximumWidth; LimitReached = $false; Segment = 0 }
}

function Save-StreetViewPhoto {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)]$Position, [Parameter(Mandatory)]$Capture)
    if ($Session.LimitReached) { return $null }
    $stamp = [DateTimeOffset]::Parse([string]$Capture.CapturedUtc)
    $positionStamp = [DateTimeOffset]::Parse([string]$Position.capturedUtc)
    $offset = ($stamp - $positionStamp).TotalMilliseconds
    if ($offset -lt -250 -or $offset -gt 2000) { throw 'Photo skipped: position and image are more than two seconds apart.' }
    foreach ($name in @('x', 'y', 'z')) {
        $value = [double]$Position.$name
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or [Math]::Abs($value) -gt 10000000) { throw 'Invalid photo position.' }
    }
    $bytes = [byte[]]$Capture.Jpeg
    if ($bytes.Length -lt 4 -or $bytes[0] -ne 255 -or $bytes[1] -ne 216 -or $bytes[-2] -ne 255 -or $bytes[-1] -ne 217) { throw 'Capture did not return a complete JPEG.' }
    if ($Session.Bytes + $bytes.LongLength -gt $Session.BudgetBytes -or $Session.Count -ge 20000) {
        $Session.LimitReached = $true; return $null
    }
    $disk = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($Session.Directory))
    if ($disk.AvailableFreeSpace -lt ($bytes.LongLength + 100MB)) { throw 'Photo skipped: less than 100 MB of free disk space remains.' }
    $number = $Session.Count + 1
    $relative = 'images/{0:D6}.jpg' -f $number
    $path = Join-Path $Session.Directory $relative
    $stream = [IO.File]::Open($path, 'CreateNew', 'Write', 'None')
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    $frame = [ordered]@{ index = $number; path = $relative; capturedUtc = $stamp.ToString('O');
        positionCapturedUtc = $positionStamp.ToString('O'); positionOffsetMs = [Math]::Round($offset); segment = $Session.Segment;
        worldId = [uint32]$Position.worldId; instanceId = [uint32]$Position.instanceId; zoneId = [uint32]$Position.zoneId;
        x = [double]$Position.x; y = [double]$Position.y; z = [double]$Position.z;
        playerHeadingRadians = $Position.headingRadians; cameraHeadingRadians = $null; projection = 'perspective';
        width = [int]$Capture.Width; height = [int]$Capture.Height;
        sha256 = (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant(); bytes = $bytes.Length }
    $frame.captureTimestampBasis=if($Capture.PSObject.Properties['CaptureTimestampBasis']){$Capture.CaptureTimestampBasis}else{'visible-pixels-copied'}
    if($Capture.PSObject.Properties['SourceFileObservedUtc']) {
        $frame.sourceFileObservedUtc=$Capture.SourceFileObservedUtc
        $frame.sourceFileSha256=$Capture.SourceFileSha256
        $frame.sourceBytes=$Capture.SourceBytes
        $Session.SourceBytes += [long]$Capture.SourceBytes
    }
    [IO.File]::AppendAllText((Join-Path $Session.Directory 'frames.jsonl'), (($frame | ConvertTo-Json -Compress) + "`n"), $script:PhotoUtf8)
    $Session.Count = $number; $Session.Bytes += $bytes.LongLength
    if($Session.SourceBytes -ge $Session.BudgetBytes){$Session.LimitReached=$true}
    return [pscustomobject]$frame
}

function Export-StreetViewBundle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RecordingPath, [Parameter(Mandatory)][string]$PhotoDirectory,
        [Parameter(Mandatory)][string]$OutputDirectory)
    # Reuse the route validator, but retain observed points rather than interpolated geometry.
    $recording = Read-PlayerRouteRecording $RecordingPath
    $session = Get-Content -LiteralPath (Join-Path $PhotoDirectory 'session.json') -Raw | ConvertFrom-Json
    if ($session.schema -ne 'archeage-street-view-session-v1' -or $session.recordingId -ne $recording.Header.recordingId) { throw 'Photo session belongs to a different recording.' }
    $frames = @(Get-Content -LiteralPath (Join-Path $PhotoDirectory 'frames.jsonl') | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    if ($frames.Count -eq 0) { throw 'No photos were captured. Raw route and photo session are preserved.' }
    $expected = 1
    foreach ($frame in $frames) {
        if ($frame.index -ne $expected -or $frame.path -cne ('images/{0:D6}.jpg' -f $expected)) { throw 'Invalid photo path or sequence.' }
        $path = Join-Path $PhotoDirectory $frame.path
        if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Photo links are not supported.' }
        if ((Get-FileHash -LiteralPath $path).Hash -ne $frame.sha256 -or (Get-Item -LiteralPath $path).Length -ne $frame.bytes) { throw "Photo checksum mismatch: $($frame.path)" }
        if ([Math]::Abs(([DateTimeOffset]::Parse($frame.capturedUtc) - [DateTimeOffset]::Parse($frame.positionCapturedUtc)).TotalMilliseconds) -gt 2000) { throw 'Photo has a stale position.' }
        foreach ($name in @('x', 'y', 'z')) {
            $value = [double]$frame.$name
            if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or [Math]::Abs($value) -gt 10000000) { throw 'Invalid photo coordinates.' }
        }
        $expected++
    }
    $name = ([string]$recording.Header.metadata.pathName -replace '[^a-zA-Z0-9]+','-').Trim('-')
    if (!$name) { $name = 'walk' }; if ($name.Length -gt 40) { $name = $name.Substring(0,40) }
    $name += '-' + $session.recordingId.Substring(0,8) + '-street-view'
    $destination = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) $name
    $zipPath = $destination + '.zip'
    foreach ($path in @($destination, $zipPath, ($zipPath + '.sha256'))) { if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite existing Street View export: $path" } }
    [IO.Directory]::CreateDirectory((Join-Path $destination 'images')) | Out-Null
    foreach ($frame in $frames) { [IO.File]::Copy((Join-Path $PhotoDirectory $frame.path), (Join-Path $destination $frame.path), $false) }
    $trace = [Collections.Generic.List[object]]::new()
    $segment = 0; $previous = $null
    $events = @($recording.Events | Sort-Object capturedUtc); $eventIndex = 0
    foreach ($sample in $recording.Samples) {
        $time = [DateTimeOffset]::Parse($sample.capturedUtc)
        while ($eventIndex -lt $events.Count -and [DateTimeOffset]::Parse($events[$eventIndex].capturedUtc) -le $time) {
            if ($events[$eventIndex].eventType -in @('paused','resumed','disconnected','reconnected','teleport-observed','world-or-instance-change')) { $segment++ }
            $eventIndex++
        }
        if ($previous) {
            $distance = [Math]::Sqrt([Math]::Pow($sample.x-$previous.x,2)+[Math]::Pow($sample.y-$previous.y,2)+[Math]::Pow($sample.z-$previous.z,2))
            if ($sample.worldId -ne $previous.worldId -or $sample.instanceId -ne $previous.instanceId -or $distance -ge 150 -or ($time - [DateTimeOffset]::Parse($previous.capturedUtc)).TotalSeconds -gt 65) { $segment++ }
        }
        $trace.Add([ordered]@{ x = $sample.x; y = $sample.y; z = $sample.z; worldId = $sample.worldId; instanceId = $sample.instanceId; zoneId = $sample.zoneId; segment = $segment; capturedUtc = $sample.capturedUtc })
        $previous = $sample
    }
    $data = [ordered]@{ schema = 'archeage-street-view-v1'; schemaVersion = 1; recordingId = $session.recordingId;
        metadata = $recording.Header.metadata; capture = $session; frames = $frames; trace = $trace.ToArray();
        content = [ordered]@{ containsScreenshots = $true; mayContainNamesChatOrOverlays = $true; cameraOrientationKnown = $false; panorama = $false }; rawRecordingSha256 = $recording.RawSha256 }
    $json = $data | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText((Join-Path $destination 'street-view.json'), $json, $script:PhotoUtf8)
    # External JS assignment works from file:// without a local server. Escape script delimiters too.
    $safeJson = $json.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026').Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
    [IO.File]::WriteAllText((Join-Path $destination 'data.js'), ('window.STREET_VIEW = ' + $safeJson + ';'), $script:PhotoUtf8)
    foreach ($file in @('index.html','viewer.js','viewer.css')) { [IO.File]::Copy((Join-Path $PSScriptRoot ('street-view/' + $file)), (Join-Path $destination $file), $false) }
    $files = @(Get-ChildItem -LiteralPath $destination -Recurse -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{ path = $_.FullName.Substring($destination.Length+1).Replace('\','/'); sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant(); bytes = $_.Length }
    })
    $manifest = [ordered]@{ schema = 'archeage-street-view-bundle-v1'; recordingId = $session.recordingId; files = $files; containsScreenshots = $true; reviewBeforeSharing = $true }
    $manifestPath = Join-Path $destination 'manifest.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), $script:PhotoUtf8)
    $checksums = @($files | ForEach-Object { $_.sha256 + ' *' + $_.path }) + ((Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant() + ' *manifest.json')
    [IO.File]::WriteAllText((Join-Path $destination 'SHA256SUMS.txt'), (($checksums -join "`n") + "`n"), $script:PhotoUtf8)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($destination, $zipPath, [IO.Compression.CompressionLevel]::Fastest, $false)
    $hash = (Get-FileHash -LiteralPath $zipPath).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(($zipPath + '.sha256'), ($hash + ' *' + [IO.Path]::GetFileName($zipPath)), $script:PhotoUtf8)
    [pscustomobject]@{ BundleZip = $zipPath; Viewer = (Join-Path $destination 'index.html'); Frames = $frames.Count; Sha256 = $hash }
}
Export-ModuleMember -Function Initialize-GamePhotoCapture, New-StreetViewSession, Save-StreetViewPhoto, Export-StreetViewBundle
