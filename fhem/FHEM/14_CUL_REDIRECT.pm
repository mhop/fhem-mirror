##############################################
# From dancer0705
#
# Receive additional protocols received by cul
#
# Copyright (C) 2015 Bjoern Hempel
#
# This program is free software; you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free Software 
# Foundation; either version 2 of the License, or (at your option) any later 
# version.
#
# This program is distributed in the hope that it will be useful, but 
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for 
# more details.
#
# You should have received a copy of the GNU General Public License along with 
# this program; if not, write to the 
# Free Software Foundation, Inc., 
# 51 Franklin St, Fifth Floor, Boston, MA 02110, USA
#
##############################################

package main;


use Data::Dumper;
use strict;
use warnings;

use SetExtensions;
use constant { TRUE => 1, FALSE => 0 };

sub
CUL_REDIRECT_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^o........";
  $hash->{ParseFn}   = "CUL_REDIRECT_Parse";
}

#
# Decode Oregon 2
#
sub decodeOrego2 {
    my $msg = shift;
    my $name = shift;
    my @a = split("", $msg);

    Log3 $name, 5, "CUL_REDIRECT decode Oregon 2 ($msg)"; 
    my $newMSG = "";
    my $bitData;
    my $hlen = length($msg);
	my $blen = $hlen * 4;
	$bitData= unpack("B$blen", pack("H$hlen", $msg)); 
	Log3 $name, 5, "bitdata: $bitData";
    
    if (index($bitData,"10011001") != -1) 
    {  # Valid OSV2 detected!	
	
	    Log3 $name, 5, "OSV2 protocol detected ($msg)";
	    
	    my $preamble_pos=index($bitData,"10011001");
	    my $message_end=index($bitData,"10011001",$preamble_pos+44);
       	$message_end = length($bitData) if ($message_end == -1);
		my $message_length = $message_end - $preamble_pos;
        my $idx=0;
		my $osv2bits="";
		my $osv2hex ="";
		
		for ($idx=$preamble_pos;$idx<length($bitData);$idx=$idx+16)
		{
			if (length($bitData)-$idx  < 16 )
			{
			  last;
			}
			my $osv2byte = "";
			$osv2byte=NULL;
			$osv2byte=substr($bitData,$idx,16);

			my $rvosv2byte="";
			
			for (my $p=1;$p<length($osv2byte);$p=$p+2)
			{
				$rvosv2byte = substr($osv2byte,$p,1).$rvosv2byte;
			}
			$osv2hex=$osv2hex.sprintf('%02X', oct("0b$rvosv2byte")) ;
			$osv2bits = $osv2bits.$rvosv2byte;
		}
		$osv2hex = sprintf("%02X", length($osv2hex)*4).$osv2hex;
		if (length($osv2hex)*4 == 88) {
		    Log3 $name, 5, "CUL_REDIRECT: OSV2 protocol converted to hex: ($osv2hex) with length (".(length($osv2hex)*4).") bits \n";
            return (1,$osv2hex);
        } else {
            Log3 $name, 5, "CUL_REDIRECT: ERROR: To short: OSV2 protocol converted to hex: ($osv2hex) with length (".(length($osv2hex)*4).") bits \n"; 
            return (-1, "CUL_REDIRECT: ERROR: To short: OSV2 protocol converted to hex: ($osv2hex) with length (".(length($osv2hex)*4).") bits"); 
        }  
	}
	return (-1, "Not a origon 2 protocol");
}
#
# Decode Oregon 3
#
sub decodeOrego3 {
    my $msg = shift;
    my $name = shift;
    my @a = split("", $msg);

    Log3 $name, 5, "CUL_REDIRECT decode Oregon 3 ($msg)"; 
    my $newMSG = "";
    my $bitData;
    my $hlen = length($msg);
	my $blen = $hlen * 4;
	$bitData= unpack("B$blen", pack("H$hlen", $msg)); 
	Log3 $name, 5, "bitdata: $bitData";
    
    if (index($bitData,"11110101") != -1) 
    {  # Valid OSV2 detected!	
	
	    Log3 $name, 5, "OSV3 protocol detected ($msg)";
	    
	    my $message_start=index($bitData,"0101");
	    my $message_end=length($bitData)-8;
       	
		my $message_length = $message_end - $message_start;
        my $idx=0;
		my $osv2bits="";
		my $osv2hex ="";
		
		
		
		for ($idx=$message_start; $idx<$message_end; $idx=$idx+8)
		{
		    if (length($bitData)-$idx  < 16 )
			{
			  last;
			}
			my $byte = "";
			$byte= substr($bitData,$idx,8); ## Ignore every 9th bit
			Log3 $name, 5, "$name: byte in order $byte ";
			$byte = scalar reverse $byte;
			Log3 $name, 5, "$name: byte reversed $byte , as hex: ".sprintf('%X', oct("0b$byte"))."\n";

			#$osv2hex=$osv2hex.sprintf('%X', oct("0b$byte"));
			$osv2hex=$osv2hex.sprintf('%2X', oct("0b$byte")) ;
		}
		$osv2hex = sprintf("%2X", length($osv2hex)*4).$osv2hex;
		if (length($osv2hex)*4 > 87) {
		    Log3 $name, 5, "CUL_REDIRECT: OSV3 protocol converted to hex: ($osv2hex) with length (".(length($osv2hex)*4).") bits \n";
            return (1,$osv2hex);
        } else {
            Log3 $name, 5, "CUL_REDIRECT: ERROR: To short: OSV3 protocol converted to hex: ($osv2hex) with length (".(length($osv2hex)*4).") bits \n"; 
            return (-1, "CUL_REDIRECT: ERROR: To short: OSV3 protocol converted to hex: ($osv2hex) with length (".(length($osv2hex)*4).") bits"); 
        }  
	}
	return (-1, "Not a origon 3 protocol");
}

