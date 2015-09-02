##############################################
# $Id$
# 
# This file is part of fhem.
# 
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################


package main;
use strict;
use warnings;

sub DOIF_cmd ($$$$);

sub
DOIF_delTimer($)
{
  my ($hash) = @_;
  RemoveInternalTimer($hash);
  my $max_timer=keys %{$hash->{timerfunc}};
  for (my $i=0; $i<$max_timer;$i++) 
  {
    RemoveInternalTimer ($hash->{timerfunc}{$i});
  }
  return undef;
}

sub
DOIF_delAll($)
{
  my ($hash) = @_;
  delete ($hash->{helper});
  delete ($hash->{condition});
  delete ($hash->{do});
  delete ($hash->{devices});
  delete ($hash->{time});
  delete ($hash->{timer});
  delete ($hash->{timers});
  delete ($hash->{itimer});
  delete ($hash->{timeCond});
  delete ($hash->{realtime});
  delete ($hash->{days});
  delete ($hash->{readings});
  delete ($hash->{internals});
  delete ($hash->{trigger});
  delete ($defs{$hash->{NAME}}{READINGS});
}   

#########################
sub
DOIF_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "DOIF_Define";
  $hash->{SetFn}   = "DOIF_Set";
  $hash->{UndefFn}  = "DOIF_Undef";
  $hash->{AttrFn}   = "DOIF_Attr";
  $hash->{NotifyFn} = "DOIF_Notify";
  $hash->{AttrList} = "disable:0,1 loglevel:0,1,2,3,4,5,6 wait do:always,resetwait cmdState state initialize repeatsame waitsame waitdel cmdpause timerWithWait ".$readingFnAttributes;
}


 
sub 
GetBlockDoIf ($$)
{
  my ($cmd,$match) = @_;
  my $count=0;
  my $first_pos=0;
  my $last_pos=0;
  my $err="";
  while($cmd =~ /$match/g) {
    if (substr($cmd,pos($cmd)-1,1) eq substr($match,2,1)) {
      $count++;
      $first_pos=pos($cmd) if ($count == 1);
    } elsif (substr($cmd,pos($cmd)-1,1) eq substr($match,4,1)) {
      $count--;
    }
    if ($count < 0)
    {
      $err="right bracket without left bracket";
      return ("",substr($cmd,pos($cmd)-1),$err,"");
    }
    
    if ($count == 0) {
      $last_pos=pos($cmd);
      last;
    }
  }
  if ($count > 0) {
    $err="no right bracket";
    return ("",substr($cmd,$first_pos-1),$err);
  }
  if ($first_pos) {
    return (substr($cmd,0,$first_pos-1),substr($cmd,$first_pos,$last_pos-$first_pos-1),"",substr($cmd,$last_pos));
  } else {
    return ($cmd,"","","");
  }
}

sub
EventDoIf($$$$)
{
  my ($n,$dev,$events,$NotifyExp)=@_;
  return 0 if ($dev ne $n);
  return 0 if(!$events); # Some previous notify deleted the array.
  my $max = int(@{$events});
  my $ret = 0;
  return 1 if ($NotifyExp eq "");
  for (my $i = 0; $i < $max; $i++) {
    my $s = $events->[$i];
    $s = "" if(!defined($s));
    my $found = ($s =~ m/$NotifyExp/);
    return 1 if ($found);
    #if(!$found && AttrVal($n, "eventMap", undef)) {
    #  my @res = ReplaceEventMap($n, [$n,$s], 0);
    #  shift @res;
    #  $s = join(" ", @res);
    #  $found = ("$n:$s" =~ m/^$re$/);
  }
  return 0;
}

sub
InternalDoIf($$$)
{
  my ($name,$internal,$regExp)=@_;
  my $r="";
  my $element;
    $r=$defs{$name}{$internal};
    if ($regExp) {
      $element = ($r =~  /$regExp/) ? $1 : "";
    } else {
      $element=$r;
    }
    return($element);
}

sub
ReadingSecDoIf($$)
{
  my ($name,$reading)=@_;
  my ($seconds, $microseconds) = gettimeofday();
  return ($seconds - time_str2num(ReadingsTimestamp($name, $reading, "1970-01-01 01:00:00")));
}

sub
ReadingValDoIf($$$)
{
  my ($name,$reading,$regExp)=@_;
  my $r;
  my $element;
    $r=$defs{$name}{READINGS}{$reading}{VAL};
    $r="" if (!defined($r));
    if ($regExp) {
      $element = ($r =~  /$regExp/) ? $1 : "";
    } else {
      $element=$r;
    }
    return($element);
}

sub
EvalAllDoIf($)
{
  my ($tailBlock)= @_;
  my $eval="";
  my $beginning;
  my $err;
  my $cmd="";
  my $ret="";
  
  while ($tailBlock ne "") {
    ($beginning,$eval,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]');
    return ($eval,$err) if ($err);
    if ($eval) {
      if (substr($eval,0,1) eq "(") {
        my $ret = eval $eval;
        return($eval." ",$@) if ($@);
        $eval=$ret;
      } else {
        $eval="{".$eval."}";
      }
    }
    $cmd.=$beginning.$eval;
  }
  return ($cmd,"");
}

sub ReplaceReadingDoIf($)
{
  my ($element) = @_;
  my $beginning;
  my $tailBlock;
  my $err;
  my $regExp="";
  my ($name,$reading,$format)=split(":",$element);
  my $internal="";
  my $notifyExp="";
  if ($name) {
    #return ($name,"unknown Device") if(!$defs{$name});
    if ($reading) {
      if (substr($reading,0,1) eq "\?") {
        $notifyExp=substr($reading,1);
        return("EventDoIf('$name',".'$hash->{helper}{triggerDev},'.'$hash->{helper}{triggerEvents},'."'$notifyExp')","",$name,undef,undef);
      }  
      $internal = substr($reading,1) if (substr($reading,0,1) eq "\&");
      if ($format) {
        if ($format eq "d") {
          $regExp = '(-?\d+(\.\d+)?)';
        } elsif ($format eq "sec") {
          return("ReadingSecDoIf('$name','$reading')","",$name,$reading,undef);
        } elsif (substr($format,0,1) eq '[') {
          ($beginning,$regExp,$err,$tailBlock)=GetBlockDoIf($format,'[\[\]]');
          return ($regExp,$err) if ($err);
          return ($regExp,"no round brackets in regular expression") if ($regExp !~ /.*\(.*\)/);
        } else {
          return($format,"unknown expression format");
        }  
      } 
      if ($internal) {
        return("InternalDoIf('$name','$internal','$regExp')","",$name,undef,$internal);
      } else {
        return("ReadingValDoIf('$name','$reading','$regExp')","",$name,$reading,undef);
      }
    } else {
      return("InternalDoIf('$name','STATE','$regExp')","",$name,undef,'STATE');
    }
  }
}

sub ReplaceReadingEvalDoIf($$)
{
  my ($element,$eval) = @_;
  my ($block,$err,$device,$reading,$internal)=ReplaceReadingDoIf($element);
  return ($block,$err) if ($err);
  if ($eval) {
    return ($device,"device does not exist: $device") if(!$defs{$device});
    return ($block,"reading does not exist: $device:$reading") if (defined ($reading) and !defined($defs{$device}{READINGS}{$reading}));
    return ($block,"internal does not exist: $device:$internal") if (defined ($internal) and !defined($defs{$device}{$internal}));
    my $ret = eval $block;
    return($block." ",$@) if ($@);
    $block=$ret;
  } 
  return ($block,"",$device,$reading,$internal);
}

sub AddItemDoIf($$)
{
  my ($items,$item)=@_;
  if (!$items) {
    $items=" $item ";
  } elsif ($items !~ / $item /) {
    $items.="$item ";
  }
  return $items;
}
    
sub ReplaceAllReadingsDoIf($$$$)
{
  my ($hash,$tailBlock,$condition,$eval)= @_;
  my $block="";
  my $beginning;
  my $err;
  my $cmd="";
  my $ret="";
  my $device="";
  my @timerarray;
  my $nr;
  my $timer="";
  my $event=0;
  my $definition=$tailBlock;
  my $reading;
  my $internal;
  my $trigger=1;
  while ($tailBlock ne "") {
    $trigger=1;
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\[\]]');
    return ($block,$err) if ($err);
    if ($block ne "") {
      if (substr($block,0,1) eq "?") {
        $block=substr($block,1);
        $trigger=0;
      }
     # if ($block =~ /^[0-9]+$/) {
     #   $block="[".$block."]";
     # } elsif
      if ($block =~ /^\??[a-z0-9._]*[a-z._]+[a-z0-9._]*($|:.+$)/i) {
        ($block,$err,$device,$reading,$internal)=ReplaceReadingEvalDoIf($block,$eval);
        return ($block,$err) if ($err);
        if ($trigger) {
          if ($condition >= 0) {
            $hash->{devices}{$condition} = AddItemDoIf($hash->{devices}{$condition},$device);
            $hash->{devices}{all} = AddItemDoIf($hash->{devices}{all},$device);
            $hash->{readings}{$condition} = AddItemDoIf($hash->{readings}{$condition},"$device:$reading") if (defined ($reading));
            $hash->{internals}{$condition} = AddItemDoIf($hash->{internals}{$condition},"$device:$internal") if (defined ($internal));
            $hash->{readings}{all} = AddItemDoIf($hash->{readings}{all},"$device:$reading") if (defined ($reading));
            $hash->{internals}{all} = AddItemDoIf($hash->{internals}{all},"$device:$internal") if (defined ($internal));
            $hash->{trigger}{all} = AddItemDoIf($hash->{trigger}{all},"$device") if (!defined ($internal) and !defined($reading));
            $event=1;
          } elsif ($condition == -2) {
            $hash->{state}{device} = AddItemDoIf($hash->{state}{device},$device) if ($device ne $hash->{NAME});
          } elsif ($condition == -3) {
              $hash->{itimer}{all} = AddItemDoIf($hash->{itimer}{all},$device);
          }
        }
      } elsif ($condition >= 0) {
	      ($timer,$err)=DOIF_CheckTimers($hash,$block,$condition,$trigger,\@timerarray);
		    return($timer,$err) if ($err);
        if ($timer) {
          $block=$timer;
          $event=1 if ($trigger);
        }
      } else {
        $block="[".$block."]";
      }
    }
    $cmd.=$beginning.$block;
  }
  return ($definition,"no trigger in condition") if ($condition >=0 and $event == 0);
  return ($cmd,"");
}

sub
ParseCommandsDoIf($$$)
{
  my($hash,$tailBlock,$eval) = @_;
  my $pn=$hash->{NAME};
  my $currentBlock="";
  my $beginning="";
  my $err="";
  my $pos=0;
  my $last_error="";
  my $ifcmd;
  my $ret;
  
  while ($tailBlock ne "") {
    if ($tailBlock=~ /^\s*\{/) { # perl block
      ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]'); 
      return ($currentBlock,$err) if ($err);
      if ($currentBlock ne "") {
         ($currentBlock,$err)=ReplaceAllReadingsDoIf($hash,$currentBlock,-1,$eval);
         return ($currentBlock,$err) if ($err);
         if ($eval) {
           ($currentBlock,$err)=EvalAllDoIf($currentBlock);
           return ($currentBlock,$err) if ($err);
         }
      }
      $currentBlock="{".$currentBlock."}";
    } elsif ($tailBlock =~ /^\s*IF/) {
      my $ifcmd="";
      ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\(\)]'); #condition
      return ($currentBlock,$err) if ($err);
      $ifcmd.=$beginning."(".$currentBlock.")";
      ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\(\)]'); #if case
      return ($currentBlock,$err) if ($err);
      $ifcmd.=$beginning."(".$currentBlock.")";
      if ($tailBlock =~ /^\s*ELSE/) {
        ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\(\)]'); #else case
        return ($currentBlock,$err) if ($err);
      $ifcmd.=$beginning."(".$currentBlock.")";
      }
      $currentBlock=$ifcmd;
    } else {
      if ($tailBlock =~ /^\s*\(/) { # remove bracket  
          ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\(\)]'); 
          return ($currentBlock,$err) if ($err);
          #$tailBlock=substr($tailBlock,pos($tailBlock)) if ($tailBlock =~ /^\s*,/g);
      } elsif ($tailBlock =~ /,/g) {
            $pos=pos($tailBlock)-1;
            $currentBlock=substr($tailBlock,0,$pos);
            $tailBlock=substr($tailBlock,$pos+1);
      } else {
          $currentBlock=$tailBlock;
          $tailBlock="";
        }
      if ($currentBlock ne "") {
         ($currentBlock,$err)=ReplaceAllReadingsDoIf($hash,$currentBlock,-1,$eval);
         return ($currentBlock,$err) if ($err);
         if ($eval) {
           ($currentBlock,$err)=EvalAllDoIf($currentBlock);
           return ($currentBlock,$err) if ($err);
         }
      }
    }
    if ($eval) {
      if ($ret = AnalyzeCommandChain(undef,$currentBlock)) {
        Log3 $pn,2 , "$pn: $currentBlock: $ret";
        $last_error.="$currentBlock: $ret ";
      }
    }
    $tailBlock=substr($tailBlock,pos($tailBlock)) if ($tailBlock =~ /^\s*,/g);
  }
  return("",$last_error);
}

