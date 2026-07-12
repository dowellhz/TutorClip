APP_NAME := TutorClip
DEVELOPMENT_TEAM ?= T84BKD53ZD
BUILD_DIR := .build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
LOCAL_APP_DIR := $(HOME)/Applications/$(APP_NAME).app
XCODE_DERIVED_DATA := .xcode-derived
XCODE_TEST_DERIVED_DATA := .xcode-derived-tests
XCODE_APP_DIR := $(XCODE_DERIVED_DATA)/Build/Products/Debug/$(APP_NAME).app
RELEASE_APP_DIR := $(XCODE_DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app
RELEASE_DIR := $(BUILD_DIR)/release
RELEASE_DMG := $(RELEASE_DIR)/$(APP_NAME).dmg
DEVELOPER_ID ?= Developer ID Application: lu lin ($(DEVELOPMENT_TEAM))
NOTARY_PROFILE ?= TutorClip
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
SOURCES := $(shell find Sources/TutorClip -name '*.swift' | sort)

.PHONY: all build test test-visible verify-automated xcode-build xcode-build-signed release-app package-dmg notarize-dmg release-notarized install-current-signed-local install-signed-local run-signed-local run-signed-demo-local diagnose-signed-local diagnose-app-signed-local request-permissions-signed-local xcode-run xcode-run-signed xcode-run-demo xcode-run-demo-signed xcode-diagnose xcode-diagnose-signed xcode-request-permissions xcode-request-permissions-signed verify-signed verify-table-ai run run-demo install-local run-local diagnose request-permissions verify clean

all: xcode-build

build: xcode-build-signed
	rm -rf "$(APP_DIR)"
	mkdir -p "$(BUILD_DIR)"
	cp -R "$(XCODE_APP_DIR)" "$(APP_DIR)"
	codesign -dv "$(APP_DIR)" 2>&1 | rg "TeamIdentifier=$(DEVELOPMENT_TEAM)"
	-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(CURDIR)/$(APP_DIR)"

test:
	xcodebuild -quiet -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$(XCODE_TEST_DERIVED_DATA)" test CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64

test-visible:
	-osascript -e 'tell application "TutorClip" to quit'
	sleep 1
	xcodebuild -project $(APP_NAME).xcodeproj -scheme TutorClipVisibleUITests -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$(XCODE_TEST_DERIVED_DATA)" test DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates ONLY_ACTIVE_ARCH=YES ARCHS=arm64

verify-automated: verify test-visible

run: run-local

xcode-build:
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$(XCODE_DERIVED_DATA)" build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64

xcode-build-signed:
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$(XCODE_DERIVED_DATA)" build DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates ONLY_ACTIVE_ARCH=YES ARCHS=arm64

release-app:
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "$(XCODE_DERIVED_DATA)" build DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(DEVELOPER_ID)" ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp"
	codesign --force --deep --options runtime --timestamp --sign "$(DEVELOPER_ID)" "$(RELEASE_APP_DIR)"
	codesign --verify --deep --strict --verbose=2 "$(RELEASE_APP_DIR)"
	codesign -dv --verbose=4 "$(RELEASE_APP_DIR)" 2>&1 | rg "Authority=Developer ID Application|TeamIdentifier=$(DEVELOPMENT_TEAM)|Runtime Version"

package-dmg: release-app
	./Scripts/package_release.sh "$(RELEASE_APP_DIR)" "$(RELEASE_DMG)" "$(DEVELOPER_ID)"

notarize-dmg:
	test -f "$(RELEASE_DMG)"
	xcrun notarytool submit "$(RELEASE_DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(RELEASE_DMG)"
	xcrun stapler validate "$(RELEASE_DMG)"
	spctl --assess --type open --context context:primary-signature --verbose=4 "$(RELEASE_DMG)"

release-notarized: package-dmg notarize-dmg

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

verify-table-ai: xcode-build
	test -n "$(IMAGE)"
	"$(XCODE_APP_DIR)/Contents/MacOS/$(APP_NAME)" --probe-table-image "$(IMAGE)" $(if $(EXPECTED_ANSWER),--expected-answer "$(EXPECTED_ANSWER)") $(if $(EXPECTED_TITLE),--expected-title "$(EXPECTED_TITLE)")

verify-signed: xcode-build-signed
	codesign --verify --deep --strict "$(XCODE_APP_DIR)"
	codesign -dv "$(XCODE_APP_DIR)"

clean:
	rm -rf "$(BUILD_DIR)" "$(XCODE_DERIVED_DATA)" "$(XCODE_TEST_DERIVED_DATA)"