sub	decode_Hideki
{
    my $msg = shift;
    my $name = shift;
    my @a = split("", $msg);
    
    Log3 $name, 5, "CUL_REDIRECT decode Hideki ($msg)"; 
    my $bitData;
    my $hlen = length($msg);
	my $blen = $hlen * 4;
    $bitData= unpack("B$blen", pack("H$hlen", $msg)); 
	
    Log3 $name, 5, "$name: search in $bitData \n";
	my $message_start = index($bitData,"10101110");
	my $length_min = 72;
    my $length_max = 104;
	
	if ($message_start >= 0 )   # 0x75 but in reverse order
	{
		Log3 $name, 5, "$name: Hideki protocol detected \n";

		# Todo: Mindest Länge für startpunkt vorspringen 
		# Todo: Wiederholung auch an das Modul weitergeben, damit es dort geprüft werden kann
		my $message_end = index($bitData,"10101110",$message_start+18); # pruefen auf ein zweites 0x75,  mindestens 18 bit nach 1. 0x75
        $message_end = length($bitData) if ($message_end == -1);
        my $message_length = $message_end - $message_start;
		
		return (-1,"message is to short") if ($message_length < $length_min );
		return (-1,"message is to long") if ($message_length > $length_max );

		
		my $hidekihex;
		my $idx;
		
		for ($idx=$message_start; $idx<$message_end; $idx=$idx+9)
		{
			my $byte = "";
			$byte= substr($bitData,$idx,8); ## Ignore every 9th bit
			Log3 $name, 5, "$name: byte in order $byte ";
			$byte = scalar reverse $byte;
			Log3 $name, 5, "$name: byte reversed $byte , as hex: ".sprintf('%X', oct("0b$byte"))."\n";

			$hidekihex=$hidekihex.sprintf('%02X', oct("0b$byte"));
		}
		Log3 $name, 4, "$name: hideki protocol converted to hex: $hidekihex with " .$message_length ." bits, messagestart $message_start";

		return  (1,$hidekihex); ## Return only the original bits, include length
	}
	return (-1,"Not a hideki protocol");
}

