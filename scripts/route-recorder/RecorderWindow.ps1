# Native WinForms layout. Every control belongs to its visible container.
[Windows.Forms.Application]::EnableVisualStyles()
$script:colors = [pscustomobject]@{
    Canvas = [Drawing.ColorTranslator]::FromHtml('#252824')
    Card = [Drawing.ColorTranslator]::FromHtml('#30352f')
    Input = [Drawing.ColorTranslator]::FromHtml('#1b211d')
    Text = [Drawing.ColorTranslator]::FromHtml('#eee6d2')
    Muted = [Drawing.ColorTranslator]::FromHtml('#c0bba9')
    Gold = [Drawing.ColorTranslator]::FromHtml('#d9bb79')
    Success = [Drawing.ColorTranslator]::FromHtml('#486644')
    Warning = [Drawing.ColorTranslator]::FromHtml('#806632')
    Slate = [Drawing.ColorTranslator]::FromHtml('#4d554a')
}

function New-FieldLabel([string]$Text) {
    $c = [Windows.Forms.Label]::new()
    $c.Text = $Text; $c.AutoSize = $true; $c.Anchor = 'Left'
    $c.Margin = [Windows.Forms.Padding]::new(4, 4, 12, 4)
    return $c
}
function New-FieldText([string]$Text = '') {
    $c = [Windows.Forms.TextBox]::new()
    $c.Text = $Text; $c.Dock = 'Fill'; $c.BorderStyle = 'FixedSingle'
    $c.BackColor = $script:colors.Input; $c.ForeColor = $script:colors.Text
    $c.Margin = [Windows.Forms.Padding]::new(4, 6, 4, 6)
    return $c
}
function New-FieldButton([string]$Text) {
    $c = [Windows.Forms.Button]::new()
    $c.Text = $Text; $c.AutoSize = $true; $c.MinimumSize = [Drawing.Size]::new(118, 34)
    $c.Padding = [Windows.Forms.Padding]::new(8, 3, 8, 3)
    $c.BackColor = $script:colors.Slate; $c.ForeColor = $script:colors.Text
    $c.FlatStyle = 'Flat'; $c.FlatAppearance.BorderColor = $script:colors.Muted
    $c.UseVisualStyleBackColor = $false
    return $c
}
function New-FieldCombo([string[]]$Items) {
    $c = [Windows.Forms.ComboBox]::new()
    $c.DropDownStyle = 'DropDownList'; $c.Dock = 'Fill'; $c.FlatStyle = 'Flat'
    $c.BackColor = $script:colors.Input; $c.ForeColor = $script:colors.Text
    if ($Items.Count -gt 0) { $c.Items.AddRange($Items); $c.SelectedIndex = 0 }
    $c.Margin = [Windows.Forms.Padding]::new(4, 6, 4, 6)
    return $c
}
function New-FieldTable {
    $c = [Windows.Forms.TableLayoutPanel]::new()
    $c.Dock = 'Top'; $c.AutoSize = $true; $c.ColumnCount = 2
    $c.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 132)) | Out-Null
    $c.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100)) | Out-Null
    return $c
}
function Add-FieldRow($Table, [string]$Label, $Control) {
    $row = $Table.RowCount; $Table.RowCount++
    $Table.RowStyles.Add([Windows.Forms.RowStyle]::new('AutoSize')) | Out-Null
    $Table.Controls.Add((New-FieldLabel $Label), 0, $row)
    $Table.Controls.Add($Control, 1, $row)
}
function Add-FieldGroup($Parent, [string]$Title) {
    $group = [Windows.Forms.GroupBox]::new()
    $group.Text = $Title; $group.ForeColor = $script:colors.Gold
    $group.Dock = 'Top'; $group.AutoSize = $true
    $group.Padding = [Windows.Forms.Padding]::new(12, 10, 12, 8)
    $group.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 10)
    $table = New-FieldTable; $table.ForeColor = $script:colors.Text
    $group.Controls.Add($table); $Parent.Controls.Add($group)
    return $table
}

$script:form = [Windows.Forms.Form]::new()
$script:form.Text = 'Player Route Recorder - Field Journal'
$script:form.Font = [Drawing.Font]::new('Segoe UI', 10)
$script:form.AutoScaleMode = 'Font'
$script:form.AutoScaleDimensions = [Drawing.SizeF]::new(7, 17)
$script:form.StartPosition = 'CenterScreen'
$script:form.ClientSize = [Drawing.Size]::new(920, 730)
$script:form.MinimumSize = [Drawing.Size]::new(740, 560)
$script:form.BackColor = $script:colors.Canvas; $script:form.ForeColor = $script:colors.Text
if ($LauncherPath -and [IO.File]::Exists($LauncherPath)) {
    $script:form.Icon = [Drawing.Icon]::ExtractAssociatedIcon($LauncherPath)
}
$root = [Windows.Forms.TableLayoutPanel]::new()
$root.Dock = 'Fill'; $root.ColumnCount = 1; $root.RowCount = 4
$root.Padding = [Windows.Forms.Padding]::new(18, 8, 18, 10)
$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 80)) | Out-Null
$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 100)) | Out-Null
$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 50)) | Out-Null
$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 146)) | Out-Null
$script:form.Controls.Add($root)

