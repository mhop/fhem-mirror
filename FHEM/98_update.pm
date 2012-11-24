################################################################
# $Id$
# vim: ts=2:et
# 
#  (c) 2012 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
################################################################
package main;
use strict;
use warnings;
use HttpUtils;
use File::Copy qw(cp mv);

sub CommandUpdate($$);
sub update_CheckFhemRelease($$);
sub update_CheckUpdates($$$$);
sub update_CleanUpLocalFiles($$$);
sub update_DoUpdate(@);
sub update_DoHousekeeping($);
sub update_GetRemoteFiles($$$);
sub update_ListChanges($);
sub update_MakeDirectory($);
sub update_ParseControlFile($$$$);
sub update_WriteLocalControlFile($$$);

my $BRANCH;


########################################
sub
update_Initialize($$)
{
  if(!eval "require FhemUtils::release") {
    require release;
  }

  foreach my $pack (split(" ",uc($UPDATE{packages}))) {
    $UPDATE{$pack}{control} = "controls_".lc($pack).".txt";
  }

  my %hash = (
    Fn  => "CommandUpdate",
    Hlp => "[development|stable] [<file>|check|fhem],update Fhem",
  );
  $cmds{update} = \%hash;
}

########################################
sub
CommandUpdate($$)
{
  my ($cl,$param) = @_;
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $moddir  = "$modpath/FHEM";
  my $srcdir  = "";
  my $update  = "";
  my $force   = 0;
  my $ret     = "";

  # split arguments
  my @args = split(/ +/,$param);

  # set default trunk
  $BRANCH = (!defined($attr{global}{updatebranch}) ? $DISTRIB_BRANCH : uc($attr{global}{updatebranch}));
  if ($BRANCH ne "STABLE" && $BRANCH ne "DEVELOPMENT") {
    $ret = "global attribute 'updatebranch': unknown keyword: '$BRANCH'. Keyword should be 'STABLE' or 'DEVELOPMENT'";
    Log 1, "update $ret";
    return "$ret";
  }

  if (!defined($args[0])) {
    push(@args,$BRANCH);
  } elsif (uc($args[0]) ne "STABLE" && uc($args[0]) ne "DEVELOPMENT") {
    unshift(@args,$BRANCH);
  } elsif (uc($args[0]) eq "STABLE" || uc($args[0]) eq "DEVELOPMENT") {
    $args[0] = uc($args[0]);
    $BRANCH = $args[0];
  }

  # set path for fhem.de
  my $branch = lc($BRANCH);
  $branch = "SVN" if ($BRANCH eq "DEVELOPMENT");
  $srcdir = $UPDATE{path}."/".lc($branch);

  # check arguments
  if (defined($args[1]) && $args[1] eq "?" ||
     (int(@args) > 3 && uc($args[1]) eq "HOUSEKEEPING") ||
     (int(@args) > 2 && uc($args[2]) ne "FORCE" && 
      (uc($args[1]) eq "CHECK"   || 
       uc($args[1]) eq "FHEM"    || 
       uc($args[1]) eq "FULL"))  || 
     (int(@args) > 2   &&
      (uc($args[1]) ne "CHECK"   &&
       uc($args[1]) ne "FHEM"    &&
       uc($args[1]) ne "FULL"    && 
       uc($args[1]) ne "HOUSEKEEPING"))) {
    return "Usage: update [development|stable] [<file>|check|fhem|full] [force]";
  }

  # check arguments for housekeeping
  if (defined($args[1]) && uc($args[1]) eq "HOUSEKEEPING" && (int(@args) > 2 )) {
    return "Usage: update housekeeping";
  }

  # set default update
  if (!defined($args[1]) ||
     (defined($args[1])  &&
        (uc($args[1]) eq "FORCE") ||
         uc($args[1]) eq "HOUSEKEEPING")) {
    $update = "FHEM";
  } else {
    $update = $args[1];
  }

  # force update
  $force = 1 if (defined($args[1]) && uc($args[1]) eq "FORCE" ||
                 defined($args[2]) && uc($args[2]) eq "FORCE");

  if (defined($args[1]) && uc($args[1]) eq "CHECK") {
    $ret = update_ListChanges($srcdir);
  } elsif (defined($args[1]) && uc($args[1]) eq "HOUSEKEEPING") {
    $ret = update_DoHousekeeping($update);
    $ret = "nothing to do..." if (!$ret);
  } else {
    $ret = update_DoUpdate($srcdir,$BRANCH,$update,$force,$cl);
  }

  return $ret;
}

