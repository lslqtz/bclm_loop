prefix ?= /usr/local
bindir = $(prefix)/bin

build:
	swift build -c release --disable-sandbox --arch arm64 --arch x86_64
	strip .build/apple/Products/Release/bclm_loop

install: build
	mkdir -p "$(bindir)"
	install ".build/apple/Products/Release/bclm_loop" "$(bindir)"

uninstall:
	rm -rf "$(bindir)/bclm_loop"

clean:
	rm -rf .build

.PHONY: build install uninstall clean
