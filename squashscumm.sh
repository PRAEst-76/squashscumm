#!/bin/bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_NAME="squashscumm.conf"

find_config() {

    if [ $# -gt 0 ] && [ -n "${1:-}" ]; then
        [ -f "$1" ] && {
            echo "$1"
            return 0
        }

        echo "Specified config not found: $1" >&2
        exit 1
    fi

    [ -f "$SCRIPT_DIR/$CONFIG_NAME" ] && {
        echo "$SCRIPT_DIR/$CONFIG_NAME"
        return 0
    }

    if [ -n "${XDG_CONFIG_HOME:-}" ] &&
       [ -f "$XDG_CONFIG_HOME/squashscumm/$CONFIG_NAME" ]; then
        echo "$XDG_CONFIG_HOME/squashscumm/$CONFIG_NAME"
        return 0
    fi

    if [ -f "$HOME/.config/squashscumm/$CONFIG_NAME" ]; then
        echo "$HOME/.config/squashscumm/$CONFIG_NAME"
        return 0
    fi

    if [ -f "/etc/$CONFIG_NAME" ]; then
        echo "/etc/$CONFIG_NAME"
        return 0
    fi

    return 1
}

CONFIG_FILE="$(find_config "${1:-}")"

if [ -z "$CONFIG_FILE" ]; then
    echo "No configuration file found."
    exit 1
fi

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

mkdir -p "$OUTPUT_DIR"
mkdir -p "$BACKUP_DIR"
touch "$MANIFEST_FILE"

get_saved_choice() {
    local game="$1"

    grep -F "^${game}|" "$MANIFEST_FILE" 2>/dev/null |
        tail -n1 |
        cut -d'|' -f2-
}

save_choice() {
    local game="$1"
    local file="$2"

    grep -v -F "^${game}|" "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp" 2>/dev/null || true
    mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"

    echo "${game}|${file}" >> "$MANIFEST_FILE"
}

SELECTED_FILE=""

choose_scummvm_file() {

    local game="$1"
    shift

    local files=("$@")
    local saved

    SELECTED_FILE=""

    saved="$(get_saved_choice "$game")"

    if [ -n "$saved" ]; then
        for file in "${files[@]}"; do
            if [ "$(basename "$file")" = "$saved" ]; then
                echo "  Using saved selection: $saved"
                SELECTED_FILE="$file"
                return 0
            fi
        done
    fi

    echo
    echo "Multiple .scummvm files found for $game:"
    echo

    for i in "${!files[@]}"; do
        printf "  %d) %s\n" \
            $((i + 1)) \
            "$(basename "${files[$i]}")"
    done

    echo

    while true; do

        read -rp \
            "Select file [1-${#files[@]}] (default 1): " \
            CHOICE < /dev/tty

        CHOICE="${CHOICE:-1}"

        if [[ "$CHOICE" =~ ^[0-9]+$ ]] &&
           (( CHOICE >= 1 && CHOICE <= ${#files[@]} ))
        then
            break
        fi

        echo "Invalid selection."
    done

    SELECTED_FILE="${files[$((CHOICE - 1))]}"

    save_choice "$game" "$(basename "$SELECTED_FILE")"

    echo
    echo "  Selected: $(basename "$SELECTED_FILE")"
}

resolve_output_file() {

    local output="$1"

    while [ -e "$output" ]; do

        echo
        echo "Output already exists:"
        echo "  $output"
        echo

        read -rp "[S]kip, [O]verwrite, [R]ename? " ACTION < /dev/tty

        case "${ACTION^^}" in
            S)
                return 1
                ;;

            O)
                rm -f "$output"
                break
                ;;

            R)
                read -rp "New filename: " NEWNAME < /dev/tty
                output="$OUTPUT_DIR/${NEWNAME}.squashfs"
                ;;
        esac
    done

    RESOLVED_OUTPUT_FILE="$output"
    return 0
}

while IFS= read -r GAME_DIR; do

    GAME="$(basename "$GAME_DIR")"

    echo
    echo "Processing: $GAME"

    mapfile -t SCUMMVM_FILES < <(
        find "$GAME_DIR" -maxdepth 1 -type f -name "*.scummvm" | sort
    )

    if [ "${#SCUMMVM_FILES[@]}" -eq 0 ]; then
        echo "  No .scummvm file found. Skipping."
        continue
    fi

    if [ "${#SCUMMVM_FILES[@]}" -eq 1 ]; then
        CHOSEN_FILE="${SCUMMVM_FILES[0]}"
        echo "  Selected: $(basename "$CHOSEN_FILE")"
    else
        choose_scummvm_file "$GAME" "${SCUMMVM_FILES[@]}"
        CHOSEN_FILE="$SELECTED_FILE"
    fi

    GAME_NAME="$(basename "$CHOSEN_FILE" .scummvm)"
    OUTPUT_FILE="$OUTPUT_DIR/${GAME_NAME}.squashfs"

    resolve_output_file "$OUTPUT_FILE" || {
        echo "  Skipped."
        continue
    }

    OUTPUT_FILE="$RESOLVED_OUTPUT_FILE"

    echo "  Creating:"
    echo "  $OUTPUT_FILE"

    if mksquashfs \
        "$GAME_DIR" \
        "$OUTPUT_FILE" \
        ${MKSQUASHFS_OPTS:-}
    then

        DEST="$BACKUP_DIR/$GAME"

        if [ -e "$DEST" ]; then
            DEST="${DEST}-$(date +%Y%m%d-%H%M%S)"
        fi

        mv "$GAME_DIR" "$DEST"

        echo "  Success."
        echo "  Moved to:"
        echo "  $DEST"

    else
        echo "  mksquashfs failed."
    fi

done < <(
    find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d | sort
)

echo
echo "Finished."