########################################
sub
update_DoUpdate(@)
{
  my ($srcdir,$BRANCH,$update,$force,$cl) = @_;
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $moddir  = "$modpath/FHEM";
  my $server = $UPDATE{server};
  my $fail;
  my $ret = "";

  # Get fhem.pl version
  my $checkFhemRelease = update_CheckFhemRelease($force,$srcdir);
  return $checkFhemRelease if ($checkFhemRelease);

  # get list of files
  my $rControl_ref = {};
  my $lControl_ref = {};
  foreach my $pack (split(" ",uc($UPDATE{packages}))) {
    Log 3, "update get $server/$srcdir/$UPDATE{$pack}{control}";
    my $controlFile = GetFileFromURL("$server/$srcdir/$UPDATE{$pack}{control}");
    return "Can't get '$UPDATE{$pack}{control}' from $server" if (!$controlFile);
    # parse remote controlfile
    ($fail,$rControl_ref) = update_ParseControlFile($pack,$controlFile,$rControl_ref,0);
    return "$fail\nUpdate canceled..." if ($fail);

    # parse local controlfile
    ($fail,$lControl_ref) = update_ParseControlFile($pack,"$moddir/$UPDATE{$pack}{control}",$lControl_ref,1);
    return "$fail\nUpdate canceled..." if ($fail);
  }

  # Check for new / modified files
  my ($checkUpdates,$updateFiles_ref) = update_CheckUpdates($update,$force,$lControl_ref,$rControl_ref);
  if (!keys %$updateFiles_ref) {
    return $checkUpdates;
  } else {
    $ret = $checkUpdates;
  }

  # save statefile
  $ret .= "\nSaving statefile: ";
  my $cmdret = WriteStatefile();
  if (!$cmdret) {
    Log 1, "update saving statefile";
    $ret .= "done\n\n";
  } else {
    Log 1, "update statefile: $cmdret";
    $ret .= "Something went wrong with statefile:\n$cmdret\n\n";
  }

  # do a backup first
  my $doBackup = (!defined($attr{global}{backup_before_update}) ? 1 : $attr{global}{backup_before_update});

  if ($doBackup) {
    my $cmdret = AnalyzeCommand(undef, "backup");
    if ($cmdret !~ m/backup done.*/) {
      Log 1, "update Backup: The operation was canceled. Please check manually!";
      $ret .= "Something went wrong during backup:\n$cmdret\n";
      $ret .= "The operation was canceled. Please check manually!";
      return $ret;
    }
    $ret .= "Backup:\n$cmdret\n";
  }

  # get new / modified files
  my $getUpdates;
  ($fail,$getUpdates) = update_GetRemoteFiles($srcdir,$updateFiles_ref,$cl);
  $ret .= $getUpdates if($getUpdates);
  undef($updateFiles_ref);

  foreach my $pack (split(" ",uc($UPDATE{packages}))) {
    # write local controlfile
    my $localControlFile = update_WriteLocalControlFile($pack,$lControl_ref,$rControl_ref);
    $ret .= $localControlFile if ($localControlFile);
  }

  return $ret if($fail);
  if (uc($update) eq "FULL" || uc($update) eq "FHEM") {
    my $doHousekeeping = update_DoHousekeeping($update);
    $ret .= $doHousekeeping if ($doHousekeeping);
  }

  $ret .= "\nUpdate completed!";
  return $ret;
}

