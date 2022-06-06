########################################################################################
#
# NT5000.pm
#
# FHEM module to read the data from a Sunways NT5000 solar inverter
#
# Prof. Dr. Peter A. Henning, 2008
# 
# Version 2.2 - January 2014
#
# TODO: do not ask for serialport.pm when emulator is called
#
# Setup as:
# define  <name> NT5000 <device>
#    
# where <name> may be replaced by any name string and <device> 
# is a serial (USB) device or the keyword "emulator".
# In the latter case, a 4.5 kWP solar installation is simulated
#
# get <name> present     => 1 if device present, 0 if not
# get <name> serial      => inverter serial number
# get <name> proto       => protocol 
# get <name> reading     => measurement for all channels
# get <name> month       => monthly measurement
# get <name> year       => yearly measurement
#
# set <name> time        => set inverter clock
#
# Additional attributes are defined in fhem.cfg as 
#  attr    nt5000 room Solaranlage
# Area of solar installation
#  attr    nt5000 Area 32.75
# Peak Solar Power
#  attr    nt5000 PSP 4.5
# Monthly and yearly log file
#  attr    nt5000 LogM SolarLogM
#  attr    nt5000 LogY SolarLogY
# Months with erroneous readings - see line 83 ff
#  attr    nt5000 MERR <list>
# Expected yields per month / year
#  attr    nt5000 Wx_M1 150
#  attr    nt5000 Wx_M2 250
#  attr    nt5000 Wx_M3 350
#  attr    nt5000 Wx_M4 450
#  attr    nt5000 Wx_M5 600
#  attr    nt5000 Wx_M6 600
#  attr    nt5000 Wx_M7 600
#  attr    nt5000 Wx_M8 600
#  attr    nt5000 Wx_M9 450
#  attr    nt5000 Wx_M10 350
#  attr    nt5000 Wx_M11 250
#  attr    nt5000 Wx_M12 150
#  attr    nt5000 Wx_Y 4800
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

#-- Prototypes to make komodo happy
use vars qw{%attr %defs};
sub Log($$);

#-- Line counter 
my $cline=0;

#-- These we may get on request
my %gets = (
  "present"   => "",
  "serial"    => "S",
  "proto"     => "P",
  "reading"   => "R",
  "month"     => "M",
  "year"      => "Y"
);

#-- These occur in a pulldown menu as settable values
my %sets = (
  "time" => "T"
);


########################################################################################
#
# NT5000_Initialize
#
# Parameter hash
#
########################################################################################

sub NT5000_Initialize ($) {
  my ($hash) = @_;
  
  $hash->{DefFn}   = "NT5000_Define";
  $hash->{GetFn}   = "NT5000_Get";
  $hash->{SetFn}   = "NT5000_Set";
  # Area = Area of solar panels, to calculate expected output from solar irradiation
  # PSP  = Peak Solar Power of installation
  # MERR = List of month entries that failed. Reason: Defective loggers in the NT5000 itself
  #        sometimes "jump" ahead in the monthly setting. Maybe singular problem of author ?
  #        Every pseudo-month-entry in this list means that its yield is ADDED to the FOLLOWING month
  #        e.g. MERR = 4 => Month value for April is wrong and should be added to the value from May,
  #        which is the following one.
  # WxM1 .. WxM12 = Expected yield from January .. December
  # WxY  = Expected yield per year 
  # LogM, LogY = name of the monthly and yearly log file
  $hash->{AttrList}= "Area PSP MERR ".
           "Wx_M1 Wx_M2 Wx_M3 Wx_M4 Wx_M5 Wx_M6 Wx_M7 Wx_M8 Wx_M9 Wx_M10 Wx_M11 Wx_M12 ".
           "Wx_Y LogM LogY ".
           "loglevel ".
           $readingFnAttributes;
}

########################################################################################
#
# NT5000_Define - Implements DefFn function
#
# Parameter hash, definition string
#
########################################################################################

sub NT5000_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Define the serial device as a parameter, use none or emulator for a fake device"
    if(@a != 3);
  
  my $dev = $a[2];

  Log 1, "NT5000 device is none, commands will be echoed only"
    if($dev eq "none");

  Log 1, "NT5000 with emulator mode"
    if($dev eq "emulator");

  if( ($dev ne "none") && ($dev ne "emulator")) {
    Log 3, "NT5000 opening device $dev";
    my $nt5000_serport = new Device::SerialPort ($dev);
    return "NT5000 Can't open $dev: $!" if(!$nt5000_serport);
    Log 2, "NT5000 opened device $dev";
    $hash->{USBDev} =  $nt5000_serport;
    sleep(1);
    $nt5000_serport->close();  
  }

  $hash->{DeviceName}   = $dev;
  $hash->{INTERVAL}       = 60;        # call every 60 seconds
  $hash->{Cmd}          = "reading";   # get all data,  min/max unchange
  $hash->{SerialNumber} = "";
  $hash->{Protocol}     = "";
  $hash->{Firmware}     = "";
  
  $modules{NT5000}{defptr}{$a[0]} = $hash;

  #-- InternalTimer blocks if init_done is not true
  my $oid = $init_done;
  $init_done = 1;
  readingsSingleUpdate($hash,"state","initialized",1);

  NT5000_GetStatus($hash);
  $init_done = $oid;
  return undef;
}

########################################################################################
#
# NT5000_Get -  Implements GetFn function 
#
# Parameter hash, argument array
#
########################################################################################

