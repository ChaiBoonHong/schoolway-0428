param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [string]$DatabaseId,

    [Parameter()]
    [string]$Confirmation
)

$ErrorActionPreference = "Stop"
$expectedConfirmation = "ERASE-$ProjectId-$DatabaseId"
Write-Host "This permanently deletes Firestore and Auth data." -ForegroundColor Red
Write-Host "Project: $ProjectId" -ForegroundColor Yellow
Write-Host "Database: $DatabaseId" -ForegroundColor Yellow
if ([string]::IsNullOrWhiteSpace($Confirmation)) {
    $Confirmation = Read-Host "Type $expectedConfirmation to continue"
}

if ($Confirmation -cne $expectedConfirmation) {
    Write-Host "Confirmation did not match. Nothing was deleted." -ForegroundColor Green
    exit 2
}

foreach ($command in @("gcloud", "node", "npm")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        Write-Host "$command is required to run the erasure utility." -ForegroundColor Red
        exit 1
    }
}

$functionsPath = Join-Path -Path $PSScriptRoot -ChildPath "functions"
$scriptPath = Join-Path -Path $functionsPath -ChildPath "erase_db.js"
$packagePath = Join-Path -Path $functionsPath -ChildPath "package.json"
$lockPath = Join-Path -Path $functionsPath -ChildPath "package-lock.json"

foreach ($requiredFile in @($scriptPath, $packagePath, $lockPath)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        Write-Host "Required file is missing: $requiredFile" -ForegroundColor Red
        exit 1
    }
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempPath = Join-Path -Path $tempRoot -ChildPath "schoolway-erase-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $tempPath | Out-Null

try {
    Write-Host "Configuring Application Default Credentials quota project..." -ForegroundColor Cyan
    & gcloud auth application-default set-quota-project $ProjectId
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to set the ADC quota project to $ProjectId."
    }

    Copy-Item -LiteralPath $scriptPath -Destination $tempPath
    Copy-Item -LiteralPath $packagePath -Destination $tempPath
    Copy-Item -LiteralPath $lockPath -Destination $tempPath

    Write-Host "Installing locked production dependencies in an isolated directory..." -ForegroundColor Cyan
    & npm ci --omit=dev --ignore-scripts --prefix $tempPath
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to install the locked erasure dependencies."
    }

    $previousQuotaProject = $env:GOOGLE_CLOUD_QUOTA_PROJECT
    $env:GOOGLE_CLOUD_QUOTA_PROJECT = $ProjectId
    try {
        & node (Join-Path $tempPath "erase_db.js") `
            --project $ProjectId `
            --database $DatabaseId `
            --confirm $Confirmation
        if ($LASTEXITCODE -ne 0) {
            throw "The database erasure command failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        $env:GOOGLE_CLOUD_QUOTA_PROJECT = $previousQuotaProject
    }

    Write-Host "Firestore and Firebase Auth erasure completed successfully." -ForegroundColor Green
}
finally {
    $resolvedTempPath = [System.IO.Path]::GetFullPath($tempPath)
    if ($resolvedTempPath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTempPath).StartsWith("schoolway-erase-")) {
        Remove-Item -LiteralPath $resolvedTempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Warning "Temporary path failed safety validation and was not removed: $resolvedTempPath"
    }
}
