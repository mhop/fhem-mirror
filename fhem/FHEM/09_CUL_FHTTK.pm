#
# 09_CUL_FHTTK.pm
#
# A module for FHEM to handle ELV's FHT80 TF-type sensors
# written by Kai 'wusel' Siering, 2009-11-06 with help
# from previously written FHEM code as well as members
# of fhem-users at googlegroups.com! Thanks, guys!
#
# e-mail: wusel+source at uu punkt org
#
# This module reads, despite setting an IODev explicitely,
# from any (CUL-) source and drops any identical message
# arriving within 5 seconds. It does handle the automatic
# retransmission of FHT80 TF as well as concurrent recep-
# tion from multiple sources; in my system, it could happen
# that the CUL in the same room "overhears" a telegram from
# FHT80 TF (most likely due to other messages sent/received
# at the same time) but the one downstairs still picks it up.
# My implementation should be safe for the device in question,
# if you see problems, the "only on this IODev"-code is still
# in place but commented out.
#
#
# Note: The sensor in question is named "FHT80 TF",
# in it's (formerly current, now old) design it looks
# similar to "FS20 TFK" but operates differently.
#
# FHT80 TF is designed to serve as a sensor to FHT80 B,
# only the B receives TF's transmissions (after made
# known to each FHT80 B) normally. The B then, if in-
# structed that way, turns down the heating while any
# of the TFs known to it signal "Window open". The TF
# transmits about every 255 seconds a telegram stating
# whether or nor the (reed-) contact is open (which
# means Window or Door, relevant for heating, open)
# and whether the battery is still full enough.
#
# The FS20 TFK on the other hand just directly addresses
# another FS20 device on opening/closing of it's (reed-)
# contact.
#
# Finally, the HMS100 TFK is designed to notify a HMS-
# central about opened/closed contacts immediately,
# but you can't directly address FS20 devices ...
#
# So, to notify e. g. FHEM instantly about opening
# or closure of doors/windows, your best buy might be
# an HMS100 TFK (as of this writing EUR 29,95 @ ELV).
# You could use an FS20 TFK as well (EUR 34,95 @ ELV),
# that way you could directly have FS20 switches act
# on opened/closed doors or windows in parallel or
# even without FHEM. The FHT80 TF (as eQ-3 FHT 80 TF
# currently for EUR 14,95 available @ ELV) only sends
# out a status telegram every ca. 2,5 minutes, so it's
# ok for seeing where one might have left a window
# open before leaving the house but by no means suit-
# able for any alerting uses (unless a delay of said
# amount of time doesn't matter, of course ;)).
#
# in charge of code: Matscher 
#
# $Id$
##############################################
package main;

use strict;
use warnings;

my %fhttfk_codes = (
    "02" => "Window:Closed",
    "82" => "Window:Closed",
    "01" => "Window:Open",
    "81" => "Window:Open",
    "0c" => "Sync:Syncing",
    "91" => "Window:Open, Low Batt",
    "11" => "Window:Open, Low Batt",
    "92" => "Window:Closed, Low Batt",
    "12" => "Window:Closed, Low Batt",
    "0f" => "Test:Success");

# -wusel, 2009-11-09: Map retransmission codes to major (8x) ones (0x)
#                     As I'm somewhat lazy, I just list all codes from
#                     %fhttfk_codes and map them to their major one.
#                     (FIXME: it would be sufficient to have %fhttfk_codes
#                     only list these major, "translated" ones.)
my %fhttfk_translatedcodes = (
    "01" => "01",
    "11" => "11",
    "12" => "12",
    "02" => "02",
    "0c" => "0c",
    "0f" => "0f",
    "81" => "01",
    "82" => "02",
    "91" => "11",
    "92" => "12");

# set
my %fhttfk_c2b;	# command->button hash
my %canset = (
  "01" => "Open",
  "02" => "Closed",
  "0c" => "Pair",
  "ff" => "ReSync");

# -wusel, 2009-11-06
#
# Parse messages from FHT80TK, normally interpreted only by FHT80
#
# Format as follows: "TCCCCCCXX" with CCCCCC being the id of the
# sensor in hex, XX being the current status: 02/82 is Window
# closes, 01/81 is Window open, 0C is synchronization, ?? is the
# battery low warning. FIXME!


