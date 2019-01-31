# $Id$

package main;

use strict;
use warnings;
use Linux::Inotify2;
use Data::Dumper;

my $missingModule = "";


eval "use File::Find;1" or $missingModule .= "File::Find ";


#######################
# Global variables
my $version = "0.5.8";
our $inotify;
our @watch;


my %gets = (
  "version:noArg"     => "",
); 

my @maskAttrs	=	(
								"IN_ACCESS",
								"IN_MODIFY",
								"IN_ATTRIB",
								"IN_CLOSE_WRITE",
								"IN_CLOSE_NOWRITE",
								"IN_OPEN",
								"IN_MOVED_FROM",
								"IN_MOVED_TO",
								"IN_CREATE",
								"IN_DELETE",
								"IN_DELETE_SELF",
								"IN_MOVE_SELF",
								"IN_ALL_EVENTS",
								"IN_ONLYDIR",
								"IN_CLOSE",
								"IN_MOVE"
								);


sub inotify_Initialize($) {
	my ($hash) = @_;
	$hash->{SetFn}    = "inotify_Set";
	$hash->{GetFn}    = "inotify_Get";
	$hash->{DefFn}    = "inotify_Define";
	$hash->{UndefFn}  = "inotify_Undefine";
	$hash->{AttrFn}   = "inotify_Attr";
	$hash->{NotifyFn} = "inotify_Notify";
	$hash->{ReadFn}		= "inotify_Read";

	$hash->{AttrList} = "disable:1,0 ".
											"do_not_notify ".
											"subfolders:1,0 ".
											"mask:multiple-strict,".join(',',@maskAttrs)." ".
											$readingFnAttributes;
											
	$hash->{NotifyOrderPrefix} = "81-";
											
  ## renew version in reload
  foreach my $d ( sort keys %{ $modules{inotify}{defptr} } ) {
      my $hash = $modules{inotify}{defptr}{$d};
      $hash->{VERSION} = $version;
  }
	
	return undef;
}

sub inotify_Define($$) {
  my ($hash, $def) = @_;
	my $now = time();
	my $name = $hash->{NAME}; 
  
	
	my @a = split( "[ \t][ \t]*", $def );
	
	if ( int(@a) < 2 ) {
    my $msg = "Wrong syntax: define <name> inotify <path> [<regexp>]";
    Log3 $name, 4, $msg;
    return $msg;
  }
  elsif ($a[3] && $a[3]=~/^\*.*/) {
    my $msg = "Wrong syntax: define <name> inotify <path> [<regexp>]. Please provide a valid regexp in <regexp>.";
    Log3 $name, 4, $msg;
    return $msg;
  }
  
  return "Cannot define a inotify device. Perl module(s) $missingModule is/are missing." if ( $missingModule );
  
  $hash->{PATH}=$a[2];
  $hash->{FILES}=$a[3]?$a[3]:undef;
  
  $hash->{VERSION}  = $version;
  
  #$hash->{MID}     = 'da39a3ee5e6dfdss434436657657bdbfef95601890afd80709'; # 
  my $mid           = "inotify_".$a[2].$a[3];
  $mid              =~ s/[^A-Za-z0-9\-_]//g;
  $hash->{MID}      = $mid;
  
  $hash->{NOTIFYDEV}= "global";
  
  $modules{inotify}{defptr}{ $hash->{MID} } = $hash; #MID for internal purposes
  
  ## start polling
	if ($init_done && !IsDisabled($name)) {
	  readingsSingleUpdate($hash,"state","active",1);
	  inotify_Watch($hash);
	}
	
	CommandAttr( undef, $name . ' mask IN_CREATE' ) if ( AttrVal( $name, 'mask', '-' ) eq '-' );
  
  return undef;
}

sub inotify_Undefine($$) {
  my ($hash, $arg) = @_;
	
  RemoveInternalTimer($hash);
	
  return undef;
}

sub inotify_Notify ($$) {
	my ($hash,$dev) = @_;
	
	my $name = $hash->{NAME};

  return if($dev->{NAME} ne "global");
	
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));
	
	if (!IsDisabled($name)) {
	  inotify_Watch($hash);
	  $attr{$name}{"mask"}=~s/\|/,/g;
	}

  return undef;
}

sub inotify_Read($) {
	my ($hash) = @_;
  my $name = $hash->{NAME};
  
  $inotify->poll;
}
 