$header = [Windows.Forms.TableLayoutPanel]::new()
$header.Dock = 'Fill'; $header.ColumnCount = 2; $header.RowCount = 2
$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100)) | Out-Null
$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 168)) | Out-Null
$title = New-FieldLabel 'Field Journal'; $title.Font = [Drawing.Font]::new('Georgia', 24)
$title.ForeColor = $script:colors.Gold; $title.Margin = [Windows.Forms.Padding]::Empty
$header.Controls.Add($title, 0, 0)
$subtitle = New-FieldLabel 'STANDALONE RECORDER  /  AAEMU 1.2'
$subtitle.Font = [Drawing.Font]::new('Segoe UI', 9); $subtitle.Margin = [Windows.Forms.Padding]::Empty
$header.Controls.Add($subtitle, 0, 1)
$script:modeLabel = New-FieldLabel 'READY'; $script:modeLabel.Dock = 'Fill'
$script:modeLabel.TextAlign = 'MiddleCenter'; $header.Controls.Add($script:modeLabel, 1, 0)
$helpLink = [Windows.Forms.LinkLabel]::new()
$helpLink.Text = 'Start here / setup help'; $helpLink.Dock = 'Fill'; $helpLink.TextAlign = 'MiddleCenter'
$helpLink.LinkColor = $script:colors.Gold; $helpLink.ActiveLinkColor = $script:colors.Text
$header.Controls.Add($helpLink, 1, 1); $root.Controls.Add($header, 0, 0)

$script:tabs = [Windows.Forms.TabControl]::new(); $script:tabs.Dock = 'Fill'
$root.Controls.Add($script:tabs, 0, 1)
function New-JournalPage([string]$Title) {
    $page = [Windows.Forms.TabPage]::new($Title)
    $page.BackColor = $script:colors.Canvas; $page.ForeColor = $script:colors.Text
    $page.AutoScroll = $true; $page.Padding = [Windows.Forms.Padding]::new(12)
    $stack = [Windows.Forms.TableLayoutPanel]::new()
    $stack.Dock = 'Top'; $stack.AutoSize = $true; $stack.ColumnCount = 1
    $stack.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100)) | Out-Null
    $page.Controls.Add($stack); $script:tabs.TabPages.Add($page)
    return $stack
}
$recordPage = New-JournalPage '  Record a route  '
$settingsPage = New-JournalPage '  Route settings  '
$setupPage = New-JournalPage '  Server setup  '
$photosPage = New-JournalPage '  Photo settings  '
$photoFields = Add-FieldGroup $photosPage 'Advanced photo settings - defaults are ready to use'
$script:photosEnabled = [Windows.Forms.CheckBox]::new()
$script:photosEnabled.Text = 'Take game photos while recording'; $script:photosEnabled.AutoSize = $true
$script:photoSourceCombo=New-FieldCombo @('Game screenshot key','Visible window capture')
Add-FieldRow $photoFields 'Photo source' $script:photoSourceCombo
$script:gameWindowCombo = New-FieldCombo @()
$script:gameWindowCombo.AccessibleName = 'ArcheAge capture window'
Add-FieldRow $photoFields 'Game client window' $script:gameWindowCombo
$script:refreshWindowsButton = New-FieldButton 'Refresh game windows'
Add-FieldRow $photoFields 'Find the game' $script:refreshWindowsButton
$script:screenshotKeyCombo=New-FieldCombo @('F9','F1','F2','F3','F4','F5','F6','F7','F8','F10','F11','F12')
Add-FieldRow $photoFields 'Screenshot key' $script:screenshotKeyCombo
$script:screenshotFolderText=New-FieldText (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArcheAge/ScreenShots')
$script:screenshotFolderText.AccessibleName='Game screenshot folder'
$script:screenshotFolderButton=New-FieldButton 'Browse folder...'
$screenshotRow=[Windows.Forms.TableLayoutPanel]::new();$screenshotRow.Dock='Fill';$screenshotRow.AutoSize=$true;$screenshotRow.ColumnCount=2
$screenshotRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))|Out-Null
$screenshotRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('AutoSize'))|Out-Null
$screenshotRow.Controls.Add($script:screenshotFolderText,0,0);$screenshotRow.Controls.Add($script:screenshotFolderButton,1,0)
Add-FieldRow $photoFields 'Screenshot folder' $screenshotRow
$script:photoInterval = [Windows.Forms.NumericUpDown]::new()
$script:photoInterval.Minimum = 1; $script:photoInterval.Maximum = 60; $script:photoInterval.Value = 5
Add-FieldRow $photoFields 'Photo seconds' $script:photoInterval
$script:photoWidth = [Windows.Forms.NumericUpDown]::new()
$script:photoWidth.Minimum = 640; $script:photoWidth.Maximum = 2560; $script:photoWidth.Increment = 160; $script:photoWidth.Value = 1600
Add-FieldRow $photoFields 'Maximum width (px)' $script:photoWidth
$script:photoBudget = [Windows.Forms.NumericUpDown]::new()
$script:photoBudget.Minimum = 16; $script:photoBudget.Maximum = 2048; $script:photoBudget.Value = 512
Add-FieldRow $photoFields 'Photo limit (MB)' $script:photoBudget
$photoHelp = New-FieldLabel 'First press F9 in game and confirm its screenshot folder. The recorder requests that key only with the game in front, then collects the new file. Visible window capture remains available as a fallback.'
$photoHelp.MaximumSize = [Drawing.Size]::new(610,0); $photoHelp.Dock = 'Fill'
Add-FieldRow $photoFields 'Capture area' $photoHelp
$photoPrivacy = New-FieldLabel 'Game originals stay untouched. Images may include names/chat; review before sharing. The limit stops new requests after collected copies or observed originals reach the budget (one native image may exceed it).'
$photoPrivacy.MaximumSize = [Drawing.Size]::new(610,0); $photoPrivacy.Dock = 'Fill'
Add-FieldRow $photoFields 'Before sharing' $photoPrivacy
$script:photoStatusLabel = New-FieldLabel 'At a stop, turn the camera yourself and press Ctrl+Alt+P for extra views. These are perspective photos, not a stitched 360 panorama.'
$script:photoStatusLabel.MaximumSize = [Drawing.Size]::new(610,0); $script:photoStatusLabel.Dock = 'Fill'
Add-FieldRow $photoFields 'Photo status' $script:photoStatusLabel
$setup = Add-FieldGroup $setupPage 'Install the small recorder extension once'
$setupIntro = New-FieldLabel 'Baseline: AAEmu 1.2 r208022. Other builds may work when the position command responds. No PlayerBots installation is needed.'
$setupIntro.Dock = 'Fill'; $setupIntro.MaximumSize = [Drawing.Size]::new(630, 0)
Add-FieldRow $setup 'Supported server' $setupIntro
$script:serverFolderText = New-FieldText
$script:serverFolderText.AccessibleName = 'Game server folder'
$script:chooseServerButton = New-FieldButton 'Choose Game EXE...'
$serverRow = [Windows.Forms.TableLayoutPanel]::new()
$serverRow.Dock = 'Fill'; $serverRow.AutoSize = $true; $serverRow.ColumnCount = 2
$serverRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100)) | Out-Null
$serverRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('AutoSize')) | Out-Null
$serverRow.Controls.Add($script:serverFolderText, 0, 0); $serverRow.Controls.Add($script:chooseServerButton, 1, 0)
Add-FieldRow $setup 'Game folder' $serverRow
$script:installBridgeButton = New-FieldButton 'Install extension'
Add-FieldRow $setup 'One file' $script:installBridgeButton
$script:setupStatusLabel = New-FieldLabel 'Close the Game server normally. Select AAEmu.Game.exe in AAEmu.Game/bin/Debug/net10.0 (or Release), then Install extension. AAEmu.Launcher.exe opens the client and is not the server.'
$script:setupStatusLabel.Dock = 'Fill'; $script:setupStatusLabel.MaximumSize = [Drawing.Size]::new(630, 0)
Add-FieldRow $setup 'Next step' $script:setupStatusLabel
$scopeHint = New-FieldLabel 'Adds Scripts/Commands/PlayerRoutePositionCommand.cs only. Existing scripts, settings and databases are preserved.'
$scopeHint.Dock = 'Fill'; $scopeHint.MaximumSize = [Drawing.Size]::new(630, 0)
Add-FieldRow $setup 'What it changes' $scopeHint
$connection = Add-FieldGroup $recordPage '1. Connect your character'
$connectionRow = [Windows.Forms.TableLayoutPanel]::new()
$connectionRow.Dock = 'Fill'; $connectionRow.AutoSize = $true; $connectionRow.ColumnCount = 2
$connectionRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100)) | Out-Null
$connectionRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('AutoSize')) | Out-Null
$script:characterText = New-FieldText
$script:characterText.AccessibleName = 'Character name'
$script:checkButton = New-FieldButton 'Check connection'
$connectionRow.Controls.Add($script:characterText, 0, 0); $connectionRow.Controls.Add($script:checkButton, 1, 0)
Add-FieldRow $connection 'Character name *' $connectionRow
$script:connectionLabel = New-FieldLabel 'First use: Server setup. Then start AAEmu and log into your GM character.'
$script:connectionLabel.Dock = 'Fill'; $script:connectionLabel.MaximumSize = [Drawing.Size]::new(630, 0)
Add-FieldRow $connection 'Local server' $script:connectionLabel