sub
DOIF_CheckTimers($$$$$)
{
  my $i=0;
  my @nrs;
  my @times;
  my $nr=0;
  my $days="";
  my $err;
  my $beginning;
  my $pos;
  my $time;
  my $block;
  my $result;
  my ($hash,$timer,$condition,$trigger,$timerarray)=@_;
  $timer =~ s/\s//g;
  while ($timer ne "") {
     if ($timer=~ /^\+\(/) { 
      ($beginning,$time,$err,$timer)=GetBlockDoIf($timer,'[\(\)]'); 
      return ($time,$err) if ($err);
      $time="+(".$time.")";
      ($result,$err)=ReplaceAllReadingsDoIf($hash,$time,-3,0);
      return ($time,$err) if ($err);
    } elsif ($timer=~ /^\(/) { 
      ($beginning,$time,$err,$timer)=GetBlockDoIf($timer,'[\(\)]'); 
      return ($time,$err) if ($err);
      $time="(".$time.")";
      ($result,$err)=ReplaceAllReadingsDoIf($hash,$time,-3,0);
      return ($time,$err) if ($err);
    } elsif ($timer=~ /^\{/) { 
      ($beginning,$time,$err,$timer)=GetBlockDoIf($timer,'[\{\}]'); 
      return ($time,$err) if ($err);
      $time="{".$time."}";
    } elsif ($timer=~ m/^\+\[([0-9]+)\]:([0-5][0-9])/g) {
      $pos=pos($timer);
      $time=substr($timer,0,$pos);
      $timer=substr($timer,$pos);
    } elsif ($timer=~ /^\+\[/) { 
      ($beginning,$time,$err,$timer)=GetBlockDoIf($timer,'[\[\]]'); 
      return ($time,$err) if ($err);
      $time="+[".$time."]";
      ($result,$err)=ReplaceAllReadingsDoIf($hash,$time,-3,0);
      return ($time,$err) if ($err);
    } elsif ($timer=~ /^\[/) { 
      ($beginning,$time,$err,$timer)=GetBlockDoIf($timer,'[\[\]]'); 
      return ($time,$err) if ($err);
      $time="[".$time."]";
      ($result,$err)=ReplaceAllReadingsDoIf($hash,$time,-3,0);
      return ($time,$err) if ($err);
    } elsif ($timer =~ /-/g) {
      $pos=pos($timer)-1;
      $time=substr($timer,0,$pos);
      $timer=substr($timer,$pos);
    } else {
      ($time,$days)=split(/\|/,$timer);
      $timer="";
    }
    $times[$i]=$time;
    $nrs[$i++]=$hash->{helper}{last_timer}++;
    if ($timer) {
      if ($timer =~ /\-/g) {
        $timer=substr($timer,pos($timer));
      } elsif ($timer =~ /\|/g) {
        $days=substr($timer,pos($timer));
        $timer="";
      } else {
        return ($timer,"wrong time format");
      }
    }      
  }  
  $days = "" if (!defined ($days));
  for (my $j=0; $j<$i;$j++) {
    $nr=$nrs[$j];
    $time=$times[$j];
    $time .=":00" if ($time =~ m/^[0-9][0-9]:[0-5][0-9]$/);
    $hash->{timer}{$nr}=0;
    $hash->{time}{$nr}=$time;
    $hash->{timeCond}{$nr}=$condition;
    $hash->{days}{$nr}=$days if ($days ne "");
    ${$timerarray}[$nr]={hash=>$hash,nr=>$nr};
    if ($init_done) {
      $err=(DOIF_SetTimer("DOIF_TimerTrigger",\${$timerarray}[$nr]));
      return($hash->{time}{$nr},$err) if ($err);
    }
    $hash->{timers}{$condition}.=" $nr " if ($trigger);
    $hash->{timerfunc}{$nr}=\${$timerarray}[$nr];
  }
  if ($i == 2) {
    $block='DOIF_time($hash,$hash->{realtime}{'.$nrs[0].'},$hash->{realtime}{'.$nrs[1].'},$wday,$hms,"'.$days.'")';
  } else {
    $block='DOIF_time_once($hash,$hash->{timer}{'.$nrs[0].'},$wday,"'.$days.'")';
  }
  return ($block,"");
}

sub
DOIF_time($$$$$$)
{
  my $ret=0;
  my ($hash,$begin,$end,$wday,$hms,$days)=@_;
  my $err;
  ($days,$err)=ReplaceAllReadingsDoIf($hash,$days,-1,1);
  if ($err) {
    my $errmsg="error in days: $err";
    Log3 ($hash->{NAME},2 , "$hash->{NAME}: $errmsg");
    readingsSingleUpdate ($hash, "error", $errmsg,1);
    return 0;
  }
  my $we=DOIF_we($wday);
  if ($end gt $begin) {
    if ($hms ge $begin and $hms lt $end) {
      $ret=1; 
    }    
  } else {
    if ($hms ge $begin) {
      $ret=1;
    } elsif ($hms lt $end) {
      $wday=1 if ($wday-- == -1);
      $we=DOIF_we($wday);
      $ret=1; 
    } 
  }
  if ($ret == 1) {
    return 1 if ($days eq "" or $days =~ /$wday/ or ($days =~ /7/ and $we) or ($days =~ /8/ and !$we));
  }
  return 0;
}  

sub
DOIF_time_once($$$$)
{
  my ($hash,$flag,$wday,$days)=@_;
  my $err;
  ($days,$err)=ReplaceAllReadingsDoIf($hash,$days,-1,1);
  if ($err) {
    my $errmsg="error in days: $err";
    Log3 ($hash->{NAME},2 , "$hash->{NAME}: $errmsg");
    readingsSingleUpdate ($hash, "error", $errmsg,1);
    return 0;
  }
  my $we=DOIF_we($wday);
  if ($flag) {
    return 1 if ($days eq "" or $days =~ /$wday/ or ($days =~ /7/ and $we) or ($days =~ /8/ and !$we));
  }
  return 0;  
}  

############################
sub
DOIF_SetState($$$$$)
{
  my ($hash,$nr,$subnr,$event,$last_error)=@_;
  my $pn=$hash->{NAME};
  my $cmdNr="";
  my $cmd="";
  my $err="";
  my $attr=AttrVal($hash->{NAME},"cmdState","");
  my $state=AttrVal($hash->{NAME},"state","");
  my @cmdState=split(/\|/,$attr);
  return undef if (AttrVal($hash->{NAME},"disable",""));
  $nr=ReadingsVal($pn,"cmd_nr",0)-1 if (!$event);
  
  if ($nr!=-1) {
    $cmdNr=$nr+1;
    if (defined $hash->{do}{$nr}{$subnr+1}) {
      $cmd="cmd_".$cmdNr."_".($subnr+1);
    } else {
      if ($attr) {
        $cmd=$cmdState[$nr] if (defined ($cmdState[$nr]));
      } else {
        $cmd="cmd_$cmdNr";
      }
    }
  }
  readingsBeginUpdate  ($hash);
  if ($event) {
    readingsBulkUpdate($hash,"cmd_nr",$cmdNr);
    if (defined $hash->{do}{$nr}{1}) {
      readingsBulkUpdate($hash,"cmd_seqnr",$subnr+1)
      
    } else {
      delete ($defs{$hash->{NAME}}{READINGS}{cmd_seqnr});
    }
    readingsBulkUpdate($hash,"cmd_event",$event);
    if ($last_error) {
      readingsBulkUpdate($hash,"error",$last_error);
    } else {
      delete ($defs{$hash->{NAME}}{READINGS}{error});
    }
  }
  
  if ($state and !defined $hash->{do}{$nr}{$subnr+1}) {
    my $stateblock='\['.$pn.'\]';
    $state =~ s/$stateblock/$cmd/g; 
    ($state,$err)=ReplaceAllReadingsDoIf($hash,$state,-1,1);
    if ($err) {
      Log3 $pn,2 , "$pn: error in state: $err" if ($err);
      $state=$err;
    } else {
      ($state,$err)=EvalAllDoIf($state);
      if ($err) {
        Log3 $pn,2 , "$pn: error in state: $err" if ($err);
        $state=$err;
      }
    }      
  } else {
    $state=$cmd;
  }
  readingsBulkUpdate($hash, "state", $state);
  readingsEndUpdate    ($hash, 1);
}

sub
DOIF_we($) {
  my ($wday)=@_;
  my $we = (($wday==0 || $wday==6) ? 1 : 0);
  if(!$we) {
    my $h2we = $attr{global}{holiday2we};
    $we = 1 if($h2we && $value{$h2we} && $value{$h2we} ne "none");
  }
  return $we;
}

sub
DOIF_CheckCond($$)
{
  my ($hash,$condition) = @_;
  my $err="";
  my ($seconds, $microseconds) = gettimeofday();
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime($seconds);
  my $hms = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
  my $hm = sprintf("%02d:%02d", $hour, $min);
  my $device;
  my $reading;
  my $internal;
  my $we=DOIF_we($wday);
  
  $month++;
  $year+=1900;
  if (defined ($hash->{readings}{$condition})) {
    foreach my $devReading (split(/ /,$hash->{readings}{$condition})) {
      ($device,$reading)=(split(":",$devReading));
      return (0,"reading does not exist: [$device:$reading]") if ($devReading and !defined($defs{$device}{READINGS}{$reading}));
    }
  }
  if (defined ($hash->{internals}{$condition})) {
    foreach my $devInternal (split(/ /,$hash->{internals}{$condition})) {
      ($device,$internal)=(split(":",$devInternal));
      return (0,"internal does not exist: [$device:$internal]") if ($devInternal and !defined($defs{$device}{$internal}));
    }
  }
  my $ret = eval $hash->{condition}{$condition};
  if($@){
    $err = "perl error in condition: $hash->{condition}{$condition}: $@";
    $ret = 0;
  }
  return ($ret,$err);
}

sub
DOIF_cmd ($$$$)
{
  my ($hash,$nr,$subnr,$event)=@_;
  my $pn = $hash->{NAME};
  my $ret;
  my $cmd;
  my $err="";
  my $repeatnr;
  my $last_cmd=ReadingsVal($pn,"cmd_nr",0)-1;
  my @repeatsame=split(/:/,AttrVal($pn,"repeatsame",""));
  my @cmdpause=split(/:/,AttrVal($pn,"cmdpause",""));
  my @waitsame=split(/:/,AttrVal($pn,"waitsame",""));
  my ($seconds, $microseconds) = gettimeofday();
  if ($cmdpause[$nr] and $subnr==0) {
    return undef if ($seconds - time_str2num(ReadingsTimestamp($pn, "state", "1970-01-01 01:00:00")) < $cmdpause[$nr]);
  }
  if (AttrVal($pn,"repeatsame","")) {
    if ($subnr == 0) {
      if ($repeatsame[$nr]) {
        $repeatnr=ReadingsVal($pn,"cmd_count",0);
        if ($last_cmd == $nr) {
          if ($repeatnr < $repeatsame[$nr]) {
            $repeatnr++;
          } else {
            return undef;
          }
        } else {
          $repeatnr=1;
        }
        readingsSingleUpdate ($hash, "cmd_count", $repeatnr,1);
      } else {
        return undef if ($last_cmd == $nr and $subnr==0 and (AttrVal($pn,"do","") ne "always" and AttrVal($pn,"do","") ne "resetwait"));
        delete ($defs{$hash->{NAME}}{READINGS}{cmd_count});
      }
    }
  }
  if (AttrVal($pn,"waitsame","")) {
    if ($subnr == 0) {
      if ($waitsame[$nr]) {
        my $cmd_nr="cmd_".($nr+1);
        if (ReadingsVal($pn,"waitsame","") eq $cmd_nr) {
          if ($seconds - time_str2num(ReadingsTimestamp($pn, "waitsame", "1970-01-01 01:00:00"))  > $waitsame[$nr]) {
            readingsSingleUpdate ($hash, "waitsame", $cmd_nr,1);
            return undef;
          }
        } else {
          readingsSingleUpdate ($hash, "waitsame", $cmd_nr,1);
          return undef;
        }
      } 
      delete ($defs{$hash->{NAME}}{READINGS}{waitsame});
    }
  }
  if ($hash->{do}{$nr}{$subnr}) { 
    ($cmd,$err)=ParseCommandsDoIf($hash,$hash->{do}{$nr}{$subnr},1);
  }
  DOIF_SetState ($hash,$nr,$subnr,$event,$err);
  if (defined $hash->{do}{$nr}{++$subnr}) {
    my $last_cond=ReadingsVal($pn,"cmd_nr",0)-1;
    if (DOIF_SetSleepTimer($hash,$last_cond,$nr,$subnr,$event,-1)) {
      DOIF_cmd ($hash,$nr,$subnr,$event);
    }
  }
  return undef;
}


sub
DOIF_Trigger ($$$)
{
  my ($hash,$device,$timerNr)= @_;
  my $ret;
  my $err;
  my $doelse=0;
  my $event;
  my $pn=$hash->{NAME};
  my $max_cond=keys %{$hash->{condition}};
  my $last_cond=ReadingsVal($pn,"cmd_nr",0)-1;
  for (my $i=0; $i<$max_cond;$i++) {
    if ($device eq "") {# timer
      next if (!defined ($hash->{timers}{$i}));
      next if ($hash->{timers}{$i} !~ / $timerNr /);
      $event="timer_".($timerNr+1);
    } else { #event
      next if (!defined ($hash->{devices}{$i}));
      next if ($hash->{devices}{$i} !~ / $device /);
      $event="$device";
    }
    if (($ret,$err)=DOIF_CheckCond($hash,$i)) {
      if ($err) {
        Log3 $hash->{Name},2,"$hash->{NAME}: $err";
        readingsSingleUpdate ($hash, "error", $err,1);
        return undef;
      }
      if ($ret) {
        if (DOIF_SetSleepTimer($hash,$last_cond,$i,0,$device,$timerNr)) {
          DOIF_cmd ($hash,$i,0,$event);
          return 1;
        } else {
          return undef;
        }
      } else {
        $doelse = 1;
      }
    }
  }
  if ($doelse) {  #DOELSE
    if (defined ($hash->{do}{$max_cond}{0}) or ($max_cond == 1 and !(AttrVal($pn,"do","") or AttrVal($pn,"repeatsame","")))) {  #DOELSE
      if (DOIF_SetSleepTimer($hash,$last_cond,$max_cond,0,$device,$timerNr)) {
        DOIF_cmd ($hash,$max_cond,0,$event) ;
        return 1;
      }
    }
  }
  return undef;
}

sub
DOIF_Notify($$)
{
  my ($hash, $dev) = @_;
  my $pn = $hash->{NAME};
  return "" if($attr{$pn} && $attr{$pn}{disable});
  return "" if (!$dev->{NAME});
  my $device;
  my $reading;
  my $internal;
  my $ret;
  my $err;
  
  if ($dev->{NAME} eq "global" and ((EventDoIf("global","global",deviceEvents($dev, AttrVal("global", "addStateEvent", 0)),"INITIALIZED")) or EventDoIf("global","global",deviceEvents($dev, AttrVal("global", "addStateEvent", 0)),"REREADCFG")))
  {
    $hash->{helper}{globalinit}=1;
    if ($hash->{helper}{last_timer} > 0){
      for (my $j=0; $j<$hash->{helper}{last_timer};$j++)
      {
        DOIF_SetTimer("DOIF_TimerTrigger",$hash->{timerfunc}{$j});
      }
    }
  }
  
  if (($hash->{itimer}{all}) and $hash->{itimer}{all} =~ / $dev->{NAME} /) {
    for (my $j=0; $j<$hash->{helper}{last_timer};$j++)
    {
      if ($hash->{time}{$j} =~ /\[$dev->{NAME}\]|\[$dev->{NAME}:/) {
        DOIF_SetTimer("DOIF_TimerTrigger",$hash->{timerfunc}{$j});
      } 
    }
  }
  
  return "" if (!$hash->{devices}{all} and !$hash->{state}{device});
  return "" if (!$hash->{helper}{globalinit});
  return "" if (ReadingsVal($pn,"mode","") eq "disabled");

  if (($hash->{devices}{all}) and $hash->{devices}{all} =~ / $dev->{NAME} /) {
    readingsSingleUpdate ($hash, "Device",$dev->{NAME},0);
    #my $events = deviceEvents($dev, AttrVal($dev->{NAME}, "addStateEvent", 0));
    #readingsSingleUpdate ($hash, "Event","@{$events}",0);
    
    if ($hash->{readings}{all}) {
      foreach my $item (split(/ /,$hash->{readings}{all})) {
        ($device,$reading)=(split(":",$item));
        readingsSingleUpdate ($hash, "e_".$dev->{NAME}."_".$reading,$defs{$device}{READINGS}{$reading}{VAL},0) if ($item and $device eq $dev->{NAME} and defined ($defs{$device}{READINGS}{$reading}));
      }
    }
    
    if ($hash->{internals}{all}) {
      foreach my $item (split(/ /,$hash->{internals}{all})) {
        ($device,$internal)=(split(":",$item));
        readingsSingleUpdate ($hash, "e_".$dev->{NAME}."_".$internal,$defs{$device}{$internal},0) if ($item and $device eq $dev->{NAME} and defined ($defs{$device}{$internal}));
      }
    }
    #my ($seconds, $microseconds) = gettimeofday();
    #if ($hash->{helper}{last_event_time}) {
    #  return undef if (($seconds-$hash->{helper}{last_event_time}) < AttrVal($pn,"eventpause",0));
    #}
    #$hash->{helper}{last_event_time}=$seconds;
    if ($hash->{trigger}{all}) {
      foreach my $item (split(/ /,$hash->{trigger}{all})) {
        my $events = deviceEvents($dev, AttrVal($dev->{NAME}, "addStateEvent", 0));
        $hash->{helper}{triggerEvents}=$events;
        $hash->{helper}{triggerDev}=$dev->{NAME};
        readingsSingleUpdate ($hash, "e_".$dev->{NAME}."_events","@{$events}",0);
      }
    }
    $ret=DOIF_Trigger($hash,$dev->{NAME},-1);
  }
  if (($hash->{state}{device}) and $hash->{state}{device} =~ / $dev->{NAME} / and !$ret) {
    DOIF_SetState($hash,"",0,"","");
  }
  return undef;
} 
  
sub
DOIF_TimerTrigger ($)
{
  my ($timer)=@_;
  my $nr=${$timer}->{nr};
  my $hash=${$timer}->{hash};
  my $pn = $hash->{NAME};
  my $ret;
# if (!AttrVal($hash->{NAME},"disable","")) {
  if (ReadingsVal($pn,"mode","") ne "disabled") {
    $hash->{timer}{$nr}=1;
    $ret=DOIF_Trigger ($hash,"",$nr);
    $hash->{timer}{$nr}=0;
  }
  DOIF_SetTimer("DOIF_TimerTrigger",$timer) if (!AttrVal($hash->{NAME},"disable",""));
  return($ret);
}

sub
DOIF_DetTime($)
{
  my ($timeStr) = @_;
  my $rel=0;
  my $align;
  my $hr=0;
  my $err;
  my $h=0;
  my $m=0;
  my $s=0;
  my $fn;
  if (substr($timeStr,0,1) eq "+") {
    $timeStr=substr($timeStr,1);
    $rel=1;
  }
  my ($now, $microseconds) = gettimeofday();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
  if($timeStr =~ m/^\[([0-9]+)\]:([0-5][0-9])$/) {
    $hr=$1;
    $rel=0;
    $align=$2;
  } elsif ($timeStr =~ m/^:([0-5][0-9])$/) {
    $align=$1;
  } elsif ($timeStr =~ m/^(\-?([0-9]+))$/) {
    $s=$1;
  } else {
    if ($timeStr =~ m/^\$hms$/) {
      $timeStr = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
    } elsif ($timeStr =~ m/^\$hm$/) {
      $timeStr = sprintf("%02d:%02d", $hour, $min);  
    } 
    ($err, $h, $m, $s, $fn) = GetTimeSpec($timeStr);
    return $err if ($err);
  }
  if (defined ($align)) {
    if ($rel) {
      if ($align > 0) {
        $m = (int($min/$align)+1)*$align;
        if ($m>=60) {
          $h = $hour+1;
          $m = 0;
        } else {
          $h = $hour;
        }
      }
      $rel=0;
    } else {
      $m=$align;
      if ($hr > 1) {
        $h = (int($hour/$hr)+1)*$hr;
        $h = 0 if ($h >=24);
      } else {
        if ($m <= $min) {
          $h = $hour+1;
        } else {
          $h = $hour;
        }
      }
    }
  }
  my $second = $h*3600+$m*60+$s;
  if ($second == 0 and $rel) {
    $err = "null is not allowed on a relative time";
  }
  return ($err, ($rel and !defined ($align)), $second);
}

sub
DOIF_CalcTime($)
{
  my ($block)= @_;
  my $tailBlock;
  my $beginning;
  my $err;
  my $cmd="";
  my $rel="";
  my $relGlobal=0;
  my $reading;
  my $internal;
  my $device;
  my $pos;
  my $ret;
  if ($block=~ m/^\+\[([0-9]+)\]:([0-5][0-9])$/) {
    ($err,$rel,$block)=DOIF_DetTime($block);
    return ($block,$err,$rel);
  } elsif ($block =~ /^\+\(/ or $block =~ /^\+\[/) {
    $relGlobal=1;
    #$pos=pos($block);
    $block=substr($block,1);
  } 

  if ($block =~ /^\(/) {
    ($beginning,$tailBlock,$err,$tailBlock)=GetBlockDoIf($block,'[\(\)]');
    return ($tailBlock,$err) if ($err);
  } else { 
    if ($block =~ /^\[/) {
      ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($block,'[\[\]]');
      return ($block,$err) if ($err);
      ($block,$err,$device,$reading,$internal)=ReplaceReadingEvalDoIf($block,1);
      return ($block,$err) if ($err);
    }
    ($err,$rel,$block)=DOIF_DetTime($block);
    $rel=1 if ($relGlobal);
    return ($block,$err,$rel);
  }
  $tailBlock=$block;
  while ($tailBlock ne "") {
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\[\]]');
    return ($block,$err) if ($err);
    if ($block ne "") {
      if ($block =~ /^\??[a-z0-9._]*[a-z._]+[a-z0-9._]*($|:.+$)/i) {
        ($block,$err,$device,$reading,$internal)=ReplaceReadingEvalDoIf($block,1);
        return ($block,$err) if ($err);
      }
      ($err,$rel,$block)=DOIF_DetTime($block);
    }
    $cmd.=$beginning.$block;
  }
  $tailBlock=$cmd;
  $cmd="";
  while ($tailBlock ne "") {
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]');
    return ($block,$err) if ($err);
    if ($block ne "") {
       $ret = eval $block;
       return($block." ",$@) if ($@);
       $block=$ret;
       ($err,$rel,$block)=DOIF_DetTime($block);
    }
    $cmd.=$beginning.$block;
  }
  $ret = eval $cmd;
  return($cmd." ",$@) if ($@);
  return ($ret,"null is not allowed on a relative time",$relGlobal) if ($ret == 0 and $relGlobal);
  return ($ret,"",$relGlobal);
}

sub
DOIF_SetTimer($$)
{
  my ($func, $timer) = @_;
  my $nr=${$timer}->{nr};
  my $hash=${$timer}->{hash};
  my $timeStr=$hash->{time}{$nr};
  my $cond=$hash->{timeCond}{$nr};
  my $next_time;
  
  my ($second,$err, $rel)=DOIF_CalcTime($timeStr);
  if ($err)
  {
      readingsSingleUpdate ($hash,"timer_".($nr+1)."_c".($cond+1),"error: ".$err,0);
      RemoveInternalTimer($timer);
      $hash->{realtime}{$nr}="00:00:00";
      return $err;
  }
  my ($now, $microseconds) = gettimeofday();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
  my $isdst_now=$isdst;

  my $sec_today = $hour*3600+$min*60+$sec;
  my $midnight = $now-$sec_today;
  if ($rel) {
    $next_time =$now+$second;
  } else {
    $next_time = $midnight+$second;
  }
  $next_time+=86400 if ($second <= $sec_today and !$rel);
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($next_time);
  if ($isdst_now != $isdst) {
    if ($isdst_now == 1) {
      $next_time+=3600 if ($isdst == 0);
    } else {
      $next_time-=3600 if ($isdst == 1); 
    }
  }
  if ($next_time < $now) {
    readingsSingleUpdate ($hash,"timer_".($nr+1)."_c".($cond+1),"back to the past ist not allowed",0);
    return("timer_".($nr+1)."_c".($cond+1),"back to the past ist not allowed");
  } else {
    my $next_time_str=strftime("%d.%m.%Y %H:%M:%S",localtime($next_time));
    $next_time_str.="\|".$hash->{days}{$nr} if (defined ($hash->{days}{$nr}));
    readingsSingleUpdate ($hash,"timer_".($nr+1)."_c".($cond+1),$next_time_str,0);
    $hash->{realtime}{$nr}=strftime("%H:%M:%S",localtime($next_time));
    RemoveInternalTimer($timer);
    InternalTimer($next_time, $func, $timer, 0);
  }
  return undef;
}

sub
DOIF_SetSleepTimer($$$$$$)
{
  my ($hash,$last_cond,$nr,$subnr,$device,$timerNr)=@_;
  my $pn = $hash->{NAME};
  my $sleeptimer=$hash->{helper}{sleeptimer};
  my @waitdel=split(/:/,AttrVal($pn,"waitdel",""));
  my @waitdelsubnr=split(/,/,defined $waitdel[$sleeptimer] ? $waitdel[$sleeptimer] : "");
  my $err;
  
  if ($sleeptimer != -1 and (($sleeptimer != $nr or AttrVal($pn,"do","") eq "resetwait") or ($sleeptimer == $nr and $waitdelsubnr[$subnr]))) {
    RemoveInternalTimer($hash);
    #delete ($defs{$hash->{NAME}}{READINGS}{wait_timer});
    readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
    $hash->{helper}{sleeptimer}=-1;
    $subnr=$hash->{helper}{sleepsubtimer} if ($hash->{helper}{sleepsubtimer}!=-1);
    return 0 if ($sleeptimer == $nr and $waitdelsubnr[$subnr]);
  }
    
  if ($timerNr >= 0 and !AttrVal($pn,"timerWithWait","")) {#Timer
    if ($last_cond != $nr or AttrVal($pn,"do","") eq "always" or AttrVal($pn,"repeatsame","")) {
      return 1;
    } else {
      return 0;
    }
  } 
 
  if ($hash->{helper}{sleeptimer} == -1 and ($last_cond != $nr or $subnr > 0 or AttrVal($pn,"do","") eq "always" or AttrVal($pn,"do","") eq "resetwait" or AttrVal($pn,"repeatsame",""))) {
    my @sleeptimer=split(/:/,AttrVal($pn,"wait",""));
    my $sleeptime=0;
    if ($waitdelsubnr[$subnr]) { 
      $sleeptime = $waitdelsubnr[$subnr];
    } else {
      my @sleepsubtimer=split(/,/,defined $sleeptimer[$nr]? $sleeptimer[$nr]: "");
      if ($sleepsubtimer[$subnr]) {
        $sleeptime=$sleepsubtimer[$subnr];
      }
    }
    ($sleeptime,$err)=ReplaceAllReadingsDoIf($hash,$sleeptime,-1,1);
    if ($err) {
      Log3 $pn,2 , "$pn: error in wait: $err" if ($err);
      $sleeptime=0;
    } else {
       my $ret = eval $sleeptime;
       if ($@) {
         Log3 ($pn,2 , "$pn: error in wait: $sleeptimer: $@");
         $sleeptime=0;
       } else {
         $sleeptime=$ret;
       }
    } 
    if ($sleeptime) {
      my ($seconds, $microseconds) = gettimeofday();
      my $next_time = $seconds+$sleeptime;
      $hash->{helper}{sleeptimer}=$nr;
      $hash->{helper}{sleepsubtimer}=$subnr;
      $device="timer_".($timerNr+1) if ($timerNr >= 0);
      $hash->{helper}{sleepdevice}=$device;
      my $cmd_nr=$nr+1;
      if (defined $hash->{do}{$nr}{1}) {
        my $cmd_subnr=$subnr+1;
        readingsSingleUpdate ($hash,"wait_timer",strftime("%d.%m.%Y %H:%M:%S cmd_$cmd_nr"."_$cmd_subnr $device",localtime($next_time)),1);
      } else {
        readingsSingleUpdate ($hash,"wait_timer",strftime("%d.%m.%Y %H:%M:%S cmd_$cmd_nr $device",localtime($next_time)),1);
      }
      InternalTimer($next_time, "DOIF_SleepTrigger",$hash, 0);
      return 0;
    } else {
      return 1;
    }
  } else {
    return 0;
  }
}

sub
DOIF_SleepTrigger ($)
{
  my ($hash)=@_;
  my $sleeptimer=$hash->{helper}{sleeptimer};
  my $sleepsubtimer=$hash->{helper}{sleepsubtimer};
  $hash->{helper}{sleeptimer}=-1;
  $hash->{helper}{sleepsubtimer}=-1;
  my $pn = $hash->{NAME};
  readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
# if (!AttrVal($hash->{NAME},"disable","")) {
  if (ReadingsVal($pn,"mode","") ne "disable") {
    DOIF_cmd ($hash,$sleeptimer,$sleepsubtimer,$hash->{helper}{sleepdevice});
  }
  
  return undef;
}

#############################
sub
CmdDoIf($$)
{
  my ($hash, $tail) = @_;
  my $cond="";
  my $err="";
  my $if_cmd="";
  my $if_cmd_ori="";
  my $else_cmd="";
  my $else_cmd_ori="";
  my $tailBlock;
  my $eval="";
  my $beginning;
  my $i=0;
  my $j=0;
  my $last_do;

  if (!$tail) {
    $tail="";
  } else {
    $tail =~ s/(##.*\n)|(##.*$)|\n//g;;
  }
  
#  if (defined $hash->{helper}) #def modify
  if ($init_done)
  {
    DOIF_delTimer($hash);
    DOIF_delAll ($hash);
    readingsSingleUpdate ($hash,"state","initialized",1);
    $hash->{helper}{globalinit}=1;
  }
  #$hash->{STATE} = 'initialized';
  $hash->{helper}{last_timer}=0;
  $hash->{helper}{sleeptimer}=-1;
#  if ($init_done) {  
#    $hash->{helper}{globalinit}=1;
#  }
  
  while ($tail ne "") {
    return($tail, "no left bracket of condition") if ($tail !~ /^ *\(/);
    #condition
    ($beginning,$cond,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
    return ($cond,$err) if ($err); 
    ($cond,$err)=ReplaceAllReadingsDoIf($hash,$cond,$i,0);
    return ($cond,$err) if ($err); 
    return ($tail,"no condition") if ($cond eq "");
    $hash->{condition}{$i}=$cond;
    #DOIF
    $if_cmd_ori="";
    $j=0;
    while ($tail =~ /^\s*\(/) {
      ($beginning,$if_cmd_ori,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
      return ($if_cmd_ori,$err) if ($err);
      ($if_cmd,$err)=ParseCommandsDoIf($hash,$if_cmd_ori,0);
      return ($if_cmd,$err) if ($err);
      #return ($tail,"no commands") if ($if_cmd eq "");
      $hash->{do}{$i}{$j++}=$if_cmd_ori;
    } 
    $hash->{do}{$i}{0}=$if_cmd_ori if ($j==0); #do without brackets 
    $last_do=$i;
    if (length($tail)) {
      $tail =~ /^\s*DOELSEIF/g;
      if (pos($tail)) {
        $tail=substr($tail,pos($tail));
        if (!length($tail)) {
          return ($tail,"no DOELSEIF block");
        }
      } else {
        last if ($tail =~ /^\s*DOELSE/);
        return ($tail,"expected DOELSEIF or DOELSE");
      }
    }
    $i++;
  }
  #DOELSE
  if (length($tail)) {
    $tail =~ /^\s*DOELSE/g;
    if (pos($tail)) {
      $tail=substr($tail,pos($tail));
    } else {
      return ($tail,"expected DOELSE");
    }
    $j=0;
    while ($tail =~ /^\s*\(/) {
      ($beginning,$else_cmd_ori,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
       return ($else_cmd_ori,$err) if ($err);
       ($else_cmd,$err)=ParseCommandsDoIf($hash,$else_cmd_ori,0);
       return ($else_cmd,$err) if ($err);
       $hash->{do}{$last_do+1}{$j++}=$else_cmd_ori;
    }
    $hash->{do}{$last_do+1}{0}=$else_cmd_ori if ($j==0); #doelse without brackets
  }
  return("","")
}

sub
DOIF_Define($$$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $cmd) = split(/[\s]+/, $def, 3);
  return undef if (AttrVal($hash->{NAME},"disable",""));
  my ($msg,$err)=CmdDoIf($hash,$cmd);
  if ($err ne "") {
    $msg=$cmd if (!$msg);
    my $errmsg="$name $type: $err: $msg";
    return $errmsg;
  } else {
    return undef;
  }
}

#################################

sub
DOIF_Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};
  my $ret="";
  if (($a[0] eq "set" and $a[2] eq "disable" and ($a[3] eq "0")) or (($a[0] eq "del" and $a[2] eq "disable")))
  {
    my $cmd = $defs{$hash->{NAME}}{DEF};
    my ($msg,$err)=CmdDoIf($hash,$cmd);
    if ($err ne "") {
      $msg=$cmd if (!$msg);
      return ("$err: $msg");
    }
  } elsif($a[0] eq "set" and $a[2] eq "disable" and $a[3] eq "1") {
    DOIF_delTimer($hash);
    DOIF_delAll ($hash);
    readingsSingleUpdate ($hash,"state","deactivated",1);
  } elsif($a[0] eq "set" && $a[2] eq "state") {
      delete ($hash->{state}{device});
      my ($block,$err)=ReplaceAllReadingsDoIf($hash,$a[3],-2,0);
      return $err if ($err);
  } elsif($a[0] eq "set" && $a[2] eq "wait") {
      RemoveInternalTimer($hash);
      #delete ($defs{$hash->{NAME}}{READINGS}{wait_timer});
      readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
      $hash->{helper}{sleeptimer}=-1;
  } elsif($a[0] eq "set" && $a[2] eq "initialize") {
    readingsSingleUpdate ($hash,"state",$a[3],1);
    readingsSingleUpdate ($hash,"cmd_nr","0",1);
  } elsif($a[0] eq "del" && $a[2] eq "repeatsame") {
    delete ($defs{$hash->{NAME}}{READINGS}{cmd_count});
  } elsif($a[0] eq "del" && $a[2] eq "waitsame") {
    delete ($defs{$hash->{NAME}}{READINGS}{waitsame});
  }
  return undef;
}

sub
DOIF_Undef
{
  my ($hash, $name) = @_;
  $hash->{DELETED} = 1;
  DOIF_delTimer($hash);
  return undef;
}



sub
DOIF_Set($@)
{
  my ($hash, @a) = @_;
  my $pn = $hash->{NAME};
  my $arg = $a[1];
  my $value = (defined $a[2]) ? $a[2] : "";
  my $ret="";
  if ($arg eq "disable" or  $arg eq "initialize") {
    if (AttrVal($hash->{NAME},"disable","")) {
      return ("modul ist deactivated by disable attribut, delete disable attribut first");
    }
  }
  if ($arg eq "disable") {
      readingsBeginUpdate  ($hash);
      readingsBulkUpdate($hash, "state", "disabled");
      readingsBulkUpdate($hash, "mode", "disabled");
      readingsEndUpdate    ($hash, 1);
  } elsif ($arg eq "initialize" ) {
      delete ($defs{$hash->{NAME}}{READINGS}{mode});
      delete ($defs{$hash->{NAME}}{READINGS}{cmd_nr});
      delete ($defs{$hash->{NAME}}{READINGS}{cmd_event});
      readingsSingleUpdate($hash, "state","initialize",1);
  } else {
    return "$pn: unknown argument $a[1], choose one of disable initialize"
  } 
  return $ret;
}


1;

=pod
=begin html

<a name="DOIF"></a>
<h3>DOIF</h3>
<ul>
DOIF is a universal module. It works event- and time-controlled.<br>
<br>
It combines the functionality of a notify, at-, watchdog command with logical queries.<br>
<br>
Complex problems can be solved with this module, which would otherwise be solved only with several modules at different locations in FHEM. This leads to clear solutions and simplifies their maintenance.<br>
<br>
Logical queries are created in conditions using Perl operators.
These are combined with information from states, readings, internals of devices or times in square brackets.
Arbitrary Perl functions can also be specified that are defined in FHEM.
The module is triggered by time or by events information through the Devices specified in the condition.
If a condition is true, the associated FHEM- or Perl commands are executed.<br>
<br>
Syntax:<br>
<br>
<code>define &lt;name&gt; DOIF (&lt;condition&gt;) (&lt;commands&gt;) DOELSEIF (&lt;condition&gt;) (&lt;commands&gt;) DOELSEIF ... DOELSE (&lt;commands&gt;)</code><br>
<br>
The commands are always processed from left to right. There is only one command executed, namely the first, for which the corresponding condition in the processed sequence is true. In addition, only the conditions are checked, which include a matching device of the trigger (in square brackets).<br>
<br>
<b>Features</b><br>
<ol><br>
+ intuitive syntax, as used in branches (if - elseif-....elseif - else) in higher-level languages<br>
+ in the condition of any logical queries can be made as well as perl functions are used (full perl support)<br>
+ it can be any FHEM commands and perl commands are executed<br>
+ syntax checking at the time of definition are identified missing brackets<br>
+ status is specified with <code>[&lt;devicename&gt;]</code>, readings with <code>[&lt;devicename&gt;:&lt;readingname&gt;]</code> or internals with <code>[&lt;devicename&gt;:&&lt;internal&gt;]</code><br>
+ time information on the condition: <code>[HH:MM:SS]</code> or <code>[HH:MM]</code> or <code>[&lt;seconds&gt;]</code><br>
+ indirect time on the condition: <code>[[&lt;devicename&gt;]]</code> or <code>[[&lt;devicename&gt;:&lt;readingname&gt;]]</code> or <code>[{&lt;perl-function&gt;}]</code><br>
+ time calculation on the condition: <code>[(&lt;time calculation in Perl with time syntax specified above&gt;)]</code><br>
+ time intervals: <code>[&lt;begin&gt;-&lt;end&gt;]</code> for <code>&lt;begin&gt;</code> and <code>&lt;end&gt;</code>, the above time format can be selected.<br>
+ relative times preceded by a plus sign <code>[+&lt;time&gt;]</code> or <code>[+&lt;begin&gt;-+&lt;end&gt;]</code> combined with Perl functions<br>
+ weekday control: <code>[&lt;time&gt;|012345678]</code> or <code>[&lt;begin&gt;-&lt;end&gt;|012345678]</code> (0-6 corresponds to Sunday through Saturday) such as 7 for $we and 8 for !$we<br>
+ statuses, readings, internals und time intervals for only queries without trigger with [?...]<br>
+ DOELSEIF cases and DOELSE at the end are optional<br>
+ delay specification with resetting is possible (watchdog function)<br>
+ the execution part can be left out in each case. So that the module can be used for pure status display.<br>
+ definition of the status display with use of any readings or statuses<br>
</ol><br>
<br>
Many examples with english identifiers - see german section. 
<br>
</ul>
=end html
=begin html_DE

<a name="DOIF"></a>
<h3>DOIF</h3>
<ul>
DOIF ist ein universelles Modul, welches sowohl ereignis- als auch zeitgesteuert arbeitet.<br>
<br>
Es vereinigt die Funktionalität eines notify-, at-, watchdog-Befehls in Kombination mit logischen Abfragen unter einem Dach.
Damit können insb. komplexere Problemstellungen innerhalb eines DOIF-Moduls gelöst werden, die sonst nur mit Hilfe einzelner Module an mehreren Stellen in FHEM vorgenommen werden müssten.
Das führt zu übersichtlichen Lösungen und vereinfacht deren Pflege.<br>
<br>
Logische Abfragen werden in Bedingungen mit Hilfe von Perl-Operatoren erstellt.
Diese werden mit Angaben von Stati, Readings, Internals, Events von Devices oder Zeiten in eckigen Klammern kombiniert. Ebenso können beliebige Perl-Funktionen angegeben werden, die in FHEM definiert sind.
Getriggert wird das Modul durch Zeitangaben bzw. durch Ereignisse ausgelöst durch die in der Bedingung angegebenen Devices.
Wenn eine Bedingung wahr wird, so werden die dazugehörigen FHEM- bzw. Perl-Kommandos ausgeführt.<br>
<br>
Syntax:<br>
<br>
<ol><code>define &lt;name&gt; DOIF (&lt;Bedingung&gt;) (&lt;Befehle&gt;) DOELSEIF (&lt;Bedingung&gt;) (&lt;Befehle&gt;) DOELSEIF ... DOELSE (&lt;Befehle&gt;)</code></ol>
<br>
Die Angaben werden immer von links nach rechts abgearbeitet. Zu beachten ist, dass nur die Bedingungen überprüft werden,
die zum ausgelösten Event das dazughörige Device bzw. die dazugehörige Triggerzeit beinhalten.
Kommt ein Device in mehreren Bedingungen vor, so wird immer nur ein Kommando ausgeführt, und zwar das erste,
für das die dazugehörige Bedingung in der abgearbeiteten Reihenfolge wahr ist.<br>
<br>
<u>Einfache Anwendungsbeispiele:</u><ol>
<br>
Fernbedienung (Ereignissteuerung): <code>define di_rc_tv DOIF ([remotecontol] eq "on") (set tv on) DOELSE (set tv off)</code><br>
<br>
Zeitschaltuhr (Zeitsteuerung): <code>define di_clock_radio DOIF ([06:30]) (set radio on) DOELSEIF ([08:00]) (set radio off)</code><br>
<br>
Kombinierte Ereignis- und Zeitsteuerung: <code>define di_lamp DOIF ([06:00-09:00] and [sensor:brightness] &lt; 40) (set lamp on) DOELSE (set lamp off)</code><br>
</ol><br>
<b>Features</b><br>
<ol><br>
+ Syntax angelehnt an Verzweigungen if - elseif - ... - elseif - else in höheren Sprachen<br>
+ Bedingungen werden vom Perl-Interpreter ausgewertet, daher beliebige logische Abfragen möglich<br>
+ Die Perl-Syntax in der Bedingung wird um Angaben von Stati, Readings, Internals, Events oder Zeitangaben in eckigen Klammern erweitert, diese führen zur Triggerung des Moduls<br>
+ Es können beliebig viele DOELSEIF-Angaben gemacht werden, sie sind, wie DOELSE am Ende der Kette, optional<br>
+ Verzögerungsangaben mit Zurückstellung sind möglich (watchdog-Funktionalität)<br>
+ Der Ausführungsteil kann jeweils ausgelassen werden. Damit kann das Modul für reine Statusanzeige genutzt werden<br>
</ol><br>
<b>Lesbarkeit der Definitionen</b><br>
<br>
Da die Definitionen im Laufe der Zeit recht umfangreich werden können, sollten die gleichen Regeln, wie auch beim Programmieren in höheren Sprachen, beachtet werden.
Dazu zählen: das Einrücken von Befehlen, Zeilenumbrüche sowie das Kommentieren seiner Definition, damit man auch später noch die Funktionalität seines Moduls nachvollziehen kann.<br>
<br>
Das Modul unterstützt dazu Einrückungen, Zeilenumbrüche an beliebiger Stelle und Kommentierungen beginnend mit ## bis zum Ende der Zeile.
Die Formatierungen lassen sich im DEF-Editor der Web-Oberfläche vornehmen.<br>
<br>
So könnte eine Definition aussehen:<br>
<br>
<code>define di_Modul DOIF ([Switch1] eq "on" and [Switch2] eq "on")  ## wenn Schalter 1 und Schalter 2 on ist<br>
<br>
<ol>(set lamp on) ## wird Lampe eingeschaltet</ol>
<br>
DOELSE ## im sonst-Fall, also wenn einer der Schalter off ist<br>
<br>
<ol>(set lamp off) ## wird die Lampe ausgeschaltet</ol></code>
<br>
Im Folgenden wird die Funktionalität des Moduls im Einzelnen an vielen praktischen Beispielen erklärt.<br>
<br>
<b>Ereignissteuerung</b><br>
<br>
Vergleichende Abfragen werden, wie in Perl gewohnt, mit Operatoren <code>==, !=, <, <=, >, >=</code> bei Zahlen und mit <code>eq, ne, lt, le, gt, ge, =~, !~</code> bei Zeichenketten angegeben.
Logische Verknüpfungen sollten zwecks Übersichtlichkeit mit <code>and</code> bzw. <code>or</code> vorgenommen werden.
Selbstverständlich lassen sich auch alle anderen Perl-Operatoren verwenden, da die Auswertung der Bedingung vom Perl-Interpreter vorgenommen wird.
Die Reihenfolge der Auswertung wird, wie in höheren Sprachen üblich, durch runde Klammern beeinflusst.
Stati werden mit <code>[&lt;devicename&gt;]</code>, Readings mit <code>[&lt;devicename&gt;:&lt;readingname&gt;]</code>,
Internals mit <code>[&lt;devicename&gt;:&&lt;internal&gt;]</code> angegeben.<br>
<br>
<u>Anwendungsbeispiel</u>: Einfache Ereignissteuerung wie beim notify mit einmaliger Ausführung beim Zustandswechsel, "remotecontrol" ist hier ein Device, es wird in eckigen Klammern angegeben. Ausgewertet wird der Status des Devices - nicht das Event.<br>
<br>
<code>define di_garage DOIF ([remotecontrol] eq "on") (set garage on) DOELSEIF ([remotecontrol] eq "off") (set garage off)</code><br>
<br>
Das Modul wird getriggert, sobald das angegebene Device hier "remotecontrol" ein Event erzeugt. Das geschieht, wenn irgendein Reading oder der Status von "remotecontrol" aktualisiert wird.
Ausgewertet wird hier der Zustand des Statuses von remotecontrol nicht das Event selbst. Die Ausführung erfolgt standardmäßig einmalig nur nach Zustandswechsel des Moduls.
Das bedeutet, dass ein mehrmaliges Drücken der Fernbedienung auf "on" nur einmal "set garage on" ausführt. Die nächste mögliche Ausführung ist "set garage off", wenn Fernbedienung "off" liefert.
Wünscht man eine Ausführung des gleichen Befehls mehrfach nacheinander bei jedem Trigger, unabhängig davon welchen Zustand das DOIF-Modul hat, weil z. B. Garage nicht nur über die Fernbedienung geschaltet wird und dann muss man das per "do always"-Attribut angeben:<br>
<br>
<code>attr di_garage do always</code><br>
<br>
Bei der Angabe von zyklisch sendenden Sensoren (Temperatur, Feuchtigkeit, Helligkeit usw.) wie z. B.:<br>
<br>
<code>define di_heating DOIF ([sens:temperature] < 20) (set heating on)</code><br>
<br>
ist die Nutzung des Attributes <code>do always</code> nicht sinnvoll, da das entsprechende Kommando hier: "set heating on" jedes mal ausgeführt wird,
wenn der Temperatursensor in regelmäßigen Abständen eine Temperatur unter 20 Grad sendet.
Ohne <code>do always</code> wird hier dagegen erst wieder "set heating on" ausgeführt, wenn der Zustand des Moduls gewechselt hat, also die Temperatur zwischendurch größer oder gleich 20 Grad war.<br>
<br>
Abfragen nach Vorkommen eines Wortes innerhalb einer Zeichenkette können mit Hilfe des Perl-Operators <code>=~</code> vorgenommen werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Garage soll beim langen Tastendruck öffnen, hier: wenn das Wort "Long" im Status vorkommt (bei HM-Komponenten stehen im Status noch weitere Informationen).<br>
<br>
<code>define di_garage DOIF ([remotecontrol] =~ "Long") (set garage on)<br>
attr di_garage do always</code><br>
<br>
Weitere Möglichkeiten bei der Nutzung des Perl-Operators: <code>=~</code>, insbesondere in Verbindung mit regulären Ausdrücken, können in der Perl-Dokumentation nachgeschlagen werden.<br>
<br>
<b>Ereignissteuerung über Auswertung von Events</b><br>
<br>
Eine Alternative zur Auswertung von Stati oder Readings ist das Auswerten von Ereignissen (Events) mit Hilfe von regulären Ausdrücken, wie beim notify. Eingeleitet wird die Angabe eines regulären Ausdrucks durch ein Fragezeichen.
Die Syntax lautet: <code>[&lt;devicename&gt;:?&lt;regexp&gt;]</code><br>
<br>
<u>Anwendungsbeispiel</u>: wie oben, jedoch wird hier nur das Ereignis (welches im Eventmonitor erscheint) ausgewertet und nicht der Status von "remotecontrol" wie im vorherigen Beispiel<br>
<br>
<code>define di_garage DOIF ([remotecontrol:?on]) (set garage on) DOELSEIF ([remotecontrol] eq "off")  (set garage off)</code><br>
<br>
In diesem Beispiel wird nach dem Vorkommen von "on" innerhalb des Events gesucht.
Falls "on" gefunden wird, wird der Ausdruck wahr und der DOIF-Fall wird ausgeführt, ansonsten wird der DOELSEIF-Fall ausgeführt.
Die Auswertung von reinen Ereignissen bietet sich dann an, wenn ein Modul keinen Status oder Readings benutzt, die man abfragen kann, wie z. B. beim Modul "sequence".
Die Angabe von regulären Ausdrücken kann recht komplex werden und würde die Aufzählung aller Möglichkeiten an dieser Stelle den Rahmen sprengen.
Weitere Informationenen zu regulären Ausdrücken sollten in der Perl-Dokumentation nachgeschlagen werden.
Die logische Verknüpfung "and" mehrerer Ereignisse ist nicht sinnvoll, da zu einem Zeitpunkt immer nur ein Ereignis zutreffen kann.<br>
<br>
<b>Angaben im Ausführungsteil</b>:<br>
<br>
Der Ausführungsteil wird immer, wie die Bedingung, in runden Klammern angegeben. Es werden standardmäßig FHEM-Befehle angegeben, wie z. B.: <code>...(set lamp on)</code><br>
<br>
Sollen mehrere FHEM-Befehle ausgeführt werden, so werden sie mit Komma statt mit Semikolon angegeben <code>... (set lamp1 on, set lamp2 off)</code><br>
<br>
Falls ein Komma nicht als Trennzeichen zwischen FHEM-Befehlen gelten soll, so muss der FHEM-Ausdruck zusätzlich in runde Klammern gesetzt werden: <code>...((set lamp1,lamp2 on),set switch on)</code><br>
<br>
Perlbefehle müssen zusätzlich in geschweifte Klammern gesetzt werden: <code>... ({system ("wmail Peter is at home")})</code> <br>
<br>
Mehrere Perlbefehle hintereinander werden im DEF-Editor mit zwei Semikolons angegeben: <code>...({system ("wmail Peter is at home");;system ("wmail Marry is at home")})</code><br>
<br>
FHEM-Befehle lassen sich mit Perl-Befehlen kombinieren: <code>... ({system ("wmail Peter is at home")}, set lamp on)</code><br>
<br>
<b>Zeitsteuerung</b><br>
<br>
Zeitangaben in der Bedingung im Format: <code>[HH:MM:SS]</code> oder <code>[HH:MM]</code> oder <code>[Zahl]</code><br>
<br>
<u>Anwendungsbeispiele</u>:<br>
<br>
Einschalten um 8:00 Uhr, ausschalten um 10:00 Uhr.<br>
<br>
<code>define di_light DOIF ([08:00]) (set switch on) DOELSEIF ([10:00]) (set switch off)</code><br>
<br>
Zeitsteuerung mit mehreren Zeitschaltpunkten:<br>
<br>
<code>define di_light DOIF ([08:00] or [10:00] or [20:00]) (set switch on) DOELSEIF ([09:00] or [11:00] or [00:00]) (set switch off)</code><br>
<br>
Zeitangaben können ebenfalls in Sekunden angegeben werden. Es handelt sich dann um Sekundenangaben nach Mitternacht, hier also um 01:00 Uhr:<br>
<br>
<code>define di_light DOIF ([3600]) (set lamp on)</code><br>
<br>
<b>Relative Zeitangaben</b><br>
<br>
Zeitangaben, die mit Pluszeichen beginnen, werden relativ behandelt, d. h. die angegebene Zeit wird zum aktuellen Zeitpunkt hinzuaddiert.<br>
<br>
<u>Anwendungsbeispiel</u>: Automatisches Speichern der Konfiguration im Stundentakt:<br>
<br>
<code>define di_save DOIF ([+01:00]) (save)<br>
attr di_save do always</code><br>
<br>
Ebenfalls lassen sich relative Angaben in Sekunden angeben. Das obige Beispiel entspricht:<br>
<br>
<code>define di_save DOIF ([+3600]) (save)</code><br>
<br>
<b>Zeitangaben nach Zeitraster ausgerichtet</b><br>
<br>
Das Format lautet: [:MM] MM sind Minutenangaben zwischen 00 und 59.<br>
<br>
<u>Anwendungsbeispiel</u>: Viertelstunden-Gong<br>
<br>
<code>define di_gong DOIF ([:00])<br>
  <ol>({system ("mplayer /opt/fhem/Sound/BigBen_00.mp3 -volume 90 −really−quiet &")})</ol>
DOELSEIF ([:15])<br>
  <ol>({system ("mplayer /opt/fhem/Sound/BigBen_15.mp3 -volume 90 −really−quiet &")})</ol>
DOELSEIF ([:30])<br>
  <ol>({system ("mplayer /opt/fhem/Sound/BigBen_30.mp3 -volume 90 −really−quiet &")})</ol>
DOELSEIF ([:45])<br>
  <ol>({system ("mplayer /opt/fhem/Sound/BigBen_45.mp3 -volume 90 −really−quiet &")})</ol></code>
<br>
<b>Relative Zeitangaben nach Zeitraster ausgerichtet</b><br>
<br>
Das Format lautet: [+:MM] MM sind Minutenangaben zwischen 1 und 59.<br>
<br>
<u>Anwendungsbeispiel</u>: Gong alle fünfzehn Minuten um XX:00 XX:15 XX:30 XX:45<br>
<br>
<code>define di_gong DOIF ([+:15]) (set Gong_mp3 playTone 1)<br>
attr di_gong do always</code><br>
<br>
<b>Zeitangaben nach Zeitraster ausgerichtet alle X Stunden</b><br>
<br>
Format: [+[h]:MM] mit: h sind Stundenangaben zwischen 2 und 23 und MM Minuten zwischen 00 und 59<br>
<br>
<u>Anwendungsbeispiel</u>: Es soll immer fünf Minuten nach einer vollen Stunde alle 2 Stunden eine Pumpe eingeschaltet werden, die Schaltzeiten sind 00:05, 02:05, 04:05 usw.<br>
<br>
<code>define di_gong DOIF ([+[2]:05]) (set pump on-for-timer 300)<br>
attr di_gong do always</code><br>
<br>
<b>Wochentagsteuerung</b><br>
<br>
Hinter der Zeitangabe kann ein oder mehrere Wochentage als Ziffer getrennt mit einem Pipezeichen | angegeben werden. Die Syntax lautet:<br>
<br>
<code>[&lt;time&gt;|012345678]</code> 0-8 entspricht: 0-Sonntag, 1-Montag, ... bis 6-Samstag sowie 7 für Wochenende und Feiertage (entspricht $we) und 8 für Arbeitstage (entspricht !$we)<br>
<br>
<u>Anwendungsbeispiel</u>: Radio soll am Wochenende und an Feiertagen um 08:30 Uhr eingeschaltet und um 09:30 Uhr ausgeschaltet werden. An Arbeitstagen soll das Radio um 06:30 Uhr eingeschaltet und um 07:30 Uhr ausgeschaltet werden.<br>
<br>
<code>define di_radio DOIF ([06:30|8] or [08:30|7]) (set radio on) DOELSEIF ([07:30|8] or [09:30|7]) (set radio off)</code><br>
<br>
Anstatt einer Zifferkombination kann ein Status oder Reading in eckigen Klammern angegeben werden. Dieser muss zum Triggerzeitpunkt mit der gewünschten Ziffernkombination für Wochentage, wie oben definiert, belegt sein.<br>
<br>
<u>Anwendungsbeispiel</u>: Der Wochentag soll über einen Dummy bestimmt werden.<br>
<br>
<code>define dummy Wochentag<br>
set Wochentag 135<br>
<br>
define di_radio DOIF ([06:30|[Wochentag]] (set radio on) DOELSEIF ([07:30|[Wochentag]]) (set radio off)</code><br>
<br>
<b>Zeitsteuerung mit Zeitintervallen</b><br>
<br>
Zeitintervalle werden im Format angegeben: <code>[&lt;begin&gt;-&lt;end&gt;]</code>,
für <code>&lt;begin&gt;</code> bzw. <code>&lt;end&gt;</code> wird das gleiche Zeitformat verwendet,
wie bei einzelnen Zeitangaben. Getriggert wird das Modul zum Zeitpunkt <code>&lt;begin&gt;</code> und zum Zeitpunkt <code>&lt;end&gt;</code>.
Soll ein Zeitintervall ohne Zeittrigger lediglich zur Abfrage dienen, so muss hinter der eckigen Klammer ein Fragezeichen angegeben werden (siehe Beispiele weiter unten).
Das Zeitintervall ist als logischer Ausdruck ab dem Zeitpunkt <code>&lt;begin&gt;</code> wahr und ab dem Zeitpunkt <code>&lt;end&gt;</code> nicht mehr wahr.<br>
<br>
<u>Anwendungsbeispiele</u>:<br>
<br>
Radio soll zwischen 8:00 und 10:00 Uhr an sein:<br>
<br>
<code>define di_radio DOIF ([08:00-10:00]) (set radio on) DOELSE (set radio off) </code><br>
<br>
mit mehreren Zeitintervallen:<br>
<br>
<code>define di_radio DOIF ([08:00-10:00] or [20:00-22:00]) (set radio on) DOELSE (set radio off) </code><br>
<br>
Radio soll nur sonntags (0) eingeschaltet werden:<br>
<br>
<code>define di_radio DOIF ([08:00-10:00|0]) (set radio on) DOELSE (set radio off) </code><br>
<br>
Nur montags, mittwochs und freitags:<br>
<br>
<code>define di_radio DOIF ([08:00-10:00|135]) (set radio on) DOELSE (set radio off) </code><br>
<br>
Nur am Wochenende bzw. an Feiertagen lt. holiday-Datei (7 entspricht $we):<br>
<br>
<code>define di_radio DOIF ([08:00-10:00|7]) (set radio on) DOELSE (set radio off) </code><br>
<br>
Zeitintervalle über Mitternacht:<br>
<br>
<code>define di_light DOIF ([22:00-07:00]) (set light on) DOELSE (set light off) </code><br>
<br>
in Verbindung mit Wochentagen (einschalten am Freitag ausschalten am Folgetag):<br>
<br>
<code>define di_light DOIF ([22:00-07:00|5]) (set light on) DOELSE (set light off) </code><br>
<br>
Zeitintervalle über mehrere Tage müssen als Zeitpunkte angegeben werden.<br>
<br>
Einschalten am Freitag ausschalten am Montag:<br>
<br>
<code>define di_light DOIF ([22:00|5]) (set light on) DOELSEIF ([10:00|1]) (set light off) </code><br>
<br>
Schalten mit Zeitfunktionen, hier: bei Sonnenaufgang und Sonnenuntergang:<br>
<br>
<code>define di_light DOIF ([+{sunrise_rel(900,"06:00","08:00")}]) (set outdoorlight off) DOELSEIF ([+{sunset_rel(900,"17:00","21:00")}]) (set outdoorlight on)</code><br>
<br>
<b>Indirekten Zeitangaben</b><br>
<br>
Oft möchte man keine festen Zeiten im Modul angeben, sondern Zeiten, die man z. B. über Dummys über die Weboberfläche verändern kann.
Statt fester Zeitangaben können Stati, Readings oder Internals angegeben werden. Diese müssen eine Zeitangabe im Format HH:MM oder HH:MM:SS oder eine Zahl beinhalten.<br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll zu einer bestimmten Zeit eingeschaltet werden. Die Zeit soll über den Dummy <code>time</code> einstellbar sein:<br>
<br>
<code>define time dummy<br>
set time 08:00<br>
define di_time DOIF ([[time]])(set lamp on)</code><br>
<br>
Ebenfalls kann das Dummy mit einer Sekundenzahl belegt werden, oder als indirekte Zeit angegeben werden, hier z. B. schalten alle 300 Sekunden:<br>
<br>
<code>define time dummy<br>
set time 300<br>
define di_time DOIF ([+[time]])(save)</code><br>
<br>
Ebenfalls funktionieren indirekte Zeitangaben mit Zeitintervallen. Hier wird die Ein- und Ausschaltzeit jeweils über einen Dummy bestimmt:<br>
<br>
<code>define begin dummy<br>
set begin 08:00<br>
<br>
define end dummy<br>
set end 10:00<br>
<br>
define di_time DOIF ([[begin]-[end]]) (set radio on) DOELSE (set radio off)</code><br>
<br>
Bei einer Änderung des angebenen Status oder Readings wird die geänderte Zeit sofort im Modul aktualisiert.<br>
<br>
Angabe eines Readings als Zeitangabe. Beispiel: Schalten anhand eines Twilight-Readings:<br> 
<br>
<code>define di_time DOIF ([[myTwilight:ss_weather]])(set lamp on)</code><br>
<br>
Dynamische Änderung einer Zeitangabe.<br>
<br>
<u>Anwendungsbeispiel</u>: Die Endzeit soll abhängig von der Beginnzeit mit Hilfe einer eigenen Perl-Funktion, hier: <code>OffTime()</code>, bestimmt werden. <code>begin</code> und <code>end</code> sind Dummys, wie oben definiert:<br>
<br>
<code>define di_time DOIF ([[begin]-[end]]) (set lamp on, set end {(OffTime("[begin]"))}) DOELSE (set lamp off)</code><br>
<br>
Indirekte Zeitangaben lassen sich mit Wochentagangaben kombinieren, z. B.:<br>
<br>
<code>define di_time DOIF ([[begin]-[end]|7]) (set radio on) DOELSE (set radio off)</code><br>
<br>
<b>Zeitsteuerung mit Zeitberechnung</b><br>
<br>
Zeitberechnungen werden innerhalb der eckigen Klammern zusätzlich in runde Klammern gesetzt. Die berechneten Triggerzeiten können absolut oder relativ mit einem Pluszeichen vor den runden Klammern angegeben werden.
Es können beliebige Ausdrücke der Form HH:MM und Angaben in Sekunden als ganze Zahl in Perl-Rechenoperationen kombiniert werden.
Perlfunktionen, wie z. B. sunset(), die eine Zeitangabe in HH:MM liefern, werden in geschweifte Klammern gesetzt.
Zeiten im Format HH:MM bzw. Stati oder Readings, die Zeitangaben in dieser Form beinhalten werden in eckige Klammern gesetzt.<br>
<br>
<u>Anwendungsbeispiele</u>:<br>
<br>
Lampe wird nach Sonnenuntergang zwischen 900 und 1500 (900+600) Sekunden zufällig zeitverzögert eingeschaltet. Ausgeschaltet wird die Lampe nach 23:00 Uhr um bis zu 600 Sekunden zufällig verzögert:<br>
<br>
<code>define di_light DOIF ([({sunset()}+900+int(rand(600)))])<br>
   <ol>(set lamp on)</ol>
DOELSEIF ([([23:00]+int(rand(600)))])<br>
   <ol>(set lamp off) </ol></code>
<br>
Zeitberechnung können ebenfalls in Zeitintervallen genutzt werden.<br> 
<br>
Licht soll eine Stunde vor gegebener Zeit eingeschaltet werden und eine Stunde danach wieder ausgehen:<br>
<br>
<code>define Fixtime dummy<br>
set Fixtime 20:00<br>
<br>
define di_light DOIF ([([Fixtime]-[01:00]) - ([Fixtime]+[01:00])])<br>
 <ol>(set lampe on)</ol>
DOELSE<br>
 <ol>(set lampe off)</ol>
 </code>
<br>
Hier das Gleiche wie oben, zusätzlich mit Zufallsverzögerung von 300 Sekunden und nur an Wochenenden:<br>
<br>
<code>define di_light DOIF ([([Fixtime]-[01:00]-int(rand(300))) - ([Fixtime]+[01:00]+int(rand(300)))]|7])<br>
 <ol>(set lampe on)</ol>
DOELSE<br>
 <ol>(set lampe off)</ol>
 </code>
<br>
Ein Änderung des Dummys Fixtime z. B. durch "set Fixtime ...", führt zur sofortiger Neuberechnung der Timer im DOIF-Modul.<br> 
<br>
Für die Zeitberechnung wird der Perlinterpreter benutzt, daher sind für die Berechnung der Zeit keine Grenzen gesetzt.<br>
<br>
<b>Kombination von Ereignis- und Zeitsteuerung mit logischen Abfragen</b><br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll ab 6:00 Uhr angehen, wenn es dunkel ist und wieder ausgehen, wenn es hell wird, spätestens aber um 9:00 Uhr:<br>
<br>
<code>define di_lamp DOIF ([06:00-09:00] and [sensor:brightness] &lt; 40) (set lamp on) DOELSE (set lamp off)</code><br>
<br>
<u>Anwendungsbeispiel</u>: Rollläden sollen an Arbeitstagen nach 6:25 Uhr hochfahren, wenn es hell wird, am Wochenende erst um 9:00 Uhr, herunter sollen sie wieder, wenn es dunkel wird:<br>
<br>
<code>define di_shutters DOIF ([sensor:brightness]&gt;100 and [06:25-09:00|8] or [09:00|7]) (set shutters up) DOELSEIF ([sensor:brightness]&lt;50) (set shutters down)</code><br>
<br>
<b>Zeitintervalle, Readings und Stati ohne Trigger</b><br>
<br>
Angaben in eckigen Klammern, die mit einem Fragezeichen beginnen, führen zu keiner Triggerung des Moduls, sie dienen lediglich der Abfrage.<br>
<br>
<u>Anwendungsbeispiel</u>: Licht soll zwischen 06:00 und 10:00 angehen, getriggert wird nur durch den Taster nicht um 06:00 bzw. 10:00 Uhr<br>
<br>
<code>define di_motion DOIF ([?06:00-10:00] and [button])(set lamp on-for-timer 600)<br>
attr di_motion do always</code><br>
<br>
<b>Nutzung von Readings, Stati oder Internals im Ausführungsteil</b><br>
<br>
<u>Anwendungsbeispiel</u>: Wenn ein Taster betätigt wird, soll Lampe1 mit dem aktuellen Zustand der Lampe2 geschaltet werden:<br>
<br>
<code>define di_button DOIF ([button]) (set lamp1 [lamp2])<br>
attr di_button do always</code><br>
<br>
<u>Anwendungsbeispiel</u>: Benachrichtung beim Auslösen eines Alarms durch Öffnen eines Fensters:<br>
<br>
<code>define di_pushmsg DOIF ([window] eq "open" and [alarm] eq "armed") (set Pushover msg 'alarm' 'open windows [window:LastDevice]' '' 2 'persistent' 30 3600)</code><br>
<br>
<b>Berechnungen im Ausführungsteil</b><br>
<br>
Berechnungen können in geschweiften Klammern erfolgen. Aus Kompatibilitätsgründen, muss die Berechnung mit einer runden Klammer beginnen. Innerhalb der Perlberechnung können Readings, Stati oder Internals wie gewohnt in eckigen Klammern angegeben werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Es soll ein Vorgabewert aus zwei verschiedenen Readings ermittelt werden und an das set Kommando übergeben werden:<br>
<br>
<code>define di_average DOIF ([08:00]) (set TH_Modul desired {([default:temperature]+[outdoor:temperature])/2})<br>
attr di_average do always</code><br>
<br>
<b>Filtern nach Zahlen</b><br>
<br>
Es soll aus einem Reading, das z. B. ein Prozentzeichen beinhaltet, nur der Zahlenwert für den Vergleich genutzt werden:<br>
<br>
<code>define di_heating DOIF ([adjusting:actuator:d] &lt; 10) (set heating off) DOELSE (set heating on)</code><br>
<br>
<b>Verzögerungen</b><br>
<br>
Verzögerungen für die Ausführung von Kommandos werden pro Befehlsfolge über das Attribut "wait" definiert. Syntax:<br>
<br>
<code>attr &lt;DOIF-modul&gt; wait &lt;Sekunden für Befehlsfolge des ersten DO-Falls&gt;:&lt;Sekunden für Befehlsfolge des zweiten DO-Falls&gt;:...<br></code>
<br>
Statt Sekundenangaben können ebenfalls Stati in eckigen Klammen oder Perlbefehle angegeben werden.<br>
<br>
Beispiel:<br>
<br>
<code>define delay dummy<br>
set delay 400<br>
attr &lt;DOIF-modul&gt; wait 1:[delay]:rand(600)</code><br>
<br>
Hier wird der erste DO-Fall um eine Sekunde verzögert, der zweite wird durch die Angabe des Dummys "delay" bestimmt, der dritte wird durch eine zufällige Sekundenzahl bis 600 Sekunden bestimmt.<br>
<br>
Sollen Verzögerungen innerhalb von Befehlsfolgen stattfinden, so müssen diese Komandos in eigene Klammern gesetzt werden, das Modul arbeitet dann mit Zwischenzuständen.<br>
<br>
Beispiel: Bei einer Befehlssequenz, hier: <code>(set lamp1 on, set lamp2 on)</code>, soll vor dem Schalten von <code>lamp2</code> eine Verzögerung von einer Sekunde stattfinden.
Die Befehlsfolge muss zunächst mit Hilfe von Klammerblöcke aufgespaltet werden: <code>(set lamp1 on)(set lamp2 on)</code>.
Nun kann mit dem wait-Attribut nicht nur für den Beginn der Sequenz, sondern für jeden Klammerblock eine Verzögerung, getrennt mit Komma, definieren werden,
 hier also: <code>wait 0,1</code>. Damit wird <code>lamp1</code> sofort, <code>lamp2</code> nach einer Sekunden geschaltet.<br>
<br> 
Beispieldefinition bei mehreren DO-Blöcken mit mehreren Sequenzen:<br>
<br>
<code>DOIF (Bedingung1)<br>
(set ...) ## erster Befehl der ersten Sequenz soll um eine Sekunde verzögert werden<br>
(set ...) ## zweiter Befehl der ersten Sequenz soll um 2 Sekunden verzögert werden<br>
DOELSE (Bedingung2)<br>
(set ...) ## erster Befehl der zweiten Sequenz soll um 3 Sekunden verzögert werden<br>
(set ...) ## zweiter Befehl der zweiten Sequenz soll um 0,5 Sekunden verzögert werden<br>
<br>
attr &lt;DOIF-modul&gt; wait 1,2:3,0.5</code><br>
<br>
Für Kommandos ohne Verzögerung werden Sekundenangaben ausgelassen oder auf Null gesetzt. Die Verzögerungen werden nur auf Events angewandt und nicht auf Zeitsteuerung. Eine bereits ausgelöste Verzögerung wird zurückgesetzt, wenn während der Wartezeit ein Kommando eines anderen DO-Falls, ausgelöst durch ein neues Ereignis, ausgeführt werden soll.<br>
<br>
<b>Verzögerungen von Timern</b><br>
<br>
Verzögerungen können mit Hilfe des Attributs <code>timerWithWait</code> auf Timer ausgeweitet werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll zufällig nach Sonnenuntergang verzögert werden.<br>
<br>
<code>define di_rand_sunset([{sunset()}])(set lamp on)<br>
attr di_rand_sunset wait rand(1200)<br>
attr di_rand_sunset timerWithWait<br>
attr di_rand_sunset do always</code><br>
<br>
<u>Anwendungsbeispiel</u>: Benachrichtung "Waschmaschine fertig", wenn Verbrauch mindestens 5 Minuten unter 2 Watt (Perl-Code wird in geschweifte Klammern gesetzt):<br>
<br>
<code>define di_washer DOIF ([power:watt]&lt;2) ({system("wmail washer finished")})<br>
attr di_washer wait 300</code><br>
<br>
Eine erneute Benachrichtigung wird erst wieder ausgelöst, wenn zwischendurch der Verbrauch über 2 Watt angestiegen war.<br>
<br>
<u>Anwendungsbeispiel</u>: Rolladen um 20 Minuten zeitverzögert bei Sonne runter- bzw. hochfahren (wenn der Zustand der Sonne wechselt, wird die Verzögerungszeit zurückgesetzt):<br>
<br>
<code>define di_shutters DOIF ([Sun] eq "on") (set shutters down) DOELSE (set shutters up) <br>
attr di_shutters wait 1200:1200</code><br>
<br>
<u>Anwendungsbeispiel</u>: Beschattungssteuerung abhängig von der Temperatur. Der Rollladen soll runter von 11:00 Uhr bis Sonnenuntergang, wenn die Temperatur über 26 Grad ist. Temperaturschwankungen um 26 Grad werden mit Hilfe des wait-Attributes durch eine 15 minutige Verzögerung ausgeglichen. <br>
<br>
<code>define di_shutters DOIF ([sensor:temperature] &gt; 26 and [11:00-{sunset_abs()}] (set shutters down) DOELSE (set shutters up)<br>
attr di_shutters wait 900:900 </code><br>
<br>
<u>Anwendungsbeispiel</u>: Belüftung in Kombination mit einem Lichtschalter mit Nachlaufsteuerung. Der Lüfter soll angehen, wenn das Licht mindestens 2 Minuten lang brennt oder die Luftfeuchtigkeit 65 % überschreitet, der Lüfter soll ausgehen, drei Minuten nachdem die Luftfeuchtigkeit unter 60 % fällt und das Licht aus ist bzw. das Licht ausgeht und die Luftfeuchtigkeit unter 60% ist. Definitionen lassen sich über die Weboberfläche (DEF-Eingabebereich) übersichtlich gestalten:<br>
<br>
<code>define di_fan DOIF ([light] eq "on")<br>
   <ol>
  (set fan on)<br>
  </ol>
DOELSEIF ([sensor:humidity]&gt;65)<br>
  <ol>
  (set fan on)<br>
  </ol>
DOELSEIF ([light] eq "off" and [sensor:humidity]&lt;60)<br>  <ol>
  (set fan off)<br>
  </ol>
<br>
attr di_fan wait 120:0:180</code><br>
<br>
<b>Zurücksetzen des Waittimers für das gleiche Kommando</b><br>
<br>
Im Gegensatz zu <code>do always</code> wird ein Waittimer mit dem Attribut <code>do resetwait</code> auch dann zurückgesetzt, wenn die gleiche Bedingung wiederholt wahr wird.<br>
Damit können Ereignisse ausgelöst werden, wenn etwas innerhalb einer Zeitspanne nicht passiert.<br>
Das Attribut <code>do resetwait</code> impliziert eine beliebige Wiederholung wie <code>do always</code>. Diese lässt sich allerdings mit dem Attribut <code>repeatsame</code> einschränken s. u.<br>
<br>
<u>Anwendungsbeispiel</u>: Meldung beim Ausbleiben eines Events<br>
<br>
<code>define di_push DOIF ([Tempsensor])(set pushmsg "sensor failed again")<br>
attr di_push wait 1800<br>
attr di_push do resetwait</code><br>
<br>
<b>Zwangspause für das Ausführen eines Kommandos seit der letzten Zustandsänderung</b><br>
<br>
Mit dem Attribut <code>cmdpause &lt;Sekunden für cmd_1&gt;:&lt;Sekunden für cmd_2&gt;:...</code> wird die Zeitspanne in Sekunden angegeben für eine Zwangspause seit der letzten Zustandsänderung.
In der angegebenen Zeitspanne wird ein Kommando nicht ausgeführt, auch wenn die dazugehörige Bedingung wahr wird.<br>
<br>
<u>Anwendungsbeispiel</u>: Meldung über Frostgefahr alle 60 Minuten<br>
<br>
<code>define di_frost DOIF ([outdoor:temperature] < 0) (set pushmsg "danger of frost")<br>
attr di_frost cmdpause 3600<br>
attr di_frost do always</code><br>
<br>
<b>Begrenzung von Wiederholungen eines Kommandos</b><br>
<br>
Mit dem Attribut <code>repeatsame &lt;maximale Anzahl von cmd_1&gt;:&lt;maximale Anzahl von cmd_2&gt;:...</code> wird die maximale Anzahl hintereinander folgenden Ausführungen festgelegt.<br>
<br>
<u>Anwendungsbeispiel</u>: Die Meldung soll maximal dreimal erfolgen mit einer Pause von mindestens 10 Minuten <br>
<br>
<code>define di_washer DOIF ([Watt]<2) (set pushmeldung "washer finished")<br>
attr di_washer repeatsame 3<br>
attr di_washer cmdpause 600 </code><br>
<br>
Das Attribut <code>repeatsame</code> lässt sich mit <code>do always</code> oder <code>do resetwait</code> kombinieren.
Wenn die maximale Anzahl für ein Kommando ausgelassen oder auf Null gesetzt wird, so gilt für dieses Kommando der Defaultwert "einmalige Wiederholung";
in Kombination mit <code>do always</code> bzw. <code>do resetwait</code> gilt für dieses Kommando "beliebige Wiederholung".<br>
<br>
<u>Anwendungsbeispiel</u>: cmd_1 soll beliebig oft wiederholt werden, cmd_2 maximal zweimal<br>
<br>
<code>attr di_repeat repeatsame 0:2<br>
attr di_repeat do always</code><br>
<br>
<b>Ausführung eines Kommandos nach einer Wiederholung einer Bedingung</b><br>
<br>
Mit dem Attribut <code>waitsame &lt;Zeitspanne in Sekunden für cmd_1&gt;:&lt;Zeitspanne in Sekunden für das cmd_2&gt;:...</code> wird ein Kommando erst dann ausgeführt, wenn innerhalb einer definierten Zeitspanne die entsprechende Bedingung zweimal hintereinander wahr wird.<br>
Für Kommandos, für die <code>waitsame</code> nicht gelten soll, werden die entsprechenden Sekundenangaben ausgelassen oder auf Null gesetzt.<br>
<br>
<u>Anwendungsbeispiel</u>: Rollladen soll hoch, wenn innerhalb einer Zeitspanne von 2 Sekunden ein Taster betätigt wird<br>
<br>
<code>define di_shuttersup DOIF ([Button])(set shutters up)<br>
attr di_shuttersup waitsame 2<br>
attr di_shuttersup do always</code><br>
<br>
<b>Löschen des Waittimers nach einer Wiederholung einer Bedingung</b><br>
<br>
Das Gegenstück zum <code>repeatsame</code>-Attribut ist das Attribut <code>waitdel</code>. Die Syntax mit Sekundenangaben pro Kommando entspricht der, des wait-Attributs. Im Gegensatz zum wait-Attribut, wird ein laufender Timer gelöscht, falls eine Bedingung wiederholt wahr wird.
Sekundenangaben können pro Kommando ausgelassen oder auf Null gesetzt werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Rollladen soll herunter, wenn ein Taster innerhalb von zwei Sekunden nicht wiederholt wird<br>
<br>
<code>define di_shuttersdown DOIF ([Button])(set shutters down)<br>
attr di_shuttersdown waitdel 2<br>
attr di_shuttersdown do always</code><br>
<br>
"di_shuttersdown" kann nicht mit dem vorherigen Anwendungsbeispiel "di_shuttersup" innerhalb eines DOIF-Moduls kombiniert werden, da in beiden Fällen die gleiche Bedingung vorkommt.<br>
<br>
Die Attribute <code>wait</code> und <code>waitdel</code> lassen sich für verschiedene Kommandos kombinieren. Falls das Attribut für ein Kommando nicht gesetzt werden soll, kann die entsprechende Sekundenzahl ausgelassen oder eine Null angegeben werden.<br>
<br>
<u>Beispiel</u>: Für cmd_1 soll <code>wait</code> gelten, für cmd_2 <code>waitdel</code><br>
<br>
<code>attr di_cmd wait 2:0<br>
attr di_cmd waitdel 0:2</code><br>
<br>
<b>Zeitspanne eines Readings seit der letzten Änderung</b><br>
<br>
Bei Readingangaben kann die Zeitspanne mit <code>[&lt;Device&gt;:&lt;Reading&gt;:sec]</code> in Sekunden seit der letzten Änderung bestimmt werden<br>
<br>
<u>Anwendungsbeispiel</u>: Licht soll angehen, wenn der Status des Bewegungsmelders in den letzten fünf Sekunden upgedatet wurde.<br>
<br>
<code>define di_lamp DOIF ([BM:state:sec] < 5)(set lamp on-for-timer 300)<br>
attr di_lamp do always</code><br>
<br>
Bei HM-Bewegungsmelder werden periodisch Readings aktualisiert, dadurch wird das Modul getrigger, auch wenn keine Bewegung stattgefunden hat.
Der Status bleibt dabei auf "motion". Mit der obigen Abfrage lässt sich feststellen, ob der Status aufgrund einer Bewegung tatsächlich upgedatet wurde.<br>
<br>
<b>Status des Moduls</b><br>
<br>
Der Status des Moduls wird standardmäßig mit cmd_1, cmd_2, usw. belegt. Dieser lässt sich über das Attribut "cmdState" mit | getrennt umdefinieren:<br>
<br>
attr &lt;DOIF-modul&gt; cmdState  &lt;Status für das erste Kommando&gt;|&lt;Status für das zweite Kommando&gt;|...<br>
<br>
z. B.<br>
<br>
<code>attr di_Lampe cmdState on|off</code><br>
<br>
Wenn nur der DOIF-Fall angegeben wird, so wird, wenn Bedingung nicht erfüllt ist, ein cmd_2-Status gesetzt. Damit wird ein Zustandswechsel des Moduls erreicht, was zur Folge hat, dass beim nächsten Wechsel von false auf true das DOIF-Kommando erneut ausgeführt wird.<br>
<br>
<b>Reine Statusanzeige ohne Ausführung von Befehlen</b><br>
<br>
Der Ausführungsteil kann jeweils ausgelassen werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Aktuelle Außenfeuchtigkeit im Status<br>
<br>
<code>define di_hum DOIF ([outdoor:humidity]&gt;70) DOELSEIF ([outdoor:humidity]&gt;50) DOELSE<br>
attr di_hum cmdState wet|normal|dry</code><br>
<br>
<b>Anpassung des Status mit Hilfe des Attributes <code>state</code></b><br>
<br>
Es können beliebige Reading und Stati oder Internals angegeben werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Aktuelle Außenfeuchtigkeit inkl. Klimazustand (Status des Moduls wurde mit cmdState definiert s. o.)<br>
<br>
<code>attr di_hum state The current humidity is [outdoor:humidity], it is [di_hum]</code><br>
<br>
Es können beim Attribut state ebenfalls Berechnungen in geschweiften Klammern durchgeführt werden. Aus Kompatibilitätsgründen, muss die Berechnung mit einer runden Klammer beginnen.<br>
<br>
<u>Anwendungsbeispiel</u>: Berechnung des Mittelwertes zweier Readings:<br>
<br>
<code>define di_average DOIF <br>
attr di_average state Average of the two rooms is {([room1:temperature]+[room2:temperature])/2}</code><br>
<br>
Der Status wird automatisch aktualisiert, sobald sich eine der Temperaturen ändert<br>
<br>
Da man beliebige Perl-Ausdrücke verwenden kann, lässt sich z. B. der Mittelwert auf eine Stelle mit der Perlfunktion sprintf formatieren:<br>
<br>
<code>attr di_average state Average of the two rooms is {(sprintf("%.1f",([room1:temperature]+[room2:temperature])/2))}</code><br>
<br>
<b>Vorbelegung des Status mit Initialisierung nach dem Neustart mit dem Attribut <code>initialize</code></b><br>
<br>
<u>Anwendungsbeispiel</u>: Nach dem Neustart soll der Zustand von <code>di_lamp</code> mit "initialized" vorbelegt werden. Das Reading <code>cmd_nr</code> wird auf 0 gesetzt, damit wird ein Zustandswechsel provoziert, das Modul wird initialisiert - der nächste Trigger führt zum Ausführen eines Kommandos.<br>
<br>
<code>attr di_lamp intialize initialized</code><br>
<br>
Das ist insb. dann sinnvoll, wenn das System ohne Sicherung der Konfiguration (unvorhergesehen) beendet wurde und nach dem Neustart die zuletzt gespeicherten Zustände des Moduls nicht mit den tatsächlichen übereinstimmen.<br>
<br>
<b>Deaktivieren des Moduls</b><br>
<br>
Ein DOIF-Modul kann mit Hilfe des Attributes disable, deaktiviert werden. Dabei werden alle Timer und Readings des Moduls gelöscht.
Soll das Modul nur vorübergehend deaktiviert werden, so kann das durch <code>set &lt;DOIF-modul&gt; disable</code> geschehen. 
Hierbei bleiben alle Timer aktiv, sie werden aktualisiert - das Modul bleibt im Takt, allerding werden keine Befehle ausgeführt.
Das Modul braucht mehr Rechenzeit, als wenn es komplett über das Attribut deaktiviert wird. In beiden Fällen bleibt der Zustand nach dem Neustart erhalten, das Modul bleibt deaktiviert.<br>
<br>
<b>Initialisieren des Moduls</b><br>
<br>
Mit <code>set &lt;DOIF-modul&gt; initialize</code> wird ein mit <code>set &lt;DOIF-modul&gt; disable</code> deaktiviertes Modul wieder aktiviert.
Das Kommando <code>set &lt;DOIF-modul&gt; initialize</code> kann auch dazu genutzt werden ein aktives Modul zu initialisiert,
in diesem Falle wird der letzte Zustand des Moduls gelöscht, damit wird ein Zustandswechsel herbeigeführt, der nächste Trigger führt zur Ausführung.<br>
<br>
<b>Weitere Anwendungsbeispiele</b><br>
<br>
Zweipunktregler a la THRESHOLD<br>
<br>
<code>setreading sensor default 20<br>
setreading sensor hysteresis 1<br>
<br>
define di_threshold DOIF ([sensor:temperature]&lt;([sensor:default]-[sensor:hysteresis])) (set heating on) DOELSEIF ([sensor:temperature]&gt;[sensor:default]) (set heating off)</code><br>
<br>
Eleganter lässt sich ein Zweipunktregler (Thermostat) mit Hilfe des, für solche Zwecke, spezialisierten THRESHOLD-Moduls realisieren, siehe: <a href="http://fhem.de/commandref_DE.html#THRESHOLD">THRESHOLD</a><br>
<br>
on-for-timer<br>
<br>
Die Nachbildung eines on-for-timers lässt sich wie folgt realisieren:<br>
<br>
<code>define di_on_for_timer ([detector:?motion])<br>
  (set light on)<br>
  (set light off)<br>
attr di_on_for_timer do resetwait<br>
attr di_on_for_timer wait 0,30</code><br>
<br>
Hiermit wird das Licht bei Bewegung eingeschaltet. Dabei wird, solange es brennt, bei jeder Bewegung die Ausschaltzeit neu auf 30 Sekunden gesetzt, "set light on" wird dabei nicht unnötig wiederholt.<br>
<br>
Die Beispiele stellen nur eine kleine Auswahl von möglichen Problemlösungen dar. Da sowohl in der Bedingung (hier ist die komplette Perl-Syntax möglich), als auch im Ausführungsteil, keine Einschränkungen gegeben sind, sind die Möglichkeiten zur Lösung eigener Probleme mit Hilfe des Moduls sehr vielfältig.<br>
<br>
<b>Zu beachten</b><br>
<br>
In jeder Bedingung muss mindestens ein Trigger angegeben sein (Angaben in eckigen Klammern). Die entsprechenden DO-Fälle werden nur dann ausgewertet, wenn auch das entsprechende Event oder Zeit-Trigger ausgelöst wird.<br>
<br>
Zeitangaben der Art: <br>
<br>
<code>define di_light DOIF ([08:00] and [10:00]) (set switch on)</code><br>
<br>
sind nicht sinnvoll, da diese Bedingung nie wahr sein wird.<br>
<br>
Angaben, bei denen aufgrund der Definition kein Zustandswechsel erfolgen kann z. B.:<br>
<br>
<code>define di_light DOIF ([08:00]) (set switch on)<br>
attr di_light do always</code><br>
<br>
müssen mit Attribut <code>do always</code> definiert werden, damit sie nicht nur einmal, sondern jedes mal (hier jeden Tag) ausgeführt werden.<br>
<br>
Rekursionen vermeiden<br>
<br>
Das Verändern des Status eines Devices z. B. durch set-Befehl, welches in der Bedingung bereits vorkommt, würde das Modul erneut triggern.
Solche Rekursionen (Loops) werden zwar von FHEM unterbunden, können jedoch elegant durch Abfragen mit Fragezeichen [?...] gelöst werden:<br>
<br>
statt:<br>
<br>
<code>define di_lamp ([brightness] < 50 and [lamp] eq "off")(set lamp on)</code><br>
<br>
mit Fragezeichen abfragen:<br>
<br>
<code>define di_lamp ([brightness] < 50 and [?lamp] eq "off")(set lamp on)</code><br>
<br>
Bei Devices, die mit Zwischenzuständen arbeiten, insbesondere HM-Komponenten (Zwischenzustand: set_on, set_off), sollte die Definition möglichst genau formuliert werden, um unerwünschte Effekte zu vermeiden: <br>
<br>
statt:<br>
<br>
<code>define di_lamp DOIF ([HM_switch] eq "on") (set lamp on) DOELSE (set lamp off)</code><br>
<br>
konkreter spezifizieren:<br>
<br>
<code>define di_lamp DOIF ([HM_switch] eq "on") (set lamp on) DOELSEIF ([HM_switch] eq "off") (set lamp off)</code><br>
<br>
Namenskonvention: Da der Doppelpunkt bei Readingangaben als Trennzeichen gilt, darf er nicht im Namen des Devices vorkommen. In solchen Fällen bitte das Device umbenennen.<br>
<br>
Standardmäßig, ohne das Attribut <code>do always</code>, wird das Wiederholen desselben Kommmandos vom Modul unterbunden. Daher sollte nach Möglichkeit eine Problemlösung mit Hilfe eines und nicht mehrerer DOIF-Module realisiert werden, getreu dem Motto "wer die Lampe einschaltet, soll sie auch wieder ausschalten".
Dadurch wird erreicht, dass unnötiges (wiederholendes) Schalten vom Modul unterbunden werden kann, ohne dass sich der Anwender selbst darum kümmern muss.<br>
<br>
Mehrere Bedingungen, die zur Ausführung gleicher Kommandos führen, sollten zusammengefasst werden. Dadurch wird ein unnötiges Schalten aufgrund verschiedener Zustände verhindert.<br>
<br>
Beispiel:<br>
<br>
<code>define di_lamp DOIF ([brightness] eq "off") (set lamp on) DOELSEIF ([19:00]) (set lamp on) DOELSE (set lamp off)</code><br>
<br>
Hier wird um 19:00 Uhr Lampe eingeschaltet, obwohl sie evtl. vorher schon durch das Ereignis brightness "off" eingeschaltet wurde.<br>
<br>
<code>define di_lamp DOIF ([brightness] eq "off" or [19:00]) (set lamp on) DOELSE (set lamp off)</code><br>
<br>
Hier passiert das nicht mehr, da die ursprünglichen Zustände cmd_1 und cmd_2 jetzt nur noch einen Zustand cmd_1 darstellen und dieser wird nicht wiederholt.<br>
<br>
</ul>
=end html_DE
=cut