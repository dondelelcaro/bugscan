#! /usr/bin/perl
# vim: ts=8 sw=8 nowrap
#
# General functions for scanning the BTS-database.
# Based on bugscan, written by Richard Braakman <dark@debian.org>,
# which was based on an unknown other script.
#
# Global variables:
#   %maintainer     - map from packagename to maintainer
#   %section        - map from packagename to section in the FTP-site
#   %packagelist    - map from packagename to bugreports

use lib qw(/org/bugs.debian.org/perl);
use LWP::UserAgent;
use Debbugs::MIME qw(decode_rfc1522 encode_rfc1522);
use Debbugs::Packages;
use Debbugs::Versions;
use Debbugs::Status;
use Fcntl qw(O_RDONLY);
use strict;
use warnings;
require bugcfg;
package scanlib;

our (%maintainer,%section,%packagelist,%debbugssection,%bugs);


# Read the list of maintainer 
sub readmaintainers() {
	my $pkg;					# Name of package
	my $mnt;					# Maintainer name & email

	open(M, $bugcfg::maintainerlist) or die "open $bugcfg::maintainerlist: $!\n";
	while (<M>) {
		chomp;
		m/^(\S+)\s+(\S.*\S)\s*$/ or die "Maintainers: $_ ?";
		($pkg, $mnt) = ($1, $2);
		$pkg =~ y/A-Z/a-z/;			# Normalize package-name. why???
		$_=$mnt;
		if (not m/</) {
			$mnt="$2 <$1>" if ( m/(\S+)\s+\(([^)]+)\)/ );
		}
		$maintainer{$pkg}= $mnt;
	}
	close(M);
}


sub readsources() {
	my $root;					# Root of archive we are scanning
	my $archive;				# Name of archive we are scanning
	my $sect;					# Name of current section

	$root=shift;
	$archive=shift;
	for $sect (@bugcfg::sections) {
		open(P, "zcat $root/$sect/source/Sources.gz|")
			or die open "open: $sect sourcelist: $!\n";
		while (<P>) {
			chomp;
			next unless m/^Package:\s/;
			s/^Package:\s*//;			# Strip the fieldname
			$section{$_} = "$archive/$sect";
		}
		close (P);
	}
}

sub readpackages {
    my ($root,$archive) = @_;
	for my $arch ( @bugcfg::architectures ) {
		for my $sect ( @bugcfg::sections) {
			open(P, "zcat $root/$sect/binary-$arch/Packages.gz|")
				or die "open: $root/$sect/binary-$arch/Packages.gz: $!\n";
			while (<P>) {
				chomp;
				next unless m/^Package:\s/;	# We're only interested in the packagenames
				s/^Package:\s*//;			# Strip the fieldname
				$section{$_} = "$archive/$sect";
				print "$root/$sect/binary-$arch/Packages.gz\n" if ($_ eq 'xtla');
			}
			close(P);
		}
	}
    # handle the source packages
    for my $sect (@bugcfg::sections) {
	my $fh;
	open($fh,'-|','zcat',"$root/$sect/source/Sources.gz") or
	    die "Unable to open zcat $root/$sect/source/Sources.gz for reading: $!";
	while (<$fh>) {
	    chomp;
	    next unless m/^Package:\s/;	# We're only interested in the packagenames
	    s/^Package:\s*//;			# Strip the fieldname
	    $section{$_} = "$archive/$sect";
	}
    }
}

sub readdebbugssources() {
	my $file;
	my $archive;

	$file=shift;
	$archive=shift;
	open(P, $file)
		or die "open: $file: $!\n";
	while (<P>) {
		chomp;
		my ($host, $bin, $sect, $ver, $src) = split /\s+/;
		my $sectname = ($sect =~ /^\Q$archive/) ? $sect : "$archive/$sect";
		$debbugssection{$bin} = $sectname;
		$debbugssection{$src} = $sectname;
	}
	close(P);
}

sub readpseudopackages() {
	open(P, $bugcfg::pseudolist) or die("open $bugcfg::pseudolist: $!\n");
	while (<P>) {
		chomp;
		s/\s.*//;
		$section{$_} = "pseudo";
	}
	close(P);
}


