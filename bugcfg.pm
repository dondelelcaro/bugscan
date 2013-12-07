#! /usr/bin/perl
# vim: ts=8 sw=8 nowrap

use strict;
use warnings;
package bugcfg;
our ($spooldir,$maintainerlist,$debian_ftproot,$debian_sources,$pseudolist);

use Debbugs::Config qw(:config);

# General configuration stuff

$spooldir = $config{spool_dir}.'/db-h';
$maintainerlist = $config{maintainer_file};
$debian_sources = "/etc/debbugs/indices/ftp.sources";
$debian_ftproot = "/srv/bugs.debian.org/etc/indices/ftp/testing";
$pseudolist = $config{pseudo_desc_file};

# this is just the default, and should always be overriden by the
# Debbugs::Config; set values
our $debian_releases = {testing => 'jessie',
                        stable  => 'wheezy',
                        unstable => 'sid',
                        oldstable => 'squeeze',
                       };
# figure out debian releases from distribution aliases
for my $alias (keys %{$config{distribution_aliases}//{}}) {
    next if $alias eq $config{distribution_aliases}{$alias};
    $debian_releases->{$config{distribution_aliases}{$alias}} =
        $alias;
}

# check out:
# http://release.debian.org/wheezy/arch_qualify.html
# and then generally include architectures which are currently in testing
our @architectures = qw(amd64 armel armhf i386 ia64 kfreebsd-amd64 kfreebsd-i386 mips mipsel powerpc s390 s390x sparc);
our @sections		= ( "main", "contrib", "non-free" );
our @priorities		= @{$config{strong_severities}};
our @skiptags		= ( );

1;

