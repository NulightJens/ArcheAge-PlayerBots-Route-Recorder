#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$SourcePath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $PSScriptRoot 'windows\PlayerRouteRecorderLauncher.cs'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot 'bin\PlayerRouteRecorder.exe'
}
$resolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
$absoluteOutput = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = [IO.Path]::GetDirectoryName($absoluteOutput)
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

$compiler = @(
    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
    'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($compiler)) {
    throw 'The Windows .NET Framework C# compiler was not found.'
}

Add-Type -AssemblyName System.Drawing
if (-not ('RouteRecorderBuild.NativeIcon' -as [type])) {
    Add-Type 'namespace RouteRecorderBuild { public static class NativeIcon { [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr icon); } }'
}
$iconPath = [IO.Path]::ChangeExtension($absoluteOutput, '.ico')
$bitmap = [Drawing.Bitmap]::new(64, 64)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([Drawing.Color]::Transparent)
    $background = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(28, 42, 58))
    $routePen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(48, 190, 166), 7)
    $routePen.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $routePen.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $waypoint = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(244, 166, 62))
    try {
        $graphics.FillEllipse($background, 2, 2, 60, 60)
        $graphics.DrawBezier($routePen, 14, 45, 22, 12, 42, 54, 51, 18)
        $graphics.FillEllipse($waypoint, 44, 11, 14, 14)
        $graphics.FillEllipse([Drawing.Brushes]::White, 49, 16, 4, 4)
    }
    finally {
        $waypoint.Dispose()
        $routePen.Dispose()
        $background.Dispose()
    }
    $iconHandle = $bitmap.GetHicon()
    $icon = [Drawing.Icon]::FromHandle($iconHandle)
    try {
        $stream = [IO.File]::Create($iconPath)
        try { $icon.Save($stream) } finally { $stream.Dispose() }
    }
    finally { $icon.Dispose(); [RouteRecorderBuild.NativeIcon]::DestroyIcon($iconHandle) | Out-Null }
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

$compilerArguments = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/platform:anycpu',
    "/out:$absoluteOutput",
    "/win32icon:$iconPath",
    '/reference:System.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll',
    $resolvedSource
)
& $compiler $compilerArguments
if ($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($absoluteOutput)) {
    throw 'PlayerRouteRecorder.exe did not compile successfully.'
}

$file = Get-Item -LiteralPath $absoluteOutput
[pscustomobject]@{
    Executable = $file.FullName
    Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    Bytes = $file.Length
    Compiler = $compiler
}
