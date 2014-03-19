#!/usr/bin/perl

use warnings;
use strict;

use MLDBM qw(DB_File Storable);
use Fcntl;

$MLDBM::DumpMeth=q(portable);

# given an index and a set of stubs, populate the index with the stubs

my ($index,@stubs) = @ARGV;

my $index_new = $index.'.new';
my $tied_index = open_index($index_new);
populate_index($tied_index,\@stubs);
close_index($tied_index,$index_new,$index);

# open and create a tied index
sub open_index {
    my ($index) = @_;
    my %db;
    tie %db, "MLDBM", $index, O_CREAT|O_RDWR, 0664
        or die "tie $index: $!";
    return \%db;
}

# populate the index with the given stubs
sub populate_index{
    my ($tie,$stubs) = @_;
    for my $stub (@{$stubs}) {
        my $fh = IO::File->new($stub,'r');
        local $/;
        my $file_contents = <$fh>;
        my @stub_results = eval $file_contents;
        if ($@) {
            die "Stub $stub failed with error $@";
        }
        my %stub_results_to_add;
        if (@stub_results == 1 and
            ref($stub_results[0]) and
            ref($stub_results[0]) eq 'ARRAY') {
            @stub_results = @{$stub_results[0]};
        }
        if ((@stub_results % 2) == 0 and
            not ref($stub_results[0])
           ) {
            %stub_results_to_add = @stub_results;
        } else {
            for my $stub_result (@stub_results) {
                next unless ref($stub_result);
                next unless ref($stub_result) eq 'HASH';
                %stub_results_to_add = (%stub_results_to_add,
                                        %{$stub_result});
            }
        }
        for my $sr (keys %stub_results_to_add) {
            $tie->{$sr} = $stub_results_to_add{$sr};
        }
    }
}

# close the index
sub close_index{
    my ($tie,$index_new,$index) = @_;
    untie %{$tie};
    rename($index_new,$index);
}
