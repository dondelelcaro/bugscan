#! /usr/bin/perl
# vim: ts=4 sw=4 nowrap
#
# General functions for scanning the BTS-database.
# Based on bugscan, written by Richard Braakman <dark@debian.org>,
# which was based on an unknown other script.
#
# Global variables:
#   %comments       - map from bugnumber to bug description
#   %premature      - list of prematurely closed bugreports
#   %exclude        - list of bugreports to exclude from the report
#   %maintainer     - map from packagename to maintainer
#   %section        - map from packagename to section in the FTP-site
#   %packagelist    - map from packagename to bugreports
#   %NMU            - map with NMU information

#use lib qw(/org/bugs.debian.org/perl/);
use lib qw(/home/sesse/debbugs);
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

our (%comments,%premature,%exclude,%maintainer,%section,%packagelist,%NMU,%debbugssection,%bugs);

sub readcomments() {
# Read bug commentary 
# It is in paragraph format, with the first line of each paragraph being
# the bug number or package name to which the comment applies.
# Prefix a bug number with a * to force it to be listed even if it's closed.
# (This deals with prematurely closed bugs)

	my $index;					# Bug-number for current comment
	my $file;					# Name of comments-file

	%comments = ();					# Initialize our data
	%premature = ();
	%exclude = ();
	$file=shift;
	open(C, $file) or die "open $file: $!\n";
	while (<C>) {
		chomp;
		if (m/^\s*$/) {				# Check for paragraph-breaks
			undef $index;
		} elsif (defined $index) {
			$comments{$index} .= $_ . "\n";
		} else {
			if (s/^\*//) {			# Test & remove initial *
				$premature{$_} = 1;
			}
			if (s/\s+EXCLUDE\s*//) {	# Test & remove EXCLUDE
				$exclude{$_} = 1;
				next;
			}
			$index = $_;
			$comments{$index} = '';	# New comment, initialize data
		}
	}
	close(C);
}


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