sub NT5000_Get ($@) {
  my ($hash, @a) = @_;

  #-- check syntax
  return "NT5000_Get needs exactly one parameter" if(@a != 2);
  my $name = $hash->{NAME};
  my $v;

  #-- get present
  if($a[1] eq "present") {
    $v =  ($hash->{READINGS}{"state"}{VAL} =~ m/.*kW/) ? 1 : 0;
    return "$a[0] present => $v";
  } 

  #-- current reading
  if($a[1] eq "reading") {
    $v = NT5000_GetLine($hash,"reading");
    if(!defined($v)) {
      Log GetLogLevel($name,2), "NT5000_Get $a[1] error";
      return "$a[0] $a[1] => Error";
    }
    $v =~ s/[\r\n]//g;                          # Delete the NewLine
    readingsSingleUpdate($hash,"reading",$v,1);
  #-- monthly reading   
  } elsif($a[1] eq "month") {
    $v = NT5000_GetMonth($hash);
    if(!defined($v)) {
      Log GetLogLevel($name,2), "NT5000_Get $a[1] error";
      return "$a[0] $a[1] => Error";
    }
    readingsSingleUpdate($hash,"month","Wm: ".$hash->{month}->[0]." kWh (".$hash->{month}->[2]."%)",1);
  #-- yearly reading  
  } elsif($a[1] eq "year") {
    $v = NT5000_GetYear($hash);
    if(!defined($v)) {
      Log GetLogLevel($name,2), "NT5000_Get $a[1] error";
      return "$a[0] $a[1] => Error";
    }
    readingsSingleUpdate($hash,"year","Wy: ".$hash->{year}->[0]." kWh (".$hash->{year}->[4]."%)",1);
  } else {
    return "NT5000_Get with unknown argument $a[1], choose one of " . join(" ", sort keys %gets);
  }

  Log GetLogLevel($name,3), "NT5000_Get $a[1] $v";
  return "$a[0] $a[1] => $v";
}

########################################################################################
#
# NT5000_Set - Implements SetFn function
#
# Parameter hash, a = argument array
#
########################################################################################

sub NT5000_Set ($@) {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $res;

  #-- for the selector: which values are possible
  return join(" ", sort keys %sets) if(@a != 2);
  return "NT5000_Set: With unknown argument $a[0], choose one of " . join(" ", sort keys %sets)
    if(!defined($sets{$a[0]}));

  #-- Set time value
  if( $a[0] eq "time" ){
    #-- only values >= 15 secs allowed
    if( $a[1] >= 15){
  	  $res = "not yet implemented";
  	} else {
  	  $res = "not yet implemented";
  	}
    Log GetLogLevel($name,3), "NT5000_Set $name ".join(" ",@a)." => $res";  
    return "NT5000_Set => $name ".join(" ",@a)." => $res";
  }
}

########################################################################################
#
# NT5000 - GetStatus - Called in regular intervals to obtain current reading
#
# Parameter hash
#
########################################################################################

sub NT5000_GetStatus ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+ $hash->{INTERVAL}, "NT5000_GetStatus", $hash,1);

  # Obtain the current reading
  my $result = NT5000_GetLine($hash, "reading");

  # If one of these applies we must assume that the inverter is offline (no retry !)
  # Logging only if this is a change from the previous state
  if( !defined($result) ) {
    Log GetLogLevel($name,1), "NT5000 cannot be read, inverter offline" if( $hash->{READINGS}{"state"}{VAL} ne "offline" );
    #Log 3, "NT5000 cannot be read, inverter offline";
    readingsSingleUpdate($hash,"state","offline",1);
    return "offline"; 
  } elsif( length($result) < 13 ){
    Log GetLogLevel($name,1), "NT5000 returns incomplete line, inverter offline" if( $hash->{READINGS}{"state"}{VAL} ne "starting" );
    #Log 3, "NT5000 returns incomplete line";
    readingsSingleUpdate($hash,"state","incomplete",1);
    return "incomplete";
  }else {
    # we have obtained a reading: inverter is online
    readingsBeginUpdate($hash);
    my @names    = ("Udc", "Idc", "Pdc", "Uac", "Iac", "Pac", "Temp", "S", "Wd", "Wtot", "Eta");
    my @units    = ("Volt", "Ampere", "Kilowatt", "Volt", "Ampere", "Kilowatt", "Celsius", "Watt per m<sup>2</sup>", "Kilowatthours", "Kilowatthours", "percent");
    my @unitabbr = ("V", "A", "kW", "V", "A", "kW", "&deg;C", "W/m<sup>2</sup>", "kWh", "kWh", "%");
    my @type     = ("voltage", "current", "power", "voltage", "current", "power", "temperature", "power density", "energy", "energy","efficiency");
    
    #-- we are in the first reading, have turned online recently
    if( $hash->{READINGS}{"state"}{VAL} !~ m/.*kW.*/ ) {
      Log GetLogLevel($name,2), "NT5000 inverter is online";
      readingsBulkUpdate($hash,"state","online");
      #-- Obtain the serial number and protocol
      my $serial  = NT5000_GetLine($hash, "serial");
      $serial =~ s/^.*S://;
      $serial =~ s/[\r\n ]//g;
      $hash->{SerialNumber} = "$serial";
      my $proto  = NT5000_GetLine($hash, "proto");
      $proto =~ s/^.*P://;
      $proto =~ s/[\r\n ]//g;
      $hash->{Firmware} = substr($proto,0,1).".".substr($proto,1,1);
      $hash->{Protocol} = substr($proto,2,1).".".substr($proto,4,2);
      
      # Obtain monthly readings in 20 seconds - only once
      InternalTimer(gettimeofday()+ 20, "NT5000_GetMonth", $hash,1);
      
      # Obtain yearly readings in 40 seconds - only once
      InternalTimer(gettimeofday()+ 40, "NT5000_GetYear", $hash,1);
      
      #-- Put header lines into the log file
      my $resmod ="";
      for(my $i = 0; $i < int(@names); $i++) {
        $resmod .= $names[$i]."  ";
      }
      readingsBulkUpdate($hash,"header1",$resmod);
     
      $resmod ="";
      for(my $i = 0; $i < int(@unitabbr); $i++) {
        $resmod .= "[".$unitabbr[$i]."] ";
      }
      readingsBulkUpdate($hash,"header2",$resmod);
      #-- set units properly
      for(my $i = 0; $i < int(@names); $i++)  {
        $hash->{READINGS}{$names[$i]}{UNIT}     = $units[$i];
        $hash->{READINGS}{$names[$i]}{UNITABBR} = $unitabbr[$i];
        $hash->{READINGS}{$names[$i]}{TYPE}     = $type[$i];
      } 
    }; 
    
    #-- put into READINGS
    readingsBulkUpdate($hash,"reading",$result);
    Log GetLogLevel($name,5), "NT5000 online result = $result";
   
    #-- split result for writing into hash
    my @data = split(' ',$result);
    readingsBulkUpdate($hash,"state", sprintf("%5.3f %s",$data[5],$unitabbr[5]));
    for(my $i = 0; $i < int(@names); $i++)  {
      # This puts individual pairs into the tabular view
      readingsBulkUpdate($hash,$names[$i],$data[$i]);
    } 
    readingsEndUpdate($hash,1); 
    $result =~ s/;/ /g;  
  }

  return $hash->{READINGS}{"state"}{VAL};
}

