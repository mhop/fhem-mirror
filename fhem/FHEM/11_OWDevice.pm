# $Id$
##############################################################################
#
#     11_OWDevice.pm
#     Copyright by Dr. Boris Neubert & Martin Fischer
#     e-mail: omega at online dot de
#     e-mail: m_fischer at gmx dot de
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

package main;

use strict;
use warnings;

use vars qw(%owdevice);

# 1-Wire devices (order by family code)
# http://owfs.sourceforge.net/family.html

$owdevice{"01"} = {
    # DS2401 - Silicon Serial Number
    # DS1990A - Serial Number iButton
    "read"      => [],
    "write"     => [],
    "poll"      => [ qw(id) ],
    "state"     => [],
    "interface" => "id",
};
$owdevice{"05"} = {
    # DS2405 - Addressable Switch
    "read"      => [ qw(PIO sensed) ],
    "write"     => [ qw(PIO) ],
    "poll"      => [ qw(sensed) ],
    "state"     => [ qw(sensed) ],
    "event"     => { qw(0 closed 1 opened) },
    "interface" => "state",
};
$owdevice{"10"} = {
    # DS18S20 - High-Precision 1-Wire Digital Thermometer
    # DS1920 - iButton version of the thermometer
    "read"      => [ qw(power),
                     qw(temperature templow temphigh) ],
    "write"     => [ qw(templow temphigh) ],
    "poll"      => [ qw(temperature) ],
    "state"     => [ qw(temperature) ],
    "alarm"     => 1,
    "interface" => "temperature",
};
$owdevice{"12"} = {
    # DS2406, DS2407 - Dual Addressable Switch with 1kbit Memory
    "read"      => [ qw(channels),
                     qw(latch.A latch.B latch.ALL latch.BYTE),
                     qw(memory),
                     qw(pages/page.0 pages/page.1 pages/page.2 pages/page.3 pages/page.ALL),
                     qw(PIO.A PIO.B PIO.ALL PIO.BYTE),
                     qw(power),
                     qw(sensed.A sensed.B sensed.ALL sensed.BYTE),
                     qw(set_alarm),
                     qw(TAI8570/pressure TAI8570/sibling TAI8570/temperature),
                     qw(T8A/volt.0 T8A/volt.1 T8A/volt.2 T8A/volt.3 T8A/volt.4 T8A/volt.5 T8A/volt.6),
                     qw(T8A/volt.7 T8A/volt.ALL) ],
    "write"     => [ qw(latch.A latch.B latch.ALL latch.BYTE),
                     qw(memory),
                     qw(pages/page.0 pages/page.1 pages/page.2 pages/page.3 pages/page.ALL),
                     qw(PIO.A PIO.B PIO.ALL PIO.BYTE),
                     qw(sensed.A sensed.B sensed.ALL sensed.BYTE),
                     qw(set_alarm), ],
    "poll"      => [ qw(sensed.A sensed.B) ],
    "state"     => [ qw(sensed.A sensed.B) ],
    "alarm"     => 1,
    "event"     => { qw(0 off 1 on) },
    "interface" => "state",
};
$owdevice{"1B"} = {
    # DS2436 - Battery ID/Monitor Chip
    "read"      => [ qw(pages/page.0 pages/page.1 pages/page.2 pages/page.3 pages/page.4 pages/page.ALL),
                     qw(temperature),
                     qw(volts),
                     qw(counter/cycles) ],
    "write"     => [ qw(pages/page.0 pages/page.1 pages/page.2 pages/page.3 pages/page.4 pages/page.ALL),
                     qw(counter/increment counter/reset) ],
    "poll"      => [ qw(temperature volts counter/cycles) ],
    "state"     => [ qw(temperature volts counter/cycles) ],
    "interface" => "multisensor",
};
$owdevice{"1D"} = {
    # DS2423 - 4kbit 1-Wire RAM with Counter
    "read"      => [ qw(counters.A counters.B counters.ALL),
                     qw(memory),
                     qw(pages/page.0 pages/page.1 pages/page.2 pages/page.3 pages/page.4 pages/page.5),
                     qw(pages/page.6 pages/page.7 pages/page.8 pages/page.9 pages/page.10 pages/page.11),
                     qw(pages/page.12 pages/page.13 pages/page.14 pages/page.15),
                     qw(pages/count.0 pages/count.1 pages/count.2 pages/count.3 pages/count.4 pages/count.5),
                     qw(pages/count.6 pages/count.7 pages/count.8 pages/count.9 pages/count.10 pages/count.11),
                     qw(pages/count.12 pages/count.13 pages/count.14 pages/count.15) ],
    "write"     => [ qw(memory),
                     qw(pages/page.0 pages/page.1 pages/page.2 pages/page.3 pages/page.4 pages/page.5),
                     qw(pages/page.6 pages/page.7 pages/page.8 pages/page.9 pages/page.10 pages/page.11),
                     qw(pages/page.12 pages/page.13 pages/page.14 pages/page.15) ],
    "poll"      => [ qw(counters.A counters.B) ],
    "state"     => [ qw(counters.A counters.B) ],
    "offset"    => [ qw(counters.A counters.B) ],
    "interface" => "counter",
};
$owdevice{"20"} = {
    # DS2450 - Quad A/D Converter
    "read"      => [ qw(alarm/high.A alarm/high.B alarm/high.C alarm/high.D alarm/high.ALL),
                     qw(alarm/low.A alarm/low.B alarm/low.C alarm/low.D alarm/low.ALL),
                     qw(memory),
                     qw(pages/page.0 pages/page.1 pages/page.2 pages/page.3 pages/page.ALL),
                     qw(PIO.A PIO.B PIO.C PIO.D PIO.ALL),
                     qw(power),
                     qw(set_alarm/high.A set_alarm/high.B set_alarm/high.C set_alarm/high.D set_alarm/high.ALL),
                     qw(set_alarm/low.A set_alarm/low.B set_alarm/low.C set_alarm/low.D set_alarm/low.ALL),
                     qw(set_alarm/volthigh.A set_alarm/volthigh.B set_alarm/volthigh.C set_alarm/volthigh.D),
                     qw(set_alarm/volthigh.ALL),
                     qw(set_alarm/volt2high.A set_alarm/volt2high.B set_alarm/volt2high.C set_alarm/volt2high.D),
                     qw(set_alarm/volt2high.ALL),
                     qw(set_alarm/voltlow.A set_alarm/voltlow.B set_alarm/voltlow.C set_alarm/voltlow.D),
                     qw(set_alarm/voltlow.ALL),
                     qw(set_alarm/volt2low.A set_alarm/volt2low.B set_alarm/volt2low.C set_alarm/volt2low.D),
                     qw(set_alarm/volt2low.ALL),
                     qw(set_alarm/unset),
                     qw(volt.A volt.B volt.C volt.D volt.ALL),
                     qw(8bit/volt.A 8bit/volt.B 8bit/volt.C 8bit/volt.D 8bit/volt.ALL),
                     qw(volt2.A volt2.B volt2.C volt2.D volt2.ALL),
                     qw(8bit/volt2.A 8bit/volt2.B 8bit/volt2.C 8bit/volt2.D 8bit/volt2.ALL),
                     qw(CO2/power CO2/ppm CO2/status) ],
    "write"     => [ qw(alarm/high.A alarm/high.B alarm/high.C alarm/high.D alarm/high.ALL),
                     qw(alarm/low.A alarm/low.B alarm/low.C alarm/low.D alarm/low.ALL),
                     qw(memory),
                     qw(pages/page.0 pages/page.1 pages/page.2 pages/page.3 pages/page.ALL),
                     qw(PIO.A PIO.B PIO.C PIO.D PIO.ALL),
                     qw(power),
                     qw(set_alarm/high.A set_alarm/high.B set_alarm/high.C set_alarm/high.D set_alarm/high.ALL),
                     qw(set_alarm/low.A set_alarm/low.B set_alarm/low.C set_alarm/low.D set_alarm/low.ALL),
                     qw(set_alarm/volthigh.A set_alarm/volthigh.B set_alarm/volthigh.C set_alarm/volthigh.D),
                     qw(set_alarm/volthigh.ALL),
                     qw(set_alarm/volt2high.A set_alarm/volt2high.B set_alarm/volt2high.C set_alarm/volt2high.D),
                     qw(set_alarm/volt2high.ALL),
                     qw(set_alarm/voltlow.A set_alarm/voltlow.B set_alarm/voltlow.C set_alarm/voltlow.D),
                     qw(set_alarm/voltlow.ALL),
                     qw(set_alarm/volt2low.A set_alarm/volt2low.B set_alarm/volt2low.C set_alarm/volt2low.D),
                     qw(set_alarm/volt2low.ALL),
                     qw(set_alarm/unset) ],
    "poll"      => [ qw(PIO.A PIO.B PIO.C PIO.D),
                     qw(volt.A volt.B volt.C volt.D),
                     qw(volt2.A volt2.B volt2.C volt2.D) ],
    "state"     => [ qw(PIO.A PIO.B PIO.C PIO.D),
                     qw(volt.A volt.B volt.C volt.D),
                     qw(volt2.A volt2.B volt2.C volt2.D) ],
    "event"     => { qw(0 off 1 on) },
    "interface" => "multisensor",
};
$owdevice{"22"} = {
    # DS1822 - Econo 1-Wire Digital Thermometer
    "read"      => [ qw(temperature temperature9 temperature10 temperature11 temperature12 fasttemp),
                     qw(temphigh templow),
		     qw(power) ],
    "write"	=> [ qw(temphigh templow) ],
    "poll"      => [ qw(temperature) ],
    "state"     => [ qw(temperature) ],
    "alarm"     => 1,
    "interface" => "temperature",
};
$owdevice{"24"} = {
    # DS2415 - 1-Wire Time Chip
    # DS1904 - RTC iButton
    "read"      => [ qw(date flags running udate) ],
    "write"     => [ qw(date flags running udate) ],
    "poll"      => [ qw(date running udate) ],
    "state"     => [ qw(date running) ],
    "interface" => "timer",
};
$owdevice{"26"} = {
    # DS2438 - Smart Battery Monitor
    "read"      => [ qw(pages/page.0 pages/page.1 pages/page.2 pages/page.3 pages/page.4),
                     qw(pages/page.5 pages/page.6 pages/page.7 pages/page.ALL),
                     qw(temperature),
                     qw(VAD VDD),
                     qw(vis),
                     qw(CA),
                     qw(EE),
                     qw(IAD),
                     qw(date),
                     qw(disconnect/date disconnect/udate),
                     qw(endcharge/date endcharge/udate),
                     qw(udate),
                     qw(HIH4000/humidity),
                     qw(HTM1735/humidity),
                     qw(DATANAB/humidity),
                     qw(humidity),
                     qw(B1-R1-A/pressure B1-R1-A/gain B1-R1-A/offset),
                     qw(S3-R1-A/current S3-R1-A/illumination S3-R1-A/gain),
                     qw(MultiSensor/type),
                     qw(offset) ],
    "write"     => [ qw(pages/page.0 pages/page.1 pages/page.2 pages/page.3 pages/page.4),
                     qw(pages/page.5 pages/page.6 pages/page.7 pages/page.ALL),
                     qw(CA),
                     qw(EE),
                     qw(IAD),
                     qw(date),
                     qw(disconnect/date disconnect/udate),
                     qw(endcharge/date endcharge/udate),
                     qw(udate),
                     qw(DATANAB/reset),
                     qw(B1-R1-A/gain B1-R1-A/offset),
                     qw(S3-R1-A/gain),
                     qw(offset) ],
    "poll"      => [ qw(temperature VAD VDD) ],
    "state"     => [ qw(temperature VAD VDD) ],
    "interface" => "multisensor",
};
$owdevice{"27"} = {
    # DS2417 - 1-Wire Time Chip with Interrupt
    "read"      => [ qw(date enable interval itime running udate) ],
    "write"     => [ qw(date enable interval itime running udate) ],
    "poll"      => [ qw(date enable running udate) ],
    "state"     => [ qw(date enable running) ],
    "interface" => "timer",
};
$owdevice{"28"} = {
    # DS18B20 - Programmable Resolution 1-Wire Digital Thermometer
    "read"      => [ qw(temperature temperature9 temperature10 temperature11 temperature12 fasttemp),
                     qw(temphigh templow) ],
    "write"     => [ qw(temphigh templow) ],
    "poll"      => [ qw(temperature) ],
    "state"     => [ qw(temperature) ],
    "alarm"     => 1,
    "interface" => "temperature",
};
$owdevice{"29"} = {
    # DS2408 - 1-Wire 8 Channel Addressable Switch
    "read"      => [ qw(latch.0 latch.1 latch.2 latch.3 latch.4 latch.5 latch.6 latch.7 latch.ALL latch.BYTE),
                     qw(PIO.0 PIO.1 PIO.2 PIO.3 PIO.4 PIO.5 PIO.6 PIO.7 PIO.ALL PIO.BYTE),
                     qw(power),
                     qw(sensed.0 sensed.1 sensed.2 sensed.3 sensed.4 sensed.5 sensed.6 sensed.7 sensed.ALL),
                     qw(strobe),
                     qw(por),
                     qw(set_alarm) ],
    "write"     => [ qw(latch.0 latch.1 latch.2 latch.3 latch.4 latch.5 latch.6 latch.7 latch.ALL latch.BYTE),
                     qw(PIO.0 PIO.1 PIO.2 PIO.3 PIO.4 PIO.5 PIO.6 PIO.7 PIO.ALL PIO.BYTE),
                     qw(strobe),
                     qw(por),
                     qw(set_alarm),
                     qw(LCD_H/clear LCD_H/home LCD_H/screen LCD_H/screenyc LCD_H/onoff LCD_H/message),
                     qw(LCD_M/clear LCD_M/home LCD_M/screen LCD_M/screenyc LCD_M/onoff LCD_M/message) ],
    "poll"      => [ qw(sensed.0 sensed.1 sensed.2 sensed.3 sensed.4 sensed.5 sensed.6 sensed.7) ],
    "state"     => [ qw(sensed.0 sensed.1 sensed.2 sensed.3 sensed.4 sensed.5 sensed.6 sensed.7) ],
    "alarm"     => 1,
    "event"     => { qw(0 off 1 on) },
    "interface" => "state",
};
$owdevice{"3A"} = {
    # DS2413 - Dual Channel Addressable Switch
    "read"      => [ qw(PIO.A PIO.B PIO.ALL PIO.BYTE),
                     qw(sensed.A sensed.B sensed.ALL sensed.BYTE) ],
    "write"     => [ qw(PIO.A PIO.B PIO.ALL PIO.BYTE) ],
    "poll"      => [ qw(sensed.A sensed.B) ],
    "state"     => [ qw(sensed.A sensed.B) ],
    "event"     => { qw(0 off 1 on) },
    "interface" => "state",
};
$owdevice{"3B"} = {
    # DS1825 - Programmable Resolution 1-Wire Digital Thermometer with ID
    "read"      => [ qw(prog_addr temperature temperature9 temperature10 temperature11 temperature12 fasttemp) ],
    "write"     => [ qw(temphigh templow) ],
    "poll"      => [ qw(temperature) ],
    "state"     => [ qw(temperature) ],
    "alarm"     => 1,
    "interface" => "temperature",
};
$owdevice{"7E"} = {
    # EDS0066 - Multisensor temperature Pressure
    "read" => [ qw(EDS0066/temperature EDS0066/pressure)],
    "write" => [],
    "poll" => [ qw(EDS0066/temperature EDS0066/pressure) ],
    "state" => [ qw(EDS0066/temperature EDS0066/pressure) ],
    "interface" => "multisensor",
};
$owdevice{"81"} = {
    # USB id - ID found in DS2490R and DS2490B USB adapters 
    "read"      => [],
    "write"     => [],
    "poll"      => [ qw(id) ],
    "state"     => [],
    "interface" => "id",
};
$owdevice{"FF"} = {
    # LCD - LCD controller by Louis Swart
    "read"      => [ qw(counters.0 counters.1 counters.2 counters.3 counters.ALL),
                     qw(cumulative.0 cumulative.1 cumulative.2 cumulative.3 cumulative.ALL),
                     qw(data),
                     qw(memory),
                     qw(register),
                     qw(version) ],
    "write"     => [ qw(backlight),
                     qw(cumulative.0 cumulative.1 cumulative.2 cumulative.3 cumulative.ALL),
                     qw(data),
                     qw(LCDon),
                     qw(line16.0 line16.1 line16.2 line16.3 line16.ALL),
                     qw(line20.0 line20.1 line20.2 line20.3 line20.ALL),
                     qw(line40.0 line40.1 line40.2 line40.3 line40.ALL),
                     qw(memory),
                     qw(register),
                     qw(screen16 screen20 screen40) ],
    "poll"      => [ qw(counters.0 counters.1 counters.2 counters.3) ],
    "state"     => [ qw(counters.0 counters.1 counters.2 counters.3) ],
    "interface" => "display",
};

