########################################################################################
#
# 15_EMX.pm MUST be saved as 15_CUL_EM.pm !!!
#
# FHEM module to read the data from an EM1000 WZ/EM/GZ power sensor 
#
# Version 1.1 - February, 2013
#
# Prof. Dr. Peter A. Henning, 2011
#
#----------------------------------------------------------------------------------------------------
# 
# Setup as:
# define  <emx> EMX <code> <rpunit>
#    
# where 
#   <name>    may be replaced by any name string 
#   <code>    is a number 1 - 12 or the keyword "emulator".
#   <rpunit>  is the scale factor = rotations per kWh or m^3 (not needed for emulator)
#
# get <name> midnight => todays starting value for counter
# get <name> month    => summary of current month
#   
# Attributes are set as
#
#  Monthly and yearly log file
#  attr    emx LogM EnergyM
#  attr    emx LogY EnergyY
#
#  Basic fee per Month (€ per Month)
#  attr    emx CostM
#
#  Cost rate during daytime (€ per kWh) 
#  attr    emx CrateD      <cost rate in €/unit>
#  
#  Start and end of daytime cost rate - optional
#  attr    emx CrateDStart <time as hh:mm>
#  attr    emx CrateDEnd   <time as hh:mm>
#  
#  Cost rate during nighttime (cost per unit) - only if needed
#  attr    emx CrateN      <cost rate in €/unit>
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

my %gets = (
  "midnight"    => "",
  "month"       => ""
);

my %sets = (
  "meter"     => "M",
  "midnight"  => "T"
);

#-- Global variables for the raw readings
my $emx_seqno; #  number of received datagram in sequence, runs from 2 to 255
my $emx_cnt;   #  current count from device. This value has an arbitrary offset at each start of the device
my $emx_5min;  #  count during last 5 min interval  
my $emx_peak;  #  peak count during last 5 min interval

#--Forward definition
sub EMX_Parse($$);

########################################################################################
#
# EMX_Initialize 
#
########################################################################################

#-- stub function for CUL_EM replacement

sub CUL_EM_Initialize ($) {
  my ($hash) = @_;
  
  return EMX_Initialize ($hash);
}
 
#-- real initialization function 
sub EMX_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}     = "EMX_Define";
  $hash->{UndefFn}   = "EMX_Undef";
  $hash->{ParseFn}   = "EMX_Parse";
  $hash->{SetFn}     = "EMX_Set";
  $hash->{GetFn}     = "EMX_Get";
  $hash->{Match}     = "^E0.................\$";

  $hash->{AttrList}  = "IODev " .
                       "model:EMEM,EMWZ,EMGZ loglevel LogM LogY CrateD CrateDStart CrateDEnd CrateN CostM ".
                       $readingFnAttributes;
}

########################################################################################
#
# EMX_Define - Implements DefFn function
#
# Parameter hash, definition string
#
########################################################################################

