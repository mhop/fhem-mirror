# $Id$
##############################################################################
#
#     11_OWDevice.pm
#     Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

# Todos:
# - stateFormat via Interface
# - warum wird jeder Wert 2x geloggt?

package main;

use strict;
use warnings;


###################################
sub
OWDevice_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "OWDevice_Get";
  $hash->{SetFn}     = "OWDevice_Set";
  $hash->{DefFn}     = "OWDevice_Define";
  $hash->{AttrFn}    = "OWDevice_Attr";

  $hash->{AttrList}  = "IODev trimvalues polls interfaces model loglevel:0,1,2,3,4,5 ".  
                       $readingFnAttributes;
}

###################################
# return array
# 1st element: interface
# 2nd element: array of getters/readings
# 3rd element: array of setters/readings
# 4th element: array of readings to be periodically updated
# the value of the first reading in getters is written to state
sub
OWDevice_GetDetails($) {

      my ($hash)= @_;
      my $interface= "";
      my @getters= qw(address alias family id power type);
      my @setters= qw(alias);
      my @polls;

      # below we use shift such that the potentially
      # more important values get listed first and
      # that the first reading in getters could be
      # defined (it is shown in the STATE).
            
      # http://owfs.sourceforge.net/family.html
      my $family= substr($hash->{fhem}{address}, 0, 2);
      if($family eq "10") {
        # 18S20 high precision digital thermometer
        # 1920  iButton version of the thermometer
        unshift @getters, qw(temperature templow temphigh);
        unshift @setters, qw(templow temphigh);
        unshift @polls, qw(temperature);
        $interface= "temperature";
      } elsif($family eq "28") {
        # 18B20 programmable resolution digital thermometer
        unshift @getters, qw(temperature templow temphigh);
        unshift @setters, qw(templow temphigh);
        unshift @polls, qw(temperature);
        $interface= "temperature";
      } elsif($family eq "1D") {
        # 2423 4k RAM with counter
        unshift @getters, qw(counters.A counters.B);
        unshift @setters, qw();
        unshift @polls, qw(counters.A counters.B);
        #$interface= "count";
      } elsif($family eq "22") {
        # 1822 - Econo 1-Wire Digital Thermometer
        # added by m. fischer
        unshift @getters, qw(temperature temperature9 temperature10 temperature11 temperature12 fasttemp);
        unshift @setters, qw(temphigh templow);
        unshift @polls, qw(temperature);
        $interface= "temperature";
      } elsif($family eq "3B") {
        # 1825 - Programmable Resolution 1-Wire Digital Thermometer with ID
        # added by m. fischer
        unshift @getters, qw(prog_addr temperature temperature9 temperature10 temperature11 temperature12 fasttemp);
        unshift @setters, qw(temphigh templow);
        unshift @polls, qw(temperature);
        $interface= "temperature";
      } elsif($family eq "24") {
        # 2415 - 1-Wire Time Chip
        # 1904 - RTC iButton
        # 2417 - 1-Wire Time Chip with Interrupt
        # added by m. fischer
        unshift @getters, qw(date enable interval itime flags running udate);
        unshift @setters, qw(date enable itime flags running udate);
        unshift @polls, qw(date enable running udate);
        #$interface= "timer"; # to be discussed
      } elsif($family eq "01") {
        # 2401 - Silicon Serial Number
        # 1990A - Serial Number iButton
        # added by m. fischer
        # this chip has no special properties to set, get or poll
        # it has only a "unique serial number identifier"
        #interface= "serial"; # to be discussed
      } elsif($family eq "05") {
        # 2405 - Addressable Switch
        # added by m. fischer
        unshift @getters, qw(PIO);
        unshift @setters, qw(PIO);
        unshift @polls, qw(PIO);
        #$interface= "state";
      } elsif($family eq "12") {
        # 2406, 2407 - Dual Addressable Switch with 1kbit Memory
        # added by m. fischer
        unshift @getters, qw(PIO.A PIO.B);
        unshift @setters, qw(PIO.A PIO.B);
        unshift @polls, qw(PIO.A PIO.B);
        #$interface= "state";
      } elsif($family eq "3A") {
        # 2413 1-Wire Dual Channel Addressable Switch
        unshift @getters, qw(PIO.A PIO.B);
        unshift @setters, qw(PIO.A PIO.B);
        unshift @polls, qw(PIO.A PIO.B);
        #$interface= "state";
      } elsif($family eq "29") {
        # 2408 - 1-Wire 8 Channel Addressable Switch
        # added by m. fischer
        unshift @getters, qw(PIO.0 PIO.1 PIO.2 PIO.3 PIO.4 PIO.5 PIO.6 PIO.7);
        unshift @setters, qw(PIO.0 PIO.1 PIO.2 PIO.3 PIO.4 PIO.5 PIO.6 PIO.7);
        unshift @polls, qw(PIO.0 PIO.1 PIO.2 PIO.3 PIO.4 PIO.5 PIO.6 PIO.7);
        #$interface= "state";
      } elsif($family eq "FF") {
        # LCD - LCD controller
        # added by m. fischer
        unshift @getters, qw(counters.0 counters.1 counters.2 counters.3);
        unshift @getters, qw(cumulative.0 cumulative.1 cumulative.2 cumulative.3 version);
        unshift @setters, qw(cumulative.0 cumulative.1 cumulative.2 cumulative.3);
        unshift @setters, qw(line16.0 line16.1 line16.2 line16.3 screen16);
        unshift @setters, qw(line20.0 line20.1 line20.2 line20.3 screen20);
        unshift @setters, qw(line40.0 line40.1 line40.2 line40.3 screen40);
        unshift @setters, qw(backlight LCDon);
        unshift @polls, qw(counters.0 counters.1 counters.2 counters.3);
        unshift @polls, qw(cumulative.0 cumulative.1 cumulative.2 cumulative.3);
        #$interface= "display"; # to be discussed
      } elsif($family eq "1B") {
        # 2436 - Battery ID/Monitor Chip
        # added by m. fischer
        unshift @getters, qw(temperature volts counter/cycles);
        unshift @setters, qw(counter/increment counter/reset);
        unshift @polls, qw(temperature volts counter/cycles);
        #interface= "state"; # to be discussed
      } elsif($family eq "26") {
        # 2438 - Smart Battery Monitor
        # added by m. fischer
        unshift @getters, qw(temperature VAD VDD vis CA EE IAD date disconnect/date disconnect/udate);
        # configuration properties
        unshift @getters, qw(CA EE IAD);
        # date properties
        unshift @getters, qw(date disconnect/date disconnect/udate endcharge/date endcharge/udate udate);
        # humidity sensor
        unshift @getters, qw(HIH4000/humidity HTM1735/humidity DATANAB/humidity humidity);
        # barometer
        unshift @getters, qw(B1-R1-A/pressure B1-R1-A/gain B1-R1-A/offset);
        # solar sensor
        unshift @getters, qw(S3-R1-A/current S3-R1-A/illumination S3-R1-A/gain);
        # multisensor
        unshift @getters, qw(MultiSensor/type offset);
        # configuration properties
        unshift @setters, qw(CA EE IAD);
        # date properties
        unshift @setters, qw(date disconnect/date disconnect/udate endcharge/date endcharge/udate udate);
        # humidity sensor
        unshift @setters, qw(DATANAB/reset);
        # solar sensor
        unshift @setters, qw(S3-R1-A/gain);
        # multisensor
        unshift @setters, qw(offset);
        unshift @polls, qw(temperature VAD VDD);
        #$interface= "multisensor"; # to be discussed
      } elsif($family eq "20") {
        # 2450 - Quad A/D Converter
        # added by m. fischer
        unshift @getters, qw(alarm/high.A alarm/high.B alarm/high.C alarm/high.D);
        unshift @getters, qw(alarm/low.A alarm/low.B alarm/low.C alarm/low.D);
        unshift @getters, qw(PIO.A PIO.B PIO.C PIO.D);
        unshift @getters, qw(set_alarm/high.A set_alarm/high.B set_alarm/high.C set_alarm/high.D);
        unshift @getters, qw(set_alarm/low.A set_alarm/low.B set_alarm/low.C set_alarm/low.D);
        unshift @getters, qw(set_alarm/volthigh.A set_alarm/volthigh.B set_alarm/volthigh.C set_alarm/volthigh.D);
        unshift @getters, qw(set_alarm/volt2high.A set_alarm/volt2high.B set_alarm/volt2high.C set_alarm/volt2high.D);
        unshift @getters, qw(set_alarm/voltlow.A set_alarm/voltlow.B set_alarm/voltlow.C set_alarm/voltlow.D);
        unshift @getters, qw(set_alarm/volt2low.A set_alarm/volt2low.B set_alarm/volt2low.C set_alarm/volt2low.D);
        unshift @getters, qw(set_alarm/unset);
        unshift @getters, qw(volt.A volt.B volt.C volt.D);
        unshift @getters, qw(8bit/volt.A 8bit/volt.B 8bit/volt.C 8bit/volt.D);
        unshift @getters, qw(volt2.A volt2.B volt2.C volt2.D);
        unshift @getters, qw(8bit/volt2.A 8bit/volt2.B 8bit/volt2.C 8bit/volt2.D);
        # co2 (carbon dioxide) sensor
        unshift @getters, qw(CO2/power CO2/ppm CO2/status);
        unshift @setters, qw(alarm/high.A alarm/high.B alarm/high.C alarm/high.D);
        unshift @setters, qw(alarm/low.A alarm/low.B alarm/low.C alarm/low.D);
        unshift @setters, qw(PIO.A PIO.B PIO.C PIO.D);
        unshift @setters, qw(set_alarm/high.A set_alarm/high.B set_alarm/high.C set_alarm/high.D);
        unshift @setters, qw(set_alarm/low.A set_alarm/low.B set_alarm/low.C set_alarm/low.D);
        unshift @setters, qw(set_alarm/volthigh.A set_alarm/volthigh.B set_alarm/volthigh.C set_alarm/volthigh.D);
        unshift @setters, qw(set_alarm/volt2high.A set_alarm/volt2high.B set_alarm/volt2high.C set_alarm/volt2high.D);
        unshift @setters, qw(set_alarm/voltlow.A set_alarm/voltlow.B set_alarm/voltlow.C set_alarm/voltlow.D);
        unshift @setters, qw(set_alarm/volt2low.A set_alarm/volt2low.B set_alarm/volt2low.C set_alarm/volt2low.D);
        unshift @setters, qw(set_alarm/unset);
        unshift @polls, qw(PIO.A PIO.B PIO.C PIO.D);
        unshift @polls, qw(volt.A volt.B volt.C volt.D);
        unshift @polls, qw(alarm/high.A alarm/high.B alarm/high.C alarm/high.D);
        unshift @polls, qw(alarm/low.A alarm/low.B alarm/low.C alarm/low.D);
        #$interface= "multisensor"; # to be discussed
      } elsif($family eq "reserved") {
        # reserved for other devices
        # add other devices here and post your additions as patch in
        # http://forum.fhem.de/index.php?t=thread&frm_id=26&rid=10
      };
      # http://perl-seiten.homepage.t-online.de/html/perl_array.html
      return ($interface, \@getters, \@setters, \@polls);
}

