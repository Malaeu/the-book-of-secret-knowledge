#!/usr/bin/env bash
# Thin wrapper around the yue2-music skill scripts so every run lands in outputs/<name>
# with all artifacts (audio.flac, score.abc, semantic.npy, latent.npy, result.json).
#
#   bash play.sh generate prompts/neon_garage.json first-song [--cot full|melody|off] [--abc-file x.abc]
#   bash play.sh modes    prompts/neon_garage.json modes          # full + melody + off in one go
#   bash play.sh plan     prompts/neon_garage.json plan           # only the ABC score, no audio
#   bash play.sh inspect  outputs/plan/score.abc
#   bash play.sh compare  outputs/plan/score.abc edits/jazz.abc [--voices Vocal]
#   bash play.sh strip-chords in.abc out.abc
#   bash play.sh listen   outputs/first-song outputs/jazz         # HTML A/B page in outputs/compare-<ts>
#   bash play.sh doctor
set -euo pipefail

PLAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-$([[ -d /workspace ]] && echo /workspace || echo "$PLAY_DIR/..")}"
YUE_DIR="${YUE_DIR:-$WORKDIR/YuE}"
SCRIPTS="$YUE_DIR/skills/yue2-music/scripts"
PY="$YUE_DIR/.venv/bin/python"
export HF_HOME="${HF_HOME:-$WORKDIR/hf}"
OUT="$PLAY_DIR/outputs"
mkdir -p "$OUT"

[[ -x "$PY" ]] || { echo "No venv at $PY. Run setup_runpod.sh first." >&2; exit 2; }

# YuE2 wants 24 GB; on smaller cards tell it the truth so it shrinks the VAE window
# instead of dying halfway through decode.
budget_flag() {
  local mib
  mib=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 24576)
  local gib=$(( mib / 1024 ))
  (( gib < 24 )) && echo "--memory-budget-gib $gib" || true
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  generate|plan|modes)
    action="$cmd"; [[ "$cmd" == "modes" ]] && action="all-modes"
    req="${1:?request.json}"; name="${2:?output name}"; shift 2
    dest="$OUT/$name"
    [[ -e "$dest" ]] && { echo "$dest exists. Pick a new name; every version is kept on purpose." >&2; exit 2; }
    cp "$req" "$OUT/.last-request.json"
    set -x
    "$PY" "$SCRIPTS/run_yue2.py" "$action" --request "$req" --output "$dest" $(budget_flag) "$@"
    set +x
    echo; echo "artifacts: $dest"; ls "$dest"
    ;;
  inspect)       "$PY" "$SCRIPTS/abc_tools.py" inspect "$@" ;;
  compare)       "$PY" "$SCRIPTS/abc_tools.py" compare "$@" ;;
  strip-chords)  "$PY" "$SCRIPTS/abc_tools.py" strip-chords "$@" ;;
  listen)
    dest="$OUT/compare-$(date +%Y%m%d-%H%M%S)"
    "$PY" "$SCRIPTS/listen.py" "$@" --output "$dest"
    echo "open $dest/index.html (scp the folder to your Mac, it is self-contained)"
    ;;
  decode)
    src="${1:?source dir}"; name="${2:?output name}"
    "$PY" "$SCRIPTS/run_yue2.py" decode --source "$src" --output "$OUT/$name" $(budget_flag)
    ;;
  doctor)        "$YUE_DIR/.venv/bin/yue2" doctor "$@" ;;
  help|*)        sed -n '2,13p' "$0" ;;
esac
