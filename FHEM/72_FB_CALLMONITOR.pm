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
use Digest::MD5;
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
  $hash->{GetFn}   = "FB_CALLMONITOR_Get";
  $hash->{DefFn}   = "FB_CALLMONITOR_Define";
  $hash->{UndefFn} = "FB_CALLMONITOR_Undef";
 
  
  $hash->{AttrList}= "do_not_notify:0,1 loglevel:1,2,3,4,5 unique-call-ids:0,1 local-area-code remove-leading-zero:0,1 reverse-search-cache-file reverse-search:all,internal,klicktel.de,dasoertliche.de,search.ch,none reverse-search-cache:0,1 reverse-search-phonebook-file ".
                        $readingFnAttributes;
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

  InternalTimer(gettimeofday()+3, "FB_CALLMONITOR_loadInternalPhonebookFile", $hash, 0);
  
  InternalTimer(gettimeofday()+2, "FB_CALLMONITOR_loadCacheFile", $hash, 0);


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
FB_CALLMONITOR_Get($@)
{

my ($hash, @arguments) = @_;


return "argument missing" if(int(@arguments) < 2);

if($arguments[1] eq "search")
{
    if($arguments[2] =~ /^\d+$/)
    {
        return FB_CALLMONITOR_reverseSearch($hash, $arguments[2]);
    }
    else
    {
    return "given argument is not a telephone number";
    }
}
else
{

   return "unknown argument, choose on of search"; 

}

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
  my $area_code = AttrVal($name, "local-area-code", "");
  my $external_number = undef;
  
  
  
   @array = split(";", $data);
  
   $external_number = $array[3] if(not $array[3] eq "0" and $array[1] eq "RING" and $array[3] ne "");
   $external_number = $array[5] if($array[1] eq "CALL" and $array[3] ne "");
  
   $external_number =~ s/^0// if(AttrVal($name, "remove-leading-zero", "0") eq "1");
  
   if(defined($external_number) and not $external_number =~ /^0/ and $area_code ne "")
   {
    if($area_code =~ /^0[1-9]\d+$/)
    {
      $external_number = $area_code.$external_number;
    }
    else
    {
     Log GetLogLevel($name, 2), "$name: given local area code '$area_code' is not an area code. therefore will be ignored";
    }
   
   }
   
   $reverse_search = FB_CALLMONITOR_reverseSearch($hash, $external_number) if(defined($external_number) and AttrVal($name, "reverse-search", "none") ne "none");
   
   readingsBeginUpdate($hash);
   readingsBulkUpdate($hash, "event", lc($array[1]));
   readingsBulkUpdate($hash, "external_number", (defined($external_number) ? $external_number : "unknown")) if($array[1] eq "RING" or $array[1] eq "CALL");
   readingsBulkUpdate($hash, "external_name",(defined($reverse_search) ? $reverse_search : "unknown")) if($array[1] eq "RING" or $array[1] eq "CALL");
   readingsBulkUpdate($hash, "internal_number", $array[4]) if($array[1] eq "RING" or $array[1] eq "CALL");
   readingsBulkUpdate($hash, "external_connection", $array[5]) if($array[1] eq "RING");
   readingsBulkUpdate($hash, "external_connection", $array[6]) if($array[1] eq "CALL");
   readingsBulkUpdate($hash, "internal_connection", $connection_type{$array[3]}) if($array[1] eq "CALL" or $array[1] eq "CONNECT" and defined($connection_type{$array[3]}));
   readingsBulkUpdate($hash, "call_duration", $array[3]) if($array[1] eq "DISCONNECT");
   
    if(AttrVal($name, "unique-call-ids", "0") eq "1")
    {
	if($array[1] eq "RING" or $array[1] eq "CALL")
	{
	    $hash->{helper}{CALLID}{$array[2]} = Digest::MD5::md5_hex($data);
	}
	
	readingsBulkUpdate($hash, "call_id", $hash->{helper}{CALLID}{$array[2]});
	
	if($array[1] eq "DISCONNECT")
	{
	    delete($hash->{helper}{CALLID}{$array[2]});
	}
    }
    else
    {
	readingsBulkUpdate($hash, "call_id", $array[2]);
    }
    
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


# Using internal phonebook if available and enabled
if(AttrVal($name, "reverse-search", "none") eq "all" or AttrVal($name, "reverse-search", "none") eq "internal" and defined($hash->{helper}{PHONEBOOK}))
{
   if(defined($hash->{helper}{PHONEBOOK}{$number}))
   {
      Log GetLogLevel($name, 4), "FB_CALLMONITOR $name using internal phonebook for reverse search of $number";
         return $hash->{helper}{PHONEBOOK}{$number};

   }
}

# Using Cache if enabled
if(AttrVal($name, "reverse-search-cache", "0") eq "1")
{
   if(defined($hash->{helper}{CACHE}{$number}))
   {
      Log GetLogLevel($name, 4), "FB_CALLMONITOR $name using cache for reverse search of $number";
      if($hash->{helper}{CACHE}{$number} ne "timeout")
      {
         return $hash->{helper}{CACHE}{$number};
      }
   }
}

# Ask klicktel.de
if(AttrVal($name, "reverse-search", "none") eq "all" or AttrVal($name, "reverse-search", "none") eq "klicktel.de")
{ 
  Log GetLogLevel($name, 4), "FB_CALLMONITOR: $name using klicktel.de for reverse search of $number";
   
  $result = GetFileFromURL("http://www.klicktel.de/inverssuche/index/search?_dvform_posted=1&phoneNumber=".$number, 5, undef, 1);
  if(not defined($result))
  {
     if(AttrVal($name, "reverse-search-cache", "0") eq "1")
     {
       $hash->{helper}{CACHE}{$number} = "timeout";
       undef($result);
       return "timeout";
     }
  }
  else
  {
   
   if($result =~ /<a class="namelink" href=".+?">(.+?)<\/a>/)
   {
     $invert_match = $1;
     $invert_match = FB_CALLMONITOR_html2txt($invert_match);
     FB_CALLMONITOR_writeToCache($hash, $number, $invert_match) if(AttrVal($name, "reverse-search-cache", "0") eq "1");
     undef($result);
     return $invert_match;
   }
  }
}

# Ask dasoertliche.de
if(AttrVal($name, "reverse-search", "none") eq "all" or AttrVal($name, "reverse-search", "none") eq "dasoertliche.de")
{
  Log GetLogLevel($name, 4), "FB_CALLMONITOR: $name using dasoertliche.de for reverse search of $number";
  
  $result = GetFileFromURL("http://www1.dasoertliche.de/?form_name=search_inv&ph=".$number, 5, undef, 1);
  if(not defined($result))
  {
    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
    {
       $hash->{helper}{CACHE}{$number} = "timeout";
       undef($result);
       return "timeout";
    }
    
  }
  else
  {
   #Log 2, $result;
   if($result =~ /getItemData\('.*?', '.*?', '.*?', '.*?', '.*?', '(.*?)', '.*?', '.*?', '.*?'\);/)
   {
     $invert_match = $1;
     $invert_match = FB_CALLMONITOR_html2txt($invert_match);
     FB_CALLMONITOR_writeToCache($hash, $number, $invert_match) if(AttrVal($name, "reverse-search-cache", "0") eq "1");
     undef($result);
     return $invert_match;
   }
  }
}

# SWITZERLAND ONLY!!! Ask search.ch
if(AttrVal($name, "reverse-search", "none") eq "search.ch")
{
  Log GetLogLevel($name, 4), "FB_CALLMONITOR: $name using search.ch for reverse search of $number";
  
  $result = GetFileFromURL("http://tel.search.ch/?tel=".$number, 5, undef, 1);
  if(not defined($result))
  {
    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
    {
       $hash->{helper}{CACHE}{$number} = "timeout";
       undef($result);
       return "timeout";
    }
    
  }
  else
  {
   #Log 2, $result;
   if($result =~ /<h5><a href=".*?" class="fn">(.+?)<\/a><\/h5>/)
   {
     $invert_match = $1;
     $invert_match = FB_CALLMONITOR_html2txt($invert_match);
     FB_CALLMONITOR_writeToCache($hash, $number, $invert_match) if(AttrVal($name, "reverse-search-cache", "0") eq "1");
     undef($result);
     return $invert_match;
   }
  }
}


if(AttrVal($name, "reverse-search-cache", "0") eq "1")
{ 
    # If no result is available set cache result and return undefined 
    $hash->{helper}{CACHE}{$number} = "unknown";
}

    return undef;

} 

