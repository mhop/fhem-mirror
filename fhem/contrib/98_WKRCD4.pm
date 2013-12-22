#########################################################################
# fhem Modul für Waterkotte Wärmepumpe mit Resümat CD4 Steuerung
# Vorlage: Modul WHR962, diverse Foreneinträge sowie Artikel über Auswertung der 
# Wärmepumpe mit Linux / Perl im Linux Magazin aus 2010
# insbesondere: 
#		http://www.haustechnikdialog.de/Forum/t/6144/Waterkotte-5017-3-an-den-Computer-anschliessen?page=2  (Speicheradressen-Liste)
#       http://www.ip-symcon.de/forum/threads/2092-ComPort-und-Waterkotte-abfragen 							(Protokollbeschreibung)
#		http://www.haustechnikdialog.de/Forum/t/6144/Waterkotte-5017-3-an-den-Computer-anschliessen?page=4 	(Beispiel Befehls-Strings)
#	
							
package main;

use strict;                          
use warnings;                        
use Time::HiRes qw(gettimeofday);    

#
# list of Readings / values that can explicitely be requested
# from the WP with the GET command
my %WKRCD4_gets = (  
	"Hzg-TempBasisSoll"	=> "Hzg-TempBasisSoll",
	"WW-Temp-Soll"		=> "Temp-WW-Soll"
);

# list of Readings / values that can be written to the WP
my %WKRCD4_sets = (  
	"Hzg-TempBasisSoll"	=> "Hzg-TempBasisSoll"
);