########################################
sub
update_DoHousekeeping($)
{
  my ($update) = @_;
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $moddir  = "$modpath/FHEM";
  my $cleanup;
  my $pack = uc($update);
  my $ret;

  # parse local controlfile
  my $fail;
  my $lControl_ref;
  ($fail,$lControl_ref) = update_ParseControlFile($pack,"$moddir/$UPDATE{$pack}{control}",$lControl_ref,1);
  return "$fail\nHousekeeping canceled..." if ($fail);


  my %lControl = %$lControl_ref;

  # first run: create directories
  foreach my $f (sort keys %{$lControl{$pack}}) {
    my $lCtrl = $lControl{$pack}{$f}{ctrl};
    my $str;
    next if ($lCtrl ne "DIR");

    if ($lCtrl eq "DIR") {
      $str = update_CleanUpLocalFiles($lCtrl,"$f","");
      if($str) {
        $cleanup .= "==> $str\n" ;
        Log 1, "update $str";
      }
    }
  }

  # second run: move named files
  foreach my $f (sort keys %{$lControl{$pack}}) {
    my $lCtrl = $lControl{$pack}{$f}{ctrl};
    my $str;
    next if ($lCtrl ne "MOV");

    if ($lCtrl eq "MOV" && $f !~ /\*/) {
      $str = update_CleanUpLocalFiles($lCtrl,"$modpath/$f","$modpath/$lControl{$pack}{$f}{move}");
      $cleanup .= "==> $str\n";
      Log 1, "update $str";
    }
  }

  # third run: move glob
  foreach my $f (sort keys %{$lControl{$pack}}) {
    my $lCtrl = $lControl{$pack}{$f}{ctrl};
    my $str;
    next if ($lCtrl ne "MOV");

    if ($lCtrl eq "MOV" && $f =~ /\*/) {
      # get filename and path
      #my $fname = substr $f,rindex($f,'/')+1;
      my $fpath = substr $f,0,rindex($f,'/')+1;

      foreach my $file (<$modpath/$f>) {
        $str = update_CleanUpLocalFiles($lCtrl,"$file","$modpath/$lControl{$pack}{$f}{move}/");
        $cleanup .= "==> $str\n";
        Log 1, "update $str";
      }
    }
  }

  # last run: delete
  foreach my $f (sort keys %{$lControl{$pack}}) {
    my $lCtrl = $lControl{$pack}{$f}{ctrl};
    my $str;
    next if ($lCtrl ne "DEL");

    if ($f =~ /\*/) {
      # get filename and path
      #my $fname = substr $f,rindex($f,'/')+1;
      my $fpath = substr $f,0,rindex($f,'/')+1;

      foreach my $file (<$modpath/$f>) {
        if ($lCtrl eq "DEL") {
          $str = update_CleanUpLocalFiles($lCtrl,"$file","");
          $cleanup .= "==> $str\n";
          Log 1, "update $str";
        }
      }
    } else {
      if ($lCtrl eq "DEL") {
        $str = update_CleanUpLocalFiles($lCtrl,"$modpath/$f","");
        $cleanup .= "==> $str\n";
        Log 1, "update $str";
      }
    }
  }

  if ($cleanup) {
    $ret = "\nHousekeeping:\n$cleanup";
  }
  return $ret;
}

