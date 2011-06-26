package main;
use strict;
use warnings;
use IO::Socket;

sub CommandUpdatefhem($$);

my $server = "fhem.de:80";
my $sdir   = "/fhemupdate";
my $ftime  = "filetimes.txt";


#####################################
sub
updatefhem_Initialize($$)
{
  my %lhash = ( Fn=>"CommandUpdatefhem",
                Hlp=>",update fhem from the nightly CVS checkout" );
  $cmds{updatefhem} = \%lhash;
}


#####################################
sub
CommandUpdatefhem($$)
{
  my ($cl, $param) = @_;
  my $lt = "";
  my $ret = "";

  #my $moddir = "$attr{global}{modpath}/FHEM";
  my $moddir = "XXX";

  # Read in the OLD filetimes.txt
  my %oldtime;
  if(open FH, "$moddir/$ftime") {
    while(my $l = <FH>) {
      chomp($l);
      my ($ts, $fs, $file) = split(" ", $l, 3);
      $oldtime{$file} = $ts;
    }
    close(FH);
  }

  my $filetimes = GetHttpFile($server, "$sdir/$ftime");
  return "Can't get $ftime from $server" if(!$filetimes);

  my (%filetime, %filesize);
  foreach my $l (split("[\r\n]", $filetimes)) {
    chomp($l);
    return "Corrupted filetimes.txt file"
        if($l !~ m/^20\d\d-\d\d-\d\d_\d\d:\d\d:\d\d /);
    my ($ts, $fs, $file) = split(" ", $l, 3);
    $filetime{$file} = $ts;
    $filesize{$file} = $fs;
  }

  my @reload;
  my $newfhem = 0;
  foreach my $f (sort keys %filetime) {
    if($param) {
      next if($f ne $param);
    } else {
      next if($oldtime{$f} && $filetime{$f} eq $oldtime{$f});
    }
    my $localfile = "$moddir/$f";
    my $remfile = $f;

    if($f eq "fhem.pl") {
      $ret .= "updated fhem.pl, restart of fhem is required\n";
      $newfhem = 1;
      $localfile = $0;
      $remfile = "$f.txt";
    }

    if($f =~ m/^(\d\d_)(.*).pm$/) {
      my $m = $2;
      push @reload, $f if($modules{$m} && $modules{$m}{LOADED});
    }

    my $content = GetHttpFile($server, "$sdir/$remfile");
    return "File size for $f does not correspond to filetimes.txt entry"
        if(length($content) ne $filesize{$f});
    open(FH,">$localfile") || return "Can't write $localfile";
    print FH $content;
    close(FH)
  }

  return "Can't write $moddir/$ftime" if(!open(FH, ">$moddir/$ftime"));
  print FH $filetimes;
  close(FH);

  if(!$newfhem) {
    foreach my $m (@reload) {
      $ret .= "reloading module $m\n";
      my $cret = CommandReload($cl, $m);
      return "$ret$cret" if($cret);
    }
  }
  
  return $ret;
}

sub
GetHttpFile($$)
{
  my ($host, $filename) = @_;

  my $server = IO::Socket::INET->new(PeerAddr => $server);
  if(!$server) {
    Log 1, "Can't connect to $server\n";
    return undef;
  }
  $host =~ s/:.*//;
  my $req = "GET $filename HTTP/1.0\r\nHost: $host\r\n\r\n\r\n";
  syswrite $server, $req;
  my ($buf, $ret);
  while(sysread($server, $buf, 65536) > 0) {
    $ret .= $buf;
  }
  $ret=~ s/.*?\r\n\r\n//s;
  Log 1, "Got http://$host$filename, length: ".length($ret);
  return $ret;
}

1;