#############################
sub
CUL_FHTTK_Initialize($)
{
  my ($hash) = @_;
  
  foreach my $k (keys %canset) {
  my $v = $canset{$k};
  $fhttfk_c2b{$v} = $k;
  }

  $hash->{Match}     = "^T[A-F0-9]{8}";
  $hash->{SetFn}     = "CUL_FHTTK_Set";
  $hash->{DefFn}     = "CUL_FHTTK_Define";
  $hash->{UndefFn}   = "CUL_FHTTK_Undef";
  $hash->{AttrFn}    = "CUL_FHTTK_Attr";  
  $hash->{ParseFn}   = "CUL_FHTTK_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:0,1 " .
                        "model:FHT80TF,FHT80TF-2,virtual ".
                        $readingFnAttributes;
  $hash->{AutoCreate}=
     { "CUL_FHTTK.*" => { GPLOT => "fht80tf:Window,", FILTER => "%NAME" } };
}

#############################

sub
CUL_FHTTK_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = "";
  
  return "\"set $a[0]\" needs at least two parameters" if(@a < 2);
  
  my $name = shift(@a);
  my $opt = shift @a;
  
  # suppress SET option
  if(defined($attr{$name}) && defined($attr{$name}{"model"})) {
    if($attr{$name}{"model"} eq "dummy") {
      Log3 $name, 5, "CUL_FHTTK ($name) Attribute was renamed from dummy to virtual! No functional lack.";
      $attr{$name}{"model"} = "virtual";
    }
    if($attr{$name}{"model"} ne "virtual") {
      return $ret;
    }
  }
  else {
    return $ret;
  }
    
  my $value = join("", @a);
  
  Log3 $name, 5, "CUL_FHTTK ($name) option: $opt and value: $value";
  
  if(!defined($fhttfk_c2b{$opt})) {
    my @cList = keys %fhttfk_c2b;
    return "Unknown argument $opt ($value), choose one of " . join(" ", @cList);
  }
  
  if ($opt eq "Open" ) {
    Log3 $name, 3, "CUL_FHTTK ($name) changed window state to open.";
    IOWrite($hash, "", sprintf("T%s01", $hash->{CODE})); # 0x01 - open or 0x81

  } elsif ($opt eq "Closed" ) {
    Log3 $name, 3, "CUL_FHTTK ($name) changed window state to closed.";
    
    IOWrite($hash, "", sprintf("T%s02", $hash->{CODE})); # 0x02 - closed or 0x82

  } elsif($opt eq "Pair" ) {
    Log3 $name, 3, "CUL_FHTTK ($name) pairing with FHT80b.";

    IOWrite($hash, "", sprintf("T%s0c", $hash->{CODE})); # 0x0c - sync
    # window state switch to closed through cul FW implementation
    $opt = "Closed";

  } elsif($opt eq "ReSync" ) {
    Log3 $name, 3, "CUL_FHTTK ($name) resyncing with FHT80b.";

    CUL_FHTTK_ReSync($hash);
    
    # return, because readingsupdate is perfomred by sub function
    return $ret;

  } else {
    return "Unknown argument $a[1], choose one of Pair ReSync Open Closed"
  }
  
  # update new state 
  readingsSingleUpdate($hash, "state", $opt, 1);
  readingsSingleUpdate($hash, "Window", $opt, 1);
   
  return $ret;
}

#############################
sub
CUL_FHTTK_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u= "wrong syntax: define <name> CUL_FHTTK <sensor>";
  return $u if((int(@a)< 3) || (int(@a)>3));

  my $name     = $hash->{NAME};
  my $sensor   = lc($a[2]);
  if($sensor !~ /^[0-9a-f]{6}$/) {
    return "wrong sensor specification $sensor, need a 6 digit hex number!";
  }
  
  $hash->{CODE} = $sensor;
  $modules{CUL_FHTTK}{defptr}{$sensor} = $hash;
  
  AssignIoPort($hash);
  return undef;
}


#############################
sub
CUL_FHTTK_Undef($$)
{
  my ($hash, $name) = @_;

  RemoveInternalTimer($hash);
 
  delete($modules{CUL_FHTTK}{defptr}{$hash->{CODE}}) if($hash && $hash->{CODE});

  return undef;
}