########################################
sub
update_CheckUpdates($$$$)
{
  my ($update,$force,$lControl_ref,$rControl_ref) = @_;
  return "Wildcards are not ( yet ;-) ) allowed." if ($update =~ /(\*|\?)/);

  my @exclude;
  my $excluded = (!defined($attr{global}{exclude_from_update}) ? "" : $attr{global}{exclude_from_update});
  my $found = 0;
  my $pack;
  my $ret;
  my $singleFile = 0;
  my $search = lc($update);
  my @suggest;
  my %updateFiles = ();

  # select package
  $pack = "FHEM";
  $pack = uc($update) if ($force);

  # build searchstring
  if (uc($update) ne "FULL" && uc($update) ne "FHEM") {
    $singleFile = 1;
    if ($update =~ m/^(\S+)\.(.*)$/) {
      $search = lc($1);
      if ($search =~ m/(\d+)_(.*)/) {
        $search = lc($2);
      }
    }
  }

  # search for new / modified files
  my %rControl = %$rControl_ref;
  my %lControl = %$lControl_ref;
  foreach my $f (sort keys %{$rControl{$pack}}) {
    # skip housekeeping
    next if ($rControl{$pack}{$f}{ctrl} eq "DEL" ||
             $rControl{$pack}{$f}{ctrl} eq "DIR" ||
             $rControl{$pack}{$f}{ctrl} eq "MOV");

    # get remote filename
    my $fname = substr $f,rindex($f,'/')+1;

    # suggest filenames for given searchstring
    if ($singleFile && lc($fname) ne lc($update)) {
      if ($search && lc($fname) =~ m/$search/) {
        push(@suggest,$fname);
      }
    }
    # skip if some file was specified and the name does not match
    next if ($singleFile && $fname ne $update);

    if ($excluded =~ /$fname/) {
      $lControl{$pack}{$f}{ctrl} = "EXC";
      $lControl{$pack}{$f}{date} = (!defined($lControl{$pack}{$f}{date}) ?
                                             $rControl{$pack}{$f}{date} : 
                                             $lControl{$pack}{$f}{date});
      $lControl{$pack}{$f}{size} = (!defined($lControl{$pack}{$f}{size}) ?
                                             $rControl{$pack}{$f}{size} :
                                             $lControl{$pack}{$f}{size});
      $lControl{$pack}{$f}{file} = (!defined($lControl{$pack}{$f}{file}) ?
                                             $rControl{$pack}{$f}{file} :
                                             $lControl{$pack}{$f}{file});
      Log 1, "update excluded by configuration: $fname";
      push(@exclude,$f);
    }

    if ($singleFile && $fname eq $update) {
      #if (!@exclude && $lControl{$pack}{$f}{date} &&
      #                 $rControl{$pack}{$f}{date} ne $lControl{$pack}{$f}{date}) {
      if (!@exclude && $lControl{$pack}{$f}{date}) {
        $updateFiles{$f}{file} = $fname;
        $updateFiles{$f}{size} = $rControl{$pack}{$f}{size};
        $updateFiles{$f}{date} = $rControl{$pack}{$f}{date};
      }
      $found = 1;
      last;
    }

    next if (!$force &&
             $lControl{$pack}{$f}{date} &&
             $rControl{$pack}{$f}{date} eq $lControl{$pack}{$f}{date});

    if ($excluded !~ /$fname/) {
      $updateFiles{$f}{file} = $fname;
      $updateFiles{$f}{size} = $rControl{$pack}{$f}{size};
      $updateFiles{$f}{date} = $rControl{$pack}{$f}{date};
    }

    $found = 1;
  }


  my $nothing = "nothing to do...";
  if ($found) {
    if (@exclude) {
      my $exc;
      foreach my $f (sort @exclude) {
        my $fname = substr $f,rindex($f,'/')+1;
        $exc .= "==> $fname\n" if ($rControl{$pack}{$f}{date} ne $lControl{$pack}{$f}{date});
      }
      if (!keys(%updateFiles)) {
        $ret .= $nothing;
        Log 1, "update $nothing";
      } else {
        if ($exc) {
          $ret = "\nFile(s) skipped for an update! Excluded by configuration:\n$exc";
        }
      }
    }
  } else {
    if ($singleFile && !@suggest) {
      $ret = "'$update' not found.";
      Log 1, "update $nothing";
    }
    if ($singleFile && @suggest) {
      $ret = "'$update' not found. Did you mean:\n";
      foreach my $f (sort @suggest) {
        if ($excluded =~ /$f/) {
          $ret .= "==> $f (excluded from updates)\n";
        } else {
          $ret .= "==> $f\n";
        }
      }
      $ret .= $nothing;
      Log 1, "update $nothing";
    }
    if (!$singleFile && !keys(%updateFiles)) {
      $ret .= $nothing;
      Log 1, "update $nothing";
    }
  }
  return ($ret,\%updateFiles);
}