########################################################################################
#
# NT5000_GetMonth - Read monthly data from inverter
#
# Parameter hash
#
########################################################################################

sub NT5000_GetMonth ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my ($ln,$lf,$ret,$daten);
  
  my ($sec,$min,$hour,$dayn,$month,$year,$wday,$yday,$isdst) = localtime(time);
  my $yearn = $year+1900;
  my $monn  = $month+1;
  
  #-- Obtain the monthly reading
  my $result = NT5000_GetLine($hash, "month");
  $result =~ s/^.*M://;
  $result =~ s/[\r\n ]//g;   
  Log GetLogLevel($name,3), "NT5000 monthly result = $result";
  $result=~ s/,/./g;
  my @data = split(";", $result);
  my $day = $data[0];

  #-- Expected yield for month
 
  my $mex  = "Wx_M".($month+1);
  my $wex  = $attr{$name}{$mex};
  my $wac  = 0;
  my $wre;
  my $wav;
  my $value;

  my @names = ("W_D01","W_D02","W_D03","W_D04","W_D05","W_D06","W_D07","W_D08","W_D09","W_D10",
   "W_D11","W_D12","W_D13","W_D14","W_D15","W_D16","W_D17","W_D18","W_D19","W_D20",
   "W_D21","W_D22","W_D23","W_D24","W_D25","W_D26","W_D27","W_D28","W_D29","W_D30","W_D31");
   
  #-- Check current logfile 
  $ln = $attr{$name}{"LogM"};
  if( !(defined($ln))){
    Log 1,"NT5000_GetMonth: Attribute LogM is missing";
    #-- here some other output of monthly data
  } else {
    $lf = $defs{$ln}{currentlogfile};
    $ret  = open(NT5000FILE, "> $lf" );
    if( $ret) {
      print NT5000FILE "monthly data:              Day   Wd     Wm    Wex\n";
      for(my $i = 0; $i < $day; $i++) {
        $dayn  = $i+1;
        #-- for current day actual time, otherwise dummy time
        if( $i == ($day-1) ){
          $daten = sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$yearn,$monn,$dayn,$hour,$min,$sec);
        }else{
          $daten = sprintf("%4d-%02d-%02d_23:59:00",$yearn,$monn,$dayn);
        }
        $wac  += $data[$day-$i];
        if( $wex ){  
          $wre  = int(1000*$wac/$wex)/10 if ($wex>0 );
        };
        # Put one item per line into the log file
        printf NT5000FILE "%s %s %5s %6.3f %5.1f %5.1f\n",$daten,$name,$names[$i],$data[$day-$i],$wac,$wre;  
      };
      Log 1,"NT5000_GetMonth: File $lf overwritten"; 
      close(NT5000FILE);      
      #-- daily average
      $wav = ($day > 1) ? int( 10*($wac-$data[1]) / ($day-1) )/10.0 : 0.0;
      #-- store value 
      $hash->{month}->[0]=$wac;
      $hash->{month}->[1]=$wex;
      $hash->{month}->[2]=$wre;
      $hash->{month}->[2]=$wav;
      #-- return value 
      $value  = "\nWm ".$wac." kWh (monthly sum until now)\n";
      $value .= "Wa ".$wav." kWh/d (average until yesterday)\n";
      $value .= $wre."% of expected ".$wex." kWh";
      return $value;  
    } else {
      Log 1,"NT5000_GetMonth: Cannot open $lf for writing!"; 
      return undef;
    }
  }
}

########################################################################################
#
# NT5000_GetYear - Read yearly data from inverter
#
# Parameter hash
#
########################################################################################

