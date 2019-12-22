# $Id$
############################################################################
# 2018-10-12, v0.0.11
#
# v0.0.11
# - BUGFIX:  https://forum.fhem.de/index.php/topic,81929.msg844975.html#msg844975
#
# v0.0.10
# - BUGFIX:  Readings mit 0 wurden nicht geschrieben
# - CHANGE:  readingsBulkUpdateIfChanged to readingsBulkUpdate
#
# v0.0.9
# - BUGFIX:  Reading "online"
#
# v0.0.8
# - FEATURE: Reading "online"
#
# v0.0.7
# - BUGFIX:  Logeinträge PERL WARNING: Use of uninitialized value $value in string eq at fhem.pl line 4547
#
# v0.0.6
# - BUGFIX:  https://forum.fhem.de/index.php/topic,81929.msg780110.html#msg780110
#
# v0.0.5
# - BUGFIX:  https://forum.fhem.de/index.php/topic,81929.msg756900.html#msg756900
#
# v0.0.3
# - BUGFIX:  Readings anzeigen von Umlauten
# - CHANGE:  Send Data nonBlocking
# - FEATURE: Add Support psucontrol inkl. set Befehle turnPSUOn, turnPSUOff und togglePSU (Aktivierung über Attribut "plugin_psucontrol")
#            Neue Set Befehle move_axis_x, move_axis_y, move_axis_z und extrude
#
# v0.0.2 BETA
# - FEATURE: Navigieren (gohome)
#            Shutdown / Reboot / Restart (OctoPrint)
#            send_gcode z.B. M500
#
# v0.0.1 BETA
# - FEATURE: Read div. Readings
#            start/stop/connect/disconnect printer
#
#     70_OctoPrint.pm
#     Copyright by Michael Winkler
#     e-mail: michael.winkler at online.de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it andor modify
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
use HttpUtils;
use Encode;
use Time::Piece;
use LWP::UserAgent;

no warnings "all";

sub OctoPrint_Set($@);
sub OctoPrint_GetStatus($;$);
sub OctoPrint_Define($$);
sub OctoPrint_Undefine($$);

###################################
sub OctoPrint_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "OctoPrint_Initialize: Entering";

    $hash->{SetFn}   = "OctoPrint_Set";
    $hash->{DefFn}   = "OctoPrint_Define";
    $hash->{UndefFn} = "OctoPrint_Undefine";

    $hash->{AttrList} = "apikey plugin_psucontrol:0,1 " . $readingFnAttributes;
  
    return;
}

sub OctoPrint_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    my $name = $hash->{NAME};

    Log3 $name, 0, "OctoPrint $name [OctoPrint_Define] start device";

    eval { require XML::Simple; };
    return "Please install Perl XML::Simple to use module OctoPrint"
      if ($@);

    if ( int(@a) < 3 ) {
        my $msg = "Wrong syntax: define <name> OctoPrint <ip-or-hostname> [<port>] [<poll-interval>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    $hash->{TYPE} = "OctoPrint";

    my $address = $a[2];
    $hash->{helper}{ADDRESS} = $address;

    # use port 80 if not defined
    my $port = $a[3] || 80;
    $hash->{helper}{PORT} = $port;

    # use interval of 45sec if not defined
    my $interval = $a[4] || 45;
    $hash->{INTERVAL} = $interval;
 
    $hash->{helper}{CMD_QUEUE} = ();
    delete($hash->{helper}{HTTP_CONNECTION}) if(exists($hash->{helper}{HTTP_CONNECTION}));
	
    # set default settings on first define
    if ($init_done) {
        $attr{$name}{icon} = 'it_printer';
    }

    # start the status update timer
    InternalTimer( gettimeofday() + 2, "OctoPrint_GetStatus", $hash, 1 );

    return;
}

sub OctoPrint_Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "OctoPrint $name [OctoPrint_Undefine] called function";

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return;
}

sub OctoPrint_GetStatus($;$) {
    my ( $hash, $update ) = @_;
    my $name     = $hash->{NAME};
    my $interval = $hash->{INTERVAL};

    Log3 $name, 5, "OctoPrint $name [OctoPrint_GetStatus] called function";
	if ($update ne '') {Log3 $name, 5, "OctoPrint $name [OctoPrint_GetStatus] Update = $update";}
	
    #RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + $interval, "OctoPrint_GetStatus", $hash, 0 );

    return if ( AttrVal( $name, "disable", 0 ) == 1 );

    if ( !$update ) {
		OctoPrint_RefreshData($hash)
	}
	
    return;
}

sub OctoPrint_RefreshData($){
    my ( $hash ) = @_;
	my $name     = $hash->{NAME};
	OctoPrint_SendCommand( $hash, "readings_job" );
	OctoPrint_SendCommand( $hash, "readings_printer" );
	OctoPrint_SendCommand( $hash, "getPSUState", "" ) if (AttrVal( $name, "plugin_psucontrol", 0 ) == 1);
}

