#!/usr/bin/env bash
# Second stage: SheetSage2 (audio -> ABC score) for the mp3 -> cover workflow.
# Separate venv on purpose: SheetSage2 pins torch 2.8 / transformers 4.45 / numpy 1.24,
# YuE2 pins torch 2.10 / transformers 4.57 / numpy 2.2. They cannot share one env.
#
#   bash setup_cover.sh
set -euo pipefail

WORKDIR="${WORKDIR:-/workspace}"
MODELS="$WORKDIR/models"
VENV="$WORKDIR/.venv-sheetsage2"
export HF_HOME="${HF_HOME:-$WORKDIR/hf}"
export HF_HUB_ENABLE_HF_TRANSFER=1
export PATH="$HOME/.local/bin:$PATH"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

command -v uv >/dev/null || { curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null; }
command -v ffmpeg >/dev/null || { apt-get update -qq && apt-get install -y -qq ffmpeg >/dev/null; }

log "Python 3.11 venv for SheetSage2"
[[ -d "$VENV" ]] || uv venv --python 3.11 "$VENV"
uv pip install --python "$VENV/bin/python" "huggingface-hub==0.36.0" hf_transfer

log "Download SheetSage2 snapshot (pulls its MERT-v2-FullSong parent on first load)"
mkdir -p "$MODELS"
"$VENV/bin/hf" download m-a-p/SheetSage2 --local-dir "$MODELS/SheetSage2" >/dev/null

log "torch 2.8.0 (cu126) + SheetSage2 requirements"
uv pip install --python "$VENV/bin/python" torch==2.8.0 torchaudio==2.8.0 \
  --index-url https://download.pytorch.org/whl/cu126
uv pip install --python "$VENV/bin/python" -r "$MODELS/SheetSage2/requirements.txt"

log "Smoke test: import + melody_only support"
"$VENV/bin/python" - <<'PY'
import inspect, torch
from transformers import AutoModel
m = AutoModel.from_pretrained("/workspace/models/SheetSage2", trust_remote_code=True)
ok = "melody_only" in inspect.signature(m.transcribe).parameters
print("cuda:", torch.cuda.is_available(), "| melody_only supported:", ok)
assert ok, "this SheetSage2 snapshot lacks melody_only; re-download a newer revision"
PY

log "Done. Try: bash play.sh cover song.mp3 prompts/cover_template.json my-cover"
