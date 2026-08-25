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

.PHONY: all install uninstall enable disable restart status clean

all: $(BIN)

$(BIN): $(SOURCES)
	@mkdir -p $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) $(SOURCES) -o $@
	@codesign --force --sign $(SIGN_ID) --identifier $(LABEL) $@

# $(BINDIR) is root-owned under the default prefix, so this needs `sudo make
# install`. The agent targets below must NOT be run under sudo: they write a
# per-user plist into your own ~/Library/LaunchAgents and bootstrap into
# gui/<your uid>. Override with `make install PREFIX=$$HOME/.local` to drop
# the sudo entirely.
install: all
	install -d $(BINDIR)
	install -m 0755 $(BIN) $(BINDIR)/$(NAME)
	@codesign --force --sign $(SIGN_ID) --identifier $(LABEL) $(BINDIR)/$(NAME)

uninstall: disable
	rm -f $(BINDIR)/$(NAME)

# Deliberately not dependent on `install`, which needs root under the default
# prefix. After a rebuild: `sudo make install && make restart`.
enable:
	$(BINDIR)/$(NAME) enable

disable:
	-$(BINDIR)/$(NAME) disable

restart:
	$(BINDIR)/$(NAME) restart

# `-` so an exit code of 3 or 4 reports the agent's state rather than failing make.
status:
	-@$(BINDIR)/$(NAME) status

clean:
	rm -rf $(BUILD)