$route = Add-FieldGroup $recordPage '2. Name this walk'
$script:surveyModeCombo = New-FieldCombo @('Landmark-to-landmark route', 'City / area network')
Add-FieldRow $route 'Recording mode' $script:surveyModeCombo
$script:pathNameText = New-FieldText; $script:pathNameText.AccessibleName = 'Path name (optional)'
$script:pathNameText.MaxLength = 120
Add-FieldRow $route 'Walk name' $script:pathNameText
$script:pathNameCaption = $route.GetControlFromPosition(0, $route.RowCount-1)
$endpoints = [Windows.Forms.TableLayoutPanel]::new()
$endpoints.Dock = 'Fill'; $endpoints.AutoSize = $true; $endpoints.ColumnCount = 3
$endpoints.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 50)) | Out-Null
$endpoints.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('AutoSize')) | Out-Null
$endpoints.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 50)) | Out-Null
$script:fromText = New-FieldText; $script:fromText.AccessibleName = 'From landmark'
$script:toText = New-FieldText; $script:toText.AccessibleName = 'To landmark'
$script:fromText.MaxLength = 120; $script:toText.MaxLength = 120
$endpoints.Controls.Add($script:fromText, 0, 0); $endpoints.Controls.Add((New-FieldLabel 'to'), 1, 0)
$endpoints.Controls.Add($script:toText, 2, 0)
Add-FieldRow $route 'From / to *' $endpoints
$script:routeEndpoints = $endpoints
$script:routeEndpointsCaption = $route.GetControlFromPosition(0, $route.RowCount-1)
$hint = New-FieldLabel 'Example: Village gate to East bridge. Leave Walk name blank to use these landmarks.'
$hint.Font = [Drawing.Font]::new('Segoe UI', 9); $hint.Dock = 'Fill'
$hint.MaximumSize = [Drawing.Size]::new(610,0)
Add-FieldRow $route 'Example' $hint
$script:routeHint = $hint
$photoSwitch=[Windows.Forms.FlowLayoutPanel]::new();$photoSwitch.Dock='Fill';$photoSwitch.AutoSize=$true
$script:photosEnabled.Margin=[Windows.Forms.Padding]::new(4,10,12,4)
$script:photoSettingsButton=New-FieldButton 'Photo settings'
$script:photoSettingsButton.Add_Click({$script:tabs.SelectedIndex=3})
$photoSwitch.Controls.AddRange(@($script:photosEnabled,$script:photoSettingsButton))
Add-FieldRow $route 'Street View' $photoSwitch