sub inotify_Set ($@) {
  my ($hash, $name, $cmd, @args) = @_;
	my @sets = ();
	
	push @sets, "active:noArg" if (IsDisabled($name));
	push @sets, "inactive:noArg" if (!IsDisabled($name));
	
	return join(" ", @sets) if ($cmd eq "?");
	
	my $usage = "Unknown argument ".$cmd.", choose one of ".join(" ", @sets) if(scalar @sets > 0);
	
	if (IsDisabled($name) && $cmd !~ /^(active|inactive)?$/) {
		Log3 $name, 3, "inotify ($name): Device is disabled at set Device $cmd";
		return "Device is disabled. Enable it on order to use command ".$cmd;
	}
	if ( $cmd eq "inactive" ) {
		inotify_Inactive($hash);
	}
	elsif ( $cmd eq "active") {
		inotify_Active($hash);
	}
	else {
		return $usage;
	}

	return undef;
}

sub inotify_Get($@) {
  my ($hash, $name, $cmd, @args) = @_;
  my $ret = undef;
  
  if ( $cmd eq "version") {
  	$hash->{VERSION} = $version;
    return "Version: ".$version;
  }
  else {
    $ret ="$name get with unknown argument $cmd, choose one of " . join(" ", sort keys %gets);
  }
 
  return $ret;
}

sub inotify_Attr($@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
	
  my $orig = $attrVal;
	
	my $hash = $defs{$name};
	
	if ( $attrName eq "disable" ) {

		if ( $cmd eq "set" && $attrVal == 1 ) {
			if ($hash->{READINGS}{state}{VAL} ne "inactive") {
				inotify_Inactive($hash);
			}
		}
		elsif ( $cmd eq "del" || $attrVal == 0 ) {
			if ($hash->{READINGS}{state}{VAL} ne "active") {
				inotify_Active($hash,1);
			}
		}
	}
	
	if ( $attrName eq "mask" ) {

		if ( $cmd eq "set" ) {
			my @maskSet = split(',',$attrVal);
			my $check = 1;
			foreach (@maskSet) {
				if (!inotify_inArray(\@maskAttrs,$_)) {
					$check=0;
				}
			}
			return "$name: mask has to be a list of possible masks divided by comma. Select out of ".join(', ',@maskAttrs) if (!$check);
			Log3 $name, 4, "inotify ($name): set attribut $attrName to $attrVal";		
			inotify_setMasks ($hash,$attrVal);
			InternalTimer(gettimeofday()+1, "inotify_Watch", $hash, 0) if (!IsDisabled($name));
		}
		elsif ( $cmd eq "del") {
			delete ($hash->{helper}{"masks"});
			InternalTimer(gettimeofday()+1, "inotify_Watch", $hash, 0) if (!IsDisabled($name));
		}
	}
	
	if ( $attrName eq "subfolders") {
		if ( $cmd eq "set" ) {
			return "$name: $attrName has to be 0 or 1" if ($attrVal !~ /^(0|1)$/);
			Log3 $name, 4, "inotify ($name): set attribut $attrName to $attrVal";
			InternalTimer(gettimeofday()+1, "inotify_Watch", $hash, 0) if (!IsDisabled($name));
		}
		elsif ( $cmd eq "del" ) {
			Log3 $name, 4, "inotify ($name): deleted attribut $attrName";
			InternalTimer(gettimeofday()+1, "inotify_Watch", $hash, 0) if (!IsDisabled($name));
		}
	}
	
	return;
}

sub inotify_Active($;$) {
	my ($hash,$ndel) = @_;
	
	my $name = $hash->{NAME};
	
	$ndel = 0 if (!defined($ndel));
	
	CommandDeleteAttr(undef,"$name disable") if (AttrVal($name,"disable",0)==1 && $ndel==0);
	InternalTimer(gettimeofday()+1, "inotify_Watch", $hash, 0);
	
	readingsSingleUpdate($hash,"state","active",1);
	
	Log3 $name, 3, "inotify ($name): set Device active";
	
	return;
}

sub inotify_Inactive($) {
	my ($hash) = @_;
	
	my $name = $hash->{NAME};
	
	readingsSingleUpdate($hash,"state","inactive",1);
	inotify_CancelWatches($hash);
	
	Log3 $name, 3, "inotify ($name): set Device inactive";
	
	return;
}


