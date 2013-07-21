# $Id$
##############################################################################
#
#     71_LISTENLIVE.pm
#     An FHEM Perl module for controlling ListenLive-enabled Mediaplayers
#     via network connection.
#
#     Copyright: betateilchen ®
#     e-mail   : fhem.development@betateilchen.de
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
#	Changelog:
#	2013-07-21	Logging vereinheitlich
#				Meldungen komplett auf englisch umgestellt
#				pod (EN) erstellt
#
##############################################################################

package main;

#use strict;
use warnings;
use POSIX;
use CGI qw(:standard);
use IO::Socket;
use IO::Socket::INET;
use MIME::Base64;
use Time::HiRes qw(gettimeofday sleep usleep nanosleep);
use HttpUtils;
use feature qw/say switch/;


sub LISTENLIVE_Set($@);
sub LISTENLIVE_Get($@);
sub LISTENLIVE_Define($$);
sub LISTENLIVE_GetStatus($;$);
sub LISTENLIVE_Undefine($$);

###################################
sub
LISTENLIVE_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "LISTENLIVE_Get";
  $hash->{SetFn}     = "LISTENLIVE_Set";
  $hash->{DefFn}     = "LISTENLIVE_Define";
  $hash->{UndefFn}   = "LISTENLIVE_Undefine";

  $hash->{AttrList}  = "do_not_notify:0,1 loglevel:0,1,2,3,4,5 ".
                      $readingFnAttributes;
}

###################################
sub
LISTENLIVE_Set($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
	my $loglevel = GetLogLevel($name, 3);
    my $result;
    my $response;
    my $command;
       
    return "No Argument given!\n\n".LISTENLIVE_HelpSet() if(!defined($a[1]));     
    
    my $pstat = $hash->{READINGS}{power}{VAL};
	my $mute  = $hash->{READINGS}{mute}{VAL};

#	my @b = split(/\./, $a[1]);
#	my $area = $b[0];
#	my $doit = $b[1];
#	if(!defined($doit) && defined($a[2])) { $doit = $a[2]; }

	my $area = $a[1];
	my $doit = $a[2];

    my $usage = "Unknown argument, choose one of help statusRequest power:on,off audio:volp,volm,mute,unmute cursor:up,down,left,right,enter,exit,home,ok reset:power,mute,menupos app:weather raw user";

	given ($area){

#
# AREA = user <userDefFunction>
# ruft eine userdefinierte Funktion, z.B. aus 99_myUtils.pm auf
#

		when("user"){
			if(defined($doit)){
				Log $loglevel, "LISTENLIVE $name input: $area $doit";
				$result = &{$doit};
				readingsBeginUpdate($hash);
		   		readingsBulkUpdate($hash, "lastCmd","$area $doit");
			   	readingsBulkUpdate($hash, "lastResult",$result);
			   	readingsEndUpdate($hash, 1);
			}
			else
			{ return $usage; }
			break;
		} # end user

#
# AREA = raw <command>
# sendet einfach das <command> per http an das Gerät
# und schreibt die Rückmeldung in das Reading "rawresult"
# (hauptsächlich für Debugging vorgesehen)
#

		when("raw"){
			if(defined($doit)){
				Log $loglevel, "LISTENLIVE $name input: $area $doit";
				$result = LISTENLIVE_SendCommand($hash, $doit);
				if($result =~  m/OK/){
					readingsBeginUpdate($hash);
				   	readingsBulkUpdate($hash, "lastCmd","$area $doit");
	    			readingsBulkUpdate($hash, "lastResult",$result);
			   		readingsEndUpdate($hash, 1);
				}
				else
				{
					LISTENLIVE_rbuError($hash, $area, $doit);
				}
			}
			else
     		{ return $usage; }
			break;
		} # end raw

#
# AREA = reset <power>|<mute>|<menupos>
# sendet gnadenlos ein POWER oder MUTE oder setzt 
# die MENUPOS auf 11 (oben links), damit man eine Chance hat,
# den Gerätestatus zu synchronisieren
#

		when("reset"){
			given($doit){
				when("power"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					readingsBeginUpdate($hash);
				   	readingsBulkUpdate($hash, "lastCmd","$area $doit");
	    			readingsBulkUpdate($hash, "lastResult","OK");
    				readingsBulkUpdate($hash, "power","???");
					readingsEndUpdate($hash, 1);
					break;
				} # end reset.power
		
				when("mute"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
    				readingsBeginUpdate($hash);
				   	readingsBulkUpdate($hash, "lastCmd","$area $doit");
    				readingsBulkUpdate($hash, "lastResult","OK");
					readingsBulkUpdate($hash, "mute","???");
					readingsEndUpdate($hash, 1);
					break;
				} # end reset.mute
		
				when("menupos"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "HOME");
					if($result =~  m/OK/){
		    			readingsBeginUpdate($hash);
					   	readingsBulkUpdate($hash, "lastCmd","$area $doit");
	    				readingsBulkUpdate($hash, "lastResult",$result);
    					readingsBulkUpdate($hash, "menuPos","11");
	   					readingsEndUpdate($hash, 1);
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit);
					}
					break;
				} # end reset.menupos

				default:
	        		{ return $usage; }
	
			} # end doit

		} # end area.reset