#############################
sub CUL_FHTTK_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  if( $attrName eq "model" && $attrVal eq "dummy") {
    $attr{$name}{$attrName} = "virtual";
    return "$name - Renamed attrubte model from dummy to virtual! No functional lack!";
  }
  return undef;
}

#############################
sub
CUL_FHTTK_Parse($$)
{
  my ($hash, $msg) = @_;

  my $sensor= lc(substr($msg, 1, 6));
  my $def   = $modules{CUL_FHTTK}{defptr}{$sensor};
  if(!$def) {
    Log3 $hash, 1, "FHTTK Unknown device $sensor, please define it";
    return "UNDEFINED CUL_FHTTK_$sensor CUL_FHTTK $sensor";
  }

  my $name  = $def->{NAME};
  my $state = lc(substr($msg, 7, 2));

  Log3 $hash, 4, "CUL_FHTTK $sensor RAW message: $msg";
  
  return "" if(IsIgnored($name));

  if(!defined($fhttfk_translatedcodes{$state})) {
      Log3 $name, 1, sprintf("FHTTK $def Unknown state $state");
      $defs{$name}{READINGS}{"Unknown"}{VAL} = $state;
      $defs{$name}{READINGS}{"Unknown"}{TIME} = TimeNow();
      return "";
  }

  $state=$fhttfk_translatedcodes{$state};
  # PREVIOUS
  # FIXME: Message regarded as similar if last char is identical;
  # sure that's always the differentiator? -wusel, 2009-11-09
  if(defined($defs{$name}{PREV}{TIMESTAMP})) {
      if($defs{$name}{PREV}{TIMESTAMP} > time()-5) {
         if(defined($defs{$name}{PREV}{STATE})) {
             if($defs{$name}{PREV}{STATE} eq $state) {
                 Log3 $name, 4, sprintf("FHTTK skipping state (%s) as last similar telegram was received less than 5 (%s) secs ago", $defs{$name}{PREV}{STATE}, time()-$defs{$name}{PREV}{TIMESTAMP});
                 return "";
             }
         }
      }
  }
  
  if (! defined($defs{$name}{READINGS}{"Previous"})) {
    $defs{$name}{READINGS}{"Previous"}{VAL} = "";
    $defs{$name}{READINGS}{"Previous"}{TIME} = "";
  }
  
  if (defined($defs{$name}{PREV}{STATE}) && $defs{$name}{PREV}{STATE} ne $state) {
    my $prevState = $defs{$name}{PREV}{STATE};
    my ($windowReading,$windowState) = split(/:/, $fhttfk_codes{$prevState});
    $defs{$name}{READINGS}{"Previous"}{VAL} = $windowState if defined($windowState) && $windowState ne "";
    $defs{$name}{READINGS}{"Previous"}{TIME} = TimeNow();
  }
 
  $def->{PREVTIMESTAMP} = defined($defs{$name}{PREV}{TIMESTAMP})?$defs{$name}{PREV}{TIMESTAMP}:time();
  $def->{PREVSTATE} = defined($def->{STATE})?$def->{STATE}:"Unknown";
  $defs{$name}{PREV}{STATE}=$state;
  
  #
  # from here readings are effectively updated
  #
  readingsBeginUpdate($def);
  
  #READINGS
  my ($reading,$val) = split(/:/, $fhttfk_codes{$state});
  readingsBulkUpdate($def, $reading, $val);

  $defs{$name}{PREV}{TIMESTAMP} = time();
  # -wusel, 2009-11-09: According to http://fhz4linux.info/tiki-index.php?page=FHT+protocol,
  #                     FHT80TF usually transmitts between 60 and 240 seconds. (255-256 sec in
  #                     my experience ...) If we got no fresh data for over 5 minutes (300 sec),
  #                     flag this.
  if($defs{$name}{PREV}{TIMESTAMP}+720 < time()) {
      readingsBulkUpdate($def, "Reliability", "dead");
  } elsif($defs{$name}{PREV}{TIMESTAMP}+600 < time()) {
      readingsBulkUpdate($def, "Reliability", "low");
  } elsif($defs{$name}{PREV}{TIMESTAMP}+300 < time()) {
      readingsBulkUpdate($def, "Reliability", "medium");
  } else {
      readingsBulkUpdate($def, "Reliability", "ok");
  }
  
  # set battery state - Forum #87575
  my $batteryReading = "batteryState";
  my $batteryState = "ok";
  
  if($state eq "11" || $state eq "12") {
    $batteryState = "low";
  }
  
  if(exists($defs{$name}{READINGS}{"Battery"})) {
    if(defined($featurelevel) && $featurelevel <= 5.8) {
        readingsBulkUpdate($def, "Battery", $batteryState);
    } else {
        # delete reading
        readingsDelete($def, "Battery");
    }
  }
  
  readingsBulkUpdate($def, $batteryReading, $batteryState);
  
  #CHANGED
  readingsBulkUpdate($def, "state", $val);

  $def->{OPEN} = lc($val) eq "open" ? 1 : 0;
  Log3 $name, 4, "FHTTK Device $name ($reading: $val)";

  #
  # now we are done with updating readings
  #
  readingsEndUpdate($def, 1);
  
  return $def->{NAME};
}