sub EMX_Define ($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> EMX <code> <rpunit>"
            if(int(@a) < 3 || int(@a) > 4);
            
  my $name = $a[0];
            
  #-- emulator mode ------------------------------------------------------------
  if( $a[2] eq "emulator") {
    $hash->{CODE} = "emulator";
    Log 1, "EMX with emulator mode";
    
    #-- counts per unit etc.
    $hash->{READINGS}{"reading"}{FACTOR}  =  150;
    $hash->{READINGS}{"reading"}{UNIT}    = "Kilowattstunden";
    $hash->{READINGS}{"reading"}{UNITABBR}= "kWh";
    $hash->{READINGS}{"rate"}{PERIOD}     = "h";
    $hash->{READINGS}{"rate"}{UNIT}       = "Kilowatt";
    $hash->{READINGS}{"rate"}{UNITABBR}   = "kW";
    CommandAttr(undef,"$name model emulator"); 

    #-- set/ get artificial data
    my $msg=EMX_emu(0,12345);
    $hash->{READINGS}{"count"}{midnight}=12345;
    EMX_store($hash);
    $hash->{emumsg}=$msg;
    
    $modules{EMX}{defptr}{0} = $hash;

    # Call emulator in 15 seconds again, and then cyclic repetition
    InternalTimer(gettimeofday()+15, "EMX_Parse", $hash, 0);
    
  } else {
  #-- Real device definition -----------------------------------------------------
    return "EMX_Define $a[0]: wrong CODE format: valid is 1-12 or \"emulator\""
      if(  $a[2] !~ m/^\d+$/ || $a[2] < 1 || $a[2] > 12  );   
    $hash->{CODE} = $a[2];
    
    #-- TODO: check for consistency of attributes !
    
    
    #--counts per unit etc.
    if($a[2] >= 1 && $a[2] <= 4) {          # EMWZ      
       $hash->{READINGS}{"reading"}{FACTOR}   = $a[3]; 
       $hash->{READINGS}{"reading"}{UNIT}     = "Kilowattstunden";
       $hash->{READINGS}{"reading"}{UNITABBR} = "kWh";
       $hash->{READINGS}{"rate"}{PERIOD}    = "h";
       $hash->{READINGS}{"rate"}{UNIT}      = "Kilowatt";
       $hash->{READINGS}{"rate"}{UNITABBR}  = "kW";
       CommandAttr (undef,"$name model EMWZ"); 
    } elsif($a[2] >= 5 && $a[2] <= 8) {     # EMEM
       $hash->{READINGS}{"reading"}{FACTOR}   = $a[3];
       $hash->{READINGS}{"reading"}{UNIT}     = "Kilowattstunden";
       $hash->{READINGS}{"reading"}{UNITABBR} = "kWh";
       $hash->{READINGS}{"rate"}{PERIOD}    = "h";
       $hash->{READINGS}{"rate"}{UNIT}      = "Kilowatt";
       $hash->{READINGS}{"rate"}{UNITABBR}  = "kW";
       CommandAttr (undef,"$name model EMEM"); 
    } elsif($a[2] >= 9 && $a[2] <= 12) {    # EMGZ
       $hash->{READINGS}{"reading"}{FACTOR}   = $a[3];
       $hash->{READINGS}{"reading"}{UNIT}     = "Kubikmeter";
       $hash->{READINGS}{"reading"}{UNITABBR} = "m^3";
       $hash->{READINGS}{"rate"}{PERIOD}    = "h";
       $hash->{READINGS}{"rate"}{UNIT}      = "Kubikmeter/Stunde";
       $hash->{READINGS}{"rate"}{UNITABBR}  = "m^3/h";
       CommandAttr (undef,"$name model EMGZ"); 
    }

    #-- Couple to I/O device
    $modules{EMX}{defptr}{$a[2]} = $hash;
    AssignIoPort($hash);   
  }    
   
  readingsSingleUpdate($hash,"state","defined",1);
  Log 3, "EMX: Device $name defined."; 
  #-- Start timer for initialization in a few seconds
  InternalTimer(time()+3, "EMX_InitializeDevice", $hash, 0);
  return undef;
}

########################################################################################
#
# EMX_InitializeDevice -  Sets up the device after start
#
# Parameter hash
#
########################################################################################

sub EMX_InitializeDevice ($) {
  my ($hash) = @_;

  my $ret;

  my $name = $hash->{NAME};
  Log 1,"EMX_InitializeDevice $name";

  #-- read starting value of the day
  $ret = EMX_recall($hash);
  Log 1, $ret
    if( defined($ret));
  return $ret
    if( defined($ret));
  
  return undef;
}

########################################################################################
#
# EMX_FormatValues -  Calculate display values
#
# Parameter hash
#
########################################################################################

