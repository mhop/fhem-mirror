##############################################################################
#
# 20_N4HBUS.pm
#
# net4home Busconnector Device
#
# (c) 2014-2016 Oliver Koerber <koerber@net4home.de>
#
#
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# $Id$
#
##############################################################################

package main;

use strict;
use warnings;
use POSIX;
use Data::Dumper;

my $n4hbus_Version = "1.0.1.0 - 22.10.2016";

sub N4HBUS_Read($@);
sub N4HBUS_Write($$$$);
sub N4HBUS_Ready($);
sub N4HBUS_getDevList($$);
sub N4HBUS_decompSection($$$);
sub N4HBUS_CompressSection($$);
sub N4HBUS_Initialize($)
{
	my ($hash) = @_;
	require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
	$hash->{ReadFn}		= "N4HBUS_Read";
	$hash->{WriteFn}	= "N4HBUS_Write";
	$hash->{ReadyFn}	= "N4HBUS_Ready";

# Normal devices
	$hash->{UndefFn}	= "N4HBUS_Undef";
	$hash->{DefFn}		= "N4HBUS_Define";
	$hash->{AttrList}	= "dummy:1,0 ".
						  "OBJADR ".
						  "MI ";
}

#################################################################################
sub N4HBUS_Define($$) {
#################################################################################

	my ($hash, $def) = @_;
	my @a = split("[ \t]+", $def);

	if(@a != 3) {
     my $msg = "wrong syntax: define <name> N4HBUS hostname:port";
     Log3 $hash, 2, $msg;
	 return $msg;
	}
    DevIo_CloseDev($hash);

	my $name = $a[0];
	my $dev  = $a[2];
	
	$hash->{VERSION}	= $n4hbus_Version;
	$hash->{DeviceName} = $dev;
	$hash->{Clients} 	= ":N4HMODULE:";
	my %matchList = ( "1:N4HMODULE" => ".*" );
	$hash->{MatchList} = \%matchList;

	Log3 $hash, 3, "N4HBUS_Define -> $name at $dev";

	if($dev eq "none") {
		Log3 $hash, 1, "N4HBUS device is none, commands will be echoed only";
		$attr{$name}{dummy} = 1;
		return undef;
	}
  
	my $ret = DevIo_OpenDev($hash, 0, "N4HBUS_DoInit");
	return $ret;
}

#################################################################################
sub N4HBUS_DoInit($) {
#################################################################################

	my $hash = shift;
	my $name = $hash->{NAME};
	delete $hash->{HANDLE}; 

	# set OBJ and MI if not defined as attributes
	if (!defined($hash->{OBJADR}) ) {
		$attr{$name}{OBJADR} = 32700;
	}
		
	if (!defined($hash->{MI}) ) {
		$attr{$name}{MI}  = 65281;
	}

	my $sendmsg = "190000000002ac0f400a000002bc02404600000487000000c000000200";
	DevIo_SimpleWrite($hash, $sendmsg, 1);
	return undef;
}

#################################################################################
sub N4HBUS_Undef($@) {
#################################################################################

	my ( $hash, $arg ) = @_;       
	my $name = $hash->{NAME};
	
    Log3 $hash, 2, "deleting port for $name";
	DevIo_CloseDev($hash);         
	
	return undef;  	
	
}

##################################################################################
sub decode_d2b (@) {
##################################################################################
# Umwandeln 
	my $w = sprintf("%04x\n", @_);   
	my $ret = substr($w,2,2).substr($w,0,2);

	return $ret;
}

#################################################################################
sub N4HBUS_CompressSection($$) {
#################################################################################

	my ($hash, $pUnCompressed) = @_;
	
	my ($cs, $x) = 0;
	my $pCompressed = "";
	my $sizeRaw = length($pUnCompressed)/2;
	
    for(my $i=0;$i < (length($pUnCompressed)/2); $i++) {
	 $cs = $cs + hex(substr($pUnCompressed,$i*2,2));
	}

	my $len = length($pUnCompressed)/2;
	my $hi = $len >> 8;
	my $lo = $len & 0b0000000011111111;				
	$pCompressed = sprintf ("%02X%02X", $hi,$lo);
			
	my $p = 0;
	while ($len>0){
	 $pCompressed = $pCompressed.(substr($pUnCompressed,$p*2,2));
	 $len--;	
	 $p++;
	}

	$pCompressed = $pCompressed."C0";
	$pCompressed = $pCompressed.sprintf ("%02X", ($cs>>24) );	
	$pCompressed = $pCompressed.sprintf ("%02X", ($cs>>16) );	
	$pCompressed = $pCompressed.sprintf ("%02X", ($cs>>8) );	
	$pCompressed = $pCompressed.sprintf ("%02X", ( ($cs>>0) & 0xff ) );	
	
	$pCompressed = sprintf ("%02X", (length($pCompressed)/2))."000000".$pCompressed;	
	return $pCompressed;
}	

