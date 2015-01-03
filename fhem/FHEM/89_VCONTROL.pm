#################################################################################
# 
# $Id$ 
#
# FHEM Module for Viessman Vitotronic200  / Typ  KW1 und KW2
#
# Derived from 89_VCONTROL.pm: Copyright (C) Adam WItalla
#
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
#package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Time::Local;

# Helper Constants
use constant NO_SEND => 9999;
use constant POLL_ACTIVE => 1;
use constant POLL_PAUSED => 0;
use constant READ_ANSWER => 1;
use constant READ_UNDEF => 0;
use constant GET_TIMER_ACTIVE => 1;
use constant GET_TIMER_PAUSED => 0;
use constant GET_CONFIG_ACTIVE => 1;
use constant GET_CONFIG_PAUSED => 0;

#Poll Parameter
my $defaultPollInterval = 180;
my $last_cmd = 0;
my $poll_now = POLL_PAUSED;
my $get_timer_now = GET_TIMER_PAUSED;
my $get_config_now = GET_CONFIG_PAUSED;
my $command_config_file = "";
my $poll_duration = 0;
#Send Parameter
my $send_now = NO_SEND;
my $send_additonal_param="";

#Get Parameter
#Answer Parameter
my $read_now = READ_UNDEF;

#actually used command list
my @cmd_list;
my @poll_cmd_list;
my @write_cmd_list;
my @timer_cmd_list;
my @set_cmd_list;
my @get_timer_cmd_list;
#remember days for daystart values
my %DayHash;

#States the Heater can be set to
my @mode = ("WW","RED","NORM","H+WW","H+WW FS","ABSCHALT");
my $temp_mode=0;

######################################################################################
sub VCONTROL_1ByteUParse($$);
sub VCONTROL_1ByteSParse($$);
sub VCONTROL_2ByteSParse($$);
sub VCONTROL_2ByteUParse($$);
sub VCONTROL_2BytePercentParse($$);
sub VCONTROL_4ByteParse($$);
sub VCONTROL_timerParse($);
sub VCONTROL_ModusParse($);
sub VCONTROL_DateParse($);
sub VCONTROL_1ByteUConv($);
sub VCONTROL_1ByteSConv($);
sub VCONTROL_1ByteUx10Conv($);
sub VCONTROL_2ByteUConv($);
sub VCONTROL_2ByteSConv($);
sub VCONTROL_DateConv($);
sub VCONTROL_TimerConv($$);
sub VCONTROL_Clear($);
sub VCONTROL_Read($);
sub VCONTROL_Ready($);
sub VCONTROL_Parse($$$$);
sub VCONTROL_Poll($);
sub VCONTROL_CmdConfig($);

sub
VCONTROL_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{ReadFn}  = "VCONTROL_Read";
  #$hash->{WriteFn} = "VCONTROL_Write";
  $hash->{ReadyFn} = "VCONTROL_Ready";
  $hash->{DefFn}   = "VCONTROL_Define";
  $hash->{UndefFn} = "VCONTROL_Undef";
  $hash->{SetFn}   = "VCONTROL_Set";
  $hash->{GetFn}   = "VCONTROL_Get";
  $hash->{StateFn} = "VCONTROL_SetState";
  $hash->{ShutdownFn} = "VCONTROL_Shutdown";
  $hash->{AttrList}  = "disable:0,1 setList closedev:0,1 ". $readingFnAttributes;
}

#####################################
# define <name> VIESSMANN <port> <commad_config> [<interval>] 

sub
VCONTROL_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $po;
  
  if (@a != 4 && @a != 5) {
  	my $msg = "wrong syntax: define <name> VCONTROL <port> <command_config> [<interval>]";
  	Log3 undef, 2, $msg;
  	return $msg;
  }

  #Close Device to initialize properly
    ###USB
  if (index($a[2], ':') == -1) {
     delete $hash->{USBDev};
     delete $hash->{FD};
  }
  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];

  #check existence of config_file
  if($a[3]){
     $command_config_file = $a[3];
          
     if(-e $command_config_file){
        Log3 $name, 3, "VCONTROL: Define open DATEI '$command_config_file'";
        VCONTROL_CmdConfig($command_config_file);
     }
     else {
        my $msg = "config file $command_config_file does not exist";
  	    Log3 undef, 2, $msg;
  	    return $msg;
    }
  }
  
  #set command list to poll list
  @cmd_list = @poll_cmd_list;
  
  #use configured Pollinterval if given
  if($a[4]){
     $hash->{INTERVAL} = $a[4];
  }
  else {
     $hash->{INTERVAL} = $defaultPollInterval;
  }

  $hash->{STATE} = "defined";
  $hash->{DeviceName} = $dev;
  $hash->{PARTIAL} = "";
  
  #Opening USB Device
  Log3($name, 3, "VCONTROL opening VCONTROL device $dev");
  
      ###USB
  if (index($a[2], ':') == -1) {

     if ($^O=~/Win/) {
        require Win32::SerialPort;
        $po = new Win32::SerialPort ($dev);
     } else  {
        require Device::SerialPort;
        $po = new Device::SerialPort ($dev);
     }
     if(!$po) {
         my $msg = "Can't open $dev: $!";
         Log3($name, 3, $msg) if($hash->{MOBILE});
         return $msg if(!$hash->{MOBILE});
         $readyfnlist{"$name.$dev"} = $hash;
         return "";
     }
     Log3($name, 3, "VCONTROL opened VCONTROL device $dev");

     $hash->{USBDev} = $po;
     if( $^O =~ /Win/ ) {
        $readyfnlist{"$name.$dev"} = $hash;
     } else {
        $hash->{FD} = $po->FILENO;
        delete($readyfnlist{"$name.$dev"});
        $selectlist{"$name.$dev"} = $hash;
     }
     
     #Initialize to be able to receive data
     VCONTROL_DoInit($hash, $po);
     
  }
  else {
     DevIo_OpenDev($hash, 0, undef);
     VCONTROL_DoInit($hash, undef);
  }

  
  #set Internal Timer on Polling Interval
   my $timer = gettimeofday()+1;
   Log3($name, 5, "VCONTROL set InternalTimer +1 to $timer");

  InternalTimer(gettimeofday()+1, "VCONTROL_Poll", $hash, 0);
  return undef;
  
}

#####################################
# Input is hexstring
## This function will not be used until now!
#sub
#VCONTROL_Write($$)
#{
#  my ($hash,$fn,$msg) = @_;
#  my $name = $hash->{NAME};
#
#  return if(!defined($fn));
#
#  my $bstring;
#  $bstring = "$fn$msg";
#  Log3 $name, 5, "$hash->{NAME} sending $bstring";
#
#  DevIo_SimpleWrite($hash, $bstring, 1);
#}


#####################################
sub
VCONTROL_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log3 $name, $lev, "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
VCONTROL_Poll($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  #global Module Trigger that Polling is started
  $poll_now=POLL_ACTIVE;
  $poll_duration = gettimeofday();
  Log3 $name, 4, "VCONTROL: Start of Poll !";
  my $timer = gettimeofday()+$hash->{INTERVAL};
  Log3($name, 5, "VCONTROL: set InternalTimer to $timer");
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "VCONTROL_Poll", $hash, 0);
}

#####################################
sub
VCONTROL_Shutdown($)
{
  my ($hash) = @_;
  return undef;
}

#####################################
sub
VCONTROL_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

