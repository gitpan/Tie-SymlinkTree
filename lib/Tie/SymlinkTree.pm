package Tie::SymlinkTree;
use strict;
use bytes;

our $VERSION = 0.1;

{
    package Tie::SymlinkTree::Array;
    sub id { tied(@{shift()})->id(@_) }
    sub search { tied(@{shift()})->search(@_) }
}

{
    package Tie::SymlinkTree::Hash;
    sub id { tied(%{shift()})->id(@_) }
    sub search { tied(%{shift()})->search(@_) }
}

sub TIEARRAY {
  my ($package, $path) = @_;
  my $self = (ref $package?$package:bless {}, $package);
  $self->{ARRAY} = 1;
  return $self->TIEHASH($path);
}

sub TIEHASH {
  my ($package, $path) = @_;
  die "usage: tie(%hash, 'Tie::SymlinkTree', \$path)" if @_ != 2;
  my $self = (ref $package?$package:bless {}, $package);
  
  $path =~ s#/*$#/#;
  die "$path is invalid" if $path =~ m#/\.\.?(/|$)#;
  die "$path is not a directory" if -e $path and -l $path;
  if (! -e $path) {
    mkdir $path or -d $path or die "Can't create $path: $!";
    symlink(".",$path.".array") if $self->{ARRAY};
  } # race condition: assigning array and hash to one location at the same time
  die "$path has wrong type" if (-e $path.".array" xor $self->{ARRAY});
  $self->{PATH} = $path;
  
  return $self;
}

sub FETCH {
  my ($self, $key) = @_;
  $key =~ s#/#_#g;
  $key =~ s#^\.#_#g;
  if (-d $self->{PATH}.$key) {
	if (-e $self->{PATH}.$key."/.array") {
	    my @tmp;
	    tie @tmp, 'Tie::SymlinkTree', $self->{PATH}.$key;
	    return bless \@tmp, 'Tie::SymlinkTree::Array';
	} else {
	    my %tmp;
	    tie %tmp, 'Tie::SymlinkTree', $self->{PATH}.$key;
	    return bless \%tmp, 'Tie::SymlinkTree::Hash';
	}
  } else {
	return readlink($self->{PATH}.$key);
  }
}


sub STORE {
    my ($self, $key, $val,$recursion) = @_;
    $key =~ s#/#_#g;
    $key =~ s#^\.#_#g;
    die "no objects allowed" if ref($val) && ref($val) != 'HASH' && ref($val) != 'ARRAY';
    if (!defined($val)) {
  	open(my $fh,'>',$self->{PATH}.".$$~".$key);
	close($fh);
	rename($self->{PATH}.".$$~".$key,$self->{PATH}.$key) or $recursion or do {$self->DELETE($key);$self->STORE($key,$val,1);};
    } elsif (!ref($val)) {
  	$val =~ s/\0//g;
	$val = ' ' if !length($val);
  	symlink($val,$self->{PATH}.".$$~".$key);
	rename($self->{PATH}.".$$~".$key,$self->{PATH}.$key) or $recursion or do {$self->DELETE($key);$self->STORE($key,$val,1);};
    } elsif (ref($val) eq 'ARRAY' || ref($val) eq 'Tie::SymlinkTree::Array') {
  	my @tmp = @$val;
	eval { tie @$val, 'Tie::SymlinkTree', $self->{PATH}.$key; };
	if (!$recursion && $@) {$self->DELETE($key);$self->STORE($key,$val,1);}
	@$val = @tmp;
    } else {
  	my %tmp = %$val;
	eval { tie %$val, 'Tie::SymlinkTree', $self->{PATH}.$key; };
	if (!$recursion && $@) {$self->DELETE($key);$self->STORE($key,$val,1);}
	%$val = %tmp;
    }
}


