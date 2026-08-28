$ErrorActionPreference = 'Stop'

$figureDirectory = 'D:\OneDrive - Universiti Tunku Abdul Rahman\UTAR FYP\3. FYP2\Generated Figures'
$archivePath = 'D:\OneDrive - Universiti Tunku Abdul Rahman\UTAR FYP\3. FYP2\SchoolWay FYP2 Generated Figures.zip'

$figureFiles = Get-ChildItem -LiteralPath $figureDirectory -File
Compress-Archive -LiteralPath $figureFiles.FullName -DestinationPath $archivePath -Force

Get-Item -LiteralPath $archivePath | Select-Object FullName, Length, LastWriteTime
$figureFiles | Group-Object Extension | Select-Object Name, Count
