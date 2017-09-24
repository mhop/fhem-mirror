# $Id$
############################################################################
# 2017-09-11, v1.0.12
#
# v1.0.12
# - BUFIX:   $_ ersetzt durch $uResult
#
# v1.0.11
# - BUFIX:   Code Optimierungen
#
# v1.0.10
# - BUFIX:   Code Optimierungen
#
# v1.0.9
# - BUFIX:   BUG EPG Info https://forum.fhem.de/index.php/topic,54481.msg665959.html#msg665959
#            Change Volume
# - CHANGE   Readings für EPG zurücksetzen wenn keine Infos vorhanden sind
#
# v1.0.8
# - BUFIX:   Code Optimierungen
#            Zeilenumbruch in EPG Informationen entfernt
#            NEUTRINO BUG Umschalten wenn EGP und CHANNEL_ID nicht passen!
#            BUG leeres EPG https://forum.fhem.de/index.php/topic,54481.msg665355.html#msg665355
#
# v1.0.7 erste SVN Version
# - FEATURE: Reading Model hinzugefügt
# - CHANGE   CommandRef ergänzt
# - BUFIX:   Optimierung Neutrino Version/Model auslesen bei
#             Änderung Power
#             Initialisierung Device
#
# v1.0.6
# - FEATURE: CommandRef hinzugefügt (DE/EN)
# - BUFIX:   Optimierung Refresh Infos Senderwechsel (EPGInfos, input, Bouquetliste)
#            Optimierung Refresh EGPInfos (Wenn Sendung vorbei)
#            Optimierung Neutrino Version nur auslesen wenn sich das Reading "power" ändert!
#            Optimierung Reading time_now / time_raw_now (Wird vom FHEM Server verwendet/ Infos kommen nicht mehr von Neutrino)
#            Probleme beim Umschalten von Kanälen mit + Zeichen
#            Logeinträge überarbeitet
#            div. Codeoptimierungen
# - CHANGE   HTTP Standardtimout auf 2 gesetzt
#            NEUTRINO_HD_HandleCmdQueue hinzugefügt
#            NEUTRINO_HD_SendCommand hinzugefügt
#            Nicht verwendete Attribute entfernt
#             bouquet-tv
#             bouquet-radio
#             remotecontrol
#             lightMode
#             macaddr
#             wakeupCmd
#             http_method
#
# v1.0.5 BETA5 - 20160626
# - BUGFIX:  clear readings timerlist
#
# v1.0.4 BETA4 - 20160624
# - BUGFIX:  Not an ARRAY reference at ./FHEM/70_NEUTRINO.pm line 1237
#
# v1.0.3 BETA3 - 20160614
# - FEATURE: add recordchannel reading
#            add recordtitel reading
#
# v1.0.2 BETA2 - 20160613
# - FEATURE: add timer readings
#
# v1.0.0 BETA1 - 20160612
# - FEATURE: add recordmode reading
#
#     70_NEUTRINO.pm
#     An FHEM Perl module for controlling NEUTRINO based TV receivers
#     via network connection.
#
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

no warnings "all";

sub NEUTRINO_Set($@);
sub NEUTRINO_Get($@);
sub NEUTRINO_GetStatus($;$);
sub NEUTRINO_Define($$);
sub NEUTRINO_Undefine($$);

###################################
sub NEUTRINO_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "NEUTRINO_Initialize: Entering";

    $hash->{GetFn}   = "NEUTRINO_Get";
	$hash->{AttrFn}  = "NEUTRINO_Attr";
    $hash->{SetFn}   = "NEUTRINO_Set";
    $hash->{DefFn}   = "NEUTRINO_Define";
    $hash->{UndefFn} = "NEUTRINO_Undefine";

    $hash->{AttrList} = "https:0,1 http-method:absolete http-noshutdown:1,0 disable:0,1 timeout " . $readingFnAttributes;
  
    return;
}

#####################################
# AttrFn
#####################################
sub NEUTRINO_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;
	
	if( $attrName eq "bouquet-tv" || $attrName eq "bouquet-radio" || $attrName eq "remotecontrol" || $attrName eq "http-method" || $attrName eq "wakeupCmd" || $attrName eq "macaddr" || $attrName eq "lightMode" ) {
		if( $cmd eq "set" ) {
			Log3 $name, 3, "NEUTRINO $name [NEUTRINO_Attr] [$attrName] - !!! Attention, the attribut is absolete and will delete in the future";
			return "NEUTRINO $name [NEUTRINO_Attr] [$attrName] - !!! Attention, the attribut is absolete and will delete in the future";
		}
	}
}

#####################################
# Get Status
#####################################
sub NEUTRINO_GetStatus($;$) {
    my ( $hash, $update ) = @_;
    my $name     = $hash->{NAME};
    my $interval = $hash->{INTERVAL};

    Log3 $name, 5, "NEUTRINO $name [NEUTRINO_GetStatus] called function";
	if ($update ne '') {Log3 $name, 5, "NEUTRINO $name [NEUTRINO_GetStatus] Update = $update";}
	
    #RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + $interval, "NEUTRINO_GetStatus", $hash, 0 );

    return if ( AttrVal( $name, "disable", 0 ) == 1 );

    if ( !$update ) {NEUTRINO_SendCommand( $hash, "powerstate" );}
	
    return;
}

###################################
sub NEUTRINO_SendCommand($$;$$) {
    my ( $hash, $service, $cmd, $type ) = @_;
    my $name            = $hash->{NAME};
    my $address         = $hash->{helper}{ADDRESS};
    my $port            = $hash->{helper}{PORT};
	my $serviceurl;
	my $channelid 		= ReadingsVal( $name, "channel_id", "" );
	my $param;
	
	# Cannelname
	my $channelname 	= ReadingsVal( $name, "recordchannel", "" );
	$channelname =~ s/_/%20/g;
	
    #$cmd = ( defined($cmd) ) ? $cmd : "";

    Log3 $name, 5, "NEUTRINO $name [NEUTRINO_SendCommand] called function CMD = $cmd ";

    my $http_proto;
    if ( $port eq "443" ) {
        $http_proto = "https";
        Log3 $name, 5, "NEUTRINO $name [NEUTRINO_SendCommand] port 443 implies using HTTPS";
    }
    elsif ( AttrVal( $name, "https", "0" ) eq "1" ) {
        Log3 $name, 5, "NEUTRINO $name [NEUTRINO_SendCommand] explicit use of HTTPS";
        $http_proto = "https";
        if ( $port eq "80" ) {
            $port = "443";
            Log3 $name, 5,
              "NEUTRINO $name [NEUTRINO_SendCommand] implicit change of from port 80 to 443";
        }
    }
    else {
        Log3 $name, 5, "NEUTRINO $name [NEUTRINO_SendCommand] using unencrypted connection via HTTP";
        $http_proto = "http";
    }

    my $http_user   = "";
    my $http_passwd = "";
    if (   defined( $hash->{helper}{USER} )
        && defined( $hash->{helper}{PASSWORD} ) )
    {
        Log3 $name, 5, "NEUTRINO $name [NEUTRINO_SendCommand] using BasicAuth";
        $http_user   = $hash->{helper}{USER};
        $http_passwd = $hash->{helper}{PASSWORD};
    }
    if ( defined( $hash->{helper}{USER} ) ) {
        Log3 $name, 5, "NEUTRINO $name [NEUTRINO_SendCommand] using BasicAuth (username only)";
        $http_user = $hash->{helper}{USER};
    }
    my $URL;
    my $response;
    my $return;

    if ( !defined($cmd) || $cmd eq "" ) {
        Log3 $name, 4, "NEUTRINO $name [NEUTRINO_SendCommand] SERVICE = $service";
    }
    else {
        #2017-07-14 - http_method deaktiviert
		$cmd = "?" . $cmd;
        #  if ( $http_method eq "GET" || $http_method eq "" );
        Log3 $name, 4, "NEUTRINO $name [NEUTRINO_SendCommand] SERVICE = $service/" . urlDecode($cmd);
    }

	# Check Service and change serviceurl
	if ($service eq "epginfo") {
		#2017.07.12 - $channelid entfernt! '$serviceurl = "epg?xml=true&channelid=" . $channelid . "&details=true&max=6";'
		$serviceurl = "epg?xml=true&details=true&max=6";
	}
	
	elsif ($service eq "epginforecord") {
		$serviceurl = 
					"epg?xml=true&channelname="
					. $channelname . "&max=6";
	}
	
	elsif ($service eq "timerlist") {
		$serviceurl = "timer";
	}
	
	elsif ($service eq "mutestate") {
		$serviceurl = "volume?status";
	}
	
	elsif ($service eq "mute") {
		$serviceurl = "volume?mute";
	}
	
	elsif ($service eq "unmute") {
		$serviceurl = "volume?unmute";
	}
	
	elsif ($service eq "recordmode") {
		$serviceurl = "setmode?status";
	}
	
	elsif ($service eq "powerstate") {
		$serviceurl = "standby";
	}
	
	elsif ($service eq "model") {
		$serviceurl = "info";
	}
	
	elsif ($service eq "bouquet") {
		$serviceurl = "getbouquet?actual";
	}
	
	elsif ($service eq "bouquet_list") {
		my $bouquet     = ReadingsVal( $name, "bouquetnr", "0" );
		my $bouquetset  = ReadingsVal( $name, "bouquetnr_set", "73482423648726384726384" );
		my $bouquetmode = ReadingsVal( $name, "input", "tv" );
		
		if (!($bouquet eq $bouquetset)) {
			$serviceurl = "getbouquet?bouquet=" . $bouquet . "&mode=" . $bouquetmode;
		}
		else{
			return "bouguet schon vorhanden!";
		}
		
	}
	
	else{
		$serviceurl = $service;
	}
	
	if ( $http_user ne "" && $http_passwd ne "" ) {
        $URL =
            $http_proto . "://"
          . $http_user . ":"
          . $http_passwd . "@"
          . $address . ":"
          . $port . "/control/"
          . $serviceurl;
        #2017-07-14 - http_method deaktiviert
		$URL .= $cmd; #if ( $http_method eq "GET" || $http_method eq "" );
    }
   
   elsif ( $http_user ne "" ) {
        $URL =
            $http_proto . "://"
          . $http_user . "@"
          . $address . ":"
          . $port . "/control/"
          . $serviceurl;
		#2017-07-14 - http_method deaktiviert
        $URL .= $cmd; #if ( $http_method eq "GET" || $http_method eq "" );
    }
   
   else {
        $URL =
          $http_proto . "://" . $address . ":" . $port . "/control/" . $serviceurl;
		  #2017-07-14 - http_method deaktiviert
		  $URL .= $cmd; #if ( $http_method eq "GET" || $http_method eq "" );
    }

	#2017.07.19 - Übergabe SendCommandQuery
	$param = {
		url        => $URL,
		service    => $service,
		cmd        => $cmd,
		type       => $type,
		callback   => \&NEUTRINO_ReceiveCommand,
	};
	
	NEUTRINO_HD_SendCommand($hash,$param);

    return;
}