# Definition of the values that can be read / written 
# with the relative address, number of bytes and 
# fmat to be used in sprintfd when formatting the value
# unp to be used in pack / unpack commands
# min / max for setting values
#
my %frameReadings = (
 'Versions-Nummer'        => { addr => 0x0000, bytes => 0x0002,                  unp => 'n' },
 'Temp-Aussen'            => { addr => 0x0008, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Ruecklauf-Soll'    => { addr => 0x0014, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Ruecklauf'         => { addr => 0x0018, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Vorlauf'           => { addr => 0x001C, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-WW-Soll'           => { addr => 0x0020, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-WW'                => { addr => 0x0024, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Raum'              => { addr => 0x0028, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-WQuelle-Ein'       => { addr => 0x0030, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-WQuelle-Aus'       => { addr => 0x0034, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Verdampfer'        => { addr => 0x0038, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Kondensator'       => { addr => 0x003C, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Temp-Saugleitung'       => { addr => 0x0040, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Druck-Verdampfer'       => { addr => 0x0048, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Druck-Kondensator'      => { addr => 0x004C, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Hzg-TempEinsatz'        => { addr => 0x00F4, bytes => 0x0004, fmat => '%0.1f', unp => 'f<', min => 15.0, max => 20.0 },
 'Hzg-TempBasisSoll'      => { addr => 0x00F8, bytes => 0x0004, fmat => '%0.1f', unp => 'f<', min => 20.0, max => 24.0 },
 'Hzg-KlSteilheit'        => { addr => 0x00FC, bytes => 0x0004, fmat => '%0.1f', unp => 'f<', min => 15.0, max => 30.0 },
 'Hzg-KlBegrenz'          => { addr => 0x0100, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Hzg-TempRlSoll'         => { addr => 0x0050, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Hzg-TempRlIst'          => { addr => 0x0054, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Hzg-TmpRaumSoll'        => { addr => 0x0105, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Hzg-RaumEinfluss'       => { addr => 0x0109, bytes => 0x0001,                  unp => 'C' },
 'Hzg-ExtAnhebung'        => { addr => 0x010A, bytes => 0x0004, fmat => '%0.1f', unp => 'f<', min => -5.0, max => 5.0 },
 'Hzg-Zeit-Ein'           => { addr => 0x010E, bytes => 0x0003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC'},
 'Hzg-Zeit-Aus'           => { addr => 0x0111, bytes => 0x0003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hzg-AnhebungEin'        => { addr => 0x0114, bytes => 0x0003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hzg-AnhebungAus'        => { addr => 0x0117, bytes => 0x0003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Hzg-St2Begrenz'         => { addr => 0x011A, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Hzg-Hysterese'          => { addr => 0x011E, bytes => 0x0004, fmat => '%0.1f', unp => 'f<', min => 1.0, max => 3.0  },
 'Hzg-PumpenNachl'        => { addr => 0x0122, bytes => 0x0001,                  unp => 'C',  min => 0,   max => 120  },
 'Klg-Abschaltung'        => { addr => 0x0123, bytes => 0x0001,                  unp => 'C' },
 'Klg-Temp-Einsatz'       => { addr => 0x0124, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Klg-TeBasisSoll'        => { addr => 0x0128, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Klg-KlSteilheit'        => { addr => 0x012C, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Klg-KlBegrenz'          => { addr => 0x0130, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Klg-KlSollwert'         => { addr => 0x0058, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Klg-Temp-Rl'            => { addr => 0x005C, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Ww-Abschaltung'         => { addr => 0x0134, bytes => 0x0001 },
 'Ww-Zeit-Ein'            => { addr => 0x0135, bytes => 0x0003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Ww-Zeit-Aus'            => { addr => 0x0138, bytes => 0x0003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Ww-Temp-Ist'            => { addr => 0x0060, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Ww-Temp-Soll'           => { addr => 0x013b, bytes => 0x0004, fmat => '%0.1f', unp => 'f<', min => 35, max => 55 },
 'Ww-Hysterese'           => { addr => 0x0143, bytes => 0x0004, fmat => '%0.1f', unp => 'f<', min => 5,  max => 10},
 'Uhrzeit'                => { addr => 0x0064, bytes => 0x0003, fmat => '%3$02d:%2$02d:%1$02d', unp => 'CCC' },
 'Datum'                  => { addr => 0x0067, bytes => 0x0003, fmat => '%02d.%02d.%02d', unp => 'CCC'},
 'BetrStundenKompressor'  => { addr => 0x006A, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'BetrStundenHzgPu'       => { addr => 0x006E, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'BetrStundenWwPu'        => { addr => 0x0072, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'BetrStundenSt2'         => { addr => 0x0076, bytes => 0x0004, fmat => '%0.1f', unp => 'f<' },
 'Zeit'                   => { addr => 0x0064, bytes => 0x0006, fmat=> '%4$02d.%5$02d.%6$02d %3$02d:%2$02d:%1$02d', unp => 'CCCCCC'},
 'SetBetriebsMode'        => { addr => 0x014E, bytes => 0x0003, 				 unp => 'N', pack => 'xC*'},
 'Display-Zeile-1'        => { addr => 0x008E, bytes => 0x0002, 				 unp => 'n' },
 'Display-Zeile-2'        => { addr => 0x0090, bytes => 0x0001, 				 unp => 'C' },
 'Status-Gesamt'          => { addr => 0x00D2, bytes => 0x0001, 				 unp => 'C' },
 'Status-Heizung'         => { addr => 0x00D4, bytes => 0x0003,                  unp => 'B24' },
 'Status-Kuehlung'        => { addr => 0x00DA, bytes => 0x0003,                  unp => 'B24' }, 
 'Mode-Heizung'           => { addr => 0x00DF, bytes => 0x0001,                  unp => 'B8' },
 'Mode-Kuehlung'          => { addr => 0x00E0, bytes => 0x0001,                  unp => 'B8' },
 'Mode-Warmwasser'        => { addr => 0x00E1, bytes => 0x0001,                  unp => 'B8' }
);

#
# FHEM module intitialisation
# defines the functions to be called from FHEM
#########################################################################
sub WKRCD4_Initialize($)
{
	my ($hash) = @_;

	require "$attr{global}{modpath}/FHEM/DevIo.pm";

	$hash->{ReadFn}  = "WKRCD4_Read";
	$hash->{ReadyFn} = "WKRCD4_Ready";
	$hash->{DefFn}   = "WKRCD4_Define";
	$hash->{UndefFn} = "WKRCD4_Undef";
	$hash->{SetFn}   = "WKRCD4_Set";
	$hash->{GetFn}   = "WKRCD4_Get";
	$hash->{AttrList} =
	  "do_not_notify:1,0 loglevel:0,1,2,3,4,5,6 " . $readingFnAttributes;
}

#
# Define command
# init internal values, open device,
# set internal timer to send read command / wakeup
#########################################################################									#
sub WKRCD4_Define($$)
{
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	return "wrong syntax: define <name> WKRCD4 [devicename|none] interval"
	  if ( @a < 3 );

	DevIo_CloseDev($hash);
	my $name = $a[0];
	my $dev  = $a[2];
	my $interval  = 60;
	
	if ( $dev eq "none" ) {
		Log3 undef, 1, "WKRCD4 device is none, commands will be echoed only";
		return undef;
	}
	
	if(int(@a) == 4) { 
		$interval= $a[3]; 
		if ($interval < 20) {
			return "interval too small, please use something > 20, default is 60";
		}
	}

	$hash->{buffer} 			= "";
	
	$hash->{DeviceName} 		= $dev;
	$hash->{INTERVAL}   		= $interval;

	$hash->{SerialRequests}		= 0;
	$hash->{SerialGoodReads} 	= 0;
	$hash->{SerialBadReads} 	= 0;

	# send wakeup string (read 2 values preceeded with AT)
	$hash->{LastRequestAdr}		= 8;
	$hash->{LastRequestLen} 	= 4;
	$hash->{LastRequest} 	  	= gettimeofday();
	my $ret = DevIo_OpenDev( $hash, 0, "WKRCD4_Wakeup" );
	
	# initial read after 3 secs, there timer is set to interval for update and wakeup
	InternalTimer(gettimeofday()+3, "WKRCD4_GetUpdate", $hash, 0);	

	return $ret;
}

#
# undefine command when device is deleted
#########################################################################
sub WKRCD4_Undef($$)    
{                     
	my ( $hash, $arg ) = @_;       
	DevIo_CloseDev($hash);         
	RemoveInternalTimer($hash);    
	return undef;                  
}    


#
# Encode the data to be sent to the device (0x10 gets doubled)
#########################################################################
sub Encode10 (@) {
	my @a = ();
	for my $byte (@_) {
		push @a, $byte;
		push @a, $byte if $byte == 0x10;
	}
	return @a;
}

#
# create a command for the WP as byte array
#########################################################################
sub WPCMD($$$$;@)
{
	my ($hash, $cmd, $addr, $len, @value ) = @_;
	my $name = $hash->{NAME};
	my @frame = ();
	
	if ($cmd eq "read") {
		@frame = (0x01, 0x15, Encode10($addr>>8, $addr%256), Encode10($len>>8, $len%256));	
	} elsif ($cmd eq "write") {
		@frame = (0x01, 0x13, Encode10($addr>>8, $addr%256), Encode10(@value));
	} else {
		Log3 $name, 3, "undefined cmd ($cmd) in WPCMD"; 
		return 0;
	}
	my $crc = CRC16(@frame);
	return (0xff, 0x10, 0x02, @frame, 0x10, 0x03, $crc >> 8, $crc % 256, 0xff);
}

#
# GET command
#########################################################################
sub WKRCD4_Get($@)
{
	my ( $hash, @a ) = @_;
	return "\"get WKRCD4\" needs at least an argument" if ( @a < 2 );

	my $name = shift @a;
	my $attr = shift @a;
	my $arg = join("", @a);
	
	if(!$WKRCD4_gets{$attr}) {
		my @cList = keys %WKRCD4_gets;
		return "Unknown argument $attr, choose one of " . join(" ", @cList);
	}

	# get Hash pointer for the attribute requested from the global hash
	my $properties = $frameReadings{$WKRCD4_sets{$attr}};
	if(!$properties) {
		return "No Entry in frameReadings found for $attr";
	}

	# get details about the attribute requested from its hash
	my $addr  = $properties->{addr};
	my $bytes = $properties->{bytes};
	Log3 $name, 4, sprintf ("Read %02x bytes starting from %02x for $attr", $bytes, $addr);

	# create command for WP
	my $cmd = pack('C*', WPCMD($hash, 'read', $addr, $bytes));

	# set internal variables to track what is happending
	$hash->{LastRequestAdr} = $addr;
	$hash->{LastRequestLen} = $bytes;
	$hash->{LastRequest}  	= gettimeofday();
	$hash->{SerialRequests}++;

	Log3 $name, 4, "Get -> Call DevIo_SimpleWrite: " . unpack ('H*', $cmd);
	DevIo_SimpleWrite( $hash, $cmd , 0 );
	
	return sprintf ("Read %02x bytes starting from %02x", $bytes, $addr);
}
	
#
# SET command
#########################################################################
sub WKRCD4_Set($@)
{
	my ( $hash, @a ) = @_;
	return "\"set WKRCD4\" needs at least an argument" if ( @a < 2 );

	my $name = shift @a;
	my $attr = shift @a;
	my $arg = join("", @a);
	
	if(!defined($WKRCD4_sets{$attr})) {
		my @cList = keys %WKRCD4_sets;
		return "Unknown argument $attr, choose one of " . join(" ", @cList);
	}

	# get Hash pointer for the attribute requested from the global hash
	my $properties = $frameReadings{$WKRCD4_sets{$attr}};
	if(!$properties) {
		return "No Entry in frameReadings found for $attr";
	}

	# get details about the attribute requested from its hash
	my $addr  = $properties->{addr};
	my $bytes = $properties->{bytes};
	my $min   = $properties->{min};
	my $max   = $properties->{max};
	my $unp   = $properties->{unp};
	
    return "a numerical value between $min and $max is expected, got $arg instead"
        if($arg !~ m/^[\d.]+$/ || $arg < $min || $arg > $max);
	
	# convert string to value needed for command
	my $vp 	  = pack($unp, $arg);
	my @value = unpack ('C*', $vp);
	
	Log3 $name, 4, sprintf ("Write $attr: %02x bytes starting from %02x with %s (%s) packed with $unp", $bytes, $addr, unpack ('H*', $vp), unpack ($unp, $vp));
	my $cmd = pack('C*', WPCMD($hash, 'write', $addr, $bytes, @value));
	
	# set internal variables to track what is happending
	$hash->{LastRequestAdr} = $addr;
	$hash->{LastRequestLen} = $bytes;
	$hash->{LastRequest}  	= gettimeofday();
	$hash->{SerialRequests}++;
	Log3 $name, 4, "Set -> Call DevIo_SimpleWrite: " . unpack ('H*', $cmd);
	DevIo_SimpleWrite( $hash, $cmd , 0 );
	
	return sprintf ("Wrote %02x bytes starting from %02x with %s (%s)", $bytes, $addr, unpack ('H*', $vp), unpack ($unp, $vp));
}



#########################################################################
# called from the global loop, when the select for hash->{FD} reports data
sub WKRCD4_Read($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	# read from serial device
	my $buf = DevIo_SimpleRead($hash);		
	return "" if ( !defined($buf) );

	# convert to hex string to make parsing with regex easier
	$hash->{buffer} .= unpack ('H*', $buf);	
	Log3 $name, 5, "Current buffer content: " . $hash->{buffer};

	# did we already get a full frame?
	if ($hash->{buffer} =~ "ff1002(.{4})(.*)1003(.{4})ff(.*)") 
	{
		my $msg   = $1;
		my $frame = $msg . $2;
		my $crc   = $3;
		
		Log3 $name, 4, "Match msg: " .$msg . " " . $frame . " CRC " . $crc . " Rest " . $4;
		$hash->{buffer} = $4;

		# convert frame contents to byte array
		my @aframe = unpack ('C*', pack ('H*', $frame));
		
		# calculate CRC and compare with CRC from read 
		my $crc2 = sprintf("%04x",CRC16(@aframe));
		if ($crc eq $crc2) 
		{
			Log3 $name, 4, "CRC Ok.";
			$hash->{SerialGoodReads}++;
			
			# reply to read request ?
			if ($msg eq "0017") {
				my @data;
				for(my $i=0,my $offset=2;$offset<=$#aframe;$offset++,$i++)
				{
					# remove duplicate 0x10 (frames are encoded like this)
					if (($aframe[$offset]==16)&&($aframe[$offset+1]==16)) { $offset++; }
					$data[$i] = $aframe[$offset];
				}	
				Log3 $name, 4, "Parse with relative request start " . $hash->{LastRequestAdr} . " Len " . $hash->{LastRequestLen};
				# extract values from data
				parseReadings($hash, @data);			
			} elsif ($msg eq "0011") {
				# reply to write
			} else {
				Log3 $name, 3, "Unknown Msg type " . $msg . " in " . $hash->{buffer};
			}
		} else 
		{
			Log3 $name, 3, "Bad CRC from WP: " . $crc . " berechnet: " . $crc2 . " Frame ". $frame;
			$hash->{SerialBadReads} ++;
		};
		@aframe = ();
	} else {
		Log3 $name, 5, "NoMatch: " . $hash->{buffer};
	};
	return "";
}

#
# copied from other FHEM modules
#########################################################################
sub WKRCD4_Ready($)
{
	my ($hash) = @_;

	return DevIo_OpenDev( $hash, 1, undef )
	  if ( $hash->{STATE} eq "disconnected" );

	# This is relevant for windows/USB only
	my $po = $hash->{USBDev};
	my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
	return ( $InBytes > 0 );
}

#
# send wakeup /at least my waterkotte WP doesn't respond otherwise
#########################################################################
sub WKRCD4_Wakeup($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	$hash->{SerialRequests}++;
	
	$hash->{LastRequestAdr} = 8;
	$hash->{LastRequestLen} = 4;
	$hash->{LastRequest}  	= gettimeofday();
	
	my $cmd = "41540D100201150008000410037EA010020115003000041003FDC3100201150034000410037D90";
	DevIo_SimpleWrite( $hash, $cmd , 1 );
	
	Log3 $name, 5, "sent wakeup string: " . $cmd . " done."; 
	return undef;
}

#
# request new data from WP
###################################
sub WKRCD4_GetUpdate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WKRCD4_GetUpdate", $hash, 1);
	InternalTimer(gettimeofday()+$hash->{INTERVAL}/2, "WKRCD4_Wakeup", $hash, 1);

	$hash->{SerialRequests}++;
	
	my $cmd = pack('C*', WPCMD($hash, 'read', 0, 0x170));
	$hash->{LastRequestAdr} = 0;
	$hash->{LastRequestLen} = 0x170;
	$hash->{LastRequest}  	= gettimeofday();
	DevIo_SimpleWrite( $hash, $cmd , 0 );
	
	Log3 $name, 5, "GetUpdate -> Call DevIo_SimpleWrite: " . unpack ('H*', $cmd);
	
	return 1;
}

#
# calculate CRC16 for communication with the WP
#####################################################################################################
sub CRC16
{
    my $CRC = 0;
    my $POLY  = 0x800500;

    for my $byte (@_, 0, 0) {
        $CRC |= $byte;
        for (0 .. 7) {
            $CRC <<= 1;
            if ($CRC & 0x1000000) { $CRC ^= $POLY; }
            $CRC &= 0xffffff;
        }
    }
    return $CRC >> 8;
}


#
# get Values out of data read
#####################################################################################################
sub parseReadings
{
    my ($hash, @data) = @_;
  	my $name = $hash->{NAME};
  
	my $reqStart = $hash->{LastRequestAdr};
	my $reqLen	 = $hash->{LastRequestLen};
    
	# get enough bytes?
    if (@data >= $reqLen)
    {
		readingsBeginUpdate($hash);
		# go through all possible readings from global hash
        while (my ($reading, $property) = each(%frameReadings))
        {
			my $addr  = $property->{addr};
			my $bytes = $property->{bytes};
			
			# is reading inside data we got?
            if (($addr >= $reqStart) && 
			    ($addr + $bytes <= $reqStart + $reqLen))
            {
				my $Idx = $addr - $reqStart;
				# get relevant slice from data array
				my @slice = @data[$Idx .. $Idx + $bytes - 1];
				
				# convert according to rules in global hash or defaults
				my $pack   = ($property->{pack}) ? $property->{pack} : 'C*';
				my $unpack = ($property->{unp})  ? $property->{unp}  : 'H*';
				my $fmat   = ($property->{fmat}) ? $property->{fmat} : '%s';
				#my $value = sprintf ($fmat, unpack ($unpack, pack ($pack, @slice))) . " packed with $pack, unpacked with $unpack, (hex " . unpack ('H*', pack ('C*', @slice)) . ") format $fmat";
				my $value = sprintf ($fmat, unpack ($unpack, pack ($pack, @slice)));
				
				readingsBulkUpdate( $hash, $reading, $value );
				Log3 $name, 4, "parse set reading $reading to $value" if (@data <= 20);
            }
        }
		readingsEndUpdate( $hash, 1 );
	}
    else
    {
        Log3 $name, 3, "Data len smaller than requested ($reqLen) : " . unpack ('H*', pack ('C*', @data));
        return 0;
    }
}

1;
