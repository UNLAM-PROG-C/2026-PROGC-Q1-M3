# Script para compilar el proyecto sin Maven (requiere descargar Gson)
# O instala Maven desde https://maven.apache.org/download.cgi

param(
    [switch]$InstallMaven = $false
)

if ($InstallMaven) {
    Write-Host "Para instalar Maven en Windows:"
    Write-Host "1. Descarga Maven 3.8+ desde https://maven.apache.org/download.cgi"
    Write-Host "2. Extrae a C:\apache-maven-3.8.X (o tu ubicación preferida)"
    Write-Host "3. Agrega C:\apache-maven-3.8.X\bin a tu PATH"
    Write-Host "4. Ejecuta: mvn clean package"
    exit
}

Write-Host "Compilando con Maven..."
Write-Host ""
Write-Host "REQUISITOS:"
Write-Host "- Java 17+ instalado y en PATH"
Write-Host "- Maven 3.8+ instalado y en PATH"
Write-Host ""
Write-Host "Si no tienes Maven instalado, sigue estos pasos:"
Write-Host ""
Write-Host "WINDOWS (PowerShell como Admin):"
Write-Host "1. Descarga Maven 3.8+ desde https://maven.apache.org/download.cgi"
Write-Host "2. Extrae el archivo descargado, p.ej. a C:\apache-maven-3.8.6"
Write-Host "3. Abre Variables de Entorno (Win+Pause > Cambiar configuración avanzada > Variables de entorno)"
Write-Host "4. Agrega/edita PATH a incluir: C:\apache-maven-3.8.6\bin"
Write-Host "5. Abre una Nueva ventana de PowerShell y ejecuta:"
Write-Host ""
Write-Host "   mvn clean package"
Write-Host ""
Write-Host "ALTERNATIVA - Instalar con Chocolatey (si lo tienes):"
Write-Host "   choco install maven"