#################################################################################
sub N4HBUS_decompSection($$$) {
#################################################################################
  my ($hash, $p2, $fs) = @_;

	my $ret = 0;
	
	my $inBlock;
	my $gPoutPos = 0;
	my $zaehler = 0;
	my $err = 0;
	my $ende = 0;
	my $gPout = "";
	my $bb = 0;
	my $bc = 0;
	my $csCalc = 0;
	my $csRx;
	my $maxoutlen = 372;
	my @ar2k;
	
	my $decompressor_err = -4;
	my $decompressor_errAdr = 0;

	
  while (($zaehler<$fs) && ($gPoutPos < $maxoutlen) && ($ende != 1) && ($err != 1)) {

	$bb = substr($p2,$zaehler*2,2);
	my $bbout = hex($bb) & 192;
 
  if ( (hex($bb) & 192) == 192) {
		# Ende ist gefunden
		$ende = 1;
		
	} elsif ((hex($bb) & 192) == 0) {
	
		$bc = substr($p2,(($zaehler+1)*2),2);
		$inBlock =  (hex(substr($p2,$zaehler*2,2))*256) + hex($bc);
		$zaehler = $zaehler+2;
		
        while ($inBlock > 0) {
			$inBlock--;
			$gPout = $gPout.substr($p2,$zaehler*2,2);
			$zaehler++;
		}

	} elsif ((hex($bb) & 192) == 64) {

		$bc = substr($p2,(($zaehler+1)*2),2);
		$inBlock =  ((hex(substr($p2,$zaehler*2,2))*256) + hex($bc)) & 16383;
		$bb = substr($p2,($zaehler+2)*2,2);

		$zaehler = $zaehler+3;

        while ($inBlock > 0) {
			$inBlock--;
			$gPout = $gPout.$bb;
		}
	
	} elsif ($bb & 0xC0 == 0x80) {
		$err = 1;
		$decompressor_err = -2;
		$zaehler++;
	}
	
    $decompressor_errAdr = $zaehler;
  }
  
  if (($err != 1) and ($ende == 1)) {
   $ret = $gPout;
  }
	return $ret;
}

##################################################################################
sub N4HBUS_bin2text ($) {
##################################################################################
# Umwandlung der empfangenen oder zu sendenden Daten in lesbares Format 

	my ( $data ) = @_;       
	my $ret = "";
	my $sub;

    if (length($data)>60) {
	# Kenne ich noch nicht
	$ret = "(".substr($data,0,12).")\t";
	# ptype 
	$sub = hex(substr($data,14,2).substr($data,12,2));
	$ret = $ret."ptype=$sub\t";
	# payloadlen
	$sub = hex(substr($data,18,2).substr($data,16,2));
	$ret = $ret."payloadlen=$sub\t";
	# MMS oder BIN
	$sub = hex(substr($data,22,2).substr($data,20,2));
	$ret = $ret."IP=$sub\t";
	# Kenne ich noch nicht
	$sub = substr($data,24, 6);
	
	$ret = $ret."($sub)\t";
	# type8
	$sub = hex(substr($data,30,2));
	$ret = $ret."type8=$sub\t";
	# ipsrc
	$sub = (substr($data,34,2).substr($data,32,2));
	$ret = $ret."MI=$sub\t";
	# ipdst
	$ret = $ret."ipdst=".hex(substr($data,38,2).substr($data,36,2))."\t";
	# objsrc
	$ret = $ret."objsrc=".hex(substr($data,42,2).substr($data,40,2))."\t";
	# datalen
	my $datalen = hex((substr($data,44,2)));
	$ret = $ret."datalen=".$datalen."\t";
	# ddata
	$ret = $ret."ddata=".substr($data,46, ($datalen*2))."\t";
	my $pos = $datalen*2+46;
	
	my $csRX	= hex(substr($data,$pos,2));
	my $csCalc	= hex(substr($data,$pos+2,2));
	my $len		= hex(substr($data,$pos+4,2));
	my $posb	= hex(substr($data,$pos+6,2));
	
	$ret = $ret."($csRX/$csCalc/$len/$posb)"
	}
	
	return $ret;
}