sub
VCONTROL_Clear($)
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
VCONTROL_DoInit($$)
{
  #Initialisation -> Send one 0x04 so the heating started to send 0x05 Synchonity-Bytes
  my ($hash,$po) = @_;
  my $name = $hash->{NAME};
  my $init = pack('H*', "04");

  if ($po)
  {
     #set USB Device Parameter 
     $po->reset_error();
     $po->baudrate(4800);
     $po->databits(8);
     $po->parity('even');
     $po->stopbits(2);
     $po->handshake('none');
     $po->write_settings;
  }
  $defs{$name}{STATE} = "Initialized";

  DevIo_SimpleWrite($hash, $init, 0);
  
  Log3 $name, 3,"VCONTROL: Initialization";
  
  return undef;
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
VCONTROL_Read($)
{

  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5,"VCONTROL_READ";
  # count the commands to send for complete poll sequence
  my $cmdcount = @cmd_list;

  #Read on Device
  my $mybuf = DevIo_SimpleRead($hash);

  #USB device is disconnected try to connect again
  if(!defined($mybuf) || length($mybuf) == 0) {
    my $dev = $hash->{DeviceName};
    Log3 $name, 3,"VCONTROL: USB device $dev disconnected, waiting to reappear";
    $hash->{USBDev}->close();
    DoTrigger($name, "DISCONNECTED");

    delete($hash->{USBDev});
    delete($selectlist{"$name.$dev"});
    $readyfnlist{"$name.$dev"} = $hash; # Start polling
    $hash->{STATE} = "disconnected";

    # Without the following sleep the open of the device causes a SIGSEGV,
    # and following opens block infinitely. Only a reboot helps.
    sleep(5);
    return "";
  }

  #msg read on device
  my $hexline = unpack('H*', $mybuf);
  Log3 $name, 5,"VCONTROL: VCONTROL_Read '$hexline'";
     
  #Append data to partial data we got before

  #ADW: 05 muss auch angehängt werden!
  if ( $read_now == READ_ANSWER && $poll_now == POLL_ACTIVE ){
#   if ( $read_now == READ_ANSWER && $poll_now == POLL_ACTIVE && $hexline ne "05"){
     $hexline = $hash->{PARTIAL}.$hexline;
     #if not received all bytes exit an read next
     my $receive_len = hex(substr($cmd_list[$last_cmd][1],8,2))*2;
     if ( length($hexline) < $receive_len ){
        Log3 $name, 5,"VCONTROL: VCONTROL_Read receive_len < $receive_len, $hexline";
        $hash->{PARTIAL} = $hexline;
        return"";
    }
  }

  #exit if no poll period 
  #exit if no set command send
  if ($poll_now == POLL_PAUSED && $send_now == NO_SEND ){
     return ""; }
  
  my $sendbuf="";
  #End of Poll Interval
  if ($poll_now == POLL_ACTIVE && $last_cmd == $cmdcount)
  {
     $poll_duration = (gettimeofday() - $poll_duration);
     my $duration = sprintf("%.2f", $poll_duration);
     $hash->{DURATION} = "$duration";
     Log3 $name, 4, "VCONTROL: End of Poll ! Duration: $duration";
     $poll_now = POLL_PAUSED;
     $last_cmd = 0;
     @cmd_list = @poll_cmd_list;
     $hash->{PARTIAL} = "";

     #activate timer get list if questioned
     if ($get_timer_now == GET_TIMER_ACTIVE && $send_now == NO_SEND ){
        @cmd_list = @get_timer_cmd_list;
        Log3 $name, 5, "VCONTROL: Poll TIMER!";
        RemoveInternalTimer($hash);
        VCONTROL_Poll($hash);
        $get_timer_now = GET_TIMER_PAUSED;
     } 
     
     #reload config file if questioned
     if ($get_config_now == GET_CONFIG_ACTIVE ){
        VCONTROL_CmdConfig($command_config_file);
        @cmd_list = @poll_cmd_list;
        $get_config_now = GET_CONFIG_PAUSED;
     }
     
  my $closeAfterPoll = AttrVal($name, "closedev", "0");   
  ###if Attribut to close after poll -> close
  if ($closeAfterPoll == 1) {
     delete $hash->{USBDev};
     delete $hash->{FD};
     Log3 $name, 3, "VCONTROL: USB device closed";
  }
        
     return "";
  };

   #exit if buffer just filled with 0x05 but not for mode (0x05 is a definde mode state)
  my $bufflen = length($hexline);
  my $buffhalflen = $bufflen/2;
  
  if ( $bufflen > 2 && $hexline =~ /(05){$buffhalflen,}/ && $cmd_list[$last_cmd][2] ne "mode"){
     Log3 $name, 5, "VCONTROL: exit if buffer just filled with 0x05";
     $hash->{PARTIAL} = "";
     $read_now = READ_UNDEF;
     return ""; }
  
  #if one 05 received we can send command
  if ( length($hexline) == 2 && $hexline eq "05" && $read_now == READ_UNDEF)
  {
     my $sendstr ="";
     #set next poll command
     if ($poll_now == POLL_ACTIVE ){
        Log3 $name, 5, "VCONTROL: Setze sendstr";
        $sendstr = $cmd_list[$last_cmd][1];
     }
     
     # no polling active but set command was given
     if ($poll_now == POLL_PAUSED && $send_now != NO_SEND ){
        $sendstr = $write_cmd_list[$send_now][2]."$send_additonal_param";
     }
     
     if ( $sendstr && $sendstr ne "" ){    
        Log3 $name, 5, "VCONTROL: send '$sendstr'";
        $sendbuf = pack('H*', "$sendstr");

        #Send on Device
        DevIo_SimpleWrite($hash, $sendbuf, 0);
     
        #we have send cmd next receive should be answer
        $read_now = READ_ANSWER;
    }
    else { #wenn wir hier reinrutschen ist etwas mit den listen durcheinander geraten, workaround reset der liste und der commands!
       Log3 $name, 5, "VCONTROL: List reset!";
       $poll_now = POLL_PAUSED;
       $last_cmd = 0;
       @cmd_list = @poll_cmd_list;
       $hash->{PARTIAL} = "";
       $get_timer_now = GET_TIMER_PAUSED;
       $get_config_now = GET_CONFIG_PAUSED;
    }
  }
  elsif ( $read_now == READ_ANSWER) #we expect answer on before send command
  {
      if ($poll_now == POLL_ACTIVE && $hexline ne "05"){
            VCONTROL_Parse($hash,$last_cmd,$hexline,0);
         $last_cmd++;
         $temp_mode = 0;
      }
      #if the mode is requestet and 0x05 is received 
      #try again to be sure that 0x05 is not the sync byte
      elsif ($poll_now == POLL_ACTIVE && $cmd_list[$last_cmd][2] eq "mode" && substr("$hexline",0,2) eq "05" ){
          Log3 $name, 5, "VCONTROL: check temp_mode";
          if ($temp_mode < 5){
             $temp_mode++;
              Log3 $name, 5, "VCONTROL: set temp_mode = $temp_mode";
          }
          elsif ($temp_mode == 5){
             $temp_mode = 0;
             VCONTROL_Parse($hash,$last_cmd,$hexline,0);
             Log3 $name, 5, "VCONTROL: set mode = ABSCHALT";
             $last_cmd++;
          }
      }

      #parse answer on set command
      if ($poll_now == POLL_PAUSED && $send_now != NO_SEND ){
         VCONTROL_Parse($hash,$send_now,$hexline,1) if ($hexline ne "05");
      }
      $read_now = READ_UNDEF;
      $hash->{PARTIAL} = "";
  }
}

#####################################
sub
VCONTROL_Parse($$$$)
{             
  my ($hash, $cmd, $hexline,$answer) = @_;

  my $value = "";
  my $valuename = "";
  my $pn = $hash->{NAME};

  if ($answer == 0){
     if      ($cmd_list[$cmd][2] eq "1ByteU"){
        $value = VCONTROL_1ByteUParse(substr($hexline, 0, 2),$cmd_list[$cmd][3]) if (length($hexline) > 1);
     } elsif ($cmd_list[$cmd][2] eq "1ByteS"){
        $value = VCONTROL_1ByteSParse(substr($hexline, 0, 2),$cmd_list[$cmd][3]) if (length($hexline) > 1);
     } elsif ($cmd_list[$cmd][2] eq "2ByteS"){
        $value = VCONTROL_2ByteSParse($hexline,$cmd_list[$cmd][3]) if (length($hexline) > 3);
     } elsif ($cmd_list[$cmd][2] eq "2ByteU"){
        $value = VCONTROL_2ByteUParse($hexline,$cmd_list[$cmd][3]) if (length($hexline) > 3);   
     } elsif ($cmd_list[$cmd][2] eq "2BytePercent"){
        $value = VCONTROL_2BytePercentParse($hexline,$cmd_list[$cmd][3]) if (length($hexline) > 1);
     } elsif ($cmd_list[$cmd][2] eq "4Byte"){
        $value = VCONTROL_4ByteParse($hexline,$cmd_list[$cmd][3]) if (length($hexline) > 7);
     } elsif ($cmd_list[$cmd][2] eq "mode"){
        $value = VCONTROL_ModeParse($hexline) if (length($hexline) > 1);
     } elsif ($cmd_list[$cmd][2] eq "timer"){
        $value = VCONTROL_timerParse($hexline) if (length($hexline) > 7);
     } elsif ($cmd_list[$cmd][2] eq "date"){
        $value = VCONTROL_DateParse($hexline) if (length($hexline) > 7);
     }
     
     #this will be the name of the Reading
     $valuename = "$cmd_list[$cmd][4]";
     Log3 $pn, 5,"VCONTROL: receive '$valuename : $value'";
 
     return $pn if ($value eq "");
 
     if (  $cmd_list[$cmd][2] 
        && $cmd_list[$cmd][2] ne "mode" 
        && $cmd_list[$cmd][2] ne "timer" 
        && $cmd_list[$cmd][3] ne "state" 
        && $cmd_list[$cmd][3] >  99){
          $value = sprintf("%.2f", $value);
		  }
     
     #TODO config Min and Max Values ????
     if ( substr($valuename,0,4) eq "Temp"){
        if ( $value < -30 || $value > 199 ){
           $value = ReadingsVal($pn,"$valuename",0);
        }
     }
 
     #get systemtime
     my ($sec,$min,$hour,$mday,$mon,$year) = localtime;
     $year+=1900;
     $mon = $mon+1;
     my $plotmonth = $mon;
     my $plotmday = $mday;
     my $plothour = $hour;
     my $plotmin = $min;
     my $plotsec = $sec;
     if ($mon < 10) {$plotmonth = "0$mon"};
     if ($mday < 10) {$plotmday = "0$mday"};
     if ($hour < 10) {$plothour = "0$hour"};
     if ($min < 10) {$plotmin = "0$min"};
     if ($sec < 10) {$plotsec = "0$sec"};
  my $systime="$year-$plotmonth-$plotmday"."_"."$plothour:$plotmin:$plotsec";
    
  #Start Update Readings 
  readingsBeginUpdate  ($hash);
  readingsBulkUpdate   ($hash, "$valuename", $value);

  #calculate Kumulation Readings and Day Readings
  
  if ("$cmd_list[$cmd][5]" eq "day"  ){
     my $start_of_the_day;
     if ( $value < 0 ){
        $value = ReadingsVal($pn,"$valuename",0);
     }
  
     $value = sprintf("%.2f", $value);
     $start_of_the_day = ReadingsVal($pn,"$valuename"."DayStart",$value);
     my $kumul_day =  $value - $start_of_the_day;
     $kumul_day = sprintf("%.2f", $kumul_day);
     readingsBulkUpdate   ($hash, "$valuename"."Today", $kumul_day);
 
     #Next Day for this value is reached
     my $debug_day= $DayHash{$valuename};
     Log3 $pn, 5, "VCONTROL: DEBUG nextday $mday <-> $debug_day";
     if ($mday != $DayHash{$valuename}){
        $start_of_the_day = $value;
        $start_of_the_day = sprintf("%.2f", $start_of_the_day);
        readingsBulkUpdate   ($hash, "$valuename"."LastDay" , $kumul_day);
        $kumul_day = 0;
        $DayHash{$valuename} = $mday;
     }
     readingsBulkUpdate   ($hash, "$valuename"."DayStart" , $start_of_the_day);
  }   

  #if all polling commands are send, update Reading UpdateTime
  my $all_cmd = @cmd_list -1;
  if ( $cmd == $all_cmd){
     readingsBulkUpdate   ($hash, "UpdateTime", $systime );
  }
  #End Update Reading
  readingsEndUpdate    ($hash, 1);

  }
  else #answer on set request
  {
    #Start Poll to refresh readings if send of set request was answered with 00
    # and no additional send has to be done
    if (substr($hexline, 0, 2) == "00")
    {   
       # it may be configured that another command has to be send
       my $next_send = NO_SEND;
       foreach(@write_cmd_list) {
          if ($$_[0] eq "SET" && $$_[1] eq $write_cmd_list[$send_now][4]){
             $next_send=$$_[5];
          }
       }   
      
       if ($next_send == NO_SEND){
          #activate timer get list if questioned
          if ($get_timer_now == GET_TIMER_ACTIVE ){
             @cmd_list = @get_timer_cmd_list;
             $get_timer_now = GET_TIMER_PAUSED;
          }
          
          if (substr($hexline, 0, 2) == "00"){
             Log3 $pn, 5, "VCONTROL: Poll SET!";
             RemoveInternalTimer($hash);
             VCONTROL_Poll($hash);
          }
       }
       $send_now = $next_send;
     }
  }

  return $pn;

}


#####################################
sub
VCONTROL_Ready($)
{
  my ($hash) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};

  my $po;

  ###USB
  if (index($dev, ':') == -1) {
     $po=$hash->{USBDev};
     if(!$po) {    # Looking for the device
        if ($^O=~/Win/) {
           $po = new Win32::SerialPort ($dev);
        } else  {
           $po = new Device::SerialPort ($dev);
        }
        return undef if(!$po);

        Log3 $name, 3, "VCONTROL: USB device $dev reappeared";
        $hash->{USBDev} = $po;
        if( $^O !~ /Win/ ) {
           $hash->{FD} = $po->FILENO;
           delete($readyfnlist{"$name.$dev"});
           $selectlist{"$name.$dev"} = $hash;
        } else {
           $readyfnlist{"$name.$dev"} = $hash;
        }
        $hash->{PARTIAL} = "";
        VCONTROL_DoInit($hash, $po);
        DoTrigger($name, "CONNECTED");
        return undef;
     }
  } else {
      $hash->{PARTIAL} = "";
      DevIo_OpenDev($hash, 1, undef);
      return undef if(!exists($hash->{FD}));
      return undef if(!defined($_[0]->{TCPDev})); 
      VCONTROL_DoInit($hash, undef);
      DoTrigger($name, "CONNECTED");
      return undef;
  }
   

  # This is relevant for windows only
  if (index($dev, ':') == -1) {
     return undef if !$po;
     my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=$po->status;
     return ($InBytes>0);
  }
}

