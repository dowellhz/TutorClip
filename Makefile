APP_NAME := TutorClip
DEVELOPMENT_TEAM ?= T84BKD53ZD
BUILD_DIR := .build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
LOCAL_APP_DIR := $(HOME)/Applications/$(APP_NAME).app
XCODE_DERIVED_DATA := .xcode-derived
XCODE_APP_DIR := $(XCODE_DERIVED_DATA)/Build/Products/Debug/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
SOURCES := $(shell find Sources/TutorClip -name '*.swift' | sort)

.PHONY: all build test xcode-build xcode-build-signed install-current-signed-local install-signed-local run-signed-local run-signed-demo-local diagnose-signed-local diagnose-app-signed-local request-permissions-signed-local xcode-run xcode-run-signed xcode-run-demo xcode-run-demo-signed xcode-diagnose xcode-diagnose-signed xcode-request-permissions xcode-request-permissions-signed verify-signed run run-demo install-local run-local diagnose request-permissions verify clean

all: xcode-build

build: xcode-build-signed
	rm -rf "$(APP_DIR)"
	mkdir -p "$(BUILD_DIR)"
	cp -R "$(XCODE_APP_DIR)" "$(APP_DIR)"
	codesign -dv "$(APP_DIR)" 2>&1 | rg "TeamIdentifier=$(DEVELOPMENT_TEAM)"
	-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(CURDIR)/$(APP_DIR)"

test:
	xcodebuild -quiet -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$(XCODE_DERIVED_DATA)" test CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64

run: run-local

xcode-build:
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$(XCODE_DERIVED_DATA)" build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64

xcode-build-signed:
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$(XCODE_DERIVED_DATA)" build DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates ONLY_ACTIVE_ARCH=YES ARCHS=arm64

install-current-signed-local:
	codesign -dv "$(XCODE_APP_DIR)" 2>&1 | rg "TeamIdentifier=$(DEVELOPMENT_TEAM)"
	mkdir -p "$(HOME)/Applications"
	-osascript -e 'tell application "$(APP_NAME)" to quit'
	sleep 1
	rm -rf "$(LOCAL_APP_DIR)"
	cp -R "$(XCODE_APP_DIR)" "$(LOCAL_APP_DIR)"
	codesign -dv "$(LOCAL_APP_DIR)" 2>&1 | rg "TeamIdentifier=$(DEVELOPMENT_TEAM)"

install-signed-local: xcode-build-signed install-current-signed-local

run-signed-local: install-current-signed-local
	open "$(LOCAL_APP_DIR)"

run-signed-demo-local: install-current-signed-local
	mkdir -p "$(HOME)/.tutorclip"
	touch "$(HOME)/.tutorclip/launch-demo"
	open "$(LOCAL_APP_DIR)"

diagnose-signed-local: install-current-signed-local
	"$(LOCAL_APP_DIR)/Contents/MacOS/$(APP_NAME)" --diagnose

diagnose-app-signed-local: install-current-signed-local
	mkdir -p "$(HOME)/.tutorclip"
	rm -f "$(HOME)/.tutorclip/diagnostics.txt"
	touch "$(HOME)/.tutorclip/write-diagnostics"
	open "$(LOCAL_APP_DIR)"
	sleep 5
	test -f "$(HOME)/.tutorclip/diagnostics.txt"
	cat "$(HOME)/.tutorclip/diagnostics.txt"
	./Scripts/verify_runtime_diagnostics.sh "$(HOME)/.tutorclip/diagnostics.txt"

request-permissions-signed-local: install-current-signed-local
	mkdir -p "$(HOME)/.tutorclip"
	touch "$(HOME)/.tutorclip/request-permissions"
	open "$(LOCAL_APP_DIR)"

xcode-run: xcode-build
	open "$(XCODE_APP_DIR)"

xcode-run-signed: xcode-build-signed
	open "$(XCODE_APP_DIR)"

xcode-run-demo: xcode-build
	mkdir -p "$(HOME)/.tutorclip"
	touch "$(HOME)/.tutorclip/launch-demo"
	open "$(XCODE_APP_DIR)"

xcode-run-demo-signed: xcode-build-signed
	mkdir -p "$(HOME)/.tutorclip"
	touch "$(HOME)/.tutorclip/launch-demo"
	open "$(XCODE_APP_DIR)"

xcode-diagnose: xcode-build
	"$(XCODE_APP_DIR)/Contents/MacOS/$(APP_NAME)" --diagnose

xcode-diagnose-signed: xcode-build-signed
	"$(XCODE_APP_DIR)/Contents/MacOS/$(APP_NAME)" --diagnose

xcode-request-permissions: xcode-build
	mkdir -p "$(HOME)/.tutorclip"
	touch "$(HOME)/.tutorclip/request-permissions"
	open "$(XCODE_APP_DIR)"

xcode-request-permissions-signed: xcode-build-signed
	mkdir -p "$(HOME)/.tutorclip"
	touch "$(HOME)/.tutorclip/request-permissions"
	open "$(XCODE_APP_DIR)"

run-demo: install-local
	mkdir -p "$(HOME)/.tutorclip"
	touch "$(HOME)/.tutorclip/launch-demo"
	open -a "$(LOCAL_APP_DIR)"

install-local: install-signed-local

run-local: run-signed-local

diagnose: build
	"$(APP_DIR)/Contents/MacOS/$(APP_NAME)" --diagnose

request-permissions: install-local
	mkdir -p "$(HOME)/.tutorclip"
	touch "$(HOME)/.tutorclip/request-permissions"
	open "$(LOCAL_APP_DIR)"

verify:
	./Scripts/verify_static.sh

verify-signed: xcode-build-signed
	codesign --verify --deep --strict "$(XCODE_APP_DIR)"
	codesign -dv "$(XCODE_APP_DIR)"

clean:
	rm -rf "$(BUILD_DIR)"
