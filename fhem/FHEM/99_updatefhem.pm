##############################################
# $Id$
# modified by M. Fischer
package main;
use strict;
use warnings;
use IO::Socket;

sub CommandUpdatefhem($$);
sub CommandCULflash($$);
sub GetHttpFile($$@);
sub ParseChanges($);
sub ReadOldFiletimes($);
sub SplitNewFiletimes($);
sub FileList($);

my $server = "fhem.de:80";
my $sdir   = "/fhemupdate2";
my $ftime  = "filetimes.txt";
my $dfu    = "dfu-programmer";


#####################################
sub
updatefhem_Initialize($$)
{
  my %fhash = ( Fn=>"CommandUpdatefhem",
                Hlp=>",update fhem from the nightly SVN" );
  $cmds{updatefhem} = \%fhash;

  my %chash = ( Fn=>"CommandCULflash",
                Hlp=>"<cul> <type>,flash the CUL from the nightly SVN" );
  $cmds{CULflash} = \%chash;
}

#####################################
sub
CommandUpdatefhem($$)
{
  my ($cl, $param) = @_;
  my $lt = "";
  my $ret = "";
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir" : $attr{global}{modpath});
  my $moddir = "$modpath/FHEM";
  my $wwwdir = "$modpath/www";
  my $preserve = 0;
  my $housekeeping = 0;
  my $clean = 0;
  my $msg;

  if(!$param && !-d $wwwdir) {
    $ret  = "Usage: updatefhem [<changed>|<filename>|<housekeeping> [<clean>] [<yes>]|<preserve> [<filename>]]\n";
    $ret .= "Please note: The update routine has changed! Please consider the manual of command 'updatefhem'!";
    return $ret;
  }

  # split arguments
  my @args = split(/ +/,$param);

  if(@args) {

    # Get list of changes
    if (uc($args[0]) eq "CHANGED") {
      $ret = ParseChanges($moddir);
      return $ret;

    # Preserve current structur
    } elsif (uc($args[0]) eq "PRESERVE") {

      # Check if new wwwdir already exists and an argument is given
      if(-d $wwwdir && @args > 1) {
        Log 1, "updatefhem The operation was canceled! Argument <preserve> not allowed in new structure!";
        $ret  = "Usage: updatefhem [<filename>]\n";
        $ret .= "Please note: It seems as if 'updatefhem <housekeeping>' has already executed.\n";
        $ret .= "The operation was canceled. Argument <preserve> is not allowed in new structure!";
        return $ret;
      }
      # Check if new wwwdir already exists
      if(-d $wwwdir) {
        Log 1, "updatefhem The operation was canceled. Please check manually!";
        $ret  = "Please note: It seems as if 'updatefhem <housekeeping>' has already executed.\n";
        $ret .= "The operation was canceled. Please check manually!";
        return $ret;
      }
      # set old sourcedir for update
      $sdir = "/fhemupdate";
      $preserve = 1;
      # discard first argument
      shift @args;
      $param = join("", @args);

    # Check whether the new structure is to be established.
    } elsif (uc($args[0]) eq "HOUSEKEEPING") {

      if(@args >3 ||
          (defined($args[1]) && uc($args[1]) ne "CLEAN") ||
          ((defined($args[1]) && uc($args[1]) eq "CLEAN") && (defined($args[2]) && uc($args[2]) ne "YES"))
        ) {
        return "Usage: updatefhem <housekeeping> [<clean>] [<yes>]";
      }
      # Check if new wwwdir already exists
      if(-d $wwwdir && @args == 1) {
        Log 1, "updatefhem The operation was canceled. Please check manually!";
        $ret  = "Please note: It seems as if 'updatefhem <housekeeping>' has already executed.\n";
        $ret .= "The operation is canceled now. Please check manually!";
        return $ret;
      }

      # user decided to delete old files
      if (@args == 2 && uc($args[1]) eq "CLEAN") {

        # returns a warning
        $ret  = "WARNING: The option <clean> will remove existing files!\n";
        $ret .= "If local changes have been made, they will be lost!\n";
        $ret .= "If you are sure, then call 'updatefhem <housekeeping> <clean> <yes>'.";
        return $ret;

      # user decided to delete old files, really
      } elsif (@args == 3 && uc($args[1]) eq "CLEAN" && uc($args[2]) eq "YES") {

        # set cleanup structure
        $clean = 1;
      }

      # prepare for housekeeping
      $housekeeping = 1;
      # set new sourcedir for update
      $sdir = "/fhemupdate2";
      # Create new pgm2 path
      $ret = `(mkdir -p $wwwdir/pgm2)`;
      chomp $ret;

      # return on errors
      if($ret) {
        Log 1, "updatefhem \"$ret\"";
        return $ret;
      }

      # remove old filetimes.txt
      if(-e "$moddir/$ftime") {
        unlink("$moddir/$ftime");
      }

      # discard arguments
      @args = ();
      $param = join("", @args);

    # help
    } elsif (uc($args[0]) eq "?") {
      return "Usage: updatefhem [<changed>|<housekeeping> [<clean>] [<yes>]|<preserve> [<filename>]]";
    # user wants to update a file / module of the old structure
    } elsif (!-d $wwwdir) {
      return "Usage: updatefhem [<changed>|<housekeeping> [<clean>] [<yes>]|<preserve> [<filename>]]";
    }

  }

  # Read in the OLD filetimes.txt
  my $oldtime = ReadOldFiletimes("$moddir/$ftime");

  # Get new filetimes.txt
  my $filetimes = GetHttpFile($server, "$sdir/$ftime");
  return "Can't get $ftime from $server" if(!$filetimes);

  # split filetime and filesize
  my ($sret, $filetime, $filesize) = SplitNewFiletimes($filetimes);
  return "$sret" if($sret);

  # Check for new / modified files
  my $c = 0;
  foreach my $f (sort keys %$filetime) {
    if($param) {
      next if($f !~ m/$param/);
    } else {
      if(!$clean) {
        next if($oldtime->{$f} && $filetime->{$f} eq $oldtime->{$f});
      }
      next if($f =~ m/.hex$/);  # skip firmware files
    }
    $c = 1;
  }

  return "nothing to do..." if (!$c);

  # do a backup first
  my $doBackup = (!defined($attr{global}{backup_before_update}) ? 1 : $attr{global}{backup_before_update});

  if ($doBackup) {
    my $cmdret = AnalyzeCommandChain(undef, "backup");
    if($cmdret !~ m/backup done.*/) {
      Log 1, "updatefhem: The operation was canceled. Please check manually!";
      $msg  = "Something went wrong during backup:\n$cmdret\n";
      $msg .= "The operation was canceled. Please check manually!";
      return $msg;
    }
    $ret .= "$cmdret\n";
  }

  my @reload;
  my $newfhem = 0;
  my $localfile;
  my $remfile;
  my $oldfile;
  my $delfile;
  my $excluded = (!defined($attr{global}{exclude_from_update}) ? "" : $attr{global}{exclude_from_update});

  foreach my $f (sort keys %$filetime) {
    my $ef = substr $f,rindex($f,'/')+1;
    if($excluded =~ /$ef/) {
      $ret .= "excluded $f\n";
      next;
    }
    if($param) {
      next if($f !~ m/$param/);
    } else {
      if(!$clean) {
        next if($oldtime->{$f} && $filetime->{$f} eq $oldtime->{$f});
      }
      next if($f =~ m/.hex$/);  # skip firmware files
    }
    if(!$preserve) {
      $localfile = "$modpath/$f";
      if($f =~ m/^www\/pgm2\/(\d\d_.*\.pm)$/) {
        my $pgm2 = $1;
        $localfile = "$moddir/$pgm2";
      }
      $remfile = $f;
    } else {
      $localfile = "$moddir/$f";
      $remfile = $f;
    }

    if($f =~ m/fhem.pl$/) {
      $newfhem = 1;
      $localfile = $0 if(! -d "updatefhem.dir");
      $remfile = "$f.txt";
    }

    if($f =~ m/^.*(\d\d_)(.*).pm$/) {
      my $mf = "$1$2";
      my $m  = $2;
      push @reload, $mf if($modules{$m} && $modules{$m}{LOADED});
    }

    my $content = GetHttpFile($server, "$sdir/$remfile");
    my $l1 = length($content);
    my $l2 = $filesize->{$f};
    return "File size for $f ($l1) does not correspond to ".
                "filetimes.txt entry ($l2)" if($l1 ne $l2);
    open(FH,">$localfile") || return "Can't write $localfile";
    print FH $content;
    close(FH);
    $ret .= "updated $f\n";
    Log 1, "updatefhem updated $f";

    if(!$preserve && $clean && $f =~ m/^www\/pgm2\/(.*)$/) {
      my $oldfile = $1;
      if($oldfile !~ m /^.*\.pm$/) {
        $delfile = $oldfile;
        if(-e "$moddir/$delfile") {
          unlink("$moddir/$delfile");
          $ret .= "deleted FHEM/$delfile\n";
          Log 1, "updatefhem deleted FHEM/$delfile";
        }
      }
    }
  }

  return "Can't write $moddir/$ftime" if(!open(FH, ">$moddir/$ftime"));
  print FH $filetimes;
  close(FH);

  if(!$newfhem) {
    foreach my $m (@reload) {
      $ret .= "reloading module $m\n";
      my $cret = CommandReload($cl, $m);
      Log 1, "updatefhem reloaded module $m" if($cret);
      return "$ret$cret" if($cret);
    }
  }

  # final housekeeping
  if($clean) {
    my @fl;
    push(@fl, FileList("$moddir/.*(example.*|gplot|html|css|js|gif|jpg|png|svg)"));
    foreach my $file (@fl) {
      my $cmdret .= `(mv $moddir/$file $wwwdir/pgm2/)`;
      $ret .= "moved $moddir/$file\n";
      Log 1, "updatefhem move $file to www/pgm2 $cmdret";
    }
  }

  if($housekeeping) {
    $ret .= "Housekeeping finished. 'shutdown restart' is recommended!";
    $ret .= "\n=> Files for WebGUI pgm2 were moved to '$wwwdir/pgm2'" if($clean);
    if ($attr{global}{backupcmd}) {
      $ret .= "\n=> A backup has been created with '$attr{global}{backupcmd}'";
    } else {
      my $backupdir;
      if ($attr{global}{backupdir}) {
        $backupdir = $attr{global}{backupdir};
      } else {
        $backupdir = "$modpath/backup";
      }
      $ret .= "\n=> A backup has been created in '$backupdir'";
    }
    Log 1, "updatefhem Housekeeping finished, 'shutdown restart' is recommended!";
  } else {
    $ret .= "update finished";
  }

  if($newfhem) {
    $ret .= "\nA new version of fhem.pl was installed, 'shutdown restart' is required!";
    Log 1, "updatefhem New version of fhem.pl, 'shutdown restart' is required!";
  }
  return $ret;
}

