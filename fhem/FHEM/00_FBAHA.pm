##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub FBAHA_Read($@);
sub FBAHA_Write($$$);
sub FBAHA_ReadAnswer($$$);
sub FBAHA_Ready($);

sub FBAHA_getDevList($$);


sub
FBAHA_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}       = "FBAHA_Read";
  $hash->{WriteFn}      = "FBAHA_Write";
  $hash->{ReadyFn}      = "FBAHA_Ready";
  $hash->{UndefFn}      = "FBAHA_Undef";
  $hash->{ShutdownFn}   = "FBAHA_Undef";
  $hash->{ReadAnswerFn} = "FBAHA_ReadAnswer";
  $hash->{NotifyFn}     = "FBAHA_Notify";

# Normal devices
  $hash->{DefFn}   = "FBAHA_Define";
  $hash->{GetFn}   = "FBAHA_Get";
  $hash->{SetFn}   = "FBAHA_Set";
  $hash->{AttrList}= "dummy:1,0";
}


#####################################
sub
FBAHA_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    return "wrong syntax: define <name> FBAHA hostname:2002";
  }

  my $name = $a[0];
  my $dev = $a[2];
  $hash->{Clients} = ":FBDECT:";
  my %matchList = ( "1:FBDECT" => ".*" );
  $hash->{MatchList} = \%matchList;

  DevIo_CloseDev($hash);
  $hash->{DeviceName} = $dev;

  return undef if($dev eq "none"); # DEBUGGING
  my $ret = DevIo_OpenDev($hash, 0, "FBAHA_DoInit");
  return $ret;
}

#####################################
sub
FBAHA_Notify($$)
{
  my ($ntfy, $dev) = @_;
  return if($dev->{NAME} ne "global" ||
            !grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}));
  delete $modules{FBAHA}{NotifyFn};
  FBAHA_reassign($ntfy);
  return;
}

#####################################
sub
FBAHA_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;
  my %sets = ("createDevs"=>1, "reregister"=>1, "reopen"=>1);

  return "set $name needs at least one parameter" if(@a < 1);
  my $type = shift @a;

  return "Unknown argument $type, choose one of " . join(" ", sort keys %sets)
    if(!defined($sets{$type}));

  if($type eq "createDevs") {

    my %ex;
    foreach my $sdev (devspec2array("TYPE=FBDECT")) {
      my @dl = split(" ", $defs{$sdev}{DEF});
      $ex{$dl[0]} = 1;
    }

    my @arg = FBAHA_getDevList($hash,0);
    foreach my $arg (@arg) {
      if($arg =~ m/ID:(\d+).*PROP:(.*)/) {
        my ($i,$p) = ($1,$2,$3);
        next if($ex{"$name:$i"});
        my $msg = "UNDEFINED FBDECT_$i FBDECT $name:$i $p";
        DoTrigger("global", $msg, 1);
        Log3 $name, 3, "$msg, please define it";
      }
    }
  }

  if($type eq "reregister") {
    # Release seems to be deadly on the 546e
    FBAHA_Write($hash, "02", "") if($hash->{HANDLE});  # RELEASE
    FBAHA_Write($hash, "00", "00022005");              # REGISTER
    my ($err, $data) = FBAHA_ReadAnswer($hash, "REGISTER", "^01");
    if($err) {
      Log3 $name, 1, $err;
      $hash->{STATE} =
      $hash->{READINGS}{state}{VAL} = "???";
      $hash->{READINGS}{state}{TIME} = TimeNow();
      return $err;
    }

    if($data =~ m/^01030010(........)/) {
      $hash->{STATE} =
      $hash->{READINGS}{state}{VAL} = "Initialized";
      $hash->{READINGS}{state}{TIME} = TimeNow();
      $hash->{HANDLE} = $1;
      Log3 $name, 1,
        "FBAHA $hash->{NAME} registered with handle: $hash->{HANDLE}";

    } else {
      my $msg = "Got bogus answer for REGISTER request: $data";
      Log3 $name, 1, $msg;
      $hash->{STATE} =
      $hash->{READINGS}{state}{VAL} = "???";
      $hash->{READINGS}{state}{TIME} = TimeNow();
      return $msg;

    }
    FBAHA_Write($hash, "03", "0000038200000000");  # LISTEN

  }

  if($type eq "reopen") {
    DevIo_CloseDev($hash);
    delete $hash->{HANDLE};
    return DevIo_OpenDev($hash, 0, "FBAHA_DoInit");
  }

  return undef;
}

#####################################
sub
FBAHA_Get($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;
  my %gets = ("devList"=>1);

  return "get $name needs at least one parameter" if(@a < 1);
  my $type = shift @a;

  return "Unknown argument $type, choose one of ". join(" ", sort keys %gets)
    if(!defined($gets{$type}));

  if($type eq "devList") {
    return join("\n", FBAHA_getDevList($hash,0));
  }

  return undef;
}

