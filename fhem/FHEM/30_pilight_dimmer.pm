##############################################
# $Id: 30_pilight_dimmer.pm 0.55 2015-07-27 Risiko $
#
# Usage
# 
# define <name> pilight_dimmer <protocol> <id> <unit> [protocol]
#
# Changelog
#
# V 0.10 2015-02-26 - initial beta version 
# V 0.50 2015-05-20 - NEW: handle screen messages (up,down)
# V 0.50 2015-05-20 - NEW: max dimlevel for gui and device
# V 0.51 2015-05-21 - CHG: modifications for dimers without dimlevel
# V 0.52 2015-05-25 - CHG: attributes dimlevel_on, dimlevel_off 
# V 0.53 2015-05-30 - FIX: set dimlevel 0
# V 0.54 2015-05-30 - FIX: StateFn
# V 0.55 2015-07-27 - NEW: SetExtensions on-for-timer
############################################## 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;
use Switch;  #libswitch-perl

use SetExtensions;

sub pilight_dimmer_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "pilight_dimmer_Define";
  $hash->{Match}    = "^PISWITCH|^PIDIMMER|^PISCREEN";
  $hash->{ParseFn}  = "pilight_dimmer_Parse";
  $hash->{SetFn}    = "pilight_dimmer_Set";
  $hash->{StateFn}  = "pilight_dimmer_State";
  $hash->{AttrList} = "dimlevel_max dimlevel_step dimlevel_max_device dimlevel_on dimlevel_off ".$readingFnAttributes;
}

#####################################
sub pilight_dimmer_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 5) {
    my $msg = "wrong syntax: define <name> pilight_dimmer <protocol> <id> <unit> [protocol]";
    Log3 undef, 2, $msg;
    return $msg;
  }

  my $me = $a[0];
  my $protocol = $a[2];
  my $id = $a[3];
  my $unit = $a[4];

  $hash->{STATE} = "defined";
  
  $hash->{PROTOCOL} = lc($protocol);  
  $hash->{ID} = $id;  
  $hash->{UNIT} = $unit;
  $hash->{PROTOCOL2} = lc($a[5]) if (@a == 6);
  
  $hash->{helper}{OWN_DIM} = 1;
  $hash->{helper}{OWN_DIM} = 0 if ($hash->{PROTOCOL} =~ /screen/);
  
  $hash->{helper}{ISSCREEN} = 1 if ($hash->{PROTOCOL} =~ /screen/ or (defined($hash->{PROTOCOL2}) and $hash->{PROTOCOL2}) =~ /screen/);
  
  #$attr{$me}{verbose} = 5;
  
  $modules{pilight_dimmer}{defptr}{lc($id)}{$me} = $hash;
  AssignIoPort($hash);
  return undef;
}

###########################################
sub pilight_dimmer_Parse($$)
{
  my ($mhash, $rmsg, $rawdata) = @_;
  my $backend = $mhash->{NAME};

  Log3 $backend, 4, "pilight_dimmer_Parse: RCV -> $rmsg";
  
  my ($dev,$protocol,$id,$unit,$state,$dimlevel) = split(",",$rmsg);
  return () if($dev !~ m/PISWITCH|PIDIMMER|PISCREEN/);
  
  my $chash;
  foreach my $n (keys %{ $modules{pilight_dimmer}{defptr}{lc($id)} }) { 
    my $lh = $modules{pilight_dimmer}{defptr}{$id}{$n};
    next if ( !defined($lh->{UNIT}) );
    if ($lh->{ID} eq $id && $lh->{UNIT} eq $unit) {
      $chash = $lh;
      last;
    }
  }
  
  return () if (!defined($chash->{NAME}));
  
  my $dimlevel_max_dev = AttrVal($chash->{NAME}, "dimlevel_max_device",15);
  my $dimlevel_max     = AttrVal($chash->{NAME}, "dimlevel_max",$dimlevel_max_dev);
  my $dimlevel_step    = AttrVal($chash->{NAME}, "dimlevel_step",1);
  my $dimlevel_old     = ReadingsVal($chash->{NAME},"dimlevel",0);
  my $state_old        = ReadingsVal($chash->{NAME},"state",0);
  
  Log3 $chash->{NAME}, 4, "pilight_dimmer_Parse: RCV -> $rmsg";
  
  if ($state eq "up") {
    $dimlevel = $dimlevel_old + $dimlevel_step;
    $dimlevel = $dimlevel_max if ($dimlevel > $dimlevel_max);
    $state="on";
  }
  
  if ($state eq "down") {    
    $dimlevel = $dimlevel_old - $dimlevel_step;
    $state="on";
    if ($dimlevel <= 0) {
      $state="off";
      $dimlevel= AttrVal($chash->{NAME}, "dimlevel_off",0);
    }
  }
  
  readingsBeginUpdate($chash);
  readingsBulkUpdate($chash,"state",$state) if ("$state_old" ne "$state");
  if (defined($dimlevel)) {
    $chash->{helper}{DEV_DIMLEVEL} = $dimlevel;
    Log3 $chash->{NAME}, 5, "pilight_dimmer_Parse: $dimlevel $dimlevel_max_dev $dimlevel_max";
    $dimlevel = $dimlevel / $dimlevel_max_dev * $dimlevel_max;
    Log3 $chash->{NAME}, 5, "pilight_dimmer_Parse: $dimlevel_old $dimlevel";
    $dimlevel = int($dimlevel+0.5);
    Log3 $chash->{NAME}, 5, "pilight_dimmer_Parse: $dimlevel_old round $dimlevel";
    readingsBulkUpdate($chash,"dimlevel",$dimlevel) if ($dimlevel_old != $dimlevel);
  }
  readingsEndUpdate($chash, 1); 
  
  return $chash->{NAME};
}