sub FB_CALLMONITOR_html2txt($)
{

my ($string) = @_;

$string =~ s/&nbsp;/ /g;
$string =~ s/(\xe4|&auml;)/ä/g;
$string =~ s/(\xc4|&Auml;)/Ä/g;
$string =~ s/(\xf6|&ouml;)/ö/g;
$string =~ s/(\xd6|&Ouml;)/Ö/g;
$string =~ s/(\xfc|&uuml;)/ü/g;
$string =~ s/(\xdc|&Uuml;)/Ü/g;
$string =~ s/(\xdf|&szlig;)/ß/g;
$string =~ s/<.+?>//g;
$string =~ s/(^\s+|\s+$)//g;

return $string;

}


sub FB_CALLMONITOR_writeToCache($$$)
{
  my ($hash, $number, $txt) = @_;
  my $name = $hash->{NAME};
  my $file = AttrVal($name, "reverse-search-cache-file", "");

  
  $file =~ s/(^\s+|\s+$)//g;
  
  $hash->{helper}{CACHE}{$number} = $txt;
  
  if($file ne "")
  {
    Log GetLogLevel($name, 4), "FB_CALLMONITOR: $name opening cache file $file";
    if(open(CACHEFILE, ">>$file"))
    {
       print CACHEFILE "$number|$txt\n";
       close(CACHEFILE); 
    }
    else
    {
       Log GetLogLevel($name, 2), "FB_CALLMONITOR: $name could not open cache file";
    }
  }


}