#############################
# pushes new command to cmd queue
sub NEUTRINO_HD_SendCommand($$) {
    my ($hash, $param) = @_;
    my $name = $hash->{NAME};
     
    Log3 $name, 5, "NEUTRINO $name [NEUTRINO_HD_SendCommand] - append to queue " .$param->{url};
    
    # In case any URL changes must be made, this part is separated in this function".
    
    push @{$hash->{helper}{CMD_QUEUE}}, $param;  
    
	NEUTRINO_HD_HandleCmdQueue($hash);
}

#############################
# starts http requests from cmd queue
sub NEUTRINO_HD_HandleCmdQueue($) {
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
                       hash       => $hash,
                       callback   => \&NEUTRINO_ReceiveCommand
                      };
  
        my $request = pop @{$hash->{helper}{CMD_QUEUE}};

        map {$hash->{helper}{HTTP_CONNECTION}{$_} = $params->{$_}} keys %{$params};
        map {$hash->{helper}{HTTP_CONNECTION}{$_} = $request->{$_}} keys %{$request};
        
        $hash->{helper}{RUNNING_REQUEST} = 1;
		
        Log3 $name, 5, "NEUTRINO $name [NEUTRINO_HD_HandleCmdQueue] - send command " .$params->{url};
        HttpUtils_NonblockingGet($hash->{helper}{HTTP_CONNECTION});
    }
}

###################################
sub NEUTRINO_Get($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $what;

    return "argument is missing" if ( int(@a) < 2 );
	$what = $a[1];

	#2017.07.21 - Log nur schreiben wenn get nicht initialisiert wird
	if ($what ne '?') {
		Log3 $name, 5, "NEUTRINO $name [NEUTRINO_Get] [$what] called function";
	}

    if ( $what =~
/^(power|input|volume|mute|channel|currentTitle|channel_url)$/
      )
    {
        if ( ReadingsVal( $name, $what, "" ) ne "" ) {
            return ReadingsVal( $name, $what, "" );
        }
        else {
            return "no such reading: $what";
        }
    }
    
    else {
        return "Unknown argument $what, choose one of power:noArg input:noArg volume:noArg mute:noArg channel:noArg currentTitle:noArg channel_url:noArg ";
    }
}