sub DELETE {
  my ($self, $key) = @_;
  $key =~ s#/#_#g;
  $key =~ s#^\.#_#g;
  my $val = $self->FETCH($key);
  if (UNIVERSAL::isa($val,'ARRAY')) {
  	my @tmp = @$val;
	for my $i (0..$#tmp) {
	    $tmp[$i] = delete $val->[$i];
	}
	$val = \@tmp;
  } elsif (UNIVERSAL::isa($val,'HASH')) {
  	my %tmp = %$val;
	for my $k (keys %tmp) {
	    $tmp{$k} = delete $val->{$k};
	}
	$val = \%tmp;
  }
  unlink $self->{PATH}.$key;
  rmdir $self->{PATH}.$key;
  return $val;
}

sub CLEAR {
  my ($self) = @_;
  $self->lock;
  unlink(glob($self->{PATH}."*"));
  rmdir(glob($self->{PATH}."*"));
  $self->unlock;
}

sub EXISTS {
  my ($self, $key) = @_;
  $key =~ s#/#_#g;
  $key =~ s#^\.#_#g;
  return -e $self->{PATH}.$key || -l $self->{PATH}.$key;
}


sub DESTROY {
}


sub FIRSTKEY {
  my ($self) = @_;
  
  my $dh;
  opendir($dh,$self->{PATH});
  $self->{HANDLE} = $dh;
  my $entry;
  while (defined ($entry = readdir($self->{HANDLE}))) {
    return $entry unless (substr($entry,0,1) eq '.');
  }
  return;
}


sub NEXTKEY {
  my ($self) = @_;
  my $entry;
  while (defined ($entry = readdir($self->{HANDLE}))) {
    return $entry unless (substr($entry,0,1) eq '.');
  }
  return;
}

sub FETCHSIZE {
  my ($self) = @_;
  my $dh;
  opendir($dh,$self->{PATH});
  my $max = -1;
  my $entry;
  while (defined ($entry = readdir($dh))) {
    next if substr($entry,0,1) eq '.';
    $max = int($entry) if $entry > $max;
  }
  return $max+1;
}

sub STORESIZE {
  my ($self, $size) = @_;
  $self->lock;
  $size = int($size);
  while (-e $self->{PATH}.$size) {
  	$self->DELETE($size);
	$size++;
  }
  $self->unlock;
}

sub EXTEND { }
sub UNSHIFT { scalar shift->SPLICE(0,0,@_) }
sub SHIFT { shift->SPLICE(0,1) }

sub PUSH {
  my ($self, $value) = @_;
  $self->lock;
  my $key = $self->FETCHSIZE;
  $self->STORE($key,$value);
  $self->unlock;
  return $key+1;
}

sub POP {
  my ($self, $value) = @_;
  $self->lock;
  my $key = $self->FETCHSIZE-1;
  my $val = $self->FETCH($key);
  $self->DELETE($key);
  $self->unlock;
  return $val;
}

sub SPLICE {
    my $self = shift;
    $self->lock;
    my $size  = $self->FETCHSIZE;
    my $off = (@_) ? shift : 0;
    $off += $size if ($off < 0);
    my $len = (@_) ? shift : $size - $off;
    $len += $size - $off if $len < 0;
    my @result;
    for (my $i = 0; $i < $len; $i++) {
        push(@result,$self->FETCH($off+$i));
    }
    $off = $size if $off > $size;
    $len -= $off + $len - $size if $off + $len > $size;
    if (@_ > $len) {
        # Move items up to make room
        my $d = @_ - $len;
        my $e = $off+$len;
        for (my $i=$size-1; $i >= $e; $i--) {
	    rename($self->{PATH}.$i,$self->{PATH}.($i+$d));
        }
    }
    elsif (@_ < $len) {
        # Move items down to close the gap
        my $d = $len - @_;
        my $e = $off+$len;
        for (my $i=$off+$len; $i < $size; $i++) {
	    rename($self->{PATH}.$i,$self->{PATH}.($i-$d));
        }
    }
    for (my $i=0; $i < @_; $i++) {
        $self->STORE($off+$i,$_[$i]);
    }
    $self->unlock;
    return wantarray ? @result : pop @result;
}