########################################
sub
update_GetRemoteFiles($$$)
{
  my ($srcdir,$updateFiles_ref,$cl) = @_;
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $moddir  = "$modpath/FHEM";
  my $server = $UPDATE{server};
  my %diffSize = ();
  my $fail = 0;
  my $localFile;
  my $newFhem = 0;
  my $remoteFile;
  my @reloadModules;
  my $writeError;
  my $ret;

  foreach my $f (sort keys %$updateFiles_ref) {
    $remoteFile = $f;
    $localFile  = "$modpath/$f";

    # mark for a restart of fhem.pl
    if ($f =~ m/fhem.pl$/) {
      $newFhem = 1;  
      $localFile = $0 if (! -d "updatefhem.dir");
      $remoteFile = "$f.txt";
    }

    # replace special char % in filename
    $remoteFile =~ s/%/%25/g;

    # get remote filename
    my $fname = substr $f,rindex($f,'/')+1;
    my $fpath = $f;
    $fpath =~ s/$fname//g;

    # get remote File
    Log 3, "update get $server/$srcdir/$remoteFile";
    my $fileContent = GetFileFromURL("$server/$srcdir/$remoteFile");
    my $fileLength = length($fileContent);
    my $ctrlLength = $updateFiles_ref->{$f}->{size};

    if ($fileLength ne $ctrlLength) {
      $diffSize{$fname}{filelength} = $fileLength;
      $diffSize{$fname}{ctrllength} = $ctrlLength;
      $diffSize{$fname}{updatefile} = $f;
      Log 1, "update skip '$fname'. Size does not correspond to " .
             "controlfile: $ctrlLength bytes download: $fileLength bytes";
    } else {

      # mark for a reload of a modified module if its in use
      if ($f =~ m/^.*(\d\d_)(.*).pm$/) {
        my $modFile = "$1$2";
        my $modName = $2;
        push(@reloadModules,$modFile) if ($modules{$modName} && $modules{$modName}{LOADED});
      }

      my $mkdir;
      $mkdir = update_MakeDirectory($fpath);
      $ret .= $mkdir if ($mkdir);

      next if ($mkdir);

      if (open (FH, ">$localFile")) {
        print FH $fileContent;
        close (FH);
        Log 5, "update write $localFile";
      } else {
        delete $updateFiles_ref->{$f};
        Log 1, "update Can't write $localFile: $!";
        $writeError .= "Can't write $localFile: $!\n";
      }
        
    }
  }

  if ($writeError) {
    $ret .= "\nFile(s) skipped for an update! Error while writing:\n";
    $ret .= "$writeError";
  }

  if (keys(%diffSize)) {
    $ret .= "\nFile(s) skipped for an update! Size does not correspond:\n";
    foreach my $f (sort keys(%diffSize)) {
      delete $updateFiles_ref->{$diffSize{$f}{updatefile}};
      $ret .= "==> $f: size from controlfile: $diffSize{$f}{ctrllength} bytes, " .
              "size after download: $diffSize{$f}{filelength} bytes\n";
    }
  }

  if (keys(%$updateFiles_ref)) {
    my $str = keys(%$updateFiles_ref)." file(s) have been updated";
    $ret .= "\n$str:\n";
    Log 1, "update $str.";
    foreach my $f (sort keys(%$updateFiles_ref)) {
      my ($date,$time) = split("_",$updateFiles_ref->{$f}->{date});
      $ret .= "==> $date $time $f\n";
    }

    if (!$newFhem && @reloadModules) {
      $ret .= "A new version of one ore more module(s) was installed, 'shutdown restart' is required!";
      #$ret .= "\nModule(s) reloaded:\n";
      #foreach my $modFile (@reloadModules) {
      #  my $cmdret = CommandReload($cl,$modFile);
      #  if (!$cmdret) {
      #    Log 1, "update reloaded module: $modFile";
      #    $ret .= "==> $modFile\n";
      #  } else {
      #    $ret .= "==> $modFile:\n$cmdret\n";
      #  }
      #}
    }

    if ($newFhem) {
      my $str = "A new version of fhem.pl was installed, 'shutdown restart' is required!";
      Log 1, "update $str";
      $ret .= "\n$str\n";
    }

  } else {
    my $str = "No files have been updated because one or more errors have occurred!";
    $fail = 1;
    $ret .= "\n$str\n";
    Log 1, "update $str";
  }

  return ($fail,$ret);
}

