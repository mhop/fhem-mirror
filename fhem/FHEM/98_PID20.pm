# $Id: 98_PID20.pm 3988 2013-11-06 10:00:00Z john $
####################################################################################################
#
#	98_PID20.pm
#	The PID device is a loop controller, used to set the value e.g of a heating
#	valve dependent of the current and desired temperature.
#
#	This module is derived from the contrib/99_PID by Alexander Titzel.
#   The framework of the module is derived from proposals by betateilchen.
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#
# V 1.00.c
#  03.12.2013 - bugfix : pidActorLimitUpper wrong assignment
# V 1.00.d
#  09.12.2013 - verbose-level adjusted 
#  20.12.2013 - bugfix: actorErrorPos: wrong assignment by pidCalcInterval-attribute, if defined
# V 1.00.e
#  01.01.2014 - fix: {helper}{actorCommand} assigned to an emptry string if not defined
# V 1.00.f
#  22.01.2014   fix:pidDeltaTreshold only int was assignable, now even float
# V 1.00.g
#  29.01.2014   fix:calculation of i-portion is independent from pidCalcInterval
# V 1.00.h
#  26.02.2014   fix:new logging format; adjusting verbose-levels
#
#  26.03.2014   (betateilchen)
#               code review, pod added, removed old version info (will be provided via SVN)

####################################################################################################
package main;
use strict;
use warnings;
use feature qw/say switch/;
use vars qw(%defs);
use vars qw($readingFnAttributes);
use vars qw(%attr);
use vars qw(%modules);

sub PID20_Calc($);

########################################
sub PID20_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline = (caller(0))[2];
   
   my $xsubroutine = (caller(1))[3];
   my $sub = (split( ':', $xsubroutine ))[2];
   $sub = substr ($sub, 6); # without PID20
   
   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : "PID20";
   Log3 $hash, $loglevel, "PID20 $instName: $sub.$xline " . $text;
}

########################################
sub PID20_Initialize($)
{
   my ($hash) = @_;
   $hash->{DefFn}    = "PID20_Define";
   $hash->{UndefFn}  = "PID20_Undef";
   $hash->{SetFn}    = "PID20_Set";
   $hash->{GetFn}    = "PID20_Get";
   $hash->{NotifyFn} = "PID20_Notify";
   $hash->{AttrList} =
       "pidActorValueDecPlaces:0,1,2,3,4,5 "
     . "pidActorInterval "
     . "pidActorTreshold "
     . "pidActorErrorAction:freeze,errorPos "
     . "pidActorErrorPos "
     . "pidActorKeepAlive "
     . "pidActorLimitLower "
     . "pidActorLimitUpper "
     . "pidCalcInterval "
     . "pidDeltaTreshold "
     . "pidDesiredName "
     . "pidFactor_P "
     . "pidFactor_I "
     . "pidFactor_D "
     . "pidMeasuredName "
     . "pidSensorTimeout "
     . "pidReverseAction "
     . "pidUpdateInterval "
#    . "pidDebugEnable:0,1 ";
     . "pidDebugSensor:0,1 "
     . "pidDebugActuation:0,1 "
     . "pidDebugCalc:0,1 "
     . "pidDebugDelta:0,1 "
     . "pidDebugUpdate:0,1 "
     . "pidDebugNotify:0,1 "

     . "disable:0,1 "
     . $readingFnAttributes;

}


########################################
sub PID20_TimeDiff($) {
  my ($strTS)=@_;
  #my ( $package, $filename, $line ) = caller(0);
  #print "PID $strTS line $line \n";
  
  my $serTS = (defined($strTS) && $strTS ne "") ? time_str2num($strTS) : gettimeofday();
  my $timeDiff = gettimeofday()- $serTS;
  $timeDiff=0 if ( $timeDiff<0);
  return $timeDiff;
}

