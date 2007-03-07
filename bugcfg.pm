#! /usr/bin/perl
# vim: ts=4 sw=4 nowrap

use strict;
use warnings;
package bugcfg;
our ($spooldir,$maintainerlist,$debian_ftproot,$nonUS_ftproot,$debian_sources,$nonUS_sources,$pseudolist);
our ($nonuslist,$versionindex,$versionpkgdir);

# General configuration stuff

my $host=`hostname`;
chomp $host;
if ($host eq "master" or $host eq "spohr" or $host eq "rietz") {
	$spooldir	= "/org/bugs.debian.org/debbugs/spool/db-h";
	$maintainerlist	= "/etc/debbugs/Maintainers";
	$debian_ftproot	= "/org/bugs.debian.org/etc/indices/ftp/testing";
	$nonUS_ftproot	= "/org/bugs.debian.org/etc/indices/nonus/testing";
	$debian_sources	= "/etc/debbugs/indices/ftp.sources";
	$nonUS_sources	= "/etc/debbugs/indices/nonus.sources";
	$pseudolist	= "/org/bugs.debian.org/etc/pseudo-packages.description";
	$nonuslist	= "/debian/home/maor/masterfiles/Packages.non-US";
	$versionindex   = "/org/bugs.debian.org/versions/indices/versions.idx";
	$versionpkgdir  = "/org/bugs.debian.org/versions/pkg";
} elsif ($host eq "merkel") {
	$spooldir	= "/org/bugs.debian.org/spool/db-h";
	$maintainerlist	= "/etc/debbugs/Maintainers";
	$debian_ftproot	= "/org/bugs.debian.org/etc/indices/ftp/testing";
	$nonUS_ftproot	= "/org/bugs.debian.org/etc/indices/nonus/testing";
	$debian_sources	= "/etc/debbugs/indices/ftp.sources";
	$nonUS_sources	= "/etc/debbugs/indices/nonus.sources";
	$pseudolist	= "/org/bugs.debian.org/etc/pseudo-packages.description";
	$nonuslist	= "/debian/home/maor/masterfiles/Packages.non-US";
	$versionindex = "/org/bugs.debian.org/versions/indices/versions.idx";
	$versionpkgdir = "/org/bugs.debian.org/versions/pkg";
} else {
	die "Unknown machine, please configure paths in bugcfg.pm\n";
}

my $btsURL			= "http://www.debian.org/Bugs/";
my @architectures		= ( "i386", "m68k", "alpha", "sparc", "powerpc", "arm", "hppa", "ia64", "mips", "mipsel", "s390" );
my @sections		= ( "main", "contrib", "non-free" );
my @priorities		= ( "serious", "grave", "critical" );
my @skiptags		= ( );

1;

