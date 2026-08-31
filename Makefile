# =============================================================================
# zcore — Development targets
# =============================================================================
# Description:  Bundle, test, lint, and install helpers for the zcore
#               framework. Modules with a lib/<module>/parts manifest are
#               assembled from their parts by bin/zbundle; the root file is a
#               generated artifact. Modules without one are edited directly.
#
# Usage:        make help
#               make bundle && make test
#               PREFIX=/usr/local make install
#
# Requires:     zsh 5.x; GNU or BSD make
# =============================================================================

VERSION := $(shell cat VERSION)
PREFIX  ?= $(HOME)/.local
ZSHDIR  := $(PREFIX)/share/zcore

# Sourceable modules, in dependency order. zlog is a symlink into the
# lib/zsh-log submodule and is installed by resolving it (cp -L).
MODULES := zlog zbase ui zkv zbus z

# Modules owned by this repository. zlog is excluded: it is a git submodule
# tracking its own upstream and follows that project's conventions.
OWNED := zbase ui zkv zbus z

# Modules assembled from parts. Their root files must never be hand-edited.
SPLIT := z

.PHONY: help bundle bundle-check test test-unit test-integration \
        test-module lint lint-style install clean

help:
	@echo "zcore v$(VERSION)"
	@echo "  make bundle            Assemble split modules from lib/<module>/"
	@echo "  make bundle-check      Fail if a generated module has drifted"
	@echo "  make test              Run all suites"
	@echo "  make test-unit         Run tests/unit/ only"
	@echo "  make test-integration  Run tests/integration/ only"
	@echo "  make test-module M=zkv Run one module's suites"
	@echo "  make lint              Syntax check plus bundle and style checks"
	@echo "  make lint-style        Comment and header standard only"
	@echo "  make install           Install to $(ZSHDIR)"
	@echo "  make clean             Remove temp files"

# Parts are canonical: edit lib/<module>/*.zsh, then regenerate.
bundle:
	@zsh bin/zbundle $(SPLIT)

bundle-check:
	@zsh bin/zbundle --check $(SPLIT)

# Each suite loads the modules it exercises through ztest::require, so these
# targets differ only in which files the runner selects. A suite is equally
# runnable on its own: zsh tests/unit/zkv/test_zkv_tx.zsh
test:
	zsh tests/run_tests.zsh

test-unit:
	zsh tests/run_tests.zsh unit

test-integration:
	zsh tests/run_tests.zsh integration

# M names a directory under tests/unit/, e.g. make test-module M=zkv
test-module:
	zsh tests/run_tests.zsh $(M)

# Parse-only check of every module, part, test, and helper. `zsh -n` catches
# syntax errors without executing anything.
lint: bundle-check
	@for f in $(MODULES); do zsh -n $$f || exit 1; done
	@for f in lib/*/*.zsh; do zsh -n "$$f" || exit 1; done
	@zsh -n bin/zbundle
	@zsh -n bin/zlint-comments
	@zsh -n tests/run_tests.zsh
	@zsh -n tests/ztest
	@zsh -n tests/bootstrap.zsh
	@for f in tests/unit/*/*.zsh tests/integration/*.zsh; do zsh -n "$$f" || exit 1; done
	@echo "lint OK"
	@$(MAKE) --no-print-directory lint-style

# Enforces docs/conventions.md — see "File header & comment standard".
lint-style:
	@zsh bin/zlint-comments $(OWNED) bin/zbundle bin/zlint-comments \
	  --module lib/z/header.zsh \
	  --part lib/z/debug.zsh lib/z/cache.zsh lib/z/sys.zsh lib/z/config.zsh \
	         lib/z/help.zsh lib/z/event.zsh lib/z/init.zsh \
	  --script lib/z/z.zsh tests/run_tests.zsh \
	           tests/unit/*/*.zsh tests/integration/*.zsh \
	  --module tests/ztest tests/bootstrap.zsh

install: bundle-check
	@install -d $(ZSHDIR)
	@for f in $(MODULES); do cp -L $$f $(ZSHDIR)/; done
	@chmod 644 $(ZSHDIR)/*
	@echo "Installed zcore v$(VERSION) to $(ZSHDIR)"

clean:
	rm -rf _tmp