sub inotify_Watch($) {
	my ($hash, $arg) = @_;
	
	my $path = $hash->{PATH};
	
	my $name = $hash->{NAME}; 
	
	my $subF = AttrVal($name,"subfolders",0);
	
	inotify_CancelWatches($hash,1);
	
	inotify_setMasks ($hash,AttrVal($name,"mask",undef));

	$inotify = new Linux::Inotify2;
	  
	$inotify->blocking(0);
	
	delete ($hash->{helper}{dirs});
		
	if ($subF!=1) {
		push @{$hash->{helper}{dirs}},$path;
		$watch[0] = $inotify->watch ($path, IN_ALL_EVENTS, sub {
			my $e = shift;
			Log3 $name, 4, "inotify ($name): path to watch ".$path;
			inotify_AnalyseEvent($hash,$e);
		});
	}
	else {
		my $i=0;
		my @dirs = split(/\n/,`find $path -type d`);
		@{$hash->{helper}{dirs}}=@dirs;
		foreach my $entry (@dirs) {
		    Log3 $name, 4, "inotify ($name): path to watch ".$entry;
		   	$watch[$i] = $inotify->watch ($entry, IN_ALL_EVENTS, sub {
					my $e = shift;
					inotify_AnalyseEvent($hash,$e);
				});
				$i++;
		}
	}

	$hash->{FD} = $inotify->fileno;

	$selectlist{$hash->{NAME}} = $hash;
	
	my $watchString = $path;
	if ($hash->{FILES} && $hash->{FILES} ne "") {
		$watchString .= " with the file pattern ".$hash->{FILES};
	}
	
	Log3 $name, 3, "inotify ($name): startet watching ".$watchString;
	
	return;
}

sub inotify_CancelWatches($;$) {
	my ($hash,$noLog) = @_;
	
	$noLog = 0 if (!defined($noLog));
	
	my $path = $hash->{PATH};
	
	my $name = $hash->{NAME}; 
	
	foreach my $w (@watch) {
		$w->cancel;
	}
	my $watchString = $path;
	if ($hash->{FILES} && $hash->{FILES} ne "") {
		$watchString .= " with the file pattern ".$hash->{FILES};
	}
	
	delete($hash->{helper}{events});
	
	Log3 $name, 3, "inotify ($name): stopped watching ".$watchString if (!$noLog);
	return;
}

sub inotify_AnalyseEvent($$) {
	my ($hash,$e) = @_;
	
	my $name = $hash->{NAME}; 
	
	my $mask = "NA";
	
	Log3 $name, 5, "inotify ($name): Fullname ".$e->fullname;
	
	if (($hash->{FILES} && $hash->{FILES}!~/^\*.*/ && $e->fullname=~/$hash->{FILES}/) || !$hash->{FILES}) {
		Log3 $name, 5, "inotify ($name): got ".Dumper($e);
		
		$mask="IN_ACCESS" if ($e->IN_ACCESS);
		$mask="IN_MODIFY" if ($e->IN_MODIFY);
		$mask="IN_ATTRIB" if ($e->IN_ATTRIB);
		$mask="IN_CLOSE_WRITE" if ($e->IN_CLOSE_WRITE);
		$mask="IN_CLOSE_NOWRITE" if ($e->IN_CLOSE_NOWRITE);	
		$mask="IN_OPEN" if ($e->IN_OPEN);
		$mask="IN_MOVED_FROM" if ($e->IN_MOVED_FROM);
		$mask="IN_MOVED_TO" if ($e->IN_MOVED_TO);
		$mask="IN_CREATE" if ($e->IN_CREATE);
		$mask="IN_DELETE" if ($e->IN_DELETE);	
		$mask="IN_DELETE_SELF" if ($e->IN_DELETE_SELF);
		$mask="IN_MOVE_SELF" if ($e->IN_MOVE_SELF);
		$mask="IN_Q_OVERFLOW" if ($e->IN_Q_OVERFLOW);
		
		if (!$hash->{helper}{"masks"} || inotify_inArray(\@{$hash->{helper}{"masks"}},$mask) || inotify_inArray(\@{$hash->{helper}{"masks"}},"IN_ALL_EVENTS")) {	
			
			my $r=0;
			for (my $i=9;$i>=1;$i--) {
				$r=$i-1;
				$hash->{helper}{events}{$i}{"mask"}=$hash->{helper}{events}{$r}{"mask"} if ($hash->{helper}{events}{$r}{"mask"});
				$hash->{helper}{events}{$i}{"file"}=$hash->{helper}{events}{$r}{"file"} if ($hash->{helper}{events}{$r}{"file"});
				$hash->{helper}{events}{$i}{"time"}=$hash->{helper}{events}{$r}{"time"} if ($hash->{helper}{events}{$r}{"time"});
			}
			$hash->{helper}{events}{0}{"mask"}=$mask;
			$hash->{helper}{events}{0}{"file"}=$e->fullname;
			$hash->{helper}{events}{0}{"time"}=TimeNow();
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash,"lastEventFile",$e->fullname);
			readingsBulkUpdate($hash,"lastEventMask",$mask);
			readingsEndUpdate( $hash, 1 );
		
			Log3 $name, 4, "inotify ($name): got event ".$mask." for ".$e->fullname;
			Log3 $name, 1, "inotify ($name): got error ".$mask." for ".$e->fullname if ($mask eq "IN_Q_OVERFLOW");
		}
		else {
			Log3 $name, 4, "inotify ($name): event is not matching any configured mask: ".$mask;
		}
		my $subF = AttrVal($name,"subfolders",0);
		inotify_Watch($hash) if ($subF==1 && ((-d $e->fullname && $mask eq "IN_CREATE") || $mask eq "IN_DELETE"));
	}
	return;
}