sub EMX_FormatValues ($) {
  my ($hash) = @_;
  
  #Log 1," seqno $emx_seqno cnt $emx_cnt 5min $emx_5min peak $emx_peak";
  
  my $name    = $hash->{NAME}; 
  my ($model,$factor,$period,$unit,$runit,$midnight,$cval,$vval,$rval,$pval,$dval,$deltim,$delcnt,$msg);
  my ($svalue,$dvalue,$mvalue) = ("","","");
  my $cost;

  my ($sec, $min, $hour, $day, $month, $year, $wday,$yday,$isdst) = localtime(time);
  my ($seco,$mino,$houro,$dayo,$montho,$yearo,$dayrest);
  my $daybreak = 0;
  my $monthbreak = 0;
  
  #-- Check, whether we have a new "day" 
  #   emulator: less than 15 seconds from 5-minute period
  if( $hash->{CODE} eq "emulator"){
    $deltim = $min%5+$sec/60.0 - 4.75;
    if( $deltim>0 ){
      $yearo  = $year+1900;
      $montho = $month;
      $dayo   = $day."-".$hour."-".$min."-".$sec;
      $daybreak = 1;
      #-- Check, whether we have a new "month" = three 5 minute periods
      if( $min%15 == 0){
        $monthbreak = 1;
      }
    }
  # normal mode: less than 5 minutes from midnight
  }else {
    $deltim = $hour*60.0+$min+$sec/60.0 - 1435.0;
    if( $deltim>=0 ){
      $daybreak = 1;
      #-- Timer data from tomorrow
      my ($secn,$minn,$hourn,$dayn,$monthn,$yearn,$wdayn,$ydayn,$isdstn) = localtime(time() + 24*60*60);   
      #-- Check, whether we have a new month
      if( $dayn == 1 ){
        $monthbreak = 1;
      }
    }
  }
  
  $model    = $main::attr{$name}{"model"};
  $midnight = $hash->{READINGS}{"count"}{midnight};
  $factor   = $hash->{READINGS}{"reading"}{FACTOR};
  $unit     = $hash->{READINGS}{"reading"}{UNITABBR};
  $period   = $hash->{READINGS}{"rate"}{PERIOD};
  $runit    = $hash->{READINGS}{"rate"}{UNITABBR};
    
  my $emx_cnt_prev;
  my $emx_cnt_tim;  
    
  #-- skip some things if undefined
  if( $emx_cnt eq ""){
    $svalue =  "???";
  }else {     
    #-- put into READINGS
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"count",$emx_cnt);
    $svalue = "raw $emx_cnt";
    
    #-- get the old values (raw counts, always integer)
    $emx_cnt_prev = $hash->{READINGS}{"count"}{VAL};
    $emx_cnt_tim  = $hash->{READINGS}{"count"}{TIME};
    $emx_cnt_tim = "" if(!defined($emx_cnt_tim));

    #-- safeguard against the case where no previous measurement
    if( length($emx_cnt_tim) > 0 ){    
    
      #-- correct counter wraparound since last reading
      if( $emx_cnt < $emx_cnt_prev) {
         $emx_cnt_prev -= 65536;
      }
      #-- correct counter wraparound since last day
      if( $emx_cnt < $midnight) {
         $midnight -= 65536;
      }
  
      #--  For this calculation we could use either $emx_5min
      #   or ($emx_cnt - $emx_cnt_prev) since they are the same.
      my $delcnt      = ($emx_cnt-$emx_cnt_prev);
      
      #-- Extrapolate these values when a new day will be started (0<deltim<5)
      if( $daybreak==1 ) {
        $emx_cnt +=  $deltim /5.0 *$delcnt;
        $cval = $emx_cnt-$midnight; 
        #-- store corrected counter value at midnight 
        $hash->{READINGS}{"count"}{midnight} = $emx_cnt;
        EMX_store($hash);
      #-- no daybreak -> subtract only midnight count
      }else{
        $cval = $emx_cnt-$midnight; 
      }
      #-- Translate from device into physical units
      #   $factor = no. of counts per unit
      #   $emx_peak has to be divided by 20 = 60 min/ 5 min
      if( $model eq "EMWZ" ){
        $vval      = int($cval/$factor*1000)/1000;
        $rval      = int($emx_5min*12/$factor*1000)/1000;
        $pval      = int($emx_peak/($factor*20)*1000)/1000;
      } elsif( $model eq "EMEM" ){
        $vval      = int($cval/($factor*10)*1000)/1000;
        $rval      = int($emx_5min/$factor*1000)/1000;
        $pval      = int($emx_peak/($factor*20)*1000)/1000;
      } elsif( $model eq "EMGZ" ){
        $vval      = int($cval/$factor*1000)/1000;
        $rval      = int($emx_5min/$factor*1000)/1000;
        $pval      = int($emx_peak/($factor*20)*1000)/1000;
      } else {
        Log 3,"EMX: Wrong device model $model";
      }
      $svalue = sprintf("W: %5.2f %s P: %5.2f %s Pmax: %5.3f %s",$vval,$unit,$rval,$runit,$pval,$runit);
      #-- calculate cost
      if( defined($main::attr{$name}{"CrateD"}) ){
        #-- single rate counter
        if( !defined($main::attr{$name}{"CrateN"}) ){
          $cost = $vval*$main::attr{$name}{"CrateD"};
        #-- dual rate counter
        }else{
          #--determine period 1 = still night, 2 = day, 3 = night again
          my @crs=split(':',$main::attr{$name}{"CrateDStart"});
          my @crs=split(':',$main::attr{$name}{"CrateDEnd"});
          #-- period 1
          if ( ($hour<=$crs[0]) & ($min<$crs[1]) ){
          #-- period 2
          }elsif ( ($hour<=$crs[0]) & ($min<$crs[1]) ){
          #-- period 3
          }else{
          }
        }
      }
      
      #-- put into READING
      readingsBulkUpdate($hash,"reading",$vval);
      readingsBulkUpdate($hash,"rate",$rval);
      readingsBulkUpdate($hash,"peak",$pval);
      readingsBulkUpdate($hash,"cost",$cost);
 
      #-- Daily/monthly accumulated value
      if( $daybreak == 1 ){
        my @month = EMX_GetMonth($hash);
        my $total = $month[0]+$vval;
        $dvalue = sprintf("D_%02d Wd: %5.2f Wm: %6.2f",$day,$vval,$total);
        readingsBulkUpdate($hash,"day",$dvalue);
        if( $monthbreak == 1){
          $mvalue = sprintf("M_%02d Wm: %6.2f",$month,$total);
          readingsBulkUpdate($hash,"month",$mvalue);
          Log 1,$name." has monthbreak $msg ".$mvalue;
        }  
      }
    }
    #-- STATE
    readingsBulkUpdate($hash,"state",$svalue);
    readingsEndUpdate($hash,1); 
  }
}

