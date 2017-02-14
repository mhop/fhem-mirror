#############################################
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
  foreach my $key (keys %{$hash->{triggertime}}) {
    RemoveInternalTimer (\$hash->{triggertime}{$key}); 
  }
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
  delete ($hash->{localtime});
  delete ($hash->{days});
  delete ($hash->{readings});
  delete ($hash->{internals});
  delete ($hash->{trigger});
  delete ($hash->{triggertime});
  delete ($hash->{interval});
  delete ($hash->{regexp});
  #delete ($hash->{state});
  #delete ($defs{$hash->{NAME}}{READINGS});
  foreach my $key (keys %{$defs{$hash->{NAME}}{READINGS}}) {
    delete $defs{$hash->{NAME}}{READINGS}{$key} if ($key =~ "^(Device|state|error|cmd|e_|timer_|wait_|matched_|last_cmd|mode)");
  }

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
  $hash->{AttrList} = "disable:0,1 loglevel:0,1,2,3,4,5,6 wait do:always,resetwait cmdState state initialize repeatsame repeatcmd waitsame waitdel cmdpause timerWithWait:1,0 notexist selftrigger:wait,all timerevent:1,0 checkReadingEvent:1,0 addStateEvent:1,0 checkall:event,timer,all setList:textField-long readingList ".$readingFnAttributes;
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
GetCommandDoIf ($$)
{
  my ($separator,$tailBlock) = @_;
   my $char;
  my $beginning;
  my $currentBlock;
  my $err;
  my $cmd="";
  while ($tailBlock=~ /^([^$separator^"^\[^\{^\(]*)/g) { 
       $char=substr($tailBlock,pos($tailBlock),1);
       if ($char eq $separator) {  
         $cmd=$cmd.substr($tailBlock,0,pos($tailBlock));
         $tailBlock=substr($tailBlock,pos($tailBlock)+1);
         return($cmd,$tailBlock,"");
       } elsif ($char eq '{') {
         ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]');
         return ($currentBlock,$tailBlock,$err) if ($err);
         $cmd=$cmd.$beginning."{$currentBlock}";         
       } elsif ($char eq '(') {
         ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\(\)]'); 
         return ($currentBlock,$tailBlock,$err) if ($err);
         $cmd=$cmd.$beginning."($currentBlock)"; 
       } elsif ($char eq '[') {
         ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\[\]]');
         return ($currentBlock,$tailBlock,$err) if ($err);
         $cmd=$cmd.$beginning."[$currentBlock]"; 
       } elsif ($char eq '"') {
         if ($tailBlock =~ /(^[^"]*"[^"]*")(.*)/) {
           $cmd=$cmd.$1;
           $tailBlock=$2;
         }
       } 
  }
  if ($cmd eq "") {
    $cmd=$tailBlock;
  } else {
    $cmd=$cmd.$tailBlock
  }
  return ($cmd,"","");
}

sub EvalValueDoIf($$$)
{
my ($hash,$attr,$value)=@_;
return undef if (!defined($value));
my $err="";
my $pn=$hash->{NAME};
   $value =~ s/\$SELF/$pn/g;
  ($value,$err)=ReplaceAllReadingsDoIf($hash,$value,-1,1);
  if ($err) {
    my $error="$pn: error in $attr: $err";
    Log3 $pn,4 , $error;
    readingsSingleUpdate ($hash, "error", $error,0);
    $value=0;
  } else {
     my $ret = eval $value;
     if ($@) {
       my $error="$pn: error in $attr: $value";
       Log3 $pn,4 , $error;
       readingsSingleUpdate ($hash, "error", $error,0);
       $value=0;
     } else {
       $value=$ret;
     }
  }
  return ($value);
}

sub EvalCmdStateDoIf($$)
{
my ($hash,$state)=@_; 
my $err;
my $pn=$hash->{NAME};
  ($state,$err)=ReplaceAllReadingsDoIf($hash,$state,-1,1);
  if ($err) {
    Log3 $pn,4 , "$pn: error in state: $err" if ($err);
    $state=$err;
  } else {
    ($state,$err)=EvalAllDoIf($hash, $state);
    if ($err) {
      Log3 $pn,4 , "$pn: error in state: $err" if ($err);
      $state=$err;
    }
  }
  return($state)  
}

sub
SplitDoIf($$)
{
my ($separator,$tailBlock)=@_;
my @commands;
my $cmd;
my $err;
if (defined $tailBlock) {
  while ($tailBlock ne "") {
    ($cmd,$tailBlock,$err)=GetCommandDoIf($separator,$tailBlock);
    #return (@commands,$err) if ($err);
    push(@commands,$cmd);
  }
}
return(@commands);
}

sub
EventCheckDoif($$$$)
{
  my ($n,$dev,$eventa,$NotifyExp)=@_;
  my $found=0;
  my $s;
  return 0 if ($dev ne $n);
  return 0 if(!$eventa);
  my $max = int(@{$eventa});
  my $ret = 0;
  if ($NotifyExp eq "") {
    return 1 ;
  } 
  for (my $i = 0; $i < $max; $i++) {
    $s = $eventa->[$i];
    $s = "" if(!defined($s));
    $found = ($s =~ m/$NotifyExp/);
    if ($found) {
      return 1;
    }
  }
  return 0;
}

sub
EventDoIf
{
  my ($n,$hash,$NotifyExp,$check,$filter,$output,$default)=@_;
  
  my $dev=$hash->{helper}{triggerDev};
  my $eventa=$hash->{helper}{triggerEvents};
  if ($check) {
    if ($dev ne $n) {
      if (defined $filter) {
        return ($default)
      } else {
        return 0;
      }
    }
  } else {
    if ($n and $dev !~ /$n/) {
      if (defined $filter) {
        return ($default)
      } else {
        return 0;
      }
    }
  }
  return 0 if(!$eventa);
  my $max = int(@{$eventa});
  my $ret = 0;
  if ($NotifyExp eq "") {
    return 1 if (!defined $filter);
  } 
  my $s;
  my $found;
  my $element;
  for (my $i = 0; $i < $max; $i++) {
    $s = $eventa->[$i];
    $s = "" if(!defined($s));
    $found = ($s =~ m/$NotifyExp/);
    if ($found or $NotifyExp eq "") {
      $hash->{helper}{event}=$s;
      if (defined $filter) {
        $element = ($s =~  /$filter/) ? $1 : "";
        if ($element) {
          if ($output ne "") {
            $element= eval $output;
            if ($@) {
              Log3 ($hash->{NAME},4 , "$hash->{NAME}: $@");
              readingsSingleUpdate ($hash, "error", $@,0);
              return(undef);
            } 
          }
          return ($element);
        }
      } else {
        return 1;
      }
    }
    #if(!$found && AttrVal($n, "eventMap", undef)) {
    #  my @res = ReplaceEventMap($n, [$n,$s], 0);
    #  shift @res;
    #  $s = join(" ", @res);
    #  $found = ("$n:$s" =~ m/^$re$/);
  }
  if (defined $filter) {
    return ($default);
  } else {
    return 0;
  }
}

sub
InternalDoIf
{ 
  my ($hash,$name,$internal,$default,$regExp,$output)=@_;

  $default=AttrVal($hash->{NAME},'notexist','') if (!defined $default);
  $regExp='' if (!defined $regExp);
  $output='' if (!defined $output);
  if ($default =~ /^"(.*)"$/) {
    $default = $1;
  } else {
    $default=EvalValueDoIf($hash,"default",$default);
  }
  my $r="";
  my $element;
  return ($default) if (!defined $defs{$name});
  return ($default) if (!defined $defs{$name}{$internal});
  $r=$defs{$name}{$internal};
  if ($regExp) {
    $element = ($r =~  /$regExp/) ? $1 : "";
    if ($output) {
      $element= eval $output;
      if ($@) {
        Log3 ($hash->{NAME},4 , "$hash->{NAME}: $@");
        readingsSingleUpdate ($hash, "error", $@,0);
        return(undef);
      }
    }
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
ReadingValDoIf
{

  my ($hash,$name,$reading,$default,$regExp,$output)=@_;
  
  $default=AttrVal($hash->{NAME},'notexist','') if (!defined $default);
  $output='' if (!defined $output);
  $regExp='' if (!defined $regExp);
  if ($default =~ /^"(.*)"$/) {
    $default = $1;
  } else {
    $default=EvalValueDoIf($hash,"default",$default);
  }

  my $r;
  my $element;
    return ($default) if (!defined $defs{$name});
    return ($default) if (!defined $defs{$name}{READINGS}{$reading}{VAL});
    $r=$defs{$name}{READINGS}{$reading}{VAL};
    $r="" if (!defined($r));
    if ($regExp) {
      $element = ($r =~  /$regExp/) ? $1 : "";
      if ($output) {
        $element= eval $output;
        if ($@) {
          Log3 ($hash->{NAME},4 , "$hash->{NAME}: $@");
          readingsSingleUpdate ($hash, "error", $@,0);
          return(undef);
        }  
      }
    } else {
      $element=$r;
    }
    return($element);
}

sub
EvalAllDoIf($$)
{
  my ($hash,$tailBlock)= @_;
  my $eval="";
  my $beginning;
  my $err;
  my $cmd="";
  my $ret="";
  my $eventa=$hash->{helper}{triggerEvents};
  my $device=$hash->{helper}{triggerDev};
  my $event=$hash->{helper}{event};
  my $events="";
  if ($eventa) {
    $events=join(",",@{$eventa});
  }
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

sub ReplaceEventDoIf($)
{
  my ($block) = @_;
  my $exp;
  my $exp2;
  my $nameExp;
  my $notifyExp;
  my $default;
  my $filter;
  my $output;

  ($exp,$default)=SplitDoIf(",",$block);
  ($exp2,$filter,$output)=SplitDoIf(":",$exp);
  if ($exp2 =~ /^"(.*)"/){
    $exp2=$1;
    if ($exp2 =~ /([^\:]*):(.*)/) {
      $nameExp=$1;
      $notifyExp=$2;
    } else {
      $nameExp=$exp2;
    }
  }
  $nameExp="" if (!defined $nameExp);
  $notifyExp="" if (!defined $notifyExp);
  $output="" if (!defined $output);
  if (defined $default) {
    if ($default =~ /"(.*)"/) {
      $default = $1;
    }
    if (defined $filter) {
      if ($filter =~ /"(.*)"/) {
        $filter=$1;
      } else {
        return ($filter,"wrong filter Regex")
      }
    } else {
       $filter='[^\:]*: (.*)';
    }
  } else {
    if (defined $filter) {
      return ($block,"default value must be defined")
    } else {
      $block="EventDoIf('$nameExp',".'$hash,'."'$notifyExp',0)";  
      return ($block,undef);
    } 
  }
  $block="EventDoIf('$nameExp',".'$hash,'."'$notifyExp',0,'$filter','$output','$default')";  
  return ($block,undef);
}

sub ReplaceReadingDoIf($)
{
  my ($element) = @_;
  my $beginning;
  my $tailBlock;
  my $err;
  my $regExp="";
  my $name;
  my $reading;
  my $format;
  my $output="";
  my $exp;
  my $default;
  my $param="";

  
  ($exp,$default)=SplitDoIf(",",$element);
  $default="" if (!defined($default));

  my $internal="";
  my $notifyExp="";
  if ($exp =~ /^([^:]*):(".*")/) {
    $name=$1;
    $reading=$2;
  } elsif ($exp =~ /^([^:]*)(?::([^:]*)(?::(.*))?)?/) {
    $name=$1;
    $reading=$2;
    $format=$3;
  }
  if ($name) {
    if ($reading) {
      if (substr($reading,0,1) eq "\?") {
        $notifyExp=substr($reading,1);
        return("EventDoIf('$name',".'$hash,'."'$notifyExp',1)","",$name,undef,undef);
      } elsif ($reading =~ /^"(.*)"$/g)  {
        $notifyExp=$1;
        return("EventDoIf('$name',".'$hash,'."'$notifyExp',1)","",$name,undef,undef);
      }
      $internal = substr($reading,1) if (substr($reading,0,1) eq "\&");
      if ($format) {
        if ($format eq "sec") {
          return("ReadingSecDoIf('$name','$reading')","",$name,$reading,undef);
        } elsif (substr($format,0,1) eq '[') { #old Syntax
          ($beginning,$regExp,$err,$tailBlock)=GetBlockDoIf($format,'[\[\]]');
          return ($regExp,$err) if ($err);
          return ($regExp,"no round brackets in regular expression") if ($regExp !~ /.*\(.*\)/);
        } elsif ($format =~ /^"([^"]*)"(?::(.*))?/){
          $regExp=$1;
          $output=$2;
          return ($regExp,"no round brackets in regular expression") if ($regExp !~ /.*\(.*\)/);
        } elsif ($format =~ /^d[^:]*(?::(.*))?/) {
          $regExp = '(-?\d+(\.\d+)?)';
          $output=$1;
        }
          else {
          return($format,"unknown expression format");
        }  
      } 
      $output="" if (!defined($output));
      
      if ($output) {
        $param=",'$default','$regExp','$output'";
      } elsif ($regExp) {
        $param=",'$default','$regExp'";
      } elsif ($default) {
        $param=",'$default'";
      }
      if ($internal) {
        return("InternalDoIf(".'$hash'.",'$name','$internal'".$param.")","",$name,undef,$internal);
      } else {
        return("ReadingValDoIf(".'$hash'.",'$name','$reading'".$param.")","",$name,$reading,undef);
      }
    } else {
      if ($default) {
        $param=",'$default'";
      }
      return("InternalDoIf(".'$hash'.",'$name','STATE'".$param.")","",$name,undef,'STATE');
    }
  }
}

sub ReplaceReadingEvalDoIf($$$)
{
  my ($hash,$element,$eval) = @_;
  my ($block,$err,$device,$reading,$internal)=ReplaceReadingDoIf($element);
  return ($block,$err) if ($err);
  if ($eval) {
   #   return ("[".$element."]","") if(!$defs{$device});
   #   return ("[".$element."]","") if (defined ($reading) and !defined($defs{$device}{READINGS}{$reading}));
   #   return ("[".$element."]","") if (defined ($internal) and !defined($defs{$device}{$internal}));
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

sub AddRegexpTriggerDoIf($$$)   
{
  my ($hash,$regexp,$condition)= @_;
  my $max_regexp=keys %{$hash->{regexp}{$condition}};
  for (my $i=0; $i<$max_regexp;$i++) 
  {
    if ($hash->{regexp}{$condition}{$i} eq $regexp) {
      return;
    }
  }
  $hash->{regexp}{$condition}{$max_regexp}=$regexp;
  $max_regexp=keys %{$hash->{regexp}{all}};
  for (my $i=0; $i<$max_regexp;$i++) 
  {
    if ($hash->{regexp}{all}{$i} eq $regexp) {
      return;
    }
  }
  $hash->{regexp}{all}{$max_regexp}=$regexp;
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
  my $nr;
  my $timer="";
  my $event=0;
  my $definition=$tailBlock;
  my $reading;
  my $internal;
  my $trigger=1;
  if (!defined $tailBlock) {
    return ("","");
  } 
  $tailBlock =~ s/\$SELF/$hash->{NAME}/g;
  while ($tailBlock ne "") {
    $trigger=1;
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\[\]]');
    return ($block,$err) if ($err);
    if ($block ne "") {
      if ($block =~ /^"([^"]*)"/){
	    if ($condition>=0) {
		  ($block,$err)=ReplaceEventDoIf($block);
		  return ($block,$err) if ($err);
		  AddRegexpTriggerDoIf($hash,$1,$condition);
	      $event=1;
		} else {
           $block="[".$block."]";
		}
      } else {
        if (substr($block,0,1) eq "?") {
          $block=substr($block,1);
          $trigger=0;
        }
        $trigger=0 if (substr($block,0,1) eq "\$");
        if ($block =~ /^\$?[a-z0-9._]*[a-z._]+[a-z0-9._]*($|:.+$|,.+$)/i) {
          ($block,$err,$device,$reading,$internal)=ReplaceReadingEvalDoIf($hash,$block,$eval);
          return ($block,$err) if ($err);
          if ($condition >= 0) {
            if ($trigger) {
              $hash->{devices}{$condition} = AddItemDoIf($hash->{devices}{$condition},$device);
              $hash->{devices}{all} = AddItemDoIf($hash->{devices}{all},$device);
              $event=1;
            }
            $hash->{readings}{$condition} = AddItemDoIf($hash->{readings}{$condition},"$device:$reading") if (defined ($reading));
            $hash->{internals}{$condition} = AddItemDoIf($hash->{internals}{$condition},"$device:$internal") if (defined ($internal));
            $hash->{readings}{all} = AddItemDoIf($hash->{readings}{all},"$device:$reading") if (defined ($reading));
            $hash->{internals}{all} = AddItemDoIf($hash->{internals}{all},"$device:$internal") if (defined ($internal));
            $hash->{trigger}{all} = AddItemDoIf($hash->{trigger}{all},"$device") if (!defined ($internal) and !defined($reading));
            
          } elsif ($condition == -2) {
              $hash->{state}{device} = AddItemDoIf($hash->{state}{device},$device); #if ($device ne $hash->{NAME});
          } elsif ($condition == -3) {
              $hash->{itimer}{all} = AddItemDoIf($hash->{itimer}{all},$device);
          }
        } elsif ($condition >= 0) {
          ($timer,$err)=DOIF_CheckTimers($hash,$block,$condition,$trigger);
          return($timer,$err) if ($err);
          if ($timer) {
            $block=$timer;
            $event=1 if ($trigger);
          }
        } else {
          $block="[".$block."]";
        }
      }
    }
    $cmd.=$beginning.$block;
  }
  #return ($definition,"no trigger in condition") if ($condition >=0 and $event == 0);
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
  my $eventa=$hash->{helper}{triggerEvents};
  my $device=$hash->{helper}{triggerDev};
  my $event=$hash->{helper}{event};
  my $events="";
  if ($eventa) {
    $events=join(",",@{$eventa});
  }
  while ($tailBlock ne "") {
    if ($tailBlock=~ /^\s*\{/) { # perl block
      ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]'); 
      return ($currentBlock,$err) if ($err);
      if ($currentBlock ne "") {
         ($currentBlock,$err)=ReplaceAllReadingsDoIf($hash,$currentBlock,-1,$eval);
         return ($currentBlock,$err) if ($err);
         if ($eval) {
           ($currentBlock,$err)=EvalAllDoIf($hash,$currentBlock);
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
      } else {
        ($currentBlock,$tailBlock)=GetCommandDoIf(',',$tailBlock);
      } 
      if ($currentBlock ne "") {
       ($currentBlock,$err)=ReplaceAllReadingsDoIf($hash,$currentBlock,-1,$eval);
       return ($currentBlock,$err) if ($err);
       if ($eval) {
         ($currentBlock,$err)=EvalAllDoIf($hash, $currentBlock);
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
DOIF_CheckTimers($$$$)
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
  my ($hash,$timer,$condition,$trigger)=@_;
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
    if ($init_done) {
      $err=(DOIF_SetTimer($hash,"DOIF_TimerTrigger",$nr));
      return($hash->{time}{$nr},$err) if ($err);
    }
    $hash->{timers}{$condition}.=" $nr " if ($trigger);
  }
  if ($i == 2) {
    if ($days eq "") { 
      $block='DOIF_time($hash,'.$nrs[0].','.$nrs[1].',$wday,$hms)';
    } else {
      $block='DOIF_time($hash,'.$nrs[0].','.$nrs[1].',$wday,$hms,"'.$days.'")';
    }
    $hash->{interval}{$nrs[0]}=-1;
    $hash->{interval}{$nrs[1]}=$nrs[0];
  } else {
    if ($days eq "") { 
      $block='DOIF_time_once($hash,'.$nrs[0].',$wday)';
    } else {
      $block='DOIF_time_once($hash,'.$nrs[0].',$wday,"'.$days.'")';
    } 
  }
  return ($block,"");
}

sub
DOIF_time
{
  my $ret=0;
  my ($hash,$b,$e,$wday,$hms,$days)=@_;
  $days="" if (!defined ($days));
  my $begin=$hash->{realtime}{$b};
  my $end=$hash->{realtime}{$e};
  my $err;
  return 0 if ($begin eq $end);
  ($days,$err)=ReplaceAllReadingsDoIf($hash,$days,-1,1);
  if ($err) {
    my $errmsg="error in days: $err";
    Log3 ($hash->{NAME},4 , "$hash->{NAME}: $errmsg");
    readingsSingleUpdate ($hash, "error", $errmsg,0);
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
      $wday=6 if ($wday-- == 0);
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
DOIF_time_once
{
  my ($hash,$nr,$wday,$days)=@_;
  $days="" if (!defined ($days));
  my $flag=$hash->{timer}{$nr};
  my $err;
  ($days,$err)=ReplaceAllReadingsDoIf($hash,$days,-1,1);
  if ($err) {
    my $errmsg="error in days: $err";
    Log3 ($hash->{NAME},4 , "$hash->{NAME}: $errmsg");
    readingsSingleUpdate ($hash, "error", $errmsg,0);
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
  $state =~ s/\$SELF/$pn/g;
  my @cmdState=SplitDoIf('|',$attr);
  return undef if (AttrVal($hash->{NAME},"disable",""));
  $nr=ReadingsVal($pn,"cmd_nr",0)-1 if (!$event);
  
  if ($nr!=-1) {
    $cmdNr=$nr+1;
    my @cmdSubState=SplitDoIf(',',$cmdState[$nr]);
    if (defined $cmdSubState[$subnr]) {
      $cmd=EvalCmdStateDoIf($hash,$cmdSubState[$subnr]);
    } else {
      if (defined $hash->{do}{$nr}{$subnr+1}) {
        $cmd="cmd_".$cmdNr."_".($subnr+1);
      } else {
        if (defined ($cmdState[$nr]) and defined $cmdSubState[$subnr]) {
          $cmd=EvalCmdStateDoIf($hash,$cmdState[$nr]);
        } else {
          $cmd="cmd_$cmdNr";
        }
      }
    }
  }
  if ($cmd =~ /^"(.*)"$/) {
    $cmd=$1;
  }
  readingsBeginUpdate  ($hash);
  if ($event) {
    readingsBulkUpdate($hash,"cmd_nr",$cmdNr);
    if (defined $hash->{do}{$nr}{1}) {
      readingsBulkUpdate($hash,"cmd_seqnr",$subnr+1);
      readingsBulkUpdate($hash,"cmd",$cmdNr.".".($subnr+1));
    } else {
      delete ($defs{$hash->{NAME}}{READINGS}{cmd_seqnr});
      readingsBulkUpdate($hash,"cmd",$cmdNr);
    }
    readingsBulkUpdate($hash,"cmd_event",$event);
    if ($last_error) {
      readingsBulkUpdate($hash,"error",$last_error);
    } else {
      delete ($defs{$hash->{NAME}}{READINGS}{error});
    }
  }
  
 # if ($state and !defined $hash->{do}{$nr}{$subnr+1}) {
 if ($state) {
    my $stateblock='\['.$pn.'\]';
    $state =~ s/$stateblock/$cmd/g;
    $state=EvalCmdStateDoIf($hash,$state);
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
    if($h2we && Value($h2we)) {
      my ($a, $b) = ReplaceEventMap($h2we, [$h2we, Value($h2we)], 0);
      $we = 1 if($b ne "none");
    }
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
  $month++;
  $year+=1900;
  my $week=strftime ('%W', localtime($seconds));
  my $hms = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
  my $hm = sprintf("%02d:%02d", $hour, $min);
  my $ymd = sprintf("%02d-%02d-%02d", $year, $month,$mday);
  my $md = sprintf("%02d-%02d",$month,$mday);
  my $dev;
  my $reading;
  my $internal;
  my $we=DOIF_we($wday);
  my $eventa=$hash->{helper}{triggerEvents};
  my $device=$hash->{helper}{triggerDev};
  my $event=$hash->{helper}{event};
  my $events="";
  my $cmd=ReadingsVal($hash->{NAME},"cmd",0);
  if ($eventa) {
    $events=join(",",@{$eventa});
  }
  if (defined ($hash->{readings}{$condition})) {
    foreach my $devReading (split(/ /,$hash->{readings}{$condition})) {
      $devReading=~ s/\$DEVICE/$hash->{helper}{triggerDev}/g if ($devReading);
      #if (!AttrVal($hash->{NAME},'notexist',undef)) {
      #  ($dev,$reading)=(split(":",$devReading));
      #  return (-1,"device does not exist: [$dev:$reading]") if ($devReading and !defined ($defs{$dev}));
      #  return (-1,"reading does not exist: [$dev:$reading]") if ($devReading and !defined($defs{$dev}{READINGS}{$reading}{VAL}));
      #}   
    }
  }
  if (defined ($hash->{internals}{$condition})) {
    foreach my $devInternal (split(/ /,$hash->{internals}{$condition})) {
      $devInternal=~ s/\$DEVICE/$hash->{helper}{triggerDev}/g if ($devInternal);
      #if (!AttrVal($hash->{NAME},'notexist',undef)) {
      #  ($dev,$internal)=(split(":",$devInternal));
      #  return (-1,"device does not exist: [$dev:$internal]") if ($devInternal and !defined ($defs{$dev}));
      #  return (-1,"internal does not exist: [$dev:$internal]") if ($devInternal and !defined($defs{$dev}{$internal}));
      #}
    }
  }
  my $command=$hash->{condition}{$condition};
  if ($command) {
    my $eventa=$hash->{helper}{triggerEvents};
    my $events="";
    if ($eventa) {
       $events=join(",",@{$eventa});
    }
    $command =~ s/\$DEVICE/$hash->{helper}{triggerDev}/g;
    $command =~ s/\$EVENTS/$events/g;
    $command =~ s/\$EVENT/$hash->{helper}{event}/g;
    #my $idx = 0;
    #my $evt;
    #foreach my $part (split(" ", $hash->{helper}{event})) {
    #   $evt='\$EVTPART'.$idx;
    #   $command =~ s/$evt/$part/g;
    #   $idx++;
    #}
  }
  my $ret = eval $command;
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
 
  my @cmdpause=SplitDoIf(':',AttrVal($pn,"cmdpause",""));
  my @sleeptimer=SplitDoIf(':',AttrVal($pn,"repeatcmd",""));
  my ($seconds, $microseconds) = gettimeofday();
  my $cmdpauseValue=EvalValueDoIf($hash,"cmdpause",$cmdpause[$nr]);
  if ($cmdpauseValue and $subnr==0) {
    return undef if ($seconds - time_str2num(ReadingsTimestamp($pn, "state", "1970-01-01 01:00:00")) < $cmdpauseValue);
  }
  if (AttrVal($pn,"repeatsame","")) {
   my @repeatsame=SplitDoIf(':',AttrVal($pn,"repeatsame",""));
   my $repeatsameValue=EvalValueDoIf($hash,"repeatsame",$repeatsame[$nr]);
    if ($subnr == 0) {
      if ($repeatsameValue) {
        $repeatnr=ReadingsVal($pn,"cmd_count",0);
        if ($last_cmd == $nr) {
          if ($repeatnr < $repeatsameValue) {
            $repeatnr++;
          } else {
            delete ($defs{$hash->{NAME}}{READINGS}{cmd_count}) if (defined ($sleeptimer[$nr]) and (AttrVal($pn,"do","") eq "always" or AttrVal($pn,"do","") eq "resetwait"));
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
    my @waitsame=SplitDoIf(':',AttrVal($pn,"waitsame",""));
    my $waitsameValue=EvalValueDoIf($hash,"waitsame",$waitsame[$nr]);
    if ($subnr == 0) {
      if ($waitsameValue) {
        my $cmd_nr="cmd_".($nr+1);
        if (ReadingsVal($pn,"waitsame","") eq $cmd_nr) {
          if ($seconds - time_str2num(ReadingsTimestamp($pn, "waitsame", "1970-01-01 01:00:00"))  > $waitsameValue) {
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
     $cmd=$hash->{do}{$nr}{$subnr};
     
     my $eventa=$hash->{helper}{triggerEvents};
     my $events="";
     if ($eventa) {
        $events=join(",",@{$eventa});
     }
     $cmd =~ s/\$DEVICE/$hash->{helper}{triggerDev}/g;
     $cmd =~ s/\$EVENTS/$events/g;
     $cmd =~ s/\$EVENT/$hash->{helper}{event}/g;
     #my $idx = 0;
     #my $evt;
     #foreach my $part (split(" ", $hash->{helper}{event})) {
     #  $evt='\$EVTPART'.$idx;
     #  $cmd =~ s/$evt/$part/g;
     #  $idx++;
     #}
     #readingsSingleUpdate ($hash, "Event",$hash->{helper}{event},0);
     ($cmd,$err)=ParseCommandsDoIf($hash,$cmd,1);
  }
  DOIF_SetState ($hash,$nr,$subnr,$event,$err);
  if (defined $hash->{do}{$nr}{++$subnr}) {
    my $last_cond=ReadingsVal($pn,"cmd_nr",0)-1;
    if (DOIF_SetSleepTimer($hash,$last_cond,$nr,$subnr,$event,-1,undef)) {
      DOIF_cmd ($hash,$nr,$subnr,$event);
    }
  } else {
    if (defined ($sleeptimer[$nr])) {
      my $last_cond=ReadingsVal($pn,"cmd_nr",0)-1;
      if (DOIF_SetSleepTimer($hash,$last_cond,$nr,0,$event,-1,$sleeptimer[$nr])) {
        DOIF_cmd ($hash,$nr,$subnr,$event);
      }
    }
  }
  #delete $hash->{helper}{cur_cmd_nr};
  return undef;
}


sub CheckiTimerDoIf($$$)
{
  my ($device,$itimer,$eventa)=@_;
  my $max = int(@{$eventa});
  my $found;
  return 1 if ($itimer =~ /\[$device(\]|,.+\])/);
  for (my $j = 0; $j < $max; $j++) {
    if ($eventa->[$j] =~ "^(.+): ") { 
      $found = ($itimer =~ /\[$device:$1(\]|:.+\]|,.+\])/);
      if ($found) {
        return 1;
      }
    }
  }
  return 0;
}



sub CheckReadingDoIf($$)
{
  my ($readings,$eventa)=@_;
  my $max = int(@{$eventa});
  my $s;
  my $found=0;
  my $device;
  my $reading;
  
  if (!defined $readings) {
    return 1;
  }
  foreach my $item (split(/ /,$readings)) {
    ($device,$reading)=(split(":",$item));
    if (defined $reading) {
      for (my $j = 0; $j < $max; $j++) {
        $s = $eventa->[$j];
        $s = "" if(!defined($s));
        $found = ($s =~ m/^$reading: /);
        if ($found) {
          return 1;
        }
      }
    }
  }
  return 0;
}

sub CheckRegexpDoIf($$$$)
{
  my ($hash,$name,$eventa,$condition)=@_;
  my $cond=($condition == -1) ? "all" : $condition;
  my $max_regexp=keys %{$hash->{regexp}{$cond}};
  my $c;
  my $nameExp;
  my $notifyExp;
  
  for (my $i=0; $i<$max_regexp;$i++) 
  {
    if ($hash->{regexp}{$cond}{$i} =~ /([^\:]*):(.*)/) {
      $nameExp=$1;
      $notifyExp=$2;
    } else {
      $nameExp=$hash->{regexp}{$cond}{$i};
    }
    $nameExp="" if (!$nameExp);
    $notifyExp="" if (!$notifyExp);
    if ($nameExp eq "" or $name =~ /$nameExp/) {
      #my $eventa = $hash->{helper}{triggerEvents};
      my $events="";
      if ($eventa) {
        $events=join(",",@{$eventa});
      }       
      if ($notifyExp eq "") {
        if ($cond ne "all") {
          $c=$cond+1;
          readingsSingleUpdate ($hash, "matched_event_c".$c."_".($i+1),"$events",0);
        }
        return 1;
      }
      my $max = int(@{$eventa});
      my $s;
      my $found;
      for (my $j = 0; $j < $max; $j++) {
        $s = $eventa->[$j];
        $s = "" if(!defined($s));
        $found = ($s =~ m/$notifyExp/);
        if ($found) {
          if ($cond ne "all") {
            $c=$cond+1;
          readingsSingleUpdate ($hash, "matched_event_c".$c."_".($i+1),$s,0);
          }
          return 1
        }
      }
    }
  }
  return 0;
} 

sub
DOIF_Trigger ($$)
{
  my ($hash,$device)= @_;
  my $timerNr=-1;
  my $ret;
  my $err;
  my $doelse=0;
  my $event="$device";
  my $pn=$hash->{NAME};
  my $max_cond=keys %{$hash->{condition}};
  my $last_cond=ReadingsVal($pn,"cmd_nr",0)-1;
  my $j;
  my @triggerEvents;
  if (AttrVal($pn, "checkall", 0) =~ "1|all|timer" and $device eq "") {
    for ($j=0; $j<$hash->{helper}{last_timer};$j++) {
      if ($hash->{timer}{$j}==1) {
        $timerNr=$j; #first timer
        last;
      }
    }
  }
  for (my $i=0; $i<$max_cond;$i++) {
    if ($device eq "") {# timer
      my $found=0;
      if (defined ($hash->{timers}{$i})) {
        foreach $j (split(" ",$hash->{timers}{$i})) {
          if ($hash->{timer}{$j} == 1) {
            $found=1;
            $timerNr=$j;
            last;
          }  
        }
      }
      next if (!$found and AttrVal($pn, "checkall", 0) !~ "1|all|timer");
      $event="timer_".($timerNr+1);
      @triggerEvents=($event);
      $hash->{helper}{triggerEvents}=\@triggerEvents;
      $hash->{helper}{triggerDev}="";
      $hash->{helper}{event}=$event;
    } else { #event
      if (!CheckRegexpDoIf($hash, $device, $hash->{helper}{triggerEvents}, $i)) { 
        if (AttrVal($pn, "checkall", 0) !~ "1|all|event") {
          next if (!defined ($hash->{devices}{$i}));
          next if ($hash->{devices}{$i} !~ / $device /);
          next if (AttrVal($pn, "checkReadingEvent", 0) and !CheckReadingDoIf ($hash->{readings}{$i},$hash->{helper}{triggerEventsState}) and (defined $hash->{internals}{$i} ? $hash->{internals}{$i} !~ / $device:.+ /:1))
        }
      }
      $event="$device";
    }
    if (($ret,$err)=DOIF_CheckCond($hash,$i)) {
      if ($err) {
        Log3 $hash->{Name},4,"$hash->{NAME}: $err" if ($ret != -1);
        readingsSingleUpdate ($hash, "error", $err,0);
        return undef;
      }
      if ($ret) {
        $hash->{helper}{timerevents}=$hash->{helper}{triggerEvents};
        $hash->{helper}{timereventsState}=$hash->{helper}{triggerEventsState};
        $hash->{helper}{timerevent}=$hash->{helper}{event};
        $hash->{helper}{timerdev}=$hash->{helper}{triggerDev};
        if (DOIF_SetSleepTimer($hash,$last_cond,$i,0,$device,$timerNr,undef)) {
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
      $hash->{helper}{timerevents}=$hash->{helper}{triggerEvents};
      $hash->{helper}{timereventsState}=$hash->{helper}{triggerEventsState};
      $hash->{helper}{timerevent}=$hash->{helper}{event};
      $hash->{helper}{timerdev}=$hash->{helper}{triggerDev};
      if (DOIF_SetSleepTimer($hash,$last_cond,$max_cond,0,$device,$timerNr,undef)) {
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
  my $eventa;
  my $eventas;
  $eventa = deviceEvents($dev, AttrVal($pn, "addStateEvent", 0)); 
  $eventas = deviceEvents($dev, 1);
  if ($dev->{NAME} eq "global" and (EventCheckDoif($dev->{NAME},"global",$eventa,"INITIALIZED") or EventCheckDoif($dev->{NAME},"global",$eventa,"REREADCFG")))
  {
    $hash->{helper}{globalinit}=1;
    # delete old timer-readings
    foreach my $key (keys %{$defs{$hash->{NAME}}{READINGS}}) {
      delete $defs{$hash->{NAME}}{READINGS}{$key} if ($key =~ "^timer_");
    }
    if ($hash->{helper}{last_timer} > 0){
      for (my $j=0; $j<$hash->{helper}{last_timer};$j++)
      {
        DOIF_SetTimer($hash,"DOIF_TimerTrigger",$j);
      }
    }
	if (AttrVal($pn,"initialize",0) and !AttrVal($pn,"disable",0)) {
		readingsBeginUpdate($hash);
		readingsBulkUpdate ($hash,"state",AttrVal($pn,"initialize",0));
		readingsBulkUpdate ($hash,"cmd_nr","0");
		readingsBulkUpdate ($hash,"cmd",0);
		readingsEndUpdate($hash, 0);
    }
  }
 
  if (($hash->{itimer}{all}) and $hash->{itimer}{all} =~ / $dev->{NAME} /) {
    for (my $j=0; $j<$hash->{helper}{last_timer};$j++) { 
	  if (CheckiTimerDoIf ($dev->{NAME},$hash->{time}{$j},$eventas)) {
  #  { if (AttrVal($pn, "checkReadingEvent", 0) and CheckiTimerDoIf ($dev->{NAME},$hash->{time}{$j},$eventas)
  #    or !AttrVal($pn, "checkReadingEvent", 0) and $hash->{time}{$j} =~ /\[$dev->{NAME}(\]|:.+\]|,.+\])/) {
        DOIF_SetTimer($hash,"DOIF_TimerTrigger",$j);
      }
    }
  }
  return "" if (ReadingsVal($pn,"mode","") eq "disabled");
  return "" if (!$hash->{helper}{globalinit});
  return "" if (defined $hash->{helper}{cur_cmd_nr});
  return "" if (!$hash->{devices}{all} and !$hash->{state}{device} and !$hash->{regexp}{all});
    
  if ((($hash->{devices}{all}) and $hash->{devices}{all} =~ / $dev->{NAME} /) or CheckRegexpDoIf($hash,$dev->{NAME},$eventa,-1)){
    $hash->{helper}{cur_cmd_nr}="Trigger  $dev->{NAME}" if (AttrVal($hash->{NAME},"selftrigger","") ne "all");
    readingsSingleUpdate ($hash, "Device",$dev->{NAME},0);
    #my $events = deviceEvents($dev, AttrVal($dev->{NAME}, "addStateEvent", 0));
    #readingsSingleUpdate ($hash, "Event","@{$events}",0);
    if ($hash->{readings}{all}) {
      foreach my $item (split(/ /,$hash->{readings}{all})) {
        ($device,$reading)=(split(":",$item));
        if ($item and $device eq $dev->{NAME} and defined ($defs{$device}{READINGS}{$reading})) { 
          if (!AttrVal($pn, "checkReadingEvent", 0) or CheckReadingDoIf ("$item",$eventas)) {
            readingsSingleUpdate ($hash, "e_".$dev->{NAME}."_".$reading,$defs{$device}{READINGS}{$reading}{VAL},0);
          }
        }
      }
    }
    if ($hash->{internals}{all}) {
      foreach my $item (split(/ /,$hash->{internals}{all})) {
        ($device,$internal)=(split(":",$item));
        readingsSingleUpdate ($hash, "e_".$dev->{NAME}."_".$internal,$defs{$device}{$internal},0) if ($item and $device eq $dev->{NAME} and defined ($defs{$device}{$internal}));
      }
    }
    if ($hash->{trigger}{all}) {
      foreach my $item (split(/ /,$hash->{trigger}{all})) {
        readingsSingleUpdate ($hash, "e_".$dev->{NAME}."_events",join(",",@{$eventa}),0);
      }
    }
    $hash->{helper}{triggerEvents}=$eventa;
    $hash->{helper}{triggerEventsState}=$eventas;
    $hash->{helper}{triggerDev}=$dev->{NAME};
    $hash->{helper}{event}=join(",",@{$eventa});
    $ret=DOIF_Trigger($hash,$dev->{NAME});
  }
  if (($hash->{state}{device}) and $hash->{state}{device} =~ / $dev->{NAME} / and !$ret) {
    $hash->{helper}{cur_cmd_nr}="Trigger  $dev->{NAME}" if (AttrVal($hash->{NAME},"selftrigger","") ne "all");
    $hash->{helper}{triggerEvents}=$eventa;
    $hash->{helper}{triggerEventsState}=$eventas;
    $hash->{helper}{triggerDev}=$dev->{NAME};
    $hash->{helper}{event}=join(",",@{$eventa});
    DOIF_SetState($hash,"",0,"","");
  }
  delete $hash->{helper}{cur_cmd_nr};
  return undef;
} 
  
sub
DOIF_TimerTrigger ($)
{
  my ($timer)=@_;
  my $hash=${$timer}->{hash};
  my $pn = $hash->{NAME};
  my $localtime=${$timer}->{localtime};
  delete $hash->{triggertime}{$localtime};
  my $ret;
  my ($now, $microseconds) = gettimeofday();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
  $hash->{helper}{cur_cmd_nr}="timer $localtime" if (AttrVal($hash->{NAME},"selftrigger","") ne "all");
  #$hash->{helper}{cur_cmd_nr}="timer $localtime";
  for (my $j=0; $j<$hash->{helper}{last_timer};$j++) {
    if ($hash->{localtime}{$j} == $localtime) {
      if (defined ($hash->{interval}{$j})) {
        if ($hash->{interval}{$j} != -1) {
          if ($hash->{realtime}{$j} eq $hash->{realtime}{$hash->{interval}{$j}}) {
            $hash->{timer}{$hash->{interval}{$j}}=0;
            next;
          }
        }
      }
      $hash->{timer}{$j}=1;
      if (!DOIF_time_once($hash,$j,$wday,$hash->{days}{$j})) {#check days
        $hash->{timer}{$j}=0;
      }
    }
  }
  $ret=DOIF_Trigger ($hash,"") if (ReadingsVal($pn,"mode","") ne "disabled"); 
  for (my $j=0; $j<$hash->{helper}{last_timer};$j++) {
    $hash->{timer}{$j}=0;
    if ($hash->{localtime}{$j} == $localtime) {
      if (!AttrVal($hash->{NAME},"disable","")) {
        if (defined ($hash->{interval}{$j})) {
          if ($hash->{interval}{$j} != -1) {
            DOIF_SetTimer($hash,"DOIF_TimerTrigger",$hash->{interval}{$j}) ;
            DOIF_SetTimer($hash,"DOIF_TimerTrigger",$j) ;
          }
        } else {
          DOIF_SetTimer($hash,"DOIF_TimerTrigger",$j) ;
        }
      }
    }
  }
  delete ($hash->{helper}{cur_cmd_nr});
  return undef;
  #return($ret);
}

sub
DOIF_DetTime($$)
{
  my ($hash, $timeStr) = @_;
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
    ($timeStr,$err)=ReplaceAllReadingsDoIf($hash,$timeStr,-3,1);
     return ($err) if ($err);
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
DOIF_CalcTime($$)
{
  my ($hash,$block)= @_;
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
    ($err,$rel,$block)=DOIF_DetTime($hash,$block);
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
      ($block,$err,$device,$reading,$internal)=ReplaceReadingEvalDoIf($hash,$block,1);
      return ($block,$err) if ($err);
    }
    ($err,$rel,$block)=DOIF_DetTime($hash, $block);
    $rel=1 if ($relGlobal);
    return ($block,$err,$rel);
  }
  $tailBlock=$block;
  while ($tailBlock ne "") {
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]');
    return ($block,$err) if ($err);
    if ($block ne "") {
 #      $ret = eval $block;
 #      return($block." ",$@) if ($@);
 #      $block=$ret;
       ($err,$rel,$block)=DOIF_DetTime($hash,"{".$block."}");
       return ($block,$err) if ($err);
    }
    $cmd.=$beginning.$block;
  }
  $tailBlock=$cmd;
  $cmd="";
  while ($tailBlock ne "") {
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\[\]]');
    return ($block,$err) if ($err);
    if ($block ne "") {
      if ($block =~ /^\??[a-z0-9._]*[a-z._]+[a-z0-9._]*($|:.+$)/i) {
        ($block,$err,$device,$reading,$internal)=ReplaceReadingEvalDoIf($hash,$block,1);
        return ($block,$err) if ($err);
      }
      ($err,$rel,$block)=DOIF_DetTime($hash,$block);
      return ($block,$err) if ($err);
    }
    $cmd.=$beginning.$block;
  }
  $ret = eval $cmd;
  return($cmd." ",$@) if ($@);
  return ($ret,"null is not allowed on a relative time",$relGlobal) if ($ret == 0 and $relGlobal);
  return ($ret,"",$relGlobal);
}

sub
DOIF_SetTimer($$$)
{
  my ($hash, $func, $nr) = @_;
  my $timeStr=$hash->{time}{$nr};
  my $cond=$hash->{timeCond}{$nr};
  my $next_time;
  
  my ($second,$err, $rel)=DOIF_CalcTime($hash,$timeStr);
  my $timernr=sprintf("timer_%02d_c%02d",($nr+1),($cond+1));
  if ($err)
  {   
      readingsSingleUpdate ($hash,$timernr,"error: ".$err,AttrVal($hash->{NAME},"timerevent","")?1:0);
      Log3 $hash->{NAME},4 , "$hash->{NAME} ".$timernr." error: ".$err;
      #RemoveInternalTimer($timer);
      $hash->{realtime}{$nr}="00:00:00";
      return $err;
  }
  
  if ($second < 0 and $rel) {
    readingsSingleUpdate ($hash,$timernr,"time offset: $second, negativ offset is not allowed",AttrVal($hash->{NAME},"timerevent","")?1:0);
    return($timernr,"time offset: $second, negativ offset is not allowed");
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
  
  if ($second <= $sec_today and !$rel) {
    $next_time+=86400;
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($next_time);
    if ($isdst_now != $isdst) {
      if ($isdst_now == 1) {
        $next_time+=3600 if ($isdst == 0);
      } else {
        $next_time-=3600 if ($second>=3*3600 or $second <= $sec_today and $second<2*3600);
      }
    }
  }
  #if ($next_time < $now and $isdst_now == $isdst) {
  #  readingsSingleUpdate ($hash,"timer_".($nr+1)."_c".($cond+1),"back to the past is not allowed",AttrVal($hash->{NAME},"timerevent","")?1:0);
  #  return("timer_".($nr+1)."_c".($cond+1),"back to the past is not allowed");
  #} else {
  
  my $next_time_str=strftime("%d.%m.%Y %H:%M:%S",localtime($next_time));
  $next_time_str.="\|".$hash->{days}{$nr} if (defined ($hash->{days}{$nr}));
  readingsSingleUpdate ($hash,$timernr,$next_time_str,AttrVal($hash->{NAME},"timerevent","")?1:0);
  $hash->{realtime}{$nr}=strftime("%H:%M:%S",localtime($next_time));
  if (defined ($hash->{localtime}{$nr})) {
    my $old_lt=$hash->{localtime}{$nr};
    my $found=0;
    delete ($hash->{localtime}{$nr});
    foreach my $lt (keys %{$hash->{localtime}}) {
      if ($hash->{localtime}{$lt} == $old_lt) {
        $found=1;
        last;
      }
    }
    if (!$found) {
      RemoveInternalTimer(\$hash->{triggertime}{$old_lt});
      delete ($hash->{triggertime}{$old_lt});
    }    
  }
  $hash->{localtime}{$nr}=$next_time;
  if (!defined ($hash->{triggertime}{$next_time})) {
    $hash->{triggertime}{$next_time}{hash}=$hash;
    $hash->{triggertime}{$next_time}{localtime}=$next_time;
    InternalTimer($next_time, $func, \$hash->{triggertime}{$next_time}, 0);
  }  
  return undef;
}

sub
DOIF_SetSleepTimer($$$$$$$)
{
  my ($hash,$last_cond,$nr,$subnr,$device,$timerNr,$repeatcmd)=@_;
  my $pn = $hash->{NAME};
  my $sleeptimer=$hash->{helper}{sleeptimer};
  my @waitdel=SplitDoIf(':',AttrVal($pn,"waitdel",""));
  my @waitdelsubnr=SplitDoIf(',',defined $waitdel[$sleeptimer] ? $waitdel[$sleeptimer] : "");
  my $err;
  
  if ($sleeptimer != -1 and (($sleeptimer != $nr or AttrVal($pn,"do","") eq "resetwait") or ($sleeptimer == $nr and $waitdelsubnr[$subnr]))) {
    RemoveInternalTimer($hash);
    #delete ($defs{$hash->{NAME}}{READINGS}{wait_timer});
    readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
    $hash->{helper}{sleeptimer}=-1;
    $subnr=$hash->{helper}{sleepsubtimer} if ($hash->{helper}{sleepsubtimer}!=-1 and $sleeptimer == $nr);
    return 0 if ($sleeptimer == $nr and $waitdelsubnr[$subnr]);
  }
    
  if ($timerNr >= 0 and !AttrVal($pn,"timerWithWait","")) {#Timer
    if ($last_cond != $nr or AttrVal($pn,"do","") eq "always" or AttrVal($pn,"repeatsame","")) {
      return 1;
    } else {
      return 0;
    }
  } 
  if ($hash->{helper}{sleeptimer} == -1 and ($last_cond != $nr or $subnr > 0 
      or AttrVal($pn,"do","") eq "always" 
      or AttrVal($pn,"do","") eq "resetwait" 
      or AttrVal($pn,"repeatsame","") 
      or defined($repeatcmd))) {
    my $sleeptime=0;
    if (defined ($repeatcmd)) {
      $sleeptime=$repeatcmd;
    } else {
      my @sleeptimer=SplitDoIf(':',AttrVal($pn,"wait",""));
      if ($waitdelsubnr[$subnr]) { 
        $sleeptime = $waitdelsubnr[$subnr];
      } else {
        my @sleepsubtimer=SplitDoIf(',',defined $sleeptimer[$nr]? $sleeptimer[$nr]: "");
        if ($sleepsubtimer[$subnr]) {
          $sleeptime=$sleepsubtimer[$subnr];
        }
      }
    }
    $sleeptime=EvalValueDoIf($hash,"wait",$sleeptime);
    if ($sleeptime) {
      my $seconds = gettimeofday();
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
    } elsif (defined($repeatcmd)){
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
  $hash->{helper}{cur_cmd_nr}="wait_timer" if (!AttrVal($hash->{NAME},"selftrigger",""));
  $hash->{helper}{triggerEvents}=$hash->{helper}{timerevents};
  $hash->{helper}{triggerEventsState}=$hash->{helper}{timereventsState};
  $hash->{helper}{event}=$hash->{helper}{timerevent};
  $hash->{helper}{triggerDev}=$hash->{helper}{timerdev};
  readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
# if (!AttrVal($hash->{NAME},"disable","")) {
  if (ReadingsVal($pn,"mode","") ne "disabled") {
    DOIF_cmd ($hash,$sleeptimer,$sleepsubtimer,$hash->{helper}{sleepdevice});
  }
  delete $hash->{helper}{cur_cmd_nr};
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
    $tail =~ s/(##.*\n)|(##.*$)|\n/ /g;
    $tail =~ s/\$SELF/$hash->{NAME}/g;
  }
   
#def modify
  if ($init_done)
  {
    DOIF_delTimer($hash);
    DOIF_delAll ($hash);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"cmd",0);
    readingsBulkUpdate($hash,"state","initialized");
    readingsEndUpdate($hash, 1);
    $hash->{helper}{globalinit}=1;
  }
  
  $hash->{helper}{last_timer}=0;
  $hash->{helper}{sleeptimer}=-1;

  return("","") if ($tail =~ /^ *$/);
  
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
    $tail =~ s/^\s*$//g;
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
  } elsif($a[0] eq "del" && $a[2] eq "state") {
      delete ($hash->{state}{device});
  } elsif($a[0] eq "set" && $a[2] eq "wait") {
      RemoveInternalTimer($hash);
      #delete ($defs{$hash->{NAME}}{READINGS}{wait_timer});
      readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
      $hash->{helper}{sleeptimer}=-1;
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

  if ($arg eq "disable" or  $arg eq "initialize" or  $arg eq "enable") {
    if (AttrVal($hash->{NAME},"disable","")) {
      return ("modul ist deactivated by disable attribut, delete disable attribut first");
    }
  }
  if ($arg eq "disable") {
      readingsBeginUpdate  ($hash);
      readingsBulkUpdate($hash,"last_cmd",ReadingsVal($pn,"state",""));
      readingsBulkUpdate($hash, "state", "disabled");
      readingsBulkUpdate($hash, "mode", "disabled");
      readingsEndUpdate    ($hash, 1);
  } elsif ($arg eq "initialize" ) {
      delete ($defs{$hash->{NAME}}{READINGS}{mode});
      delete ($defs{$hash->{NAME}}{READINGS}{cmd_nr});
      delete ($defs{$hash->{NAME}}{READINGS}{cmd_event});
      readingsSingleUpdate($hash, "state","initialize",1);
  } elsif ($arg eq "enable" ) {
      #delete ($defs{$hash->{NAME}}{READINGS}{mode});
      readingsSingleUpdate ($hash,"state",ReadingsVal($pn,"last_cmd",""),0) if (ReadingsVal($pn,"last_cmd","") ne "");
      delete ($defs{$hash->{NAME}}{READINGS}{last_cmd});
      readingsSingleUpdate ($hash,"mode","enable",1)
  } elsif ($arg =~ /^cmd_(.*)/ ) {
    if (ReadingsVal($pn,"mode","") ne "disabled") {
	  if ($hash->{helper}{sleeptimer} != -1) {
         RemoveInternalTimer($hash);
	     readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
	     $hash->{helper}{sleeptimer}=-1;
      }
      DOIF_cmd ($hash,$1-1,0,"set_cmd_".$1);
	}
  } else {
      my $setList = AttrVal($pn, "setList", " ");
      $setList =~ s/\n/ /g;
	  my $cmdList="";
	  my $max_cond=keys %{$hash->{condition}};
	  $max_cond++ if (defined ($hash->{do}{$max_cond}{0}) or ($max_cond == 1 and !(AttrVal($pn,"do","") or AttrVal($pn,"repeatsame",""))));
	  for (my $i=0; $i <$max_cond;$i++) {
	   $cmdList.="cmd_".($i+1).":noArg ";
	  }
      return "unknown argument ? for $pn, choose one of disable:noArg initialize:noArg enable:noArg $cmdList $setList" if($arg eq "?");
      my @rl = split(" ", AttrVal($pn, "readingList", ""));
      my $doRet;
      eval {
        if(@rl && grep /\b$arg\b/, @rl) {
          my $v = shift @a;
          $v = shift @a;
          readingsSingleUpdate($hash, $v, join(" ",@a), 1);
          $doRet = 1;
        }
      };
      return if($doRet);
      return "unknown argument $arg for $pn, choose one of disable:noArg initialize:noArg enable:noArg cmd $setList";
  } 
  return $ret;
}


1;

=pod
=item helper
=item summary    universal module, it works event- and time-controlled   
=item summary_DE universelles Modul, welches ereignis- und zeitgesteuert Anweisungen ausführt
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
Many examples with english identifiers - see <a href="http://fhem.de/commandref_DE.html#DOIF">german section</a>.
<br>
</ul>
=end html
=begin html_DE

<a name="DOIF"></a>
<h3>DOIF</h3>
<ul>
DOIF (ausgeprochen: du if, übersetzt: tue wenn) ist ein universelles Modul, welches ereignis- und zeitgesteuert in Abhängigkeit definierter Bedingungen Anweisungen ausführt.<br>
<br>
In einer Hausautomatisation geht es immer wieder um die Ausführung von Befehlen abhängig von einem Ereignis. Oft reicht aber eine einfache Abfrage der Art: "wenn Ereignis eintritt, dann Befehl ausführen" nicht aus.
Ebenso häufig möchte man eine Aktion nicht nur von einem einzelnen Ereignis abhängig ausführen, sondern abhängig von mehreren Bedingungen, z. B. "schalte Außenlicht ein, wenn es dunkel wird, aber nicht vor 18:00 Uhr"
oder "schalte die Warmwasserzirkulation ein, wenn die Rücklauftemperatur unter 38 Grad fällt und jemand zuhause ist".
In solchen Fällen muss man mehrere Bedingung logisch miteinander verknüpfen. Ebenso muss sowohl auf Ereignisse wie auch auf Zeittrigger gleichermaßen reagiert werden.
<br><br>
An dieser Stelle setzt das Modul DOIF an. Es stellt eine eigene Benutzer-Schnittstelle zur Verfügung ohne Programmierkenntnisse in Perl unmittelbar vorauszusetzen.
Mit diesem Modul ist es möglich, sowohl Ereignis- als auch Zeitsteuerung mit Hilfe logischer Abfragen miteinander zu kombinieren.
Damit können komplexere Problemstellungen innerhalb eines DOIF-Moduls gelöst werden, ohne Perlcode in Kombination mit anderen Modulen programmieren zu müssen.
<br><br>
Das DOIF-Modul bedient sich selbst des Perlinterpreters, damit sind beliebige logische Abfragen möglich. Logische Abfragen werden in DOIF/DOELSEIF-Bedingungen vornehmlich mit Hilfe von and/or-Operatoren erstellt.
Diese werden mit Angaben von Stati, Readings, Internals, Events oder Zeiten kombiniert.
Sie werden grundsätzlich in eckigen Klammern angegeben und führen zur Triggerung des Moduls und damit zur Auswertung der dazugehörigen Bedingung.
Zusätzlich können in einer Bedingung Perl-Funktionen angegeben werden, die in FHEM definiert sind.
Wenn eine Bedingung wahr wird, so werden die dazugehörigen Befehle ausgeführt.<br>
<br>
Syntax:<br>
<br>
<ol><code>define &lt;name&gt; DOIF (&lt;Bedingung&gt;) (&lt;Befehle&gt;) DOELSEIF (&lt;Bedingung&gt;) (&lt;Befehle&gt;) DOELSEIF ... DOELSE (&lt;Befehle&gt;)</code></ol>
<br>
Die Angaben werden immer von links nach rechts abgearbeitet. Zu beachten ist, dass nur die Bedingungen überprüft werden,
die zum ausgelösten Event das dazughörige Device bzw. die dazugehörige Triggerzeit beinhalten.
Kommt ein Device in mehreren Bedingungen vor, so wird immer nur ein Kommando ausgeführt, und zwar das erste,
für das die dazugehörige Bedingung in der abgearbeiteten Reihenfolge wahr ist.<br><br>
Das DOIF-Modul arbeitet mit Zuständen. Jeder Ausführungszweig DOIF/DOELSEIF..DOELSEIF/DOELSE stellt einen eigenen Zustand dar (cmd_1, cmd_2, usw.).
Das Modul merkt sich den zuletzt ausgeführten Ausführungszweig und wiederholt diesen standardmäßig nicht.
Ein Ausführungszweig wird erst dann wieder ausgeführt, wenn zwischenzeitlich ein anderer Ausführungszweig ausgeführt wurde, also ein Zustandswechsel stattgefunden hat.
Dieses Verhalten ist sinnvoll, um zu verhindern, dass zyklisch sendende Sensoren (Temperatur, Feuchtigkeit, Helligkeit, usw.) zu ständiger Wiederholung des selben Befehls oder Befehlsabfolge führen.<br>
<br>
<u>Einfache Anwendungsbeispiele:</u><ol>
<br>
Fernbedienung (Ereignissteuerung): <code>define di_rc_tv DOIF ([remotecontol] eq "on") (set tv on) DOELSE (set tv off)</code><br>
<br>
Zeitschaltuhr (Zeitsteuerung): <code>define di_clock_radio DOIF ([06:30]) (set radio on) DOELSEIF ([08:00]) (set radio off)</code><br>
<br>
Kombinierte Ereignis- und Zeitsteuerung: <code>define di_lamp DOIF ([06:00-09:00] and [sensor:brightness] &lt; 40) (set lamp on) DOELSE (set lamp off)</code><br>
</ol><br>
<a name="DOIF_Inhaltsuebersicht"></a>
<b>Inhaltsübersicht</b><br>
<ul><br>
  <a href="#DOIF_Features">Features</a><br>
  <a href="#DOIF_Lesbarkeit_der_Definitionen">Lesbarkeit der Definitionen</a><br>
  <a href="#DOIF_Ereignissteuerung">Ereignissteuerung</a><br>
  <a href="#DOIF_Teilausdruecke_abfragen">Teilausdrücke abfragen</a><br>
  <a href="#DOIF_Ereignissteuerung_ueber_Auswertung_von_Events">Ereignissteuerung über Auswertung von Events</a><br>
  <a href="#DOIF_Angaben_im_Ausfuehrungsteil">Angaben im Ausführungsteil</a><br>
  <a href="#DOIF_Zeitsteuerung">Zeitsteuerung</a><br>
  <a href="#DOIF_Relative_Zeitangaben">Relative Zeitangaben</a><br>
  <a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet">Zeitangaben nach Zeitraster ausgerichtet</a><br>
  <a href="#DOIF_Relative_Zeitangaben_nach_Zeitraster_ausgerichtet">Relative Zeitangaben nach Zeitraster ausgerichtet</a><br>
  <a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet_alle_X_Stunden">Zeitangaben nach Zeitraster ausgerichtet alle X Stunden</a><br>
  <a href="#DOIF_Wochentagsteuerung">Wochentagsteuerung</a><br>
  <a href="#DOIF_Zeitsteuerung_mit_Zeitintervallen">Zeitsteuerung mit Zeitintervallen</a><br>
  <a href="#DOIF_Indirekten_Zeitangaben">Indirekten Zeitangaben</a><br>
  <a href="#DOIF_Zeitsteuerung_mit_Zeitberechnung">Zeitsteuerung mit Zeitberechnung</a><br>
  <a href="#DOIF_Kombination_von_Ereignis_und_Zeitsteuerung_mit_logischen_Abfragen">Kombination von Ereignis- und Zeitsteuerung mit logischen Abfragen</a><br>
  <a href="#DOIF_Zeitintervalle_Readings_und_Stati_ohne_Trigger">Zeitintervalle, Readings und Stati ohne Trigger</a><br>
  <a href="#DOIF_Nutzung_von_Readings_Stati_oder_Internals_im_Ausfuehrungsteil">Nutzung von Readings, Stati oder Internals im Ausführungsteil</a><br>
  <a href="#DOIF_Berechnungen_im_Ausfuehrungsteil">Berechnungen im Ausführungsteil</a><br>
  <a href="#DOIF_notexist">Ersatzwert für nicht existierende Readings oder Stati</a><br>
  <a href="#DOIF_Filtern_nach_Zahlen">Filtern nach Ausdrücken mit Ausgabeformatierung</a><br>
  <a href="#DOIF_wait">Verzögerungen</a><br>
  <a href="#DOIF_timerWithWait">Verzögerungen von Timern</a><br>
  <a href="#DOIF_do_resetwait">Zurücksetzen des Waittimers für das gleiche Kommando</a><br>
  <a href="#DOIF_repeatcmd">Wiederholung von Befehlsausführung</a><br>
  <a href="#DOIF_cmdpause">Zwangspause für das Ausführen eines Kommandos seit der letzten Zustandsänderung</a><br>
  <a href="#DOIF_repeatsame">Begrenzung von Wiederholungen eines Kommandos</a><br>
  <a href="#DOIF_waitsame">Ausführung eines Kommandos nach einer Wiederholung einer Bedingung</a><br>
  <a href="#DOIF_waitdel">Löschen des Waittimers nach einer Wiederholung einer Bedingung</a><br>
  <a href="#DOIF_checkReadingEvent">Readingauswertung nur beim Event des jeweiligen Readings</a><br>
  <a href="#DOIF_addStateEvent">Eindeutige Statuserkennung</a><br>
  <a href="#DOIF_selftrigger">Triggerung durch selbst ausgelöste Events</a><br>
  <a href="#DOIF_timerevent">Setzen der Timer mit Event</a><br>
  <a href="#DOIF_Zeitspanne_eines_Readings_seit_der_letzten_Aenderung">Zeitspanne eines Readings seit der letzten Änderung</a><br>
  <a href="#DOIF_setList__readingList">Darstellungselement mit Eingabemöglichkeit im Frontend und Schaltfunktion</a><br>
  <a href="#DOIF_cmdState">Status des Moduls</a><br>
  <a href="#DOIF_Reine_Statusanzeige_ohne_Ausfuehrung_von_Befehlen">Reine Statusanzeige ohne Ausführung von Befehlen</a><br>
  <a href="#DOIF_state">Anpassung des Status mit Hilfe des Attributes <code>state</code></a><br>
  <a href="#DOIF_initialize">Vorbelegung des Status mit Initialisierung nach dem Neustart mit dem Attribut <code>initialize</code></a><br>
  <a href="#DOIF_disable">Deaktivieren des Moduls</a><br>  
  <a href="#DOIF_cmd">Bedingungslose Ausführen von Befehlszweigen</a><br>
  <a href="#DOIF_Initialisieren_des_Moduls">Initialisieren des Moduls</a><br>
  <a href="#DOIF_Weitere_Anwendungsbeispiele">Weitere Anwendungsbeispiele</a><br>
  <a href="#DOIF_Zu_beachten">Zu beachten</a><br>
  <a href="https://wiki.fhem.de/wiki/DOIF">DOIF im FHEM-Wiki</a><br>
  <a href="https://forum.fhem.de/index.php/board,73.0.html">DOIF im FHEM-Forum</a><br>
  <a href="#DOIF_Kurzreferenz">Kurzreferenz</a><br>
<!-- Vorlage Inhaltsübersicht und Sprungmarke-->
  <a href="#DOIF_"></a><br>
<a name="DOIF_"></a>
<!-- Vorlage Rücksprung zur Inhaltsübersicht-->
<!--&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>-->
</ul>
  <a name="DOIF_Attribute"></a>
  <a href="#DOIF_Attribute_kurz"><b>Attribute</b></a><br>
  <ul>
  <a href="#DOIF_cmdpause">cmdpause</a> &nbsp;
  <a href="#DOIF_cmdState">cmdState</a> &nbsp;
  <a href="#DOIF_disable">disable</a> &nbsp;
  <a href="#DOIF_do_always">do always</a> &nbsp;
  <a href="#DOIF_do_resetwait">do resetwait</a> &nbsp;
  <a href="#DOIF_initialize">initialize</a> &nbsp;
  <a href="#DOIF_notexist">notexist</a> &nbsp;
  <a href="#DOIF_repeatcmd">repeatcmd</a> &nbsp;
  <a href="#DOIF_repeatsame">repeatsame</a> &nbsp;
  <a href="#DOIF_state">state</a> &nbsp;
  <a href="#DOIF_timerWithWait">timerWithWait</a> &nbsp;
  <a href="#DOIF_wait">wait</a> &nbsp;
  <a href="#DOIF_waitdel">waitdel</a> &nbsp;
  <a href="#DOIF_waitsame">waitsame</a> &nbsp;
  <a href="#DOIF_checkReadingEvent">checkReadingEvent</a> &nbsp;
  <a href="#DOIF_addStateEvent">addStateEvent</a> &nbsp;
  <a href="#DOIF_selftrigger">selftrigger</a> &nbsp;
  <a href="#DOIF_timerevent">timerevent</a> &nbsp;
  <a href="#DOIF_checkall">checkall</a> &nbsp;
  <a href="#DOIF_setList__readingList">setList</a> &nbsp;
  <a href="#DOIF_setList__readingList">readingList</a> &nbsp;
  
  <br><a href="#readingFnAttributes">readingFnAttributes</a> &nbsp;
  </ul>
<br>
<a name="DOIF_Features"></a>
<b>Features</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<ol><br>
+ Syntax angelehnt an Verzweigungen if - elseif - ... - elseif - else in höheren Programmiersprachen<br>
+ Pro Modul können beliebig viele Zeit- und beliebig viele Ereignis-Angaben logisch miteinander kombiniert werden<br>
+ Das Modul reagiert sowohl auf Ereignisse als auch auf Zeittrigger<br>
+ Bedingungen werden vom Perl-Interpreter ausgewertet, daher sind beliebige logische Abfragen möglich<br>
+ Es können beliebig viele DOELSEIF-Angaben gemacht werden, sie sind, wie DOELSE am Ende der Kette, optional<br>
+ Verzögerungsangaben mit Zurückstellung sind möglich (watchdog-Funktionalität)<br>
+ Der Ausführungsteil kann jeweils ausgelassen werden. Damit kann das Modul für reine Statusanzeige genutzt werden<br>
</ol><br>
<a name="DOIF_Lesbarkeit_der_Definitionen"></a>
<b>Lesbarkeit der Definitionen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Da die Definitionen im Laufe der Zeit recht umfangreich werden können, sollten die gleichen Regeln, wie auch beim Programmieren in höheren Programmiersprachen, beachtet werden.
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
<a name="DOIF_Ereignissteuerung"></a>
<b>Ereignissteuerung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_do_always"></a>
Wünscht man eine Ausführung des gleichen Befehls mehrfach nacheinander bei jedem Trigger, unabhängig davon welchen Zustand das DOIF-Modul hat, 
weil z. B. Garage nicht nur über die Fernbedienung geschaltet wird, dann muss man das per "do always"-Attribut angeben:<br>
<br>

<code>attr di_garage do always</code><br>
<br>
Bei der Angabe von zyklisch sendenden Sensoren (Temperatur, Feuchtigkeit, Helligkeit usw.) wie z. B.:<br>
<br>
<code>define di_heating DOIF ([sens:temperature] < 20) (set heating on)</code><br>
<br>
ist die Nutzung des Attributes <code>do always</code> nicht sinnvoll, da das entsprechende Kommando hier: "set heating on" jedes mal ausgeführt wird,
wenn der Temperatursensor in regelmäßigen Abständen eine Temperatur unter 20 Grad sendet.
Ohne <code>do always</code> wird hier dagegen erst wieder "set heating on" ausgeführt, wenn der Zustand des Moduls auf "cmd_2" gewechselt hat, also die Temperatur zwischendurch größer oder gleich 20 Grad war.<br>
<br>
Zu beachten ist, dass bei <code>do always</code> der Zustand "cmd_2" bei Nichterfüllung der Bedingung nicht gesetzt wird.
Möchte man dennoch bei Nichterfüllung der Bedingung einen Zustandswechsel auf "cmd_2" erreichen, so muss man am Ende seiner Definition DOELSE ohne weitere Angaben setzen.
Wenn das Attribut <code>do always</code> nicht gesetzt ist, wird dagegen bei Definitionen mit einer einzigen Bedingung, wie im obigen Beispiel, der Zustand "cmd_2" bei Nichterfüllung der Bedingung automatisch gesetzt.
Ohne diesen automatischen Zustandswechsel, wäre ansonsten die Definition nicht sinnvoll, da der Zustand "cmd_1" ohne <code>do always</code> nur ein einziges Mal ausgeführt werden könnte.<br> 
<br>
<a name="DOIF_Teilausdruecke_abfragen"></a>
<b>Teilausdrücke abfragen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_Ereignissteuerung_ueber_Auswertung_von_Events"></a>
<b>Ereignissteuerung über Auswertung von Events</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Eine Alternative zur Auswertung von Stati oder Readings ist das Auswerten von Ereignissen (Events) mit Hilfe von regulären Ausdrücken, wie beim notify. Der Suchstring wird als regulärer Ausdruck in Anführungszeichen angegeben.
Die Syntax lautet: <code>[&lt;devicename&gt;:"&lt;regex&gt;"]</code><br>
<br>
<u>Anwendungsbeispiel</u>: wie oben, jedoch wird hier nur das Ereignis (welches im Eventmonitor erscheint) ausgewertet und nicht der Status von "remotecontrol" wie im vorherigen Beispiel<br>
<br>
<code>define di_garage DOIF ([remotecontrol:"on"]) (set garage on) DOELSEIF ([remotecontrol:"off"]) (set garage off)</code><br>
<br>
In diesem Beispiel wird nach dem Vorkommen von "on" innerhalb des Events gesucht.
Falls "on" gefunden wird, wird der Ausdruck wahr und der DOIF-Fall wird ausgeführt, ansonsten wird der DOELSEIF-Fall entsprechend ausgewertet.
Die Auswertung von reinen Ereignissen bietet sich dann an, wenn ein Modul keinen Status oder Readings benutzt, die man abfragen kann, wie z. B. beim Modul "sequence".
Die Angabe von regulären Ausdrücken kann recht komplex werden und würde die Aufzählung aller Möglichkeiten an dieser Stelle den Rahmen sprengen.
Weitere Informationenen zu regulären Ausdrücken sollten in der Perl-Dokumentation nachgeschlagen werden.
Die logische Verknüpfung "and" mehrerer Ereignisse ist nicht sinnvoll, da zu einem Zeitpunkt immer nur ein Ereignis zutreffen kann.<br>
<br>
Die alte Syntax <code>[&lt;devicename&gt;:?&lt;regex&gt;]</code> wird aus Kompatibilitätsgründen noch unterstützt, sollte aber nicht mehr benutzt werden.<br>
<br>
Sollen Events verschiedener Devices ausgewertet werden, so lässt sich folgende Syntax anwenden: <code>["&lt;device regex&gt;:&lt;event regex&gt;"]</code><br>
<br>
Im Gegensatz zum notify werden vom DOIF-Modul selbst keine Regex-Sonderzeichen hinzugefügt. Insb. wird kein ^ für Anfang vorangestellt, bzw. kein $ für Ende angehängt.<br>
<br>
Beispiele für Regex-Angaben: <br>
<br>
["FS"] triggert auf alle Devices, die "FS" im Namen beinhalten <br>
["^FS"] triggert auf alle Devices, die mit "FS" im Namen anfangen <br>
["FS:temp"] triggert auf alle Devices, die "FS" im Namen und "temp" im Event beinhalten <br>
([":^temp"]) triggert auf beliebige Devices, die im Event mit "temp" beginnen <br>
(["^FS$:^temp$"] triggert auf Devices, die genau "FS" heißen und im Event genau "temp" vorkommt <br>
[""] triggert auf alles<br>
<br>
In der Bedingung und im Ausführungsteil werden die Schlüsselwörter $SELF durch den eigenen Namen des DOIF-Moduls, $DEVICE durch das aktuelle Device, $EVENT durch die passende Eventzeile, $EVENTS kommagetrennt durch alle Eventzeilen des Triggers ersetzt.<br>
<br>
Entsprechend können Perl-Variablen in der DOIF-Bedingung ausgewertet werden, sie werden in Kleinbuchstaben geschrieben. Sie lauten: $device, $event, $events<br>
<br>
<u>Anwendungsbeispiele</u>:<br>
<br>
Loggen aller Ereignisse in FHEM<br>
<br>
<code>define di_all_events DOIF ([""]) ({Log 3,"Events from device $DEVICE:$EVENTS"})<br>
<br>
attr di_all_events do always<br></code>
<br>
"Fenster offen"-Meldung<br>
<br>
<code>define di_window_open (["^window_:open"]) (set Pushover msg 'alarm' 'open windows $DEVICE' '' 2 'persistent' 30 3600)<br>
<br>
attr di_window_open do always</code><br>
<br>
Hier werden alle Fenster, die mit dem Device-Namen "window_" beginnen auf "open" im Event überwacht.<br>
<br>
Verzögerte "Fenster offen"-Meldung<br>
<br>
<code>define di_window_open DOIF ["^window_:open|tilted"])<br>
  (defmod at_$DEVICE at +00:05 set send window $DEVICE open)<br>
DOELSEIF (["^window_:closed"])<br>
  (delete at_$DEVICE)<br>
<br>
attr di_window_open do always</code><br>
<br>
Alternative mit sleep<br>
<br>
<code>define di_window_open DOIF ["^window_:open|tilted"])<br>
  (sleep 300 $DEVICE quiet;set send window $DEVICE open)<br>
DOELSEIF (["^window_:closed"])<br>
  (cancel $DEVICE quiet)<br>
<br>
attr di_window_open do always</code><br>
<br>
In den obigen beiden Beispielen ist eine Verzögerung über das Attribut wait nicht sinnvoll, da pro Fenster ein eigener Timer (hier mit Hilfe von at/sleep) gesetzt werden muss.<br>
<br>
Batteriewarnung per E-Mail verschicken<br>
<br>
<code>define di_battery DOIF ([":battery: low"] and [?$SELF:B_$DEVICE] ne "low")<br>
  <ol>({DebianMail('yourname@gmail.com', 'FHEM - battery warning from device: $DEVICE')}, setreading $SELF B_$DEVICE low)</ol>
DOELSEIF ([":battery: ok"] and [?$SELF:B_$DEVICE] ne "ok")<br>
  <ol>(setreading $SELF B_$DEVICE ok)</ol>
<br>  
attr di_battery do always</code><br>
<br>
Eine aktuelle Übersicht aller Batterie-Stati entsteht gleichzeitig in den Readings des di_battery-DOIF-Moduls.<br>
<br>
<br>
Allgemeine Ereignistrigger können ebenfalls so definiert werden, dass sie nicht nur wahr zum Triggerzeitpunkt und sonst nicht wahr sind,
 sondern Inhalte des Ereignisses zurückliefern. Initiiert wird dieses Verhalten durch die Angabe eines Default-Wertes.<br>
<br>
Syntax:<br>
<br>
<code>["regex for trigger",&lt;default value&gt;]</code><br>
<br>
Anwendungsbeispiel:<br>
<br>
<code>define di_warning DOIF ([":^temperature",0]< 0 and [06:00-09:00] ) (set pushmsg danger of frost)</code><br>
<br>
Damit wird auf alle Devices getriggert, die mit "temperature" im Event beginnen. Zurückgeliefert wird der Wert, der im Event hinter "temperature: " steht.
Wenn kein Event stattfindet, wird der Defaultwert, hier 0,  zurückgeliefert.
<br>
Ebenfalls kann ein Ereignisfilter mit Ausgabeformatierung angegeben werden.<br>
<br>
Syntax:<br>
<br>
<code>["regex for trigger":"&lt;regex filter&gt;":&lt;output&gt;,&lt;default value&gt;]</code><br>
<br>
Regex-Filter- und Output-Parameter sind optional. Der Default-Wert ist verpflichtend.<br>
<br>
Die Angaben zum Filter und Output funktionieren, wie die beim Reading-Filter. Siehe: <a href="#DOIF_Filtern_nach_Zahlen">Filtern nach Ausdrücken mit Ausgabeformatierung</a><br><br>
<br>
Wenn kein Filter, wie obigen Beispiel, angegeben wird, so wird intern folgende Regex vorbelegt: "[^\:]*: (.*)"  Damit wird der Wert hinter der Readingangabe genommen.
Durch eigene Regex-Filter-Angaben kann man beliebige Teile des Events herausfiltern, ggf. über Output formatieren und in der Bedingung entsprechend auswerten,
 ohne auf Readings zurückgreifen zu müssen.<br>
<br>
<a name="DOIF_Angaben_im_Ausfuehrungsteil"></a>
<b>Angaben im Ausführungsteil</b>:&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_Zeitsteuerung"></a>
<b>Zeitsteuerung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_Relative_Zeitangaben"></a>
<b>Relative Zeitangaben</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet"></a>
<b>Zeitangaben nach Zeitraster ausgerichtet</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_Relative_Zeitangaben_nach_Zeitraster_ausgerichtet"></a>
<b>Relative Zeitangaben nach Zeitraster ausgerichtet</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Das Format lautet: [+:MM] MM sind Minutenangaben zwischen 1 und 59.<br>
<br>
<u>Anwendungsbeispiel</u>: Gong alle fünfzehn Minuten um XX:00 XX:15 XX:30 XX:45<br>
<br>
<code>define di_gong DOIF ([+:15]) (set Gong_mp3 playTone 1)<br>
attr di_gong do always</code><br>
<br>
<a name="DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet_alle_X_Stunden"></a>
<b>Zeitangaben nach Zeitraster ausgerichtet alle X Stunden</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Format: [+[h]:MM] mit: h sind Stundenangaben zwischen 2 und 23 und MM Minuten zwischen 00 und 59<br>
<br>
<u>Anwendungsbeispiel</u>: Es soll immer fünf Minuten nach einer vollen Stunde alle 2 Stunden eine Pumpe eingeschaltet werden, die Schaltzeiten sind 00:05, 02:05, 04:05 usw.<br>
<br>
<code>define di_gong DOIF ([+[2]:05]) (set pump on-for-timer 300)<br>
attr di_gong do always</code><br>
<br>
<a name="DOIF_Wochentagsteuerung"></a>
<b>Wochentagsteuerung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
define di_radio DOIF ([06:30|[Wochentag]]) (set radio on) DOELSEIF ([07:30|[Wochentag]]) (set radio off)</code><br>
<br>
<a name="DOIF_Zeitsteuerung_mit_Zeitintervallen"></a>
<b>Zeitsteuerung mit Zeitintervallen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_Indirekten_Zeitangaben"></a>
<b>Indirekten Zeitangaben</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Oft möchte man keine festen Zeiten im Modul angeben, sondern Zeiten, die man z. B. über Dummys über die Weboberfläche verändern kann.
Statt fester Zeitangaben können Stati, Readings oder Internals angegeben werden. Diese müssen eine Zeitangabe im Format HH:MM oder HH:MM:SS oder eine Zahl beinhalten.<br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll zu einer bestimmten Zeit eingeschaltet werden. Die Zeit soll über den Dummy <code>time</code> einstellbar sein:<br>
<br>
<code>define time dummy<br>
set time 08:00<br>
define di_time DOIF ([[time]])(set lamp on)<br>
attr di_time do always</code><br>
<br>
Die indirekte Angabe kann ebenfalls mit einer Zeitfunktion belegt werden. Z. B. <br>
<br>
<code>set time {sunset()}</code><br>
<br>
Das Dummy kann auch mit einer Sekundenzahl belegt werden, oder als relative Zeit angegeben werden, hier z. B. schalten alle 300 Sekunden:<br>
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
Indirekte Zeitangaben können auch als Übergabeparameter für Zeitfunktionen, wie z. B. sunset oder sunrise übergeben werden:<br>
<br>
<code>define di_time DOIF ([{sunrise(0,"[begin]","09:00")}-{sunset(0,"18:00","[end]")}]) (set lamp off) DOELSE (set lamp on) </code><br>
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
<a name="DOIF_Zeitsteuerung_mit_Zeitberechnung"></a>
<b>Zeitsteuerung mit Zeitberechnung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_Kombination_von_Ereignis_und_Zeitsteuerung_mit_logischen_Abfragen"></a>
<b>Kombination von Ereignis- und Zeitsteuerung mit logischen Abfragen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll ab 6:00 Uhr angehen, wenn es dunkel ist und wieder ausgehen, wenn es hell wird, spätestens aber um 9:00 Uhr:<br>
<br>
<code>define di_lamp DOIF ([06:00-09:00] and [sensor:brightness] &lt; 40) (set lamp on) DOELSE (set lamp off)</code><br>
<br>
<u>Anwendungsbeispiel</u>: Rollläden sollen an Arbeitstagen nach 6:25 Uhr hochfahren, wenn es hell wird, am Wochenende erst um 9:00 Uhr, herunter sollen sie wieder, wenn es dunkel wird:<br>
<br>
<code>define di_shutters DOIF ([sensor:brightness]&gt;100 and [06:25-09:00|8] or [09:00|7]) (set shutters up) DOELSEIF ([sensor:brightness]&lt;50) (set shutters down)</code><br>
<br>
<a name="DOIF_Zeitintervalle_Readings_und_Stati_ohne_Trigger"></a>
<b>Zeitintervalle, Readings und Stati ohne Trigger</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Angaben in eckigen Klammern, die mit einem Fragezeichen beginnen, führen zu keiner Triggerung des Moduls, sie dienen lediglich der Abfrage.<br>
<br>
<u>Anwendungsbeispiel</u>: Licht soll zwischen 06:00 und 10:00 angehen, getriggert wird nur durch den Taster nicht um 06:00 bzw. 10:00 Uhr und nicht durch das Device Home<br>
<br>
<code>define di_motion DOIF ([?06:00-10:00] and [button] and [?Home] eq "present")(set lamp on-for-timer 600)<br>
attr di_motion do always</code><br>
<br>
<a name="DOIF_Nutzung_von_Readings_Stati_oder_Internals_im_Ausfuehrungsteil"></a>
<b>Nutzung von Readings, Stati oder Internals im Ausführungsteil</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_Berechnungen_im_Ausfuehrungsteil"></a>
<b>Berechnungen im Ausführungsteil</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Berechnungen können in geschweiften Klammern erfolgen. Aus Kompatibilitätsgründen, muss die Berechnung unmittelbar mit einer runden Klammer beginnen.
Innerhalb der Perlberechnung können Readings, Stati oder Internals wie gewohnt in eckigen Klammern angegeben werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Es soll ein Vorgabewert aus zwei verschiedenen Readings ermittelt werden und an das set Kommando übergeben werden:<br>
<br>
<code>define di_average DOIF ([08:00]) (set TH_Modul desired {([default:temperature]+[outdoor:temperature])/2})<br>
attr di_average do always</code><br>
<br>
<a name="DOIF_notexist"></a>
<b>Ersatzwert für nicht existierende Readings oder Stati</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Es kommt immer wieder vor, dass in der Definition des DOIF-Moduls angegebene Readings oder Stati zur Laufzeit nicht existieren. Der Wert ist dann leer.
Bei der Definition von Stati oder Readings kann für diesen Fall ein Vorgabewert oder sogar eine Perlberechnung am Ende des Ausdrucks kommagetrennt angegeben werden.<br>
<br>
Syntax:<br>
<br>
<code>[&lt;device&gt,&lt;default value&gt;]</code><br>
oder <br>
<code>[&lt;device&gt:&lt;reading&gt,&lt;default value&gt;]</code><br>
<br>
Beispiele:<br>
<br>
<code>
[lamp,"off"]<br>
[room:temperatur,20]<br>
[brightness,3*[myvalue]+2]<br>
[heating,AttrVal("mydevice","myattr","")]<br>
[[mytime,"10:00"]]<br>
</code><br>
Möchte man stattdessen einen bestimmten Wert global für das gesamte Modul definieren,
so lässt sich das über das Attribut <code>notexist</code> bewerkstelligen. Ein angegebener Default-Wert beim Status oder beim Reading übersteuert das "notexist"-Attribut.<br>
<br>
Syntax: <code>attr &lt;DOIF-module&gt; notexist "&lt;default value&gt;"</code> <br>
<br>
<a name="DOIF_Filtern_nach_Zahlen"></a>
<b>Filtern nach Ausdrücken mit Ausgabeformatierung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Syntax: <code>[&lt;Device&gt;:&lt;Reading&gt;|&lt;Internal&gt;:d|"&lt;Regex&gt;":&lt;Output&gt;]</code><br>
<br>
d - Der Buchstabe "d" ist ein Synonym für das Filtern nach Dezimalzahlen, es entspricht intern dem regulären Ausdruck "(-?\d+(\.\d+)?)"<br>
&lt;Regex&gt;- Der reguläre Ausdruck muss in Anführungszeichen angegeben werden. Dabei werden Perl-Mechanismen zu regulären Ausdrücken mit Speicherung der Ergebnisse in Variablen $1, $2 usw. genutzt.<br>
&lt;Output&gt; - ist ein optionaler Parameter, hier können die in den Variablen $1, $2, usw. aus der Regex-Suche gespeicherten Informationen für die Aufbereitung genutzt werden. Sie werden in Anführungzeichen bei Texten oder in Perlfunktionen angegeben. Wird kein Output-Parameter angegeben, so wird automatisch $1 genutzt.<br>
<br>
Beispiele:<br>
<br>
Es soll aus einem Reading, das z. B. ein Prozentzeichen beinhaltet, nur der Zahlenwert für den Vergleich genutzt werden:<br>
<br>
<code>define di_heating DOIF ([adjusting:actuator:d] &lt; 10) (set heating off) DOELSE (set heating on)</code><br>
<br>
Alternativen für die Nutzung der Syntax am Beispiel des Filterns nach Zahlen:<br>
<br>
<code>[mydevice:myreading:d]</code><br>
entspricht:<br>
<code>[mydevice:myreading:"(-?\d+(\.\d+)?)"]</code><br>
entspricht:<br>
<code>[mydevice:myreading:"(-?\d+(\.\d+)?)":$1]</code><br>
entspricht:<br>
<code>[mydevice:myreading:"(-?\d+(\.\d+)?)":"$1"]</code><br>
entspricht:<br>
<code>[mydevice:myreading:"(-?\d+(\.\d+)?)":sprintf("%s":$1)]</code><br>
<br>
Es soll aus einem Text eine Zahl herausgefiltert werden und anschließend die Einheit °C angehängt werden:<br>
<br>
<code>... (set mydummy [mydevice:myreading:d:"$1 °C"])</code><br>
<br>
Es soll die Zahl aus einem Reading auf 2 Nachkommastellen formatiert werden:<br>
<br>
<code>[mydevice:myreading:d:sprintf("%.2f",$1)]</code><br>
<br>
Es sollen aus einem Reading der Form "HH:MM:SS" die Stunden, Minuten und Sekunden separieret werden:<br>
<br>
<code>[mydevice:myreading:"(\d\d):(\d\d):(\d\d)":"hours: $1, minutes $2, seconds: $3"]</code><br>
<br>
Der Inhalt des Dummys Alarm soll in einem Text eingebunden werden:<br>
<br>
<code>[alarm:state:"(.*)":"state of alarm is $1"]</code><br>
<br>
Die Definition von regulären Ausdrücken mit Nutzung der Perl-Variablen $1, $2 usw. kann in der Perldokumentation nachgeschlagen werden.<br>
<br>
<a name="DOIF_wait"></a>
<b>Verzögerungen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Verzögerungen für die Ausführung von Kommandos werden pro Befehlsfolge über das Attribut "wait" definiert. Syntax:<br>
<br>
<code>attr &lt;DOIF-module&gt; wait &lt;Sekunden für Befehlsfolge des ersten DO-Falls&gt;:&lt;Sekunden für Befehlsfolge des zweiten DO-Falls&gt;:...<br></code>
<br>

Sollen Verzögerungen innerhalb von Befehlsfolgen stattfinden, so müssen diese Komandos in eigene Klammern gesetzt werden, das Modul arbeitet dann mit Zwischenzuständen.<br>
<br>
Beispiel: Bei einer Befehlssequenz, hier: <code>(set lamp1 on, set lamp2 on)</code>, soll vor dem Schalten von <code>lamp2</code> eine Verzögerung von einer Sekunde stattfinden.
Die Befehlsfolge muss zunächst mit Hilfe von Klammerblöcke in eine Befehlssequenz aufgespalten werden: <code>(set lamp1 on)(set lamp2 on)</code>.
Nun kann mit dem wait-Attribut nicht nur für den Beginn der Sequenz, sondern für jeden Klammerblock eine Verzögerung, getrennt mit Komma, definieren werden,
 hier also: <code>wait 0,1</code>. Damit wird <code>lamp1</code> sofort, <code>lamp2</code> eine Sekunde danach geschaltet. Die Verzögerungszeit bezieht sich immer auf den vorherigen Befehl.<br>
<br> 
Beispieldefinition bei mehreren DO-Blöcken mit Befehlssequenzen:<br>
<br>
<code>DOIF (Bedingung1)<br>
(set ...) ## erster Befehl der ersten Sequenz soll um eine Sekunde verzögert werden<br>
(set ...) ## zweiter Befehl der ersten Sequenz soll um 2 Sekunden nach dem ersten Befehl verzögert werden<br>
DOELSEIF (Bedingung2)<br>
(set ...) ## erster Befehl der zweiten Sequenz soll um 3 Sekunden verzögert werden<br>
(set ...) ## zweiter Befehl der zweiten Sequenz soll um 0,5 Sekunden nach dem ersten Befehl verzögert werden<br>
<br>
attr &lt;DOIF-module&gt; wait 1,2:3,0.5</code><br>
<br>
Das Aufspalten einer kommagetrennten Befehlskette in eine Befehlssequenz, wie im obigen Beispiel, sollte nicht vorgenommen werden, wenn keine Verzögerungen zwischen den Befehlen benötigt werden.
Denn bei einer Befehlssequenz werden Zwischenzustände cmd1_1, cmd1_2 usw. generiert, die Events erzeugen und damit unnötig FHEM-Zeit kosten.<br>
<br>
Für Kommandos, die nicht verzögert werden sollen, werden Sekundenangaben ausgelassen oder auf Null gesetzt. Die Verzögerungen werden nur auf Events angewandt und nicht auf Zeitsteuerung. Eine bereits ausgelöste Verzögerung wird zurückgesetzt, wenn während der Wartezeit ein Kommando eines anderen DO-Falls, ausgelöst durch ein neues Ereignis, ausgeführt werden soll.<br>
<br>
Statt Sekundenangaben können ebenfalls Stati, Readings in eckigen Klammen, Perl-Funktionen sowie Perl-Berechnung angegeben werden. Dabei werden die Trennzeichen Komma und Doppelpunkt in Klammern geschützt und gelten dort nicht als Trennzeichen.
Diese Angaben können ebenfalls bei folgenden Attributen gemacht werden: cmdpause, repeatcmd, repeatsame, waitsame, waitdel<br>
<br>
Beispiel:<br>
<br>
<code>attr my_doif wait 1:[mydummy:state]*3:rand(600)+100,Attr("mydevice","myattr","")</code><br>
<br>
<a name="DOIF_timerWithWait"></a>
<br>
<b>Verzögerungen von Timern</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Verzögerungen können mit Hilfe des Attributs <code>timerWithWait</code> auf Timer ausgeweitet werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll zufällig nach Sonnenuntergang verzögert werden.<br>
<br>
<code>define di_rand_sunset DOIF ([{sunset()}])(set lamp on)<br>
attr di_rand_sunset wait rand(1200)<br>
attr di_rand_sunset timerWithWait 1<br>
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
<a name="DOIF_do_resetwait"></a>
<b>Zurücksetzen des Waittimers für das gleiche Kommando</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_repeatcmd"></a>
<b>Wiederholung von Befehlsausführung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Wiederholungen der Ausführung von Kommandos werden pro Befehlsfolge über das Attribut "repeatcmd" definiert. Syntax:<br>
<br>
<code>attr &lt;DOIF-modul&gt; repeatcmd &lt;Sekunden für Befehlsfolge des ersten DO-Falls&gt;:&lt;Sekunden für Befehlsfolge des zweiten DO-Falls&gt;:...<br></code>
<br>
Statt Sekundenangaben können ebenfalls Stati in eckigen Klammen oder Perlbefehle angegeben werden.<br>
<br>
Die Wiederholung findet so lange statt, bis der Zustand des Moduls in einen anderen DO-Fall wechselt.<br>
<br>
<u>Anwendungsbeispiel</u>: Nach dem Eintreffen des Ereignisses wird die push-Meldung stündlich wiederholt, bis Frost ungleich "on" ist.<br>
<br>
<code>define di_push DOIF ([frost] eq "on")(set pushmsg "danger of frost")<br>
attr di_push repeatcmd 3600</code><br>
<br>
Eine Begrenzung der Wiederholungen kann mit dem Attribut repeatsame vorgenommen werden<br>
<code>attr di_push repeatsame 3</code><br>
<br>
Ebenso lässt sich das repeatcmd-Attribut mit Zeitangaben kombinieren.<br>
<br>
<u>Anwendungsbeispiel</u>: Wiederholung ab einem Zeitpunkt<br>
<br>
<code>define di_alarm_clock DOIF ([08:00])(set alarm_clock on)<br>
attr di_alarm_clock repeatcmd 300<br>
attr di_alarm_clock repeatsame 3<br>
attr di_alarm_clock do always</code><br>
<br>
Ab 8:00 Uhr wird 3 mal der Weckton jeweils nach 5 Minuten wiederholt.<br>
<br>
<u>Anwendungsbeispiel</u>: Warmwasserzirkulation<br>
<br>
<code>define di_pump_circ DOIF ([05:00-22:00])(set pump on)(set pump off) DOELSE (set pump off)<br>
attr di_pump_circ wait 0,300<br>
attr di_pump_circ repeatcmd 3600</code><br>
<br>
Zwischen 5:00 und 22:00 Uhr läuft die Zirkulationspumpe alle 60 Minuten jeweils 5 Minuten lang.<br>
<br>
<u>Anwendungsbeispiel</u>: Anwesenheitssimulation<br>
<br>
<code>define di_presence_simulation DOIF ([19:00-00:00])(set lamp on-for-timer {(int(rand(1800)+300))}) DOELSE (set lamp off)<br>
attr di_presence_simulation repeatcmd rand(3600)+2200</code><br>
<br>
<br>
<a name="DOIF_cmdpause"></a>
<b>Zwangspause für das Ausführen eines Kommandos seit der letzten Zustandsänderung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_repeatsame"></a>
<b>Begrenzung von Wiederholungen eines Kommandos</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_waitsame"></a>
<b>Ausführung eines Kommandos nach einer Wiederholung einer Bedingung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_waitdel"></a>
<b>Löschen des Waittimers nach einer Wiederholung einer Bedingung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_checkReadingEvent"></a>
<br>
<b>Readingauswertung nur beim Event des jeweiligen Readings</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Standardmäßig werden angegebene Readings ausgewertet, wenn irgend ein Event des angegebenen Devices triggert.
Möchte man gezielt nur dann ein angegebenes Reading auswerten, wenn sich nur dieses ändert, so lässt sich das mit dem Attribut <code>checkReadingEvent</code> einschränken.
Das ist insb. dann interessant, wenn ein Modul verschiedene Readings zu unterschiedlichen Zeitpunkten aktualisiert.<br>
<br>
<u>Beispiel</u>:<br>
<br>
<code>define di_lamp DOIF ([mytwilight:light] < 3) (set lamp on) DOELSEIF ([mytwilight:light] > 3) (set lamp off)<br>
attr di_lamp checkReadingEvent 1</code><br>
<br>
Bei der Angabe von indirekten Timern wird grundsätzlich intern <code>checkReadingEvent</code> benutzt:<br>
<br>
<code>define di_lamp ([[mytwilight:ss_weather]]) (set lamp on)<br>
attr di_lamp do always</code><br>
<br>
Hier braucht das Attribut <code>checkReadingEvent</code> nicht explizit gesetzt werden.
Die Zeit wird nur dann neu gesetzt, wenn sich tatsächlich das Reading ss_weather ändert.<br>
<br>
<a name="DOIF_addStateEvent"></a>
<b>Eindeutige Statuserkennung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Bei Änderungen des Readings state wird in FHEM standardmäßig, im Gegensatz zu allen anderen Readings, der Readingname hier: "state: " im Event nicht vorangestellt.
Möchte man eindeutig eine Statusänderung eines Moduls erkennen, so lässt sich das mit dem Attribut <code>addStateEvent</code> bewerksteligen.
Bei Statusänderungen eines Devices wird bei der Angabe des Attributes <code>addStateEvent</code> im Event "state: " vorangestellt, darauf kann man dann gezielt im DOIF-Modul triggern.<br>
<br>
<u>Beispiel</u>:<br>
<br>
<code>define di_lamp ([FB:"^state: on$"]) (set lamp on)<br>
attr di_lamp do always<br>
attr di_lamp addStateEvent</code><br>
<br>
<a name="DOIF_selftrigger"></a>
<b>Triggerung durch selbst ausgelöste Events</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Standardmäßig unterbindet das DOIF-Modul Selbsttriggerung. D. h. das Modul reagiert nicht auf Events, die es selbst direkt oder indirekt auslöst. Dadurch werden Endlosschleifen verhindert.
Wenn das Attribut <code>selftrigger wait</code> gesetzt ist, kann das DOIF-Modul auf selbst ausgelöste Events reagieren. Dazu müssen die entsprchenden Kommandos mit wait verzögert werden.
Bei der Angabe  <code>selftrigger all</code> reagiert das Modul grundsätzlich alle selbst ausgelösten Trigger.<br>
<br>
Zu beachten ist, dass der Zustand des Moduls erst nach der Ausführung des Befehls gesetzt wird, dadurch wird die Zustandsverwaltung (ohne do always) ausgehebelt.
Die Auswertung des eigenen Zustands z. B. über [$SELF:cmd] funktioniert dagegen korrekt, weil dieser immer bei der eigenen Triggerung bereits gesetzt ist.
Bei der Verwendung des Attributes <code>selftrigger all</code> sollte beachtet werden, dass bereits in der zweiten Rekursion,
 wenn ein Befehl nicht durch wait verzögert wird, FHEM eine weitere Triggerung unterbindet, um Endlosschleifen zu verhindern.<br>
<br>
<a name="DOIF_timerevent"></a>
<b>Setzen der Timer mit Event</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Wenn das Attribut <code>timerevent</code> ungleich Null gesetzt ist, wird beim Setzen der Timer im DOIF-Modul ein Event erzeugt. Das kann z. B. bei FHEM2FHEM nützlich sein, um die Timer-Readings zeitnah zu aktualisieren.<br>
<br>
<a name="DOIF_Zeitspanne_eines_Readings_seit_der_letzten_Aenderung"></a>
<b>Zeitspanne eines Readings seit der letzten Änderung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Bei Readingangaben kann die Zeitspanne mit <code>[&lt;Device&gt;:&lt;Reading&gt;:sec]</code> in Sekunden seit der letzten Änderung bestimmt werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Licht soll angehen, wenn der Status des Bewegungsmelders in den letzten fünf Sekunden upgedatet wurde.<br>
<br>
<code>define di_lamp DOIF ([BM:state:sec] < 5) (set lamp on-for-timer 300)<br>
attr di_lamp do always</code><br>
<br>
Bei HM-Bewegungsmelder werden periodisch Readings aktualisiert, dadurch wird das Modul getrigger, auch wenn keine Bewegung stattgefunden hat.
Der Status bleibt dabei auf "motion". Mit der obigen Abfrage lässt sich feststellen, ob der Status aufgrund einer Bewegung tatsächlich upgedatet wurde.<br>
<br>
<a name="DOIF_checkall"></a>
<b>Alle Bedingungen prüfen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Bei der Abarbeitung der Bedingungen, werden nur die Bedingungen überprüft,
die zum ausgelösten Event das dazughörige Device bzw. die dazugehörige Triggerzeit beinhalten. Mit dem Attribut <b>checkall</b> lässt sich das Verhalten so verändern,
dass bei einem Event-Trigger auch Bedingungen geprüft werden, die das triggernde Device nicht beinhalten.
Folgende Parameter können angebeben werden:<br>
<br>
<code>checkall event</code> Es werden alle Bedingungen geprüft, wenn ein Event-Trigger auslöst.<br>
<code>checkall timer</code> Es werden alle Bedingungen geprüft, wenn ein Timer-Trigger auslöst.<br>
<code>checkall all&nbsp;&nbsp;</code> Es werden grundsätzlich alle Bedingungen geprüft.<br>
<br>
Zu beachten ist, dass bei einer wahren Bedingung die dazugehörigen Befehle ausgeführt werden und die Abarbeitung immer beendet wird -
 es wird also grundsätzlich immer nur ein Befehlszweig ausgeführt und niemals mehrere.<br>
<br>
<a name="DOIF_setList__readingList"></a>
<b>Darstellungselement mit Eingabemöglichkeit im Frontend und Schaltfunktion</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Die unter <a href="#dummy">Dummy</a> beschriebenen Attribute <a href="#readingList">readingList</a> und <a href="#setList">setList</a> stehen auch im DOIF zur Verf&uuml;gung. Damit wird erreicht, dass DOIF im WEB-Frontend als Eingabeelement mit Schaltfunktion dienen kann. Zus&auml;tzliche Dummys sind nicht mehr erforderlich. Es k&ouml;nnen im Attribut <a href="#setList">setList</a>, die in <a href="#FHEMWEB">FHEMWEB</a> angegebenen Modifier des Attributs <a href="#widgetOverride">widgetOverride</a> verwendet werden. Siehe auch das <a href="http://www.fhemwiki.de/wiki/DOIF/Ein-_und_Ausgabe_in_FHEMWEB_und_Tablet-UI_am_Beispiel_einer_Schaltuhr">weiterf&uuml;hrende Beispiel für Tablet-UI</a>. Für die Verwendung moduleigener Readings ist die Funktionalität nicht gew&auml;hrleistet, siehe <a href="#DOIF_Benutzerreadings">benutzerdefinierte Readings</a>.<br>
<br>
<u>Anwendungsbeispiel</u>: Eine Schaltuhr mit time-Widget f&uuml;r die Ein- u. Ausschaltzeiten und der M&ouml;glichkeit &uuml;ber eine Auswahlliste manuell ein und aus zu schalten.<br>
<br>
<code>
define time_switch DOIF (["$SELF:mybutton: on"] or [[$SELF:mybegin,"00:00"]])
<ol>(set lamp on)</ol>
DOELSEIF (["$SELF:mybutton: off"] or [[$SELF:myend,"00:00"]])
<ol>(set lamp off)</ol>
<br>
attr time_switch cmdState on|off<br>
attr time_switch readingList mybutton mybegin myend<br>
attr time_switch setList mybutton:on,off mybegin:time myend:time<br>
attr time_switch webCmd mybutton:mybegin:myend
</code><br>
<br>
<a name="DOIF_cmdState"></a>
<b>Status des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Der Status des Moduls wird standardmäßig mit cmd_1, cmd_2, usw., bzw. cmd1_1 cmd1_2 usw. für Befehlssequenzen belegt. Dieser lässt sich über das Attribut "cmdState" mit Komma bzw. | getrennt umdefinieren:<br>
<br>
attr &lt;DOIF-modul&gt; cmdState  &lt;Status für cmd1_1&gt;,&lt;Status für cmd1_2&gt;,...| &lt;Status für cmd2_1&gt;,&lt;Status für cmd2_2&gt;,...|...<br>
<br>
Beispiele:<br>
<br>
<code>attr di_lamp cmdState on|off</code><br>
<br>
Pro Status können ebenfalls Stati oder Readings in eckigen Klammern oder Perlfunktionen sowie Berechnungen in Klammern der Form {(...)} angegeben werden.<br>
Die Trennzeichen Komma und | sind in Klammern und Anführungszeichen geschützt und gelten dort nicht als Trennzeichen.<br>
<br>
Zustände cmd1_1, cmd1 und cmd2 sollen wie folgt umdefiniert werden:<br>
<br>
<code>attr di_mytwilight cmdState [mytwilight:ss_astro], {([mytwilight:twilight_weather]*2+10)}|My attribut is: {(Attr("mydevice","myattr",""))}</code><br>
<br>
<a name="DOIF_Reine_Statusanzeige_ohne_Ausfuehrung_von_Befehlen"></a>
<b>Reine Statusanzeige ohne Ausführung von Befehlen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Der Ausführungsteil kann jeweils ausgelassen werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Aktuelle Außenfeuchtigkeit im Status<br>
<br>
<code>define di_hum DOIF ([outdoor:humidity]&gt;70) DOELSEIF ([outdoor:humidity]&gt;50) DOELSE<br>
attr di_hum cmdState wet|normal|dry</code><br>
<br>
<a name="DOIF_state"></a>
<b>Anpassung des Status mit Hilfe des Attributes <code>state</code></b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<a name="DOIF_initialize"></a>
<b>Vorbelegung des Status mit Initialisierung nach dem Neustart mit dem Attribut <code>initialize</code></b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<u>Anwendungsbeispiel</u>: Nach dem Neustart soll der Zustand von <code>di_lamp</code> mit "initialized" vorbelegt werden. Das Reading <code>cmd_nr</code> wird auf 0 gesetzt, damit wird ein Zustandswechsel provoziert, das Modul wird initialisiert - der nächste Trigger führt zum Ausführen eines Kommandos.<br>
<br>
<code>attr di_lamp intialize initialized</code><br>
<br>
Das ist insb. dann sinnvoll, wenn das System ohne Sicherung der Konfiguration (unvorhergesehen) beendet wurde und nach dem Neustart die zuletzt gespeicherten Zustände des Moduls nicht mit den tatsächlichen übereinstimmen.<br>
<br>
<a name="DOIF_disable"></a>
<b>Deaktivieren des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Ein DOIF-Modul kann mit Hilfe des Attributes disable, deaktiviert werden. Dabei werden alle Timer und Readings des Moduls gelöscht.
Soll das Modul nur vorübergehend deaktiviert werden, so kann das durch <code>set &lt;DOIF-modul&gt; disable</code> geschehen. 
Hierbei bleiben alle Timer aktiv, sie werden aktualisiert - das Modul bleibt im Takt, allerding werden keine Befehle ausgeführt.
Das Modul braucht mehr Rechenzeit, als wenn es komplett über das Attribut deaktiviert wird. In beiden Fällen bleibt der Zustand nach dem Neustart erhalten, das Modul bleibt deaktiviert.<br>
<br>
<a name="DOIF_Initialisieren_des_Moduls"></a>
<b>Initialisieren des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit <code>set &lt;DOIF-modul&gt; initialize</code> wird ein mit <code>set &lt;DOIF-modul&gt; disable</code> deaktiviertes Modul wieder aktiviert.
Das Kommando <code>set &lt;DOIF-modul&gt; initialize</code> kann auch dazu genutzt werden ein aktives Modul zu initialisiert,
in diesem Falle wird der letzte Zustand des Moduls gelöscht, damit wird ein Zustandswechsel herbeigeführt, der nächste Trigger führt zur Ausführung.<br>
<br>
<a name="DOIF_cmd"></a>
<b>Auführen von Befehlszweigen ohne Auswertung der Bedingung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit <code>set &lt;DOIF-modul&gt; cmd_&lt;nr&gt</code> lässt sich ein Befehlszweig (cmd_1, cmd_2, usw.) bedingunglos ausführen.<br>
<br>
Der Befehl hat folgende Eigenschaften:<br>
<br>
1) der set-Befehl übersteuert alle Attribute wie z. B. wait, do, usw.<br>
2) ein laufender Wait-Timer wird unterbrochen<br>
3) beim deaktivierten oder im Modus disable befindlichen Modul wird der set Befehl ignoriert<br>
<br>
<u>Anwendungsbeispiel</u>: Schaltbare Lampe über Fernbedienung und Webinterface<br>
<br>
<code>
define di_lamp DOIF ([FB:"on"]) (set lamp on) DOELSEIF ([FB:"off"]) (set lamp off)<br>
attr di_lamp cmdState on|off<br>
attr di_lamp devStateIcon on:on:cmd_2 initialized|off:off:cmd_1<br>
</code><br>
Mit der Definition des Attribut <code>devStateIcon</code> führt das Anklicken des on/off-Lampen-Icons zum Ausführen des set-Kommandos cmd_1 bzw. cmd_2 und damit zum Schalten der Lampe.<br>
<br>
<a name="DOIF_Weitere_Anwendungsbeispiele"></a>
<b>Weitere Anwendungsbeispiele</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<code>define di_on_for_timer ([detector:"motion"])<br>
  (set light on)<br>
  (set light off)<br>
attr di_on_for_timer do resetwait<br>
attr di_on_for_timer wait 0,30</code><br>
<br>
Hiermit wird das Licht bei Bewegung eingeschaltet. Dabei wird, solange es brennt, bei jeder Bewegung die Ausschaltzeit neu auf 30 Sekunden gesetzt, "set light on" wird dabei nicht unnötig wiederholt.<br>
<br>
Die Beispiele stellen nur eine kleine Auswahl von möglichen Problemlösungen dar. Da sowohl in der Bedingung (hier ist die komplette Perl-Syntax möglich), als auch im Ausführungsteil, keine Einschränkungen gegeben sind, sind die Möglichkeiten zur Lösung eigener Probleme mit Hilfe des Moduls sehr vielfältig.<br>
<br>
<a name="DOIF_Zu_beachten"></a>
<b>Zu beachten</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
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
<!-- Beginn der Kurzreferenz -->
<a name="DOIF_Kurzreferenz"></a>
<b>Kurzreferenz</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a></br>

<ul>
&lang;&rang; kennzeichnet optionale Angaben
</ul>
</br>
<u><a href="#DOIF">Definition</a></u>
<ul>
<dl>
        <dt> <code><b>define</b> &lt;name&gt; <b>DOIF </b>&lang;<b>(</b>&lt;Bedingung&gt;<b>) </b>&lang;&lang;<b>(</b>&lang;&lt;Befehle&gt;&rang;<b>)</b>&rang; &lang;&lang;&lang;<b>DOELSEIF (</b>&lt;Bedingung&gt;<b>) </b>&lang;<b>(</b>&lang;&lt;Befehle&gt;&rang;<b>)</b>&rang;&rang; ... &rang;&lang;<b>DOELSE </b>&lang;<b>(</b>&lang;&lt;Befehle&gt;&rang;<b>)</b>&rang;&rang;&rang;&rang;&rang;</code>
        </dt>
                <dd>Befehlstrennzeichen ist das Komma<code><b> (</b>&lt;Befehl&gt;<b>,</b> &lt;Befehl&gt;, ...<b>)</b></code>
                </dd>
                <dd>Befehlssequenzen werden in runde Klammern gesetzt <code><b>(</b>&lt;Befehlssequenz A&gt;<b>) (</b>&lt;Befehlssequenz B&gt;<b>) ...</b></code>
                </dd>
                <dd>Enth&auml;lt ein Befehl Kommata, ist er zus&auml;tzlich in runde Klammern einzuschliessen <code><b>(</b>&lt;Befehlsteil a&gt;<b>, </b>&lt;Befehlsteil b&gt; ... <b>)</b></code>
                </dd>
                <dd>Perl-Befehle <code><b>{</b>&lt;Perl-Befehl&gt;<b>}</b></code> sind in geschweifte Klammern einzuschliessen
                </dd>
                <dd>Jede <a href="#DOIF_Berechnungen_im_Ausfuehrungsteil">Berechnung</a> <code><b>{(</b>&lt;Berechnung&gt;<b>)</b>&lang;&lt;Berechnung&gt;&rang;<b>}</b></code> in einem Befehl ist in geschweifte Klammern einzuschliessen und muss mit einer ge&ouml;ffneten runden Klammer beginnen.
                </dd>
</dl>
</ul>
</br>
<u>Readings</u>
<ul>
<dl>
        <dt>Device</dt>
                <dd>Name des ausl&ouml;senden Ger&auml;tes</dd>
</br>
        <dt>cmd</dt>
                <dd>Nr. des letzten ausgef&uuml;hrten Befehls als Dezimalzahl oder 0 nach Initialisierung des DOIF, in der Form &lt;Nr. des Befehlszweiges&gt;&lang;.&lt;Nr. der Sequenz&gt;&rang;</dd>
</br>
        <dt>cmd_event</dt>
                <dd>Angabe des ausl&ouml;senden Ereignisses</dd>
</br>
        <dt>cmd_nr</dt>
                <dd>Nr. des letzten ausgef&uuml;hrten Befehlszweiges</dd>
</br>
        <dt>cmd_seqnr</dt>
                <dd>Nr. der letzten ausgef&uuml;hrten Befehlssequenz</dd>
</br>
        <dt>e_&lt;Device&gt;_&lt;Reading&gt;|&lt;Internal&gt;|Events</dt>
                <dd>Bezeichner und Wert der ausl&ouml;senden Ger&auml;te mit Readings, Internals oder Events</dd>
</br>
        <dt>error</dt>
                <dd>Enthält Fehlermeldungen oder R&uuml;ckgabewerte von Befehlen, siehe <a href="http://www.fhemwiki.de/wiki/DOIF/Tools_und_Fehlersuche#Besonderheit_des_Error-Reading">Besonderheit des Error-Reading</a></dd>
</br>
        <dt>last_cmd</dt>
                <dd>letzter Status</dd>
</br>
        <dt>matched_event_c&lt;lfd. Nr. der Bedingung&gt;_&lt;lfd. Nr. des Events&gt;</dt>
                <dd>Wert, der mit dem Regul&auml;ren Ausdruck &uuml;bereinstimmt</dd>
</br>
        <dt>mode</dt>
                <dd>der Modus, in dem sich DOIF befindet: &lt;disabled|enable&gt;</dd>
</br>
        <dt>state</dt>
                <dd>Status des DOIF nach Befehlsausf&uuml;hrung, Voreinstellung: cmd_&lt;Nr. des Befehlszweiges&gt;&lang;_&lt;Nr. der Befehlssequenz&gt;&rang;</dd>
</br>
        <dt>timer_&lt;lfd. Nr.&gt;_c&lt;Nr. des Befehlszweiges&gt;</dt>
                <dd>verwendete Timer mit Angabe des n&auml;chsten Zeitpunktes</dd>
</br>
        <dt>wait_timer</dt>
                <dd>Angabe des aktuellen Wait-Timers</dd>
</br>
  <a name="DOIF_Benutzerreadings"></a>
        <dt>&lt;A-Z&gt;_&lt;readingname&gt;</dt>
                <dd>Readings, die mit einem Großbuchstaben und nachfolgendem Unterstrich beginnen, sind für User reserviert und werden auch zuk&uuml;nftig nicht vom Modul selbst benutzt.</dd>
</dl>
</br>
</ul>
<u>Operanden in der Bedingung und den Befehlen</u>
<ul>
<dl>
        <dt><a href="#DOIF_Ereignissteuerung">Stati</a> <code><b>[</b>&lt;Device&gt;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
                <dd></dd>
</br>
        <dt><a href="#DOIF_Ereignissteuerung">Readings</a> <code><b>[</b>&lt;Device&gt;<b>:</b>&lt;Reading&gt;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
                <dd></dd>
</br>
        <dt><a href="#DOIF_Ereignissteuerung">Internals</a> <code><b>[</b>&lt;Device&gt;<b>:&amp;</b>&lt;Internal&gt;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
                <dd></dd>
</br>
        <dt><a href="#DOIF_Filtern_nach_Zahlen">Filtern allgemein</a> nach Ausdr&uuml;cken mit Ausgabeformatierung: <code><b>[</b>&lt;Device&gt;:&lt;Reading&gt;|&lt;Internal&gt;:"&lt;Filter&gt;"&lang;:&lt;Output&gt;&rang;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
</br>
        <dt><a href="#DOIF_Filtern_nach_Zahlen">Filtern einer Zahl</a> <code><b>[</b>&lt;Device&gt;<b>:</b>&lt;Reading&gt;<b>:d</b>&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
</br>
        <dt><a href="#DOIF_Zeitspanne_eines_Readings_seit_der_letzten_Aenderung">Zeitspanne eines Readings seit der letzten &Auml;nderung</a> <code><b>[</b>&lt;Device&gt;<b>:</b>&lt;Reading&gt;<b>:sec</b>&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
</br>
        <dt>$DEVICE</dt>
                <dd>f&uuml;r den Ger&auml;tenamen</dd>
</br>
        <dt>$EVENT</dt>
                <dd>f&uuml;r das zugeh&ouml;rige Ereignis</dd>
</br>
        <dt>$EVENTS</dt>
                <dd>f&uuml;r alle zugeh&ouml;rigen Ereignisse eines Triggers</dd>
</br>
        <dt>$SELF</dt>
                <dd>f&uuml;r den Ger&auml;tenamen des DOIF</dd>
</br>
        <dt>&lt;Perl-Funktionen&gt;</dt>
                <dd>vorhandene und selbsterstellte Perl-Funktionen</dd>
</dl>
</br>
</ul>

<u>Operanden in der Bedingung</u>
<ul>
<dl>
        <dt><a href="#DOIF_Ereignissteuerung_ueber_Auswertung_von_Events">Events</a> <code><b>[</b>&lt;Device&gt;<b>:"</b>&lt;Regex-Events&gt;"<b>]</b></code> oder <code><b>["</b>&lt;Regex-Devices&gt;<b>:</b>&lt;Regex-Events&gt;<b>"]</b></code> oder <code><b>["</b>&lt;Regex-Devices&gt;<b>"</b>&lang;<b>:"</b>&lt;Regex-Filter&gt;<b>"</b>&rang;&lang;<b>:</b>&lt;Output&gt;&rang;<b>,</b>&lt;Default&gt;<b>]</b></code></dt>
                <dd>f&uuml;r <code>&lt;Regex&gt;</code> gilt: <code><b>^</b>&lt;ist eindeutig&gt;<b>$</b></code>, <code><b>^</b>&lt;beginnt mit&gt;</code>, <code>&lt;endet mit&gt;<b>$</b></code>, <code><b>""</b></code> entspricht <code><b>".*"</b></code>, Regex-Filter ist mit <code><b>[^\:]*: (.*)</b></code> vorbelegt siehe auch <a target=blank href="https://wiki.selfhtml.org/wiki/Perl/Regul%C3%A4re_Ausdr%C3%BCcke">Regul&auml;re Ausdr&uuml;cke</a> und Events des Ger&auml;tes <a target=blank href="#global">global</a>
                </dd>
</br>
        <dt><a href="#DOIF_Zeitsteuerung">Zeitpunkte</a> <code><b>[</b>&lt;time&gt;<b>]</b> </code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl] </b></code> in Sekunden nach Mitternacht</dd>
</br>
        <dt><a href="#DOIF_Zeitsteuerung_mit_Zeitintervallen">Zeitintervalle</a> <code><b>[</b>&lt;begin&gt;<b>-</b>&lt;end&gt;<b>]</b></code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl]</b></code> in Sekunden nach Mitternacht</dd>
</br>
        <dt><a href="#DOIF_Indirekten_Zeitangaben">indirekte Zeitangaben</a> <code><b>[[</b>&lt;indirekte Zeit&gt;<b>]]</b></code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl]</b></code> in Sekunden nach Mitternacht, <code>&lt;indirekte Zeit&gt;</code> ist ein Stati, Reading oder Internal</dd>
</br>
        <dt><a href="#DOIF_Relative_Zeitangaben">relative Zeitangaben</a> <code><b>[+</b>&lt;time&gt;<b>]</b></code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl]</b></code> in Sekunden</dd>
</br>
        <dt><a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet">ausgerichtete Zeitraster</a> <code><b>[:MM]</b></code></dt>
                <dd>in Minuten zwischen 00 und 59</dd>
</br>
        <dt><a href="#DOIF_Relative_Zeitangaben_nach_Zeitraster_ausgerichtet">rel. Zeitraster ausgerichtet</a> <code><b>[+:MM]</b></code></dt>
                <dd>in Minuten zwischen 1 und 59</dd>
</br>
        <dt><a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet_alle_X_Stunden">rel. Zeitraster ausgerichtet alle X Stunden</a> <code><b>[+[h]:MM]</b></code></dt>
                <dd><b>MM</b> in Minuten zwischen 1 und 59, <b>h</b> in Stunden zwischen 2 und 23</dd>
</br>
        <dt><a href="#DOIF_Wochentagsteuerung">Wochentagsteuerung</a> <code><b>[</b>&lt;time&gt;<b>|012345678]</b></code>, <code><b>[</b>&lt;begin&gt;<b>-</b>&lt;end&gt;<b>]</b><b>|012345678]</b></code></dt>
                <dd>Pipe, gefolgt von ein o. mehreren Ziffern. Bedeutung: 0 bis 6 f&uuml;r So. bis Sa., 7 f&uuml;r $we, Wochenende oder Feiertag, 8 f&uuml;r !$we, Werktags.</dd>
</br>
        <dt><a href="#DOIF_Zeitsteuerung_mit_Zeitberechnung">berechnete Zeitangaben</a> <code><b>[(</b>&lt;Berechnung, gibt Zeit in Sekunden zur&uuml;ck, im Sinne von <a target=blank href="http://perldoc.perl.org/functions/time.html">time</a>&gt;<b>)]</b></code></dt>
                <dd>Berechnungen sind mit runden Klammern einzuschliessen. Perlfunktionen, die HH:MM zur&uuml;ckgeben sind mit geschweiften Klammern einzuschliessen.</dd>
</br>
        <dt><a href="#DOIF_Zeitintervalle_Readings_und_Stati_ohne_Trigger">Trigger verhindern</a> <code><b>[?</b>&lt;devicename&gt;<b>]</b></code>, <code><b>[?</b>&lt;devicename&gt;<b>:</b>&lt;readingname&gt;<b>]</b></code>, <code><b>[?</b>&lt;devicename&gt;<b>:&amp;</b>&lt;internalname&gt;<b>]</b></code>, <code><b>[?</b>&lt;time specification&gt;<b>]</b></code></dt>
                <dd>Werden Stati, Readings, Internals und Zeitangaben in der Bedingung mit einem Fragezeichen eingeleitet, triggern sie nicht.</dd>
</br>
        <dt>$device, $event, $events</dt>
                <dd>Perl-Variablen mit der Bedeutung der Schl&uuml;sselworte $DEVICE, $EVENT, $EVENTS</dd>
</br>
        <dt>$cmd</dt>
                <dd>Perl-Variablen mit der Bedeutung [$SELF:cmd]</dd>
</br>
        <dt>&lt;Perl-Zeitvariablen&gt;</dt>
                <dd>Variablen f&uuml;r Zeit- und Datumsangaben, $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst, $week, $hms, $hm, $md, $ymd</dd>
</dl>
</br>
</ul>
<u>set-Befehl</u>
<ul>
<dl>
        <dt><a href="#DOIF_disable">disable</a> <code><b> set </b>&lt;name&gt;<b> disable</b></code></dt>
                <dd>blockiert die Befehlsausf&uuml;hrung</dd>
</br>
        <dt><a href="#DOIF_initialize">initialize</a> <code><b> set </b>&lt;name&gt;<b> initialize</b></code></dt>
                <dd>initialisiert das DOIF und aktiviert die Befehlsausf&uuml;hrung</dd>
</br>
        <dt><a href="#DOIF_initialize">enable</a> <code><b> set </b>&lt;name&gt;<b> enable</b></code></dt>
                <dd>aktiviert die Befehlsausf&uuml;hrung, im Gegensatz zur obigen Initialisierung bleibt der letzte Zustand des Moduls erhalten</dd>
</br>
        <dt><a href="#DOIF_cmd">cmd_&lt;nr&gt</a> <code><b> set </b>&lt;name&gt;<b> cmd_&lt;nr&gt;</b></code></dt>
                <dd>führt ohne Auswertung der Bedingung den Befehlszweig mit der Nummer &lt;nr&gt; aus</dd>
</dl>
</br>
</ul>

<a name="DOIF_Attribute_kurz"></a>
<u>Attribute</u>
<ul>
<dl>
        <dt><a href="#DOIF_wait">Verz&ouml;gerungen</a> <code><b>attr</b> &lt;name&gt; <b>wait </b>&lt;timer_1_1&gt;<b>,</b>&lt;timer_1_2&gt;<b>,...:</b>&lt;timer_2_1&gt;<b>,</b>&lt;timer_2_2&gt;<b>,...:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, ein Doppelpunkt trennt die Timer der Bedingungsweige, ein Komma die Timer der Befehlssequenzen eines Bedingungszweiges.</dd>
</br>
        <dt><a href="#DOIF_timerWithWait">Verz&ouml;gerung von Timern</a> <code><b>attr</b> &lt;name&gt; <b>timerWithWait</b></code></dt>
                <dd>erweitert <code>wait</code> auf Zeitangaben</dd>
</br>
        <dt><a href="#DOIF_do_always">Befehlswiederholung zulassen</a> <code><b>attr</b> &lt;name&gt; <b>do always</b></code></dt>
                <dd>wiederholt den Ausf&uuml;hrungsteil, wenn die selbe Bedingung wiederholt wahr wird.</dd>
</br>
        <dt><a href="#DOIF_do_resetwait">Zur&uuml;cksetzen des Waittimers bei Wiederholung</a> <code><b>attr</b> &lt;name&gt; <b>do resetwait</b></code></dt>
                <dd>setzt den Waittimer zur&uuml;ck, wenn die selbe Bedingung wiederholt wahr wird.</dd>
</br>
        <dt><a href="#DOIF_repeatcmd">Befehle wiederholen</a> <code><b>attr</b> &lt;name&gt; <b>repeatcmd </b>&lt;timer Bedingungszweig 1&gt;<b>:</b>&lt;timer Bedingungszweig 2&gt;<b>:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, nach der Befehle wiederholt werden.</dd>
</br>
        <dt><a href="#DOIF_cmdpause">Pause f&uuml;r Wiederholung</a> <code><b>attr</b> &lt;name&gt; <b>cmdpause </b>&lt;Pause cmd_1&gt;<b>:</b>&lt;Pause cmd_2&gt;<b>:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, blockiert die Befehlsausf&uuml;hrung w&auml;hrend der Pause.</dd>
</br>
        <dt><a href="#DOIF_repeatsame">Begrenzung von Wiederholungen</a> <code><b>attr</b> &lt;name&gt; <b>repeatsame </b>&lt;maximale Anzahl von cmd_1&gt;<b>:</b>&lt;maximale Anzahl von cmd_2&gt;<b>:...</b></code></dt>
                <dd>Anzahl als direkte Angabe oder Berechnung, begrenzt die maximale Anzahl unmittelbar folgender Befehlsausf&uuml;hrungen.</dd>
</br>
        <dt><a href="#DOIF_waitsame">Warten auf Wiederholung</a> <code><b>attr</b> &lt;name&gt; <b>waitsame </b>&lt;Wartezeit cmd_1&gt;<b>:</b>&lt;Wartezeit cmd_2&gt;<b>:...</b></code></dt>
                <dd>Wartezeit in Sekunden als direkte Angabe oder Berechnung, f&uuml;r ein unmittelbar wiederholtes Zutreffen einer Bedingung.</dd>
</br>
        <dt><a href="#DOIF_waitdel">L&ouml;schen des Waittimers</a> <code><b>attr</b> &lt;name&gt; <b>waitdel </b>&lt;timer_1_1&gt;<b>,</b>&lt;timer_1_2&gt;<b>,...:</b>&lt;timer_2_1&gt;<b>,</b>&lt;timer_2_2&gt;<b>,...:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, ein laufender Timer wird gel&ouml;scht und die Befehle nicht ausgef&uuml;hrt, falls eine Bedingung vor Ablauf des Timers wiederholt wahr wird.</dd>
</br>
        <dt><a href="#DOIF_checkReadingEvent">Auswertung von Readings auf passende Events beschr&auml;nken</a> <code><b>attr</b> &lt;name&gt; <b>checkReadingEvent </b>&lt;<b>0</b>|<b>ungleich Null</b>&gt;</code></dt>
                <dd>ungleich Null aktiviert, 0 deaktiviert</dd>
</br>
        <dt><a href="#DOIF_selftrigger">Selbsttriggerung</a> <code><b>attr</b> &lt;name&gt; <b>selftrigger </b>&lt;<b>wait</b>|<b>all</b>&gt;</code></dt>
                <dd>lässt die Triggerung des Gerätes durch sich selbst zu. <code>wait</code> zugelassen für verzögerte Befehle, <code>all</code> zugelassen auch für nicht durch wait verzögerte Befehle; es ist nur eine Rekusion möglich</dd>
</br>
        <dt><a href="#DOIF_timerevent">Event beim Setzen eines Timers</a> <code><b>attr</b> &lt;name&gt; <b>timerevent </b>&lt;<b>0</b>|<b>ungleich Null</b>&gt;</code></dt>
                <dd>erzeugt beim Setzen eines Timers ein Event. ungleich Null aktiviert, 0 deaktiviert</dd>
</br>
        <dt><a href="#DOIF_cmdState">Ger&auml;testatus ersetzen</a> <code><b>attr</b> &lt;name&gt; <b>cmdState </b>&lt;Ersatz cmd_1_1&gt;<b>,</b>...<b>,</b>&lt;Ersatz cmd_1&gt;<b>|</b>&lt;Ersatz cmd_2_1&gt;<b>,</b>...<b>,</b>&lt;Ersatz cmd_2&gt;<b>|...</b></code></dt>
                <dd>ersetzt die Standartwerte des Ger&auml;testatus als direkte Angabe oder Berechnung, die Ersatzstati von Befehlssequenzen werden durch Kommata, die von Befehlszweigen durch Pipe Zeichen getrennt.</dd>
</br>
        <dt><a href="#DOIF_state">dynamischer Status </a> <code><b>attr</b> &lt;name&gt; <b>state </b>&lt;dynamischer Inhalt&gt;</code></dt>
                <dd>Zum Erstellen von <code>&lt;dynamischer Inhalt&gt;</code> k&ouml;nnen die f&uuml;r Befehle verf&uuml;gbaren Operanden verwendet werden.</dd>
</br>
        <dt><a href="#DOIF_notexist">Ersatzwert für nicht existierende Readings oder Stati</a> <code><b>attr</b> &lt;name&gt; <b>notexist </b>"&lt;Ersatzwert&gt;"</code></dt>
                <dd></dd>
</br>
        <dt><a href="#DOIF_initialize">Status Initialisierung nach Neustart</a> <code><b>attr</b> &lt;name&gt; <b>intialize </b>&lt;Status nach Neustart&gt;</code></dt>
                <dd></dd>
</br>
        <dt><a href="#DOIF_disable">Ger&auml;t vollst&auml;ndig deaktivieren</a> <code><b>attr</b> &lt;name&gt; <b>disable </b>&lt;<b>0</b>|<b>1</b>&gt;</code></dt>
                <dd>1 deaktiviert das Modul vollst&auml;ndig, 0 aktiviert es.</dd>
</br>
        <dt><a href="#DOIF_checkall">Alle Bedingungen pr&uuml;fen</a> <code><b>attr</b> &lt;name&gt; <b>checkall </b>&lt;<b>event</b>|<b>timer</b>|<b>all</b>&gt;</code></dt>
                <dd><code>event</code> Alle Bedingungen werden geprüft, wenn ein Event-Trigger (Ereignisauslöser) auslöst.<br>
                    <code>timer</code> Alle Bedingungen werden geprüft, wenn ein Timer-Trigger (Zeitauslöser) auslöst.<br>
                    <code>all&nbsp;&nbsp;</code> Alle Bedingungen werden gepr&uuml;ft.<br>
                    Die Befehle nach der ersten wahren Bedingung werden ausgef&uuml;hrt.
                </dd>
</br>
        <dt><a href="#DOIF_addStateEvent">Eindeutige Statuserkennung</a> <code><b>attr</b> &lt;name&gt; <b>addStateEvent </b>&lt;<b>0</b>|<b>ungleich Null</b>&gt;</code></dt>
                <dd>fügt einem Ger&auml;testatus-Event "state:" hinzu. ungleich Null aktiviert, 0 deaktiviert, siehe auch <a href="#addStateEvent">addStateEvent</a></dd>
</br>
        <dt><a href="#DOIF_setList__readingList">Readings, die mit set gesetzt werden k&ouml;nnen</a> <code><b>attr</b> &lt;name&gt; <b>readingList </b>&lt;Reading1&gt;&nbsp;&lt;Reading2&gt; ...</code></dt>
                <dd>fügt zum set-Befehl direkt setzbare, durch Leerzeichen getrennte Readings hinzu. siehe auch <a href="#readingList">readingList</a></dd>
</br>
        <dt><a href="#DOIF_setList__readingList">Readings mit Werteliste und optionaler Widgetangabe</a> <code><b>attr</b> &lt;name&gt; <b>setList </b>&lt;Reading1&gt;<b>:</b>&lang;&lt;Modifier1&gt;<b>,</b>&rang;&lt;Value1&gt;<b>,</b>&lt;Value2&gt;<b>,</b>&lt;...&gt;<b> </b>&lt;Reading2&gt;<b>:</b>&lang;&lt;Modifier2&gt;<b>,</b>&rang;&lt;Value1&gt;<b>,</b>&lt;Value2&gt;<b>,</b>&lt;...&gt; ...</code></dt>
                <dd>fügt einem Reading einen optionalen Widgetmodifier und eine Werteliste (, getrennt) hinzu, siehe auch <a href="#setList">setList</a>, <a href="#widgetOverride">widgetOverride</a>, und <a href="#webCmd">webCmd</a></dd>
</br>
        <dt><a href="#readingFnAttributes">readingFnAttributes</a></dt>
                <dd></dd>
</br>
</dl>
</ul>
<!-- Ende der Kurzreferenz -->
</ul>
=end html_DE
=cut
