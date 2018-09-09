#################################################################################
# 45_Plugwise.pm
#
# FHEM Module for Plugwise
#
# Copyright (C) 2014 Stefan Guttmann
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
# Info on protocol:
# http://roheve.wordpress.com/2011/05/15/plugwise-protocol-analysis-part-3/
# http://www.domoticaforum.eu/viewtopic.php?f=39&t=4319&start=30
#
# The GNU General Public License may also be found at http://www.gnu.org/licenses/gpl-2.0.html .
#
# define myPlugwise Plugwise /dev/ttyPlugwise
#
#
###########################
# # $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Digest::CRC qw(crc);
#use Math::Round;
use Data::Dumper;

my $Make2Channels = 1;
my $testcount=-1;
my $firstrun=0;
my $device=0;
my $data="";
my $toggle=0;
my $status="";
my ($self)=();
my $lastcircle="";
my $buffer="";
my $LastTime=time;
my $lastSync=-1;
my @buffer=();
my $initdone=0;
my %PW_gets = (
	"features"	=> 'Z'
  );  
 my %PW_sets = (
 	"Scan_Circles" => " ",
 	"reOpen"       => " ",
 	"syncTime"	   => " ",
# 	"pwPairForSec"  => ""
 );
my %PWType = (
  	"00" => "PW_Circle",
  	"01" => "PW_Circle",
  	"02" => "PW_Circle",
  	"03" => "PW_Switch",
  	"04" => "PW_Switch",
  	"05" => "PW_Sense",
  	"06" => "PW_Scan"
);
sub PW_Read($);
sub PW_Ready($);
sub PW_Undef($$);
sub PW_Write;
sub PW_Parse($$$$);
sub PW_DoInit($);
sub Plugwise_Initialize($$)
{
  my ($hash) = @_;
  $self = bless {
        _buf               => '',
        baud               => 115200,
        device             => '',
        _awaiting_stick_response => 0
    };

require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{Clients} = ":PW_Circle:PW_Scan:PW_Switch:PW_Sense:";
  my %mc = (
    "1:PW_Circle"      => "^PW_Circle",
    "2:PW_Scan"        => "^PW_Scan",
    "3:PW_Switch"      => "^PW_Switch",
    "4:PW_Sense"       => "^PW_Sense"
  );
  $hash->{MatchList} = \%mc;
# Normal devices
  $hash->{ReadFn}  = "PW_Read";
  $hash->{WriteFn} = "PW_Write";
  $hash->{ReadyFn} = "PW_Ready";
  $hash->{DefFn}   = "PW_Define";
  $hash->{UndefFn} = "PW_Undef";
  $hash->{SetFn}   = "PW_Set";
  $hash->{GetFn}   = "PW_Get";
  $hash->{StateFn} = "PW_SetState";
  $hash->{AttrList}= "do_not_notify:1,0 interval circlecount WattFormat showCom autosync";
  $hash->{ShutdownFn} = "PW_Shutdown";
}

#####################################
sub PW_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $inter	= 10;
  if (@a != 3 ) {
    my $msg = "wrong syntax: define <name> Plugwise devicename";
    Log3 $hash, 2, $msg;
    return $msg;
  }
  my $name = $a[0];
  my $dev = $a[2];
  $hash->{NAME}=$name;

  DevIo_CloseDev($hash);
  $firstrun=0;
  $hash->{DeviceName} = $dev;

#  if( $init_done ) {
#	  $attr{$name}{room}="Plugwise";
#	  $attr{$name}{interval}=10;
#	  $attr{$name}{circlecount}=50;
#	  $attr{$name}{WattFormat}="%0.f";
#  }
  my $ret = DevIo_OpenDev( $hash, 0, undef);
  InternalTimer(gettimeofday()+5, "PW_GetUpdate", $hash, 0);
  return undef;
}

sub PW_GetUpdate($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit) = localtime(time);
  my $n=0;
  if ($firstrun==2) {return undef};
  InternalTimer(gettimeofday()+$attr{$name}{interval}, "PW_GetUpdate", $hash, 1);
#  Log 3,Dumper($hash->{helper});
  if ($firstrun==0) {
    PW_DoInit($hash); 
    return undef;
  }
  delete $self->{_waiting};

  foreach ( keys %{ $hash->{helper}->{circles} } ) {
	$n=$_;
	if (defined $hash->{helper}->{circles}->{$n}->{lastContact}) {
		if (time>$hash->{helper}->{circles}->{$n}->{lastContact} +960) {
			Log3 $hash,3,"Set Circle $n offline";
			my %xplmsg = ( schema => 'plugwise.basic', );
			my $saddr=$hash->{helper}->{circles}->{$n}->{name};
			$xplmsg{dest}=$self->{_plugwise}->{circles}->{$saddr}->{type};
	        $xplmsg{type} = 'output';
	        $xplmsg{text}= 'offline';
	        $xplmsg{short} = $saddr;
	        PW_Parse($hash, $hash, $hash->{NAME}, \%xplmsg);
			delete $hash->{helper}->{circles}->{$n};
		} elsif (time > $hash->{helper}->{circles}->{$n}->{lastContact} +900) {
			command($hash,'history',$hash->{helper}->{circles}->{$n}->{name},4);
			Log 3,"GetLog offline Circle $n";
		}
	}
  }
  foreach ( keys %{ $self->{_plugwise}->{circles} } ) {
    $n=$_;
    if (!defined $self->{_plugwise}->{circles}->{$n}->{type}) {$self->{_plugwise}->{circles}->{$n}->{type}=""};
        if ($self->{_plugwise}->{circles}->{$n}->{type} eq "" ||
        	!defined $self->{_plugwise}->{circles}->{$n}->{type}) {
    			command($hash,'status',$n);
        	}
    	if (defined $attr{$name}{autosync}) {
    		if ($attr{$name}{autosync}>0 && time > $lastSync+$attr{$name}{autosync}) {
    			$lastSync=time;
    			command($hash,'syncTime',$n);
    		}
    	}    
    }
}

sub MyRead($$)
{
  	my ($hash, $msg) = @_;
  	return if (!defined $msg->{dest} );
    PW_Parse($hash, $hash, $hash->{NAME}, $msg) if defined $msg;
}

sub PW_Write
{
  	my ($hash,$reciever,$fn,$a) = @_;
  	my $name = $hash->{NAME};
  	return if(!defined($fn));
  	my $msg = "$hash->{NAME} sending $fn";
  	$msg .= " to Adress $a" if defined $a;
  	if ($fn =~ /(on|off)/) {
     	command($hash,$fn,$reciever,$a);
  	} 
  	elsif ($fn =~ /(syncTime|ping|removeNode|livepower|status)/) {
    	command($hash,$fn,$reciever)
  	} 
  	elsif ($fn eq "getLog") {
 		command($hash,'history',$reciever,$a) if($a ne -1);
  	}
  	else
  	{	Log3 $hash,3,$msg;
  	}
  	return undef;
}


