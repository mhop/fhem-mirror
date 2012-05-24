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
sub CreateBackup($);
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
  my $backuppaths = "";
  my $preserve = 0;
  my $housekeeping = 0;
  my $clean = 0;
  my $msg;

  if(!$param && !-d $wwwdir) {
    $ret  = "Usage: updatefhem [<backup>|<filename>|<housekeeping> [<clean>] [<yes>]|<preserve> [<filename>]]\n";
    $ret .= "Please note: The update routine has changed! Please consider the manual of command 'updatefhem'!";
    return $ret;
  }

  # split arguments
  my @args = split(/ +/,$param);

  if(@args) {

    # Check if the first parameter is "backup"
    # backup by RueBe, simplified by rudi, modified by M.Fischer
    if(uc($args[0]) eq "BACKUP") {
      return "Usage: updatefhem <backup>" if(@args > 1);

      if(-d $wwwdir) {
        # backup new structure
        $backuppaths = "FHEM www";
      } else {
        # backup old structure
        $backuppaths = "FHEM";
      }
      my $ret = CreateBackup($backuppaths);
      if($ret !~ m/backup done.*/) {
        Log 1, "updatefhem backup: The operation was canceled. Please check manually!";
        $msg  = "Something went wrong during backup:\n$ret\n";
        $msg .= "The operation was canceled. Please check manually!";
        return $msg;
      } else {
        Log 1, "updatefhem $ret";
      }
      return $ret if($ret);

    # Check whether the old structure to be maintained
    } elsif (uc($args[0]) eq "PRESERVE") {

      # Check if new wwwdir already exists and an argument is given
      if(-d $wwwdir && @args > 1) {
        Log 1, "updatefhem The operation was canceled! Argument <preserve> not allowed in new structure!";
        $ret  = "Usage: updatefhem [<backup>|<filename>]\n";
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

      # Backup existing structure
      if(-d $wwwdir) {
        # backup new structure
        $backuppaths = "FHEM www";
      } else {
        # backup old structure
        $backuppaths = "FHEM";
      }
      my $ret = CreateBackup($backuppaths);
      if($ret !~ m/backup done.*/) {
        Log 1, "updatefhem backup: The operation was canceled. Please check manually!";
        $msg  = "Something went wrong during backup:\n$ret\n";
        $msg .= "The operation was canceled. Please check manually!";
        return $msg;
      } else {
        Log 1, "updatefhem $ret";
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

    # user wants to update a file / module of the old structure
    } elsif (!-d $wwwdir) {
      return "Usage: updatefhem [<backup>|<housekeeping> [<clean>] [<yes>]|<preserve> [<filename>]]";
    }

  }

  # Read in the OLD filetimes.txt
  my %oldtime = ();
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

  my (%filetime, %filesize) = ();
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
  my $localfile;
  my $remfile;
  my $oldfile;
  my $delfile;
  foreach my $f (sort keys %filetime) {
    if($param) {
      next if($f !~ m/$param/);
    } else {
      if(!$clean) {
        next if($oldtime{$f} && $filetime{$f} eq $oldtime{$f});
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
    my $l2 = $filesize{$f};
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
#  if($clean) {
    my @fl;
    push(@fl, FileList("$moddir/.*(example.*|gplot|html|css|js|gif|jpg|png|svg)"));
    foreach my $file (@fl) {
      my $cmdret .= `(mv $moddir/$file $wwwdir/pgm2/)`;
      $ret .= "moved $moddir/$file\n";
      Log 1, "updatefhem move $file to www/pgm2 $cmdret";
    }
#  }

  if($housekeeping) {
    $ret .= "Housekeeping finished. 'shutdown restart' is recommended!";
    my $backupdir;
    if ($attr{global}{backupdir}) {
      $backupdir = $attr{global}{backupdir};
    } else {
      $backupdir = "$modpath/backup";
    }
    $ret .= "\n=> Files for WebGUI pgm2 were moved to '$wwwdir/pgm2'" if($clean);
    $ret .= "\n=> A backup has been created in '$backupdir'";
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
CreateBackup($)
{
  my ($backuppaths) = shift;
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir" : $attr{global}{modpath});
  my ($dir,$conf) = $attr{global}{configfile} =~ m/(.*\/)(.*)$/;
  my $backupdir;
  my $ret;
  if ($attr{global}{backupdir}) {
    $backupdir = $attr{global}{backupdir};
  } else {
    $backupdir = "$modpath/backup";
  }
  $ret = `(cp $attr{global}{configfile} $modpath/)`;
  $backuppaths .= " $conf";
  my $dateTime = TimeNow();
  $dateTime =~ s/ /_/g;
  $dateTime =~ s/(:|-)//g;
  # prevents tar's output of "Removing leading /" and return total bytes of archive
  $ret = `(mkdir -p $backupdir && tar -C $modpath -cf - $backuppaths | gzip > $backupdir/FHEM-$dateTime.tar.gz) 2>&1`;
  unlink("$modpath/$conf");
  if($ret) {
    chomp $ret;
    return $ret;
  }
  my $size = -s "$backupdir/FHEM-$dateTime.tar.gz";
  return "backup done: FHEM-$dateTime.tar.gz ($size Bytes)";
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

1;
