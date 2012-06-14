################################################################
#
#  Copyright notice
#
#  (c) 2012 Axel Berner (bikensnow@googlemail.com)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
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
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

##############################################
package main;

use strict;
use warnings;
use Data::Dumper;

my %POKEYS_IOTYPE = (
  "Obsolete"    => 0x0100, 
  "DigIn"       => 0x8200,
  "DigOut"      => 0x8400,
  "AdcIn"       => 0x0800,
  "DigInCtRise" => 0x4001,
  "DigInCtFall" => 0x4002,
  "ExtDigOut"   => 0xEF00,
  "GetBasic"    => 0xFFFF
);

my %sets = (
  "OFF"       => 0,
  "ON"        => 1,
  "OFF_PULSE" => 2,
  "ON_PULSE"  => 3
);

my %gets = (
  "Version"       => 0,
  "DevName"       => 1,
  "Serial"        => 2,
  "User"          => 3,
  "Value"         => 4,
  "CPUload"       => 5
);

sub
POKEYS_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "POKEYS_Define";
#  $hash->{UndefFn}   = "POKEYS_Undef";
  $hash->{SetFn}   = "POKEYS_Set";
  $hash->{GetFn}   = "POKEYS_Get";
  
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6"; #info
  Log(3,"POKEYS_Initialize OK");
}

sub
POKEYS_Get($@)
{
 	my ($hash, @a) = @_;

  if ( (int(@a) != 2) ) {
    return "Wrong syntax: use get <Name> <Type>";
  }
  if (!defined($gets{$a[1]})) {
    return "State \"$a[1]\" not known. Use ".join(",", sort keys %gets);
  }
 
  my $Type = $a[1];
  my $buf = undef;
  
 
  if ($hash->{IOTYPE} eq "GetBasic" ) {
    if($Type eq "Version") {
      $buf = POKEYS_IO($hash, 0x00, 0x00, 0x00, 0x00, 0x00, ""); #get version
      if (defined($buf)) {
        my ($ReCtrl,$ReOp,$ReOP1,$ReOP2,$ReOP3,$ReOP4,$ReReqId,$Chk,$ReOPX) = unpack("CCCCCCCCH56", "$buf");
        Log(3, "Version:".(1+$ReOP3/16).".".($ReOP3%16).".".$ReOP4);
      }   
    }

    elsif ($Type eq "Serial") {
      $buf = POKEYS_IO($hash, 0x00, 0x00, 0x00, 0x00, 0x00, ""); #get serial number
      if (defined($buf)) {
        my ($ReCtrl,$ReOp,$ReOP1,$ReOP2,$ReOP3,$ReOP4,$ReReqId,$Chk,$ReOPX) = unpack("CCCCCCCCH56", "$buf");
        Log(3, "Serial:".($ReOP1*256+$ReOP2));
      }   
    }
    
    elsif ($Type eq "User") {
      $buf = POKEYS_IO($hash, 0x03, 0x00, 0x00, 0x00, 0x00, ""); #get user id
      if (defined($buf)) {
        my ($ReCtrl,$ReOp,$ReOP1,$ReOP2,$ReOP3,$ReOP4,$ReReqId,$Chk,$ReOPX) = unpack("CCCCCCCCH56", "$buf");
        Log(3, "UserId: ".$ReOP1);
      }   
    } 

    elsif ($Type eq "DevName") {
      $buf = POKEYS_IO($hash, 0x06, 0x00, 0x00, 0x00, 0x00, ""); #get device name
      if (defined($buf)) {
        my ($ReCtrl,$ReOp,$ReOP1,$ReOP2,$ReOP3,$ReOP4,$ReReqId,$Chk,$ReOPX) = unpack("CCCCCCCCH56", "$buf");
        Log(3, "Name: ".unpack("A*",pack("H*",$ReOPX)));
      }
    }
 
    elsif ($Type eq "CPUload") {
      $buf = POKEYS_IO($hash, 0x05, 0x00, 0x00, 0x00, 0x00, ""); #get CPU load
      if (defined($buf)) {
        my ($ReCtrl,$ReOp,$ReOP1,$ReOP2,$ReOP3,$ReOP4,$ReReqId,$Chk,$ReOPX) = unpack("CCCCCCCCH56", "$buf");
        Log(3, "CPUload: ".(($ReOP1*100)/256)."%");
      }
    }
    
    else {
      return "Get $Type not supported by GetBasic-Pin";
    }
  } else {
    return "Get function not supported for $hash->{IOTYPE}";
  }
  
  return undef;
}

