##############################################
package main;

use strict;
use warnings;
use IO::File;

#####################################
sub
FileLog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "FileLog_Define";
  $hash->{UndefFn} = "FileLog_Undef";
  $hash->{NotifyFn} = "FileLog_Log";
  $hash->{AttrFn}   = "FileLog_Attr";
  # logtype is used by the frontend
  $hash->{AttrList} = "disable:0,1 logtype nrarchive archivedir archivecmd";
}


#####################################
sub
FileLog_Define($@)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $fh;

  return "wrong syntax: define <name> FileLog filename regexp" if(int(@a) != 4);

  eval { "Hallo" =~ m/^$a[3]$/ };
  return "Bad regexp: $@" if($@);

  my @t = localtime;
  my $f = ResolveDateWildcards($a[2], @t);
  $fh = new IO::File ">>$f";
  return "Can't open $f" if(!defined($fh));

  $hash->{FH} = $fh;
  $hash->{REGEXP} = $a[3];
  $hash->{FILENAME} = $a[2];
  $hash->{CURRENT} = $f;
  $hash->{STATE} = "active";

  return undef;
}

#####################################
sub
FileLog_Undef($$)
{
  my ($hash, $name) = @_;
  close($hash->{FH});
  return undef;
}

sub
HandleArchiving($)
{
  my ($log) = @_;
  my $ln = $log->{NAME};
  return if(!$attr{$ln});

  # If there is a command, call that
  my $cmd = $attr{$ln}{archivecmd};
  if($cmd) {
    $cmd =~ s/%/$log->{CURRENT}/g;
    Log 2, "Archive: calling $cmd"; 
    system($cmd);
    return;
  }

  my $nra = $attr{$ln}{nrarchive};
  my $ard = $attr{$ln}{archivedir};
  return if(!defined($nra));

  # If nrarchive is set, then check the last files:
  # Get a list of files:

  my ($dir, $file);
  if($log->{FILENAME} =~ m,^(.+)/([^/]+)$,) {
    ($dir, $file) = ($1, $2);
  } else {
    ($dir, $file) = (".", $log->{FILENAME});
  }

  $file =~ s/%./.+/g;
  return if(!opendir(DH, $dir));
  my @files = sort grep {/^$file$/} readdir(DH);
  closedir(DH);

  my $max = int(@files)-$nra;
  for(my $i = 0; $i < $max; $i++) {
    if($ard) {
      Log 2, "Moving $files[$i] to $ard";
      rename("$dir/$files[$i]", "$ard/$files[$i]");
    } else {
      Log 2, "Deleting $files[$i]";
      unlink("$dir/$files[$i]");
    }
  }
}

#####################################
sub
FileLog_Log($$)
{
  # Log is my entry, Dev is the entry of the changed device
  my ($log, $dev) = @_;

  my $ln = $log->{NAME};
  return if($attr{$ln} && $attr{$ln}{disable});

  my $n = $dev->{NAME};
  my $re = $log->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
Log 1, "FL: Checking $n:$s against $re";
    $s = "" if(!defined($s));
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/) {
Log 1, "FL: Logging";
      my $t = TimeNow();
      $t = $dev->{CHANGETIME}[$i] if(defined($dev->{CHANGETIME}[$i]));
      $t =~ s/ /_/; # Makes it easier to parse with gnuplot

      my $fh = $log->{FH};
      my @t = localtime;
      my $cn = ResolveDateWildcards($log->{FILENAME},  @t);

      if($cn ne $log->{CURRENT}) { # New logfile
	$fh->close();
        HandleArchiving($log);
	$fh = new IO::File ">>$cn";
	if(!defined($fh)) {
	  Log(0, "Can't open $cn");
	  return;
	}
	$log->{CURRENT} = $cn;
	$log->{FH} = $fh;
      }

      print $fh "$t $n $s\n";
      $fh->flush;
      $fh->sync;
    }
  }
  return "";
}

sub
FileLog_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");

  return undef;
}
1;
