Write-Host "Starting database erasure..." -ForegroundColor Cyan

# 2. Delete Auth users using Node
if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Node.js is required to run this script. Please install Node.js." -ForegroundColor Red
    exit 1
}

Push-Location -Path "functions"
if (-not (Test-Path "node_modules")) {
    Write-Host "Installing dependencies in functions folder..." -ForegroundColor Yellow
    npm install
}

Write-Host "🔥 Erasing Firebase Auth Users..." -ForegroundColor Yellow
node erase_db.js

Pop-Location
Write-Host "🎉 Erase operation completed successfully!" -ForegroundColor Green
