# Loaded by PlayerRouteTools.psm1; shares its validation and serialization helpers.

function Assert-PlayerRouteJunction {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)]$Position, [object[]]$Existing = @())
    Assert-TextLength $Label 'Junction name' 40 -Required
    foreach ($node in $Existing) {
        if ($node.label -ine $Label.Trim()) { continue }
        if ([uint32]$node.worldId -ne [uint32]$Position.worldId -or [uint32]$node.instanceId -ne [uint32]$Position.instanceId) { continue }
        $dx = [double]$node.x - [double]$Position.x; $dy = [double]$node.y - [double]$Position.y
        if ([Math]::Sqrt($dx*$dx+$dy*$dy) -gt 1.5 -or [Math]::Abs([double]$node.z - [double]$Position.z) -gt 0.75) {
            throw "Junction '$Label' is elsewhere or on another floor. Return to the same spot, or use a different name. No junction was joined."
        }
    }
}

function ConvertTo-PlayerRouteNetwork {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Recording)

    $samples = @($Recording.Samples)
    $bySequence = @{}
    foreach ($sample in $samples) { $bySequence[[string]$sample.sequence] = $sample }
    $marks = @{}
    foreach ($eventRecord in @($Recording.Events | Where-Object eventType -eq 'network-node')) {
        try { $mark = $eventRecord.detail | ConvertFrom-Json } catch { throw 'A junction event contains invalid JSON.' }
        $label = [string](Get-RequiredProperty $mark 'label')
        Assert-TextLength $label 'Junction name' 40 -Required
        $sequence = Get-RequiredProperty $mark 'sequence'
        if ([string]$sequence -notmatch '^[1-9][0-9]*$' -or -not $bySequence.ContainsKey([string]$sequence)) { throw 'A junction refers to a missing sample.' }
        if ((ConvertTo-RouteTimestamp $eventRecord.capturedUtc) -ne $bySequence[[string]$sequence]._captured) { throw 'A junction timestamp does not match its fresh sample.' }
        if ($marks.ContainsKey([string]$sequence)) { throw 'A sample has more than one junction mark.' }
        $marks[[string]$sequence] = $label.Trim()
    }

    $nodes = [Collections.Generic.List[object]]::new()
    $namedNodes = @{}
    $edges = [Collections.Generic.List[object]]::new()
    $breaks = [Collections.Generic.List[object]]::new()
    $chunks = [Collections.Generic.List[object]]::new()
    $chunk = [Collections.Generic.List[object]]::new()
    $maximumGap = [Math]::Max(10.0, [double]$Recording.Header.capture.sampleIntervalMs / 1000.0 * 3.0)
    foreach ($sample in $samples) {
        if ($chunk.Count -gt 0) {
            $previous = $chunk[-1]
            $seconds = ($sample._captured - $previous._captured).TotalSeconds
            $distance = Get-RouteDistance $previous $sample
            $reason = $null
            if ($previous.worldId -ne $sample.worldId -or $previous.instanceId -ne $sample.instanceId) { $reason = 'world-or-instance-change' }
            elseif (Test-EventBoundary @($Recording.Events) $previous._captured $sample._captured) { $reason = 'pause-or-disconnect' }
            elseif ($seconds -gt $maximumGap) { $reason = 'sample-gap' }
            elseif ($distance -ge 150 -or $distance / [Math]::Max(0.001,$seconds) -gt 80) { $reason = 'implausible-movement' }
            if ($reason) {
                $chunks.Add($chunk.ToArray()); $chunk = [Collections.Generic.List[object]]::new()
                $breaks.Add([ordered]@{ beforeSequence = [long]$previous.sequence; afterSequence = [long]$sample.sequence; reason = $reason })
            }
        }
        $chunk.Add($sample)
    }
    if ($chunk.Count -gt 0) { $chunks.Add($chunk.ToArray()) }

    # Only an explicit repeated name joins nodes; geometry alone never connects roads.
    function Resolve-SurveyNode($Point) {
        $label = $marks[[string]$Point.sequence]
        $key = if ($label) { '{0}|{1}|{2}' -f $Point.worldId,$Point.instanceId,$label.ToLowerInvariant() } else { $null }
        if ($key -and $namedNodes.ContainsKey($key)) {
            $node = $namedNodes[$key]
            Assert-PlayerRouteJunction $label $Point @($node)
            $node.sampleSequences += [long]$Point.sequence
            return $node.id
        }
        $node = [ordered]@{
            id = 'n{0:d6}' -f ($nodes.Count+1)
            label = if ($label) { $label } else { 'Unmarked endpoint' }
            explicit = [bool]$label
            worldId = [uint32]$Point.worldId; instanceId = [uint32]$Point.instanceId; zoneId = [uint32]$Point.zoneId
            x = [double]$Point.x; y = [double]$Point.y; z = [double]$Point.z
            sampleSequences = @([long]$Point.sequence)
        }
        $nodes.Add($node)
        if ($key) { $namedNodes[$key] = $node }
        return $node.id
    }

    foreach ($chunkObject in $chunks) {
        $points = @($chunkObject)
        $start = 0; $from = Resolve-SurveyNode $points[0]
        for ($index=1; $index -lt $points.Count; $index++) {
            if ($index -ne $points.Count-1 -and -not $marks.ContainsKey([string]$points[$index].sequence)) { continue }
            $to = Resolve-SurveyNode $points[$index]
            $length = 0.0
            for ($j=$start+1; $j -le $index; $j++) { $length += Get-RouteDistance $points[$j-1] $points[$j] }
            if ($length -ge 0.05) {
                $geometry = @($points[$start..$index] | ForEach-Object {
                    [ordered]@{ x=[double]$_.x; y=[double]$_.y; z=[double]$_.z; zoneId=[uint32]$_.zoneId
                        sequence=[long]$_.sequence; capturedUtc=[string]$_.capturedUtc }
                })
                $edges.Add([ordered]@{
                    id = 'e{0:d6}' -f ($edges.Count+1); from=$from; to=$to
                    worldId=[uint32]$points[$start].worldId; instanceId=[uint32]$points[$start].instanceId
                    direction='from-to'; pathType=[string]$Recording.Header.metadata.pathType
                    lengthMeters=[Math]::Round($length,3); points=$geometry
                    evidence='observed-traversal'; reverseVerified=$false
                })
            }
            $start=$index; $from=$to
        }
    }
    if ($edges.Count -eq 0) { throw 'The survey contains no traversed connection. Walk between junctions before exporting.' }
    return [ordered]@{
        schema='playerbots-route-network-v1'; schemaVersion=1
        networkId=[string]$Recording.Header.recordingId; name=[string]$Recording.Header.metadata.pathName
        generatedUtc=[string]$samples[-1].capturedUtc
        coordinateSystem='aaemu-server-world-xyz-metres'; gameVersion=[string]$Recording.Header.metadata.gameVersion
        versionDeclaration='contributor-supplied-not-auto-detected'
        junctionPolicy=[ordered]@{ method='explicit-name-and-same-context'; maximumHorizontalMeters=1.5; maximumHeightMeters=0.75; inferredCrossings=$false }
        nodes=$nodes.ToArray(); edges=$edges.ToArray(); breaks=$breaks.ToArray()
        provenance=[ordered]@{ rawRecordingSha256=[string]$Recording.RawSha256; recorderVersion=$script:RouteToolVersion; recordingId=[string]$Recording.Header.recordingId }
    }
}

