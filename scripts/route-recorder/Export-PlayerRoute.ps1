#requires -Version 5.1

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

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PlayerRouteTools.psm1') -Force

Export-PlayerRouteBundle @PSBoundParameters