sub
VCONTROL_Set($@)
{
  my ($hash, @a) = @_;
  my $pn = $hash->{NAME};
  my $arg = $a[1];
  my $value = (defined $a[2]) ? $a[2] : "";

  my $setList = AttrVal($pn, "setList", " ");
  
  #return "Unknown argument ?, choose one of HWW ABSCHALT SPAR-ON SPAR-OFF PARTY-ON PARTY-OFF" if( $arg eq "?");
  return "Unknown argument ?, choose one of $setList" if( $arg eq "?");
  
  #needed if cmd in config_file is just a prefix, e.g. set of an timer value
  $send_additonal_param="";
  
  #set write commands to send
  foreach(@write_cmd_list) {
     my $debug_info0=$$_[0];
     my $debug_info1=$$_[1];
     Log3 $pn, 5, "VCONTROL: DEBUG SET <-> $debug_info0 / $arg <-> $debug_info1";
     if ($$_[0] eq "SET" && $$_[1] eq $arg){
        $send_now=$$_[5];
        
        if ($$_[3] eq "1ByteU"){
           $send_additonal_param=VCONTROL_1ByteUConv($value);
        }
        elsif ($$_[3] eq "1ByteS"){
           $send_additonal_param=VCONTROL_1ByteSConv($value);
        }
        elsif ($$_[3] eq "1ByteUx10"){
           $send_additonal_param=VCONTROL_1ByteUx10Conv($value);
        }
        elsif ($$_[3] eq "2ByteU"){
           $send_additonal_param=VCONTROL_2ByteUConv($value);
        }
        elsif ($$_[3] eq "2ByteS"){
           $send_additonal_param=VCONTROL_2ByteSConv($value);
        }
        elsif ($$_[3] eq "date"){
          my $strtemp = VCONTROL_DateConv($value);
          Log3 $pn, 5, "VCONTROL: DEBUG Timestr: $strtemp";
          $send_additonal_param=$strtemp;
        }
        elsif ($$_[3] eq "timer"){
          my $tempday = $$_[4];
          $send_additonal_param=VCONTROL_TimerConv($tempday,$value);
          @get_timer_cmd_list = @timer_cmd_list;
          $get_timer_now = GET_TIMER_ACTIVE;
        }
    
        return "";
     }
  }
 
  # possible to correct DayStart Values
  if(index($arg,"DayStart") >= 0){
     if ( $value ne "" )
     {
        readingsBeginUpdate  ($hash);
        readingsBulkUpdate   ($hash, $arg, $value);
        readingsEndUpdate    ($hash, 1);
     }
 	
  }	

  #else {
  # print "not data_ready: $arg \n";
  #}
  return "";      
}

