APP_NAME := Kornflake
APP_DIR := dist/$(APP_NAME).app
BIN := .build/release/$(APP_NAME)

.PHONY: build test app run clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp "$(BIN)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	codesign --force --sign - "$(APP_DIR)"

run: app
	open "$(APP_DIR)"

clean:
	swift package clean
	rm -rf dist
