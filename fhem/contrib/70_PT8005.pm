########################################################################################
#
# PT8005.pm
#
# FHEM module to read the data from a PeakTech PT8005 sound level meter
#
# Prof. Dr. Peter A. Henning, 2014
# 
# Version 1.3 - January 2014
#
# setup, set/get functions and attributes see HTML text at bottom
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
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
########################################################################################
package main;

use strict;
use warnings;
use Device::SerialPort;
use vars qw{%attr %defs};
sub Log($$);

#-- globals on start
my $freq ="db(A)";     # dB(A) or dB(C)
my $speed="fast";      # response speed fast or slow
my $mode ="normal";    # min/max/...
my $range="50-100 dB"; # measurement range
my $over ="";          # over/underflow

#-- arrays for averaging (max 60 values per hour)
my @noisearr;
my @timearr;
my $arrind=0;
my $arrmax=70;
my @noisehour;
my $noisenight="";
my $noiseday="";

#-- arrays for hourly values
my @hourarr;

#-- These we may get on request
my %gets = (
  "present"   => "",
  "reading"   => "R",
);

#-- These occur in a pulldown menu as settable values
my %sets = (
  "interval"     => "T",
  "Min/Max"=> "", 
  "off"   => "O",
  "rec"   => "",
  "speed" => "",
  "range" => "",      # toggle the measurement range
  "auto"  => "",      # set the measurement range to auto
  "dBA/C" => "",      # toggle the frequency curve
  "freq"  => ""       # set the frequency curve to a value db(A) or db(C)
);

#-- Single key commands to the PT8005
my %SKC = ("Min/Max","\x11", "off","\x33", "rec","\x55", "speed","\x77", "range","\x88", "dBA/C","\x99");


########################################################################################
#
# PT8005_Initialize
#
# Parameter hash
#
########################################################################################

sub PT8005_Initialize ($) {
  my ($hash) = @_;
  
  $hash->{DefFn}   = "PT8005_Define";
  $hash->{GetFn}   = "PT8005_Get";
  $hash->{SetFn}   = "PT8005_Set";
  # LogM, LogY = name of the monthly and yearly log file
  $hash->{AttrList}= "LogM LogY LimNight LimDay ".
           "loglevel ".
           $readingFnAttributes;
}

########################################################################################
#
# PT8005_Define - Implements DefFn function
#
# Parameter hash, definition string
#
########################################################################################

sub PT8005_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Define the serial device as a parameter"
    if(@a != 3);
  
  my $dev = $a[2];

  Log 1, "PT8005 opening device $dev";
  my $pt8005_serport = new Device::SerialPort ($dev);
  return "PT8005 Can't open $dev: $!" if(!$pt8005_serport);
  Log 1, "PT8005 opened device $dev";
  $hash->{USBDev} =  $pt8005_serport;
  sleep(1);
  $pt8005_serport->close();  
 
  $hash->{DeviceName}   = $dev;
  $hash->{interval}     = 60;        # call every 60 seconds
  
  $modules{PT8005}{defptr}{$a[0]} = $hash;

  #-- InternalTimer blocks if init_done is not true
  my $oid = $init_done;
  $init_done = 1;
  readingsSingleUpdate($hash,"state","initialized",1);
   
  PT8005_GetStatus($hash);
  $init_done = $oid;
  return undef;
}

#######################################################################################
#
# PT8005_Average - Average backwards over given period
# 
# Parameter hash, secsincemidnight,period
#
########################################################################################

