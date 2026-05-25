@echo off
REM Script para compilar el proyecto TP Concurrente

echo.
echo === COMPILANDO PROYECTO TP CONCURRENTE ===
echo.

REM Verificar si Maven está disponible
where mvn >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Maven no se encuentra en PATH
    echo.
    echo SOLUCIONES:
    echo.
    echo 1. INSTALAR MAVEN (recomendado):
    echo    - Descarga Maven 3.8+ desde https://maven.apache.org/download.cgi
    echo    - Extrae a C:\apache-maven-3.8.6 (o similar)
    echo    - Abre Variables de Entorno en Windows:
    echo      Win + Pause (o Inicio > Busca "Variables de entorno")
    echo    - Edita PATH y agrega: C:\apache-maven-3.8.6\bin
    echo    - Abre una NUEVA terminal (cmd o PowerShell) y ejecuta:
    echo      mvn clean package
    echo.
    echo 2. INSTALAR CON CHOCOLATEY (si lo tienes):
    echo    choco install maven
    echo.
    pause
    exit /b 1
)

REM Verificar si Java 17+ está disponible
java -version 2>&1 | find "17" >nul
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] Java 17+ no detectado
    echo Por favor asegúrate de tener Java 17 LTS o superior instalado
    echo.
)

REM Compilar con Maven
echo Compilando...
mvn clean package -DskipTests

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [SUCCESS] Compilacion exitosa!
    echo.
    echo Para ejecutar:
    echo   java -jar target/tp-concurrente-1.0-SNAPSHOT.jar
    echo.
    echo O con Maven:
    echo   mvn exec:java -Dexec.mainClass=com.tp.Main
    echo.
) else (
    echo.
    echo [ERROR] Compilacion fallida
    exit /b 1
)

pause