sub inotify_setMasks ($$) {
	my ($hash,$attrVal) = @_;
	my $name = $hash->{NAME}; 
	
	$attr{$name}{"mask"}=~s/\|/,/g;
	if ($attrVal) {
		my @masks = split(/\,/,$attrVal);
		@{$hash->{helper}{"masks"}} = @masks;
	}
	
	return undef;
}

sub inotify_inArray {
  my ($arr,$search_for) = @_;
  foreach (@$arr) {
  	return 1 if ($_ eq $search_for);
  }
  return 0;
}

1;

=pod
=item helper
=item summary    uses inotify to track on file events in a given path
=item summary_DE überwacht gegebenen Ordner auf zu konfigurierende events
=begin html

<a name="inotify"></a>
<h3>inotify</h3>
<ul>
    This module collects file events in a given path. Inotify (inode notify) is a Linux kernel subsystem that<br /> 
    acts to extend filesystems to notice changes to the filesystem, and report those changes to applications
    <br /><br />
    Notes:<br />
    <ul>
        <li>Perl modules Data::Dumper, Linux::Inotify2, File::Find have to be 
        installed on the FHEM host.</li>
    </ul>
    <br />
    <a name="inotify_Define"></a>
    <h4>Define</h4>
    <ul>
        <code>define &lt;name&gt; inotify &lt;path&gt; [&lt;file-RegEx&gt;]</code><br />
        <br />
        <ul>
        	<li>path: absolute path to watch</li>
        	<li>file-RegEx: file-Pattern (only watch a group of files)</li>
        </ul>
        <br /><br />

        Example:
        <ul>
            <code>define watchPath inotify /temp testfile.*</code>
        </ul>
    </ul>
    <br />
    <a name="inotify_Set"></a>
    <h4>Set</h4>
    <ul> 
    	<li><b>active</b> - set active - watching starts</li>
    	<li><b>inactive</b> - set iactive - watching stops</li>
    </ul>
    <br />
    <a name="inotify_Attributes"></a>
    <h4>Attributes</h4>
    <ul>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a name="#disable">disable</a></li>
        <li><b>subfolders</b><br />
        set to 1 if you want to watch all subfolders of the given path.<br /></li>
       	<li><b>mask</b><br />
        set your own mask for watching. Komma seperated list.
        See the <a href='http://search.cpan.org/~mlehmann/Linux-Inotify2-1.22/Inotify2.pm'>
        	Linux::Inotify2</a> 
        Doku for possible masks.<br /><br /></li>
    </ul>
    <a name="inotify_Readings"></a>
    <h4>Readings</h4>
    <ul>
    	<li><b>lastEventFile</b><br />
    			the last modified file</li>
    	<li><b>lastEventMask</b><br />
    			the last mask we got in the event</li>
    	<li><b>state</b><br />
    			device is active or inactive</li>
    </ul>
</ul>
=end html
=cut 	