#requires -Version 5.1
Set-StrictMode -Version Latest

function Test-QuickMarkLabel([string]$Label) {
    $label = $Label.Trim()
    if (!$label -or $label.Length -gt 40 -or $label -match '[\p{Cc}\p{Cf}]') {
        throw 'Enter a quick mark from 1 to 40 characters on one line.'
    }
    return $label
}

function Read-QuickMarkStore([string]$SettingsDirectory) {
    $latest = $null
    if ([IO.Directory]::Exists($SettingsDirectory)) {
        $latest = Get-ChildItem -LiteralPath $SettingsDirectory -File -Filter 'quick-marks-*.json' |
            Where-Object Name -Match '^quick-marks-[0-9]{12}\.json$' | Sort-Object Name -Descending | Select-Object -First 1
    }
    if (!$latest) { return [pscustomobject]@{ Revision = 0L; Labels = @('Quest', 'Fork', 'Merchant', 'Mail') } }
    try {
        if ($latest.Length -gt 64KB) { throw 'Settings file exceeds the expected size.' }
        $data = Get-Content -LiteralPath $latest.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($data.schemaVersion -ne 1 -or $data.labels -isnot [array] -or $data.labels.Count -gt 24) { throw 'Invalid quick mark settings.' }
        $labels = @($data.labels | ForEach-Object {
            if ($_ -isnot [string]) { throw 'Invalid quick mark label.' }
            Test-QuickMarkLabel $_
        })
        if (@($labels | Sort-Object -Unique).Count -ne $labels.Count) { throw 'Duplicate saved quick marks.' }
        return [pscustomobject]@{ Revision = [long]$latest.BaseName.Substring(12); Labels = $labels }
    } catch {
        throw ('Saved quick marks could not be read; files were preserved. Details: ' + $_.Exception.Message)
    }
}

function Get-QuickMarkOptions([Parameter(Mandatory)][string]$SettingsDirectory) {
    return (Read-QuickMarkStore $SettingsDirectory).Labels
}

function Set-QuickMarkOption {
    param([Parameter(Mandatory)][string]$SettingsDirectory, [Parameter(Mandatory)][AllowEmptyString()][string]$Label,
        [Parameter(Mandatory)][bool]$Enabled)
    $label = Test-QuickMarkLabel $Label
    $directory = [IO.Path]::GetFullPath($SettingsDirectory)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $lock = $null
    try {
        try { $lock = [IO.File]::Open((Join-Path $directory 'quick-marks.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch [IO.IOException] { throw 'Another recorder is saving quick marks. Try again in a moment.' }
        # Reload inside the lock so a second recorder cannot overwrite newer choices.
        $current = Read-QuickMarkStore $directory
        $labels = @($current.Labels)
        if ($Enabled) {
            if ($labels -contains $label) { throw 'That quick mark already exists.' }
            if ($labels.Count -ge 24) { throw 'You can keep 24 quick marks. Remove one before adding another.' }
            $labels += $label
        } else { $labels = @($labels | Where-Object { $_ -ine $label }) }
        if ($current.Revision -ge 999999999999L) { throw 'Quick mark settings reached their version limit.' }
        $path = Join-Path $directory ('quick-marks-{0:D12}.json' -f ($current.Revision + 1L))
        $json = [ordered]@{ schemaVersion = 1; labels = $labels } | ConvertTo-Json -Depth 3
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + [Environment]::NewLine)
        # Each edit creates a new snapshot; removed buttons remain in earlier versions.
        $stream = [IO.File]::Open($path, 'CreateNew', 'Write', 'None')
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        return $labels
    } finally { if ($lock) { $lock.Dispose() } }
}

Export-ModuleMember -Function Get-QuickMarkOptions, Set-QuickMarkOption