$surveyFields = Add-FieldGroup $recordPage 'City junctions'
$script:surveyGroup = $surveyFields.Parent
$script:nodeNameText = New-FieldCombo @()
$script:nodeNameText.DropDownStyle = 'DropDown'; $script:nodeNameText.MaxLength = 40
$script:nodeNameText.AccessibleName = 'Junction name'
$script:markNodeButton = New-FieldButton 'Mark junction'
$nodeRow = [Windows.Forms.FlowLayoutPanel]::new(); $nodeRow.AutoSize=$true; $nodeRow.Dock='Fill'
$script:nodeNameText.Width=260
$nodeRow.Controls.AddRange(@($script:nodeNameText,$script:markNodeButton))
Add-FieldRow $surveyFields 'Name / reuse' $nodeRow
$script:nodeStatusLabel = New-FieldLabel 'Name the area above. Mark each junction and reuse its name when you return to the same spot. Only walked directions are recorded.'
$script:nodeStatusLabel.MaximumSize=[Drawing.Size]::new(610,0);$script:nodeStatusLabel.Dock='Fill'
Add-FieldRow $surveyFields 'How to survey' $script:nodeStatusLabel
function Update-RecorderSurveyControls {
    $survey = $script:surveyModeCombo.SelectedIndex -eq 1
    $idle = $script:state.Mode -eq 'Idle'
    $script:surveyGroup.Visible = $survey
    $script:routeEndpoints.Visible = -not $survey
    $script:routeEndpointsCaption.Visible = -not $survey
    $script:pathNameCaption.Text = if ($survey) { 'Area name *' } else { 'Walk name' }
    $script:pathNameText.AccessibleName = if ($survey) { 'Area or city name' } else { 'Path name (optional)' }
    $script:routeHint.Text = if ($survey) { 'Example: Crescent Throne. Mark named junctions as you explore each branch.' } else { 'Example: Village gate to East bridge. Leave Walk name blank to use these landmarks.' }
    $script:fromText.Enabled = $idle -and -not $survey
    $script:toText.Enabled = $idle -and -not $survey
    $script:directionCombo.Enabled = $idle -and -not $survey
    if ($survey) { $script:directionCombo.SelectedItem = 'from-to' }
    $script:markNodeButton.Enabled = $survey -and $script:state.Mode -eq 'Recording'
}
$script:surveyModeCombo.Add_SelectedIndexChanged({ Update-RecorderSurveyControls })
$script:markNodeButton.Add_Click({
    if ($script:state.Mode -ne 'Recording') { return }
    try {
        $label = $script:nodeNameText.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($label)) { throw 'Enter a junction name, for example Market square.' }
        $position = Invoke-RecorderSample -PassThru
        if ($null -eq $position) { throw 'No fresh position. Check the connection and try marking again.' }
        Assert-PlayerRouteJunction $label $position $script:state.SurveyNodes
        $detail = [ordered]@{label=$label;sequence=[long]$position.sequence} | ConvertTo-Json -Compress
        if ($detail.Length -gt 240) { throw 'Shorten this junction name.' }
        Add-RouteEvent 'network-node' $detail ([DateTimeOffset]::Parse($position.capturedUtc))
        $script:state.SurveyNodes += [pscustomobject]@{label=$label;worldId=$position.worldId;instanceId=$position.instanceId;x=$position.x;y=$position.y;z=$position.z}
        if (-not $script:nodeNameText.Items.Contains($label)) { $null=$script:nodeNameText.Items.Add($label) }
        $script:nodeStatusLabel.Text = 'Junction marked: ' + $label
        Add-RecorderStatus $script:nodeStatusLabel.Text
    } catch { $script:nodeStatusLabel.Text = $_.Exception.Message; Add-RecorderStatus ('Junction not marked: ' + $_.Exception.Message) }
})

$observations = Add-FieldGroup $recordPage '3. Note what you find (optional)'
$script:markerText = New-FieldText; $script:markerText.MaxLength = 80
$script:markerText.AccessibleName = 'Location note'
$script:markerButton = New-FieldButton 'Mark location'
$markerRow = [Windows.Forms.TableLayoutPanel]::new()
$markerRow.Dock = 'Fill'; $markerRow.AutoSize = $true; $markerRow.ColumnCount = 2
$markerRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100)) | Out-Null
$markerRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('AutoSize')) | Out-Null
$markerRow.Controls.Add($script:markerText, 0, 0); $markerRow.Controls.Add($script:markerButton, 1, 0)
Add-FieldRow $observations 'Bridge, gate, snag' $markerRow

