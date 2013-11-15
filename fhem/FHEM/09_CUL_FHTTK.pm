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

  $hash->{Match}     = "^T[A-F0-9]{8}",
  $hash->{DefFn}     = "CUL_FHTTK_Define";
  $hash->{UndefFn}   = "CUL_FHTTK_Undef";
  $hash->{ParseFn}   = "CUL_FHTTK_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:0,1 " .
                        "model:FHT80TF loglevel:0,1,2,3,4,5,6";
  $hash->{AutoCreate}=
     { "CUL_FHTTK.*" => { GPLOT => "fht80tf:Window,", FILTER => "%NAME" } };
}


#############################
sub
CUL_FHTTK_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u= "wrong syntax: define <name> CUL_FHTTK <sensor>";
  return $u if((int(@a)< 3) || (int(@a)>3));

  my $name     = $a[0];
  my $sensor   = lc($a[2]);
  if($sensor !~ /^[0-9a-f]{6}$/) {
       return "wrong sensor specification $sensor, need a 6 digit hex number";
  }

#  $hash->{SENSOR}= "$sensor";
  $hash->{CODE} = $sensor;
  $modules{CUL_FHTTK}{defptr}{$sensor} = $hash;
#  $defs{$hash}{READINGS}{PREV}{STATE}="00";
#  $defs{$hash}{READINGS}{PREV}{TIMESTAMP} = localtime();
  AssignIoPort($hash);
  return undef;
}


#############################
sub
CUL_FHTTK_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{CUL_FHTTK}{defptr}{$hash->{CODE}}) if($hash && $hash->{CODE});
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
    Log 3, "FHTTK Unknown device $sensor, please define it";
    return "UNDEFINED CUL_FHTTK_$sensor CUL_FHTTK $sensor";
  }

  my $self  = $def->{NAME};
  my $state = lc(substr($msg, 7, 2));

  return "" if(IsIgnored($self));

  if(!defined($fhttfk_translatedcodes{$state})) {
      Log 3, sprintf("FHTTK $def Unknown state $state");
      $defs{$self}{READINGS}{"Unknown"}{VAL} = $state;
      $defs{$self}{READINGS}{"Unknown"}{TIME} = TimeNow();
      return "";
  }

  $state=$fhttfk_translatedcodes{$state};
  # PREVIOUS
  # FIXME: Message regarded as similar if last char is identical;
  # sure that's always the differentiator? -wusel, 2009-11-09
  if(defined($defs{$self}{PREV}{TIMESTAMP})) {
      if($defs{$self}{PREV}{TIMESTAMP} > time()-5) {
         if(defined($defs{$self}{PREV}{STATE})) {
             if($defs{$self}{PREV}{STATE} eq $state) {
                 Log GetLogLevel($def->{NAME},4), sprintf("FHTTK skipping state $state as last similar telegram was received less than 5 (%d) secs ago", $defs{$self}{PREV}{STATE}, time()-$defs{$self}{PREV}{TIMESTAMP});
                 return "";
             }
         }
      }
  }
  
  if (! defined($defs{$self}{READINGS}{"Previous"})) {
    $defs{$self}{READINGS}{"Previous"}{VAL} = "";
    $defs{$self}{READINGS}{"Previous"}{TIME} = "";
  }
  
  if (defined($defs{$self}{PREV}{STATE}) && $defs{$self}{PREV}{STATE} ne $state) {
    my $prevState = $defs{$self}{PREV}{STATE};
    my ($windowReading,$windowState) = split(/:/, $fhttfk_codes{$prevState});
    $defs{$self}{READINGS}{"Previous"}{VAL} = $windowState if defined($windowState) && $windowState ne "";
    $defs{$self}{READINGS}{"Previous"}{TIME} = TimeNow();
  }
 
  $def->{PREVTIMESTAMP} = defined($defs{$self}{PREV}{TIMESTAMP})?$defs{$self}{PREV}{TIMESTAMP}:time();
  $def->{PREVSTATE} = defined($def->{STATE})?$def->{STATE}:"Unknown";
  $defs{$self}{PREV}{STATE}=$state;
  

  
  #READINGS
  my ($reading,$val) = split(/:/, $fhttfk_codes{$state});
  $defs{$self}{READINGS}{$reading}{VAL} = $val;
  $defs{$self}{READINGS}{$reading}{TIME} = TimeNow();
  $defs{$self}{PREV}{TIMESTAMP} = time();
  # -wusel, 2009-11-09: According to http://fhz4linux.info/tiki-index.php?page=FHT+protocol,
  #                     FHT80TF usually transmitts between 60 and 240 seconds. (255-256 sec in
  #                     my experience ...) If we got no fresh data for over 5 minutes (300 sec),
  #                     flag this.
  if($defs{$self}{PREV}{TIMESTAMP}+720 < time()) {
      $defs{$self}{READINGS}{"Reliability"}{VAL} = "dead";
      $defs{$self}{READINGS}{"Reliability"}{TIME} = TimeNow();
  } elsif($defs{$self}{PREV}{TIMESTAMP}+600 < time()) {
      $defs{$self}{READINGS}{"Reliability"}{VAL} = "low";
      $defs{$self}{READINGS}{"Reliability"}{TIME} = TimeNow();
  } elsif($defs{$self}{PREV}{TIMESTAMP}+300 < time()) {
      $defs{$self}{READINGS}{"Reliability"}{VAL} = "medium";
      $defs{$self}{READINGS}{"Reliability"}{TIME} = TimeNow();
  } else {
      $defs{$self}{READINGS}{"Reliability"}{VAL} = "ok";
      $defs{$self}{READINGS}{"Reliability"}{TIME} = TimeNow();
  }
  # Flag the battery warning separately
  if($state eq "11" || $state eq "12") {
      $defs{$self}{READINGS}{"Battery"}{VAL} = "Low";
      $defs{$self}{READINGS}{"Battery"}{TIME} = TimeNow();
  } else {
      $defs{$self}{READINGS}{"Battery"}{VAL} = "ok";
      $defs{$self}{READINGS}{"Battery"}{TIME} = TimeNow();
  }
  #CHANGED
  $defs{$self}{CHANGED}[0] = $reading . ": " . $val;
  $def->{STATE} = $val;
  $def->{OPEN} = lc($val) eq "open" ? 1 : 0;
  Log GetLogLevel($def->{NAME},4), "FHTTK Device $self ($reading: $val)";

  return $def->{NAME};
}

#############################

1;

=pod
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
  <a href="#CUL">CUL</a> device, so this must be defined first.<br><br>

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
  <b>Set </b>
    <ul> Nothing to set here yet ... </ul>
  <br>

  <b>Get</b>
   <ul> No get implemented yet ...
   </ul><br>

  <a name="CUL_FHTTKattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
    <li><a href="#model">model</a> (FHT80TF)</li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#IODev">IODev</a></li><br>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#eventMap">eventMap</a></li><br>
  </ul>
  <br>

</ul>

=end html
=cut
