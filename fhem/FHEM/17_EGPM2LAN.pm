############################################## 
# $Id: EGPM2LAN.pm 2891 2013-07-11 12:47:57Z alexus $ 
#
#  based / modified Version 98_EGPMS2LAN from ericl
#
#  (c) 2013 Copyright: Alex Storny (moselking at arcor dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
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
  $hash->{SetFn}     = "EGPM2LAN_Set"; 
  $hash->{DefFn}     = "EGPM2LAN_Define"; 
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6 stateDisplay:sockNumber,sockName autocreate:on,off"; 
} 

################################### 
sub 
EGPM2LAN_Set($@) 
{ 
  my ($hash, @a) = @_; 

  return "no set value specified" if(int(@a) < 2); 
  return "Unknown argument $a[1], choose one of on:1,2,3,4 off:1,2,3,4 toggle:1,2,3,4 clearreadings statusrequest" if($a[1] eq "?"); 

  
  my $name = shift @a; 
  my $setcommand = shift @a; 
  my $params = join(" ", @a); 
  my $logLevel = GetLogLevel($name,4); 
  my $post = "http://" . $hash->{IP} . "/ POST:";

  Log $logLevel, "EGPM2LAN set $name (". $hash->{IP}. ") $setcommand $params";
 
  EGPM2LAN_Login($hash, $logLevel); 
  
  if($setcommand eq "on") 
  { 
    $post .= "cte1=" . ($params == "1" ? "1" : "") . "&cte2=" . ($params == "2" ? "1" : "") . "&cte3=" . ($params == "3" ? "1" : "") . "&cte4=". ($params == "4" ? "1" : ""); 
    Log $logLevel, "EGPM2LAN $post";    
    eval {       
      CustomGetFileFromURL($hash, $post, 0, $logLevel); 
      EGPM2LAN_Statusrequest($hash, $logLevel); 
    }; 
    if ($@){ 
      ### catch block 
      Log $logLevel, "EGPM2LAN error: $@"; 
    }; 
  } 
  elsif($setcommand eq "off") 
  { 
    $post .= "cte1=" . ($params == "1" ? "0" : "") . "&cte2=" . ($params == "2" ? "0" : "") . "&cte3=" . ($params == "3" ? "0" : "") . "&cte4=". ($params == "4" ? "0" : ""); 
    Log $logLevel, "EGPM2LAN $post"; 
    eval {                 
      CustomGetFileFromURL($hash, $post, 0, $logLevel); 
      EGPM2LAN_Statusrequest($hash, $logLevel); 
    }; 
    if ($@){ 
      ### catch block 
      Log $logLevel, "EGPM2LAN error: $@"; 
    }; 
  } 
  elsif($setcommand eq "toggle") 
  { 
    my $currentstate = EGPM2LAN_Statusrequest($hash, $logLevel);
    if(defined($currentstate))
    {
	my @powerstates = split(",", $currentstate);
	my $newcommand="off";
	if($powerstates[$params-1] eq "0")
	{
	   $newcommand="on";
	}
        my @cmd = ($name,$newcommand,$params);
	EGPM2LAN_Set($hash,@cmd);
    } 
  } 
  elsif($setcommand eq "statusrequest") 
  { 
	EGPM2LAN_Statusrequest($hash, $logLevel); 
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
sub EGPM2LAN_Login($$) { 
  my ($hash, $logLevel) = @_; 

  Log $logLevel,"EGPM2LAN try to Login";

  eval{
  CustomGetFileFromURL($hash, "http://".$hash->{IP}."/login.html", 10, "pw=" . (defined($hash->{PASSWORD}) ? $hash->{PASSWORD} : ""), 0, $logLevel);  
  }; 
  if ($@){ 
      ### catch block 
      Log 1, "EGPM2LAN Login error: $@";
      return 0; 
  }; 

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
	push(@socketlist,trim($1)); 
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
sub EGPM2LAN_Statusrequest($$) { 
  my ($hash, $logLevel) = @_;
  my $name = $hash->{NAME}; 
  
  my $response = CustomGetFileFromURL($hash, "http://".$hash->{IP}."/", 10, undef, 0, $logLevel); 
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

                if(AttrVal($name, "autocreate", "on") eq "on" && not defined($defptr))
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
		   Log $logLevel, "Update State of ".$defptr->{NAME};
		   readingsSingleUpdate($defptr, "state", ($powerstates[$index-1] ? "on" : "off") ,0);
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
           readingsSingleUpdate($hash, "state", "Login failed",0);
	   Log $logLevel, "EGPM2LAN: Login failed";
	}
   #something went wrong :-( 
   return undef; 
} 

sub EGPM2LAN_Logoff($$) {
  my ($hash, $logLevel) = @_; 

  CustomGetFileFromURL($hash, "http://".$hash->{IP}."/login.html", 10, undef, 0, $logLevel);
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
  my $result = EGPM2LAN_Login($hash, 4);
  if($result == 1)
  { 
    #delayed auto-create 
    #InternalTimer(gettimeofday()+ 3, "EGPM2LAN_Statusrequest", $hash, 4);
    EGPM2LAN_Logoff($hash, 4); 
    $hash->{STATE} = "initialized";
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
    Defines an <a href="http://energenie.com/item.aspx?id=7557" >Energenie EG-PM2-LAN</a> device to switch up to 4 sockets over the network.
    You can connect and configure your device over the web-interface. Name Settings will be adopted to Fhem-Devices to identify the sockets.
<br>
</ul>
  <a name="EGPM2LANget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="EGPM2LANattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li>autocreate</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
<br>

    Example:
    <ul>
      <code>define mainswitch EGPM2LAN 10.192.192.20 SecretGarden</code><br>
      <code>set mainswitch on 1</code><br>
    </ul>
</ul>

=end html
=cut
