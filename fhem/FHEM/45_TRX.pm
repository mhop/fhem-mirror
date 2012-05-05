#################################################################################
# 45_TRX.pm
#
# FHEM Module for RFXtrx433
#
# Derived from 00_CUL.pm: Copyright (C) Rudolf Koenig"
#
# Copyright (C) 2012 Willi Herzig
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# The GNU General Public License may also be found at http://www.gnu.org/licenses/gpl-2.0.html .
#
###########################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

my $last_rmsg = "abcd";
my $last_time = 1;

sub TRX_Clear($);
sub TRX_Read($);
sub TRX_Ready($);
sub TRX_Parse($$$$);

sub
TRX_Initialize($)
{
  my ($hash) = @_;


  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "TRX_Read";
  $hash->{WriteFn} = "TRX_Write";
  $hash->{Clients} =
        ":TRX_WEATHER:TRX_SECURITY:TRX_LIGHT:";
  my %mc = (
    "1:TRX_WEATHER"   	=> "^..(50|51|52|54|55|56|5d).*",
    "2:TRX_SECURITY" 	=> "^..(20).*", 
    "3:TRX_LIGHT"	=> "^..(10|11|12).*", 
    "4:TRX_ELSE"   	=> "^...*",
  );
  $hash->{MatchList} = \%mc;

  $hash->{ReadyFn} = "TRX_Ready";

# Normal devices
  $hash->{DefFn}   = "TRX_Define";
  $hash->{UndefFn} = "TRX_Undef";
  $hash->{GetFn}   = "TRX_Get";
  $hash->{SetFn}   = "TRX_Set";
  $hash->{StateFn} = "TRX_SetState";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 addvaltrigger:1:0 longids loglevel:0,1,2,3,4,5,6";
  $hash->{ShutdownFn} = "TRX_Shutdown";
}

#####################################
sub
TRX_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> TRX devicename [noinit]"
    if(@a != 3 && @a != 4);

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  my $opt = $a[3] if(@a == 4);;

  if($dev eq "none") {
    Log 1, "TRX: $name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }

  if(defined($opt)) {
    if($opt eq "noinit") {
      Log 1, "TRX: $name no init is done";
      $attr{$name}{do_not_init} = 1;
    } else {
      return "wrong syntax: define <name> TRX devicename [noinit]"
    }
  }
  
  
  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "TRX_DoInit");
  return $ret;
}

#####################################
# Input is hexstring
sub
TRX_Write($$$)
{
  my ($hash,$fn,$msg) = @_;
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);

  return if(!defined($fn));

  my $bstring;
  $bstring = "$fn$msg";
  Log $ll5, "$hash->{NAME} sending $bstring";

  DevIo_SimpleWrite($hash, $bstring, 1);
}


#####################################
sub
TRX_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log GetLogLevel($name,$lev), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
TRX_Shutdown($)
{
  my ($hash) = @_;
  return undef;
}

#####################################
sub
TRX_Set($@)
{
  my ($hash, @a) = @_;

  my $msg;
  my $name=$a[0];
  my $reading= $a[1];
  $msg="$name => No Set function ($reading) implemented";
    return $msg;
}

#####################################
sub
TRX_Get($@)
{
  my ($hash, @a) = @_;

  my $msg;
  my $name=$a[0];
  my $reading= $a[1];
  $msg="$name => No Get function ($reading) implemented";
    Log 1,$msg;
    return $msg;
}

#####################################
sub
TRX_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

sub
TRX_Clear($)
{
  my $hash = shift;
  my $buf;

  # clear buffer:
  if($hash->{USBDev}) {
    while ($hash->{USBDev}->lookfor()) { 
    	$buf = DevIo_SimpleRead($hash);
    }
  }
  if($hash->{TCPDev}) {
   # TODO
    return $buf;
  }
}