sub VCONTROL_Get($@) {
  my ($hash, @a) = @_;
  return "no get value specified" if(@a < 2);
  
  my $pn = $hash->{NAME};
  my $arg = $a[1];
  my $value = (defined $a[2]) ? $a[2] : "";
  
  return "Unknown argument ?, choose one of TIMER CONFIG" if( $arg eq "?");

  if ($arg eq "TIMER" )
  { 
    @get_timer_cmd_list = @timer_cmd_list;
  }
  elsif ($arg eq "CONFIG" )
  {
     if ($poll_now == POLL_PAUSED ){
        VCONTROL_CmdConfig($command_config_file);
        @cmd_list = @poll_cmd_list;
     }
     else { $get_config_now = GET_CONFIG_ACTIVE; }
     return "";   
  }

  if ($poll_now == POLL_PAUSED ){
     @cmd_list = @get_timer_cmd_list;
     Log3 $pn, 5, "VCONTROL: Poll GET!";
     RemoveInternalTimer($hash);
     VCONTROL_Poll($hash);
  }
  else { $get_timer_now = GET_TIMER_ACTIVE; }
  
  
  return "";
}

#####################################
#####################################
## Load Config
#####################################
#####################################
sub VCONTROL_CmdConfig($)
{
  
  my $cmd_config_file = shift;                      
  
  my ($sec,$min,$hour,$mday,$mon,$year) = localtime;
  my $write_idx=0;
  Log3 undef, 3, "VCONTROL: open DATEI '$cmd_config_file'";
  open(CMDDATEI,"<$cmd_config_file") || die "problem opening $cmd_config_file\n" ;

  undef @poll_cmd_list;
  undef @write_cmd_list;
  undef @timer_cmd_list;
#  undef @timer_ww_cmd_list;
  
  while(<CMDDATEI>){
        my $zeile=trim($_);
        Log3 undef, 5, "VCONTROL: CmdConfig-Zeile $zeile";
        if ( length($zeile) > 0 && substr($zeile,0,1) ne "#")
        {
           my @cfgarray = split(",",$zeile);

           foreach(@cfgarray) {
              $_ = trim($_);
           } 

           #TODO: CHECK IF CONFIG PARAMS are allowed!!!  
           if ($cfgarray[0] eq "POLL"){
              if (  $cfgarray[2] ne "1ByteU" 
                 && $cfgarray[2] ne "1ByteS" 
                 && $cfgarray[2] ne "2ByteS" 
                 && $cfgarray[2] ne "2ByteU" 
                 && $cfgarray[2] ne "2BytePercent" 
                 && $cfgarray[2] ne "4Byte" 
                 && $cfgarray[2] ne "mode" 
                 && $cfgarray[2] ne "date"
                 && $cfgarray[2] ne "timer"
                 ){
                 Log3 undef, 3, "VCONTROL: unknown parse method '$cfgarray[2]' in '$cmd_config_file'";
              }
              elsif( index($cfgarray[1],"01F7") == -1 || length($cfgarray[1]) < 10 ){
                 Log3 undef, 3, "VCONTROL: wrong Address '$cfgarray[1]' in '$cmd_config_file'";
              }
              else {
                 if ($cfgarray[2] eq "timer")
                 {
                    my @timercmd = ($cfgarray[0],$cfgarray[1],$cfgarray[2],$cfgarray[3],$cfgarray[4],$cfgarray[5]);
                    push(@timer_cmd_list,\@timercmd);
                 }
                 else {
                    my @pollcmd = ($cfgarray[0],$cfgarray[1],$cfgarray[2],$cfgarray[3],$cfgarray[4],$cfgarray[5]);
                    push(@poll_cmd_list,\@pollcmd);
                    if ("$cfgarray[5]" eq "day"){
                       $DayHash{$cfgarray[4]} = $mday;
                    }
                 }
              }
           }
           elsif ($cfgarray[0] eq "SET"){
              if ($cfgarray[3] eq "timer")
                 {
                    if (  $cfgarray[4] ne "MO"
                       && $cfgarray[4] ne "DI"
                       && $cfgarray[4] ne "MI"
                       && $cfgarray[4] ne "DO"
                       && $cfgarray[4] ne "FR"
                       && $cfgarray[4] ne "SA"
                       && $cfgarray[4] ne "SO"
                       )
                    {   Log3 undef, 1, "VCONTROL: wrong Day '$cfgarray[4]' in '$cmd_config_file'";
                    }
                    else {
                       my @setcmd = ($cfgarray[0],$cfgarray[1],$cfgarray[2],$cfgarray[3],$cfgarray[4],$write_idx);
                       push(@write_cmd_list,\@setcmd);
                       $write_idx++;
                    }
              }
              else {
                 my @setcmd = ($cfgarray[0],$cfgarray[1],$cfgarray[2],$cfgarray[3],$cfgarray[4],$write_idx);
                 push(@write_cmd_list,\@setcmd);
                 $write_idx++;
              } 
           }
           else{
              Log3 undef, 3, "VCONTROL: unknown command '$cfgarray[0]' in '$cmd_config_file'";
           }
        }
  };

close (CMDDATEI);
Log3 undef, 3, "VCONTROL: DATEI '$cmd_config_file' refreshed";
}