########################################################################################
#
# EMX_Get -  Implements GetFn function
#
# Parameter hash, argument array
#
########################################################################################

sub EMX_Get ($@) {
my ($hash, @a) = @_;

#-- empty argument list
return join(" ", sort keys %gets) 
  if(@a < 2);

#-- check syntax
my $name = $hash->{NAME};
return "EMX_Get with unknown argument $a[1], choose one of " . join(" ", sort keys %gets)
  	if(!defined($gets{$a[1]}));

$name     = shift @a;
my $key   = shift @a;
my $value;
my $ret;
   
#-- midnight counter value 
if($key eq "midnight"){
   $value = $hash->{READINGS}{"count"}{midnight};
}  

#-- monthly summary 
if($key eq "month"){
   my @month  = EMX_GetMonth($hash);
   $value = "Wm ".$month[1]." kWh (av. ".$month[2]." kWh)";
}     

Log GetLogLevel($name,3), "EMX_Get => $key $value";  
return "EMX_Get => $key $value";
}

########################################################################################
#
# EMX_Set -  Implements SetFn function
#
# Parameter hash, argument array
#
########################################################################################

sub EMX_Set ($@) {
my ($hash, @a) = @_;

#-- empty argument list
return join(" ", sort keys %sets) 
  if(@a < 3);

#-- check syntax
return "EMX_Set needs at least two parameters" 
  if(@a < 3);
my $name = $hash->{NAME};
Log GetLogLevel($name,3), "EMX Set request $a[1] $a[2]"; 
return "EMX_Set with unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

$name     = shift @a;
my $key   = shift @a;
my $value = join("", @a);
my $tn = TimeNow();
my $ret;

#-- value of meter reading may be set at runtime
if($key eq "meter"){

}
   
#-- midnight counter value may be set at runtime
if($key eq "midnight"){
   return "EMX_Set: Wrong midnight value for counter, must be -65536 <= value < 65536"
     if( ($value < -65536) || ($value > 65535) );
   $hash->{READINGS}{"count"}{midnight}=$value;
   #-- store this for later usage
   $ret = EMX_store($hash);
   return "EMX_Set: ".$ret
     if( defined($ret) );
}     

Log GetLogLevel($name,3), "EMX_Set => $key $value";  
return "EMX_Set => $key $value";
}

