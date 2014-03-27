############################################## 
# $Id$
#
#  based / modified Version 98_EGPMS2LAN from ericl
#
#  (c) 2013, 2014 Copyright: Alex Storny (moselking at arcor dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################
#  -> Module 70_EGPM.pm (for a single Socket) needed.
################################################################
package main; 

use strict; 
use warnings; 
use HttpUtils;

sub 
EGPM2LAN_Initialize($) 
{ 
  my ($hash) = @_; 
  $hash->{Clients}   = ":EGPM:";
  $hash->{GetFn}     = "EGPM2LAN_Get";
  $hash->{SetFn}     = "EGPM2LAN_Set"; 
  $hash->{DefFn}     = "EGPM2LAN_Define"; 
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6 stateDisplay:sockNumber,sockName autocreate:on,off"; 
} 

###################################
sub
EGPM2LAN_Get($@)
{
    my ($hash, @a) = @_;
    my $what;

    return "argument is missing" if(int(@a) != 2);
    
    $what = $a[1];
    
    if($what =~ /^(state|lastcommand)$/)
    {
      if(defined($hash->{READINGS}{$what}))
      {
			   return $hash->{READINGS}{$what}{VAL};
		  }
      else
		  {
			   return "reading not found: $what";
		  }
    }
    else
    {
		  return "Unknown argument $what, choose one of state:noArg lastcommand:noArg".(exists($hash->{READINGS}{output})?" output:noArg":"");
    }
}

################################### 
sub 
EGPM2LAN_Set($@) 
{ 
  my ($hash, @a) = @_; 

  return "no set value specified" if(int(@a) < 2); 
  return "Unknown argument $a[1], choose one of on:1,2,3,4,all off:1,2,3,4,all toggle:1,2,3,4 clearreadings:noArg statusrequest:noArg" if($a[1] eq "?"); 

  my $name = shift @a; 
  my $setcommand = shift @a; 
  my $params = join(" ", @a); 
  my $logLevel = GetLogLevel($name,4); 
  Log $logLevel, "EGPM2LAN set $name (". $hash->{IP}. ") $setcommand $params";
 
  EGPM2LAN_Login($hash, $logLevel); 
  
  if($setcommand eq "on" || $setcommand eq "off") 
  { 
    if($params eq "all")
	  { #switch all Sockets; thanks to eric!
  	  for (my $count = 1; $count <= 4; $count++)
      {
   	    EGPM2LAN_Switch($hash, $setcommand, $count, $logLevel);
      }
	  }
	  else
	  {  #switch single Socket
       EGPM2LAN_Switch($hash, $setcommand, $params, $logLevel);
    }
    EGPM2LAN_Statusrequest($hash, $logLevel, 1); 
  }   
  elsif($setcommand eq "toggle") 
  { 
    my $currentstate = EGPM2LAN_Statusrequest($hash, $logLevel, 1);
    if(defined($currentstate))
    {
    	my @powerstates = split(",", $currentstate);
    	my $newcommand="off";
    	if($powerstates[$params-1] eq "0")
    	{
    	   $newcommand="on";
    	}
      EGPM2LAN_Switch($hash, $newcommand, $params, $logLevel);
	    EGPM2LAN_Statusrequest($hash, $logLevel, 0); 
    } 
  } 
  elsif($setcommand eq "statusrequest") 
  { 
	   EGPM2LAN_Statusrequest($hash, $logLevel, 1); 
  }
  elsif($setcommand eq "clearreadings") 
  { 
	   delete $hash->{READINGS};
  } 
  else 
  { 
     return "unknown argument $setcommand, choose one of on, off, toggle, statusrequest, clearreadings"; 
  } 
  
  EGPM2LAN_Logoff($hash, $logLevel); 

  $hash->{CHANGED}[0] = $setcommand; 
  $hash->{READINGS}{lastcommand}{TIME} = TimeNow(); 
  $hash->{READINGS}{lastcommand}{VAL} = $setcommand." ".$params; 
  
  return undef; 
} 

