#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ApiBase = 'http://127.0.0.1:1280/api',
    [string]$OutputDirectory = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArcheAge Routes'),
    [string]$SettingsDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ArcheAge Route Recorder/quick-marks'),
    [switch]$ValidateOnly,
    [string]$ScreenshotPath,
    [string]$LauncherPath,
    [ValidateRange(1, 2)][double]$UiScale = 1,
    [scriptblock]$ValidationAction
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    throw 'The graphical route recorder requires Windows.'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
Import-Module (Join-Path $PSScriptRoot 'PlayerRouteTools.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'RecorderBridge.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'StreetView.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'NativeScreenshot.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'QuickMarks.psm1') -Force
$moduleRoot = Get-RecorderPackageRoot
$recorderManifest = Get-Content -LiteralPath (Join-Path $moduleRoot 'recorder.json') -Raw | ConvertFrom-Json
$moduleVersionDefault = 'recorder-only/' + [string]$recorderManifest.version
$humanGuidePath = Join-Path $moduleRoot 'START-HERE.html'
$identityPath = Join-Path $moduleRoot 'package-identity.json'
if ([IO.File]::Exists($identityPath)) {
    $identity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
    if ([string]$identity.commit -notmatch '^[0-9a-f]{40}$') { throw 'Package identity is invalid. Re-extract the complete ZIP.' }
    $moduleVersionDefault += '+' + $identity.commit.Substring(0, 12)
}

if (-not ('PlayerBots.RouteRecorder.HotKeyWindow' -as [type])) {
    $hotKeyReferences = @(
        [Windows.Forms.NativeWindow].Assembly.Location,
        [Windows.Forms.Message].Assembly.Location,
        [Windows.Forms.CreateParams].Assembly.Location
    ) | Sort-Object -Unique
    Add-Type -ReferencedAssemblies $hotKeyReferences -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace PlayerBots.RouteRecorder
{
    public sealed class HotKeyWindow : NativeWindow, IDisposable
    {
        private const int WmHotKey = 0x0312;
        private int id;
        public event EventHandler HotKeyPressed;

        public HotKeyWindow()
        {
            CreateHandle(new CreateParams());
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint virtualKey);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr window, int id);

        public bool Register(int hotKeyId, uint modifiers, uint virtualKey)
        {
            id = hotKeyId;
            return RegisterHotKey(Handle, id, modifiers, virtualKey);
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == WmHotKey && message.WParam.ToInt32() == id)
            {
                EventHandler handler = HotKeyPressed;
                if (handler != null)
                    handler(this, EventArgs.Empty);
            }
            base.WndProc(ref message);
        }

        public void Dispose()
        {
            if (Handle != IntPtr.Zero)
            {
                UnregisterHotKey(Handle, id);
                DestroyHandle();
            }
        }
    }
}
'@
}

$script:state = [pscustomobject]@{
    Mode = 'Idle'
    SurveyNodes = @()
    RawPath = $null
    RecordingId = $null
    StartedUtc = [DateTimeOffset]::MinValue
    Sequence = 0L
    SampleCount = 0
    LastSample = $null
    SourceOffline = $false
    InSample = $false
    OutputRoot = $null
    LastExport = $null
    Photos = $null
    PhotoTarget = $null
    InPhoto = $false
    PhotoStatus = ''
    LastPhotoPosition = $null
    LastStreetView = $null
    NativePending = $null
    ManualPhotoDue = $null
}
$script:utf8NoBom = [Text.UTF8Encoding]::new($false)
$script:httpHandler = [Net.Http.HttpClientHandler]::new()
$script:httpHandler.AllowAutoRedirect = $false
$script:http = [Net.Http.HttpClient]::new($script:httpHandler)
$script:http.Timeout = [TimeSpan]::FromMilliseconds(1500)

function Add-RecorderStatus {
    param([Parameter(Mandatory)][string]$Text)
    $timestamp = [DateTime]::Now.ToString('HH:mm:ss')
    $script:statusBox.AppendText("[$timestamp] $Text`r`n")
    $script:statusBox.SelectionStart = $script:statusBox.TextLength
    $script:statusBox.ScrollToCaret()
}

