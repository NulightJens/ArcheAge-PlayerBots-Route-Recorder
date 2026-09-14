#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$GameDirectory, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RecorderBridge.psm1') -Force
if ($CheckOnly) { Get-RecorderBridgePlan -GameDirectory $GameDirectory }
else { Install-RecorderBridge -GameDirectory $GameDirectory }