sub
POKEYS_Set($@)
{
 	my ($hash, @a) = @_;

  if (   (int(@a) == 0) #internal call by ON/OFF_PULSE
      && (defined($hash->{NEXTSTATE}))) {
    $a[1] = $hash->{NEXTSTATE};
    delete($hash->{NEXTSTATE});
  }
  
  if ( (int(@a) < 2) ) {
    return "Wrong syntax: use set <Name> <State> <holdTime in ms>" ;
  }
  if (!defined($sets{$a[1]})) {
    return "State \"$a[1]\" not known. Use ".join(",", sort keys %sets);
  }
  my $State       = $sets{$a[1]} % 2;
  my $PulseActive = (($a[1] eq "ON_PULSE") || ($a[1] eq "OFF_PULSE"));
  my $HoldTime    = (defined($a[2])) ? $a[2]/1000 : 1;
  
	if ($hash->{IOTYPE} eq "ExtDigOut" ) {
		my $p = $hash->{PIN} - 101;
		my @extPinArray = (0,0,0,0,0,0,0,0,0,0);
		if ($State eq "ON") {
			$extPinArray[9- int($p/8)] = 2**($p % 8);
		} else {
      #todo clear
      Log(3,"clear not yet supported");
    }
    
		#print "@extPinArray\n";
		my $pS = unpack("H*", pack("C*", @extPinArray));
		#p += 1; print "$p->$pS<-";
		my $buf = POKEYS_IO($hash, 0xDA, 0x01, 0x00, 0x00, 0x00, $pS); #set pin config
    return "POKEYS_IO error" if (!defined($buf));
    
    my ($ReCtrl,$ReOp,$ReOP1,$ReOP2,$ReOP3,$ReOP4,$ReReqId,$Chk,$ReOPX) = unpack("CCCCCCCCH56", "$buf");
    Log(3, "Set ExtPin $hash->{PIN} to $State: $ReOP1 $ReOP2");
    $hash->{STATE} = $State;
    $hash->{CHANGED}[0] = $State;
    DoTrigger($hash->{NAME}, undef);
	}

  elsif ($hash->{IOTYPE} eq "DigOut"){
		
		my $buf = POKEYS_IO($hash, 0x40, $hash->{PIN}-1, $State, 0x00, 0x00, ""); #set pin config
    return "POKEYS_IO error" if (!defined($buf));

    my ($ReCtrl,$ReOp,$ReOP1,$ReOP2,$ReOP3,$ReOP4,$ReReqId,$Chk,$ReOPX) = unpack("CCCCCCCCH56", "$buf");
    Log(3, "Set Pin $hash->{PIN} to $State: (0=OK) $ReOP1");
    $hash->{STATE} = $State;
    $hash->{CHANGED}[0] = $State;
    DoTrigger($hash->{NAME}, undef);
  } 
  
  else {
		return "Pin is no output";
	}
 
  if ($PulseActive != 0) {
    $hash->{NEXTSTATE} = ($State == 0) ? "ON" : "OFF";
    RemoveInternalTimer($hash); #remove old trigger
    InternalTimer(gettimeofday()+ $HoldTime, "POKEYS_Set", $hash, 0);
  } 

  return undef;
}

