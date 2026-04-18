#!/bin/bash

INPUT_FILE="/home/agentafter/list_urls.txt"
OUTPUT_FILE="/home/agentafter/huaka-sigda-data/sources.csv"

# Crear directorio si no existe (por seguridad)
mkdir -p huaka-sigda-data

echo "Generando fuentes. Por favor espera..."
echo "--------------------------------------"

# Limpiamos el archivo de salida
rm -f "$OUTPUT_FILE"

while read -r URL; do
    # Saltar líneas vacías
    if [ -z "$URL" ]; then continue; fi

    echo "Analizando: $URL"

    # 1. Hacemos petición al servicio para obtener el JSON de definición
    # Usamos curl con timeout por si el servidor se cuelga
    JSON_DATA=$(curl -s --max-time 10 "${URL}?f=pjson")

    # 2. Verificamos si curl trajo algo
    if [ -z "$JSON_DATA" ]; then
        echo "  ⚠️ Error: No se pudo conectar."
        continue
    fi

    # 3. Usamos jq para extraer ID y NOMBRE de cada capa
    # El formato de salida de jq será: "ID|NOMBRE"
    LAYERS=$(echo "$JSON_DATA" | jq -r '.layers[] | "\(.id)|\(.name)"')

    # 4. Procesamos cada capa encontrada
    while read -r LAYER_INFO; do
        if [ -z "$LAYER_INFO" ]; then continue; fi
        
        ID=$(echo "$LAYER_INFO" | cut -d'|' -f1)
        RAW_NAME=$(echo "$LAYER_INFO" | cut -d'|' -f2)

        # Limpieza del nombre para que sea un archivo amigable
        # Convertimos a minúsculas, espacios a guiones bajos, quitamos caracteres raros
        CLEAN_NAME=$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | sed 's/[^a-z0-9_]//g')
        
        # Si el nombre quedó vacío (ej. caracteres raros), usar un genérico
        if [ -z "$CLEAN_NAME" ]; then CLEAN_NAME="layer_${ID}"; fi

        # Escribimos en el CSV: nombre_limpio,url/id
        echo "${CLEAN_NAME},${URL}/${ID}" >> "$OUTPUT_FILE"
        
        echo "  ✅ Encontrada: ID $ID -> $CLEAN_NAME"

    done <<< "$LAYERS"

done < "$INPUT_FILE"

echo "--------------------------------------"
echo "¡Listo! Archivo generado en: $OUTPUT_FILE"
echo "Total de capas encontradas: $(wc -l < $OUTPUT_FILE)"
