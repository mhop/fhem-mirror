#################################################################################
# 46_Sense.pm
#
# FHEM module Plugwise motion scanners
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
# $Id: 46_sense.pm 0037 2015-11-09 19:18:38Z sguttmann $ 
package main;

use strict;
use warnings;
use Data::Dumper;

my $time_old = 0;

my $DOT = q{_};

sub Sense_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "Sense";
  $hash->{DefFn}     = "Sense_Define";
  $hash->{UndefFn}   = "Sense_Undef";
  $hash->{ParseFn}   = "Sense_Parse";
  $hash->{SetFn}     = "Sense_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ".
                       $readingFnAttributes;

  Log3 $hash, 5, "Sense_Initialize() Initialize";
}

#####################################
sub Sense_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $a = int(@a);

  Log3 $hash,5,"Sense: Define called --> $def";

  return "wrong syntax: define <name> Sense address" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2];
  my $device_name = "Sense".$DOT.$code;

  $hash->{CODE} = $code;
  $modules{Sense}{defptr}{$device_name} = $hash;
  AssignIoPort($hash);
  if( $init_done ) {
  	$attr{$name}{room}='Plugwise';
        }

  return undef;
}

#####################################
sub Sense_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{Sense}{defptr}{$name});
  return undef;
}

sub Sense_Set($@)
{
	my ( $hash, @a ) = @_;
	return "\"set X\" needs at least an argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt = shift @a;
	my $value = join("", @a);

	Log3 $hash,5,"$hash->{NAME} - Sense-Set: N:$name O:$opt V:$value";
	
	if ($opt eq "removeNode") {
		IOWrite($hash,$hash->{CODE},$opt);
	} elsif ($opt eq "ping") {
		IOWrite($hash,$hash->{CODE},$opt);
	}
	else
        {
          return "Unknown argument $opt, choose one removeNode ping";
        }
}

sub Sense_Parse($$)
{
 my ($hash, $msg2) = @_;
  my $msg=$hash->{RAWMSG};
#Log 3,"Sense: got a msg";

  my $time = time();
  if ($msg->{type} eq "err") {return undef};

  Log3 $hash,5,"Sense: Parse called ".$msg->{short};

  $time_old = $time;
  Log3 $hash,5, Dumper($msg);
  my $device_name = "Sense".$DOT.$msg->{short};
  Log3 $hash,5,"New Devicename: $device_name";
  my $def = $modules{Sense}{defptr}{"$device_name"};
  if(!$def) {
        Log3 $hash, 3, "Sense: Unknown device $device_name, please define it";
        return "UNDEFINED $device_name Sense $msg->{short}";
  }
  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};

  my $type = $msg->{type};
  Log3 $hash,5,"Sense: Type is '$type'";
  Log3 $hash,5,Dumper($msg);

  readingsBeginUpdate($def);

  if($type eq "humtemp") {
    readingsBulkUpdate($def, "temperature", $msg->{val2});
    readingsBulkUpdate($def, "humidity", $msg->{val1});
  }
  if($type eq "Sense") {
    readingsBulkUpdate($def, "Sense", ($msg->{val1}) eq 0 ? 'off' : 'on');
  }
  readingsEndUpdate($def, 1);
  
  return $name;
   }

"Cogito, ergo sum.";

=pod
=begin html

<a name="Sense"></a>
<h3>Sense</h3>
<ul>
  The Sense module is invoked by Plugwise. You need to define a Plugwise-Stick first. 
See <a href="#Sense">Sense</a>.
  <br>
  <a name="Sense define"></a>
  <br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Sense &lt;ShortAddress&gt;</code> <br>
    <br>
    <code>&lt;ShortAddress&gt;</code>
    <ul>
      specifies the short (last 4 Bytes) of the Sense received by the Plugwise-Stick. <br>
    </ul>
    <br>
      Example: <br>
    	<code>define Sense_2907CC9 Sense 2907CC9</code>
      <br>
  </ul>
  <br>
</ul>

=end html
=cut