sub FB_CALLMONITOR_loadInternalPhonebookFile($)
{

  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $phonebook = undef;
  my $contact;
  my $contact_name;
  my $number;
  my $count_contacts;
  
  my $area_code = AttrVal($name, "local-area-code", "");
  my $phonebook_file = AttrVal($name, "reverse-search-phonebook-file", "/var/flash/phonebook");

  delete $hash->{helper}{PHONEBOOK} if(defined($hash->{helper}{PHONEBOOK}));

  if(-r $phonebook_file)
  {
    if(open(PHONEBOOK, "<$phonebook_file"))
    {
     
      $phonebook = join('', <PHONEBOOK>);
      if($phonebook =~ /<contact/ and $phonebook =~ /<realName>/ and $phonebook =~ /<number/ and $phonebook =~ /<phonebook/ and $phonebook =~ /<\/phonebook>/)
      {
        Log GetLogLevel($name, 2), "FB_CALLMONITOR: $name found FritzBox phonebook $phonebook_file";


        while($phonebook =~ m/<contact[^>]*>(.+?)<\/contact>/gs)
        {

          $contact = $1;
          if($contact =~ m/<realName>(.+?)<\/realName>/)
          {
            $contact_name = $1; 
            Log GetLogLevel($name, 4), "FB_CALLMONITOR: $name found $contact_name";
 
            while($contact =~ m/<number[^>]*?type="([^<>"]+?)"[^<>]*?>([^<>"]+?)<\/number>/gs)
            {
              if($1 ne "intern" and $1 ne "memo")
              {
                $number = $2;
                
                $number =~ s/^\+\d\d/0/g; # quick'n'dirty fix in case of international number format.
                $number =~ s/\D//g unless($number =~ /@/);
                $number =~ s/\s//g if($number =~ /@/);
                
                if(not $number =~ /^0/ and not $number =~ /@/ and $area_code ne "")
                {
                  if($area_code =~ /^0[1-9]\d+$/)
                  {
                    $number = $area_code.$number;
                  }
    
                }
            
                $hash->{helper}{PHONEBOOK}{$number} = FB_CALLMONITOR_html2txt($contact_name) if(not defined($hash->{helper}{PHONEBOOK}{$number}));
                undef $number;
              }
            }
            undef $contact_name;
          }
        }
        undef $phonebook;
        $count_contacts = scalar keys %{$hash->{helper}{PHONEBOOK}};
        Log GetLogLevel($name, 2), "FB_CALLMONITOR: $name read ".($count_contacts > 0 ? $count_contacts : "no")." contact".($count_contacts == 1 ? "" : "s")." from FritzBox phonebook";
      }
      else
      {
        Log GetLogLevel($name, 2), "FB_CALLMONITOR: the file $phonebook_file is not a FritzBox phonebook";
      }
    
    }
    else
    {
       Log GetLogLevel($name, 2), "FB_CALLMONITOR: $name internal could not read FritzBox phonebook file: $phonebook_file";
    }

}

}