sub PT8005_Average($$$) {

  my ($hash, $secsincemidnight, $period) = @_;
  
  #-- max. 1 hour allowed
  if( $period>60*$arrmax ){
    Log 1,"PT8005_Average: wrong averaging period $period, must be <= ".(60*$arrmax);
    return "";
  }

  my ($minind,$cntind,$oldtime,$ia,$ib,$fa,$fb,$ta,$tb,$fd,$avdata);
  
  #-- go backwards until we have period covered (=max. arrmax values)
  $minind=$arrind-1;
  $cntind=1;
  $minind+=$arrmax if($minind<0);
  $oldtime = $timearr[$minind];
  #-- no average if the previous time is undefined
  if( (!defined($oldtime)) || !($oldtime>0) ){
    Log 4,"PT8005_Average: invalid measurement at index $minind, no average possible";
    return "";
  }
  $oldtime-=86400 if($oldtime > $secsincemidnight); 
  while( $oldtime > ($secsincemidnight-$period) ){
    #Log 1,"===>index $minind is ".($secsincemidnight-$timearr[$minind])." ago";
    $minind--;
    $minind+=$arrmax if($minind<0);
    $oldtime = $timearr[$minind];
    #-- no average if the previous time is undefined
    if( (!defined($oldtime)) || !($oldtime>0) ){
      Log 4,"PT8005_Average: invalid measurement at index $minind, no average possible";
      return "";
    }
    $oldtime-=86400 if($oldtime > $secsincemidnight); 
    $cntind++;
    if( $cntind > $arrmax) {
       $cntind=$arrmax;
       Log 4,"PT8005_Average: ERROR, cntind > $arrmax";
       last;
    }
  }
  #-- now go forwards 
  #-- first value must be done by hand
  $ia = $minind;
  $ib = $minind+1;
  $ib-=$arrmax if($ib>=$arrmax);
  $fa = $noisearr[$ia];
  $fb = $noisearr[$ib];
  $ta = $timearr[$ia];
  $ta-= 86400 if($ta > $secsincemidnight);
  $tb = $timearr[$ib];
  $tb-= 86400 if($tb > $secsincemidnight);
  $fd = $fa + ($fb-$fa)*($secsincemidnight-$period - $ta)/($tb - $ta);
  $avdata = ($fd + $fb)/2 * ($tb - ($secsincemidnight-$period));
  #Log 1,"===> interpolated value for data point between $ia and $ib is $fd and avdata=$avdata (tb=$tb, ssm=$secsincemidnight)";  
  #-- other values can be done automatically
  for( my $i=1; $i<$cntind; $i++){
    $ia = $minind+$i;
    $ia-= $arrmax if($ia>=$arrmax);
    $ib = $ia+1;
    $ib-= $arrmax if($ib>=$arrmax);
    $fa = $noisearr[$ia];
    $fb = $noisearr[$ib];
    $ta = $timearr[$ia];
    $ta-= 86400 if($ta > $secsincemidnight);
    $tb = $timearr[$ib];
    $tb-= 86400 if($tb > $secsincemidnight);
    $avdata += ($fa + $fb)/2 * ($tb - $ta);
    #Log 1,"===> adding a new interval between $ia and $ib, new avdata = $avdata (tb=$tb ta=$ta)";  
  }
  #-- and now the average for the period
  $avdata = int($avdata/($period/10))/10;
  
  return $avdata;
}
  
#########################################################################################
#
# PT8005_Cmd - Write command to meter
# 
# Parameter hash, cmd = command 
#
########################################################################################

 sub PT8005_Cmd ($$) {
  my ($hash, $cmd) = @_;

  my $res;
  my $dev= $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $serport = new Device::SerialPort ($dev);
  
  if(!$serport) {
      Log GetLogLevel($name,1), "PT8005: Can't open $dev: $!";
      return undef;
  }
  $serport->reset_error();
  $serport->baudrate(9600);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');
  $serport->write_settings;
    
  #-- calculate checksum and send
  #my $cmd="\x33";
  my $count_out = $serport->write($cmd);
  Log GetLogLevel($name,3), "PT8005 write failed\n"  unless ($count_out);
  #-- sleeping 0.05 seconds
  select(undef,undef,undef,0.05);
  my ($count_in, $string_in) = $serport->read(4);
  #-- control
  #my ($i,$j,$k);
  #my $ans="receiving:";
  #for($i=0;$i<$count_in;$i++){
  #  $j=int(ord(substr($string_in,$i,1))/16);
  #  $k=ord(substr($string_in,$i,1))%16;
  #  $ans.="byte $i = 0x$j$k\n";
  #}
  #Log 1, $ans;
  #-- sleeping 0.05 seconds
  select(undef,undef,undef,0.05);
  $serport->close();
}
  
########################################################################################
#
# PT8005_Get -  Implements GetFn function 
#
# Parameter hash, argument array
#
########################################################################################