################################
sub EGPM2LAN_Switch($$$$) { 
  my ($hash, $state, $port, $logLevel) = @_; 
  $state = ($state eq "on" ? "1" : "0");
  
  my $fritz = 0; #may be important for FritzBox-users
  my $data = "cte1=" . ($port == "1" ? $state : "") . "&cte2=" . ($port == "2" ? $state : "") . "&cte3=" . ($port == "3" ? $state : "") . "&cte4=". ($port == "4" ? $state : ""); 
  Log $logLevel, "EGPM2LAN $data"; 
  eval {                 
    CustomGetFileFromURL($hash ,"http://".$hash->{IP}."/",10 ,$data ,$fritz ,$logLevel); 
  }; 
  if ($@){ 
    ### catch block 
    Log $logLevel, "EGPM2LAN error: $@"; 
  }; 

  return 1; 
} 

################################
sub EGPM2LAN_Login($$) { 
  my ($hash, $logLevel) = @_; 

  Log $logLevel,"EGPM2LAN try to Login @".$hash->{IP};

  eval{
  CustomGetFileFromURL($hash, "http://".$hash->{IP}."/login.html", 10, "pw=" . (defined($hash->{PASSWORD}) ? $hash->{PASSWORD} : ""), 0, $logLevel);  
  }; 
  if ($@){ 
      ### catch block 
      Log 1, "EGPM2LAN Login error: $@";
      return 0; 
  }; 

  Log $logLevel,"EGPM2LAN Login successful!";
    
return 1; 
} 