sub NT5000_GetYear ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my ($ln,$lf,$ret,$monn,$daten,$mex,$mmex,$value);

  my ($sec,$min,$hour,$dayn,$month,$year,$wday,$yday,$isdst) = localtime(time);
  my $yearn = $year+1900;

  #-- Obtain the yearly reading
  my $result = NT5000_GetLine($hash, "year");
  $result =~ s/^.*Y://;
  $result =~ s/[\r\n ]//g;   
  Log GetLogLevel($name,3), "NT5000 yearly result = $result";
  $result=~ s/,/./g;
  my @data = split(";", $result);
  
  #-- Expected yield for year
  my $wex  = $attr{$name}{Wx_Y};
  my $wac  = 0;
  my $wre;
  my $wme = 0;
  my $wrm;

  my @names = ("W_M01","W_M02","W_M03","W_M04","W_M05","W_M06","W_M07","W_M08","W_M09","W_M10",
  "W_M11","W_M12");

  #-- Check current logfile 
  $ln = $attr{$name}{"LogY"};
  if( !(defined($ln))){
    Log 1,"NT5000_GetYear: Attribute LogY is missing";
    #-- here some other output of yearly data
  } else {
    $lf = $defs{$ln}{currentlogfile};
    $ret  = open(NT5000FILE, "> $lf" );
    if( $ret) {
      print NT5000FILE "yearly data:               Month Wm    Wex Wy     Wy \n";
      for(my $i = 0; $i <= $month; $i++) {
        $monn  = $i+1;
        #-- for current month actual time, otherwise dummy time
        if( $i == $month ){
          $daten = sprintf("%4d-%02d-28_%02d:%02d:%02d",$yearn,$monn,$hour,$min,$sec);
        }else{
          $daten = sprintf("%4d-%02d-28_23:59:00",$yearn,$monn);
        }
        $mex  = "Wx_M".($monn);
        $mmex  = $attr{$name}{$mex};
        $wme += $mmex;
        $wac  += $data[$month+1-$i];
        #-- relative total
        if( $wex ){ 
          $wre  = int(1000.0*$wac/$wex)/10 if ($wex > 0);
        };
        #-- relative expected
        if( $wme ){ 
          $wrm  = int(1000.0*$wac/$wme)/10 if ($wme > 0);
        };
        # Put one item per line into the log file
        printf NT5000FILE "%s %s %5s %5.1f %3d %6.1f %5.1f %6.1f %5.1f\n",$daten,$name,$names[$i],$data[$month+1-$i],$mmex,$wac,$wre,$wme,$wrm;
      }
      Log 1,"NT5000_GetYear: File $lf overwritten"; 
      close(NT5000FILE);    
       #-- store value 
      $hash->{year}->[0]=$wac;
      $hash->{year}->[1]=$wex;
      $hash->{year}->[2]=$wre;
      $hash->{year}->[3]=$wme;
      $hash->{year}->[4]=$wrm;
      #-- return value 
      $value  = "\nWy ".$wac." kWh (yearly sum until now)\n";
      $value .= $wrm."% of expected ".$wme." kWh\n";
      $value .= $wre."% of total ".$wex." kWh";
      return $value;       
    } else {
      Log 1,"NT5000_GetYear: Cannot open $lf for writing!"; 
      return undef;
    }
  }
}

########################################################################################
#
# NT5000_GetLine - Read data from inverter
# 
# Parameter hash, a = string parameter to define what will be asked
#
########################################################################################