###################################
sub NEUTRINO_Set($@) {
    my ( $hash, @a ) = @_;
    my $name     = $hash->{NAME};
    my $state    = ReadingsVal( $name, "state", "absent" );
    my $presence = ReadingsVal( $name, "presence", "absent" );
    my $input    = ReadingsVal( $name, "input", "" );
    my $channel  = ReadingsVal( $name, "channel", "" );
    my $channels = "";
	
	#2017.07.21 - Log nur schreiben wenn get nicht initialisiert wird
	if ($a[1] ne '?') {
		Log3 $name, 5, "NEUTRINO $name [NEUTRINO_Set] called function";
		
		Log3 $name, 5, "NEUTRINO $name [NEUTRINO_Set] [" . $a[1] . "] set";
	}
   
    return "No Argument given" if ( !defined( $a[1] ) );

    # load channel list
    if (
           defined($input)
        && defined($channel)
        && $input ne ""
        && $channel ne ""
        && (   !defined( $hash->{helper}{channels}{$input} )
            || !defined( $hash->{helper}{channels}{$input} ) )
      )
    {
        $channels = $channel . ",";
    }

    if (   $input ne ""
        && defined( $hash->{helper}{channels}{$input} )
        && ref( $hash->{helper}{channels}{$input} ) eq "ARRAY" )
    {
        $channels = join( ',', @{ $hash->{helper}{channels}{$input} } );
    }

    my $usage = "Unknown argument " . $a[1] . ", choose one of toggle:noArg on:noArg off:noArg volume:slider,0,1,100 remoteControl showText showtextwithbutton channel:" . $channels;
    
	$usage .= " mute:-,on,off"
      if ( ReadingsVal( $name, "mute", "-" ) eq "-" );
    
	$usage .= " mute:on,off"
      if ( ReadingsVal( $name, "mute", "-" ) ne "-" );
    
    $usage .= " reboot:noArg";
    $usage .= " shutdown:noArg";
    $usage .= " statusRequest:noArg";

    my $cmd = '';
    my $result;

    # statusRequest
    if ( lc( $a[1] ) eq "statusrequest" ) {
        NEUTRINO_GetStatus($hash);
    }

    # toggle
    elsif ( lc( $a[1] ) eq "toggle" ) {
        if ( $state ne "on" ) {
            return NEUTRINO_Set( $hash, $name, "on" );
        }
        else {
            return NEUTRINO_Set( $hash, $name, "off" );
        }
    }

    # shutdown
    elsif ( lc( $a[1] ) eq "shutdown" ) {

        if ( $state ne "absent" ) {
            $cmd = "shutdown";
            $result = NEUTRINO_SendCommand( $hash, "shutdown");
        }
        else {
            return "Device needs to be ON to be set to standby mode.";
        }
    }

    # reboot
    elsif ( lc( $a[1] ) eq "reboot" ) {
        if ( $state ne "absent" ) {
            $result = NEUTRINO_SendCommand( $hash, "reboot");
        }
        else {
            return "Device needs to be reachable to be rebooted.";
        }
    }

    # on
    elsif ( lc( $a[1] ) eq "on" ) {
        
		if ( $state eq "standby" ) {
            $cmd = "off";
            $result = NEUTRINO_SendCommand( $hash, "powerstate", $cmd, "off" );
        }
        else {
			return "Device needs to be reachable to be set to standby mode.";
        }
    }

    # off
    elsif ( lc( $a[1] ) eq "off" ) {
        if ( $state ne "absent" ) {
			$cmd = "on";
			NEUTRINO_SendCommand( $hash, "powerstate", $cmd, "on" );
        }
        else {
            return "Device needs to be reachable to be set to standby mode.";
        }
    }

    # volume
    elsif ( lc( $a[1] ) eq "volume" ) {
        if ( !defined( $a[2] ) ) {return "No argument given";}

        Log3 $name, 5, "NEUTRINO $name [NEUTRINO_Set] [" . $a[1] . "] " . $a[2];

        if ( $state eq "on" ) {
            my $uResult = $a[2];
            if ( $uResult =~ m/^\d+$/ && $uResult >= 0 && $uResult <= 100 ) {
                $cmd = $a[2];
            }
            else {
                return "Argument does not seem to be a valid integer between 0 and 100";
            }
            $result = NEUTRINO_SendCommand( $hash, "volume", $cmd );
        }
        else {
            return "Device needs to be ON to adjust volume.";
        }
    }

    # mute
    elsif ( lc( $a[1] ) eq "mute" || lc( $a[1] ) eq "mutet" ) {
        if ( $state eq "on" ) {
            if ( defined( $a[2] ) ) {
                Log3 $name, 5, "NEUTRINO $name [NEUTRINO_Set] [" . $a[1] . "] " . $a[2];
            }

            if ( lc( $a[2] ) eq "off" ) {
				NEUTRINO_SendCommand( $hash, "unmute", $cmd );
            }
            elsif ( lc( $a[2] ) eq "on" ) {
                NEUTRINO_SendCommand( $hash, "mute", $cmd );
            }
            else {
                return "Unknown argument " . $a[2];
            }
        }
        else {
            return "Device needs to be ON to mute/unmute audio.";
        }
    }
   
    # remoteControl
    elsif ( lc( $a[1] ) eq "remotecontrol" ) {

		if ( !defined( $a[2] ) ){return "No argument given.";}
	
        Log3 $name, 5, "NEUTRINO $name [NEUTRINO_Set] [" . $a[1] . "] " . $a[2];

		if ( defined( $a[2] )){
            $result = NEUTRINO_SendCommand( $hash, "rcem", $a[2] );
			return $result;
        }        
	
    }

    # channel
    elsif ( lc( $a[1] ) eq "channel" ) {
		
		if ( !defined( $a[2] ) ) {return "No argument given, choose one of channel channelNumber servicereference ";}

        if ( defined( $a[2] )
            && $presence eq "present"
            && $state ne "on" )
        {
            Log3 $name, 5, "NEUTRINO $name [NEUTRINO_Set] [" . $a[1] . "] indirect switching request to ON";
            NEUTRINO_Set( $hash, $name, "on" );
        }

		if ( defined( $a[3] ) ) {
			Log3 $name, 5, "NEUTRINO $name [NEUTRINO_Set] [" . $a[1] . "] " . $a[2] . "+" . $a[3];
		}
		else{
			Log3 $name, 5, "NEUTRINO $name [NEUTRINO_Set] [" . $a[1] . "] " . $a[2];
		}
 
        if ( $state eq "on" ) {
            my $uResult = $a[2];
			my $channellistname;
			
			#2017.07.19 - Plus Zeichen im Name erkennen
			if ( defined( $a[3] ) ) {
				# + Zeichen im Name erkannt!
				$channellistname = $a[2] . "%2B" . $a[3];
			}
			else {$channellistname = $a[2];}
						
			$channellistname =~ s/_/%20/g;
			NEUTRINO_SendCommand( $hash, "zapto", "name=$channellistname" );
        }
        else {
            return
              "Device needs to be present to switch to a specific channel.";
        }
    }
       
    # showText
    elsif ( lc( $a[1] ) eq "showtext" ) {
        if ( $state ne "absent" ) {
            
			if ( !defined( $a[2] ) ) {return "No argument given, choose one of messagetext ";}

            my $i    = 2;
            my $text = $a[$i];
            $i++;
            if ( defined( $a[$i] ) ) {
                my $arr_size = @a;
                while ( $i < $arr_size ) {
                    $text = $text . " " . $a[$i];
                    $i++;
                }
            }
            $cmd = "popup=" . urlEncode($text) ."&timeout=10";
            $result = NEUTRINO_SendCommand( $hash, "message", $cmd );
        }
        else {
            return "Device needs to be reachable to send a message to screen.";
        }
    }
	
	# showTextwithbutton
	elsif ( lc( $a[1] ) eq "showtextwithbutton" ) {
        if ( $state ne "absent" ) {
            if ( !defined( $a[2] ) ) {return "No argument given, choose one of messagetext";}

            my $i    = 2;
            my $text = $a[$i];
            $i++;
            if ( defined( $a[$i] ) ) {
                my $arr_size = @a;
                while ( $i < $arr_size ) {
                    $text = $text . " " . $a[$i];
                    $i++;
                }
            }
            $cmd = "nmsg=" . urlEncode($text);
            $result = NEUTRINO_SendCommand( $hash, "message", $cmd );
        }
        else {
            return "Device needs to be reachable to send a message to screen.";
        }
    }

    # return usage hint
    else {
        return $usage;
    }

    return;
}