##################################################################################
sub N4HBUS_Write($$$$) {
##################################################################################

	my ($hash,$ipdst,$ddata,$objsource) = @_;
	my $name = $hash->{NAME};
	
	return if(!$hash || AttrVal($hash->{NAME}, "dummy", 0) != 0);
	
	my $sendmsg = "";
	my $sendbus = "";
	my $msg = "";
	
	my $objsrc = AttrVal($name, "OBJADR", 32700); 
	my $ipsrc  = AttrVal($name, "MI", 65281); 
	
	#  A10F 0000 4E00 0000 00 -  00 5902 0D62 2D65 03 32 00 64 03D416070102201500003120736563742000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004A4A030000

	# payload type
	$sendbus = "A10F0000";
	# payload len0
	$sendbus = $sendbus."4E000000";
	#??
	$sendbus = $sendbus."00";

	# typ8
	$sendbus = $sendbus."00";

	$sendbus = $sendbus.decode_d2b($ipsrc);
	$sendbus = $sendbus.decode_d2b($ipdst);

	if ($objsource !=0 ) {
	 $objsrc = $objsource;
	}
	
	$sendbus = $sendbus.decode_d2b($objsrc);
	
	# ddata
	while (length($ddata)<128) {
	 $ddata = $ddata."00";
	}
	$sendbus = $sendbus.$ddata;
	
	# csRx, csCalc, len, posb
	$sendbus = $sendbus."00000000";

	$sendmsg = N4HBUS_CompressSection($hash, $sendbus);
    Log3 $hash, 5, "N4HBUS (+++): $sendmsg";

		
	if(defined($hash)) {
		DevIo_SimpleWrite($hash, $sendmsg, 1);
	}
	

}

##################################################################################
sub N4HBUS_Read($@) {
#################################################################################
	my ($hash, $local, $regexp) = @_;
    my $buf = DevIo_SimpleRead($hash);

	return "" if(!defined($buf));
	my $name = $hash->{NAME};
 
	my $recdata = unpack('H*', $buf);
	my $data;

	my $len  = 0;
	$len  = substr($recdata,6,2); 
	$len  = $len.substr($recdata,4,2); 
	$len  = $len.substr($recdata,2,2); 
	$len  = $len.substr($recdata,0,2); 
	$len  =~ s/^0+//;

	my $test = "";
	$recdata  = substr($recdata,8,hex($len)*2); 
	
	
	while (length($recdata) >= ( hex($len) *2)) {
	
	$data 	= substr($recdata,0, hex($len)*2); 
	Log3 $hash, 5, "N4HBUS (DECOMP): Länge (".hex($len)." bytes)-$data";
# 001c a10f00000400000030 00 01ff a10f bc7f 03 66 00 00 01 76121401022015403a00c00000050d

	my $idx;
	$idx = index($data,"a10f");

	if ($idx>=0) {
		$data = substr($data,$idx); # Cut off beginning - Der Anfang interessiert erst mal nicht...

		my $msg 	= substr($data,18,length($data));
		my $type8   = hex(substr($msg,0,2));

		# Es ist ein "normales" Status-Paket
		
		if ($type8>=0) {

			$hash->{"${name}_MSGCNT"}++;
			$hash->{"${name}_TIME"} = TimeNow();
			$hash->{RAWMSG} = $msg;

			my %addvals = (RAWMSG => $data);
			Dispatch($hash, $msg, \%addvals) if($init_done);
			
		}
	} # a10f - Statuspaket
	
  	$recdata = substr($recdata,( hex($len) *2)); 
	} # while
	return undef;
}

#################################################################################
sub N4HBUS_Ready($) {
#################################################################################

	my ($hash) = @_;
	
	Log3 $hash, 1, "N4HBUS_Ready";
	return DevIo_OpenDev($hash, 1, "N4HBUS_DoInit");
}

# function decompSection(p2:pbyte; offset, fs:dword; p2out:pbyte; MaxOutLen:dword; useCS:boolean):dword;


#################################################################################
1;

=pod
=item device
=item summary Connector to net4home bus via IP
=item summary_DE Konnektor zum net4home Bus über IP
=begin html

<a name="N4HBUS"></a>
<h3>N4HBUS</h3>
  This module connects fhem to the net4home Bus.
  <br /><br />
  Further technical information can be found at the <a href="http://www.net4home.de">net4home.de</a> Homepage  
  <br /><br />
  <a name="N4HBUS_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; N4HBUS &lt;device&gt;</code>
  <br />  <br />
  &lt;device&gt; is a combination of &lt;host&gt;:&lt;port&gt;, where
  &lt;host&gt; is the IP address of the net4home Busconnector and &lt;port&gt; (default:3478).
  <br />  <br />
  Example:
  <ul>
    <code>define net4home N4HBUS 192.168.1.69:3478</code>
  </ul>
  </ul>

=end html

=begin html_DE

<a name="N4HBUS"></a>
<h3>N4HBUS</h3>
  Dieses Modul verbindet fhem über IP mit dem net4home Bus.
  <br /><br />
  Weitere technische Informationen gibt es auf der Homepage unter <a href="http://www.net4home.de">net4home.de</a>  
  <br /><br />
  <a name="N4HBUS_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; N4HBUS &lt;device&gt;</code>
  <br />  <br />
  &lt;device&gt; ist eine Kombination aus IP Adresse des net4home Busconnectors und dem Port (default:3478).
  <br />  <br />
  Beispiel:
  <ul>
    <code>define net4home N4HBUS 192.168.1.69:3478</code>
  </ul>
  </ul>

=end html_DE

=cut