sub
FBAHA_getDevList($$)
{
  my ($hash, $onlyId) = @_;

  FBAHA_Write($hash, "05", "00000000");  # CONFIG_REQ
  my $data = "";
  for(;;) {
    my ($err, $buf) = FBAHA_ReadAnswer($hash, "CONFIG_RSP", "^06");
    last if($err && $err =~ m/Timeout/);
    return ($err) if($err);
    $data .= substr($buf, 32);
    last if($buf =~ m/^060[23]/);
  }

  return FBAHA_configInd($data, $onlyId);
}

sub
FBAHA_configInd($$)
{
  my ($data, $onlyId) = @_;
  #my $off = 288; #for old Client Id
  my $off = 304;
  my @answer;

  while(length($data) >= $off) {
    my $id  = hex(substr($data,  0, 4)); 
    my $act = hex(substr($data,  4, 2));
    my $typ = hex(substr($data,  8, 8));
    my $lsn = hex(substr($data, 16, 8));
    my $nam = pack("H*",substr($data,24,160)); $nam =~ s/\x0//g;

    $act = ($act == 2 ? "active" : ($act == 1 ? "inactive" : "removed"));

    my %tl = ( 2=>"AVM FRITZ!Dect Powerline 546E",
               3=>"Comet DECT",
               9=>"AVM FRITZ!Dect 200");
    $typ = $tl{$typ} ? $tl{$typ} : "unknown($typ)";

    my %ll = (7=>"powerMeter",9=>"switch");
    $lsn = join ",", map { $ll{$_} if((1 << $_) & $lsn) } sort keys %ll;

    my $dlen = hex(substr($data, $off-8, 8))*2; # DATA MSG

    push @answer, "NAME:$nam, ID:$id, $act, TYPE:$typ PROP:$lsn"
      if(!$onlyId || $onlyId == $id);

    if($onlyId && $onlyId == $id) {
      my $mnf = hex(substr($data,184, 8)); # empty/0
      my $idf = substr($data,192,40); $idf =~ s/(00)*$//; $idf =pack("H*",$idf);
      my $frm = substr($data,232,40); $frm =~ s/(00)*$//; $frm =pack("H*",$frm);
      push @answer, "  MANUF:$mnf";
      push @answer, "  UniqueID:$idf";
      push @answer, "  Firmware:$frm";
      push @answer, substr($data, $off, $dlen);
      return @answer;
    }
    $data = substr($data, $off+$dlen); # rest
  }
  return @answer;
}

#####################################
# Check all FBDECTs, reorg them if the id has changed and FBNAME is set.
sub
FBAHA_reassign($)
{
  my ($me) = @_;
  my $myname = $me->{NAME};

  my $devList = FBAHA_Get($me, ($myname, "devList"));
  my %fbdata;
  foreach my $l (split("\n", $devList)) {
    next if($l !~ m/NAME:(.*), ID:(.*), (.*), TYPE:(.*) PROP:(.*)/);
    if($fbdata{$1}) {
      Log 1, "FBAHA: multiple devices are using the same name, wont reorder";
      return;
    }
    $fbdata{$1} = $2;
  }

  foreach my $sdev (devspec2array("TYPE=FBDECT")) {
    my $hash = $defs{$sdev};
    my $name = $hash->{NAME};
    my $fbname = ReadingsVal($name, "FBNAME", "");
    my $fbid = $fbdata{$fbname};
    my $oldid = $hash->{id};

    next if(!$fbid || $oldid eq $fbid || $hash->{IODev}{NAME} ne $myname);
    Log 2, "FBAHA: changing the id of $name/$fbname from $oldid to $fbid";

    delete $modules{FBDECT}{defptr}{"$myname:$oldid"};
    $modules{FBDECT}{defptr}{"$myname:$fbid"} = $hash;
    $hash->{DEF} =~ s/^$myname:$oldid /$myname:$fbid /; # New syntax
    $hash->{DEF} =~ s/^$oldid /$myname:$fbid /;         # Old Syntax
    $hash->{id} = $fbid;
  }

  return;
}

#####################################
sub
FBAHA_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  delete $hash->{HANDLE}; # else reregister fails / RELEASE is deadly
  my $ret = FBAHA_Set($hash, ($name, "reregister"));
  FBAHA_reassign($hash) if(!$ret && $init_done);
  return $ret;
}