# add default properties to each owdevice
foreach my $f (sort keys %owdevice) {
    push(@{$owdevice{$f}{"read"}},qw(address crc8 family id locator r_address r_id r_locator type));
    @{$owdevice{$f}{"read"}}  = sort(@{$owdevice{$f}{"read"}});
    if(defined($owdevice{$f}{"write"}) && @{$owdevice{$f}{"write"}}) {
        @{$owdevice{$f}{"write"}} = sort(@{$owdevice{$f}{"write"}});
    }
    if(defined($owdevice{$f}{"poll"}) && @{$owdevice{$f}{"poll"}}) {
    	@{$owdevice{$f}{"poll"}}  = sort(@{$owdevice{$f}{"poll"}});
    }
    if(defined($owdevice{$f}{"state"}) && @{$owdevice{$f}{"state"}}) {
    	@{$owdevice{$f}{"state"}} = sort(@{$owdevice{$f}{"state"}});
    }
}

###################################
sub
OWDevice_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "OWDevice_Get";
  $hash->{SetFn}     = "OWDevice_Set";
  $hash->{DefFn}     = "OWDevice_Define";
  $hash->{NotifyFn}  = "OWDevice_Notify";
  $hash->{UndefFn}   = "OWDevice_Undef";
  $hash->{AttrFn}    = "OWDevice_Attr";

  $hash->{AttrList}  = "IODev uncached trimvalues polls interfaces model ".  
                       "resolution:9,10,11,12 ".
                       $readingFnAttributes;
}