sub lock {
  my ($self) = @_;
  my $i = 0;
  while (symlink($$,$self->{PATH}.".lock") && $i++ < 10) {
  	sleep(1);
  }
}

sub unlock {
  my ($self) = @_;
  unlink($self->{PATH}.".lock");
}

sub id {
    my ($self) = @_;
    return ($self->{PATH} =~ m{/([^/]+)/$})[0];
}

sub search {
    my ($self,$code) = @_;
    my $key = $self->FIRSTKEY;
    if (wantarray) {
	my @res;
	while (defined $key) {
	    my $val = $self->FETCH($key);
	    local $_ = $val;
	    push @res, $val if $code->();
	    $key = $self->NEXTKEY;
	}
	return @res
    } else {
	while (defined $key) {
	    my $val = $self->FETCH($key);
	    local $_ = $val;
	    return $val if $code->();
	    $key = $self->NEXTKEY;
	}
	return undef;
    }
}

1;

__END__

=head1 NAME

Tie::SymlinkTree - interface to a directory tree of symlinks

=head1 SYNOPSIS

 use Tie::SymlinkTree;
 tie %hash, 'Tie::SymlinkTree', '/some_directory';
 $hash{'one'} = "some text";         # Creates symlink /some_directory/one
                                     # with contents "some text"
 $hash{'bar'} = "some beer";
 $hash{'two'} = [ "foo", "bar", "baz" ];
  
 # Warning: experimental and subject to change without notice:
 my @entries = tied(%hash)->search(sub { m/some/ }); # returns ("some text","some beer")
 my $firstmatch = $hash{'two'}->search(sub { m/b/ }); # returns "bar"
 print $firstmatch->id; # prints out "1", as it is element nr. 1
 
=head1 DESCRIPTION

The Tie::SymlinkTree module is a TIEHASH/TIEARRAY interface which lets you tie a
Perl hash or array to a directory on the filesystem.  Each entry in the hash
represents a symlink in the directory.

To use it, tie a hash to a directory:

 tie %hash, "Tie::SymlinkTree", "/some_directory";

Any changes you make to the hash will create, modify, or delete
symlinks in the given directory. 'undef' values are represented by
an empty file instead of a symlink.

If the directory itself doesn't exist C<Tie::SymlinkTree> will
create it (or die trying).

This module is fully reentrant, multi-processing safe, and still real
fast (as the OS permits; a modern filesystem is recommended when storing
lots of keys/array elements).

=head1 CAVEATS

C<Tie::SymlinkTree> is restricted in what it can store: Keys may not
contain "/" or start with a dot, values may not contain "\0" and are
limited in length, depending on OS limits. You may store scalars, hashrefs
and arrayrefs, these will be transparently mapped to subdirs as neccessary,
nested as deeply as you wish, but no objects are allowed. (Order me a pizza
to get any of these missing features ;-)

This module will probably only work on UNIXish systems.

How fast are ties? I can't tell. That is the most important bottleneck left.

=head1 RATIONALE

This module was designed for quick prototyping of multi-processing
applications as often found in CGI scripts. It uses the fastest way to store and
retrive small bits of information: Symlinks. "Small bits" is the key: most
web-centric tasks involve a need for permanent storage, yet the usage pattern
and data set size usually doesn't require a full SQL database.

Setting up a database schema and designing queries can be quite tedious when you're
doing a prototype. A tie is much easier to use, but the usual Tie::* modules
are lacking mp-safety or performance (or both), since they usually store the
hash data in one big chunk. C<Tie::SymlinkTree> avoids this bottleneck and source
of bugs by only using atomic OS primitives on individual keys. Locking is not
completely avoidable, but reduces to a minimum.

The result is a reasonably fast module that scales very nicely. One day I may
write an API-compatible counterpart that uses SQL as storage, then you'd get an
easy upgrade path.

=head1 AUTHOR and LICENSE

Copyright (C) 2004, Jörg Walter.

This plugin is licensed under either the GNU GPL Version 2, or the Perl Artistic
License.

=cut