sub readpackages() {
	my $root;					# Root of archive we are scanning
	my $archive;				# Name of archive we are scanning
	my $sect;					# Name of current section
	my $arch;					# Name of current architecture

	$root=shift;
	$archive=shift;
	for $arch ( @bugcfg::architectures ) {
		for $sect ( @bugcfg::sections) {
			open(P, "zcat $root/$sect/binary-$arch/Packages.gz|")
				or die "open: $root/$sect/binary-$arch/Packages.gz: $!\n";
			while (<P>) {
				chomp;
				next unless m/^Package:\s/;	# We're only interested in the packagenames
				s/^Package:\s*//;			# Strip the fieldname
				$section{$_} = "$archive/$sect";
			}
			close(P);
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

sub scanspooldir() {
	my ($dir)		= @_;
	my $f;			# While we're currently processing
	my @list;		# List of files to process
	my $skip;		# Flow control
	my $walk;		# index variable
	my $taginfo;	# Tag info

	chdir($dir) or die "chdir $dir: $!\n";

	opendir(DIR, $dir) or die "opendir $dir: $!\n";
	@list = grep { s/\.summary$// }
			grep { m/^\d+\.summary$/ } 
			readdir(DIR);
	closedir(DIR);

	for $f (@list) {
		next if $exclude{$f};			# Check the list of bugs to skip
	
		my $bug = Debbugs::Status::read_bug(summary => "$f.summary");
		next if (!defined($bug));
		
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
		$disttags{'oldstable'}    = grep(/^woody$/, @tags);
		$disttags{'stable'}       = grep(/^sarge$/, @tags);
		$disttags{'testing'}      = grep(/^etch$/, @tags);
		$disttags{'unstable'}     = grep(/^sid$/, @tags);
		$disttags{'experimental'} = grep(/^experimental$/, @tags);

		# default according to dondelelcaro 2006-11-11
		if (!$disttags{'oldstable'} && !$disttags{'stable'} && !$disttags{'testing'} && !$disttags{'unstable'} && !$disttags{'experimental'}) {
			$disttags{'testing'} = 1;
			$disttags{'unstable'} = 1;
			$disttags{'experimental'} = 1;
		}

		# only bother to check the versioning status for the distributions indicated by the tags 
		my $relinfo = "";
		for my $dist qw(oldstable stable testing unstable experimental) {
			next if (!$disttags{$dist});
			if (Debbugs::Status::check_bug_presence(bug => $f, status => $bug, dist => $dist) eq 'pending') {
				$relinfo .= uc(substr($dist, 0, 1));
			}
		}
		
		next if $relinfo eq '' and not $premature{$f};
		$premature{$f}++ if $relinfo eq '';

		$taginfo = "[";
		$taginfo .= ($bug->{'keywords'} =~ /\bpending\b/        ? "P" : " ");
		$taginfo .= ($bug->{'keywords'} =~ /\bpatch\b/          ? "+" : " ");
		$taginfo .= ($bug->{'keywords'} =~ /\bhelp\b/           ? "H" : " ");
		$taginfo .= ($bug->{'keywords'} =~ /\bmoreinfo\b/       ? "M" : " ");
		$taginfo .= ($bug->{'keywords'} =~ /\bunreproducible\b/ ? "R" : " ");
		$taginfo .= ($bug->{'keywords'} =~ /\bsecurity\b/       ? "S" : " ");
		$taginfo .= ($bug->{'keywords'} =~ /\bupstream\b/       ? "U" : " ");
		$taginfo .= ($bug->{'keywords'} =~ /\betch-ignore\b/    ? "I" : " ");
		$taginfo .= "]";

		if (length($bug->{'mergedwith'})) {
			my @merged = split(' ', $bug->{'mergedwith'});
			next if ($merged[0] < $f);
		}

		for my $package (split /[,\s]+/, $bug->{'package'}) {
			$_= $package; y/A-Z/a-z/; $_= $` if m/[^-+._a-z0-9]/;
			if (not defined $section{$_}) {
				if (defined $debbugssection{$_}) {
					$relinfo .= "X";
				} else {
					next;	# Skip unavailable packages
				}
			}

			push @{$packagelist{$_}}, $f;
		}

		if ($relinfo eq "") { # or $relinfo eq "U" # confuses e.g. #210306
			$relinfo = "";
		} else {
			$relinfo = " [$relinfo]";
		}

		$bugs{$f} = "$f $taginfo$relinfo " . $bug->{'subject'};
	}
}


sub readstatus() {
	my $bug;		# Number of current bug
	my $subject;	# Subject for current bug
	my $pkg;		# Name of current package
	my $file;		# Name of statusfile
	my $sect;		# Section of current package
	my $mnt;		# Maintainer of current package

	$file=shift;
	open(P, $file) or die "open $file: $!";
	while (<P>) {
		chomp;
		if (m/^[0-9]+ \[/) {
			($bug,$subject)=split(/ /, $_, 2);
			$bugs{$bug}=$subject;
			push @{$packagelist{$pkg}}, $bug;
		} else {
			($pkg,$sect, $mnt)=split(/ /, $_, 3);
			next if (!defined($pkg));
			$section{$pkg}=$sect;
			$maintainer{$pkg}=$mnt;
		}
	}
	close P;
}


sub readNMUstatus() {
	my $bug;       # Number of current bug
	my $source;    # Source upload which closes this bug.
	my $version;   # Version where this bug was closed.
	my $flag;      # Whether this paragraph has been processed.
	my ($field, $value);

	for (split /\n/, LWP::UserAgent->new->request(HTTP::Request->new(GET => shift))->content) {
		chomp;
		if (m/^$/) {
			$NMU{$bug} = 1;
			$NMU{$bug, "source"} = $source;
			$NMU{$bug, "version"} = $version;
#			$comments{$bug} .= "[FIXED] Fixed package $source is in Incoming\n";
			$flag = 0;
		} else {
			($field, $value) = split(/: /, $_, 2);
			$bug = $value if($field =~ /bug/i);
			$source = $value if($field =~ /source/i);
			$version = $value if($field =~ /version/i);
			$flag = 1;
		}
	}
	if ($flag) {
		$NMU{$bug} = 1;
		$NMU{$bug, "source"} = $source;
		$NMU{$bug, "version"} = $version;
#		$comments{$bug} .= "[FIXED] Fixed package $source in in Incoming\n";
	}
	close P;
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
#	my $section);				# Section for the bug

	"<A HREF=\"http://bugs.debian.org/cgi-bin/bugreport.cgi?archive=no&amp;bug=" .
		urlsanit($number) . '">' . htmlsanit($number) . '</A>';
#	($section=$number) =~ s/([0-9]{2}).*/$1/;
#	"<A HREF=\"${btsURL}/db/$section/$number.html\">$number</A>";
}

sub wwwname() {
	my $name = shift;			# Name of package

	"<A HREF=\"http://bugs.debian.org/cgi-bin/pkgreport.cgi?archive=no&amp;pkg=" .
		urlsanit($name) . '">' . htmlsanit($name) . '</A>';
#	"<A HREF=\"${btsURL}/db/pa/l$name.html\">$name</A>";
}

sub check_worry {
	my ($status) = @_;

	if ($status =~ m/^\[[^]]*I/ or
	    $status =~ m/ \[[^]]*X/ or
            ($status =~ m/ \[[^]]*[OSUE]/ and $status !~ m/ \[[^]]*T/)) {
		return 0;
	}
	return 1;
}

1;
