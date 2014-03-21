#!/usr/bin/perl
# dump_stub_from_index.pl Outputs stubs from a tied index
# and is released under the terms of the GNU GPL version 3, or any
# later version, at your option. See the file README and COPYING for
# more information.
# Copyright 2014 by Don Armstrong <don@donarmstrong.com>.


use warnings;
use strict;

use Getopt::Long;
use Pod::Usage;

=head1 NAME

dump_stub_from_index.pl - Outputs stubs from a tied index

=head1 SYNOPSIS

dump_stub_from_index.pl index.idx key1 [key2...]

 Options:
   --debug, -d debugging level (Default 0)
   --help, -h display this help
   --man, -m display manual

=head1 OPTIONS

=over

=item B<--debug, -d>

Debug verbosity. (Default 0)

=item B<--help, -h>

Display brief usage information.

=item B<--man, -m>

Display this manual.

=back

=head1 EXAMPLES

dump_stub_from_index.pl

=cut


use vars qw($DEBUG);
use MLDBM qw(DB_File Storable);
# Use the portable dump method
$MLDBM::DumpMeth=q(portable);
use Data::Dumper;
# sort Data::Dumper keys
$Data::Dumper::Sortkeys=1;
use Fcntl;
use File::Basename;


my %options = (debug           => 0,
               help            => 0,
               man             => 0,
              );

GetOptions(\%options,
           'debug|d+','help|h|?','man|m');

pod2usage() if $options{help};
pod2usage({verbose=>2}) if $options{man};

$DEBUG = $options{debug};

my @USAGE_ERRORS;
if (@ARGV < 2) {
    push @USAGE_ERRORS,"You must give an index and at least one stub";
}

pod2usage(join("\n",@USAGE_ERRORS)) if @USAGE_ERRORS;

my ($index,@stubs) = @ARGV;

print "# dump_stub_from_index.pl ".basename($index)." ".join(' ',@stubs)."\n";
my %db;
tie %db, "MLDBM",$index, O_RDONLY
    or die "Unable to open and tie $index for reading: $!";

my %object;
for my $stub (@stubs) {
    $object{$stub} = $db{$stub};
}
print Data::Dumper->Dump([\%object],[qw($stub)]);




__END__
