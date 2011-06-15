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
$debian_ftproot = $config{package_source};
$debian_sources = $config{package_source};
$pseudolist = $config{pseudo_desc_file};

$debian_sources	= "/etc/debbugs/indices/ftp.sources";



our @architectures		= ( "i386", "amd64", "alpha", "sparc", "powerpc", "armel", "hppa", "ia64", "mips", "mipsel", "s390" );
our @sections		= ( "main", "contrib", "non-free" );
our @priorities		= $config{strong_severities};
our @skiptags		= ( );

1;