function Add-RawRecord {
    param([Parameter(Mandatory)]$Record)
    $line = ($Record | ConvertTo-Json -Depth 12 -Compress) + "`n"
    [IO.File]::AppendAllText($script:state.RawPath, $line, $script:utf8NoBom)
}

function Add-RouteEvent {
    param([Parameter(Mandatory)][string]$EventType, [AllowEmptyString()][string]$Detail = '', [DateTimeOffset]$CapturedUtc = [DateTimeOffset]::UtcNow)
    Add-RawRecord ([ordered]@{
        recordType = 'event'
        capturedUtc = $CapturedUtc.ToUniversalTime().ToString('O', [Globalization.CultureInfo]::InvariantCulture)
        eventType = $EventType
        detail = $Detail
    })
}

function Get-ThreeDimensionalDistance {
    param($Left, $Right)
    $dx = [double]$Right.x - [double]$Left.x
    $dy = [double]$Right.y - [double]$Left.y
    $dz = [double]$Right.z - [double]$Left.z
    return [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz)
}

function Get-ApiSample {
    $uri = [Uri]::new($script:apiText.Text.TrimEnd('/') + '/commands/playerrouteposition')
    if ($uri.Scheme -notin @('http', 'https') -or -not $uri.IsLoopback) {
        throw 'API base must be a loopback HTTP address.'
    }
    $body = [ordered]@{ character = $script:characterText.Text.Trim(); arguments = 'sample' } | ConvertTo-Json -Compress
    $requestContent = [Net.Http.StringContent]::new($body, [Text.Encoding]::UTF8, 'application/json')
    try {
        try { $response = $script:http.PostAsync($uri, $requestContent).GetAwaiter().GetResult() }
        catch { throw '[API_UNREACHABLE] Cannot reach the local AAEmu Game API. Start Game, check WebApiNetwork and the API address in Server setup, then retry.' }
        try {
            $httpStatus = [int]$response.StatusCode
            $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
        finally { $response.Dispose() }
    }
    finally { $requestContent.Dispose() }

    $sample = ConvertFrom-PlayerRouteApiResponse $responseText -HttpStatusCode $httpStatus
    $age = ([DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse($sample.capturedUtc)).TotalSeconds
    if ([Math]::Abs($age) -gt 30) { throw 'The server returned an old position. Check the PC clock and reconnect your character.' }
    return $sample
}

function Test-RecorderConnection {
    if ([string]::IsNullOrWhiteSpace($script:characterText.Text)) {
        $script:connectionLabel.Text = 'Enter your exact character name, then check connection.'
        $script:characterText.Focus() | Out-Null
        return $false
    }
    try {
        $sample = Get-ApiSample
        $script:connectionLabel.Text = "Connected to your character. Zone $($sample.zoneId). Ready to record."
        Add-RecorderStatus $script:connectionLabel.Text
        Update-RecorderCompatibility
        if ($script:gameVersionText.Text.Trim() -ne 'ArcheAge 1.2 r208022') {
            Add-RecorderStatus $script:compatibilityLabel.Text
        }
        return $true
    }
    catch {
        $script:connectionLabel.Text = $_.Exception.Message
        Add-RecorderStatus ("Connection check: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Set-RecorderMode {
    param([Parameter(Mandatory)][ValidateSet('Idle', 'Recording', 'Paused')][string]$Mode)
    $script:state.Mode = $Mode
    $script:modeLabel.Text = switch ($Mode) {
        'Recording' { 'RECORDING' }
        'Paused' { 'PAUSED' }
        default { 'READY' }
    }
    $script:modeLabel.BackColor = switch ($Mode) {
        'Recording' { $script:colors.Success }
        'Paused' { $script:colors.Warning }
        default { $script:colors.Slate }
    }
    $idle = $Mode -eq 'Idle'
    foreach ($control in $script:metadataControls) { $control.Enabled = $idle }
    $script:startButton.Enabled = $idle
    $script:pauseButton.Enabled = -not $idle
    $script:pauseButton.Text = if ($Mode -eq 'Paused') { 'Resume' } else { 'Pause' }
    $script:stopButton.Enabled = -not $idle
    $script:markerButton.Enabled = $Mode -eq 'Recording'
    foreach ($button in $script:quickMarkButtons) { $button.Enabled = $Mode -eq 'Recording' }
    $script:checkButton.Enabled = $idle
    Update-PhotoSourceControls
    Update-RecorderSurveyControls
}

function Invoke-RecorderSample {
    param([switch]$PassThru)
    if ($script:state.Mode -ne 'Recording' -or $script:state.InSample) { return }
    if (([DateTimeOffset]::UtcNow - $script:state.StartedUtc).TotalMinutes -ge [double]$script:maxDuration.Value) {
        Add-RecorderStatus 'Maximum duration reached; stopping safely.'
        Stop-RouteRecording 'maximum-duration'
        return
    }

    $script:state.InSample = $true
    try {
        $sample = Get-ApiSample
        $captured = [DateTimeOffset]::Parse([string]$sample.capturedUtc, [Globalization.CultureInfo]::InvariantCulture)
        if ($script:state.SourceOffline) {
            Add-RouteEvent 'reconnected' 'position-source-available' $captured
            Add-RecorderStatus 'Position source reconnected.'
            $script:state.SourceOffline = $false
        }

        $quality = [string]$sample.quality
        if ($null -ne $script:state.LastSample) {
            $distance = Get-ThreeDimensionalDistance $script:state.LastSample $sample
            $contextChanged = [uint32]$sample.worldId -ne [uint32]$script:state.LastSample.worldId -or
                              [uint32]$sample.instanceId -ne [uint32]$script:state.LastSample.instanceId
            if ($contextChanged) {
                Add-RouteEvent 'world-or-instance-change' "world=$($sample.worldId), instance=$($sample.instanceId)" $captured
                $quality = 'context-boundary'
            }
            elseif ($distance -ge 150.0) {
                Add-RouteEvent 'teleport-observed' "gapMeters=$([Math]::Round($distance, 3))" $captured
                $quality = 'teleport-boundary'
            }
            elseif ([uint32]$sample.zoneId -ne [uint32]$script:state.LastSample.zoneId) {
                Add-RouteEvent 'zone-change' "zone=$($sample.zoneId)" $captured
            }
            elseif ($distance -lt 0.05) {
                $quality = 'stationary-server-transform'
            }
        }

        $script:state.Sequence++
        Add-RawRecord ([ordered]@{
            recordType = 'sample'
            sequence = $script:state.Sequence
            capturedUtc = [string]$sample.capturedUtc
            worldId = [uint32]$sample.worldId
            instanceId = [uint32]$sample.instanceId
            zoneId = [uint32]$sample.zoneId
            x = [double]$sample.x
            y = [double]$sample.y
            z = [double]$sample.z
            headingRadians = if ($null -eq $sample.headingRadians) { $null } else { [double]$sample.headingRadians }
            quality = $quality
            source = [string]$sample.source
        })
        $sample | Add-Member -NotePropertyName sequence -NotePropertyValue $script:state.Sequence -Force
        $script:state.SampleCount++
        $script:state.LastSample = $sample
        $script:sampleLabel.Text = "Samples: $($script:state.SampleCount)    World: $($sample.worldId)    Instance: $($sample.instanceId)    Zone: $($sample.zoneId)"
        $script:positionLabel.Text = 'X {0:N2}    Y {1:N2}    Z {2:N2}' -f [double]$sample.x, [double]$sample.y, [double]$sample.z
        if ($PassThru) { return $sample }
    }
    catch {
        if (-not $script:state.SourceOffline) {
            Add-RouteEvent 'disconnected' 'position-source-unavailable'
            Add-RecorderStatus ("Position source unavailable; retrying: {0}" -f $_.Exception.Message)
            $script:state.SourceOffline = $true
        }
    }
    finally { $script:state.InSample = $false }
}

function Start-RouteRecording {
    if ($script:state.Mode -ne 'Idle') { return }
    $survey = $script:surveyModeCombo.SelectedIndex -eq 1
    $required = @(,@($script:pathNameText, 'Area or city name'))
    if (-not $survey) { $required = @(@($script:fromText, 'Starting landmark'), @($script:toText, 'Destination landmark')) }
    foreach ($pair in ($required + @(
        @($script:characterText, 'Character name'),
        @($script:gameVersionText, 'Game version'),
        @($script:moduleVersionText, 'Module version')
    ))) {
        if ([string]::IsNullOrWhiteSpace($pair[0].Text)) {
            $script:tabs.SelectedIndex=0
            $script:tabs.TabPages[0].ScrollControlIntoView($pair[0])
            $pair[0].Focus() | Out-Null
            Add-RecorderStatus ("Enter the {0} before recording." -f $pair[1].ToLowerInvariant())
            return
        }
    }
    try {
        if([string]::IsNullOrWhiteSpace($script:pathNameText.Text)){
            $walkName=$script:fromText.Text.Trim()+' to '+$script:toText.Text.Trim()
            $script:pathNameText.Text=$walkName.Substring(0,[Math]::Min(120,$walkName.Length))
        }
        if (-not (Test-RecorderConnection)) { return }
        if ($script:photosEnabled.Checked -and $null -eq $script:gameWindowCombo.SelectedItem) {
            Find-RecorderGameWindows
            if($null -eq $script:gameWindowCombo.SelectedItem){
                $script:tabs.SelectedIndex=3
                throw 'Enter the game, then select its window in Photo settings. Turn off Take game photos while recording to record a route without pictures.'
            }
        }
        if($script:photosEnabled.Checked -and $script:photoSourceCombo.SelectedIndex -eq 0) {
            try { $null=Get-NativeScreenshotFiles $script:screenshotFolderText.Text.Trim() }
            catch {
                $script:tabs.SelectedIndex=3
                $script:tabs.TabPages[3].ScrollControlIntoView($script:screenshotFolderText)
                $script:screenshotFolderText.Focus() | Out-Null
                throw
            }
        }
        $apiUri = [Uri]::new($script:apiText.Text.Trim())
        if ($apiUri.Scheme -notin @('http', 'https') -or -not $apiUri.IsLoopback) { throw 'API base must be a loopback HTTP address.' }
        $recordingId = [guid]::NewGuid()
        $started = [DateTimeOffset]::UtcNow
        $outputRoot = [IO.Path]::GetFullPath($script:outputText.Text.Trim())
        [IO.Directory]::CreateDirectory($outputRoot) | Out-Null
        $rawDirectory = Join-Path $outputRoot 'working-recordings'
        [IO.Directory]::CreateDirectory($rawDirectory) | Out-Null
        $safeName = ($script:pathNameText.Text.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
        if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'route' }
        if ($safeName.Length -gt 40) { $safeName = $safeName.Substring(0, 40).TrimEnd('-') }
        $rawPath = Join-Path $rawDirectory ('{0}-{1}-{2}.jsonl' -f $started.ToString('yyyyMMdd-HHmmss'), $safeName, $recordingId.ToString('N').Substring(0, 8))
        if ([IO.File]::Exists($rawPath)) { throw "Recording path already exists: $rawPath" }
        $header = New-PlayerRouteRecordingHeader `
            -RecordingId $recordingId `
            -CreatedUtc $started `
            -PathName $script:pathNameText.Text `
            -FromLabel $(if ($survey) { 'Survey start' } else { $script:fromText.Text }) `
            -ToLabel $(if ($survey) { 'Survey end' } else { $script:toText.Text }) `
            -PathType ([string]$script:pathTypeCombo.SelectedItem) `
            -Directionality ([string]$script:directionCombo.SelectedItem) `
            -Notes $script:notesText.Text `
            -GameVersion $script:gameVersionText.Text `
            -ModuleVersion $script:moduleVersionText.Text `
            -SampleIntervalMs ([int]$script:interval.Value * 1000) `
            -MaximumDurationMinutes ([int]$script:maxDuration.Value)
        [IO.File]::WriteAllText($rawPath, (($header | ConvertTo-Json -Depth 12 -Compress) + "`n"), $script:utf8NoBom)

        $script:state.RawPath = $rawPath
        $script:state.RecordingId = $recordingId
        $script:state.StartedUtc = $started
        $script:state.Sequence = 0L
        $script:state.SurveyNodes = @()
        $script:nodeNameText.Items.Clear()
        $script:nodeStatusLabel.Text = 'Mark junctions while recording. Reuse the name only at the same spot.'
        $script:state.SampleCount = 0
        $script:state.LastSample = $null
        $script:state.SourceOffline = $false
        $script:state.OutputRoot = $outputRoot
        $script:state.LastExport = $null
        $script:state.Photos = $null
        $script:state.PhotoTarget = $null
        $script:state.LastPhotoPosition = $null
        $script:state.PhotoStatus = ''
        $script:state.LastStreetView = $null
        $script:state.NativePending=$null;$script:state.ManualPhotoDue=$null
        $script:viewPhotosButton.Enabled = $false
        if ($script:photosEnabled.Checked) {
            $script:state.Photos = New-StreetViewSession -RawPath $rawPath -RecordingId $recordingId `
                -IntervalSeconds ([int]$script:photoInterval.Value) -BudgetBytes ([long]$script:photoBudget.Value * 1MB) `
                -MaximumWidth ([int]$script:photoWidth.Value) `
                -CaptureMethod $(if($script:photoSourceCombo.SelectedIndex -eq 0){'game-screenshot-key-and-folder'}else{'foreground-game-client-rectangle'})
            $script:state.PhotoTarget = $script:gameWindowCombo.SelectedItem
            $script:photoTimer.Interval = [int]$script:photoInterval.Value * 1000
        }
        $script:exportButton.Enabled = $false
        $script:exportLabel.Text = 'Recording in progress. Stop & export creates the shareable ZIP.'
        $script:timer.Interval = [int]$script:interval.Value * 1000
        Set-RecorderMode 'Recording'
        Add-RouteEvent 'started' 'recorder-started' $started
        if ($survey) { Add-RouteEvent 'survey-started' 'explicit-directed-network' $started }
        Add-RecorderStatus "Recording started. Raw session: $rawPath"
        Invoke-RecorderSample
        $script:timer.Start()
        if ($script:state.Photos) {
            $script:photoTimer.Start()
            $script:nativePollTimer.Start()
            Set-PhotoStatus 'Photos armed. Switch to the selected game window; Ctrl+Alt+P takes an extra view.'
        }
    }
    catch {
        if ($ValidateOnly) { throw }
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Could not start recording') | Out-Null
        Add-RecorderStatus ("Start failed: {0}" -f $_.Exception.Message)
    }
}

function Pause-RouteRecording {
    if ($script:state.Mode -eq 'Recording') {
        $script:timer.Stop()
        $script:photoTimer.Stop()
        Clear-NativePhotoRequest
        $script:nativePollTimer.Stop()
        if ($script:state.Photos) { $script:state.Photos.Segment++ }
        Add-RouteEvent 'paused' 'contributor-paused'
        Set-RecorderMode 'Paused'
        Add-RecorderStatus 'Recording paused. Ctrl+Alt+R resumes.'
    }
    elseif ($script:state.Mode -eq 'Paused') {
        Add-RouteEvent 'resumed' 'contributor-resumed'
        Set-RecorderMode 'Recording'
        $script:timer.Start()
        if ($script:state.Photos -and -not $script:state.Photos.LimitReached) { $script:photoTimer.Start();$script:nativePollTimer.Start() }
        Add-RecorderStatus 'Recording resumed.'
        Invoke-RecorderSample
    }
}

function Stop-RouteRecording {
    param([string]$Reason = 'contributor-stopped')
    if ($script:state.Mode -eq 'Idle') { return }
    $script:timer.Stop()
    $script:photoTimer.Stop()
    Clear-NativePhotoRequest
    $script:nativePollTimer.Stop()
    Add-RouteEvent 'stopped' $Reason
    Set-RecorderMode 'Idle'
    Add-RecorderStatus "Recording stopped with $($script:state.SampleCount) samples."
    if ($script:state.SampleCount -lt 2) {
        Add-RecorderStatus 'Raw session preserved; at least two traversable samples are required to export.'
    }
    if ($script:state.SampleCount -ge 2) { try {
        $exportDirectory = Join-Path $script:state.OutputRoot 'exports'
        $result = Export-PlayerRouteBundle -RecordingPath $script:state.RawPath -OutputDirectory $exportDirectory
        $script:state.LastExport = $result.BundleZip
        $script:exportButton.Enabled = $true
        $script:exportLabel.Text = 'Ready to share: ' + [IO.Path]::GetFileName($result.BundleZip)
        Add-RecorderStatus "Export ready: $($result.BundleZip)"
        Add-RecorderStatus "SHA-256: $($result.Sha256)"
        Add-RecorderStatus 'ZIP includes route.json and navigation-prior files; city surveys also include network.json.'
        $script:sampleLabel.Text = "Exported $($result.Statistics.normalizedPoints) normalized points in $($result.Statistics.segments) segment(s)."
    }
    catch {
        Add-RecorderStatus ("Raw session preserved, but export needs attention: {0}" -f $_.Exception.Message)
        if (-not $ValidateOnly) { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Route export needs attention') | Out-Null }
    }
    }
    if ($script:state.Photos -and $script:state.Photos.Count -gt 0) {
        try {
            $photos = Export-StreetViewBundle -RecordingPath $script:state.RawPath -PhotoDirectory $script:state.Photos.Directory `
                -OutputDirectory (Join-Path $script:state.OutputRoot 'exports')
            $script:state.LastStreetView = $photos
            $script:viewPhotosButton.Enabled = $true
            if (!$script:state.LastExport) { $script:exportLabel.Text = 'Street View ready: ' + [IO.Path]::GetFileName($photos.BundleZip) }
            Add-RecorderStatus ("Street View ready: {0} photos. {1}" -f $photos.Frames, $photos.BundleZip)
            Set-PhotoStatus ('Ready: ' + $photos.Frames + ' photos. View photos opens your walk; its separate Street View ZIP is beside the route ZIP.')
        } catch {
            Add-RecorderStatus ('Photo originals preserved; export needs attention: ' + $_.Exception.Message)
            if ($ValidateOnly) { throw }
        }
    } elseif ($script:state.Photos) { Set-PhotoStatus 'No photos captured. Keep the selected game in the foreground, windowed or borderless, and try a short walk.' }
}

function Set-PhotoStatus([string]$Message) {
    $script:photoStatusLabel.Text = $Message
    if ($script:state.PhotoStatus -ne $Message) {
        Add-RecorderStatus $Message
        $script:state.PhotoStatus = $Message
    }
}

function Test-SelectedGameForeground { return [PlayerBots.RouteRecorder.GameWindowCapture]::IsForeground($script:state.PhotoTarget) }
function Get-GamePhoto { return [PlayerBots.RouteRecorder.GameWindowCapture]::Capture($script:state.PhotoTarget, $script:state.Photos.MaximumWidth) }

function Complete-RecorderPhoto($position,$capture) {
    if ($script:state.LastPhotoPosition) {
        $last = $script:state.LastPhotoPosition
        if ($last.worldId -ne $position.worldId -or $last.instanceId -ne $position.instanceId -or (Get-ThreeDimensionalDistance $last $position) -ge 150) { $script:state.Photos.Segment++ }
    }
    $photo = Save-StreetViewPhoto -Session $script:state.Photos -Position $position -Capture $capture
    if ($script:state.Photos.LimitReached) {
        $script:photoTimer.Stop();$script:nativePollTimer.Stop()
        Set-PhotoStatus 'Photo storage/count limit reached. Route recording continues; game originals and collected photos are preserved.'
    } elseif ($photo) {
        $script:state.LastPhotoPosition = $position
        if ($script:state.PhotoStatus -ne 'Photos recording.') { Set-PhotoStatus 'Photos recording.' }
        $script:photoStatusLabel.Text = '{0} photos / {1:N1} MB. Ctrl+Alt+P adds a view; turn the camera manually at a stop.' -f $script:state.Photos.Count, ($script:state.Photos.Bytes / 1MB)
    }
}

function Clear-NativePhotoRequest {
    if($script:state.NativePending){Add-RecorderStatus 'Pending screenshot left unlinked in the game folder; completed photos are preserved.'}
    $script:state.NativePending=$null;$script:state.ManualPhotoDue=$null
}

function Send-GameScreenshotKey([int]$Key) { return [PlayerBots.RouteRecorder.GameWindowCapture]::RequestScreenshot($script:state.PhotoTarget,$Key) }

function Invoke-NativePhotoPoll {
    if($script:state.Mode -ne 'Recording' -or $script:state.InPhoto){return}
    if($script:state.ManualPhotoDue -and [DateTimeOffset]::UtcNow -ge $script:state.ManualPhotoDue){
        $script:state.ManualPhotoDue=$null
        Invoke-RecorderPhoto
    }
    if(!$script:state.NativePending){return}
    $script:state.InPhoto=$true
    try {
        $request=$script:state.NativePending
        if(-not(Test-SelectedGameForeground)){throw 'Game lost focus while waiting for its screenshot; original left unlinked.'}
        $capture=Receive-NativeScreenshot $request
        if($capture){$script:state.NativePending=$null;Complete-RecorderPhoto $request.Position $capture}
    } catch {
        $script:state.NativePending=$null;$script:state.Photos.Segment++
        Set-PhotoStatus $_.Exception.Message
    } finally {$script:state.InPhoto=$false}
}

function Invoke-RecorderPhoto {
    if ($script:state.Mode -ne 'Recording' -or $null -eq $script:state.Photos -or $script:state.InPhoto -or $script:state.InSample -or $script:state.Photos.LimitReached -or $script:state.NativePending) { return }
    if (([DateTimeOffset]::UtcNow - $script:state.StartedUtc).TotalMinutes -ge [double]$script:maxDuration.Value) { Stop-RouteRecording 'maximum-duration'; return }
    $script:state.InPhoto = $true
    try {
        if (-not (Test-SelectedGameForeground)) { throw 'Photos waiting: bring the selected ArcheAge window to the foreground.' }
        if($script:photoSourceCombo.SelectedIndex -eq 0){
            $request=New-NativeScreenshotRequest -Directory $script:screenshotFolderText.Text.Trim() -Position ([pscustomobject]@{}) -MaximumWidth $script:state.Photos.MaximumWidth
            $request.Position=Get-ApiSample
            $key=[int][Enum]::Parse([Windows.Forms.Keys],[string]$script:screenshotKeyCombo.SelectedItem)
            $request.RequestedUtc=Send-GameScreenshotKey $key
            $request.DeadlineUtc=[DateTimeOffset]::Parse($request.RequestedUtc).AddSeconds(5)
            $script:state.NativePending=$request
            Set-PhotoStatus 'Screenshot requested; waiting for one completed image from the game.'
        }else{
            $position=Get-ApiSample
            Complete-RecorderPhoto $position (Get-GamePhoto)
        }
    } catch {
        if ($script:state.PhotoStatus -ne $_.Exception.Message) { $script:state.Photos.Segment++ }
        Set-PhotoStatus $_.Exception.Message
    } finally { $script:state.InPhoto = $false }
}

function Toggle-RouteRecording {
    switch ($script:state.Mode) {
        'Idle' { Start-RouteRecording }
        default { Pause-RouteRecording }
    }
}

. (Join-Path $PSScriptRoot 'RecorderWindow.ps1')