sub scanspool() {
	my @dirs;
	my $dir;

	chdir($bugcfg::spooldir) or die "chdir $bugcfg::spooldir: $!\n";

	opendir(DIR, $bugcfg::spooldir) or die "opendir $bugcfg::spooldir: $!\n";
	@dirs=grep(m/^\d+$/,readdir(DIR));
	closedir(DIR);

	for $dir (@dirs) {
		scanspooldir("$bugcfg::spooldir/$dir");
	}

}

sub scanspooldir {
	my ($dir)		= @_;
	my $f;			# While we're currently processing
	my @list;		# List of files to process
	my $skip;		# Flow control
	my $walk;		# index variable
	my $taginfo;	# Tag info
					
	my @archs_with_source = ( @bugcfg::architectures, 'source' );

	chdir($dir) or die "chdir $dir: $!\n";

	opendir(DIR, $dir) or die "opendir $dir: $!\n";
	@list = grep { s/\.summary$// }
			grep { m/^\d+\.summary$/ } 
			readdir(DIR);
	closedir(DIR);

	for $f (@list) {
		my $bug = Debbugs::Status::read_bug(summary => "$f.summary");
		next if (!defined($bug));
		
		my $bi = {
			number => $f,
			subject => $bug->{'subject'},
			package => $bug->{'package'}
		};
		
		$skip=1;
		for $walk (@bugcfg::priorities) {
			$skip=0 if $walk eq $bug->{'severity'};
		}

		my @tags = split(' ', $bug->{'keywords'});
		for my $tag (@tags) {
			for my $s (@bugcfg::skiptags) {
				$skip=1 if $tag eq $s;
			}
		}
		next if $skip==1;
	
		my %disttags = ();	
		$disttags{'oldstable'}    = grep(/^lenny$/, @tags);
		$disttags{'stable'}       = grep(/^squeeze$/, @tags);
		$disttags{'testing'}      = grep(/^wheezy$/, @tags);
		$disttags{'unstable'}     = grep(/^sid$/, @tags);
		$disttags{'experimental'} = grep(/^experimental$/, @tags);
			
		# default according to vorlon 2007-06-17
		if (!$disttags{'oldstable'} && !$disttags{'stable'} && !$disttags{'testing'} && !$disttags{'unstable'} && !$disttags{'experimental'}) {
			$disttags{'stable'} = 1;
			$disttags{'testing'} = 1;
			$disttags{'unstable'} = 1;
			$disttags{'experimental'} = 1;
		}
		
		if (defined($section{$bug->{'package'}}) && $section{$bug->{'package'}} eq 'pseudo') {
			# versioning information makes no sense for pseudo packages,
			# just use the tags
			for my $dist (qw(oldstable stable testing unstable experimental)) {
				$bi->{$dist} = $disttags{$dist};
			}
			next if (length($bug->{'done'}));
		} else {
			my $affects_any = 0;
		
			# only bother to check the versioning status for the distributions indicated by the tags 
			for my $dist (qw(oldstable stable testing unstable experimental)) {
				local $SIG{__WARN__} = sub {};

				$bi->{$dist} = 0;
				next if (!$disttags{$dist});

				my $presence = Debbugs::Status::bug_presence(
					bug => $f, 
					status => $bug, 
					dist => $dist, 
					arch => \@archs_with_source
				);

				# ignore bugs that are absent/fixed in this distribution, include everything
				# else (that is, "found" which says that the bug is present, and undef, which
				# indicates that no versioning information is present and it's not closed
				# unversioned)
				if (!defined($presence) || ($presence ne 'absent' && $presence ne 'fixed')) {
					$bi->{$dist} = 1;
					$affects_any = 1;
				}
			}
			
			next if !$affects_any;
		}

		for my $keyword (qw(pending patch help moreinfo unreproducible security upstream etch-ignore lenny-ignore squeeze-ignore wheezy-ignore)) {
			$bi->{$keyword} = grep(/^$keyword$/, @tags);
		}

		if (length($bug->{'mergedwith'})) {
			my @merged = split(' ', $bug->{'mergedwith'});
			next if ($merged[0] < $f);
		}

		for my $package (split /[,\s]+/, $bug->{'package'}) {
			$_= $package; y/A-Z/a-z/; $_= $` if m/[^-+._:a-z0-9]/;
			push @{$packagelist{$_}}, $f;
		}

		my $taginfo = get_taginfo($bi);
		my $relinfo = get_relinfo($bi);

		$bugs{$f} = $bi;
	}
}


sub readstatus {
    my $filename = shift;
	open STATUS, "<", $filename
		or die "$filename: $!";

    while (1) {
		chomp (my $type = <STATUS>);
		if ($type eq 'package') {
			chomp (my $package = <STATUS>);
			chomp (my $section = <STATUS>);
			chomp (my $maintainer = <STATUS>);
			my $blank = <STATUS>;

			$section{$package} = $section;
			$maintainer{$package} = $maintainer;
		}
		if ($type eq 'bug') {
			my $bug = {};
			while (1) {
				my $line = <STATUS>;
				last if ($line !~ /^(.*?)=(.*)$/);

				$bug->{$1} = $2;				
			}
			$bugs{$bug->{'number'}} = $bug;

			for my $package (split /[,\s]+/, $bug->{'package'}) {
				$_= $package; y/A-Z/a-z/; $_= $` if m/[^-+._:a-z0-9]/;
				push @{$packagelist{$_}}, $bug->{'number'};
			}
		}
		last if ($type eq 'end');
	}
	close(STATUS);
}