########################################
sub
update_ListChanges($)
{
  my ($srcdir) = @_;
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $moddir  = "$modpath/FHEM";
  my $excluded = (!defined($attr{global}{exclude_from_update}) ? "" : $attr{global}{exclude_from_update});
  my $fail;
  my $pack;
  my $server = $UPDATE{server};
  my $ret = "List of new / modified files since last update:\n";

  # select package
  $pack = "FHEM";

  # get list of files
  Log 3, "update get $server/$srcdir/$UPDATE{$pack}{control}";
  my $controlFile = GetFileFromURL("$server/$srcdir/$UPDATE{$pack}{control}");
  return "Can't get $UPDATE{$pack}{control} from $server" if (!$controlFile);

  # parse remote controlfile
  my $rControl_ref = {};;
  ($fail,$rControl_ref) = update_ParseControlFile($pack,$controlFile,$rControl_ref,0);
  return "$fail" if ($fail);

  # parse local controlfile
  my $lControl_ref = {};
  ($fail,$lControl_ref) = update_ParseControlFile($pack,"$moddir/$UPDATE{$pack}{control}",$lControl_ref,1);
  return "$fail" if ($fail);

  # Check for new / modified files
  my $str;
  my %rControl = %$rControl_ref;
  my %lControl = %$lControl_ref;
  foreach my $f (sort keys %{$rControl{$pack}}) {
    next if ($rControl{$pack}{$f}{ctrl} eq "DEL" ||
             $rControl{$pack}{$f}{ctrl} eq "DIR" ||
             $rControl{$pack}{$f}{ctrl} eq "MOV");
    next if ($lControl{$pack}{$f} &&
             $rControl{$pack}{$f}{date} eq $lControl{$pack}{$f}{date});
    $str = "$rControl{$pack}{$f}{ctrl} $f\n";
    if ($f !~ m/\*/) {
      my $ef = substr $f,rindex($f,'/')+1;
      if ($excluded =~ /$ef/) {
        $str = "--- $f (excluded from updates)\n";
      }
    }
    $ret .= $str;
  }

  if (!$str) {
    $ret .= "nothing to do...";
  } else {
    # get list of changes
    $ret .= "\nList of last changes:\n";
    my $changed = GetFileFromURL("$server/$srcdir/CHANGED");
    if (!$changed || $changed =~ m/Error 404/g) {
      $ret .= "Can't get list of changes from $server";
    } else {
      my @lines = split(/\015\012|\012|\015/,$changed);
      foreach my $line (@lines) {
        last if ($line eq "");
        $ret .= $line."\n";
      }
    }
  }

  return $ret;
}

########################################
sub
update_CheckFhemRelease($$)
{
  my ($force,$srcdir) = @_;
  my $server = $UPDATE{server};
  my $versRemote;
  my $ret = undef;
  
  # get fhem to check version
  Log 3, "update get $server/$srcdir/FHEM/FhemUtils/release.pm";
  my $uRelease = GetFileFromURL("$server/$srcdir/FHEM/FhemUtils/release.pm");
  Log 5, "update get $server/$srcdir/FHEM/FhemUtils/release.pm";
  return "Can't get release.pm from $server" if (!$uRelease);

  my ($NEW_DISTRIB_ID,$NEW_DISTRIB_RELEASE,$NEW_DISTRIB_BRANCH,$NEW_DISTRIB_DESCRIPTION) = "";
  foreach my $l (split("[\r\n]", $uRelease)) {
    chomp($l);
    Log 5, "update release.pm: $l";
    if ($l =~ m/^\$DISTRIB_ID="(.*)"/) {
      $NEW_DISTRIB_ID = $1;
    }
    if ($l =~ m/^\$DISTRIB_RELEASE="(\d+.\d+)"/) {
      $NEW_DISTRIB_RELEASE = $1;
    }
    if ($l =~ m/^\$DISTRIB_BRANCH="(.*)"/) {
      $NEW_DISTRIB_BRANCH = $1;
    }
  }

  if (!$NEW_DISTRIB_ID || !$NEW_DISTRIB_RELEASE || !$NEW_DISTRIB_BRANCH) {
    Log 1, "update The operation was canceled, while checking the remote Release.";
    return "Can't read remote Release Informations. Update canceled now."
  }
  $NEW_DISTRIB_DESCRIPTION="$NEW_DISTRIB_ID $NEW_DISTRIB_RELEASE ($NEW_DISTRIB_BRANCH)";

  if (!$force &&
     ($NEW_DISTRIB_RELEASE lt $DISTRIB_RELEASE ||
     ($NEW_DISTRIB_RELEASE == $DISTRIB_RELEASE &&
     ($DISTRIB_BRANCH eq "DEVELOPMENT" && $NEW_DISTRIB_BRANCH ne "DEVELOPMENT")))) {
    $ret  = "The installed version $DISTRIB_DESCRIPTION is newer than the remote\n";
    $ret .= "version $NEW_DISTRIB_DESCRIPTION.\n";
    $ret .= "A downgrade is not recommended! Your default updatebranch is '$BRANCH'.\n";
    $ret .= "You can force the downgrade with the argument 'force' (e.g. 'update force')\n";
    $ret .= "at your own risk. In case of problems within the downgrade process, there is\n";
    $ret .= "no support from the developers!";
    Log 1, "update Downgrade is not allowed!";
  }
  Log 1, "update check Releases => local: $DISTRIB_DESCRIPTION remote: $NEW_DISTRIB_DESCRIPTION";
  return $ret;
}