function Get-PlayerRouteSupplementDocuments {
    param([Parameter(Mandatory)]$Recording, [Parameter(Mandatory)]$Route)
    $documents = [ordered]@{}
    $isSurvey = @($Recording.Events | Where-Object eventType -eq 'survey-started').Count -gt 0
    if ($isSurvey) {
        $network = ConvertTo-PlayerRouteNetwork $Recording
        $documents['network.json'] = $network
        $segments = @($network.edges)
    } else {
        $segments = @($Route.segments | ForEach-Object {
            [ordered]@{ worldId=$_.worldId; instanceId=$_.instanceId; direction=$Route.metadata.directionality; points=$_.points }
        })
    }
    # The extractor applies a centerline preference, not these edges as topology.
    # Emit one context per file; no line ever bridges two disconnected segments.
    $contexts = @($segments | Group-Object { '{0}|{1}' -f $_.worldId,$_.instanceId } | Sort-Object Name)
    foreach ($context in $contexts) {
        $first = $context.Group[0]
        $name = 'navigation-prior-w{0}-i{1}.json' -f $first.worldId,$first.instanceId
        $documents[$name] = [ordered]@{
            schemaVersion='playerbots-navigation-prior-v1'; routeId=[string]$Recording.Header.recordingId
            coordinateSystem='aaemu-server-world-xyz-metres'; worldId=[uint32]$first.worldId; instanceId=[uint32]$first.instanceId
            gameVersion=[string]$Recording.Header.metadata.gameVersion
            source=[ordered]@{ kind='human-recorded-centerline'; rawRecordingSha256=[string]$Recording.RawSha256; recordingId=[string]$Recording.Header.recordingId }
            usage='Extractor road-prior or validation trace only; does not create graph links or enforce direction.'
            edges=@($context.Group | ForEach-Object {
                [ordered]@{ worldId=[uint32]$_.worldId; instanceId=[uint32]$_.instanceId; direction=[string]$_.direction
                    points=@($_.points | ForEach-Object { [ordered]@{x=[double]$_.x;y=[double]$_.y;z=[double]$_.z} }) }
            })
        }
    }
    return $documents
}
