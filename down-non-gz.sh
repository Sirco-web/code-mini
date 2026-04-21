#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Game Asset Downloader & Offline Converter
#  
#  Usage:
#    bash down-non-gz.sh [html-file] [output-folder]
#
#  Downloads all http:// and https:// assets referenced in an HTML file,
#  creates an 'assets' folder, and rewrites the HTML to use
#  local asset paths for offline functionality.
#
#  Skips: blob: and data: URLs
#
#  If no arguments provided, uses defaults for legacy mode:
#    GN-Math Game Downloader (Parallel Edition)
#    Downloads game HTML + required assets from gn-math repos
#    Requires bash ≥ 4.3 for `wait -n`.
#
#  Special flags:
#    --check-urls    Test if all required URLs are accessible
#    --help          Show this help message
#
#  NOTE: Do NOT run with sudo — files will get root ownership
# ============================================================

# Handle special flags
if [[ "${1:-}" == "--help" ]]; then
  grep "^#  Usage:" -A 20 "$0" | sed 's/^#  //'
  exit 0
fi

if [[ "${1:-}" == "--check-urls" ]]; then
  echo "[*] Testing URL accessibility…"
  echo ""
  curl_test() {
    local url="$1"
    local name="$2"
    echo -n "  Testing $name... "
    if curl -fsSL --connect-timeout 3 -I "$url" > /dev/null 2>&1; then
      echo "✓"
      return 0
    else
      echo "✗"
      return 1
    fi
  }
  
  curl_test "https://raw.githubusercontent.com/gn-math/assets/main/zones.json" "zones.json (GitHub Raw)"
  curl_test "https://raw.githubusercontent.com/gn-math/html/main/697.html" "HTML base (sample)"
  curl_test "https://github.com/gn-math/assets.git" "Assets repo"
  curl_test "https://raw.githubusercontent.com/gn-math/covers/main/697.png" "Covers (GitHub Raw)"
  
  echo ""
  echo "[*] URL check complete. If any failed, check your internet or repo URLs."
  exit 0
fi

