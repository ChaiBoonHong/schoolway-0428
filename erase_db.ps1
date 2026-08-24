param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [string]$DatabaseId
)

$expectedConfirmation = "ERASE-$ProjectId-$DatabaseId"
Write-Host "This permanently deletes Firestore and Auth data." -ForegroundColor Red
Write-Host "Project: $ProjectId" -ForegroundColor Yellow
Write-Host "Database: $DatabaseId" -ForegroundColor Yellow
$confirmation = Read-Host "Type $expectedConfirmation to continue"

if ($confirmation -cne $expectedConfirmation) {
    Write-Host "Confirmation did not match. Nothing was deleted." -ForegroundColor Green
    exit 2
}

if (-not (Get-Command "gcloud" -ErrorAction SilentlyContinue)) {
    Write-Host "Google Cloud CLI is required for Application Default Credentials." -ForegroundColor Red
    exit 1
}

Push-Location -LiteralPath "functions"
try {
    node erase_db.js --project $ProjectId --database $DatabaseId --confirm $confirmation
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
