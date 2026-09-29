PREFIX ?= /usr/local
DESTDIR ?=

BINDIR      = $(DESTDIR)$(PREFIX)/bin
MANDIR      = $(DESTDIR)$(PREFIX)/share/man/man1
DOCDIR      = $(DESTDIR)$(PREFIX)/share/doc/decaf
BASHCOMPDIR = $(DESTDIR)$(PREFIX)/share/bash-completion/completions

SHELL_SOURCES = src/decaf completions/decaf.bash scripts/*.sh \
                tests/helpers.bash tests/fakes/fake tests/*.bats tests/integration.sh

BATS ?= bats

.PHONY: all install uninstall check test integration

all:
	@echo "Nothing to build. Run 'make install' (PREFIX=$(PREFIX))."

install:
	install -Dm755 src/decaf              $(BINDIR)/decaf
	install -Dm644 man/decaf.1            $(MANDIR)/decaf.1
	install -Dm644 completions/decaf.bash $(BASHCOMPDIR)/decaf
	install -Dm644 README.md              $(DOCDIR)/README.md

uninstall:
	rm -f  $(BINDIR)/decaf
	rm -f  $(MANDIR)/decaf.1
	rm -f  $(BASHCOMPDIR)/decaf
	rm -rf $(DOCDIR)

# Lint and formatting check (same as CI).
check:
	shellcheck -x $(SHELL_SOURCES)
	shfmt -d $(SHELL_SOURCES)

# Run the test suite (needs bats: pacman -S bash-bats).
test:
	$(BATS) tests

# Test against the real systemd; run locally before each release.
# The automatic checks never suspend. SUSPEND=1 adds three checks that do,
# each started only after you press Enter.
integration:
	tests/integration.sh $(if $(SUSPEND),--suspend)