$quickMarks = Add-FieldGroup $recordPage '4. Quick mark options'
$script:quickMarkText = New-FieldText
$script:quickMarkText.MaxLength = 40; $script:quickMarkText.AccessibleName = 'Add quick mark'
$script:addQuickMarkButton = New-FieldButton 'Add quick mark'
$quickMarkEditor = [Windows.Forms.TableLayoutPanel]::new()
$quickMarkEditor.Dock = 'Fill'; $quickMarkEditor.AutoSize = $true; $quickMarkEditor.ColumnCount = 2
$quickMarkEditor.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100)) | Out-Null
$quickMarkEditor.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('AutoSize')) | Out-Null
$quickMarkEditor.Controls.Add($script:quickMarkText, 0, 0); $quickMarkEditor.Controls.Add($script:addQuickMarkButton, 1, 0)
Add-FieldRow $quickMarks 'New button' $quickMarkEditor
$script:quickMarkPanel = [Windows.Forms.FlowLayoutPanel]::new()
$script:quickMarkPanel.Dock = 'Fill'; $script:quickMarkPanel.AutoSize = $true
$script:quickMarkPanel.WrapContents = $true
Add-FieldRow $quickMarks 'Click to mark' $script:quickMarkPanel
$script:quickMarkStatus = New-FieldLabel 'Click a label while recording to mark this location. Use x to remove a button. Your buttons are saved automatically.'
$script:quickMarkStatus.Dock = 'Fill'; $script:quickMarkStatus.MaximumSize = [Drawing.Size]::new(610, 0)
Add-FieldRow $quickMarks 'Saved buttons' $script:quickMarkStatus
$script:quickMarkButtons = @()
$script:quickMarkLabels = @()
$script:quickMarkTips = [Windows.Forms.ToolTip]::new()

$settings = Add-FieldGroup $settingsPage 'Capture settings'
$script:apiText = New-FieldText $ApiBase
$script:apiText.MaxLength = 200
Add-FieldRow $setup 'Local API address' $script:apiText
$script:gameVersionText = New-FieldText 'Unknown (not declared)'
$script:gameVersionText.MaxLength = 80
$script:gameVersionText.AccessibleName = 'Client version or build (declared)'
Add-FieldRow $connection 'Client build' $script:gameVersionText
$script:compatibilityLabel = New-FieldLabel ''
$script:compatibilityLabel.Dock = 'Fill'; $script:compatibilityLabel.MaximumSize = [Drawing.Size]::new(630,0)
Add-FieldRow $connection 'Compatibility' $script:compatibilityLabel
function Update-RecorderCompatibility {
    if ($script:gameVersionText.Text.Trim() -eq 'ArcheAge 1.2 r208022') {
        $script:compatibilityLabel.Text = 'r208022 baseline selected. This is your declared build; Check connection verifies the position command.'
    } else {
        $script:compatibilityLabel.Text = 'Experimental or unknown build. Enter your client version, for example ArcheAge 1.2 r208088. You can record after Check connection succeeds. If problems persist, use a matching r208022 setup.'
    }
}
$script:gameVersionText.Add_TextChanged({ Update-RecorderCompatibility })
Update-RecorderCompatibility
$script:moduleVersionText = New-FieldText $moduleVersionDefault; $script:moduleVersionText.ReadOnly = $true
Add-FieldRow $settings 'Package version' $script:moduleVersionText
$script:pathTypeCombo = New-FieldCombo @('main-road', 'side-path', 'shortcut', 'cave', 'dungeon', 'water', 'other')
Add-FieldRow $settings 'Path type' $script:pathTypeCombo
# A walk in one direction is not evidence that the reverse direction works.
$script:directionCombo = New-FieldCombo @('from-to', 'bidirectional', 'to-from')
Add-FieldRow $settings 'Observed direction' $script:directionCombo
$script:interval = [Windows.Forms.NumericUpDown]::new()
$script:interval.Minimum = 1; $script:interval.Maximum = 60; $script:interval.Value = 2
Add-FieldRow $settings 'Sample seconds' $script:interval
$script:maxDuration = [Windows.Forms.NumericUpDown]::new()
$script:maxDuration.Minimum = 1; $script:maxDuration.Maximum = 1440; $script:maxDuration.Value = 120
Add-FieldRow $settings 'Auto-stop minutes' $script:maxDuration
$script:notesText = New-FieldText; $script:notesText.Multiline = $true
$script:notesText.Height = 64; $script:notesText.MaxLength = 2000
Add-FieldRow $settings 'Session notes' $script:notesText
$outputRow = [Windows.Forms.TableLayoutPanel]::new()
$outputRow.Dock = 'Fill'; $outputRow.AutoSize = $true; $outputRow.ColumnCount = 2
$outputRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100)) | Out-Null
$outputRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('AutoSize')) | Out-Null
$script:outputText = New-FieldText $OutputDirectory
$script:browseButton = New-FieldButton 'Browse...'
$outputRow.Controls.Add($script:outputText, 0, 0); $outputRow.Controls.Add($script:browseButton, 1, 0)
Add-FieldRow $settings 'Save folder' $outputRow