sub FB_CALLMONITOR_loadCacheFile($)
{
  my ($hash) = @_;
  my $file = AttrVal($hash->{NAME}, "reverse-search-cache-file", "");
  my @cachefile;
  my @tmpline;
  
  $file =~ s/(^\s+|\s+$)//g;
  
  if($file ne "")
  {
    Log 2, "FB_CALLMONITOR: loading cache file $file";
    if(open(CACHEFILE, "$file"))
    {
       @cachefile = <CACHEFILE>;
       close(CACHEFILE);
       
       foreach my $line (@cachefile)
       {
        if(not $line =~ /^\s*$/)
        {
          $line =~ s/\n//g;
          
	  @tmpline = split("\\|", $line);
	
	  if(@tmpline == 2)
	  {
	    $hash->{helper}{CACHE}{$tmpline[0]} = $tmpline[1];
	  }
         }
       } 
    }
    else
    {
       Log 2, "FB_CALLMONITOR: could not open cache file";
    }
  }
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
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a name="reverse-search">reverse-search</a> (all|internal|klicktel.de|dasoertliche.de|search.ch|none)</li>
    Activate the reverse searching of the external number (at dial and call receiving).
    It is possible to select a specific web service, which should be used for reverse searching.
    If the attribute is set to "all", the reverse search will use the internal phonebook (if running FHEM on a FritzBox) or reverse search on all websites (execept search.ch) until a valid answer is found on of them 
    If is set to "none", then no reverse searching will be used.<br><br>Default value is "none".<br><br>
    <li><a name="reverse-search-cache">reverse-search-cache</a></li>
    If this attribute is activated each reverse-search result is saved in an internal cache
    and will be used instead of reverse searching again the same number.<br><br>
    Possible values: 0 => off , 1 => on<br>
    Default Value is 0 (off)<br><br>
    <li><a name="reverse-search-cache-file">reverse-search-cache-file</a> &lt;file&gt;</li>
    Write the internal reverse-search-cache to the given file and use it next time FHEM starts.
    So all reverse search results are persistent written to disk and will be used instantly after FHEM starts.<br><br>
    <li><a name="reverse-search-phonebook-file">reverse-search-phonebook-file</a> &lt;file&gt;</li>
    This attribute can be used to specify the (full) path to a phonebook file in FritzBox format (XML structure). Using this option it is possible to use the phonebook of a FritzBox even without FHEM running on a Fritzbox.
    The phonebook file can be obtained by an export via FritzBox web UI<br><br>
    Default value is /var/flash/phonebook (phonebook filepath on FritzBox)<br><br>
    <li><a name="remove-leading-zero">remove-leading-zero</a></li>
    If this attribute is activated, a leading zero will be removed from the external_number (e.g. in telefon systems).<br><br>
    Possible values: 0 => off , 1 => on<br>
    Default Value is 0 (off)<br><br>
    <li><a name="unique-call-ids">unique-call-ids</a></li>
    If this attribute is activated, each call will use a biunique call id. So each call can be separated from previous calls in the past.<br><br>
    Possible values: 0 => off , 1 => on<br>
    Default Value is 0 (off)<br><br>
    <li><a name="local-area-code">local-area-code</a></li>
    Use the given local area code for reverse search in case of a local call (e.g. 0228 for Bonn, Germany)<br><br>
  </ul>
  <br>
 
  <a name="FB_CALLMONITORevents"></a>
  <b>Generated Events:</b><br><br>
  <ul>
  <li><b>event</b>: (call|ring|connect|disconnect) - which event in detail was triggerd</li>
  <li><b>external_number</b>: $number - The participants number which is calling (event: ring) or beeing called (event: call)</li>
  <li><b>external_name</b>: $name - The result of the reverse lookup of the external_number via internet. Is only available if reverse-search is activated. Special values are "unknown" (no search results found) and "timeout" (got timeout while search request). In case of an timeout and activated caching, the number will be searched again next time a call occurs with the same number</li>
  <li><b>internal_number</b>: $number - The internal number (fixed line, VoIP number, ...) on which the participant is calling (event: ring) or is used for calling (event: call)</li>
  <li><b>internal_connection</b>: $connection - The internal connection (FON1, FON2, ISDN, DECT, ...) which is used to take the call</li>
  <li><b>external_connection</b>: $connection - The external connection (fixed line, VoIP account) which is used to take the call</li>
  <li><b>call_duration</b>: $seconds - The call duration in seconds. Is only generated at a disconnect event. The value 0 means, the call was not taken by anybody.</li>
  <li><b>call_id</b>: $id - The call identification number to separate events of two or more different calls at the same time. This id number is equal for all events relating to one specific call.</li>
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
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a name="reverse-search">reverse-search</a> (all|internal|klicktel.de|dasoertliche.de|search.ch|none)</li>
    Aktiviert die R&uuml;ckw&auml;rtssuche der externen Rufnummer der Gegenstelle (bei eingehenden/abgehenden Anrufen).
    Es ist m&ouml;glich einen bestimmten Suchanbieter zu verwenden, welcher f&uuml;r die R&uuml;ckw&auml;rtssuche verwendet werden soll.
    Falls FHEM auf einer FritzBox Fon l&auml;uft, kann mit dem Wert "internal" ausschlie&szlig;lich das interne Telefonbuch verwendet werden.
    Wenn dieses Attribut auf dem Wert "all" steht, wird (sofern FHEM auf einer FritzBox Fon l&auml;uft) das interne Telefonbuch verwendet,
    sowie alle verf&uuml;gbaren Suchanbieter (ausser search.ch)
    f&uuml;r die R&uuml;ckw&auml;rtssuche herangezogen, solange bis irgend ein Anbieter ein valides Ergebniss liefert.
    Wenn der Wert "none" ist, wird keine R&uuml;ckw&auml;rtssuche durchgef&uuml;hrt.<br><br>Standardwert ist "none" (keine R&uuml;ckw&auml;rtssuche).<br><br>
    <li><a name="reverse-search-cache">reverse-search-cache</a></li>
    Wenn dieses Attribut gesetzt ist, werden alle Ergebisse der R&uuml;ckw&auml;rtssuche in einem modul-internen gespeichert
    und von da an nur noch aus dem Cache genutzt anstatt eine erneute R&uuml;ckw&auml;rtssuche durchzuf&uuml;hren.<br><br>
    M&ouml;gliche Werte: 0 => deaktiviert , 1 => aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>
    <li><a name="reverse-search-cache-file">reverse-search-cache-file</a> &lt;Dateipfad&gt;</li>
    Da der Cache nur im Arbeitsspeicher existiert, ist er nicht persisten und geht beim stoppen von FHEM verloren.
    Mit diesem Parameter werden alle Cache-Ergebnisse in eine Textdatei geschrieben (z.B.  /usr/share/fhem/telefonbuch.txt) 
    und beim n&auml;chsten Start von FHEM direkt wieder in den Cache geladen und genutzt.
    <br><br>
    <li><a name="reverse-search-phonebook-file">reverse-search-phonebook-file</a> &lt;Dateipfad&gt</li>
    Mit diesem Attribut kann man optional den Pfad zu einer Datei angeben, welche ein Telefonbuch im FritzBox-Format (XML-Struktur) enth&auml;lt.
    Dadurch ist es m&ouml;glich ein FritzBox-Telefonbuch zu verwenden, ohne das FHEM auf einer FritzBox laufen muss.
    Sofern FHEM auf einer FritzBox l&auml;uft (und nichts abweichendes angegeben wurde), wird das interne File /var/flash/phonebook verwendet. Alternativ kann man das Telefonbuch in der FritzBox-Weboberfläche exportieren und dieses verwenden<br><br>
    Standartwert ist /var/flash/phonebook (entspricht dem Pfad auf einer FritzBox)<br><br>
    <li><a name="remove-leading-zero">remove-leading-zero</a></li>
    Wenn dieses Attribut aktiviert ist, wird die f&uuml;hrende Null aus der externen Rufnummer (bei eingehenden & abgehenden Anrufen) entfernt. Dies ist z.B. notwendig bei Telefonanlagen.<br><br>
    M&ouml;gliche Werte: 0 => deaktiviert , 1 => aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>
<li><a name="unique-call-ids">unique-call-ids</a></li>
    Wenn dieses Attribut aktiviert ist, wird f&uuml;r jedes Gespr&auml;ch eine eineindeutige Identifizierungsnummer verwendet. Dadurch lassen sich auch bereits beendete Gespr&auml;che voneinander unterscheiden. Dies ist zum Beispiel notwendig bei der Verarbeitung der Events durch eine Datenbank.<br><br>
    M&ouml;gliche Werte: 0 => deaktiviert , 1 => aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>
    <li><a name="local-area-code">local-area-code</a></li>
    Verwendet die gesetze Vorwahlnummer bei R&uuml;ckw&auml;rtssuchen bei Ortsgespr&auml;chen (z.B. 0228 f&uuml;r Bonn)<br><br>
  </ul>
  <br>
 
  <a name="FB_CALLMONITORevents"></a>
  <b>Generierte Events:</b><br><br>
  <ul>
  <li><b>event</b>: (call|ring|connect|disconnect) - Welches Event wurde genau ausgel&ouml;st.</li>
  <li><b>external_number</b>: $number - Die Rufnummer des Gegen&uuml;bers, welcher anruft (event: ring) oder angerufen wird (event: call)</li>
  <li><b>external_name</b>: $name - Das Ergebniss der R&uuml;ckw&auml;rtssuche (sofern aktiviert). Im Fehlerfall kann diese Reading auch den Inhalt "unknown" (keinen Eintrag gefunden) und "timeout" (Zeit&uuml;berschreitung bei der Abfrage) enthalten. Im Falle einer Zeit&uuml;berschreitung und aktiviertem Caching, wird die Rufnummer beim n&auml;chsten Mal erneut gesucht.</li>
  <li><b>internal_number</b>: $number - Die interne Rufnummer (Festnetz, VoIP-Nummer, ...) auf welcher man angerufen wird (event: ring) oder die man gerade nutzt um jemanden anzurufen (event: call)</li>
  <li><b>internal_connection</b>: $connection - Der interne Anschluss an der Fritz!Box welcher genutzt wird um das Gespr&auml;ch durchzuf&uuml;hren (FON1, FON2, ISDN, DECT, ...)</li>
  <li><b>external_connection</b>: $connection - Der externe Anschluss welcher genutzt wird um das Gespr&auml;ch durchzuf&uuml;hren  (Festnetz, VoIP Nummer, ...)</li>
  <li><b>call_duration</b>: $seconds - Die Gespr&auml;chsdauer in Sekunden. Dieser Wert wird nur bei einem disconnect-Event erzeugt. Ist der Wert 0, so wurde das Gespr&auml;ch von niemandem angenommen.</li>
  <li><b>call_id</b>: $id - Die Identifizierungsnummer eines einzelnen Gespr&auml;chs. Dient der Zuordnung bei 2 oder mehr parallelen Gespr&auml;chen, damit alle Events eindeutig einem Gespr&auml;ch zugeordnet werden k&ouml;nnen</li>
  </ul>
</ul>


=end html_DE

=cut