sub PT8005_Get ($@) {
  my ($hash, @a) = @_;

  #-- check syntax
  return "PT8005_Get needs exactly one parameter" if(@a != 2);
  my $name = $hash->{NAME};
  my $v;

  #-- get present
  if($a[1] eq "present") {
    $v =  ($hash->{READINGS}{"state"}{VAL} =~ m/.*dB.*/) ? 1 : 0;
    return "$a[0] present => $v";
  } 

  #-- current reading
  if($a[1] eq "reading") {
    $v = PT8005_GetStatus($hash);
    if(!defined($v)) {
      Log GetLogLevel($name,2), "PT8005_Get $a[1] error";
      return "$a[0] $a[1] => Error";
    }
    $v =~ s/[\r\n]//g;                          # Delete the NewLine
  } else {
    return "PT8005_Get with unknown argument $a[1], choose one of " . join(" ", sort keys %gets);
  }

  Log GetLogLevel($name,3), "PT8005_Get $a[1] $v";
  return "$a[0] $a[1] => $v";
}
 
#######################################################################################
#
# PT8005 - GetStatus - Called in regular intervals to obtain current reading
#
# Parameter hash
#
########################################################################################

sub PT8005_GetStatus ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my ($bcd,$i,$j,$k);

  my $data    = 0.0;
  my $nospeed = 1;
  my $norange = 1;
  my $nofreq  = 1;
  my $nodata  = 1;
  my $loop    = 0;
  
  my $secsincemidnight;
  my $av15 = "";
  my $av60 = "";
  my $avnight = 0;
  my $avday   = 0;
  my $avcnt   = 0;
  
  my $svalue;
  my $lvalue;
  my $hvalue;

  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday() + $hash->{interval}, "PT8005_GetStatus", $hash,1);
  #-- check if rec is really off
  PT8005_Unrec($hash);
  
   #-- Obtain the current reading
  my $res;
  my $dev= $hash->{DeviceName};
  my $serport = new Device::SerialPort ($dev);
  
  if(!$serport) {
    Log GetLogLevel($name,3), "PT8005_Read: Can't open $dev: $!";
    return undef;
  }
  $serport->reset_error();
  $serport->baudrate(9600);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');
  $serport->write_settings;
   
  #-- switch into recording mode
  my $count_out = $serport->write($SKC{"rec"});
  Log GetLogLevel($name,3), "PT8005_GetStatus: Switch to REC failed" unless ($count_out);
  #-- sleeping some time
  select(undef,undef,undef,0.15);
 
  #-- loop for the data 
  while ( ($nodata > 0) and ($loop <3) ){
    #my $string_in=PT8005_Read($hash);
    select(undef,undef,undef,0.02);
    my ($count_in, $string_in) = $serport->read(64);
    $loop++;
  
    #--find data items    
    if( index($string_in,"\xA5\x02") != -1){
      $nospeed=0;
      $speed="fast";
    } elsif( index($string_in,"\xA5\x03") != -1){
      $nospeed=0;
      $speed="slow";
    }
   
    if( index($string_in,"\xA5\x04") != -1){
      $mode="max";
    }elsif( index($string_in,"\xA5\x05") != -1){
      $mode="min";
    }else{
      $mode="normal";
    }
   
    if( index($string_in,"\xA5\x10") != -1){
      $norange=0;
      $range="30-80 dB";
    }elsif( index($string_in,"\xA5\x20") != -1){
      $norange=0;
      $range="50-100 dB";
    }elsif( index($string_in,"\xA5\x30") != -1){
      $norange=0;
      $range="80-130 dB";
    }elsif( index($string_in,"\xA5\x40") != -1){
      $norange=0;
      $range="30-130 dB";
    }
  
    if( index($string_in,"\xA5\x07") != -1){
      $over="over";
    }elsif( index($string_in,"\xA5\x08") != -1){
      $over="under";
    }else{
      $over="";
    }
   
    if( index($string_in,"\xA5\x1B") == -1){
      $nofreq=0;
      $freq="dB(A)";
    } elsif ( index($string_in,"\xA5\x1C") != -1){
      $nofreq=0;
      $freq="dB(C)";  
    } 
     
    #-- time not needed
    #my $in_time = index($string_in,"\xA5\x06");
    #if( $in_time != -1 ){
    #  $bcd=ord(substr($string_in,$in_time+2,1));
    #  $hour=int($bcd/16)*10 + $bcd%16 - 20;
    #  $bcd=ord(substr($string_in,$in_time+3,1));
    #  $min = int($bcd/16)*10 + $bcd%16;
    #  $bcd=ord(substr($string_in,$in_time+4,1));
    #  $sec = int($bcd/16)*10 + $bcd%16;     
    #  $time=sprintf("%02d:%02d:%02d",$hour,$min,$sec);
    #} else { 
    #  $time="undef";
    #  Log GetLogLevel($name,3),"PT8005_GetStatus: no time value obtained"
    #}
  
    #-- data value
    my $in_data = index($string_in,"\xA5\x0D");
    if( $in_data != -1){
      my $s1=substr($string_in,$in_data+2,1);
      my $s2=substr($string_in,$in_data+3,1);
      if( ($s1 ne "") && ($s2 ne "") ){ 
        $nodata = 0;
        $bcd=ord($s1);
        $data=(int($bcd/16)*10 + $bcd%16)*10;
        $bcd=ord($s2);
        $data+=(int($bcd/16)*10 + $bcd%16)*0.1;
      }
    } 
  }

  #-- sleeping some time
  select(undef,undef,undef,0.01);
  #-- leave recording mode
  $count_out = $serport->write($SKC{"rec"}); 
  #-- sleeping some time
  select(undef,undef,undef,0.01);
  #-- 
  $serport->close();
  
  #-- could not find a value
  if( $nofreq==1 ){
    Log GetLogLevel($name,4), "PT8005_GetStatus: no dBA/C frequency curve value obtained";
  };
  if( $norange==1 ){
    Log GetLogLevel($name,4), "PT8005_GetStatus: no range value obtained";
  };
  if( $nospeed==1 ){
    Log GetLogLevel($name,4), "PT8005_GetStatus: no speed value obtained";
  };
  if( $nodata==1 ){
    Log GetLogLevel($name,4), "PT8005_GetStatus: no data value obtained";
  };
  
  #-- addnl. messages
  if( $over eq "over"){
    Log GetLogLevel($name,4), "PT8005_GetStatus: Range overflow";
  }elsif( $over eq "under" ){
    Log GetLogLevel($name,4), "PT8005_GetStatus: Range underflow";
  }
  
  #-- put into readings
  $hash->{READINGS}{"soundlevel"}{UNIT}     = $freq 
    if( $nofreq ==0 );
  $hash->{READINGS}{"soundlevel"}{UNITABBR} = $freq
    if( $nofreq ==0 );
  
  #-- testing for wrong data value 
  if( $data <=30 ){
    $nodata=1;
  };
  
  #-- put into READINGS
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"speed",$speed)     
    if( $nospeed ==0 );
  readingsBulkUpdate($hash,"mode",$mode); 
  readingsBulkUpdate($hash,"range",$range)     
    if( $norange ==0 );
  readingsBulkUpdate($hash,"overflow",$over);
    
  if( $nodata==0 ){

    my ($sec, $min, $hour, $day, $month, $year, $wday,$yday,$isdst) = localtime(time);
  
    $secsincemidnight = $hour*3600+$min*60+$sec;
    $noisearr[$arrind] = $data;
    $timearr[$arrind] = $secsincemidnight;    
    
    #-- average last 15 minutes
    $av15 = PT8005_Average($hash,$secsincemidnight,900);
    
    #-- output
    if( $av15 ne "" ){
      $svalue = sprintf("%3.1f %s [av15 %3.1f %s]",$data,$freq,$av15,$freq);
      $lvalue = sprintf("%3.1f av15  %3.1f ",$data,$av15);
    }else{
      $svalue = sprintf("%3.1f %s",$data,$freq);
      $lvalue = sprintf("%3.1f",$data);
    }
    readingsBulkUpdate($hash,"state",$svalue);  
    readingsBulkUpdate($hash,"soundlevel",$lvalue);
    
    #-- average last hour if hour is past
    my $oldtime = $timearr[
      $arrind>0 ? $arrind-1 : $arrmax-1];
    if( defined($oldtime) ){
      my $oldhour = int($oldtime/3600);
      if( ($hour == ($oldhour+1)) || ($hour == ($oldhour-23)) ){
        my $longav    = PT8005_Average($hash,$secsincemidnight,3600+$min*60+$sec);
        my $shortav   = PT8005_Average($hash,$secsincemidnight,$min*60+$sec);
        if( ($longav ne "") && ($shortav ne "") ){
          $av60 = ($longav*(3600+$min*60+$sec)-$shortav*($min*60+$sec))/3600;
          $noisehour[$hour]=int($av60*10)/10;;
          Log GetLogLevel($name,4),"PT8005 gives average for hour $oldhour as $av60";
          #-- output
          $hvalue = sprintf("%3.1f",$av60);
          readingsBulkUpdate($hash,"soundav60",$hvalue);
          
          #-- check if nightly or daily average
          if( $hour==6 ){
              $avnight = 0.0;
              $avcnt   = 0;
              if( defined($noisehour[23])){
                $avnight += $noisehour[23];
                $avcnt++;
              }
              for( my $i=0;$i<=6;$i++ ){
                if( defined($noisehour[$i])){
                  $avnight += $noisehour[$i];
                  $avcnt++;
                }
              }
              if( $avcnt > 0){
                $noisenight = int($avnight/$avcnt*10)/10;
                Log GetLogLevel($name,1),"PT8005: Nightly average = $avnight from $avcnt values";
                #-- output
                $hvalue = sprintf("%3.1f %s",$noisenight,$freq);
                readingsBulkUpdate($hash,"soundavnight",$hvalue);
              } else {
                $noisenight = "";
              }
            } elsif( $hour==22 ){
              $avday = 0.0;
              $avcnt   = 0;
              for( my $i=7;$i<=22;$i++ ){
                if( defined($noisehour[$i])){
                  $avday += $noisehour[$i];
                  $avcnt++;
                }
              }
              if( $avcnt > 0){
                $noiseday = int($avday/$avcnt*10)/10;
                Log GetLogLevel($name,1),"PT8005: Daily average = $avnight from $avcnt values";
                #-- output
                $hvalue = sprintf("%3.1f %s",$noiseday,$freq);
                readingsBulkUpdate($hash,"soundavday",$hvalue);
              } else {
                $noiseday = "";
              }
              $hvalue = sprintf("%3.1f %3.1f",$noisenight,$noiseday);
              readingsBulkUpdate($hash,"soundday",$hvalue);
            }
        } else {
          $noisehour[$hour]=undef;
          Log GetLogLevel($name,4),"PT8005 NOT calculating new hourly average";
        }
      }
    }
    
    $arrind++;
    $arrind-=$arrmax if($arrind>=$arrmax);
      
  }  
  readingsEndUpdate($hash,1); 
}
 
