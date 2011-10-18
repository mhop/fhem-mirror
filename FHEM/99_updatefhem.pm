package main;
use strict;
use warnings;
use IO::Socket;

sub CommandUpdatefhem($$);
sub CommandCULflash($$);

my $server = "fhem.de:80";
my $sdir   = "/fhemupdate";
my $ftime  = "filetimes.txt";
my $dfu    = "dfu-programmer";


#####################################
sub
updatefhem_Initialize($$)
{
  my %fhash = ( Fn=>"CommandUpdatefhem",
                Hlp=>",update fhem from the nightly CVS" );
  $cmds{updatefhem} = \%fhash;

  my %chash = ( Fn=>"CommandCULflash",
                Hlp=>"<cul> <type>,flash the CUL from the nightly CVS" );
  $cmds{CULflash} = \%chash;
}


#####################################
sub
CommandUpdatefhem($$)
{
  my ($cl, $param) = @_;
  my $lt = "";
  my $ret = "";
  my $moddir = "$attr{global}{modpath}/FHEM";
  #my $moddir = "XXX";

  ## backup by RueBe
  my @commandchain = split(/ +/,$param);

  #  Check if the first parameter is "backup"
  if(uc($commandchain[0]) eq "BACKUP") {
    my $backupdir = AttrVal("global", "backupdir", "/tmp/FHEM_Backup");
    # create the backupfolder
    if(!-d $backupdir) {
      if(!mkdir($backupdir)) {
        return "Can't create backup folder $!";
      }
    }
    # full backup, for compatibility, we use the native copy unction, not
    # dircopy from File::Copy::Recursive
    if($commandchain[1] eq "") {
      opendir(IMD, $moddir) || return "Cannot open fhem-module directory";
      my @files= readdir(IMD);
      closedir(IMD);
      my $f;

      foreach $f (@files) {
        unless ( ($f eq ".") || ($f eq "..") ) {
          my $ret = copy("$moddir/$f", "$backupdir/$f");
        }
      }
      $param = "";

    } else {
      # one file backup
      copy("$moddir/$commandchain[1]", "$backupdir/$commandchain[1]");
      # recreate $param for further use
      $param = $commandchain[1];
    }
  }

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
      next if($f =~ m/.hex$/);  # skip firmware files
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
CommandCULflash($$)
{
  my ($cl, $param) = @_;
  my $moddir = "$attr{global}{modpath}/FHEM";
  #my $moddir = "XXX";

  my %ctypes = (
    CUL_V2     => "at90usb162",
    CUL_V2_HM  => "at90usb162",
    CUL_V3     => "atmega32u4",
    CUL_V4     => "atmega32u2",
  );
  my @a = split("[ \t]+", $param);
  return "Usage: CULflash <Fhem-CUL-Device> <CUL-type>, ".
                "where <CUL-type> is one of ". join(" ", sort keys %ctypes)
      if(int(@a) != 2 ||
         !$defs{$a[0]} ||
         $defs{$a[0]}{TYPE} ne "CUL" ||
         !$ctypes{$a[1]});

  my $cul  = $a[0];
  my $target = $a[1];

  ################################
  # First get the index file to prove the file size
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

  ################################
  # Now get the firmware file:
  my $content = GetHttpFile($server, "$sdir/$target.hex");
  return "File size for $target.hex does not correspond to filetimes.txt entry"
          if(length($content) ne $filesize{"$target.hex"});
  my $localfile = "$moddir/$target.hex";
  open(FH,">$localfile") || return "Can't write $localfile";
  print FH $content;
  close(FH);

  my $cmd = "($dfu MCU erase && $dfu MCU flash TARGET && $dfu MCU start) 2>&1";
  my $mcu = $ctypes{$target};
  $cmd =~ s/MCU/$mcu/g;
  $cmd =~ s/TARGET/$localfile/g;

  CUL_SimpleWrite($defs{CUL}, "B01");
  sleep(4);     # B01 needs 2 seconds for the reset
  Log 1, $cmd;
  my $result = `$cmd`;
  Log 1, $result;
  return $result;
}

sub
GetHttpFile($$)
{
  my ($host, $filename) = @_;

  my $conn = IO::Socket::INET->new(PeerAddr => $host);
  if(!$conn) {
    Log 1, "Can't connect to $host\n";
    return undef;
  }
  $host =~ s/:.*//;
  my $req = "GET $filename HTTP/1.0\r\nHost: $host\r\n\r\n\r\n";
  syswrite $conn, $req;
  my ($buf, $ret);
  while(sysread($conn, $buf, 65536) > 0) {
    $ret .= $buf;
  }
  $ret=~ s/.*?\r\n\r\n//s;
  Log 1, "Got http://$host$filename, length: ".length($ret);
  return $ret;
}

1;