sub OctoPrint_Set($@) {
    my ( $hash, @a ) = @_;
    my $name     = $hash->{NAME};

	shift @a;
	my $command       = shift @a;
	my $parameter     = join(' ',@a);
	
	#2017.07.21 - Log nur schreiben wenn set nicht initialisiert wird
	if ($command ne '?') {
		Log3 $name, 5, "Octoprint $name [OctoPrint_Set] called function";
		
		Log3 $name, 3, "Octoprint $name [OctoPrint_Set] [" . $command . "] set";
	}
   
    return "No Argument given" if ( !defined( $command ) );

	my $usage = "Unknown argument " . $command . ", choose one of job:start,cancel printer:connect,disconnect,gohome powermode:shutdown,restart,reboot send_gcode move_axis_z move_axis_y move_axis_x extrude ";
	
	$usage .= "turnPSUOn:noArg turnPSUOff:noArg togglePSU:noArg " if (AttrVal( $name, "plugin_psucontrol", 0 ) == 1);
	
    # job informationen
    if ( lc( $command ) eq "job" ) {
		OctoPrint_SendCommand( $hash, "job" , $parameter );
    }
	elsif ( lc( $command ) eq "printer" ) {
		OctoPrint_SendCommand( $hash, "printer_" . $parameter );
    }
	elsif ( lc( $command ) eq "powermode" ) {
		OctoPrint_SendCommand( $hash, "octoprint_" . $parameter );
    }
	elsif ( lc( $command ) eq "send_gcode" ) {
		OctoPrint_SendCommand( $hash, "send_gcode", $parameter );
    }
	elsif ( lc( $command ) eq "move_axis_z" ) {
		OctoPrint_SendCommand( $hash, "move_axis_z", $parameter );
    }
	elsif ( lc( $command ) eq "move_axis_x" ) {
		OctoPrint_SendCommand( $hash, "move_axis_x", $parameter );
    }
	elsif ( lc( $command ) eq "move_axis_y" ) {
		OctoPrint_SendCommand( $hash, "move_axis_y", $parameter );
    }
	elsif ( lc( $command ) eq "extrude" ) {
		OctoPrint_SendCommand( $hash, "extrude", $parameter );
    }
	elsif ($command eq "turnPSUOn" ) {
		OctoPrint_SendCommand( $hash, "turnPSUOn", "" );
    }
	elsif ($command eq "turnPSUOff" ) {
		OctoPrint_SendCommand( $hash, "turnPSUOff", "" );
    }
	elsif ($command eq "togglePSU" ) {
		OctoPrint_SendCommand( $hash, "togglePSU", "" );
    }
    # return usage hint
    else {
        return $usage;
    }

    return;
}

sub OctoPrint_ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash     = $param->{hash};
    my $name     = $hash->{NAME};
    my $service  = $param->{service};
    my $cmd      = $param->{cmd};
    my $type     = ( $param->{type} ) ? $param->{type} : "";
    my $return;
	my $line;
	my $UnixDate = time();

	if  (eval {require JSON;1;} ne 1) {Log3 $name, 3, "OctoPrint $name [OctoPrint_ReceiveCommand] missing JSON modul";}
	
	Log3 $name, 5, "OctoPrint $name [OctoPrint_ReceiveCommand] called function";
	Log3 $name, 5, "OctoPrint $name [OctoPrint_ReceiveCommand] [$service] Data = $data";
    	
	#my $dJSON;
	my $dJSON = eval { JSON->new->utf8(0)->decode($data) };
	#eval { $dJSON = decode_json($data); 1; };
	
	Log3 $name, 5, "OctoPrint $name [OctoPrint_ReceiveCommand] [$service] JSON = $dJSON";
	
	$hash->{helper}{RUNNING_REQUEST} = 0;
	
    delete($hash->{helper}{HTTP_CONNECTION}) unless($param->{keepalive});
		
	readingsBeginUpdate($hash);
	
	# Job Informationen
	if ($dJSON eq "") {
		Log3 $name, 5, "OctoPrint $name [OctoPrint_ReceiveCommand] [$service] JSON = NODATA";
		if ($err) {
			readingsBulkUpdate($hash, "online", "false" ) ;
			Log3 $name, 5, "OctoPrint $name [OctoPrint_ReceiveCommand] ERROR = $err";
		}
		else {
			readingsBulkUpdate($hash, "online", "true" ) ;
		}
	}
	elsif ($service eq "readings_job"){
		OctoPrint_expandJSON($hash,$name,"",$dJSON);
	}

	elsif ($service eq "readings_printer"){
		OctoPrint_expandJSON($hash,$name,"",$dJSON);
	}
	
	elsif ($service eq "getPSUState"){
		readingsBulkUpdate($hash, "PSUIsOn", $dJSON->{"isPSUOn"} ) ;
		#OctoPrint_expandJSON($hash,$name,"",$dJSON);
	}
	else{
		OctoPrint_RefreshData($hash)
	}

	readingsEndUpdate( $hash, 1 );
	
	OctoPrint_HD_HandleCmdQueue($hash);
	
    undef $return;
    return;
}