sub
POKEYS_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
  
  if ( (int(@a) < 5) ) {
    return "Wrong syntax: use define <name> POKEYS <PokeysName or IP> <Pin> <IOState> <updateTime in ms>" ;
  }
  
  #create connection to device
  $hash->{POKEYSNAME} = $a[2];
  my $err = POKEYS_Connect($hash);
  if (defined($err)) {
    return "Connect failed: $err";
  }
  
  #define pin
  $hash->{STATE}      = "undefined";
  $hash->{PIN}        = $a[3];
  $hash->{IOTYPE}     = $a[4];
  $hash->{INTERVAL}   = (defined($a[5])) ? ($a[5]/1000) : 1; #if no time is defined -> default 1sec
  $err = POKEYS_PinDefine($hash);
  if (defined($err)) {
    $hash->{PIN}      = undef;
    $hash->{IOTYPE}   = undef;
    $hash->{INTERVAL} = undef;
    return "PinDefine failed: $err ";
  }
  
  return undef;
}

sub
POKEYS_ReDefine($)
{
  my ($hash) = @_;
 
  my $err = POKEYS_Connect($hash);
  if (defined($err)) {
    #connect failed retry in 5sec
    InternalTimer(gettimeofday()+5, "POKEYS_Redefine", $hash, 0);
    return undef;
  }
 
  foreach my $d (keys %defs) {
    next if ($defs{$d}->{TYPE}       ne  $hash->{TYPE}); #no POKEYS device
    next if ($defs{$d}->{POKEYSNAME} ne  $hash->{POKEYSNAME}); #other POKEYS device
    # redefine of pin
    POKEYS_PinDefine($defs{$d});
  } 
}

sub
POKEYS_GetIPAdress($)
{
  #Log(3, "$PokeysName is found at $Host");
  return '192.168.178.34';
}

sub
POKEYS_Connect($)
{
	my ($hash) = @_;
  
  if (   (defined($hash->{TYPE}))
      && (defined($hash->{POKEYSNAME})
      && (defined($modules{$hash->{TYPE}}{$hash->{POKEYSNAME}}))
      && ($modules{$hash->{TYPE}}{$hash->{POKEYSNAME}}{STATE} eq "connected"))) {
    return undef; #Pokeys is already successfully connected
  }
  
  my $PokeysDev  = $hash->{TYPE};    
  my $PokeysName = $hash->{POKEYSNAME};  
  my $Host;
  my $Host_Port = '20055'; #default Port of Pokeys
  if ($PokeysName ~~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ ) {
    # Pokeys IP-adress is directly set
    $Host = $PokeysName;
  } else {
    #get Pokeys IP-adrress by UDP broadcast request
    $Host = POKEYS_GetIPAdress($PokeysName);
    
    return "PokeysName: $PokeysName does not exist" if (!defined($Host));
  }
          
  my $conn = IO::Socket::INET->new(PeerAddr => $Host,
                                   PeerPort => $Host_Port,
                                   Proto    => 'tcp');
  if($conn) {
    Log(3, "Connected to $PokeysName at $conn");
    $modules{$PokeysDev}{$PokeysName}{IP}     = $Host;
    $modules{$PokeysDev}{$PokeysName}{PORT}   = $Host_Port;
    $modules{$PokeysDev}{$PokeysName}{STATE}  = "connected";
    $modules{$PokeysDev}{$PokeysName}{TCPDev} = $conn;
  } else {
    return "Can't connect to $PokeysName at $Host";
  }

  return undef;
}


