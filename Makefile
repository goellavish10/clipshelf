.PHONY: build test app run clean

APP_NAME := ClipShelf
BUILD_DIR := $(CURDIR)/build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
RELEASE_BINARY := $(CURDIR)/.build/release/$(APP_NAME)
SWIFT_FLAGS := --disable-sandbox --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security
SWIFT_ENV := CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/ModuleCache

build:
	$(SWIFT_ENV) swift build $(SWIFT_FLAGS)

test:
	$(SWIFT_ENV) swift test $(SWIFT_FLAGS)

app:
	$(SWIFT_ENV) swift build -c release $(SWIFT_FLAGS)
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(RELEASE_BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp "$(CURDIR)/Resources/Info.plist" "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --deep --sign - "$(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

clean:
	swift package clean
