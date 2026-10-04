# Install yowu-headset system-wide. Also used by packaging/arch/PKGBUILD.
#
#   sudo make install                    # into /usr/local
#   make install DESTDIR=pkg PREFIX=/usr UDEVRULESDIR=/usr/lib/udev/rules.d
#
# Set PYTHON to install with a specific interpreter, e.g. one from a venv that
# has bleak: make install PYTHON=/opt/yowu-headset/venv/bin/python

PREFIX       ?= /usr/local
BINDIR       ?= $(PREFIX)/bin
DOCDIR       ?= $(PREFIX)/share/doc/yowu-headset
SYSCONFDIR   ?= /etc
# udev doesn't read /usr/local; packages should use /usr/lib/udev/rules.d.
UDEVRULESDIR ?= $(SYSCONFDIR)/udev/rules.d
USERUNITDIR  ?= $(PREFIX)/lib/systemd/user
PYTHON       ?= /usr/bin/env python3

BIN  = yowu-headsetd yowu-led yowu-toggle
CONF = $(DESTDIR)$(SYSCONFDIR)/yowu-headset/headsetd.conf

all: build/yowu-headsetd.service $(addprefix build/,$(BIN))

build/yowu-headsetd.service: systemd/yowu-headsetd.service.in
	@mkdir -p build
	sed 's|@BINDIR@|$(BINDIR)|g' $< > $@

build/%: %
	@mkdir -p build
	sed '1s|^#!.*|#!$(PYTHON)|' $< > $@

install: all
	install -Dm755 -t $(DESTDIR)$(BINDIR) $(addprefix build/,$(BIN))
	install -Dm644 udev/70-yowu-headset.rules $(DESTDIR)$(UDEVRULESDIR)/70-yowu-headset.rules
	install -Dm644 build/yowu-headsetd.service $(DESTDIR)$(USERUNITDIR)/yowu-headsetd.service
	install -Dm644 -t $(DESTDIR)$(DOCDIR) README.md docs/INSTALL.md docs/PROTOCOL.md config/headsetd.conf.example
	@# never overwrite an existing system config
	test -e $(CONF) || install -Dm644 config/headsetd.conf.example $(CONF)

uninstall:
	rm -f $(addprefix $(DESTDIR)$(BINDIR)/,$(BIN))
	rm -f $(DESTDIR)$(UDEVRULESDIR)/70-yowu-headset.rules
	rm -f $(DESTDIR)$(USERUNITDIR)/yowu-headsetd.service
	rm -rf $(DESTDIR)$(DOCDIR)
	@echo "left $(CONF) in place"

clean:
	rm -rf build

.PHONY: all install uninstall clean
