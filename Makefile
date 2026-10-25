EMACS ?= emacs
# LispM Kit, with which MYCIN declares its commands: a checkout beside
# this one by default.
LISPM_KIT ?= ../lispm-kit
# Emacs Common Lisp, which runs MYCIN: a checkout beside this one by
# default.
EMACS_CL ?= ../emacs-cl

.PHONY: test compile

test:
	$(EMACS) -Q --batch -L . -L $(LISPM_KIT) -L $(EMACS_CL) -l test/lispm-mycin-test.el \
	  -f ert-run-tests-batch-and-exit

# A check: the .elc file is removed again, as it would shadow the source
# of a checkout Emacs loads from.
compile:
	$(EMACS) -Q --batch -L . -L $(LISPM_KIT) -L $(EMACS_CL) --eval '(setq byte-compile-error-on-warn t)' \
	  -f batch-byte-compile lispm-mycin.el; \
	status=$$?; rm -f lispm-mycin.elc; exit $$status