#############################
sub
CUL_FHTTK_ReSync($)
{
  my ($hash) = @_;
  
  RemoveInternalTimer($hash);
  
  Log3 undef, 3, "CUL_FHTTK_ReSync() - ReSync for $hash->{NAME} started!";
  
  # set resync
  IOWrite($hash, "", sprintf("T%sff", $hash->{CODE})); # 0xff - ReSync
  
  # update new state 
  readingsSingleUpdate($hash, "state", "ReSync", 1);
  readingsSingleUpdate($hash, "Window", "ReSync", 1);
  
  # finish timer
  InternalTimer( gettimeofday() + 64, "CUL_FHTTK_ReSyncDone", $hash, 0 );
}

#############################
sub
CUL_FHTTK_ReSyncDone($)
{
  my ($hash) = @_;
  
  RemoveInternalTimer($hash);
  
  # update new state 
  readingsSingleUpdate($hash, "state", "Closed", 1);
  readingsSingleUpdate($hash, "Window", "Closed", 1);
  
  Log3 undef, 3, "CUL_FHTTK_ReSyncDone() - ReSync for $hash->{NAME} done!";
}

#############################
sub
CUL_FHTTK_ReSyncAll()
{
  my $timeOffset = 0;
  
  foreach my $culFhtTk ( sort keys %{$modules{CUL_FHTTK}{defptr}} ) {
    my $hash = $modules{CUL_FHTTK}{defptr}{$culFhtTk};
    my $name = $hash->{NAME};

    Log3 undef, 4, "CUL_FHTTK_ReSyncAll - Possible device ($hash->{NAME}) found.";
    
    # check for model virtual
    if(AttrVal($name, "model", "") eq "virtual") {
      my $timerRaised = gettimeofday() + $timeOffset;
      InternalTimer( $timerRaised, "CUL_FHTTK_ReSync", $hash, 0 );
      Log3 undef, 3, "CUL_FHTTK_ReSyncAll() - ReSync for $hash->{NAME} starts at ".localtime($timerRaised)."!";

      $timeOffset += 3600; # one hour later, the next one, because of LOVF
    }
  }
  Log3 undef,  3, "CUL_FHTTK_ReSyncAll done! Devices will be synchronized in steps!";
}

#############################

1;

=pod
=item summary    support for the window sensor fht80tf and fht80tf-2
=item summary_DE Einbindung des fht80tf und fht80tf-2 Fensterkontaktes
=begin html

