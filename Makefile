PROJECT     = DygmaContextSwitcher.xcodeproj
SCHEME      = DygmaContextSwitcher
TEST_SCHEME = DygmaContextSwitcherTests
CONFIG      = Debug
DERIVED     = build

.PHONY: build test clean run open release install

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) build

test:
	xcodebuild -project $(PROJECT) -scheme $(TEST_SCHEME) \
	  -destination 'platform=macOS' -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) test

run: build
	open $(DERIVED)/Build/Products/$(CONFIG)/DygmaContextSwitcher.app

clean:
	rm -rf $(DERIVED)

open:
	open $(PROJECT)

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	  -derivedDataPath $(DERIVED) build

install: release
	@echo "Installing DygmaContextSwitcher to /Applications…"
	@rm -rf /Applications/DygmaContextSwitcher.app
	@cp -R $(DERIVED)/Build/Products/Release/DygmaContextSwitcher.app /Applications/
	@echo "Done. Launch with: open /Applications/DygmaContextSwitcher.app"
