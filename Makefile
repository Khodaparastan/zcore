VERSION := $(shell cat VERSION)
ROOT    := $(shell pwd)
DIST    := $(ROOT)/dist
PREFIX  ?= $(HOME)/.local
ZSHDIR  := $(PREFIX)/share/zcore

.PHONY: test test-unit test-integration lint bundle install clean help

help:
	@echo "zcore v$(VERSION)"
	@echo "  make test              Run all tests"
	@echo "  make test-unit         Run unit tests only"
	@echo "  make test-integration  Run integration tests only"
	@echo "  make lint              Shell syntax check (zsh -n)"
	@echo "  make bundle            Build dist/ single-file bundles"
	@echo "  make install           Install to $(ZSHDIR)"
	@echo "  make clean             Remove dist/ and temp files"

test:
	zsh tests/run_tests.zsh

test-unit:
	zsh tests/run_tests.zsh unit

test-integration:
	zsh tests/run_tests.zsh integration

lint:
	@find lib bin tests -name '*.zsh' -print | while read f; do \
		zsh -n "$$f" || exit 1; \
	done
	@zsh -n bin/zbundle
	@zsh -n tests/run_tests.zsh
	@for f in z zbase zkv zbus zlog; do zsh -n $$f || exit 1; done
	@echo "lint OK"

bundle:
	@zsh bin/zbundle

install: bundle
	@install -d $(ZSHDIR)/lib $(ZSHDIR)/bin
	@cp -R lib/* $(ZSHDIR)/lib/
	@cp dist/* $(ZSHDIR)/
	@install -m 755 z zbase zkv zbus zlog $(ZSHDIR)/
	@echo "Installed zcore v$(VERSION) to $(ZSHDIR)"

clean:
	rm -rf dist _tmp
