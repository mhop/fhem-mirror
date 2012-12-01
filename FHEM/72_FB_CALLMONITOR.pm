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
use DevIo;
use HttpUtils;

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
  $hash->{AttrList}= "do_not_notify:0,1 reverse-search:all,klicktel,dasoertliche,none reverse-search-cache:0,1 event-on-update-reading event-on-change-reading";

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
  my $reverse_search = undef;
  my $data = $buf;
  
   @array = split(";", $data);
  
   $reverse_search = FB_CALLMONITOR_reverseSearch($hash, $array[3]) if(not $array[3] eq "0" and $array[1] eq "RING" and AttrVal($name, "reverse-search", "none") ne "none");
   $reverse_search = FB_CALLMONITOR_reverseSearch($hash, $array[5]) if($array[1] eq "CALL" and AttrVal($name, "reverse-search", "none") ne "none");
  
   
  
   readingsBeginUpdate($hash);
   readingsBulkUpdate($hash, "event", lc($array[1]));
   readingsBulkUpdate($hash, "external_number", $array[3]) if(not $array[3] eq "0" and $array[1] eq "RING");
   readingsBulkUpdate($hash, "external_name", $reverse_search) if(defined($reverse_search)); 
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

sub
FB_CALLMONITOR_reverseSearch($$)
{
my ($hash, $number) = @_;
my $name = $hash->{NAME};
my $result;
my $invert_match = undef;


# Using Cache if enabled
if(AttrVal($name, "reverse-search-cache", "0") eq "1")
{
   if(defined($hash->{helper}{CACHE}{$number}))
   {
      Log GetLogLevel($name, 4), "FB_CALLMONITOR $name using cache for reverse search of $number";
      if($hash->{helper}{CACHE}{$number} ne "timeout")
      {
         return ($hash->{helper}{CACHE}{$number} ne "unknown" ? $hash->{helper}{CACHE}{$number} : undef) ;
      }
   }
}

# Ask klicktel.de
if(AttrVal($name, "reverse-search", "none") eq "all" or AttrVal($name, "reverse-search", "none") eq "klicktel")
{
  $result = GetFileFromURL("http://www.klicktel.de/inverssuche/index/search?_dvform_posted=1&phoneNumber=".$number, 5);
  if(not defined($result))
  {
     if(AttrVal($name, "reverse-search-cache", "0") eq "1")
     {
       $hash->{helper}{CACHE}{$number} = "timeout";
       return undef;
     }
  }
  else
  {
    #Log 2, $result;
   if($result =~ /<a class="namelink" href=".+?">.*?<span class="fn">(.+?)<\/span>.*?<\/a>/)
   {
     $invert_match = $1;
     # char replacing todo;
     $hash->{helper}{CACHE}{$number} = $invert_match if(AttrVal($name, "reverse-search-cache", "0") eq "1");
     return $invert_match;
   }
  }
}

# Ask dasoertliche.de
if(AttrVal($name, "reverse-search", "none") eq "all" or AttrVal($name, "reverse-search", "none") eq "dasoertliche")
{
  $result = GetFileFromURL("http://www1.dasoertliche.de/?form_name=search_inv&ph=".$number, 5);
  if(not defined($result))
  {
    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
    {
       $hash->{helper}{CACHE}{$number} = "timeout";
       return undef;
    }
    
  }
  else
  {
   #Log 2, $result;
   if($result =~ /getItemData\('.*?', '.*?', '.*?', '.*?', '.*?', '(.*?)', '.*?', '.*?', '.*?'\);/)
   {
     $invert_match = $1;
     # char replacing todo
     $hash->{helper}{CACHE}{$number} = $invert_match if(AttrVal($name, "reverse-search-cache", "0") eq "1");
     return $invert_match;
   }
  }
}

 
# If no result is available set cache result and return undefined 
$hash->{helper}{CACHE}{$number} = "unknown";
return undef 
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
    <li><a href="#do_not_notiy">do_not_notify</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li><br>
    <li><a name="reverse-search">reverse-search</a> (all|klicktel|dasoertliche|none)</li>
    Activate the reverse searching of the external number (at dial and call receiving).
    It is possible to select a specific web service, which should be used for reverse searching.
    If the attribute is set to "all", the reverse search will reverse search on all websites until a valid answer is found on of them 
    If is set to "none", then no reverse searching will be used.<br><br>Default value is "none".<br><br>
    <li><a name="reverse-search-cache">reverse-search-cache</a></li>
    If this attribute is activated each reverse-search result is saved in an internal cache
    and will be used instead of reverse searching again the same number.<br><br>
    Possible values: 0 => off , 1 => on<br>
    Default Value is 0 (off)
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
=begin html_DE

<a name="FB_CALLMONITOR"></a>
<h3>FB_CALLMONITOR</h3>
<ul>
  <tr><td>
  Das Modul FB_CALLMONITOR verbindet sich zu einer AVM FritzBox Fon und verarbeitet
  Telefonie-<a href="#FB_CALLMONITORevents">Ereignisse</a>.(eingehende & ausgehende Telefonate)
  <br><br>
  Um dieses Modul nutzen zu k&ouml;nnen, muss der CallMonitor via Kurzwahl mit einem Telefon aktiviert werden.
 .<br><br>
  <ul>
      <code>#96*5* - CallMonitor aktivieren<br>#96*4* - CallMonitor deaktivieren</code>
  </ul>
  <br>
  Einfach die entsprechende Kurzwahl auf irgend einem Telefon eingeben, welches an die Fritz!Box angeschlossen ist. 
  Nach ca. 3 Sekunden kann man einfach wieder auflegen. Nun ist der CallMonitor aktiviert.
  <br>
  Sobald der CallMonitor auf der Fritz!Box aktiviert wurde erzeugt das Modul entsprechende Events (s.u.)
  <br><br>
  Dieses Modul funktioniert mit allen Fritz!Box Modellen, welche Telefonie unterst&uuml;tzen (Namenszusatz: Fon).
  <br><br>
  
  <a name="FB_CALLMONITORdefine"></a>
  <b>Definition</b>
  <ul>
    <code>define &lt;name&gt; FB_CALLMONITOR &lt;IP-Addresse&gt;[:Port]</code><br>
    <br>
    Port 1012 ist der Standardport und muss daher nicht explizit angegeben werden.
    <br>
  </ul>
  <br>
  <a name="FB_CALLMONITORset"></a>
  <b>Set-Kommandos</b>
  <ul>
  N/A 
  </ul>
  <br>

  <a name="FB_CALLMONITORget"></a>
  <b>Get-Kommandos</b>
  <ul>
  N/A
  </ul>
  <br>

  <a name="FB_CALLMONITORattr"></a>
  <b>Attribute</b><br><br>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notiy">do_not_notify</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
  </ul>
  <br>
 
  <a name="FB_CALLMONITORevents"></a>
  <b>Generierte Events:</b><br><br>
  <ul>
  <li><b>event</b>: (call|ring|connect|disconnect) - Welches Event wurde genau ausgel&ouml;st.</li>
  <li><b>external_number</b>: $number - Die Rufnummer des Gegen&uuml;bers, welcher anruft (event: ring) oder angerufen wird (event: call)</li>
  <li><b>internal_number</b>: $number - Die interne Rufnummer (Festnetz, VoIP-Nummer, ...) auf welcher man angerufen wird (event: ring) oder die man gerade nutzt um jemanden anzurufen (event: call)</li>
  <li><b>internal_connection</b>: $connection - Der interne Anschluss an der Fritz!Box welcher genutzt wird um das Gespr&auml;ch durchzuf&uuml;hren (FON1, FON2, ISDN, DECT, ...)</li>
  <li><b>external_connection</b>: $connection - Der externe Anschluss welcher genutzt wird um das Gespräch durchzuf&uuml;hren  (Festnetz, VoIP Nummer, ...)</li>
  <li><b>call_duration</b>: $seconds - Die Gespr&auml;chsdauer in Sekunden. Dieser Wert wird nur bei einem disconnect-Event erzeugt. Ist der Wert 0, so wurde das Gespr&auml;ch von niemandem angenommen.</li>
  </ul>
</ul>


=end html_DE

=cut
