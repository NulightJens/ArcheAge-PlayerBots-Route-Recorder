#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RecordingPath, [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$PhotoDirectory)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PlayerRouteTools.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'StreetView.psm1') -Force
if (!$PhotoDirectory) { $PhotoDirectory = [IO.Path]::ChangeExtension([IO.Path]::GetFullPath($RecordingPath), 'photos') }
Export-StreetViewBundle -RecordingPath $RecordingPath -PhotoDirectory $PhotoDirectory -OutputDirectory $OutputDirectory