<a name="CUL_FHTTK"></a>
<h3>CUL_FHTTK</h3>
<ul>
  This module handles messages from the FHT80 TF "Fenster-T&uuml;r-Kontakt" (Window-Door-Contact)
  which are normally only acted upon by the <a href="#FHT">FHT80B</a>. With this module,
  FHT80 TFs are in a limited way (see <a href="http://fhz4linux.info/tiki-index.php?page=FHT+protocol">Wiki</a>
  for detailed explanation of TF's mode of operation) usable similar to HMS100 TFK. The name
  of the module was chosen as a) only CUL will spill out the datagrams and b) "TF" designates
  usually temperature+humidity sensors (no clue, why ELV didn't label this one "TFK" like with
  FS20 and HMS).<br><br>
  As said before, FHEM can receive FHT80 TF radio (868.35 MHz) messages only through an
  <a href="#CUL">CUL</a> device, so this must be defined first.
  <br><br>
  With the latest build on <a href="http://sourceforge.net/p/culfw/code/HEAD/tree/trunk/culfw/Devices/">SVN</a> 
  or next official version 1.62 or higher, it is possible to send out FHT80 TF data with a CUL or simular 
  devices. So it can be simulate up to four window sensor with one device 
  (see <a href="http://www.fhemwiki.de/wiki/CUL_FHTTK">FHEM Wiki</a>). To setup a window sensor, you have to
  add and/or change the attribute "model" to virtual. The 6 digit hex number must not equal to FHTID.<br><br>

  <a name="CUL_FHTTKdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_FHTTK &lt;devicecode&gt;</code>
    <br><br>

    <code>&lt;devicecode&gt;</code> is a six digit hex number, given to the FHT80 TF during
    production, i. e. it is not changeable. (Yes, it keeps this code after changing batteries
    as well.)<br>

    Examples:
    <ul>
      <code>define TK_TEST CUL_FHTTK 965AB0</code>
    </ul>
  </ul>
  <br>

  <a name="CUL_FHTTKset"></a>
  <b>Set</b>
    <ul> Only available, if model is set to virtual.<br><br>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul>
      <li><code>Closed</code><br>set window state to Closed</li><br>
      <li><code>Open</code><br>set window state to Open</li><br>
      <li><code>Pair</code><br>start pairing with FHT80B (activate FHT80B sync mode before) - state after pairing is Closed</li><br>
      <li><code>ReSync</code><br>resync virtual sensor with FHT80b after a reset of CUL device. In other words, perform a virtual
                 battery exchange to synchronize the sensor with FHT80b device again. (at the moment, only 
                 available with prototype cul fw - see forum 55774)</li><br>
    </ul>
    </ul>
    <br>

    <u>Special to the "ReSync" of existing FHT80TFs after a CUL firmware reset:</u><br>
    After a reset or restart of a CUL device, the connection between the FHT80B and the virtual FHT80TFs is interrupted. This is equivalent to a battery change. 
    The contacts are still registered at the FHT80B. No new pairing is required. If multiple virtual contacts are used, it is recommended to synchronize them at large intervals!<br>
    Calling the <b>CUL_FHTTK_ReSyncAll()</b> function synchronizes all virtual window contacts successively with the FHT80B. 
    The time interval between the individual sensors is <u>1 hour</u>. This is determined by the 1% rule, since per contact 480 credits are consumed within 64 seconds!<br><br>
    
  <b>Get</b>
   <ul> No get implemented yet ...
   </ul><br>

  <a name="CUL_FHTTKattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#verbose">verbose</a></li><br>
    <li><a href="#model">model</a><br>Possible values are: FHT80TF, FHT80TF-2, virtual (value, which allow to simulate a window sensor)</li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#IODev">IODev</a></li><br>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#eventMap">eventMap</a></li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html
=begin html_DE

