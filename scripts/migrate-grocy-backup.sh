#!/usr/bin/env bash
# ==============================================================================
# Grocy Add-on Migration Helper
#
# Extracts the Grocy database and storage from an old add-on backup,
# injects them into a new add-on backup, and produces a ready-to-upload
# backup .tar file for Home Assistant.
#
# Usage:
#   ./migrate-grocy-backup.sh \
#       --old-backup /path/to/old-grocy-backup.tar \
#       --new-backup /path/to/new-grocy-backup.tar \
#       --output /path/to/migrated-backup.tar
# ==============================================================================
set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

# ---- Helpers ----------------------------------------------------------------

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} --old-backup <file> --new-backup <file> --output <file>

Arguments:
  --old-backup   Path to the Home Assistant backup .tar containing the
                 ORIGINAL Grocy add-on (hassio-addons).
  --new-backup   Path to the Home Assistant backup .tar containing the
                 NEW Grocy add-on (lazytarget-homeassistant-apps).
  --output       Path for the resulting migrated backup .tar file.
  -h, --help     Show this help message.

Both backups should be partial backups that include only the Grocy add-on.
The old add-on should be stopped before creating its backup.
EOF
    exit "${1:-0}"
}

log()   { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
error() { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

cleanup() {
    if [[ -n "${WORK_DIR:-}" && -d "${WORK_DIR}" ]]; then
        log "Cleaning up temporary directory..."
        rm -rf "${WORK_DIR}"
    fi
}
trap cleanup EXIT

# ---- Parse arguments --------------------------------------------------------

OLD_BACKUP=""
NEW_BACKUP=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --old-backup) OLD_BACKUP="$2"; shift 2 ;;
        --new-backup) NEW_BACKUP="$2"; shift 2 ;;
        --output)     OUTPUT="$2";     shift 2 ;;
        -h|--help)    usage 0 ;;
        *)            error "Unknown argument: $1" ;;
    esac
done

[[ -n "${OLD_BACKUP}" ]] || { echo "Missing --old-backup"; usage 1; }
[[ -n "${NEW_BACKUP}" ]] || { echo "Missing --new-backup"; usage 1; }
[[ -n "${OUTPUT}" ]]     || { echo "Missing --output";     usage 1; }
[[ -f "${OLD_BACKUP}" ]] || error "Old backup not found: ${OLD_BACKUP}"
[[ -f "${NEW_BACKUP}" ]] || error "New backup not found: ${NEW_BACKUP}"

# Resolve output to an absolute path before we cd around
OUTPUT="$(cd "$(dirname "${OUTPUT}")" && pwd)/$(basename "${OUTPUT}")"

# ---- Set up working directory -----------------------------------------------

WORK_DIR="$(mktemp -d)"
log "Working directory: ${WORK_DIR}"

OLD_DIR="${WORK_DIR}/old"
NEW_DIR="${WORK_DIR}/new"
mkdir -p "${OLD_DIR}" "${NEW_DIR}"

# ---- Extract old backup and find the Grocy add-on archive -------------------

log "Extracting old backup..."
tar xf "${OLD_BACKUP}" -C "${OLD_DIR}"

OLD_ADDON_ARCHIVE="$(find "${OLD_DIR}" -maxdepth 1 -name '*_grocy.tar.gz' | head -n1)"
[[ -n "${OLD_ADDON_ARCHIVE}" ]] || error "Could not find a *_grocy.tar.gz in the old backup. Is this a Grocy add-on backup?"

log "Found old add-on archive: $(basename "${OLD_ADDON_ARCHIVE}")"

OLD_ADDON_DIR="${WORK_DIR}/old-addon"
mkdir -p "${OLD_ADDON_DIR}"
tar xzf "${OLD_ADDON_ARCHIVE}" -C "${OLD_ADDON_DIR}"

# Verify the database exists
OLD_DB="${OLD_ADDON_DIR}/data/grocy/grocy.db"
[[ -f "${OLD_DB}" ]] || error "grocy.db not found in old backup at data/grocy/grocy.db"
log "Found old Grocy database ($(du -h "${OLD_DB}" | cut -f1))"

# ---- Extract new backup and its add-on archive -----------------------------

log "Extracting new backup..."
tar xf "${NEW_BACKUP}" -C "${NEW_DIR}"

NEW_ADDON_ARCHIVE="$(find "${NEW_DIR}" -maxdepth 1 -name '*_grocy.tar.gz' | head -n1)"
[[ -n "${NEW_ADDON_ARCHIVE}" ]] || error "Could not find a *_grocy.tar.gz in the new backup. Is this a Grocy add-on backup?"

NEW_ADDON_ARCHIVE_NAME="$(basename "${NEW_ADDON_ARCHIVE}")"
log "Found new add-on archive: ${NEW_ADDON_ARCHIVE_NAME}"

NEW_ADDON_DIR="${WORK_DIR}/new-addon"
mkdir -p "${NEW_ADDON_DIR}"
tar xzf "${NEW_ADDON_ARCHIVE}" -C "${NEW_ADDON_DIR}"

# ---- Migrate data -----------------------------------------------------------

log "Copying Grocy database..."
cp "${OLD_DB}" "${NEW_ADDON_DIR}/data/grocy/grocy.db"

OLD_STORAGE="${OLD_ADDON_DIR}/data/grocy/storage"
if [[ -d "${OLD_STORAGE}" ]]; then
    log "Copying uploaded files (storage directory)..."
    cp -a "${OLD_STORAGE}" "${NEW_ADDON_DIR}/data/grocy/storage"
else
    log "No storage directory found in old backup (skipping)."
fi

# ---- Repackage --------------------------------------------------------------

log "Repackaging new add-on archive..."
(cd "${NEW_ADDON_DIR}" && tar czf "${NEW_DIR}/${NEW_ADDON_ARCHIVE_NAME}" .)

log "Repackaging final backup..."
(cd "${NEW_DIR}" && tar cf "${OUTPUT}" ./*.json ./*.tar.gz 2>/dev/null || tar cf "${OUTPUT}" ./*)

log ""
log "=========================================="
log " Migration complete!"
log "=========================================="
log ""
log " Output: ${OUTPUT}"
log ""
log " Next steps:"
log "   1. Upload this backup in Home Assistant:"
log "      Settings → System → Backups → ⋮ → Upload backup"
log "   2. Restore only the new Grocy add-on from this backup."
log "   3. Reconfigure your add-on settings (culture, currency,"
log "      features, tweaks, etc.) in the Configuration tab."
log "   4. Start the new Grocy add-on and verify your data."
log ""