###################################
# This could be IORead in fhem, But there is none.
# Read http://forum.fhem.de/index.php?t=tree&goto=54027&rid=10#msg_54027
# to find out why.
sub
OWDevice_ReadFromServer($@)
{
  my ($hash, @a) = @_;

  my $dev = $hash->{NAME};
  return if(IsDummy($dev) || IsIgnored($dev));
  my $iohash = $hash->{IODev};
  if(!$iohash ||
     !$iohash->{TYPE} ||
     !$modules{$iohash->{TYPE}} ||
     !$modules{$iohash->{TYPE}}{ReadFn}) {
    Log 5, "No I/O device or ReadFn found for $dev";
    return;
  }

  no strict "refs";
  my $ret = &{$modules{$iohash->{TYPE}}{ReadFn}}($iohash, @a);
  use strict "refs";
  return $ret;
}

###################################
sub
OWDevice_ReadValue($$) {

        my ($hash,$reading)= @_;
        
        my $address= $hash->{fhem}{address};
        my $value= OWDevice_ReadFromServer($hash, "/$address/$reading");
        #Debug "/$address/$reading => $value";  
        if(defined($value)) {
          $value= trim($value) if(AttrVal($hash,"trimvalues",1));
        } else {
          Log 3, $hash->{NAME} . ": reading $reading did not return a value";
        }
        
        return $value;
}