#####################################
sub PW_Undef($$)
{
  my ($hash, $arg) = @_;
  $firstrun=2;
  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub PW_Shutdown($)
{
  my ($hash) = @_;
  DevIo_CloseDev($hash);
  return undef;
}

#NeedsEdit
#####################################
sub PW_Set($@)
{
  my ($hash, @a) = @_;

  my $msg;
  my $name=$a[0];  my $reading= $a[1];
  my $n=1;
  return "\"set X\" needs at least one argument" if ( @a < 2 );
  if ($reading eq "myTest") {
  	$testcount=0;
  } elsif ($reading eq "myTestOff") {
  	$testcount=-1;
  }
  
	elsif(!$PW_sets{$reading}) {
		my @cList = keys %PW_sets;
		return "Unknown argument $reading, choose one of " . join(" ", @cList);
	}
	    if ($reading eq "Scan_Circles") {
        PW_DoInit($hash);
        #query_connected_circles($hash);
    } 
    elsif ($reading eq "syncTime") {
        foreach ( keys %{ $self->{_plugwise}->{circles} } ) {
			$n=$_;
			command($hash,'syncTime',$n);
  		}	    
    } 
    elsif ($reading eq "reOpen") {
        DevIo_CloseDev($hash);
        $hash->{ERRCNT} = 0;
        $firstrun=0;
        my $ret = DevIo_OpenDev( $hash, 0, undef);
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday()+2, "PW_GetUpdate", $hash, 0);
        return undef;        
    } 
    elsif ($reading eq "pwPairForSec") {
    	
  		# 	RemoveInternalTimer("pairTimer");
        #	InternalTimer(gettimeofday()+$value, "PW_Circle_OnOffTimer", 'pairTimer'), 1);
    
    	Mywrite( $hash, "000701" . _addr_s2l( $self->{_plugwise}->{coordinator_MAC} ) ,1 );
    }
}

