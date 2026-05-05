Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "   Construyendo AIOps Remediation Engine Lambda" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

# Comprueba si Python está instalado
if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Python no está instalado o no está en el PATH." -ForegroundColor Red
    exit 1
}

Write-Host "1. Instalando dependencias en la carpeta lambda/ ..." -ForegroundColor Yellow
pip install -r lambda/requirements.txt -t lambda/

if ($LASTEXITCODE -eq 0) {
    Write-Host "-> Dependencias instaladas correctamente." -ForegroundColor Green
    Write-Host ""
    Write-Host "Todo listo. Ahora Terraform empaquetará automáticamente estas dependencias en el .zip al aplicar." -ForegroundColor Green
    Write-Host "Siguiente paso: Ejecuta 'terraform apply'" -ForegroundColor Cyan
} else {
    Write-Host "ERROR: Hubo un problema al instalar las dependencias." -ForegroundColor Red
}