#
# AREA power <on>|<off>
# Es wird vor dem Senden geprüft, ob der Befehl Sinn macht,
# da der gleiche Befehl für das Ein- und Ausschalten
# verwendet wird.
# Ein "power on" wird bei einem eingeschalteten Gerät nicht gesendet
# Ein "power off" wird bei einem ausgeschalteten Gerät nicht gesendet
# Als Basis für die Entscheidung dient das Reading power
#

		when("power"){
			given ($doit){
				when("on") {
					if($pstat ne "on"){ 
						Log $loglevel, "LISTENLIVE $name input: $area $doit";
						$result = LISTENLIVE_SendCommand($hash, "POWER");
						if($result =~  m/OK/)
						{
			    			readingsBeginUpdate($hash);
						   	readingsBulkUpdate($hash, "lastCmd","$area $doit");
	    					readingsBulkUpdate($hash, "lastResult",$result);
	    					readingsBulkUpdate($hash, "power","on");
	    					readingsEndUpdate($hash, 1);
						}
						else
						{
							LISTENLIVE_rbuError($hash, $area, $doit);
						}
					}
					else
        			{
        				LISTENLIVE_rbuError($hash, $area, $doit, " => device already on!");
        			}
        			break;
		      	} # end power.on

				when("off") {
    		    	if($pstat ne "off")
    		    	{
						Log $loglevel, "LISTENLIVE $name input: $area $doit";
						$result = LISTENLIVE_SendCommand($hash, "POWER");
		    		    if($result =~  m/OK/){
							readingsBeginUpdate($hash);
					   		readingsBulkUpdate($hash, "lastCmd","$area $doit");
	    					readingsBulkUpdate($hash, "lastResult",$result);
							readingsBulkUpdate($hash, "power","off");
    	        			readingsEndUpdate($hash, 1);
        				}
        				else
        				{
							LISTENLIVE_rbuError($hash, $area, $doit);
        				}
					}
					else
        			{
        				LISTENLIVE_rbuError($hash, $area, $doit, " => device already off!");
        			}
        			break;
	      		} # end power.off

			default:
        		{ return $usage; }

			} # end power.doit

		} # end area.power