###########################################################################
###########################################################################
### PARSE ROUTINES
###########################################################################
###########################################################################
sub VCONTROL_1ByteUParse($$)
{
  my $hexvalue = shift;
  my $divisor = shift;
  my $retstr="";
  
  if (!$divisor || length($divisor) == 0 || $divisor eq "state"){
     $retstr = ($hexvalue eq "00") ? "off" : "on";
  }
  else{
     #check if divisor is numeric and not 0
     if ( $divisor =~ /^\d+$/ && $divisor != 0){
     	  $retstr = hex($hexvalue)/$divisor;
     }
     else {
     	  Log3 undef, 3, "VCONTROL: divisor not numeric '$divisor' or 0, it will be ignored";
     	  $retstr = hex($hexvalue)
     }
  }
  return $retstr;
}
#####################################
sub VCONTROL_1ByteSParse($$)
{
  my $hexvalue = shift;
  my $divisor = shift;

  return unpack('c', pack('C',hex(substr($hexvalue,0,2))))/$divisor;
}
#####################################
sub VCONTROL_2ByteUParse($$)
{
  my $hexvalue = shift;
  my $divisor = shift;

  return hex(substr($hexvalue,2,2).substr($hexvalue,0,2))/$divisor;
}
#####################################
sub VCONTROL_2ByteSParse($$)
{
  my $hexvalue = shift;
  my $divisor = shift;

  return unpack('s', pack('S',hex(substr($hexvalue,2,2).substr($hexvalue,0,2))))/$divisor;
}
#####################################
sub VCONTROL_2BytePercentParse($$)
{
  my $hexvalue = shift;
  my $divisor = shift;

  return hex(substr($hexvalue,2,2))/$divisor;
}
#####################################
sub VCONTROL_4ByteParse($$)
{
  my $hexvalue = shift;
  my $divisor = shift;

  return hex(substr($hexvalue,6,2).substr($hexvalue,4,2).substr($hexvalue,2,2).substr($hexvalue,0,2))/$divisor;

}
#####################################
sub VCONTROL_ModeParse($)
{
  my $index = hex(shift); 
  return "$mode[$index]" if ($mode[$index]);
  
  return "";
}
#####################################
sub VCONTROL_timerParse($)
{
  my $binvalue = shift;
  $binvalue = pack('H*', "$binvalue");
  
  my ($h1,$h2,$h3,$h4,$h5,$h6,$h7,$h8) = unpack ("CCCCCCCC",$binvalue); 
  my @bytes = ($h1,$h2,$h3,$h4,$h5,$h6,$h7,$h8);
  my $timer_str;

  for ( $a = 0; $a < 8; $a = $a+1){
     my $delim = "-";
     if ( $a % 2 ){ 
        $delim = "/";
        }
 
     my $byte = $bytes[$a];
     if ($byte == 0xff){
     $timer_str = $timer_str."--$delim";
     }
     else{
     my $hour = ($byte & 0xF8)>>3;
     my $min = ($byte & 7)*10;

     $hour = "0$hour" if ( $hour < 10 );
     $min = "0$min" if ( $min < 10 );

     $timer_str = $timer_str."$hour:$min$delim";
     }
  }
  
  return "$timer_str";  		 
		 
}
#####################################
sub VCONTROL_DateParse($){
   
  my $hexvalue = shift;
  my $vcday;

  #0011223344556677
  #01 23 45 67 89 01 23 45
	$vcday = "So" if ( substr($hexvalue,8,2) eq "00" );
  $vcday = "Mo" if ( substr($hexvalue,8,2) eq "01" );
  $vcday = "Di" if ( substr($hexvalue,8,2) eq "02" );
  $vcday = "Mi" if ( substr($hexvalue,8,2) eq "03" );
  $vcday = "Do" if ( substr($hexvalue,8,2) eq "04" );
  $vcday = "Fr" if ( substr($hexvalue,8,2) eq "05" );
  $vcday = "Sa" if ( substr($hexvalue,8,2) eq "06" );
  $vcday = "So" if ( substr($hexvalue,8,2) eq "07" );

	return $vcday.",".substr($hexvalue,6,2).".".substr($hexvalue,4,2).".".substr($hexvalue,0,4)." ".substr($hexvalue,10,2).":".substr($hexvalue,12,2).":".substr($hexvalue,14,2);

}

###########################################################################
###########################################################################
##  CONV ROUTINES
###########################################################################
###########################################################################
sub VCONTROL_1ByteUConv($)
{
  my $convvalue = shift;
  return (sprintf "%02X", $convvalue);
}
#####################################
sub VCONTROL_1ByteSConv($)
{
  my $convvalue = shift;
  my $cnvstrvalue = (sprintf "%02X", $convvalue);
  if ($convvalue <0){
    return substr($cnvstrvalue,6,2);
  }
  else {
    return $cnvstrvalue;
  }
}
#####################################
sub VCONTROL_1ByteUx10Conv($)
{
  my $convvalue = shift;
  return (sprintf "%02X", $convvalue*10);
}
#####################################
sub VCONTROL_2ByteUConv($)
{
  my $convvalue = shift;
  my $hexstr = (sprintf "%04X", $convvalue);
  return substr($hexstr,2,2).substr($hexstr,0,2);
}
#####################################
sub VCONTROL_2ByteSConv($)
{
  my $convvalue = shift;
  my $cnvstrvalue = (sprintf "%04X", $convvalue);
  if ($convvalue <0){
    return substr($cnvstrvalue,6,2).substr($cnvstrvalue,4,2);
  }
  else {
    return substr($cnvstrvalue,2,2).substr($cnvstrvalue,0,2);
  }
}
#####################################
sub VCONTROL_DateConv($){
  #Eingabe
  #dd.mm.yyyy_hh:mm:ss
  #Ziel
  #yyyymmddwwhhmmss
   
  #dd.mm.yyyy
  my $date = shift;
  my $vcday   = substr($date,0,2);
  my $vcmonth = substr($date,3,2);
  my $vcyear  = substr($date,6,4);
  #hh:mm:ss
  my $vchour = substr($date,11,2);
  my $vcmin  = substr($date,14,2);
  my $vcsec  = substr($date,17,2);
  my $wday;
  my $tmp;
  my $hlptime = timelocal($vcsec, $vcmin, $vchour, $vcday, $vcmonth -1 , $vcyear - 1900);
  ($tmp, $tmp, $tmp, $tmp, $tmp, $tmp, $wday) = localtime $hlptime;
  
  my @Wochentage = ("00","01","02","03","04","05","06");
  $wday = $Wochentage[$wday];
  
  #0011223344556677
  #01 23 45 67 89 01 23 45
	return $vcyear.$vcmonth.$vcday.$wday.$vchour.$vcmin.$vcsec;

}
#####################################
sub VCONTROL_TimerConv($$){

   my $timer_day = shift;
   my $value = shift;
   my @timerarray = split(",",$value); 

   return "" if (@timerarray != 8); 
        
   my @hextimerdata;
   foreach(@timerarray) {
      if ($_ eq "--"){
        push(@hextimerdata,"FF");
      }
     else{
        my ($timerhour, $timermin) = split(":",$_,2);
        if (length($timerhour) != 2 || length($timermin) != 2 ){
           {return "";}
        }
              
        if ( $timerhour < "00" || $timerhour > "23" ){
           {return "";}
        }    

        if ( $timermin ne "00" && $timermin ne "10" && $timermin ne "20" && $timermin ne "30" && $timermin ne "40" && $timermin ne "50"){
           {return "";}
        } 
                           
        my $helpvalue = (($timerhour <<3) + ($timermin/10)) & 0xff;
        push(@hextimerdata, (sprintf "%X", $helpvalue));
     } 
   }
        
   my $suffix="";
   foreach (@hextimerdata){
      $suffix = "$suffix"."$_";
   }
   
   return $suffix;        
}
1;