########################################
sub PID20_Define($$$)
{
   my ( $hash, $def ) = @_;
   my @a = split( "[ \t][ \t]*", $def );
   my $name = $a[0];
   my $reFloat ='^([\\+,\\-]?\\d+\\.?\d*$)'; # gleitpunkt  
   
   if ( @a != 4)
   {
      return "wrong syntax: define <name> PID20 " . "<sensor>:reading:[regexp] <actor>[:cmd] ";
   }
   ###################
   # Sensor
   my ( $sensor, $reading, $regexp ) = split( ":", $a[2], 3 );
   
   # if sensor unkonwn
   if ( !$defs{$sensor} )
   {
      my $msg = "$name: Unknown sensor device $sensor specified";
      PID20_Log $hash, 1, $msg;
      return $msg;
   }
   
   # if reading of sender is unkown
   if (ReadingsVal($sensor,$reading,'unknown') eq 'unkown')
   {
      my $msg = "$name: Unknown reading $reading for sensor device $sensor specified";
      PID20_Log $hash, 1, $msg;
      return $msg;
   }
   
   $hash->{helper}{sensor} = $sensor;
   
   # defaults for regexp
   if ( !$regexp )
   {
      $regexp=$reFloat;
   }
   
   $hash->{helper}{reading} = $reading;
   $hash->{helper}{regexp}  = $regexp;

   # Actor
   my ( $actor, $cmd ) = split( ":", $a[3],2 );

   if ( !$defs{$actor} )
   {
      my $msg = "$name: Unknown actor device $actor specified";
      PID20_Log $hash, 1, $msg;
      return $msg;
   }
   
   $hash->{helper}{actor} = $actor;
   $hash->{helper}{actorCommand}= (defined ($cmd)) ? $cmd :"";
   $hash->{helper}{stopped}=0;
   $hash->{helper}{adjust}="";
   
   $modules{PID20}{defptr}{$name}=$hash; 
   
   readingsSingleUpdate( $hash, 'state', 'initializing',1 );
   
   RemoveInternalTimer($name);
   InternalTimer( gettimeofday() + 10, "PID20_Calc", $name, 0 );
   return undef;
}
########################################
sub PID20_Undef($$)
{
   my ( $hash, $arg ) = @_;
   RemoveInternalTimer($hash->{NAME});
   return undef;
}
sub
########################################
# we need a gradient for delta as base for d-portion calculation
# 
PID20_Notify($$)
{
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  my $sensorName = $hash->{helper}{sensor};
  
  my $DEBUG     = AttrVal($name, 'pidDebugNotify', '0' ) eq '1';
  
  
  # no action if disabled
  if (defined($attr{$name}) && defined($attr{$name}{disable}) )
  {
      $hash->{helper}{sensorTsOld}=undef;
      return "" ;
  }

  return if($dev->{NAME} ne $sensorName);

  my $sensorReadingName = $hash->{helper}{reading};
  my $regexp            = $hash->{helper}{regexp}; 
  my $desiredName       = AttrVal( $name, 'pidDesiredName', 'desired' );  
  my $desired           = ReadingsVal( $name,$desiredName, undef );
   
  my $max = int(@{$dev->{CHANGED}});
  PID20_Log $hash, 4, "check $max readings for ". $sensorReadingName;  

  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    
    # continue, if no match with reading-name
    $s = "" if(!defined($s));
    PID20_Log $hash, 5, "check event:<$s>";
    next if($s !~ m/$sensorReadingName/);
    
    # ---- build difference current - old value
    # get sensor value
    
    my $sensorStr = ReadingsVal( $sensorName, $sensorReadingName, undef );
    $sensorStr =~ m/$regexp/; 
    my $sensorValue = $1;   
    
    # calc difference of delta/deltaOld
    my $delta = $desired - $sensorValue if (defined($desired));
    my $deltaOld = ($hash->{helper}{deltaOld}+0) if (defined($hash->{helper}{deltaOld}));
    
    my $deltaDiff = ($delta - $deltaOld) if (defined($delta) && defined($deltaOld));
    PID20_Log $hash, 5, "Diff: delta[".sprintf( "%.2f",$delta)."]"
                     ." - deltaOld[".sprintf( "%.2f",$deltaOld)."]"
                     ."= Diff[".sprintf( "%.2f",$deltaDiff)."]"
                     if ($DEBUG); 
    
    # ----- build difference of timestamps (ok)
    my $deltaOldTsStr =  $hash->{helper}{deltaOldTS};
    my $deltaOldTsNum =time_str2num($deltaOldTsStr) if (defined($deltaOldTsStr));
    my $nowTsNum = gettimeofday();    
    my $tsDiff = ($nowTsNum - $deltaOldTsNum) 
        if ( defined($deltaOldTsNum) && (($nowTsNum - $deltaOldTsNum)>0));
    PID20_Log $hash, 5, "tsDiff: tsDiff = $tsDiff "  if ($DEBUG); 
    
    # ----- calculate gradient of delta 
    my $deltaGradient =$deltaDiff/$tsDiff if(defined($deltaDiff) && defined($tsDiff) && ($tsDiff>0));
    $deltaGradient = 0 if (!defined($deltaGradient));
    
    my $sdeltaDiff = ($deltaDiff)?sprintf( "%.2f",$deltaDiff):"";
    my $sTSDiff = ($tsDiff)?sprintf( "%.2f",$tsDiff):"";
    my $sDeltaGradient=($deltaGradient)?sprintf( "%.6f",$deltaGradient):"";
    PID20_Log $hash, 5, "deltaGradient: (Diff[$sdeltaDiff]"
                       ."/tsDiff[$sTSDiff]"
                       ."=deltaGradient per sec [$sDeltaGradient]" if ($DEBUG); 
                       
    # ----- store results
    $hash->{helper}{deltaGradient}=$deltaGradient;
    $hash->{helper}{deltaOld}= $delta;
    $hash->{helper}{deltaOldTS}= TimeNow();
      
    last;
  }
  return "";
}
########################################
sub PID20_Get($@) 
{
   my ( $hash, @a ) = @_;
   my $name  = $hash->{NAME};
   my $usage = "Unknown argument $a[1], choose one of params:noArg";
   return $usage if ( @a < 2 );
   my $cmd   = lc( $a[1] );
   given ($cmd)
   {
      when ('params')
      {
         my $ret = "Defined parameters for PID20 $name:\n\n";
         $ret .= 'Actor name       : ' . $hash->{helper}{actor} . "\n";
         $ret .= 'Actor cmd        : ' . $hash->{helper}{actorCommand} . "\n\n";
         $ret .= 'Sensor name      : ' . $hash->{helper}{sensor} . "\n";
         $ret .= 'Sensor reading   : ' . $hash->{helper}{reading} . "\n\n";
         $ret .= 'Sensor regexp    : ' . $hash->{helper}{regexp} . "\n\n";
         $ret .= 'Factor P         : ' . $hash->{helper}{factor_P} . "\n";
         $ret .= 'Factor I         : ' . $hash->{helper}{factor_I} . "\n";
         $ret .= 'Factor D         : ' . $hash->{helper}{factor_D} . "\n\n";
         $ret .= 'Actor lower limit: ' . $hash->{helper}{actorLimitLower} . "\n";
         $ret .= 'Actor upper limit: ' . $hash->{helper}{actorLimitUpper} . "\n";
         return $ret;
      }
      default { return $usage; };
   }
}
########################################
sub PID20_Set($@)
{
   my ( $hash, @a ) = @_;
   my $name  = $hash->{NAME};
   my $reFloat ='^([\\+,\\-]?\\d+\\.?\d*$)';   
    
   my $usage =
     "Unknown argument $a[1], choose one of stop:noArg start:noArg restart "
     . AttrVal( $name, 'pidDesiredName', 'desired' );
   return $usage if ( @a < 2 );
   
   my $cmd = lc( $a[1] );
   my $desiredName = lc(AttrVal( $name, 'pidDesiredName', 'desired' ));
   #PID20_Log $hash, 3, "name:$name cmd:$cmd $desired:$desired"; 
          
   given ($cmd)
   {
      when ("?")
      {
         return $usage;
      }

      when ( $desiredName )
      {
         return "Set " . AttrVal( $name, 'pidDesiredName', 'desired' ) . " needs a <value> parameter"
           if ( @a != 3 );
           
         my $value=$a[2]; 
         $value=($value=~ m/$reFloat/) ? $1:undef; 
         return "value ".$a[2]." is not a number"
           if (!defined($value));     
                           
         readingsSingleUpdate( $hash, $cmd, $value, 1 );
         PID20_Log $hash, 3, "set $name $cmd $a[2]";
      }
      
      when ("start")  
      {
         return "Set start needs a <value> parameter"
           if ( @a != 2 );
         $hash->{helper}{stopped} =0; 
         
      }
      
      when ("stop")  
      {
         return "Set stop needs a <value> parameter"
           if ( @a != 2 );
         $hash->{helper}{stopped} =1; 
         PID20_Calc($hash);
      }
      
      when ("restart")  
      {
         return "Set restart needs a <value> parameter"
           if ( @a != 3 );
           
         my $value=$a[2]; 
         $value=($value=~ m/$reFloat/) ? $1:undef;
         #PID20_Log $hash, 1, "value:$value";
          
         return "value ".$a[2]." is not a number"
           if (!defined($value));   
           
         $hash->{helper}{stopped} =0; 
         $hash->{helper}{adjust} =$value;   
         PID20_Log $hash, 3, "set $name $cmd $value";        
      }
      
      when ("calc")  # inofficial function, only for debugging purposes
      {
        PID20_Calc($hash);  
      }
      
      default
      {
         return $usage;
      }
   }
   return;
}