#
# AREA audio <mute>|<unmute>|<volp>|<volm>
#

		when("audio"){
			given($doit){
		
				when("mute"){
					if($mute ne "on"){ 
						Log $loglevel, "LISTENLIVE $name input: $area $doit";
						$result = LISTENLIVE_SendCommand($hash, "MUTE");
						if($result =~  m/OK/){
			    			readingsBeginUpdate($hash);
						   	readingsBulkUpdate($hash, "lastCmd","$area $doit");
	    					readingsBulkUpdate($hash, "lastResult",$result);
	    					readingsBulkUpdate($hash, "mute","on");
							readingsEndUpdate($hash, 1);
						}
						else
						{
						LISTENLIVE_rbuError($hash, $area, $doit);
						}
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit, "Already muted!");
        			}
        			break;
				} # end mute

				when("unmute"){
					if($mute ne "off"){ 
						Log $loglevel, "LISTENLIVE $name input: $area $doit";
						$result = LISTENLIVE_SendCommand($hash, "MUTE");
						if($result =~  m/OK/){
			    			readingsBeginUpdate($hash);
	    					readingsBulkUpdate($hash, "lastCmd",$a[1]);
	    					readingsBulkUpdate($hash, "lastResult",$result);
	    					readingsBulkUpdate($hash, "mute","off");
			    			readingsEndUpdate($hash, 1);
						}
						else
						{
							LISTENLIVE_rbuError($hash, $area, $doit);
						}
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit, "Already unmuted!");
        			}
        			break;
				} # end unmute

				when("volp"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "VOLp");
					if($result =~  m/OK/){
						readingsBeginUpdate($hash);
    					readingsBulkUpdate($hash, "lastCmd","$area $doit");
    					readingsBulkUpdate($hash, "lastResult",$result);
	   					readingsEndUpdate($hash, 1);
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit);
					}
					break;
				} # end volp
		
				when("volm"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "VOLm");
					if($result =~  m/OK/){
						readingsBeginUpdate($hash);
	  					readingsBulkUpdate($hash, "lastCmd","$area $doit");
    					readingsBulkUpdate($hash, "lastResult",$result);
	   					readingsEndUpdate($hash, 1);
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit);
					}
					break;
				} # end volm
		
				default:
	        		{ return $usage; }
		
			} # end audio.doit

		} # end area.audio

#
# AREA cursor <up>|<down>|<left>|<right>|home|<enter>|<ok>|<exit>
#

		when("cursor"){
			given($doit){

				when("up"){
					Log $loglevel, "LISTENLIVE $name $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "UP");
					if($result =~  m/OK/){
						readingsBeginUpdate($hash);
	   					readingsBulkUpdate($hash, "lastCmd",$a[1]);
    					readingsBulkUpdate($hash, "lastResult",$result);
						readingsBulkUpdate($hash, "menuPos",$hash->{READINGS}{menuPos}{VAL}-10);
	   					readingsEndUpdate($hash, 1);
    					return undef;
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit);
					}
					break;
				} # end up
		
				when("down"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "DOWN");
					if($result =~  m/OK/){
						readingsBeginUpdate($hash);
	   					readingsBulkUpdate($hash, "lastCmd",$a[1]);
    					readingsBulkUpdate($hash, "lastResult",$result);
    					readingsBulkUpdate($hash, "menuPos",$hash->{READINGS}{menuPos}{VAL}+10);
			   			readingsEndUpdate($hash, 1);
    					return undef;
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit);
					}
					break;
				} # end down
		
				when("left"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "LEFT");
					if($result =~  m/OK/){
						readingsBeginUpdate($hash);
	   					readingsBulkUpdate($hash, "lastCmd",$a[1]);
    					readingsBulkUpdate($hash, "lastResult",$result);
    					readingsBulkUpdate($hash, "menuPos",$hash->{READINGS}{menuPos}{VAL}-1);
			   			readingsEndUpdate($hash, 1);
    					return undef;
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit);
					}
					break;
				} # end left
		
				when("right"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "RIGHT");
					if($result =~  m/OK/){
						readingsBeginUpdate($hash);
	   					readingsBulkUpdate($hash, "lastCmd",$a[1]);
    					readingsBulkUpdate($hash, "lastResult",$result);
		    			readingsBulkUpdate($hash, "menuPos",$hash->{READINGS}{menuPos}{VAL}+1);
	   					readingsEndUpdate($hash, 1);
    					return undef;
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit);
					}
					break;
				} # end right

				when("home"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "HOME");
					if($result =~  m/OK/){
						readingsBeginUpdate($hash);
	   					readingsBulkUpdate($hash, "lastCmd",$a[1]);
    					readingsBulkUpdate($hash, "lastResult",$result);
    					readingsBulkUpdate($hash, "menuPos","11");
			   			readingsEndUpdate($hash, 1);
    					return undef;
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit)
					}
					break;
				} # end home

				when("enter"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "OK");
					if($result =~  m/OK/){
						readingsBeginUpdate($hash);
	   					readingsBulkUpdate($hash, "lastCmd",$a[1]);
    					readingsBulkUpdate($hash, "lastResult",$result);
   						readingsEndUpdate($hash, 1);
   						return undef;
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit);
					}
					break;
				} # end enter

				when("ok"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "OK");
					if($result =~  m/OK/){
						readingsBeginUpdate($hash);
	   					readingsBulkUpdate($hash, "lastCmd",$a[1]);
    					readingsBulkUpdate($hash, "lastResult",$result);
	   					readingsEndUpdate($hash, 1);
    					return undef;
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit);
					}
					break;
				} # end ok

				when("exit"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "EXIT");
					if($result =~  m/OK/){
						readingsBeginUpdate($hash);
	   					readingsBulkUpdate($hash, "lastCmd",$a[1]);
    					readingsBulkUpdate($hash, "lastResult",$result);
	   					readingsEndUpdate($hash, 1);
    					return undef;
					}
					else
					{
						LISTENLIVE_rbuError($hash, $area, $doit);
					}
				} # end cursor.exit

				default:
	        		{ return $usage; }
				
			} # end cursor.doit
	
		} # end area.cursor

