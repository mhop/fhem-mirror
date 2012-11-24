# $Id$
##############################################################################
#
#     72_FB_CALLMONITOR.pm
#     Connects to a FritzBox Fon via network.
#     When a call is received or takes place it creates an event with further call informations.
#     This module has no sets or gets as it is only used for event triggering.
#
#     Copyright by Markus Bloch
#     e-mail: Notausstieg0309@googlemail.com
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
use Time::HiRes qw(gettimeofday);

my %connection_type = (
0 => "0",
1 => "FON1",
2 => "FON2",
3 => "FON3",
4 => "ISDN",
5 => "FAX",
6 => "not_defined",
7 => "not_defined",
8 => "not_defined",
9 => "not_defined",
10 => "DECT_1",
11 => "DECT_2",
12 => "DECT_3",
13 => "DECT_4",
14 => "DECT_5",
15 => "DECT_6",
16 => "FRITZMini_1",
17 => "FRITZMini_2",
18 => "FRITZMini_3",
19 => "FRITZMini_4",
20 => "VoIP_1",
21 => "VoIP_2",
22 => "VoIP_3",
23 => "VoIP_4",
24 => "VoIP_5",
25 => "VoIP_6",
26 => "VoIP_7",
27 => "VoIP_8",
28 => "VoIP_9",
29 => "VoIP_10",
40 => "Answering_Machine_1",
41 => "Answering_Machine_2",
42 => "Answering_Machine_3",
43 => "Answering_Machine_4",
44 => "Answering_Machine_5"
);




sub
FB_CALLMONITOR_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "FB_CALLMONITOR_Read";  
  $hash->{ReadyFn} = "FB_CALLMONITOR_Ready";
  $hash->{DefFn}   = "FB_CALLMONITOR_Define";
  $hash->{UndefFn} = "FB_CALLMONITOR_Undef";
  $hash->{AttrList}= "event-on-update-reading event-on-change-reading";

}

#####################################
sub
FB_CALLMONITOR_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> FB_CALLMONITOR ip[:port]";
    Log 2, $msg;
    return $msg;
  }
  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  $dev .= ":1012" if($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);




  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "FB_CALLMONITOR_DoInit");

  return $ret;
}


#####################################
sub
FB_CALLMONITOR_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};



  DevIo_CloseDev($hash); 
  return undef;
}



#####################################
# No get commands possible, as we just receive the events from the FritzBox.
sub
FB_CALLMONITOR_ReadAnswer($$$)
{

return "Get command is not supported by this module";

}

#####################################
# Receives an event and creates several readings for event triggering
sub
FB_CALLMONITOR_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};
  my @array;
  my $data = "";
  $data .= $buf;

 
   @array = split(";", $data);
   readingsBeginUpdate($hash);
   readingsBulkUpdate($hash, "event", lc($array[1]));
   readingsBulkUpdate($hash, "external_number", $array[3]) if(not $array[3] eq "0" and $array[1] eq "RING");
   readingsBulkUpdate($hash, "internal_number", $array[4]) if($array[1] eq "RING");
   readingsBulkUpdate($hash, "external_number" , $array[5]) if($array[1] eq "CALL");
   readingsBulkUpdate($hash, "internal_number", $array[4]) if($array[1] eq "CALL");
   readingsBulkUpdate($hash, "external_connection", $array[5]) if($array[1] eq "RING");
   readingsBulkUpdate($hash, "external_connection", $array[6]) if($array[1] eq "CALL");
   readingsBulkUpdate($hash, "internal_connection", $connection_type{$array[3]}) if($array[1] eq "CALL" or $array[1] eq "CONNECT" and defined($connection_type{$array[3]}));
   readingsBulkUpdate($hash, "call_duration", $array[3]) if($array[1] eq "DISCONNECT");
   readingsEndUpdate($hash, 1);
  
}

sub
FB_CALLMONITOR_DoInit($)
{

# No Initialization needed
return undef;

}


sub
FB_CALLMONITOR_Ready($)
{
   my ($hash) = @_;
   
   return DevIo_OpenDev($hash, 1, "FB_CALLMONITOR_DoInit");

}

1;

=pod
=begin html

<a name="FB_CALLMONITOR"></a>
<h3>FB_CALLMONITOR</h3>
<ul>
  <tr><td>
  The FB_CALLMONITOR module connects to a AVM FritzBox Fon and listens for telephone
  <a href="#FB_CALLMONITORevents">events</a> (Receiving incoming call, Making a call)
  <br><br>
  In order to use this module with fhem you <b>must</b> enable the CallMonitor feature via 
  telephone shortcode.<br><br>
  <ul>
      <code>#96*5* - for activating<br>#96*4* - for deactivating</code>
  </ul>
  
  <br>
  Just dial the shortcode for activating on one of your phones, after 3 seconds just hang up. The feature is now activated.
  <br>
  After activating the CallMonitor-Support in your FritzBox, this module is able to 
  generate an event for each call.
  <br><br>
  This module work with any FritzBox Fon model.
  <br><br>
  
  <a name="FB_CALLMONITORdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FB_CALLMONITOR &lt;ip-address&gt;[:port]</code><br>
    <br>
    port is 1012 by default.
    <br>
  </ul>
  <br>
  <a name="FB_CALLMONITORset"></a>
  <b>Set</b>
  <ul>
  N/A 
  </ul>
  <br>

  <a name="FB_CALLMONITORget"></a>
  <b>Get</b>
  <ul>
  N/A
  </ul>
  <br>

  <a name="FB_CALLMONITORattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
  </ul>
  <br>
 
  <a name="FB_CALLMONITORevents"></a>
  <b>Generated Events:</b><br><br>
  <ul>
  <li><b>event</b>: (call|ring|connect|disconnect) - which event in detail was triggerd</li>
  <li><b>external_number</b>: $number - The participants number which is calling (event: ring) or beeing called (event: call)</li>
  <li><b>internal_number</b>: $number - The internal number (fixed line, VoIP number, ...) on which the participant is calling (event: ring) or is used for calling (event: call)</li>
  <li><b>internal_connection</b>: $connection - The internal connection (FON1, FON2, ISDN, DECT, ...) which is used to take the call</li>
  <li><b>external_connection</b>: $connection - The external connection (fixed line, VoIP account) which is used to take the call</li>
  <li><b>call_duration</b>: $seconds - The call duration in seconds. Is only generated at a disconnect event. The value 0 means, the call was not taken by anybody.</li>
  </ul>
</ul>


=end html
=cut
