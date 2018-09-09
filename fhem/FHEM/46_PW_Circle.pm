#################################################################################
# 46_PW_Circle.pm
#
# FHEM module Plugwise PW_Circle
#
# Copyright (C) 2014 Stefan Guttmann
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
# # $Id$
package main;

use strict;
use warnings;
use Data::Dumper;

my $time_old = 0;

my $DOT = q{_};

my %Subtype = (
    "Stealth"     => 02,
    "Circle"	  => 01,
    "Unknown"	  => 00
  );
  
  my %PW_gets = (
	"livepower"	=> 'Z'
  );  
  
sub PW_Circle_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "PW_Circle";
  $hash->{DefFn}     = "PW_Circle_Define";
  $hash->{UndefFn}   = "PW_Circle_Undef";
  $hash->{ParseFn}   = "PW_Circle_Parse";
  $hash->{SetFn}     = "PW_Circle_Set";
  $hash->{GetFn}     = "PW_Circle_Get";
  $hash->{AttrList}  = "IODev interval do_not_notify:1,0 ".
                       $readingFnAttributes;
  $hash->{AutoCreate} =
        { "PW_Circle.*" => { ATTR => "room:Plugwise interval:10"} };

#  Log3 $hash, 3, "PW_Circle_Initialize() Initialize";
}

#####################################
sub PW_Circle_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $a = int(@a);
#Log 3,"Circle define $a[0]";
  return "wrong syntax: define <name> PW_Circle address" if(int(@a) != 3);
  my $name = $a[0];
  my $code = $a[2];
  my $device_name = "PW_Circle".$DOT.$code;
#Log 3,Dumper($hash);

  $hash->{CODE} = $code;
  $modules{PW_Circle}{defptr}{$device_name} = $hash;
  AssignIoPort($hash);
#  	$attr{$name}{interval}=$hash->{NAME}{interval};
  if( $init_done ) {
#  	$attr{$name}{room}='Plugwise';
#  	$attr{$name}{interval}=$hash->{NAME}{interval};
        }
#  PW_InternalTimer($code,gettimeofday()+2, "Circles_GetLog", $hash, 0);
	InternalTimer(gettimeofday()+2, "PW_Circle_GetLog", 'getLog:'.$name, 1);
  return undef;
}

sub PW_Circle_GetLog($){
  	my($in ) = shift;
  	my(undef,$name) = split(':',$in);
  	return if (!$name || !defined $defs{$name});
	my $hash=$defs{$name};
    my $IOName = $hash->{IODev}->{NAME};
#  	my $name = $hash->{NAME};
	my $int = AttrVal($name,"interval",undef);
	if (!defined($int)) {$int = AttrVal($IOName,"interval",undef);}
#  	Log 3,"Get Info from Circle $name on interval $int";
  	IOWrite($hash,$hash->{CODE},"status");
  	IOWrite($hash,$hash->{CODE},"livepower");
	InternalTimer(gettimeofday()+$int, "PW_Circle_GetLog", 'getLog:'.$name, 0) if defined($int);
}

#####################################
sub PW_Circle_Undef($$)
{
  my ($hash, $name) = @_;
 	RemoveInternalTimer("onofffortimer:".$name.":off");
 	RemoveInternalTimer("onofffortimer:".$name.":on");
 	RemoveInternalTimer("getLog:".$name);
  delete($modules{PW_Circle}{defptr}{$name});
  return undef;
}