#
# AREA app
#

		when ("app"){
			given($doit){
	
				when("weather"){
					Log $loglevel, "LISTENLIVE $name input: $area $doit";
					$result = LISTENLIVE_SendCommand($hash, "HOME");
					select(undef, undef, undef, 0.2);
					$result = LISTENLIVE_SendCommand($hash, "DOWN");
					select(undef, undef, undef, 0.2);
					$result = LISTENLIVE_SendCommand($hash, "DOWN");
					select(undef, undef, undef, 0.2);
					$result = LISTENLIVE_SendCommand($hash, "RIGHT");
					select(undef, undef, undef, 0.2);
					$result = LISTENLIVE_SendCommand($hash, "OK");

					readingsBeginUpdate($hash);
   					readingsBulkUpdate($hash, "lastCmd",$a[1]);
   					readingsBulkUpdate($hash, "lastResult","done");
   			 		readingsBulkUpdate($hash, "menuPos", "32");
	   				readingsEndUpdate($hash, 1);
				} # end doit.weather
	
				default:
	        		{ return $usage; }

			} # end doit

		} # end area.app

		when("statusRequest") {	break; } # wird automatisch aufgerufen!

		when("?")		{ return $usage; }

		when("help")	{ return LISTENLIVE_HelpSet(); }

		when("present")	{ break; }
		when("absent")	{ break; }
		when("online")	{ break; }
		when("offline")	{ break; }

		default:		{ return $usage; }

	} # end area
    
# Call the GetStatus() Function to retrieve the new values
	LISTENLIVE_GetStatus($hash, 1);
    
	return $response;    
}

###################################
sub
LISTENLIVE_Get($@){
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $response;
       
    return "No Argument given" if(!defined($a[1]));     

	my @b = split(/\./, $a[1]);
	my $area = $b[0];
	my $doit = $b[1];

    my $usage = "Unknown argument $a[1], choose one of help list:commands";

	given($area){
		
		when("list"){

			given("$doit"){
				
				when("commands"){
					$response = LISTENLIVE_HelpGet();
					break;
				}
				
				default: { return $usage; }

			}	# end area.list.doit

		}	# end area.list

		when("?")	{ return $usage; }			

		when("help"){ $response = LISTENLIVE_HelpGet(); }

		default:	{ return $usage; }

	} # end area

return $response;
}

