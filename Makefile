# Nexus — SwiftPM build + .app assembly + signing (D1)
#
# Signing (§111.3): TCC keys Accessibility / Screen Recording grants to the code signature.
# An ad-hoc signature changes on every build, so every grant resets. Prefer a stable identity.
# Override with:  make app SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)"

CONFIG      ?= debug
BUILD_DIR   := $(shell swift build -c $(CONFIG) --show-bin-path)
APP_NAME    := Nexus
APP         := build/$(APP_NAME).app
BUNDLE_ID   := com.congbui.nexus

# Auto-detect a stable "Apple Development" certificate; fall back to ad-hoc.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
                   | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"')
ifeq ($(strip $(SIGN_IDENTITY)),)
SIGN_IDENTITY := -
endif

.PHONY: all build release test lint app run stop clean signing-info

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
	@echo "SIGN_IDENTITY = $(SIGN_IDENTITY)"
	@if [ "$(SIGN_IDENTITY)" = "-" ]; then \
	  echo "WARNING: ad-hoc signing. macOS TCC grants (Accessibility, Screen Recording) will"; \
	  echo "         reset on every rebuild. Add a free Apple Development certificate in Xcode"; \
	  echo "         (Settings > Accounts > Manage Certificates) to make grants stick."; \
	fi

app: build signing-info
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
	@cp $(BUILD_DIR)/NexusApp $(APP)/Contents/MacOS/NexusApp
	@if [ -d "$(BUILD_DIR)/Nexus_NexusUI.bundle" ]; then cp -R "$(BUILD_DIR)/Nexus_NexusUI.bundle" $(APP)/Contents/Resources/; fi
	@if [ -d "$(BUILD_DIR)/Nexus_NexusCore.bundle" ]; then cp -R "$(BUILD_DIR)/Nexus_NexusCore.bundle" $(APP)/Contents/Resources/; fi
	@printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --deep --sign "$(SIGN_IDENTITY)" --identifier $(BUNDLE_ID) $(APP)
	@codesign -dv $(APP) 2>&1 | head -5
	@echo "Built $(APP)"

run: stop app
	open $(APP)

stop:
	@pkill -x NexusApp 2>/dev/null || true
	@sleep 0.3

clean:
	swift package clean
	rm -rf build .build