########################################################################################
#
# PT8005_Set - Implements SetFn function
#
# Parameter hash, a = argument array
#
########################################################################################

sub PT8005_Set ($@) {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $res;

  #-- for the selector: which values are possible
  #return join(" ", sort keys %sets) if(@a != 2);
  return "PT8005_Set: With unknown argument $a[0], choose one of " . join(" ", sort keys %sets)
    if(!defined($sets{$a[0]}));
 
  my $dev= $hash->{DeviceName};
  
  #-- Set single key value
  for (keys %SKC){
    if( $a[0] eq "$_" ){
      Log GetLogLevel($name,1),"PT8005_Set called with arg $_";
      PT8005_Cmd($hash,$SKC{$_});
    }
  }
  
  #-- Set timer value
  if( $a[0] eq "interval" ){
    #-- only values >= 5 secs allowed
    if( $a[1] >= 5){
      $hash->{interval} = $a[1];  
  	  $res = 1;
  	} else {
  	  $res = 0;
  	}
  }
  
  #-- Set frequency curve to db(A) or db(C)
  if( $a[0] eq "freq" ){
    my $freqn = $a[1];
    if ( (!defined($freqn)) || (($freqn ne "dB(A)") && ($freqn ne "dB(C)")) ){
      return "PT8005_Set $name ".join(" ",@a)." with missing parameter, must be dB(A) or dB(C) ";
    }
    if ( (($freq eq "dB(A)") && ($freqn eq "dB(C)")) ||
         (($freq eq "dB(C)") && ($freqn eq "dB(A)")) ){
    Log GetLogLevel($name,1),"PT8005_Set freq $freqn";
    $res=PT8005_Cmd($hash,$SKC{"dBA/C"});
    }
  }
  
  #-- Set measurement range to auto
  if( $a[0] eq "auto" ){
    if ($range eq "30-80 dB"){
      $res =PT8005_Cmd($hash,$SKC{"range"});
      select(undef,undef,undef,0.05);
      $res.=PT8005_Cmd($hash,$SKC{"range"});
      select(undef,undef,undef,0.05);
      $res.=PT8005_Cmd($hash,$SKC{"range"});
    }elsif ($range eq "50-100 dB"){ 
      $res =PT8005_Cmd($hash,$SKC{"range"});
      select(undef,undef,undef,0.05);
      $res.=PT8005_Cmd($hash,$SKC{"range"});
    }elsif ($range eq "80-130 dB"){ 
      $res=PT8005_Cmd($hash,$SKC{"range"});
    }
     
    Log GetLogLevel($name,1),"PT8005_Set auto";
  }
  
  Log GetLogLevel($name,3), "PT8005_Set $name ".join(" ",@a)." => $res";  
  return "PT8005_Set $name ".join(" ",@a)." => $res";
}

