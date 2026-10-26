#requires -Version 5.1

Set-StrictMode -Version Latest

$script:RouteToolVersion = '1.6.0'
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:PathTypes = @('main-road', 'side-path', 'shortcut', 'cave', 'dungeon', 'water', 'other')
$script:Directions = @('bidirectional', 'from-to', 'to-from')
. (Join-Path $PSScriptRoot 'PlayerRouteNetwork.ps1')

function Get-RequiredProperty {
    param([Parameter(Mandatory)]$InputObject, [Parameter(Mandatory)][string]$Name)

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Missing required property '$Name'."
    }
    return $property.Value
}

function Assert-TextLength {
    param([AllowEmptyString()][string]$Value, [string]$Name, [int]$Maximum, [switch]$Required)

    if ($Required -and [string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name is required."
    }
    if ($null -ne $Value -and $Value.Length -gt $Maximum) {
        throw "$Name exceeds $Maximum characters."
    }
}

function ConvertTo-RouteTimestamp {
    param([Parameter(Mandatory)][string]$Value, [string]$Name = 'timestamp')

    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
        $Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed)) {
        throw "Invalid $Name '$Value'."
    }
    return $parsed.ToUniversalTime()
}

function Assert-FiniteNumber {
    param($Value, [string]$Name, [double]$Minimum = -10000000, [double]$Maximum = 10000000)

    try { $number = [double]$Value } catch { throw "$Name is not numeric." }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or
        $number -lt $Minimum -or $number -gt $Maximum) {
        throw "$Name is outside the supported finite range."
    }
    return $number
}

