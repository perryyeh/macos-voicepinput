APP_NAME := VoiceInput
APP_BUNDLE := $(APP_NAME).app
BUILD_DIR := $(shell swift build -c release --show-bin-path 2>/dev/null || echo .build/release)

.PHONY: build clean install run test package

test:
	swift test

build:
	swift build -c release
	$(eval BUILD_DIR := $(shell swift build -c release --show-bin-path))
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Info.plist $(APP_BUNDLE)/Contents/
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	codesign --force --sign - $(APP_BUNDLE)
	@echo "✅ Built $(APP_BUNDLE)"

package: build
	mkdir -p dist
	rm -f dist/$(APP_BUNDLE).zip
	ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) dist/$(APP_BUNDLE).zip
	unzip -t dist/$(APP_BUNDLE).zip
	@echo "✅ Packaged dist/$(APP_BUNDLE).zip"

run: build
	open $(APP_BUNDLE)

install: build
	rm -rf /Applications/$(APP_BUNDLE)
	cp -R $(APP_BUNDLE) /Applications/
	@echo "✅ Installed to /Applications/$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