########################################
sub
update_WriteLocalControlFile($$$)
{
  my ($pack,$lControl_ref,$rControl_ref) = @_;
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $moddir  = "$modpath/FHEM";
  return "Can't write $moddir/".$UPDATE{$pack}{control}.": $!" if (!open(FH, ">$moddir/".$UPDATE{$pack}{control}));
  Log 5, "update write $moddir/".$UPDATE{$pack}{control};
  my %rControl = %$rControl_ref;
  my %lControl = %$lControl_ref;
  foreach my $f (sort keys %{$rControl{$pack}}) {
    my $ctrl = $rControl{$pack}{$f}{ctrl} if (defined($rControl{$pack}{$f}{ctrl}));
    my $date = $rControl{$pack}{$f}{date} if (defined($rControl{$pack}{$f}{date}));
    my $size = $rControl{$pack}{$f}{size} if (defined($rControl{$pack}{$f}{size}));
    my $file = $rControl{$pack}{$f}{file} if (defined($rControl{$pack}{$f}{file}));
    my $move = $rControl{$pack}{$f}{move} if (defined($rControl{$pack}{$f}{move}));

    if ($ctrl eq "UPD") {
      if (defined($lControl{$pack}{$f}{ctrl}) && $lControl{$pack}{$f}{ctrl} eq "EXC") {
        $date = defined($lControl{$pack}{$f}{date}) ? $lControl{$pack}{$f}{date} :
                                                      $rControl{$pack}{$f}{date};
        $size = defined($lControl{$pack}{$f}{size}) ? $lControl{$pack}{$f}{size} :
                                                      $rControl{$pack}{$f}{size};
        $file = defined($lControl{$pack}{$f}{file}) ? $lControl{$pack}{$f}{file} :
                                                      $rControl{$pack}{$f}{file};
      }
      Log 5, "update ".$UPDATE{$pack}{control}.": $ctrl $date $size $file";
      print FH "$ctrl $date $size $file\n";
    }

    if ($ctrl eq "DIR") {
      Log 5, "update ".$UPDATE{$pack}{control}.": $ctrl $file";
      print FH "$ctrl $file\n";
    }
    if ($ctrl eq "MOV") {
      Log 5, "update ".$UPDATE{$pack}{control}.": $ctrl $file $move";
      print FH "$ctrl $file $move\n";
    }

    if ($ctrl eq "DEL") {
      Log 5, "update ".$UPDATE{$pack}{control}.": $ctrl $file";
      print FH "$ctrl $file\n";
    }

  }
  close(FH);
  return undef;
}

