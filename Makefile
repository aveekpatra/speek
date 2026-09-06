# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/Speek-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build

.PHONY: all clean whisper setup build local signed dmg test check healthcheck help dev run

# Stable signed dev build: signed with your Apple Development cert so macOS
# permissions (Accessibility, Microphone) survive every rebuild — grant once.
#
# Your personal signing identity is kept OUT of the repo. Put your own values in an
# untracked Makefile.local (it overrides the placeholders below):
#   SIGN_IDENTITY := Apple Development: you@example.com (YOURTEAMID)
#   DEV_TEAM := YOURTEAMID
# Find your identity with:  security find-identity -v -p codesigning
SIGN_IDENTITY := Apple Development
DEV_TEAM :=
SIGNED_APP := /Applications/Speek.app
# Build under the bundle id the app's live data (transcripts, stats, streak,
# settings) already lives under, so the signed build keeps that history instead
# of starting fresh under a separate identity.
APP_BUNDLE_ID := com.aveekpatra.speek

# Local, untracked overrides (your personal SIGN_IDENTITY / DEV_TEAM). Optional;
# silently skipped if absent.
-include Makefile.local

# `make dmg` distribution signing identity — defaults to your SIGN_IDENTITY (Apple
# Development), which is enough to produce a runnable DMG; the friend just has to
# "Open Anyway" past Gatekeeper once. If you have a paid Apple Developer Program
# membership, set your own in Makefile.local for a Developer ID + notarized build:
#   DIST_IDENTITY := Developer ID Application: You (YOURTEAMID)
DIST_IDENTITY ?= $(SIGN_IDENTITY)

# Default target
all: check build

# Development workflow
dev: build run

# Run the unit + snapshot tests. Must stay on Debug and ad-hoc signing: a Release
# test host loads whisper.framework with a different Team ID and dies at launch.
# UI tests are skipped, they drive a second copy of the app and fail whenever
# your own Speek is already running.
test: check setup
	xcodebuild test -project "Speek.xcodeproj" -scheme "Speek" \
		-configuration Debug -destination 'platform=macOS' \
		-skip-testing:SpeekUITests \
		-derivedDataPath "$(CURDIR)/.local-test-build" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		PROVISIONING_PROFILE_SPECIFIER="" \
		ENABLE_TESTABILITY=YES \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/Speek/Speek.local.entitlements"

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@command -v cmake >/dev/null 2>&1 || { echo "cmake is not installed (needed to build whisper.cpp). Run: brew install cmake"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project "Speek.xcodeproj" -scheme "Speek" -configuration Debug CODE_SIGN_IDENTITY="" build

# Build for local use without Apple Developer certificate
local: check setup
	@echo "Building Speek for local use (no Apple Developer certificate required)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project "Speek.xcodeproj" -scheme "Speek" -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		ENABLE_DEBUG_DYLIB=NO \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/Speek/Speek.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/Speek.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying Speek.app to ~/Downloads..."; \
		rm -rf "$$HOME/Downloads/Speek.app"; \
		ditto "$$APP_PATH" "$$HOME/Downloads/Speek.app"; \
		xattr -cr "$$HOME/Downloads/Speek.app"; \
		echo ""; \
		echo "Build complete! App saved to: ~/Downloads/Speek.app"; \
		echo "Run with: open ~/Downloads/Speek.app"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built Speek.app at $$APP_PATH"; \
		exit 1; \
	fi

sync-api-keys:
	@echo "API keys are entered in the app's settings and stored per-user — nothing to sync."

signed: check setup sync-api-keys
	@echo "Building signed dev build (stable Apple Development signature)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project "Speek.xcodeproj" -scheme "Speek" -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		PRODUCT_BUNDLE_IDENTIFIER="$(APP_BUNDLE_ID)" \
		ENABLE_DEBUG_DYLIB=NO \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/Speek/Speek.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/Speek.app" && \
	if [ ! -d "$$APP_PATH" ]; then echo "Error: build product not found"; exit 1; fi && \
	echo "Killing any running instances..." && \
	pkill -x "Speek" 2>/dev/null; pkill -x "Whisper" 2>/dev/null; sleep 1; \
	echo "Installing to $(SIGNED_APP)..." && \
	mkdir -p "$(SIGNED_APP)" && \
	rsync -a --delete "$$APP_PATH/" "$(SIGNED_APP)/" && \
	xattr -cr "$(SIGNED_APP)" && \
	echo "Re-signing with your Apple Development cert..." && \
	codesign --force --deep --options runtime \
		--entitlements "$(CURDIR)/Speek/Speek.local.entitlements" \
		--sign "$(SIGN_IDENTITY)" "$(SIGNED_APP)" && \
	echo "" && \
	echo "Done. Launching $(SIGNED_APP)" && \
	open "$(SIGNED_APP)" && \
	echo "" && \
	echo ">> First time only: grant Accessibility + Microphone to 'Speek Dev'." && \
	echo ">> Every future 'make signed' keeps the same signature — no re-granting."

# Build a distributable DMG (Release, ad-hoc/personal-cert signed with minimal
# entitlements — no iCloud/keychain-group, so no provisioning profile needed).
# For sharing the app with someone outside this Mac. Does not touch /Applications
# or the running dev build. See scripts/make-dmg.sh for the full pipeline.
dmg: check setup
	@DIST_IDENTITY="$(DIST_IDENTITY)" \
	APP_BUNDLE_ID="$(APP_BUNDLE_ID)" \
	./scripts/make-dmg.sh

# Run application
run:
	@if [ -d "$$HOME/Downloads/Speek.app" ]; then \
		echo "Opening ~/Downloads/Speek.app..."; \
		open "$$HOME/Downloads/Speek.app"; \
	else \
		echo "Looking for Speek.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "Speek.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "Speek.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to Speek project"
	@echo "  build              Build the Speek Xcode project"
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  dmg                Build a distributable DMG (dist/Speek-<version>.dmg)"
	@echo "  run                Launch the built Speek app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
