#!/bin/bash

# =============================================================================
# PMTiles Generator for SIGDA (Kart/GPKG Version)
# Generates tiles for datasets that have changed in Kart
# =============================================================================

# --- CONFIGURATION ---
REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPKG_FILE="$REPO_PATH/huaka_sigda.gpkg"
TILES_DIR="$REPO_PATH/tiles"
REPORT_FILE="$TILES_DIR/tiles_report.txt"
MAX_SIZE_MB=50
GITHUB_REPO="agentafter/huaka-sigda-data"
RELEASE_TAG="pmtiles-latest"

# --- ALLOWED DATASETS (only these will be processed in full scan mode) ---
ALLOWED_DATASETS=(
    "base_aprobados"
    "base_proceso_aprobacion"
    "base_proteccion_provisional"
    "base_referenciales"
    "caminos_prehispanicos_v4"
    "base_propuestas"
    "registrado_v4"
    "declarados_v4"
    "proyeccion_caminos_v4"
    "paisaje_cultural_v4"
    "patrimonio_mundial"
    "vuelos_dron"
    "ciras_v3"
    "ciras_v4"
    "das_v4"
)

# --- EXIT CODES ---
# 0 = Success
# 1 = Tippecanoe missing
# 2 = Generation failed
# 3 = Push failed

# --- FUNCTIONS ---

check_tippecanoe() {
    if ! command -v tippecanoe &> /dev/null; then
        echo "❌ ERROR: tippecanoe is not installed or not in PATH"
        exit 1
    fi
}

generate_tile() {
    local DATASET="$1"
    local OUTPUT="$TILES_DIR/${DATASET}.pmtiles"
    
    echo "  Generating: $DATASET.pmtiles"
    
    # Extraemos la capa del GPKG y la pasamos directamente a tippecanoe
    # Kart usa el nombre del dataset como el nombre de la tabla en el GPKG
    if ogr2ogr -f GeoJSON /vsistdout/ "$GPKG_FILE" "$DATASET" -t_srs EPSG:4326 | \
       tippecanoe \
        --force \
        --read-parallel \
        -P \
        --no-feature-limit \
        --no-tile-size-limit \
        --no-line-simplification \
        --minimum-zoom=5 \
        --maximum-zoom=16 \
        --no-tile-compression \
        --name="$DATASET" \
        --layer="$DATASET" \
        --description="SIGDA: $DATASET" \
        -o "$OUTPUT" 2>&1; then
        
        # Check file size
        local SIZE_MB=$(du -m "$OUTPUT" | cut -f1)
        if [ "$SIZE_MB" -gt "$MAX_SIZE_MB" ]; then
            echo "  ⚠️  WARNING: $DATASET.pmtiles is ${SIZE_MB}MB"
            echo "  [SIZE WARNING] $DATASET.pmtiles: ${SIZE_MB}MB exceeds limit" >> "$REPORT_FILE"
        fi
        
        echo "  ✅ Generated: $DATASET.pmtiles (${SIZE_MB}MB)"
        return 0
    else
        echo "  ❌ Failed: $DATASET.pmtiles"
        return 1
    fi
}

# --- MAIN ---

echo "=== PMTiles Generator for SIGDA (Kart/GPKG) ==="
echo "Started: $(date)"

check_tippecanoe
mkdir -p "$TILES_DIR"
echo "=== PMTILES GENERATION REPORT: $(date) ===" > "$REPORT_FILE"

DATASETS_TO_PROCESS=()
FAILED_COUNT=0
SUCCESS_COUNT=0
SKIPPED_COUNT=0

if [ $# -gt 0 ]; then
    # Mode: Explicit (usually called from update_sigda.sh with changed datasets)
    echo "Mode: Incremental (processing $# specified datasets)"
    echo "Mode: Incremental" >> "$REPORT_FILE"
    for DS in "$@"; do
        DATASETS_TO_PROCESS+=("$DS")
    done
else
    # Mode: Full scan (check all allowed datasets)
    echo "Mode: Full scan (checking all allowed datasets)"
    echo "Mode: Full scan" >> "$REPORT_FILE"
    for DS in "${ALLOWED_DATASETS[@]}"; do
        TILE="$TILES_DIR/${DS}.pmtiles"
        # Since we use a single GPKG, we can't easily check file dates.
        # In full scan mode without arguments, we generate all missing tiles.
        if [ ! -f "$TILE" ]; then
            echo "  📁 Missing tile: $DS.pmtiles"
            DATASETS_TO_PROCESS+=("$DS")
        else
            ((SKIPPED_COUNT++))
        fi
    done
fi

echo "---------------------------------------------------"
echo "Datasets to process: ${#DATASETS_TO_PROCESS[@]}"
echo "Datasets skipped (up-to-date): $SKIPPED_COUNT"
echo "---------------------------------------------------"

for DS in "${DATASETS_TO_PROCESS[@]}"; do
    if generate_tile "$DS"; then
        ((SUCCESS_COUNT++))
    else
        ((FAILED_COUNT++))
        echo "  [GENERATION FAILED] $DS" >> "$REPORT_FILE"
    fi
done

echo "---------------------------------------------------"
echo "Summary: $SUCCESS_COUNT generated, $FAILED_COUNT failed, $SKIPPED_COUNT skipped"

if [ "$FAILED_COUNT" -gt 0 ]; then
    echo "❌ Some tiles failed to generate"
    exit 2
fi

if [ "$SUCCESS_COUNT" -eq 0 ]; then
    echo "✅ No tiles needed generation"
    exit 0
fi

# Upload to GitHub Releases
echo "---------------------------------------------------"
echo "Uploading PMTiles to GitHub Releases..."
cd "$REPO_PATH" || exit 2

if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) not installed"
    exit 3
fi

# Create or update release
gh release delete "$RELEASE_TAG" --repo "$GITHUB_REPO" --yes 2>/dev/null || true

if gh release create "$RELEASE_TAG" \
    --repo "$GITHUB_REPO" \
    --title "PMTiles - $(date +'%Y-%m-%d')" \
    --notes "Auto-generated PMTiles from SIGDA GPKG database (Kart versioned).
Generated: $(date)" \
    "$TILES_DIR"/*.pmtiles; then
    echo "✅ Upload successful"
    exit 0
else
    echo "❌ Release upload failed"
    exit 3
fi
