#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_DIR="$SCRIPT_DIR/godot"
GAMES_SOURCE_DIR="$GODOT_DIR/games"
GAMES_OUTPUT_DIR="$SCRIPT_DIR/../livestream-listener/public/games"
EXPORT_PRESETS="$GODOT_DIR/export_presets.cfg"
GODOT="${GODOT:-godot}"
FILTER_GAME="${1:-}"

if [[ -n "$FILTER_GAME" ]]; then
    if [[ ! -d "$GAMES_SOURCE_DIR/$FILTER_GAME" ]]; then
        echo "error: game '$FILTER_GAME' not found under $GAMES_SOURCE_DIR" >&2
        exit 1
    fi
    if [[ ! -f "$GAMES_SOURCE_DIR/$FILTER_GAME/manifest.json" ]]; then
        echo "error: '$FILTER_GAME' has no manifest.json" >&2
        exit 1
    fi
fi

# Restore export_presets.cfg if the script is interrupted mid-export
cleanup() {
    if [[ -f "${EXPORT_PRESETS}.bak" ]]; then
        mv "${EXPORT_PRESETS}.bak" "$EXPORT_PRESETS"
        echo "restored export_presets.cfg after error"
    fi
}
trap cleanup EXIT

exported=0

echo "[debug] GAMES_SOURCE_DIR=$GAMES_SOURCE_DIR"
echo "[debug] GAMES_OUTPUT_DIR=$GAMES_OUTPUT_DIR"
echo "[debug] EXPORT_PRESETS=$EXPORT_PRESETS"
echo "[debug] GODOT=$(command -v "$GODOT" 2>/dev/null || echo "NOT FOUND: $GODOT")"
echo "[debug] FILTER_GAME=${FILTER_GAME:-<none>}"
echo "[debug] scanning $GAMES_SOURCE_DIR ..."

for game_dir in "$GAMES_SOURCE_DIR"/*/; do
    echo "[debug] found entry: $game_dir"
    [[ -d "$game_dir" ]] || { echo "[debug]   skipping: not a directory"; continue; }
    game_name=$(basename "$game_dir")
    if [[ ! -f "$game_dir/manifest.json" ]]; then
        echo "[debug]   skipping $game_name: no manifest.json"
        continue
    fi

    if [[ -n "$FILTER_GAME" && "$FILTER_GAME" != "$game_name" ]]; then
        echo "[debug]   skipping $game_name: filtered out (looking for '$FILTER_GAME')"
        continue
    fi

    echo "==> $game_name"
    echo "[debug]   manifest.json found: $game_dir/manifest.json"

    output_dir="$GAMES_OUTPUT_DIR/$game_name"
    mkdir -p "$output_dir"
    echo "[debug]   output_dir=$output_dir"

    # Build sorted list of res:// resource paths, excluding Godot's internal .uid files
    export_files_arr=()
    while IFS= read -r file; do
        rel="${file#"$GODOT_DIR/"}"
        export_files_arr+=("\"res://$rel\"")
    done < <(find "$game_dir" -type f ! -name "*.uid" ! -name "*.blend1" | sort)

    echo "[debug]   export_files count: ${#export_files_arr[@]}"
    for f in "${export_files_arr[@]}"; do echo "[debug]     $f"; done

    export_files_str=$(printf '%s, ' "${export_files_arr[@]}")
    export_files_str="${export_files_str%, }"  # strip trailing ", "

    # Patch the minigame preset's export_files line in export_presets.cfg.
    # ENVIRON is used to pass the value through awk so shell quoting on the
    # double-quoted resource paths doesn't cause issues.
    cp "$EXPORT_PRESETS" "${EXPORT_PRESETS}.bak"
    EXPORT_FILES="$export_files_str" awk '
        BEGIN { in_minigame = 0; patched = 0 }
        /^\[preset\.[0-9]+\]/ { in_minigame = 0 }
        /^name="minigame"/    { in_minigame = 1 }
        in_minigame && /^export_files=/ {
            print "export_files=PackedStringArray(" ENVIRON["EXPORT_FILES"] ")"
            patched = 1
            next
        }
        { print }
        END { if (!patched) print "[debug] WARNING: minigame preset export_files line not found/patched" > "/dev/stderr" }
    ' "${EXPORT_PRESETS}.bak" > "$EXPORT_PRESETS"
    echo "[debug]   export_presets.cfg patched; verifying minigame export_files line:"
    awk '/^name="minigame"/{f=1} f && /^export_files=/{print substr($0,1,200); exit}' "$EXPORT_PRESETS" || true
    echo ""

    # Export only the PCK (no HTML/JS/WASM)
    bundle_path="$(cd "$output_dir" && pwd)/bundle.pck"
    echo "    exporting bundle..."
    echo "[debug]   running: $GODOT --headless --path $GODOT_DIR --export-pack minigame $bundle_path"
    "$GODOT" --headless --path "$GODOT_DIR" --export-pack "minigame" "$bundle_path"
    godot_exit=$?
    echo "[debug]   godot exit code: $godot_exit"

    # Restore preset right after export so it's clean for the next iteration
    mv "${EXPORT_PRESETS}.bak" "$EXPORT_PRESETS"

    if [[ -f "$bundle_path" ]]; then
        echo "[debug]   bundle.pck created: $(du -sh "$bundle_path" | cut -f1)"
    else
        echo "[debug]   ERROR: bundle.pck was NOT created at $bundle_path"
    fi

    # Compute SHA-256 of the bundle (cross-platform: Linux has sha256sum, macOS has shasum)
    if command -v sha256sum &>/dev/null; then
        bundle_hash=$(sha256sum "$bundle_path" | awk '{print $1}')
    else
        bundle_hash=$(shasum -a 256 "$bundle_path" | awk '{print $1}')
    fi
    echo "    hash: $bundle_hash"

    # Copy manifest.json to the output directory with the hash field added
    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data['pck_hash'] = sys.argv[2]
print(json.dumps(data, indent=2))
" "$game_dir/manifest.json" "$bundle_hash" > "$output_dir/manifest.json"

    echo "    -> $output_dir"
    (( exported++ )) || true
done

if [[ $exported -eq 0 ]]; then
    if [[ -n "$FILTER_GAME" ]]; then
        echo "error: no game named '$FILTER_GAME' with a manifest.json found" >&2
    else
        echo "error: no games with manifest.json found under $GAMES_SOURCE_DIR" >&2
    fi
    exit 1
fi

echo ""
echo "done. exported $exported game(s)."