sub urlsanit {
	my $url = shift;
	$url =~ s/%/%25/g;
	$url =~ s/\+/%2b/g;
	my %saniarray = ('<','lt', '>','gt', '&','amp', '"','quot');
	$url =~ s/([<>&"])/\&$saniarray{$1};/g;
	return $url;
}

sub htmlsanit {
    my %saniarray = ('<','lt', '>','gt', '&','amp', '"','quot');
    my $in = shift || "";
    $in =~ s/([<>&"])/\&$saniarray{$1};/g;
    return $in;
}

sub wwwnumber() {
	my $number = shift;		# Number of bug to html-ize

	"<A HREF=\"http://bugs.debian.org/cgi-bin/bugreport.cgi?archive=no&amp;bug=" .
		urlsanit($number) . '">' . htmlsanit($number) . '</A>';
}

sub wwwname() {
	my $name = shift;			# Name of package

	"<A HREF=\"http://bugs.debian.org/cgi-bin/pkgreport.cgi?archive=no&amp;pkg=" .
		urlsanit($name) . '">' . htmlsanit($name) . '</A>';
}

sub check_worry {
	my ($bi) = @_;

	return ($bi->{'testing'} && !$bi->{'wheezy-ignore'});
}

sub check_worry_stable {
	my ($bi) = @_;

	return ($bi->{'stable'} && !$bi->{'squeeze-ignore'});
}

sub check_worry_unstable {
	my ($bi) = @_;

	return ($bi->{'unstable'});
}

sub get_taginfo {
    my $bi = shift;

	my $taginfo = "";
	$taginfo .= $bi->{'pending'}        ? "P" : " ";
	$taginfo .= $bi->{'patch'}          ? "+" : " ";
	$taginfo .= $bi->{'help'}           ? "H" : " ";
	$taginfo .= $bi->{'moreinfo'}       ? "M" : " ";
	$taginfo .= $bi->{'unreproducible'} ? "R" : " ";
	$taginfo .= $bi->{'security'}       ? "S" : " ";
	$taginfo .= $bi->{'upstream'}       ? "U" : " ";
	$taginfo .= ($bi->{'wheezy-ignore'} || $bi->{'squeeze-ignore'}) ? "I" : " ";

	return $taginfo;
}

sub get_relinfo {
    my $bi = shift;

    my $relinfo = "";
	for my $dist (qw(oldstable stable testing unstable experimental)) {
	    $relinfo .= uc(substr($dist, 0, 1)) if $bi->{$dist};
	}

	return $relinfo;
}


1;
