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

use lib qw(/org/bugs.debian.org/perl/);
use LWP::UserAgent;
use Debbugs::MIME qw(decode_rfc1522 encode_rfc1522);
use Debbugs::Packages;
use Debbugs::Versions;
use Fcntl qw(O_RDONLY);
require bugcfg;

sub readcomments() {
# Read bug commentary 
# It is in paragraph format, with the first line of each paragraph being
# the bug number or package name to which the comment applies.
# Prefix a bug number with a * to force it to be listed even if it's closed.
# (This deals with prematurely closed bugs)

	local($index);					# Bug-number for current comment
	local($file);					# Name of comments-file

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
	local ($pkg);					# Name of package
	local ($mnt);					# Maintainer name & email

	open(M, $maintainerlist) or die "open $maintainerlist: $!\n";
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
	local($root);					# Root of archive we are scanning
	local($archive);				# Name of archive we are scanning
	local($sect);					# Name of current section

	$root=shift;
	$archive=shift;
	for $sect ( @sections) {
		open(P, "zcat $root/$sect/source/Sources.gz|")
			or die open "open: $sect / $arch sourcelist: $!\n";
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
	local($root);					# Root of archive we are scanning
	local($archive);				# Name of archive we are scanning
	local($sect);					# Name of current section
	local($arch);					# Name of current architecture

	$root=shift;
	$archive=shift;
	for $arch ( @architectures ) {
		for $sect ( @sections) {
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
	local($file);
	local($archive);

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
	open(P, $pseudolist) or die("open $pseudolist: $!\n");
	while (<P>) {
		chomp;
		s/\s.*//;
		$section{$_} = "pseudo";
	}
	close(P);
}


sub scanspool() {
	local(@dirs);
	local($dir);

	chdir($spooldir) or die "chdir $spooldir: $!\n";

	opendir(DIR, $spooldir) or die "opendir $spooldir: $!\n";
	@dirs=grep(m/^\d+$/,readdir(DIR));
	closedir(DIR);

	for $dir (@dirs) {
		scanspooldir("$spooldir/$dir");
	}

}

sub scanspooldir() {
	local($dir)		= @_;
	local($f);			# While we're currently processing
	local(@list);		# List of files to process
	local($skip);		# Flow control
	local($walk);		# index variable
	local($taginfo);	# Tag info

	chdir($dir) or die "chdir $dir: $!\n";

	opendir(DIR, $dir) or die "opendir $dir: $!\n";
	@list = grep { s/\.summary$// }
			grep { m/^\d+\.summary$/ } 
			readdir(DIR);
	closedir(DIR);

	for $f (@list) {
		next if $exclude{$f};			# Check the list of bugs to skip
	
		my $bug = readbug("$f.summary");
		next if (!defined($bug));
		
		$skip=1;
		for $walk (@priorities) {
			$skip=0 if $walk eq $bug->{'severity'};
		}

		my @tags = split(' ', $bug->{'keywords'});
		for $tag (@tags) {
			for $s (@skiptags) {
				$skip=1 if $tag eq $s;
			}
		}
		next if $skip==1;
		
		my $oldstable_tag    = grep(/^woody$/, @tags);
		my $stable_tag       = grep(/^sarge$/, @tags);
		my $testing_tag      = grep(/^etch$/, @tags);
		my $unstable_tag     = grep(/^sid$/, @tags);
		my $experimental_tag = grep(/^experimental$/, @tags);

		# default according to dondelelcaro 2006-11-11
		if (!$oldstable_tag && !$stable_tag && !$testing_tag && !$unstable_tag && !$experimental_tag) {
			$testing_tag = 1;
			$unstable_tag = 1;
			$experimental_tag = 1;
		}

		# only bother to check the versioning status for the distributions indicated by the tags 
		$status_oldstable    = getbugstatus($bug, undef, 'oldstable')    if ($oldstable_tag);
		$status_stable       = getbugstatus($bug, undef, 'stable')       if ($stable_tag);
		$status_testing      = getbugstatus($bug, undef, 'testing')      if ($testing_tag);
		$status_unstable     = getbugstatus($bug, undef, 'unstable')     if ($unstable_tag);
		$status_experimental = getbugstatus($bug, undef, 'experimental') if ($experimental_tag);

		$relinfo = "";
		$relinfo .= (($oldstable_tag    && $status_oldstable->{'pending'}    eq 'pending') ? "O" : "");
		$relinfo .= (($stable_tag       && $status_stable->{'pending'}       eq 'pending') ? "S" : "");
		$relinfo .= (($testing_tag      && $status_testing->{'pending'}      eq 'pending') ? "T" : "");
		$relinfo .= (($unstable_tag     && $status_unstable->{'pending'}     eq 'pending') ? "U" : "");
		$relinfo .= (($experimental_tag && $status_experimental->{'pending'} eq 'pending') ? "E" : "");
		
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

		for $package (split /[,\s]+/, $bug->{'package'}) {
			$_= $package; y/A-Z/a-z/; $_= $` if m/[^-+._a-z0-9]/;
			if (not defined $section{$_}) {
				if (defined $debbugssection{$_}) {
					$relinfo .= "X";
				} else {
					next;	# Skip unavailable packages
				}
			}

			$packagelist{$_} .= " $f";
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
	local ($bug);		# Number of current bug
	local ($subject);	# Subject for current bug
	local ($pkg);		# Name of current package
	local ($file);		# Name of statusfile
	local ($sect);		# Section of current package
	local ($mnt);		# Maintainer of current package

	$file=shift;
	open(P, $file) or die "open $file: $!";
	while (<P>) {
		chomp;
		if (m/^[0-9]+ \[/) {
			($bug,$subject)=split(/ /, $_, 2);
			$bugs{$bug}=$subject;
			$packagelist{$pkg} .= "$bug ";
		} else {
			($pkg,$sect, $mnt)=split(/ /, $_, 3);
			$section{$pkg}=$sect;
			$maintainer{$pkg}=$mnt;
		}
	}
	close P;
}


sub readNMUstatus() {
	local ($bug);       # Number of current bug
	local ($source);    # Source upload which closes this bug.
	local ($version);   # Version where this bug was closed.
	local ($flag);      # Whether this paragraph has been processed.
	local ($field, $value);

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
	local ($number) = shift;		# Number of bug to html-ize
#	local ($section);				# Section for the bug

	"<A HREF=\"http://bugs.debian.org/cgi-bin/bugreport.cgi?archive=no&amp;bug=" .
		urlsanit($number) . '">' . htmlsanit($number) . '</A>';
#	($section=$number) =~ s/([0-9]{2}).*/$1/;
#	"<A HREF=\"${btsURL}/db/$section/$number.html\">$number</A>";
}

sub wwwname() {
	local ($name) = shift;			# Name of package

	"<A HREF=\"http://bugs.debian.org/cgi-bin/pkgreport.cgi?archive=no&amp;pkg=" .
		urlsanit($name) . '">' . htmlsanit($name) . '</A>';
#	"<A HREF=\"${btsURL}/db/pa/l$name.html\">$name</A>";
}

# === everything from here is adapted from debbugs, and should probably be merged
# === back at some point

my %_binarytosource;
my %_binarytosourcecache = ();
sub binarytosource {
    my ($binname, $binver, $binarch) = @_;

    # TODO: This gets hit a lot, especially from buggyversion() - probably
    # need an extra cache for speed here.

    if (tied %_binarytosource or
	    tie %_binarytosource, 'MLDBM',
		$Debbugs::Packages::gBinarySourceMap, O_RDONLY) {
		if (!exists($_binarytosourcecache{$binname})) {
			$_binarytosourcecache{$binname} = \%{ $_binarytosource{$binname} };
		}
		
		if (defined $_binarytosourcecache{$binname} and
			exists $_binarytosourcecache{$binname}{$binver}) {
			if (defined $binarch) {
				my $src = $_binarytosourcecache{$binname}{$binver}{$binarch};
				return () unless defined $src; # not on this arch
				# Copy the data to avoid tiedness problems.
				return [@$src];
			} else {
				# Get (srcname, srcver) pairs for all architectures and
				# remove any duplicates. This involves some slightly tricky
				# multidimensional hashing; sorry. Fortunately there'll
				# usually only be one pair returned.
				my %uniq;
				for my $ar (keys %{$_binarytosourcecache{$binname}{$binver}}) {
					my $src = $_binarytosourcecache{$binname}{$binver}{$ar};
					next unless defined $src;
					$uniq{$src->[0]}{$src->[1]} = 1;
				}
				my @uniq;
				for my $sn (sort keys %uniq) {
					push @uniq, [$sn, $_] for sort keys %{$uniq{$sn}};
				}
				return @uniq;
			}
		}
    }

    # No $gBinarySourceMap, or it didn't have an entry for this name and
    # version.
    return ();
}

my %_versionobj;
sub buggyversion {
    my ($bug, $ver, $status) = @_;
    return '' unless defined $versionpkgdir;
    my $src = getpkgsrc()->{$status->{package}};
    $src = $status->{package} unless defined $src;

    my $tree;
    if (exists $_versionobj{$src}) {
        $tree = $_versionobj{$src};
    } else {
        $tree = Debbugs::Versions->new(\&DpkgVer::vercmp);
        my $srchash = substr $src, 0, 1;
        if (open VERFILE, "< $versionpkgdir/$srchash/$src") {
            $tree->load(\*VERFILE);
            close VERFILE;
        }
        $_versionobj{$src} = $tree;
    }

    my @found = makesourceversions($status->{package}, undef,
                                   @{$status->{found_versions}});
    my @fixed = makesourceversions($status->{package}, undef,
                                   @{$status->{fixed_versions}});

    return $tree->buggy($ver, \@found, \@fixed);
}

sub getbugstatus {
    my ($bug,$common_version,$common_dist) = @_;
	my %status = %$bug;

    my @versions;
    if (defined $common_version) {
        @versions = ($common_version);
    } elsif (defined $common_dist) {
        @versions = getversions($status{package}, $common_dist, $common_arch);
    }
    
	if (not @versions) {
		$status{"pending"} = 'absent';
		return \%status;
	}

    # TODO: This should probably be handled further out for efficiency and
    # for more ease of distinguishing between pkg= and src= queries.
    my @sourceversions = makesourceversions($status{package}, $common_arch,
                                            @versions);

	$status{"pending"} = 'pending';

    if (@sourceversions) {
        # Resolve bugginess states (we might be looking at multiple
        # architectures, say). Found wins, then fixed, then absent.
        my $maxbuggy = 'absent';
        for my $version (@sourceversions) {
            my $buggy = buggyversion($bugnum, $version, \%status);
            if ($buggy eq 'found') {
                $maxbuggy = 'found';
                last;
            } elsif ($buggy eq 'fixed' and $maxbuggy ne 'found') {
                $maxbuggy = 'fixed';
            }
        }
        if ($maxbuggy eq 'absent') {
            $status{"pending"} = 'absent';
        } elsif ($maxbuggy eq 'fixed') {
            $status{"pending"} = 'done';
        }
    }
    
    if (length($status{done}) and
            (not @sourceversions or not @{$status{fixed_versions}})) {
        $status{"pending"} = 'done';
    }
    
    return \%status;
}

my %_versions;
my %_binversioncache = ();
sub getversions {
    my ($pkg, $dist, $arch) = @_;
    return () unless defined $versionindex;
    $dist = 'unstable' unless defined $dist;

    unless (tied %_versions) {
        tie %_versions, 'MLDBM', $versionindex, O_RDONLY
            or die "can't open versions index: $!";
    }

	if (!exists($_binversioncache{$pkg})) {
		$_binversioncache{$pkg} = \%{ $_versions{$pkg} };
	}
	#if ($pkg eq 'atlas3-base') {
	#	require Data::Dumper;
	#	print STDERR Data::Dumper::Dumper($_versions{$pkg});
	#}

	if (defined $arch and exists $_binversioncache{$pkg}{$dist}{$arch}) {
		my $ver = $_binversioncache{$pkg}{$dist}{$arch};
		if (defined($ver)) {
			return $ver;
		} else {
			return ();
		}
	} else {
		my %uniq;
		for my $ar (keys %{$_binversioncache{$pkg}{$dist}}) {
			$uniq{$_binversioncache{$pkg}{$dist}{$ar}} = 1 unless ($ar eq 'source' or $ar eq 'm68k' or $ar eq 'hurd-i386');
		}
		if (%uniq) {
			return keys %uniq;
		} elsif (exists $_binversioncache{$pkg}{$dist}{source}) {
			# Maybe this is actually a source package with no corresponding
			# binaries?
			return $_binversioncache{$pkg}{$dist}{source};
		} else {
			return ();
		}
	}
}

my %_sourceversioncache = ();
sub makesourceversions {
    my $pkg = shift;
    my $arch = shift;
    my %sourceversions;

    for my $version (@_) {
        if ($version =~ m[/]) {
            # Already a source version.
            $sourceversions{$version} = 1;
        } else {
            my $cachearch = (defined $arch) ? $arch : '';
            my $cachekey = "$pkg/$cachearch/$version";
            if (exists($_sourceversioncache{$cachekey})) {
                for my $v (@{$_sourceversioncache{$cachekey}}) {
					$sourceversions{$v} = 1;
				}
				next;
			}

			my @srcinfo = binarytosource($pkg, $version, $arch);
			unless (@srcinfo) {
				# We don't have explicit information about the
				# binary-to-source mapping for this version (yet). Since
				# this is a CGI script and our output is transient, we can
				# get away with just looking in the unversioned map; if it's
				# wrong (as it will be when binary and source package
				# versions differ), too bad.
				my $pkgsrc = getpkgsrc();
				if (exists $pkgsrc->{$pkg}) {
					@srcinfo = ([$pkgsrc->{$pkg}, $version]);
				} elsif (getsrcpkgs($pkg)) {
					# If we're looking at a source package that doesn't have
					# a binary of the same name, just try the same version.
					@srcinfo = ([$pkg, $version]);
				} else {
					next;
				}
			}
			$sourceversions{"$_->[0]/$_->[1]"} = 1 foreach @srcinfo;
			$_sourceversioncache{$cachekey} = [ map { "$_->[0]/$_->[1]" } @srcinfo ];
		}
	}

    return sort keys %sourceversions;
}

my %fields = (originator => 'submitter',
              date => 'date',
              subject => 'subject',
              msgid => 'message-id',
              'package' => 'package',
              keywords => 'tags',
              done => 'done',
              forwarded => 'forwarded-to',
              mergedwith => 'merged-with',
              severity => 'severity',
              owner => 'owner',
              found_versions => 'found-in',
              fixed_versions => 'fixed-in',
              blocks => 'blocks',
              blockedby => 'blocked-by',
             );

# Fields which need to be RFC1522-decoded in format versions earlier than 3.
my @rfc1522_fields = qw(originator subject done forwarded owner);

sub readbug {
    my ($location) = @_;
    if (!open(S,$location)) { return undef; }

    my %data;
    my @lines;
    my $version = 2;
    local $_;

    while (<S>) {
        chomp;
        push @lines, $_;
        $version = $1 if /^Format-Version: ([0-9]+)/i;
    }

    # Version 3 is the latest format version currently supported.
    return undef if $version > 3;

    my %namemap = reverse %fields;
    for my $line (@lines) {
        if ($line =~ /(\S+?): (.*)/) {
            my ($name, $value) = (lc $1, $2);
            $data{$namemap{$name}} = $value if exists $namemap{$name};
        }
    }
    for my $field (keys %fields) {
        $data{$field} = '' unless exists $data{$field};
    }

    close(S);

    $data{severity} = $gDefaultSeverity if $data{severity} eq '';
    $data{found_versions} = [split ' ', $data{found_versions}];
    $data{fixed_versions} = [split ' ', $data{fixed_versions}];

    if ($version < 3) {
		for my $field (@rfc1522_fields) {
			$data{$field} = decode_rfc1522($data{$field});
		}
    }

    return \%data;
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
