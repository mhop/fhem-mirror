#################################################################################
# 46_PW_Switch.pm
#
# FHEM module Plugwise switches
#
# Copyright (C) 2015 Stefan Guttmann
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# The GNU General Public License may also be found at http://www.gnu.org/licenses/gpl-2.0.html .
###################################
#
# $Id$ 
package main;

use strict;
use warnings;
use Data::Dumper;

my $time_old = 0;

my $DOT = q{_};

sub PW_Switch_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "PW_Switch";
  $hash->{DefFn}     = "PW_Switch_Define";
  $hash->{UndefFn}   = "PW_Switch_Undef";
  $hash->{ParseFn}   = "PW_Switch_Parse";
  $hash->{SetFn}     = "PW_Switch_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ".
                       $readingFnAttributes;

  Log3 $hash, 5, "PW_Switch_Initialize() Initialize";
}

#####################################
sub PW_Switch_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $a = int(@a);

  Log3 $hash,5,"PW_Switch: Define called --> $def";

  return "wrong syntax: define <name> PW_Switch address" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2];
  my $device_name = "PW_Switch".$DOT.$code;

  $hash->{CODE} = $code;
  $modules{PW_Switch}{defptr}{$device_name} = $hash;
  AssignIoPort($hash);
  if( $init_done ) {
  	$attr{$name}{room}='Plugwise';
        }

  return undef;
}

#####################################
sub PW_Switch_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{PW_Switch}{defptr}{$name});
  return undef;
}

sub PW_Switch_Set($@)
{
	my ( $hash, @a ) = @_;
	return "\"set X\" needs at least an argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt = shift @a;
	my $value = join("", @a);

	Log3 $hash,5,"$hash->{NAME} - PW_Switch-Set: N:$name O:$opt V:$value";
	
	if($opt =~ /(o2n|o2ff)/) {
	     if ($value =~/(left|right)/) {IOWrite($hash,$hash->{CODE},$opt,$value);}
	     
    } elsif ($opt eq "getLog")
    {
         IOWrite($hash,$hash->{CODE},$opt,$value);
    } elsif ($opt eq "syncTime") {
		IOWrite($hash,$hash->{CODE},$opt);
	} elsif ($opt eq "removeNode") {
		IOWrite($hash,$hash->{CODE},$opt);
	} elsif ($opt eq "ping") {
		IOWrite($hash,$hash->{CODE},$opt);
	}
	else
        {
          return "Unknown argument $opt, choose one of syncTime removeNode ping";
        }
}

sub PW_Switch_Parse($$)
{
 my ($hash, $msg2) = @_;
  my $msg=$hash->{RAWMSG};
#Log 3,"PW_Switch: got a msg";

  my $time = time();
  if ($msg->{type} eq "err") {return undef};

  Log3 $hash,5,"PW_Switch: Parse called ".$msg->{short};

  $time_old = $time;
  my $device_name = "PW_Switch".$DOT.$msg->{short};
  Log3 $hash,5,"New Devicename: $device_name";
  my $def = $modules{PW_Switch}{defptr}{"$device_name"};
  if(!$def) {
        Log3 $hash, 3, "PW_Switch: Unknown device $device_name, please define it";
        return "UNDEFINED $device_name PW_Switch $msg->{short}";
  }
  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};

  my $type = $msg->{type};

  readingsBeginUpdate($def);

  if($type eq "humtemp") {
    readingsBulkUpdate($def, "temperature", $msg->{val2});
    readingsBulkUpdate($def, "humidity", $msg->{val1});
  }
  if($type eq "sense") {
#    readingsBulkUpdate($def, "key_left", $msg->{val1}) if (ReadingsVal($name,"key_left","-") ne $msg->{val1});
#    readingsBulkUpdate($def, "key_right", $msg->{val2}) if (ReadingsVal($name,"key_right","-") ne $msg->{val2});
	readingsBulkUpdate($def, "state", "on") if ($msg->{val1}==1 && ReadingsVal($def,"state","0") ne "on");
	readingsBulkUpdate($def, "state", "off") if ($msg->{val1}==0 && ReadingsVal($def,"state","0") ne "off");
  }

  readingsEndUpdate($def, 1);
  
  return $name;
   }

"Cogito, ergo sum.";

=pod
=item device
=item summary    Submodule for 45_Plugwise
=item summary_DE Untermodul zu 45_Plugwise
=begin html

<a name="PW_Switch"></a>
<h3>PW_Switch</h3>
<ul>
  The PW_Switch module is invoked by Plugwise. You need to define a Plugwise-Stick first. 
See <a href="#PW_Switch">PW_Switch</a>.
  <br>
  <a name="PW_Switch define"></a>
  <br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PW_Switch &lt;ShortAddress&gt;</code> <br>
    <br>
    <code>&lt;ShortAddress&gt;</code>
    <ul>
      specifies the short (last 4 Bytes) of the Circle received by the Plugwise-Stick. <br>
    </ul>
    <br>
      Example: <br>
    	<code>define PW_Switch_2907CC9 PW_Switch 2907CC9</code>
      <br>
  </ul>
  <b>Set</b>
  <ul>
    <code>syncTime</code> <br>
    <ul>
      Syncronises the internal clock of the Circle with your PC's clock<br><br>
    </ul>
    <code>removeNode</code> <br>
    <ul>
      Removes this device from your Plugwise-network<br><br>
    </ul>
    <code>ping</code> <br>
    <ul>
      Ping the circle and write the Ping-Runtime to reading "ping" in format "q_in - q_out - pingTime"<br><br>
    </ul>
    </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="PW_Switch"></a>
<h3>PW_Switch</h3>
<ul>
  Das PW_Switch Module basiert auf dem Plugwise-System. Es muss zuerst ein Plugwise-Stick angelegt werden. 
Siehe <a href="#PW_Switch">PW_Switch</a>.
  <br>
  <a name="PW_Switch define"></a>
  <br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PW_Switch &lt;ShortAddress&gt;</code> <br>
    <br>
    <code>&lt;ShortAddress&gt;</code>
    <ul>
      gibt die Kurzadresse (die letzten 4 Bytes) des Circles an. <br>
    </ul>
    <br>
      Beispiel: <br>
    	<code>define PW_Switch_2907CC9 PW_Switch 2907CC9</code>
      <br>
  </ul><br>
    <b>Set</b>
  <ul>
    <code>syncTime</code> <br>
    <ul>
      Synchronisiert die interne Uhr des Circles mit der lokalen Systemzeit<br><br>
    </ul>
    <code>removeNode</code> <br>
    <ul>
      Entfernt den Circle aus dem Plugwise-Netzwerk<br><br>
    </ul>
    <code>ping</code> <br>
    <ul>
      Sendet ein Ping an den Circle und setzt das Reading "ping" im Format "q_in - q_out - pingZeit"<br><br>
    </ul>
    </ul>
  <br>
</ul>

=end html_DE
=cut