########################################################################################
#
# EMX_Undef - Implements UndefFn function
#
# Parameter hash, name
#
########################################################################################

sub EMX_Undef ($$) {
  my ($hash, $name) = @_;
  delete($modules{EMX}{defptr}{$hash->{CODE}});
  return undef;
}

########################################################################################
#
# EMX_Parse -  Parse the message string send by CUL_EM
#
# Parameter hash, msg = message string
#
########################################################################################

sub EMX_Parse ($$) {
  my ($hash,$msg) = @_;
  
  if( !($msg) ) {
    $msg=$hash->{emumsg};
  }

  # 0123456789012345678
  # E01012471B80100B80B -> Type 01, Code 01, Cnt 10
  my @a = split("", $msg);
  my $tpe = ($a[1].$a[2])+0;
  my $cde = hex($a[3].$a[4]); 

  #-- emulator
  if( $cde eq "00"){
     $cde = "emulator";
  }
  
  #-- return, if the defice is undefided
  if( not($modules{EMX}{defptr}{$cde}) ){
     Log 1, "EMX detected, Code $cde";
     return "EMX_Parse: Undefined EMX_$cde EMX $cde";
  }

  my $def = $modules{EMX}{defptr}{$cde};
  $hash   = $def;
  my $name   = $hash->{NAME};
  return "" if(IsIgnored($name));

  $emx_seqno   = hex($a[5].$a[6]);
  $emx_cnt     = hex($a[ 9].$a[10].$a[ 7].$a[ 8]);
  $emx_5min    = hex($a[13].$a[14].$a[11].$a[12]);
  $emx_peak    = hex($a[17].$a[18].$a[15].$a[16]);
  EMX_FormatValues($hash);
    
  #-- emulator mode - must be triggered here since not received by CUL
  #   Call us in 15 seconds minutes again.
  if( $hash->{CODE} eq "emulator"){ 
     # Next sequence number
     $emx_seqno++;
     $emx_seqno =0 if($emx_seqno > 255);
       
     # Get artificial data
     my $msg=EMX_emu($emx_seqno, $emx_cnt);
     $hash->{emumsg}=$msg;
     
     #-- restart timer for updates
     RemoveInternalTimer($hash);
     InternalTimer(gettimeofday()+15, "EMX_Parse", $hash,1);
  }
  
  return $hash->{NAME};
}

########################################################################################
#
# Store daily start value in a file
#
# Parameter hash
#
########################################################################################