sub PW_Circle_Set($@)
{
	my ( $hash, @a ) = @_;
	return "\"set X\" needs at least an argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt = shift @a;
	my $value = join("", @a);

	#Log3 $hash,3,"$hash->{NAME} - Circle-Set: N:$name O:$opt V:$value";
	
	if($opt eq "on"||$opt eq "off")  
    {
		IOWrite($hash,$hash->{CODE},$opt);
    } elsif ($opt eq "toggle") {
		$opt = ReadingsVal($name,"state","off") eq "off" ? "on" : "off";
		IOWrite($hash,$hash->{CODE},$opt);    	
    }elsif($opt =~ "(on|off)-for-timer")  
    {
    	if (@a == 1) {
			IOWrite($hash,$hash->{CODE},$1);
		 	RemoveInternalTimer("onofffortimer:".$name.":off");
		 	RemoveInternalTimer("onofffortimer:".$name.":on");
        	InternalTimer(gettimeofday()+$value, "PW_Circle_OnOffTimer", 'onofffortimer:'.$name.':' . ($1 eq "on"?"off":"on"), 1);
    	}
    } elsif ($opt eq "getLog") {
    	IOWrite($hash,$hash->{CODE},$opt,$value) if (@a == 3);
    } elsif ($opt eq "syncTime") {
		IOWrite($hash,$hash->{CODE},$opt);
    } elsif ($opt eq "removeNode") {
		IOWrite($hash,$hash->{CODE},$opt);
	} elsif ($opt eq "ping") {
		IOWrite($hash,$hash->{CODE},$opt);
	} elsif ($opt eq "status") {
		IOWrite($hash,$hash->{CODE},$opt);
	}
	else
        {
          return "Unknown argument $opt, choose one of on-for-timer off-for-timer on off getLog syncTime removeNode ping status";
        }
}
sub PW_Circle_OnOffTimer($) {
  	my($in ) = shift;
  	my(undef,$name,$pwr) = split(':',$in);
  	return if (!$name || !defined $defs{$name});
  	my $hash=$defs{$name};
  	IOWrite($hash,$hash->{CODE},$pwr);
}

sub PW_Circle_Get($@)
{
#	 elsif ($opt eq "livepower") {
#		IOWrite($hash,$hash->{CODE},$opt);
#	} 
	my ( $hash, @a ) = @_;
        my $n=1;
	return "\"get X\" needs at least one argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt = shift @a;
	if(!$PW_gets{$opt}) {
		my @cList = keys %PW_gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
    if($opt eq 'livepower') {
    	IOWrite($hash,$hash->{CODE},$opt);
    }
}
sub PW_Circle_Parse($$)
{
  my ($hash, $msg2) = @_;
  #Log 3,Dumper($msg2);
  my $msg=$hash->{RAWMSG};
  my $time = time();
#  RemoveInternalTimer($hash);
#  InternalTimer(gettimeofday()+3, "Circles_GetLog", $hash, 0);
#  Log 3,"SetTimer";
 #Log3 $hash,3,"Circles: Parse called ".$msg->{short};
if ($msg->{type} eq "err") {return undef};
#  Log 3,Dumper($hash->{RAWMSG});
  
  $time_old = $time;
  Log3 $hash,5, Dumper($msg);
  my $device_name = "PW_Circle".$DOT.$msg->{short};
  Log3 $hash,5,"New Devicename: $device_name";
  my $def = $modules{PW_Circle}{defptr}{"$device_name"};
  if(!$def) {
        Log3 $hash, 3, "PW_Circle: Unknown device $device_name, please define it";
        return "UNDEFINED $device_name PW_Circle $msg->{'short'}";
  }
  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};

  $hash->{helper}{circles}{$name}{lastContact}=time;
  $hash->{helper}{circles}{$name}{name}=$msg->{short};
  
#	Log 3,Dumper($hash->{helper});
  my $type = $msg->{type};
  Log3 $hash,5,"Circle: Type is '$type'";

  readingsBeginUpdate($def);
  Log3 $hash,5,Dumper($msg);

  if($type eq "output") {
    readingsBulkUpdate($def, "state", $msg->{text}) if (ReadingsVal($name,"state","off") ne $msg->{text});
    if ($msg->{text} eq "offline") {return $name}
    my $nr = $msg->{val1};
    $nr--;
    IOWrite($def,$def->{CODE},"getLog",$nr) if (ReadingsVal($name,"address","-") ne $nr);
  }

  if($type eq "ping") {
	readingsBulkUpdate($def, "ping", "$msg->{val1} - $msg->{val2} - $msg->{val3}");
  }
  if($type eq "power") {
      if ($msg->{val2} < 17000) {
           readingsBulkUpdate($def, "power", $msg->{val1});
           readingsBulkUpdate($def, "power8", $msg->{val2});
      } else
      {
           readingsBulkUpdate($def, "IgnoredSpikes",ReadingsVal($name,"IgnoredSpikes",0) + 1);          
      }
  }

  if($type eq "energy") {
    readingsBulkUpdate($def, "energy", $msg->{val1});
    readingsBulkUpdate($def, "energy_ts", $msg->{val2});
    readingsBulkUpdate($def, "address", $msg->{val3})
  }
  
#2015.09.11 05:56:25 3: $VAR1 = {
#          'code' => '0013C40B000D6F0002907CC90000000200000376FFFF8C180007',
#          'dest' => 'Circle',
#          'device' => '000D6F0002907CC9',
#          'schema' => 'plugwise.basic',
#          'short' => '2907CC9',
#          'text' => '',
#          'type' => 'power',
#          'unit1' => 'W',
#          'unit2' => 'W',
#          'val1' => '0',
#          'val2' => '1'
#        };

#2015.09.11 05:56:25 3: $VAR1 = {
#          'code' => '0024C40C000D6F0002907CC90F09392A0006A05801856539070140264E0844C202',
#          'dest' => 'Circle',
#          'device' => '000D6F0002907CC9',
#          'schema' => 'plugwise.basic',
#          'short' => '2907CC9',
#          'text' => 'on',
#          'type' => 'output',
#          'val1' => '19467',
#          'val2' => '2015-09-11 03:54'
#        };

  readingsEndUpdate($def, 1);
  
  return $name;
   }