sub
CommandCULflash($$)
{
  my ($cl, $param) = @_;
  my $modpath = (-d "update" ? "update" : $attr{global}{modpath});
  my $moddir = "$modpath/FHEM";

  my %ctypes = (
    CUL_V2     => "at90usb162",
    CUL_V2_HM  => "at90usb162",
    CUL_V3     => "atmega32u4",
    CUL_V4     => "atmega32u2",
  );
  my @a = split("[ \t]+", $param);
  return "Usage: CULflash <Fhem-CUL-Device> <CUL-type>, ".
                "where <CUL-type> is one of ". join(" ", sort keys %ctypes)
      if(!(int(@a) == 2 &&
          ($a[0] eq "none" || ($defs{$a[0]} && $defs{$a[0]}{TYPE} eq "CUL")) &&
          $ctypes{$a[1]}));

  my $cul  = $a[0];
  my $target = $a[1];

  ################################
  # First get the index file to prove the file size
  my $filetimes = GetHttpFile($server, "$sdir/$ftime");
  return "Can't get $ftime from $server" if(!$filetimes);

  # split filetime and filesize
  my ($ret, $filetime, $filesize) = SplitNewFiletimes($filetimes);
  return $ret if($ret);

  ################################
  # Now get the firmware file:
  my $content = GetHttpFile($server, "$sdir/FHEM/$target.hex");
  return "File size for $target.hex does not correspond to filetimes.txt entry"
          if(length($content) ne $filesize->{"FHEM/$target.hex"});
  my $localfile = "$moddir/$target.hex";
  open(FH,">$localfile") || return "Can't write $localfile";
  print FH $content;
  close(FH);

  my $cmd = "($dfu MCU erase && $dfu MCU flash TARGET && $dfu MCU start) 2>&1";
  my $mcu = $ctypes{$target};
  $cmd =~ s/MCU/$mcu/g;
  $cmd =~ s/TARGET/$localfile/g;

  if($cul ne "none") {
    CUL_SimpleWrite($defs{$cul}, "B01");
    sleep(4);     # B01 needs 2 seconds for the reset
  }
  Log 1, "updatefhem $cmd";
  my $result = `$cmd`;
  Log 1, "updatefhem $result";
  return $result;
}