function Write-Utf8File {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)

    if ([IO.File]::Exists($Path)) {
        throw "Refusing to overwrite '$Path'."
    }
    [IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

function ConvertTo-StableJson {
    param([Parameter(Mandatory)]$InputObject, [switch]$Compress)

    $json = ConvertTo-CanonicalJsonValue $InputObject
    if ($Compress) { return $json }
    return ($json + "`n")
}

function ConvertTo-JsonStringLiteral {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value) { return 'null' }
    $builder = [Text.StringBuilder]::new($Value.Length + 2)
    $null = $builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        switch ([int]$character) {
            8 { $null = $builder.Append('\b') }
            9 { $null = $builder.Append('\t') }
            10 { $null = $builder.Append('\n') }
            12 { $null = $builder.Append('\f') }
            13 { $null = $builder.Append('\r') }
            34 { $null = $builder.Append('\"') }
            92 { $null = $builder.Append('\\') }
            default {
                if ([int]$character -lt 32) {
                    $null = $builder.Append(('\u{0:x4}' -f [int]$character))
                }
                else { $null = $builder.Append($character) }
            }
        }
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-CanonicalJsonValue {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string] -or $Value -is [char]) { return ConvertTo-JsonStringLiteral ([string]$Value) }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]) {
        return ([IFormattable]$Value).ToString($null, [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        $number = [double]$Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { throw 'Canonical JSON cannot contain a non-finite number.' }
        return $number.ToString('0.#################', [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [Collections.IDictionary]) {
        $members = [Collections.Generic.List[string]]::new()
        foreach ($key in $Value.Keys) {
            $members.Add((ConvertTo-JsonStringLiteral ([string]$key)) + ':' + (ConvertTo-CanonicalJsonValue $Value[$key]))
        }
        return '{' + ($members -join ',') + '}'
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = [Collections.Generic.List[string]]::new()
        foreach ($item in $Value) { $items.Add((ConvertTo-CanonicalJsonValue $item)) }
        return '[' + ($items -join ',') + ']'
    }

    $properties = @($Value.PSObject.Properties | Where-Object MemberType -in @('NoteProperty', 'Property', 'AliasProperty'))
    if ($properties.Count -gt 0) {
        $members = [Collections.Generic.List[string]]::new()
        foreach ($property in $properties) {
            if ($property.Name.StartsWith('_', [StringComparison]::Ordinal)) { continue }
            $members.Add((ConvertTo-JsonStringLiteral $property.Name) + ':' + (ConvertTo-CanonicalJsonValue $property.Value))
        }
        return '{' + ($members -join ',') + '}'
    }
    throw "Unsupported canonical JSON value type '$($Value.GetType().FullName)'."
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Sha256Text {
    param([Parameter(Mandatory)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $script:Utf8NoBom.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-SafeRouteName {
    param([Parameter(Mandatory)][string]$Value)

    $safe = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $safe = $safe.Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'route' }
    if ($safe.Length -gt 48) { $safe = $safe.Substring(0, 48).TrimEnd('-') }
    return $safe
}

function New-PlayerRouteRecordingHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$RecordingId,
        [Parameter(Mandatory)][DateTimeOffset]$CreatedUtc,
        [Parameter(Mandatory)][string]$PathName,
        [Parameter(Mandatory)][string]$FromLabel,
        [Parameter(Mandatory)][string]$ToLabel,
        [Parameter(Mandatory)][ValidateSet('main-road', 'side-path', 'shortcut', 'cave', 'dungeon', 'water', 'other')][string]$PathType,
        [Parameter(Mandatory)][ValidateSet('bidirectional', 'from-to', 'to-from')][string]$Directionality,
        [AllowEmptyString()][string]$Notes = '',
        [Parameter(Mandatory)][string]$GameVersion,
        [Parameter(Mandatory)][string]$ModuleVersion,
        [ValidateRange(250, 60000)][int]$SampleIntervalMs = 2000,
        [ValidateRange(1, 1440)][int]$MaximumDurationMinutes = 120
    )

    Assert-TextLength $PathName 'Path name' 120 -Required
    Assert-TextLength $FromLabel 'From label' 120 -Required
    Assert-TextLength $ToLabel 'To label' 120 -Required
    Assert-TextLength $Notes 'Notes' 2000
    Assert-TextLength $GameVersion 'Game version' 80 -Required
    Assert-TextLength $ModuleVersion 'Module version' 80 -Required

    return [ordered]@{
        recordType = 'header'
        schema = 'playerbots-route-recording-v1'
        schemaVersion = 1
        recordingId = $RecordingId.ToString('D').ToLowerInvariant()
        createdUtc = $CreatedUtc.ToUniversalTime().ToString('O', [Globalization.CultureInfo]::InvariantCulture)
        metadata = [ordered]@{
            pathName = $PathName.Trim()
            from = $FromLabel.Trim()
            to = $ToLabel.Trim()
            pathType = $PathType
            directionality = $Directionality
            notes = $Notes.Trim()
            gameVersion = $GameVersion.Trim()
            moduleVersion = $ModuleVersion.Trim()
        }
        capture = [ordered]@{
            tool = 'playerbots-windows-route-recorder'
            toolVersion = $script:RouteToolVersion
            source = 'aaemu-loopback-command-v1'
            sampleIntervalMs = $SampleIntervalMs
            maximumDurationMinutes = $MaximumDurationMinutes
        }
    }
}

function ConvertFrom-PlayerRouteApiResponse {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$ResponseText, [int]$HttpStatusCode = 200)

    $apiResult = $null
    try { $apiResult = $ResponseText | ConvertFrom-Json } catch { }
    $messages = @()
    $errors = @()
    if ($null -ne $apiResult) {
        foreach ($name in @('Messages', 'ErrorMessages', 'Message', 'error')) {
            $property = $apiResult.PSObject.Properties[$name]
            if ($null -ne $property) {
                foreach ($value in @($property.Value)) {
                    if ($value -isnot [string]) { continue }
                    $clean = ($value -replace '\|c[0-9a-fA-F]{8}|\|r', '' -replace '[\x00-\x1f]', ' ').Trim()
                    if ($name -eq 'Messages') { $messages += $clean } else { $errors += $clean }
                }
            }
        }
    }
    $detail = (($errors + $messages | Select-Object -First 4) -join ' ')
    if ($detail.Length -gt 500) { $detail = $detail.Substring(0, 500) }
    if ($detail -match '(?i)insufficient privileges|access denied|permission') {
        throw '[GM_ACCESS] AAEmu denied this command. Use an online GM character with command access level 100.'
    }
    if ($detail -match '(?i)no commands (have been loaded|available)|compile errors') {
        throw '[SCRIPTS_NOT_LOADED] AAEmu loaded no commands. Check the Game startup log for script compilation errors; fix those before restarting Game normally.'
    }
    if ($detail -match '(?i)character.+not found|character.+offline') {
        throw '[CHARACTER_OFFLINE] AAEmu cannot find that online character. Enter the in-game character name (not account name) and log in to this local server.'
    }
    if ($HttpStatusCode -in @(401,403)) { throw '[API_ACCESS] The local Web API refused access. Check the API access settings for this server build.' }
    if ($HttpStatusCode -eq 404) { throw '[API_ENDPOINT] The command endpoint was not found. Check the local API address in Server setup (normally http://127.0.0.1:1280/api).' }
    if ($HttpStatusCode -lt 200 -or $HttpStatusCode -ge 300) {
        throw ("[API_HTTP] AAEmu returned HTTP {0}. {1}" -f $HttpStatusCode, $detail)
    }
    if ($null -eq $apiResult) { throw '[API_RESPONSE] The service returned invalid JSON. Check that the local API address points to AAEmu Game.' }
    $messagesProperty = $apiResult.PSObject.Properties['Messages']
    if ($null -eq $messagesProperty) { throw ('[API_RESPONSE] AAEmu returned no command message list. ' + $detail) }
    if ($errors.Count -gt 0) { throw ('[SERVER_ERROR] AAEmu reported: ' + $detail) }
    $message = @($messagesProperty.Value) |
        Where-Object { [string]$_ -match 'PLAYER_ROUTE_SAMPLE_V1\s+\{' } |
        Select-Object -First 1
    if ($null -eq $message) {
        if ($detail) { throw ('[NO_POSITION_SAMPLE] AAEmu answered without a position: ' + $detail) }
        throw '[NO_POSITION_SAMPLE] AAEmu answered, but the recorder command returned nothing. In game, try /playerrouteposition sample. If it is unknown, install the extension in the Game folder you actually run and restart Game. If it is known, check the Game log for a command error.'
    }

    $payloadStart = ([string]$message).IndexOf('PLAYER_ROUTE_SAMPLE_V1 ', [StringComparison]::Ordinal)
    $payload = ([string]$message).Substring($payloadStart + 'PLAYER_ROUTE_SAMPLE_V1 '.Length)
    try { $sample = $payload | ConvertFrom-Json } catch { throw 'Position payload was malformed.' }
    if ([int](Get-RequiredProperty $sample 'schemaVersion') -ne 1 -or
        [string](Get-RequiredProperty $sample 'source') -ne 'aaemu-loopback-command-v1') {
        throw 'Position payload version or source is unsupported.'
    }
    $null = ConvertTo-RouteTimestamp ([string](Get-RequiredProperty $sample 'capturedUtc')) 'position timestamp'
    foreach ($idName in @('worldId', 'instanceId', 'zoneId')) {
        $id = [long](Get-RequiredProperty $sample $idName)
        if ($id -lt 0 -or $id -gt [uint32]::MaxValue) { throw "Position payload $idName is out of range." }
    }
    foreach ($axis in @('x', 'y', 'z')) {
        $null = Assert-FiniteNumber (Get-RequiredProperty $sample $axis) "position $axis"
    }
    $headingProperty = $sample.PSObject.Properties['headingRadians']
    if ($null -ne $headingProperty -and $null -ne $headingProperty.Value) {
        $null = Assert-FiniteNumber $headingProperty.Value 'position heading' -Minimum -1000 -Maximum 1000
    }
    Assert-TextLength ([string](Get-RequiredProperty $sample 'quality')) 'Position quality' 80 -Required
    return $sample
}

function Read-PlayerRouteRecording {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not [IO.File]::Exists($resolved)) { throw "Recording '$Path' is not a file." }

    $header = $null
    $samples = [Collections.Generic.List[object]]::new()
    $events = [Collections.Generic.List[object]]::new()
    $lineNumber = 0
    $lastSequence = 0L
    $lastTimestamp = [DateTimeOffset]::MinValue

    foreach ($line in [IO.File]::ReadLines($resolved)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $record = $line | ConvertFrom-Json } catch { throw "Invalid JSON on line $lineNumber of '$resolved': $($_.Exception.Message)" }
        $recordType = [string](Get-RequiredProperty $record 'recordType')

        switch ($recordType) {
            'header' {
                if ($lineNumber -ne 1 -or $null -ne $header) { throw 'The recording must contain exactly one header on line 1.' }
                if ([string](Get-RequiredProperty $record 'schema') -ne 'playerbots-route-recording-v1' -or
                    [int](Get-RequiredProperty $record 'schemaVersion') -ne 1) {
                    throw 'Unsupported recording schema.'
                }
                $recordingId = [guid]::Empty
                if (-not [guid]::TryParse([string](Get-RequiredProperty $record 'recordingId'), [ref]$recordingId)) {
                    throw 'The recordingId is not a UUID.'
                }
                $null = ConvertTo-RouteTimestamp ([string](Get-RequiredProperty $record 'createdUtc')) 'createdUtc'
                $metadata = Get-RequiredProperty $record 'metadata'
                Assert-TextLength ([string](Get-RequiredProperty $metadata 'pathName')) 'Path name' 120 -Required
                Assert-TextLength ([string](Get-RequiredProperty $metadata 'from')) 'From label' 120 -Required
                Assert-TextLength ([string](Get-RequiredProperty $metadata 'to')) 'To label' 120 -Required
                Assert-TextLength ([string](Get-RequiredProperty $metadata 'notes')) 'Notes' 2000
                if ([string](Get-RequiredProperty $metadata 'pathType') -notin $script:PathTypes) { throw 'Unsupported path type.' }
                if ([string](Get-RequiredProperty $metadata 'directionality') -notin $script:Directions) { throw 'Unsupported directionality.' }
                $header = $record
            }
            'sample' {
                if ($null -eq $header) { throw 'A sample appears before the recording header.' }
                $sequence = [long](Get-RequiredProperty $record 'sequence')
                if ($sequence -le $lastSequence) { throw "Sample sequence is not strictly increasing on line $lineNumber." }
                $captured = ConvertTo-RouteTimestamp ([string](Get-RequiredProperty $record 'capturedUtc')) "capturedUtc on line $lineNumber"
                if ($captured -lt $lastTimestamp) { throw "Sample timestamps move backwards on line $lineNumber." }
                $null = Assert-FiniteNumber (Get-RequiredProperty $record 'x') "x on line $lineNumber"
                $null = Assert-FiniteNumber (Get-RequiredProperty $record 'y') "y on line $lineNumber"
                $null = Assert-FiniteNumber (Get-RequiredProperty $record 'z') "z on line $lineNumber"
                $headingProperty = $record.PSObject.Properties['headingRadians']
                if ($null -ne $headingProperty -and $null -ne $headingProperty.Value) {
                    $null = Assert-FiniteNumber $headingProperty.Value "headingRadians on line $lineNumber" -Minimum -1000 -Maximum 1000
                }
                foreach ($idName in @('worldId', 'instanceId', 'zoneId')) {
                    $id = [long](Get-RequiredProperty $record $idName)
                    if ($id -lt 0 -or $id -gt [uint32]::MaxValue) { throw "$idName is out of range on line $lineNumber." }
                }
                Assert-TextLength ([string](Get-RequiredProperty $record 'quality')) 'Sample quality' 80 -Required
                Assert-TextLength ([string](Get-RequiredProperty $record 'source')) 'Sample source' 120 -Required
                $record | Add-Member -NotePropertyName '_captured' -NotePropertyValue $captured
                $samples.Add($record)
                $lastSequence = $sequence
                $lastTimestamp = $captured
            }
            'event' {
                if ($null -eq $header) { throw 'An event appears before the recording header.' }
                $null = ConvertTo-RouteTimestamp ([string](Get-RequiredProperty $record 'capturedUtc')) "event timestamp on line $lineNumber"
                Assert-TextLength ([string](Get-RequiredProperty $record 'eventType')) 'Event type' 80 -Required
                Assert-TextLength ([string](Get-RequiredProperty $record 'detail')) 'Event detail' 240
                $events.Add($record)
            }
            default { throw "Unknown recordType '$recordType' on line $lineNumber." }
        }
    }

    if ($null -eq $header) { throw 'Recording header is missing.' }
    if ($samples.Count -eq 0) { throw 'Recording contains no samples.' }

    return [pscustomobject]@{
        Path = $resolved
        RawSha256 = Get-Sha256Hex $resolved
        Header = $header
        Samples = $samples.ToArray()
        Events = $events.ToArray()
    }
}

function Get-RouteDistance {
    param($Left, $Right)
    $dx = [double]$Right.x - [double]$Left.x
    $dy = [double]$Right.y - [double]$Left.y
    $dz = [double]$Right.z - [double]$Left.z
    return [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz)
}

function Get-LineDistance {
    param($Point, $Start, $End)

    $dx = [double]$End.x - [double]$Start.x
    $dy = [double]$End.y - [double]$Start.y
    $dz = [double]$End.z - [double]$Start.z
    $lengthSquared = $dx * $dx + $dy * $dy + $dz * $dz
    if ($lengthSquared -le 0.0000001) { return Get-RouteDistance $Point $Start }

    $t = (([double]$Point.x - [double]$Start.x) * $dx +
          ([double]$Point.y - [double]$Start.y) * $dy +
          ([double]$Point.z - [double]$Start.z) * $dz) / $lengthSquared
    $t = [Math]::Max(0.0, [Math]::Min(1.0, $t))
    $projected = [pscustomobject]@{
        x = [double]$Start.x + $t * $dx
        y = [double]$Start.y + $t * $dy
        z = [double]$Start.z + $t * $dz
    }
    return Get-RouteDistance $Point $projected
}

function Get-RdpSamples {
    param([object[]]$Samples, [double]$Tolerance)

    if ($Samples.Count -le 2) { return @($Samples) }
    $maximum = -1.0
    $split = -1
    for ($index = 1; $index -lt $Samples.Count - 1; $index++) {
        $distance = Get-LineDistance $Samples[$index] $Samples[0] $Samples[-1]
        if ($distance -gt $maximum) { $maximum = $distance; $split = $index }
    }
    if ($maximum -le $Tolerance) { return @($Samples[0], $Samples[-1]) }

    $left = @(Get-RdpSamples @($Samples[0..$split]) $Tolerance)
    $right = @(Get-RdpSamples @($Samples[$split..($Samples.Count - 1)]) $Tolerance)
    return @($left + $right[1..($right.Count - 1)])
}

function Get-ZoneAwareSimplifiedSamples {
    param([object[]]$Samples, [double]$Tolerance)

    if ($Samples.Count -le 2) { return @($Samples) }
    $anchors = [Collections.Generic.SortedSet[int]]::new()
    $null = $anchors.Add(0)
    $null = $anchors.Add($Samples.Count - 1)
    for ($index = 1; $index -lt $Samples.Count; $index++) {
        if ([uint32]$Samples[$index].zoneId -ne [uint32]$Samples[$index - 1].zoneId) {
            $null = $anchors.Add($index - 1)
            $null = $anchors.Add($index)
        }
    }

    $anchorArray = @($anchors)
    $result = [Collections.Generic.List[object]]::new()
    for ($anchorIndex = 0; $anchorIndex -lt $anchorArray.Count - 1; $anchorIndex++) {
        $start = $anchorArray[$anchorIndex]
        $end = $anchorArray[$anchorIndex + 1]
        $range = if ($start -eq $end) { @($Samples[$start]) } else { @($Samples[$start..$end]) }
        foreach ($sample in @(Get-RdpSamples $range $Tolerance)) {
            if ($result.Count -eq 0 -or [long]$result[-1].sequence -ne [long]$sample.sequence) { $result.Add($sample) }
        }
    }
    return $result.ToArray()
}

function Get-InterpolatedHeading {
    param($Start, $End, [double]$Fraction)

    if ($null -eq $Start -or $null -eq $End) { return $null }
    $difference = [double]$End - [double]$Start
    while ($difference -gt [Math]::PI) { $difference -= 2.0 * [Math]::PI }
    while ($difference -lt -[Math]::PI) { $difference += 2.0 * [Math]::PI }
    return [double]$Start + $difference * $Fraction
}

function ConvertTo-RoutePoint {
    param($Sample, [DateTimeOffset]$StartedUtc, [bool]$Interpolated = $false)

    $captured = if ($Sample.PSObject.Properties['_captured']) {
        $Sample._captured
    }
    else {
        ConvertTo-RouteTimestamp ([string]$Sample.capturedUtc)
    }
    $heading = $null
    if ($null -ne $Sample.PSObject.Properties['headingRadians'] -and $null -ne $Sample.headingRadians) {
        $heading = [Math]::Round([double]$Sample.headingRadians, 6)
    }
    return [ordered]@{
        offsetMs = [long][Math]::Round(($captured - $StartedUtc).TotalMilliseconds)
        worldId = [uint32]$Sample.worldId
        instanceId = [uint32]$Sample.instanceId
        zoneId = [uint32]$Sample.zoneId
        x = [Math]::Round([double]$Sample.x, 3)
        y = [Math]::Round([double]$Sample.y, 3)
        z = [Math]::Round([double]$Sample.z, 3)
        headingRadians = $heading
        quality = if ($Interpolated) { 'interpolated' } else { [string]$Sample.quality }
        sourceSequence = if ($Interpolated) { $null } else { [long]$Sample.sequence }
    }
}

function Expand-RoutePoints {
    param([object[]]$Samples, [DateTimeOffset]$StartedUtc, [double]$MaximumSpacingMeters)

    $result = [Collections.Generic.List[object]]::new()
    $result.Add((ConvertTo-RoutePoint $Samples[0] $StartedUtc))
    for ($index = 1; $index -lt $Samples.Count; $index++) {
        $left = $Samples[$index - 1]
        $right = $Samples[$index]
        $distance = Get-RouteDistance $left $right
        $parts = [Math]::Max(1, [int][Math]::Ceiling($distance / $MaximumSpacingMeters))
        for ($part = 1; $part -lt $parts; $part++) {
            $fraction = [double]$part / $parts
            $leftTime = $left._captured
            $rightTime = $right._captured
            $interpolatedTime = $leftTime.AddTicks([long][Math]::Round(($rightTime - $leftTime).Ticks * $fraction))
            $interpolated = [pscustomobject]@{
                capturedUtc = $interpolatedTime.ToString('O', [Globalization.CultureInfo]::InvariantCulture)
                _captured = $interpolatedTime
                worldId = $left.worldId
                instanceId = $left.instanceId
                zoneId = if ($fraction -lt 0.5) { $left.zoneId } else { $right.zoneId }
                x = [double]$left.x + ([double]$right.x - [double]$left.x) * $fraction
                y = [double]$left.y + ([double]$right.y - [double]$left.y) * $fraction
                z = [double]$left.z + ([double]$right.z - [double]$left.z) * $fraction
                headingRadians = Get-InterpolatedHeading $left.headingRadians $right.headingRadians $fraction
                quality = 'interpolated'
                sequence = 0L
            }
            $result.Add((ConvertTo-RoutePoint $interpolated $StartedUtc $true))
        }
        $result.Add((ConvertTo-RoutePoint $right $StartedUtc))
    }
    return $result.ToArray()
}

function Test-EventBoundary {
    param([object[]]$Events, [DateTimeOffset]$After, [DateTimeOffset]$Through)

    foreach ($eventRecord in $Events) {
        if ([string]$eventRecord.eventType -notin @('disconnected', 'paused')) { continue }
        $eventTime = ConvertTo-RouteTimestamp ([string]$eventRecord.capturedUtc) 'event timestamp'
        if ($eventTime -gt $After -and $eventTime -le $Through) { return $true }
    }
    return $false
}

function ConvertTo-PlayerRouteDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Recording,
        [ValidateRange(0.05, 20.0)][double]$StationaryToleranceMeters = 0.5,
        [ValidateRange(0.05, 20.0)][double]$SimplificationToleranceMeters = 1.5,
        [ValidateRange(0.5, 100.0)][double]$MaximumSpacingMeters = 8.0,
        [ValidateRange(5.0, 1000.0)][double]$TeleportDistanceMeters = 150.0,
        [ValidateRange(1.0, 500.0)][double]$MaximumPlausibleSpeedMetersPerSecond = 80.0
    )

    $samples = @($Recording.Samples)
    $startedUtc = $samples[0]._captured
    $endedUtc = $samples[-1]._captured
    $chunks = [Collections.Generic.List[object]]::new()
    $current = [Collections.Generic.List[object]]::new()
    $current.Add($samples[0])
    $generatedEvents = [Collections.Generic.List[object]]::new()
    $teleportCount = 0
    $contextChangeCount = 0

    for ($index = 1; $index -lt $samples.Count; $index++) {
        $previous = $samples[$index - 1]
        $sample = $samples[$index]
        $elapsedSeconds = [Math]::Max(0.001, ($sample._captured - $previous._captured).TotalSeconds)
        $distance = Get-RouteDistance $previous $sample
        $contextChanged = [uint32]$sample.worldId -ne [uint32]$previous.worldId -or
                          [uint32]$sample.instanceId -ne [uint32]$previous.instanceId
        $teleported = -not $contextChanged -and
            ($distance -ge $TeleportDistanceMeters -or $distance / $elapsedSeconds -gt $MaximumPlausibleSpeedMetersPerSecond)
        $eventBoundary = Test-EventBoundary @($Recording.Events) $previous._captured $sample._captured
        $sampleGap = $elapsedSeconds -gt [Math]::Max(10.0, [double]$Recording.Header.capture.sampleIntervalMs / 1000.0 * 3.0)

        if ($contextChanged -or $teleported -or $eventBoundary -or $sampleGap) {
            if ($current.Count -gt 0) { $chunks.Add($current.ToArray()) }
            $current = [Collections.Generic.List[object]]::new()
            if ($contextChanged) {
                $contextChangeCount++
                $generatedEvents.Add([ordered]@{
                    capturedUtc = $sample._captured.ToString('O', [Globalization.CultureInfo]::InvariantCulture)
                    eventType = 'world-or-instance-change'
                    detail = "world=$($sample.worldId), instance=$($sample.instanceId)"
                })
            }
            elseif ($teleported) {
                $teleportCount++
                $generatedEvents.Add([ordered]@{
                    capturedUtc = $sample._captured.ToString('O', [Globalization.CultureInfo]::InvariantCulture)
                    eventType = 'teleport-detected'
                    detail = "gapMeters=$([Math]::Round($distance, 3))"
                })
            }
            elseif ($sampleGap) {
                $generatedEvents.Add([ordered]@{
                    capturedUtc = $sample._captured.ToString('O', [Globalization.CultureInfo]::InvariantCulture)
                    eventType = 'sample-gap-detected'
                    detail = "gapSeconds=$([Math]::Round($elapsedSeconds, 3))"
                })
            }
        }
        $current.Add($sample)
    }
    if ($current.Count -gt 0) { $chunks.Add($current.ToArray()) }

    $segments = [Collections.Generic.List[object]]::new()
    $stationaryDropped = 0
    $zoneTransitions = 0
    $normalizedPointCount = 0
    $segmentNumber = 0

    foreach ($chunkObject in $chunks) {
        $chunk = @($chunkObject)
        if ($chunk.Count -lt 2) { continue }
        $moving = [Collections.Generic.List[object]]::new()
        $moving.Add($chunk[0])
        for ($index = 1; $index -lt $chunk.Count - 1; $index++) {
            $zoneChanged = [uint32]$chunk[$index].zoneId -ne [uint32]$chunk[$index - 1].zoneId
            if ($zoneChanged -or (Get-RouteDistance $moving[-1] $chunk[$index]) -ge $StationaryToleranceMeters) {
                $moving.Add($chunk[$index])
            }
            else { $stationaryDropped++ }
        }
        if ([long]$moving[-1].sequence -ne [long]$chunk[-1].sequence) { $moving.Add($chunk[-1]) }
        if ($moving.Count -lt 2) { continue }
        # A town circuit can end at its start and still contain a useful walk.
        $hasTravel = $false
        foreach ($point in $moving) { if ((Get-RouteDistance $moving[0] $point) -ge 0.05) { $hasTravel = $true; break } }
        if (-not $hasTravel) { continue }

        for ($index = 1; $index -lt $moving.Count; $index++) {
            if ([uint32]$moving[$index].zoneId -ne [uint32]$moving[$index - 1].zoneId) { $zoneTransitions++ }
        }
        $simplified = @(Get-ZoneAwareSimplifiedSamples $moving.ToArray() $SimplificationToleranceMeters)
        $points = @(Expand-RoutePoints $simplified $startedUtc $MaximumSpacingMeters)
        if ($points.Count -lt 2) { continue }
        $segmentNumber++
        $normalizedPointCount += $points.Count
        $segments.Add([ordered]@{
            id = 's{0:d4}' -f $segmentNumber
            worldId = [uint32]$points[0].worldId
            instanceId = [uint32]$points[0].instanceId
            points = $points
        })
    }

    if ($segments.Count -eq 0) {
        throw 'Recording has fewer than two traversable points after stationary and discontinuity checks.'
    }

    $events = [Collections.Generic.List[object]]::new()
    foreach ($eventRecord in @($Recording.Events)) {
        $events.Add([ordered]@{
            capturedUtc = (ConvertTo-RouteTimestamp ([string]$eventRecord.capturedUtc)).ToString('O', [Globalization.CultureInfo]::InvariantCulture)
            eventType = [string]$eventRecord.eventType
            detail = [string]$eventRecord.detail
        })
    }
    foreach ($eventRecord in $generatedEvents) { $events.Add($eventRecord) }
    $orderedEvents = @($events | Sort-Object @{Expression = { $_.capturedUtc }}, @{Expression = { $_.eventType }})

    return [ordered]@{
        schema = 'playerbots-route-v1'
        schemaVersion = 1
        recordingId = [string]$Recording.Header.recordingId
        metadata = [ordered]@{
            pathName = [string]$Recording.Header.metadata.pathName
            from = [string]$Recording.Header.metadata.from
            to = [string]$Recording.Header.metadata.to
            pathType = [string]$Recording.Header.metadata.pathType
            directionality = [string]$Recording.Header.metadata.directionality
            notes = [string]$Recording.Header.metadata.notes
            gameVersion = [string]$Recording.Header.metadata.gameVersion
            moduleVersion = [string]$Recording.Header.metadata.moduleVersion
        }
        captureSummary = [ordered]@{
            startedUtc = $startedUtc.ToString('O', [Globalization.CultureInfo]::InvariantCulture)
            endedUtc = $endedUtc.ToString('O', [Globalization.CultureInfo]::InvariantCulture)
            sampleIntervalMs = [int]$Recording.Header.capture.sampleIntervalMs
            source = [string]$Recording.Header.capture.source
        }
        normalization = [ordered]@{
            tool = 'playerbots-route-offline-normalizer'
            toolVersion = $script:RouteToolVersion
            stationaryToleranceMeters = $StationaryToleranceMeters
            simplificationToleranceMeters = $SimplificationToleranceMeters
            maximumSpacingMeters = $MaximumSpacingMeters
            teleportDistanceMeters = $TeleportDistanceMeters
            maximumPlausibleSpeedMetersPerSecond = $MaximumPlausibleSpeedMetersPerSecond
        }
        statistics = [ordered]@{
            rawSamples = $samples.Count
            stationarySamplesDropped = $stationaryDropped
            normalizedPoints = $normalizedPointCount
            segments = $segments.Count
            zoneTransitions = $zoneTransitions
            teleportsDetected = $teleportCount
            worldOrInstanceChanges = $contextChangeCount
            disconnects = @($Recording.Events | Where-Object { $_.eventType -eq 'disconnected' }).Count
        }
        segments = $segments.ToArray()
        events = $orderedEvents
        provenance = [ordered]@{
            rawRecordingSha256 = [string]$Recording.RawSha256
            recordingSchema = [string]$Recording.Header.schema
            recorderToolVersion = [string]$Recording.Header.capture.toolVersion
        }
    }
}

