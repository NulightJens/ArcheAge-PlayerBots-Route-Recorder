#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$InputPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateRange(0.1, 25.0)][double]$MergeRadiusMeters = 3.0
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PlayerRouteTools.psm1') -Force

Merge-PlayerRouteGraph @PSBoundParameters