###################################
sub
OWDevice_WriteValue($$$) {

        my ($hash,$reading,$value)= @_;

        my $address= $hash->{fhem}{address};
        IOWrite($hash, "/$address/$reading", $value);
        return $value;
}

###################################
sub
OWDevice_UpdateValues($) {

        my ($hash)= @_;

        my @polls= @{$hash->{fhem}{polls}};
        my @getters= @{$hash->{fhem}{getters}};
        if($#polls>=0) {
          my $address= $hash->{fhem}{address};
          readingsBeginUpdate($hash);
          foreach my $reading (@polls) {
            my $value= OWDevice_ReadValue($hash,$reading);
            if(defined($value)) {
              readingsBulkUpdate($hash,$reading,$value);
              readingsBulkUpdate($hash,"state","$reading: $value") if($reading eq $getters[0]);
            }
          }
          readingsEndUpdate($hash,1);
        }
        InternalTimer(gettimeofday()+$hash->{fhem}{interval}, "OWDevice_UpdateValues", $hash, 0)
          if(defined($hash->{fhem}{interval}));

}

###################################
sub
OWDevice_Attr($@)
{
        my ($cmd, $name, $attrName, $attrVal) = @_;
        my $hash = $defs{$name};

        $attrVal= "" unless defined($attrVal);
        $attrVal= "" if($cmd eq "del");
        
        if($attrName eq "polls") {
            my @polls= split(",", $attrVal);
            $hash->{fhem}{polls}= \@polls;
            Log 5, "$name: polls: " . join(" ", @polls);
        } elsif($attrName eq "interfaces") {
            if($attrVal ne "") {
              $hash->{fhem}{interfaces}= join(";",split(",",$attrVal));
              Log 5, "$name: interfaces: " . $hash->{fhem}{interfaces};
            } else {
              delete $hash->{fhem}{interfaces} if(defined($hash->{fhem}{interfaces}));
              Log 5, "$name: no interfaces";
            }
        }
}        