#####################################
sub
TRX_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;
  my $buf;
  my $char = undef ;


  if(defined($attr{$name}) && defined($attr{$name}{"do_not_init"})) {
    	Log 1, "TRX: defined with noinit. Do not send init string to device.";
  	$hash->{STATE} = "Initialized" if(!$hash->{STATE});

        # Reset the counter
        delete($hash->{XMIT_TIME});
        delete($hash->{NR_CMD_LAST_H});

	return undef;
  }

  # Reset
  my $init = pack('H*', "0D00000000000000000000000000");
  DevIo_SimpleWrite($hash, $init, 0);
  DevIo_TimeoutRead($hash, 0.5);

  TRX_Clear($hash);

  #
  # Get Status
  $init = pack('H*', "0D00000102000000000000000000");
  DevIo_SimpleWrite($hash, $init, 0);
  $buf = DevIo_TimeoutRead($hash, 0.1);

  if (! $buf) {
    	Log 1, "TRX: Initialization Error: No character read";
	return "TRX: Initialization Error $name: no char read";
  } elsif ($buf !~ m/^\x0d\x01\x00.........../) {
	my $hexline = unpack('H*', $buf);
    	Log 1, "TRX: Initialization Error hexline='$hexline'";
	return "TRX: Initialization Error %name expected char=0x2c, but char=$char received.";
  } else {
    	Log 1, "TRX: Init OK";
  	$hash->{STATE} = "Initialized" if(!$hash->{STATE});
	# Analyse result and display it:
	if ($buf =~ m/^\x0d\x01\x00(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)/) {
		my $status = "";

		my $seqnbr = $1;
		my $cmnd = $2;
		my $msg1 = ord($3);
		my $msg2 = ord($4);
		my $msg3 = ord($5);
		my $msg4 = ord($6);
		my $msg5 = ord($7);
  		my $freq = { 
			0x50 => '310MHz',
			0x51 => '315MHz',
			0x52 => '433.92MHz receiver only',
			0x53 => '433.92MHz transceiver',
			0x55 => '868.00MHz',
			0x56 => '868.00MHz FSK',
			0x57 => '868.30MHz',
			0x58 => '868.30MHz FSK',
			0x59 => '868.35MHz',
			0x5A => '868.35MHz FSK',
			0x5B => '868.95MHz'
                 }->{$msg1} || 'unknown Mhz';
		$status .= $freq;
		$status .= ", " . sprintf "firmware=%d",$msg2;
		$status .= ", protocols enabled: ";
		$status .= sprintf "undecoded, " if ($msg3 & 0x80); 
		$status .= "ProGuard " if ($msg4 & 0x20); 
		$status .= "FS20 " if ($msg4 & 0x10); 
		$status .= "LaCrosse " if ($msg4 & 0x08); 
		$status .= "Hideki " if ($msg4 & 0x04); 
		$status .= "LightwaveRF " if ($msg4 & 0x02); 
		$status .= "Mertik " if ($msg4 & 0x01); 
		$status .= "Visonic " if ($msg5 & 0x80); 
		$status .= "ATI " if ($msg5 & 0x40); 
		$status .= "OREGON " if ($msg5 & 0x20); 
		$status .= "KOPPLA " if ($msg5 & 0x10); 
		$status .= "HOMEEASY " if ($msg5 & 0x08); 
		$status .= "AC " if ($msg5 & 0x04); 
		$status .= "ARC " if ($msg5 & 0x02); 
		$status .= "X10 " if ($msg5 & 0x01); 
		my $hexline = unpack('H*', $buf);
    		Log 4, "TRX: Init status hexline='$hexline'";
    		Log 1, "TRX: Init status: '$status'";
	}
  }
  #

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});

  return undef;
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
TRX_Read($)
{
  my ($hash) = @_;

  my $name = $hash->{NAME};

  my $char;

  my $mybuf = DevIo_SimpleRead($hash);

  if(!defined($mybuf) || length($mybuf) == 0) {
    DevIo_Disconnected($hash);
    return "";
  }

  my $TRX_data = $hash->{PARTIAL};
  #Log 5, "TRX/RAW: $TRX_data/$mybuf";
  $TRX_data .= $mybuf;

  #my $hexline = unpack('H*', $TRX_data);
  #Log 1, "TRX: TRX_Read '$hexline'";

  # first char as byte represents number of bytes of the message
  my $num_bytes = ord(substr($TRX_data,0,1));

  while(length($TRX_data) > $num_bytes) {
    # the buffer contains at least the number of bytes we need
    my $rmsg;
    $rmsg = substr($TRX_data, 0, $num_bytes+1);
    #my $hexline = unpack('H*', $rmsg);
    #Log 1, "TRX_Read rmsg '$hexline'";
    $TRX_data = substr($TRX_data, $num_bytes+1);;
    #$hexline = unpack('H*', $TRX_data);
    #Log 1, "TRX_Read TRX_data '$hexline'";
    #
    TRX_Parse($hash, $hash, $name, unpack('H*', $rmsg));
    $num_bytes = ord(substr($TRX_data,0,1));
  }
  #Log 1, "TRX_Read END";

  $hash->{PARTIAL} = $TRX_data;
}

sub
TRX_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;

  #Log 1, "TRX_Parse1 '$rmsg'";
  Log 5, "TRX_Parse1 '$rmsg'";

  my %addvals;
  # Parse only if message is different within 2 seconds 
  # (some Oregon sensors always sends the message twice, X10 security sensors even sends the message five times)
  if (("$last_rmsg" ne "$rmsg") || (time() - $last_time) > 1) { 
    #Log 1, "TRX_Dispatch '$rmsg'";
    %addvals = (RAWMSG => $rmsg);
    Dispatch($hash, $rmsg, \%addvals); 
    $hash->{"${name}_MSGCNT"}++;
    $hash->{"${name}_TIME"} = TimeNow();
    $hash->{RAWMSG} = $rmsg;
  } else { 
    #Log 1, "TRX_Dispatch '$rmsg' dup";
    #Log 1, "<-duplicate->";
  }

  $last_rmsg = $rmsg;
  $last_time = time();

}


#####################################
sub
TRX_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "TRX_Ready")
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

1;