########################################
# disabled = 0
# idle = 1
# processing = 2
# stopped = 3
# alarm  = 4
sub PID20_Calc($)
{
   my $reUINT = '^([\\+]?\\d+)$';   # uint without whitespaces
   my $re01   = '^([0,1])$';        # only 0,1
   my $reINT  = '^([\\+,\\-]?\\d+$)';  # int
   my $reFloatpos ='^([\\+]?\\d+\\.?\d*$)'; # gleitpunkt positiv
   my $reFloat ='^([\\+,\\-]?\\d+\\.?\d*$)'; # gleitpunkt  
   
   my ($name)        = @_;
   my $hash          = $defs{$name};
   
   my $sensor        = $hash->{helper}{sensor};
   my $reading       = $hash->{helper}{reading};
   my $regexp        = $hash->{helper}{regexp};
   
   my $DEBUG_Sensor     = AttrVal($name, 'pidDebugSensor', '0' ) eq '1';
   my $DEBUG_Actuation  = AttrVal($name, 'pidDebugActuation',  '0' ) eq '1';  
   my $DEBUG_Delta      = AttrVal($name, 'pidDebugDelta',  '0' ) eq '1';  
   my $DEBUG_Calc       = AttrVal($name, 'pidDebugCalc',  '0' ) eq '1';   
   my $DEBUG_Update     = AttrVal($name, 'pidDebugUpdate',  '0' ) eq '1'; 
   
   my $DEBUG         = $DEBUG_Sensor || $DEBUG_Actuation || $DEBUG_Calc || $DEBUG_Delta || $DEBUG_Update ;
   
   my $actuation           = "";
   my $actuationDone       = ReadingsVal( $name, 'actuation', "" );
   my $actuationCalc       = ReadingsVal( $name, 'actuationCalc', "" );
   my $actuationCalcOld    = $actuationCalc;
   my $actorTimestamp      = ($hash->{helper}{actorTimestamp})
                             ?$hash->{helper}{actorTimestamp}:FmtDateTime(gettimeofday()-3600*24);

   my $sensorStr           = ReadingsVal( $sensor, $reading, "" );
   my $sensorValue         = "";
   my $sensorTS            = ReadingsTimestamp( $sensor, $reading, undef );
   my $sensorIsAlive       = 0;
   
   my $iPortion            = ReadingsVal( $name, 'p_i', 0 );
   my $pPortion      = "";
   my $dPortion      = "";
   
   my $stateStr      = "";
   
   my $deltaOld         = ReadingsVal( $name, 'delta', 0 );
   my $delta            = "";
   my $deltaGradient    = ($hash->{helper}{deltaGradient})?$hash->{helper}{deltaGradient}:0;   
   
   my $calcReq          = 0;
   
   # ---------------- check different conditions
   while (1)
   {
      # --------------- retrive values from attributes 
     
     $hash->{helper}{actorInterval}    = (AttrVal($name, 'pidActorInterval', 180 ) =~ m/$reUINT/) ? $1:180; 
     $hash->{helper}{actorThreshold}   = (AttrVal($name, 'pidActorTreshold', 1 ) =~ m/$reUINT/) ? $1:1;
     $hash->{helper}{actorKeepAlive}   = (AttrVal($name, 'pidActorKeepAlive', 1800 ) =~ m/$reUINT/) ? $1:1800;
     $hash->{helper}{actorValueDecPlaces} = (AttrVal($name, 'pidActorValueDecPlaces', 0 ) =~ m/$reUINT/) ? $1:0;
     
     $hash->{helper}{actorErrorAction} = (AttrVal($name, 'pidActorErrorAction', 'freeze') eq 'errorPos') ?'errorPos':'freeze';
     $hash->{helper}{actorErrorPos}    = (AttrVal($name, 'pidActorErrorPos', 0 ) =~ m/$reINT/) ? $1:0;

     
     $hash->{helper}{calcInterval}     = (AttrVal($name, 'pidCalcInterval', 60 ) =~ m/$reUINT/) ? $1:60;
     $hash->{helper}{deltaTreshold}    = (AttrVal($name, 'pidDeltaTreshold', 0 ) =~ m/$reFloatpos/) ? $1:0;
     $hash->{helper}{disable}          = (AttrVal($name, 'Disable', 0 ) =~ m/$re01/) ? $1:'';
     
     $hash->{helper}{sensorTimeout}    = (AttrVal($name, 'pidSensorTimeout', 3600 ) =~ m/$reUINT/) ? $1:3600;
     $hash->{helper}{reverseAction}    = (AttrVal($name, 'pidReverseAction', 0 ) =~ m/$re01/) ? $1:0;
     $hash->{helper}{updateInterval}   = (AttrVal($name, 'pidUpdateInterval', 600 ) =~ m/$reUINT/) ? $1:600;
     
     $hash->{helper}{measuredName}     = AttrVal($name, 'pidMeasuredName', 'measured') ;
     $hash->{helper}{desiredName}      = AttrVal($name, 'pidDesiredName', 'desired') ;
     
     $hash->{helper}{actorLimitLower}  = (AttrVal($name, 'pidActorLimitLower', 0) =~ m/$reFloat/) ? $1:0;
     my $actorLimitLower               = $hash->{helper}{actorLimitLower};
     
     $hash->{helper}{actorLimitUpper}  =  (AttrVal($name, 'pidActorLimitUpper', 100) =~ m/$reFloat/) ? $1:100;    
     my $actorLimitUpper               = $hash->{helper}{actorLimitUpper};
     
     $hash->{helper}{factor_P}         = (AttrVal($name, 'pidFactor_P', 25) =~ m/$reFloatpos/) ? $1:25;  
     $hash->{helper}{factor_I}         = (AttrVal($name, 'pidFactor_I', 0.25) =~ m/$reFloatpos/) ? $1:0.25;  
     $hash->{helper}{factor_D}         = (AttrVal($name, 'pidFactor_D', 0) =~ m/$reFloatpos/) ? $1:0;  
     
      if ($hash->{helper}{disable})
      {
         $stateStr="disabled";
         last;
      }
      
      if ($hash->{helper}{stopped})
      {
         $stateStr="stopped";
         last;
      }
   
      my $desired  = ReadingsVal( $name,$hash->{helper}{desiredName}, "" );
      
      # sensor found 
      PID20_Log $hash, 2, "--------------------------" if ($DEBUG);
      PID20_Log $hash, 2, "S1 sensorStr:$sensorStr sensorTS:$sensorTS" if ($DEBUG_Sensor);
      $stateStr="alarm - no $reading yet for $sensor" if ( !$sensorStr && !$stateStr);
      
      # sensor alive 
      if ($sensorStr && $sensorTS)
      {
        my $timeDiff = PID20_TimeDiff($sensorTS);
        $sensorIsAlive = 1 if ( $timeDiff <= $hash->{helper}{sensorTimeout} );     
        $sensorStr =~ m/$regexp/;
        $sensorValue = $1;
        $sensorValue="" if (!defined($sensorValue));   
        PID20_Log $hash, 2, "S2 timeOfDay:".gettimeofday() 
               ." timeDiff:$timeDiff sensorTimeout:".$hash->{helper}{sensorTimeout}
               ." --> sensorIsAlive:$sensorIsAlive"  if ($DEBUG_Sensor);       
      }
      
      # sensor dead 
      $stateStr="alarm - dead sensor"  if (!$sensorIsAlive  && !$stateStr);
      
      # missing desired 
      $stateStr="alarm - missing desired" if ($desired eq ""  && !$stateStr);
      
      # check delta threshold
      $delta =($desired ne "" && $sensorValue ne "" ) ?  $desired - $sensorValue : "";
      
      $calcReq = 1  if (!$stateStr && $delta ne "" && (abs($delta) >= abs( $hash->{helper}{deltaTreshold})) );
      
      PID20_Log $hash, 2, "D1 desired[".        ($desired ne "")     ? sprintf( "%.1f", $desired) : ""
                      ."] - sensorValue: [".  ($sensorValue ne "") ? sprintf( "%.1f", $sensorValue) : ""
                      ."] = delta[".          ($delta ne "")       ? sprintf( "%.2f", $delta):""
                      ."] calcReq:$calcReq" 
                      if ($DEBUG_Delta);
      
      #request for calculation
     
      # ---------------- calculation request
      if ($calcReq)
      {
        # reverse action requested 
        my $workDelta = ( $hash->{helper}{reverseAction} ==1 ) ? -$delta: $delta;
        my $deltaOld = - $deltaOld if ($hash->{helper}{reverseAction} ==1  );
        
        # calc p-portion
        $pPortion = $workDelta * $hash->{helper}{factor_P};
        
        # calc d-Portion
        $dPortion = ( $deltaGradient ) * $hash->{helper}{calcInterval} * $hash->{helper}{factor_D};
        
   
        # calc i-portion respecting windUp
        # freeze i-portion if windUp is active
        my $isWindup = 
          $actuationCalcOld && 
          (
              ( $workDelta > 0 && $actuationCalcOld > $actorLimitUpper )
           || ( $workDelta < 0 && $actuationCalcOld < $actorLimitLower ) 
          );
          
        if ($hash->{helper}{adjust} ne "")
        {
           $iPortion = $hash->{helper}{adjust} - ($pPortion + $dPortion);
           $iPortion= $actorLimitUpper if($iPortion > $actorLimitUpper);
           $iPortion= $actorLimitLower if($iPortion < $actorLimitLower);
           PID20_Log $hash, 5, "adjust request with:".$hash->{helper}{adjust}." ==> p_i:$iPortion";     
           
           $hash->{helper}{adjust}="";
        }  
        elsif ( !$isWindup )    # integrate only if no windUp
        {
           # normalize the intervall to minute=60 seconds
           $iPortion = $iPortion + $workDelta * $hash->{helper}{factor_I}*$hash->{helper}{calcInterval}/60;
           $hash->{helper}{isWindUP} = 0;
        } 
        $hash->{helper}{isWindUP} = $isWindup;
        
        # calc actuation
        $actuationCalc =  $pPortion + $iPortion + $dPortion; 
        PID20_Log $hash, 2, "P1 delta:".sprintf( "%.2f",$delta)
                             ." isWindup:$isWindup" 
                             if ($DEBUG_Calc);
                             
        PID20_Log $hash, 2, "P2 pPortion:".sprintf( "%.2f",$pPortion)
                          ." iPortion:".sprintf( "%.2f",$iPortion)
                          ." dPortion:".sprintf( "%.2f",$dPortion)
                          ." actuationCalc:".sprintf( "%.2f", $actuationCalc) if ($DEBUG_Calc);
   
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, 'p_p',  $pPortion ); 
        readingsBulkUpdate( $hash, 'p_i',  $iPortion ); 
        readingsBulkUpdate( $hash, 'p_d',  $dPortion ); 
        readingsBulkUpdate( $hash, 'actuationCalc',  $actuationCalc ); 
        readingsBulkUpdate( $hash, 'delta', $delta  );     
        readingsEndUpdate( $hash, 0 );
        #PID20_Log $hash, 3, "calculation done";    
      }
     
      # ---------------- acutation request
     my $noTrouble = ($desired ne "" && $sensorIsAlive); 
     
     # check actor fallback in case of sensor fault
     if (!$sensorIsAlive && ($hash->{helper}{actorErrorAction} eq "errorPos"))
     {
        $stateStr .= "- force pid-output to errorPos";
        $actuationCalc=$hash->{helper}{actorErrorPos};
        $actuationCalc="" if (!defined($actuationCalc));
     }
   
     # check acutation diff
     $actuation = $actuationCalc;
    
     # limit $actuation 
     $actuation= $actorLimitUpper if($actuation ne "" && ($actuation > $actorLimitUpper));
     $actuation= $actorLimitLower if($actuation ne "" && ($actuation < $actorLimitLower));
     
     # check if round request
     my $fmt= "%.".$hash->{helper}{actorValueDecPlaces}."f";
     $actuation  = sprintf( $fmt, $actuation) if ($actuation ne "");
     
     my $actuationDiff = abs( $actuation - $actuationDone) if ($actuation ne "" && $actuationDone ne "");
     PID20_Log $hash, 2, "A1 act:$actuation actDone:$actuationDone "
                       ." actThreshold:".$hash->{helper}{actorThreshold} 
                       ." actDiff:$actuationDiff"
                       if ($DEBUG_Actuation);   
                       
     # check threshold-condition for actuation
     my $rsTS =   $actuationDone ne "" # limit exceeded
               && $actuationDiff >= $hash->{helper}{actorThreshold};  
     
     my $rsUp =     $actuationDone ne ""  # upper range
                &&  $actuation>$actorLimitUpper-$hash->{helper}{actorThreshold}  
                &&  $actuationDiff != 0 
                &&  $actuation >=$actorLimitUpper;

     my $rsDown =   $actuationDone ne "" # low range 
                 && $actuation<$actorLimitLower+$hash->{helper}{actorThreshold}  
                 && $actuationDiff != 0 
                 && $actuation <=$actorLimitLower; 
          
     my $rsLimit =  $actuationDone ne ""
               && ($actuationDone<$actorLimitLower || $actuationDone>$actorLimitUpper); 
         
     my $actuationByThreshold = ( ($rsTS || $rsUp || $rsDown ) && $noTrouble);  
     
     PID20_Log $hash, 2, "A2 rsTS:$rsTS rsUp:$rsUp rsDown:$rsDown noTrouble:$noTrouble" if ($DEBUG_Actuation);
     
     # check time condition for actuation
     my $actTimeDiff = PID20_TimeDiff($actorTimestamp); # $actorTimestamp is valid in each case
     my $actuationByTime   = ($noTrouble) &&  ($actTimeDiff > $hash->{helper}{actorInterval});
     
     PID20_Log $hash, 2, "A3 actTS:$actorTimestamp"
                   ." actTimeDiff:".sprintf( "%.2f",$actTimeDiff)
                   ." actInterval:".$hash->{helper}{actorInterval} 
                   ."-->actByTime:$actuationByTime " if ($DEBUG_Actuation); 
        
     # check keep alive condition for actuation   
     my $actuationKeepAliveReq = ($actTimeDiff >= $hash->{helper}{actorKeepAlive}) 
       if (defined($actTimeDiff) && $actuation ne "");
     
     # summary actuation reques

     my $actuationReq =  (
                             ($actuationByThreshold && $actuationByTime) 
                          || $actuationKeepAliveReq 
                          || $rsLimit
                          || $actuationDone eq ""  # startup condition
                          )
                         && $actuation ne "";
                        
     PID20_Log $hash, 2, "A4 (actByTh:$actuationByThreshold && actByTime:$actuationByTime)"
                        ."||actKeepAlive:$actuationKeepAliveReq"
                        ."||rsLimit:$rsLimit=actnReq:$actuationReq"  if ($DEBUG_Actuation); 
           
     # perform output to actor
     if ($actuationReq) 
     {
        #build command for fhem
        PID20_Log $hash, 5, "actor:".$hash->{helper}{actor}
                   ." actorCommand:".$hash->{helper}{actorCommand}
                   ." actuation:".$actuation;
                   
        my $cmd= sprintf("set %s %s %g", $hash->{helper}{actor}, $hash->{helper}{actorCommand},$actuation);
        
        # execute command
        my $ret;
        $ret = fhem $cmd;  
          
        # note timestamp
        $hash->{helper}{actorTimestamp}=TimeNow();
        $actuationDone=$actuation; 
        my $retStr="" if (!$ret);      
        PID20_Log $hash, 3, "<$cmd> with ret:$retStr";    
     }
   
     my $updateAlive= ($actuation ne "") 
          && PID20_TimeDiff(ReadingsTimestamp( $name, 'actuation', gettimeofday()))>=$hash->{helper}{updateInterval};
          
     my $updateReq=(($actuationReq || $updateAlive) && $actuation ne "");
     
     PID20_Log $hash, 2, "U1 actReq:$actuationReq updateAlive:$updateAlive -->  updateReq:$updateReq" 
       if ($DEBUG_Update); 
     
     # ---------------- update request
     if ($updateReq) 
     {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, $hash->{helper}{desiredName},  $desired )        if ($desired ne "");
        readingsBulkUpdate( $hash, $hash->{helper}{measuredName},  $sensorValue )   if ($sensorValue ne "");
        readingsBulkUpdate( $hash, 'p_p',  $pPortion )                              if ($pPortion ne"");
        readingsBulkUpdate( $hash, 'p_d',  $dPortion )                              if ($dPortion ne "");
        readingsBulkUpdate( $hash, 'p_i',  $iPortion )                              if ($iPortion ne ""); 
        readingsBulkUpdate( $hash, 'actuation',  $actuationDone )                   if ($actuationDone ne "");  
        readingsBulkUpdate( $hash, 'actuationCalc',  $actuationCalc )               if ($actuationCalc ne "");  
        readingsBulkUpdate( $hash, 'delta', $delta  )                               if ($delta ne "");     
        readingsEndUpdate( $hash, 1 );
        PID20_Log $hash, 5, "readings updated";     
     }
     last;
   } # end while  
   
   # update statePID.
    $stateStr = "idle"        if (!$stateStr && !$calcReq);
    $stateStr = "processing"  if (!$stateStr && $calcReq);
    readingsSingleUpdate( $hash, 'state',  $stateStr , 0 );
    
    PID20_Log $hash, 2, "C1 stateStr:$stateStr calcReq:$calcReq" if ($DEBUG_Calc);
   
   # timer setup
   my $next = gettimeofday() + $hash->{helper}{calcInterval};
   RemoveInternalTimer($name);  # prevent multiple timers for same hash
   InternalTimer( $next, "PID20_Calc", $name, 1 );
   
  #PID20_Log $hash, 2, "InternalTimer next:".FmtDateTime($next)." PID20_Calc name:$name DEBUG_Calc:$DEBUG_Calc";
   
   return;
}


