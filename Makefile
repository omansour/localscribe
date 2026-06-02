# voice_rec — batch transcription with diarization and voice recognition
#
# Common usage:
#   make setup                              # install deps + download models
#   make enroll NAME="Me" FILES="enroll/me_1.wav enroll/me_2.wav"
#   make list
#   make transcribe FILE=audio/meeting.m4a
#   make transcribe FILE=audio/meeting.m4a SPEAKERS=3
#   make clean

RUN := uv run --no-sync python -m voice_rec

# Overridable variables
NAME     ?=
FILES    ?=
FILE     ?=
SPEAKERS ?= -1
OUT      ?=
DEVICE   ?= :default

# LANG is also a standard shell environment variable (the locale, e.g.
# "fr_FR.UTF-8"). We only honor it when set explicitly on the make command
# line (make transcribe ... LANG=fr); a value inherited from the environment
# is ignored so it never accidentally switches the ASR backend.
ifeq ($(origin LANG),command line)
LANG_FLAG := --language $(LANG)
else
LANG_FLAG :=
endif

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@echo "voice_rec — available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make enroll NAME=\"Me\" FILES=\"enroll/me_1.wav enroll/me_2.wav\""
	@echo "  make transcribe FILE=audio/meeting.m4a SPEAKERS=2"

.PHONY: install
install: ## Install Python dependencies (uv sync)
	uv sync

.PHONY: models
models: ## Download diarization / voiceprint models
	./models/download_models.sh

.PHONY: setup
setup: install models ## Full setup: install deps + download models
	@echo "Setup complete. Next: make enroll NAME=\"Me\" FILES=\"enroll/me_1.wav\""

.PHONY: enroll
enroll: ## Enroll a voice: NAME="Me" FILES="enroll/a.wav enroll/b.wav"
	@test -n '$(NAME)'  || (echo "ERROR: set NAME, e.g. NAME=\"Me\""; exit 1)
	@test -n '$(FILES)' || (echo "ERROR: set FILES, e.g. FILES=\"enroll/me_1.wav\""; exit 1)
	$(RUN) enroll --name '$(NAME)' $(FILES)

.PHONY: list
list: ## List enrolled voiceprints
	$(RUN) list

.PHONY: devices
devices: ## List available audio input devices (for DEVICE=...)
	@ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
		| sed -n '/audio devices/,/^$$/p' || true

.PHONY: record
record: ## Record from mic: [OUT=audio/x.wav] [DEVICE=:3]  (press q to stop)
	$(eval OUT := $(or $(OUT),audio/rec_$(shell date +%Y%m%d_%H%M%S).wav))
	@command -v ffmpeg >/dev/null || (echo "ERROR: ffmpeg not found (brew install ffmpeg)"; exit 1)
	@mkdir -p $(dir $(OUT))
	@echo "Recording from device '$(DEVICE)' -> $(OUT)"
	@echo "Speak now. Press 'q' to stop (do NOT use Ctrl+C)."
	ffmpeg -hide_banner -f avfoundation -i "$(DEVICE)" -ac 1 -ar 16000 -sample_fmt s16 -y "$(OUT)"
	@echo "Saved: $(OUT)"

.PHONY: transcribe
transcribe: ## Transcribe a file: FILE=audio/x.m4a [SPEAKERS=N] [LANG=fr]
	@test -n '$(FILE)' || (echo "ERROR: set FILE, e.g. FILE=audio/meeting.m4a"; exit 1)
	@test -f '$(FILE)' || { \
		echo "ERROR: file not found: $(FILE)"; \
		echo "Available files in audio/:"; \
		ls -1 audio/ 2>/dev/null | sed 's|^|  - audio/|' || true; \
		exit 1; \
	}
	$(RUN) transcribe '$(FILE)' --speakers $(SPEAKERS) $(LANG_FLAG)

.PHONY: clean
clean: ## Remove generated transcriptions and audio files
	@echo "This will delete output/*.md, enroll/* and audio/*"
	@read -p "Continue? [y/N] " ans && [ "$$ans" = "y" ] || (echo "Aborted."; exit 1)
	@$(MAKE) --no-print-directory _clean

.PHONY: _clean
_clean:
	rm -f output/*.md
	rm -f audio/*
	rm -f enroll/*

.PHONY: clean-all
clean-all: ## Remove venv, downloaded models and voiceprints (full reset)
	@echo "This will delete .venv, downloaded models, voiceprints, audio/*, enroll/* and output/*.md"
	@read -p "Continue? [y/N] " ans && [ "$$ans" = "y" ] || (echo "Aborted."; exit 1)
	@$(MAKE) --no-print-directory _clean
	rm -rf .venv models/sherpa-onnx-pyannote-segmentation-3-0 models/nemo_en_titanet_small.onnx personas/voiceprints.npz
	@echo "Full reset done. Run 'make setup' to reinstall."