###################################
sub
OWDevice_Get($@)
{
        my ($hash, @a)= @_;

        my $name= $hash->{NAME};
        return "get $name needs one argument" if(int(@a) != 2);
        my $cmdname= $a[1];
        my @getters= @{$hash->{fhem}{getters}};
        if($cmdname ~~ @getters) {
          my $value= OWDevice_ReadValue($hash, $cmdname);
          readingsSingleUpdate($hash,$cmdname,$value,1);
          return $value;
        } else {
          return "Unknown argument $cmdname, choose one of " . join(" ", @getters);
        }
}

#############################
sub
OWDevice_Set($@)
{
        my ($hash, @a)= @_;

        my $name= $hash->{NAME};
        my $cmdname= $a[1];
        my $value= $a[2];
        my @setters= @{$hash->{fhem}{setters}};
        if($cmdname ~~ @setters) {
          # LCD Display need more than two arguments, to display text
          # added by m.fischer
          if($cmdname =~ /(line16.0|line16.1|line16.2|line16.3|screen16)/ ||
             $cmdname =~ /(line20.0|line20.1|line20.2|line20.3|screen20)/ ||
             $cmdname =~ /(line40.0|line40.1|line40.2|line40.3|screen40)/) {
             shift @a;
             shift @a;
             $value= "@a";
          } else {
            return "set $name needs two arguments" if(int(@a) != 3);
          }
          OWDevice_WriteValue($hash,$cmdname,$value);
          readingsSingleUpdate($hash,$cmdname,$value,1);
          return undef;
        } else {
          return "Unknown argument $cmdname, choose one of " . join(" ", @setters);
        }
}