1;

=pod
=begin html

<a name="PID20"></a>
<h3>PID20</h3>
<ul>

	<a name="PID20define"></a>
	<b>Define</b>
	<ul>
		<br/>
		<code>define &lt;name&gt; PID20 &lt;sensor[:reading[:regexp]]&gt; &lt;actor:cmd &gt;</code>
		<br/><br/>
		This module provides a PID device, using &lt;sensor&gt; and &lt;actor&gt;<br/>
	</ul>
	<br/><br/>

	<a name="PID20set"></a>
	<b>Set-Commands</b><br/>
	<ul>

		<br/>
		<code>set &lt;name&gt; desired &lt;value&gt;</code>
		<br/><br/>
		<ul>Set desired value for PID</ul>
		<br/>

		<br/>
		<code>set &lt;name&gt; start</code>
		<br/><br/>
		<ul>Start PID processing again, using frozen values from former stop.</ul>
		<br/>

		<br/>
		<code>set &lt;name&gt; stop</code>
		<br/><br/>
		<ul>PID stops processing, freezing all values.</ul>
		<br/>

		<br/>
		<code>set &lt;name&gt; restart &lt;value&gt;</code>
		<br/><br/>
		<ul>Same as start, but uses value as start value for actor</ul>
		<br/>

	</ul>
	<br/><br/>

	<a name="PID20get"></a>
	<b>Get-Commands</b><br/>
	<ul>

		<br/>
		<code>get &lt;name&gt; params</code>
		<br/><br/>
		<ul>Get list containing current parameters.</ul>
		<br/>

	</ul>
	<br/><br/>

	<a name="PID20attr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
		<br/>
		<li><b>disable</b> - disable the PID device, possible values: 0,1; default: 0</li>
		<li><b>pidActorValueDecPlaces</b> - number of demicals, possible values: 0..5; default: 0</li>
		<li><b>pidActorInterval</b> - number of seconds to wait between to commands sent to actor; default: 180</li>
		<li><b>pidActorTreshold</b> - threshold to be reached before command will be sent to actor; default: 1</li>
		<li><b>pidActorErrorAction</b> - required action on error, possible values: freeze,errorPos; default: freeze</li>
		<li><b>pidActorErrorPos</b> - actor's position to be used in case of error; default: 0</li>
		<li><b>pidActorKeepAlive</b> - number of seconds to force command to be sent to actor; default: 1800</li>
		<li><b>pidActorLimitLower</b> - lower limit for actor; default: 0</li>
		<li><b>pidActorLimitUpper</b> - upper limit for actor; default: 100</li>
		<li><b>pidCalcInterval</b> - interval (seconds) to calculate new pid values; default: 60</li>
		<li><b>pidDeltaTreshold</b> - if delta < delta-threshold the pid will enter idle state; default: 0</li>
		<li><b>pidDesiredName</b> - reading's name for desired value; default: desired</li>
		<li><b>pidFactor_P</b> - P value for PID; default: 25</li>
		<li><b>pidFactor_I</b> - I value for PID; default: 0.25</li>
		<li><b>pidFactor_D</b> - D value for PID; default: 0</li>
		<li><b>pidMeasuredName</b> - reading's name for measured value; default: measured</li>
		<li><b>pidSensorTimeout</b> - number of seconds to wait before sensor will be recognized n/a; default: 3600</li>
		<li><b>pidReverseAction</b> - reverse PID operation mode, possible values: 0,1; default: 0</li>
		<li><b>pidUpdateInterval</b> - number of seconds to wait before an update will be forced for plotting; default: 300</li>

	</ul>
	<br/><br/>

	<b>Generated Readings/Events:</b>
	<br/><br/>
	<ul>
		<li><b>actuation</b> - real actuation set to actor</li>
		<li><b>actuationCalc</b> - internal actuation calculated without limits</li>
		<li><b>delta</b> - current difference desired - measured</li>
		<li><b>desired</b> - desired value</li>
		<li><b>measured</b> - measured value</li>
		<li><b>p_p</b> - p value of pid calculation</li>
		<li><b>p_i</b> - i value of pid calculation</li>
		<li><b>p_d</b> - d value of pid calculation</li>
		<li><b>state</b> - current device state</li>
		<br/>
		Names for desired and measured readings can be changed by corresponding attributes (see above).<br/>
	</ul>
	<br/><br/>

	<b>Additional informations</b><br/><br/>
	<ul>
		<li><a href="http://forum.fhem.de/index.php/topic,17067.0.html">Discussion in FHEM forum</a></li><br/>
		<li><a href="http://www.fhemwiki.de/wiki/PID20_-_Der_PID-Regler">WIKI information in FHEM wiki</a></li><br/>
	</ul>

</ul>

=end html
