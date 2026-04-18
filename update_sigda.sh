#!/bin/bash

# --- CONFIGURACIÓN GENERAL ---
REPO_PATH="/home/agentafter/huaka-sigda-data"
SOURCES_FILE="$REPO_PATH/sources.csv"
REPORT_FILE="$REPO_PATH/full_report.txt"
SCRAPER_SCRIPT="$REPO_PATH/scraper.py"
PMTILES_SCRIPT="/home/agentafter/generate_pmtiles.sh"
MAIN_GPKG="$REPO_PATH/huaka_sigda.gpkg"

# Variables de estado
GLOBAL_ERROR=0
UPDATED_COUNT=0

# --- INICIO ---
cd "$REPO_PATH" || { echo "Error: No encuentro $REPO_PATH"; exit 1; }
echo "=== REPORTE SIGDA DETALLADO (KART/GPKG): $(date) ===" > "$REPORT_FILE"

# Leemos el CSV
while IFS=, read -r NAME URL || [ -n "$NAME" ]; do
    
    NAME=$(echo "$NAME" | xargs)
    URL=$(echo "$URL" | xargs)
    if [ -z "$NAME" ]; then continue; fi

    TEMP_GPKG="temp_${NAME}.gpkg"
    RAW_FILE="raw_${NAME}.json"
    
    echo "---------------------------------------------------"
    echo "Procesando: $NAME"
    
    # 1. DESCARGA CON PYTHON
    if ! python3 "$SCRAPER_SCRIPT" "$URL" "$RAW_FILE"; then
        echo "❌ ERROR: Falló scraper en $NAME"
        echo "  - [ERROR CONEXIÓN] $NAME: El scraper Python falló (Timeout/403)." >> "$REPORT_FILE"
        [ -f "$RAW_FILE" ] && rm -f "$RAW_FILE"
        GLOBAL_ERROR=1
        continue
    fi

    # 2. CONVERSIÓN A GPKG TEMPORAL
    if ! ogr2ogr -f GPKG "$TEMP_GPKG" "$RAW_FILE" -t_srs EPSG:4326 2>&1; then
        echo "❌ ERROR: Falló conversión GDAL en $NAME"
        echo "  - [ERROR FORMATO] $NAME: El archivo descargado no es válido." >> "$REPORT_FILE"
        rm -f "$RAW_FILE"
        GLOBAL_ERROR=1
        continue
    fi
    rm -f "$RAW_FILE"

    # 3. ACTUALIZACIÓN DIRECTA DEL GPKG (Working Copy)
    echo "   Actualizando tabla en la base de datos..."
    # Sobrescribimos la tabla en el working copy directamente
    if ! ogr2ogr -f GPKG "$MAIN_GPKG" "$TEMP_GPKG" -nln "$NAME" -overwrite 2>&1; then
        echo "❌ ERROR: Falló actualización de tabla en $NAME"
        echo "  - [ERROR GPKG] $NAME: No se pudo escribir en la base de datos." >> "$REPORT_FILE"
        rm -f "$TEMP_GPKG"
        GLOBAL_ERROR=1
        continue
    fi
    rm -f "$TEMP_GPKG"

    ((UPDATED_COUNT++))
    echo "✅ OK"

done < "$SOURCES_FILE"

# --- COMMIT Y PUSH ---
echo "---------------------------------------------------"
# Verificamos cambios con kart status
if kart status | grep -q "Changes in working copy:"; then
    COMMIT_MSG="Update $(date +'%Y-%m-%d') | Capas procesadas: $UPDATED_COUNT"
    echo "Consolidando cambios en Kart..."
    kart commit -m "$COMMIT_MSG"
    
    echo "Enviando a GitHub (LFS)..."
    if git push origin main; then
        echo "✅ Push Exitoso."
        echo "Resumen: Actualización exitosa ($UPDATED_COUNT capas procesadas)." >> "$REPORT_FILE"
        
        # --- PMTILES GENERATION ---
        if [ -x "$PMTILES_SCRIPT" ]; then
            echo "---------------------------------------------------"
            echo "Generando PMTiles para capas que cambiaron..."
            
            # Obtenemos la lista de datasets que cambiaron
            CHANGED_DATASETS=$(kart diff --name-only HEAD~1 HEAD)
            
            if [ -n "$CHANGED_DATASETS" ]; then
                if "$PMTILES_SCRIPT" $CHANGED_DATASETS; then
                    echo "✅ PMTiles generados correctamente."
                    echo "PMTiles: Generación exitosa." >> "$REPORT_FILE"
                else
                    PMTILES_EXIT=$?
                    echo "⚠️  PMTiles: Generación falló (código: $PMTILES_EXIT)"
                    echo "PMTiles: Generación falló (código: $PMTILES_EXIT)" >> "$REPORT_FILE"
                fi
            else
                echo "No hubo cambios reales en los datos de las capas."
            fi
        fi
    else
        echo "❌ Git Push Falló (Verifica llaves SSH)."
        echo "ERROR: Falló el envío a GitHub." >> "$REPORT_FILE"
        exit 1
    fi
else
    echo "Sin cambios detectados en el contenido."
    echo "Resumen: Sin cambios en los datos hoy." >> "$REPORT_FILE"
fi

# Mantenemos compatibilidad con los códigos de error de n8n
if [ $GLOBAL_ERROR -eq 1 ]; then exit 3; fi
exit 0