###################################
sub
LISTENLIVE_GetStatus($;$){

    my ($hash, $local) = @_;
    my $name = $hash->{NAME};
    my $presence;

    $local = 0 unless(defined($local));

	if($hash->{helper}{ADDRESS} ne "none")
	{
		$presence = ReadingsVal("pres_".$name,"state","noPresence");
	}
	else
	{
		$presence = "present";
	}

	$presence = ReplaceEventMap($name, $presence, 1);
	
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state", $presence);
	readingsEndUpdate($hash, 1);

    InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "LISTENLIVE_GetStatus", $hash, 0) unless($local == 1);
    return $hash->{STATE};

}

#############################
sub
LISTENLIVE_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};
       
    if(! @a >= 4)
    {
		my $msg = "wrong syntax: define <name> LISTENLIVE <ip-or-hostname>[:<port>] [<interval>]";
		 Log 2, $msg;
		return $msg;
    }

# Attribut eventMap festlegen (schönere Optik im Frontend)  
    $attr{$name}{"eventMap"} = "absent:offline present:online";

# Adresse in IP und Port zerlegen
	my @address = split(":", $a[2]);
    $hash->{helper}{ADDRESS} = $address[0];

# falls kein Port angegeben, Standardport 8080 verwenden
	$address[1] = "8080" unless(defined($address[1]));  
	$hash->{helper}{PORT} = $address[1];
        
# falls kein Intervall angegeben, Standardintervall 60 verwenden
	my $interval = $a[3];
	$interval = "60" unless(defined($interval));
	$hash->{helper}{INTERVAL} = $interval;

	if($address[0] ne "none")
	{
		# PRESENCE aus device pres_+NAME lesen
		my $presence = ReadingsVal("pres_".$name,"state","noPresence");
	
		if($presence eq "noPresence")	# PRESENCE nicht vorhanden
		{ 
			$cmd = "pres_$name PRESENCE lan-ping $address[0]";
			$ret = CommandDefine(undef, $cmd);
			if($ret)
			{
				Log 2, "LISTENLIVE ERROR $ret";
			}
			else
			{
				Log 3, "LISTENLIVE $name PRESENCE pres_$name created.";
			}
		}
		else
		{
			Log 3, "LISTENLIVE $name PRESENCE pres_$name found.";
		}	
	}
	else	# Gerät ist als dummy definiert
	{
		$presence = "present";	# dummy immer als online melden
	}
	
	$presence = ReplaceEventMap($name, $presence, 1);	

# Readings anlegen und füllen	    
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "lastCmd","");
    readingsBulkUpdate($hash, "lastResult","");
    readingsBulkUpdate($hash, "menuPos","11");
	readingsBulkUpdate($hash, "mute","???"));
	readingsBulkUpdate($hash, "power","???"));
	readingsBulkUpdate($hash, "state",$presence);
	readingsEndUpdate($hash, 1);
    
    $hash->{helper}{AVAILABLE} = 1;    
    InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "LISTENLIVE_GetStatus", $hash, 0);

return;
}