sub
GetHttpFile($$@)
{
  my ($host, $filename, $timeout) = @_;
  $timeout = 2.0 if(!defined($timeout));

  $filename =~ s/%/%25/g;
  my $conn = IO::Socket::INET->new(PeerAddr => $host);
  if(!$conn) {
    Log 1, "updatefhem Can't connect to $host\n";
    undef $conn;
    return undef;
  }
  $host =~ s/:.*//;
  my $req = "GET $filename HTTP/1.0\r\nHost: $host\r\n\r\n\r\n";
  syswrite $conn, $req;
  shutdown $conn, 1; # stopped writing data
  my ($buf, $ret) = ("", "");

  $conn->timeout($timeout);
  for(;;) {
    my ($rout, $rin) = ('', '');
    vec($rin, $conn->fileno(), 1) = 1;
    my $nfound = select($rout=$rin, undef, undef, $timeout);
    if($nfound <= 0) {
      Log 1, "updatefhem GetHttpFile: Select timeout/error: $!";
      undef $conn;
      return undef;
    }

    my $len = sysread($conn,$buf,65536);
    last if(!defined($len) || $len <= 0);
    $ret .= $buf;
  }

  $ret=~ s/(.*?)\r\n\r\n//s; # Not greedy: switch off the header.
  Log 4, "updatefhem Got http://$host$filename, length: ".length($ret);
  undef $conn;
  return $ret;
}