########################################
sub
update_ParseControlFile($$$$)
{
  my ($pack,$controlFile,$control_ref,$local) = @_;
  my %control = %$control_ref if ($control_ref && ref($control_ref) eq "HASH");
  my $from = ($local ? "local" : "remote");
  my $ret;

  if ($local) {
    my $str = "";
    # read local controlfile in string
    if (open FH, "$controlFile") {
      $str = do { local $/; <FH> };
    }
    close(FH);
    $controlFile = $str
  }

  # parse file
  if ($controlFile) {
    foreach my $l (split("[\r\n]", $controlFile)) {
      chomp($l);
      Log 5, "update $from controls_".lc($pack).".txt: $l";
      my ($ctrl,$date,$size,$file,$move) = ""; 
      if ($l =~ m/^(UPD) (20\d\d-\d\d-\d\d_\d\d:\d\d:\d\d) (\d+) (\S+)$/) {
        $ctrl = $1;
        $date = $2;
        $size = $3;
        $file = $4;
      } elsif ($l =~ m/^(DIR) (\S+)$/) {
        $ctrl = $1;
        $file = $2;
      } elsif ($l =~ m/^(MOV) (\S+) (\S+)$/) {
        $ctrl = $1;
        $file = $2;
        $move = $3;
      } elsif ($l =~ m/^(DEL) (\S+)$/) {
        $ctrl = $1;
        $file = $2;
      } else {
        $ctrl = "ESC"
      }
      if ($ctrl eq "ESC") {
        Log 1, "update File 'controls_".lc($pack).".txt' ($from) is corrupt";
        $ret = "File 'controls_".lc($pack).".txt' ($from) is corrupt";
      }
      last if ($ret);
#      if ($local) {
#        next if ($l =~ m/^(DEL|MOV) /);
#      }
      $control{$pack}{$file}{ctrl} = $ctrl;
      $control{$pack}{$file}{date} = $date;
      $control{$pack}{$file}{size} = $size;
      $control{$pack}{$file}{file} = $file;
      $control{$pack}{$file}{move} = $move;
    }
  }
  return ($ret, \%control);
}

########################################
sub
update_CleanUpLocalFiles($$$)
{
  my ($ctrl,$file,$move) = @_;
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $ret;

  # make dir
  if ($ctrl eq "DIR") {
    my $mret = update_MakeDirectory($file);
    if ($mret) {
      $ret = "create directory $modpath/$file failed: $mret";
    }
  }
  # move file
  if ($ctrl eq "MOV") {
    my $mvret = mv "$file", "$move" if (-f $file);
    if ($mvret) {
      $ret = "moving $file to $move";
    } else {
      $ret = "moving $file to $move failed: $!";
    }
  }
  # delete file
  if ($ctrl eq "DEL") {
    unlink "$file" if (-f $file);
    if (!$!) {
      $ret = "deleting $file";
    } else {
      $ret = "deleting $file failed: $!";
    }
  }

  return $ret;
}

########################################
sub
update_MakeDirectory($)
{
  my $fullPath = shift;
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $error;
  my $dir;
  my $recPath = "";
  my $ret;

  foreach $dir (split(/\//, $fullPath)) {
    $recPath = "$recPath$dir/";
    if ($dir ne "") {
      if (! -d "$modpath/$recPath") {
        undef($!);
        mkdir "$modpath/$recPath";
        if($!) {
          $error .= "==> $modpath/$recPath: $!\n";
          Log 1, "update Error while creating: $modpath/$recPath: $!";
        }
      }
    }
  }
  if ($error) {
    $ret = "\nError while creating:\n$error";
  }
  return $ret;
}

1;

=pod
=begin html

<a name="update"></a>
<h3>update</h3>
<ul>
  <code>update [development|stable] [&lt;file&gt;|check|fhem|full] [force]</code><br>
  <br>
    The installed fhem distribution and its installed extensions (just like the
    webGUI PGM2) are updated via this command from the online repository. The
    locally installed files will be checked against the online repository and
    will be updated in case the files online are in a newer version. Modules
    which are used while the update is in progress will be restarted in the new
    version after the update has finished.
    <br>
    <br>
    The new update function will process more advanced distribution information
    as well as control commands for updating, removing or renaming existing files.
    New file structures can also be set up by the new control command files.
    The new update process will exclusively work with the file path which is
    given by the global attribute "modpath" except for the fhem.pl file. The user
    decides whether to use a stable, a developer- or a experimental-rated version
    of fhem (experimental is not yet implemented).
    <br>
    <br>
    Furthermore, the use of packages is supported just like in a manual installation
    of fhem. On the moment this only refers to FHEM including PGM2 (FHEMWEB), others
    may follow up. By using the update in this way, only files which are acutally
    used will be updated.
    <br>
    <br>

    <a name="updateattr"></a>
    <b>Attributes</b>
    <ul>
      <li><a href="#backup_before_update">backup_before_update</a></li><br>

      <li><a href="#exclude_from_update">exclude_from_update</a></li><br>

      <li><a href="#updatebranch">updatebranch</a></li><br>
  </ul>
</ul>

=end html
=cut
