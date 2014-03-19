PERL ?= /usr/bin/perl

test:
	$(PERL) -MTest::Harness -I. -e 'runtests(glob(q(t/*.t)))'

test_%: t/%.t
	$(PERL) -MTest::Harness -I. -e 'runtests(q($<))'

html:
	./dohtml

graph:
	./dograph

post:
	./dopost

status:
	./dostatus

rescan:
	./crontab

.PHONY: html graph post status rescan test
