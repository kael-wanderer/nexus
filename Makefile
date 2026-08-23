# Nexus — SwiftPM build + .app assembly + signing (D1)
#
# Signing (§111.3): TCC keys Accessibility / Screen Recording grants to the code signature.
# An ad-hoc signature changes on every build, so every grant resets. ANY stable identity keeps
# grants sticky — a self-signed certificate works just as well as an Apple Development one.
# Override with:  make app SIGNING_IDENTITY="Bugler Local Dev"

CONFIG      ?= debug
BUILD_DIR   := $(shell swift build -c $(CONFIG) --show-bin-path)
APP_NAME    := Nexus
APP         := build/$(APP_NAME).app
BUNDLE_ID   := com.congbui.nexus
INSTALL_DIR ?= /Applications
INSTALLED   := $(INSTALL_DIR)/$(APP_NAME).app

# Auto-detect, in order: an "Apple Development" certificate, then ANY valid codesigning
# identity, then ad-hoc. Stability is what matters to TCC, not who issued the certificate.
SIGNING_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
                      | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"')
ifeq ($(strip $(SIGNING_IDENTITY)),)
SIGNING_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null \
                      | grep -oE '"[^"]+"' | head -1 | tr -d '"')
endif
ifeq ($(strip $(SIGNING_IDENTITY)),)
SIGNING_IDENTITY := -
endif

.PHONY: all build release test lint app install run stop clean signing-info reset-config logs

all: app

build:
	swift build -c $(CONFIG)

release:
	$(MAKE) build CONFIG=release

test:
	swift test

## Fails if `swift build` emits any warning.
lint:
	@find Sources Tests -name '*.swift' -exec touch {} +
	@out=$$(swift build -c $(CONFIG) --build-tests 2>&1); \
	echo "$$out"; \
	if echo "$$out" | grep -q ": warning:"; then echo "FAIL: warnings present"; exit 1; fi; \
	echo "OK: zero warnings"

signing-info:
	@echo "SIGNING_IDENTITY = $(SIGNING_IDENTITY)"
	@if [ "$(SIGNING_IDENTITY)" = "-" ]; then \
	  echo "WARNING: ad-hoc signing. macOS TCC grants (Accessibility, Screen Recording) will"; \
	  echo "         reset on every rebuild. Create ANY stable codesigning certificate —"; \
	  echo "         Keychain Access > Certificate Assistant > Create a Certificate"; \
	  echo "         (type: Code Signing), or a free Apple Development certificate in Xcode."; \
	fi

app: build signing-info
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
	@cp $(BUILD_DIR)/NexusApp $(APP)/Contents/MacOS/NexusApp
	@cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	@cp Resources/NexusTemplate.png Resources/NexusTemplate@2x.png $(APP)/Contents/Resources/
	@if [ -d "$(BUILD_DIR)/Nexus_NexusUI.bundle" ]; then cp -R "$(BUILD_DIR)/Nexus_NexusUI.bundle" $(APP)/Contents/Resources/; fi
	@if [ -d "$(BUILD_DIR)/Nexus_NexusCore.bundle" ]; then cp -R "$(BUILD_DIR)/Nexus_NexusCore.bundle" $(APP)/Contents/Resources/; fi
	@printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --sign "$(SIGNING_IDENTITY)" --identifier $(BUNDLE_ID) $(APP)
	@codesign -dv $(APP) 2>&1 | head -5
	@echo "Built $(APP)"

## Install into /Applications and run from there. Launch at login registers the bundle where it
## stands, so a login item is only meaningful once Nexus lives somewhere permanent — not in build/,
## which `make clean` deletes. `ditto` preserves the signature, so TCC grants survive the move.
install: app
	@if [ "$(SIGNING_IDENTITY)" = "-" ]; then \
	  echo "Refusing to install an ad-hoc build: its signature changes on every rebuild, so every"; \
	  echo "Accessibility and Screen Recording grant would reset. See 'make signing-info'."; \
	  exit 1; \
	fi
	@$(MAKE) --no-print-directory stop
	@rm -rf "$(INSTALLED)"
	@ditto $(APP) "$(INSTALLED)"
	@codesign --verify --strict "$(INSTALLED)" && echo "Signature verified"
	@open "$(INSTALLED)"
	@echo "Installed $(INSTALLED). Turn on Launch at login in Settings > General."

run: stop app
	open $(APP)

stop:
	@pkill -x NexusApp 2>/dev/null || true
	@sleep 0.3

## Wipe stored settings and start Nexus as if it had never run.
reset-config:
	@defaults delete $(BUNDLE_ID) 2>/dev/null || true
	@echo "Configuration reset. The next launch runs onboarding."

## Nexus's persisted log. `log` is a shell builtin in some shells, hence the absolute path.
logs:
	@/usr/bin/log show --predicate 'subsystem == "$(BUNDLE_ID)"' --last 30m --style compact

clean:
	swift package clean
	rm -rf build .build
