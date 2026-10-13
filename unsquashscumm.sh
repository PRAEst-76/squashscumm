#!/bin/bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_NAME="squashscumm.conf"

find_config() {
    if [ -n "${1:-}" ]; then
        if [ -f "$1" ]; then
            printf '%s\n' "$1"
            return 0
        fi
        echo "Specified config not found: $1" >&2
        return 1
    fi

    local candidates=(
        "$SCRIPT_DIR/$CONFIG_NAME"
        "${XDG_CONFIG_HOME:-$HOME/.config}/squashscumm/$CONFIG_NAME"
        "/etc/$CONFIG_NAME"
    )

    for config in "${candidates[@]}"; do
        if [ -f "$config" ]; then
            printf '%s\n' "$config"
            return 0
        fi
    done

    return 1
}

CONFIG_FILE="$(find_config "${1:-}")" || {
    echo "No configuration file found."
    echo "Pass the config path as the first argument if necessary."
    exit 1
}

echo "Using config: $CONFIG_FILE"

# shellcheck source=/dev/null
source "$CONFIG_FILE"

for VAR in SOURCE_DIR OUTPUT_DIR BACKUP_DIR; do
    if [ -z "${!VAR:-}" ]; then
        echo "Missing required config variable: $VAR"
        exit 1
    fi
done

MANIFEST_FILE="${MANIFEST_FILE:-$OUTPUT_DIR/.squashscumm_manifest}"

# Where to move archives after successful extraction.
ARCHIVE_BACKUP_DIR="${ARCHIVE_BACKUP_DIR:-$OUTPUT_DIR/backup}"

# Set to "yes" to move processed archives to ARCHIVE_BACKUP_DIR.
MOVE_ARCHIVES_TO_BACKUP="${MOVE_ARCHIVES_TO_BACKUP:-no}"

if ! command -v unsquashfs >/dev/null 2>&1; then
    echo "Error: unsquashfs is not installed."
    echo "On Linux Mint, install it with:"
    echo "  sudo apt install squashfs-tools"
    exit 1
fi

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Output directory does not exist: $OUTPUT_DIR"
    exit 1
fi

mkdir -p "$SOURCE_DIR" || exit 1

if [[ "${MOVE_ARCHIVES_TO_BACKUP,,}" == "yes" ]]; then
    mkdir -p "$ARCHIVE_BACKUP_DIR" || exit 1
fi

# Recover the original game folder name from the manifest, when possible.
# Manifest format: game-directory|selected-file.scummvm
restore_game_name() {
    local archive_name="$1"
    local saved_name=""

    if [ -f "$MANIFEST_FILE" ]; then
        saved_name="$(
            awk -F '|' -v file="${archive_name}.scummvm" \
                '$2 == file { name = $1 } END { print name }' \
                "$MANIFEST_FILE"
        )"
    fi

    if [ -n "$saved_name" ]; then
        printf '%s\n' "$saved_name"
    else
        printf '%s\n' "$archive_name"
    fi
}

resolve_destination() {
    local dest="$1"
    local action
    local newname

    while [ -e "$dest" ]; do
        echo
        echo "Destination already exists:"
        echo "  $dest"
        echo
        read -r -p "[S]kip, [O]verwrite, [R]ename? " action < /dev/tty || return 1

        case "${action^^}" in
            S)
                return 1
                ;;
            O)
                read -r -p "Delete this directory and replace it? Type YES to confirm: " \
                    action < /dev/tty || return 1

                if [ "$action" != "YES" ]; then
                    echo "Overwrite cancelled."
                    return 1
                fi

                if ! rm -rf -- "$dest"; then
                    echo "Could not remove destination."
                    return 1
                fi
                break
                ;;
            R)
                read -r -p "New directory name: " newname < /dev/tty || return 1

                if [ -z "$newname" ] || [ "$newname" = "." ] ||
                   [ "$newname" = ".." ] || [[ "$newname" == */* ]]; then
                    echo "Enter a valid directory name without slashes."
                    continue
                fi

                dest="$SOURCE_DIR/$newname"
                ;;
            *)
                echo "Please enter S, O, or R."
                ;;
        esac
    done

    RESOLVED_DEST="$dest"
    return 0
}

while IFS= read -r -d '' ARCHIVE; do
    ARCHIVE_NAME="$(basename "$ARCHIVE" .squashfs)"

    echo
    echo "Processing: $(basename "$ARCHIVE")"

    GAME="$(restore_game_name "$ARCHIVE_NAME")"
    DEST="$SOURCE_DIR/$GAME"

    echo "  Restore directory: $DEST"

    resolve_destination "$DEST" || {
        echo "  Skipped."
        continue
    }

    DEST="$RESOLVED_DEST"

    echo "  Extracting to: $DEST"

    # Extract to a temporary directory first, so a failed extraction
    # does not leave a partially restored game at the final destination.
    TEMP_DIR="$(mktemp -d "$SOURCE_DIR/.unsquashscumm.XXXXXXXX")" || {
        echo "  Could not create temporary directory."
        continue
    }

    if unsquashfs -f -d "$TEMP_DIR" "$ARCHIVE"; then
        if mv -- "$TEMP_DIR" "$DEST"; then
            echo "  Extraction successful."
        else
            echo "  Could not move extracted files to destination."
            rm -rf -- "$TEMP_DIR"
            continue
        fi
    else
        echo "  Extraction failed. Archive left untouched."
        rm -rf -- "$TEMP_DIR"
        continue
    fi

    if [[ "${MOVE_ARCHIVES_TO_BACKUP,,}" == "yes" ]]; then
        ARCHIVE_DEST="$ARCHIVE_BACKUP_DIR/$(basename "$ARCHIVE")"

        if [ -e "$ARCHIVE_DEST" ]; then
            ARCHIVE_DEST="${ARCHIVE_DEST%.squashfs}-$(date +%Y%m%d-%H%M%S).squashfs"
        fi

        if mv -- "$ARCHIVE" "$ARCHIVE_DEST"; then
            echo "  Archive moved to: $ARCHIVE_DEST"
        else
            echo "  Warning: extraction succeeded, but archive could not be moved."
        fi
    else
        echo "  Archive retained."
    fi

done < <(
    find "$OUTPUT_DIR" -maxdepth 1 -type f -name "*.squashfs" -print0 |
        sort -z
)

echo
echo "Finished."