$actions = [Windows.Forms.FlowLayoutPanel]::new(); $actions.Dock = 'Fill'; $actions.WrapContents = $false
$script:startButton = New-FieldButton 'Start recording'; $script:startButton.BackColor = $script:colors.Success
$script:pauseButton = New-FieldButton 'Pause'
$script:stopButton = New-FieldButton 'Stop && export'
$script:exportButton = New-FieldButton 'Show export'; $script:exportButton.Enabled = $false
$script:viewPhotosButton = New-FieldButton 'View photos'; $script:viewPhotosButton.Enabled = $false
$actions.Controls.AddRange(@($script:startButton, $script:pauseButton, $script:stopButton, $script:exportButton, $script:viewPhotosButton))
$root.Controls.Add($actions, 0, 2)
$live = [Windows.Forms.TableLayoutPanel]::new(); $live.Dock = 'Fill'; $live.ColumnCount = 1; $live.RowCount = 4
$live.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 24)) | Out-Null
$live.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 22)) | Out-Null
$live.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 24)) | Out-Null
$live.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 100)) | Out-Null
$script:sampleLabel = New-FieldLabel 'Samples: 0    |    Ctrl+Alt+R starts, pauses and resumes in game'
$script:positionLabel = New-FieldLabel 'Position: waiting for your first sample'
$script:exportLabel = New-FieldLabel 'Your route ZIP will appear here after Stop & export.'
foreach ($label in @($script:sampleLabel, $script:positionLabel, $script:exportLabel)) {
    $label.Dock = 'Fill'; $label.AutoSize = $false; $label.AutoEllipsis = $true; $label.Margin = [Windows.Forms.Padding]::Empty
    $live.Controls.Add($label)
}
$script:statusBox = New-FieldText; $script:statusBox.Multiline = $true; $script:statusBox.ReadOnly = $true
$script:statusBox.ScrollBars = 'Vertical'; $script:statusBox.Margin = [Windows.Forms.Padding]::Empty
$live.Controls.Add($script:statusBox); $root.Controls.Add($live, 0, 3)
$script:metadataControls = @($script:surveyModeCombo, $script:gameVersionText, $script:apiText, $script:characterText, $script:pathNameText, $script:fromText, $script:toText,
    $script:pathTypeCombo, $script:directionCombo, $script:interval, $script:maxDuration,
    $script:notesText, $script:outputText, $script:browseButton, $script:serverFolderText,
    $script:chooseServerButton, $script:installBridgeButton, $script:photosEnabled, $script:gameWindowCombo,
    $script:refreshWindowsButton, $script:photoInterval, $script:photoBudget, $script:photoWidth,
    $script:photoSourceCombo,$script:screenshotKeyCombo,$script:screenshotFolderText,$script:screenshotFolderButton)
