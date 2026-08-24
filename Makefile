NAME       := nscroll
LABEL      := com.nscroll.agent

PREFIX     ?= /usr/local
BINDIR     := $(PREFIX)/bin
BUILD      := build
BIN        := $(BUILD)/$(NAME)
SOURCES    := $(wildcard Sources/*.swift)

SWIFTC     ?= swiftc
# -parse-as-library is mandatory: without it swiftc treats a file as script
# mode and @main will not compile.
SWIFTFLAGS := -parse-as-library -swift-version 5 -O -wmo \
              -target $(shell uname -m)-apple-macosx11.0

# Accessibility permission is keyed to the executable, and for an ad-hoc
# signature that key includes the code hash — so every rebuild silently revokes
# the grant. Make a self-signed code-signing certificate in Keychain Access and
# build with SIGN_ID="NScroll Dev" to make the grant stick.
SIGN_ID    ?= -

.PHONY: all install uninstall clean

all: $(BIN)

$(BIN): $(SOURCES)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) $(SOURCES) -o $@
	@codesign --force --sign $(SIGN_ID) --identifier $(LABEL) $@

install: all
	install -d $(BINDIR)
	install -m 0755 $(BIN) $(BINDIR)/$(NAME)
	@codesign --force --sign $(SIGN_ID) --identifier $(LABEL) $(BINDIR)/$(NAME)

uninstall:
	rm -f $(BINDIR)/$(NAME)

clean:
	rm -rf $(BUILD)