###################################
# return array
# 1st element: interface
# 2nd element: array of getters/readings
# 3rd element: array of setters/readings
# 4th element: array of readings to be periodically updated
# 5th element: array of readings to be written to state
# 6th element: alerting device support
sub
OWDevice_GetDetails($) {

  my ($hash)= @_;

  my $family= substr($hash->{fhem}{address}, 0, 2);
  my @getters= @{$owdevice{$family}{"read"}};
  my @setters= @{$owdevice{$family}{"write"}};
  my @polls= @{$owdevice{$family}{"poll"}};
  my @state= @{$owdevice{$family}{"state"}};
  my $alerting= ($owdevice{$family}{"alarm"}) ? 1 : 0;
      
  my $interface= $owdevice{$family}{"interface"};
  # http://perl-seiten.homepage.t-online.de/html/perl_array.html
  return ($interface, \@getters, \@setters, \@polls, \@state, $alerting);
}

###################################
# This could be IORead in fhem, But there is none.
# Read http://forum.fhem.de/index.php?t=tree&goto=54027&rid=10#msg_54027
# to find out why.
sub
OWDevice_ReadFromServer($$@)
{
  my ($hash,$cmd,@a) = @_;

  my $dev = $hash->{NAME};
  return if(IsDummy($dev) || IsIgnored($dev));
  my $iohash = $hash->{IODev};
  if(!$iohash ||
     !$iohash->{TYPE} ||
     !$modules{$iohash->{TYPE}} ||
     !$modules{$iohash->{TYPE}}{ReadFn}) {
    Log3 $hash, 5, "No I/O device or ReadFn found for $dev";
    return;
  }

  no strict "refs";
  my $ret;
  if($cmd eq "read") {
    $ret = &{$modules{$iohash->{TYPE}}{ReadFn}}($iohash, @a);
  }
  if($cmd eq "dir") {
    $ret = &{$modules{$iohash->{TYPE}}{DirFn}}($iohash, @a);
  }
  if($cmd eq "find") {
    $ret = &{$modules{$iohash->{TYPE}}{FindFn}}($iohash, @a);
  }
  use strict "refs";
  return $ret;
}