function New-DeterministicZip {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string[]]$FileNames)

    if ([IO.File]::Exists($Path)) { throw "Refusing to overwrite '$Path'." }
    if (-not ('PlayerBots.RouteRecorder.Crc32' -as [type])) {
        Add-Type -TypeDefinition @'
namespace PlayerBots.RouteRecorder
{
    public static class Crc32
    {
        public static uint Compute(byte[] data)
        {
            uint crc = 0xffffffffu;
            foreach (byte value in data)
            {
                crc ^= value;
                for (int bit = 0; bit < 8; bit++)
                    crc = (crc >> 1) ^ ((crc & 1u) == 0u ? 0u : 0xedb88320u);
            }
            return ~crc;
        }
    }
}
'@
    }

    $entries = [Collections.Generic.List[object]]::new()
    $fileStream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = [IO.BinaryWriter]::new($fileStream, [Text.Encoding]::UTF8, $true)
    try {
        foreach ($fileName in $FileNames) {
            $nameBytes = [Text.Encoding]::UTF8.GetBytes($fileName.Replace('\', '/'))
            $bytes = [IO.File]::ReadAllBytes((Join-Path $Directory $fileName))
            if ($bytes.LongLength -gt [uint32]::MaxValue -or $fileStream.Position -gt [uint32]::MaxValue) {
                throw 'Route bundles must remain below the ZIP32 size limit.'
            }
            $crc = [PlayerBots.RouteRecorder.Crc32]::Compute($bytes)
            $offset = [uint32]$fileStream.Position
            $writer.Write([uint32]0x04034b50)
            $writer.Write([uint16]20)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]33)
            $writer.Write([uint32]$crc)
            $writer.Write([uint32]$bytes.Length)
            $writer.Write([uint32]$bytes.Length)
            $writer.Write([uint16]$nameBytes.Length)
            $writer.Write([uint16]0)
            $writer.Write($nameBytes)
            $writer.Write($bytes)
            $entries.Add([pscustomobject]@{
                NameBytes = $nameBytes
                Bytes = $bytes
                Crc = $crc
                Offset = $offset
            })
        }

        $centralOffset = [uint32]$fileStream.Position
        foreach ($entry in $entries) {
            $writer.Write([uint32]0x02014b50)
            $writer.Write([uint16]20)
            $writer.Write([uint16]20)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]33)
            $writer.Write([uint32]$entry.Crc)
            $writer.Write([uint32]$entry.Bytes.Length)
            $writer.Write([uint32]$entry.Bytes.Length)
            $writer.Write([uint16]$entry.NameBytes.Length)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint32]0)
            $writer.Write([uint32]$entry.Offset)
            $writer.Write([byte[]]$entry.NameBytes)
        }
        $centralSize = [uint32]($fileStream.Position - $centralOffset)
        $writer.Write([uint32]0x06054b50)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)
        $writer.Write([uint16]$entries.Count)
        $writer.Write([uint16]$entries.Count)
        $writer.Write($centralSize)
        $writer.Write($centralOffset)
        $writer.Write([uint16]0)
        $writer.Flush()
    }
    finally {
        $writer.Dispose()
        $fileStream.Dispose()
    }
}

