##############################################
# $Id: 20_pilight_temp.pm 0.12 2015-05-16 Risiko $
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
############################################## 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;

sub pilight_temp_Parse($$);
sub pilight_temp_Define($$);
sub pilight_temp_Fingerprint($$);

sub pilight_temp_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "pilight_temp_Define";
  $hash->{Match}    = "^PITEMP";
  $hash->{ParseFn}  = "pilight_temp_Parse";
  $hash->{AttrList} = "corrTemp ".$readingFnAttributes;
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

###########################################
sub pilight_temp_Parse($$)
{
  my ($mhash, $rmsg, $rawdata) = @_;
  my $backend = $mhash->{NAME};

  Log3 $backend, 4, "pilight_temp_Parse: RCV -> $rmsg";
  
  my ($dev,$protocol,$id,$temp,$humidity,$battery,@args) = split(",",$rmsg);
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
  $temp = $temp * $corrTemp;
  
  readingsBeginUpdate($chash);
  readingsBulkUpdate($chash,"state",$temp);
  readingsBulkUpdate($chash,"temperature",$temp);
  readingsBulkUpdate($chash,"humidity",$humidity) if (defined($humidity)  && $humidity  ne "");
  readingsBulkUpdate($chash,"battery",$battery)   if (defined($battery)   && $battery   ne "");
  readingsEndUpdate($chash, 1); 
  
  return $chash->{NAME};
}


1;

=pod
=begin html

<a name="pilight_temp"></a>
<h3>pilight_temp</h3>
<ul>

  pilight_temp represents a temperature and humidity sensor receiving dat from pilight<br>
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
  </ul>
  <br>
  <a name="pilight_temp_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="corrTemp">corrTemp</a><br>
      A factor (e.q. 0.1) to correct the temperture value. Default: 1
    </li>
  </ul>
</ul>

=end html

=cut