$script:timer = [Windows.Forms.Timer]::new(); $script:timer.Interval = 2000
$script:photoTimer = [Windows.Forms.Timer]::new(); $script:photoTimer.Interval = 5000
$script:photoTimer.Add_Tick({ Invoke-RecorderPhoto })
$script:nativePollTimer=[Windows.Forms.Timer]::new();$script:nativePollTimer.Interval=250
$script:nativePollTimer.Add_Tick({Invoke-NativePhotoPoll})
function Update-PhotoSourceControls {
    $useNative=$script:state.Mode -eq 'Idle' -and $script:photoSourceCombo.SelectedIndex -eq 0
    foreach($control in @($script:screenshotKeyCombo,$script:screenshotFolderText,$script:screenshotFolderButton)){$control.Enabled=$useNative}
}
$script:photoSourceCombo.Add_SelectedIndexChanged({Update-PhotoSourceControls})
$script:screenshotFolderButton.Add_Click({
    $dialog=[Windows.Forms.FolderBrowserDialog]::new();$dialog.Description='Choose the folder where your manual game screenshot appeared.'
    if([IO.Directory]::Exists($script:screenshotFolderText.Text)){$dialog.SelectedPath=$script:screenshotFolderText.Text}
    try{if($dialog.ShowDialog($script:form) -eq 'OK'){$script:screenshotFolderText.Text=$dialog.SelectedPath}}finally{$dialog.Dispose()}
})
$script:refreshWindowsButton.Add_Click({
    Find-RecorderGameWindows
})
function Get-RecorderGameWindows { return [PlayerBots.RouteRecorder.GameWindowCapture]::List() }
function Find-RecorderGameWindows {
    try {
        Initialize-GamePhotoCapture
        $script:gameWindowCombo.Items.Clear()
        foreach ($window in (Get-RecorderGameWindows)) { $script:gameWindowCombo.Items.Add($window) | Out-Null }
        if ($script:gameWindowCombo.Items.Count -eq 1) { $script:gameWindowCombo.SelectedIndex = 0 }
        if($script:gameWindowCombo.Items.Count -eq 1){Set-PhotoStatus 'Game found. Photo settings are ready. Start recording, then return to the game.'}
        elseif($script:gameWindowCombo.Items.Count -eq 0){Set-PhotoStatus 'Enter the game first. The recorder will look for it again when you start recording.'}
        else{Set-PhotoStatus 'More than one game window is open. Choose yours in Photo settings.'}
    } catch { Set-PhotoStatus ('Cannot list game windows: ' + $_.Exception.Message) }
}
$script:photosEnabled.Add_CheckedChanged({if($script:photosEnabled.Checked -and !$script:gameWindowCombo.SelectedItem){Find-RecorderGameWindows}})
$script:viewPhotosButton.Add_Click({
    if ($script:state.LastStreetView -and [IO.File]::Exists($script:state.LastStreetView.Viewer)) { Start-Process $script:state.LastStreetView.Viewer | Out-Null }
})
$script:timer.Add_Tick({ Invoke-RecorderSample })
$script:checkButton.Add_Click({ $null = Test-RecorderConnection })
$script:chooseServerButton.Add_Click({
    $dialog = [Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = 'Choose the AAEmu 1.2 Game executable you normally run'
    $dialog.Filter = 'AAEmu Game server (AAEmu.Game.exe)|AAEmu.Game.exe'
    $dialog.CheckFileExists = $true
    try {
        if ($dialog.ShowDialog($script:form) -eq 'OK') {
            $script:serverFolderText.Text = [IO.Path]::GetDirectoryName($dialog.FileName)
        }
    } finally { $dialog.Dispose() }
})
function Install-SelectedRecorderBridge {
    try {
        if ([string]::IsNullOrWhiteSpace($script:serverFolderText.Text)) { throw 'Choose your AAEmu.Game.exe first.' }
        $result = Install-RecorderBridge -GameDirectory $script:serverFolderText.Text.Trim()
        $script:setupStatusLabel.Text = 'Extension installed and verified. Start Game normally, log in with your GM character, and use Check connection on Record a route.'
        Add-RecorderStatus ('Recorder extension ready: ' + $result.Destination)
    } catch {
        $script:setupStatusLabel.Text = $_.Exception.Message
        Add-RecorderStatus ('Setup needs attention: ' + $_.Exception.Message)
    }
}
$script:installBridgeButton.Add_Click({ Install-SelectedRecorderBridge })
$script:startButton.Add_Click({ Start-RouteRecording })
$script:pauseButton.Add_Click({ Pause-RouteRecording })
$script:stopButton.Add_Click({ Stop-RouteRecording })
$script:characterText.Add_TextChanged({ $script:connectionLabel.Text = 'Click Check connection to verify this character.' })
function Add-LocationNote {
    param([string]$Text, [switch]$QuickMark)
    if (!$QuickMark) { $Text = $script:markerText.Text }
    if ($script:state.Mode -ne 'Recording' -or [string]::IsNullOrWhiteSpace($Text)) { return }
    try {
        # Sample now; never attach a note to a stale position during a disconnect.
        $position = Get-ApiSample
        $detail = [ordered]@{ text = $Text.Trim(); worldId = $position.worldId
            instanceId = $position.instanceId; zoneId = $position.zoneId; x = $position.x; y = $position.y; z = $position.z }
        $encoded = $detail | ConvertTo-Json -Compress
        if ($encoded.Length -gt 240) { throw 'Shorten this location note; use the field-notes template for a longer description.' }
        Add-RouteEvent 'observation' $encoded ([DateTimeOffset]::Parse($position.capturedUtc))
        Add-RecorderStatus ('Location marked: ' + $Text.Trim())
        if ($QuickMark) { $script:quickMarkStatus.Text = 'Marked: ' + $Text.Trim() }
        else { $script:markerText.Clear() }
    } catch {
        if ($QuickMark) {
            $script:quickMarkStatus.Text = 'Not marked: ' + $Text.Trim() + '. ' + $_.Exception.Message + ' Click the button again to retry at your current location.'
            Add-RecorderStatus $script:quickMarkStatus.Text
        } else { Add-RecorderStatus ('Note not saved; retained in the field. ' + $_.Exception.Message) }
    }
}
$script:markerButton.Add_Click({ Add-LocationNote })

function Update-QuickMarkButtons {
    $script:quickMarkPanel.SuspendLayout()
    try {
        $oldControls = @($script:quickMarkPanel.Controls)
        $script:quickMarkPanel.Controls.Clear()
        $script:quickMarkTips.RemoveAll()
        foreach ($old in $oldControls) { $old.Dispose() }
        $script:quickMarkButtons = @()
        foreach ($label in $script:quickMarkLabels) {
            $pair = [Windows.Forms.FlowLayoutPanel]::new()
            $pair.AutoSize = $true; $pair.WrapContents = $false
            $pair.Margin = [Windows.Forms.Padding]::new(0, 0, 10, 6)
            $mark = New-FieldButton $label
            $mark.UseMnemonic = $false; $mark.Tag = $label; $mark.AccessibleName = 'Mark location: ' + $label
            $mark.MinimumSize = [Drawing.Size]::new(88, 34); $mark.MaximumSize = [Drawing.Size]::new(240, 0)
            $mark.AutoSize = $false; $mark.AutoEllipsis = $true
            $mark.Font = $script:form.Font
            $mark.Size = [Drawing.Size]::new([Math]::Min(240, [Math]::Max(88, [Windows.Forms.TextRenderer]::MeasureText($label, $mark.Font).Width + 52)), 34)
            $script:quickMarkTips.SetToolTip($mark, 'Mark this location: ' + $label)
            $mark.Enabled = $script:state.Mode -eq 'Recording'
            $mark.Add_Click({ param($sender, $eventArgs) Add-LocationNote -Text ([string]$sender.Tag) -QuickMark })
            $remove = New-FieldButton 'x'
            $remove.Tag = $label; $remove.AccessibleName = 'Remove quick mark: ' + $label
            $remove.MinimumSize = [Drawing.Size]::new(30, 34); $remove.Size = $remove.MinimumSize
            $remove.Padding = [Windows.Forms.Padding]::Empty; $remove.AutoSize = $false
            $script:quickMarkTips.SetToolTip($remove, 'Remove button: ' + $label)
            $remove.Add_Click({ param($sender, $eventArgs) Remove-QuickMarkButton ([string]$sender.Tag) })
            $pair.Controls.AddRange(@($mark, $remove)); $script:quickMarkPanel.Controls.Add($pair)
            $script:quickMarkButtons += $mark
        }
    } finally { $script:quickMarkPanel.ResumeLayout($true) }
}

function Add-QuickMarkButton {
    try {
        $script:quickMarkLabels = @(Set-QuickMarkOption -SettingsDirectory $SettingsDirectory -Label $script:quickMarkText.Text -Enabled $true)
        Update-QuickMarkButtons
        $script:quickMarkStatus.Text = 'Saved button: ' + $script:quickMarkText.Text.Trim()
        $script:quickMarkText.Clear()
    } catch { $script:quickMarkStatus.Text = $_.Exception.Message; Add-RecorderStatus ('Quick mark not added: ' + $_.Exception.Message) }
}
function Remove-QuickMarkButton([string]$Label) {
    try {
        $script:quickMarkLabels = @(Set-QuickMarkOption -SettingsDirectory $SettingsDirectory -Label $Label -Enabled $false)
        Update-QuickMarkButtons
        $script:quickMarkStatus.Text = 'Removed button: ' + $Label
    } catch { $script:quickMarkStatus.Text = $_.Exception.Message; Add-RecorderStatus ('Quick mark button not removed: ' + $_.Exception.Message) }
}
$script:addQuickMarkButton.Add_Click({ Add-QuickMarkButton })
$script:quickMarkText.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq [Windows.Forms.Keys]::Enter) {
        $eventArgs.SuppressKeyPress = $true
        Add-QuickMarkButton
    }
})
try {
    $script:quickMarkLabels = @(Get-QuickMarkOptions -SettingsDirectory $SettingsDirectory)
    Update-QuickMarkButtons
} catch {
    $script:quickMarkStatus.Text = $_.Exception.Message
    Add-RecorderStatus $_.Exception.Message
    $script:addQuickMarkButton.Enabled = $false
}
$script:exportButton.Add_Click({
    if ($script:state.LastExport -and [IO.File]::Exists($script:state.LastExport)) {
        Start-Process explorer.exe -ArgumentList ('/select,"' + $script:state.LastExport + '"') | Out-Null
    }
})
$script:browseButton.Add_Click({
    $dialog = [Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = 'Choose where to save route recordings and exports.'
    $dialog.SelectedPath = $script:outputText.Text
    try { if ($dialog.ShowDialog($script:form) -eq 'OK') { $script:outputText.Text = $dialog.SelectedPath } }
    finally { $dialog.Dispose() }
})
$helpLink.Add_LinkClicked({
    [Windows.Forms.MessageBox]::Show('Install the recorder bridge on your AAEmu server, then enter its address and your character name. Choose an output folder, name your walk, and press Record. Ctrl+Alt+R starts or stops recording; Ctrl+Alt+P captures a photo while recording. Stop saves the route and exports it to your chosen folder.', 'Route recorder help') | Out-Null
})
$script:hotKey = [PlayerBots.RouteRecorder.HotKeyWindow]::new()
$registered = $script:hotKey.Register(4107, 0x0001 -bor 0x0002 -bor 0x4000, [uint32][Windows.Forms.Keys]::R)
$script:hotKey.Add_HotKeyPressed({ Toggle-RouteRecording })
$script:photoHotKey = [PlayerBots.RouteRecorder.HotKeyWindow]::new()
$photoRegistered = $script:photoHotKey.Register(4108, 0x0001 -bor 0x0002 -bor 0x4000, [uint32][Windows.Forms.Keys]::P)
$script:photoHotKey.Add_HotKeyPressed({
    if($script:state.Mode -eq 'Recording' -and $script:state.Photos){$script:state.ManualPhotoDue=[DateTimeOffset]::UtcNow.AddMilliseconds(350)}
})
$script:form.Add_FormClosing({
    if ($script:state.Mode -ne 'Idle') { Stop-RouteRecording 'window-closed' }
    $script:timer.Dispose(); $script:photoTimer.Dispose(); $script:nativePollTimer.Dispose(); $script:photoHotKey.Dispose(); $script:hotKey.Dispose(); $script:http.Dispose(); $script:quickMarkTips.Dispose()
})
Set-RecorderMode 'Idle'
Add-RecorderStatus 'Ready. Enter your character and name a short walk. Required fields are marked *.'
if (-not $registered) { Add-RecorderStatus 'Ctrl+Alt+R is in use. The recording buttons still work.' }
if (-not $photoRegistered) { Add-RecorderStatus 'Ctrl+Alt+P is in use. Timed photos still work.' }
if ($UiScale -ne 1) { $script:form.Scale([Drawing.SizeF]::new($UiScale, $UiScale)) }
if (-not $ValidateOnly) {
    $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $script:form.Size = [Drawing.Size]::new([Math]::Min($script:form.Width, $area.Width), [Math]::Min($script:form.Height, $area.Height))
    [Windows.Forms.Application]::Run($script:form)
    return
}
try {
    $script:form.Show(); [Windows.Forms.Application]::DoEvents()
    if ($ValidationAction) { & $ValidationAction }
    if ($ScreenshotPath) {
        $absoluteScreenshot = [IO.Path]::GetFullPath($ScreenshotPath)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($absoluteScreenshot)) | Out-Null
        [Windows.Forms.Application]::DoEvents()
        $bitmap = [Drawing.Bitmap]::new($script:form.Width, $script:form.Height)
        try {
            $script:form.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height))
            $bitmap.Save($absoluteScreenshot, [Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose() }
    }
    [pscustomobject]@{ Result = 'PASS'; Check = 'Recorder window and validation actions'; Scale = $UiScale }
} finally {
    $script:timer.Dispose(); $script:photoTimer.Dispose(); $script:nativePollTimer.Dispose(); $script:photoHotKey.Dispose(); $script:hotKey.Dispose(); $script:http.Dispose(); $script:quickMarkTips.Dispose()
    $script:form.Dispose()
}