sub NT5000_GetLine ($$) {
  my ($hash,$a) = @_;
  my $name = $hash->{NAME};

  return "NT5000_GetLine: Unknown argument $a, choose one of " . join(",", sort keys %gets)
   if(!defined($gets{$a}));

  my $dev = $hash->{DeviceName};

  #-- Inverter data
  my $rError   = "\x00\x01\x01\x01"; 
  my $rOnline1 = "\x00\x01\x02\x01"; 
  my $rMon1    = "\x00\x01\x03\x01"; 
  my $rYear1   = "\x00\x01\x04\x01"; 
  my $rTime    = "\x00\x01\x06\x01"; 
  my $rSerial  = "\x00\x01\x08\x01"; 
  my $rProFW   = "\x00\x01\x09\x01"; 
  my $sYY      = "\x00\x01\x50"; 
  my $sLL      = "\x00\x01\x51"; 
  my $sDD      = "\x00\x01\x52"; 
  my $sHH      = "\x00\x01\x53"; 
  my $sMM      = "\x00\x01\x54"; 

  my @invBuffer;

  #------------------------ current readings -------------------------------------
  if( $a eq "reading" )
    {
    #Log 3, "Asking for online data";
    my $invReturn = NT5000_5to13($hash,$dev,$rOnline1);
    #-- test if this is an offline case
    if( !($invReturn) )
      {
      return undef;
      }
    @invBuffer=split(//,$invReturn);
    #-- test again if this is an offline case
    if( @invBuffer < 13 )
      {
      return undef;
      }
    #-- Process data 
    my $udc = ord($invBuffer[0])*2.8+100;  
    my $idc = ord($invBuffer[1])*0.08;        
    my $uac = ord($invBuffer[2])+100.0;  
    my $iac = ord($invBuffer[3])*0.120;       
    my $t   = ord($invBuffer[4])-40.0;
    my $s   = ord($invBuffer[5])*6.0;
    my $pdc = int($udc*$idc)/1000;
    my $pac = int($uac*$iac)/1000; 
    my $wd  = (ord($invBuffer[6])* 256 + ord($invBuffer[7]))/1000;         
    my $wtot= ord($invBuffer[8])* 256 + ord($invBuffer[9]); 
    #-- Calculate eta
    my $name= $hash->{NAME};
    my $a   = $attr{$name}{Area};
    my $eta;
    if ( $s && $a ) {
      if( ($a>0)&&($s>0) ) {
        $eta  = int(100000*$pac/($s*$a))/100;
      } else {
        $eta  = 0;
      };
    } else {
      $eta=0;
    }
    return sprintf "%3.1f %2.2f %1.3f %3.1f %2.2f %1.3f %2.0f %4.0f %2.3f %5.1f %1.2f",
      $udc,$idc,$pdc,$uac,$iac,$pac,$t,$s,$wd,$wtot,$eta;
#------------------------ montly readings -------------------------------------
  } elsif( $a eq "month" ) { 
    my $i=1;
    #-- Get the first block anyhow 
    my $ica=$i%256;
    my $cmd2=sprintf("%s%c",substr($rMon1,0,3),$ica);
    my $invReturn = NT5000_5to13($hash,$dev,$cmd2);
     #-- test if this is an offline case
    if( !($invReturn) ){
      return undef;
    }
    @invBuffer=split(//,$invReturn);
    #-- test again if this is an offline case
    if( @invBuffer < 13 ) {
      return undef;
    }
    #-- Process data 
    my $day = ord($invBuffer[1]);  
    my $result="M:$day;";
    for( my $j=0; $j<3; $j++ ) {
      $result .= ((ord($invBuffer[2+4*$j])* 256 + ord($invBuffer[3+4*$j]))/1000).";" if( ($day-$j) > 0); 
    }
    #-- Get further blocks if necessary
    for( $i=2; $i<=($day+2)/3; $i++) {    
      $ica=$i%256;
      $cmd2=sprintf("%s%c",substr($rMon1,0,3),$ica);
      $invReturn = NT5000_5to13($hash,$dev,$cmd2);
      #-- test if this is an offline case
      if( !($invReturn) )   {
        return undef;
      }
      @invBuffer=split(//,$invReturn);
      #-- test again if this is an offline case
      if( @invBuffer < 13 ) {
        return undef;
      }
      for( my $j=0; $j<3; $j++ )  {
        $result .= ((ord($invBuffer[2+4*$j])* 256 + ord($invBuffer[3+4*$j]))/1000).";" if( ($day-($i-1)*3-$j) > 0); 
      }
    };
    return "$result\n";
#------------------------ yearly readings -------------------------------------
  } elsif( $a eq "year" ) { 
    my $i=1;
    #-- We read the full data, e.g. current month (cm) .. cm-12
    my @pmval;
    #-- Get the first block
    my $ica=$i%256;
    my $cmd2=sprintf("%s%c",substr($rYear1,0,3),$ica);
    my $invReturn = NT5000_5to13($hash,$dev,$cmd2);
    #-- test if this is an offline case
    if( !($invReturn) )  {
      return undef;
    }
    @invBuffer=split(//,$invReturn);
    #-- test again if this is an offline case
    if( @invBuffer < 13 ) {
      return undef;
    }
    #-- Process data for current month (cm) .. cm-4
    my $month  = ord($invBuffer[1]);  
    for( my $j=0; $j<5; $j++ ) {
      #-- value for pseudo-month
      push(@pmval,(ord($invBuffer[2+2*$j])* 256 + ord($invBuffer[3+2*$j]))/10);
    }
    #-- Get the second block
    $i++;
    $ica=$i%256;
    $cmd2=sprintf("%s%c",substr($rYear1,0,3),$ica);
    $invReturn = NT5000_5to13($hash,$dev,$cmd2);
    #-- test if this is an offline case
    if( !($invReturn) ) {
      return undef;
    }
    @invBuffer=split(//,$invReturn);
    #-- test again if this is an offline case
    if( @invBuffer < 13 ) {
      return undef;
    }
    #-- Process data for cm-5 .. cm-10 
    for( my $j=0; $j<6; $j++ ) {
       #-- value for pseudo-month
      push(@pmval,(ord($invBuffer[2*$j])* 256 + ord($invBuffer[1+2*$j]))/10);
    };
    #-- Get the third block
    $i++;
    $ica=$i%256;
    $cmd2=sprintf("%s%c",substr($rYear1,0,3),$ica);
    $invReturn = NT5000_5to13($hash,$dev,$cmd2);
    #-- test if this is an offline case
    if( !($invReturn) ) {
      return undef;
    }
    @invBuffer=split(//,$invReturn);
    #-- test again if this is an offline case
    if( @invBuffer < 13 ) {
      return undef;
    }
    #-- Process data for cm-11 .. cm-12
    for( my $j=0; $j<2; $j++ ) {
      #-- value for pseudo-month
      push(@pmval,(ord($invBuffer[2*$j])* 256 + ord($invBuffer[1+2*$j]))/10);
    };
    #-- Now we have to correct for those erroneous jumps of the internal data logger
    #   of the NT5000   
    #   The first one is never wrong, belongs to the current month
    my @val    = ($pmval[0]);
    my $result;
    #   which and how many pseudo-month-entries do we have ?
    my $merr   = $attr{$name}{MERR};
    # none, we my return HERE
    if( !defined($merr) )  {
      @val= ($pmval[0]);
      for( my $j=1; $j<=$month; $j++ ){
         push(@val,$pmval[$j]);
      }
      $result = "Y:$month;".join(';',@val);
      return $result;
    };
    # oops, correction has to be done 
    my @merrs  = split(',',$merr);
    my $merrno = @merrs;
    #-- For the year we therefore need the first $month+$merrno entries

    my $pm;
    my $mlim   = $month+$merrno;
    for( my $j=1; $j<$mlim; $j++ ) {
      $pm = $month-$j;
      my $listed = 0;
      #-- check if this is in the list
      for( my $k=0; $k<$merrno; $k++ ) {
        # yes, it is
        if( $merrs[$k]==$pm ) {  
          $listed = 1;
        }
      }
      # yes, it is indeed
      if( $listed==1) {
        # add data to the last entry in @val
        $val[@val-1]+=$pmval[$j];
        # no, it is not
      } else {
        # append value to array
        push(@val,$pmval[$j]);
      }
    };
    #-- Compare the results
    #Log 3, "YEAR PSEUDO ".join(';',@pmval);
    #Log 3, "YEAR CORR ".join(';',@val);
    $result = "Y:$month;".join(';',@val);
    return $result;
  }elsif( $a eq "serial" ) {
    my $r1 = NT5000_5to13($hash,$dev,$rSerial);
    return "S:".substr($r1,0,12)."\n"
  }elsif( $a eq "proto" ){
    my $r1 = NT5000_5to13($hash,$dev,$rProFW);
    return "P:".substr($r1,0,6)."\n"
  }else {
    print "OHOH => NT5000_GetLine mit Argument $a\n"; 
  }
}

########################################################################################
#
# NT5000_5to13 - Read 13 bytes from the inverter or the emulator
# 
# Parameter: hash,dev = none,emulator or a serial port definition
#            cmd = 5  byte parameter to query the device properly
#
########################################################################################
sub NT5000_5to13($$$) {

my $retry = 0;
my ($hash,$dev,$cmd) = @_;

my $result;
my ($i,$j,$k);

if( $dev eq "none" ) #no inverter attached
  {
    return "\x00\x01\x02\x03\x04\x05\x06\x07\x07\x09\x0a\x0b\x0c";
  #-- read from emulator
  } elsif ( $dev eq "emulator" ) {
    my $CS = unpack("%32C*", $cmd);
    $CS=$CS%256;
    my $cmd2=sprintf("%s%c",$cmd,$CS);
    my $result = NT5000_emu(5,$cmd);
    return($result);
  #-- here we do the real thing
  } else { 
    my $serport = new Device::SerialPort ($dev);
    if(!$serport) {
      Log 1, "NT5000: Can't open $dev: $!";
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
    my $CS = unpack("%32C*", $cmd);
    $CS=$CS%256;
    my $cmd2=sprintf("%s%c",$cmd,$CS);
    my $count_out = $serport->write($cmd2);
    Log 3, "NT5000 write failed\n"         unless ($count_out);
    Log 3, "NT5000 write incomplete $count_out ne ".(length($cmd2))."\n"     if ( $count_out != 5 );;
    #-- sleeping 0.05 seconds
    select(undef,undef,undef,0.05);
    my ($count_in, $string_in) = $serport->read(13);
    #-- sleeping 0.05 seconds
    select(undef,undef,undef,0.05);
    $serport->close();
    return($string_in);
  }

}

########################################################################################
#
# NT5000_emu - Emulator section - to be used, if the real solar inverter is not attached.
#
########################################################################################

sub NT5000_emu {
#-- For configuration purpose: when does the sun come up, and when does it go down
my $start = 6 + 55.0/60;
my $stop  = 21 + 31.0/60;

#-- Inverter data

my $rError   = "\x00\x01\x01\x01"; 
my $rOnline1 = "\x00\x01\x02\x01"; 
my $rMon1    = "\x00\x01\x03\x01"; 
my $rYear1   = "\x00\x01\x04\x01"; 
my $rTime    = "\x00\x01\x06\x01"; 
my $rSerial  = "\x00\x01\x08\x01"; 
my $rProFW   = "\x00\x01\x09\x01"; 
my $sYY      = "\x00\x01\x50"; 
my $sLL      = "\x00\x01\x51"; 
my $sDD      = "\x00\x01\x52"; 
my $sHH      = "\x00\x01\x53"; 
my $sMM      = "\x00\x01\x54"; 

#-- Timer data
my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);

#-- parse incoming parameters 
my ($count,$buf1)=@_;
   
#-- default: do not send data   
my $senddata=0;
my ($i,$j,$k);
my (@buf3,@buf3a);

#-- No bytes received
if( $count == 0) 
  {
  Log 3, "[NT5000 emulator] Zero bytes received, count=0";
  return undef;
  }
#-- no sun yet  
if( (($hour+$min/60.0-$start)<0) || (($stop-$hour-$min/60.0)<0) )
  {
     Log 3, "[NT5000 emulator] No Sun !";
     return undef;
  }
#-- 5 bytes received
elsif( $count == 5)
  {  
  my $buf2 = substr($buf1,0,4);
  my $buf4 = substr($buf1,0,3);

  #---- Error
  if( $buf2 eq $rError )
    {
    Log 3, "[NT5000 emulator] Request for error list received";
    my @buf3=($year,$month,$day,$hour,
      $min,0,0,0,0,0,0,0);
    $senddata=1; 
	}    
	
  #---- Online block 1
  elsif( $buf2 eq $rOnline1 )
	{
	 #Log 3 "[NT5000 mulator] Request for online data block 1 received";
	 my ($wd,$wdl,$wdh,$wtot,$wtotl,$wtoth,$uac,$udc,$iac,$idc,$pac,$t,$s)=(0,0,0,0,0,0,0,0,0,0,0,0,0);
	#-- shift into full day
    my $q = ($hour+$min/60.0-$start)/($stop-$start);
    if( ($q>0) && ($q<1.0) )
      {
      #-- produce fake data
      $wd= int( 4500/3.14*($stop-$start)*(1-cos($q*3.14)) );
      $wdl=$wd%256;
      $wdh=int(($wd-$wdl)/256);
      $wtot=1000+int($wd/1000);
      $wtotl=$wtot%256;
      $wtoth=int(($wtot-$wtotl)/256);

      $uac=int( 230-100 + 0.5 );
      $udc=int( (600-100)/2.8 + 0.5 );  
      $iac=int( 4500/230*sin($q * 3.14)/0.12 + 0.5 );
      $idc=int( 4550/600*sin($q * 3.14)/0.08 + 0.5 );		 

      $pac=int(4500*sin($q*3.14))/1000.0;

      $t=10+40;
      $s=int(100/6);
	  }
	@buf3=($udc,$idc,$uac,$iac,$t,$s,$wdh,$wdl,$wtoth,$wtotl,0,0);
    $senddata=1;
	}    
	
	 #---- Monthly data block
  elsif( substr($buf2,0,3) eq substr($rMon1,0,3) )
	{
	 my $ica     = substr($buf2,3,1);
	 my $blocknr = ord($ica)%16;
	 # Log 3, "[NT5000 emulator] Request for monthly data block $blocknr received";
	 my ($mon1,$day1,$wdh1,$wdl1,$mon2,$day2,$wdh2,$wdl2,$mon3,$day3,$wdh3,$wdl3)=(0,0,0,0,0,0,0,0,0,0,0,0,0);

      #-- produce fake data
      $mon1 = $month;
      $day1 = $day+3-$blocknr*3;
      my $wd      = (19.001 + 2*($day1 % 2))*1000.0;
      $wdl1 = $wd%256;
      $wdh1 = int(($wd-$wdl1)/256);
      $mon2 = $mon1;
      $day2 = $day1-1;
      if( $day2 < 1 )
        {
        $mon2-- if($mon2 > 0);
        $day2 = 31;
        }
      $wd   = (19.001 + 2*($day2 % 2))*1000.0;
      $wdl2 = ($wd)%256;
      $wdh2 = int(($wd-$wdl2)/256);
      $mon3 = $mon2;
      $day3 = $day2-1;
      if( $day3 < 1 )
        {
        $mon3-- if($mon3 > 0);
        $day3 = 31;
        }
      $wd   = (19.001 + 2*($day3 % 2))*1000.0;
      $wdl3=$wd%256;
      $wdh3=int(($wd-$wdl3)/256);
    
	@buf3=($mon1,$day1,$wdh1,$wdl1,$mon2,$day2,$wdh2,$wdl2,$mon3,$day3,$wdh3,$wdl3);
    $senddata=1;
	}   
	
  #---- Yearly data block
  elsif( substr($buf2,0,3) eq substr($rYear1,0,3) )
	{
	 my $ica     = substr($buf2,3,1);
	 my $blocknr = ord($ica)%16;
	 Log 3, "[NT5000 emulator] Request for yearly data block $blocknr received";
	 my ($wmh1,$wml1,$wmh2,$wml2,$wmh3,$wml3,$wmh4,$wml4,$wmh5,$wml5)=(0,0,0,0,0,0,0,0,0,0);
	 my @pwm=(1500,2500,3500,4500,6000,6000,6000,6000,4500,3500,2500,1500);

      #-- produce fake data
      my $ip;
      @buf3=(0,0,0,0,0,0,0,0,0,0,0,0);
      if( $blocknr==1){
      $buf3[1]=$month;
         for( my $i=0;$i<5;$i++)
            {
            my $ip=$month-$i;
            if( $ip<0 ) 
               {
               $ip += 12;
               };
            my $wd=$pwm[$ip];
            my $wdl = ($wd)%256;
            my $wdh = int(($wd-$wdl)/256);
            $buf3[2*$i+2]=$wdh;
            $buf3[2*$i+3]=$wdl;
            }
      }elsif( $blocknr==2){
         for( my $i=0;$i<6;$i++)
            {
            my $ip=$month-5-$i;
            if( $ip<0 ) 
               {
               $ip += 12;
               };
            my $wd=$pwm[$ip];
            my $wdl = ($wd)%256;
            my $wdh = int(($wd-$wdl)/256);
            $buf3[2*$i]=$wdh;
            $buf3[2*$i+1]=$wdl;
            }
      }else{
         for( my $i=0;$i<2;$i++)
            {
            my $ip=$month-11-$i;
            if( $ip<0 ) 
               {
               $ip += 12;
               };
            my $wd=$pwm[$ip];
            my $wdl = ($wd)%256;
            my $wdh = int(($wd-$wdl)/256);
            $buf3[2*$i]=$wdh;
            $buf3[2*$i+1]=$wdl;
            }
      }
    $senddata=1;
	}   

  #---- Time data
  elsif( $buf2 eq $rTime )
	{
    Log 3, "[NT5000 emulator] Request for time data received";
	@buf3=($year,$month,$day,$hour,
	   $min,0,0,0,0,0,0,0,0);
    $senddata=1; 
	} 
         
  #----  Serial number
  elsif( $buf2 eq $rSerial )
    {
	Log 3, "[NT5000 emulator] Request for serial number received";
	@buf3  = (ord('1'),ord('5'),ord('3'),ord('3'),ord('A'),ord('5'),ord('0'),ord('1'),ord('2'),ord('3'),ord('4'),ord('5'));
    $senddata=1; 
	}    

  #---- Protocol and Firmware
  elsif( $buf2 eq $rProFW )
    {
    Log 3, "[NT5000 emulator] Request for protocol version received";
	@buf3=(ord('1'),ord('1'),ord('1'),ord('-'),ord('2'),ord('3'),0,0,0,0,0,0);
    $senddata=1; 
	}    
  #---- Set year
  elsif( $buf4 eq $sYY )
	{
    $year=ord(substr($buf2,3,1));
    Log 3, "[NT5000 eulator] Setting year to $year";
    }       
  #---- Set month
  elsif( $buf4 eq $sLL )
    {
    $month=ord(substr($buf2,3,1));
    Log 3, "[NT5000 emulator] Setting month to $month";
    }      
  #---- Set day
  elsif( $buf4 eq $sDD )
	{         
    $day=ord(substr($buf2,3,1));
    Log 3, "[NT5000 emulator] Setting day to $day";
    } 
  #---- Set hour
  elsif( $buf4 eq $sHH )
	 {
     $hour=ord(substr($buf2,3,1))-1;
     Log 3, "[NT5000 emulator] Setting hour to $hour";
     }           
  #---- Set minute
  elsif( $buf4 eq $sMM )
	 {
     $min=ord(substr($buf2,3,1))-1;
     Log 3, "[NT5000 emulator] Setting minute to $min";
     }
  #---- show content
  else 
     {
     Log 3, "[NT5000 emulator] Unknown request of 5 bytes received";
     for($i=0;$i<5;$i++)
       {  $j=int(ord(substr($buf2,$i,1))/16);
          $k=ord(substr($buf2,$i,1))%16;
	      print "byte $i = 0x$j$k\n";
	   }
	 }
  #---- Other number of bytes received
  } else
    {
    Log 3, "[NT5000 emulator] $count bytes received";
    for($i=0;$i<$count;$i++)
	  {  $j=int(ord(substr($buf1,$i,1))/16);
         $k=ord(substr($buf1,$i,1))%16;
	     print "byte $i = 0x$j$k\n";
	  }
    }
  #-- Here we are really sending data back to the main program
  if( $senddata==1 ) {
    #-- calculate checksum
    my $CS=0;
    for($i=0,$i<=11,$i++)
    {
       $CS+=$buf3[$i];
    }
    $CS=$CS%256;
    my $data = sprintf("%c%c%c%c%c%c%c%c%c%c%c%c%c",
		      $buf3[0],$buf3[1],$buf3[2],$buf3[3],
		      $buf3[4],$buf3[5],$buf3[6],$buf3[7],
		      $buf3[8],$buf3[9],$buf3[10],$buf3[11],$CS);
		           
	#-- control
	#print "Sending out:";
    #for($i=0;$i<13;$i++)
	#  {  $j=int(ord(substr($data,$i,1))/16);
    #     $k=ord(substr($data,$i,1))%16;
	#     print "byte $i = 0x$j$k\n";
	#  }
	$senddata=0;
    return($data);
   } 
   else 
   {
     return undef;
   }
}

1;


=pod
=begin html

<a name="NT5000"></a>
        <h3>NT5000</h3>
        <p>FHEM module to commmunicate with a Sunways NT5000 solar inverter<br />
        </p>
        <h4>Example</h4>
        <p>
            <code>define nt5000 NT5000 /dev/ttyUSB0 </code>
        </p><br />   
        <a name="NT5000define"></a>
        <h4>Define</h4>
        <p>
        <code>define &lt;name&gt; NT5000  &lt;device&gt; </code> 
        <br /><br /> Define a NT5000 solar inverter</p>
        <ul>
          <li>
            <code>&lt;name&gt;</code>
           Serial device port or the keyword <code>emulator</code>. In the latter case, a 4.5 kWP solar installation is simulated
         </li>
        </ul>
        <a name="NT5000set"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="nt5000_time">
                   Not yet implemented</a></li>
        </ul>
        <br />
        <a name="NT5000get"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="nt5000_reading">
                    <code>get &lt;name&gt; reading</code></a>
                <br /> read all current data </li>
            <li><a name="nt5000_month">
                    <code>get &lt;name&gt; month</code></a>
                <br /> read all data from current month </li>
            <li><a name="nt5000_year">
                    <code>get &lt;name&gt; year</code></a>
                <br /> read all data from current year </li>
            <li><a name="nt5000_present">
                    <code>get &lt;name&gt; present</code></a>
                <br /> 1 if device present, 0 if not </li>
            <li><a name="nt5000_serial">
                    <code>get &lt;name&gt; serial</code></a>
                <br /> inverter serial number </li>
            <li><a name="nt5000_proto">
                    <code>get &lt;name&gt; proto</code></a>
                <br /> inverter protocol </li>
        </ul>
        <br />
        <a name="NT5000attr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="nt5000_Area"><code>attr &lt;name&gt; Area &lt;float&gt;</code>
                </a>
                <br />Effective area [m<sup>2</sup>] of the installation</li>
            <li><a name="nt5000_PSP"><code>attr &lt;name&gt; PSP &lt;float&gt;</code>
                </a>
                <br />Peak Solar Power [kW] of the installation</li>
            <li><a name="nt5000_Wx_M"><code>attr &lt;name&gt; Wx_M&lt;n&gt; &lt;float&gt;</code>
                </a>
                <br />Expected yield [kWh] for month &lt;n&gt;=1...12</li>
            <li><a name="nt5000_Wx_Y"><code>attr &lt;name&gt; Wx_Y &lt;float&gt;</code>
                </a>
                <br />Expected yield [kWh] for a full year</li>
            <li><a name="nt5000_MERR"><code>attr &lt;name&gt; MERR &lt;list&gt;</code>
                </a>
                <br />List of months with erroneous logging, see lines 83ff</li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a
                    href="#stateFormat">stateFormat</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
        
=end html
=cut

