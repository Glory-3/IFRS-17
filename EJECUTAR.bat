@echo off
REM ============================================================
REM  Motor IFRS 17 - ejecutar
REM  Uso: arrastre su Excel de insumos sobre este archivo,
REM       o haga doble clic para correr el ejemplo.
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"

where julia >nul 2>nul
if errorlevel 1 (
    echo.
    echo No se encontro Julia en este equipo.
    echo Instalelo abriendo PowerShell y escribiendo:   winget install julia -s msstore
    echo o descarguelo de https://julialang.org/downloads/  y vuelva a intentar.
    echo.
    pause
    exit /b 1
)

set "ARCHIVO=%~1"
if "%ARCHIVO%"=="" set "ARCHIVO=%~dp0datos\ejemplo\IFRS17_Insumos_ejemplo.xlsx"

echo Preparando el motor (la primera vez tarda varios minutos)...
julia --project="%~dp0." -e "using Pkg; Pkg.instantiate()"
if errorlevel 1 (
    echo No se pudieron instalar las librerias. Revise la conexion a internet o el proxy.
    pause
    exit /b 1
)

julia --project="%~dp0." "%~dp0scripts\ejecutar.jl" "%ARCHIVO%"
echo.
pause
