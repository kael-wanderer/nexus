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
# Read from the bundle's own Info.plist, so the version lives in exactly one place — the same one
# the About tab reads at runtime.
VERSION     := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG         := build/$(APP_NAME)-$(VERSION).dmg
ZIP         := build/$(APP_NAME)-$(VERSION).zip

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

.PHONY: all build release test lint app install run stop clean signing-info reset-config logs dmg zip

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

## A disk image to hand to another Mac. Release build, signed, with the drag-to-Applications
## layout people expect. It is *not* notarised — Nexus has no Developer ID — so the first launch on
## another machine needs right-click → Open, or `xattr -dr com.apple.quarantine`, which the README
## says too.
dmg:
	@$(MAKE) --no-print-directory app CONFIG=release
	@rm -rf build/dmg $(DMG)
	@mkdir -p build/dmg
	@ditto $(APP) "build/dmg/$(APP_NAME).app"
	@ln -s /Applications build/dmg/Applications
	@hdiutil create -volname "$(APP_NAME) $(VERSION)" -srcfolder build/dmg -ov -format UDZO $(DMG) >/dev/null
	@rm -rf build/dmg
	@codesign --force --sign "$(SIGNING_IDENTITY)" $(DMG) 2>/dev/null || true
	@shasum -a 256 $(DMG)
	@echo "Built $(DMG)"

## The same build as a zip, for when a disk image is more ceremony than the situation needs.
zip:
	@$(MAKE) --no-print-directory app CONFIG=release
	@rm -f $(ZIP)
	@ditto -c -k --keepParent $(APP) $(ZIP)
	@shasum -a 256 $(ZIP)
	@echo "Built $(ZIP)"

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