#############################
sub
LISTENLIVE_SendCommand($$;$)
{
    my ($hash, $command, $loglevel) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $port = $hash->{helper}{PORT};
    my $response = "";
    my $modus = "dummy";
    my ($socket,$client_socket);

	$loglevel = GetLogLevel($name, 3) unless(defined($loglevel));
	Log $loglevel, "LISTENLIVE $name command: $command";
	
	if (Value("$name") eq "online" && $hash->{helper}{ADDRESS} ne "none")	{ $modus = "online"; }
	if (Value("$name") eq "offline") 										{ $modus = "offline"; }

	given($modus)
	{
		when("online")
		{
			#
			# Create a socket object for the communication with the radio
			#
			$socket = new IO::Socket::INET (
				PeerHost => $address,
				PeerPort => $port,
				Proto => 'tcp',
			) or die "ERROR in Socket Creation : $!\n";

			#
			# Send the given command into the socket
			#
			$socket->send($command);

			#
			# get the radio some time to execute the command (300ms )
			#
			usleep(30000);

			#
			# get the answer of the radio
			#
			$socket->recv($response, 2);


			if($response !~  m/OK/)
	    	{	
	    		Log 2, "LISTENLIVE $name error: $response";
	    	}
			else
	    	{
	    		Log $loglevel, "LISTENLIVE $name response: $response";
	    	}

			$socket->close();
    
			$hash->{helper}{AVAILABLE} = (defined($response) ? 1 : 0);
		}

		when("offline")
		{
			Log 2, "LISTENLIVE $name error: device offline!";
			$response = "device offline!";
		}

		default:
		{
			$response = "OK";
		}
	}

	return $response;
}

sub
LISTENLIVE_rbuError($$;$$)
{
    my ($hash, $area, $doit, $parameter) = @_;
	Log 2, "LISTENLIVE $hash->{NAME} error: $area $doit $parameter";

	readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastCmd","$area $doit $parameter");
    readingsBulkUpdate($hash, "lastResult","Error: $area $doit $parameter");
	readingsEndUpdate($hash, 1);
	return undef;
}


sub
LISTENLIVE_HelpGet()
{
my $helptext =
'get <device> <commandGroup> [<command>]


commandGroup "help"
get llradio help (show this help page)';

return $helptext;
}

sub
LISTENLIVE_HelpSet()
{
my $helptext =
'set <device> <commandGroup> [<command>]


commandGroup "help"
set llradio help (show this help page)


commandGroup "audio"
set llradio audio mute
set llradio audio unmute
set llradio audio volm
set llradio audio volp


commandGroup "cursor"
set llradio cursor down
set llradio cursor left
set llradio cursor up
set llradio cursor right

set llradio cursor enter
set llradio cursor exit
set llradio cursor home
set llradio cursor ok


commandGroup "power"
set llradio power off
set llradio power on


commandGroup "raw"
set llradio raw <command>


commandGroup "reset"
set llradio reset menupos
set llradio reset mute
set llradio reset power


commandGroup "user"  (experimental!)
set llradio user <userDefFunction>


commandGroup "app"  (experimental!)
set llradio app weather


commandGroup "statusRequest"
set llradio statusRequest';

return $helptext;
}

#############################
sub
LISTENLIVE_Undefine($$)
{
  my($hash, $name) = @_;
  
  # Stop the internal GetStatus-Loop and exist
  RemoveInternalTimer($hash);
  return undef;
}

1;

=pod
=begin html
<h3>LISTENLIVE</h3>
<ul>

  <a name="LISTENLIVEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LISTENLIVE &lt;ip-address&gt;[:&lt;port&gt;] [&lt;status_interval&gt;]</code>
    <br/><br/>

    This module can control all mediaplayers runnng ListenLive Firmware laufen via a network connection.
    It can control power state on/off, volume up/down/mute and can send all remomte-control commands.
    <br/><br/>
    The port value is optional. If not defined, standard port 8080 will be used.
    <br/><br/>
	The status_interval value is optional. If not defined, standard interval 60sec will be used.
	<br/><br/>
    Upon the definition of a new LISTENLIVE-device an internal Loop will be defined which will check and update the device readings
    all <status_interval> seconds to trigger all notify and FileLog entities.
    <br><br>

    Example:
    <br/><br/>
    <ul><code>
       define llradio LISTENLIVE 192.168.0.10<br><br>
       
       define llradio LISTENLIVE 192.168.0.10:8085 120 &nbsp;&nbsp;&nbsp; # with port (8085) und status interval (120 seconds)
    </code></ul><br><br>
  </ul>
  
  <a name="LISTENLIVEset"></a>
  <b>Set-Commands </b>
  <ul>
    <code>set &lt;name&gt; &lt;commandGroup&gt; [&lt;command&gt;] [&lt;parameter&gt;]</code>
    <br><br>
    Commands are grouped into commandGroups depending on their functional tasks.
    The following groups and commands are currently available:
    <br><br>
