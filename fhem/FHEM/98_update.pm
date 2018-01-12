################################################################
# $Id$

package main;
use strict;
use warnings;
use HttpUtils;
use File::Copy qw(mv copy);
use Blocking;

sub CommandUpdate($$);
sub upd_getUrl($);
sub upd_initRestoreDirs($);
sub upd_writeFile($$$$);
sub upd_mv($$);
sub upd_metainit($);
sub upd_metacmd($@);
sub upd_saveConfig($$$);

my $updateInBackground;
my $updRet;
my $updArg;
my $mainPgm = "/fhem.pl\$";
my %upd_connecthash;
my $upd_needJoin;
my $upd_nChanged;
my $upd_running;

eval "require IO::Socket::SSL";  # Forum #74387
my $upd_hasSSL = $@ ? 0 : 1;

########################################
sub
update_Initialize($$)
{
  my %hash = (
    Fn  => "CommandUpdate",
    Hlp => "[<fileName>|all|check|force] [http://.../controlfile],update FHEM",
  );
  $cmds{update} = \%hash;
}

########################################
sub
CommandUpdate($$)
{
  my ($cl,$param) = @_;
  my @args = split(/ +/,$param);

  my $err = upd_metainit(0);
  return $err if($err);

  if($args[0] &&
     ($args[0] eq "list" ||
      $args[0] eq "add" ||
      $args[0] eq "delete" ||
      $args[0] eq "reset")) {
    return upd_metacmd($cl, @args);
  }

  my $arg = (defined($args[0]) ? $args[0] : "all");
  my $src = (defined($args[1]) ? $args[1] : "");

  my $ret = eval { "Hello" =~ m/$arg/ };
  return "first argument must be a valid regexp, all, force or check"
        if($arg =~ m/^[-\?\*]/ || $ret);
  $arg = lc($arg) if($arg =~ m/^(check|all|force)$/i);

  $updateInBackground = AttrVal("global","updateInBackground",1);
  $updateInBackground = 0 if($arg ne "all");                                   
  $updArg = $arg;
  return "An update is already running" if($upd_running);
  $upd_running = 1;
  if($updateInBackground) {
    CallFn($cl->{NAME}, "ActivateInformFn", $cl, "log");
    sub updDone(@) { $upd_running=0 }
    BlockingCall("doUpdateInBackground", {src=>$src,arg=>$arg}, "updDone");
    return "Executing the update the background.";

  } else {
    doUpdateLoop($src, $arg);
    my $ret = $updRet; $updRet = "";
    $upd_running = 0;
    return $ret;

  }
}

sub
upd_metainit($)
{
  my $force = shift;
  my $mpath = $attr{global}{modpath}."/FHEM/controls.txt";
  if($force || ! -f $mpath || -s $mpath == 0) {
     if(!open(FH, ">$mpath")) {
       my $msg = "Can't open $mpath: $!";
       Log 1, $msg;
       return $msg;
     }
     print FH "http://fhem.de/fhemupdate/controls_fhem.txt\n";
     close(FH);
  }
  return undef;
}

sub
upd_metacmd($@)
{
  my ($cl, @args) = @_;

  my $mpath = $attr{global}{modpath}."/FHEM/controls.txt";

  if($args[0] eq "list") {
    open(FH, $mpath) || return "Can't open $mpath: $!";
    my $ret = join("", <FH>);
    close(FH);
    return $ret;
  }

  if($args[0] eq "add") {
    return "Usage: update add http://.../controls_.*.txt"
        if(int(@args) != 2 || $args[1] !~ m,^http.*/(controls_.*.txt)$,);
    my $fname = $1;
    open(FH, $mpath) || return "Can't open $mpath: $!";
    my (%fulls, %parts);
    map {chomp($_);$fulls{$_}=1; my $x=$_; $x =~ s,^.*/,,; $parts{$x}=$_;} <FH>;
    close(FH);
    return "$args[1] is already in the list" if($fulls{$args[1]});
    return "$fname is already present in $parts{$fname}" if($parts{$fname});

    open(FH, ">>$mpath") || return "Can't write $mpath: $!";
    print FH $args[1],"\n";
    close(FH);
    return undef;
  }

  if($args[0] eq "delete") {
    return "Usage: update delete http://.../controls_.*.txt"
        if(int(@args) != 2 || $args[1] !~ m,^http.*/(controls_.*.txt)$,);
    open(FH, $mpath) || return "Can't open $mpath: $!";
    my @list = grep { $_ ne $args[1]."\n"; } <FH>;
    close(FH);
    open(FH, ">$mpath") || return "Can't write $mpath: $!";
    print FH join("", @list);
    close(FH);
    return undef;
  }

  if($args[0] eq "reset") {
    return upd_metainit(1);
  }
}