function Export-PlayerRouteBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RecordingPath,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [ValidateRange(0.05, 20.0)][double]$StationaryToleranceMeters = 0.5,
        [ValidateRange(0.05, 20.0)][double]$SimplificationToleranceMeters = 1.5,
        [ValidateRange(0.5, 100.0)][double]$MaximumSpacingMeters = 8.0,
        [ValidateRange(5.0, 1000.0)][double]$TeleportDistanceMeters = 150.0,
        [ValidateRange(1.0, 500.0)][double]$MaximumPlausibleSpeedMetersPerSecond = 80.0
    )

    $recording = Read-PlayerRouteRecording $RecordingPath
    $route = ConvertTo-PlayerRouteDocument $recording `
        -StationaryToleranceMeters $StationaryToleranceMeters `
        -SimplificationToleranceMeters $SimplificationToleranceMeters `
        -MaximumSpacingMeters $MaximumSpacingMeters `
        -TeleportDistanceMeters $TeleportDistanceMeters `
        -MaximumPlausibleSpeedMetersPerSecond $MaximumPlausibleSpeedMetersPerSecond

    $supplements = Get-PlayerRouteSupplementDocuments $recording $route
    $outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
    [IO.Directory]::CreateDirectory($outputRoot) | Out-Null
    $baseName = '{0}-{1}' -f (Get-SafeRouteName ([string]$route.metadata.pathName)), ([string]$route.recordingId).Substring(0, 8)
    $bundleDirectory = Join-Path $outputRoot $baseName
    $zipPath = Join-Path $outputRoot ($baseName + '.zip')
    $zipChecksumPath = $zipPath + '.sha256'
    if ([IO.Directory]::Exists($bundleDirectory) -or [IO.File]::Exists($zipPath) -or [IO.File]::Exists($zipChecksumPath)) {
        throw "Refusing to overwrite an existing export named '$baseName'."
    }
    [IO.Directory]::CreateDirectory($bundleDirectory) | Out-Null

    $routePath = Join-Path $bundleDirectory 'route.json'
    Write-Utf8File $routePath (ConvertTo-StableJson $route)
    $routeHash = Get-Sha256Hex $routePath
    $routeBytes = (Get-Item -LiteralPath $routePath).Length
    $payloadFiles = [Collections.Generic.List[object]]::new()
    $payloadFiles.Add([ordered]@{ path='route.json'; sha256=$routeHash; bytes=$routeBytes })
    foreach ($name in $supplements.Keys) {
        $path = Join-Path $bundleDirectory $name
        Write-Utf8File $path (ConvertTo-StableJson $supplements[$name])
        $payloadFiles.Add([ordered]@{path=$name;sha256=(Get-Sha256Hex $path);bytes=(Get-Item -LiteralPath $path).Length})
    }
    $manifest = [ordered]@{
        schema = 'playerbots-route-bundle-manifest-v1'
        schemaVersion = 1
        bundleId = [string]$route.recordingId
        createdUtc = [string]$route.captureSummary.endedUtc
        files = @($payloadFiles | Sort-Object path)
        provenance = [ordered]@{
            rawRecordingSha256 = [string]$recording.RawSha256
            normalizer = 'playerbots-route-offline-normalizer'
            normalizerVersion = $script:RouteToolVersion
        }
        privacy = [ordered]@{
            containsCredentials = $false
            containsServerLogs = $false
            containsRawRecording = $false
        }
    }
    $manifestPath = Join-Path $bundleDirectory 'manifest.json'
    Write-Utf8File $manifestPath (ConvertTo-StableJson $manifest)
    $manifestHash = Get-Sha256Hex $manifestPath
    $checksumsPath = Join-Path $bundleDirectory 'SHA256SUMS.txt'
    $checksumLines = @("$manifestHash *manifest.json") + @($manifest.files | ForEach-Object { "$($_.sha256) *$($_.path)" })
    Write-Utf8File $checksumsPath (($checksumLines -join "`n") + "`n")

    New-DeterministicZip $zipPath $bundleDirectory (@('manifest.json', 'SHA256SUMS.txt') + @($manifest.files.path))
    $zipHash = Get-Sha256Hex $zipPath
    Write-Utf8File $zipChecksumPath ("$zipHash *$([IO.Path]::GetFileName($zipPath))`n")

    return [pscustomobject]@{
        BundleDirectory = $bundleDirectory
        BundleZip = $zipPath
        BundleZipChecksum = $zipChecksumPath
        Route = $routePath
        Manifest = $manifestPath
        Sha256 = $zipHash
        Statistics = [pscustomobject]$route.statistics
    }
}

