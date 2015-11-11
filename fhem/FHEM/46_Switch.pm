#################################################################################
# 46_Switch.pm
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
# $Id: 46_Switch.pm 0037 2015-11-09 19:18:38Z sguttmann $ 
package main;

use strict;
use warnings;
use Data::Dumper;

my $time_old = 0;

my $DOT = q{_};

sub Switch_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "Switch";
  $hash->{DefFn}     = "Switch_Define";
  $hash->{UndefFn}   = "Switch_Undef";
  $hash->{ParseFn}   = "Switch_Parse";
  $hash->{SetFn}     = "Switch_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ".
                       $readingFnAttributes;

  Log3 $hash, 5, "Switch_Initialize() Initialize";
}

#####################################
sub Switch_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $a = int(@a);

  Log3 $hash,5,"Switch: Define called --> $def";

  return "wrong syntax: define <name> Switch address" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2];
  my $device_name = "Switch".$DOT.$code;

  $hash->{CODE} = $code;
  $modules{Switch}{defptr}{$device_name} = $hash;
  AssignIoPort($hash);
  if( $init_done ) {
  	$attr{$name}{room}='Plugwise';
        }

  return undef;
}

#####################################
sub Switch_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{Switch}{defptr}{$name});
  return undef;
}

sub Switch_Set($@)
{
	my ( $hash, @a ) = @_;
	return "\"set X\" needs at least an argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt = shift @a;
	my $value = join("", @a);

	Log3 $hash,5,"$hash->{NAME} - Switch-Set: N:$name O:$opt V:$value";
	
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

sub Switch_Parse($$)
{
 my ($hash, $msg2) = @_;
  my $msg=$hash->{RAWMSG};
#Log 3,"Switch: got a msg";

  my $time = time();
  if ($msg->{type} eq "err") {return undef};

  Log3 $hash,5,"Switch: Parse called ".$msg->{short};

  $time_old = $time;
  my $device_name = "Switch".$DOT.$msg->{short};
  Log3 $hash,5,"New Devicename: $device_name";
  my $def = $modules{Switch}{defptr}{"$device_name"};
  if(!$def) {
        Log3 $hash, 3, "Switch: Unknown device $device_name, please define it";
        return "UNDEFINED $device_name Switch $msg->{short}";
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
=begin html

<a name="Switch"></a>
<h3>Switch</h3>
<ul>
  The Switch module is invoked by Plugwise. You need to define a Plugwise-Stick first. 
See <a href="#Switch">Switch</a>.
  <br>
  <a name="Switch define"></a>
  <br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Switch &lt;ShortAddress&gt;</code> <br>
    <br>
    <code>&lt;ShortAddress&gt;</code>
    <ul>
      specifies the short (last 4 Bytes) of the Circle received by the Plugwise-Stick. <br>
    </ul>
    <br>
      Example: <br>
    	<code>define Circle_2907CC9 Switch 2907CC9</code>
      <br>
  </ul>
  <br>
</ul>

=end html
=cut

