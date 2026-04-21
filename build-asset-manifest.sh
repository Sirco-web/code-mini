#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Asset Manifest Builder
#  
#  Usage:
#    bash build-asset-manifest.sh [games-folder]
#
#  Scans all game folders for assets and updates games.json
#  with asset metadata for offline caching decisions.
#
#  Output: Updated games.json with assetInfo field for each game
# ============================================================

GAMES_DIR="${1:-.}"
GAMES_JSON="$GAMES_DIR/games.json"
ASSET_INDEX="$GAMES_DIR/asset-cache-index.json"

if [[ ! -f "$GAMES_JSON" ]]; then
  echo "[!] Error: games.json not found at $GAMES_JSON"
  exit 1
fi

echo "[*] Asset Manifest Builder"
echo "[*] Scanning: $GAMES_DIR"
echo ""

# Create a temporary file for the updated manifest
TEMP_MANIFEST=$(mktemp)
TEMP_INDEX=$(mktemp)

# Initialize the asset index
echo "{" > "$TEMP_INDEX"
echo '  "cachedGames": {},' >> "$TEMP_INDEX"
echo '  "totalCachedSize": 0,' >> "$TEMP_INDEX"
echo '  "totalGamesCached": 0,' >> "$TEMP_INDEX"
echo '  "lastUpdated": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"' >> "$TEMP_INDEX"
echo "}" >> "$TEMP_INDEX"

# Start building the updated manifest
echo "[" > "$TEMP_MANIFEST"

TOTAL_GAMES=0
GAMES_WITH_ASSETS=0
TOTAL_CACHE_SIZE=0
CACHED_GAMES_INFO="[]"

# Read games.json and process each game
while IFS= read -r game_json; do
  [[ -z "$game_json" ]] && continue
  
  TOTAL_GAMES=$((TOTAL_GAMES + 1))
  
  # Parse game entry
  id=$(echo "$game_json" | jq -r '.id')
  name=$(echo "$game_json" | jq -r '.name')
  folder=$(echo "$game_json" | jq -r '.folder')
  
  game_path="$GAMES_DIR/$folder"
  assets_folder="$game_path/assets"
  
  # Check if assets folder exists
  if [[ -d "$assets_folder" ]]; then
    GAMES_WITH_ASSETS=$((GAMES_WITH_ASSETS + 1))
    
    # Count files and calculate size
    asset_count=$(find "$assets_folder" -type f | wc -l)
    asset_size=$(du -sb "$assets_folder" 2>/dev/null | cut -f1)
    TOTAL_CACHE_SIZE=$((TOTAL_CACHE_SIZE + asset_size))
    
    # Format size for display
    asset_size_human=$(numfmt --to=iec-i --suffix=B "$asset_size" 2>/dev/null || echo "${asset_size}B")
    
    echo "  ✓ $name: $asset_count files ($asset_size_human)"
    
    # Get list of asset files with paths relative to game folder
    asset_files=$(find "$assets_folder" -type f -printf '%P\n' | jq -R . | jq -s .)
    
    # Add asset info to game entry
    echo "$game_json" | jq --arg assetCount "$asset_count" --arg assetSize "$asset_size" --argjson assetFiles "$asset_files" '. + {
      assetInfo: {
        hasCachedAssets: true,
        assetCount: ($assetCount | tonumber),
        assetSizeBytes: ($assetSize | tonumber),
        canPlayOffline: true,
        assetFiles: $assetFiles
      }
    }' >> "$TEMP_MANIFEST"
    
    # Build cached games info for index
    CACHED_GAMES_INFO=$(echo "$CACHED_GAMES_INFO" | jq --arg id "$id" --arg name "$name" --arg folder "$folder" --arg count "$asset_count" --arg size "$asset_size" --argjson files "$asset_files" '. += [{
      id: $id,
      name: $name,
      folder: $folder,
      assetCount: ($count | tonumber),
      assetSizeBytes: ($size | tonumber),
      assetFiles: $files
    }]')
  else
    # No assets folder - add negative asset info
    echo "$game_json" | jq '. + {
      assetInfo: {
        hasCachedAssets: false,
        assetCount: 0,
        assetSizeBytes: 0,
        canPlayOffline: false,
        assetFiles: []
      }
    }' >> "$TEMP_MANIFEST"
  fi
  
  # Add comma except for the last entry (we'll handle that)
  echo "," >> "$TEMP_MANIFEST"
done < <(jq -r '.[] | @json' "$GAMES_JSON")

# Remove last comma and close the array
sed -i '$ s/,$//' "$TEMP_MANIFEST"
echo "]" >> "$TEMP_MANIFEST"

# Calculate totals in human-readable format
TOTAL_SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$TOTAL_CACHE_SIZE" 2>/dev/null || echo "${TOTAL_CACHE_SIZE}B")

# Calculate percentage (avoid division by zero)
if [[ $TOTAL_GAMES -gt 0 ]]; then
  CACHE_PERCENTAGE=$((GAMES_WITH_ASSETS * 100 / TOTAL_GAMES))
else
  CACHE_PERCENTAGE="0"
fi

# Build the asset index with cached games list
cat > "$TEMP_INDEX" << EOF
{
  "cachedGames": $GAMES_WITH_ASSETS,
  "totalCachedSize": $TOTAL_CACHE_SIZE,
  "totalCachedSizeHuman": "$TOTAL_SIZE_HUMAN",
  "totalGamesCached": $GAMES_WITH_ASSETS,
  "totalGames": $TOTAL_GAMES,
  "cachePercentage": $CACHE_PERCENTAGE,
  "lastUpdated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "repo": "Sirco-web/gm",
  "cachedGamesList": $(echo "$CACHED_GAMES_INFO" | jq '.')
}
EOF

# Replace original files
mv "$TEMP_MANIFEST" "$GAMES_JSON"
mv "$TEMP_INDEX" "$ASSET_INDEX"

echo ""
echo "════════════════════════════════════════"
echo "  ✓ ASSET MANIFEST UPDATED"
echo "  Total games: $TOTAL_GAMES"
echo "  Games with cached assets: $GAMES_WITH_ASSETS"
echo "  Total cache size: $TOTAL_SIZE_HUMAN"
echo "  Games manifest: $GAMES_JSON"
echo "  Asset index: $ASSET_INDEX"
echo "════════════════════════════════════════"
echo ""
echo "Each game now has an 'assetInfo' field with:"
echo "  - hasCachedAssets: true/false"
echo "  - assetCount: number of files"
echo "  - assetSizeBytes: total bytes"
echo "  - canPlayOffline: true = ready to cache for offline play"
echo "  - assetFiles: [] list of actual asset file paths (for caching)"
echo ""
echo "The HTML 'Cache All' button can now:"
echo "  1. Read games.json"
echo "  2. For each game with assetInfo.hasCachedAssets=true"
echo "  3. Download each file in assetInfo.assetFiles"
echo "  4. Cache them locally for offline play"