sub
uLog($$)
{
  my ($loglevel, $arg) = @_;
  return if($loglevel > $attr{global}{verbose} || !defined($arg));

  if($updateInBackground) {
    Log 1, $arg;
  } else {
    Log $loglevel, $arg if($updArg ne "check");
    $updRet .= "$arg\n";
  }
}

my $inLog = 0;
sub
update_Log2Event($$)
{
  my ($level, $text) = @_;
  return if($inLog || $level > $attr{global}{verbose});
  $inLog = 1;
  $text =~ s/\n/ /g; # Multiline text causes havoc in Analyze
  BlockingInformParent("Log", [$level, $text], 0);
  $inLog = 0;
}

sub
doUpdateInBackground($)
{
  my ($h) = @_;

  no warnings 'redefine'; # The main process is not affected
  *Log = \&update_Log2Event;
  sleep(2); # Give time for ActivateInform / FHEMWEB / JavaScript
  doUpdateLoop($h->{src}, $h->{arg});
}

sub
doUpdateLoop($$)
{
  my ($src, $arg) = @_;

  $upd_needJoin = 0;
  $upd_nChanged = 0;
  if($src =~ m/^http.*/) {
    doUpdate(1,1, $src, $arg);
    HttpUtils_Close(\%upd_connecthash);
    return;
  }

  my $mpath = $attr{global}{modpath}."/FHEM/controls.txt";
  if(!open(LFH, $mpath)) {
    my $msg = "Can't open $mpath: $!";
    uLog 1, $msg;
    return $msg;
  }
  my @list = <LFH>;
  close(LFH);
  chomp @list;

  my ($max,$curr) = (0,0);
  foreach my $srcLine (@list)  {
    next if($src && $srcLine !~ m/controls_${src}.txt/);
    $max++;
  }
  uLog 1, "No source file named controls_$src found" if($src && !$max);

  foreach my $srcLine (@list)  {
    next if($src && $srcLine !~ m/controls_${src}.txt/);
    doUpdate(++$curr, $max, $srcLine, $arg);
    HttpUtils_Close(\%upd_connecthash);
  }
  
  if($upd_nChanged) {
    if($updateInBackground) {
      BlockingInformParent("DoTrigger", ["global", "UPDATE", 0 ], 0)
    } else {
      DoTrigger("global","UPDATE", 0);
    }
  }
}