=pod
=begin html

<a name="VCONTROL"></a>
<h3>VCONTROL</h3>
<ul>
    VCONTROL is the fhem-Modul to control and read information from a VIESSMANN heating via Optolink-adapter.<br><br>
    
    An Optolink-Adapter is necessary (USB or LAN), you will find information here:<br>
    <a href="http://http://openv.wikispaces.com/">http://openv.wikispaces.com/</a><br><br>
    
    Additionaly you need to know Memory-Adresses for the div. heating types (e.g. V200KW1, VScotHO1, VPlusHO1 ....),<br>
    that will be read by the module to get the measurements or to set the actual state.<br>
    Additional information you will fin in the forum <a href="http://http://openv.wikispaces.com/">http://openv.wikispaces.com/</a> and on the following wiki page <a href="http://http://openv.wikispaces.com/">http://openv.wikispaces.com/</a><br><br><br>
    
    <a name="VCONTROLdefine"><b>Define</b></a>
    <ul>
        <code>define &lt;name&gt; VCONTROL &lt;serial-device/LAN-Device:port&gt; &lt;configfile&gt; [&lt;intervall&gt;] </code><br>
        <br>
        <li><b>&lt;serial-device/LAN-Device:port&gt;</b><br>
        USB Port (e.g. com4, /dev/ttyUSB3) or TCPIP:portnumber<br>
        </li>

        <li><b>&lt;intervall&gt;</b><br>
        Poll Intervall in seconds (default 180)<br>
        </li>
        
        <li><b>&lt;configfile&gt;</b><br>
        path to the configuration file, containing the memory addresses<br>
        </li>
        <br>
        Example:<br><br>
        
        serial device com4, every 3 minutes will be polled, configuration file name is 99_VCONTROL.cfg, existing in the fhem root directory<br><br>

        Windows:<br>
        define Heizung VCONTROL com4 99_VCONTROL.cfg 180<br><br>
        
        Linux:<br>
        define Heizung  VCONTROL /dev/ttyUSB3 99_VCONTROL.cfg 180<br>

    </ul>
    <br><br>

    <a name="VCONTROLset"><b>Set</b></a>
    <ul>
        These commands will be configured in the configuartion file.
    </ul>
    <br><br>
    <a name="VCONTROLget"><b>Get</b></a>
    <ul>
        get &lt;name&gt; CONFIG<br><br>
        reload the module specific configfile<br><br>

        More commands will be configured in the configuartion file.
    </ul>
    <br><br>

    <a name="VCONTROLparameter"><b>configfile</b></a>
    <ul>
       You will find Examples for the configuration file for the heating types V200KW1, VScotHO1, VPlusHO1 on the wiki page <a href="http://http://openv.wikispaces.com/">http://openv.wikispaces.com/</a>.<br><br>

       The lines of the configuration file can have the following structure:<br><br>

       <li>lines beginning with "#" are comments!<br></li>
       <li>Polling Commands (POLL) to read values.<br></li>
       <li>Set Commandos (SET) to set values.<br></li>
       <br>
       <b>Polling Commands have the following structure:<br><br></b>

       POLL, ADDRESSE, PARSEMETHODE, DIVISOR, READING-NAME, KUMULATION<br><br>
       
       <ul>
        <li><b>POLL</b><br>
        is fix POLL<br>
        </li>
        <br>
        <li><b>ADDRESSE</b><br>
        Memory Address leading to the value, the will be read in the memory on the heating.<br>
        It is subdivided in 3 parts:<br>
        <ul>
         <li> Beginning is fix 01F7 (defines a reading command)</li>
         <li> followed by actuak address<br></li> 
         <li> followed by number of Bytes to be read.<br></li>
         </ul>
        </li>
        <br>
        <li><b>PARSEMETHODE</b><br>
        Method how to parse the read bytes.<br>
        methods so far:<br>
        <ul>
          <li>1ByteU        :<br> Read value is 1 Byte without algebraic sign (if column Divisor set to state -> only 0 / 1 or off / on)<br></li>
          <li>1ByteS        :<br> Read value is 1 Byte with algebraic sign (wenn Spalte Divisor state ist -> nur 0 / 1 also off / on)<br></li>
          <li>2ByteS        :<br> Read value is 2 Byte with algebraic sign<br></li>
          <li>2ByteU        :<br> Read value is 2 Byte without algebraic sign<br></li>
          <li>2BytePercent  :<br> Read value is 2 Byte in percent<br></li>
          <li>4Byte         :<br> Read value is 4 Byte<br></li>
          <li>mode          :<br> Read value is the actual operating status<br></li>
          <li>timer         :<br> Read value is an 8 Byte timer value<br></li>
          <li>date          :<br> Read value is an 8 Byte timestamp<br></li>
          POLL Commands unsing the method timer will not be polled permanent, they have to be read by a GET Commando explicitly.<br>
          GET &lt;devicename&gt; TIMER<br> 
        </ul>
        </li>
        <br>
        <li><b>DIVISOR</b><br>
        If the parsed value is multiplied by a factor, you can configure a divisor.<br>
        Additionally for values, that just deliver 0 or 1, you can configure state in this column.<br>
        This will force the reading to off and on, instead of 0 and 1.<br>
        </li>
        <br>
        <li><b>READING-NAME</b><br>
        The read and parsed value will be stored in a reading with this name in the device.
        </li>
        <br>
        <li><b>KUMULATION</b><br>
        Accumulated Day values will be automatically stored for polling commands with the value day in the column KUMULATION.<br>
        Futhermore there will be stored the values of the last day in additional readings after 00:00.<br> 
        So you have the chance to plot daily values.<br>
        The reading names will be supplemented by DayStart, Today and LastDay!<br>
        </li>
       
       <br>
       Examples:<br><br>
       <code>POLL, 01F7080402, 2ByteS, 10     , Temp-WarmWater-Actual , -<br></code>
       <code>POLL, 01F7088A02, 2ByteU, 1      , BurnerStarts               , day<br></code>
        </ul>

       <br><br>
       <b>Set Commands have the following structure:<br><br></b>

       SET,SETCMD, ADRESSE, CONVMETHODE, NEXT_CMD or DAY for timer<br><br>
       
       <ul>
        <li><b>SET</b><br>
        is fix SET<br>
        </li>
        <br>

        <li><b>SETCMD</b><br>
        SETCMD are commands that will be used in FHEM to set a value of a device<br>
        set &lt;devicename&gt; &lt;setcmd&gt;<br>
        e.g. SET &lt;devicename&gt; WW to set the actual operational status to Warm Water processing<br>
        </li>
        <br>
      
        <li><b>ADDRESSE</b><br>
        Memory Address where the value has to be written in the memory of the heating.<br>
        It is subdivided in 4 parts:<br>
        <ul>
         <li> Beginning is fix 01F4 (defines a writing command)</li>
         <li> followed by actual address<br></li> 
         <li> followed by number of data-bytes to be written<br></li>
         <li> followed by the data-bytes themselves<br></li>
         </ul>
         <br>
         There are two Address versions:<br>
         <li>Version 1: Value to be set is fix, e.g. Spar Mode on is fix 01<br></li>
         <li>Version 2: Value has to be passed, e.g. warm water temperature<br></li>
        </li>
        <br>
        <li><b>CONVMETHODE</b><br>
        Method how to convert the value with Version 2 in Bytes.<br>
        For Version 1 you can use - here.<br>
        Methods so far:<br>
        <ul>
          <li>1ByteU        :<br> Value to be written in 1 Byte without algebraic sign<br>with Version 2 it has to be a number<br></li>
          <li>1ByteS        :<br> Value to be written in 1 Byte with algebraic sign<br>with Version 2 it has to be a number<br></li>
          <li>2ByteS        :<br> Value to be written in 2 Byte with algebraic sign<br>with Version 2 it has to be a number<br></li>
          <li>2ByteU        :<br> Value to be written in 2 Byte without algebraic sign<br>with Version 2 it has to be a number<br></li>
          <li>timer         :<br> Value to be written is an 8 Byte Timer value<br>with Version 2 it has to be a string with this structure:<br>
                                  8 times of day comma separeted.  (ON1,OFF1,ON2,OFF2,ON3,OFF3,ON4,OFF4)<br>
                                  no time needed ha to be specified with -- .<br>
                                  Minutes of the times are just allowed to thi values: 00,10,20,30,40 or 50<br>
                                  Example: 06:10,12:00,16:00,23:00,--,--,--,--</li>
          <li>date          :<br> Value to be written is an 8 Byte timestamp<br>with Version 2 it has to be a string with this structure:<br>
                                  format specified is DD.MM.YYYY_HH:MM:SS<br>
                                  Example: 21.03.2014_21:35:00</li>
        </ul>
        </li>
        <br>

        <li><b>NEXT_CMD or DAY</b><br>
        This column has two functions:
        <ul>
        <li> If this columns is configured with a name of another SETCMD, it will be processed directly afterwards.<br>
            Example: after setting Spar Mode on (S-ON), you have to set Party Mode off (P-OFF) <br></li> 
        <li>Using timer as CONVMETHODE, so it has to be specified a week day in this columns.<br>
            possible values: MO DI MI DO FR SA SO<br></li>
        </li>
        <br>
        </ul>
        Examples:<br><br>
        <code>SET, WW              ,  01F423010100, state          , -<br></code>
        <code>SET, S-ON             ,  01F423020101, state_spar , P-OFF<br></code>
        <code>SET, WWTEMP      ,  01F4630001    , 1ByteU        , -<br></code>
        <code>SET, TIMER_2_MO,  01F4200008  , timer      , MO<br></code>
        </ul>
    </ul>
    <br>
    <a name="VCONTROLreadings"><b>Readings</b></a>
    <ul>The values read will be stored in readings, that will be configured as described above.</ul>