sub
ParseChanges($)
{
  my $moddir = shift;
  my $excluded = (!defined($attr{global}{exclude_from_update}) ? "" : $attr{global}{exclude_from_update});
  my $ret = "List of new / modified files since last update:\n";

  # get list of files
  my $filetimes = GetHttpFile($server, "$sdir/$ftime");
  return $ret."Can't get $ftime from $server" if(!$filetimes);

  # split filetime and filesize
  my ($sret, $filetime, $filesize) = SplitNewFiletimes($filetimes);
  $ret .= "$sret\n" if($sret);

  # Read in the OLD filetimes.txt
  my $oldtime = ReadOldFiletimes("$moddir/$ftime");

  # Check for new / modified files
  my $c = 0;
  foreach my $f (sort keys %$filetime) {
    next if($oldtime->{$f} && $filetime->{$f} eq $oldtime->{$f});
    next if($f =~ m/.hex$/);  # skip firmware files
    $c = 1;
    my $ef = substr $f,rindex($f,'/')+1;
    if($excluded !~ /$ef/) {
      $ret .= "$filetime->{$f} $f\n";
    } else {
      $ret .= "$filetime->{$f} $f ==> excluded from update!\n";
    }
  }

  if (!$c) {
    $ret .= "nothing to do...";
  } else {
    # get list of changes
    $ret .= "\nList of changes:\n";
    my $changed = GetHttpFile($server, "$sdir/CHANGED");
    if(!$changed || $changed =~ m/Error 404/g) {
      $ret .= "Can't get list of changes from $server";
    } else {
      my @lines = split(/\015\012|\012|\015/,$changed);
      foreach my $line (@lines) {
        last if($line eq "");
        $ret .= $line."\n";
      }
    }
  }

  return $ret;
}

sub
ReadOldFiletimes($)
{
  my $filetimes = shift;
  my %oldtime = ();
  my $excluded = (!defined($attr{global}{exclude_from_update}) ? "" : $attr{global}{exclude_from_update});

  # Read in the OLD filetimes.txt
  if(open FH, "$filetimes") {
    while(my $l = <FH>) {
      chomp($l);
      my ($ts, $fs, $file) = split(" ", $l, 3);
      my $ef = substr $file,rindex($file,'/')+1;
      next if($excluded =~ /$ef/);
      $oldtime{$file} = $ts;
    }
    close(FH);
  }
  return (\%oldtime);
}

sub
SplitNewFiletimes($)
{
  my $filetimes = shift;
  my $ret;
  my (%filetime, %filesize) = ();
  foreach my $l (split("[\r\n]", $filetimes)) {
    chomp($l);
    $ret = "Corrupted filetimes.txt file"
        if($l !~ m/^20\d\d-\d\d-\d\d_\d\d:\d\d:\d\d /);
    last if($ret);
    my ($ts, $fs, $file) = split(" ", $l, 3);
    $filetime{$file} = $ts;
    $filesize{$file} = $fs;
  }
  return ($ret, \%filetime, \%filesize);
}

sub
FileList($)
{
  my ($fname) = @_;
  $fname =~ m,^(.*)/([^/]*)$,;
  my ($dir,$re) = ($1, $2);
  return if(!$re);
  $re =~ s/%./[A-Za-z0-9]*/g;
  my @ret;
  return @ret if(!opendir(DH, $dir));
  while(my $f = readdir(DH)) {
    next if($f !~ m,^$re$,);
    push(@ret, $f);
  }
  closedir(DH);
  return sort @ret;
}

# vim: ts=2:et
1;