"Cogito, ergo sum.";

=pod
=item device
=item summary    Submodule for 45_Plugwise
=item summary_DE Untermodul zu 45_Plugwise
=begin html

<a name="PW_Circle"></a>
<h3>PW_Circles</h3>
<ul>
  The PW_Circles module is invoked by Plugwise. You need to define a Plugwise-Stick first. 
See <a href="#Plugwise">Plugwise</a>.
  <br>
  <a name="PW_Circle define"></a>
  <br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PW_Circle &lt;ShortAddress&gt;</code> <br>
    <br>
    <code>&lt;ShortAddress&gt;</code>
    <ul>
      specifies the short (last 4 Bytes) of the Circle received by the Plugwise-Stick. <br>
    </ul>
  <br><br>    
  </ul>
  <b>Set</b>
  <ul>
    <code>on / off</code> <br>
    <ul>
      Turns the circle on or off<br><br>
    </ul>
    <code>on-for-timer / off-for-timer sec</code> <br>
    <ul>
      Turns the circle on or off for a given interval<br><br>
    </ul>
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
    <code>status</code> <br>
    <ul>
      Gets the current state of this cirle.<br><br>
    </ul>
    </ul>
    
  <br><br>
  
  <b>Attributes</b>
  <ul>
    <code>interval</code> <br>
    <ul>
      specifies the polling time for this circle<br>
    </ul>
    </ul>
    <br><br>
      <b>Example</b> <br>
    	<ul><code>define Circle_2907CC9 PW_Circle 2907CC9</code></ul>
      <br>
  
  <br>
</ul>

=end html

=begin html_DE

<a name="PW_Circle"></a>
<h3>PW_Circles</h3>
<ul>
  Das PW_Circles Modul setzt auf das Plugwise-System auf. Es muss zuerst ein Plugwise-Stick angelegt werden. 
  Siehe <a href="#Plugwise">Plugwise</a>.
  <br>
  <a name="PW_Circle define"></a>
  <br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PW_Circle &lt;ShortAddress&gt;</code> <br>
    <br>
    <code>&lt;ShortAddress&gt;</code>
    <ul>
      gibt die Kurzadresse (die letzten 4 Bytes) des Circles an. <br>
    </ul>
  <br><br>    
  </ul>
  <b>Set</b>
  <ul>
    <code>on / off</code> <br>
    <ul>
      Schaltet den Circle ein oder aus<br><br>
    </ul>
    <code>on-for-timer / off-for-timer sec</code> <br>
    <ul>
      Schaltet den Circle für n Sekunden an oder aus<br><br>
    </ul>
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
    <code>status</code> <br>
    <ul>
      Liest den aktuellen Status des Circles aus<br><br>
    </ul>
    </ul>
    
  <br><br>
  
  <b>Attribute</b>
  <ul>
    <code>interval</code> <br>
    <ul>
      Setzt das Abruf-Intervall speziell für diesen einen Circle<br>
    </ul>
    </ul>
    <br><br>
      <b>Beispiel</b> <br>
    	<ul><code>define Circle_2907CC9 PW_Circle 2907CC9</code></ul>
      <br>
  
  <br>
</ul>

=end html
=cut