# ============================================================
#  OFFLINE CONVERSION MODE
#  If HTML file argument provided, enter offline mode
# ============================================================
if [[ $# -gt 0 && ("$1" == *.html || "$1" == */ || -f "$1") ]]; then
  HTML_INPUT="${1:-.}"
  OUTPUT_DIR="${2:-.}"
  ASSETS_FOLDER="$OUTPUT_DIR/assets"
  
  # Handle if HTML_INPUT is a directory
  if [[ -d "$HTML_INPUT" ]]; then
    OUTPUT_DIR="$HTML_INPUT"
    HTML_INPUT="$HTML_INPUT/game-27fre.html"
    ASSETS_FOLDER="$OUTPUT_DIR/assets"
  fi
  
  if [[ ! -f "$HTML_INPUT" ]]; then
    echo "[!] Error: HTML file not found: $HTML_INPUT"
    exit 1
  fi
  
  echo "[*] Offline Asset Downloader"
  echo "[*] Input:  $HTML_INPUT"
  echo "[*] Output: $OUTPUT_DIR"
  echo ""
  
  mkdir -p "$ASSETS_FOLDER"
  
  # Extract URLs from HTML attributes only (src=, href=, data=, etc.)
  # This avoids picking up template literals and JavaScript code
  echo "[*] Scanning for remote assets in HTML attributes..."
  
  # Create a list of actual attribute URLs (http:// and https://)
  # Skip blob: and data: URLs
  URLS=$(grep -oP '(?:src|href|data)="https?://[^"]+"|(?:src|href|data)='"'"'https?://[^'"'"']+'"'"'' "$HTML_INPUT" | sed 's/^[^=]*=["'"'"']//' | sed 's/["'"'"']$//' | grep -v '^blob:' | grep -v '^data:' | sort -u)
  
  if [[ -z "$URLS" ]]; then
    echo "[!] No remote assets found in HTML attributes"
    exit 0
  fi
  
  TOTAL_URLS=$(echo "$URLS" | wc -l)
  DOWNLOADED=0
  FAILED=0
  DECLARED_URLS=()
  
  echo "[*] Found $TOTAL_URLS unique URLs to download"
  echo ""
  
  # Store original HTML
  TEMP_HTML=$(mktemp)
  cp "$HTML_INPUT" "$TEMP_HTML"
  MODIFIED_HTML="$TEMP_HTML.offline"
  cp "$TEMP_HTML" "$MODIFIED_HTML"
  
  # Download each asset
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    
    # Skip URLs with template variables
    if [[ "$url" =~ \$\{ ]]; then
      echo "  ⊘ Skipping template URL: $url"
      continue
    fi
    
    # Extract filename from URL (remove query strings)
    filename=$(basename "$url" | cut -d'?' -f1)
    [[ -z "$filename" ]] && filename="asset-$RANDOM"
    
    filepath="$ASSETS_FOLDER/$filename"
    
    # Skip if already exists
    if [[ -f "$filepath" ]]; then
      echo "  ✓ Already cached: $filename"
      DOWNLOADED=$((DOWNLOADED + 1))
    else
      echo -n "  ↓ Downloading: $filename ... "
      if curl -fsSL --connect-timeout 5 --max-time 15 "$url" -o "$filepath" 2>/dev/null; then
        filesize=$(du -h "$filepath" | cut -f1)
        echo "✓ ($filesize)"
        DOWNLOADED=$((DOWNLOADED + 1))
      else
        echo "✗ (FAILED)"
        FAILED=$((FAILED + 1))
        rm -f "$filepath"
        continue
      fi
    fi
    
    # Update HTML to use local path (if download succeeded or was cached)
    if [[ -f "$filepath" ]]; then
      # Escape special characters for sed
      url_escaped=$(printf '%s\n' "$url" | sed -e 's/[\/&]/\\&/g')
      sed -i "s|$url_escaped|./assets/$filename|g" "$MODIFIED_HTML"
      DECLARED_URLS+=("$url")
    fi
  done <<< "$URLS"
  
  # Also handle inline JavaScript that loads assets dynamically
  echo ""
  echo "[*] Updating inline JavaScript for offline mode..."
  
  # Replace CDN URLs in inline scripts (both http:// and https://)
  sed -i "s|https\?://cdn.jsdelivr.net/gh/gn-math/covers@main|./assets/covers|g" "$MODIFIED_HTML"
  sed -i "s|https\?://raw.githubusercontent.com/gn-math/covers/main|./assets/covers|g" "$MODIFIED_HTML"
  sed -i "s|https\?://cdn.jsdelivr.net/gh/gn-math/assets@main/zones.json|./assets/zones.json|g" "$MODIFIED_HTML"
  sed -i "s|https\?://raw.githubusercontent.com/gn-math/assets/main/zones.json|./assets/zones.json|g" "$MODIFIED_HTML"
  
  # Optional: Try to download zones.json for offline game list
  echo "[*] Attempting to download game catalog (zones.json)..."
  if curl -fsSL --connect-timeout 5 "$ZONES_JSON" -o "$ASSETS_FOLDER/zones.json" 2>/dev/null; then
    echo "  ✓ Game catalog downloaded"
    DOWNLOADED=$((DOWNLOADED + 1))
    sed -i "s|https://cdn.jsdelivr.net/gh/gn-math/assets@main/zones.json|./assets/zones.json|g" "$MODIFIED_HTML"
    sed -i "s|https://raw.githubusercontent.com/gn-math/assets/main/zones.json|./assets/zones.json|g" "$MODIFIED_HTML"
  else
    echo "  ⊘ Game catalog not available (will need internet for game list)"
  fi
  
  # Move the modified HTML to the output
  cp "$MODIFIED_HTML" "$OUTPUT_DIR/index-offline.html"
  cp "$OUTPUT_DIR/index-offline.html" "$OUTPUT_DIR/index.html"
  
  # Create a README with usage instructions
  cat > "$OUTPUT_DIR/OFFLINE_README.md" << 'EOF'
# Offline Game Setup

## What's Included
- `index.html` - Main game interface (offline ready)
- `assets/` - Downloaded JavaScript libraries
- `zones.json` - Game catalog (if downloaded)

## How to Use

### Option 1: Direct Browser Access
Simply open `index.html` in your browser. The game will:
1. Load the game list from zones.json (if available)
2. Fetch game covers from the `assets/covers/` folder
3. Load games from individual game folders

### Option 2: Local Server (Recommended)
Some features work better with a local server:

```bash
# Using Python 3
python3 -m http.server 8000

# Using Python 2
python -m SimpleHTTPServer 8000

# Using Node.js/http-server
npx http-server -p 8000
```

Then visit: `http://localhost:8000/index.html`

## Downloading Game Assets

To download specific games, use the downloader script:

```bash
# Download and convert an HTML game file
bash down-non-gz.sh path/to/game.html path/to/output/folder
```

## Offline Functionality

- ✓ All UI JavaScript and libraries are local
- ✓ Game catalogs work offline (if zones.json is present)
- ✓ Individual games load offline (if assets are downloaded)
- ✓ Cover images display from local cache

## Note

Some features may require additional game assets to be downloaded separately:
- Game covers are cached in `assets/covers/`
- Game code and assets go in individual game folders
EOF

  echo ""
  echo "════════════════════════════════════════"
  echo "  ✓ OFFLINE CONVERSION COMPLETE"
  echo "  Downloaded: $DOWNLOADED  Failed: $FAILED"
  echo "  Assets folder: $ASSETS_FOLDER"
  echo "  Offline HTML: $OUTPUT_DIR/index.html"
  echo "  Setup guide: $OUTPUT_DIR/OFFLINE_README.md"
  echo ""
  echo "  Next steps:"
  echo "  1. Open index.html in a browser"
  echo "  2. Or run: python3 -m http.server 8000"
  echo "  3. For full offline, download game assets separately"
  echo "════════════════════════════════════════"
  
  # Cleanup
  rm -f "$TEMP_HTML" "$MODIFIED_HTML"
  
  exit 0
fi

# ============================================================
#  LEGACY GN-MATH MODE (no arguments or running downloader)
# ============================================================

# Number of parallel download workers
JOBS=${JOBS:-10}

# Warn if running as root
if [[ $EUID -eq 0 ]]; then
  echo "WARNING: Running as root. File ownership will be set to root."
fi

# Use direct GitHub raw URLs to bypass JSDelivr CDN 403 block
ZONES_JSON="https://raw.githubusercontent.com/gn-math/assets/main/zones.json"
HTML_BASE="https://raw.githubusercontent.com/gn-math/html/main"
ASSETS_REPO="https://github.com/gn-math/assets.git"
COVERS_CDN="https://raw.githubusercontent.com/gn-math/covers/main"

OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$OUT_DIR/games.json"
ASSETS_DIR="$(mktemp -d)"
TMP_JSON="$(mktemp)"
JOBS_DIR="$(mktemp -d)"          # each worker writes results here

MAX_RETRIES=3

cleanup() {
  rm -rf "$ASSETS_DIR" "$TMP_JSON" "$JOBS_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"

# ============================================================
#  Pre-flight checks
# ============================================================
echo "[*] Checking dependencies…"
for cmd in curl git jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "[!] ERROR: Required command not found: $cmd"
    exit 1
  fi
done
echo "[✓] All dependencies available: curl, git, jq"

# ============================================================
#  Step 1: Download zones.json (game catalogue)
# ============================================================
echo ""
echo "[*] Fetching zones.json from $ZONES_JSON…"

# Attempt with verbose diagnostics (don't fail on HTTP error, check code instead)
HTTP_CODE=$(curl -sL -w "%{http_code}" -o "$TMP_JSON" "$ZONES_JSON" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "[!] ERROR: HTTP $HTTP_CODE when fetching zones.json"
  echo "[!] URL: $ZONES_JSON"
  echo ""
  echo "  Possible issues:"
  echo "  • Repository may be private or inaccessible"
  echo "  • Wrong branch (check if 'main' exists, try 'master')"
  echo "  • File path may be incorrect"
  echo "  • Network connectivity issue"
  echo ""
  echo "  Test with: curl -I '$ZONES_JSON'"
  rm -f "$TMP_JSON"
  exit 1
fi

# Verify JSON is valid
if ! jq empty "$TMP_JSON" 2>/dev/null; then
  echo "[!] ERROR: Downloaded file is not valid JSON"
  rm -f "$TMP_JSON"
  exit 1
fi

TOTAL=$(jq 'length' "$TMP_JSON")
if [[ -z "$TOTAL" || "$TOTAL" == "0" ]]; then
  echo "[!] ERROR: zones.json is empty or invalid"
  rm -f "$TMP_JSON"
  exit 1
fi

echo "[✓] Downloaded zones.json with $TOTAL entries"

# ============================================================
#  Step 2: Sparse-clone asset repo (only numeric game folders)
#  Uses --filter=blob:none so the initial clone is tiny (~1 MB),
#  then sparse-checkout pulls only the folders that exist.
# ============================================================
echo ""
echo "[*] Sparse-cloning assets repo…"
echo "    Repo: $ASSETS_REPO"

# Try to clone - with error checking (don't fail immediately on error)
if ! git clone --filter=blob:none --depth 1 --sparse "$ASSETS_REPO" "$ASSETS_DIR" 2>&1 | tail -10; then
  echo "[!] ERROR: Failed to clone repository"
  echo "[!] URL: $ASSETS_REPO"
  echo ""
  echo "  Possible issues:"
  echo "  • Repository URL is incorrect"
  echo "  • Repository is private"
  echo "  • Network connectivity issue"
  echo "  • Git authentication needed"
  echo ""
  echo "  Test with: git ls-remote '$ASSETS_REPO'"
  rm -rf "$ASSETS_DIR"
  exit 1
fi

if [[ ! -d "$ASSETS_DIR/.git" ]]; then
  echo "[!] ERROR: Repository clone failed (no .git directory)"
  rm -rf "$ASSETS_DIR"
  exit 1
fi

cd "$ASSETS_DIR" || exit 1
ASSET_IDS=$(git ls-tree --name-only HEAD | grep -E '^[0-9]+$' || true)
ASSET_COUNT=$(echo "$ASSET_IDS" | grep -c . || true)
echo "[✓] Found $ASSET_COUNT games with asset folders"

if [[ -n "$ASSET_IDS" ]]; then
  if ! echo "$ASSET_IDS" | tr ' ' '\n' | git sparse-checkout set --stdin 2>&1 | tail -2; then
    echo "[!] WARNING: sparse-checkout failed, continuing anyway"
  fi
  echo "[✓] Asset folders configured for download"
fi

cd "$OUT_DIR" || exit 1

# Write asset hashes to a file so workers can read it (assoc arrays can't export)
ASSET_HASH_FILE="$JOBS_DIR/_asset_hashes"
declare -A ASSET_TREE_HASH
for aid in $ASSET_IDS; do
  echo "$aid"
done > "$ASSET_HASH_FILE"

# ============================================================
#  Step 3: Download + process each game  (PARALLEL)
#  Each worker writes two files into $JOBS_DIR:
#    <safe_name>.json   – manifest entry
#    <safe_name>.status  – "skipped" / "updated" / "new" / "failed"
# ============================================================
echo ""
echo "[*] Downloading games ($JOBS parallel workers)…"

process_game() {
  local entry="$1"
  local OUT_DIR="$2"
  local ASSETS_DIR="$3"
  local HTML_BASE="$4"
  local COVERS_CDN="$5"
  local JOBS_DIR="$6"
  local MAX_RETRIES="$7"

  local ASSET_HASH_FILE="$JOBS_DIR/_asset_hashes"

  local id name raw_url
  id=$(echo "$entry" | jq -r '.id // empty')
  name=$(echo "$entry" | jq -r '.name // empty')
  raw_url=$(echo "$entry" | jq -r '.url // empty')

  # Skip junk and COMMENTS game
  [[ -z "$id" || "$id" == "null" || "$id" == "-1" ]] && return 0
  [[ "$name" =~ ^[[:space:]]*COMMENTS[[:space:]]*$ ]] && return 0

  # Sanitised folder name
  local safe_name folder_name game_dir
  safe_name=$(echo "$name" | tr '/:' '_' | tr -cd '[:alnum:] _-')
  folder_name="${safe_name}"
  game_dir="$OUT_DIR/$folder_name"

  # Resolve HTML filename
  local html_file dl_url
  html_file=$(echo "$raw_url" | sed 's|.*{HTML_URL}/||')
  if [[ -z "$html_file" || "$html_file" == "null" || "$html_file" == "$raw_url" ]]; then
    html_file="${id}.html"
  fi
  dl_url="$HTML_BASE/$html_file"

  local file="$game_dir/index.html"
  local hash_file="$game_dir/.hash"

  # ── Download HTML ──────────────────────────────────────────
  local TMP_HTML
  TMP_HTML=$(mktemp)
  local RETRY=0 OK=false
  while [[ $RETRY -lt $MAX_RETRIES ]]; do
    if curl -fsSL "$dl_url" -o "$TMP_HTML" 2>/dev/null; then OK=true; break; fi
    RETRY=$((RETRY + 1))
    [[ $RETRY -lt $MAX_RETRIES ]] && sleep 1
  done

  if ! $OK; then
    echo "    [!] FAILED: $name (id=$id)"
    rm -f "$TMP_HTML"
    echo "failed" > "$JOBS_DIR/${id}.status"
    [[ -d "$game_dir" ]] && echo "{\"id\": \"$id\", \"name\": \"$name\", \"folder\": \"$folder_name\"}" > "$JOBS_DIR/${id}.json"
    return 0
  fi

  # ── Compute hash ───────────────────────────────────────────
  local HTML_HASH ASSET_HASH COMBINED
  HTML_HASH=$(md5sum "$TMP_HTML" | cut -d' ' -f1)
  ASSET_HASH="none"
  if grep -q "^${id} " "$ASSET_HASH_FILE" 2>/dev/null; then
    ASSET_HASH=$(grep "^${id} " "$ASSET_HASH_FILE" | cut -d' ' -f2)
  fi
  COMBINED="${HTML_HASH}_${ASSET_HASH}"

  # ── Skip if nothing changed ────────────────────────────────
  if [[ -f "$hash_file" ]] && [[ "$(cat "$hash_file")" == "$COMBINED" ]]; then
    rm -f "$TMP_HTML"
    echo "skipped" > "$JOBS_DIR/${id}.status"
    echo "{\"id\": \"$id\", \"name\": \"$name\", \"folder\": \"$folder_name\"}" > "$JOBS_DIR/${id}.json"
    return 0
  fi

  # ── Log ────────────────────────────────────────────────────
  if [[ -d "$game_dir" ]]; then
    echo "[~] Updated: $folder_name"
    echo "updated" > "$JOBS_DIR/${id}.status"
  else
    echo "[+] New: $name (id=$id) → $folder_name"
    echo "new" > "$JOBS_DIR/${id}.status"
  fi

  mkdir -p "$game_dir"

  # Remove old compressed files
  find "$game_dir" -type f -name "*.gz" -delete 2>/dev/null || true

  # Place new HTML
  mv "$TMP_HTML" "$file"

  # ── Copy assets ────────────────────────────────────────────
  local src="$ASSETS_DIR/$id"
  if [[ -d "$src" ]]; then
    echo "    ↳ assets for id $id"
    find "$src" -mindepth 1 -maxdepth 1 \
      ! -name "index.html" ! -name "cover.png" \
      -exec cp -a {} "$game_dir/" \;

    sed -i 's|<base href="[^"]*">|<base href="./">|gi' "$file"

  fi

  # ── Download cover image ───────────────────────────────────
  if [[ ! -f "$game_dir/cover.png" ]]; then
    curl -fsSL "$COVERS_CDN/${id}.png" -o "$game_dir/cover.png" 2>/dev/null || true
  fi

  # Save hash
  echo "$COMBINED" > "$hash_file"

  echo "{\"id\": \"$id\", \"name\": \"$name\", \"folder\": \"$folder_name\"}" > "$JOBS_DIR/${id}.json"
}

export -f process_game

# ── Launch parallel workers using a job pool ─────────────────
RUNNING=0
while IFS= read -r entry; do
  # Spawn worker in background
  process_game "$entry" "$OUT_DIR" "$ASSETS_DIR" "$HTML_BASE" "$COVERS_CDN" "$JOBS_DIR" "$MAX_RETRIES" &

  RUNNING=$((RUNNING + 1))
  # Throttle: wait for one to finish when pool is full
  if [[ $RUNNING -ge $JOBS ]]; then
    wait -n 2>/dev/null || true
    RUNNING=$((RUNNING - 1))
  fi
done < <(jq -c '.[]' "$TMP_JSON")

# Wait for remaining workers
wait

# ── Collect results ──────────────────────────────────────────
SKIPPED=0; UPDATED=0; NEW_GAMES=0; FAILED=0
for sf in "$JOBS_DIR"/*.status; do
  [[ -f "$sf" ]] || continue
  case "$(cat "$sf")" in
    skipped)  SKIPPED=$((SKIPPED + 1)) ;;
    updated)  UPDATED=$((UPDATED + 1)) ;;
    new)      NEW_GAMES=$((NEW_GAMES + 1)) ;;
    failed)   FAILED=$((FAILED + 1)) ;;
  esac
done

# Merge manifest entries
GAMES_TMP="$JOBS_DIR/_manifest"
cat "$JOBS_DIR"/*.json > "$GAMES_TMP" 2>/dev/null || true

# ============================================================
#  Step 4: Cleanup stale compressed leftovers
# ============================================================
echo ""
echo "[*] Cleaning up stale compressed files…"
CLEANED=0
while IFS= read -r -d '' f; do
  rm -f "$f"
  CLEANED=$((CLEANED + 1))
done < <(find "$OUT_DIR" -mindepth 2 -maxdepth 5 -type f -name "*.gz" -print0 2>/dev/null)
[[ $CLEANED -gt 0 ]] && echo "    Removed $CLEANED old .gz files" || echo "    No .gz files found"

# ============================================================
#  Step 5: Build games.json manifest
# ============================================================
if [[ -f "$GAMES_TMP" && -s "$GAMES_TMP" ]]; then
  jq -s '.' "$GAMES_TMP" > "$MANIFEST"
  echo ""
  echo "[✓] Manifest: $(jq length "$MANIFEST") games"
else
  echo "[!] No games recorded"
  echo "[]" > "$MANIFEST"
fi

# Clean up empty dirs
find "$OUT_DIR" -maxdepth 1 -type d -empty -delete 2>/dev/null || true

echo ""
echo "════════════════════════════════════════"
echo "  ✓ DONE  ($JOBS parallel workers)"
echo "  New: $NEW_GAMES  Updated: $UPDATED  Skipped: $SKIPPED  Failed: $FAILED"
echo "  Games: $OUT_DIR"
echo "  Manifest: $MANIFEST"
echo "════════════════════════════════════════"