#####################################
sub pilight_dimmer_Write($$$)
{
  my ($hash, $set, $dimlevel) = @_;
  my $me = $hash->{NAME};
  
  my $proto = $hash->{PROTOCOL};
  
  if ($set =~ /up|down/ and $proto !~ /screen/) {
    $proto = $hash->{PROTOCOL2} if (defined($hash->{PROTOCOL2}));
  }
  if ($set =~ /on|off/ and $proto =~ /screen/) {
    $proto = $hash->{PROTOCOL2} if (defined($hash->{PROTOCOL2}));
  }
  
  my $msg = "$me,$set";
  $msg = $msg.",".$dimlevel if (defined($dimlevel));
  
  my $help = $hash->{PROTOCOL};
  $hash->{PROTOCOL} = $proto;
  
  Log3 $me, 4, "$me(Set): [$proto] $msg";
  
  IOWrite($hash, $msg);
  
  $hash->{PROTOCOL} = $help;  
  return undef;
}

#####################################
sub pilight_dimmer_ConvDimToDev($$)
{
    my ($me,$dimlevel_gui) = @_;
    
    my $dimlevel_max_dev =  AttrVal($me, "dimlevel_max_device",15);
    my $dimlevel_max =  AttrVal($me, "dimlevel_max",$dimlevel_max_dev);
  
    my $dimlevel = $dimlevel_gui / $dimlevel_max * $dimlevel_max_dev;
    $dimlevel = int($dimlevel + 0.5);
    return $dimlevel;
}

#####################################
sub pilight_dimmer_Set($$)
{  
  my ($hash, $me, $cmd, @a) = @_;
  
  return "no set value specified" unless defined($cmd);
  
  my $dimlevel_max_dev =  AttrVal($me, "dimlevel_max_device",15);
  my $dimlevel_step =  AttrVal($me, "dimlevel_step",1);  
  my $dimlevel_max =  AttrVal($me, "dimlevel_max",$dimlevel_max_dev);
  
  my %sets = ("on:noArg"=>0, "off:noArg"=>0);
  $sets{"dimlevel:slider,0,$dimlevel_step,$dimlevel_max"} = 1;
  
  $sets{"up:noArg"} = 0 if ($hash->{helper}{ISSCREEN});
  $sets{"down:noArg"} = 0 if ($hash->{helper}{ISSCREEN});
  
  my @match = grep( $_ =~ /^$cmd($|:)/, keys %sets );
  return SetExtensions($hash, join(" ", keys %sets), $me, $cmd, @a) unless @match == 1;
  return "$cmd expects $sets{$match[0]} parameters" unless (@a eq $sets{$match[0]});
  
  my $dimlevel = undef;
  my $currlevel = ReadingsVal($me,"dimlevel",0);
  
  if ($cmd =~ m/up|down/ and !$hash->{helper}{ISSCREEN}) {
    Log3 $me, 1, "$me(Set): up|down not supported";
    return undef;
  }
  
  if ($hash->{helper}{OWN_DIM} == 1) {
    switch($cmd) {
      case "dimlevel" {
        $dimlevel = pilight_dimmer_ConvDimToDev($me,$a[0]);
        $cmd = "on";
      }
      case "on"   { 
        my $dimlevel_on = AttrVal($me, "dimlevel_on",$currlevel);
        $dimlevel_on = $dimlevel_max if ($dimlevel_on eq "dimlevel_max");
        $dimlevel = pilight_dimmer_ConvDimToDev($me,$currlevel);
      }
    }
  } else { # device without dimlevel support
    switch($cmd) {
      case "dimlevel" {
        my $newlevel = $a[0];
        my $cnt = int(($newlevel - $currlevel) / $dimlevel_step);      
        
        return undef if ($cnt==0);
        $cmd = "up"  if ($cnt>0);
        $cmd = "down" if ($cnt<0);
        
        $cnt = abs($cnt) - 1; # correction for loop -1 
        
        if ($newlevel == 0) {
          $cmd = "off";
          $cnt=0; #break for loop
          my $dimlevel_off = AttrVal($me, "dimlevel_off",$newlevel);          
          readingsSingleUpdate($hash,"dimlevel",$dimlevel_off,1);
        }
        
        Log3 $me, 5, "$me(Set): cnt $cnt";
        
        for (my $i=0; $i < $cnt; $i++) {
           pilight_dimmer_Write($hash,$cmd,undef);
        }
      }
      case "on" { 
        my $dimlevel_on = AttrVal($me, "dimlevel_on",$currlevel);
        $dimlevel_on = $dimlevel_max if ($dimlevel_on eq "dimlevel_max");
        readingsSingleUpdate($hash,"dimlevel",$dimlevel_on,1);
        }
      case "off" { 
        my $dimlevel_off = AttrVal($me, "dimlevel_off",$currlevel);
        readingsSingleUpdate($hash,"dimlevel",$dimlevel_off,1);
        }
    }
  }
  
  if (defined($dimlevel)) {
    my $dimOld = $hash->{helper}{DEV_DIMLEVEL};
    if (defined($dimOld)) {
      return undef if ($dimOld == $dimlevel);
    }
  }
  
  delete $hash->{helper}{DEV_DIMLEVEL} if ($cmd eq "off");
  
  pilight_dimmer_Write($hash,$cmd,$dimlevel); 
  #keinen Trigger bei Set auslösen
  #Aktualisierung erfolgt in Parse
  my $skipTrigger = 1; 
  return undef,$skipTrigger;
}