function Read-RouteFromZip {
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $routeEntry = @($archive.Entries | Where-Object { $_.FullName -eq 'route.json' })
        if ($routeEntry.Count -ne 1) { throw "Bundle '$Path' must contain exactly one route.json." }
        $stream = $routeEntry[0].Open()
        try {
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
            try { $json = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        finally { $stream.Dispose() }

        $manifestEntry = @($archive.Entries | Where-Object { $_.FullName -eq 'manifest.json' })
        if ($manifestEntry.Count -ne 1) { throw "Bundle '$Path' must contain exactly one manifest.json." }
        $manifestStream = $manifestEntry[0].Open()
        try {
            $manifestReader = [IO.StreamReader]::new($manifestStream, [Text.Encoding]::UTF8, $true)
            try { $manifest = $manifestReader.ReadToEnd() | ConvertFrom-Json } finally { $manifestReader.Dispose() }
        }
        finally { $manifestStream.Dispose() }
        if ([string](Get-RequiredProperty $manifest 'schema') -ne 'playerbots-route-bundle-manifest-v1' -or
            [int](Get-RequiredProperty $manifest 'schemaVersion') -ne 1) {
            throw "Bundle '$Path' has an unsupported manifest."
        }
        $expected = @($manifest.files | Where-Object { $_.path -eq 'route.json' })
        if ($expected.Count -ne 1 -or [string]$expected[0].sha256 -ne (Get-Sha256Text $json)) {
            throw "Bundle '$Path' failed its route.json checksum."
        }
        return ($json | ConvertFrom-Json)
    }
    finally { $archive.Dispose() }
}

function Read-PlayerRouteDocument {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $manifestPath = $null
    if ([IO.Directory]::Exists($resolved)) {
        $manifestPath = Join-Path $resolved 'manifest.json'
        $resolved = Join-Path $resolved 'route.json'
    }
    if ($resolved.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) {
        $route = Read-RouteFromZip $resolved
    }
    else {
        if (-not [IO.File]::Exists($resolved)) { throw "Normalized route '$resolved' does not exist." }
        $route = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json
        if ($null -eq $manifestPath) {
            $candidateManifest = Join-Path ([IO.Path]::GetDirectoryName($resolved)) 'manifest.json'
            if ([IO.File]::Exists($candidateManifest)) { $manifestPath = $candidateManifest }
        }
        if ($null -ne $manifestPath -and [IO.File]::Exists($manifestPath)) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            if ([string](Get-RequiredProperty $manifest 'schema') -ne 'playerbots-route-bundle-manifest-v1' -or
                [int](Get-RequiredProperty $manifest 'schemaVersion') -ne 1) {
                throw "Manifest beside '$resolved' is unsupported."
            }
            $expected = @($manifest.files | Where-Object { $_.path -eq 'route.json' })
            if ($expected.Count -ne 1 -or [string]$expected[0].sha256 -ne (Get-Sha256Hex $resolved)) {
                throw "Normalized route '$resolved' failed its manifest checksum."
            }
        }
    }
    if ([string](Get-RequiredProperty $route 'schema') -ne 'playerbots-route-v1' -or
        [int](Get-RequiredProperty $route 'schemaVersion') -ne 1) {
        throw "'$Path' is not a supported normalized route."
    }
    $recordingId = [guid]::Empty
    if (-not [guid]::TryParse([string](Get-RequiredProperty $route 'recordingId'), [ref]$recordingId)) {
        throw "'$Path' has an invalid recordingId."
    }
    if (@(Get-RequiredProperty $route 'segments').Count -eq 0) { throw "'$Path' contains no route segments." }
    return $route
}

