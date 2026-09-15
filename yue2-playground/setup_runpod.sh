#!/usr/bin/env bash
# Bootstrap YuE2 on a fresh RunPod pod (or any Ubuntu box with an NVIDIA GPU).
#
#   bash setup_runpod.sh            # install runtime + models + Claude Code skill
#   bash setup_runpod.sh --no-song  # same, but skip the first test song
#
# Everything lives under $WORKDIR (default /workspace, RunPod's persistent volume),
# so a pod restart does not lose the venv or the ~10 GB of weights.
set -euo pipefail

WORKDIR="${WORKDIR:-/workspace}"
YUE_DIR="$WORKDIR/YuE"
PLAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HF_HOME="${HF_HOME:-$WORKDIR/hf}"
export HF_HUB_ENABLE_HF_TRANSFER=1
RUN_SONG=1
[[ "${1:-}" == "--no-song" ]] && RUN_SONG=0

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

log "GPU check"
if ! command -v nvidia-smi >/dev/null; then
  echo "nvidia-smi not found: this is not a GPU pod." >&2; exit 1
fi
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
echo "driver $DRIVER"
# Blackwell (RTX 5090 / PRO 6000) needs driver >= 570 (CUDA 12.8). Fail fast, before downloading 13 GB.
if [[ "$GPU_NAME" == *5090* || "$GPU_NAME" == *"PRO 6000"* ]] && (( ${DRIVER%%.*} < 570 )); then
  echo "ERROR: $GPU_NAME with host driver $DRIVER (<570). This pod cannot run Blackwell CUDA kernels; recreate the pod in another DC." >&2
  exit 1
fi
VRAM_MIB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
if (( VRAM_MIB < 23000 )); then
  echo "WARNING: <24 GB VRAM. YuE2 officially wants 24 GB. play.sh will pass --budget/--offload-ar, expect it to be slower or to OOM." >&2
fi

log "System packages (git, ffmpeg, node for Claude Code)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git ffmpeg curl ca-certificates libsndfile1 >/dev/null
if ! command -v node >/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
  apt-get install -y -qq nodejs >/dev/null
fi

log "uv (gives us Python 3.12 regardless of the pod image)"
if ! command -v uv >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
fi

log "Clone YuE2"
if [[ -d "$YUE_DIR/.git" ]]; then
  git -C "$YUE_DIR" pull --ff-only
else
  git clone https://github.com/multimodal-art-projection/YuE.git "$YUE_DIR"
fi
git -C "$YUE_DIR" rev-parse HEAD > "$WORKDIR/yue2-commit.txt"

log "Python 3.12 venv + yue2-infer"
cd "$YUE_DIR"
[[ -d .venv ]] || uv venv --python 3.12 .venv
# torch==2.10.0 is pinned by the project; PyPI wheels ship CUDA, no extra index needed.
uv pip install --python .venv/bin/python . hf_transfer
ln -sfn "$YUE_DIR/.venv" "$PLAY_DIR/.venv-yue2"

log "Download weights (public, CC BY-NC 4.0). Set HF_TOKEN if HF asks for a login."
.venv/bin/hf download m-a-p/YuE2-3B  >/dev/null
.venv/bin/hf download m-a-p/YuE2-Vae >/dev/null

log "Environment doctor"
.venv/bin/yue2 doctor || true

log "Claude Code + yue2-music skill"
if ! command -v claude >/dev/null; then
  npm install -g @anthropic-ai/claude-code >/dev/null
fi
mkdir -p "$HOME/.claude/skills"
rm -rf "$HOME/.claude/skills/yue2-music"
cp -r "$YUE_DIR/skills/yue2-music" "$HOME/.claude/skills/yue2-music"
echo "skill installed at ~/.claude/skills/yue2-music (run 'claude' in $PLAY_DIR, then 'claude auth login' if needed)"

if (( RUN_SONG )); then
  log "First song (neon_garage, cot=full). Takes a few minutes on a 24 GB card."
  cd "$PLAY_DIR"
  bash play.sh generate prompts/neon_garage.json first-song
fi

log "Done. Next: cd $PLAY_DIR && bash play.sh help"
