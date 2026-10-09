#!/usr/bin/env bash
# Motor IFRS 17 - ejecutar (Mac / Linux)
# Uso: ./ejecutar.sh [ruta/al/Excel_de_insumos.xlsx]
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
command -v julia >/dev/null || { echo "No se encontró Julia. Instálelo con: curl -fsSL https://install.julialang.org | sh"; exit 1; }
ARCHIVO="${1:-$DIR/datos/ejemplo/IFRS17_Insumos_ejemplo.xlsx}"
julia --project="$DIR" -e 'using Pkg; Pkg.instantiate()'
julia --project="$DIR" "$DIR/scripts/ejecutar.jl" "$ARCHIVO"