sub
POKEYS_PinDefine($)
{
	my ($hash) = @_;
  
  return "Pin \"$hash->{PIN}\" no number" if ($hash->{PIN} !~ /[0-9]+$/);
  
  return "IOState \"$hash->{IOTYPE}\" not known. Use ".join(",", sort keys %POKEYS_IOTYPE)
      if (!defined($POKEYS_IOTYPE{$hash->{IOTYPE}}));

  if ($hash->{IOTYPE} eq "GetBasic") {
    return "Pin $hash->{PIN} not supported (0)" if ( $hash->{PIN} != 0);
  }

  elsif ($hash->{IOTYPE} eq "ExtDigOut") {
    return "ExtPin $hash->{PIN} not supported (101-180)" if ( ($hash->{PIN} < 101) || (180 < $hash->{PIN}) );
  }
 
  else {
    return "Pin $hash->{PIN} not supported (1-55)" if ( ($hash->{PIN} < 1) || (55 < $hash->{PIN}) );
	}

  if ($hash->{IOTYPE} eq "GetBasic") {
    #No config on POKEYS needed
    #todo InternalTimer(gettimeofday()+1, "POKEYS_UpdateInputs", $hash, 0); #start cyclic input read
    Log(3, "GetBasic device defined");
  }

  elsif ($hash->{IOTYPE} eq "ExtDigOut") {
    #No config on POKEYS needed (Ext is default DigOut)
    Log(3, "ExtPin $hash->{PIN} is configured with $hash->{IOTYPE} (0=NOK, 255=OK): 255");
  }

  else {
    my $IOTYPE_HB = $POKEYS_IOTYPE{$hash->{IOTYPE}} / 0xFF;
  	my $IOTYPE_LB = $POKEYS_IOTYPE{$hash->{IOTYPE}} % 0xFF;
  	my $buf = POKEYS_IO($hash, 0x10, $hash->{PIN}-1, $IOTYPE_HB, $IOTYPE_LB, 0x00, ""); #0x10 set pin config
    return "POKEYS_IO error" if (!defined($buf));

    my ($ReCtrl,$ReOp,$ReOP1,$ReOP2,$ReOP3,$ReOP4,$ReReqId,$Chk,$ReOPX) = unpack("CCCCCCCCH56", "$buf");
    Log(3, "Pin $hash->{PIN} is configured with $hash->{IOTYPE} (0=NOK, 255=OK): $ReOP1");
    
    if ($hash->{IOTYPE} eq "DigIn") {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "POKEYS_UpdateDigIn", $hash, 0); #start cyclic DigIn read
    } 
    
    elsif ($hash->{IOTYPE} eq "AdcIn") {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "POKEYS_UpdateAdcIn", $hash, 0); #start cyclic AdcIn read
    } 
    
    elsif ($hash->{IOTYPE} eq "DigInCtRise") {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "POKEYS_UpdateDigInCt", $hash, 0); #start cyclic DigInCt read
    } 
    
    elsif ($hash->{IOTYPE} eq "DigInCtFall") {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "POKEYS_UpdateDigInCt", $hash, 0); #start cyclic DigInCt read
    } 
    
    else {
      # DigOut -> No cyclic update needed
    }
  }
  
  return undef;
}

sub
POKEYS_UpdateDigIn($)
{
  my ($hash) = @_;
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "POKEYS_UpdateDigIn", $hash, 0); #trigger next input read

  my $buf = POKEYS_IO($hash, 0x30, $hash->{PIN}-1, 0x00, 0x00, 0x00, ""); #get DigIn
  return "POKEYS_IO error" if (!defined($buf));


  my ($ReCtrl,$ReOp,$ReOP1,$ReOP2,$ReOP3,$ReOP4,$ReReqId,$Chk,$ReOPX) = unpack("CCCCCCCCH56", "$buf");
  if ($ReOP1 == 0) { #Pin state is OK
    my $newSTATE = ($ReOP2)? "ON":"OFF";
    if ($hash->{STATE} ne $newSTATE) {
      $hash->{STATE}      = $newSTATE;
      $hash->{CHANGED}[0] = $newSTATE;
      DoTrigger($hash->{NAME}, undef);
    }
  } else {
    $hash->{STATE} = "Unknown";
  }
}