#####################################
sub pilight_dimmer_State($$$$)
{
  my ($hash, $time, $name, $val) = @_;
  my $me = $hash->{NAME};
  
  #$hash->{STATE} wird nur ersetzt, wenn $hash->{STATE}  == ??? fhem.pl Z: 2469
  #machen wir es also selbst
  $hash->{STATE} = $val if ($name eq "state");
  return undef;
}

1;

=pod
=begin html

<a name="pilight_dimmer"></a>
<h3>pilight_dimmer</h3>
<ul>

  pilight_dimmer represents a dimmmer controled with\from pilight<br>
  You have to define the base device pilight_ctrl first.<br>
  Further information to pilight: <a href="http://www.pilight.org/">http://www.pilight.org/</a><br>
  Supported dimmers: <a href="http://wiki.pilight.org/doku.php/protocols#dimmers">http://wiki.pilight.org/doku.php/protocols#dimmers</a><br>
  <br>
  It is possible to add the screen feature to a dimmer. So you can change the dimlevel by set 'up' or 'down'.<br>
  If you push up or down on the remote control the dimlevel will be changed by dimlevel_step.<br>
  Further it is possible to define a simulated dimmer with a screen and switch protocol. See example three.<br>
  That means if you change the dimlevel a up or down command will be send n times to dim the device instead of send a dimlevel directly.<br>
  <br>
  <a name="pilight_dimmer_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; pilight_dimmer protocol id unit [protocol]</code>    
    <br>The second protocol is optional. With it you can add the pilight screen feature (up|down)

    Example:
    <ul>
      <code>define myctrl pilight_dimmer kaku_dimmer 13483668 0</code><br>
      <code>define myctrl pilight_dimmer kaku_dimmer 13483668 0 kaku_screen</code> - Dimmer with screen feature<br>
      <code>define myctrl pilight_dimmer quigg_screen 1 0 quigg_gt7000</code> - Simulated dimmer with screen feature<br>
    </ul>
  </ul>
  <br>
  <a name="pilight_dimmer_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <b>on</b>
    </li>
    <li>
      <b>off</b>
    </li>
    <li>
      <b>up</b> only if defined with screen protocol
    </li>
    <li>
      <b>down</b> only if defined with screen protocol
    </li>
    <li>
      <b>dimlevel</b>
    </li>
    <li>
      <a href="#setExtensions">set extensions</a> are supported<br>
    </li>
  </ul>
  <br>
  <a name="pilight_dimmer_readings"></a>
  <p><b>Readings</b></p>
  <ul>    
    <li>
      state<br>
      state of the dimmer on or off
    </li>
    <li>
      dimlevel<br>
      dimlevel of the dimmer 
    </li>
  </ul>
  <br>
  <a name="pilight_dimmer_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="dimlevel_max_device">dimlevel_max_device</a><br>
        Maximum of the dimlevel of the device - default 15<br>
        Have to be less or equal than dimlevel_max<br>
    </li>
    <li><a name="dimlevel_max">dimlevel_max</a><br>
        Maximum of the dimlevel in FHEM - default dimlevel_max_device<br>
    </li>
    <li><a name="dimlevel_step">dimlevel_step</a><br>
        Step of the dimlevel - default 1<br>
    </li>
    <li><a name="dimlevel_on">dimlevel_on</a><br>
        Change dimlevel to value if on set - default no changing<br>
        Could be a numeric value or dimlevel_max<br>
    </li>
     <li><a name="dimlevel_off">dimlevel_off</a><br>
         Change dimlevel to value if off set - default no changing<br>
    </li>
  </ul>
  <br>
</ul>

=end html

=cut
