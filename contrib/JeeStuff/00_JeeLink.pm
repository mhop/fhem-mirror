################################################################################
# FHEM-Modul see www.fhem.de
# 00_JeeLink.pm
# Modul to use a JeeLink with RF12DEMO as FHEM-IO-Device
#
# Usage: define <Name> JeeLink </dev/...> NodeID
################################################################################
# This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
################################################################################
# Autor: Axel Rieger
# Version: 1.0
# Datum: 07.2011
# Kontakt: fhem [bei] anax [punkt] info
################################################################################
package main;

use strict;
use warnings;
use Data::Dumper;
use vars qw(%defs);
use vars qw(%attr);
use vars qw(%data);
use vars qw(%modules);

sub JeeLink_Initialize($);
sub JEE_Define($$);
sub JEE_CloseDev($);
sub JEE_OpenDev($$);
sub JEE_Ready($);
sub JEE_Read($);
sub JEE_Set($);
################################################################################
sub JeeLink_Initialize($)
{
  my ($hash) = @_;
  # Provider
  $hash->{ReadFn}  = "JEE_Read";
  $hash->{ReadyFn} = "JEE_Ready";
  $hash->{SetFn} = "JEE_Set";
  $hash->{WriteFn} = "JEE_Write";
  $hash->{Clients} = ":JSN:JME:JPU";
  $hash->{WriteFn} = "JEE_Write";

  my %mc = (
            "1:JSN" => "^JSN",
            "2:JME" => "^JME",
            "3:JPU" => "^JPU");
  $hash->{MatchList} = \%mc;

  # Normal devices
  $hash->{DefFn}   = "JEE_Define";
  $hash->{AttrList} = "do_not_notify:1,0 dummy:1,0 loglevel:0,1 ";
  return undef;
}
################################################################################
sub JEE_Define($$) {
  # define JEE0001 JeeLink /dev/tty.usbserial-A600cKlS NodeID
  # defs = $a[0] <DEVICE-NAME> $a[1] DEVICE-TYPE $a[2]<Parameter-1->;
  my ($hash, $def) = @_;
  my @a = split(/\s+/, $def);



  my $name = $a[0];
  my $dev = $a[2];
  my $NodeID = $a[3];

  if($dev eq "none") {
    Log 1, "$name device is none, commands will be echoed only";
    $hash->{TYPE} = 'JeeLink';
    $hash->{STATE} = TimeNow() . " Dummy-Device";
    $attr{$name}{dummy} = 1;
    return undef;
  }

  JEE_CloseDev($hash);
  if($NodeID == 0 || $NodeID > 26 ) {return "JeeLink: NodeID between 1 and 26";}
  Log 0, "JEE-Define: Name = $name dev=$dev";

  $hash->{DeviceName} = $dev;
  $hash->{TYPE} = 'JeeLink';
  my $ret = JEE_OpenDev($hash, 0);
  my $msg = $NodeID . "i";
  $ret = &JEE_IOWrite($hash, $msg);
  return undef;
}
################################################################################
sub JEE_Set($){
  my ($hash, @a) = @_;
  # Log 0, ("JEE-SET: " . Dumper(@_));
  my $fields .= "NodeID NetGRP Frequenz LED CollectMode SendMSG BroadcastMSG RAW";
  return "Unknown argument $a[1], choose one of ". $fields if($a[1] eq "?");
  # a[0] = DeviceName
  # a[1] = Command
  # Command
  # nodeID: <n>i set node ID (standard node ids are 1..26  or 'A'..'Z')
  # netGRP: <n>g  set network group (RFM12 only allows 212)
  # freq -> <n>b set MHz band (4 = 433, 8 = 868, 9 = 915)
  # cMode -> <n>c - set collect mode (advanced 1, normally 0)
  # bCast -> t - broadcast max-size test packet, with ack
  # sendA -> ...,<nn> a - send data packet to node <nn>, with ack
  # sendS -> ...,<nn> s - send data packet to node <nn>, no ack
  # led -> <n> l   - turn activity LED on PB1 on or off
  # Remote control commands:
  # <hchi>,<hclo>,<addr>,<cmd> f     - FS20 command (868 MHz)
  # <addr>,<dev>,<on> k              - KAKU command (433 MHz)
  # Flash storage (JeeLink v2 only):
  # d                                - dump all log markers
  # <sh>,<sl>,<t3>,<t2>,<t1>,<t0> r  - replay from specified marker
  # 123,<bhi>,<blo> e                - erase 4K block
  # 12,34 w                          - wipe entire flash memory
  my($name, $msg);
  $name = $a[0];
  # LogLevel
  my $ll = 0;
  if(defined($attr{$name}{loglevel})) {$ll = $attr{$name}{loglevel};}
  Log $ll,"$name/JEE-SET: " . $a[1] . " : " . $a[2];
  # @a ge 2
  # if(int(@a) ne 3) {return "JeeLink wrong Argument Count";}
  $msg = "";
  if($a[1] eq "NodeID") {
      if($a[2] == 0 || $a[2] > 26 ) {return "JeeLink: NodeID between 1 and 26";}
      $msg = $a[2] . "i";}
  if($a[1] eq "NetGRP") {
    if($a[2] == 0 || $a[2] > 255 ) {return "JeeLink: NetGroup between 1 and 255";}
    $msg = $a[2] . "g";}
  if($a[1] eq "Frequenz") {
    if($a[2] !~ m/433|868|933/) {return "JeeLink: Frquenz setting use 433, 868 or 933";}
    my $mhz;
    if($a[2] eq "433") {$msg = "4b";}
    if($a[2] eq "868") {$msg = "8b";}
    if($a[2] eq "915") {$msg = "9b";}
    # 4 = 433, 8 = 868, 9 = 915
  }
  # LED
  if($a[1] eq "LED" && lc($a[2]) eq "on") {
    $hash->{LED} = "ON";
    $msg = "1l";}
  if($a[1] eq "LED" && lc($a[2]) eq "off") {
    $hash->{LED} = "OFF";
    $msg = "0l";}
  # CollectMode On or Off
  if($a[1] eq "CollectMode" && lc($a[2]) eq "on") {
    $hash->{CollectMode} = "ON";
    $msg = "1c";}
  if($a[2] eq "CollectMode" && lc($a[2]) eq "off") {
    $hash->{CollectMode} = "OFF";
    $msg = "0c";}
  # RF12_MSG to Remote Node with NO ack
  # set <NAME> SendMSG NodeID Data
  if($a[1] eq "SendMSG") {$msg = $a[2] . "," . $a[3] . "s"};
  # RF12- BroadcastMSG
  if($a[1] eq "BroadcastMSG") {$msg = "t";}
  # RAW
  if($a[1] eq "RAW") {$msg = $a[2];}
  # Send MSG
  Log 0,"JEE-SET->WRITE: $msg";
  my $ret = &JEE_IOWrite($hash, $msg);
  return undef;

}
################################################################################
sub JEE_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};

  return if(!$dev);
  $hash->{USBDev}->close() ;
  delete($hash->{USBDev});
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
}
################################################################################
sub JEE_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $po;

  $hash->{PARTIAL} = "";
  Log 3, "JeeLink opening $name device $dev"
        if(!$reopen);

    my $baudrate;
    ($dev, $baudrate) = split("@", $dev);
    $baudrate = 57600;

    if ($^O=~/Win/) {
     require Win32::SerialPort;
     $po = new Win32::SerialPort ($dev);
    } else  {
     require Device::SerialPort;
     $po = new Device::SerialPort ($dev);
    }

    if(!$po) {
      return undef if($reopen);
      Log(3, "Can't open $dev: $!");
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      return "";
    }
    $hash->{USBDev} = $po;
    if( $^O =~ /Win/ ) {
      $readyfnlist{"$name.$dev"} = $hash;
    } else {
      $hash->{FD} = $po->FILENO;
      delete($readyfnlist{"$name.$dev"});
      $selectlist{"$name.$dev"} = $hash;
    }

    if($baudrate) {
      $po->reset_error();
      Log 3, "$name: Setting baudrate to $baudrate";
      $po->baudrate($baudrate);
      $po->databits(8);
      $po->parity('none');
      $po->stopbits(1);
      $po->handshake('none');
    }

  if($reopen) {
    Log 1, "JeeLink $dev reappeared ($name)";
  } else {
    Log 3, "JeeLink device opened";
  }

  # Set Defaults
  # CollectMode on
  my $ret = &JEE_IOWrite($hash, "1c");
  # QuietMode on
  $ret = &JEE_IOWrite($hash, "1q");
  # LED On
  $ret = &JEE_IOWrite($hash, "1l");
  # Set Frequenz to 868MHz
  $ret = &JEE_IOWrite($hash, "8b");

  $hash->{STATE}="connected";       # Allow InitDev to set the state

  DoTrigger($name, "CONNECTED") if($reopen);
  return "Initialized";
}
################################################################################
sub JEE_Ready($)
{
  my ($hash) = @_;

  return JEE_OpenDev($hash, 1)
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  # Get Config
  my $ret = &JEE_Write($hash, "i", undef);
  return ($InBytes>0);
}
################################################################################
sub JEE_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  # LogLevel
  # Default 4
  my $ll = 4;
  if(defined($attr{$name}{loglevel})) {
    $ll = $attr{$name}{loglevel};
  }
  my $buf = $hash->{USBDev}->input();
  #
  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = $hash->{USBDev}->input();
  }
  my $jeedata = $hash->{PARTIAL};
  $jeedata .= $buf;
  ##############################################################################
  # Arduino/JeeLink
  # Prints data to the serial port as human-readable ASCII text followed by
  # a carriage return character (ASCII 13, or '\r') and
  # a newline character (ASCII 10, or '\n').
  # HEX 0D AD \xf0
   if($jeedata =~ m/\n$/){
   chomp($jeedata);
   chop($jeedata);
   my $status = substr($jeedata, 0, 2);
   Log $ll,("$name/JeeLink RAW:$status -> $jeedata");
   if($status =~/^OK/){
    Log $ll,("$name/JeeLink Dispatch RAW:$jeedata");
     &JEE_DispatchData($jeedata,$name,$ll);
   }
  elsif($jeedata =~ m/(^.*i)([0-9]{1,2})(\*.g)([0-9]{1,3})(.@.)([0-9]{1,3})(.MHz.*)/) {
    JEE_RF12MSG($jeedata,$name,$ll);
    }
  elsif($jeedata  =~/^DF/){JEE_RF12MSG($jeedata,$name,$ll);}
  $jeedata = "";
  }
  if($jeedata =~ m/^\x0A/) {
    Log $ll,("$name/JeeLink RAW DEL HEX-0A:$jeedata -> $jeedata");
    $jeedata =~ s/\x0A//;
    }
  $hash->{PARTIAL} = $jeedata;
}
################################################################################
sub JEE_DispatchData($){
  my ($rawdata,$name,$ll) = @_;
  my @data = split(/\s+/,$rawdata);
  my $status = shift(@data);
  my $NodeID = shift(@data);
  # see http://talk.jeelabs.net/topic/642#post-3622
  # The id +32 is what you see when the node requests an ACK. 
  if($NodeID > 31) {$NodeID = $NodeID - 32;}
  Log $ll, "$name JEE-DISP: Status:$status NodeID:$NodeID Data:$rawdata";
  # normalize 0 => 00 without NodeID
  for(my $i=0;$i<=$#data;$i++){
    if(length($data[$i]) == 1) { $data[$i] = "0" . $data[$i]}
  }
  # SensorData to Dispatch
  my ($DispData,$SType,$SPre,@SData,$data_bytes,$slice_end);
  for(my $i=0;$i<=$#data;$i++){
    # Get Number of DataBytes
    $SType = $data[$i];
    if(defined($data{JEECONF}{$SType}{DataBytes})){
      $data_bytes = $data{JEECONF}{$SType}{DataBytes};
      ###
      $SPre = $data{JEECONF}{$SType}{Prefix};
      $i++;
      $slice_end = $i + $data_bytes - 1;
      @SData = @data[$i..$slice_end];
      $DispData = $SPre . " " . $NodeID . " " . $SType . " " . join(" ",@SData);
    }
    else {
      Log $ll, "$name JEE-DISP: -ERROR- SensorType $SType not defined";
      return undef;
    }
    # Dispacth-Data to FHEM-Dispatcher -----------------------------------------
    #foreach my $m (sort keys %{$modules{JeeLink}{MatchList}}) {
    #  my $match = $modules{JeeLink}{MatchList}{$m};
      $defs{$name}{"${name}_MSGCNT"}++;
      $defs{$name}{"${name}_TIME"} = TimeNow();
      $defs{$name}{RAWMSG} = $DispData;
      my %addvals = (RAWMSG => $DispData);
      my $hash = $defs{$name};
      Log $ll,"$name JEE-DISP: SType=$SType -> DispData=$DispData";
      my $ret_disp = &Dispatch($hash, $DispData, \%addvals);
    #}
    # Dispacth-Data to FHEM-Dispatcher -----------------------------------------
    # Minimum 2Bytes left
    # if((int(@data) - $i) < 2 ) {
    #  Log $ll,"$name JEE-DISP: 2Byte $i -> " . int(@data);
    #  $i = int(@data);
    # }
    #else {$i = $slice_end;}
    $i = $slice_end;
  }
}
################################################################################
sub JEE_RF12MSG($$$){
  my ($rawdata,$name,$ll) = @_;
  # ^ i23* g212 @ 868 MHz
  # i -> NodeID
  # g -> NetGroup
  # @ -> 868MHz or 492MHz
  Log $ll,("$name/JeeLink RF12MSG: $rawdata");
  my($NodeID,$NetGroup,$Freq);
  if ( $rawdata =~ m/(^.*i)([0-9]{1,2})(\*.g)([0-9]{1,3})(.@.)([0-9]{1,3})(.MHz.*)/) {
    ($NodeID,$NetGroup,$Freq) = ($2,$4,$6);
    Log $ll,("$name/JeeLink RF12MSG-CONFIG: NodeId:$NodeID NetGroup:$NetGroup Freq:$Freq");
    $defs{$name}{RF12_NodeID} = $NodeID;
    $defs{$name}{RF12_NetGroup} = $NetGroup;
    $defs{$name}{RF12_Frequenz} = $Freq;

  }
  if($rawdata =~ m/\s+DF/){
    Log $ll,("$name/JeeLink RF12MSG-FLASH: $rawdata");
  }
  return undef;
}
################################################################################
sub JEE_IOWrite() {
  my ($hash, $msg,) = @_;
  return if(!$hash);
  # LogLevel
  my $name = $hash->{NAME};
  my $ll = 4;
  if(defined($attr{$name}{loglevel})) {
    $ll = $attr{$name}{loglevel};
  }
  if(defined($attr{$name}{dummy})){
    Log $ll ,"JEE-IOWRITE[DUMMY-MODE]: " . $hash->{NAME} . " $msg";
    }
  else {
    Log $ll ,"JEE-IOWRITE: " . $name . " $msg";
    $hash->{USBDev}->write($msg . "\n");
    select(undef, undef, undef, 0.001);
  }
}
################################################################################
sub JEE_Write() {
  my ($hash, $msg1, $msg2) = @_;
  # $hash -> Received form Device
  # $msg1 -> Message Type ???
  # $msg2 -> Data
  return if(!$hash);
  # LogLevel
  my $name = $hash->{NAME};
  my $ll = 4;
  if(defined($attr{$name}{loglevel})) {
    $ll = $attr{$name}{loglevel};
  }
  Log $ll ,"JEE-WRITE: " . $hash->{NAME} . " MSG-1-: $msg1 MSG-2-: $msg2";
  # Default --------------------------------------------------------------------
  my $msg = $msg2;
  # FS20 -----------------------------------------------------------------------
  # JEE-WRITE: JL01 MSG: 04 BTN: 010101 1234 33 00
  # FS20.pm
  # IOWrite($hash, "04", "010101" . $hash->{XMIT} . $hash->{BTN} . $c);
  # MSG-1-: 04 MSG-2-: 01010177770311
  # <hchi>,<hclo>,<addr>,<cmd> f     - FS20 command (868 MHz)
  # substr($jeedata, 0, 2);
  my ($hchi,$hclo,$addr,$cmd);
  if($msg2 =~ m/^010101/) {
    $msg2 =~s/010101//;
    Log 0, "JEE-IOWRITE-FS20: $msg2";

    $hchi = hex(substr($msg2,0,2));
    $hclo = substr($msg2,2,2);
    $addr = hex(substr($msg2,4,2));
    $cmd = hex(substr($msg2,6,2));

    $msg = "$hchi,$hclo,$addr,$cmd f";
    Log $ll, "JEE-IOWRITE-FS20: hchi:$hchi hclo:$hclo addr:$addr cmd:$cmd";

    $hash->{FS20_LastSend} = TimeNow() . ":" . $msg ;
  }
  # FS20 -----------------------------------------------------------------------

  if(defined($attr{$name}{dummy})){
    Log $ll, "JEE_Write[DUMMY-MODE]: >$msg<";
  }
  else {
  # Send Message >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    $hash->{USBDev}->write($msg . "\n");
    Log $ll, "JEE_Write >$msg<";
    select(undef, undef, undef, 0.001);
  # Send Message >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  }
}
################################################################################
1;
