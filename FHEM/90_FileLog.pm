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

  $hash->{Category}= "LOG";

  $hash->{DefFn}   = "FileLog_Define";
  $hash->{UndefFn} = "FileLog_Undef";
  $hash->{LogFn}   = "FileLog_Log";
}


#####################################
sub
FileLog_Define($@)
{
  my ($hash, @a) = @_;
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
  my ($log, $dev) = @_;

  my $n = $dev->{NAME};
  my $re = $log->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});

  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/) {
      my $t = TimeNow();
      $t = $dev->{CHANGETIME}[$i] if(defined($dev->{CHANGETIME}[$i]));
      $t =~ s/ /_/;

      my $fh = $log->{FH};
      my @t = localtime;
      my $cn = ResolveDateWildcards($log->{FILENAME},  @t);

      if($cn ne $log->{CURRENT}) { # New logfile
	$fh->close();
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
}

1;