###################################
sub
OWDevice_ReadValue($$) {

        my ($hash,$reading)= @_;
        
        my $address= $hash->{fhem}{address};
        my $interface= $hash->{fhem}{interfaces};
        my $cache= (AttrVal($hash->{NAME},"uncached","")) ? "/uncached" : "";
        my $path = "$cache/$address/$reading";
        $path .= AttrVal($hash->{NAME},"resolution","") if( $reading eq "temperature" );
        my ($seconds, $microseconds) = gettimeofday();
        my $value= OWDevice_ReadFromServer($hash,"read",$path);
        my ($seconds2, $microseconds2) = gettimeofday();
        #my $msec = sprintf( "%03d msec", (($seconds2-$seconds)*1000000 + $microseconds2-$microseconds)/1000 );
        #Debug "$path => $value; $msec";  
        if($interface ne "id") {
          if(defined($value)) {
            $value= trim($value) if(AttrVal($hash,"trimvalues",1));
          } else {
            Log3 $hash, 3, $hash->{NAME} . ": reading $reading did not return a value";
          }
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
        my @state= @{$hash->{fhem}{state}};
        my $alerting= $hash->{fhem}{alerting};
        my $interface= $hash->{fhem}{interfaces};
        my $state;
        if($#polls>=0) {
          my $address= $hash->{fhem}{address};
          readingsBeginUpdate($hash);
          foreach my $reading (@polls) {
            my $value= OWDevice_ReadValue($hash,$reading);
            if(defined($value)) {
              readingsBulkUpdate($hash,$reading,$value);
            }
          }
          if(@state) {
            foreach my $reading (@state) {
              my $value= ReadingsVal($hash->{NAME},$reading,undef);
              if(defined($value)) {
                $state .= "$reading: $value  ";
              } else {
                $state .= "$reading: n/a  ";
              }
            }
          }
          if($alerting) {
            my $dir= OWDevice_ReadFromServer($hash,"dir","/alarm/");
            my $alarm= (defined($dir) && $dir =~ m/$address/) ? 1 :0;
            readingsBulkUpdate($hash,"alarm",$alarm);
            $state .= "alarm: $alarm";
          }
          if($interface eq "id") {
            my $dir= OWDevice_ReadFromServer($hash,"dir","/");
            my $present= (defined($dir) && $dir =~ m/$address/) ? 1 :0;
            readingsBulkUpdate($hash,"present",$present);
            $state .= "present: $present";
            my $bus= OWDevice_ReadFromServer($hash,"find",$address);
            my $location= (defined($bus)) ? $bus :"absent";
            readingsBulkUpdate($hash,"location",$location);
          }
          $state =~ s/\s+$//;
          readingsBulkUpdate($hash,"state",$state,0);
          readingsEndUpdate($hash,1);
        }
        RemoveInternalTimer($hash);
        InternalTimer(int(gettimeofday())+$hash->{fhem}{interval}, "OWDevice_UpdateValues", $hash, 0)
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
            Log3 $name, 5, "$name: polls: " . join(" ", @polls);
        } elsif($attrName eq "interfaces") {
            if($attrVal ne "") {
              $hash->{fhem}{interfaces}= join(";",split(",",$attrVal));
              Log3 $name, 5, "$name: interfaces: " . $hash->{fhem}{interfaces};
            } else {
              delete $hash->{fhem}{interfaces} if(defined($hash->{fhem}{interfaces}));
              Log3 $name, 5, "$name: no interfaces";
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
        } elsif ($cmdname eq "interval") {
          return "Wrong interval format: Only digits are allowed!"
            if($value !~ m/^\d+$/);
          if($value == $hash->{fhem}{interval}) {
            return "new interval is equal to old interval.";
          } else {
            RemoveInternalTimer($hash);
            $hash->{fhem}{interval}= $value;
            InternalTimer(int(gettimeofday())+$hash->{fhem}{interval}, "OWDevice_UpdateValues", $hash, 0);
            return undef;
          }
        } else {
          return "Unknown argument $cmdname, choose one of interval " . join(" ", @setters);
        }
}

#############################
sub
OWDevice_Undef($$)
{
  my ($hash, $name) = @_;

  delete($modules{OWDevice}{defptr}{$hash->{NAME}});
  RemoveInternalTimer($hash);

  return undef;
}

#############################
sub
OWDevice_Define($$)
{
        my ($hash, $def) = @_;
        my @a = split("[ \t]+", $def);

        return "Usage: define <name> OWDevice <address> [interval]"  if($#a < 2|| $#a > 3);
        my $name= $a[0];

        AssignIoPort($hash) if(!defined($hash->{IODev}->{NAME}));
        if(defined($hash->{IODev}->{NAME})) {
          Log3 $name,  4, "$name: I/O device is " . $hash->{IODev}->{NAME};
        } else {
          Log3 $name, 1, "$name: no I/O device";
        }

        $hash->{fhem}{address}= $a[2];
        if($#a == 3) {
          $hash->{fhem}{interval}= $a[3];
          Log3 $name, 5, "$name: polling every $a[3] seconds";
        }
        my ($interface, $gettersref, $settersref, $pollsref, $stateref, $alerting)= OWDevice_GetDetails($hash);
        my @getters= @{$gettersref};
        my @setters= @{$settersref};
        my @polls= @{$pollsref};
        my @state= @{$stateref};
        if($interface ne "") {
          $hash->{fhem}{interfaces}= $interface;
          Log3 $name, 5, "$name: interfaces: $interface";
        }
        $hash->{fhem}{getters}= $gettersref;
        Log3 $name, 5, "$name: getters: " . join(" ", @getters);
        $hash->{fhem}{setters}= $settersref;
        Log3 $name, 5, "$name: setters: " . join(" ", @setters);
        $hash->{fhem}{polls}= $pollsref;
        Log3 $name, 5, "$name: polls: " . join(" ", @polls);
        $hash->{fhem}{state}= $stateref;
        Log3 $name, 5, "$name: state: " . join(" ", @state);
        $hash->{fhem}{alerting}= $alerting;
        Log3 $name, 5, "$name: alerting: $alerting";

        $hash->{fhem}{bus}= OWDevice_ReadFromServer($hash,"find",$hash->{fhem}{address});
        $attr{$name}{model}= OWDevice_ReadValue($hash, "type");
        if($interface eq "id" && !defined($hash->{fhem}{interval})) {
          my $dir= OWDevice_ReadFromServer($hash,"dir","/");
          my $present= ($dir =~ m/$hash->{fhem}{address}/) ? 1 :0;
          my $bus= OWDevice_ReadFromServer($hash,"find",$hash->{fhem}{address});
          my $location= (defined($bus)) ? $bus :"absent";
          my $id= OWDevice_Get($hash, $name, "id");
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"id",$id);
          readingsBulkUpdate($hash,"present",$present);
          readingsBulkUpdate($hash,"state","present: $present",0);
          readingsBulkUpdate($hash,"location",$location);
          readingsEndUpdate($hash,1);
        }

        if( $init_done ) {
          delete $modules{OWDevice}{NotifyFn};
          OWDevice_UpdateValues($hash) if(defined($hash->{fhem}{interval}));
        }

        return undef;
}

sub
OWDevice_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  return if($dev->{NAME} ne "global" ||
            !grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}));

  return if($attr{$name} && $attr{$name}{disable});

  delete $modules{OWDevice}{NotifyFn};

  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "OWDevice");
    OWDevice_UpdateValues($defs{$d}) if(defined($defs{$d}->{fhem}{interval}));
  }

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
      <li>DS2401 - Silicon Serial Number</li>
      <li>DS1990A - Serial Number iButton</li>
      <li>DS2405 - Addressable Switch</li>
      <li>DS18S20 - High-Precision 1-Wire Digital Thermometer</li>
      <li>DS1920 - iButton version of the thermometer</li>
      <li>DS2406, DS2407 - Dual Addressable Switch with 1kbit Memory</li>
      <li>DS2436 - Battery ID/Monitor Chip</li>
      <li>DS2423 - 4kbit 1-Wire RAM with Counter</li>
      <li>DS2450 - Quad A/D Converter</li>
      <li>DS1822 - Econo 1-Wire Digital Thermometer</li>
      <li>DS2415 - 1-Wire Time Chip</li>
      <li>DS1904 - RTC iButton</li>
      <li>DS2438 - Smart Battery Monitor</li>
      <li>DS2417 - 1-Wire Time Chip with Interrupt</li>
      <li>DS18B20 - Programmable Resolution 1-Wire Digital Thermometer</li>
      <li>DS2408 - 1-Wire 8 Channel Addressable Switch</li>
      <li>DS2413 - Dual Channel Addressable Switch</li>
      <li>DS1825 - Programmable Resolution 1-Wire Digital Thermometer with ID</li>
      <li>EDS0066 - Multisensor for temperature and pressure</li>
      <li>LCD - LCD controller by Louis Swart</li>
    </ul>
    <br><br>
    Adding more devices is simple. Look at the code (subroutine <code>OWDevice_GetDetails</code>).
    <br><br>
    This module is completely unrelated to the 1-wire modules with names all in uppercase.
    <br><br>
    <b>Note:</b>The state reading never triggers events to avoid confusion.<br><br>

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
    <li><code>set &lt;name&gt; interval &lt;value&gt;</code>
      <br><br>
      <code>value</code> modifies the interval for polling data. The unit is in seconds.
    </li>
    <li><code>set &lt;name&gt; &lt;reading&gt; &lt;value&gt;</code>
      <br><br>
      Sets &lt;reading&gt; to &lt;value&gt; for the 1-wire device &lt;name&gt;. The permitted values are defined by the underlying
      1-wire device type.
      <br><br>
      Example:
      <ul>
        <code>set myT1 templow 5</code><br>
      </ul>
      <br>
    </li>
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
    <li>resolution: resolution of temperature reading in bits, can be 9, 10, 11 or 12. 
    Lower resolutions allow for faster retrieval of values from the bus. 
    Particularly reasonable for large 1-wire installations to reduce busy times for FHEM.</li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>


</ul>




=end html
=cut
