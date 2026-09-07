#!/usr/bin/env bash
# Convert an asciinema .cast recording to GIF (via containerized agg) and MP4 (via ffmpeg).
#
# Usage:
#   ./scripts/convert-recording.sh recordings/demo.cast
#   ./scripts/convert-recording.sh --latest
#
# Environment variables:
#   AGG_THEME      agg color theme          (default: github-dark)
#   AGG_FONT_SIZE  agg font size in px      (default: 16)
#   AGG_SPEED      agg playback speed       (default: 1)
#   FFMPEG_BITRATE video bitrate             (default: 5M)
#   BLACK_FIX_COLOR   ANSI replacement for bold-black text  (default: 37 = white)
#   OBFUSCATE_USER    replace this username in recording     (default: current $USER)
#   OBFUSCATE_HOST    replace this hostname in recording     (default: current hostname)
#   OBFUSCATE_USER_TO replacement username                   (default: demo)
#   OBFUSCATE_HOST_TO replacement hostname                   (default: workstation)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

AGG_THEME="${AGG_THEME:-github-dark}"
AGG_FONT_SIZE="${AGG_FONT_SIZE:-16}"
AGG_SPEED="${AGG_SPEED:-1}"
FFMPEG_BITRATE="${FFMPEG_BITRATE:-5M}"
BLACK_FIX_COLOR="${BLACK_FIX_COLOR:-37}"
OBFUSCATE_USER="${OBFUSCATE_USER:-${USER}}"
OBFUSCATE_HOST="${OBFUSCATE_HOST:-$(hostname -s)}"
OBFUSCATE_USER_TO="${OBFUSCATE_USER_TO:-demo}"
OBFUSCATE_HOST_TO="${OBFUSCATE_HOST_TO:-workstation}"

for cmd in podman ffmpeg; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "Error: ${cmd} is not installed." >&2
    echo "Install it with:  sudo dnf install ${cmd}" >&2
    exit 1
  fi
done

usage() {
  cat <<'EOF' >&2
Usage: ./scripts/convert-recording.sh <recording.cast | --latest>

  <file.cast>  Path to an asciinema recording
  --latest     Auto-select the newest .cast file in recordings/
EOF
  exit 1
}

[[ $# -ge 1 ]] || usage

if [[ "$1" == "--latest" ]]; then
  CAST_FILE="$(find "${REPO_ROOT}/recordings" -maxdepth 1 -name '*.cast' -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -n1 | cut -d' ' -f2-)"
  if [[ -z "${CAST_FILE}" ]]; then
    echo "Error: no .cast files found in recordings/" >&2
    exit 1
  fi
  echo "Selected: ${CAST_FILE}"
else
  CAST_FILE="$1"
fi

if [[ ! -f "${CAST_FILE}" ]]; then
  echo "Error: file not found: ${CAST_FILE}" >&2
  exit 1
fi

BASENAME="${CAST_FILE%.cast}"
GIF_FILE="${BASENAME}.gif"
MP4_FILE="${BASENAME}.mp4"

# --- Fix unreadable colors in the .cast file ---

PATCHED_CAST="${BASENAME}.patched.cast"
echo "==> Patching bold-black text (30m) -> ${BLACK_FIX_COLOR}m"
sed "s/\\\\u001b\[30m\\\\u001b\[1m/\\\\u001b[${BLACK_FIX_COLOR}m\\\\u001b[1m/g" \
  "${CAST_FILE}" > "${PATCHED_CAST}"

echo "==> Obfuscating: ${OBFUSCATE_USER} -> ${OBFUSCATE_USER_TO}, ${OBFUSCATE_HOST} -> ${OBFUSCATE_HOST_TO}"
sed -i \
  -e "s/${OBFUSCATE_HOST}/${OBFUSCATE_HOST_TO}/g" \
  -e "s/${OBFUSCATE_USER}/${OBFUSCATE_USER_TO}/g" \
  "${PATCHED_CAST}"

# --- .cast -> .gif (containerized agg) ---

CAST_REL="$(realpath --relative-to="${REPO_ROOT}" "${PATCHED_CAST}")"
GIF_REL="$(realpath --relative-to="${REPO_ROOT}" "${GIF_FILE}")"

echo "==> Converting .cast to .gif (theme: ${AGG_THEME}, font: ${AGG_FONT_SIZE}px, speed: ${AGG_SPEED}x)"

podman run --rm --security-opt label=disable \
  -v "${REPO_ROOT}:/data" \
  ghcr.io/asciinema/agg \
  --theme "${AGG_THEME}" \
  --font-size "${AGG_FONT_SIZE}" \
  --speed "${AGG_SPEED}" \
  "${CAST_REL}" "${GIF_REL}"

echo "    GIF: ${GIF_FILE}"

# --- .gif -> .mp4 (ffmpeg) ---

echo "==> Converting .gif to .mp4 (bitrate: ${FFMPEG_BITRATE})"

ffmpeg -y -i "${GIF_FILE}" \
  -vf "fps=24,scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -c:v mpeg4 -pix_fmt yuv420p -b:v "${FFMPEG_BITRATE}" \
  -movflags +faststart \
  "${MP4_FILE}"

echo "    MP4: ${MP4_FILE}"
rm -f "${PATCHED_CAST}"

echo
echo "Done. Files:"
echo "  GIF: ${GIF_FILE}"
echo "  MP4: ${MP4_FILE}"
