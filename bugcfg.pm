#! /usr/bin/perl
# vim: ts=4 sw=4 nowrap

# General configuration stuff

$host=`hostname`;
chomp $host;
if ($host eq "master" or $host eq "spohr" or $host eq 'rietz') {
	$spooldir	= "/org/bugs.debian.org/debbugs/spool/db-h";
	$maintainerlist	= "/etc/debbugs/Maintainers";
	$debian_ftproot	= "/org/bugs.debian.org/etc/indices/ftp/testing";
	$nonUS_ftproot	= "/org/bugs.debian.org/etc/indices/nonus/testing";
	$debian_sources	= "/etc/debbugs/indices/ftp.sources";
	$nonUS_sources	= "/etc/debbugs/indices/nonus.sources";
	$pseudolist	= "/org/bugs.debian.org/etc/pseudo-packages.description";
	$nonuslist	= "/debian/home/maor/masterfiles/Packages.non-US";
} elsif ($host eq "lightning") {
	$spooldir	= "/debian/home/iwj/debian-bugs/spool/db";
	$maintainerlist = "/debian/debian/indices/Maintainers";
	$ftproot	= "/debian/debian/dists/potato/";
	$pseudolist	= "/debian/home/maor/masterfiles/pseudo-packages.description";
	$nonuslist	= "/debian/home/maor/masterfiles/Packages.non-US";
} else {
	die "Unknown machine, please configure paths in bugcfg.pm\n";
}

$btsURL			= "http://www.debian.org/Bugs/";
@architectures		= ( "i386", "m68k", "alpha", "sparc", "powerpc", "arm", "hppa", "ia64", "mips", "mipsel", "s390" );
@sections		= ( "main", "contrib", "non-free" );
@priorities		= ( "serious", "grave", "critical" );
@skiptags		= ( "wontfix", "fixed" );

1;