################################
sub EGPM2LAN_GetDeviceInfo($$) { 
  my ($hash, $input) = @_;
  my $logLevel = GetLogLevel($hash->{NAME},4); 

  #try to read Device Name
  my ($devicename) = $input =~ m/<h2>(.+)<\/h2><\/div>/si;
  $hash->{DEVICENAME} = trim($devicename);

  #try to read Socket Names
  my @socketlist; 
  while ($input =~ m/<h2 class=\"ener\">(.+?)<\/h2>/gi) 
  { 
    my $socketname = trim($1);
    $socketname =~ s/ /_/g;    #remove spaces
    push(@socketlist, $socketname); 
  }

  #check 4 dublicate Names
  my %seen;
  foreach my $entry (@socketlist)
  {
	next unless $seen{$entry}++;
        Log $logLevel, "EGPM2LAN Sorry! Can't use devicenames. ".trim($entry)." is duplicated.";
	@socketlist = qw(Socket_1 Socket_2 Socket_3 Socket_4);
  } 
  if(int(@socketlist) < 4)
  {
	@socketlist = qw(Socket_1 Socket_2 Socket_3 Socket_4);
  }
  return @socketlist; 
}

################################
sub EGPM2LAN_Statusrequest($$$) { 
  my ($hash, $logLevel, $autoCr) = @_;
  my $name = $hash->{NAME}; 
  
  my $response = CustomGetFileFromURL($hash, "http://".$hash->{IP}."/", 10, "", 0, $logLevel); 
  #Log 1,$response;
	if(defined($response) && $response =~ /.,.,.,./) 
        { 
          my $powerstatestring = $&; 
          Log $logLevel, "EGPM2LAN Powerstate: " . $powerstatestring; 
          my @powerstates = split(",", $powerstatestring);

          if(int(@powerstates) == 4) 
          { 
            my $index;
            my $newstatestring;
            my @socketlist = EGPM2LAN_GetDeviceInfo($hash,$response);
            readingsBeginUpdate($hash);
            
	    foreach my $powerstate (@powerstates)
            {
                $index++;
		if(length(trim($socketlist[$index-1]))==0)
		{
		  $socketlist[$index-1]="Socket_".$index;	
		}
                if(AttrVal($name, "stateDisplay", "sockNumber") eq "sockName") {
                  $newstatestring .= $socketlist[$index-1].": ".($powerstates[$index-1] ? "on" : "off")." ";
		} else {
            	  $newstatestring .= $index.": ".($powerstates[$index-1] ? "on" : "off")." ";
		}

                #Create Socket-Object if not available
                my $defptr = $modules{EGPM}{defptr}{$name.$index};

                if($autoCr && AttrVal($name, "autocreate", "on") eq "on" && not defined($defptr))
		{
		   if(Value("autocreate") eq "active")
		   {
		  	Log $logLevel, "EGPM2LAN: Autocreate EGPM for Socket $index";
	                CommandDefine(undef, $name."_".$socketlist[$index-1]." EGPM $name $index");
		   }
		   else
		   {
			 Log 2, "EGPM2LAN: Autocreate disabled in globals section";
       $attr{$name}{autocreate} = "off"; 
		   }
		}

		#Write state 2 related Socket-Object
		if (defined($defptr))
		{
		   if (ReadingsVal($defptr->{NAME},"state","") ne ($powerstates[$index-1] ? "on" : "off"))
		   {  #check for chages and update -> trigger event
		 		  Log $logLevel, "Update State of ".$defptr->{NAME};
          readingsSingleUpdate($defptr, "state", ($powerstates[$index-1] ? "on" : "off") ,1);
       }
		   $defptr->{DEVICENAME} = $hash->{DEVICENAME};
		   $defptr->{SOCKETNAME} = $socketlist[$index-1];
   	}

         	readingsBulkUpdate($hash, $index."_".$socketlist[$index-1], ($powerstates[$index-1] ? "on" : "off"));
        } 
        readingsBulkUpdate($hash, "state", $newstatestring);
        readingsEndUpdate($hash, 0);

	    #everything is fine
	    return $powerstatestring;
          } 
          else 
          { 
            Log $logLevel, "EGPM2LAN: Failed to parse powerstate";
          } 
        }
	else
	{
     $hash->{STATE} = "Login failed";
	   Log $logLevel, "EGPM2LAN: Login failed";
	}
   #something went wrong :-( 
   return undef; 
} 

sub EGPM2LAN_Logoff($$) {
  my ($hash, $logLevel) = @_; 

  #$quiet, $url, $timeout, $data, $noshutdown, $loglevel
  CustomGetFileFromURL($hash, "http://".$hash->{IP}."/login.html", 10, "", 0, $logLevel);
  return 1; 
} 

sub 
EGPM2LAN_Define($$) 
{ 
  my ($hash, $def) = @_; 
  my @a = split("[ \t][ \t]*", $def); 

  my $u = "wrong syntax: define <name> EGPM2LAN IP Password"; 
  return $u if(int(@a) < 2); 
    
  $hash->{IP} = $a[2]; 
  if(int(@a) == 4) 
  { 
    $hash->{PASSWORD} = $a[3];  
  } 
  else 
  { 
    $hash->{PASSWORD} = "";
  }
  my $result = EGPM2LAN_Login($hash, 3);
  if($result == 1)
  { 
    $hash->{STATE} = "initialized";
    EGPM2LAN_Statusrequest($hash, 4, 0);
    EGPM2LAN_Logoff($hash, 4); 
  }

  return undef; 
} 

1;

=pod
=begin html

<a name="EGPM2LAN"></a>
<h3>EGPM2LAN</h3>
<ul>
  <br>
  <a name="EGPM2LANdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EGPM2LAN &lt;IP-Address&gt; [&lt;Password&gt;]</code><br>
    <br>
    Creates a Gembird &reg; <a href="http://energenie.com/item.aspx?id=7557" >Energenie EG-PM2-LAN</a> device to switch up to 4 sockets over the network.
    If you have more than one device, it is helpful to connect and set names for your sockets over the web-interface first.
    The name settings will be adopted to FHEM and helps you to identify the sockets. Please make sure that you&acute;re logged off from the Energenie web-interface otherwise you can&acute;t control it with FHEM at the same time.<br>
    <b>EG-PMS2-LAN with surge protector feature was not tested until now.</b>
</ul><br>
  <a name="EGPM2LANset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;[on|off|toggle]&gt &lt;socketnr.&gt;</code><br>
    Switch the socket on or off.<br>
    <br>
    <code>set &lt;name&gt; &lt;[on|off]&gt &lt;all&gt;</code><br>
    Switch all available sockets on or off.<br>
    <br>
    <code>set &lt;name&gt; &lt;staterequest&gt;</code><br>
    Update the device information and the state of all sockets.<br>
    If <a href="#autocreate">autocreate</a> is enabled, an <a href="#EGPM">EGPM</a> device will be created for each socket.<br>
    <br>
    <code>set &lt;name&gt; &lt;clearreadings&gt;</code><br>
    Removes all readings from the list to get rid of old socketnames.
  </ul>
  <br>
  <a name="EGPM2LANget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="EGPM2LANattr"></a>
  <b>Attributes</b>
  <ul>
    <li>stateDisplay</li>
	  Default: <b>socketNumer</b> changes between <b>socketNumer</b> and <b>socketName</b> in front of the current state. Call <b>set statusrequest</b> to update all states.
    <li>autocreate</li>
    Default: <b>on</b> <a href="#EGPM">EGPM</a>-devices will be created automatically with a <b>set</b>-command.
	  Change this attribute to value <b>off</b> to avoid that mechanism.
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
<br>
   <br>

    Example:
    <ul>
      <code>define mainswitch EGPM2LAN 10.192.192.20 SecretGarden</code><br>
      <code>set mainswitch on 1</code><br>
    </ul>
</ul>

=end html
=begin html_DE

<a name="EGPM2LAN"></a>
<h3>EGPM2LAN</h3>
<ul>
  <br>
  <a name="EGPM2LANdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EGPM2LAN &lt;IP-Address&gt; [&lt;Password&gt;]</code><br>
    <br>
    Das Modul erstellt eine Verbindung zu einer Gembird &reg; <a href="http://energenie.com/item.aspx?id=7557" >Energenie EG-PM2-LAN</a> Steckdosenleiste und steuert 4 angeschlossene Ger&auml;te..
    Falls mehrere Steckdosenleisten &uuml;ber das Netzwerk gesteuert werden, ist es ratsam, diese zuerst &uuml;ber die Web-Oberfl&auml;che zu konfigurieren und die einzelnen Steckdosen zu benennen. Die Namen werden dann automatisch in die
    Oberfl&auml;che von FHEM &uuml;bernommen. Bitte darauf achten, die Weboberfl&auml;che mit <i>Logoff</i> wieder zu verlassen, da der Zugriff sonst blockiert wird.
</ul><br>
  <a name="EGPM2LANset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;[on|off|toggle]&gt &lt;socketnr.&gt;</code><br>
    Schaltet die gew&auml;hlte Steckdose ein oder aus.<br>
    <br>
    <code>set &lt;name&gt; &lt;[on|off]&gt &lt;all&gt;</code><br>
    Schaltet alle Steckdosen gleichzeitig ein oder aus.<br>
    <br>
    <code>set &lt;name&gt; &lt;staterequest&gt;</code><br>
    Aktualisiert die Statusinformation der Steckdosenleiste.<br>
    Wenn das globale Attribut <a href="#autocreate">autocreate</a> aktiviert ist, wird f&uuml;r jede Steckdose ein <a href="#EGPM">EGPM</a>-Eintrag erstellt.<br>
    <br>
    <code>set &lt;name&gt; &lt;clearreadings&gt;</code><br>
    L&ouml;scht alle ung&uuml;ltigen Eintr&auml;ge im Abschnitt &lt;readings&gt;.
  </ul>
  <br>
  <a name="EGPM2LANget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="EGPM2LANattr"></a>
  <b>Attribute</b>
  <ul>
    <li>stateDisplay</li>
	  Default: <b>socketNumer</b> wechselt zwischen <b>socketNumer</b> and <b>socketName</b> f&uuml;r jeden Statuseintrag. Verwende <b>set statusrequest</b>, um die Anzeige zu aktualisieren.
    <li>autocreate</li>
    Default: <b>on</b> <a href="#EGPM">EGPM</a>-Eintr&auml;ge werden automatisch mit dem <b>set</b>-command erstellt.
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
<br>
   <br>

    Beispiel:
    <ul>
      <code>define sleiste EGPM2LAN 10.192.192.20 SecretGarden</code><br>
      <code>set sleiste on 1</code><br>
    </ul>
</ul>
=end html_DE

=cut

