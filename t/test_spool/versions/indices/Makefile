#!/usr/bin/make -f

VERSION_INDICES=versions.idx versions_time.idx binsrc.idx srcbin.idx

PERL?=perl

all: $(VERSION_INDICES)

$(VERSION_INDICES): %.idx: %.idx_stubs make_index_from_stubs.pl $(wildcard %.idx_stubs/*.stub)
	$(PERL) $(wordlist 2,2,$^) $@ $(wordlist 3,$(words $^),$^)