<ul><code>
commandGroup power<br>
power on<br>
power off<br>
<br>
commandGroup audio<br>
audio mute<br>
audio unmute<br>
audio volm<br>
audio volp<br>
<br>
commandGroup cursor<br>
cursor up<br>
cursor down<br>
cursor left<br>
cursor right<br>
cursor home<br>
cursor exit<br>
cursor enter<br>
cursor ok<br>
<br>
commandGroup reset<br>
reset power<br>
reset mute<br>
reset menupos<br>
<br>
commandGroup raw<br>
raw <command><br>
<br>
commandGroup user (experimental)<br>
user <userDefinedFunction><br>
<br>
commandGroup app (experimental)<br>
app weather<br>
<br>
commandGroup help<br>
help<br>
<br>
commandGroup statusRequest<br>
statusRequest
</code></ul>
</ul>
<br><br>
  <a name="LISTENLIVEget"></a>
  <b>Get-Commands</b>
  <ul>
    <code>get &lt;name&gt; &lt;parameter&gt;</code>
    <br><br>
    The following parameters are available:<br><br>
     <ul>
     <li><code>help</code> - show help-text</li>
     </ul>
  </ul>
  <br>
<br><br>
  <a name="YAMAHA_AVRattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a href="#eventMap">eventMap</a>
	The attribute eventMap <code>absent:offline present:online</code> is created automagically.</li>
  </ul>
  <br><br>
  <b>Generated Readings/Events:</b><br>
  <ul>
  <li><b>lastCmd</b> - last command sent to device</li>
  <li><b>lastResult</b> - last response from device</li>
  <li><b>menuPos</b> - cursor position in main menu (experimental)</li>
  <li><b>mute</b> - current mute state ("on" =&gt; muted, "off" =&gt; unmuted)</li>
  <li><b>power</b> - current power state</li>
  <li><b>state</b> - current device state (online or offline)</li>
  </ul>
  <br><br>
  <b>Author's notes</b>
  <ul>
    You need to activate option "remote control settings" -> "network remote control [on]" in your device's settings.
    <br><br>
    Upon the device definion a corresponding PRESENCE-entity will be created to evaluate the device availability.
    <br>
  </ul>
</ul>
=end html
=begin html_DE
<a name="LISTENLIVE"></a>
<h3>LISTENLIVE</h3>
<ul>

  <a name="LISTENLIVEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LISTENLIVE &lt;ip-address&gt;[:&lt;port&gt;] [&lt;status_interval&gt;]</code>
    <br/><br/>

    Dieses Modul steuert Internetradios, die mit der ListenLive Firmware laufen, &uuml;ber die Netzwerkschnittstelle.
    Es bietet die M&ouml;glichkeit das Ger&auml;t an-/auszuschalten, die Lautst&auml;rke zu &auml;ndern, den Cursor zu steuern,
    den Receiver "Stumm" zu schalten, sowie alle Fernbedienungskommandos an das Ger&auml;t zu senden.
    <br/><br/>
    Die Angabe des TCP-ports ist optional. Fehlt dieser Parameter, wird der Standardwert 8080 verwendet.
    <br/><br/>
    Bei der Definition eines LISTENLIVE-Ger&auml;tes wird eine interne Routine in Gang gesetzt, welche regelm&auml;&szlig;ig 
    (einstellbar durch den optionalen Parameter <code>&lt;status_interval&gt;</code>; falls nicht gesetzt ist der Standardwert 60 Sekunden)
    den Status des Ger&auml;tes abfragt und entsprechende Notify-/FileLog-Ger&auml;te triggert..<br><br>

    Beispiel:
    <br/><br/>
    <ul><code>
       define llradio LISTENLIVE 192.168.0.10<br><br>
       
       define llradio LISTENLIVE 192.168.0.10:8085 120 &nbsp;&nbsp;&nbsp; # Mit modifiziertem Port (8085) und Status Interval (120 Sekunden)
    </code></ul><br><br>
  </ul>
  
  <a name="LISTENLIVEset"></a>
  <b>Set-Kommandos </b>
  <ul>
    <code>set &lt;Name&gt; &lt;Befehlsgruppe&gt; [&lt;Befehl&gt;] [&lt;Parameter&gt;]</code>
    <br><br>
    Die Befehle zur Steuerung sind weitgehend in Befehlsgruppen eingeordnet, die sich an logischen Funktionsbereichen orientieren.
    Aktuell stehen folgende Befehlsgruppen und Befehele zur Verf&uuml;gung:
