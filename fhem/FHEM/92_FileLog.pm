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

  $hash->{DefFn}    = "FileLog_Define";
  $hash->{SetFn}    = "FileLog_Set";
  $hash->{GetFn}    = "FileLog_Get";
  $hash->{UndefFn}  = "FileLog_Undef";
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
  $hash->{logfile} = $a[2];
  $hash->{currentlogfile} = $f;
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
    $s = "" if(!defined($s));
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/) {
      my $t = TimeNow();
      $t = $dev->{CHANGETIME}[$i] if(defined($dev->{CHANGETIME}[$i]));
      $t =~ s/ /_/; # Makes it easier to parse with gnuplot

      my $fh = $log->{FH};
      my @t = localtime;
      my $cn = ResolveDateWildcards($log->{logfile},  @t);

      if($cn ne $log->{currentlogfile}) { # New logfile
	$fh->close();
        HandleArchiving($log);
	$fh = new IO::File ">>$cn";
	if(!defined($fh)) {
	  Log(0, "Can't open $cn");
	  return;
	}
	$log->{currentlogfile} = $cn;
	$log->{FH} = $fh;
      }

      print $fh "$t $n $s\n";
      $fh->flush;
      $fh->sync if !($^O eq 'MSWin32'); #not implemented in Windows
    }
  }
  return "";
}

###################################
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

###################################
sub
FileLog_Set($@)
{
  my ($hash, @a) = @_;
  
  return "no set argument specified" if(int(@a) != 2);
  return "Unknown argument $a[1], choose one of reopen"
        if($a[1] ne "reopen");

  my $fh = $hash->{FH};
  my $cn = $hash->{currentlogfile};
  $fh->close();
  $fh = new IO::File ">>$cn";
  return "Can't open $cn" if(!defined($fh));
  $hash->{FH} = $fh;
  return undef;
}

###################################
sub
FileLog_Get($@)
{
  my ($hash, @a) = @_;
  
  return "Usage: get $a[0] <from> <to> <column_list>" if(int(@a) != 4);
  my $fh = new IO::File $hash->{currentlogfile};
  seekTo($fh, $hash, $a[1]);
#  my @arr =
 my $data='';
  while(my $l = <$fh>) {
    last if($l gt $a[2]);
    $data.=$l;
  }
  close($fh);
  return "EOF" if(!defined($data));

  return $data;
}

###################################
sub
seekTo($$$)
{
  my ($fh, $hash, $ts) = @_;

  # If its cached
  if($hash->{pos} && $hash->{pos}{$ts}) {
    $fh->seek($hash->{pos}{$ts}, 0);
    return;
  }

  $fh->seek(0, 2); # Go to the end
  my $upper = $fh->tell;

  my ($lower, $next, $last) = (0, $upper/2, 0);
  while() {                                             # Binary search
    $fh->seek($next, 0);
    my $data = <$fh>;
    if($data !~ m/^20\d\d-\d\d-\d\d_\d\d:\d\d:\d\d /) {
      $next = $fh->tell;
      $data = <$fh>;
    }
    last if($next eq $last);

    $last = $next;
    if($data lt $ts) {
      ($lower, $next) = ($next, ($next+$upper)/2);
    } else {
      ($upper, $next) = ($next, ($lower+$next)/2);
    }
  }
  $hash->{pos}{$ts} = $last;

}

1;