###################################
sub NEUTRINO_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    my $name = $hash->{NAME};

    Log3 $name, 0, "NEUTRINO $name [NEUTRINO_Define] start device";

    eval { require XML::Simple; };
    return "Please install Perl XML::Simple to use module NEUTRINO"
      if ($@);

    if ( int(@a) < 3 ) {
        my $msg = "Wrong syntax: define <name> NEUTRINO <ip-or-hostname> [<port>] [<poll-interval>] [<http-user] [<http-password>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    $hash->{TYPE} = "NEUTRINO";

    my $address = $a[2];
    $hash->{helper}{ADDRESS} = $address;

    # use port 80 if not defined
    my $port = $a[3] || 80;
    $hash->{helper}{PORT} = $port;

    # use interval of 45sec if not defined
    my $interval = $a[4] || 45;
    $hash->{INTERVAL} = $interval;

    # set http user if defined
    my $http_user = $a[5];
    $hash->{helper}{USER} = $http_user if $http_user;

    # set http password if defined
    my $http_passwd = $a[6];
    $hash->{helper}{PASSWORD} = $http_passwd if $http_passwd;

    $hash->{helper}{CMD_QUEUE} = ();
    delete($hash->{helper}{HTTP_CONNECTION}) if(exists($hash->{helper}{HTTP_CONNECTION}));
	
    # set default settings on first define
    if ($init_done) {

        # use http-method POST for FritzBox environment as GET does not seem to
        # work properly. Might restrict use to newer
        # NEUTRINO Webif versions or use of OWIF only.
        if ( exists $ENV{CONFIG_PRODUKT_NAME}
            && defined $ENV{CONFIG_PRODUKT_NAME} )
        {
            #2017-07-14 - http_method deaktiviert
			#$attr{$name}{"http-method"} = 'POST';
        }

        # default method is GET and should be compatible to most
        # NEUTRINO Webif versions
        else {
            #2017-07-14 - http_method deaktiviert
			#$attr{$name}{"http-method"} = 'GET';
        }
        $attr{$name}{webCmd} = 'channel';
        $attr{$name}{devStateIcon} = 'on:rc_GREEN:off off:rc_RED:on standby:rc_YELLOW:on';
        $attr{$name}{icon} = 'dreambox';
    }

    # start the status update timer
    #RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, "NEUTRINO_GetStatus", $hash, 1 );

    return;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub NEUTRINO_ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash     = $param->{hash};
    my $name     = $hash->{NAME};
    my $service  = $param->{service};
    my $cmd      = $param->{cmd};
    my $state    = ReadingsVal( $name, "state", "off" );
    my $presence = ReadingsVal( $name, "presence", "absent" );
    my $type     = ( $param->{type} ) ? $param->{type} : "";
    my $return;
	my $line;
	my $UnixDate = time();

	Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] called function";
	Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] Data = $data";
    
	$hash->{helper}{RUNNING_REQUEST} = 0;
	
    delete($hash->{helper}{HTTP_CONNECTION}) unless($param->{keepalive});
	
    readingsBeginUpdate($hash);

	# mute data = 0 then data = off
	if ($service eq "mutestate" && $data == 0){
		$data = "off";
	}

	# empty timerlist
	if ($service eq "timerlist" && $data == 0){
		$data = "empty";
	}

	# volume data = 0 then data = off
	if ($service eq "volume" && $data eq '0'){
		$data = "off";
	}
	
    # device not reachable
	if ($err) {

        # powerstate
        if ( $service eq "powerstate" ) {
            $state = "absent";

            if ( !defined($cmd) || $cmd eq "" ) {
                Log3 $name, 4, "NEUTRINO $name RCV TIMEOUT $service";
            }
            else {
                Log3 $name, 4,
                  "NEUTRINO $name RCV TIMEOUT $service/" . urlDecode($cmd);
            }

            $presence = "absent";
			readingsBulkUpdateIfChanged( $hash, "power", "off" );
			readingsBulkUpdateIfChanged( $hash, "state", "off" );
            readingsBulkUpdateIfChanged( $hash, "presence", $presence )
              if ( ReadingsVal( $name, "presence", "" ) ne $presence );
        }
    }

    # data received
    elsif ($data) {
        $presence = "present";
		$state    = "on";
        readingsBulkUpdateIfChanged( $hash, "presence", $presence )
        if ( ReadingsVal( $name, "presence", "" ) ne $presence );

		#2017.07.21 - Log anzeigen wenn $cmd befüllt ist
		if ($cmd ne "" ) {Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] URL  = " . urlDecode($cmd);}
        
		# split date (non XML services)
		my @ans = split (/\n/s, $data);

		#######################
        # process return data
        #######################
		
		# XML services
		if ($service eq "epginfo" || $service eq "epginforecord") {
			
			$data = '<?xml version="1.0" encoding="UTF-8"?>' . "\n" . $data;
			
			if ( $data =~ /<\?xml/ && $data !~ /<\/html>/ ) {

                my $parser = XML::Simple->new(
                    NormaliseSpace => 2,
                    KeepRoot       => 0,
                    ForceArray     => 0,
                    SuppressEmpty  => 1,
                    KeyAttr        => {}
                );

                eval
                  '$return = $parser->XMLin( Encode::encode_utf8($data) ); 1';
                if ($@) {

                    if ( !defined($cmd) || $cmd eq "" ) {
                        Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] - unable to parse malformed XML: $@\n"
                          . $data;
                    }
                    else {
                        Log3 $name, 5,
                            "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] "
                          . urlDecode($cmd)
                          . " - unable to parse malformed XML: $@\n"
                          . $data;

                    }

                    return undef;
                }

                undef $parser;
            }
            else {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 5,
                      "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] - not in XML format\n"
                      . $data;
                }
                else {
                    Log3 $name, 5,
                        "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] "
                      . urlDecode($cmd)
                      . " - not in XML format\n"
                      . $data;
                }

                return undef;
            }    

	   $return = Encode::encode_utf8($data)
          if ( $return && ref($return) ne "HASH" );

		}

        # powerstate
        if ( $service eq "powerstate" ) {

			if (@ans[0]) {
							
				if (index(lc(@ans[0]), "on")  != -1) {
					readingsBulkUpdateIfChanged( $hash, "power","off");
					readingsBulkUpdateIfChanged( $hash, "state", "standby" );
					$state = "off";
				}

				elsif(index(lc(@ans[0]), "off")  != -1) {

					# 2017.07.12 - Aenderungen nur durchfuehren wenn power vorher ungleich "on" war
					if (ReadingsVal( $name, "power", "unbekannt" ) ne 'on'  ) {
						Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] detect change";
						readingsBulkUpdateIfChanged( $hash, "power","on");
						readingsBulkUpdateIfChanged( $hash, "state", "on" );
						delete($hash->{helper}{FIRSTSTART});
					}
					
					#2017.07.25 - Erste Start: NUTRINO Version auslesen
					if ($hash->{helper}{FIRSTSTART} eq  '') {
						NEUTRINO_SendCommand( $hash, "version" );
						NEUTRINO_SendCommand( $hash, "model" );
						$hash->{helper}{FIRSTSTART} = '1';
					}
					
					#2017.07.12 - time_raw_now/time_now vom FHEM-Server verwenden
					readingsSingleUpdate( $hash, "time_raw_now", $UnixDate ,0);
					readingsSingleUpdate( $hash, "time_now", localtime() ,0);

					#2017.07.12 - Pruefen ob die bouquet_list aktualisiert werden muss
					if ($hash->{helper}{channels}{ReadingsVal( $name, "input", "-" )} eq '') {
						Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] bouquet_list detect change!";
						NEUTRINO_SendCommand( $hash, "bouquet_list" );
					}

					#2017.07.12 - Folgendes wird alle INTERVAL abgefragt
					NEUTRINO_SendCommand( $hash, "zapto" );      # aktuellen channel_id auslesen
					NEUTRINO_SendCommand( $hash, "bouquet" );    # aktuelles Bouguet auslesen
					NEUTRINO_SendCommand( $hash, "volume" );     # aktuelles Volumen auslesen
					NEUTRINO_SendCommand( $hash, "mutestate" );  # mutestate 0 = off 1 = on
					NEUTRINO_SendCommand( $hash, "signal" );     # SIG, SNR und BER
					NEUTRINO_SendCommand( $hash, "recordmode" ); # 0 = off 1 = on
					NEUTRINO_SendCommand( $hash, "timerlist" );  # aktuelle Timerliste
					
					#2017.07.12 - deaktivert bzw. verschoben
					# MOVE --> NEUTRINO_SendCommand( $hash, "bouquet" );        #CHANGE bei Senderwechsel
					# MOVE --> NEUTRINO_SendCommand( $hash, "version" );        #CHANGE bei Powerstat wechsel
					# MOVE --> NEUTRINO_SendCommand( $hash, "build_live_url" ); #CHANGE bei Senderwechsel
					# MOVE --> NEUTRINO_SendCommand( $hash, "getmode" );        #CHANGE bei Senderwechsel
					# DEL  --> NEUTRINO_SendCommand( $hash, "gettime" );        #FHEM Zeit verwenden
					# DEL  --> NEUTRINO_SendCommand( $hash, "getrawtime" );     #FHEM Zeit verwenden
				}

				elsif(index(lc(@ans[0]), "ok")  != -1) {

					Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] TYP = $type";
				
					if (index($type, "off")  != -1) {
						Log3 $name, 5, "NEUTRINO $name TYP = OFF";
						readingsBulkUpdateIfChanged( $hash, "power", "on");
						readingsBulkUpdateIfChanged( $hash, "state", "on" );
					}
					elsif(index($type, "on")  != -1) {
						Log3 $name, 5, "NEUTRINO $name TYP = ON";
						readingsBulkUpdateIfChanged( $hash, "power", "off");
						readingsBulkUpdateIfChanged( $hash, "state", "standby" );					
					}
					else {
						readingsBulkUpdateIfChanged( $hash, "power", "off");
						readingsBulkUpdateIfChanged( $hash, "state", "standby" );
						$state = "off";
					}			
					NEUTRINO_SendCommand( $hash, "recordmode" );
				}
				
				else{
					readingsBulkUpdateIfChanged( $hash, "power", "undefined" );
					readingsBulkUpdateIfChanged( $hash, "state", "undefined" );
				}
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no powerstate could be extracted";
			}
        }
        		
		# bouquet
		elsif ( $service eq "bouquet" ) {
		
			if (@ans[0]) {
							
				#2017.07.17 - Liste nur bei aenderung aktualisieren
				if (ReadingsVal( $name, "bouquetnr", "99999" ) ne @ans[0]  ) {
					Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] detect change";
					readingsBulkUpdateIfChanged( $hash, "bouquetnr", @ans[0] );
					NEUTRINO_SendCommand( $hash, "bouquet_list" );
				}
			}
			else {
				readingsBulkUpdateIfChanged( $hash, "bouquetnr", "0" );
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no bouquetnr could be extracted";
			}
        }
		
		# bouquet_list
		elsif ( $service eq "bouquet_list" ) {
		
			my $channellistname;
			my $i = 0;
			my $input	 = ReadingsVal( $name, "input", "-" );
			
			#2017.07.19 - Nur durchführen wenn $input <> '-' ist
			if ($input ne '-') {
				$hash->{helper}{channels}{$input} = ();
				
				foreach $line (@ans)  {
					if (index($line, "",6)  != -1) {
						$channellistname = substr($line,index($line," ", 6 )+1);
						$channellistname =~ s/\s/_/g;
						if (substr($channellistname, 0, 1) ne "" && substr($channellistname, 0, 1) ne "_") {
							$hash->{helper}{channels}{$input}[$i] = $channellistname ;
							$i++;
						}
					}
				}
			}
        }
		
        # volume
        elsif ( $service eq "volume" ) {
            if (index(lc(@ans[0]), "ok")  != -1) {
				#2017.07.12 - Nur bei einer Aenderung schreiben
				readingsBulkUpdateIfChanged( $hash, "volume", substr($cmd,1) );
			}
			elsif (index(lc(@ans[0]), "off")  != -1) {
				#2017.07.12 - Nur bei einer Aenderung schreiben
				readingsBulkUpdateIfChanged( $hash, "volume", "0" );
			}
			elsif (@ans[0]) {
				#2017.07.12 - Nur bei einer Aenderung schreiben
				readingsBulkUpdateIfChanged( $hash, "volume", @ans[0] );
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no volume could be extracted";
			}
        }

		# mutestate
        elsif ( $service eq "mutestate" ) {
			
			if (@ans[0]) {
				if (index(lc(@ans[0]), "1")  != -1) {
				    #2017.07.12 - Änderung schreiben
					readingsBulkUpdateIfChanged( $hash, "mute","on");
				}
				else{
					readingsBulkUpdateIfChanged( $hash, "mute","off");
				}
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no mute could be extracted";
			}
      
        }
		
		# mute
        elsif ( $service eq "mute" ) {
			
			if (@ans[0]) {
				if (index(lc(@ans[0]), "ok")  != -1) {
					readingsBulkUpdateIfChanged( $hash, "mute","on");
				}
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no mute could be extracted";
			}
        }
		
		# unmute
        elsif ( $service eq "unmute" ) {
			
			if (@ans[0]) {
				if (index(lc(@ans[0]), "ok")  != -1) {
					readingsBulkUpdateIfChanged( $hash, "mute","off");
				}
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no mute could be extracted";
			}
        }
		
		# model
        elsif ( $service eq "model" ) {
			
			if (@ans[0]) {
				readingsBulkUpdateIfChanged( $hash, "model",@ans[0]);
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no model could be extracted";
			}
        }
		
		# timerlist
		elsif ( $service eq "timerlist" ) {
		
			my $channellistname;
			my $timernumber;
			my $timerrepeat;
			my $timertyp;
			my $timerannounceTime;
			my $timerstartTime;
			my $timerstopTime;
			my $timername;
			my $i = 0;
			my $c = 0;
			my $d = 0;
			my $timermaxcount = ReadingsVal( $name, "timer_maxcount", 1 );
			my $neutrinotime  = ReadingsVal( $name, "time_raw_now", "" );
			
			if ($data ne "empty") {
				foreach $line (@ans)  {
					if (index($line, "",6)  != -1) {
						my @timerlist = split (/ /s, $line);
						$timernumber       = @timerlist[0];
						$timertyp          = @timerlist[1];
						$timerrepeat       = @timerlist[2];
						$timerannounceTime = @timerlist[4];
						$timerstartTime    = @timerlist[5];
						$timerstopTime     = @timerlist[6];

						#2017.07.12 - Nur Änderungen schreiben
						if (ReadingsVal( $name, "timer$i", "0" ) ne $line  ) {
							readingsBulkUpdateIfChanged( $hash, "timer$i", $line );
							readingsBulkUpdateIfChanged( $hash, "timer$i" . "number", $timernumber );
							
							# timertyp
							if ($timertyp eq "1") {$timertyp = "shutdown"}
							elsif ($timertyp eq "2") {$timertyp = "nextprogram"}
							elsif ($timertyp eq "3") {$timertyp = "zapto"}
							elsif ($timertyp eq "4") {$timertyp = "standby"}
							elsif ($timertyp eq "5") {$timertyp = "record"}
							elsif ($timertyp eq "6") {$timertyp = "remind"}
							elsif ($timertyp eq "7") {$timertyp = "sleeptimer"}
							elsif ($timertyp eq "8") {$timertyp = "exec_plugin"}
							else  {$timertyp = "unknown"}
							
							readingsBulkUpdateIfChanged( $hash, "timer$i" . "typ", $timertyp );
							
							# timer repeat
							if ($timerrepeat eq "0") {$timerrepeat = "once"}
							elsif ($timerrepeat eq "1") {$timerrepeat = "daily"}
							elsif ($timerrepeat eq "2") {$timerrepeat = "weekly"}
							elsif ($timerrepeat eq "3") {$timerrepeat = "biweekly"}
							elsif ($timerrepeat eq "4") {$timerrepeat = "fourweekly"}
							elsif ($timerrepeat eq "5") {$timerrepeat = "monthly"}
							elsif ($timerrepeat eq "6") {$timerrepeat = "beeventdescription"}
							else  {$timerrepeat = "weekdays"}
							
							readingsBulkUpdateIfChanged( $hash, "timer$i" . "repeat", $timerrepeat );
							
							# timer repcount
							readingsBulkUpdateIfChanged( $hash, "timer$i" . "repcount", @timerlist[3] );
							
							# announceTime
							if ($timerannounceTime eq "0") {readingsBulkUpdateIfChanged( $hash, "timer$i" . "manualrecord", "" );}
							else {
								my $date = localtime($timerannounceTime)->strftime('%F %T');
								readingsBulkUpdateIfChanged( $hash, "timer$i" . "announceTime", $date );
							}	
							
							# startTime
							my $date = localtime($timerstartTime)->strftime('%F %T');
							readingsBulkUpdateIfChanged( $hash, "timer$i" . "startTime", $date );
							
							# stopTime
							my $date = localtime($timerstopTime)->strftime('%F %T');
							readingsBulkUpdateIfChanged( $hash, "timer$i" . "stopTime", $date );
							
							# timer name
							$timername = "";
							$c = 0;
							foreach (@timerlist) {
								if ($c > 6){
									if ($timername ne "") {$timername = $timername . " " . @timerlist[$c]} else {$timername = @timerlist[$c]}
								}
								$c++;
							}
							readingsBulkUpdateIfChanged( $hash, "timer$i" . "name", $timername );
						}

						# find running record
						if ($neutrinotime > $timerstartTime && $neutrinotime < $timerstopTime) {
							readingsBulkUpdateIfChanged( $hash, "recordchannel", $timername );
							NEUTRINO_SendCommand( $hash, "epginforecord","");
						}
						
						$i++;
					}
				}
			}

			# timer count
			#2017.07.12 - Nur Änderungen schreiben
			readingsBulkUpdateIfChanged( $hash, "timer_count", $i );
		
			# timer maxcount
			if ($timermaxcount <= $i) {
				#2017.07.12 - Nur Änderungen schreiben
				readingsBulkUpdateIfChanged( $hash, "timer_maxcount", $i );
			}
			else {
				# detele not used timer 
				while ($d < $timermaxcount) {
					if ($d > $i -1 ) {
						foreach ( "","announceTime","name","number","repcount","repeat","startTime","stopTime","typ", ) {
							readingsBulkUpdateIfChanged( $hash, "timer" . $d . $_, "-" );
						}
					}
					$d++;
				}
			}
        }
		
		# EPG informations (record)
        elsif ( $service eq "epginforecord" ) {
		   my $readvalue;
		   my $neutrinotime = ReadingsVal( $name, "time_raw_now", "" );
		   my $readnumber	= 0;
		   my $line;

			if ( ref($return) eq "HASH"
                && defined( $return->{channel_id} ) )
            {

				if (defined( $return->{prog} ) ) {
				
					#egp stop time serach
					my $arr_size = @{ $return->{prog} };
					my $i        = 0;
					
					while ( $i < $arr_size ) {
						$readvalue = $return->{prog}[$i]{stop_sec};
						if ($readvalue > $neutrinotime){
							$readnumber = $i;
							last;
						}
						$i++;
					}
					
					# recordtitle
					$readvalue = $return->{prog}[$readnumber]{description};
					readingsBulkUpdateIfChanged( $hash, "recordtitle",$readvalue);
				}
            }
            else {
                Log3 $name, 5,
                  "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no record epg information could be found";
            }	   
        }
			
		# channel (ID)
        elsif ( $service eq "zapto" ) {
            
			if (@ans[0]) {
				if (@ans[0] eq 'ok') {
					# Umschalten eines Sender erkannt / Aktuellen Sender abfragen!
					Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] detect switch channel";
					NEUTRINO_SendCommand( $hash, "zapto" );
				}
				else {
					# Prüfen ob div. Informationen aktualisiert werden müssen
					if (ReadingsVal( $name, "channel_id", "0" ) ne @ans[0]  ) {
						Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] detect change OLD " . ReadingsVal( $name, "channel_id", "0" );
						Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] detect change NEW @ans[0]";
						
						readingsBulkUpdateIfChanged( $hash, "channel_id", @ans[0] );
						
						NEUTRINO_SendCommand( $hash, "epginfo" );
						NEUTRINO_SendCommand( $hash, "build_live_url" ); #2017.07.12 - channel_url wird nur beim Senderwechsel aktualisiert!
						NEUTRINO_SendCommand( $hash, "getmode" );        #2017.07.12 - Mode wird nur beim Senderwechsel aktualisiert!
					}
					else {
						# 2017.07.12 - EPGInfo aktualisieren wenn die aktuelle Sendeung zu ende ist
						if ($UnixDate > ReadingsVal( $name, "egp_current_stop_sec", "0" )  ) {
							Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] epginfo detect change";
							NEUTRINO_SendCommand( $hash, "epginfo" );
						}
					}
				}
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no ID could be extracted";
			}
		}
		
		# stream URL
        elsif ( $service eq "build_live_url" ) {
			if (@ans[0]) {
				readingsBulkUpdateIfChanged( $hash, "channel_url", @ans[0] );
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no build_live_url could be extracted";
			}
		}
		
		# Mode TV/Radio
        elsif ( $service eq "getmode" ) {
            
			if (@ans[0]) {
				if (index(lc(@ans[0]), "tv")  != -1) {
					readingsBulkUpdateIfChanged( $hash, "input","tv");
				}
				elsif(index(lc(@ans[0]), "radio")  != -1) {
					readingsBulkUpdateIfChanged( $hash, "input","radio");
				}
				else{
					readingsBulkUpdateIfChanged( $hash, "input", "-" )
				}
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no inputmode could be extracted";
			}

		}

		# Mode TV/Radio
        elsif ( $service eq "recordmode" ) {
            
			if (@ans[0]) {
				if (index(lc(@ans[0]), "on")  != -1) {
					#2017.07.12 - Nur bei einer Aenderung schreiben
					readingsBulkUpdateIfChanged( $hash, "recordmode","on");
				}
				elsif(index(lc(@ans[0]), "off")  != -1) {
					#2017.07.12 - Nur bei einer Aenderung schreiben
					readingsBulkUpdateIfChanged( $hash, "recordmode","off");
				}
				else{
					readingsBulkUpdateIfChanged( $hash, "recordmode", "-" )
				}
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no recordmode could be extracted";
			}

		}
				
		# EPG informations
        elsif ( $service eq "epginfo" ) {
           my $reading;
		   my $readingname;
           my $readvalue;
		   my $neutrinotime = ReadingsVal( $name, "time_raw_now", "" );
		   my $readnumber	= 0;
            if ( ref($return) eq "HASH"
                && defined( $return->{channel_id} ) )
            {
                
				# channel_Name
				$readvalue = $return->{channel_name};
				readingsBulkUpdateIfChanged( $hash, "channel_name",$readvalue);
					
				# channel displayname
				$readvalue =~ s/\s/_/g;
				readingsBulkUpdateIfChanged( $hash, "channel",$readvalue);
				
				if(ref($return->{prog}) eq 'ARRAY') {
					Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ARRAY!!!" . ref($return->{prog});
				}else {Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ARRAY!!! NOT" . ref($return->{prog});}
				
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] Data = $data";
				
				if (defined( $return->{prog} ) && ref($return->{prog}) eq 'ARRAY' ) {
				
					#egp stop time serach
					my $arr_size = @{ $return->{prog} };
					my $i        = 0;
					
					while ( $i < $arr_size ) {
						$readvalue = $return->{prog}[$i]{stop_sec};
						if ($readvalue > $neutrinotime){
							$readnumber = $i;
							readingsBulkUpdateIfChanged( $hash, "egp_current_number", $readnumber);
							last;
						}
						$i++;
					}
					
					# 2017.07.27 - BUG NEUTRINO / Umschalten wenn EGP und CHANNEL_ID nicht passen!
					if (ReadingsVal( $name, "channel_id", "" ) ne $return->{prog}[$readnumber]{channel_id}) {
						Log3 $name, 0, "NEUTRINO [BUG NEUTRINO] EPG channel_id = " . $return->{prog}[$readnumber]{channel_id} ;
						NEUTRINO_SendCommand( $hash, "zapto", $return->{prog}[$readnumber]{channel_id} );
					}

					# currentTitel
					$readvalue = $return->{prog}[$readnumber]{description};
					readingsBulkUpdateIfChanged( $hash, "currentTitle",$readvalue);
					
					foreach ( "eventid","description","info1","info2","start_t","stop_t","duration_min","date","channel_id","stop_sec","start_sec", ) {
						$reading     = $_;
						if ($_ eq "eventid") {$readingname = $reading ;} else {$readingname = "egp_current_" . $_;}
						
						if ( defined( $return->{prog}[$readnumber]{$reading} )
							&& lc( $return->{prog}[$readnumber]{$reading} ) ne "n/a" )
						{
							$readvalue = $return->{prog}[$readnumber]{$reading};
							$readvalue =~ s/\n//g;
							
							if ($readvalue) {
								readingsBulkUpdateIfChanged( $hash, $readingname, $readvalue );
							}
							else {
								readingsBulkUpdateIfChanged( $hash, $readingname, "-" );
							}
						}
						else {
							readingsBulkUpdateIfChanged( $hash, $readingname, "-" );
						}
					}
				}else{
					readingsBulkUpdateIfChanged( $hash, "eventid", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_description", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_info1", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_info2", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_start_t", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_stop_t", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_duration_min", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_date", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_channel_id", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_stop_sec", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_start_sec", "-" );
					readingsBulkUpdateIfChanged( $hash, "egp_current_number", "-" );
					readingsBulkUpdateIfChanged( $hash, "currentTitle", "-" );
				}
            }
            else {
                Log3 $name, 5,
                  "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no epg information could be found";
            }	   
        }

        # signal
        elsif ( $service eq "signal" ) {
			my $signalvalue;
            if (@ans[0]) {
				foreach $line (@ans)  {
					foreach ("sig","snr","ber",) {
						if (index(lc($line), $_)  != -1) {
							$signalvalue = substr($line,index($line,":")+1);
							#2017.07.12 - Nur bei einer Aenderung schreiben
							readingsBulkUpdateIfChanged( $hash, "$_",$signalvalue);
						}
					}
				}
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no signal could be extracted";
			}
        }
		
        # Boxinformations
        elsif ( $service eq "version" ) {
			my $versionvalue;
			my $versionname;
            if (@ans[0]) {
				foreach $line (@ans)  {
					if (index(lc($line), "=")  != -1) {
						$versionvalue = substr($line,index($line,"=")+1);
						$versionname = substr($line,0,index($line,"="));
						readingsBulkUpdateIfChanged( $hash, "image_" . "$versionname",$versionvalue);
					}
				}
			}
			else {
				Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] ERROR: no signal could be extracted";
			}
        }
		
        # all other command results
        else {
            NEUTRINO_GetStatus( $hash, 1 );
        }
		
    }
	else{
		Log3 $name, 5, "NEUTRINO $name [NEUTRINO_ReceiveCommand] [$service] no data!";
	}

    readingsEndUpdate( $hash, 1 );

	NEUTRINO_HD_HandleCmdQueue($hash);
	
    undef $return;
    return;
}

