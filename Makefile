# Usage:
#   make                      build and run with the demo transcript
#   make run FILE=talk.md     build and run with your own transcript
#   make test                 run the test suite

FILE ?= demo/demo.md

# Some Command Line Tools releases intermittently omit the swift-testing macro
# plugin path, so pass it explicitly from whichever toolchain is active.
TESTING_PLUGINS := $(dir $(shell xcrun --find swift))../lib/swift/host/plugins/testing

.PHONY: run test clean

run:
	@test -f "$(FILE)" || { echo "transcript not found: $(FILE)" >&2; exit 1; }
	swift build -c release
	.build/release/Visitant "$(abspath $(FILE))"

test:
	swift test -Xswiftc -plugin-path -Xswiftc "$(TESTING_PLUGINS)"

clean:
	swift package clean