#############################
sub
OWDevice_Define($$)
{
        my ($hash, $def) = @_;
        my @a = split("[ \t]+", $def);

        return "Usage: define <name> OWDevice <address> [interval]"  if($#a < 2|| $#a > 3);
        my $name= $a[0];

        AssignIoPort($hash);
        if(defined($hash->{IODev}->{NAME})) {
          Log 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
        } else {
          Log 1, "$name: no I/O device";
        }

        $hash->{fhem}{address}= $a[2];
        if($#a == 3) {
          $hash->{fhem}{interval}= $a[3];
          Log 5, "$name: polling every $a[3] seconds";
        }
        my ($interface, $gettersref, $settersref, $pollsref)= OWDevice_GetDetails($hash);
        my @getters= @{$gettersref};
        my @setters= @{$settersref};
        my @polls= @{$pollsref};
        if($interface ne "") {
          $hash->{fhem}{interfaces}= $interface;
          Log 5, "$name: interfaces: $interface";
        }
        $hash->{fhem}{getters}= $gettersref;
        Log 5, "$name: getters: " . join(" ", @getters);
        $hash->{fhem}{setters}= $settersref;
        Log 5, "$name: setters: " . join(" ", @setters);
        $hash->{fhem}{polls}= $pollsref;
        Log 5, "$name: polls: " . join(" ", @polls);

        $attr{$name}{model}= OWDevice_ReadValue($hash, "type");
        OWDevice_UpdateValues($hash) if(defined($hash->{fhem}{interval}));

        return undef;
}
###################################

1;

###################################
=pod
=begin html

<a name="OWDevice"></a>
<h3>OWDevice</h3>
<ul>
  <br>
  <a name="OWDevicedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OWDevice &lt;address&gt; [&lt;interval&gt;]</code>
    <br><br>

    Defines a 1-wire device. The 1-wire device is identified by its &lt;address&gt;. It is
    served by the most recently defined <a href="#OWServer">OWServer</a>.
    <br><br>

    If &lt;interval&gt; is given, the OWServer is polled every &lt;interval&gt; seconds for
    a subset of readings.
    <br><br>

    OWDevice is a generic device. Its characteristics are retrieved at the time of the device's
    definition. The available readings that you can get or set as well as those that are
    regularly retrieved by polling can be seen when issuing the
    <code><a href="#list">list</a> &lt;name&gt;</code> command.
    <br><br>
    The following devices are currently supported:
    <ul>
      <li>18S20 high precision digital thermometer</li>
      <li>18B20 programmable resolution digital thermometer</li>
      <li>2423 4k RAM with counter</li>
      <li>2413 1-Wire Dual Channel Addressable Switch</li>
      <li>2405 Addressable Switch</li>
      <li>2406, 2407 - Dual Addressable Switch with 1kbit Memory</li>
      <li>2408 1-Wire 8 Channel Addressable Switch</li>
      <li>LCD 1-wire LCD controller by Louis Swart</li>
    </ul>
    <br><br>
    Adding more devices is simple. Look at the code (subroutine <code>OWDevice_GetDetails</code>).
    <br><br>
    This module is completely unrelated to the 1-wire modules with names all in uppercase.
    <br><br>

    Example:
    <ul>
      <code>
      define myOWServer localhost:4304<br><br>
      get myOWServer devices<br>
      10.487653020800 DS18S20<br><br>
      define myT1 10.487653020800<br><br>
      list myT1 10.487653020800<br>
      Internals:<br>
          ...<br>
        Readings:<br>
          2012-12-22 20:30:07   temperature     23.1875<br>
        Fhem:<br>
          ...<br>
          getters:<br>
            address<br>
            alias<br>
            family<br>
            id<br>
            power<br>
            type<br>
            temperature<br>
            templow<br>
            temphigh<br>
          polls:<br>
            temperature<br>
          setters:<br>
            alias<br>
            templow<br>
            temphigh<br>
        ...<br>
      </code>
    </ul>
    <br>
  </ul>

  <a name="OWDeviceset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;reading&gt; &lt;value&gt;</code>
    <br><br>
    Sets &lt;reading&gt; to &lt;value&gt; for the 1-wire device &lt;name&gt;. The permitted values are defined by the underlying
    1-wire device type.
    <br><br>
    Example:
    <ul>
      <code>set myT1 templow 5</code><br>
    </ul>
    <br>
  </ul>


  <a name="OWDeviceget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt; &lt;value&gt;</code>
    <br><br>
    Gets &lt;reading&gt; for the 1-wire device &lt;name&gt;. The permitted values are defined by the underlying
    1-wire device type.
    <br><br>
    Example:
    <ul>
      <code>get myT1 temperature</code><br>
    </ul>
    <br>
  </ul>


  <a name="OWDeviceattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="IODev"></a>
    <li>IODev: 
        Set the OWServer device which should be used for sending and receiving data
        for this OWDevice. Note: Upon startup fhem assigns each OWDevice
        to the last previously defined OWServer. Thus it is best if you define OWServer
        and OWDevices in blocks: first define the first OWServer and the OWDevices that
        belong to it, then continue with the next OWServer and the attached OWDevices, and so on.
    </li>
    <li>trimvalues: removes leading and trailing whitespace from readings. Default is 1 (on).</li>
    <li>polls: a comma-separated list of readings to poll. This supersedes the list of default readings to poll.</li>
    <li>interfaces: supersedes the interfaces exposed by that device.</li>
    <li>model: preset with device type, e.g. DS18S20.</li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>


</ul>




=end html
=cut
