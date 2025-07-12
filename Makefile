prefix ?= /usr/local
bindir = $(prefix)/bin

build:
	swift build -c release --disable-sandbox --arch arm64
	strip .build/release/bclm_loop

install: build
	mkdir -p "$(bindir)"
	install ".build/release/bclm_loop" "$(bindir)"

uninstall:
	rm -rf "$(bindir)/bclm_loop"

clean:
	rm -rf .build

.PHONY: build install uninstall clean
