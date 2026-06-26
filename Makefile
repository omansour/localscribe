# localscribe — batch transcription with diarization and voice recognition
#
# Common usage:
#   make setup                              # install deps + download models
#   make enroll NAME="Me" FILES="enroll/me_1.wav enroll/me_2.wav"
#   make list
#   make transcribe FILE=audio/meeting.m4a
#   make transcribe FILE=audio/meeting.m4a SPEAKERS=3
#   make clean

RUN := uv run --no-sync python -m localscribe

# Overridable variables
NAME     ?=
FILES    ?=
FILE     ?=
SPEAKERS ?= -1
OUT      ?=
DEVICE   ?= default

# macOS menu bar recorder app (macos/). Building needs full Xcode; override
# DEVELOPER_DIR if Xcode lives elsewhere than /Applications/Xcode.app.
# The build output MUST live outside this repo: ~/Documents is synced by iCloud
# Drive, which stamps files with extended attributes (com.apple.FinderInfo /
# fileprovider) that make codesign fail ("detritus not allowed").
XCODE_PROJECT := macos/LocalScribeRecorder/LocalScribeRecorder.xcodeproj
APP_BUILD_DIR := $(HOME)/Library/Caches/LocalScribeRecorder-build
APP_BUNDLE    := $(APP_BUILD_DIR)/Build/Products/Release/LocalScribeRecorder.app
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

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
	@echo "localscribe — available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make enroll NAME=\"Me\" FILES=\"enroll/me_1.wav enroll/me_2.wav\""
	@echo "  make transcribe FILE=audio/meeting.m4a SPEAKERS=2"

.PHONY: check
check: ## Check that all system requirements are met
	@echo "Checking system requirements..."
	@errors=0; \
	arch=$$(uname -m); \
	if [ "$$arch" != "arm64" ]; then \
		echo "  [FAIL] Architecture: $$arch (need arm64 / Apple Silicon)"; errors=$$((errors+1)); \
	else \
		echo "  [ OK ] Architecture: $$arch"; \
	fi; \
	if ! command -v ffmpeg >/dev/null 2>&1; then \
		echo "  [FAIL] ffmpeg not found (brew install ffmpeg)"; errors=$$((errors+1)); \
	else \
		echo "  [ OK ] ffmpeg: $$(ffmpeg -version 2>&1 | head -1)"; \
	fi; \
	if ! command -v sox >/dev/null 2>&1; then \
		echo "  [WARN] sox not found — needed for 'make record' (brew install sox)"; \
	else \
		echo "  [ OK ] sox: $$(sox --version 2>&1 | head -1)"; \
	fi; \
	if ! command -v uv >/dev/null 2>&1; then \
		echo "  [FAIL] uv not found (see https://docs.astral.sh/uv/)"; errors=$$((errors+1)); \
	else \
		echo "  [ OK ] uv: $$(uv --version)"; \
	fi; \
	if [ ! -d .venv ]; then \
		echo "  [WARN] .venv not found — run: make install"; \
	else \
		pyver=$$(uv run --no-sync python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null); \
		major=$$(echo $$pyver | cut -d. -f1); \
		minor=$$(echo $$pyver | cut -d. -f2); \
		if [ "$$major" -lt 3 ] || { [ "$$major" -eq 3 ] && [ "$$minor" -lt 11 ]; }; then \
			echo "  [FAIL] Python $$pyver (need ≥ 3.11)"; errors=$$((errors+1)); \
		else \
			echo "  [ OK ] Python $$pyver"; \
		fi; \
	fi; \
	seg=models/sherpa-onnx-pyannote-segmentation-3-0; \
	emb=models/nemo_en_titanet_small.onnx; \
	if [ ! -d "$$seg" ] || [ ! -f "$$emb" ]; then \
		echo "  [WARN] Diarization models not found — run: make models"; \
	else \
		echo "  [ OK ] Diarization models present"; \
	fi; \
	echo ""; \
	if [ $$errors -eq 0 ]; then \
		echo "All checks passed."; \
	else \
		echo "$$errors check(s) failed. Fix the issues above, then run 'make setup'."; \
		exit 1; \
	fi

.PHONY: install
install: ## Install Python dependencies (uv sync)
	uv sync

.PHONY: models
models: ## Download diarization / voiceprint models
	./models/download_models.sh

.PHONY: sox
sox: ## Ensure SoX is installed (needed for 'make record')
	@if command -v sox >/dev/null 2>&1; then \
		echo "  [ OK ] sox already installed"; \
	elif command -v brew >/dev/null 2>&1; then \
		echo "Installing sox via Homebrew (needed for 'make record')..."; brew install sox; \
	else \
		echo "  [WARN] sox missing and Homebrew unavailable — install sox manually for 'make record'"; \
	fi

.PHONY: setup
setup: install models sox ## Full setup: install deps + download models + sox
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
devices: ## List audio input devices (use the NAME shown as DEVICE="...")
	@ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
		| sed -n '/audio devices/,/^$$/p' || true

.PHONY: record
record: ## Record mic via SoX: [OUT=audio/x.wav] [DEVICE="Mic Name"]  (press q to stop)
	$(eval OUT := $(or $(OUT),audio/rec_$(shell date +%Y%m%d_%H%M%S).wav))
	@command -v sox >/dev/null || (echo "ERROR: sox not found (brew install sox)"; exit 1)
	@mkdir -p $(dir $(OUT))
	@echo "Recording from device '$(DEVICE)' -> $(OUT)"
	@echo "Speak now. Press 'q' to stop (Ctrl+C also works)."
	@# SoX captures via CoreAudio (negotiates the device's native rate) and
	@# resamples offline to 16 kHz mono, avoiding ffmpeg/avfoundation's
	@# real-time sample-rate bug (crackle / sped-up audio). It runs in the
	@# background so we can stop it on 'q' by sending SIGINT, which makes SoX
	@# finalize the WAV header cleanly (same as Ctrl+C).
	@bash -c 'if [ "$(DEVICE)" = "default" ]; then \
	    sox -d -b 16 -c 1 -r 16000 "$(OUT)" & \
	  else \
	    sox -t coreaudio "$(DEVICE)" -b 16 -c 1 -r 16000 "$(OUT)" & \
	  fi; \
	  pid=$$!; \
	  if [ -t 0 ]; then \
	    while :; do read -rsn1 k; [ "$$k" = "q" ] && break; done; \
	    kill -INT $$pid 2>/dev/null || true; \
	  fi; \
	  wait $$pid 2>/dev/null || true'
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

.PHONY: app-build
app-build: ## Build the macOS recorder app (needs full Xcode)
	@test -d "$(DEVELOPER_DIR)" || { \
		echo "ERROR: full Xcode not found at $(DEVELOPER_DIR)."; \
		echo "Install Xcode from the App Store, or pass DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer."; \
		exit 1; \
	}
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -project $(XCODE_PROJECT) \
		-scheme LocalScribeRecorder -configuration Release \
		-derivedDataPath $(APP_BUILD_DIR) build

.PHONY: app-run
app-run: app-build ## Build and launch the macOS recorder app
	open "$(APP_BUNDLE)"

.PHONY: app-install
app-install: app-build ## Install the recorder app into /Applications
	rm -rf "/Applications/LocalScribeRecorder.app"
	cp -R "$(APP_BUNDLE)" /Applications/
	@echo "Installed: /Applications/LocalScribeRecorder.app"
	open "/Applications/LocalScribeRecorder.app"

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
