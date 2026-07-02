PROJECT := Joshu.xcodeproj
SCHEME := Joshu
DERIVED := .build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Joshu.app

.PHONY: gen build test run kill clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) -quiet build

test: gen
	cd Packages/JoshuKit && swift test
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) -quiet build

run: build kill
	open $(APP)

kill:
	-pkill -x Joshu 2>/dev/null || true

clean:
	rm -rf $(DERIVED) Joshu.xcodeproj