<br><br>
<ul><code>
Befehlsgruppe power<br>
power on<br>
power off<br>
<br>
Befehlsgruppe audio<br>
audio mute<br>
audio unmute<br>
audio volm<br>
audio volp<br>
<br>
Befehlsgruppe cursor<br>
cursor up<br>
cursor down<br>
cursor left<br>
cursor right<br>
cursor home<br>
cursor exit<br>
cursor enter<br>
cursor ok<br>
<br>
Befehlsgruppe reset<br>
reset power<br>
reset mute<br>
reset menupos<br>
<br>
Befehlsgruppe raw<br>
raw <command><br>
<br>
Befehlsgruppe user (experimentell)<br>
user <userDefinedFunction><br>
<br>
Befehlsgruppe app (experimentell)<br>
app weather<br>
<br>
Befehlsgruppe help<br>
help<br>
<br>
Befehlsgruppe statusRequest<br>
statusRequest
</code></ul>
</ul>
<br><br>
  <a name="LISTENLIVEget"></a>
  <b>Get-Kommandos</b>
  <ul>
    <code>get &lt;Name&gt; &lt;Parameter&gt;</code>
    <br><br>
    Aktuell stehen folgende Parameter zur Verf&uuml;gung:<br><br>
     <ul>
     <li><code>help</code> - zeigt einen Hilfetext an</li>
     </ul>
  </ul>
  <br>
<br><br>
  <a name="YAMAHA_AVRattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a href="#eventMap">eventMap</a>
	Die eventMap <code>absent:offline present:online</code> wird bei der Definition des Ger&auml;tes automatisch angelegt.</li>
  </ul>
  <br><br>
  <b>Generierte Readings/Events:</b><br>
  <ul>
  <li><b>lastCmd</b> - der letzte gesendete Befehl</li>
  <li><b>lastResult</b> - die letzte Antwort des Ger&auml;tes</li>
  <li><b>menuPos</b> - Cursorposition im Hauptmen&uuml; (experimentell)</li>
  <li><b>mute</b> - der aktuelle Stumm-Status("on" =&gt; Stumm, "off" =&gt; Laut)</li>
  <li><b>power</b> - der aktuelle Betriebsstatuse ("on" =&gt; an, "off" =&gt; aus)</li>
  <li><b>state</b> - der aktuelle Ger&auml;testatus (online oder offline)</li>
  </ul>
  <br><br>
  <b>Hinweise</b>
  <ul>
    Dieses Modul ist nur nutzbar, wenn die Option "remote control settings" -> "network remote control [on]" in der Firmware aktiviert ist.
    <br><br>
    W&auml;hrend der Definition wird automatisch ein passendes PRESENCE angelegt, um die Verf&uuml;gbarkeit des Ger&auml;tes zu ermitteln.
    <br>
  </ul>
</ul>
=end html_DE

=cut