sub EMX_store($) {
  my ($hash) = @_;
  
  my $name = $hash->{NAME};
  my $mp   = AttrVal("global", "modpath", ".");
  my $ret  = open(EMXFILE, "> $mp/FHEM/EMX_$name.dat" );
  my $msg;
  if( $ret) {
    #-- Timer data
    my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);
    
    if( $hash->{CODE} eq "emulator"){
      $msg = sprintf "%4d-%02d-%02d %02d:%02d:%02d %02d",  $year+1900,$month,$day,$hour,$min,$sec,$hash->{READINGS}{"count"}{midnight}; 
    } else {
      $msg = sprintf "%4d-%02d-%02d midnight %d",$year+1900,$month,$day,$hash->{READINGS}{"count"}{midnight};
    }
    print EMXFILE $msg;
    Log 1, "EMX_store: $name $msg";
    close(EMXFILE);         
  } else {
    Log 1,"EMX_store: Cannot open EMX_$name.dat for writing!"; 
  }
  return undef;                   
}

########################################################################################
#
# Recall daily start value from a file
#
# Parameter hash
#
########################################################################################

sub EMX_recall($) {
  my ($hash) = @_;
  
  my $name= $hash->{NAME};
  my $mp  = AttrVal("global", "modpath", ".");
  my $ret = open(EMXFILE, "< $mp/FHEM/EMX_$name.dat" );
  my $msg;
  if( $ret ){
    my $line = readline EMXFILE;
    close(EMXFILE);      
    my @a=split(' ',$line);
    #-- Timer data from yesterday
    my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime(time() - 24*60*60);   
    $msg = sprintf "%4d-%02d-%02d",     $year+1900,$month,$day;
    if( $msg ne $a[0]){
      Log 1, "EMX_recall: midnight value $a[2] for $name not from last day, but from $a[0]";
      $hash->{READINGS}{"count"}{midnight}=$a[2];
    } else {
      Log 1, "EMX_recall: recalled midnight value $a[2] for $name";
      $hash->{READINGS}{"count"}{midnight} = $a[2]; 
    }
  } else {
    Log 1, "EMX_recall: Cannot open EMX_$name.dat for reading!";
    $hash->{READINGS}{"count"}{midnight}=0;
  }
  return undef;                    
}

########################################################################################
#
# Read monthly data from a file
#
# Parameter hash
#
# Returns total value up to last day, including this day and average including this day
#
########################################################################################

sub EMX_GetMonth($) {

  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $regexp = ".*$name.*";
  my @month;
  
  #-- Check current logfile 
  my $ln = $attr{$name}{"LogM"};
  if( !(defined($ln))){
    Log 1,"EMX_GetMonth: Attribute LogM is missing";
    return undef;
  } else {
    my $lf = $defs{$ln}{currentlogfile};
    my $ret  = open(EMXFILE, "< $lf" );
    if( $ret) {
      while( <EMXFILE> ){
        #-- line looks like 
        #   2013-02-09_23:59:31 <name> day D_09 Wd:  0.00 Wm: 171.70

        my $line = $_;
        chomp($line);
        if ( $line =~ m/$regexp/i){  
          my @linarr = split(' ',$line);
          my $day = $linarr[3];
          $day =~ s/D_0+//;
          my $val = $linarr[5];
          push(@month,$val);
        }
      }
    }
    #-- sum and average
    my $total = 0.0;
    foreach(@month){
      $total +=$_;
    }
    #-- add data from current day
    $total = int($total*100)/100;
    my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);
    my $deltim = ($hour+$min/60.0 + $sec/3600.0)/24.0;
    my $total2 = int(100*($total+$hash->{READINGS}{"reading"}{VAL}))/100;
    my $av = int(100*$total2/(int(@month)+$deltim))/100;
    
    return ($total,$total2,$av);
  } 
}

########################################################################################
#
# Emulator section - to be used, if the real device is not attached.
#
########################################################################################