# Function which dispatches a message if needed.
sub CUL_REDIRECT_Dispatch($$$)
{
	my ($hash, $rmsg,$dmsg) = @_;
	my $name = $hash->{NAME};
	
	Log3 $name, 5, "converted Data to ($dmsg)";
	#if (!defined($hash->{DMSG})) {
	#    $hash->{DMSG} = "";
	#}
	#Dispatch only if $dmsg is different from last $dmsg, or if 2 seconds are between transmits
    if (($hash->{RAWMSG} ne $dmsg) || ($hash->{TIME}+1 < time()) ) { 
		#$hash->{MSGCNT}++;
		$hash->{TIME} = time();
		#$hash->{DMSG} = $dmsg;
		#$hash->{IODEV} = "RFXCOM";
		my $OregonClientMatch=index($hash->{Clients},"OREGON");
		if ($OregonClientMatch == -1) {
		    # Append Clients and MatchList for CUL
		    $hash->{Clients} = $hash->{Clients}.":OREGON:";
		    $hash->{MatchList}{"C:OREGON"} = "^(3[8-9A-F]|[4-6][0-9A-F]|7[0-8]).*";
		}
		my $HidekiClientMatch=index($hash->{Clients},"Hideki");
		if ($HidekiClientMatch == -1) {
		    # Append Clients and MatchList for CUL
		    $hash->{Clients} = $hash->{Clients}.":Hideki:";
		    $hash->{MatchList}{"C:Hideki"} = "^P12#75[A-F0-9]{17,30}";
		}
		readingsSingleUpdate($hash, "state", $hash->{READINGS}{state}{VAL}, 0);
		
		$hash->{RAWMSG} = $rmsg;
		my %addvals = (RAWMSG => $rmsg, DMSG => $dmsg);
		Dispatch($hash, $dmsg, \%addvals);  ## Dispatch to other Modules 
	}	else {
		Log3 $name, 1, "Dropped ($dmsg) due to short time or equal msg";
	}	
}

###################################
sub
CUL_REDIRECT_Parse($$)
{

    my ($hash, $msg) = @_;
    $msg = substr($msg, 1);
    my @a = split("", $msg);
    my $name = $hash->{NAME};

    my $rssi;
    my $l = length($msg);
    my $dmsg;
    my $message_dispatched=FALSE;
    $rssi = substr($msg, $l-2, 2);
    undef($rssi) if ($rssi eq "00");

    if (defined($rssi))
    {
        $rssi = hex($rssi);
        $rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74)) if defined($rssi);
        Log3 $name, 5, "CUL_REDIRECT ($msg) length: $l RSSI: $rssi";
    } else {
        Log3 $name, 5, "CUL_REDIRECT ($msg) length: $l"; 
    }

    if ("$a[0]" eq "m") {
        # Orego2
        Log3 $name, 5, "CUL_REDIRECT ($msg) match Manchester COODE length: $l"; 
        my ($rcode,$res) = decodeOrego2(substr($msg, 1), $name); 
	    if ($rcode != -1) {
			$dmsg = $res;	
			Log3 $name, 5, "$name Dispatch now to Oregon Module.";	
			CUL_REDIRECT_Dispatch($hash,$msg,$dmsg);
			$message_dispatched=TRUE;
		} 
		($rcode,$res) = decodeOrego3(substr($msg, 1), $name); 
	    if ($rcode != -1) {
			$dmsg = $res;	
			Log3 $name, 5, "$name Dispatch now to Oregon Module.";	
			CUL_REDIRECT_Dispatch($hash,$msg,$dmsg);
			$message_dispatched=TRUE;
		} 
		($rcode,$res) = decode_Hideki(substr($msg, 1), $name); 
		if ($rcode != -1) {
			$dmsg = 'P12#' . $res;	
			Log3 $name, 5, "$name Dispatch now to Hideki Module.";	
			CUL_REDIRECT_Dispatch($hash,$msg,$dmsg);
			$message_dispatched=TRUE;
		} 
		if ($rcode == -1) {
			Log3 $name, 5, "protocol does not match, ignore received package (" . substr($msg, 1) . ") Reason: $res";
            return "";
		}
        
    }
    if ($message_dispatched == FALSE) {
        return undef;
    }
    return "";
    
}

1;


=pod
=begin html

<a name="CUL_REDIRECT"></a>
<h3>CUL_REDIRECT</h3>
<ul>
  The CUL_REDIRECT modul receive additional protocols from CUL<br>
  and redirect them to other modules.
  <br>
  
  <a name="CUL_REDIRECT_Parse"></a>

</ul>

=end html

=begin html_DE

<a name="CUL_REDIRECT"></a>
<h3>CUL_REDIRECT</h3>
<ul>
  Das CUL_REDIRECT Modul empfängt weitere Protokolle vom CUL<br>
  und leitet diese an die entsprechenden Module weiter.
  <br>
  
  <a name="CUL_REDIRECT_Parse"></a>

</ul>

=end html_DE
=cut