########################################################################################
#
# PT8005_Unrec - switch recording mode off
# 
# Parameter hash 
#
########################################################################################

 sub PT8005_Unrec ($) {
  my ($hash) = @_;

  my $res;
  my $dev= $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $serport = new Device::SerialPort ($dev);
  
  if(!$serport) {
      Log GetLogLevel($name,3), "PT8005_UnRec: Can't open $dev: $!";
      return undef;
  }
  $serport->reset_error();
  $serport->baudrate(9600);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');
  $serport->write_settings;
    
  for(my $i = 0; $i < 3; $i++) {  
    #-- read data and look if it is nonzero
    my ($count_in, $string_in) = $serport->read(1);
    if( $string_in eq "" ){
      $serport->close();
      Log GetLogLevel($name,4),"PT8005_UnRec:  REC is off ";
      return 1;
    } else {
    #-- leave recording mode
      select(undef,undef,undef,0.02);
      my $count_out = $serport->write($SKC{"rec"}); 
      #-- sleeping some time
      select(undef,undef,undef,0.02);
    }
  }
  $serport->close();
  Log GetLogLevel($name,4),"PT8005_UnRec: REC cannot be turned off ";
 
  return 0;
}

1;


=pod
=begin html

<a name="PT8005"></a>
        <h3>PT8005</h3>
        <p>FHEM module to commmunicate with a PeakTech PT8005 soundlevel meter<br />
        </p>
        <h4>Example</h4>
        <p>
            <code>define pt8005 PT8005 /dev/ttyUSB0 </code>
        </p><br />   
        <a name="PT8005define"></a>
        <h4>Define</h4>
        <p>
        <code>define &lt;name&gt; PT8005  &lt;device&gt; </code> 
        <br /><br /> Define a PT8005 soundlevel meter</p>
        <ul>
          <li>
            <code>&lt;name&gt;</code>
           Serial device port 
         </li>
        </ul>
        <a name="PT8005set"></a>
        <h4>Set</h4>
          <li><a name="pt8005_interval">
                    <code>set &lt;name&gt; interval &lt;value&gt;</code>
                </a>
                <br />sets the time period between measurements in seconds (default
                is 60 seconds, minimum is 5 seconds).
            </li>
            <li><a name="pt8005_auto">
                    <code>set &lt;name&gt; auto</code>
                </a>
                <br />set the measurement range to auto (30 -130 dB) (displayed in status) 
            </li>
             <li><a name="pt8005_freq">
                    <code>set &lt;name&gt; freq dB(A)|dB(C)</code>
                </a>
                <br />set frequency curve to A or C (displayed in status) 
            </li>
             <li><a name="pt8005_rec">
                    <code>set &lt;name&gt; rec</code>
                </a>
                <br />toggle the recording mode 
            </li>
             <li><a name="pt8005_minmax">
                    <code>set &lt;name&gt; Min/Max</code>
                </a>
                <br />toggle the display between min value, max value and running measurement (displayed in status) 
            </li>
             <li><a name="pt8005_dBA/C">
                    <code>set &lt;name&gt; dBA/C</code>
                </a>
                <br />toggle the frequency curve (displayed in status) 
            </li>
             <li><a name="pt8005_off">
                    <code>set &lt;name&gt; off</code>
                </a>
                <br />switch off the device 
            </li>
        </ul>
        <br />
        <a name="PT8005get"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="pt8005_reading">
                    <code>get &lt;name&gt; reading</code></a>
                <br /> read all current data </li>
            <li><a name="pt8005_present">
                    <code>get &lt;name&gt; present</code></a>
                <br /> 1 if device present, 0 if not </li>
        </ul>
        <br />
        <a name="PT8005attr"></a>
        <h4>Attributes</h4>
        <ul>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a
                    href="#stateFormat">stateFormat</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
        
=end html
=cut