sub
POKEYS_UpdateAdcIn($)
{
  my ($hash) = @_;
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "POKEYS_UpdateAdcIn", $hash, 0); #trigger next input read

  my $buf = POKEYS_IO($hash, 0x35, $hash->{PIN}-1, 0x00, 0x00, 0x00, ""); #get AdcIn
  return "POKEYS_IO error" if (!defined($buf));
  
  my ($ReCtrl,$ReOp,$ReOP1,$ReOP2,$ReOP3,$ReOP4,$ReReqId,$Chk,$ReOPX) = unpack("CCCCCCCCH56", "$buf");
  if ($ReOP1 == 0) { #Pin state is OK
    my $newSTATE = $ReOP2;  #todo cast
    if ($hash->{STATE} ne $newSTATE) {
      $hash->{STATE}      = $newSTATE;
      $hash->{CHANGED}[0] = $newSTATE;
      DoTrigger($hash->{NAME}, undef);
    }
  } else {
    $hash->{STATE} = "Unknown";
  }
}

sub
POKEYS_IO($$$$$$$)
{
	my ($hash, $SendOperation, $SOP1, $SOP2, $SOP3, $SOP4, $SOPX) = @_;
	
  if ($modules{$hash->{TYPE}}{$hash->{POKEYSNAME}}{STATE} ne "connected") {
    return undef;
  }
  
  my $conn = $modules{$hash->{TYPE}}{$hash->{POKEYSNAME}}{TCPDev};
  if (!defined($conn)) {
    Log(3, "POKEYS_IO: No handle (TCPDev) defined");
    POKEYS_Disconnect($hash);    
    return undef;
  }

  my $SendControl   = 0xBB;
	my $SendRequestId = 0x05; #todo random
	my $SChk = ($SendControl + $SendOperation + $SOP1 + $SOP2 + $SOP3 + $SOP4 + $SendRequestId) % 0x100;
	
	# add 8 bytes, plus string (max 56byte) and rest filled with zero
	my $msg = pack ("CCCCCCCCH112",$SendControl,$SendOperation,$SOP1, $SOP2, $SOP3, $SOP4,$SendRequestId,$SChk,$SOPX);
	my $res = syswrite($conn, $msg);
  if (!defined($res)) {
    Log(3, "POKEYS_IO write error"); 
    POKEYS_Disconnect($hash);    
    return undef;
  }
	
	my $bufRaw;
	$res = sysread($conn, $bufRaw, 64);
	if(!defined($res)) { 
    Log(3, "POKEYS_IO read error"); 
    POKEYS_Disconnect($hash);    
    return undef;
  }

 	#my $buf = unpack("H*","$bufRaw");
	#print "$buf\n";
	my ($ResControl,$ResOperation,$ROP1,$ROP2,$ROP3,$ROP4,$ResRequestId, $RChk) = unpack("CCCCCCCC", "$bufRaw");
	#print "$ResControl $ResOperation $ROP1 $ROP2 $ROP3 $ROP4 $ResRequestId $RChk\n";
	if (($ResControl + $ResOperation + $ROP1 + $ROP2 +$ROP3 + $ROP4 + $ResRequestId) % 0x100 != $RChk) 
		{ Log(3, "Wrong chk"); return undef; }
	if ($ResControl != 0xAA) 
		{ Log(3, "Control wrong"); return undef;}
	if ($ResOperation != $SendOperation) 
		{ Log(3, "Control Operation: $ResOperation vs $SendOperation"); return undef;}
	if ($SendRequestId != $ResRequestId) 
		{ Log(3, "Wrong Id: $SendRequestId vs $ResRequestId"); return undef;}
	
  return $bufRaw;
}

sub
POKEYS_Disconnect($)
{
  my ($hash) = @_;
  $modules{$hash->{TYPE}}{$hash->{POKEYSNAME}}{STATE} = "disconnected";
  Log(3, "Disconnect of $hash->{POKEYSNAME}. Try reconnect");
  InternalTimer(gettimeofday()+0.1, "POKEYS_ReDefine", $hash, 0);
}


1;