sub OctoPrint_SendCommand($$;$$) {
    my ( $hash, $service, $cmd, $type ) = @_;
    my $name            = $hash->{NAME};
    my $address         = $hash->{helper}{ADDRESS};
    my $port            = $hash->{helper}{PORT};
	my $ApiKey          = AttrVal( $name, "apikey", "0" );
	my $serviceurl;
	my $param;
    my $senddata		= "";
	my $method = "GET";
	
    Log3 $name, 5, "OctoPrint $name [OctoPrint_SendCommand] called function CMD = $cmd ";

    my $http_proto;
    if ( $port eq "443" ) {
        $http_proto = "https";
        Log3 $name, 5, "OctoPrint $name [OctoPrint_SendCommand] port 443 implies using HTTPS";
    }
    elsif ( AttrVal( $name, "https", "0" ) eq "1" ) {
        Log3 $name, 5, "OctoPrint $name [OctoPrint_SendCommand] explicit use of HTTPS";
        $http_proto = "https";
        if ( $port eq "80" ) {
            $port = "443";
            Log3 $name, 5,
              "OctoPrint $name [OctoPrint_SendCommand] implicit change of from port 80 to 443";
        }
    }
    else {
        Log3 $name, 5, "OctoPrint $name [OctoPrint_SendCommand] using unencrypted connection via HTTP";
        $http_proto = "http";
    }
    
    my $URL;

	# Check Service and change serviceurl
	if ($service eq "readings_job") {
		$serviceurl = "job?";
	}
	elsif ($service eq "extrude") {
		$serviceurl = "printer/tool?";
		$senddata = '{"command": "extrude","amount": '.$cmd.'}';
		$method = "POST";
	}
	elsif ($service eq "move_axis_z") {
		$serviceurl = "printer/printhead?";
		$senddata = '{"command": "jog","z": '.$cmd.'}';
		$method = "POST";
	}
	elsif ($service eq "move_axis_x") {
		$serviceurl = "printer/printhead?";
		$senddata = '{"command": "jog","x": '.$cmd.'}';
		$method = "POST";
	}	
	elsif ($service eq "move_axis_y") {
		$serviceurl = "printer/printhead?";
		$senddata = '{"command": "jog","y": '.$cmd.'}';
		$method = "POST";
	}	
	elsif ($service eq "readings_printer") {
		$serviceurl = "printer?exclude=state,sd";
	}
	elsif ($service eq "job") {
		$serviceurl = "job?";
		$senddata = '{"command": "' . $cmd . '"}';
		$method = "POST";
	}
	elsif ($service eq "printer_connect") {
		$serviceurl = "connection?";
		$senddata = '{"command": "connect"}';
		$method = "POST";
	}
	elsif ($service eq "printer_disconnect") {
		$serviceurl = "connection?";
		$senddata = '{"command": "disconnect"}';
		$method = "POST";
	}	
	elsif ($service eq "printer_gohome") {
		$serviceurl = "printer/printhead?";
		$senddata = '{"command": "home","axes": ["x","y","z"]}';
		$method = "POST";
	}	
	elsif ($service eq "octoprint_restart") {
		$serviceurl = "system/commands/core/restart?";
		$senddata = '{"action": "restart"}';
		$method = "POST";
	}
	elsif ($service eq "octoprint_reboot") {
		$serviceurl = "system/commands/core/reboot?";
		$senddata = '{"action": "reboot"}';
		$method = "POST";
	}
	elsif ($service eq "octoprint_shutdown") {
		$serviceurl = "system/commands/core/shutdown?";
		$senddata = '{"action": "shutdown"}';
		$method = "POST";
	}
	elsif ($service eq "send_gcode") {
		$serviceurl = "printer/command?";
		$senddata = '{"command": "' . $cmd . '"}';
		$method = "POST";
	}
	elsif ($service eq "getPSUState" || $service eq "turnPSUOn" || $service eq "turnPSUOff" || $service eq "togglePSU") {
		$serviceurl = "plugin/psucontrol?";
		$senddata = '{"command": "'.$service.'"}';
		$method = "POST";
	}	
	else{
		$serviceurl = $service;
	}

	$URL = $http_proto . "://" . $address . ":" . $port . "/api/" . $serviceurl ."&apikey=" .$ApiKey ;

	#2017.07.19 - Übergabe SendCommandQuery
	$param = {
		url        => $URL,
		service    => $service,
		cmd        => $cmd,
		type       => $type,
		data       => $senddata,
		method     => $method,
		header     => 'Content-Type: application/json', #"User-Agent: None\r\nContent-Type: application/json ;charset=utf-8\r\n",
		callback   => \&OctoPrint_ReceiveCommand,
	};
		
	OctoPrint_HD_SendCommand($hash,$param);
	
    return;
}