#####################################
sub
FBAHA_Undef($@)
{
  my ($hash, $arg) = @_;
  FBAHA_Write($hash, "02", "");  # RELEASE
  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
FBAHA_Write($$$)
{
  my ($hash,$fn,$msg) = @_;

  $msg = sprintf("%s03%04x%s%s", $fn, length($msg)/2+8,
           $hash->{HANDLE} ?  $hash->{HANDLE} : "00000000", $msg);
  DevIo_SimpleWrite($hash, $msg, 1);
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
FBAHA_Read($@)
{
  my ($hash, $local, $regexp) = @_;

  my $buf = ($local ? $local : DevIo_SimpleRead($hash));
  return "" if(!defined($buf));

  my $name = $hash->{NAME};

  $buf = unpack('H*', $buf);
  my $data = ($hash->{PARTIAL} ? $hash->{PARTIAL} : "");

  # drop old data
  if($data) {
    $data = "" if(gettimeofday() - $hash->{READ_TS} > 5);
    delete($hash->{READ_TS});
  }

  Log3 $name, 5, "FBAHA/RAW: $data/$buf";
  $data .= $buf;

  my $msg;
  while(length($data) >= 16) {
    my $len = hex(substr($data, 4,4))*2;
    if($len < 16 || $len > 20480) { # Out of Sync
      Log3 $name, 1, "FBAHA: resetting buffer as we are out of sync ($len)";
      $hash->{PARTIAL} = "";
      return "";
    }
    last if($len > length($data));
    $msg = substr($data, 0, $len);
    $data = substr($data, $len);
    last if(defined($local) && (!defined($regexp) || ($msg =~ m/$regexp/)));

    $hash->{"${name}_MSGCNT"}++;
    $hash->{"${name}_TIME"} = TimeNow();
    $hash->{RAWMSG} = $msg;
    my %addvals = (RAWMSG => $msg);
    Dispatch($hash, $msg, \%addvals) if($init_done);
    $msg = undef;
  }

  $hash->{PARTIAL} = $data;
  $hash->{READ_TS} = gettimeofday() if($data);
  return $msg if(defined($local));
  return undef;
}

#####################################
# This is a direct read for commands like get
sub
FBAHA_ReadAnswer($$$)
{
  my ($hash, $arg, $regexp) = @_;
  return ("No FD (dummy device?)", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

  for(;;) {
    return ("Device lost when reading answer for get $arg", undef)
      if(!$hash->{FD});
    my $rin = '';
    vec($rin, $hash->{FD}, 1) = 1;
    my $nfound = select($rin, undef, undef, 3);
    if($nfound <= 0) {
      next if ($! == EAGAIN() || $! == EINTR());
      my $err = ($! ? $! : "Timeout");
      #$hash->{TIMEOUT} = 1;
      #DevIo_Disconnected($hash);
      return("FBAHA_ReadAnswer $arg: $err", undef);
    }
    my $buf = DevIo_SimpleRead($hash);
    return ("No data", undef) if(!defined($buf));

    my $ret = FBAHA_Read($hash, $buf, $regexp);
    return (undef, $ret) if(defined($ret));
  }
}

#####################################
sub
FBAHA_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "FBAHA_DoInit")
                if($hash->{STATE} eq "disconnected");
  return 0;
}

1;

=pod
=item summary    (deprecated) connection to the Fritz!OS AHA Server
=item summary_DE Anbindung des (veralteten) Fritz!OS AHA Servers
=begin html

<a name="FBAHA"></a>
<h3>FBAHA</h3>
<ul>
  <br>Note: Fritz!OS 6.90 and later does not offer the AHA service needed by
  this module. Use the successor FBAHAHTTP instead of this module.</b><br>

  This module connects to the AHA server (AVM Home Automation) on a FRITZ!Box.
  It serves as the "physical" counterpart to the <a href="#FBDECT">FBDECT</a>
  devices. Note: you have to enable the access to this feature in the FRITZ!Box
  frontend first.
  <br><br>
  <a name="FBAHAdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FBAHA &lt;device&gt;</code>
  <br>
  <br>
  &lt;device&gt; is either a &lt;host&gt;:&lt;port&gt; combination, where
  &lt;host&gt; is normally the address of the FRITZ!Box running the AHA server
  (fritz.box or localhost), and &lt;port&gt; 2002, or
  UNIX:SEQPACKET:/var/tmp/me_avm_home_external.ctl, the latter only works on
  the fritz.box. With FRITZ!OS 5.50 the network port is available, on some
  Labor variants only the UNIX socket is available.<br>

  Example:
  <ul>
    <code>define fb1 FBAHA fritz.box:2002</code><br>
    <code>define fb1 FBAHA UNIX:SEQPACKET:/var/tmp/me_avm_home_external.ctl</code><br>
  </ul>
  </ul>
  <br>

  <a name="FBAHAset"></a>
  <b>Set</b>
  <ul>
  <li>createDevs<br>
    create a FHEM device for each DECT device found on the AHA-Host, see also
    get devList.
    </li>
  <li>reopen<br>
    close and reopen the connection to the AHA server. Debugging only.
    </li>
  <li>reregister<br>
    release existing registration handle, and get a new one. Debugging only.
    </li>
  </ul>
  <br>

  <a name="FBAHAget"></a>
  <b>Get</b>
  <ul>
  <li>devList<br>
    return a list of devices with short info.
    </li>
  </ul>
  <br>

  <a name="FBAHAattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#dummy">dummy</a></li>
  </ul>
  <br>

  <a name="FBAHAevents"></a>
  <b>Generated events:</b>
  <ul>
  <li>UNDEFINED FBDECT_$ahaName_${NR} FBDECT $id"
    </li>
  </ul>

  <br>
  As sometimes the FRITZ!Box reassigns the internal id's of the FBDECT devices,
  the FBAHA module compares upon connect/reconnect the stored names (FBNAME)
  with the current value. This feature will only work, if you assign each
  FBDECT device a unique Name in the FRITZ!Box, and excecute the FHEM "get
  FBDECTDEVICE devInfo" command, which saves the FBNAME reading.<br>

</ul>


=end html

=begin html_DE

<a name="FBAHA"></a>
<h3>FBAHA</h3>
<ul>
  <br>Achtung: ab Fritz!OS 6.90 ist der ben&ouml;tigte Dienst deaktiviert,
  bitte den Nachfolger FBAHAHTTP verwenden.</b><br>

  Dieses Modul verbindet sich mit dem AHA (AVM Home Automation) Server auf
  einem FRITZ!Box. Es dient als "physikalisches" Gegenst&uuml;ck zum <a
  href="#FBDECT">FBDECT</a> Modul. Als erstes muss der Zugang zu diesen Daten
  in der FRITZ!Box Web-Oberfl&auml;che aktiviert werden.
  <br><br>
  <a name="FBAHAdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FBAHA &lt;device&gt;</code>
  <br>
  <br>
  &lt;host&gt; ist normalerweise die Adresse der FRITZ!Box, wo das AHA Server
  l&auml;uft (fritz.box oder localhost), &lt;port&gt; ist 2002.

  &lt;device&gt; is entweder a eine Kombianation aus &lt;host&gt;:&lt;port&gt;,
  wobei &lt;host&gt; die Adresse der FRITZ!Box ist (localhost AUF dem
  FRITZ.BOX) und &lt;port&gt; 2002 ist, oder
  UNIX:SEQPACKET:/var/tmp/me_avm_home_external.ctl, wobei das nur fuer
  FHEM@FRITZ!BOX zur Verf&uuml;gung steht. Mit FRITZ!OS 5.50 steht auch der
  Netzwerkport zur Verf&uuml;gung, auf manchen Laborvarianten nur das UNIX
  socket.<br>
  
  Beispiel:
  <ul>
    <code>define fb1 FBAHA fritz.box:2002</code><br>
    <code>define fb1 FBAHA UNIX:SEQPACKET:/var/tmp/me_avm_home_external.ctl</code><br>
  </ul>
  </ul>
  <br>

  <a name="FBAHAset"></a>
  <b>Set</b>
  <ul>
  <li>createDevs<br>
    legt FHEM Ger&auml;te an f&uuml;r jedes auf dem AHA-Server gefundenen DECT
    Eintrag, siehe auch "get devList".
    </li>
  <li>reopen<br>
    Schlie&szlig;t und &oulm;ffnet die Verbindung zum AHA Server. Nur f&uuml;r
    debugging.
    </li>
  <li>reregister<br>
    Gibt den AHA handle frei, und registriert sich erneut beim AHA Server. Nur
    f&uuml;r debugging.
    </li>
  </ul>
  <br>

  <a name="FBAHAget"></a>
  <b>Get</b>
  <ul>
  <li>devList<br>
    liefert die Liste aller DECT-Eintr&auml;ge der AHA Server zur&uuml;ck, mit
    einem kurzen Info.
    </li>
  </ul>
  <br>

  <a name="FBAHAattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#dummy">dummy</a></li>
  </ul>
  <br>

  <a name="FBAHAevents"></a>
  <b>Generierte Events:</b>
  <ul>
  <li>UNDEFINED FBDECT_$ahaName_${NR} FBDECT $id"
    </li>
  </ul>

  <br>
  Da manchmal die FRITZ!Box die interne Nummer der FBDECT Ger&auml;te
  neu vergibt, werden beim Verbindungsaufbau zum AHA Server die gespeicherten
  Namen (FBNAME) mit dem aktuellen Wert verglichen. Damit das funktioniert,
  m&uuml;ssen alle FBDECT Ger&auml;te auf dem FRITZ!Box einen eindeutigen Namen
  bekommen, und in FHEM muss f&uuml;r alle Ger&auml;te "get FBDECTDEVICE
  devInfo" ausgef&uuml;hrt werden, um FBNAME als Reading zu speichern.<br>

</ul>
=end html_DE

=cut