</ul>

=end html
=begin html_DE

<a name="VCONTROL"></a>
<h3>VCONTROL</h3>
<ul>
    Das VCONTROL ist das fhem-Modul eine VIESSMANN Heizung via Optolink-Schnittstelle auszulesen und zu steuern.<br><br>
    
    Notwendig ist dazu ein Optolink-Adapter (USB oder LAN), zu dem hier Informationen zu finden sind:<br>
    <a href="http://http://openv.wikispaces.com/">http://openv.wikispaces.com/</a><br><br>
    
    Zus&auml;tzlich m&uuml;ssen f&uuml;r die verschiedenen Heizungstypen (z.B. V200KW1, VScotHO1, VPlusHO1 ....) Speicher-Adressen bekannt sein,<br>
    unter denen die Messwerte abgefragt oder aber auch Stati gesetzt werden k&ouml;nnen.<br>
    Informationen hierzu findet man im Forum <a href="http://http://openv.wikispaces.com/">http://openv.wikispaces.com/</a> und auf der wiki Seite <a href="http://http://openv.wikispaces.com/">http://openv.wikispaces.com/</a><br><br><br>
    
    <a name="VCONTROLdefine"><b>Define</b></a>
    <ul>
        <code>define &lt;name&gt; VCONTROL &lt;serial-device/LAN-Device:port&gt; &lt;configfile&gt; [&lt;intervall&gt;] </code><br>
        <br>
        <li><b>&lt;serial-device/LAN-Device:port&gt;</b><br>
        USB Port (z.B. com4, /dev/ttyUSB3) oder aber TCPIP:portnummer<br>
        </li>

        <li><b>&lt;intervall&gt;</b><br>
        Anzahl Sekunden wie oft die Heizung ausgelesen werden soll (default 180)<br>
        </li>
        
        <li><b>&lt;configfile&gt;</b><br>
        Pfad wo die Konfigurationsdatei f&uuml;r das Modul zu finden ist, die die Adressen beinhaltet<br>
        </li>
        <br>
        Beispiel:<br><br>
        
        serielle Schnittstelle &uuml;ber com4, alle 3 Minuten wird gepollt, configfile heisst 99_VCONTROL.cfg und liegt im fhem root Verzeichnis<br><br>

        Windows:<br>
        define Heizung VCONTROL com4 99_VCONTROL.cfg 180<br><br>
        
        Linux:<br>
        define Heizung  VCONTROL /dev/ttyUSB3 99_VCONTROL.cfg 180<br>

    </ul>
    <br><br>

    <a name="VCONTROLset"><b>Set</b></a>
    <ul>
        Diese m&uuml;ssen &uuml;ber das configfile konfiguriert werden.
    </ul>
    <br><br>
    <a name="VCONTROLget"><b>Get</b></a>
    <ul>
        get &lt;name&gt; CONFIG<br><br>
        Mit diesem Befehl wird das Modul spezifische configfile nachgeladen.<br><br>
         
        Diese anderen Befehler m&uuml;ssen &uuml;ber das configfile konfiguriert werden.
    </ul>
    <br><br>

    <a name="VCONTROLparameter"><b>configfile</b></a>
    <ul>
       Im configfile hat man nun die folgenden Konfigurations M&ouml;glichkeiten.<br><br>
       
       Beispieldateien f&uml;r die Ger&auml;te-Typen V200KW1, VScotHO1, VPlusHO1 sind auf der wiki Seite <a href="http://http://openv.wikispaces.com/">http://openv.wikispaces.com/</a> zu finden.<br><br>

       <li>Zeilen die mit "#" beginnen sind Kommentar!<br></li>
       <li>Polling Commandos (POLL) zum Lesen von Werten k&ouml;nnen konfiguriert werden.<br></li>
       <li>Set Commandos (SET) zum setzen von Werten k&ouml;nnen konfiguriert werden.<br></li>
       <br>
       <b>Polling Commandos haben den folgenden Aufbau:<br><br></b>

       POLL, ADDRESSE, PARSEMETHODE, DIVISOR, READING-NAME, KUMULATION<br><br>
       
       <ul>
        <li><b>POLL</b><br>
        muss fest auf POLL stehen<br>
        </li>
        <br>
        <li><b>ADDRESSE</b><br>
        Adresse, an der der auszulesende Wert im Speicher zu finden ist.<br>
        Sie besteht aus 3 Teilen:<br>
        <ul>
         <li> beginnt immer mit 01F7 (Kommando zum Lesen)</li>
         <li> danach folgt die eigentliche Addresse<br></li> 
         <li> danach muss die Anzahl der zu lesenden Bytes noch an die Adresse angehängt werden.<br></li>
         </ul>
        </li>
        <br>
        <li><b>PARSEMETHODE</b><br>
        Methode wie die gelesenen Bytes interpretiert werden m&uuml;ssen.<br>
        Bisher m&ouml;gliche Parsemethoden:<br>
        <ul>
          <li>1ByteU        :<br> Empfangener Wert in 1 Byte ohne Vorzeichen (wenn Spalte Divisor state ist -> nur 0 / 1 also off / on)<br></li>
          <li>1ByteS        :<br> Empfangener Wert in 1 Byte mit Vorzeichen (wenn Spalte Divisor state ist -> nur 0 / 1 also off / on)<br></li>
          <li>2ByteS        :<br> Empfangener Wert in 2 Byte mit Vorzeichen<br></li>
          <li>2ByteU        :<br> Empfangener Wert in 2 Byte ohne Vorzeichen<br></li>
          <li>2BytePercent  :<br> Empfangener Wert in 2 Byte als Prozent Wert<br></li>
          <li>4Byte         :<br> Empfangener Wert in 4 Byte<br></li>
          <li>mode          :<br> Empfangener Wert ist der Betriebsstatus<br></li>
          <li>timer         :<br> Empfangener Wert ist ein 8 Byte Timer Werte<br></li>
          <li>date          :<br> Empfangener Wert ist ein 8 Byte Zeitstempel<br></li>
          POLL Commandos die die Parsemethode timer enthalten werden nicht ständig gelesen, sondern müssen mit einem GET Commando geholt werden.<br>
          GET &lt;devicename&gt; TIMER<br> 
        </ul>
        </li>
        <br>
        <li><b>DIVISOR</b><br>
        Wenn der interpretierte Wert noch um einen Faktor zu hoch ist, kann hier ein Divisor angegeben werden.<br>
        Zus&auml;tzlich hat man hier bei Werten, die nur 0 oder 1 liefern die m&ouml;glich state einzutragen.<br>
        Dies f&uuml;hrt dazu, dass das Reading mit off (0) und on (1) belegt wird, statt mit dem Wert.<br>
        </li>
        <br>
        <li><b>READING-NAME</b><br>
        Der gelesene und interpretierte Wert wird unter diesem Reading abgelegt.
        </li>
        <br>
        <li><b>KUMULATION</b><br>
        Bei den Polling Commandos mit dem Wert day bei der Spalte KUMULATION werden Tageswerte Kumuliert.<br>
        Es werden dann jeweils nach 00:00 Uhr die Werte des letzten Tages ebenfalls als Readings im Device eingetragen,<br> 
        so dass man die Werte pro Tag auch plotten oder auswerten kann.<br>
        Beim Readingnamen wird dann jeweils: DayStart,Today und LastDay angehangen!<br>
        </li>
       
       <br>
       Beispiel:<br><br>
       <code>POLL, 01F7080402, 2ByteS, 10    , Temp-WarmWasser-Ist , -<br></code>
       <code>POLL, 01F7088A02, 2ByteU, 1      , BrennerStarts               , day<br></code>
        </ul>

       <br><br>
       <b>Set Commandos haben den folgenden Aufbau:<br><br></b>

       SET,SETCMD, ADRESSE, CONVMETHODE, NEXT_CMD or DAY for timer<br><br>
       
       <ul>
        <li><b>SET</b><br>
        muss fest auf SET stehen<br>
        </li>
        <br>

        <li><b>SETCMD</b><br>
        Die SETCMD sind die Commandos die man in FHEM zum setzen angeben muss<br>
        set &lt;devicename&gt; &lt;setcmd&gt;<br>
        z.B. SET &lt;devicename&gt; WW zum setzen auf den Status nur Warm Wasser Aufbereitung<br>
        </li>
        <br>
      
        <li><b>ADDRESSE</b><br>
        Adresse, an der der zu setzende Wert im Speicher zu schreiben ist.<br>
        Sie besteht aus 4 Teilen:<br>
        <ul>
         <li> beginnt immer mit 01F4 (Kommando zum Lesen)</li>
         <li> danach folgt die eigentliche Addresse<br></li> 
         <li> danach folgt die Anzahl der zu schreibenden Daten-Bytes<br></li>
         <li> danach m&uuml;ssen die Daten-Bytes selber noch an die Adresse angehängt werden.<br></li>
         </ul>
         <br>
         Es gibt zwei Varianten bei den Adressen:<br>
         <li>Variante 1: Wert steht bereits fest, z.B. Spar Modus einschalten ist fix 01<br></li>
         <li>Variante 2: Wert muss &uumlbergeben werden, z.B. Warm Wasser Temperatur<br></li>
        </li>
        <br>
        <li><b>CONVMETHODE</b><br>
        Methode wie der zu schreibende Wert bei Variante 2 in Bytes konvertiert werden muss.<br>
        Bei Variante 1 kann man - eintragen.<br>
        Bisher m&ouml;gliche Convmethoden:<br>
        <ul>
          <li>1ByteU        :<br> Zu sendender Wert in 1 Byte ohne Vorzeichen<br>bei Variante 2 muss eine Zahl &uuml;bergeben werden<br></li>
          <li>1ByteS        :<br> Zu sendender Wert in 1 Byte mit Vorzeichen<br>bei Variante 2 muss eine Zahl &uuml;bergeben werden<br></li>
          <li>2ByteS        :<br> Zu sendender Wert in 2 Byte mit Vorzeichen<br>bei Variante 2 muss eine Zahl &uuml;bergeben werden<br></li>
          <li>2ByteU        :<br> Zu sendender Wert in 2 Byte ohne Vorzeichen<br>bei Variante 2 muss eine Zahl &uuml;bergeben werden<br></li>
          <li>timer         :<br> Zu sendender Wert ist ein 8 Byte Timer Werte<br>bei Variante 2 muss folgender String uebergeben werden:<br>
                                  8 Uhrzeiten mit Komma getrennt.  (AN1,AUS1,AN2,AUS2,AN3,AUS3,AN4,AUS4)<br>
                                  Keine Uhrzeit muss als -- angegeben werden.<br>
                                  Minuten der Uhrzeiten dürfen nur 00,10,20,30,40 oder 50 sein<br>
                                  Beispiel: 06:10,12:00,16:00,23:00,--,--,--,--</li>
          <li>date          :<br> Zu sendender Wert ist ein 8 Byte Zeitstempel<br>bei Variante 2 muss folgender String uebergeben werden:<br>
                                  es muss das Format DD.MM.YYYY_HH:MM:SS eingehalten werden<br>
                                  Beispiel: 21.03.2014_21:35:00</li>
        </ul>
        </li>
        <br>

        <li><b>NEXT_CMD or DAY</b><br>
        Diese Spalte erf&uuml;llt zwei Funktionen:
        <ul>
        <li>Gibt man in dieser Spalte ein anderes konfiguriertes SETCMD an, so wird dies anschließend ausgeführt.<br>
            Beispiel: nach dem Spar Modus (S-ON) gesetzt wurde, muss der Party Modus (P-OFF) ausgeschaltet werden<br></li> 
        <li>Ist als CONVMETHODE timer angegeben, so muss man in dieser Spalte den Wochentag angeben, für den der Timer gilt.<br>
            M&ouml;gliche Werte: MO DI MI DO FR SA SO<br></li>
        </li>
        <br>
        </ul>
        Beispiele:<br><br>
        <code>SET, WW              ,  01F423010100, state          , -<br></code>
        <code>SET, S-ON             ,  01F423020101, state_spar , P-OFF<br></code>
        <code>SET, WWTEMP      ,  01F4630001    , 1ByteU        , -<br></code>
        <code>SET, TIMER_2_MO,  01F4200008  , timer      , MO<br></code>
        </ul>
    </ul>
    <br>
    <a name="VCONTROLreadings"><b>Readings</b></a>
    <ul>Die eingelesenen Werte werden wie oben beschrieben in selbst konfigurierten Readings abgelegt.</ul>
</ul>
=end html_DE
=cut
