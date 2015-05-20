##############################################
# $Id: 30_pilight_dimmer.pm 0.50 2015-05-20 Risiko $
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
############################################## 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;

sub pilight_dimmer_Parse($$);
sub pilight_dimmer_Define($$);
sub pilight_dimmer_Fingerprint($$);

sub pilight_dimmer_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "pilight_dimmer_Define";
  $hash->{Match}    = "^PISWITCH|^PIDIMMER|^PISCREEN";
  $hash->{ParseFn}  = "pilight_dimmer_Parse";
  $hash->{SetFn}    = "pilight_dimmer_Set";
  $hash->{AttrList} = "dimlevel_max dimlevel_step dimlevel_max_device ".$readingFnAttributes;
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
  
  $hash->{helper}{ISSCREEN} = 1 if ($hash->{PROTOCOL} =~ /screen/ or $hash->{PROTOCOL2} =~ /screen/);
  
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
  my $dimlevel = undef;

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
  
  my $max_default = 15;
  $max_default = 100 if ($chash->{helper}{OWN_DIM} != 1);
  
  my $dimlevel_max_dev = AttrVal($chash->{NAME}, "dimlevel_max_device",$max_default);
  my $dimlevel_max     = AttrVal($chash->{NAME}, "dimlevel_max",$dimlevel_max_dev);
  my $dimlevel_step    = AttrVal($chash->{NAME}, "dimlevel_step",1);
  my $dimlevel_old     = ReadingsVal($chash->{NAME},"dimlevel",0);
  
  Log3 $chash->{NAME}, 4, "pilight_dimmer_Parse: RCV -> $rmsg";
  
  readingsBeginUpdate($chash);
  
  if ($state eq "up") {
    $dimlevel = $dimlevel_old + $dimlevel_step;
    $dimlevel = $dimlevel_max if ($dimlevel > $dimlevel_max);
    $state="on";
  }
  
  if ($state eq "down") {    
    $dimlevel = $dimlevel_old - $dimlevel_step;
    $state="on";
    if ($dimlevel < 0) {
      $state="off";
      $dimlevel = 0;
    }
  }
  
  readingsBulkUpdate($chash,"state",$state);
  if (defined($dimlevel)) {
    $chash->{helper}{DEV_DIMLEVEL} = $dimlevel;
    $dimlevel = $dimlevel / $dimlevel_max_dev * $dimlevel_max;
    $dimlevel = int($dimlevel+0.5);
    readingsBulkUpdate($chash,"dimlevel",$dimlevel);
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
sub pilight_dimmer_Set($$)
{  
  my ($hash, @a) = @_;
  my $me = shift @a;

  return "no set value specified" if(int(@a) < 1);
  my $dimlevel_max_dev =  AttrVal($me, "dimlevel_max_device",15);
  my $dimlevel_step =  AttrVal($me, "dimlevel_step",1);  
  my $dimlevel_max =  AttrVal($me, "dimlevel_max",$dimlevel_max_dev);
  
  my $canSet = "on off";
  $canSet .= " up down" if ($hash->{helper}{ISSCREEN});
  
  return "Unknown argument ?, choose one of $canSet dimlevel:slider,0,$dimlevel_step,$dimlevel_max" if($a[0] eq "?");
  
  my $set = $a[0];
  my $dimlevel = undef;
  
  if ($a[0] eq "dimlevel") {
    if ($hash->{helper}{OWN_DIM} == 1) {
      $dimlevel = $a[1] / $dimlevel_max * $dimlevel_max_dev;
      $dimlevel = int($dimlevel + 0.5);
      $set = "on";
    } elsif ($hash->{helper}{ISSCREEN}){
      my $newlevel = $a[1];
      my $currlevel = ReadingsVal($me,"dimlevel",0);
      my $cnt = int(($newlevel - $currlevel) / $dimlevel_step);
      return undef if ($cnt==0);
      $set = "up"  if ($cnt>0);
      $set = "down" if ($cnt<0);
      for (my $i=0; $i < abs($cnt); $i++) {
         pilight_dimmer_Write($hash,$set,undef);
      }
      return undef;
    } else {
      Log3 $me, 1, "$me(Set): error setting dimlevel"; 
      return undef;
    }
  } elsif ( ($set eq "up" or $set eq "down") and !$hash->{helper}{ISSCREEN}) {
    Log3 $me, 1, "$me(Set): up|down not supported";
    return undef;
  } elsif ( $set eq "off" ) {
    delete $hash->{helper}{DEV_DIMLEVEL};
  }
  
  if (defined($dimlevel)) {
    my $dimOld = $hash->{helper}{DEV_DIMLEVEL};
    if (defined($dimOld)) {
      return undef if ($dimOld == $dimlevel);
    }
  }
  
  pilight_dimmer_Write($hash,$set,$dimlevel); 
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
    </li>
    <li><a name="dimlevel_max">dimlevel_max</a><br>
        Maximum of the dimlevel in FHEM - default dimlevel_max_device<br>
    </li>
    <li><a name="dimlevel_step">dimlevel_step</a><br>
        Step of the dimlevel - default 1<br>
    </li>
  </ul>
  <br>
</ul>

=end html

=cut
