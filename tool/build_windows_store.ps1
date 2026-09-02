$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$storeConfigPath = Join-Path $projectRoot 'tool\microsoft_store.local.psd1'
$stagingImages = Join-Path $projectRoot 'build\windows\x64\runner\Release\Images'
$sourceLogo = Join-Path $projectRoot 'assets\index.png'
$outputPackage = Join-Path $projectRoot 'build\windows\msix\Schulregister-Suedtirol-1.13.39.0-x64.msix'

if (-not (Test-Path -LiteralPath $storeConfigPath)) {
    throw "Microsoft Store configuration not found: $storeConfigPath. Copy tool\\microsoft_store.local.psd1.example and enter the Partner Center values."
}

$storeConfig = Import-PowerShellDataFile -LiteralPath $storeConfigPath
$requiredStoreConfigKeys = @('PublisherDisplayName', 'IdentityName', 'Publisher')
foreach ($key in $requiredStoreConfigKeys) {
    if ([string]::IsNullOrWhiteSpace([string]$storeConfig[$key])) {
        throw "Microsoft Store configuration is missing '$key': $storeConfigPath"
    }
}

function Invoke-DartMsix {
    param([Parameter(Mandatory = $true)][string]$Command)

    & dart run "msix:$Command" --store `
        --publisher-display-name $storeConfig.PublisherDisplayName `
        --identity-name $storeConfig.IdentityName `
        --publisher $storeConfig.Publisher
    if ($LASTEXITCODE -ne 0) {
        throw "msix:$Command failed with exit code $LASTEXITCODE."
    }
}

function Write-CompliantBadgeLogos {
    Add-Type -AssemblyName System.Drawing

    if (-not (Test-Path -LiteralPath $sourceLogo)) {
        throw "Source logo not found: $sourceLogo"
    }
    if (-not (Test-Path -LiteralPath $stagingImages)) {
        throw "MSIX staging image directory not found: $stagingImages"
    }

    $source = [System.Drawing.Image]::FromFile($sourceLogo)
    try {
        $badges = @(
            @{ Name = 'BadgeLogo.scale-100.png'; Size = 24 },
            @{ Name = 'BadgeLogo.scale-125.png'; Size = 30 },
            @{ Name = 'BadgeLogo.scale-150.png'; Size = 36 },
            @{ Name = 'BadgeLogo.scale-200.png'; Size = 48 },
            @{ Name = 'BadgeLogo.scale-400.png'; Size = 96 }
        )

        foreach ($badge in $badges) {
            $size = [int]$badge.Size
            $bitmap = [System.Drawing.Bitmap]::new(
                $size,
                $size,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
            )
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                try {
                    $graphics.Clear([System.Drawing.Color]::Transparent)
                    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $graphics.DrawImage($source, 0, 0, $size, $size)
                }
                finally {
                    $graphics.Dispose()
                }

                # Windows badge logos must be monochrome. Preserve the alpha
                # silhouette of the Android logo and make every visible pixel white.
                for ($y = 0; $y -lt $size; $y++) {
                    for ($x = 0; $x -lt $size; $x++) {
                        $alpha = $bitmap.GetPixel($x, $y).A
                        if ($alpha -gt 0) {
                            $bitmap.SetPixel(
                                $x,
                                $y,
                                [System.Drawing.Color]::FromArgb($alpha, 255, 255, 255)
                            )
                        }
                    }
                }

                $target = Join-Path $stagingImages $badge.Name
                $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $bitmap.Dispose()
            }
        }
    }
    finally {
        $source.Dispose()
    }
}

Push-Location $projectRoot
try {
    Invoke-DartMsix -Command 'build'
    Write-CompliantBadgeLogos
    Invoke-DartMsix -Command 'pack'

    if (-not (Test-Path -LiteralPath $outputPackage)) {
        throw "Expected MSIX package was not created: $outputPackage"
    }

    $package = Get-Item -LiteralPath $outputPackage
    $hash = Get-FileHash -LiteralPath $outputPackage -Algorithm SHA256
    Write-Output "Store package: $($package.FullName)"
    Write-Output "Size: $($package.Length) bytes"
    Write-Output "SHA256: $($hash.Hash)"
}
finally {
    Pop-Location
}