sub OctoPrint_HD_SendCommand($$) {
    my ($hash, $param) = @_;
    my $name = $hash->{NAME};
     
    Log3 $name, 5, "OctoPrint $name [OctoPrint_HD_SendCommand] - append to queue " .$param->{url};
    
    # In case any URL changes must be made, this part is separated in this function".
    
    push @{$hash->{helper}{CMD_QUEUE}}, $param;  
    
	OctoPrint_HD_HandleCmdQueue($hash);
}

sub OctoPrint_HD_HandleCmdQueue($) {
    my ($hash, $param)  = @_;
    my $name            = $hash->{NAME};
	my $http_noshutdown = AttrVal( $name, "http-noshutdown", "0" );
	my $http_timeout    = AttrVal( $name, "timeout", "2" );
		
    if(not($hash->{helper}{RUNNING_REQUEST}) and @{$hash->{helper}{CMD_QUEUE}})
    {
  
		my $params =  {
                       url        => $param->{url},
                       timeout    => $http_timeout,
                       noshutdown => $http_noshutdown,
                       keepalive  => 0,
					   data       => $param->{data},
                       hash       => $hash,
					   header     => "agent: FHEM/1.0\r\nUser-Agent: FHEM/1.0\r\nContent-Type: application/json",
                       callback   => \&OctoPrint_ReceiveCommand
                      };
  
        my $request = pop @{$hash->{helper}{CMD_QUEUE}};

        map {$hash->{helper}{HTTP_CONNECTION}{$_} = $params->{$_}} keys %{$params};
        map {$hash->{helper}{HTTP_CONNECTION}{$_} = $request->{$_}} keys %{$request};
        
        $hash->{helper}{RUNNING_REQUEST} = 1;
		
        Log3 $name, 5, "OctoPrint $name [OctoPrint_HD_HandleCmdQueue] - send command url  = " .$hash->{helper}{HTTP_CONNECTION}{url};
		Log3 $name, 5, "OctoPrint $name [OctoPrint_HD_HandleCmdQueue] - send command data = " .$hash->{helper}{HTTP_CONNECTION}{data};
		Log3 $name, 5, "OctoPrint $name [OctoPrint_HD_HandleCmdQueue] - send command head = " .$hash->{helper}{HTTP_CONNECTION}{header};
        HttpUtils_NonblockingGet($hash->{helper}{HTTP_CONNECTION});
    }
}

sub OctoPrint_expandJSON($$$$;$$) {
	my ($hash,$dhash,$sPrefix,$ref,$prefix,$suffix) = @_;
	my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
	
	$prefix = "" if( !$prefix );
	$suffix = "" if( !$suffix );
	$suffix = "_$suffix" if( $suffix );

	if( ref( $ref ) eq "ARRAY" ) {
		while( my ($key,$value) = each @{ $ref } ) {
			OctoPrint_expandJSON($hash,$name,"",$value, $prefix.sprintf("%02i",$key+1)."_");
		}
	}
	
	elsif( ref( $ref ) eq "HASH" ) {
		while( my ($key,$value) = each %{ $ref } ) {
			if( ref( $value ) ) {
				OctoPrint_expandJSON($hash,$name,"",$value,$prefix.$key.$suffix."_");
			}
			else {
				(my $reading = $sPrefix.$prefix.$key.$suffix) =~ s/[^A-Za-z\d_\.\-\/]/_/g;
				
				#my $unicode = decode('ISO-8859-1',$value);
				#readingsBulkUpdate($hash, $reading, encode('UTF-8', $unicode) ) if($value ne "");
				readingsBulkUpdate($hash, $reading, encode('UTF-8', $value) ) if($value ne "");
				#readingsBulkUpdate($hash, $reading, $value ) if($value ne "");
			}
		}
	}
}

###################################

1;

=pod
=item device
=item summary control for OctoPrint
=item summary_DE Steuerung von OctoPrint
=begin html

    <p>
      <a name="OctoPrint" id="OctoPrint"></a>
    </p>
    <h3>
      OctoPrint
    </h3>

=end html

=begin html_DE

    <p>
      <a name="OctoPrint" id="OctoPrint"></a>
    </p>
    <h3>
      OctoPrint
    </h3>

=end html_DE

=cut