sub EMX_emu ($$) {

  #-- Timer data
  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);

  #-- parse incoming parameters 
  my ($seqno,$Wd_cnt_old)=@_;

  #-- setup message
  my $sj=sprintf("%02x",$seqno);
  # power value = 0.6 from 0:00 - 06:00 / 1.8 kW from 6:00 - 22:00/1.2 kW from 22:00 - 24:00
  my $Pac_cnt;
  my $Wd_cnt = $Wd_cnt_old%65536;
  if( ($hour+$min/60.0)<6.0 ){
     $Pac_cnt= 0.64*150.0/12.0;
     $Wd_cnt+= 0.64*150.0/12.0;
  } elsif ( ($hour+$min/60.0)<22.0 ) {
     $Pac_cnt= 1.92*150.0/12.0;
     $Wd_cnt+= 1.92*150.0/12.0; 
  } else {
     $Pac_cnt= 1.28*150.0/12.0;
     $Wd_cnt+= 1.28*150.0/12.0;
  }
  my $cj=sprintf("%02x",int($Pac_cnt/256));
  my $ck=sprintf("%02x",$Pac_cnt%256);
  my $tj=sprintf("%02x",int($Wd_cnt/256));
  my $tk=sprintf("%02x",$Wd_cnt%256);
       
  my $msg="E0100".$sj.$tk.$tj.$ck.$cj."0000";
  #Log 1,"cj = $cj, ck=$ck, tj=$tj, tk=$tk";
  return $msg;
}
1;

=pod
=begin html

<a name="EMX"></a>
        <h3>EMX</h3>
        <p>FHEM module to commmunicate with the EM1000 WZ/EM/GZ power/gas sensors <br />
         <br /> <b>NOTE:</b> This module is currently NOT registered in the client list of 00_CUL.pm. 
         Therefore ist must be saved under the name 15_CUL_EM.pm or entered into the client list manually.
         <br /></p>
        <br /><h4>Example</h4>
        <p>
            <code>define E_Verbrauch EMX 1 75</code>
        </p>
        <br />
        <a name="EMXdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; EMX  &lt;code&gt; &lt;rpunit&gt;</code> or <br/>
            <code>define &lt;name&gt; EMX  emulator</code>
            <br /><br /> Define an EMX device or an emulated EM1000-WZ device <br /><br />
            
         </p>
        <ul>
            <li>
                <code>&lt;code&gt;</code><br /> Defines the sensor model, currently the following values are permitted: 
                <ul>
                    <li>1 .. 4: EM1000-WZ power meter sensor => unit is kWh</li>
                    <li>5 .. 8: EM1000-EM power sensor => unit is kWh</li>
                    <li>9 .. 12: EM1000-GZ gas meter sensor => unit is m<sup>3</sup></li>
                </ul>
            </li>
            <li>
                <code>&lt;rpunit&gt;</code><br/>Fcator to scale the reading into units
                <ul>
                    <li>EM1000-WZ devices: rotations per kWh, usually 75 or 150</li>
                    <li>EM1000-EM devices: digits per kWh, usually 100</li>
                    <li>EM1000-GZ devices: digits per <sup>3</sup>, usually 100</li>
                </ul>
            </li>
        </ul>
        <a name="EMXset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="emx_midnight">
                    <code>set &lt;name&gt; midnight &lt;int&gt;</code></a><br /> Value of counter at midnight </li>
        </ul>
        <br />
        <a name="EMXget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="emx_midnight2">
                    <code>get &lt;name&gt; midnight</code></a>
                <br /> Returns the value of the counter at midnight </li>
            <li><a name="emx_month">
                    <code>get &lt;name&gt; month</code>
                </a>
                <br /> Returns a summary of the current month</li>
        </ul>
        <br />
        <a name="EMXattr"></a>
        <h4>Attributes</h4> 
        <ul>
            <li><a name="emx_logm"><code>attr &lt;name&gt; &lt;LogM&gt;
                        &lt;string&gt;</code></a>
                <br />Device name (<i>not file name</i>) of the monthly logfile </li>
            <li><a name="emx_logy"><code>attr &lt;name&gt; &lt;LogY&gt;
                        &lt;string&gt;</code></a>
                <br />Device name (<i>not file name</i>) of the yearly logfile </li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a
                    href="#stateFormat">stateFormat</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
        
=end html
=cut

