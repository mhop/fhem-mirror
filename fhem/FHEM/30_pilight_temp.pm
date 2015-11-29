##############################################
# $Id: 30_pilight_temp.pm 0.17 2015-11-29 Risiko $
#
# Usage
# 
# define <name> pilight_temp <protocol> <id> 
#
# Changelog
#
# V 0.10 2015-03-29 - initial beta version 
# V 0.11 2015-03-29 - FIX:  $readingFnAttributes
# V 0.12 2015-05-16 - NEW:  reading battery
# V 0.12 2015-05-16 - NEW:  attribut corrTemp, a factor to modify temperatur 
# V 0.13 2015-05-17 - NEW:  attribut corrHumidity, a factor to modify humidity
# V 0.14 2015-05-30 - FIX:  StateFn 
# V 0.15 2015-08-30 - NEW:  support pressure, windavg, winddir, windgust
# V 0.16 2015-09-06 - FIX:  pressure, windavg, winddir, windgust from weather stations without temperature 
# V 0.17 2015-11-29 - NEW:  offsetTemp and offsetHumidity to correct temperature and humidity 
############################################## 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;
use Switch;  #libswitch-perl

sub pilight_temp_Parse($$);
sub pilight_temp_Define($$);

sub pilight_temp_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "pilight_temp_Define";
  $hash->{Match}    = "^PITEMP";
  $hash->{ParseFn}  = "pilight_temp_Parse";
  $hash->{StateFn}  = "pilight_temp_State";
  $hash->{AttrList} = "corrTemp corrHumidity offsetTemp offsetHumidity ".$readingFnAttributes;
}

#####################################
sub pilight_temp_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 4) {
    my $msg = "wrong syntax: define <name> pilight_temp <protocol> <id>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  my $me = $a[0];
  my $protocol = $a[2];
  my $id = $a[3];

  $hash->{STATE} = "defined";
  $hash->{PROTOCOL} = lc($protocol);  
  $hash->{ID} = $id;  

  #$attr{$me}{verbose} = 5;
  
  $modules{pilight_temp}{defptr}{lc($protocol)}{$me} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub pilight_temp_State($$$$)
{
  my ($hash, $time, $name, $val) = @_;
  my $me = $hash->{NAME};
  
  #$hash->{STATE} wird nur ersetzt, wenn $hash->{STATE}  == ??? fhem.pl Z: 2469
  #machen wir es also selbst
  $hash->{STATE} = $val if ($name eq "state");
  return undef;
}

###########################################
sub pilight_temp_Parse($$)
{
  my ($mhash, $rmsg, $rawdata) = @_;
  my $backend = $mhash->{NAME};

  Log3 $backend, 4, "pilight_temp_Parse: RCV -> $rmsg";
  
  my ($dev,$protocol,$id,@args) = split(",",$rmsg);
  return () if($dev ne "PITEMP");
  
  my $chash;
  foreach my $n (keys %{ $modules{pilight_temp}{defptr}{lc($protocol)} }) { 
    my $lh = $modules{pilight_temp}{defptr}{$protocol}{$n};
    next if ( !defined($lh->{ID}) );
    if ($lh->{ID} eq $id) {
      $chash = $lh;
      last;
    }
  }
  
  return () if (!defined($chash->{NAME}));
  
  my $corrTemp = AttrVal($chash->{NAME}, "corrTemp",1);  
  my $corrHumidity = AttrVal($chash->{NAME}, "corrHumidity",1);
  
  my $tempOffset = AttrVal($chash->{NAME}, "offsetTemp",0);  
  my $humidityOffset = AttrVal($chash->{NAME}, "offsetHumidity",0);
  
  readingsBeginUpdate($chash);
  
  foreach my $arg (@args){
    #temperature, humidity, battery    
    #pressure, windavg, winddir, windgust
    my($feature,$value) = split(":",$arg);
    switch($feature) {
      case m/temperature/ {
          $value = $value * $corrTemp + $tempOffset;
          readingsBulkUpdate($chash,"state",$value);
        }
      case m/humidity/    { $value = $value * $corrHumidity + $humidityOffset;}
    }
    readingsBulkUpdate($chash,$feature,$value);
  }
  readingsEndUpdate($chash, 1); 
  
  return $chash->{NAME};
}


1;

=pod
=begin html

<a name="pilight_temp"></a>
<h3>pilight_temp</h3>
<ul>

  pilight_temp represents a temperature and humidity sensor receiving data from pilight<br>
  You have to define the base device pilight_ctrl first.<br>
  Further information to pilight: <a href="http://www.pilight.org/">http://www.pilight.org/</a><br>
  Supported Sensors: <a href="http://wiki.pilight.org/doku.php/protocols#switches">http://wiki.pilight.org/doku.php/protocols#weather_stations</a><br>     
  <br>
  <a name="pilight_temp_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; pilight_temp protocol id</code>    
    <br><br>

    Example:
    <ul>
      <code>define myctrl pilight_temp alecto_wsd17 100</code><br>
    </ul>
  </ul>
  <br>
  <a name="pilight_temp_readings"></a>
  <p><b>Readings</b></p>
  <ul>    
    <li>
      state<br>
      present the current temperature
    </li>
    <li>
      temperature<br>
      present the current temperature
    </li>
    <li>
      humidity<br>
      present the current humidity (if sensor support it)
    </li>
    <li>
      battery<br>
      present the battery state of the senor (if sensor support it)
    </li>
    <li>
      pressure<br>
      present the pressure state of the senor (if sensor support it)
    </li>
    <li>
      windavg<br>
      present the average wind speed state of the senor (if sensor support it)
    </li>
    <li>
      winddir<br>
      present the wind direction state of the senor (if sensor support it)
    </li>
    <li>
      windgust<br>
      present the wind gust state of the senor (if sensor support it)
    </li>
  </ul>
  <br>
  <a name="pilight_temp_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="corrTemp">corrTemp</a><br>
      A factor (e.q. 0.1) to correct the temperture value. Default: 1
      temperature = corrTemp * piligt_temp + offsetTemp
    </li>
    <li><a name="offsetTemp">offsetTemp</a><br>
      An offset for temperature value. Default: 0
      temperature = corrTemp * piligt_temp + offsetTemp
    </li>
    <li><a name="corrHumidity">corrHumidity</a><br>
      A factor (e.q. 0.1) to correct the humidity value. Default: 1
      humidity = corrHumidity * piligt_humidity + offsetHumidity
    </li>
    <li><a name="offsetHumidity">offsetHumidity</a><br>
      An offset for humidity value. Default: 0
      humidity = corrHumidity * piligt_humidity + offsetHumidity
    </li>
  </ul>
</ul>

=end html

=cut