function Get-ConsensusConfidence {
    param([int]$Sources, [double]$SpreadMeters = 0, [double]$MergeRadiusMeters = 1)

    $sourceConfidence = 1.0 - [Math]::Exp(-0.7 * $Sources)
    $agreement = 1.0 - [Math]::Min(0.5, $SpreadMeters / ([Math]::Max(0.001, $MergeRadiusMeters) * 2.0))
    return [Math]::Round($sourceConfidence * $agreement, 3)
}

function Merge-PlayerRouteGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$InputPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [ValidateRange(0.1, 25.0)][double]$MergeRadiusMeters = 3.0
    )

    if ([IO.File]::Exists([IO.Path]::GetFullPath($OutputPath))) { throw "Refusing to overwrite '$OutputPath'." }
    $routes = @($InputPath | ForEach-Object { Read-PlayerRouteDocument $_ } | Sort-Object recordingId)
    if ($routes.Count -eq 0) { throw 'At least one route is required.' }
    $versions = @($routes | ForEach-Object { $_.metadata.gameVersion.Trim().ToLowerInvariant() } | Sort-Object -Unique)
    if ($versions.Count -gt 1) { throw 'Routes declare different client builds. Keep them separate for compatibility review.' }
    $duplicateIds = @($routes | Group-Object recordingId | Where-Object Count -gt 1)
    if ($duplicateIds.Count -gt 0) { throw "Duplicate recordingId '$($duplicateIds[0].Name)'." }

    $nodes = [Collections.Generic.List[object]]::new()
    $pointNode = @{}
    foreach ($route in $routes) {
        foreach ($segment in @($route.segments | Sort-Object id)) {
            $pointIndex = 0
            foreach ($point in @($segment.points)) {
                $x = Assert-FiniteNumber $point.x 'route point x'
                $y = Assert-FiniteNumber $point.y 'route point y'
                $z = Assert-FiniteNumber $point.z 'route point z'
                $candidate = $null
                $candidateDistance = [double]::MaxValue
                foreach ($node in $nodes) {
                    if ($node.WorldId -ne [uint32]$point.worldId -or $node.InstanceId -ne [uint32]$point.instanceId) { continue }
                    $centroid = [pscustomobject]@{ x = $node.SumX / $node.Count; y = $node.SumY / $node.Count; z = $node.SumZ / $node.Count }
                    $distance = Get-RouteDistance $point $centroid
                    if ($distance -le $MergeRadiusMeters -and $distance -lt $candidateDistance) {
                        $candidate = $node
                        $candidateDistance = $distance
                    }
                }
                if ($null -eq $candidate) {
                    $candidate = [pscustomobject]@{
                        Index = $nodes.Count
                        WorldId = [uint32]$point.worldId
                        InstanceId = [uint32]$point.instanceId
                        SumX = 0.0
                        SumY = 0.0
                        SumZ = 0.0
                        Count = 0
                        Observations = [Collections.Generic.List[object]]::new()
                    }
                    $nodes.Add($candidate)
                }
                $candidate.SumX += $x; $candidate.SumY += $y; $candidate.SumZ += $z; $candidate.Count++
                $candidate.Observations.Add([pscustomobject]@{
                    recordingId = [string]$route.recordingId
                    zoneId = [uint32]$point.zoneId
                    x = $x; y = $y; z = $z
                })
                $pointNode["$($route.recordingId)|$($segment.id)|$pointIndex"] = $candidate.Index
                $pointIndex++
            }
        }
    }

    $graphNodes = [Collections.Generic.List[object]]::new()
    foreach ($node in $nodes) {
        $cx = $node.SumX / $node.Count; $cy = $node.SumY / $node.Count; $cz = $node.SumZ / $node.Count
        $sourceGroups = @($node.Observations | Group-Object recordingId | Sort-Object Name)
        $observations = [Collections.Generic.List[object]]::new()
        $spread = 0.0
        foreach ($group in $sourceGroups) {
            $gx = ($group.Group | Measure-Object x -Average).Average
            $gy = ($group.Group | Measure-Object y -Average).Average
            $gz = ($group.Group | Measure-Object z -Average).Average
            $distance = Get-RouteDistance ([pscustomobject]@{ x = $gx; y = $gy; z = $gz }) ([pscustomobject]@{ x = $cx; y = $cy; z = $cz })
            $spread = [Math]::Max($spread, $distance)
            $observations.Add([ordered]@{
                recordingId = $group.Name
                x = [Math]::Round([double]$gx, 3)
                y = [Math]::Round([double]$gy, 3)
                z = [Math]::Round([double]$gz, 3)
                zoneIds = @($group.Group.zoneId | Sort-Object -Unique)
                distanceFromConsensusMeters = [Math]::Round($distance, 3)
            })
        }
        $zoneVotes = [ordered]@{}
        foreach ($zoneGroup in @($node.Observations | Group-Object zoneId | Sort-Object { [uint32]$_.Name })) {
            $zoneVotes[[string]$zoneGroup.Name] = @($zoneGroup.Group.recordingId | Sort-Object -Unique).Count
        }
        $graphNodes.Add([ordered]@{
            id = 'n{0:d6}' -f ($node.Index + 1)
            worldId = $node.WorldId
            instanceId = $node.InstanceId
            x = [Math]::Round($cx, 3)
            y = [Math]::Round($cy, 3)
            z = [Math]::Round($cz, 3)
            confidence = Get-ConsensusConfidence $sourceGroups.Count $spread $MergeRadiusMeters
            supportCount = $sourceGroups.Count
            spreadMeters = [Math]::Round($spread, 3)
            zoneVotes = $zoneVotes
            observations = $observations.ToArray()
        })
    }

    $edgeMap = @{}
    foreach ($route in $routes) {
        foreach ($segment in @($route.segments | Sort-Object id)) {
            $points = @($segment.points)
            for ($index = 1; $index -lt $points.Count; $index++) {
                $leftIndex = [int]$pointNode["$($route.recordingId)|$($segment.id)|$($index - 1)"]
                $rightIndex = [int]$pointNode["$($route.recordingId)|$($segment.id)|$index"]
                if ($leftIndex -eq $rightIndex) { continue }
                $direction = [string]$route.metadata.directionality
                if ($direction -eq 'to-from') { $swap = $leftIndex; $leftIndex = $rightIndex; $rightIndex = $swap }
                $minimum = [Math]::Min($leftIndex, $rightIndex); $maximum = [Math]::Max($leftIndex, $rightIndex)
                $edgeKey = "$minimum|$maximum"
                if (-not $edgeMap.ContainsKey($edgeKey)) {
                    $edgeMap[$edgeKey] = [pscustomobject]@{
                        Minimum = $minimum
                        Maximum = $maximum
                        Support = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                        PathTypes = @{}
                        Directions = @{}
                    }
                }
                $edge = $edgeMap[$edgeKey]
                $null = $edge.Support.Add([string]$route.recordingId)
                $pathType = [string]$route.metadata.pathType
                if (-not $edge.PathTypes.ContainsKey($pathType)) { $edge.PathTypes[$pathType] = 0 }
                $edge.PathTypes[$pathType]++
                if ($direction -eq 'bidirectional') {
                    foreach ($directionKey in @('both')) {
                        if (-not $edge.Directions.ContainsKey($directionKey)) { $edge.Directions[$directionKey] = 0 }
                        $edge.Directions[$directionKey]++
                    }
                }
                else {
                    $directionKey = if ($leftIndex -eq $minimum) { 'a-to-b' } else { 'b-to-a' }
                    if (-not $edge.Directions.ContainsKey($directionKey)) { $edge.Directions[$directionKey] = 0 }
                    $edge.Directions[$directionKey]++
                }
            }
        }
    }

    $graphEdges = [Collections.Generic.List[object]]::new()
    $edgeNumber = 0
    foreach ($pair in @($edgeMap.GetEnumerator() | Sort-Object { [int]($_.Key.Split('|')[0]) }, { [int]($_.Key.Split('|')[1]) })) {
        $edge = $pair.Value; $edgeNumber++
        $pathVotes = [ordered]@{}
        foreach ($key in @($edge.PathTypes.Keys | Sort-Object)) { $pathVotes[$key] = $edge.PathTypes[$key] }
        $directionVotes = [ordered]@{}
        foreach ($key in @($edge.Directions.Keys | Sort-Object)) { $directionVotes[$key] = $edge.Directions[$key] }
        $graphEdges.Add([ordered]@{
            id = 'e{0:d6}' -f $edgeNumber
            a = 'n{0:d6}' -f ($edge.Minimum + 1)
            b = 'n{0:d6}' -f ($edge.Maximum + 1)
            confidence = Get-ConsensusConfidence $edge.Support.Count 0 $MergeRadiusMeters
            supportCount = $edge.Support.Count
            recordingIds = @($edge.Support | Sort-Object)
            pathTypeVotes = $pathVotes
            directionVotes = $directionVotes
        })
    }

    $identity = ($routes | ForEach-Object { "$($_.recordingId):$($_.provenance.rawRecordingSha256)" }) -join "`n"
    $graphId = (Get-Sha256Text $identity).Substring(0, 16)
    $generatedUtc = @($routes.captureSummary.endedUtc | ForEach-Object {
        ConvertTo-RouteTimestamp ([string]$_)
    } | Sort-Object | Select-Object -Last 1)[0]
    $sourceRoutes = @($routes | ForEach-Object {
        [ordered]@{
            recordingId = [string]$_.recordingId
            pathName = [string]$_.metadata.pathName
            pathType = [string]$_.metadata.pathType
            rawRecordingSha256 = [string]$_.provenance.rawRecordingSha256
        }
    })
    $graph = [ordered]@{
        schema = 'playerbots-route-graph-v1'
        schemaVersion = 1
        graphId = $graphId
        generatedUtc = $generatedUtc.ToString('O', [Globalization.CultureInfo]::InvariantCulture)
        merge = [ordered]@{
            tool = 'playerbots-route-merge'
            toolVersion = $script:RouteToolVersion
            mergeRadiusMeters = $MergeRadiusMeters
            method = 'deterministic-greedy-spatial-consensus'
        }
        sourceRoutes = $sourceRoutes
        nodes = $graphNodes.ToArray()
        edges = $graphEdges.ToArray()
    }

    $absoluteOutput = [IO.Path]::GetFullPath($OutputPath)
    $parent = [IO.Path]::GetDirectoryName($absoluteOutput)
    if (-not [string]::IsNullOrWhiteSpace($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    Write-Utf8File $absoluteOutput (ConvertTo-StableJson $graph)
    $checksumPath = $absoluteOutput + '.sha256'
    $hash = Get-Sha256Hex $absoluteOutput
    Write-Utf8File $checksumPath ("$hash *$([IO.Path]::GetFileName($absoluteOutput))`n")
    return [pscustomobject]@{
        Graph = $absoluteOutput
        Checksum = $checksumPath
        Sha256 = $hash
        Nodes = $graphNodes.Count
        Edges = $graphEdges.Count
        SourceRoutes = $routes.Count
    }
}

Export-ModuleMember -Function @(
    'New-PlayerRouteRecordingHeader',
    'ConvertFrom-PlayerRouteApiResponse',
    'Read-PlayerRouteRecording',
    'ConvertTo-PlayerRouteDocument',
    'Export-PlayerRouteBundle',
    'Read-PlayerRouteDocument',
    'Merge-PlayerRouteGraph',
    'Assert-PlayerRouteJunction',
    'ConvertTo-PlayerRouteNetwork'
)