sub
doUpdate($$$$)
{
  my ($curr, $max, $src, $arg) = @_;
  my ($basePath, $ctrlFileName);
  $src =~ s'^http://fhem\.de'https://fhem.de' if($upd_hasSSL);
  if($src !~ m,^(.*)/([^/]*)$,) {
    uLog 1, "Cannot parse $src, probably not a valid http control file";
    return;
  }
  $basePath = $1;
  $ctrlFileName = $2;
  $ctrlFileName =~ m/controls_(.*).txt/;
  my $srcName = $1;

  if(AttrVal("global", "backup_before_update", 0) &&
     $arg ne "check" && $curr==1) {
    my $cmdret = AnalyzeCommand(undef, "backup startedByUpdate");
    if ($cmdret !~ m/backup done.*/) {
      uLog 1, "Something went wrong during backup: $cmdret";
      uLog 1, "update was canceled. Please check manually!";
      return;
    }
  }

  if($max != 1) {
    uLog 1, "";
    uLog 1, $srcName;
  }

  my $remCtrlFile = upd_getUrl($src);
  return if(!$remCtrlFile);
  my @remList = split(/\R/, $remCtrlFile);
  uLog 4, "Got remote $ctrlFileName with ".int(@remList)." entries.";

  ###########################
  # read in & digest the local control file
  my $root = $attr{global}{modpath};
  my $restoreDir = ($arg eq "check" ? "" : restoreDir_init());

  my @locList;
  if(($arg eq "check" || $arg eq "all") &&
     open(FD, "$root/FHEM/$ctrlFileName")) {
    @locList = map { $_ =~ s/[\r\n]//; $_ } <FD>;
    close(FD);
    uLog 4, "Got local $ctrlFileName with ".int(@locList)." entries.";
  }
  my %lh;
  foreach my $l (@locList) {
    my @l = split(" ", $l, 4);
    next if($l[0] ne "UPD");
    $lh{$l[3]}{TS} = $l[1];
    $lh{$l[3]}{LEN} = $l[2];
  }

  my $canJoin;
  my $cmod = AttrVal('global', 'commandref', 'full');
  my $cj = "$root/contrib/commandref_".
                ($cmod eq "full" ? "join":"modular").".pl";
  if(-f $cj &&
     -f "$root/docs/commandref_frame.html" &&
     -w "$root/docs/commandref.html" &&
     (AttrVal('global','exclude_from_update','') !~ m/commandref/) ) {
    $canJoin = 1;
  }

  my @excl = split(" ", AttrVal("global", "exclude_from_update", ""));
  my $noSzCheck = AttrVal("global", "updateNoFileCheck", configDBUsed());

  my @rl = upd_getChanges($root, $basePath);
  ###########################
  # process the remote controlfile
  my ($nChanged,$nSkipped) = (0,0);
  my $isSingle = ($arg ne "all" && $arg ne "force"  && $arg ne "check");
  foreach my $r (@remList) {
    my @r = split(" ", $r, 4);

    if($r[0] eq "MOV" && ($arg eq "all" || $arg eq "force")) {
      if($r[1] =~ m+\.\.+ || $r[2] =~ m+\.\.+) {
        uLog 1, "Suspicious line $r, aborting";
        return 1;
      }
      restoreDir_mkDir($root, $r[2], 0);
      my $mvret = upd_mv("$root/$r[1]", "$root/$r[2]");
      uLog 4, "mv $root/$r[1] $root/$r[2]". ($mvret ? " FAILED:$mvret":"");
    }

    next if($r[0] ne "UPD");
    my $fName = $r[3];
    if($fName =~ m+\.\.+) {
      uLog 1, "Suspicious line $r, aborting";
      return 1;
    }

    if($isSingle) {
      next if($fName !~ m/$arg/);

    } else {
   
      my $isExcl;
      foreach my $ex (@excl) {
        $isExcl = 1 if($fName =~ m/$ex/ || "$src:$fName" =~ m/$ex/);
      }
      my $fPath = "$root/$fName";
      $fPath = $0 if($fPath =~ m/$mainPgm/);
      my $fileOk = ($lh{$fName} &&
                    $lh{$fName}{TS} eq $r[1] &&
                    $lh{$fName}{LEN} eq $r[2]);
      if($isExcl && !$fileOk) {
        uLog 1, "update: skipping $fName, matches exclude_from_update";
        $nSkipped++;
        next;
      }

      if($noSzCheck) {
        next if($isExcl || $fileOk);

      } else {
        my $sz = -s $fPath;
        next if($isExcl || ($fileOk && defined($sz) && $sz eq $r[2]));

      }
    }

    $upd_needJoin = 1 if($fName =~ m/commandref_frame/ || $fName=~ m/\d+.*.pm/);
    next if($fName =~ m/commandref.*html/ && $fName !~ m/frame/ && $canJoin);

    uLog 1, "List of new / modified files since last update:"
      if($arg eq "check" && $nChanged == 0);

    $nChanged++;
    uLog 1, "$r[0] $fName";
    next if($arg eq "check");

    my $remFile = upd_getUrl("$basePath/$fName");
    return if(!$remFile); # Error already reported

    if(length($remFile) ne $r[2]) {
      uLog 1, "Got ".length($remFile)." bytes for $fName, expected $r[2]";
      if($attr{global}{verbose} == 5) {
        upd_writeFile($root, $restoreDir, "$fName.corrupt", $remFile);
        uLog 1, "saving it to $fName.corrupt .";
        next;
      } else {
        uLog 1, "aborting.";
        return;
      }
    }

    return if(!upd_writeFile($root, $restoreDir, $fName, $remFile));
  }

  if($nChanged) {
    for my $f ($attr{global}{configfile}, $attr{global}{statefile}) {
      upd_saveConfig($root, $restoreDir, $f) if($f && $f !~ m,(^/|\.\.),);
    }
  }

  uLog 1, "nothing to do..." if($nChanged == 0 && $nSkipped == 0);

  if(@rl && ($nChanged || $nSkipped)) {
    uLog(1, "");
    uLog 1, "New entries in the CHANGED file:";
    map { uLog 1, $_ } @rl;
  }
  return if($arg eq "check");

  if(($arg eq "all" || $arg eq "force") && ($nChanged || $nSkipped)) {
    return if(!upd_writeFile($root, $restoreDir,
                           "FHEM/$ctrlFileName", $remCtrlFile));
  }


  if($canJoin && $upd_needJoin && $curr == $max) {
    chdir($root);
    $cj .= " -noWarnings" if($cmod eq "full");
    uLog(1, "Calling $^X $cj, this may take a while");
    my $ret = `$^X $cj`;
    foreach my $l (split(/[\r\n]+/, $ret)) {
      uLog(1, $l);
    }
  }

  $upd_nChanged += $nChanged;
  return "" if(!$upd_nChanged);

  uLog(1, "");
  if($curr == $max) {
    uLog 1,
       'update finished, "shutdown restart" is needed to activate the changes.';
    my $ss = AttrVal("global","sendStatistics",undef);
    if(!defined($ss)) {
      uLog(1, "");
      uLog(1, "Please consider using the global attribute sendStatistics");
    } elsif(defined($ss) && lc($ss) eq "onupdate") {
      uLog(1, "");
      my $ret = AnalyzeCommandChain(undef, "fheminfo send");
      $ret =~ s/.*server response:/server response:/ms;
      uLog(1, "fheminfo $ret");
    }
  }
}

sub
upd_mv($$)
{
  my ($src, $dest) = @_;
  if($src =~ m/\*/) {
    $src =~ m,^(.*)/([^/]+)$,;
    my ($dir, $pat) = ($1, $2);
    $pat = "^$pat\$";
    opendir(my $dh, $dir) || return "$dir: $!";
    while(my $r = readdir($dh)) {
      next if($r !~ m/$pat/ || "$dir/$r" eq $dest);
      my $mvret = mv("$dir/$r", $dest);
      return "MV $dir/$r $dest: $!" if(!$mvret);
      Log 3, "MV $dir/$r $dest";
    }
    closedir($dh);

  } else {
    return "MV $src $dest: $!" if(mv($src, $dest));

  }
  return undef;
}

sub
upd_getChanges($$)
{
  my ($root, $basePath) = @_;
  my $lFile = "";
  if(open(FH, "$root/CHANGED")) {
    foreach my $l (<FH>) { # first non-comment line
      next if($l =~ m/^#/);
      chomp $l;
      $lFile = $l;
      last;
    }
    close(FH);
  }
  my @lines = split(/[\r\n]/,upd_getUrl("$basePath/CHANGED"));
  my $maxLines = 25;
  my @ret;
  foreach my $line (@lines) {
    next if($line =~ m/^#/);
    last if($line eq "" || $line eq $lFile);
    push @ret, $line;
    if($maxLines-- < 1) {
      push @ret, "... rest of lines skipped.";
      last;
    }
  }
  return @ret;
}

sub
upd_getUrl($)
{
  my ($url) = @_;
  $url =~ s/%/%25/g;
  $upd_connecthash{url} = $url;
  $upd_connecthash{keepalive} = ($url =~ m/localUpdate/ ? 0 : 1); # Forum #49798
  my ($err, $data) = HttpUtils_BlockingGet(\%upd_connecthash);
  if($err) {
    uLog 1, $err;
    return "";
  }
  if(!$data) {
    uLog 1, "$url: empty file received";
    return "";
  }
  return $data;
}

sub
upd_saveConfig($$$)
{
  my($root, $restoreDir, $fName) = @_;

  return if(!$fName || !$restoreDir || configDBUsed() || !-r "$root/$fName");
  restoreDir_mkDir($root, "$restoreDir/$fName", 1);
  Log 1, "saving $fName";
  if(!copy("$root/$fName", "$root/$restoreDir/$fName")) {
    uLog 1, "copy $root/$fName $root/$restoreDir/$fName failed:$!, ".
              "aborting the update";
    return 0;
  }
}

sub
upd_writeFile($$$$)
{
  my($root, $restoreDir, $fName, $content) = @_;

  # copy the old file and save the new
  restoreDir_mkDir($root, $fName, 1);
  restoreDir_mkDir($root, "$restoreDir/$fName", 1) if($restoreDir);
  if($restoreDir && -f "$root/$fName" &&
     ! copy("$root/$fName", "$root/$restoreDir/$fName")) {
    uLog 1, "copy $root/$fName $root/$restoreDir/$fName failed:$!, ".
              "aborting the update";
    return 0;
  }

  my $rest = ($restoreDir ? "trying to restore the previous version and ":"").
                "aborting the update";
  my $fPath = "$root/$fName";
  $fPath = $0 if($fPath =~ m/$mainPgm/);
  if(!open(FD, ">$fPath")) {
    uLog 1, "open $fPath failed: $!, $rest";
    copy "$root/$restoreDir/$fName", "$root/$fName" if($restoreDir);
    return 0;
  }
  binmode(FD);
  print FD $content;
  close(FD);

  my $written = -s "$fPath";
  if($written != length($content)) {
    uLog 1, "writing $fPath failed: $!, $rest";
    copy "$root/$restoreDir/$fName", "$fPath" if($restoreDir);
    return;
  }

  cfgDB_FileUpdate("$fPath") if(configDBUsed());

  return 1;
}

1;

=pod
=item command
=item summary    update FHEM program files from the central repository
=item summary_DE FHEM Programmdateien aktualisieren
=begin html

<a name="update"></a>
<h3>update</h3>
<ul>
  <code>update [&lt;fileName&gt;|all|check|force]
       [http://.../controlfile]</code>
  <br>or<br>
  <code>update [add source|delete source|list|reset]</code>
  <br>
  <br>
  Update the FHEM installation. Technically this means update will download
  the controlfile(s) first, compare it to the local version of the file in the
  moddir/FHEM directory, and download each file where the attributes (timestamp
  and filelength) are different. Upon completion it triggers the global:UPDATE
  event.
  <br>
  With the commands add/delete/list/reset you can manage the list of
  controlfiles, e.g. for thirdparty packages.
  Notes:
  <ul>
    <li>The contrib directory will not be updated.</li>
    <li>The files are automatically transferred from the source repository
        (SVN) to the web site once a day, at 7:45 CET / CEST.</li>
    <li>The all argument is default.</li>
    <li>The force argument will disregard the local file.</li>
    <li>The check argument will only display the files it would download, and
        the last section of the CHANGED file.</li>
    <li>Specifying a filename will only download matching files (regexp).</li>
  </ul>
  See also the restore command.<br>
  <br>
  Examples:<br>
  <ul>
    <li>update check</li>
    <li>update</li>
    <li>update force</li>
    <li>update check http://fhem.de/fhemupdate/controls_fhem.txt</li>
  </ul>
  <a name="updateattr"></a>

  <br>
  <b>Attributes</b> (use attr global ...)
  <ul>
    <a name="updateInBackground"></a>
    <li>updateInBackground<br>
        If this attribute is set (to 1), the update will be executed in a
        background process. The return message is communicated via events, and
        in telnet the inform command is activated, in FHEMWEB the Event
        Monitor. Default is set. Set it to 0 to switch it off.
        </li><br>

    <a name="updateNoFileCheck"></a>
    <li>updateNoFileCheck<br>
        If set, the command won't compare the local file size with the expected
        size. This attribute was introduced to satisfy some experienced FHEM
        user, its default value is 0.
        </li><br>

    <a name="backup_before_update"></a>
    <li>backup_before_update<br>
        If this attribute is set, an update will back up your complete
        installation via the <a href="#backup">backup</a> command. The default
        is not set as update relies on the restore feature (see below).<br>
        Example:<br>
        <ul>
          attr global backup_before_update
        </ul>
        </li><br>

    <a name="exclude_from_update"></a>
    <li>exclude_from_update<br>
        Contains a space separated list of fileNames (regexps) which will be
        excluded by an update. The special value commandref will disable calling
        commandref_join at the end, i.e commandref.html will be out of date.
        The module-only documentation is not affected and is up-to-date.<br>
        Example:<br>
        <ul>
          attr global exclude_from_update 21_OWTEMP.pm FS20.off.png
        </ul>
        The regexp is checked against the filename and the source:filename
        combination. To exclude the updates for FILE.pm from fhem.de, as you are
        updating it from another source, specify fhem.de.*:FILE.pm
        </li><br>

    <li><a href="#restoreDirs">restoreDirs</a></li><br>

  </ul>
</ul>

=end html
=begin html_DE

<a name="update"></a>
<h3>update</h3>
<ul>
  <code>update [&lt;fileName&gt;|all|check|force]
        [http://.../controlfile]</code>
  <br>oder<br>
  <code>update [add source|delete source|list|reset]</code>
  <br>
  <br>
  Erneuert die FHEM Installation. D.h. es wird (werden) zuerst die
  Kontroll-Datei(en) heruntergeladen, und mit der lokalen Version dieser Datei
  in moddir/FHEM verglichen. Danach werden alle in der  Kontroll-Datei
  spezifizierten Dateien heruntergeladen, deren Gr&ouml;&szlig;e oder
  Zeitstempel sich unterscheidet. Wenn dieser Ablauf abgeschlossen ist, wird
  das globale UPDATE Ereignis ausgel&ouml;st.
  <br>
  Mit den Befehlen add/delete/list/reset kann man die Liste der Kontrolldateien 
  pflegen.
  <br>
  <br>
  Zu beachten:
  <ul>
    <li>Das contrib Verzeichnis wird nicht heruntergeladen.</li>
    <li>Die Dateien werden auf der Webseite einmal am Tag um 07:45 MET/MEST aus
        der Quell-Verwaltungssystem (SVN) bereitgestellt.</li>
    <li>Das all Argument ist die Voreinstellung.</li>
    <li>Das force Argument beachtet die lokale controls_fhem.txt Datei
        nicht.</li>
    <li>Das check Argument zeigt die neueren Dateien an, und den letzten
        Abschnitt aus der CHANGED Datei</li>
    <li>Falls man &lt;fileName&gt; spezifiziert, dann werden nur die Dateien
        heruntergeladen, die diesem Regexp entsprechen.</li>
  </ul>
  Siehe also das restore Befehl.<br>
  <br>
  Beispiele:<br>
  <ul>
    <li>update check</li>
    <li>update</li>
    <li>update force</li>
    <li>update check http://fhem.de/fhemupdate/controls_fhem.txt</li>
  </ul>
  <a name="updateattr"></a>

  <br>
  <b>Attribute</b>  (sind mit attr global zu setzen)
  <ul>
    <a name="updateInBackground"></a>
    <li>updateInBackground<br>
        Wenn dieses Attribut gesetzt ist, wird das update Befehl in einem
        separaten Prozess ausgef&uuml;hrt, und alle Meldungen werden per Event
        &uuml;bermittelt. In der telnet Sitzung wird inform, in FHEMWEB wird
        das Event Monitor aktiviert. Die Voreinstellung ist an, zum
        Deaktivieren bitte Attribut auf 0 setzen.
        </li><br>

    <a name="updateNoFileCheck"></a>
    <li>updateNoFileCheck<br>
        Wenn dieses Attribut gesetzt ist, wird die Gr&ouml;&szlig;e der bereits
        vorhandenen, lokalen Datei nicht mit der Sollgr&ouml;&szlig;e
        verglichen. Dieses Attribut wurde nach nicht genau spezifizierten Wnsch
        erfahrener FHEM Benutzer eingefuehrt, die Voreinstellung ist 0.
        </li><br>

    <a name="backup_before_update"></a>
    <li>backup_before_update<br>
        Wenn dieses Attribut gesetzt ist, erstellt FHEM eine Sicherheitskopie
        der FHEM Installation vor dem update mit dem backup Befehl. Die
        Voreinstellung is "nicht gesetzt", da update sich auf das restore
        Feature verl&auml;sst, s.u.<br>
        Beispiel:<br>
        <ul>
          attr global backup_before_update
        </ul>
        </li><br>

    <a name="exclude_from_update"></a>
    <li>exclude_from_update<br>
        Enth&auml;lt eine Liste durch Leerzeichen getrennter Dateinamen
        (regexp), welche nicht im update ber&uuml;cksichtigt werden.<br>
        Falls der Wert commandref enth&auml;lt, dann wird commandref_join.pl
        nach dem update nicht aufgerufen, d.h. die Gesamtdokumentation ist
        nicht mehr aktuell. Die Moduldokumentation bleibt weiterhin aktuell.
        <br>
        Beispiel:<br>
        <ul>
          attr global exclude_from_update 21_OWTEMP.pm temp4hum4.gplot 
        </ul>
        Der Regexp wird gegen den Dateinamen und gegen Quelle:Dateiname
        gepr&uuml;ft. Um die Datei FILE.pm von updates von fhem.de
        auszuschlie&szlig;en, weil sie von einer anderen Quelle bezogen wird,
        kann man fhem.de.*:FILE.pm spezifizieren.

        </li><br>

    <li><a href="#restoreDirs">restoreDirs</a></li><br>

  </ul>
</ul>


=end html_DE
=cut