###################################
sub NEUTRINO_Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "NEUTRINO $name [NEUTRINO_Undefine] called function";

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return;
}

1;

=pod
=item device
=item summary control for NEUTRINO based receivers via network connection
=item summary_DE Steuerung von NEUTRINO basierte Receiver &uuml;ber das Netzwerk
=begin html

    <p>
      <a name="NEUTRINO" id="NEUTRINO"></a>
    </p>
    <h3>
      NEUTRINO
    </h3>

    <ul>
      <a name="NEUTRINOdefine" id="NEUTRINOdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; NEUTRINO &lt;ip-address-or-hostname&gt; [[[[&lt;port&gt;] [&lt;poll-interval&gt;]] [&lt;http-user&gt;]] [&lt;http-password&gt;]]</code><br>
        <br>
        This module controls NEUTRINO based devices like Coolstream receiver via network connection.<br>
        <br>
        Defining an NEUTRINO device will schedule an internal task (interval can be set with optional parameter &lt;poll-interval&gt; in seconds, if not set, the value is 45 seconds), which periodically reads the status of the device and triggers notify/filelog commands.<br>
        <br>
        Example:<br>
        <ul>
          <code>define SATReceiver NEUTRINO 192.168.0.10<br>
          <br>
          # With custom port<br>
          define SATReceiver NEUTRINO 192.168.0.10 8080<br>
          <br>
          # With custom interval of 20 seconds<br>
          define SATReceiver NEUTRINO 192.168.0.10 80 20<br>
          <br>
          # With HTTP user credentials<br>
          define SATReceiver NEUTRINO 192.168.0.10 80 20 root secret</code>
      </ul>
    </ul>
      <br>
      <br>
      <a name="NEUTRINOset" id="NEUTRINOset"></a> <b>Set</b>
      <ul>
        <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Currently, the following commands are defined.<br>
        <ul>
          <li>
            <b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device (standby mode)
          </li>
          <li>
            <b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in standby mode
          </li>
          <li>
            <b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between on and off (standby mode)
          </li>
          <li>
            <b>shutdown</b> &nbsp;&nbsp;-&nbsp;&nbsp; poweroff the device
          </li>
          <li>
            <b>reboot</b> &nbsp;&nbsp;-&nbsp;&nbsp;reboots the device
          </li>
          <li>
            <b>channel</b> &nbsp;&nbsp;-&nbsp;&nbsp; zap to specific channel
          </li>
          <li>
            <b>volume</b> 0...100 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage
          </li>
          <li>
            <b>mute</b> on,off,toggle &nbsp;&nbsp;-&nbsp;&nbsp; controls volume to mute
          </li>
          <li>
            <b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device
          </li>
          <li>
            <b>remoteControl</b> UP,DOWN,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control command<br />
          </li>
          <li>
            <b>showText</b> text &nbsp;&nbsp;-&nbsp;&nbsp; sends info messages to be displayed on screen
          </li>
          <li>
            <b>showtextwithbutton</b> &nbsp;&nbsp;-&nbsp;&nbsp; sends info messagees to be displayed on screen with OK button
          </li>
         <br>
      <br>
      <br>
     </ul>
     </ul>
      <a name="NEUTRINOget" id="NEUTRINOget"></a> <b>Get</b>
      <ul>
        <code>get &lt;name&gt; &lt;what&gt;</code><br>
        <br>
        Currently, the following commands are defined:<br>
        <br>
        <ul>
          <code>channel<br>
          channelurl<br>
          currentTitle<br>
          input<br>
          mute<br>
          power<br>
          volume<br></code>
        </ul>
      </ul><br>
      <br>
      <a name="NEUTRINOattr" id="NEUTRINOattr"></a> <b>Attributes</b><br>
      <ul>
        <ul>
          <li>
            <b>disable</b> - Disable polling (true/false)
          </li>
          <li>
            <b>http-noshutdown</b> - Set FHEM-internal HttpUtils connection close behaviour (defaults=0)
          </li>
          <li>
            <b>https</b> - Access box via secure HTTP (true/false)
          </li>
          <li>
            <b>timeout</b> - Set different polling timeout in seconds (default=2)
          </li>
        </ul>
      </ul><br>
      <br>
      <br>
      <b>Generated Readings:</b><br>
      <ul>
        <ul>
          <li>
            <b>ber</b> - Shows Bit Error Rate for current channel
          </li>
          <li>
            <b>bouquetnr</b> - Shows bouquet number for current channel
          </li>
          <li>
            <b>channel</b> - Shows the service name of current channel
          </li>
          <li>
            <b>channel_id</b> - Shows the channel id of current channel
          </li>
          <li>
            <b>channel_name</b> - Shows the channel name of current channel
          </li>
          <li>
            <b>channel_url</b> - Shows the channel url of current channel (use with vlc player)
          </li>
          <li>
            <b>currentTitle</b> - Shows the title of the running event
          </li>
          <li>
            <b>epg_current_channel_id</b> - Shows the channel id of epg information
          </li>
          <li>
            <b>epg_current_date</b> - Shows the date of epg information
          </li>
          <li>
            <b>egp_current_description</b> - Shows the current description of the current program
          </li>
          <li>
            <b>egp_current_duration_min</b> - Shows the current duration of the current program
          </li>
          <li>
            <b>egp_current_info1</b> - Displays the current information of the current program
          </li>
          <li>
            <b>egp_current_info2</b> - Displays the current information of the current program
          </li>
          <li>
            <b>egp_current_number</b> - Displays the current number(epg) of the current program
          </li>
          <li>
            <b>egp_current_start_sec</b> - Shows the current start time of the current program (ticks)
          </li>
          <li>
            <b>egp_current_start_t</b> - Shows the current start time of the current program
          </li>
          <li>
            <b>egp_current_stop_sec</b> - Shows the current stop time of the current program (ticks)
          </li>
          <li>
            <b>egp_current_stop_t</b> - Shows the current stop time of the current program
          </li>
          <li>
            <b>eventid</b> - Shows the current event id of the current program
          </li>
          <li>
            <b>image_*</b> - Shows image information of NEUTRINO
          </li>
          <li>
            <b>input</b> - Shows currently used input
          </li>
          <li>
            <b>mute</b> - Reports the mute status of the device (can be "on" or "off")
          </li>
          <li>
            <b>power</b> - Reports the power status of the device (can be "on" or "off")
          </li>
          <li>
            <b>presence</b> - Reports the presence status of the receiver (can be "absent" or "present").
          </li>
            <li>
            <b>recordmode</b> - Reports the record mode of the device (can be "on" or "off")
          </li>
             <li>
            <b>recordmodetitle</b> - Reports the last record title
          </li>
          <li>
            <b>sig</b> - Shows signal for current channel in percent
          </li>
          <li>
            <b>snr</b> - Shows signal to noise for current channel in percent
          </li>
          <li>
            <b>state</b> - Reports current power state and an absence of the device (can be "on", "off" or "standby")
          </li>
          <li>
            <b>time_now</b> - Reports current time
          </li>
          <li>
            <b>time_raw_now</b> - Reports current time (ticks)
          </li>
          <li>
            <b>timerX</b> - Shows complete timer (Report from NEUTRINO)
          </li>
          <li>
            <b>timerXannounceTime</b> - Shows announce time of the timer
          </li>
          <li>
            <b>timerXname</b> - Shows channel name of the timer
          </li>
          <li>
            <b>timerXnumber</b> - Shows timer number
          </li>
          <li>
            <b>timerXrepcount</b> - Shows rep count of the timer
          </li>
          <li>
            <b>timerXrepeat</b> - Shows repeat time of the timer
          </li>
          <li>
            <b>timerXstartTime</b> - Shows start time of the timer
          </li>
          <li>
            <b>timerXstopTime</b> - Shows stop time of the timer
          </li>
          <li>
            <b>timerXtyp</b> - Shows type of the timer
          </li>
          <li>
            <b>timer_count</b> - Shows the number of timers
          </li>
          <li>
            <b>timer_count</b> - Shows the maximum number of timers
          </li>
          <li>
            <b>volume</b> - Reports current volume level of the receiver in percentage values (between 0 and 100 %)
          </li>
        </ul>
      </ul>
    </ul>

