#################################################################################
# 46_Scan.pm
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
# $Id: 46_scan.pm 0037 2015-11-09 19:18:38Z sguttmann $ 
package main;

use strict;
use warnings;
use Data::Dumper;

my $time_old = 0;

my $DOT = q{_};

sub Scan_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "Scan";
  $hash->{DefFn}     = "Scan_Define";
  $hash->{UndefFn}   = "Scan_Undef";
  $hash->{ParseFn}   = "Scan_Parse";
  $hash->{SetFn}     = "Scan_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ".
                       $readingFnAttributes;

  Log3 $hash, 5, "Scan_Initialize() Initialize";
}

#####################################
sub Scan_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $a = int(@a);

  Log3 $hash,5,"Scan: Define called --> $def";

  return "wrong syntax: define <name> Scan address" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2];
  my $device_name = "Scan".$DOT.$code;

  $hash->{CODE} = $code;
  $modules{Scan}{defptr}{$device_name} = $hash;
  AssignIoPort($hash);
  if( $init_done ) {
  	$attr{$name}{room}='Plugwise';
        }

  return undef;
}

#####################################
sub Scan_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{Scan}{defptr}{$name});
  return undef;
}

sub Scan_Set($@)
{
	my ( $hash, @a ) = @_;
	return "\"set X\" needs at least an argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt = shift @a;
	my $value = join("", @a);

	Log3 $hash,5,"$hash->{NAME} - Scan-Set: N:$name O:$opt V:$value";
	
	if ($opt eq "removeNode") {
		IOWrite($hash,$hash->{CODE},$opt);
	} elsif ($opt eq "ping") {
		IOWrite($hash,$hash->{CODE},$opt);
	}
	else
        {
          return "Unknown argument $opt, choose one of removeNode ping";
        }
}

sub Scan_Parse($$)
{
 my ($hash, $msg2) = @_;
  my $msg=$hash->{RAWMSG};
#Log 3,"SCAN: got a msg";

  my $time = time();
  if ($msg->{type} eq "err") {return undef};

  Log3 $hash,5,"Scan: Parse called ".$msg->{short};

  $time_old = $time;
  Log3 $hash,5, Dumper($msg);
  my $device_name = "Scan".$DOT.$msg->{short};
  Log3 $hash,5,"New Devicename: $device_name";
  my $def = $modules{Scan}{defptr}{"$device_name"};
  if(!$def) {
        Log3 $hash, 3, "Scan: Unknown device $device_name, please define it";
        return "UNDEFINED $device_name Scan $msg->{short}";
  }
  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};

  my $type = $msg->{type};
  Log3 $hash,5,"Scan: Type is '$type'";
  Log3 $hash,5,Dumper($msg);

  readingsBeginUpdate($def);
  Log3 $hash,5,Dumper($msg);

  if($type eq "sense") {
    readingsBulkUpdate($def, "state", ($msg->{val1} eq 0 ? 'off' : 'on' ));
  }
  
  readingsEndUpdate($def, 1);
  
  return $name;
   }

"Cogito, ergo sum.";

=pod
=begin html

<a name="Scan"></a>
<h3>Scan</h3>
<ul>
  The Scan module is invoked by Plugwise. You need to define a Plugwise-Stick first. 
See <a href="#Scan">Scan</a>.
  <br>
  <a name="Scan define"></a>
  <br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Scan &lt;ShortAddress&gt;</code> <br>
    <br>
    <code>&lt;ShortAddress&gt;</code>
    <ul>
      specifies the short (last 4 Bytes) of the Scan received by the Plugwise-Stick. <br>
    </ul>
    <br>
      Example: <br>
    	<code>define Scan_2907CC9 Scan 2907CC9</code>
      <br>
  </ul>
  <br>
</ul>

=end html
=cut