sub PW_Get($@)
{
	my ( $hash, @a ) = @_;
        my $n=1;
	return "\"get X\" needs at least one argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt = shift @a;
	if(!$PW_gets{$opt}) {
		my @cList = keys %PW_gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
    if($opt eq 'features') {
    	foreach ( keys %{ $self->{_plugwise}->{circles} } ) {
        	$n=$_;
            command($hash,'feature',$n);
        }
        return undef;
    }
}
#NeedsEdit
#####################################
sub PW_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

#####################################
sub PW_DoInit($)
{
  my $hash = shift;
  Mywrite($hash,"000A",1);
  return undef;
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub PW_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $char;
  my $body;

# read from serial device
    my $buf = DevIo_SimpleRead($hash);
    my $buf2= $buf;
    $buf2=~s/\r\n/\|/g;
    return "" if ( !defined($buf) );
    $hash->{helper}{buffer} .=  $buf;	
    return unless ( $hash->{helper}{buffer} =~ s/(.+)\r\n// );
    do {
		my $v=$1;
 		if ($v=~/\x83?\x05\x05\x03\x03(\w+)/) {
    		$body = process_response($hash,$1);
    		if (length $body) {
#			if ($body ne undef) {
				my $str2=AttrVal($hash->{NAME},"showCom","xyz");
				my $showcom=qr/$str2/;
				if ($body->{showCom} =~ $showcom) {readingsSingleUpdate($hash,"communication", $body->{showCom},1)}
	    		if ($body->{text} eq "Found circle") {
					if ($body->{device} ne "FFFFFFFFFFFFFFFF") {
						PW_Write($hash,$body->{short},"getLog",1);
	
		    			command($hash,'status',$body->{short});
	        	        command($hash,'livepower',$body->{short});
	        	      } else {$body->{type}=""}        
		     	}
		        if ($body->{text} eq "Connected") {$hash->{"STATE"}="Connected";}
	 	        if ($body->{type} =~ /output|power|sense|humtemp|energy|ping/)    {
	 	        	if ($body->{dest} eq "PW_Switch" && $Make2Channels==1) {
	 	        		my $dest=$body->{short};
						$body->{short}=$dest . "_Ch".$body->{val3};
						MyRead($hash,$body);
	 	        	} else {
	 	        		MyRead($hash,$body);
	 	        	}
	 	        }
	         	if ($body->{dest} eq "none" 
	         	 && $body->{type} eq "stat"
	         	 && $body->{text} ne "ack")      {
	         	 	readingsSingleUpdate($hash,"LastMsg", $body->{text}." - Device: ".$body->{code},1) ;
	         	 }
	         	 if ($body->{type} eq "err3")      {Mywrite($hash, "0026" . $body->{device} ,1);}
	        	 if ($body->{type} eq "err")       {readingsSingleUpdate($hash,"LastMsg", $body->{text}." - Device: ".$body->{code},1) ;;
				 my $tm=(time - $LastTime);
	 			 if ($tm>600) {$hash->{"ERRCNT"}=0};
				 $LastTime=time;
	             $hash->{"ERRCNT"}++;
	             Log 3,Dumper($body);
	             if ($hash->{"ERRCNT"} == 50) {
	             		Log3 $hash,3,"$name - Too many Errors, giving up. Use 'get $name reOpen' after correcting the Problem";
		                DevIo_CloseDev($hash);
	        	        $firstrun=2;
	                	DevIo_CloseDev($hash);
	                	Log 3,Dumper($hash->{helper}{buffer});
	                	Log 3,"$name Disconnected...........................................";
		                $hash->{"STATE"}="Disconnected";
		                @buffer=();
	        	        return undef;
		             }
	        	 }
 #   		}
    		}
		} elsif ($v=~/\x23.*/) {}
		  elsif ($v=~/[0-9A-F]{16}/){} 
		else
		{
			Log3 $hash,3,"Not processed: $v";
		}
		
    } while ( $hash->{helper}{buffer} =~  s/(.+)\r\n// );
    $self->{_awaiting_stick_response} = 0;
	if (@buffer) {real_write($hash)};
        return $body;
}

sub PW_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;

  my %addvals;

    Log3 $hash, 5, "PW_Parse() ".Dumper($rmsg);
    $hash->{"MSGCNT"}++;
    $hash->{"TIME"} = TimeNow();
    $hash->{RAWMSG} = $rmsg;
    %addvals = (RAWMSG => $rmsg);
    Dispatch($iohash, $rmsg->{'dest'}, \%addvals);  

}

#NeedEdit
#####################################
sub PW_Ready($)
{
  my ($hash) = @_;
  return undef;
  return DevIo_OpenDev($hash, 1, "PW_Ready") if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

############# Plugwise-Tools

sub Mywrite {
    my ( $hash, $cmd, $cb, $pri ) = @_;
    my $packet = "\05\05\03\03" . $cmd . _plugwise_crc($cmd) . "\r\n"; # "\05\05\03\03" .
    real_write($hash,$packet,$pri);
}

sub _plugwise_crc {
    my ( $data ) = @_;
    sprintf( "%04X", crc( $data, 16, 0, 0, 0, 0x1021, 0, 0 ) );
}

sub real_write {
    my ( $hash, $str, $pri ) = @_;
    if (!$pri) {$pri=0;}
    if (defined $str) {
        if ($pri==0) {
        	push @buffer,$str;
        } else {
            unshift @buffer,$str;
        }
    } 
    if ($self->{_awaiting_stick_response} == 1) {    
    	return undef;
	}
	$str=shift @buffer;
    DevIo_SimpleWrite($hash,$str,undef);
    $str=~s/\r\n//;
    $self->{_awaiting_stick_response} = 1;
    my $str2=AttrVal($hash->{NAME},"showCom","xyz");
	my $showcom=qr/$str2/;
	$str=~s/....([[:xdigit:]]{4})([[:xdigit:]]{4})(.*)/$1 $2 $3/g;
	if ($str =~ $showcom) {readingsSingleUpdate($hash,"communication", ">> $str",1)}
	readingsSingleUpdate($hash,"Buffer",@buffer,1);
	
}

# Print the data in hex
sub _hexdump {
    my $s = shift;
    my $r = unpack 'H*', $s;
    $s =~ s/[^ -~]/./g;
    $r . ' ' . $s;
}

# This function processes a response received from the USB stick.
#
# In a first step, the ACK response from the stick is handled. This means that the
# communication sequence number is captured, and a new entry is made in the response queue.
#
# Second step, if we receive an error response from the stick, pass this message back
#
# Finally, of course, decode actual useful messages and return their value to the caller
#
# The input to this function is the message with CRC, with the header and trailing part removed
sub process_response {
#    my ( $hash, $frame ) = @_;
    my $hash= shift;
    my $frame= shift;
    if (!defined $frame||$frame eq '') {
        return undef
    }

        $frame =~ s/\x83*//g;
    Log3 $hash,5, "Response-Processing '$frame'";
    my $name=$hash->{NAME};
    my %xplmsg = ( schema => 'plugwise.basic', );
    # Check if the CRC matches
    if (!( _plugwise_crc( substr( $frame, 0, -4 ) ) eq
            substr( $frame, -4, 4 )
        )
        )
    {
        # Send out notification...
        #$xpl->ouch("PLUGWISE: received a frame with an invalid CRC");
        $xplmsg{dest}='none';
        $xplmsg{type} = 'err';
        $xplmsg{text}="Received frame with invalid CRC";
        $xplmsg{code} = $frame;
        return \%xplmsg;
    }

#Switch:
if ($testcount>=0){
	$testcount=$testcount+1;
	if ($testcount == 41) { $frame = "002403C1000D6F0002907DC90F09412E0006A17000856539070140264E0844C2030000";Log 3,"Insert 0024";}
	if ($testcount == 39) { $frame = "0061FFFE000D6F0002907DC90000";Log 3,"Insert 0061";}
	if ($testcount == 47) { $frame = "004FFFFE000D6F0002907DC9000000";Log 3,"Insert 004F";}
	if ($testcount == 53) { $frame = "0056FFFF000D6F0002907DC90101xxxx";Log 3,"Insert 0056";}
	if ($testcount == 56) { $frame = "0056FFFF000D6F0002907DC90100xxxx";Log 3,"Insert keypress";}
	if ($testcount == 62) { $frame = "0056FFFF000D6F0002907DC90201xxxx";Log 3,"Insert keypress";}
	if ($testcount == 69) { $frame = "0056FFFF000D6F0002907DC90200xxxx";Log 3,"Insert keypress";}

# Circle
#	$testcount=$testcount+1;
#	if ($testcount == 40) { $frame = "0027527B000D6F0002907DC83F807E5AB5DCBDA03D74A00400000000xxxx";Log 3,"Insert Calibration";}
#	if ($testcount == 42) { $frame = "0024527C000D6F0002907DC80F097CA60006A95801856539070140264E0844C202xxxx";Log 3,"Insert Status";}
#	if ($testcount == 48) { $frame = "0013527E000D6F0002907DC800000000xxxx";Log 3,"Insert PowerInfo";}
#	if ($testcount == 54) { $frame = "0024527C000D6F0002907DC80F097CA60006A95800856539070140264E0844C202xxxx";Log 3,"Insert Status";}

}
    # Strip CRC, we already know it is correct
    $frame =~ s/(.{4}$)//;
#    my $str2=AttrVal($hash->{NAME},"showCom","xyz");
#	my $showcom=qr/$str2/;
#		if ($frame =~ $showcom) {readingsSingleUpdate($hash,"communication", "<< $frame",1)}
    
    Log3 $hash,4,"Frame after CRC-strip: $frame";
# After a command is sent to the stick, we first receive an 'ACK'. This 'ACK' contains a sequence number that we want to track and that notifies us of errors.
    if ( $frame =~ /^0000([[:xdigit:]]{4})([[:xdigit:]]{4})(.*)/ ) {
                      # ack | seq. nr. || response code |
        my $seqnr = $1;
        $xplmsg{showCom}="<< 0000 $1 $2 $3";
        $xplmsg{dest}='none';
        $xplmsg{type} = 'stat';
        $xplmsg{code} = $frame;
        if ( $2 eq "00C1" )    {	                   $xplmsg{text}="ack";                 return \%xplmsg;}
        elsif ( $2 eq "00C2" ) { $xplmsg{text}="Error on Ack-Signal"; $xplmsg{type} = 'err';Log 3,Dumper(%xplmsg);return \%xplmsg;}
        #Mywrite($hash,"000A");
	 	elsif ( $2 eq "00E1" ) {	                   $xplmsg{text}="Circle out of range"; $xplmsg{text}="ack";return \%xplmsg;}
	 	elsif ( $2 eq "00DE" ) {
	 				if ( $initdone == 0) {return undef};
			        my $saddr = _addr_l2s($3);
		            $xplmsg{dest}=$self->{_plugwise}->{circles}->{$saddr}->{type};
			        $xplmsg{type} = 'output';
			        $xplmsg{text}= 'off';
			        $xplmsg{code} = $frame;
			        $xplmsg{device} = $3;
			        $xplmsg{short} = $saddr;
			        return \%xplmsg;
	 	}
	 	elsif ( $2 eq "00D8"  ) {
	 				if ( $initdone == 0) {return undef};
	 		        my $saddr = _addr_l2s($3);
		            $xplmsg{dest}=$self->{_plugwise}->{circles}->{$saddr}->{type};
			        $xplmsg{type} = 'output';
			        $xplmsg{text}= 'on';
			        $xplmsg{code} = $frame;
			        $xplmsg{device} = $3;
			        $xplmsg{short} = $saddr;
			        return \%xplmsg;
	 	}
	 	elsif ( $2 eq "00F9" ) {	                   $xplmsg{text}="Clear group MAC-Table"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00FA" ) {	                   $xplmsg{text}="Fill Switch-schedule"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00F7" ) {	                   $xplmsg{text}="Request self-removal from network"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00F1" ) {	                   $xplmsg{text}="Set broadcast-time interval"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00F5" ) {	                   $xplmsg{text}="Set handle off"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00F4" ) {	                   $xplmsg{text}="Set handle on"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00E6" ) {	                   $xplmsg{text}="Set PN"     ; return \%xplmsg;}
	 	elsif ( $2 eq "00F8" ) {	                   $xplmsg{text}="Set powerrecording"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00BE" ) {	                   $xplmsg{text}="Set scan-params ACK"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00BF" ) {	                   $xplmsg{text}="Set scan-params NACK"      ; $xplmsg{type} = 'err';return \%xplmsg;}
	 	elsif ( $2 eq "00B5" ) {	                   $xplmsg{text}="Set sense-boundaries ACK"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00B6" ) {	                   $xplmsg{text}="Set sense-boundaries NACK"      ; $xplmsg{type} = 'err';return \%xplmsg;}
	 	elsif ( $2 eq "00B3" ) {	                   $xplmsg{text}="Set sense-interval ACK"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00B4" ) {	                   $xplmsg{text}="Set sense-interval NACK"      ; $xplmsg{type} = 'err';return \%xplmsg;}
	 	elsif ( $2 eq "00F6" ) {	                   $xplmsg{text}="Set sleep-behavior"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00E5" ) {	                   $xplmsg{text}="Activate Switch-schedule on"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00E4" ) {	                   $xplmsg{text}="Activate Switch-schedule off"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00DD" ) {	                   $xplmsg{text}="Allow nodes to join ACK0"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00D9" ) {	                   $xplmsg{text}="Allow nodes to join ACK1"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00C8" ) {	                   $xplmsg{text}="Bootload aborted"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00C9" ) {	                   $xplmsg{text}="Bootload done"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00D5" ) {	                   $xplmsg{text}="Cancel read Powermeter-Info Logdata"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00C4" ) {	                   $xplmsg{text}="Cannot join network"      ; $xplmsg{type} = 'err';return \%xplmsg;}
	 	elsif ( $2 eq "00C3" ) {	                   $xplmsg{text}="Command not allowed"      ; $xplmsg{type} = 'err';return \%xplmsg;}
	 	elsif ( $2 eq "00D1" ) {	                   $xplmsg{text}="Done reading Powermeter-Info Logdata"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00C0" ) {	                   $xplmsg{text}="Ember stack error"      ; $xplmsg{type} = 'err';return \%xplmsg;}
	 	elsif ( $2 eq "00C5" ) {	                   $xplmsg{text}="Exceeding Tableindex"      ;$xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00CF" ) {	                   $xplmsg{text}="Flash erased"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00C6" ) {	                   $xplmsg{text}="Flash error"      ;  $xplmsg{type} = 'err';return \%xplmsg;}
	 	elsif ( $2 eq "00ED" ) {	                   $xplmsg{text}="Group-MAC added"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00EF" ) {	                   $xplmsg{text}="Group-MAC not added"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00F0" ) {	                   $xplmsg{text}="Group-MAC not removed"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00EE" ) {	                   $xplmsg{text}="Group-MAC removed"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00E8" ) {	                   $xplmsg{text}="Image activate ACK"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00CC" ) {	                   $xplmsg{text}="Image check timeout"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00CB" ) {	                   $xplmsg{text}="Image invalid"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00CA" ) {	                   $xplmsg{text}="Image valid"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00C7" ) {	                   $xplmsg{text}="Node-change accepted"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00CD" ) {	                   $xplmsg{text}="Ping timeout 1sec"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00EB" ) {	                   $xplmsg{text}="Pingrun busy"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00EC" ) {	                   $xplmsg{text}="Pingrun finished"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00CE" ) {	                   $xplmsg{text}="Public network-info complete"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00D0" ) {	                   $xplmsg{text}="Remote flash erased"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00F3" ) {	                   $xplmsg{text}="Reply role changed NOK"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00F2" ) {	                   $xplmsg{text}="Reply role changed OK"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00E0" ) {	                   $xplmsg{text}="Send switchblock NACK"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00DA" ) {	                   $xplmsg{text}="Send calib-params ACK"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00E2" ) {	                   $xplmsg{text}="Set relais denied"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00DF" ) {	                   $xplmsg{text}="Set RTC-Data ACK"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00E7" ) {	                   $xplmsg{text}="Set RTC-Data NACK"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
	 	elsif ( $2 eq "00D7" ) {	                   $xplmsg{text}="Set year, month and flashadress DONE"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00BD" ) {	                   $xplmsg{text}="Start Light-Calibration started"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00E9" ) {	                   $xplmsg{text}="Start Pingrun ACK"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00EA" ) {	                   $xplmsg{text}="Stop Pingrun ACK"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00DC" ) {	                   $xplmsg{text}="Syncronize NC ACK"      ; return \%xplmsg;}
	 	elsif ( $2 eq "00D6" ) {	                   $xplmsg{text}="Timeout Powermeter Logdata"      ; $xplmsg{type} = 'err'; return \%xplmsg;}
        else {
        	if ( $initdone == 0) {return undef};
            $xplmsg{schema} = 'log.basic';

            # Default error message
            my $text = 'Received error response: $frame';
            my $error = $2;

            my $msg_causing_error = $frame;
            if ( $msg_causing_error =~ /^0026([[:xdigit:]]{16}$)/ ) {
                my $device = _addr_l2s($1);
                $text = "No calibration response received for $device";
                delete $self->{_plugwise}->{circles}->{$device};
            }
			Log3 $hash,3, "Received error response: $frame";
	        $xplmsg{dest}='none';
	        $xplmsg{type} = 'stat';
	        $xplmsg{text}= $text;
	        $xplmsg{code} = $frame . ":" . $error;
            return \%xplmsg;

        }
    }

    if ( $frame
        =~ /^0011([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{4})/
        )
#0011 0063 000D6F00029014D 8010 14D0D6F00029C512 2BA4DFF4 6D2
# init resp | seq. nr.|| stick MAC addr || don't care || network key || short key
    {
        $hash->{"STICK_MAC"} = $2;
        $hash->{"NET_KEY"} = $4;
        $self->{_plugwise}->{stick_MAC} = _addr_l2s( $2 );
        $self->{_plugwise}->{network_key} = $4;
        $self->{_plugwise}->{short_key} = $5;
        $self->{_plugwise}->{connected} = 1;
        $firstrun = 1;

        Log3 $hash,3, "PLUGWISE: Received a valid response to the init request from the Stick. Connected!";
            query_connected_circles($hash);
	        $xplmsg{dest}='none';
	        $xplmsg{type} = 'stat';
	        $xplmsg{text}= 'Connected';
	        $xplmsg{code} = $frame;
	        $xplmsg{showCom}="<< 0011 $1 $2 $3 $4 $5";
	        return \%xplmsg;
    }

##############################################################################
##### Heartbeat
##### 0061 ???? Circle-MAC CRC
##############################################################################

if ( $frame =~ /^0061([[:xdigit:]]{4})([[:xdigit:]]{16})$/ ) {
	if ( $initdone == 0) {return undef};
    my $saddr = _addr_l2s($2);
    unless ($saddr ~~  $self->{_plugwise}->{circles}->{$saddr}) {
	    Log3 $hash,3, "PLUGWISE:Heartbeat from Unknown Device $2";
        $self->{_plugwise}->{circles}->{ _addr_l2s( $2 ) } = {};
        Mywrite($hash, "0026" . $2 ,0);
	    command($hash,'feature',_addr_l2s($2));
      	$xplmsg{dest}='none';
	    $xplmsg{type} = 'stat';
	    $xplmsg{text}= 'Found circle';
        $xplmsg{code} = $frame;
	    $xplmsg{device} = $2;
	    $xplmsg{showCom}="<< 0061 $1 $2";
        $xplmsg{short} = $saddr;
       }
    return \%xplmsg;
    }

# Process the response on a powerinfo request
# powerinfo resp | seq. nr. || Circle MAC || pulse1 || pulse8 | other stuff we don't care about
    #0013 0051 000D6F0000994CAA 0000 FFFF 00000000 FFFFF DB9000D
    if ( $frame
        =~ /^0013([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{4})([[:xdigit:]]{4})/
        )
    {
        my $saddr = _addr_l2s($2);
        my $pulse1 = $3;
        my $pulse8 = $4;

        # Assign the values to the data hash
        $self->{_plugwise}->{circles}->{$saddr}->{pulse1} = $pulse1;
        $self->{_plugwise}->{circles}->{$saddr}->{pulse8} = $pulse8;
        $xplmsg{showCom}="<< 0013 $1 $2 $3 $4";
        if ($4 eq "FFFF") {            
			$xplmsg{dest}='none';
	        $xplmsg{type} = 'ignore';
	        $xplmsg{text}= 'Ignored Spike';
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $saddr;

            return \%xplmsg;
        }
        # Ensure we have the calibration info before we try to calc the power,
        # if we don't have it, return an error reponse
        if ( !defined $self->{_plugwise}->{circles}->{$saddr}->{gainA} ) {
            $xplmsg{dest}='none';
	        $xplmsg{type} = 'err3';
	        $xplmsg{text}= 'Report power failed, calibration data not retrieved yet';
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $saddr;

            return \%xplmsg;
        }

        # Calculate the live power
        my ( $pow1, $pow8 ) = _calc_live_power($hash,$saddr);

        $xplmsg{dest}=$self->{_plugwise}->{circles}->{$saddr}->{type};
        $xplmsg{type} = 'power';
        $xplmsg{text}= ' ';
        $xplmsg{code} = $frame;
        $xplmsg{device} = $2;
        $xplmsg{short} = $saddr;
		$xplmsg{val1} = $pow1;
		$xplmsg{val2} = $pow8;
		$xplmsg{unit1} = 'W';
		$xplmsg{unit2} = 'W';
			
        return \%xplmsg;
    }

# Process the response on a query known circles command
# circle query resp| seq. nr. || Circle+ MAC || Circle MAC on || memory position
    if ( $frame
        =~ /^0019([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{2})$/
        )
    {
        $xplmsg{showCom}="<< 0019 $1 $2 $3 $4";
        my $nr=sprintf( "%02X", AttrVal($hash->{NAME},"circlecount",50) -1);
        if ($4 eq $nr) {Log 3,$hash->{NAME} . "Init done, found ". (keys(%{$self->{_plugwise}->{circles}})) . " devices";$initdone=1}
        if ( $3 ne "FFFFFFFFFFFFFFFF" ) {
            $self->{_plugwise}->{circles}->{ _addr_l2s( $3 ) } = {};
            Mywrite($hash, "0026" . $3 ,0);
        }
        
        $xplmsg{schema} = 'log.basic';
        $xplmsg{dest}='none';
        $xplmsg{type} = 'stat';
        $xplmsg{text}='none';
    	$xplmsg{text}= 'Found circle' if (defined $self->{_plugwise}->{circles}->{_addr_l2s($3)});
        $xplmsg{code} = $frame;
        $xplmsg{device} = $3;
        $xplmsg{short} = _addr_l2s($3);
        return \%xplmsg;
    }

# Process the response on a status request
# status response | seq. nr. || Circle+ MAC || year,mon, min || curr_log_addr || powerstate
    if ( $frame
    #0024 0050 000D6F0000994CAA 0F08595B 000440B 80 18 565390701402 24E0844C2 02
        =~ /^0024([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{8})([[:xdigit:]]{8})([[:xdigit:]]{2})([[:xdigit:]]{2})([[:xdigit:]]{12})([[:xdigit:]]{8})([[:xdigit:]]{2})/
        )
    {
    	my $saddr = _addr_l2s($2);
        my $onoff = $5 eq '00' ? 'off' : 'on';
        my $current = $5 eq '00' ? 'LOW' : 'HIGH';
        $self->{_plugwise}->{circles}->{$saddr}->{onoff}        = $onoff;
        if(!exists $PWType{$9}) {
	    	Log3 $name, 2, "$name: Autocreate: unknown familycode '$9' found. Please report this!";
      		next;
    	} else {
#    		Log 3,"Device $saddr now is $PWType{$9}";
    		$self->{_plugwise}->{circles}->{$saddr}->{type} = $PWType{$9};
    	}
#        $self->{_plugwise}->{circles}->{$saddr}->{type}         = 'Circle' if (hex($9) <= 2);
#        $self->{_plugwise}->{circles}->{$saddr}->{type}         = 'Switch' if (hex($9) == 3 || hex($9) == 4);
#        $self->{_plugwise}->{circles}->{$saddr}->{type}         = 'Sense' if (hex($9) == 5);
#        $self->{_plugwise}->{circles}->{$saddr}->{type}         = 'Scan' if (hex($9) == 6);
        $self->{_plugwise}->{circles}->{$saddr}->{curr_logaddr} = ( hex($4) - 278528 ) / 8;
		Log 3, "Unknown Device-Code: $frame" if (!defined $self->{_plugwise}->{circles}->{$saddr}->{type});
		Log 3, "Unknown Circle: $saddr" if (!defined $self->{_plugwise}->{circles}->{$saddr});
        my $circle_date_time = _tstamp2time($hash,$3);

            $xplmsg{dest}=$self->{_plugwise}->{circles}->{$saddr}->{type};
	        $xplmsg{type} = 'output';
	        $xplmsg{text}= $onoff;
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $saddr;
	        $xplmsg{showCom}="<< 0024 $1 $2 $3 $4 $5 $6 $7 $8 $9";
			$xplmsg{val1} = $self->{_plugwise}->{circles}->{$saddr}->{curr_logaddr};
			$xplmsg{val2} = $circle_date_time;
			$xplmsg{val3} = 0;

        return \%xplmsg;
    }

    # Process the response on a calibration request
    if ( $frame
        =~ /^0027([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{8})([[:xdigit:]]{8})([[:xdigit:]]{8})([[:xdigit:]]{8})$/
        )
    {
# calibration resp | seq. nr. || Circle+ MAC || gainA || gainB || offtot || offruis
#print "Received for $2 calibration response!\n";
        my $saddr = _addr_l2s($2);

        #print "Short address = $saddr\n";
        Log3 $hash,5,"PLUGWISE: Received calibration reponse for circle $saddr";

        $self->{_plugwise}->{circles}->{$saddr}->{gainA}
            = _hex2float($3);
        $self->{_plugwise}->{circles}->{$saddr}->{gainB}
            = _hex2float($4);
        $self->{_plugwise}->{circles}->{$saddr}->{offtot}
            = _hex2float($5);
        $self->{_plugwise}->{circles}->{$saddr}->{offruis}
            = _hex2float($6);

        Log3 $hash,5,"$2 - Calib: $3 - $4 - $5 - $6";
		$lastcircle=$saddr;

            $xplmsg{dest}='none';
	        $xplmsg{type} = 'stat';
	        $xplmsg{text}= 'Calibration-Info received.';
	        $xplmsg{showCom}="<< 0027 $1 $2 $3 $4 $5 $6";
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $saddr;
		return \%xplmsg;
    }

    # Process a Feature-Request
    if ( $frame
        =~ /^0060([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{16})/
        )
     {
     	my $s_id = _addr_l2s($2);
            $xplmsg{dest}='none';
            $xplmsg{showCom}="<< 0060 $1 $2 $3";
	        $xplmsg{type} = 'stat';
	        $xplmsg{text}= 'Features';
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $s_id;
			$xplmsg{val1} = $3;
        Log3 $hash,5,Dumper(%xplmsg);

        Log3 $hash,3, "PLUGWISE: Features for $s_id are $3";

        return \%xplmsg;
     }


    # Process the response of TempHum-Sensor

    if ( $frame
        =~ /^0105([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{4})([[:xdigit:]]{4})/
        )
     {
     	my $s_id = _addr_l2s($2);

            $xplmsg{dest}=$self->{_plugwise}->{circles}->{$s_id}->{type};
	        $xplmsg{type} = 'humtemp';
	        $xplmsg{showCom}="<< 0105 $1 $2 $3 $4";
	        $xplmsg{text}= ' ';
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $s_id;
			$xplmsg{val1} = (hex($3)-3145)/524.30;
			$xplmsg{val2} = (hex($4)-17473)/372.90;
			$xplmsg{unit1} = 'h';
			$xplmsg{unit2} = 'C';
			
            Log3 $hash,5,Dumper(%xplmsg);

        Log3 $hash,5, "PLUGWISE: Temperature for $s_id set";

        return \%xplmsg;
     }

## RemoveNode response
     if ( $frame
        =~ /^001D([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{2})/
        )
        #001D 1026 000D6F00029C5122 000D6F00029C5122 00
     {	
     	Log3 $hash,3,"Removed Node $3 (Index $4) from Network.";
     	$xplmsg{showCom}="<< 0000 $1 $2 $3 $4";
        $xplmsg{dest}='none';
        $xplmsg{type} = 'stat';
        $xplmsg{code} = $frame;
        $xplmsg{text} = 'Removed Node $3 (Index $4) from Network.';
        return \%xplmsg;
     }        
     
## Keypress on Switch
#0056FFFF000D6F0002769C7D0101   
     if ( $frame
        =~ /^0056([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{2})([[:xdigit:]]{2})/
        )
     {	
     	Log3 $hash,4,"Keypress";
        my $s_id = _addr_l2s($2);

            $xplmsg{dest}=$self->{_plugwise}->{circles}->{$s_id}->{type};
	        $xplmsg{type} = 'sense';
	        $xplmsg{showCom}="<< 0056 $1 $2 $3 $4";
	        $xplmsg{text}= ' ';
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $s_id;
			$xplmsg{val1} = hex($4);
			if ($Make2Channels==0) {
				$xplmsg{val1} = hex($4); #+((hex($3)-1)<<1) if ($self->{_plugwise}->{circles}->{$s_id}->{type} eq "PW_Switch");
				$xplmsg{val2} = (hex($3)-1)<<1;
			} else {
				$xplmsg{val3} = hex($3);
			}
            Log3 $hash,5,Dumper(%xplmsg);

        Log3 $hash,5, "PLUGWISE: Motion-Signal detected";

        return \%xplmsg;
     }
# Ping-Response
    if ( $frame
        =~ /^000E([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{2})([[:xdigit:]]{2})([[:xdigit:]]{4})/
        )
        {
    	if ( $initdone == 0) {return undef};
        Log3 $hash,4,"ping";
        my $s_id = _addr_l2s($2);

            $xplmsg{dest}=$self->{_plugwise}->{circles}->{$s_id}->{type};
	        $xplmsg{type} = 'ping';
	        $xplmsg{showCom}="<< 004F $1 $2 $3 $4 $5";
	        $xplmsg{text}= ' ';
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $s_id;
			$xplmsg{val1} = hex($3);
			$xplmsg{val2} = hex($4);
			$xplmsg{val3} = hex($5);
			Log3 $hash,5,Dumper(%xplmsg);

        return \%xplmsg;
        	
        }
# Pushbuttons
    if ( $frame
        =~ /^004F([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{2})/
        )
    {
    	if ( $initdone == 0) {return undef};
        Log3 $hash,4,"Keypress";
        my $s_id = _addr_l2s($2);

            $xplmsg{dest}=$self->{_plugwise}->{circles}->{$s_id}->{type};
	        $xplmsg{type} = 'press';
	        $xplmsg{showCom}="<< 004F $1 $2 $3";
	        $xplmsg{text}= ' ';
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $s_id;
			$xplmsg{val1} = hex($3);
            Log3 $hash,5,Dumper(%xplmsg);

        return \%xplmsg;
    }
    # Process the response on a historic buffer readout
    if ( $frame
        =~ /^0049([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{8})$/
        )
    {
    	# history resp | seq. nr. || Circle+ MAC || info 1 || info 2 || info 3 || info 4 || address
        my $s_id = _addr_l2s($2);
        my $log_addr = ( hex($7) - 278528 ) / 8;
	       	$xplmsg{showCom}="<< 0049 $1 $2 $3 $4 $5 $6 $7";

        #print "Received history response for $2 and address $log_addr!\n";

        # Assign the values to the data hash
        $self->{_plugwise}->{circles}->{$s_id}->{history}->{logaddress}
            = $log_addr;
        $self->{_plugwise}->{circles}->{$s_id}->{history}->{info1} = $3;
        $self->{_plugwise}->{circles}->{$s_id}->{history}->{info2} = $4;
        $self->{_plugwise}->{circles}->{$s_id}->{history}->{info3} = $5;
        $self->{_plugwise}->{circles}->{$s_id}->{history}->{info4} = $6;

        # Ensure we have the calibration info before we try to calc the power,
        # if we don't have it, return an error reponse
        if ( !defined $self->{_plugwise}->{circles}->{$s_id}->{gainA} ) {

#$xpl->ouch("Cannot report the power, calibration data not received yet for $s_id\n");
            $xplmsg{dest}='none';
	        $xplmsg{type} = 'err';
	        $xplmsg{text}= 'Report power failed, calibration data not retrieved yet';
	        $xplmsg{showCom}="<< 0049 $1 $2 $3 $4 $5 $6 $7";
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $s_id;

            return \%xplmsg;
        }
        my ( $tstamp, $energy ) = _report_history($hash,$s_id);

# If the timestamp is no good, we tried to retrieve a field that contains no valid data, generate an error response
        if ( $tstamp eq "000000000000" ) {

#$xpl->ouch("Cannot report the power for interval $log_addr of circle $s_id, it is in the future\n");
            $xplmsg{dest}='none';
	        $xplmsg{type} = 'err';
	        $xplmsg{text}= 'Report power failed, no valid data in time interval';
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $s_id;
	       	$xplmsg{showCom}="<< 0049 $1 $2 $3 $4 $5 $6 $7";
            return \%xplmsg;
        }

            $xplmsg{dest}=$self->{_plugwise}->{circles}->{$s_id}->{type};
	        $xplmsg{type} = 'energy';
	        $xplmsg{text}= ' ';
	        $xplmsg{code} = $frame;
	        $xplmsg{device} = $2;
	        $xplmsg{short} = $s_id;
			$xplmsg{val1} = $energy;
			$xplmsg{val2} = $tstamp;
			$xplmsg{val3} = $log_addr;
			$xplmsg{unit1} = 'kWh';

            Log3 $hash,5,Dumper(%xplmsg);

        Log3 $hash,5, "PLUGWISE: Historic energy for $s_id [$log_addr] is $energy kWh on $tstamp";

        return \%xplmsg;
    }

# We should not get here unless we receive responses that are not implemented...
#$xpl->ouch("Received unknown response: '$frame'");
		Log3 $hash,3,"PLUGWISE: Unknown Frame received: $frame - Please report this";

            $xplmsg{dest}='none';
	        $xplmsg{type} = 'err2';
	        $xplmsg{text}= 'Unknown Frame received';
	        $xplmsg{code} = $frame;
             return \%xplmsg;
}

sub command {
    my ( $hash, $command, $target, $parameter ) = @_;

    Log3 $hash,5,"Command=$command - Target=$target";
    if ( !defined($command) || !defined($target) ) {
        Log3 $hash,3,"A command to the stick needs a command and a target ID as parameter";
        return 0;
    }

#Log 3,"Set $self->{_plugwise}->{circles}->{$target}->{type} $target $command to $parameter";
    my $packet = "";
    my $pri=0;
    if ( defined $target ) {

 # Commands that target a specific device might need to be sent multiple times
 # if multiple devices are defined
            my $circle = uc($target);
            if ( $command =~ /(on|off)/ ) {
            	if ($self->{_plugwise}->{circles}->{$circle}->{type} eq "PW_Circle") {
                	$packet = "0017" . _addr_s2l($circle) . ($1 eq 'on' ? '01' : '00');
            	} elsif($self->{_plugwise}->{circles}->{$circle}->{type} eq "PW_Switch"){
#            		Log 3,"Set Switch $circle $parameter to $1";
            		if ($parameter eq "left") {
            			$packet = "0017" . _addr_s2l($circle) . "01" . $1 eq 'on' ? '01' : '00';         			
            		} elsif ($parameter eq "right") {
            			$packet = "0017" . _addr_s2l($circle) . "02" . $1 eq 'on' ? '01' : '00';
            		}         			

            	}
                $pri=1;
            	
            }
            elsif ($command eq "feature") {
                $packet = "005F" . _addr_s2l($circle);
            }
            elsif ($command eq "ping") {
                $packet = "000D" . _addr_s2l($circle);
            }
            elsif ( $command eq 'syncTime' ) {
                my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		$packet = "0016" . 
		               _addr_s2l($circle) . 
			         sprintf( "%02X", $year-100) .
				 sprintf( "%02X", $mon) .
				 sprintf( "%04X", ($mday * 24 * 60) + ($hour * 60) + $min) .
				 "FFFFFFFF" . 
				 sprintf( "%02X", $hour) . sprintf( "%02X", $min) . sprintf( "%02X", $sec) . sprintf( "%02X", $wday) ;
#		             Log3 $hash,3,"syncTime-Frame: $packet";
#			     return (undef);

            }
            elsif ( $command eq 'status' ) {
                $packet = "0023" . _addr_s2l($circle);
            }
            elsif ($command eq 'removeNode') {
            	$packet = "001C" . _addr_s2l( $self->{_plugwise}->{coordinator_MAC} ) . _addr_s2l($circle);
            }
            elsif ( $command eq 'livepower' ) {

     # Ensure we have the calibration readings before we send the read command
     # because the processing of the response of the read command required the
     # calibration readings output to calculate the actual power
# Log3 $hash,3,Dumper( $self->{_plugwise});
                if (!defined(
                        $self->{_plugwise}->{circles}->{$circle}->{offruis}
                    )
                    )
                {
                    my $longaddr = _addr_s2l($circle);
                    Mywrite( $hash,"0026" . $longaddr ,0)
                        ; #, "Request calibration info");
                }
                $packet = "0012" . _addr_s2l($circle);

            }
            elsif ( $command eq 'history' ) {

     # Ensure we have the calibration readings before we send the read command
     # because the processing of the response of the read command required the
     # calibration readings output to calculate the actual power
                if (!defined(
                        $self->{_plugwise}->{circles}->{$circle}->{offruis}
                    )
                    )
                {
                    my $longaddr = _addr_s2l($circle);
                    Mywrite($hash, "0026" . $longaddr ,0)
                        ; #, "Request calibration info");
                }

                if ( !defined $parameter ) {
                    Log3 $hash,3,"The 'history' command needs both a Circle ID and an address to read...";
                    return 0;
                }
                Log3 $hash,5,"requesting Log for $parameter";
                my $address = ($parameter *  8) + 278528;#* 8 + 278528;
                $packet
                    = "0048"
                    . _addr_s2l($circle)
                    . sprintf( "%08X", $address );
            Log3 $hash,5,"Write command: $packet";
            }
            else {
                Log3 $hash,3,"Received invalid command '$command'";
                return 0;
            }

            # Send the packet to the stick!
            Log3 $hash,5,"Write command: $packet";
            Mywrite($hash,$packet,$pri) if ( defined $packet );

        }
    }


# Interrogate the network coordinator (Circle+) for all connected Circles
# This sub will generate the requests, and then the response parser function
# will generate a hash with all known circles
# When a circle is detected, a calibration request is sent to ge the relevant info
# required to calculate the power information.
# Circle info goes into a global hash like this:
# $object->{_plugwise}->{circles}
# A single circle entry contains the short id and the following info:
# short_id => { gainA => xxx,
# gainB => xxx,
# offtot => xxx,
# offruis => xxx }
sub query_connected_circles {

    my ($hash) = @_;

# In this code we will scan all connected circles to be able to add them to the $self->{_plugwise}->{circles} hash
    my $index = 0;
Log3 $hash,5,$hash->{NAME} . " - Looking for Circles.....";
    # Interrogate the Circle+ and add its info into the circles hash
    $self->{_plugwise}->{coordinator_MAC}
        = _addr_l2s( $self->{_plugwise}->{network_key} );
    $self->{_plugwise}->{circles} = {}; # Reset known circles hash
    $self->{_plugwise}->{circles}->{ _addr_l2s( $self->{_plugwise}->{network_key} ) }
        = {}; # Add entry for Circle+
    Mywrite( $hash,        "0026" . _addr_s2l( $self->{_plugwise}->{coordinator_MAC} )  ,0);

    # Interrogate the first x connected devices
        while ( $index < AttrVal($hash->{NAME},"circlecount",50) ) {
        my $strindex = sprintf( "%02X", $index++ );
        my $packet
            = "0018"
            . _addr_s2l( $self->{_plugwise}->{coordinator_MAC} )
            . $strindex;
        Mywrite($hash,$packet,0); #, "Query connected device $strindex");
    }
    return;
}

# Convert the long Circle address notation to short
sub _addr_l2s {
    my ( $address ) = @_;
    my $saddr = substr( $address, -8, 8 );

# We will return at least 6 bytes, more if required
# This is to keep compatibility with existing code that only supports 6 byte short addresses
    return sprintf( "%06X", hex($saddr) );
}

# Convert the short Circle address notation to long
sub _addr_s2l {
    my ( $address ) = @_;
#    Log 3,Dumper(caller) if ($address eq 0xffffffff); 
    return "000D6F00" . sprintf( "%08X", hex($address) );
}

# Convert hex values to float for power readout
sub _hex2float {
    my ( $hexstr ) = @_;
    my $floater = unpack( 'f', reverse pack( 'H*', $hexstr ) );
    return $floater;
}

sub _report_history {
    my ( $hash, $id ) = @_;

    # Get the first data entry
    my $data = $self->{_plugwise}->{circles}->{$id}->{history}->{info1};

    my $energy = 0;
    my $tstamp = 0;

    if ( $data =~ /^([[:xdigit:]]{8})([[:xdigit:]]{8})$/ ) {

        # Calculate Wh
        my $corrected_pulses = _pulsecorrection( $hash,$id, hex($2) );
        $energy = $corrected_pulses / 3600 / 468.9385193 * 1000;
        $tstamp = _tstamp2time($hash,$1);

        # Round to 1 Wh
        $energy = sprintf($attr{$hash->{NAME}}{WattFormat},$energy);

        # Report kWh
#        $energy = $energy / 1000;

        #print "info1 date: $tstamp, energy $energy kWh\n";
    }

    return ( $tstamp, $energy );

}

# Convert a Plugwise timestamp to a human-readable format
sub _tstamp2time {
    my ( $hash, $tstamp ) = @_;
    # Return empty time on empty timestamp
    return "000000000000" if ( $tstamp eq "FFFFFFFF" );

    # Convert
    if ( $tstamp =~ /([[:xdigit:]]{2})([[:xdigit:]]{2})([[:xdigit:]]{4})/ ) {
        my $circle_date = sprintf( "%04i-%02i-%02i",
            2000 + hex($1),
            hex($2), int( hex($3) / 60 / 24 ) + 1 );
        my $circle_time = hex($3) % ( 60 * 24 );
        my $circle_hours = int( $circle_time / 60 );
        my $circle_minutes = $circle_time % 60;
        $circle_time = sprintf( " %02i:%02i", $circle_hours, $circle_minutes );

        return $circle_date . $circle_time;
    }
    else {
        return "000000000000";
    }
}

# Calculate the live power consumption from the last report.
sub _calc_live_power {
    my ( $hash, $id ) = @_;

    #my ($pulse1, $pulse8) = $self->pulsecorrection($id);
    my $pulse1 = _pulsecorrection( $hash,$id,
        hex( $self->{_plugwise}->{circles}->{$id}->{pulse1} ) );
    my $pulse8 = _pulsecorrection( $hash,$id,
        hex( $self->{_plugwise}->{circles}->{$id}->{pulse8} ) /8 );

   my $live1 = $pulse1 * 1000 / 468.9385193;
    my $live8 = $pulse8 * 1000 / 468.9385193;
    # Round
    $live1 = sprintf($attr{$hash->{NAME}}{WattFormat},$live1);
    $live8 = sprintf($attr{$hash->{NAME}}{WattFormat},$live8);

    return ( $live1, $live8 );

}

# Correct the reported number of pulses based on the calibration values
sub _pulsecorrection {
    my ( $hash, $id, $pulses ) = @_;

    # Get the calibration values for the circle
    my $offnoise = $self->{_plugwise}->{circles}->{$id}->{offruis};
    my $offtot = $self->{_plugwise}->{circles}->{$id}->{offtot};
    my $gainA = $self->{_plugwise}->{circles}->{$id}->{gainA};
    my $gainB = $self->{_plugwise}->{circles}->{$id}->{gainB};

    # Correct the pulses with the calibration data
    my $out
        = ( ( $pulses + $offnoise ) ^ 2 ) * $gainB
        + ( ( $pulses + $offnoise ) * $gainA )
        + $offtot;

    # Never report negative values, can happen with really small values
    $out = 0 if ( $out < 0 );

    return $out;

}



"Cogito, ergo sum.";

=pod
=item device
=item summary    Module for controling Plugwise-Devices
=item summary_DE Modul für das Plugwise-System
=begin html

<a name="Plugwise"></a>
<h3>Plugwise</h3>
<ul>
  This module is for the Plugwise-System.
  <br>
  Note: this module requires the Device::SerialPort or Win32::SerialPort module
  if the devices is connected via USB or a serial port.
  Also needed: digest:CRC
  You can install these modules using CPAN.
  <br><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Plugwise &lt;device&gt; </code><br>
  </ul>
    <br>
      &lt;device&gt; specifies the serial port to communicate with the Plugwise-Stick.
      Normally on Linux the device will be named /dev/ttyUSBx, where x is a number.
      For example /dev/ttyUSB0. Please note that the Plugwise-Stick normally operates at 115200 baud. You may specify the baudrate used after the @ char.<br>
      <br>
      Example: <br>
    <code>define myPlugwise Plugwise /dev/ttyPlugwise@115200</code>
      <br>
     </ul>
    <br>
 
  <a name="PLUGWISEset"></a>
  <b>Set</b>
  <ul>
    <code>Scan_Circles</code>
    <ul>
        Initiates a scan for new devices and defines them.
    </ul><br><br>
    <code>syncTime</code>
    <ul>
        Syncs all reachable devices to the system-time.
    </ul><br><br>
    <code>reOpen</code>
    <ul>
        Closes and reopens the serial-Port. (useful in case of to many Errors)
    </ul><br><br>
  </ul>
  <br><br>

  <b>Attributes</b>
  <ul>
    <code>circlecount</code><br>
    <ul>
      Max. Number of Circles to be found by the Scan-Command
      <br><br>
      </ul>
   <code>interval</code><br>
      <ul>standard polling-interval for new Circles
      </ul><br><br>
   <code>autosync</code><br>
      <ul>Sends every n seconds a SyncTime to each device
      </ul><br><br>
   <code>WattFormat</code><br>
      <ul>A string representing the format of the power-readings.
      If not defined, it defaults to %0.f
      </ul><br><br>
   <code>showCom</code><br>
      <ul>Writes the complete communication matching a RegEx into the reading "communication"
      (can be viewed in EventMonitor or used with a FileLog)
      </ul><br><br>      
  
  <br>
</ul>

=end html

=begin html_DE

<a name="Plugwise"></a>
<h3>Plugwise</h3>
<ul>
  Modul für das Plugwise-System.
  <br>
  Achtung: Dieses Modul benötigt folgende Perl-Module:
  <ul><li>Device::SerialPort oder Win32::SerialPort</li>
  <li>digest:CRC</li></ul>
  <br><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Plugwise &lt;device&gt; </code><br>
  </ul>
    <br>
      &lt;device&gt; Gibt den COM-Port des Plugwise-Stick an.
      Unter Linux ist dies im Normalfall /dev/ttyUSBx, wobei x eine fortlaufende Nummer ist. (zB /dev/ttyUSB0)
      Wobei es unter Linux sinnvoller ist, den Port mittels UDEV-Regeln oder mittels /dev/by-id/ anzugeben.
      Der Plugwise-Stick läuft fix auf 115200 Baud<br>
      <br>
      Beispiel: <br>
    <code>define myPlugwise Plugwise /dev/ttyPlugwise</code>
      <br>
     </ul>
    <br>
 
  <a name="PLUGWISEset"></a>
  <b>Set</b>
  <ul>
    <code>Scan_Circles</code>
    <ul>
        Startet eine Suche nach neuen Geräten und legt diese per Autocreate an.
    </ul><br><br>
    <code>syncTime</code>
    <ul>
        Syncronisiert die internen RTCs der Geräte mit der aktuellen Systemzeit.
    </ul><br><br>
    <code>reOpen</code>
    <ul>
        Öffnet den COM-Port neu (zB bei zu vielen Fehlern, nach deren Behebung)
    </ul><br><br>
  </ul>
  <br><br>

  <b>Attribute</b>
  <ul>
    <code>circlecount</code><br>
    <ul>
      Maximale Anzahl der Geräte, nach denengesucht wird.
      <br><br>
      </ul>
   <code>interval</code><br>
      <ul>Standard-Abfrageintervall der Circles
      </ul><br><br>
   <code>autosync</code><br>
      <ul>Sendet alle >n< Sekunden ein "syncTime" an alle Geräte
      </ul><br><br>
   <code>WattFormat</code><br>
      <ul>String, mit welchem die Power-Readings formatiert werden 
      Standard: %0.f
      </ul><br><br>
   <code>showCom</code><br>
      <ul>Schreibt die gesamte Kommunikation (gefiltern nach >regEx<) in das Reading "communication"
      (Am besten mit FileLog oder dem Eventmonitor anzusehen)
      </ul><br><br>      
  
  <br>
</ul>

=end html
=cut