<a name="CUL_FHTTK"></a>
<h3>CUL_FHTTK</h3>
<ul>
  Dieses Modul hantiert die empfangen Daten von FHT80 TF "Fenster-T&uuml;r-Kontakt" Sensoren, welche 
  normalerweise nur mit den <a href="#FHT">FHT80B</a> Geräten kommunizieren. Mit diesen Modul k&ouml;nnen 
  FHT80 TFs in eingeschr&auml;nkter Weise &auml;hnlich wie HMS TFK Sensoren benutzt werden (weitere 
  Informationen sind unter <a href="http://fhz4linux.info/tiki-index.php?page=FHT+protocol">Wiki</a> zu lesen).
  Der name des FHEM Moduls wurde so gewählt, weil a) nur der CUL die Daten empfangen kann und b) "TF" normalerweise
  Temperatur- und Feuchtigkeitssensoren suggeriert. (Keine Ahnung, warum ELV diesen Sensor nicht TFK genannt hat, 
  wie die Sensoren von FS20 und HMS).
  <br><br>
  <a href="#CUL">CUL</a> device muss vorhr definiert sein.
  <br><br>
  Mit dem letzten Build auf <a href="http://sourceforge.net/p/culfw/code/HEAD/tree/trunk/culfw/Devices/">SVN</a> 
  oder mit der n&auml;chsten offiziellen Version 1.62 oder h&ouml;her, ist es m&ouml;glich, FHT80 TF Daten zu senden. 
  M&ouml;glich mit einem CUL oder &auml;hnlichen Ger&auml;ten. So k&ouml;nnen bis zu vier Fenstersensoren mit einem Ger&auml;t
  simuliert werden (siehe <a href="http://www.fhemwiki.de/wiki/CUL_FHTTK">FHEM Wiki</a>). Es muss lediglich das Attribut model mit dem 
  Wert "virtual" hinzugef&uuml;gt oder ge&auml;ndert werden. Wichtig: Der Devicecode sollte nicht der FHTID entsprechen.<br><br>

  <a name="CUL_FHTTKdefine"></a>
  <b>D</b>
  <ul>
    <code>define &lt;name&gt; CUL_FHTTK &lt;devicecode&gt;</code>
    <br><br>

    <code>&lt;devicecode&gt;</code> Ist eine sechstellige Hexadezimalzahl, welche zum Zeitpunkt der Produktion 
  des FHT80 TF gegeben wurde. Somit ist diese auch nicht mehr &auml;nderbar und bleibt auch nach einem Batteriewechsel 
  erhalten.<br>

    Examples:
    <ul>
      <code>define TK_TEST CUL_FHTTK 965AB0</code>
    </ul>
  </ul>
  <br>

  <a name="CUL_FHTTKset"></a>
  <b>Set</b>
    <ul> Nur vorhanden, wenn das Attribut model mit virtual definiert wurde.<br><br>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    wobei <code>value</code> folgendes sein kann:<br>
    <ul>
      <li><code>Closed</code><br>setzt den Fensterstatus zu Closed</li><br>
      <li><code>Open</code><br>setzt den Fensterstatus zu Open</li><br>
      <li><code>Pair</code><br>startet das Anlernen an das FHT80B (FHT80B muss sich im Sync mode befinden) - danach wird der state auf "Closed" gesetzt</li><br>
      <li><code>ReSync</code><br>neu synchronisieren des virtuellen Sensor mit dem FHT80b Module. Damit wird ein virtueller Batteriewechsel simuliert und der angelernte
                 Sensor wieder aufsynchronisiert. (aktuell nur mit Prototyp CUL FW verf&uuml;gbar Forum 55774)</li><br>
    </ul>
    </ul>
    <br>
    
    <u>Spezielles zum "ReSync" von vorhanden FHT80TFs nach einem CUL Firmware Reset:</u><br>
    Nach einem Reset bzw. Neustart eines CUL Devices ist die Verbindung zwischen dem FHT80B und den virtuellen FHT80TFs unterbrochen. Dies kommt einem Batteriewechsel gleich. 
    Die Kontakte sind weiterhin am FHT80B angelernt. Ein neues Pairen entf&auml;llt. Wenn mehrere vitruelle Kontakte verwendet werden, empfiehlt es sich diese in großen Abst&auml;nden 
    wieder zu synchronisieren!<br>
    Mithilfe des Aufrufes der Funktion <b>CUL_FHTTK_ReSyncAll()</b> werden alle virtuellen Fensterkontakte <u>nacheinander</u> mit den FHT80B wieder synchronisiert. 
    Der Abstand betr&auml;gt zwischen den einzelnen Sensoren <u>1 Stunde</u>. Dies wird durch die 1% Regeln bestimmt, da pro Kontakt 480 credits innerhalb von 64 Sekunden verbraucht werden!<br><br>
    
  <b>Get</b>
  <ul> N/A </ul>
  <br>

  <a name="CUL_FHTTKattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#verbose">verbose</a></li><br>
    <li><a href="#model">model</a><br>M&ouml;gliche Werte sind: FHT80TF, FHT80TF-2, virtual (zum simulieren eines Fensterkontaktes)</li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#IODev">IODev</a></li><br>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#eventMap">eventMap</a></li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html_DE
=cut
