#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-NativeScreenshotFiles([string]$Directory) {
    if (![IO.Directory]::Exists($Directory)) { throw 'Take one F9 screenshot in game, then choose the folder where it appeared.' }
    return @(Get-ChildItem -LiteralPath $Directory -File | Where-Object { $_.Extension.ToLowerInvariant() -in @('.jpg','.jpeg','.png','.bmp','.tga') })
}

function New-NativeScreenshotRequest {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)]$Position, [int]$MaximumWidth=1600)
    $folder=[IO.Path]::GetFullPath($Directory)
    $baseline=@{}
    foreach($file in (Get-NativeScreenshotFiles $folder)) { $baseline[$file.Name]=('{0}:{1}' -f $file.Length,$file.LastWriteTimeUtc.Ticks) }
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($folder))
    if($drive.AvailableFreeSpace -lt 200MB) { throw 'Screenshot key skipped: less than 200 MB remains on the game screenshot drive.' }
    [pscustomobject]@{ Directory=$folder; Baseline=$baseline; Position=$Position; MaximumWidth=$MaximumWidth;
        RequestedUtc=$null; DeadlineUtc=[DateTimeOffset]::UtcNow.AddSeconds(5); Candidate=$null; Fingerprint=$null; StableSince=[DateTimeOffset]::MinValue; Finished=$false }
}

function Receive-NativeScreenshot {
    param([Parameter(Mandatory)]$Request)
    if($Request.Finished) { return $null }
    if(!$Request.RequestedUtc) { throw 'Screenshot key has not been requested.' }
    $now=[DateTimeOffset]::UtcNow
    if($now -gt $Request.DeadlineUtc) { $Request.Finished=$true;throw 'No completed screenshot within 5 seconds. Check the selected key/folder with one manual screenshot.' }
    $candidates=@(Get-NativeScreenshotFiles $Request.Directory | Where-Object {
        !$Request.Baseline.ContainsKey($_.Name) -or $Request.Baseline[$_.Name] -ne ('{0}:{1}' -f $_.Length,$_.LastWriteTimeUtc.Ticks)
    })
    if($candidates.Count -gt 1) { $Request.Finished=$true;throw 'Multiple screenshots appeared for one request; none were linked. Originals were preserved.' }
    if($candidates.Count -eq 0) { return $null }
    $file=$candidates[0]
    if($file.Extension -ieq '.tga') { $Request.Finished=$true;throw 'The game saved TGA. Use JPG/PNG/BMP if your client offers it, or select Visible window capture. Original preserved.' }
    if($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { $Request.Finished=$true;throw 'A screenshot file is a link; it was not imported.' }
    $fingerprint='{0}:{1}' -f $file.Length,$file.LastWriteTimeUtc.Ticks
    if($Request.Candidate -ne $file.Name -or $Request.Fingerprint -ne $fingerprint) {
        $Request.Candidate=$file.Name;$Request.Fingerprint=$fingerprint;$Request.StableSince=$now;return $null
    }
    if(($now-$Request.StableSince).TotalMilliseconds -lt 200 -or $file.Length -eq 0) { return $null }
    if($file.Length -gt 128MB) { $Request.Finished=$true;throw 'Screenshot exceeds the 128 MB import limit; original preserved.' }
    $source=$null;$memory=[IO.MemoryStream]::new()
    try {
        # FileShare.Read refuses an existing writer and keeps the image stable during decode.
        try { $source=[IO.File]::Open($file.FullName,'Open','Read','Read') } catch [IO.IOException] { return $null }
        $source.CopyTo($memory);$bytes=$memory.ToArray()
        try { $decoded=[PlayerBots.RouteRecorder.GameWindowCapture]::DecodeScreenshot($bytes,$Request.MaximumWidth,$Request.RequestedUtc) }
        catch { return $null } # A partly written image may decode on a later poll; deadline remains bounded.
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$sha=([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
        $Request.Finished=$true
        [pscustomobject]@{Jpeg=$decoded.Jpeg;Width=$decoded.Width;Height=$decoded.Height;CapturedUtc=$Request.RequestedUtc;
            CaptureTimestampBasis='screenshot-key-request';SourceFileObservedUtc=$now.ToString('O');SourceFileSha256=$sha;SourceBytes=$bytes.LongLength}
    } finally { if($source){$source.Dispose()};$memory.Dispose() }
}
Export-ModuleMember -Function Get-NativeScreenshotFiles, New-NativeScreenshotRequest, Receive-NativeScreenshot
