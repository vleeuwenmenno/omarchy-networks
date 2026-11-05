# Common tasks. Run `make` for the list.
QMLLINT ?= /usr/lib/qt6/bin/qmllint

.PHONY: help test lint validate check
help:
	@echo "make test      run the model tests (node --test)"
	@echo "make lint      qmllint every QML file"
	@echo "make validate  check manifest.json against Omarchy's plugin schema"
	@echo "make check     all of the above"

test:
	node --test test

lint:
	@fail=0; for f in *.qml sections/*.qml components/*.qml; do \
	  out=$$($(QMLLINT) "$$f" 2>&1 | grep -E '^Error|syntax'); \
	  if [ -n "$$out" ]; then echo "$$f: $$out"; fail=1; fi; \
	done; exit $$fail

validate:
	omarchy plugin validate .

check: test lint validate