=end html

=begin html_DE

    <p>
      <a name="NEUTRINO" id="NEUTRINO"></a>
    </p>
    <h3>
      NEUTRINO
    </h3>
    <ul>
      <a name="NEUTRINOdefine" id="NEUTRINOdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; NEUTRINO &lt;ip-address-or-hostname&gt; [[[[&lt;port&gt;] [&lt;poll-interval&gt;]] [&lt;http-user&gt;]] [&lt;http-password&gt;]]</code><br>
        <br>
        Dieses Modul steuert NEUTRINO basierte Ger&auml;te wie die Coolstream &uuml;ber eine Netzwerkverbindung.<br>
        <br>
        F&uuml;r definierte NEUTRINO Ger&auml;te wird ein interner Task angelegt, welcher periodisch die Readings aktualisiert. Der Standartpollintervall ist 45 Sekunden.<br>
        <br>
        Beispiele:<br>
        <ul>
          <code>define SATReceiver NEUTRINO 192.168.0.10<br>
          <br>
          # Alternativer Port<br>
          define SATReceiver NEUTRINO 192.168.0.10 8080<br>
          <br>
          # Alternativer poll intervall von 20 seconds<br>
          define SATReceiver NEUTRINO 192.168.0.10 80 20<br>
          <br>
          # Mit HTTP Benutzer Zugangsdaten<br>
          define SATReceiver NEUTRINO 192.168.0.10 80 20 root secret</code>
        </ul>
      </ul><br>
      <br>
      <a name="NEUTRINOset" id="NEUTRINOset"></a> <b>Set</b>
      <ul>
        <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Aktuell gibt es folgende Befehle.<br>
        <ul>
          <li>
            <b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet das Ger&auml;t aus dem Standby wieder an
          </li>
          <li>
            <b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet das Ger&auml;t in den Standby
          </li>
          <li>
            <b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; Ein- und Ausschalten zwischen Standby
          </li>
          <li>
            <b>shutdown</b> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet das Ger&auml;t aus
          </li>
          <li>
            <b>reboot</b> &nbsp;&nbsp;-&nbsp;&nbsp;Neustart des Ger&auml;tes
          </li>
          <li>
            <b>channel</b> &nbsp;&nbsp;-&nbsp;&nbsp;Schaltet auf den angegebenen Kanal
          </li>
          <li>
            <b>volume</b> 0...100 &nbsp;&nbsp;-&nbsp;&nbsp; &Auml;ndert die Lautst&auml;rke in Prozent
          </li>
          <li>
            <b>mute</b> on,off,toggle &nbsp;&nbsp;-&nbsp;&nbsp; Steuert Lautst&auml;rke "stumm"
          </li>
          <li>
            <b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; Fordert den aktuellen Status des Ger&auml;tes an
          </li>
          <li>
            <b>remoteControl</b> UP,DOWN,... &nbsp;&nbsp;-&nbsp;&nbsp; Sendet Fernsteuerungsbefehle<br />
          </li>
          <li>
            <b>showText</b> text &nbsp;&nbsp;-&nbsp;&nbsp; Sendet eine Textnachricht
          </li>
          <li>
            <b>showtextwithbutton</b> &nbsp;&nbsp;-&nbsp;&nbsp; Sendet eine Textnachricht mit OK Button
          </li>
         <br>
     </ul>
     </ul>
     <br>
      <br>
      <a name="NEUTRINOget" id="NEUTRINOget"></a> <b>Get</b>
      <ul>
        <code>get &lt;name&gt; &lt;what&gt;</code><br>
        <br>
        Aktuell gibt es folgende Befehle.<br>
        <br>
        <ul>
          <code>channel<br>
          channelurl<br>
          currentTitle<br>
          input<br>
          mute<br>
          power<br>
          volume<br></code>
        </ul>
      </ul><br>
      <br>
      <a name="NEUTRINOattr" id="NEUTRINOattr"></a> <b>Attributes</b><br>
      <ul>
        <ul>
          <li>
            <b>disable</b> - Schaltet das Polling aus (true/false)
          </li>
          <li>
            <b>http-noshutdown</b> - Setzt FHEM-internal HttpUtils Verbindung offen halten (defaults=0)
          </li>
          <li>
            <b>https</b> - Zugriff &uuml;ber HTTPS aktivieren (true/false)
          </li>
          <li>
            <b>timeout</b> - Setzen des Timeout der HTTP Verbindung (default=2)
          </li>
        </ul>
      </ul><br>
      <br>
      <br>
      <b>Generelle Readings:</b><br>
      <ul>
        <ul>
          <li>
            <b>ber</b> - Zeigt die Bit Error Rate vom aktuellen Kanal
          </li>
          <li>
            <b>bouquetnr</b> - Zeigt die aktuelle Bouquet Nummer vom aktuellen Kanal
          </li>
          <li>
            <b>channel</b> - Zeigt den aktuellen Servicenamen vom aktuellen Kanal
          </li>
          <li>
            <b>channel_id</b> - Zeigt die aktuelle Kanal ID vom aktuellen Kanal
          </li>
          <li>
            <b>channel_name</b> - Zeigt den aktuellen Kanal Namen
          </li>
          <li>
            <b>channel_url</b> - Zeigt die aktuelle Kanal URL, welche im Vlc Player zum Streamen verwendet werden kann
          </li>
          <li>
            <b>currentTitle</b> - Zeigt den aktuellen Titel der aktuellen Sendung an
          </li>
          <li>
            <b>epg_current_channel_id</b> - Zeigt die Kanal ID von aktuellen EPG an
          </li>
          <li>
            <b>epg_current_date</b> - Zeigt das Datum des aktuellen EPGs an
          </li>
          <li>
            <b>egp_current_description</b> - Zeigt die aktuelle Beschreibung der aktuellen Sendung an
          </li>
          <li>
            <b>egp_current_duration_min</b> - Zeigt die Dauer der aktuellen Sendung an
          </li>
          <li>
            <b>egp_current_info1</b> - Zeigt die Information Teil 1 der aktuellen Sendung an
          </li>
          <li>
            <b>egp_current_info2</b> - Zeigt die Information Teil 2 der aktuellen Sendung an
          </li>
          <li>
            <b>egp_current_number</b> - Zeigt die EPG Nummer der aktuellen Sendung an
          </li>
          <li>
            <b>egp_current_start_sec</b> - Zeigt die Startzeit der aktuellen Sendung an (ticks)
          </li>
          <li>
            <b>egp_current_start_t</b> - Zeigt die Startzeit der aktuellen Sendung an
          </li>
          <li>
            <b>egp_current_stop_sec</b> - Zeigt die Stopzeit der aktuellen Sendung an (ticks)
          </li>
          <li>
            <b>egp_current_stop_t</b> - Zeigt die Stopzeit der aktuellen Sendung an
          </li>
          <li>
            <b>eventid</b> - Zeigt die aktuelle Event ID von der aktuellen Sendung an
          </li>
          <li>
            <b>image_*</b> - Zeigt Image Informationen von NEUTRINO
          </li>
          <li>
            <b>input</b> - Zeigt den aktuellen Input an (TV/Radio)
          </li>
          <li>
            <b>mute</b> - Zeigt aktuellen Mute Status ("on" oder "off")
          </li>
          <li>
            <b>power</b> - Zeigt aktuellen Power Status ("on" oder "off")
          </li>
          <li>
            <b>presence</b> - Zeigt den aktuellen presence Status an ("absent" oder "present").
          </li>
            <li>
            <b>recordmode</b> - Zeigt an ob die Box gerade eine Aufnahme macht ("on" oder "off")
          </li>
             <li>
            <b>recordmodetitle</b> - Zeigt den letzten Aufnahme Titel an
          </li>
          <li>
            <b>sig</b> - Zeigt Signalst&auml;rke vom aktuellen Sender an
          </li>
          <li>
            <b>snr</b> - Zeigt Singal Noise vom aktuellen Sender an
          </li>
          <li>
            <b>state</b> - Zeigt den aktuellen Status an ("on", "off" oder "standby")
          </li>
          <li>
            <b>time_now</b> - Aktuelle Uhrzeit
          </li>
          <li>
            <b>time_raw_now</b> - Aktuelle Uhrzeit (ticks)
          </li>
          <li>
            <b>timerX</b> - Zeigt den kompletten Timer an (Report from NEUTRINO)
          </li>
          <li>
            <b>timerXannounceTime</b> - Zeigt die Ank&uuml;ndigungszeit des Timers an
          </li>
          <li>
            <b>timerXname</b> - Zeigt den Aufnahmekanal des Timers an
          </li>
          <li>
            <b>timerXnumber</b> - Zeigt die Timernummer an
          </li>
          <li>
            <b>timerXrepcount</b> - Zeigt den Rep. Counter des Timers an
          </li>
          <li>
            <b>timerXrepeat</b> - Zeigt die Wiederholungszeit an
          </li>
          <li>
            <b>timerXstartTime</b> - Zeigt die Startzeit des Timers an
          </li>
          <li>
            <b>timerXstopTime</b> - Zeigt die Stopzeit des Timers an
          </li>
          <li>
            <b>timerXtyp</b> - Zeigt den Typ des Timers an
          </li>
          <li>
            <b>timer_count</b> - Zeigt die Anzahl der aktuellen Timer an
          </li>
          <li>
            <b>timer_count</b> - Zeitg die max. Anzahl der Timer an (wird intern verwendet)
          </li>
          <li>
            <b>volume</b> - Zeit die aktuelle Lautst&auml;rke an (zwischen 0 und 100 %)
          </li>
        </ul>
      </ul>
    </ul>


=end html_DE

=cut