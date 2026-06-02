#!/usr/bin/env bash
#
# Downloads the ONNX models needed for diarization (who spoke when) and
# speaker recognition (is this YOUR voice?).
#
# Parakeet (the transcription model) is NOT downloaded here: parakeet-mlx
# fetches it automatically from Hugging Face on first run.
#
set -euo pipefail

cd "$(dirname "$0")"

BASE_SEG="https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models"
BASE_EMB="https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models"

# 1) Speaker segmentation model (splits audio into speech turns)
if [ ! -d "sherpa-onnx-pyannote-segmentation-3-0" ]; then
  echo "==> Downloading segmentation model (pyannote 3.0)..."
  curl -L -o seg.tar.bz2 "${BASE_SEG}/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2"
  tar xf seg.tar.bz2
  rm seg.tar.bz2
else
  echo "==> Segmentation model already present, skipping."
fi

# 2) Voiceprint (embedding) model — NVIDIA TitaNet, multilingual, robust fr/en
if [ ! -f "nemo_en_titanet_small.onnx" ]; then
  echo "==> Downloading voiceprint model (NVIDIA TitaNet)..."
  curl -L -o nemo_en_titanet_small.onnx "${BASE_EMB}/nemo_en_titanet_small.onnx"
else
  echo "==> Voiceprint model already present, skipping."
fi

echo ""
echo "Models ready in: $(pwd)"
ls -lh sherpa-onnx-pyannote-segmentation-3-0/*.onnx nemo_en_titanet_small.onnx
