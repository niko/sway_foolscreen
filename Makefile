PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
CFLAGS ?= -O2 -Wall
XDG_SHELL := $(shell pkg-config --variable=pkgdatadir wayland-protocols)/stable/xdg-shell/xdg-shell.xml
WAYLAND := $(shell pkg-config --cflags --libs wayland-client)

all: foolscreen-placeholder

xdg-shell-client-protocol.h:
	wayland-scanner client-header $(XDG_SHELL) $@

xdg-shell-protocol.c:
	wayland-scanner private-code $(XDG_SHELL) $@

foolscreen-placeholder: foolscreen-placeholder.c xdg-shell-protocol.c xdg-shell-client-protocol.h
	$(CC) $(CFLAGS) -o $@ foolscreen-placeholder.c xdg-shell-protocol.c $(WAYLAND)

install: all
	install -Dm755 foolscreen $(DESTDIR)$(BINDIR)/foolscreen
	install -Dm755 foolscreen-placeholder $(DESTDIR)$(BINDIR)/foolscreen-placeholder

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/foolscreen $(DESTDIR)$(BINDIR)/foolscreen-placeholder

clean:
	rm -f foolscreen-placeholder xdg-shell-protocol.c xdg-shell-client-protocol.h

test: all
	./test.sh

.PHONY: all install uninstall clean test
