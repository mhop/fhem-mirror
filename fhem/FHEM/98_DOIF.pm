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
# You should have received a copy of the GNU General Public License655
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################


package main;
use strict;
use warnings;
use Blocking;
use Color;
use vars qw($FW_CSRF $FW_room);

my $hs;

sub DOIF_cmd ($$$$);
sub DOIF_Notify ($$);

sub DOIF_delTimer($)
{
  my ($hash) = @_;
  RemoveInternalTimer($hash);
  foreach my $key (keys %{$hash->{triggertime}}) {
    RemoveInternalTimer (\$hash->{triggertime}{$key});
  }
  foreach my $key (keys %{$hash->{ptimer}}) {
    RemoveInternalTimer (\$hash->{ptimer}{$key});
  }
}
sub DOIF_killBlocking($)
{
  my ($hash) = @_;
  foreach my $key (keys %{$hash->{var}{blockingcalls}}) {
    BlockingKill($hash->{var}{blockingcalls}{$key}) if(defined($hash->{var}{blockingcalls}{$key}));
  }
}

sub DOIF_delAll($)
{
  my ($hash) = @_;
  DOIF_killBlocking($hash);
  
  delete ($hash->{helper});
  delete ($hash->{condition});
  delete ($hash->{do});
  #delete ($hash->{devices});
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
  delete ($hash->{ptimer});
  delete ($hash->{interval});
  delete ($hash->{intervaltimer});
  delete ($hash->{intervalfunc});
  delete ($hash->{perlblock});
  delete ($hash->{var});
  delete ($hash->{accu});
  #delete ($hash->{collect});
  delete ($hash->{Regex});
  delete ($hash->{defs});

  #foreach my $key (keys %{$hash->{Regex}}) {
  #  delete $hash->{Regex}{$key} if ($key !~ "STATE|DOIF_Readings|uiTable");
  #}
  
  my $readings = ($hash->{MODEL} eq "Perl") ? "^(Device|error|warning|cmd|e_|timer_|wait_|matched_|last_cmd|mode|block_)":"^(Device|state|error|warning|cmd|e_|timer_|wait_|matched_|last_cmd|mode|block_)";
  foreach my $key (keys %{$defs{$hash->{NAME}}{READINGS}}) {
    delete $defs{$hash->{NAME}}{READINGS}{$key} if ($key =~ $readings);
  }
}

sub DOIF_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "DOIF_Define";
  $hash->{SetFn}   = "DOIF_Set";
  $hash->{GetFn}   = "DOIF_Get";
  $hash->{UndefFn}  = "DOIF_Undef";
  $hash->{ShutdownFn}  = "DOIF_Shutdown";
  $hash->{AttrFn}   = "DOIF_Attr";
  $hash->{NotifyFn} = "DOIF_Notify";
  $hash->{FW_deviceOverview} = 1;
  $hash->{FW_addDetailToSummary} = 1;
  $hash->{FW_detailFn} = "DOIF_detailFn";
  $hash->{FW_summaryFn}  = "DOIF_summaryFn";
  #$hash->{FW_atPageEnd} = 1;

  $data{FWEXT}{DOIF}{SCRIPT} = "doif.js";

  $hash->{AttrList} = "disable:0,1 loglevel:0,1,2,3,4,5,6 wait:textField-long do:always,resetwait cmdState startup:textField-long state:textField-long initialize repeatsame repeatcmd waitsame waitdel cmdpause timerWithWait:1,0 notexist selftrigger:wait,all timerevent:1,0 checkReadingEvent:0,1 addStateEvent:1,0 checkall:event,timer,all weekdays setList:textField-long readingList DOIF_Readings:textField-long event_Readings:textField-long uiState:textField-long uiTable:textField-long ".$readingFnAttributes;
}

# uiTable
sub DOIF_reloadFW {
  map { FW_directNotify("#FHEMWEB:$_", "location.reload()", "") } devspec2array("TYPE=FHEMWEB");
}

sub DOIF_hsv
{
  my ($cur,$min,$max,$min_s,$max_s,$s,$v)=@_;
  
  $s=100 if (!defined ($s));
  $v=100 if (!defined ($v));
  
  my $m=($max_s-$min_s)/($max-$min);
  my $n=$min_s-$min*$m;
  if ($cur>$max) {
   $cur=$max;
  } elsif ($cur<$min) {
    $cur=$min;
  }
    
  my $h=$cur*$m+$n;
  $h /=360;
  $s /=100;
  $v /=100;  
  
  my($r,$g,$b)=Color::hsv2rgb ($h,$s,$v);
  $r *= 255;
  $g *= 255;
  $b *= 255;
  return sprintf("#%02X%02X%02X", $r+0.5, $g+0.5, $b+0.5);
}


sub DOIF_rgb {
  my ($sc,$ec,$pct,$max,$cur) = @_;
  $cur = ($cur =~ /(-?\d+(\.\d+)?)/ ? $1 : 0);
  $pct = ($cur-$pct)/($max-$pct) if (@_ == 5);
  my $prefix = "";
  $prefix = "#" if ("$sc $ec"=~"#");
  $sc =~ s/^#//;
  $ec =~ s/^#//;
  $pct = $pct > 1 ? 1 : $pct;
  $pct = $pct < 0 ? 0 : $pct;
  $sc =~/([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})/;
  my @sc = (hex($1),hex($2),hex($3));
  $ec =~/([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})/;
  my @ec = (hex($1),hex($2),hex($3));
  my @rgb;
  for (0..2) {
    $rgb[$_] = sprintf("%02X", int(($ec[$_] - $sc[$_])*$pct + $sc[$_] + .5));
  }
  return $prefix.join("",@rgb);
} 

#sub DOIF_Icon {
#  my ($dev, $reading, $icon, $cmd, $type) = @_;
#  my $val = ReadingsVal($dev,$reading,"???");
#  $type= $reading eq 'state' ? 'set' : 'setreading' if (!defined $type);
#  my $ret = FW_makeImage($icon,$cmd,"icon");
#  $ret = FW_pH "cmd.$dev=$type $dev $reading $cmd", $ret, 0, "webCmd", 1;
#  return "$ret";
#}

sub DOIF_UpdateCell
{
  my ($hash,$doifId,$dev,$reading) =@_;
  my $pn = $hash->{NAME};
  my $retVal="";
  my $retStyle="";
  my $reg="";
  my $VALUE="";
  if ($doifId =~ /.*_(.*)_c_(.*)_(.*)_(.*)_(.*)$/) { 
    my $command=$hash->{$1}{table}{$2}{$3}{$4}{$5};
    eval ($command);
    if ($@) {
        my $err="$pn: eval: $command error: $@" ;
        Log3 $pn,3,$err; 
    }
  }
}

sub DOIF_Widget
{
  my ($hash,$reg,$doifId,$value,$style,$widget,$command,$dev,$reading)=@_;
  if ($reg) {
    return DOIF_Widget_Register($doifId,$value,$style,$widget,$dev,$reading,$command);
  } else {
    DOIF_Widget_Update($hash->{NAME},$doifId,$value,$style,$widget,$command,$dev,$reading);
  }
}

sub DOIF_Widget_Update
{
  my ($pn,$doifId,$value,$style,$widget,$command,$dev,$reading)=@_;
  if (defined $widget and $widget ne "") {
      map { 
         FW_directNotify("#FHEMWEB:$_", "doifUpdateCell('$pn','informid','$dev-$reading','$value')","");
      } devspec2array("TYPE=FHEMWEB");
  } else {
      map { 
         FW_directNotify("#FHEMWEB:$_", "doifUpdateCell('$pn','doifId','$doifId','$value','display:inline-table;$style')","");
      } devspec2array("TYPE=FHEMWEB") if ($value ne "");
  }
}

sub DOIF_Widget_Register
{
  my ($doifId,$value,$style,$widget,$dev,$reading,$command)=@_;
  my $type;
  my $cmd='';
  if (defined $widget and $widget ne "") {
    if (defined $command and $command ne "") {
      if ($command =~ /^([^ ]*) *(.*)/) {
        $type = !defined $1 ? '': $1;
        $cmd = !defined $2 ? '': $2;
      } else {
        $type=$command;
      } 
    } else {
      $type= $reading eq 'state' ? 'set' : 'setreading';
    }
    $cmd = $cmd eq '' ? $reading : $cmd;
    return "<div class='fhemWidget' cmd='$cmd' reading='$reading' dev='$dev' arg='$widget' current='$value' type='$type'></div>";
  } else {
    return "<div class='dval' doifId='$doifId' style='display:inline-table;$style'>$value</div>";
  }
}

sub DOIF_RegisterCell
{
  my ($hash,$table,$func,$r,$c,$cc,$cr) =@_;
  my $event;
  my $err;
  my $dev="";
  my $reading="";
  my $value="";
  my $expr;
  my $style;
  my $widget;
  my $command;
  my $cell;
  my $widsty=0;
  my $trigger=0;
  
  if ($func=~ /^\s*(STY[ \t]*\(|WID[ \t]*\()/) {
    my ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($func,'[\(\)]');
      if ($err) {
        return $err;
      } elsif ($currentBlock ne "") {
      $cell=$currentBlock;
    } 
  } else {
    $cell=$func;
  }
  
  my $doifId="$hash->{NAME}_".$table."_c_".$r."_".$c."_".$cc."_".$cr;
  if ($func=~ /^\s*STY[ \t]*\(/) {
    $widsty=1;
    ($expr,$style) = SplitDoIf(',',$cell);
  } elsif ($func=~ /^\s*WID[ \t]*\(/) {
    $widsty=2;
    ($expr,$widget,$command) = SplitDoIf(',',$cell);
  } else {
    $expr=$cell;
  }
  ($expr,$err,$event)=ReplaceAllReadingsDoIf($hash,$expr,($table eq "uiTable" ? -5:-6),0,$doifId);
  if ($err) {
    $err="'error $err: in expression: $expr'";
    return $err;
  } else {
    $lastWarningMsg="";
    my ($exp,$sty,$wid,$com)=eval ($hash->{$table}{package}.$expr);
    return "'error $@ in expression: $expr'" if ($@);
    if ($lastWarningMsg) {
      $lastWarningMsg =~ s/^(.*) at \(eval.*$/$1/;
      Log3 ($hash->{NAME},3,"$hash->{NAME}:Warning in DOIF_RegisterCell:$hash->{$table}{package}.$expr");
      $lastWarningMsg="";
    }
    if (defined $sty and $sty eq "" and defined $wid and $wid ne "") {
       if ($event) {
         $dev=$hash->{$table}{dev} if (defined $hash->{$table}{dev});
         $reading=$hash->{$table}{reading} if (defined $hash->{$table}{reading});
       } else {
         return "'no trigger reading in widget: $expr'";
       }
       $reading="state" if ($reading eq '&STATE');
       return "$hash->{$table}{package}::DOIF_Widget(".'$hash,$reg,'."'$doifId',$expr,".(defined $com ? "":"'',")."'$dev','$reading')";
    } elsif (defined $sty) {
      $widsty=3;
    }
  }
  $trigger=$event; 
  if (defined $widget and $widget ne "") {
    if ($event) {
      $dev=$hash->{$table}{dev} if (defined $hash->{$table}{dev});
      $reading=$hash->{$table}{reading} if (defined $hash->{$table}{reading});
    } else {
      return "'no trigger reading in widget: $expr'";
    }
    ($widget,$err,$event)=ReplaceAllReadingsDoIf($hash,$widget,($table eq "uiTable" ? -5:-6),0,$doifId);
    $trigger=$event if ($event);
    if ($err) {
      $err="'error $err: in widget: $widget'";
      return $err;
    } else {
      $lastWarningMsg="";
      eval ($widget);
      return "'error $@ in widget: $widget'" if ($@);
      if ($lastWarningMsg) {
        Log3 ($hash->{NAME},3,"$hash->{NAME}:Warning in DOIF_RegisterCell:$widget");
        $lastWarningMsg="";
      }
    }
  } else {
    $widget="";
  }
  if ($style) {
    ($style,$err,$event)=ReplaceAllReadingsDoIf($hash,$style,($table eq "uiTable" ? -5:-6),0,$doifId);
    $trigger=$event if ($event);
    if ($err) {
      $err="'error $err: in style: $style'";
      return $err;
    } else {
      $lastWarningMsg="";
      eval $style;
      return "'error $@ in style: $style'" if ($@);
      if ($lastWarningMsg) {
        Log3 ($hash->{NAME},3,"$hash->{NAME}:Warning in DOIF_RegisterCell:$style");
        $lastWarningMsg="";
      }
    }
  } else {
    $style='""';
  }
  
  if ($widsty==2) {
      $reading="state" if ($reading eq '&STATE');
      return "$hash->{$table}{package}::DOIF_Widget(".'$hash,$reg,'."'$doifId',$expr,$style,$widget,".(defined $command ? "$command":"''").",'$dev','$reading')";
  } elsif ($widsty==3) {
      return "$hash->{$table}{package}::DOIF_Widget(".'$hash,$reg,'."'$doifId',$expr)";
  } elsif (($widsty==1) or $trigger) {
      return "$hash->{$table}{package}::DOIF_Widget(".'$hash,$reg,'."'$doifId',$expr,$style)";
  } else {
      return ("$hash->{$table}{package}".$expr);
  }
  return ""
}

sub DOIF_DEF_TPL {
  my ($hash,$table,$tail) = @_;
  my $beginning;
  my $currentBlock;
  my $output="";
  my $err;
  
  while ($tail ne "") {
    if ($tail =~ /(?:^|\n)\s*DEF\s/g) {
      my $prefix=substr($tail,0,pos($tail));
      my $begin=substr($tail,0,pos($tail)-4);
      $tail=substr($tail,pos($tail)-4);
      if ($tail =~ /^DEF\s*(TPL_[^ ^\t^\(]*)[^\(]*\(/) {
        ($beginning,$currentBlock,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
        if ($err) {
            return ("DEF TPL: $err",$currentBlock);
        } elsif ($currentBlock ne "") {
          $hash->{$table}{tpl}{$1}=$currentBlock;
          $output.=$begin;
        }
      }  else {
        $tail=substr($tail,4);
        $output.=$prefix;
      }
    } else {
      $output.=$tail;
      $tail="";
    }
  }
  return ("",$output);
}

sub DOIF_DEF_TPL_OLD
{
  my ($hash,$table,$tail) =@_;
  my ($beginning,$currentBlock,$err);
  while($tail =~ /(?:^|\n)\s*DEF\s*(TPL_[^ ^\t^\(]*)[^\(]*\(/g) {
    ($beginning,$currentBlock,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
    if ($err) {
        return ("DEF TPL: $err",$currentBlock);
    } elsif ($currentBlock ne "") {
      $hash->{$table}{tpl}{$1}=$currentBlock;
    }
  }
  return ("",$tail);
}

sub parse_tpl
{
  my ($hash,$wcmd,$table) = @_;
  my $d=$hash->{NAME};
  my $err="";
  $hash->{$table}{header}="";

  while ($wcmd =~ /\s*IMPORT\s*(.*)(\n|$)/g) {
    $err=import_tpl($hash,$1,$table);
    return ($err,"") if ($err);
  }

  $wcmd =~ s/(##.*\n)|(##.*$)/\n/g;

  $wcmd =~ s/\s*IMPORT.*(\n|$)//g;

  $wcmd =~ s/\$TPL\{/\$hash->\{$table\}\{template\}\{/g;
  $wcmd =~ s/\$ATTRIBUTESFIRST/\$hash->{$table}{attributesfirst}/;
  
  $wcmd =~ s/\$TC\{/\$hash->{$table}{tc}\{/g;
  $wcmd =~ s/\$hash->\{$table\}\{tc\}\{([\d,.]*)?\}.*(\".*\")/for my \$i ($1) \{\$hash->\{$table\}\{tc\}\{\$i\} = $2\}/g;
  
  $wcmd =~ s/\$TR\{/\$hash->{$table}{tr}\{/g;
  $wcmd =~ s/\$hash->\{$table\}\{tr\}\{([\d,.]*)?\}.*(\".*\")/for my \$i ($1) \{\$hash->\{$table\}\{tr\}\{\$i\} = $2\}/g;
  
  $wcmd =~ s/\$TD\{(.*)?\}\{(.*)?\}.*(\".*\")/for my \$rowi ($1) \{for my \$coli ($2) \{\$hash->\{$table\}\{td\}\{\$rowi\}\{\$coli\} = $3\}\}/g;
  $wcmd =~ s/\$TABLE/\$hash->{$table}{tablestyle}/;
  $wcmd =~ s/<\s*\n/\."<\/tbody><\/table>\$hash->{$table}{header}"\n/g;
  $wcmd =~ s/\$VAR/\$hash->{var}/g;
  $wcmd =~ s/\$_(\w+)/\$hash->\{var\}\{$1\}/g;
  $wcmd =~ s/\$SELF/$d/g;
  $wcmd =~ s/FUNC_/::DOIF_FUNC_$d\_/g;
  $wcmd =~ s/PUP[ \t]*\(/::DOIF_tablePopUp(\"$d\",/g;
  $wcmd =~ s/\$SHOWNOSTATE/\$hash->{$table}{shownostate}/;
  $wcmd =~ s/\$SHOWNODEVICELINK/\$hash->{$table}{shownodevicelink}/;
  $wcmd =~ s/\$SHOWNODEVICELINE/\$hash->{$table}{shownodeviceline}/;
  $wcmd =~ s/\$SHOWNOUITABLE/\$hash->{$table}{shownouitable}/;
  $wcmd =~ s/\$ANIMATE/\$hash->{card}{animate}/;
  $hash->{$table}{package} = "" if (!defined ($hash->{$table}{package}));
  if ($wcmd=~ /^\s*\{/) { # perl block
    my ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($wcmd,'[\{\}]');
    if ($err) {
        return ("error in $table: $err","");
    } elsif ($currentBlock ne "") {
      $currentBlock ="no warnings 'redefine';".$currentBlock;
      if ($currentBlock =~ /\s*package\s*(\w*)/) {
        $hash->{$table}{package}="package $1;";
      }
      eval ($currentBlock);
      if ($@) {
        $err="$d: error: $@ in $table: $currentBlock";
        return ($err,"");
      }
      $wcmd=$tailBlock;
    }
  }
  
  ($err,$wcmd)=DOIF_FOR($hash,$table,$wcmd);
  if ($err) {
    return($err,"");
  }
   
  $wcmd =~ s/^\s*//;
  $wcmd =~ s/[ \t]*\n/\n/g;
  $wcmd =~ s/,[ \t]*[\n]+/,/g;
  $wcmd =~ s/\.[ \t]*[\n]+/\./g;
  $wcmd =~ s/\|[ \t]*[\n]+/\|/g;
  $wcmd =~ s/>[ \t]*[\n]+/>/g;
   
  my $tail=$wcmd;
  my $beginning;
  my $currentBlock;

  ($err,$tail)=DOIF_DEF_TPL($hash,$table,$wcmd);
  return ("$err: $tail") if ($err);
  return ("",$tail);
}

sub import_tpl
{
  my ($hash,$file,$table) = @_;
  my $fh;
  my $err;
  if(!open($fh, $file)) {
    return "Can't open $file: $!";
  }
  my @tpl=<$fh>;
  close $fh;
  my $wcmd=join("",@tpl);
  ($err,$wcmd)=parse_tpl($hash,$wcmd,$table);
  return $err if ($err);
  return "";
}

sub DOIF_FOR
{
  my ($hash,$table,$wcmd,$count)=@_;
  my $err="";
  my $tail=$wcmd;
  my $beginning;
  my $currentBlock;
  my $output="";
  while ($tail ne "") {
    if ($tail =~ /FOR/g) {
      my $prefix=substr($tail,0,pos($tail));
      my $begin=substr($tail,0,pos($tail)-3);
      $tail=substr($tail,pos($tail)-3);
      if ($tail =~ /^FOR\s*\(/) {
        ($beginning,$currentBlock,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
        if ($err) {
          return ("FOR: $err $currentBlock","");
        } elsif ($currentBlock ne "") {
          my ($array,$command) = SplitDoIf(',',$currentBlock);
          my $cmd=$command;
          if ($cmd =~ /^\s*\(/) {
            my ($begin,$curr,$error,$end)=GetBlockDoIf($command,'[\(\)]');
            if ($error) {
              return ("FOR: $error $curr","");
            } else {
              $command=$curr;
            }
          }
          my $commandoutput="";
          if (!defined $count) {
            $count=0;
          }
          $count++;
          my $i=0;
          for (eval($array)) {
            my $temp=$command;
            my $item=$_;
            if (ref($item) eq "ARRAY"){
              my $j=1;
              for (@{$item}) {
                $temp =~ s/\$_\$$j/$_/g;
                $temp =~ s/\$$count\$$j/$_/g;
                $j++;
              }
            } else {
              $temp =~ s/\$$count/$_/g;
              $temp =~ s/\$_/$_/g;
            }
            $temp =~ s/\$COUNT$count/$i/g;
            if ($temp =~ /FOR\s*\(/) {
              ($err,$temp)=DOIF_FOR($hash,"defs",$temp,$count);
              return($temp,$err) if ($err); 
            }
            $commandoutput.=$temp."\n";
            $i++;
          }
          $output.=($begin.$commandoutput);
        }
      } else {
        $tail=substr($tail,3);
        $output.=$prefix;
      }
    } else {
      $output.=$tail;
      $tail="";
    }
    $count=undef;
  }
  return ("",$output);
}

sub DOIF_TPL {
  my ($hash,$table,$tail) = @_;
  my $beginning;
  my $currentBlock;
  my $output="";
  my $err;
  
  while ($tail ne "") {
    if ($tail =~ /(\w*)\s*TPL_/g) {
      next if $1 eq "DEF";
      my $prefix=substr($tail,0,pos($tail));
      my $begin=substr($tail,0,pos($tail)-4);
      $tail=substr($tail,pos($tail)-4);
      if ($tail =~ /^(TPL_\w*)\s*\(/) {
        my $template=$1;
        if (defined $hash->{$table}{tpl}{$template}) {
          my $templ=$hash->{$table}{tpl}{$template};
          ($beginning,$currentBlock,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
          if ($err) {
            return "error: $err";
          } elsif ($currentBlock ne "") {
            my @param = SplitDoIf(',',$currentBlock);
            for (my $j=@param;$j>0;$j--) {
              my $p=$j;
              $templ =~ s/\$$p/$param[$j-1]/g;
            }
          }
          $output.=($begin.$templ);
        }  else {
          return ("no Template $template defined",$tail);
        }
      } else {
        $tail=substr($tail,4);
        $output.=$prefix;
      }
    } else {
      $output.=$tail;
      $tail="";
    }
  }
  return ("",$output);
}


sub DOIF_uiTable_def 
{
  my ($hash,$wcmd,$table) = @_;
  return undef if (!$wcmd); 
  my $err="";

  delete ($hash->{Regex}{$table});
  delete ($hash->{$table});

  ($err,$wcmd)=parse_tpl($hash,$wcmd,$table);
  return $err if ($err);
  my $output="";
  my $tail=$wcmd;

  ($err,$output)=DOIF_TPL($hash,$table,$tail);
  return ("$err: $output") if ($err);

  $wcmd=$output;

  my @rcmd = split(/\n/,$wcmd);
  my $ii=0;

  for (my $i=0; $i<@rcmd; $i++) {
    next if ($rcmd[$i] =~ /^\s*$/);
    my @ccmd = SplitDoIf('|',$rcmd[$i]);
    for (my $k=0;$k<@ccmd;$k++) {
      my @cccmd = SplitDoIf(',',$ccmd[$k]);
      for (my $l=0;$l<@cccmd;$l++) {
        my @crcmd = SplitDoIf('.',$cccmd[$l]);
        for (my $m=0;$m<@crcmd;$m++) {
          $hash->{$table}{table}{$ii}{$k}{$l}{$m}= DOIF_RegisterCell($hash,$table,$crcmd[$m],$ii,$k,$l,$m);
        }
      }
    }
    $ii++;
  }
  return undef;
  ##$hash->{$table}{tabledef}=DOIF_RegisterEvalAll($hash);
}

sub DOIF_RegisterEvalAll
{
  my ($hash,$d,$table) = @_;
  my $ret = "";
  my $reg=1;
  return undef if (!defined $hash->{$table}{table});
  if ($table eq "uiTable") {
    $ret.= "\n<table uitabid='DOIF-$d' class=' block wide ".$table."doif doif-$d ' style='".($hash->{$table}{tablestyle} ? $hash->{$table}{tablestyle} : "")."'";
    $ret.=" doifnostate='".($hash->{$table}{shownostate} ? $hash->{$table}{shownostate} : "")."'";
    $ret.=" doifnodevline='".($hash->{$table}{shownodeviceline} ? $hash->{$table}{shownodeviceline} : "")."'";
    $ret.=" doifattrfirst='".($hash->{$table}{attributesfirst} ? $hash->{$table}{attributesfirst} : "")."'";
    $ret.= ">";
    $hash->{$table}{header}= "\n<table uitabid='DOIF-$d' class=' block wide ".$table."doif doif-$d ' style='border-top:none;".($hash->{$table}{tablestyle} ? $hash->{$table}{tablestyle} : "")."'>";
  } else {
    $ret.= "\n<table uitabid='DOIF-$d' class=' wide ".$table."doif doif-$d ' style='border:none;".($hash->{$table}{tablestyle} ? $hash->{$table}{tablestyle} : "")."'";
    $ret.=" doifattrfirst='".($hash->{$table}{attributesfirst} ? $hash->{$table}{attributesfirst} : "")."'";
    $ret.= ">";
    $hash->{$table}{header}= "\n<table uitabid='DOIF-$d' class=' wide ".$table."doif doif-$d ' style='border-top:none;".($hash->{$table}{tablestyle} ? $hash->{$table}{tablestyle} : "")."'>";
  }
  my $class="";
  my $lasttr =scalar keys %{$hash->{$table}{table}};
  for (my $i=0;$i < $lasttr;$i++){
    if ($table eq "uiTable") {
      $class = ($i&1)?"class='odd'":"class='even'";
    }
    $ret .="<tr ";
    $ret .=((defined $hash->{$table}{tr}{$i}) ? $hash->{$table}{tr}{$i}:"");
    $ret .=" ".(($i&1) ? $hash->{$table}{tr}{odd}:"") if (defined $hash->{$table}{tr}{odd});
    $ret .=" ".((!($i&1)) ? $hash->{$table}{tr}{even}:"") if (defined $hash->{$table}{tr}{even});
    $ret .=" ".(($i==$lasttr-1) ? $hash->{$table}{tr}{last}:"") if (defined $hash->{$table}{tr}{last});
    $ret .=" $class >";
    my $lastc =scalar keys %{$hash->{$table}{table}{$i}};
    for (my $k=0;$k < $lastc;$k++){
      $ret .="<td ";
      $ret .=((defined $hash->{$table}{td}{$i}{$k}) ? $hash->{$table}{td}{$i}{$k}:"");
      $ret .=" ".((defined $hash->{$table}{tc}{$k} )? $hash->{$table}{tc}{$k}:"");
      $ret .=" ".(($k&1)?$hash->{$table}{tc}{odd}:"") if (defined $hash->{$table}{tc}{odd});
      $ret .=" ".((!($k&1))?$hash->{$table}{tc}{even}:"") if (defined $hash->{$table}{tc}{even});
      $ret .=" ".(($k==$lastc-1)?$hash->{$table}{tc}{last}:"") if (defined $hash->{$table}{tc}{last});
      $ret .=">";
      my $lastcc =scalar keys %{$hash->{$table}{table}{$i}{$k}};
      for (my $l=0;$l < $lastcc;$l++){
      for (my $m=0;$m < scalar keys %{$hash->{$table}{table}{$i}{$k}{$l}};$m++) {
          if (defined $hash->{$table}{table}{$i}{$k}{$l}{$m}){
            $lastWarningMsg="";
            my $value= eval($hash->{$table}{table}{$i}{$k}{$l}{$m});
            if ($lastWarningMsg) {
              Log3 ($hash->{NAME},3,"$hash->{NAME}:Warning in DOIF_RegisterEvalAll:$hash->{$table}{table}{$i}{$k}{$l}{$m}");
              $lastWarningMsg="";
            }
            if (defined ($value)) {
              if (defined $defs{$value} and (!defined $hash->{$table}{shownodevicelink} or !$hash->{$table}{shownodevicelink})) {
                $ret.="<a href='$FW_ME?detail=$value$FW_CSRF'>$value</a>";
              } else {
                $ret.=$value;
              }
            }
          }
        }
        $ret.="<br>" if ($l+1 != $lastcc);
      }
      $ret.="</td>";
    }
    $ret .= "</tr>";
  }
  $ret .= "</table>\n"; # if ($table eq "uiTable");
  
  #$hash->{$table}{deftable}=$ret;
  return $ret;
}

sub DOIF_tablePopUp {
  my ($pn,$d,$icon,$table) = @_;
  $table = $table ? $table : "uiTable";
  my ($ic,$itext,$iclass)=split(",",$icon);
  if ($defs{$d} && AttrVal($d,$table,"")) {
    my $ret = "<a href=\"#\" onclick=\"doifTablePopUp('$defs{$d}','$d','$pn','$table')\">".FW_makeImage($ic,$itext,$iclass)."</a>";
  } else {
    return "no device $d or attribut $table";
  }
}
sub DOIF_summaryFn ($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};
  my $ret = "";
  return undef if($attr{$d} && $attr{$d}{disable});
  $ret=DOIF_RegisterEvalAll($hash,$d,"uiState");
  return $ret;
}

sub DOIF_detailFn ($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};
  my $ret = "";
  return undef if($attr{$d} && $attr{$d}{disable});
  return undef if (defined $hash->{"uiTable"}{shownouitable} and $FW_room =~ /$hash->{"uiTable"}{shownouitable}/);
  $ret=DOIF_RegisterEvalAll($hash,$d,"uiTable");
  return $ret;
}

sub GetBlockDoIf ($$)
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

sub GetCommandDoIf ($$)
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
  return "" if (!defined($value) or $value eq "");
  my $err="";
  my $pn=$hash->{NAME};
   $value =~ s/\$SELF/$pn/g;
  ($value,$err)=ReplaceAllReadingsDoIf($hash,$value,-1,1);
  if ($err) {
    my $error="$pn: error in $attr: $err";
    Log3 $pn,4 , $error;
    readingsSingleUpdate ($hash, "error", $error,1);
    $value=0;
  } else {
     my $ret = eval $value;
     if ($@) {
       my $error="$pn: error in $attr: $value";
       Log3 $pn,4 , $error;
       readingsSingleUpdate ($hash, "error", $error,1);
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

sub SplitDoIf($$)
{
  my ($separator,$tailBlock)=@_;
  my @commands;
  my $cmd;
  my $err;
  if (defined $tailBlock) {
    while ($tailBlock ne "") {
      ($cmd,$tailBlock,$err)=GetCommandDoIf($separator,$tailBlock);
      push(@commands,$cmd) if (defined $cmd);
    }
  }
  return(@commands);
}

sub EventCheckDoif($$$$)
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

sub AggrIntDoIf
{
  my ($hash,$modeType,$device,$reading,$cond,$default)=@_;
  my $num=0;
  my $value="";
  my $sum=0;
  my $average;
  my $extrem;
  my $name;
  my $devname;
  my $err;
  my ($median, @median_values);
  my $ret;
  my $result;
  my @devices;
  my $group;
  my $room;
  my $STATE;
  my $TYPE;
  my $warning=0;
  my $mode=substr($modeType,0,1);
  my $type;
  my $format;
  my $place;
  my $number;
  my $readingRegex;

  if ($modeType =~ /.(sum|average|max|min|median)?[:]?(?:(a|d)?(\d)?)?/) {
    $type = (defined $1)? $1 : "";
    $format= (defined $2)? $2 : "";
    $place= $3;
  }
  
  if (defined $default) {
    if ($default =~ /^"(.*)"$/) {
      $default = $1;
    } else {
      $default=EvalValueDoIf($hash,"default",$default);
    }
  }
  
  $reading = "" if (!defined $reading);
  
  if ($reading ne "") {
    if ($reading =~ /^"(.*)"$/) {
      $readingRegex = $1;
    }
  }

  foreach my $name (($device eq "") ? keys %defs:grep {/$device/} keys %defs) {
    next if($attr{$name} && $attr{$name}{ignore});
    foreach my $reading ((defined $readingRegex) ? grep {/$readingRegex/} keys %{$defs{$name}{READINGS}} : $reading) {
      $value="";
      $number="";
      if ($reading ne "") {
        if (defined $defs{$name}{READINGS}{$reading}) {
          $value=$defs{$name}{READINGS}{$reading}{VAL};
          $number = ($value =~ /(-?\d+(\.\d+)?)/ ? $1 : 0);
        } else {
          next;
        }
      }
      if ($cond) {
        if ($cond =~ /^"(.*)"$/) {
           if (defined $defs{$name}{READINGS}{$reading}) {
             $ret=($value =~ /$1/); 
           }
        } else {
          $_=$value;
          $STATE=Value($name);
          $TYPE=$defs{$name}{TYPE};
          $group=AttrVal($name,"group","");
          $room=AttrVal($name,"room","");
          $lastWarningMsg="";
          $ret = eval $cond;
          if ($@) {
            $@ =~ s/^(.*) at \(eval.*\)(.*)$/$1,$2/;
            if (defined $hash) {
               Log3 ($hash->{NAME},3 , "$hash->{NAME}: aggregate function: error in condition: $cond, $@");
            }
            return("error in aggregate function: ".$@);
          }
          if ($lastWarningMsg) {
            $warning=1;
            $lastWarningMsg =~ s/^(.*) at \(eval.*$/$1/;
            Log3 ($hash->{NAME},3 , "$hash->{NAME}: aggregate function: warning in condition: $cond, Device: $name");
            readingsSingleUpdate ($hash, "warning_aggr", "condition: $cond , device: $name, $lastWarningMsg",1);
          } 
          $lastWarningMsg="";
        }
      } else {
        $ret=1;
      }
      if ($format eq "a") {
        $devname=AttrVal($name,"alias",$name);
      } else {
        $devname=$name;
      }
      if ($ret) {
        if ($type eq ""){
          $num++;
          push (@devices,$devname);
        } elsif (defined $value) {
          $num++;
          if ($type eq "sum" or $type eq "average") {
            push (@devices,$devname);
            $sum+=$number;
          } elsif ($type eq "max") {
              if (!defined $extrem or $number>$extrem) {
                $extrem=$number;
                @devices=($devname);
              }  
          } elsif ($type eq "min") {
              if (!defined $extrem or $number<$extrem) {
                $extrem=$number;
                @devices=($devname);
              }
          } elsif ($type eq "median") {
            push @median_values, $number;
            push (@devices,$devname);
          }
        }
      }
    }
  }
  
  delete ($defs{$hash->{NAME}}{READINGS}{warning_aggr}) if (defined $hash and $warning==0);
  
  if ($type eq "max" or $type eq "min") {
    $extrem=0 if (!defined $extrem);  
    $result=$extrem;
  } elsif ($type eq "sum") {
    $result= $sum;
  } elsif ($type eq "average") {
    if ($num>0) {
      $result=($sum/$num)
    }
  } elsif ($type eq "median"){

      $result = &{ sub {
            return 0 if $num == 0;

            my @vals = sort{  $a <=> $b } @median_values;

            # odd amount of values, return the middle one
            return $vals[int($num / 2)] if ( $num % 2);

            # even amount of values, return the median
             return  ( $vals[int($num / 2) - 1] + $vals[int($num / 2)] ) / 2;
        }
      };

  } else {
    $result=$num;
  }
  if ($mode eq "#") {
    if (defined $result and $format eq "d") {
      $result = ($result =~ /(-?\d+(\.\d+)?)/ ? $1 : 0);
      $result = round ($result,$place) if (defined $place);
    } 
    if ($num==0 and defined $default) {
      return ($default);
    } else {    
      return ($result);
    }
  } elsif ($mode eq "@") {
    if ($num==0 and defined $default) {
      @devices =($default);
    }
    return (sort @devices);
  }
  return 0;
}

sub AggrDoIf
{
  my ($modeType,$device,$reading,$cond,$default)=@_;
  return (AggrIntDoIf(undef,$modeType,$device,$reading,$cond,$default));
}

sub AggregateDoIf
{
  my ($hash,$modeType,$device,$reading,$cond,$default)=@_;
  my $mode=substr($modeType,0,1);
  my $type=substr($modeType,1);
  my $splittoken=",";
  if ($modeType =~ /.(?:sum|average|max|min|median)?[:]?[^s]*(?:s\((.*)\))?/) {
    $splittoken=$1 if (defined $1);
  } 
  if ($mode eq "#") {
    return (AggrIntDoIf($hash,$modeType,$device,$reading,$cond,$default));
  } elsif ($mode eq "@") {
    return (join ($splittoken,AggrIntDoIf($hash,$modeType,$device,$reading,$cond,$default)));
  }
  return ("");
}

sub EventDoIf
{
  my ($n,$hash,$NotifyExp,$check,$filter,$output,$default)=@_;

  my $dev=$hash->{helper}{triggerDev};
  my $eventa=$hash->{helper}{triggerEvents};
  return 0 if (!defined $dev); 
  if ($check) {
    if ($dev eq "" or $dev ne $n) {
      if (defined $filter) {
        return ($default)
      } else {
        return 0;
      }
    }
  } else {
    if ($dev eq "" or $n and $dev !~ /$n/) {
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
              readingsSingleUpdate ($hash, "error", $@,1);
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

sub InternalDoIf
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
        readingsSingleUpdate ($hash, "error", $@,1);
        return(undef);
      }
    }
  } else {
    $element=$r;
  }
  return($element);
}

sub ReadingSecDoIf($$)
{
  my ($name,$reading)=@_;
  my ($seconds, $microseconds) = gettimeofday();
  return ($seconds - time_str2num(ReadingsTimestamp($name, $reading, "1970-01-01 01:00:00")));
}

sub ReadingValDoIf
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
    return ($default) if (!defined $defs{$name}{READINGS});
    return ($default) if (!defined $defs{$name}{READINGS}{$reading});
    $r=$defs{$name}{READINGS}{$reading}{VAL};
    $r="" if (!defined($r));
    if ($regExp) {
      if ($regExp =~ /^(avg|med|diffpsec|diff|inc)(\d*)/) {
        my @a=@{$hash->{accu}{"$name $reading"}{value}};
        my $func=$1;      
        my $dim=$2;
        $dim=2 if (!defined $dim or !$dim);
        my $num=@a < $dim ? @a : $dim;
        @a=splice (@a, -$num,$num);
        if ($func eq "avg" or $func eq "med") {
          return ($r) if (!@a);
        } elsif ($func eq "diff" or $func eq "diffpsec" or $func eq "inc") {
          return (0) if (@a <= 1);
        }
        if ($func eq "avg") {
          my $sum=0;
          foreach (@a) {
            $sum += $_;
          }
          return ($sum/$num);
        } elsif ($func eq "med") {
            my @vals = sort{$a <=> $b} @a;
            if ($num % 2) {
              return $vals[int($num/2)] if ($num % 2)
            } else {
              return ($vals[int($num/2) - 1] + $vals[int($num/2)])/2;
            }
        } elsif ($func eq "diffpsec") {
          my @t=@{$hash->{accu}{"$name $reading"}{time}};
          @t=splice (@t, -$num,$num);
          return (int(($a[-1]-$a[0])/($t[-1]-$t[0])*1000000)/1000000);
        } elsif ($func eq "diff") {
          return (($a[-1]-$a[0]));
        } elsif  ($func eq "inc") {
          if ($a[0] == 0) {
            return(0);
          } else {
            return (($a[-1]-$a[0])/$a[0]);
          }
        }
      } elsif ($regExp =~ /^((\d*)col(\d*)(.?))/) {
        my $dim= $2 eq "" ? 72:$2; 
        my $num=$3;
        my $time=$4;
        my $hours=24;
        if ($num ne "") {
         if($time eq "d") {
           $hours=24*$num;
         }elsif ($time eq "w") {
           $hours=24*$num*7;
         } else {
           $hours=$num;
         }
        }
        if (!defined $hash->{collect}{"$name $reading"}{$hours}) {
          return(undef);
        }
        DOIF_setValue_collect($hash,\%{$hash->{collect}{"$name $reading"}{$hours}});
        return (\%{$hash->{collect}{"$name $reading"}{$hours}});
      } elsif ($regExp =~ /^((bar|barAvg)(\d*)(day|week|month|year|decade))/) {
        my $bartype=$2;
        my $num = $3;  
        my $period = $4;
        if (!defined $hash->{$bartype}{"$name $reading"}{"$num $period"}) {
          return(undef);
        }
        DOIF_setValue_bar($hash,\%{$hash->{$bartype}{"$name $reading"}{"$num $period"}});
        return (\%{$hash->{$bartype}{"$name $reading"}{"$num $period"}});
      } elsif ($regExp =~ /^d(\d)?$/) {
        my $round=$1;
        $r = ($r =~ /(-?\d+(\.\d+)?)/ ? $1 : 0);
        $r = round ($r,$round) if (defined $round); 
        $regExp="(.*)";
      }
      "" =~ /()()()()()()()()()/; #reset $1, $2...
      $element = ($r =~  /$regExp/) ? $1 : "";
      if ($output) {
        $element= eval $output;
        if ($@) {
          Log3 ($hash->{NAME},4 , "$hash->{NAME}: $@");
          readingsSingleUpdate ($hash, "error", $@,1);
          return(undef);
        }
      }
    } else {
      $element=$r;
    }
    return($element);
}

sub accu_setValue
{
  
  my ($hash,$name,$reading)=@_;
  if (defined $hash->{accu}{"$name $reading"}) {
    my $a=$hash->{accu}{"$name $reading"}{value};
    my $dim=$hash->{accu}{"$name $reading"}{dim};
    shift (@{$a}) if (@{$a} >= $dim);
    my $r=ReadingsVal($name,$reading,0);
    $r = ($r =~ /(-?\d+(\.\d+)?)/ ? $1 : 0);
    push (@{$a},$r);
    if (defined $hash->{accu}{"$name $reading"}{time}) {
      my $t=$hash->{accu}{"$name $reading"}{time};
      shift (@{$t}) if (@{$t} >= $dim);
      #push (@{$t},time_str2num(ReadingsTimestamp($name,$reading,"")));
      my ($seconds, $microseconds) = gettimeofday();
      push (@{$t},$seconds+$microseconds/1000000);
    }
  }
}

sub DOIF_save_readings {
  my ($hash)=@_;
  foreach my $key (keys %{$defs{$hash->{NAME}}{READINGS}}) {
    delete $defs{$hash->{NAME}}{READINGS}{$key} if ($key =~ /^(\.col|\.bar)/);
  }
  DOIF_collect_save_values($hash);
  DOIF_bar_save_values($hash);
}


sub DOIF_collect_save_values {
  my ($hash)=@_;
  if (defined $hash->{collect}) {
    foreach my $dev_reading (keys %{$hash->{collect}}) {
      foreach my $hours (keys %{$hash->{collect}{"$dev_reading"}}) {
        if (ref($hash->{collect}{$dev_reading}{$hours}{values}) eq "ARRAY") {
          my @va=@{$hash->{collect}{$dev_reading}{$hours}{values}};
          my @ta=@{$hash->{collect}{$dev_reading}{$hours}{times}};
          for (@va) { $_ = "" if (!defined $_); };
          for (@ta) { $_ = "" if (!defined $_); };
          my $dim=$hash->{collect}{$dev_reading}{$hours}{dim};
          my $devReading=$dev_reading;
          $devReading =~ s/ /_/g;
          ::readingsSingleUpdate($hash,".col_".$dim."_".$devReading."_".$hours."_values",join(",",@va),0);
          ::readingsSingleUpdate($hash,".col_".$dim."_".$devReading."_".$hours."_times",join(",",@ta),0);
        }
      }
    }
  }
} 

sub DOIF_bar_save_values {
  my ($hash)=@_;
  foreach my $bartype ("bar","barAvg") {
    if (defined $hash->{$bartype}) {
      foreach my $dev_reading (keys %{$hash->{$bartype}}) {
        foreach my $num_period (keys %{$hash->{$bartype}{"$dev_reading"}}) {
          if (ref($hash->{$bartype}{$dev_reading}{$num_period}{values}) eq "ARRAY") {
            DOIF_setValue_bar($hash,\%{$hash->{$bartype}{$dev_reading}{$num_period}});
            my @va=@{$hash->{$bartype}{$dev_reading}{$num_period}{values}};
            for (@va) { $_ = "" if (!defined $_); };
            my $dim=$hash->{$bartype}{$dev_reading}{$num_period}{dim};
            my $last_period2=$hash->{$bartype}{$dev_reading}{$num_period}{last_period2};
            my $last_period1=$hash->{$bartype}{$dev_reading}{$num_period}{last_period1};
            my $devReading=$dev_reading;
            $devReading =~ s/ /_/g;
            my $numPeriod=$num_period;
            $numPeriod =~ s/ /_/g;
            ::readingsSingleUpdate($hash,".".$bartype."_".$devReading."_".$numPeriod."_values","$last_period1,$last_period2,".join(",",@va),0);
          }
        }
      }
    }
  }
} 

sub DOIF_setColvalue 
{
  my ($collect,$seconds,$value,$optimize)=@_;  
  my $dim=${$collect}{dim};
  my $hours=${$collect}{hours};
  my $va=${$collect}{values};
  my $ta=${$collect}{times};
  
  my $seconds_per_slot=$hours*3600/$dim;
  my $slot_nr=int ($seconds/$seconds_per_slot);
  my $last_slot=int(${$collect}{time}/$seconds_per_slot);   
  my $last_value;

  my $diff_slots=$last_slot-$slot_nr;
  if ($diff_slots >= 0) {
    if ($diff_slots < $dim) {
      my $pos=$dim-1-$diff_slots;
      if (defined $optimize or $pos > 1) {
        for (my $i=$pos-1;$i>=0;$i--) {
          if (defined (${$va}[$i])) {
            $last_value=${$va}[$i];
            last;
          }
        }
      }
      if (!defined $optimize or !defined ${$va}[$pos] or !defined $last_value or (abs($value-$last_value) >  abs(${$va}[$pos]-$last_value))) {
        ${$va}[$pos]=$value;
        ${$ta}[$pos]=$seconds;
      }
    }
  }
}

sub DOIF_get_file_data
{
  my ($file) = @_;
  my $fh;
  if(!open($fh, $file)) {
    return "Can't open $file: $!";
  }
  my @tpl=<$fh>;
  close $fh;
  my $cmd=join("",@tpl);
  $cmd =~ s/\r//g;
  return ($cmd);
}

sub DOIF_modify_card_data
{
  my ($name,$device,$reading,$colBarDes,$timeOffset,$valueData)=@_;
  DOIF_card_data (undef,$name,$device,$reading,$colBarDes,$timeOffset,$valueData);
}

sub DOIF_set_card_data
{
  my ($name,$device,$reading,$colBarDes,$timeOffset,$valueData)=@_;
  DOIF_card_data (1,$name,$device,$reading,$colBarDes,$timeOffset,$valueData);
}
  
sub DOIF_card_data
{
  my ($delOpt,$name,$device,$reading,$colBarDes,$timeOffset,$valueData)=@_;
  my $collect=ReadingValDoIf($defs{$name},$device,$reading,'',$colBarDes);
  if (!defined $collect) {
    return ("undefined  $name, $device, $reading, $colBarDes combination");
  }
  DOIF_delete_values ($collect) if (defined $delOpt);
  return(DOIF_setCardValues($defs{$name},$delOpt,ReadingValDoIf($defs{$name},$device,$reading,'',$colBarDes),$timeOffset,$valueData));
}

sub DOIF_setCardValues 
{
  my ($hash,$optimize,$collect,$timeOffset,$valueData)=@_;
  my $seconds;
  my $type=${$collect}{type};
  if (!defined $timeOffset or $timeOffset eq "") {
    $timeOffset=0;
  }
  ##if ($valueData !~ /^\d\d\d\d/) {
  ##  return("invalid syntax: $valueData");
  ##}
  if ($type eq "bar") {
    DOIF_setValue_bar($hash,$collect);
  } else {
    DOIF_setValue_collect($hash,$collect);
  }
  my @data;
  if ($valueData =~ /\n/) {
    @data=split (/[\n]/,$valueData);
  } else {
    @data=split (/[\,]/,$valueData);
  }
  my $out="";
  for (my $i=0;$i < scalar (@data);$i++) {
    if ($data[$i] !~ /\s*#/) {
      if ($data[$i] =~ /(.*)[\s;]+([\S^;]*)$/) {
        my $dateTime = $1;
        my $value = $2;
        $value =~ s/\,/\./g;
        my $time=DOIF_time_sec($dateTime);
        if (defined $time) {
          if ($type eq "bar") {
            DOIF_setBarvalue ($collect,$time+$timeOffset,$value);
          } else {
            DOIF_setColvalue ($collect,$time+$timeOffset,$value,$optimize);
          }
        } else {
          $out.="error at: $data[$i]\n";
        }
      } else {
          $out.="error at: $data[$i]\n";
      }
    }
  }
  if ($type eq "bar") {
    DOIF_setValue_bar($hash,$collect,undef,1);
  } else {
    DOIF_setValue_collect($hash,$collect,1);
  }
  if ($out eq "") {
    return;
  } else {
    return ($out);
  }
}

sub DOIF_delete_card_data
{
  my ($name,$device,$reading,$colBarDes)=@_;
  my $collect=ReadingValDoIf($defs{$name},$device,$reading,'',$colBarDes);
  if (!defined $collect) {
    return ("undefined  $name, $device, $reading, $colBarDes combination");
  }
  DOIF_delete_values($collect);
  return(undef);
}


sub DOIF_delete_values
{
  my ($a)=@_;
  @{${$a}{values}}=();
  @{${$a}{times}}=();
  
  delete ${$a}{max_value}; 
  delete ${$a}{max_value_slot}; 
  delete ${$a}{max_value_time}; 
  delete ${$a}{min_value}; 
  delete ${$a}{min_value_slot}; 
  delete ${$a}{min_value_time}; 
 
  delete ${$a}{average_value}; 
 # delete ${$a}{begin_period}; 
 # delete ${$a}{last_period1}; 
 # delete ${$a}{last_period2}; 
  
  if (${$a}{type} eq "col") {
    ${$a}{values}[${$a}{dim}-1]=undef;
    ${$a}{times}[${$a}{dim}-1]=undef;
  } elsif (${$a}{type} eq "bar") {
    ${$a}{values}[${$a}{dim}*${$a}{num}-1]=undef;
  }
}

sub DOIF_setValue_collect
{
  my ($hash,$collect,$statistic)=@_;
  if (!defined ${$collect}{dim}) {
    return;
  }
  my $name=${$collect}{name};
  my $reading=${$collect}{reading};
  my $hours=${$collect}{hours};
  my $change;

  my $r=ReadingsVal($name,$reading,0);
  if (defined ${$collect}{output}) {
    $_=$r;
    $r=eval(${$collect}{output});
    if ($@) {
      Log3 ($hash->{NAME},4 , "$hash->{NAME}: $@");
      readingsSingleUpdate ($hash, "error", "${$collect}{output}, ".$@,1);
    }
  }
  
  my ($seconds, $microseconds) = gettimeofday();
  
  if (defined $r) {
    $r = ($r =~ /(-?\d+(\.\d+)?)/ ? $1 : "N/A");
  } else {
    $r="N/A";
  }
  
  ${$collect}{value}=$r;
  ${$collect}{time}=$seconds;
  
  my $diff_slots=0;
  my $last_slot;

  my $dim=${$collect}{dim};
  my $va=${$collect}{values};
  my $ta=${$collect}{times};
  

  my $seconds_per_slot=$hours*3600/$dim;
   
  my $slot_nr=int ($seconds/$seconds_per_slot);
  
  if (defined ${$collect}{last_slot}) {
    $last_slot=${$collect}{last_slot};
  } elsif (defined ${$va}[$dim-1]) {
    $last_slot=int (${$ta}[-1]/$seconds_per_slot);
  }
  
  if (defined $last_slot) {
    $diff_slots=$slot_nr-$last_slot;
  }
  
  if ($diff_slots > 0) {
    $change=1;
    if ($diff_slots >= $dim) {
      ${$collect}{last_value}=${$collect}{value} if (defined ${$collect}{value});
      @{$va}=();
      @{$ta}=();
    } else {
      my @rv=splice (@{$va},0,$diff_slots);
      my @rt=splice (@{$ta},0,$diff_slots);
      if ($diff_slots > 1 and !defined ${$va}[$dim-$diff_slots] and defined ${$collect}{last} and ${$va}[$dim-$diff_slots-1] != ${$collect}{last}) {
        ${$va}[$dim-$diff_slots]=${$collect}{last};
        ${$ta}[$dim-$diff_slots]=(int(${$ta}[$dim-$diff_slots-1]/$seconds_per_slot)+1)*$seconds_per_slot;
      }
      for (my $i=@rv-1;$i>=0;$i--) {
        if (defined ($rv[$i])) {
          ${$collect}{last_value}=$rv[$i];
          last;
        }
      }
    }
    ${$collect}{last}=undef;
  }
  
  if (!defined ${$va}[$dim-1] or !defined ${$collect}{last_v} or (abs($r-${$collect}{last_v}) >  abs(${$va}[$dim-1]-${$collect}{last_v}))) {
    if ($r ne "N/A") {
      if (!defined ${$va}[$dim-1] or ${$va}[$dim-1] != $r) {
        $change=1;
        ${$va}[$dim-1]=$r;
      }
     # ${$collect}{last_v}=$r
    } else { 
      ${$va}[$dim-1]=undef;
    }
    ${$ta}[$dim-1]=$seconds;
    ${$collect}{last_slot}=$slot_nr;
  } elsif ($r ne "N/A" and ${$va}[$dim-1] != $r) {
    ${$collect}{last}=$r;
  }
  
  if (defined $statistic or defined $change) {
    DOIF_statistic_col ($collect)
  }
} 

sub DOIF_statistic_col 
{   
  my ($collect)=@_;
  my $maxVal;
  my $maxValTime;
  my $maxValSlot;
  my $minVal;
  my $minValTime;
  my $minValSlot;
  my $dim=${$collect}{dim};
  my $va=${$collect}{values};
  my $ta=${$collect}{times};
  
  for (my $i=0;$i<@{$va};$i++) {
    my $value=${$va}[$i];
    my $time=${$ta}[$i];
    if (defined $value and defined $time) {
      if (!defined $maxVal or $value >= $maxVal) {
         $maxVal=$value;
         $maxValTime=$time;
         $maxValSlot=$i;
      }
      if (!defined $minVal or $value <= $minVal) {
         $minVal=$value;
         $minValTime=$time;
         $minValSlot=$i;
      }
    }
  }
  
  ${$collect}{last_v}= undef;
  for (my $i=@{$va}-2;$i >= 0;$i--) {
    if (defined ${$va}[$i]) {
       ${$collect}{last_v}=${$va}[$i];
      last;
    }
  }
  delete ${$collect}{max_value};
  delete ${$collect}{max_value_time};
  delete ${$collect}{max_value_slot};
  delete ${$collect}{min_value};
  delete ${$collect}{min_value_time};
  delete ${$collect}{min_value_slot};
  
  if (defined $maxVal) {
    ${$collect}{max_value}=$maxVal;
    ${$collect}{max_value_time}=$maxValTime;
    ${$collect}{max_value_slot}=$maxValSlot;
    
    ${$collect}{min_value}=$minVal;
    ${$collect}{min_value_time}=$minValTime;
    ${$collect}{min_value_slot}=$minValSlot;
  }
  if (defined ${$collect}{last_value}) {
    if (${$collect}{last_value} > $maxVal) {
      ${$collect}{last_value}=$maxVal;
    } elsif (${$collect}{last_value} < $minVal) {
      ${$collect}{last_value}=$minVal;
    }
  }
}

sub DOIF_time_sec($)
{
  my ($dateTime) = @_;
  my @a;
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst);
  if ($dateTime =~/^(\d\d\d\d)(?:.(.*))?/) {
    $year=$1;
    ($month,$mday,$hour,$min,$sec) = split(/[\D]/, $2) if (defined $2);
  } elsif ($dateTime =~/(\d\d).(\d\d).(\d\d\d\d)(?:.(\d\d):(\d\d)(?::(\d\d))?)?/) {
    $mday=$1;
    $month=$2;
    $year=$3;
    $hour=$4;
    $min=$5;
    $sec=$6;
  } else {
    return (undef);
  }
 
  $month=1 if (!defined $month);
  $mday=1 if (!defined $mday);
  $hour=0 if (!defined $hour);
  $min=0 if (!defined $min);
  $sec=0 if (!defined $sec);
  
  return mktime($sec,$min,$hour,$mday,$month-1,$year-1900,0,0,-1);
}

sub DOIF_statistic_bar
{
  my ($bar)=@_;
  my $num=${$bar}{num};
  my $numOrig=${$bar}{numOrig};
  my $dim=${$bar}{dim};
  my $maxVal;
  my $minVal;
  my $maxValSlot;
  my $minValSlot;
  my $sum=0;
  my $numb=0;
  my $period2=${$bar}{last_period2};
  my $period1=${$bar}{last_period1};
  my $va=${$bar}{values};
  
  for (my $i=0;$i<@{$va};$i++) {
    my $value=${$va}[$i];
  #  if (defined $value) {
    if (defined $value and ($numOrig != 1 or (int($i/$dim) == 0 or $i % $dim > $period1 or $i % $dim == $period1 and !defined ${$va}[$period1]))) {
      $numb++;
      $sum+=$value;
      if (!defined $maxVal or $value > $maxVal) {
         $maxVal=$value;
         $maxValSlot=$i;
      }
      if (!defined $minVal or $value < $minVal) {
         $minVal=$value;
         $minValSlot=$i;
      }
    }
  }
  
  delete ${$bar}{max_value};
  delete ${$bar}{max_value_slot};
  delete ${$bar}{min_value};
  delete ${$bar}{min_value_slot};
  delete ${$bar}{average_value};
  
  if ($numb > 0) {
    ${$bar}{max_value}=$maxVal;
    ${$bar}{max_value_slot}=$maxValSlot;
    ${$bar}{min_value}=$minVal;
    ${$bar}{min_value_slot}=$minValSlot;
    ${$bar}{average_value}=$sum/$numb;
    if (${$bar}{period} eq "decade") {
      ${$bar}{max_value_time}=((${$bar}{last_period2}-int($maxValSlot/$dim))*10+($maxValSlot % $dim));
      ${$bar}{min_value_time}=((${$bar}{last_period2}-int($minValSlot/$dim))*10+($minValSlot % $dim));
    } elsif (${$bar}{period} eq "year") {
      ${$bar}{max_value_time}=qw(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)[$maxValSlot % $dim]." ".(($period2-int($maxValSlot/$dim)) % 100);
      ${$bar}{min_value_time}=qw(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)[$minValSlot % $dim]." ".(($period2-int($minValSlot/$dim)) % 100);
    } elsif (${$bar}{period} eq "month") {
     # ${$bar}{max_value_time}=(($maxValSlot % $dim)+1).". ".qw(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)[($period2-int($maxValSlot/$dim)) % 12];
      ${$bar}{max_value_time}=sprintf("%02d.%02d",(($maxValSlot % $dim)+1),($period2-int($maxValSlot/$dim)) % 12+1);
      ${$bar}{min_value_time}=sprintf("%02d.%02d",(($minValSlot % $dim)+1),($period2-int($minValSlot/$dim)) % 12+1);
    } elsif (${$bar}{period} eq "week") {
      my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday)=gmtime(($period2-int($maxValSlot/$dim))*604800+(($maxValSlot % $dim)-3)*86400);
      ${$bar}{max_value_time}=sprintf("%02d.%02d",$mday,$month+1);
      ($sec,$min,$hour,$mday,$month,$year,$wday,$yday)=gmtime(($period2-int($minValSlot/$dim))*604800+(($minValSlot % $dim)-3)*86400);
      #${$bar}{min_value_time}=sprintf("%s %02d.%02d",qw(So Mo Di Mi Do Fr Sa)[$wday],$mday,$month+1);
      ${$bar}{min_value_time}=sprintf("%02d.%02d",$mday,$month+1);
    } elsif (${$bar}{period} eq "day") {
      my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday)=gmtime(($period2-int($maxValSlot/$dim))*86400+(($maxValSlot % $dim))*3600);
      ${$bar}{max_value_time}=sprintf("%s %02d:",qw(So Mo Di Mi Do Fr Sa)[$wday],$hour);
      ($sec,$min,$hour,$mday,$month,$year,$wday,$yday)=gmtime(($period2-int($minValSlot/$dim))*86400+(($minValSlot % $dim))*3600);
      ${$bar}{min_value_time}=sprintf("%s %02d:",qw(So Mo Di Mi Do Fr Sa)[$wday],$hour);
    }
  }
}

sub DOIF_setPeriod
{
  my ($seconds,$period)=@_;

  my $period1;
  my $period2;
  my $begin_period2;

 # $seconds+=5*3600+30*60;
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime($seconds);
  $year+=1900;
  if ($period eq "decade") {
    $period1=$year%10;
    $period2=int($year/10);
    $begin_period2=($period2)."-";
  } elsif ($period eq "year") {
    $period1=$month;
    $period2=$year;
    $begin_period2=$year;
  } elsif ($period eq "month") {
    $period1=$mday-1;
    $period2=$month+$year*12;
    $begin_period2=qw(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)[$month];
  } else {
    my ($gsec,$gmin,$ghour,$gmday,$gmon,$gyear,$gwday,$gyday)  = gmtime($seconds);
    $gyear+=1900;
    my $offset=($min - $gmin)/60 + $hour - $ghour + 24 * ($year - $gyear || $yday - $gyday); # time zone offset
    if ($period eq "week") {
      $period1=$wday == 0 ? 6: $wday-1;
      $period2=int(($seconds+3*86400+$offset*3600)/604800);
      ($sec,$min,$hour,$mday,$month,$year,$wday,$yday) = gmtime($period2*604800-3*86400);
      $begin_period2=sprintf("%02d.%02d-",$mday,$month+1);
    } elsif ($period eq "day") {
      $period1=$hour;
      $period2=int(($seconds+$offset*3600)/86400);
      #($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime($period2*86400+($isdst+$offset)*3600);
      #$begin_period2=sprintf("%02d.%02d",$mday,$month+1);
      $begin_period2=qw(So Mo Di Mi Do Fr Sa)[$wday];
    }
  }
  return ($period1,$period2,$begin_period2);
}

sub DOIF_setBarPosValue
{
  my ($bar,$pos,$value)=@_;  
  my $va=${$bar}{values};
  if (defined ${$bar}{barType} and ${$bar}{barType} eq "barAvg") {
    if (defined ${$va}[$pos] and defined ${$bar}{value_pos} and $pos == ${$bar}{value_pos}) {
      ${$bar}{value_sum}+=$value;
      ${$bar}{value_num}++;
      ${$va}[$pos]=${$bar}{value_sum}/${$bar}{value_num};
    } else {
      ${$bar}{value_pos}=$pos;
      ${$bar}{value_sum}=$value;
      ${$bar}{value_num}=1;
      ${$va}[$pos]=$value;
    }
  } else {  
    ${$va}[$pos]=$value;
  }
}


sub DOIF_setBarvalue 
{
  my ($bar,$seconds,$value)=@_;  
  my $period=${$bar}{period};
  my $num=${$bar}{num};
  my $dim=${$bar}{dim};

  my ($period1,$period2)=DOIF_setPeriod($seconds,$period);
     
  if (defined ${$bar}{last_period2} and $period2 <= ${$bar}{last_period2}) {
    my $diff=(${$bar}{last_period2} - $period2);
    if ($diff < $num) {
      DOIF_setBarPosValue($bar,$diff*$dim+$period1,$value);
    }
  }
}

sub DOIF_setValue_bar
{
  my ($hash,$bar,$trigger,$statistic)=@_;
  if (!defined ${$bar}{dim}) {
    return;
  }
  my $name=${$bar}{name};
  my $reading=${$bar}{reading};
  my $period=${$bar}{period};
  my $num=${$bar}{num};
  my $dim=${$bar}{dim};
  my $timeOffset=${$bar}{timeOffset};
  
  my $r=ReadingsVal($name,$reading,0);
  if (defined ${$bar}{output}) {
    $_=$r;
    $r=eval(${$bar}{output});
    if ($@) {
      Log3 ($hash->{NAME},4 , "$hash->{NAME}: $@");
      readingsSingleUpdate ($hash, "error", "${$bar}{output}, ".$@,1);
    }
  }
  
  my ($seconds, $microseconds) = gettimeofday();
  my ($period1,$period2,$begin_period2)=DOIF_setPeriod($seconds,$period);

  if (defined $r) { 
    $r = ($r =~ /(-?\d+(\.\d+)?)/ ? $1 : "N/A");
  } else {
    $r="N/A";
  }

  if (defined $trigger) {
    if ($r ne "N/A") {
     # if (${$bar}{counter}) {
     #   if (!defined ${$bar}{last_period1}) {
     #     ${$bar}{last_period1}=$period1;
     #   } elsif (${$bar}{last_period1} <= $period1) {
     #     ${$bar}{last_counter}=$r;
     #   }
     #   ${$bar}{value}=${$bar}{last_counter}-$r;
     # } else {
        ${$bar}{value}=$r;
     # }
    }
  }


  my $va=${$bar}{values};
  my $change="";
  
  if (defined ${$bar}{last_period2} and ${$bar}{last_period2} < $period2) {
    my @empty;
    my $diff=($period2-${$bar}{last_period2});
    if ($diff < $num) {
      $empty [$diff*$dim-1]=undef;
      splice (@{$va},($num-$diff)*$dim);        
      splice (@{$va},0,0,@empty);
    } else {
      @{$va}=();
      ${$va}[$num*$diff-1]=undef;
    }
    $change=1;
  }

  ${$bar}{last_period2}=$period2;
  ${$bar}{last_period1}=$period1;
  ${$bar}{begin_period2}=$begin_period2;
 

  
  ${$bar}{value}=$r;
  if (defined $trigger and $r ne "N/A") {
    if ($timeOffset == 0) {
      DOIF_setBarPosValue($bar,$period1,${$bar}{value})
      #${$va}[$period1]=${$bar}{value};
    } else {
      DOIF_setBarvalue ($bar,$seconds+$timeOffset,${$bar}{value});
    }      
    $change=1;
  }
  
  if ($change or defined $statistic) {
    DOIF_statistic_bar ($bar)
  }
}

sub EvalAllDoIf($$)
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
	    $eval=$1 if ($eval =~/^\((.*)\)$/);
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

sub ReplaceAggregateDoIf($$$)
{
  my ($hash,$block,$eval) = @_;
  my $exp;
  my $nameExp;
  my $notifyExp;
  my $match;
  my $reading;
  my $aggrType;
  my $default;
  
  ($block,$default)=SplitDoIf(",",$block);
  
  if ($block =~ /^([^"]*)(.*)/) {
    $aggrType=$1;
    $block=$2;
  }
  
  ($exp,$reading,$match)=SplitDoIf(":",$block);
  if ($exp =~ /^"(.*)"/){
    $exp=$1;
    if ($exp =~ /([^\:]*):(.*)/) {
      $nameExp=$1;
      $notifyExp=$2;
    } else {
      $nameExp=$exp;
    }
  }
  $nameExp="" if (!defined $nameExp);
  $notifyExp="" if (!defined $notifyExp);
  
  if (defined $default) {
    $match="" if (!defined $match);
    $block="::AggregateDoIf(".'$hash'.",'$aggrType','$nameExp','$reading','$match','$default')";
  } elsif (defined $match) {
    $block="::AggregateDoIf(".'$hash'.",'$aggrType','$nameExp','$reading','$match')";
  } elsif (defined $reading) {
    $block="::AggregateDoIf(".'$hash'.",'$aggrType','$nameExp','$reading')";
  } else {
     $block="::AggregateDoIf(".'$hash'.",'$aggrType','$nameExp')";
  }
  
  if ($eval) {
    my $ret = eval $block;
    return($block." ",$@) if ($@);
    $block=$ret;
  }
  return ($block,undef);
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
      $block="::EventDoIf('$nameExp',".'$hash,'."'$notifyExp',0)";
      return ($block,undef);
    }
  }
  $block="::EventDoIf('$nameExp',".'$hash,'."'$notifyExp',0,'$filter','$output','$default')";
  return ($block,undef);
}

sub ReplaceReadingDoIf
{
  my ($hash,$element,$cond) = @_;
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
    if (defined ($reading)) {
      if (substr($reading,0,1) eq "\?") {
        $notifyExp=substr($reading,1);
        return("::EventDoIf('$name',".'$hash,'."'$notifyExp',1)","",$name,undef,undef);
      } elsif ($reading =~ /^"(.*)"$/g)  {
        $notifyExp=$1;
        return("::EventDoIf('$name',".'$hash,'."'$notifyExp',1)","",$name,undef,undef);
      }
      $internal = substr($reading,1) if (substr($reading,0,1) eq "\&");
      if ($format) {
        if ($format eq "sec") {
          return("::ReadingSecDoIf('$name','$reading')","",$name,$reading,undef);
        } elsif (substr($format,0,1) eq '[') { #old Syntax
          ($beginning,$regExp,$err,$tailBlock)=GetBlockDoIf($format,'[\[\]]');
          return ($regExp,$err) if ($err);
          return ($regExp,"no round brackets in regular expression") if ($regExp !~ /.*\(.*\)/);
        } elsif ($format =~ /^"([^"]*)"(?::(.*))?/){
          $regExp=$1;
          $output=$2;
          return ($regExp,"no round brackets in regular expression") if ($regExp !~ /.*\(.*\)/);
        } elsif ($format =~ /^((avg|med|diffpsec|diff|inc)(\d*))/) {
           AddRegexpTriggerDoIf($hash,"accu","","accu",$name,$reading);
           $regExp =$1;
           my $dim=$3;
           $dim=2 if (!defined $dim or !$dim);
           if (!defined $hash->{accu}{"$name $reading"}{dim} or $hash->{accu}{"$name $reading"}{dim} != $dim) {
#             $hash->{accu}{"$name $reading"}{dim}=$hash->{accu}{"$name $reading"}{dim} != $dim ? $dim : $hash->{accu}{"$name $reading"}{dim};
#           } else {
             $hash->{accu}{"$name $reading"}{dim}=$dim;
             @{$hash->{accu}{"$name $reading"}{value}}=();
             @{$hash->{accu}{"$name $reading"}{time}}=() if ($2 eq "diffpsec");
           }
        } elsif ($format =~ /^((\d*)col(\d*)(\w?))(?::(.*))?/) {
           $regExp =$1;
           my $dim= $2 eq "" ? 72:$2;           
           my $num=$3;
           my $time=$4;
           $output=$5;
          if (defined $cond and $cond >= -7 and $cond <= -4) { #DOIF_Readings,event_Readings,uiTable,uiState
             my $hours=24;
             if ($num ne "") {
               if($time eq "d") {
                 $hours=24*$num;
               }elsif ($time eq "w") {
                 $hours=24*$num*7;
               } else {
                 $hours=$num;
               }
             }
             AddRegexpTriggerDoIf($hash,"collect","","collect",$name,$reading);
             if (ref($hash->{collect}{"$name $reading"}{$hours}{values}) ne "ARRAY" or $dim != $hash->{collect}{"$name $reading"}{$hours}{dim}) {
               delete $hash->{collect}{"$name $reading"}{$hours};
               $hash->{collect}{"$name $reading"}{$hours}{hours}=$hours;
               $hash->{collect}{"$name $reading"}{$hours}{dim}=$dim;
               $hash->{collect}{"$name $reading"}{$hours}{animate}= (defined $hash->{card}{animate} and $hash->{card}{animate} eq "1") ? 1 :0;
               my $values=::ReadingsVal($hash->{NAME},".col_".$hash->{collect}{"$name $reading"}{$hours}{dim}."_".$name."_".$reading."_".$hours."_values","");
               my $times=::ReadingsVal($hash->{NAME},".col_".$hash->{collect}{"$name $reading"}{$hours}{dim}."_".$name."_".$reading."_".$hours."_times","");
               my $va;
               my $ta;
               @{$va}=split (",",$values);
               for (@{$va}) { $_ = undef if ($_ eq ""); };
               @{$ta}=split (",",$times);
               for (@{$ta}) { $_ = undef if ($_ eq ""); };
               $hash->{collect}{"$name $reading"}{$hours}{values}=$va;
               $hash->{collect}{"$name $reading"}{$hours}{times}=$ta;
               $hash->{collect}{"$name $reading"}{$hours}{dim}=$dim;
               $hash->{collect}{"$name $reading"}{$hours}{name}=$name;
               $hash->{collect}{"$name $reading"}{$hours}{reading}=$reading;
               $hash->{collect}{"$name $reading"}{$hours}{type}="col";
             }
             if (!defined $output or $output eq "") {
              delete $hash->{collect}{"$name $reading"}{$hours}{output};
             } else {
              $hash->{collect}{"$name $reading"}{$hours}{output}=$output;
             }
             DOIF_setValue_collect($hash,\%{$hash->{collect}{"$name $reading"}{$hours}},1);
          }
        } elsif ($format =~ /^((bar|barAvg)(\d*)(day|week|month|year|decade))(-?\d*)?(?::(.*))?/) {
           $regExp = $1;
           my $bartype=$2;
           my $num = $3;  
           my $period = $4;
           my $timeOffset = $5;
           $output = $6;
           if (defined $cond and $cond >= -7 and $cond <= -4) { #DOIF_Readings,event_Readings,uiTable,uiState
             my $dim;
             if ($period eq "decade") {
               $dim=10;
             } elsif ($period eq "year") {
               $dim=12;
             } elsif ($period eq "month") {
               $dim=31;
             } elsif ($period eq "week") {
               $dim=7;
             } elsif ($period eq "day") {
               $dim=24;
             }
             AddRegexpTriggerDoIf($hash,$bartype,"",$bartype,$name,$reading);
             if (ref($hash->{$bartype}{"$name $reading"}{"$num $period"}{values}) ne "ARRAY")  {
               delete $hash->{$bartype}{"$name $reading"}{"$num $period"};
               my $values=::ReadingsVal($hash->{NAME},".".$bartype."_".$name."_".$reading."_".$num."_".$period."_values","");
               my $va;
               my $vadim=($num == 1 ? 2 : $num)*$dim;
               if ($values ne "") {
                 ($hash->{$bartype}{"$name $reading"}{"$num $period"}{last_period1},$hash->{$bartype}{"$name $reading"}{"$num $period"}{last_period2},@{$va})=split (",",$values);
                 if (@{$va} < $vadim) {
                   ${$va}[$vadim-1]=undef;
                 }
                 for (@{$va}) { $_ = undef if (defined $_ and $_ eq ""); };
               } else {
                 ${$va}[$vadim-1]=undef;
               }
               $hash->{$bartype}{"$name $reading"}{"$num $period"}{values} = $va;
               $hash->{$bartype}{"$name $reading"}{"$num $period"}{numOrig} = $num;
               $hash->{$bartype}{"$name $reading"}{"$num $period"}{num} = $num == 1 ? 2 : $num;
               $hash->{$bartype}{"$name $reading"}{"$num $period"}{period} = $period;
               $hash->{$bartype}{"$name $reading"}{"$num $period"}{name} = $name;
               $hash->{$bartype}{"$name $reading"}{"$num $period"}{reading} = $reading;
               #$hash->{$bartype}{"$name $reading"}{"$num $period"}{counter}=$counter;
               
               $hash->{$bartype}{"$name $reading"}{"$num $period"}{dim} = $dim;
               $hash->{$bartype}{"$name $reading"}{"$num $period"}{type} = "bar";
               $hash->{$bartype}{"$name $reading"}{"$num $period"}{barType} = $bartype;
            } 
            if (!defined $output or $output eq "") {
              delete $hash->{$bartype}{"$name $reading"}{"$num $period"}{output};
            } else {
              $hash->{$bartype}{"$name $reading"}{"$num $period"}{output} = $output;
            }
            $hash->{$bartype}{"$name $reading"}{"$num $period"}{timeOffset} = (defined $timeOffset and $timeOffset ne "") ? $timeOffset : 0; 
            DOIF_setValue_bar($hash,\%{$hash->{$bartype}{"$name $reading"}{"$num $period"}},undef,1);            
          }
        } elsif ($format =~ /^(d\d?)(?::(.*))?/) {
          $regExp =$1;
          $output=$2;
        }else {
          return($format,"unknown expression format");
        }
      }
      $output="" if (!defined($output));

      if ($output) {
        $param=",'$default','$regExp','$output'";
      } elsif ($regExp) {
        $param=",'$default','$regExp'";
      } elsif ($default ne "") {
        $param=",'$default'";
      }
      if ($internal) {
        return("::InternalDoIf(".'$hash'.",'$name','$internal'".$param.")","",$name,undef,$internal);
      } else {
        return("::ReadingValDoIf(".'$hash'.",'$name','$reading'".$param.")","",$name,$reading,undef);
      }
    } else {
      if ($default ne "") {
        $param=",'$default'";
      }
      return("::InternalDoIf(".'$hash'.",'$name','STATE'".$param.")","",$name,undef,'STATE');
    }
  }
}

sub ReplaceReadingEvalDoIf
{
  my ($hash,$element,$eval,$cond) = @_;
  my ($block,$err,$device,$reading,$internal)=ReplaceReadingDoIf($hash,$element,$cond);
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

sub AddRegexpTriggerDoIf
{
  my ($hash,$type,$regexp,$element,$dev,$reading)= @_;
  
  $dev="" if (!defined($dev));
  $reading="" if (!defined($reading));
  my $regexpid='"'.$regexp.'"';
  if ($dev) {
    if (defined ($reading)){
      $hash->{Regex}{$type}{$dev}{$element}{$reading}=(($reading =~ "^\&") ? "\^$dev\$":"\^$dev\$:\^$reading: ");
    } elsif ($regexp) {
      $hash->{Regex}{$type}{$dev}{$element}{$regexpid}="\^$dev\$:$regexp";
    }
    return;
  }
  $hash->{Regex}{$type}{$dev}{$element}{$regexpid}=$regexp;
}

sub addDOIF_Readings
{
  my ($hash,$DOIF_Readings,$ReadingType) = @_;
  delete $hash->{$ReadingType};
  delete $hash->{Regex}{$ReadingType};
  $DOIF_Readings =~ s/\n/ /g;
  my @list=SplitDoIf(',',$DOIF_Readings);
  my $reading;
  my $readingdef;
  
  for (my $i=0;$i<@list;$i++)
  {
    ($reading,$readingdef)=SplitDoIf(":",$list[$i]);
    if (!$readingdef) {
      return ($DOIF_Readings,"no reading definiton: $list[$i]");
    }
    if ($reading =~ /^\s*([a-z0-9._-]*[a-z._-]+[a-z0-9._-]*)\s*$/i) {
      my ($def,$err)=ReplaceAllReadingsDoIf($hash,$readingdef,($ReadingType eq "event_Readings" ? -7 : -4),0,$1);
      return ($def,$err) if ($err);
      $hash->{$ReadingType}{$1}=$def;
    } else {
      return ($list [$i],"wrong reading specification for: $reading");
    }
  }
  return ("","");
}

sub setDOIF_Reading
{
  my ($hash,$DOIF_Reading,$reading,$ReadingType,$eventa,$eventas,$dev) = @_;
  $lastWarningMsg="";
  $hash->{helper}{triggerEvents}=$eventa;
  $hash->{helper}{triggerEventsState}=$eventas;
  $hash->{helper}{triggerDev}=$dev;
  $hash->{helper}{event}=join(",",@{$eventa}) if ($eventa);

  my $ret = eval $hash->{$ReadingType}{$DOIF_Reading};

  if ($@) {
    $@ =~ s/^(.*) at \(eval.*\)(.*)$/$1,$2/;
    $ret="error in $ReadingType: ".$@;
  }
  if ($lastWarningMsg) {
    $lastWarningMsg =~ s/^(.*) at \(eval.*$/$1/;
    Log3 ($hash->{NAME},3 , "$hash->{NAME}: warning in $ReadingType: $DOIF_Reading");
  } 
  $lastWarningMsg="";
  if (!defined $ret) {
    return;
  }
  if ($ReadingType eq "event_Readings") {
    readingsSingleUpdate ($hash,$DOIF_Reading,$ret,1);
  } elsif ($ret ne ReadingsVal($hash->{NAME},$DOIF_Reading,"") or !defined $defs{$hash->{NAME}}{READINGS}{$DOIF_Reading}) {
      push (@{$hash->{helper}{DOIF_Readings_events}},"$DOIF_Reading: $ret");
      push (@{$hash->{helper}{DOIF_Readings_eventsState}},"$DOIF_Reading: $ret");
      readingsSingleUpdate ($hash,$DOIF_Reading,$ret,0);
    }
}

sub ReplaceAllReadingsDoIf
{
  my ($hash,$tailBlock,$condition,$eval,$id,$event)= @_;
  my $block="";
  my $beginning;
  my $err;
  my $cmd="";
  my $ret="";
  my $device="";
  my $nr;
  my $timer="";
  my $definition=$tailBlock;
  my $reading;
  my $internal;
  my $trigger=1;
  $event=0 if (!defined ($event));
  
  if (!defined $tailBlock) {
    return ("","");
  }
  $tailBlock =~ s/\$SELF/$hash->{NAME}/g;
  while ($tailBlock ne "") {
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\[\]]');
    return ($block,$err) if ($err);
    if ($block ne "") {
      if (substr($block,0,1) eq "?") {
            $block=substr($block,1);
            $trigger=0;
      } else {
        $trigger=1;
      }
      if ($block =~ /^(?:(?:#|@)[^"]*)"([^"]*)"/) {
        ($block,$err)=ReplaceAggregateDoIf($hash,$block,$eval);
        return ($block,$err) if ($err);
        if ($trigger) {
          $event=1;
          if ($condition >= 0) {
            AddRegexpTriggerDoIf($hash,"cond",$1,$condition);
          } elsif ($condition == -2) {
            AddRegexpTriggerDoIf($hash,"STATE",$1,"STATE");
          } elsif ($condition == -4) {
            AddRegexpTriggerDoIf($hash,"DOIF_Readings",$1,$id);
          } elsif ($condition == -5) {
            AddRegexpTriggerDoIf($hash,"uiTable",$1,$id);
          }  elsif ($condition == -6) {
            AddRegexpTriggerDoIf($hash,"uiState",$1,$id);
          } elsif ($condition == -7) {
            AddRegexpTriggerDoIf($hash,"event_Readings",$1,$id);
          }
        }
      } elsif ($block =~ /^"([^"]*)"/ and $condition != -5 and $condition != -6) {
        ($block,$err)=ReplaceEventDoIf($block);
        return ($block,$err) if ($err);
        if ($trigger) {
          if ($condition>=0) {
            AddRegexpTriggerDoIf($hash,"cond",$1,$condition);
            $event=1;
          } elsif ($condition == -4) {
            AddRegexpTriggerDoIf($hash,"DOIF_Readings",$1,$id);
          } elsif ($condition == -7) {
            AddRegexpTriggerDoIf($hash,"event_Readings",$1,$id);
          } else {
            $block="[".$block."]";
          }
        } else {
          $block="[".$block."]";
        }
      } else {
        $trigger=0 if (substr($block,0,7) eq "\$DEVICE");
        if ($block =~ /^(\$DEVICE|[a-z0-9._]*[a-z._]+[a-z0-9._]*)($|:.+$|,.+$)/i) {
          ($block,$err,$device,$reading,$internal)=ReplaceReadingEvalDoIf($hash,$block,$eval,$condition);
          return ($block,$err) if ($err);
          if ($condition >= 0) {
            if ($trigger) {
              AddRegexpTriggerDoIf($hash,"cond","",$condition,$device,((defined $reading) ? $reading :((defined $internal) ? ("&".$internal):"&STATE")));
              $event=1;
            }
            $hash->{readings}{all} = AddItemDoIf($hash->{readings}{all},"$device:$reading") if (defined ($reading) and $trigger);
            $hash->{internals}{all} = AddItemDoIf($hash->{internals}{all},"$device:$internal") if (defined ($internal));
            $hash->{trigger}{all} = AddItemDoIf($hash->{trigger}{all},"$device") if (!defined ($internal) and !defined($reading));
          } elsif ($condition == -2) {
            if ($trigger) {
              AddRegexpTriggerDoIf($hash,"STATE","","STATE",$device,((defined $reading) ? $reading :((defined $internal) ? ("&".$internal):"&STATE")));
              $event=1;
            }
          } elsif ($condition == -3) {
              AddRegexpTriggerDoIf($hash,"itimer","","itimer",$device,((defined $reading) ? $reading :((defined $internal) ? ("&".$internal):"&STATE")));
          } elsif ($condition == -4) {
            if ($trigger) {
              AddRegexpTriggerDoIf($hash,"DOIF_Readings","",$id,$device,((defined $reading) ? $reading :((defined $internal) ? ("&".$internal):"&STATE")));
              $event=1;
            }
          } elsif ($condition == -5) {
            if ($trigger) {
              AddRegexpTriggerDoIf($hash,"uiTable","",$id,$device,((defined $reading) ? $reading :((defined $internal) ? ("&".$internal):"&STATE")));
              $hash->{uiTable}{dev}=$device;
              $hash->{uiTable}{reading}=((defined $reading) ? $reading :((defined $internal) ? ("&".$internal):"&STATE"));
              $event=1;
            }
          } elsif ($condition == -6) {
            if ($trigger) {
              AddRegexpTriggerDoIf($hash,"uiState","",$id,$device,((defined $reading) ? $reading :((defined $internal) ? ("&".$internal):"&STATE")));
              $hash->{uiState}{dev}=$device;
              $hash->{uiState}{reading}=((defined $reading) ? $reading :((defined $internal) ? ("&".$internal):"&STATE"));
              $event=1;
            }
          } elsif ($condition == -7) {
            if ($trigger) {
              AddRegexpTriggerDoIf($hash,"event_Readings","",$id,$device,((defined $reading) ? $reading :((defined $internal) ? ("&".$internal):"&STATE")));
              $event=1;
            }
          }
        } elsif ($condition >= 0) {
          ($timer,$err)=DOIF_CheckTimers($hash,$block,$condition,$trigger);
          if ($err eq "no timer") {
            $block="[".$block."]";
          } else {  
            return($timer,$err) if ($err);
            if ($timer) {
              $block=$timer;
              $event=1 if ($trigger);
            }
          }
        } else {
          ($block,$err,$event)=ReplaceAllReadingsDoIf($hash,$block,$condition,$eval,$id,$event);
          return ($block,$err) if ($err);
          $block="[".$block."]";
        }
      }
    }
    $cmd.=$beginning.$block;
  }
  #return ($definition,"no trigger in condition") if ($condition >=0 and $event == 0);
  return ($cmd,"",$event);
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
	   if ($currentBlock =~ /^{.*}$/) {
	     $ret = AnalyzePerlCommand(undef,$currentBlock);
	   } else {
         $ret = AnalyzeCommandChain(undef,$currentBlock);
       }
	   if ($ret) {
         Log3 $pn,2 , "$pn: $currentBlock: $ret";
         $last_error.="$currentBlock: $ret ";
       }
    }
    $tailBlock=substr($tailBlock,pos($tailBlock)) if ($tailBlock =~ /^\s*,/g);
  }
  return("",$last_error);
}

sub DOIF_weekdays($$)
{
  my ($hash,$weekdays)=@_;
  my @days=split(',',AttrVal($hash->{NAME},"weekdays","So|Su,Mo,Di|Tu,Mi|We,Do|Th,Fr,Sa,WE,AT|WD,MWE|TWE,MAT|TWD"));
  
  for (my $i=@days-1;$i>=0;$i--)
  {
    my $wd = $i==10 ? "X" : $i;
    $weekdays =~ s/$days[$i]/$wd/;
  }

  return($weekdays);
}


sub
DOIF_CheckTimers($$$$)
{
  my ($hash,$timer,$condition,$trigger)=@_;
  my $i=0;
  my $days;
  my $err;
  my $time;
  my $block;
  my $result;
  my $end;
  my $intervaltimer;
    
  $timer =~ s/\s//g;

  ($timer,$days)=SplitDoIf('|',$timer);
  $days="" if (!defined $days);
  ($timer,$intervaltimer)=SplitDoIf(',',$timer);
  ($time,$end)=SplitDoIf('-',$timer);
  
  if (defined $intervaltimer) {
    if (!defined $end) {
      return($timer,"intervaltimer without time interval");
    }
  }
  $i=$hash->{helper}{last_timer};
  if (defined $time) {
    if ($time !~ /^\s*(\[.*\]|\{.*\}|\(.*\)|\+.*|[0-9][0-9]:.*|:[0-5][0-9])$/ and $hash->{MODEL} eq "Perl") {
      return ($timer,"no timer");
    }
    ($result,$err) = DOIF_getTime($hash,$condition,$time,$trigger,$i,$days);
    return ($result,$err) if ($err);
    $hash->{helper}{last_timer}++;
  } else {
    return($timer,"no timer defined");
  }
  if (defined $end) {
    if ($end !~ /^\s*(\[.*\]|\{.*\}|\(.*\)|\+.*|[0-9][0-9]:.*|:[0-5][0-9])$/ and $hash->{MODEL} eq "Perl") {
      return ($timer,"no timer");
    }
    ($result,$err) = DOIF_getTime($hash,$condition,$end,$trigger,$i+1,$days);
    return ($result,$err) if ($err);
    $hash->{helper}{last_timer}++
  }
  if (defined $intervaltimer) {
    ($result,$err) = DOIF_getTime($hash,$condition,$intervaltimer,$trigger,$i+2,$days);
    return ($result,$err) if ($err);
    $hash->{helper}{last_timer}++
  }
  if (defined $end) {
    if ($days eq "") {
      $block='::DOIF_time($hash,'.$i.','.($i+1).',$wday,$hms)';
    } else {
      $block='::DOIF_time($hash,'.$i.','.($i+1).',$wday,$hms,"'.$days.'")';
    }
    $hash->{interval}{$i}=-1;
    $hash->{interval}{($i+1)}=$i;
    if (defined ($intervaltimer)) {
      $hash->{intervaltimer}{$i}=($i+2);
      $hash->{intervaltimer}{($i+1)}=($i+2);
      $hash->{intervalfunc}{($i+2)}=$block;
    }
  } else {
    if ($days eq "") {
      $block='::DOIF_time_once($hash,'.$i.',$wday)';
    } else {
      $block='::DOIF_time_once($hash,'.$i.',$wday,"'.$days.'")';
    }
  }
  if ($init_done) {
    DOIF_SetTimer ($hash,"DOIF_TimerTrigger",$i);
    DOIF_SetTimer ($hash,"DOIF_TimerTrigger",($i+1)) if (defined $end);
    DOIF_SetTimer ($hash,"DOIF_TimerTrigger",($i+2)) if (defined $intervaltimer);
  }
  return ($block,"");
}

sub DOIF_getTime {
  my ($hash,$condition,$time,$trigger,$nr,$days)=@_;
  my ($result,$err)=ReplaceAllReadingsDoIf($hash,$time,-3,0);
  return ($time,$err) if ($err);
  $time .=":00" if ($time =~ m/^[0-9][0-9]:[0-5][0-9]$/);
  $hash->{timer}{$nr}=0;
  $hash->{time}{$nr}=$time;
  $hash->{timeCond}{$nr}=$condition;
  $hash->{days}{$nr}=$days if ($days ne "");
  $hash->{timers}{$condition}.=" $nr " if ($trigger);
}



sub DOIF_time {
  my $ret=0;
  my ($hash,$b,$e,$wday,$hms,$days)=@_;
  $days="" if (!defined ($days));
  return 0 if (!defined $hash->{realtime}{$b});
  return 0 if (!defined $hash->{realtime}{$e});
  my $begin=$hash->{realtime}{$b};
  my $end=$hash->{realtime}{$e};
  my $err;
  return 0 if ($begin eq $end);
  ($days,$err)=ReplaceAllReadingsDoIf($hash,$days,-1,1);
  if ($err) {
    my $errmsg="error in days: $err";
    Log3 ($hash->{NAME},4 , "$hash->{NAME}: $errmsg");
    readingsSingleUpdate ($hash, "error", $errmsg,1);
    return 0;
  }
  $days=DOIF_weekdays($hash,$days);
  my $we=DOIF_we($wday);
  my $twe=DOIF_tomorrow_we($wday);
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
    return 1 if ($days eq "" or $days =~ /$wday/ or ($days =~ /7/ and $we) or ($days =~ /8/ and !$we) or ($days =~ /9/ and $twe) or ($days =~ /X/ and !$twe));
  }
  return 0;
}

sub DOIF_time_once {
  my ($hash,$nr,$wday,$days)=@_;
  $days="" if (!defined ($days));
  my $flag=$hash->{timer}{$nr};
  my $err;
  ($days,$err)=ReplaceAllReadingsDoIf($hash,$days,-1,1);
  if ($err) {
    my $errmsg="error in days: $err";
    Log3 ($hash->{NAME},4 , "$hash->{NAME}: $errmsg");
    readingsSingleUpdate ($hash, "error", $errmsg,1);
    return 0;
  }
  $days=DOIF_weekdays($hash,$days);
  my $we=DOIF_we($wday);
  my $twe=DOIF_tomorrow_we($wday);
  if ($flag) {
    return 1 if ($days eq "" or $days =~ /$wday/ or ($days =~ /7/ and $we) or ($days =~ /8/ and !$we) or ($days =~ /9/ and $twe) or ($days =~ /X/ and !$twe));
  }
  return 0;
}

sub DOIF_SetState($$$$$) {
  my ($hash,$nr,$subnr,$event,$last_error)=@_;
  my $pn=$hash->{NAME};
  my $cmdNr="";
  my $cmd="";
  my $err="";
  my $state=AttrVal($hash->{NAME},"state","");
  $state =~ s/\$SELF/$pn/g;
  $nr=ReadingsVal($pn,"cmd_nr",0)-1 if (!$event);
  if ($nr!=-1) {
    $cmdNr=$nr+1;
    my @cmdState;
    @cmdState=@{$hash->{attr}{cmdState}{$nr}} if (defined $hash->{attr}{cmdState}{$nr});
    if (defined $cmdState[$subnr]) {
      $cmd=EvalCmdStateDoIf($hash,$cmdState[$subnr]);
    } else {
      if (defined $hash->{do}{$nr}{$subnr+1}) {
        $cmd="cmd_".$cmdNr."_".($subnr+1);
      } else {
        if (defined ($cmdState[0])) {
          $cmd=EvalCmdStateDoIf($hash,$cmdState[0]);
        } else {
          $cmd="cmd_$cmdNr";
        }
      }
    }
  }
  if ($cmd =~ /^"(.*)"$/) {
    $cmd=$1;
  }
  delete $hash->{helper}{DOIF_eventa};
  delete $hash->{helper}{DOIF_eventas};
  readingsBeginUpdate($hash);
  if ($event) {
    push (@{$hash->{helper}{DOIF_eventas}},"cmd_nr: $cmdNr");
    readingsBulkUpdate($hash,"cmd_nr",$cmdNr);
    if (defined $hash->{do}{$nr}{1}) {
      readingsBulkUpdate($hash,"cmd_seqnr",$subnr+1);
      push (@{$hash->{helper}{DOIF_eventas}},("cmd_seqnr: ".($subnr+1)));
      readingsBulkUpdate($hash,"cmd",$cmdNr.".".($subnr+1));
    } else {
      delete ($defs{$hash->{NAME}}{READINGS}{cmd_seqnr});
      push (@{$hash->{helper}{DOIF_eventas}},"cmd: $cmdNr");
      readingsBulkUpdate($hash,"cmd",$cmdNr);
    }
    push (@{$hash->{helper}{DOIF_eventas}},"cmd_event: $event");
    readingsBulkUpdate($hash,"cmd_event",$event);
    if ($last_error) {
      push (@{$hash->{helper}{DOIF_eventas}},"error: $last_error");
      readingsBulkUpdate($hash,"error",$last_error);
    } else {
      delete ($defs{$hash->{NAME}}{READINGS}{error});
    }
  }

 if ($state) {
    my $stateblock='\['.$pn.'\]';
    $state =~ s/$stateblock/$cmd/g;
    $state=EvalCmdStateDoIf($hash,$state);
  } else {
    $state=$cmd;
  }
  if (defined($hash->{helper}{DOIF_eventas})) {
    @{$hash->{helper}{DOIF_eventa}}=@{$hash->{helper}{DOIF_eventas}};
  }
  push (@{$hash->{helper}{DOIF_eventas}},"state: $state");
  push (@{$hash->{helper}{DOIF_eventa}},"$state");
  readingsBulkUpdate($hash, "state", $state); 
  if (defined $hash->{uiState}{table}) {
    readingsEndUpdate ($hash, 0);
  } else {
    readingsEndUpdate ($hash, 1);
  }
}

sub DOIF_we($) {
  my ($wday)=@_;
  my $we=IsWe("",$wday);
  #my $we = (($wday==0 || $wday==6) ? 1 : 0);
  #if(!$we) {
  #  foreach my $h2we (split(",", AttrVal("global", "holiday2we", ""))) {
  #    if($h2we && Value($h2we)) {
  #      my ($a, $b) = ReplaceEventMap($h2we, [$h2we, Value($h2we)], 0);
  #      $we = 1 if($b ne "none");
  #    }
  #  }
  #}
  return $we;
}

sub DOIF_tomorrow_we($) {
  my ($wday)=@_;
  my $we=IsWe("tomorrow",$wday);
  #my $we = (($wday==5 || $wday==6) ? 1 : 0);
  #if(!$we) {
  #  foreach my $h2we (split(",", AttrVal("global", "holiday2we", ""))) {
  #    if($h2we && ReadingsVal($h2we,"tomorrow",0)) {
  #      my ($a, $b) = ReplaceEventMap($h2we, [$h2we, ReadingsVal($h2we,"tomorrow",0)], 0);
  #      $we = 1 if($b ne "none");
  #    }
  #  }
  #}
  return $we;
}

sub DOIF_CheckCond($$) {
  my ($hash,$condition) = @_;
  my $err="";
  my ($seconds, $microseconds) = gettimeofday();
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime($seconds);
  $month++;
  $year+=1900;
  my $week=strftime ('%V', localtime($seconds));
  my $hms = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
  my $hm = sprintf("%02d:%02d", $hour, $min);
  my $ymd = sprintf("%02d-%02d-%02d", $year, $month,$mday);
  my $md = sprintf("%02d-%02d",$month,$mday);
  my $dev;
  my $reading;
  my $internal;
  my $we=DOIF_we($wday);
  my $twe=DOIF_tomorrow_we($wday);
  my $eventa=$hash->{helper}{triggerEvents};
  my $device=$hash->{helper}{triggerDev};
  my $event=$hash->{helper}{event};
  my $events="";
  my $cmd=ReadingsVal($hash->{NAME},"cmd",0);
  if ($eventa) {
    $events=join(",",@{$eventa});
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
  }
  $cmdFromAnalyze="$hash->{NAME}: ".sprintf("warning in condition c%02d",($condition+1));
  $lastWarningMsg="";
  my $cur_hs=$hs;
  $hs=$hash;
  my $ret=$hash->{MODEL} eq "Perl" ? eval("package DOIF; $command"):eval ($command);  
  if($@){
    $@ =~ s/^(.*) at \(eval.*\)(.*)$/$1,$2/;
    $err = sprintf("condition c%02d",($condition+1)).": $@";
    $ret = 0;
  }
  if ($lastWarningMsg) {
    $lastWarningMsg =~ s/^(.*) at \(eval.*$/$1/;
    readingsSingleUpdate ($hash, "warning", sprintf("condition c%02d",($condition+1)).": $lastWarningMsg",1);
  } else {
    delete ($defs{$hash->{NAME}}{READINGS}{warning});
  }
  $lastWarningMsg="";
  $cmdFromAnalyze = undef;
  $hs=$cur_hs;
  return ($ret,$err);
}

sub DOIF_cmd ($$$$) {
  my ($hash,$nr,$subnr,$event)=@_;
  my $pn = $hash->{NAME};
  my $ret;
  my $cmd;
  my $err="";
  my $repeatnr;
  my $last_cmd=ReadingsVal($pn,"cmd_nr",0)-1;
  
  my ($seconds, $microseconds) = gettimeofday();
  
  if (defined $hash->{attr}{cmdpause}) {
    my @cmdpause=@{$hash->{attr}{cmdpause}};
    my $cmdpauseValue=EvalValueDoIf($hash,"cmdpause",$cmdpause[$nr]);
    if ($cmdpauseValue and $subnr==0) {
      return undef if ($seconds - time_str2num(ReadingsTimestamp($pn, "state", "1970-01-01 01:00:00")) < $cmdpauseValue);
    }
  }
  my @sleeptimer;
  if (defined $hash->{attr}{repeatcmd}) {
    @sleeptimer=@{$hash->{attr}{repeatcmd}};
  }
  if (defined $hash->{attr}{repeatsame}) {
   my @repeatsame=@{$hash->{attr}{repeatsame}};
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
  if (defined $hash->{attr}{waitsame}) {
    my @waitsame=@{$hash->{attr}{waitsame}};
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
    if (($sleeptimer[$nr])) {
      my $last_cond=ReadingsVal($pn,"cmd_nr",0)-1;
      if (DOIF_SetSleepTimer($hash,$last_cond,$nr,0,$event,-1,$sleeptimer[$nr])) {
        DOIF_cmd ($hash,$nr,$subnr,$event);
      }
    }
  }
  #delete $hash->{helper}{cur_cmd_nr};
  return undef;
}


sub CheckiTimerDoIf($$$) {
  my ($device,$itimer,$eventa)=@_;
  my $max = int(@{$eventa});
  my $found;
  return 1 if ($itimer =~ /\[$device(\]|,.+\])/);
  for (my $j = 0; $j < $max; $j++) {
    if ($eventa->[$j] =~ "^([^:]+): ") {
      $found = ($itimer =~ /\[$device:$1(\]|:.+\]|,.+\])/);
      if ($found) {
        return 1;
      }
    }
  }
  return 0;
}



sub CheckReadingDoIf($$$)
{
  my ($mydevice,$readings,$eventa)=@_;
  my $max = int(@{$eventa});
  my $s;
  my $found=0;
  my $device;
  my $reading;
 
  if (!defined $readings) {
    return 1;
  }
  if ($readings !~ / $mydevice:.+ /) {
    return 1;
  }
  
  foreach my $item (split(/ /,$readings)) {
    ($device,$reading)=(split(":",$item));
    if (defined $reading and $mydevice eq $device) {
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

sub CheckRegexpDoIf
{
  my ($hash,$type,$device,$id,$eventa,$eventas,$reading)=@_;
  my $nameExp;
  my $notifyExp;
  my $event;
  my @idlist;
  my @devlist;
  my @readinglist;
  
  return undef if (!defined $hash->{Regex}{$type});
  if (!AttrVal($hash->{NAME}, "checkReadingEvent", 1))  {
    if (defined $hash->{Regex}{$type}{$device}) {
      return 1;
    }
    @devlist=("");
  } else {
    @devlist=("$device","");
  }
  
  foreach my $dev (@devlist){
    if (defined $hash->{Regex}{$type}{$dev}) {
      @idlist=($id eq "") ? (keys %{$hash->{Regex}{$type}{$dev}}):($id);
      foreach my $id (@idlist) {
        @readinglist=(!defined $reading) ? (keys %{$hash->{Regex}{$type}{$dev}{$id}}):($reading);
        foreach my $i (@readinglist) {
          $nameExp="";
          $notifyExp="";
          if ($hash->{Regex}{$type}{$dev}{$id}{$i} =~ /([^\:]*):(.*)/) {
            $nameExp=$1;
            $notifyExp=$2;
          } else {
            $nameExp=$hash->{Regex}{$type}{$dev}{$id}{$i};
          }
          if ($nameExp eq "" or $device =~ /$nameExp/) {
            if ($notifyExp eq "") {
              return $i;
            }
            if (defined $eventa and defined $eventas) {
              my @events_temp;
              if (substr($i,0,1) eq '"') {
                @events_temp=@{$eventa};
              }
              else {
                @events_temp=@{$eventas};
              }
              #my $max=defined @events_temp ? int(@events_temp):0;
              my $s;
              my $found;
              for (my $j = 0; $j < @events_temp; $j++) {
                $s = $events_temp[$j];
                $s = "" if(!defined($s));
                $found = ($s =~ m/$notifyExp/);
                if ($found) {
                  return $i;
                }
              }
            }
          }
        }
      }
    }
  }
  return undef;
}

sub DOIF_block 
{
  my ($hash,$i)= @_;
  my $ret;
  my $err;
  my $blockname;
  ($ret,$err)=DOIF_CheckCond($hash,$i);
  if ($hash->{perlblock}{$i} =~ /^block_/) {
    $blockname=$hash->{perlblock}{$i};
  } else {
    $blockname="block_".$hash->{perlblock}{$i};
  }
  if ($err) {
    Log3 $hash->{NAME},4,"$hash->{NAME}: $err in perl block: $hash->{perlblock}{$i}" if ($ret != -1);
    readingsSingleUpdate ($hash, $blockname, $err,1);
  } else {
    readingsSingleUpdate ($hash, $blockname, "executed",0);
  }
}

sub DOIF_Perl_Trigger 
{
  my ($hash,$device)= @_;
  my $timerNr=-1;
  my $ret;
  my $err;
  my $event="$device";
  my $pn=$hash->{NAME};
  my $max_cond=keys %{$hash->{condition}};
  my $j;
  my @triggerEvents;
  for (my $i=0; $i<$max_cond;$i++) {
    if ($device eq "") {# timer
      my $found=0;
      if (defined ($hash->{timers}{$i})) {
        foreach $j (split(" ",$hash->{timers}{$i})){
          if ($hash->{timer}{$j} == 1) {
            $found=1;
            $timerNr=$j;
            last;
          }
        }
      }
      next if (!$found);
      $event="timer_".($timerNr+1);
      @triggerEvents=($event);
      $hash->{helper}{triggerEvents}=\@triggerEvents;
      $hash->{helper}{triggerEventsState}=\@triggerEvents;
      $hash->{helper}{triggerDev}="";
      $hash->{helper}{event}=$event;
    } else { #event
      next if (!defined (CheckRegexpDoIf($hash,"cond", $device,$i,$hash->{helper}{triggerEvents},$hash->{helper}{triggerEventsState})));
      $event="$device";
    }
    DOIF_block($hash,$i); 
  }
  return undef;
}

sub DOIF_Trigger 
{
  my ($hash,$device,$checkall)= @_;
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
      $hash->{helper}{triggerEventsState}=\@triggerEvents;
      $hash->{helper}{triggerDev}="";
      $hash->{helper}{event}=$event;
    } else { #event
      if (!defined (CheckRegexpDoIf($hash,"cond", $device,$i,$hash->{helper}{triggerEvents},$hash->{helper}{triggerEventsState}))) {
        if (!defined ($checkall) and AttrVal($pn, "checkall", 0) !~ "1|all|event") {
          next;
        } 
      }
      $event="$device";
    }
    if (($ret,$err)=DOIF_CheckCond($hash,$i)) {
      if ($err) {
        Log3 $hash->{NAME},4,"$hash->{NAME}: $err" if ($ret != -1);
        readingsSingleUpdate ($hash, "error", $err,1);
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

sub DOIF_Set_Filter 
{
  my ($hash) = @_;
  my @ndev=();
#  my @ddev=();
  push(@ndev,"global");
#  push(@ddev,"\^global\$");
  foreach my $type (keys %{$hash->{Regex}}) {
    foreach my $device (keys %{$hash->{Regex}{$type}}) {
      foreach my $id (keys %{$hash->{Regex}{$type}{$device}}) {
        foreach my $reading (keys %{$hash->{Regex}{$type}{$device}{$id}}) {
          my $devreg=$hash->{Regex}{$type}{$device}{$id}{$reading};
          my($regdev)=split(/:/,$devreg);
          my $item;
          if ($regdev =~  /^\^([\w.]*)\$$/) {
            $item=$1;
          } else {
            $item='.*('.$regdev.').*';
          }
          push (@ndev,$item);
 #         push (@ddev,$regdev);
        }
      }
    }
  }
  my %h;
  %h = map { $_ => 1 } @ndev;
  @ndev = keys %h; # remove duplicates
  $hash->{helper}{NOTIFYDEV} = join(",", @ndev);
  setNotifyDev ($hash,$hash->{helper}{NOTIFYDEV});
  

 # %h = map { $_ => 1 } @ddev;
 # @ddev = keys %h; # remove duplicates
 # $hash->{helper}{DEVFILTER} = join("|", @ddev);
 # $hash->{DOIFDEV}=$hash->{helper}{DEVFILTER};
}

sub
DOIF_Notify($$)
{
  my ($hash, $dev) = @_;
  my $pn = $hash->{NAME};
  #return "" if($attr{$pn} && $attr{$pn}{disable});
  #return "" if (!$dev->{NAME});
  my $device;
  my $reading;
  my $internal;
  my $ret;
  my $err;
  my $eventa;
  my $eventas;
  
 ## print("DOIF $pn aufgerufen $dev->{NAME}\n");
 # if (!defined($hash->{helper}{DEVFILTER})) {
 # if (!defined($hash->{helper}{NOTIFYDEV})) {
 #   return "";
 # }
 #   elsif ($dev->{NAME} !~ /$hash->{helper}{DEVFILTER}/) {
 #   return "";
 # }
  
  $eventa = deviceEvents($dev, AttrVal($pn, "addStateEvent", 0));
  $eventas = deviceEvents($dev, 1);
  delete ($hash->{helper}{DOIF_eventas});
  delete ($hash->{helper}{DOIF_eventa});
  
  if ($dev->{NAME} eq "global" and (EventCheckDoif($dev->{NAME},"global",$eventa,'^INITIALIZED$') or EventCheckDoif($dev->{NAME},"global",$eventa,'^REREADCFG$')))
  {
    $hash->{helper}{globalinit}=1;
     # delete old timer-readings
    foreach my $key (keys %{$defs{$hash->{NAME}}{READINGS}}) {
      delete $defs{$hash->{NAME}}{READINGS}{$key} if ($key =~ "^timer_");
    }
    delete ($defs{$hash->{NAME}}{READINGS}{wait_timer});
    if ($hash->{helper}{last_timer} > 0){
      for (my $j=0; $j<$hash->{helper}{last_timer};$j++) {
        DOIF_SetTimer ($hash,"DOIF_TimerTrigger",$j);
      }
    }
     
    for my $attr ("DOIF_Readings","event_Readings") {
      my $defs=AttrVal($pn, $attr, 0);
      if ($defs) {
        my ($def,$err)=addDOIF_Readings($hash,$defs,$attr);
        if ($err) {
          Log3 ($pn,3,"$pn: error in $def, $err") ;
        } else {
          foreach my $reading (keys %{$hash->{$attr}}) {
            setDOIF_Reading ($hash,$reading,"",$attr,"","","");
          }
        }
      }
    }
    
    if (AttrVal($pn,"initialize",0) and !AttrVal($pn,"disable",0)) {
      readingsBeginUpdate($hash);
      readingsBulkUpdate ($hash,"state",AttrVal($pn,"initialize",0));
      readingsBulkUpdate ($hash,"cmd_nr","0");
      readingsBulkUpdate ($hash,"cmd",0);
      readingsEndUpdate($hash, 0);
    }
     
    for (my $i=0; $i < keys %{$hash->{perlblock}};$i++) {  
      if ($hash->{perlblock}{$i} eq "init" or $hash->{perlblock}{$i} =~ "^init_" ) {
        if (($ret,$err)=DOIF_CheckCond($hash,$i)) {
          if ($err) {
            Log3 $hash->{NAME},4,"$hash->{NAME}: $err in perl block $hash->{perlblock}{$i}" if ($ret != -1);
            readingsSingleUpdate ($hash, "block_$hash->{perlblock}{$i}", $err,0);
          } else {
            readingsSingleUpdate ($hash, "block_$hash->{perlblock}{$i}", "executed",0);
          }
        }
      }
    }

  
    my $startup=AttrVal($pn, "startup", 0);
    if ($startup  and !AttrVal($pn,"disable",0)) {
      $startup =~ s/\$SELF/$pn/g;
      my ($cmd,$err)=ParseCommandsDoIf($hash,$startup,1);
      Log3 ($pn,3,"$pn: error in startup: $err") if ($err);
    }
    
    my $uiTable=AttrVal($pn, "uiTable", 0);
    if ($uiTable){
      my $err=DOIF_uiTable_def($hash,$uiTable,"uiTable");
      Log3 ($pn,3,"$pn: error in uiTable: $err") if ($err);
    }
    
    my $uiState=AttrVal($pn, "uiState", 0);
    if ($uiState){
      my $err=DOIF_uiTable_def($hash,$uiState,"uiState");
      Log3 ($pn,3,"$pn: error in uiState: $err") if ($err);
    }
    DOIF_Set_Filter ($hash);
  }
  
  return "" if (!$hash->{helper}{globalinit});
  
  if ($dev->{NAME} eq "global" and (EventCheckDoif($dev->{NAME},"global",$eventa,'^SAVE$'))) {
    DOIF_save_readings($hash);
  }
  
  #return "" if (!$hash->{itimer}{all} and !$hash->{devices}{all} and !keys %{$hash->{Regex}});
  
  #if (($hash->{itimer}{all}) and $hash->{itimer}{all} =~ / $dev->{NAME} /) {
  if (defined CheckRegexpDoIf($hash,"itimer",$dev->{NAME},"itimer",$eventa,$eventas)) {
    for (my $j=0; $j<$hash->{helper}{last_timer};$j++) {
      if (CheckiTimerDoIf ($dev->{NAME},$hash->{time}{$j},$eventas)) {
        DOIF_SetTimer ($hash,"DOIF_TimerTrigger",$j);
        if (defined $hash->{intervaltimer}{$j}) {
          DOIF_SetTimer($hash,"DOIF_TimerTrigger",$hash->{intervaltimer}{$j});
        } 
      }
    }
  }

  return "" if (defined $hash->{helper}{cur_cmd_nr} and $hash->{MODEL} ne "Perl");
  return "" if (ReadingsVal($pn,"mode","") eq "disabled");
  
  $ret=0;
#  if (defined $hash->{Regex}{"event_Readings"}) {
#    foreach $device ("$dev->{NAME}","") {
#      if (defined $hash->{Regex}{"event_Readings"}{$device}) {
#        foreach my $reading (keys %{$hash->{Regex}{"event_Readings"}{$device}}) {
#          my $readingregex=CheckRegexpDoIf($hash,"event_Readings",$dev->{NAME},$reading,$eventa,$eventas);
#    	   if (defined($readingregex)) {
#             setDOIF_Reading($hash,$reading,$readingregex,"event_Readings",$eventa, $eventas,$dev->{NAME});
#		   }
#        }
#      }
#    }
#  }
  
  if (defined $hash->{Regex}{"accu"}{"$dev->{NAME}"}) {
    my $device=$dev->{NAME};
    foreach my $reading (keys %{$hash->{Regex}{"accu"}{$device}{"accu"}}) {
      my $readingregex=CheckRegexpDoIf($hash,"accu",$dev->{NAME},"accu",$eventa,$eventas,$reading);
      accu_setValue($hash,$device,$readingregex) if (defined $readingregex);
    }
  }
  
  if (defined $hash->{Regex}{"collect"}{"$dev->{NAME}"}) {
    my $device=$dev->{NAME};
    foreach my $reading (keys %{$hash->{Regex}{"collect"}{$device}{"collect"}}) {
      my $readingregex=CheckRegexpDoIf($hash,"collect",$dev->{NAME},"collect",$eventa,$eventas,$reading);
      if (defined $readingregex) {
        foreach my $hours (keys %{$hash->{collect}{"$device $readingregex"}}){
          DOIF_setValue_collect($hash,\%{$hash->{collect}{"$device $readingregex"}{$hours}});
        }
      }
    }
  }
  
  foreach my $bartype ("bar","barAvg") {
    if (defined $hash->{Regex}{$bartype}{"$dev->{NAME}"}) {
      my $device=$dev->{NAME};
      foreach my $reading (keys %{$hash->{Regex}{$bartype}{$device}{$bartype}}) {
        my $readingregex=CheckRegexpDoIf($hash,$bartype,$dev->{NAME},$bartype,$eventa,$eventas,$reading);
        if (defined $readingregex) {
          foreach my $period (keys %{$hash->{$bartype}{"$device $readingregex"}}){
            DOIF_setValue_bar($hash,\%{$hash->{$bartype}{"$device $readingregex"}{$period}},1);
          }
        }
      }
    }
  }

  if (defined CheckRegexpDoIf($hash,"cond",$dev->{NAME},"",$eventa,$eventas)) {
    $hash->{helper}{cur_cmd_nr}="Trigger  $dev->{NAME}" if (AttrVal($hash->{NAME},"selftrigger","") ne "all");
    $hash->{helper}{triggerEvents}=$eventa;
    $hash->{helper}{triggerEventsState}=$eventas;
    $hash->{helper}{triggerDev}=$dev->{NAME};
    $hash->{helper}{event}=join(",",@{$eventa});

    if ($hash->{readings}{all}) {
      foreach my $item (split(/ /,$hash->{readings}{all})) {
        ($device,$reading)=(split(":",$item));
        if ($item and $device eq $dev->{NAME} and defined ($defs{$device}{READINGS}{$reading})) {
          if (!AttrVal($pn, "checkReadingEvent", 1) or CheckReadingDoIf ($dev->{NAME}," $item ",$eventas)) {
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
      if ($hash->{trigger}{all} =~ / $dev->{NAME} /) {
        readingsSingleUpdate ($hash, "e_".$dev->{NAME}."_events",join(",",@{$eventa}),0);
      }
    }
    readingsSingleUpdate ($hash, "Device",$dev->{NAME},0) if ($dev->{NAME} ne $hash->{NAME});
    $ret=$hash->{MODEL} eq "Perl" ? DOIF_Perl_Trigger($hash,$dev->{NAME}) : DOIF_Trigger($hash,$dev->{NAME});
  }
  
  if ((defined CheckRegexpDoIf($hash,"STATE",$dev->{NAME},"STATE",$eventa,$eventas)) and !$ret) {
    $hash->{helper}{triggerEvents}=$eventa;
    $hash->{helper}{triggerEventsState}=$eventas;
    $hash->{helper}{triggerDev}=$dev->{NAME};
    $hash->{helper}{event}=join(",",@{$eventa});
    DOIF_SetState($hash,"",0,"","");
  }
  
  
  delete $hash->{helper}{cur_cmd_nr};
  
   
  foreach my $table ("uiTable","uiState") {
    if (defined $hash->{Regex}{$table}) {
      foreach $device ("$dev->{NAME}","") {
        if (defined $hash->{Regex}{$table}{$device}) {
          foreach my $doifId (keys %{$hash->{Regex}{$table}{$device}}) {
            my $readingregex=CheckRegexpDoIf($hash,$table,$dev->{NAME},$doifId,$eventa,$eventas);
            DOIF_UpdateCell($hash,$doifId,$hash->{NAME},$readingregex) if (defined($readingregex));
          }
        }
      }
      if (defined ($hash->{helper}{DOIF_eventas})) {# $SELF events
        foreach my $doifId (keys %{$hash->{Regex}{$table}{$hash->{NAME}}}) {
          my $readingregex=CheckRegexpDoIf($hash,$table,$hash->{NAME},$doifId,$hash->{helper}{DOIF_eventa},$hash->{helper}{DOIF_eventas});
          DOIF_UpdateCell($hash,$doifId,$hash->{NAME},$readingregex) if (defined($readingregex));
        }
      }
    }
  }
  
  foreach my $readings ("DOIF_Readings","event_Readings") {
    if (defined $hash->{Regex}{$readings}) {
      foreach $device ("$dev->{NAME}","") {
        if (defined $hash->{Regex}{$readings}{$device}) {
          foreach my $reading (keys %{$hash->{Regex}{$readings}{$device}}) {
            my $readingregex=CheckRegexpDoIf($hash,$readings,$dev->{NAME},$reading,$eventa,$eventas);
            setDOIF_Reading($hash,$reading,$readingregex,$readings,$eventa, $eventas,$dev->{NAME}) if (defined($readingregex));
          }
        }
      }
      if (defined ($hash->{helper}{DOIF_eventas})) {# $SELF events
        foreach my $reading (keys %{$hash->{Regex}{$readings}{$hash->{NAME}}}) {
          my $readingregex=CheckRegexpDoIf($hash,$readings,$hash->{NAME},$reading,$hash->{helper}{DOIF_eventa},$hash->{helper}{DOIF_eventas});
          setDOIF_Reading($hash,$reading,$readingregex,$readings,$eventa, $eventas,$dev->{NAME}) if (defined($readingregex));
        }
      }
    }
  }

  if (defined $hash->{helper}{DOIF_Readings_events}) {# only for DOIF_Readings
    if ($dev->{NAME} ne $hash->{NAME}) {
      @{$hash->{CHANGED}}=@{$hash->{helper}{DOIF_Readings_events}};
      @{$hash->{CHANGEDWITHSTATE}}=@{$hash->{helper}{DOIF_Readings_eventsState}};
      delete $hash->{helper}{DOIF_Readings_events};
      delete $hash->{helper}{DOIF_Readings_eventsState};
      DOIF_Notify($hash,$hash);
    }
  }
  return undef;
}

sub DOIF_TimerTrigger ($) {
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
    if (defined $hash->{localtime}{$j} and $hash->{localtime}{$j} == $localtime) {
      if (defined ($hash->{interval}{$j})) {
        if ($hash->{interval}{$j} != -1) {
          if (defined $hash->{realtime}{$j} eq $hash->{realtime}{$hash->{interval}{$j}}) {
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
  $ret=($hash->{MODEL} eq "Perl" ? DOIF_Perl_Trigger($hash,"") : DOIF_Trigger($hash,"")) if (ReadingsVal($pn,"mode","") ne "disabled");
  for (my $j=0; $j<$hash->{helper}{last_timer};$j++) {
    $hash->{timer}{$j}=0;
    if (defined $hash->{localtime}{$j} and $hash->{localtime}{$j} == $localtime) {
      if (!AttrVal($hash->{NAME},"disable","")) {
        if (defined ($hash->{interval}{$j})) {
          if ($hash->{interval}{$j} != -1) {
            DOIF_SetTimer($hash,"DOIF_TimerTrigger",$hash->{interval}{$j});
            DOIF_SetTimer($hash,"DOIF_TimerTrigger",$j,1);
            #if (defined $hash->{intervaltimer}{$j}) {
            #  DOIF_DelInternalTimer($hash, $hash->{intervaltimer}{$j});
            #}
          } else {
            if (defined $hash->{intervaltimer}{$j}) {
              DOIF_SetTimer($hash,"DOIF_TimerTrigger",$hash->{intervaltimer}{$j});
            } 
          }
        } else {
          DOIF_SetTimer($hash,"DOIF_TimerTrigger",$j,1);
        }
      }
    }
  }
  delete ($hash->{helper}{cur_cmd_nr});
  return undef;
  #return($ret);
}

sub DOIF_DelInternalTimer {
  my ($hash, $nr) = @_;
  RemoveInternalTimer(\$hash->{triggertime}{$hash->{localtime}{$nr}});
  delete ($hash->{triggertime}{$hash->{localtime}{$nr}});
  my $cond=$hash->{timeCond}{$nr};
  my $timernr=sprintf("timer_%02d_c%02d",($nr+1),($cond+1));
  delete ($defs{$hash->{NAME}}{READINGS}{$timernr});
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
  return ($err, ($rel and !defined ($align)), $second,defined ($align));
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
  my $align;
  my $alignInCalc;
  if ($block=~ m/^\+\[([0-9]+)\]:([0-5][0-9])$/) {
    ($err,$rel,$block,$align)=DOIF_DetTime($hash,$block);
    return ($block,$err,$rel,$align);
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
    ($err,$rel,$block,$align)=DOIF_DetTime($hash, $block);
    $rel=1 if ($relGlobal);
    return ($block,$err,$rel,$align);
  }
  $tailBlock=$block;
  while ($tailBlock ne "") {
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]');
    return ($block,$err) if ($err);
    if ($block ne "") {
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
      ($err,$rel,$block,$alignInCalc)=DOIF_DetTime($hash,$block);
      $align=$alignInCalc if ($alignInCalc);
      return ($block,$err) if ($err);
    }
    $cmd.=$beginning.$block;
  }
  $ret = eval $cmd;
  return($cmd." ",$@) if ($@);
  return ($ret,"null is not allowed on a relative time",$relGlobal) if ($ret == 0 and $relGlobal);
  return ($ret,"",$relGlobal,$align);
}

sub DOIF_SetTimer {
  my ($hash, $func, $nr,$next_day) = @_;
  my $timeStr=$hash->{time}{$nr};
  my $cond=$hash->{timeCond}{$nr};
  my $next_time;
  if (defined ($hash->{localtime}{$nr})) {
    my $old_lt=$hash->{localtime}{$nr};
    my $found=0;
    delete ($hash->{localtime}{$nr});
    delete ($hash->{realtime}{$nr});
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
  my ($second,$err, $rel,$align)=DOIF_CalcTime($hash,$timeStr);
  my $timernr=sprintf("timer_%02d_c%02d",($nr+1),($cond+1));
  if ($err)
  {
      readingsSingleUpdate ($hash,$timernr,"error: ".$err,AttrVal($hash->{NAME},"timerevent","")?1:0);
      Log3 $hash->{NAME},4 , "$hash->{NAME} ".$timernr." error: ".$err;
      #RemoveInternalTimer($timer);
      #$hash->{realtime}{$nr} = "00:00:00" if (!defined $hash->{realtime}{$nr});
      return $err;
  }

  if ($second < 0) {
    if ($rel) {
      readingsSingleUpdate ($hash,$timernr,"time offset: $second, negativ offset is not allowed",AttrVal($hash->{NAME},"timerevent","")?1:0);
      return($timernr,"time offset: $second, negativ offset is not allowed");
    } else {
      readingsSingleUpdate ($hash,$timernr,"time in seconds: $second, negative times are not allowed",AttrVal($hash->{NAME},"timerevent","")?1:0);
      return($timernr,"time in seconds: $second, negative times are not allowed");
    }
  }

  my ($now, $microseconds) = gettimeofday();
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime($now);
  my $hms_now = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
  my $wday_now = $wday;
  my $isdst_now=$isdst;

  my $sec_today = $hour*3600+$min*60+$sec;
  my $midnight = $now-$sec_today;
  if ($rel) {
    $next_time =$now+$second;
  } else {
    $next_time = $midnight+$second;
  }

  if ($second <= $sec_today and !$rel or defined ($next_day) and !$rel and $second < 86400 and !$align) {
    $next_time+=86400;
  }
  ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime($next_time);
  if ($isdst_now != $isdst and !$rel) {
    if ($isdst_now == 1) {
      $next_time+=3600 if ($isdst == 0);
    } else {
      $next_time-=3600 if ($second>=3*3600 or $second <= $sec_today and $second<2*3600);
    }
  }
  if (defined ($hash->{intervalfunc}{$nr})) {
    my $hms  = $hms_now;
    $wday = $wday_now;
    my $cond=$hash->{timeCond}{$nr};
    my $timernr=sprintf("timer_%02d_c%02d",($nr+1),($cond+1));
    if (!eval ($hash->{intervalfunc}{$nr})) {
      delete ($defs{$hash->{NAME}}{READINGS}{$timernr});
      return undef;
    } 
    ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime($next_time);
    $hms = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
    if (!eval ($hash->{intervalfunc}{$nr})) {
      delete ($defs{$hash->{NAME}}{READINGS}{$timernr});
      return undef;
    }
  }
  my $next_time_str=strftime("%d.%m.%Y %H:%M:%S",localtime($next_time));
  $next_time_str.="\|".$hash->{days}{$nr} if (defined ($hash->{days}{$nr}));
  readingsSingleUpdate ($hash,$timernr,$next_time_str,AttrVal($hash->{NAME},"timerevent","")?1:0);
  $hash->{realtime}{$nr}=strftime("%H:%M:%S",localtime($next_time));
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
  
  my @waitdel;
  @waitdel=@{$hash->{attr}{waitdel}{$nr}} if (defined $hash->{attr}{waitdel}{$nr});
  my $err;

  if ($sleeptimer != -1 and (($sleeptimer != $nr or AttrVal($pn,"do","") eq "resetwait") or ($sleeptimer == $nr and $waitdel[$subnr]))) {
    RemoveInternalTimer($hash);
    #delete ($defs{$hash->{NAME}}{READINGS}{wait_timer});
    readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
    $hash->{helper}{sleeptimer}=-1;
    $subnr=$hash->{helper}{sleepsubtimer} if ($hash->{helper}{sleepsubtimer}!=-1 and $sleeptimer == $nr);
    return 0 if ($sleeptimer == $nr and $waitdel[$subnr]);
  }

  if ($timerNr >= 0 and !AttrVal($pn,"timerWithWait","")) {#Timer
    if ($last_cond != $nr or AttrVal($pn,"do","") eq "always" or AttrVal($pn,"do","") eq "resetwait" or AttrVal($pn,"repeatsame","")) {
      return 1;
    } else {
      return 0;
    }
  }
  if ($hash->{helper}{sleeptimer} == -1 and ($last_cond != $nr or $subnr > 0
      or AttrVal($pn,"do","") eq "always"
      or AttrVal($pn,"do","") eq "resetwait"
      or AttrVal($pn,"repeatsame","")
      or $repeatcmd)) {
    my $sleeptime=0;
    if ($repeatcmd) {
      $sleeptime=$repeatcmd;
    } else {
      my @sleeptimer;
      @sleeptimer=@{$hash->{attr}{wait}{$nr}} if (defined $hash->{attr}{wait}{$nr});
      if ($waitdel[$subnr]) {
        $sleeptime = $waitdel[$subnr];
      } else {
        if ($sleeptimer[$subnr]) {
          $sleeptime=$sleeptimer[$subnr];
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
    } elsif ($repeatcmd){
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
  my $pn = $hash->{NAME};
  
  $hash->{helper}{cur_cmd_nr}="wait_timer" if (!AttrVal($hash->{NAME},"selftrigger",""));
  $hash->{helper}{triggerEvents}=$hash->{helper}{timerevents};
  $hash->{helper}{triggerEventsState}=$hash->{helper}{timereventsState};
  $hash->{helper}{event}=$hash->{helper}{timerevent};
  $hash->{helper}{triggerDev}=$hash->{helper}{timerdev};
  readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
  $hash->{helper}{sleeptimer}=-1;
  $hash->{helper}{sleepsubtimer}=-1;
  if (ReadingsVal($pn,"mode","") ne "disabled") {
    DOIF_cmd ($hash,$sleeptimer,$sleepsubtimer,$hash->{helper}{sleepdevice});
  }
  delete $hash->{helper}{cur_cmd_nr};
  return undef;
}

sub DOIF_Perlblock 
{
  my ($hash,$table,$tail,$subs) =@_;
  my ($beginning,$perlblock,$err,$i);
  $i=0;
  while($tail =~ /(?:^|\n)\s*([\w\.\/\-]*)\s*\{/g) {
    my $blockname=$1;
    ($beginning,$perlblock,$err,$tail)=GetBlockDoIf($tail,'[\{\}]');
    if ($err) {
        return ("Perlblck: $err",$perlblock);
    } elsif (defined $subs) {
      if ($blockname eq "subs") {
        $perlblock ="no warnings 'redefine';package DOIF;".$perlblock;
        eval ($perlblock);
        if ($@) {
          return ("error in defs block",$@);
        }
        return("","");
      }
    } elsif ($blockname ne "subs") {
      ($perlblock,$err)=ReplaceAllReadingsDoIf($hash,$perlblock,$i,0);
      return ($perlblock,$err) if ($err);
      $hash->{condition}{$i}=$perlblock;
      $hash->{perlblock}{$i}=$blockname ? $blockname:sprintf("block_%02d",($i+1));
      #if ($blockname eq "init") {
      #  $hash->{perlblock}{init}=$i;
      #}
      $i++;
    }
  }
  return ("","");
}

sub
CmdDoIfPerl($$)
{
  my ($hash, $tail) = @_;
  my $perlblock="";
  my $beginning;
  my $ret;
  my $err="";
  my $i=0;
  my $cur_hs=$hs;
  $hs=$hash;
  my $msg;
  
  
  #def modify

  if ($init_done)
  {
    DOIF_delTimer($hash);
    DOIF_delAll ($hash);
    readingsBeginUpdate($hash);
    readingsBulkUpdate ($hash,"mode","enabled");
    readingsEndUpdate($hash, 1);
    readingsSingleUpdate($hash,"state","initialized",0);
    $hash->{helper}{globalinit}=1;
    #foreach my $key (keys %{$attr{$hash->{NAME}}}) {
    #  if ($key ne "disable" and AttrVal($hash->{NAME},$key,"")) {
    #    DOIF_Attr ("set",$hash->{NAME},$key,AttrVal($hash->{NAME},$key,""));
    #  }
    #}
  }

  $hash->{helper}{last_timer}=0;
  $hash->{helper}{sleeptimer}=-1;
 
  if ($tail =~ /^ *$/) {
    $hs=$cur_hs;
    return("","");
  }
  $tail =~ s/\$VAR/\$hash->{var}/g;
  $tail =~ s/\$_(\w+)/\$hash->\{var\}\{$1\}/g;
  $tail =~ s/\$SELF/$hash->{NAME}/g;

  ($err,$msg)=DOIF_Perlblock($hash,"defs",$tail,1);
  return ($msg,$err) if ($err);

  ($err,$tail)=DOIF_DEF_TPL($hash,"defs",$tail);
  if ($err) {
    $hs=$cur_hs;
    return ($tail,$err);
  }
  ($err,$tail)=DOIF_FOR($hash,"defs",$tail);
  if ($err) {
    $hs=$cur_hs;
    return ($tail,$err);
  }
 
  ($err,$tail)=DOIF_TPL($hash,"defs",$tail);
  if ($err) {
    $hs=$cur_hs;
    return ($tail,$err);
  }

  ($err,$msg)=DOIF_Perlblock($hash,"defs",$tail);
  if ($err) {
    $hs=$cur_hs;
    return ($tail,$err);
  }

#  while ($tail ne "") {
#    ($beginning,$perlblock,$err,$tail)=GetBlockDoIf($tail,'[\{\}]');
#    return ($perlblock,$err) if ($err);
#    next if (!$perlblock);
#    if ($beginning =~ /(\w*)[\s]*$/) {
#      my $blockname=$1;
#      if ($blockname eq "subs") {
#        $perlblock =~ s/\$SELF/$hash->{NAME}/g;
#        $perlblock ="no warnings 'redefine';package DOIF;".$perlblock;
#        eval ($perlblock);
#        if ($@) {
#          return ("error in defs block",$@);
#        }
#        next;
#      }
#      ($perlblock,$err)=ReplaceAllReadingsDoIf($hash,$perlblock,$i,0);
#      return ($perlblock,$err) if ($err);
#      $hash->{condition}{$i}=$perlblock;
#      $hash->{perlblock}{$i}=$blockname ? $blockname:sprintf("block_%02d",($i+1));
#      if ($blockname eq "init") {
#        $hash->{perlblock}{init}=$i;
#      }
#    }
#    $i++;
#  }
  if ($init_done) {
    for (my $i=0; $i < keys %{$hash->{perlblock}};$i++) {  
      if ($hash->{perlblock}{$i} eq "init" or $hash->{perlblock}{$i} =~ "^init_" ) {
        if (($ret,$err)=DOIF_CheckCond($hash,$i)) {
          if ($err) {
            Log3 $hash->{NAME},4,"$hash->{NAME}: $err in perl block $hash->{perlblock}{$i}" if ($ret != -1);
            readingsSingleUpdate ($hash, "block_$hash->{perlblock}{$i}", $err,0);
          } else {
            readingsSingleUpdate ($hash, "block_$hash->{perlblock}{$i}", "executed",0);
          }
        }
      }
    }
  }
  if ($init_done) {
    foreach my $key (keys %{$attr{$hash->{NAME}}}) {
      if ($key ne "disable" and AttrVal($hash->{NAME},$key,"")) {
        DOIF_Attr ("set",$hash->{NAME},$key,AttrVal($hash->{NAME},$key,""));
      }
    }
  }
  $hs=$cur_hs;
  return("","")
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
  
  #def modify
  if ($init_done)
  {
    DOIF_delTimer($hash);
    DOIF_delAll ($hash);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"cmd",0);
    readingsBulkUpdate($hash,"state","initialized");
    readingsBulkUpdate ($hash,"mode","enabled");
    readingsEndUpdate($hash, 1);
    $hash->{helper}{globalinit}=1;
    
    #foreach my $key (keys %{$attr{$hash->{NAME}}}) {
    #  if ($key ne "disable" and AttrVal($hash->{NAME},$key,"")) {
    #    DOIF_Attr ("set",$hash->{NAME},$key,AttrVal($hash->{NAME},$key,""));
    #  }
    #}
  }

  $hash->{helper}{last_timer}=0;
  $hash->{helper}{sleeptimer}=-1;
  

  if ($tail !~ /^ *$/) {
    $tail =~ s/\n/ /g;
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
      while ($tail =~ /^\s*(\(|\{)/) {
      if ($tail =~ /^\s*\(/) {
          ($beginning,$if_cmd_ori,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
          return ($if_cmd_ori,$err) if ($err);
      } elsif ($tail =~ /^\s*\{/) {
        ($beginning,$if_cmd_ori,$err,$tail)=GetBlockDoIf($tail,'[\{\}]');
          return ($if_cmd_ori,$err) if ($err);
      $if_cmd_ori="{".$if_cmd_ori."}";
      }
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
      while ($tail =~ /^\s*(\(|\{)/) {
        if ($tail =~ /^\s*\(/) {
          ($beginning,$else_cmd_ori,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
           return ($else_cmd_ori,$err) if ($err);
        } elsif ($tail =~ /^\s*\{/) { 
          ($beginning,$else_cmd_ori,$err,$tail)=GetBlockDoIf($tail,'[\{\}]');
           return ($else_cmd_ori,$err) if ($err);
           $else_cmd_ori="{".$else_cmd_ori."}";
        }  
        ($else_cmd,$err)=ParseCommandsDoIf($hash,$else_cmd_ori,0);
        return ($else_cmd,$err) if ($err);
        $hash->{do}{$last_do+1}{$j++}=$else_cmd_ori;
      }
      $hash->{do}{$last_do+1}{0}=$else_cmd_ori if ($j==0); #doelse without brackets
    }
  }
  if ($init_done) {
    foreach my $key (keys %{$attr{$hash->{NAME}}}) {
      if ($key ne "disable" and AttrVal($hash->{NAME},$key,"")) {
        DOIF_Attr ("set",$hash->{NAME},$key,AttrVal($hash->{NAME},$key,""));
      }
    }
  }
  return("","")
}

sub
DOIF_Define($$$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $cmd) = split(/[\s]+/, $def, 3);
  return undef if (AttrVal($hash->{NAME},"disable",""));
  my $err;
  my $msg;
  my $cur_hs=$hs;
  $hs=$hash;
  if (AnalyzeCommandChain(undef,"version 98_DOIF.pm noheader") =~ "^98_DOIF.pm (.*)Z") {
    $hash->{VERSION}=$1;
  }

  if (!$cmd) {
    $cmd="";
    $defs{$hash->{NAME}}{DEF}="##";
  } else {
    $cmd =~ s/(##.*\n)|(##.*$)/ /g;
    $cmd =~ s/\$SELF/$hash->{NAME}/g;
  }

  if ($cmd =~ /^\s*(\(|$)/) {
    $hash->{MODEL}="FHEM";
    ($msg,$err)=CmdDoIf($hash,$cmd);
    #delete $defs{$hash->{NAME}}{".AttrList"};
    setDevAttrList($hash->{NAME});
  } else {
    $hash->{MODEL}="Perl";
    #$defs{$hash->{NAME}}{".AttrList"}  = "disable:0,1 loglevel:0,1,2,3,4,5,6 startup state initialize notexist checkReadingEvent:1,0 addStateEvent:1,0 weekdays setList:textField-long readingList DOIF_Readings:textField-long uiTable:textField-long ".$readingFnAttributes;
    setDevAttrList($hash->{NAME},"disable:0,1 loglevel:0,1,2,3,4,5,6 notexist checkReadingEvent:0,1 addStateEvent:1,0 weekdays setList:textField-long readingList DOIF_Readings:textField-long event_Readings:textField-long uiState:textField-long uiTable:textField-long ".$readingFnAttributes);
    ($msg,$err)=CmdDoIfPerl($hash,$cmd);
  }  
  if ($err ne "") {
    $msg=$cmd if (!$msg);
    my $errmsg="$name $type: $err: $msg";
    $hs=$cur_hs;
    return $errmsg;
  } else {
    DOIF_Set_Filter ($hash);
    $hs=$cur_hs;
    return undef;
  }
}

#################################

sub
DOIF_Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};
  my $pn=$hash->{NAME};
  my $ret="";
  my $cur_hs=$hs;
  $hs=$hash;
  
  if (($a[0] eq "set" and $a[2] eq "disable" and ($a[3] eq "0")) or (($a[0] eq "del" and $a[2] eq "disable")))
  {
    my $cmd = $defs{$hash->{NAME}}{DEF};
    my $msg;
    my $err;
    setDisableNotifyFn($hash,0);
    if (!$cmd) {
      $cmd="";
      $defs{$hash->{NAME}}{DEF}="##";
    } else {
      $cmd =~ s/(##.*\n)|(##.*$)/ /g;
      $cmd =~ s/\$SELF/$hash->{NAME}/g;
    }

    if ($cmd =~ /^\s*(\(|$)/) {
      $hash->{MODEL}="FHEM";  
      ($msg,$err)=CmdDoIf($hash,$cmd);
    } else {
      $hash->{MODEL}="Perl";
      ($msg,$err)=CmdDoIfPerl($hash,$cmd);
    }  

    if ($err ne "") {
      $msg=$cmd if (!$msg);
      $hs=$cur_hs;
      return ("$err: $msg");
    }
  } elsif($a[0] eq "set" and $a[2] eq "disable" and $a[3] eq "1") {
    DOIF_delTimer($hash);
    DOIF_delAll ($hash);
    setDisableNotifyFn($hash,1);
    readingsBeginUpdate($hash);
    #if ($hash->{MODEL} ne "Perl") {
    #  readingsBulkUpdate ($hash, "state", "deactivated");
    #}
    readingsBulkUpdate ($hash, "state", "deactivated");
    readingsBulkUpdate ($hash, "mode", "deactivated");
    readingsEndUpdate  ($hash, 1);
  } elsif($a[0] eq "set" && $a[2] eq "state") {
      delete $hash->{Regex}{"STATE"};
      my ($block,$err)=ReplaceAllReadingsDoIf($hash,$a[3],-2,0);
      $hs=$cur_hs;
      return $err if ($err);
  } elsif($a[0] eq "del" && $a[2] eq "state") {
      delete $hash->{Regex}{"STATE"};
  } elsif($a[0] =~ "set|del"  && $a[2] eq "wait") {
      if ($a[0] eq "del") {
        RemoveInternalTimer($hash);
        readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
        $hash->{helper}{sleeptimer}=-1;
      }
      delete $hash->{attr}{wait};
      my @wait=SplitDoIf(':',$a[3]);
      for (my $i=0;$i<@wait;$i++){
        @{$hash->{attr}{wait}{$i}}=SplitDoIf(',',$wait[$i]);
      }
  } elsif($a[0] =~ "set|del"  && $a[2] eq "waitdel") {
      if ($a[0] eq "del") {
        RemoveInternalTimer($hash);
        readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
        $hash->{helper}{sleeptimer}=-1;
      }
      delete $hash->{attr}{waitdel};
      my @waitdel=SplitDoIf(':',$a[3]);
      for (my $i=0;$i<@waitdel;$i++){
        @{$hash->{attr}{waitdel}{$i}}=SplitDoIf(',',$waitdel[$i]);
      }
  } elsif($a[0] =~ "set|del" && $a[2] eq "repeatsame") {
    delete ($defs{$hash->{NAME}}{READINGS}{cmd_count});
    @{$hash->{attr}{repeatsame}}=SplitDoIf(':',$a[3]);
  } elsif($a[0] =~ "set|del" && $a[2] eq "repeatcmd") {
    @{$hash->{attr}{repeatcmd}}=SplitDoIf(':',$a[3]);
  } elsif($a[0] =~ "set|del" && $a[2] eq "cmdpause") {
    @{$hash->{attr}{cmdpause}}=SplitDoIf(':',$a[3]);
  } elsif($a[0] =~ "set|del" && $a[2] eq "cmdState") {
      delete $hash->{attr}{cmdState};
      my @cmdState=SplitDoIf('|',$a[3]);
      for (my $i=0;$i<@cmdState;$i++){
        @{$hash->{attr}{cmdState}{$i}}=SplitDoIf(',',$cmdState[$i]);
      }
  } elsif($a[0] =~ "set|del" && $a[2] eq "waitsame") {
    delete ($defs{$hash->{NAME}}{READINGS}{waitsame});
    @{$hash->{attr}{waitsame}}=SplitDoIf(':',$a[3]);
  } elsif($a[0] eq "set" && ($a[2] eq "DOIF_Readings" or $a[2] eq "event_Readings")) {
    if ($init_done) {
      my ($def,$err)=addDOIF_Readings($hash,$a[3],$a[2]);
      if ($err) {
        $hs=$cur_hs;
        return ("error in $a[2] $def, $err");
      } else {
        foreach my $reading (keys %{$hash->{$a[2]}}) {
          setDOIF_Reading ($hash,$reading,"",$a[2],"","","");
        }
      }
    }
  } elsif($a[0] eq "del" && ($a[2] eq "DOIF_Readings" or $a[2] eq "event_Readings")) {
    delete ($hash->{$a[2]});
    delete $hash->{Regex}{$a[2]};
  } elsif($a[0] eq "set" && ($a[2] eq "uiTable" || $a[2] eq "uiState")) {
    if ($init_done) {
      my $err=DOIF_uiTable_def($hash,$a[3],$a[2]);
      $hs=$cur_hs;
      return $err if ($err);
      DOIF_reloadFW;
    }
  } elsif($a[0] eq "del" && ($a[2] eq "uiTable" || $a[2] eq "uiState")) {
    delete ($hash->{Regex}{$a[2]});
    delete ($hash->{$a[2]});
  } elsif($a[0] eq "set" && $a[2] eq "startup") {
    my ($cmd,$err)=ParseCommandsDoIf($hash,$a[3],0);
    if ($err) {
     $hs=$cur_hs;
     return ("error in startup $a[3], $err");
    }
  }
  DOIF_Set_Filter($hash);
  $hs=$cur_hs;
  return undef;
}

sub
DOIF_Undef
{
  my ($hash, $name) = @_;
  $hash->{DELETED} = 1;
  DOIF_delTimer($hash);
  DOIF_killBlocking($hash);
  return undef;
}
sub
DOIF_Shutdown
{
  my ($hash) = @_;
  DOIF_killBlocking($hash);
  
  DOIF_save_readings($hash);
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
  my $cur_hs=$hs;
  $hs=$hash;

  if ($arg eq "disable" or  $arg eq "initialize" or  $arg eq "enable") {
    if (AttrVal($hash->{NAME},"disable","")) {
      $hs=$cur_hs;
      return ("device is deactivated by disable attribute, delete disable attribute first");
    }
  }
  if ($arg eq "disable") {
      readingsBeginUpdate  ($hash);
      if ($hash->{MODEL} ne "Perl") {
        readingsBulkUpdate($hash,"last_cmd",ReadingsVal($pn,"state",""));
        readingsBulkUpdate($hash, "state", "disabled");
      }
      readingsBulkUpdate($hash, "mode", "disabled");
      readingsEndUpdate    ($hash, 1);
  } elsif ($arg eq "initialize" ) {
      readingsSingleUpdate ($hash,"mode","enabled",1);
      if ($hash->{MODEL} ne "Perl") {
        delete ($defs{$hash->{NAME}}{READINGS}{cmd_nr});
        delete ($defs{$hash->{NAME}}{READINGS}{cmd});
        delete ($defs{$hash->{NAME}}{READINGS}{cmd_seqnr});
        delete ($defs{$hash->{NAME}}{READINGS}{cmd_event});
        readingsSingleUpdate($hash, "state","initialize",1);
      }
  } elsif ($arg eq "enable" ) {
      #delete ($defs{$hash->{NAME}}{READINGS}{mode});
      if ($hash->{MODEL} ne "Perl") {
        readingsSingleUpdate ($hash,"state",ReadingsVal($pn,"last_cmd",""),1) if (ReadingsVal($pn,"last_cmd","") ne "");
        delete ($defs{$hash->{NAME}}{READINGS}{last_cmd});
      }
      readingsSingleUpdate ($hash,"mode","enabled",1)
  } elsif ($arg eq "checkall" ) {
    $hash->{helper}{triggerDev}="";
    delete $hash->{helper}{triggerEvents};
    delete $hash->{helper}{triggerEventsState};
    DOIF_Trigger ($hash,$pn,1);
  } elsif ($arg =~ /^cmd_(.*)/ ) {
    if (ReadingsVal($pn,"mode","") ne "disabled") {
	  if ($hash->{helper}{sleeptimer} != -1) {
         RemoveInternalTimer($hash);
	     readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
	     $hash->{helper}{sleeptimer}=-1;
      }
      DOIF_cmd ($hash,$1-1,0,"set_cmd_".$1);
	}
  } elsif ($arg eq "?") {
    my $setList = AttrVal($pn, "setList", " ");
    $setList =~ s/\n/ /g;
	  my $cmdList="";
    my $checkall="";
    my $initialize="";
    my $max_cond=keys %{$hash->{condition}};
    if ($hash->{MODEL} ne "Perl") {
      $checkall="checkall:noArg";
      $initialize="initialize:noArg";
      $max_cond++ if (defined ($hash->{do}{$max_cond}{0}) or ($max_cond == 1 and !(AttrVal($pn,"do","") or AttrVal($pn,"repeatsame",""))));
      for (my $i=0; $i <$max_cond;$i++) {
        $cmdList.="cmd_".($i+1).":noArg ";
	    }
    } else {
       for (my $i=0; $i <$max_cond;$i++) {
         $cmdList.=$hash->{perlblock}{$i}.":noArg ";
	     }
    }
    $hs=$cur_hs;
	  return "unknown argument ? for $pn, choose one of disable:noArg enable:noArg $initialize $checkall $cmdList $setList";
  } else {
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
    if($doRet) {
      $hs=$cur_hs;
      return;
    }
    if (ReadingsVal($pn,"mode","") ne "disabled") {
      if ($hash->{MODEL} ne "Perl") {
        foreach my $i (keys %{$hash->{attr}{cmdState}}) {
          if ($arg eq EvalCmdStateDoIf($hash,$hash->{attr}{cmdState}{$i}[0])) {
            if ($hash->{helper}{sleeptimer} != -1) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
            $hash->{helper}{sleeptimer}=-1;
            }
            DOIF_cmd ($hash,$i,0,"set_".$arg."_cmd_".($i+1));
            last;
          }
        }
      } else {
        for (my $i=0; $i < keys %{$hash->{condition}};$i++) { 
          if ($arg eq $hash->{perlblock}{$i}) {
            DOIF_block ($hash,$i);
            last;
          }
        }
      }
      #return "unknown argument $arg for $pn, choose one of disable:noArg initialize:noArg enable:noArg cmd $setList";
    }
  }
  $hs=$cur_hs;
  return $ret;
}

sub
DOIF_Get($@)
{
  my ($hash, @a) = @_;
  my $pn = $a[0];
  return "$pn: get needs at least one parameter" if(@a < 2);
  my $arg= $a[1];
  if( $arg eq "html" ) {
    return DOIF_RegisterEvalAll($hash,$pn,"uiTable");
  }

  return undef;
}

package DOIF;

#use Date::Parse qw(str2time);
use Time::HiRes qw(gettimeofday);

sub DOIF_ExecTimer
{
  my ($timer)=@_;
  my $hash=${$timer}->{hash};
  my $timername=${$timer}->{name};
  my $name=$hash->{NAME};
  my $subname=${$timer}->{subname};
  my $count=${$timer}->{count};
  my $condition=${$timer}->{cond};
  my $param=${$timer}->{param} if (defined ${$timer}->{param});
  my $cur_hs=$hs;
  $hs=$hash;
  
  delete ($::defs{$name}{READINGS}{"timer_$timername"});
  if (defined ($condition) and !eval ($condition)) {
    $hs=$cur_hs;
    return (0);
  }
  if (!defined ($param)) {
    eval ("package DOIF;$subname");
  } else {
    eval('package DOIF;no strict "refs";&{$subname}($param);use strict "refs"');
  }
  if ($@) {
    ::Log3 ($hash->{NAME},1 , "$name error in $subname: $@");
    ::readingsSingleUpdate ($hash, "error", "in $subname: $@",1);
  }
  if (defined ($condition)) {
    $count=++${$timer}->{count};
    if (!eval ($condition)) {
      $hs=$cur_hs;
      return (0);
    }
  } else {
    $hs=$cur_hs;
    return (0);
  }
  my $current = ::gettimeofday();
  my $seconds=eval (${$timer}->{sec});
  my $next_time = $current+$seconds;
  ${$timer}->{time}=$next_time;
  if ($seconds > 0) {
    if (defined ($condition)) {
      ::readingsSingleUpdate ($hs,"timer_$timername",::strftime("%d.%m.%Y %H:%M:%S",localtime($next_time))." $count",0);
    } else {
      ::readingsSingleUpdate ($hs,"timer_$timername",::strftime("%d.%m.%Y %H:%M:%S",localtime($next_time)),0); 
    }
  }
  ::InternalTimer($next_time, "DOIF::DOIF_ExecTimer",$timer, 0);
  $hs=$cur_hs;
  return(0);
}

sub set_Exec
{
  my ($timername,$sec,$subname,$param4,$param5)=@_;
  my $count=0;
  my $hash=$hs;
  if (defined $param5) {
    $hs->{ptimer}{$timername}{cond}=$param5;
    $hs->{ptimer}{$timername}{param}=$param4;
  } elsif (defined $param4) {
    if (!ref($param4)) {
      $hs->{ptimer}{$timername}{cond}=$param4;
    } else { 
      $hs->{ptimer}{$timername}{param}=$param4;
    }
  }
  $hs->{ptimer}{$timername}{sec}=$sec;
  $hs->{ptimer}{$timername}{name}=$timername;
  $hs->{ptimer}{$timername}{subname}=$subname;
  $hs->{ptimer}{$timername}{count}=$count;
  $hs->{ptimer}{$timername}{hash}=$hs;
  ::RemoveInternalTimer(\$hs->{ptimer}{$timername});

  if (defined ($hs->{ptimer}{$timername}{cond})) {
    my $cond=eval ($hs->{ptimer}{$timername}{cond});
    if ($@) {
      ::Log3 ($hs->{NAME},1,"$hs->{NAME} error eval condition: $@");
      ::readingsSingleUpdate ($hs, "error", "eval condition: $@",1);
      return (1);
    }
    if (!$cond) {
      return (0);
    }
  }  
  my $seconds=eval($sec);
  if ($@) {
    ::Log3 ($hs->{NAME},1,"$hs->{NAME} error eval seconds: $@");
    ::readingsSingleUpdate ($hs, "error", "eval seconds : $@",1);
    return(1);
  }
  my $current = ::gettimeofday();
  my $next_time = $current+$seconds;
  $hs->{ptimer}{$timername}{time}=$next_time;
  if ($seconds > 0) {
    if (defined ($hs->{ptimer}{$timername}{cond})) {
      ::readingsSingleUpdate ($hs,"timer_$timername",::strftime("%d.%m.%Y %H:%M:%S",localtime($next_time))." $count",0);
    } else {
      ::readingsSingleUpdate ($hs,"timer_$timername",::strftime("%d.%m.%Y %H:%M:%S",localtime($next_time)),0); 
    }
  }
  ::InternalTimer($next_time, "DOIF::DOIF_ExecTimer",\$hs->{ptimer}{$timername}, 0);       
}

sub get_Exec
{
  my ($timername)=@_;
  my $current = ::gettimeofday();
  if (defined $hs->{ptimer}{$timername}{time}) {
    my $sec=$hs->{ptimer}{$timername}{time}-$current;
    if ($sec > 0) {
      return ($sec);
    } else {
      delete ($hs->{ptimer}{$timername}{time});
      return (0);
    }
  } else {
    return (0);
  }
}

sub del_Exec
{
  my ($timername)=@_;
  ::RemoveInternalTimer(\$hs->{ptimer}{$timername});
  delete $hs->{ptimer}{$timername};
  delete ($::defs{$hs->{NAME}}{READINGS}{"timer_$timername"});
}

sub set_Event
{
  my ($event)=@_;
  ::DoTrigger($hs->{NAME}, $event);
}

sub set_State
{
  my ($content,$trigger)=@_;
  if (defined $trigger) {
    return(::readingsSingleUpdate($hs,"state",$content,$trigger));
  } else {
    return(::readingsSingleUpdate($hs,"state",$content,1));
  }
}

sub set_Reading
{
  my ($reading,$content,$trigger)=@_;
  if (defined $trigger) {
    return(::readingsSingleUpdate($hs,$reading,$content,$trigger));
  } else {
    return(::readingsSingleUpdate($hs,$reading,$content,0));
  }
}

sub set_Reading_Begin
{
  return(::readingsBeginUpdate  ($hs));
}

sub set_Reading_Update ($$@)
{
  my ($reading,$value,$changed)= @_;
  return(::readingsBulkUpdate($hs, $reading, $value,$changed));
}

sub set_Reading_End
{
  my ($trigger)=@_;
  return(::readingsEndUpdate($hs,$trigger));
}

sub get_State
{
  my ($default)=@_;
  if (defined $default) {
    return(::ReadingsVal($hs->{NAME},"state",$default));
  } else {
    return(::ReadingsVal($hs->{NAME},"state",""));
  }
}  

sub get_Reading
{
  my ($reading,$default)=@_;
  if (defined $default) {
    return(::ReadingsVal($hs->{NAME},$reading,$default));
  } else {
    return(::ReadingsVal($hs->{NAME},$reading,""));
  }
} 

sub fhem_set {
  my ($content)=@_;
  return(::CommandSet(undef,$content));
}

sub fhem ($@){
  my ($param, $silent) = @_;
  return(::fhem($param, $silent));
}

sub Log {
  my ($loglevel, $text) = @_;
  return(::Log3(undef, $loglevel, $text));
}

sub Log3 {
  my ($dev, $loglevel, $text) = @_;
  return(::Log3($dev, $loglevel, $text));
}

sub InternalVal {
  my ($d,$n,$default) = @_;
  return(::InternalVal($d,$n,$default));
}

sub InternalNum {
  my ($d,$n,$default,$round) = @_;
  return(::InternalNum($d,$n,$default,$round));
}

sub OldReadingsVal {
  my ($d,$n,$default) = @_;
  return(::OldReadingsVal($d,$n,$default));
}

sub OldReadingsNum {
  my ($d,$n,$default,$round) = @_;
  return(::OldReadingsNum($d,$n,$default,$round));
}

sub OldReadingsTimestamp {
  my ($d,$n,$default) = @_;
  return(::OldReadingsTimestamp($d,$n,$default));
}

sub OldReadingsAge {
  my ($device,$reading,$default) = @_;
  return(::OldReadingsAge($device,$reading,$default));
}

sub ReadingsVal {
  my ($device,$reading,$default)=@_;
  return(::ReadingsVal($device,$reading,$default));
}

sub ReadingsNum {
  my ($d,$n,$default,$round) = @_;
  return(::ReadingsNum($d,$n,$default,$round));
}

sub ReadingsTimestamp {
  my ($d,$n,$default) = @_;
  return(::ReadingsTimestamp($d,$n,$default));
}

sub ReadingsAge {
  my ($device,$reading,$default) = @_;
  return(::ReadingsAge($device,$reading,$default));
}

sub Value($) {
  my ($d) = @_;
  return(::Value($d));
}

sub OldValue {
  my ($d) = @_;
  return(::OldValue($d));
}

sub OldTimestamp {
  my ($d) = @_;
  return(::OldTimestamp($d));
}

sub AttrVal {
  my ($d,$n,$default) = @_;
  return(::AttrVal($d,$n,$default));
}

sub AttrNum {
  my ($d,$n,$default,$round) = @_;
  return (::AttrNum($d,$n,$default,$round));
}

package ui_Table;

sub FW_makeImage {
  my ($image) = @_;
  return (::FW_makeImage($image));
}
#Styles
 sub temp
 {
   my ($temp,$size,$icon)=@_;
   return((defined($icon) ? ::FW_makeImage($icon):"").$temp."&nbsp;°C","font-weight:bold;".(defined ($size) ? "font-size:".$size."pt;":"").ui_Table::temp_style($temp));
 }

 sub temp_style
 {
     my ($temp)=@_;
     if ($temp >=30) {
	   return ("color:".::DOIF_hsv ($temp,30,50,20,0,90,95));
     } elsif ($temp >= 10) {
       return ("color:".::DOIF_hsv ($temp,10,30,73,20,80,95));  
	 } elsif ($temp >= 0) {
	   return ("color:".::DOIF_hsv ($temp,0,10,211,73,60,95));
	 } elsif ($temp >= -20) {
	   return ("color:".::DOIF_hsv ($temp,-20,0,277,211,50,95));
	 }
 }
 
 sub hum
 {
    my ($hum,$size,$icon)=@_;
    return ((defined($icon) ? ::FW_makeImage($icon):"").$hum."&nbsp;%","font-weight:bold;".(defined ($size) ? "font-size:".$size."pt;":"")."color:".::DOIF_hsv ($hum,30,100,30,260,60,90));
 }

 sub style
 {
   my ($text,$color,$font_size,$font_weight)=@_;
   my $style="";
   $style.="color:$color;" if (defined ($color));
   $style.="font-size:$font_size"."pt;" if (defined ($font_size));
   $style.="font-weight:$font_weight;" if (defined ($font_weight));
   return ('<div style="display:inline-table;'.$style.'">'.$text.'</div>');
   #return ($text,$style);

 }
 

# Widgets

 
sub widget { 
  my ($value,$widget,$set)=@_;
  $set="" if (!defined $set);
  return ($value,"",$widget,$set)
} 
 
 sub temp_knob {
    my ($value,$color,$set)=@_;
    $color="DarkOrange" if (!defined $color); 
    $set="set" if (!defined $set);
    return ($value,"","knob,min:15,max:27,width:40,height:35,step:0.5,fgColor:$color,bgcolor:grey,anglearc:270,angleOffset:225,cursor:15,thickness:.3",$set) 
 }
 
 sub shutter {
   my ($value,$color,$type,$coloroff)=@_;
   $color="\@darkorange" if (!defined ($color) or $color eq "");
   $coloroff="" if (!defined ($coloroff));
   if (!defined ($type) or $type == 3) {
       return ($value,"","iconRadio,$color,100,fts_shutter_10$coloroff,30,fts_shutter_70$coloroff,0,fts_shutter_100$coloroff","set");
   } elsif ($type == 4) {
       return ($value,"","iconRadio,$color,100,fts_shutter_10$coloroff,50,fts_shutter_50$coloroff,30,fts_shutter_70$coloroff,0,fts_shutter_100$coloroff","set");
     } elsif ($type == 5) {
         return ($value,"","iconRadio,$color,100,fts_shutter_10$coloroff,70,fts_shutter_30$coloroff,50,fts_shutter_50$coloroff,30,fts_shutter_70,0,fts_shutter_100$coloroff","set");
       } elsif ($type >= 6) {
           return ($value,"","iconRadio,$color,100,fts_shutter_10$coloroff,70,fts_shutter_30$coloroff,50,fts_shutter_50$coloroff,30,fts_shutter_70$coloroff,20,fts_shutter_80$coloroff,0,fts_shutter_100$coloroff","set");
         } elsif ($type == 2) {
             return ($value,"","iconRadio,$color,100,fts_shutter_10$coloroff,0,fts_shutter_100$coloroff","set");
         }
 } 
 
 sub dimmer {
   my ($value,$color,$type)=@_;
   $color="\@darkorange" if (!defined ($color) or $color eq "");
   if (!defined ($type) or $type == 3) {
     return ($value,"","iconRadio,$color,0,light_light_dim_00,50,light_light_dim_50,100,light_light_dim_100","set");
   } elsif ($type == 4) {
       return ($value,"","iconRadio,$color,0,light_light_dim_00,50,light_light_dim_50,70,light_light_dim_70,100,light_light_dim_100","set");
     } elsif ($type == 5) {
         return ($value,"","iconRadio,$color,0,light_light_dim_00,30,light_light_dim_30,50,light_light_dim_50,70,light_light_dim_70,100,light_light_dim_100","set");
       } elsif ($type == 6) {
         return ($value,"","iconRadio,$color,0,light_light_dim_00,30,light_light_dim_30,50,light_light_dim_50,70,light_light_dim_70,80,light_light_dim_80,100,light_light_dim_100","set");
         } elsif ($type >= 7) {
           return ($value,"","iconRadio,$color,0,light_light_dim_00,20,light_light_dim_20,30,light_light_dim_30,50,light_light_dim_50,70,light_light_dim_70,80,light_light_dim_80,100,light_light_dim_100","set");
           } elsif ($type == 2) {
             return ($value,"","iconRadio,$color,0,light_light_dim_00,100,light_light_dim_100","set");
           }
 } 
 
 sub switch {
   my ($value,$icon_off,$icon_on,$state_off,$state_on)=@_;
   $state_on=(defined ($state_on) and $state_on ne "") ? $state_on : "on";
   $state_off=(defined ($state_off) and $state_off ne "") ? $state_off : "off";
   my $i_off=(defined ($icon_off) and $icon_off ne "") ? $icon_off : "off";
   $icon_on=((defined ($icon_on) and $icon_on ne "") ? $icon_on :(defined ($icon_off) and $icon_off ne "") ? "$icon_off\@DarkOrange" : "on");
   return($value,"",("iconSwitch,".$state_on.",".$i_off.",".$state_off.",".$icon_on));
 }
 
 sub ICON {
   my ($icon)=@_;
   ::FW_makeImage($icon);
 }
 
 sub icon {
   my ($value,$icon_off,$icon_on,$state_off,$state_on)=@_;
   $state_on=(defined ($state_on) and $state_on ne "") ? $state_on : "on";
   $state_off=(defined ($state_off) and $state_off ne "") ? $state_off : "off";
   my $i_off=(defined ($icon_off) and $icon_off ne "") ? $icon_off : "off";
   $icon_on=((defined ($icon_on) and $icon_on ne "") ? $icon_on :(defined ($icon_off) and $icon_off ne "") ? "$icon_off\@DarkOrange" : "on");
   return($value,"",("iconLabel,".$state_on.",".$icon_on.",".$state_off.",".$i_off));
 }

 sub icon_label
 {
   my ($icon,$text,$color,$color_bg,$pos_left,$pos_top) = @_;
   $color = "" if (!defined ($color));
   $color_bg = "" if (!defined ($color_bg));
   $pos_left = -3 if (!defined ($pos_left));
   $pos_top = -8 if (!defined ($pos_top));
   my $pad = (length($text) > 1) ? 2 : 5; 
   return '<div style="display:inline-table;">'.::FW_makeImage($icon).'<div style="display:inline;border-radius:20px;color:'.$color.';background-color:'.
          $color_bg.
          ';font-size:14px;font-weight:bold;text-align:center;position:relative;padding-top: 1px;padding-left: '.$pad.'px; padding-right: '.$pad.'px;padding-bottom: 1px;'.
          'left:'.$pos_left.'px;top:'.$pos_top.'px;">'.$text.'</div></div>'
 }
 
 sub hsv {
   return(::DOIF_hsv(@_));
 }
 
 sub temp_hue {
   #temp->hue   
   #-20->270
   #-10->240
   #0  ->180
   #10 ->120
   #20 ->60
   #40 ->0
   #70 ->340
   my($temp)=@_;
   my $hue;
   if ($temp < -10) {
    $hue=-3*$temp+210;
   } elsif ($temp < 20) {
    $hue=-6*$temp+180;
   } elsif ($temp < 40) {
    $hue=-3*$temp+120;
   } else {
    $hue = -2/3*$temp+386;
   }
   return (int($hue));  
 }
 
 sub m_n
 {
   my ($x1,$y1,$x2,$y2) =@_;
   return(0,0) if ($x2==$x1);
   my $m=($y2-$y1)/($x2-$x1);
   my $y=$y1-$m*$x1;
   return($m,$y);
 }
 
  sub hum_hue {
   my($hum)=@_;
   my $hue;
   my $m;
   my $n;
   if ($hum > 60) {
     ($m,$n)=m_n(60,180,100,260);
   } elsif ($hum > 40) {
     ($m,$n)=m_n(40,60,60,180);
   } else {
     ($m,$n)=m_n(0,40,40,60);
   }
   $hue = $m*$hum+$n;
   return (int($hue));  
 }

sub format_value {
  my ($val,$min,$dec)=@_;
  my $format;
  my $value=$val;
  if (!defined $val or $val eq "" or $val eq "N/A") {
    $val="N/A";
    $format='%s';
    $value=$min;
  } elsif ($val =~ /(-?\d+(\.\d+)?)/) {
    $format='%1.'.$dec.'f';
    $value=$1;
    $val=$value;
  } else {
    $format='%s';
    $val="N/A";
    $value=$min;
  }
  return($format,$value,$val);
}

sub get_color {
  my ($value,$min,$max,$minColor,$maxColor,$func)=@_;
  my $color;
  if (!defined $value or $value eq "N/A" or $value < $min ) {
    $value = $min;
  } elsif ($value > $max) {
    $value = $max;
  }
  if (ref($func) eq "CODE") {
    $minColor=&{$func}($min);
    $maxColor=&{$func}($max);
    $color=&{$func}($value);
  } elsif (ref($func) eq "ARRAY") {
    $minColor=${$func}[1];
    $maxColor=${$func}[-1];
    for (my $i=0;$i<@{$func};$i+=2) {
      if ($value <= ${$func}[$i]) {
        $color=${$func}[$i+1];
        last;
      }
    }
  } else {
    $minColor=120 if (!defined $minColor);
    $maxColor=0 if (!defined $maxColor);
    my $prop=0;
    $prop=($value-$min)/($max-$min) if ($max-$min);
    if ($minColor < $maxColor) {
      $color=$prop*($maxColor-$minColor)+$minColor;
    } else {
      $color=(1-$prop)*($minColor-$maxColor)+$maxColor;
    }
  }
  return(int($color),$minColor,$maxColor);
}

sub nice_scale {
    my ($data_min, $data_max, $ticks) = @_;
    my $span = $data_max - $data_min;
    return ($data_min,$data_max, $ticks) if ($span==0);
    my $raw_step = $span / ($ticks - 1);
        my $mag  = 10 **  POSIX::floor(log($raw_step)/log(10));
    my $norm = $raw_step / $mag;

    my $nice_norm;
    if    ($norm < 1.5) { $nice_norm = 1; }
    elsif ($norm < 3)   { $nice_norm = 2; }
    elsif ($norm < 7)   { $nice_norm = 5; }
    else                { $nice_norm = 10; }

    my $step = $nice_norm * $mag;

    my $nice_min = POSIX::floor($data_min / $step) * $step;
    my $nice_max = POSIX::ceil($data_max / $step) * $step;
    
    my $lines = int(($nice_max-$nice_min)/$step+0.5);
    
    return ($nice_min, $nice_max, $lines);
}



sub plot {
  
  my ($collect,$min_a,$max_a,$minColor,$maxColor,$dec,$func,$steps,$x_prop,$chart_dim,$noColor,$lmm,$ln,$lr,$plot,$bwidth,$footerPos,$fill,$pos,$anchor,$unitColor,$unit)=@_;
  
  $lmm=42 if (!defined $lmm or $lmm eq "");

  my $points="";
  my $v;
  my $last;
  my $outDescript="";
  my $out="";
  my $yNull;
  my $nullColor;
  my $nullProp;
  my $topVal;
  my $topOpacity;
  my $bottomVal;
  my $bottomOpacity;
  my $nullOpacity;
  my $minPlot;
  my $maxPlot;
  $unit="" if (!defined $unit);

  my $val=${$collect}{value};
  my $a=@{$collect}{values};
  my $minVal = ${$collect}{min_value};
  my $maxVal = ${$collect}{max_value};
  my $maxValTime = ${$collect}{max_value_time};
  my $maxValSlot = ${$collect}{max_value_slot};
  my $last_value=${$collect}{last_value};
  my $minValTime = ${$collect}{min_value_time};
  my $minValSlot = ${$collect}{min_value_slot};
  my $averageVal = ${$collect}{average_value};
  my $hours = ${$collect}{hours};
  my $time = ${$collect}{time};
  my $dim=${$collect}{dim};
  my $type=${$collect}{type};
  my $period=${$collect}{period};
  my $period1=${$collect}{last_period1};
  my $num=${$collect}{num};
  my $numOrig=${$collect}{numOrig};
  my $animate=(defined ${$collect}{animate} and ${$collect}{animate} eq "1") ? '<animate attributeName="opacity" values="0.0;1;0.0" dur="2s" repeatCount="indefinite"/></circle>':'</circle>';

  my $min;
  my $max;
  if (ref($min_a) eq "ARRAY") {
    $min=${$min_a}[0];
    $minVal=${$min_a}[1];
    $max=${$max_a}[0];
    $maxVal=${$max_a}[1];
  } else {
    $min=$min_a;
    $max=$max_a;
  }
  my ($format,$value);
  ($format,$value,$val)=format_value($val,$min,$dec);
  
  my $decform='%1.'.$dec.'f';

  $minVal=$value if (!defined $minVal);
  $maxVal=$value if (!defined $maxVal);
  
  my $autoScaling = ($plot ne "1");
  
  if ($plot ne "1" and $minVal ne $maxVal) {
    $autoScaling=1;
    if ($val ne "N/A") {
      $minPlot=($value < $minVal ? $value : $minVal);
      $maxPlot=($value > $maxVal ? $value : $maxVal);
    } else {
      $minPlot=$minVal;
      $maxPlot=$maxVal;
    }
  } else {
    my $minimum = ($min<$minVal) ? $min:$minVal;
    my $maximum = ($max>$maxVal) ? $max:$maxVal;
    if ($val ne "N/A") {
       if ($value < $minimum) {
         $minimum=$value;
         $autoScaling=1;
       }
       if ($value > $maximum) {
         $maximum=$value; 
         $autoScaling=1;
       }
    }
    $minPlot=(($min < 0 and $minVal > 0) ? 0 : $minimum);
    $maxPlot=(($max > 0 and $maxVal < 0) ? 0 : $maximum);
    if ($minVal < $min or $maxVal > $max) {
      $autoScaling=1;  
    }      
 }
 
  my $lines=5;
  if ($autoScaling) {
    ($minPlot,$maxPlot,$lines)=nice_scale($minPlot,$maxPlot,6);
    if ($lines >= 7) {
      ($minPlot,$maxPlot,$lines)=nice_scale($minPlot,$maxPlot,5);
    }
  }
  my ($m,$n)=m_n($minPlot,0,$maxPlot,50); 
  
  my $currColor;
  ($currColor,$minColor,$maxColor)=get_color($value,$min,$max,$minColor,$maxColor,$func);
 
  $maxVal=${$collect}{max_value};
  $minVal=${$collect}{min_value};
  
  $minVal=$value if (!defined $minVal);
  $maxVal=$value if (!defined $maxVal);
  my $opacity=0.4;
  my $minopacity=0.05;
  if ($minPlot < 0 and $maxPlot > 0) {
    $yNull=50-int($n*10)/10;
    $topVal=($maxVal > 0 ? $maxVal : 0);
    $bottomVal=($minVal < 0 ? $minVal : 0);
    ($nullColor)=get_color(0,$min,$max,$minColor,$maxColor,$func);
    $nullProp=int ($topVal/($topVal-$bottomVal)*100)/100 if ($bottomVal<0 and $topVal>0);
    $topOpacity=($topVal==0 ? $minopacity : $opacity);
    $bottomOpacity=($bottomVal==0 ? $minopacity: $opacity);
    $nullOpacity=$minopacity;
  } elsif ($maxPlot <= 0) {
    $yNull=0;
    $topVal=$maxPlot;
    $topOpacity=0;
    $bottomOpacity=$opacity;
    $bottomVal=$minVal;
  } else {
    $yNull=50;
    $topVal=$maxVal;
    $topOpacity=$opacity;
    $bottomOpacity=$minopacity;
    $bottomVal=$minPlot;
  }
  
  my ($topValColor)=get_color($topVal,$min,$max,$minColor,$maxColor,$func);
  my ($bottomValColor)=get_color($bottomVal,$min,$max,$minColor,$maxColor,$func);
  
  my ($maxValColor)=get_color(${$collect}{max_value},$min,$max,$minColor,$maxColor,$func);
  my ($minValColor)=get_color(${$collect}{min_value},$min,$max,$minColor,$maxColor,$func);
  my ($averageValColor)=get_color(${$collect}{average_value},$min,$max,$minColor,$maxColor,$func);
  
  $out.= '<defs>';
    if ($type eq "bar") {
    $out.= '<linearGradient id="graddark" x1="0" y1="0" x2="1" y2="0"><stop offset="0" style="stop-color:rgb(32,32,32);stop-opacity:0.5"/><stop offset="1" style="stop-color:rgb(32, 32, 32);stop-opacity:0.9"/></linearGradient>';
    $out.= '<linearGradient id="gradbright" x1="0" y1="0" x2="1" y2="0"><stop offset="0" style="stop-color:rgb(32,32,32);stop-opacity:0"/><stop offset="1" style="stop-color:rgb(32, 32, 32);stop-opacity:0.8"/></linearGradient>';
  } else {
    if (!defined $unitColor) {
      $out.= sprintf('<linearGradient id="gradplotLight_%s_%s_%s" x1="0" y1="0" x2="0" y2="1">',$topValColor,$bottomValColor,(defined $lr ? $lr:0));
      $out.= sprintf('<stop offset="0" style="stop-color:%s;stop-opacity:%s"/>',color($topValColor,$lr),$topOpacity);
      $out.= sprintf('<stop offset="%s" style="stop-color:%s;stop-opacity:%s"/>',$nullProp,color($nullColor,$lr),$nullOpacity) if (defined $nullProp);
      $out.= sprintf('<stop offset="1" style="stop-color:%s;stop-opacity:%s"/></linearGradient>',color($bottomValColor,$lr),$bottomOpacity);
      
      $out.= sprintf('<linearGradient id="gradplot_%s_%s_%s" x1="0" y1="0" x2="0" y2="1">',$topValColor,$bottomValColor,(defined $lr ? $lr:0));
      for (my $i=0; $i<=1;$i+=0.10) {
        my ($color)=get_color(($topVal-$bottomVal)*(1-$i)+$bottomVal,$min,$max,$minColor,$maxColor,$func);
        $out.= sprintf('<stop offset="%s" style="stop-color:%s;stop-opacity:1"/>',$i,color($color,$lr));
      }
      $out.= '</linearGradient>';
    } else {
      $out.= sprintf('<linearGradient id="gradplotLight_%s" x1="0" y1="0" x2="0" y2="1">',$unitColor);
      $out.= sprintf('<stop offset="0" style="stop-color:%s;stop-opacity:%s"/>',$unitColor,$topOpacity);
      $out.= sprintf('<stop offset="%s" style="stop-color:%s;stop-opacity:%s"/>',$nullProp,$unitColor,$nullOpacity) if (defined $nullProp);
      $out.= sprintf('<stop offset="1" style="stop-color:%s;stop-opacity:%s"/></linearGradient>',$unitColor,$bottomOpacity);
    }
  }
  $out.= '</defs>';
  

  for (my $i=0;$i<=$lines;$i++) {
    my $y=$i*int((50/$lines)*3)/3;
    $outDescript.=sprintf('<polyline points="0,%s %s,%s"  style="stroke:#505050; stroke-width:0.3; stroke-opacity:1"/>',$y,$chart_dim,$y);
  }
 
  if ($noColor ne "-1") {
     for (my $i=0;$i<=$lines;$i++) {
       my $v=($maxPlot-$minPlot)*(1-$i*(1/$lines))+$minPlot;
       my ($color)= get_color($v,$min,$max,$minColor,$maxColor,$func); 
       $outDescript.= sprintf('<text text-anchor="%s" x="%s" y="%s" style="fill:%s;font-size:7px;%s">%s</text>',$anchor,$pos,int(($i*(50/$lines)+2)*3)/3,$noColor eq "1" ? "#CCCCCC":color($color,$lmm),"",sprintf($decform,$v)); 
     } 
  }
  
  my $footer="";

  if ($type eq "bar") {
    my $dimdev;
    if ($period eq "month") {
      $dimdev=32;
    } elsif ($period eq "day") {
      $dimdev=26;
    } else {
      $dimdev=$dim; 
    }
    my $wide=$chart_dim/$dimdev;

    my $barOffset=0.8;
    my $barsWide=$wide*0.85;
    my $barWide=int(100*$barsWide/(($numOrig-1)*$barOffset+1))/100;
    my $xBar=$barWide*$barOffset;



     my $xOffset;
    if ($period eq "month" or $period eq "day") {
      $xOffset=$wide*0.6;
    } else {
      $xOffset=$wide*0.08;    
    }
    
#    $out.=sprintf('<polyline points="0,%s %s,%s"  style="stroke:#CCCCCC; stroke-width:0.3; stroke-opacity:0.7" />',$yNull,$chart_dim,$yNull);
    
    if ($averageVal) {
      my $yAverage=50-int(($averageVal*$m+$n)*10)/10;
      $out.=sprintf('<polyline points="0,%s %s,%s"  style="stroke:%s; stroke-width:0.3; stroke-opacity:1" />',$yAverage,$chart_dim,$yAverage,color($averageValColor,$lmm));
    }
    
    for (my $i=0; $i < $numOrig;$i++) {
      for (my $j=0; $j < $dim; $j++) {
        my $num;
        if ($numOrig == 1) {
          if (defined ${$a}[($i)*$dim+$j]) {
            $num = 1;
          } else {
            $num = 2;
          }
        } else {
          $num=$numOrig;
        }         
        my $y=${$a}[($num-1-$i)*$dim+$j];
        if (defined $y) {   
          my $y_pos=int(($y*$m+$n)*10)/10-(50-$yNull);
          my ($color)=get_color($y,$min,$max,$minColor,$maxColor,$func);
          my $x=int(($xOffset+$j*$wide+$i*$xBar)*10)/10;
          if ($y > 0) {
            $out.= sprintf('<rect x="%s" y="%s" width="%s" height="%s" rx="0.5" ry="0.5" style="fill:%s" opacity="1"/>',$x,$yNull-$y_pos,$barWide,$y_pos,defined $unitColor ? $unitColor:color($color));
            $out.= sprintf('<rect x="%s" y="%s" width="%s" height="%s" rx="0.5" ry="0.5" style="fill:url(#grad%s)"/>',$x,$yNull-$y_pos+0.1,$barWide,$y_pos-0.1,($i==$num-1 ? "bright" : "dark"));
          } else {
            $out.= sprintf('<rect x="%s" y="%s" width="%s" height="%s" rx="0.5" ry="0.5" style="fill:%s" opacity="1"/>',$x,$yNull,$barWide,-$y_pos,defined $unitColor ? $unitColor:color($color));
            $out.= sprintf('<rect x="%s" y="%s" width="%s" height="%s" rx="0.5" ry="0.5" style="fill:url(#grad%s)"/>',$x,$yNull,$barWide,-$y_pos-0.1,($i==$num-1 ? "bright" : "dark"));
          }
        }
      }
    }
    
    $out.=sprintf('<polyline points="0,%s %s,%s"  style="stroke:#CCCCCC; stroke-width:0.3; stroke-opacity:0.7" />',$yNull,$chart_dim,$yNull);

    my ($x1,$y1);
    if (defined $maxValSlot) {
      ($x1,$y1)=(int(($xOffset+($maxValSlot % $dim)*$wide+($numOrig-1-($numOrig == 1 ?  0: int ($maxValSlot / $dim)))*$xBar+$barWide/2)*10)/10 ,(50-int((${$a}[$maxValSlot]*$m+$n)*10)/10)-2.3);
      $out.=sprintf('<path d="M%s %s L%s %s L%s %s Z" fill="%s" opacity="0.5"/>',$x1,$y1,$x1+2.4,$y1+4.3,$x1-2.4,$y1+4.3, defined $unitColor ? $unitColor:color($maxValColor,$ln));
      ($x1,$y1)=(int(($xOffset+($minValSlot % $dim)*$wide+($numOrig-1-($numOrig == 1 ?  0: int ($minValSlot / $dim)))*$xBar+$barWide/2)*10)/10,(50-int((${$a}[$minValSlot]*$m+$n)*10)/10)+2.3);
      $out.=sprintf('<path d="M%s %s L%s %s L%s %s Z" fill="%s" opacity="0.5"/>',$x1,$y1,$x1+2.4,$y1-4.3,$x1-2.4,$y1-4.3, defined $unitColor ? $unitColor:color($minValColor,$ln)) if (defined $minValSlot);
    }
    
    
    if ($footerPos) {
      $footer.= sprintf('<text text-anchor="start" x="12" y="%s" style="fill:%s;font-size:8px"><tspan style="fill:#CCCCCC">%s</tspan></text>',$footerPos,defined $unitColor ? $unitColor : "#CCCCCC", $unit);
      if (defined $maxValSlot) {
        $footer.= sprintf('<text text-anchor="start" x="43" y="%s" style="fill:%s;font-size:8px">&#x00D8</text>',$footerPos,defined $unitColor ? $unitColor : "#CCCCCC");
        $footer.= sprintf('<text text-anchor="end" x="%s" y="%s" style="fill:%s;font-size:8px;%s">%s</text>',$bwidth/2-15,$footerPos,color($averageValColor,$lmm),"",sprintf($decform,$averageVal));
        $footer.= sprintf('<text text-anchor="start" x="%s" y="%s" style="fill:%s;font-size:8px">&#x25B2<tspan style="fill:#CCCCCC">%s</tspan></text>',$bwidth/2-15,$footerPos,defined $unitColor ? $unitColor : "#CCCCCC", $maxValTime) ;
        $footer.= sprintf('<text text-anchor="end" x="%s" y="%s" style="fill:%s;font-size:8px;%s">%s</text>',$bwidth/2+42.5,$footerPos,color($maxValColor,$lmm),"",sprintf($decform,${$collect}{max_value}));
        $footer.= sprintf('<text text-anchor="start" x="%s" y="%s" style="fill:#CCCCCC;font-size:8px"><tspan style="fill:%s">&#x25BC</tspan>%s</text>',$bwidth/2+42.5,$footerPos,defined $unitColor ? $unitColor : "#CCCCCC", $minValTime);
        $footer.= sprintf('<text text-anchor="end" x="%s" y="%s" style="fill:%s;font-size:8px;%s">%s</text>', $bwidth+8,$footerPos,color($minValColor,$lmm),"",sprintf($decform,${$collect}{min_value}));
      }
    }
  } else { # col
    my $j=0;
    if (@{$a} > 0) {
      if (!defined ${$a}[0]) {
        if (defined $last_value) {
          $v=$last_value;
        } else {
          for ($j=0;$j<@{$a};$j++) {
            if (defined ${$a}[$j]) {
             $v=${$a}[$j];
             last;
            }
          }
        }   
      } else {
        $v=${$a}[0];
      }

      $points.=$j*$x_prop.",$yNull ";
      $last=(50-int(($v*$m+$n)*10)/10);
      $points.=$j*$x_prop.",$last ";
      $j++;
      
      for (my $i=$j;$i<@{$a};$i++) {
        if (defined ${$a}[$i]) {
          $points.=$i*$x_prop.",$last " if (!defined ${$a}[$i-1] or $steps eq "1"); 
          $last=(50-int((${$a}[$i]*$m+$n)*10)/10);
          $points.=$i*$x_prop.",$last ";
        }
      }
      if ($val ne "N/A") {
        $points.=$chart_dim.",".$last." " if ($steps eq "1");
        $points.=$chart_dim.",".(50-int(($val*$m+$n)*10)/10)." ";
      }
      if (!defined $unitColor) {
        $out.=sprintf('<path d="M%s,%s L',$chart_dim,$yNull);
        $out.= $points;
        $out.= sprintf('" style="fill:url(#gradplotLight_%s_%s_%s);stroke:url(#gradplot_%s_%s_%s);stroke-width:0.4;stroke-opacity:1" />',$topValColor,$bottomValColor,(defined $lr ? $lr:0),$topValColor,$bottomValColor,(defined $lr ? $lr:0));
      } else {
        $out.=sprintf('<path d="M%s,%s L',$chart_dim,$yNull);
        $out.= $points;
        $out.= sprintf('" style="fill:url(#gradplotLight_%s);stroke:%s;stroke-width:0.4;stroke-opacity:1" />',$unitColor,$unitColor);
      }
    }
    $out.=sprintf('<polyline points="0,%s %s,%s"  style="stroke:gray; stroke-width:0.3; stroke-opacity:1" />',$yNull,$chart_dim,$yNull);

    if (defined $maxValSlot) {
      my ($x1,$y1)=($maxValSlot*$x_prop,(50-int((${$a}[$maxValSlot]*$m+$n)*10)/10)-2.3);
      $out.=sprintf('<path d="M%s %s L%s %s L%s %s Z" fill="%s" opacity="0.5"/>',$x1,$y1,$x1+2.4,$y1+4.3,$x1-2.4,$y1+4.3, defined $unitColor ? $unitColor:color($maxValColor,$ln));
      ($x1,$y1)=($minValSlot*$x_prop,(50-int((${$a}[$minValSlot]*$m+$n)*10)/10)+2.3);
      $out.=sprintf('<path d="M%s %s L%s %s L%s %s Z" fill="%s" opacity="0.5"/>',$x1,$y1,$x1+2.4,$y1-4.3,$x1-2.4,$y1-4.3, defined $unitColor ? $unitColor:color($minValColor,$ln));
    }
    
    $out.=sprintf(('<circle cx="%s" cy="%s" r="2" fill="%s"  opacity="0.5">'.$animate),$chart_dim,(50-int(($value*$m+$n)*10)/10),defined $unitColor ? $unitColor:color($currColor,$ln)) if ($val ne "N/A");
    
    if ($footerPos) {
      $footer.= sprintf('<text text-anchor="start" x="12" y="%s" style="fill:%s;font-size:8px"><tspan style="fill:#CCCCCC">%s</tspan></text>',$footerPos,defined $unitColor ? $unitColor : "#CCCCCC", $unit);
      if (defined $maxValTime) {
        if ($hours > 168) {
          $footer.= sprintf('<text text-anchor="start" x="43" y="%s" style="fill:%s;font-size:8px">&#x25B2<tspan style="fill:#CCCCCC">%s</tspan></text>',$footerPos,defined $unitColor ? $unitColor : "#CCCCCC", ::strftime("%d.%m %H:%M",localtime($maxValTime)));
        } else {
          $footer.= sprintf('<text text-anchor="start" x="45" y="%s" style="fill:%s;font-size:8px">&#x25B2<tspan style="fill:#CCCCCC">%s</tspan></text>',$footerPos,defined $unitColor ? $unitColor : "#CCCCCC", ::strftime("%a",localtime($maxValTime)));
          $footer.= sprintf('<text text-anchor="start" x="65" y="%s" style="fill:#CCCCCC;font-size:8px">%s</text>',$footerPos,::strftime("%H:%M",localtime($maxValTime)));
        }
        $footer.= sprintf('<text text-anchor="end" x="%s" y="%s" style="fill:%s;font-size:8px;%s">%s</text>',$bwidth/2+25.5,$footerPos,color($maxValColor,$lmm),"",sprintf($decform,${$collect}{max_value}));
      }
      if (defined $minValTime) {
        if ($hours > 168) {
         ## $footer.= sprintf('<text text-anchor="start" x="%s" y="%s" style="fill:#CCCCCC;font-size:8px">&#x2022<tspan style="fill:%s">&#x25BC</tspan>%s</text>',$bwidth/2+25,$footerPos,defined $unitColor ? $unitColor : "#CCCCCC", ::strftime("%d.%m %H:%M",localtime($minValTime)));
          $footer.= sprintf('<text text-anchor="start" x="%s" y="%s" style="fill:#CCCCCC;font-size:8px"><tspan style="fill:%s">&#x25BC</tspan>%s</text>',$bwidth/2+25.5,$footerPos,defined $unitColor ? $unitColor : "#CCCCCC", ::strftime("%d.%m %H:%M",localtime($minValTime)));
        } else {
          $footer.= sprintf('<text text-anchor="start" x="%s" y="%s" style="fill:#CCCCCC;font-size:8px"><tspan style="fill:%s">&#x25BC</tspan>%s</text>',$bwidth/2+25.5,$footerPos,defined $unitColor ? $unitColor : "#CCCCCC", ::strftime("%a",localtime($minValTime)));
          $footer.= sprintf('<text text-anchor="start" x="%s" y="%s" style="fill:#CCCCCC;font-size:8px">%s</text>',$bwidth/2+46,$footerPos,::strftime("%H:%M",localtime($minValTime)));
        }
        $footer.= sprintf('<text text-anchor="end" x="%s" y="%s" style="fill:%s;font-size:8px;%s">%s</text>', $bwidth+8,$footerPos,color($minValColor,$lmm),"",sprintf($decform,${$collect}{min_value}));
      }
    }
  } # col
  return($outDescript,$out,$footer);
}


sub card
{
  my ($col,$header,$icon,$min,$max,$minColor,$maxColor,$unit_a,$func,$decfont,$prop,$model,$lightness,$col2,$min2,$max2,$minColor2,$maxColor2,$unit_b,$func2,$decfont2) = @_;
  
  my @value1;
  my @value2;
  my @unit1;
  my @unit2;
  my @colcount=();
  my @col2count=();
  
  my $hours;
  my $time;
  my $dim;
  my $type;
  my $period;
  my $period1;
  my $period2;  
  my $begin_period2;
  

  if (!defined $col) {
    return("no definition at collect parameter");
  }
  
  if (ref($col) eq "ARRAY") {
    for (my $i=0;$i< @{$col};$i++) {
      delete $value1[$i]{ring};
      if (ref (${$col}[$i]) eq "ARRAY") {
        $value1[$i]{value}=${$col}[$i][0];
        $value1[$i]{min}=${$col}[$i][1];
        $value1[$i]{max}=${$col}[$i][2];
        $value1[$i]{minColor}=${$col}[$i][3];
        $value1[$i]{maxColor}=${$col}[$i][4];
        $value1[$i]{unit}=${$col}[$i][5];
        $value1[$i]{func}=${$col}[$i][6];
        $value1[$i]{decfont}=${$col}[$i][7];
        $value1[$i]{model}=${$col}[$i][8];
      } elsif (ref (${$col}[$i]) eq "HASH") {
        $value1[$i]=${$col}[$i];
        if (@colcount < 2) { 
          $value1[$i]{ring}=1;
        }
        push(@colcount,$i);
        if (!defined $dim) {
          $type=$value1[$i]{type};
          $hours=$value1[$i]{hours};
          $time=$value1[$i]{time};
          $dim=$value1[$i]{dim};
          $period=$value1[$i]{period};
          $period1=$value1[$i]{last_period1};
          $period2=$value1[$i]{last_period2};
          $begin_period2=$value1[$i]{begin_period2};
        }
      } else {
        $value1[$i]{value}=${$col}[$i];
      }
    }
  } elsif (ref ($col) eq "HASH") {
    $value1[0]=$col;
    $value1[0]{ring}=1;
    push(@colcount,0);
    if (!defined $dim) {
      $type=$value1[0]{type};
      $hours=$value1[0]{hours};
      $time=$value1[0]{time};
      $dim=$value1[0]{dim};
      $period=$value1[0]{period};
      $period1=$value1[0]{last_period1};
      $period2=$value1[0]{last_period2};
      $begin_period2=$value1[0]{begin_period2};
    }
  } else {
    if ($col eq "") {
      return ("not defined collect reading");
    } else {
      return ("wrong definition at collect parameter, return value: $col");
    }
   # $value1[0]{value}=$col;
  }
 
  if (ref($unit_a) eq "ARRAY") {
    for (my $i=0;$i < @{$unit_a};$i++) {
      $unit1[$i]=${$unit_a}[$i];
    }
  } elsif (!defined $unit_a) {
      $unit1[0]="";
  } else {
      $unit1[0]=$unit_a;
  }

  if (defined $col2) {
    if (ref($col2) eq "ARRAY") {
      for (my $i=0;$i< @{$col2};$i++) {
        delete $value2[$i]{ring};
        if (ref (${$col2}[$i]) eq "ARRAY") {
          $value2[$i]{value}=${$col2}[$i][0];
          $value2[$i]{min}=${$col2}[$i][1];
          $value2[$i]{max}=${$col2}[$i][2];
          $value2[$i]{minColor}=${$col2}[$i][3];
          $value2[$i]{maxColor}=${$col2}[$i][4];
          $value2[$i]{unit}=${$col2}[$i][5];
          $value2[$i]{func}=${$col2}[$i][6];
          $value2[$i]{decfont}=${$col2}[$i][7];
          $value2[$i]{model}=${$col2}[$i][8];
        } elsif (ref (${$col2}[$i]) eq "HASH") {
            $value2[$i]=${$col2}[$i];
            if (@colcount+@col2count < 2) { 
              $value2[$i]{ring}=1;
            }
            push(@col2count,$i);
            if (!defined $dim) {
              $type=$value2[$i]{type};
              $hours=$value2[$i]{hours};
              $time=$value2[$i]{time};
              $dim=$value2[$i]{dim};
              $period=$value2[$i]{period};
            }
        } else {
            $value2[$i]{value}=${$col2}[$i];
        }
      }
    } elsif (ref ($col2) eq "HASH") {
        $value2[0]=$col2;
        delete $value2[0]{ring};
        if (@colcount < 2) { 
          $value2[0]{ring}=1;
        }
        push(@col2count,0);
        if (!defined $dim) {
          $type=$value2[0]{type};
          $hours=$value2[0]{hours};
          $time=$value2[0]{time};
          $dim=$value2[0]{dim};
          $period=$value2[0]{period};
        }  
    } else {
      return ("wrong definition at collect2 parameter: $col2");
      #  $value2[0]{value}=$col2;
    }
  }
  if (ref($unit_b) eq "ARRAY") {
    for (my $i=0;$i < @{$unit_b};$i++) {
      $unit2[$i]=${$unit_b}[$i];
    }
  } elsif (!defined $unit_b) {
      $unit2[0]="";
  } else {
      $unit2[0]=$unit_b;
  }
  
  if (!defined $dim) {
    return("");
  }

  my $bheight=73;
  my $htrans=0;
  
 
  my $out;
  my ($ic,$iscale,$ix,$iy,$rotate);

  my ($size,$plot,$steps,$noFooter,$noColor,$hring,$bwidth);
  ($size,$plot,$steps,$noFooter,$noColor,$hring,$bwidth)=split (/,/,$prop) if (defined $prop);
  
  if (!defined $plot or $plot eq "autoscaling") {
    $plot = "";
  } elsif ($plot eq "fixedscaling") {
    $plot=1;
  }
  if (!defined $steps or $steps eq "nosteps") {
    $steps = "";
  } elsif ($steps eq "steps") {
    $steps = 1;
  }
  if (!defined $noFooter or $noFooter eq "footer") {
    $noFooter = "" 
  } elsif ($noFooter eq "nofooter") {
    $noFooter = 1;
  }
  if (!defined $noColor or $noColor eq "ycolor") {
    $noColor = "";
  } elsif ($noColor eq "noycolor") {
    $noColor = 1;
  }
  
  if (!defined $hring or $hring eq "ring") {
    $hring = "";
  } elsif ($hring  eq "noring") {
    $hring = 0;
  }  elsif ($hring eq "halfring") {
    $hring = 1
  }
    
  
  if (!defined $bwidth or $bwidth eq "") {
    $bwidth=180;
  }
  
  
  my $chart_dim = ($hring eq "" and $type ne "bar") ? $bwidth-90: $bwidth-36 ;
  
  $chart_dim+=8 if ($type eq "bar");
  
  $chart_dim += scalar @colcount ? 0: 18;
  
  $chart_dim -= scalar @col2count ? ($hring eq "1" ? 15 : 17):0;
  
  my $x_prop=int($chart_dim/$dim*100)/100;
  
  my ($dec,$fontformat,$unitformat);
  ($dec,$fontformat,$unitformat)=split (/,/,$decfont) if (defined $decfont);
  $fontformat="" if (!defined $fontformat);
  $unitformat="" if (!defined $unitformat);
  
  my ($dec2,$fontformat2,$unitformat2);
  ($dec2,$fontformat2,$unitformat2)=split (/,/,$decfont2) if (defined $decfont2);
  $fontformat2="" if (!defined $fontformat2);
  $unitformat2="" if (!defined $unitformat2);
  
  my ($header_txt,$header_style);
  ($header_txt,$header_style)=split (/,/,$header) if (defined $header);
  $header_txt="" if (!defined $header_txt);
  $header_style="" if (!defined $header_style);
   
  my ($lr,$lir,$lmm,$lu,$ln,$li);
  ($lr,$lir,$lmm,$lu,$ln,$li)=split (/,/,$lightness) if (defined $lightness);

  my $head;
  #if (defined $header or $hring eq "1" or (@value1+@value2)>2) {
  if (defined $header or $hring eq "1") {
    $head=1;
  }
  
  if (defined $head) {
    $htrans = 24;
    $bheight += 24;
  }
  
  if ($noFooter ne "1") {
    $bheight += 5;
    for (my $i=0;$i<@value1;$i++) {
      if (defined ($value1[$i]{dim})) {
        $bheight += 10;
      }
    }
    if (defined $col2) {
      for (my $i=0;$i<@value2;$i++) {
        if (defined ($value2[$i]{dim})) {
          $bheight += 10;
        }
      }
    }  
  }

  $min=0 if (!defined $min);
  $max=100 if (!defined $max);
  $min2=0 if (!defined $min2);
  $max2=100 if (!defined $max2);
  $dec=1 if (!defined $dec);
  $dec2=1 if (!defined $dec2);
  $size=130 if (!defined $size or $size eq "");
  
  if (defined ($icon)) {
    ($ic,$iscale,$ix,$iy,$rotate)=split(",",$icon);
    $rotate=0 if (!defined $rotate);
    $iscale=1 if (!defined $iscale);
    $ic="" if (!defined($ic));
  }
   
  my $svg_width=int($size/100*$bwidth);
  my $svg_height=int($size/100*$bheight);
  
  my $currColor;
  ($currColor,$minColor,$maxColor)=get_color(${$value1[0]}{value},$min,$max,$minColor,$maxColor,$func);
  
  ##$ic="$ic\@".color($currColor,$ln) if (defined($icon) and $icon !~ /@/);

  if (defined $icon and $icon ne "") {
    if ($ic !~ /@/) {
      $ic="$ic\@".color($currColor,$li);
    } elsif ($ic =~ /^(.*\@)colorVal1/) {
      $ic="$1".color($currColor,$li);
    } elsif ($ic =~ /^(.*\@)colorVal2/) {
      if (defined $col2) {
        my ($currColor2)=get_color(${$value2[0]}{value},$min2,$max2,$minColor2,$maxColor2,$func2);
        $ic="$1".color($currColor2,$li);
      }
    }
  }
$out.= sprintf ('<svg class="DOIF_card" id="%d %d" xmlns="http://www.w3.org/2000/svg" viewBox="10 0 %d %d" width="%d" height="%d" style="width:%dpx; height:%dpx;">',$svg_width,$svg_height,$bwidth,$bheight,$svg_width,$svg_height,$svg_width,$svg_height);
##$out.= sprintf ('<svg class="DOIF_card" id="%d %d" xmlns="http://www.w3.org/2000/svg" viewBox="10 0 %d %d" width="%d" height="%d" style="width:100%; height:100%;">',$svg_width,$svg_height,$bwidth,$bheight,$svg_width,$svg_height);
  $out.= '<defs>';
  $out.= '<linearGradient id="gradcardback" x1="0" y1="1" x2="0" y2="0"><stop offset="0" style="stop-color:rgb(40,40,40);stop-opacity:1"/><stop offset="1" style="stop-color:rgb(64, 64, 64);stop-opacity:1"/></linearGradient>';
  $out.= '</defs>';

  $out.= sprintf('<rect x="11" y="0" width="%d" height="%d" rx="2" ry="2" fill="url(#gradcardback)"/>',$bwidth-2,$bheight);

  $out.='<polyline points="11,23 '.($bwidth+9).',23"  style="stroke:gray; stroke-width:0.7" />' if (defined $head);

  sub r_details {
    my ($min,$max,$minColor,$maxColor,$unit,$unit0,$func,$decfont,$model,$value)=@_;
        
    my $r_min = defined $value->{min} ? $value->{min} : $min;
    my $r_max = defined $value->{max} ? $value->{max} : $max;
    my $r_minColor = defined $value->{minColor} ? $value->{minColor} : $minColor;
    my $r_maxColor = defined $value->{maxColor} ? $value->{maxColor} : $maxColor;
    my $r_unit = defined $value->{unit} ? $value->{unit} : (defined $unit ? $unit : $unit0);
    my $r_unitColor = (split(",",$r_unit))[1];
       $r_unit = (split(",",$r_unit))[0];
    my $r_func = defined $value->{func} ? $value->{func} : $func;
    my $r_decfont = defined $value->{decfont} ? $value->{decfont} : $decfont;
    if (!defined $r_decfont) {
      $r_decfont = "";  
    } else {
      if (defined $r_unitColor) {
        my ($dec,$styleVal,$styleDesc,$unit)=split(",",$r_decfont);
        $dec="" if (!defined $dec);
        $styleVal="" if (!defined $styleVal);
        $styleDesc="" if (!defined $styleDesc);
        $unit="" if (!defined $unit);
        $r_decfont="$dec,$styleVal,fill:$r_unitColor,$unit";
      }
    }
    my $r_model = defined $value->{model} ? $value->{model} : $model;
    return($r_min,$r_max,$r_minColor,$r_maxColor,$r_unit,$r_func,$r_decfont,$r_model);
  }
 
  if (defined $head) {
    $out.= sprintf('<text text-anchor="start" x="%s" y="19" style="fill:#CCCCCC; font-size:12.5px;%s">%s</text>',defined $ic ? 34:14,$header_style,$header_txt) if (defined $header); 
    if (defined $icon and $icon ne "" and  $icon ne " ") {
      my $svg_icon=::FW_makeImage($ic);
      if (!($svg_icon =~ s/\sheight="[^"]*"/ height="18"/)) {
          $svg_icon =~ s/svg/svg height="18"/ 
      }
      if (!($svg_icon =~ s/\swidth="[^"]*"/ width="18"/)) {
          $svg_icon =~ s/svg/svg width="18"/ 
      }
      $out.='<g transform="translate(14,2) scale('.$iscale.') rotate('.$rotate.',9,9) ">';
      $out.= $svg_icon;
      $out.='</g>';
    }
    $out.='<polyline points="11,23 '.($bwidth+9).',23"  style="stroke:gray; stroke-width:0.7" />';
    my $j=0;
    my $count_rings_head = @value1+@value2;
    $count_rings_head -= (@colcount + @col2count >= 2 ? 2 : @colcount + @col2count) if ($hring ne "1");
    for (my $i=0;$i<@value1;$i++) {
      if (!defined $value1[$i]{ring} or $hring eq "1"){
        $out .= sprintf('<g transform = "translate(%s,1)">',$bwidth+7-($count_rings_head-$j++)*43);
        my ($r_min,$r_max,$r_minColor,$r_maxColor,$r_unit,$r_func,$r_decfont,$r_model)=r_details($min,$max,$minColor,$maxColor,$unit1[$i],$unit1[0],$func,$decfont,$model,\%{$value1[$i]});  
        $out .=  ui_Table::ring($value1[$i]{value},$r_min,$r_max,$r_minColor,$r_maxColor,$r_unit,"70,1",$r_func,$r_decfont,$r_model,$lightness);
        $out .= '</g>';
      }
    }
    if (defined $col2) {
      for (my $i=0;$i<@value2;$i++) {
        if (!defined $value2[$i]{ring} or $hring eq "1"){
          $out .= sprintf('<g transform = "translate(%s,1)">',$bwidth+7-($count_rings_head-$j++)*43);
          my ($r_min,$r_max,$r_minColor,$r_maxColor,$r_unit,$r_func,$r_decfont,$r_model)=r_details($min2,$max2,$minColor2,$maxColor2,$unit2[$i],$unit2[0],$func2,$decfont2,$model,\%{$value2[$i]});  
          $out .=  ui_Table::ring($value2[$i]{value},$r_min,$r_max,$r_minColor,$r_maxColor,$r_unit,"70,1",$r_func,$r_decfont,$r_model,$lightness);
          $out .= '</g>';
        }
      }
    }
  }
  
  $out.= sprintf('<g transform="translate(0,%d)">',$htrans);
  $out.='<polyline points="11,73 '.($bwidth+9).',73"  style="stroke:gray; stroke-width:0.7" />' if (!$noFooter);
  $out.= sprintf('<svg width="%s" height="72">',$chart_dim+84);
  $out.= sprintf('<g transform="translate(%s,8) scale(1) ">', scalar @colcount ? 35:17);

  $out.= '<rect x="-2" y="-3" width="'.($chart_dim+4).'" height="56" rx="1" ry="1" fill="url(#gradcardback)"/>';

 
  my ($outDescript,$outplot,$outfooter);
  my @outfooter;

  if ($type eq "bar") {
    my ($sec,$minutes,$hour,$mday,$month,$year,$wday,$yday,$isdst); 
    my @desc;
    my @monthDays;
    my $x;
    my $dimplot=$dim;
    if ($period eq "decade") {
      @desc= qw(0 1 2 3 4 5 6 7 8 9);
    } elsif ($period eq "year") {
      @desc= qw(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez);
    } elsif ($period eq "month") {
      @desc=qw(01 03 05 07 09 11 13 15 17 19 21 23 25 27 29 31);
      ($sec,$minutes,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime();
      @monthDays=qw(31 28 31 30 31 30 31 31 30 31 30 31);
      $monthDays[1]=($year % 4 == 0 and $year % 100 != 0 or $year % 400 == 0) ? 29 : 28;
      $dimplot=32;
    } elsif ($period eq "week") {
      @desc=qw(Mo Di Mi Do Fr Sa So);
    } elsif ($period eq "day") {
      $dimplot=26;
      @desc=qw(00 02 04 06 08 10 12 14 16 18 20 22 24);
    }
    
    
    
    my $xOffset=0.5*$chart_dim/@desc;
    $x=int(($xOffset+$period1*$chart_dim/$dimplot)*10)/10;
    $out.= sprintf('<text text-anchor="end" x=-2.5 y=61 style="fill:#CCCCCC;font-size:7px;">%s</text>',$begin_period2); 
    $out.= sprintf('<circle cx="%s" cy="53" r="1.5" fill=#CCCCCC  opacity="1"/>',$x);
    for (my $i=0;$i<@desc;$i++) {
      $x=int(($i+0.5)*$chart_dim/@desc*10)/10;
      $out.=sprintf('<polyline points="%s,%s %s,%s"  style="stroke:#505050; stroke-width:0.3; stroke-opacity:1" />',$x,0,$x,50);
      $out.=sprintf('<text text-anchor="middle" x="%s" y="61" style="fill:%s;font-size:7px">%s</text>',$x,($period eq "month" and $desc[$i] > $monthDays[$month]) ? "#A0A0A0":"#CCCCCC",$desc[$i]);
    }
    
    if ($period eq "month") {
      my $su=$period1+7-$wday;
      my $first=$su % 7;
      for (my $i=0;$i<5;$i++) {
        my $day=$first+$i*7;
        $x=int(($xOffset+($first+$i*7)*$chart_dim/$dimplot)*10)/10;  
        $out.=sprintf('<polyline points="%s,63,%s,63"  style="stroke:#CCCCCC; stroke-width:1; stroke-opacity:1" />',$x-2,$x+2) if ($day < $monthDays[$month]);
      }
    }
    
    my $minVal;
    my $maxVal;
    for (my $i=0;$i< @value1;$i++) {
      if (defined ($value1[$i]{dim})) {
        my $min=defined $value1[$i]{min_value} ? $value1[$i]{min_value} : $value1[$i]{value} ne "N/A" ? $value1[$i]{value} : $min;
        my $max=defined $value1[$i]{max_value} ? $value1[$i]{max_value} : $value1[$i]{value} ne "N/A" ? $value1[$i]{value} : $max;
        $minVal=$min if (!defined $minVal or $min < $minVal);
        $maxVal=$max if (!defined $maxVal or $max > $maxVal);
      }
    }
    
    my $j=0;
    my $outD="";
    my $outP="";
    for (my $i=0;$i<@value1;$i++) {
      if (defined $value1[$i]{dim}) {
        ($outDescript,$outplot,$outfooter) = plot ($value1[$i],[$min,$minVal],[$max,$maxVal],$minColor,$maxColor,$dec,$func,$steps,$x_prop,$chart_dim, $noColor,$lmm,$ln,$lr,$plot,$bwidth,$noFooter eq "1" ? 0:84+$j*10,undef,-2.5,"end",(defined $unit1[$i]?(split(",",$unit1[$i]))[1] : undef),(defined $unit1[$i] ? ( split(",",$unit1[$i]))[0] : undef));
        $j++;
        $outD.=$outDescript if ($outD eq "");
        $outP.=$outplot;
        push (@outfooter,$outfooter);
      }
    }
    $out.=$outD.$outP;
    $out.= '</g>';
    $out.= '</svg>';
  } else { ## col   
    my $timebeginn=$time-$hours*3600;
    
    my $scale;
    my $scale_strokes;
    my $description=4;
    my $strokes=12;
    
    my $div = $hours > 168 ? ($hours % 168 == 0 ? 168 : ($hours % 24 == 0 ? 24 : 1)):1;
    
    if ($div==168 and $hours/$div/2 == 1) {  #2w
      $description=7;
      $strokes=$description;
    } elsif ($hours <= 168*7) {
      for (my $i=7;$i>=3;$i--) {
        if  ($hours/$div % $i == 0) {
          $description=$i;
          if ($div == 168 and $chart_dim > 130) {
            $strokes=$description*7;
          } else {
            $strokes=$description;
          }
          last;
        }
      }
    }
    $scale=$hours/$description;
    $scale_strokes=$hours/$strokes;
    if ($hours > 2) {
      my ($sec,$minutes,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime($timebeginn);
      my $beginhour=int($hour/$scale)*$scale;
      my $diffsec=($hour-$beginhour)*3600+$minutes*60+$sec;
      my $pos=(1-$diffsec/($scale*3600))*$chart_dim/$description-$x_prop;
      my $pos_strokes=(1-$diffsec/($scale_strokes*3600))*$chart_dim/$strokes-$x_prop;    
       
      for (my $i=0;$i<=$strokes;$i++) {
       my $x=int((($i)*($chart_dim/$strokes)+$pos_strokes)*10)/10;
       $out.=sprintf('<polyline points="%s,%s %s,%s"  style="stroke:#505050; stroke-width:0.3; stroke-opacity:1" />',$x,0,$x,50) if ($x >= 0 and $x <= $chart_dim);
      }
      for (my $i=0;$i<$description;$i++) {
        my $h=$beginhour+($i+1)*$scale;
        $hour=($h >= 24 ? $h % 24:$h);
        my $x=int((($i*($chart_dim/$description)+$pos))*10)/10;
        if ($hours <= 2) {
     #     $out.=sprintf('<text text-anchor="middle" x="%s" y="60" style="fill:#CCCCCC;font-size:7px">%s</text>',$x,::strftime("%H:%M",localtime($time-$hours*3600*(1-$i/3))));
        } elsif ($hours <= 168) {
          if ($hour != 0) {
            $out.=sprintf('<text text-anchor="middle" x="%s" y="60" style="fill:#CCCCCC;font-size:7px">%02d:</text>',$x,$hour);
          } else {
            $out.=sprintf('<text text-anchor="middle" x="%s" y="60" style="fill:#CCCCCC;font-size:7px">%s</text>',$x,substr(::strftime("%a",localtime($timebeginn+$h*3600)),0,2));
          }
        } elsif ($hours <= 168*7) {
           $out.=sprintf('<text text-anchor="middle" x="%s" y="60" style="fill:#CCCCCC;font-size:7px">%s</text>',$x,::strftime("%d.",localtime($timebeginn+$h*3600)));
        } else {
           $out.=sprintf('<text text-anchor="middle" x="%s" y="60" style="fill:#CCCCCC;font-size:7px">%s</text>',$x,::strftime("%d.%m",localtime($timebeginn+$h*3600)));
        }  
      }
    } else {
      for (my $i=0;$i<=12;$i++) {
        my $x=int((($i)*($chart_dim/12)+1)*10)/10-2;      
        $out.=sprintf('<polyline points="%s,%s %s,%s"  style="stroke:#505050; stroke-width:0.3; stroke-opacity:1" />',$x,0,$x,50) if ($x >= 0 and $x <= $chart_dim);
        for (my $i=0;$i<=3;$i++) {
          my $x=int(($i*($chart_dim/3)-1)*10)/10-2;
          $out.=sprintf('<text text-anchor="middle" x="%s" y="60" style="fill:#CCCCCC;font-size:7px">%s</text>',$x+2,::strftime("%H:%M",localtime($time-$hours*3600*(1-$i/3))));
        }
      }
    }
    
    my $minVal;
    my $maxVal;
    for (my $i=0;$i< @value1;$i++) {
      if (defined ($value1[$i]{dim})) {
        my $min=defined $value1[$i]{min_value} ? $value1[$i]{min_value} : $value1[$i]{value} ne "N/A" ? $value1[$i]{value} : $min;
        my $max=defined $value1[$i]{max_value} ? $value1[$i]{max_value} : $value1[$i]{value} ne "N/A" ? $value1[$i]{value} : $max;
        $minVal=$min if (!defined $minVal or $min < $minVal);
        $maxVal=$max if (!defined $maxVal or $max > $maxVal);
      }
    }
    my $j=0;
    my $outD="";
    my $outP="";
    for (my $i=0;$i<@value1;$i++) {
      if (defined $value1[$i]{dim}) {
        ($outDescript,$outplot,$outfooter) = plot ($value1[$i],[$min,$minVal],[$max,$maxVal],$minColor,$maxColor,$dec,$func,$steps,$x_prop,$chart_dim, $j == 0 ? $noColor:-1,$lmm,$ln,$lr,$plot,$bwidth,$noFooter eq "1" ? 0:84+$j*10,undef,-2.5,"end",(defined $unit1[$i]?(split(",",$unit1[$i]))[1] : undef),(defined $unit1[$i] ? ( split(",",$unit1[$i]))[0] : undef));
        $j++;
        $outD.=$outDescript if ($outD eq "");
        $outP.=$outplot;
        push (@outfooter,$outfooter);
      }
    }
    if (defined $col2) {
      my $minVal2;
      my $maxVal2;
      for (my $i=0;$i< @value2;$i++) {
        if (defined ($value2[$i]{dim})) {
          my $min=defined $value2[$i]{min_value} ? $value2[$i]{min_value} : $value2[$i]{value} ne "N/A" ? $value2[$i]{value} : $min;
          my $max=defined $value2[$i]{max_value} ? $value2[$i]{max_value} : $value2[$i]{value} ne "N/A" ? $value2[$i]{value} : $max;
          $minVal2=$min if (!defined $minVal2 or $min < $minVal2);
          $maxVal2=$max if (!defined $maxVal2 or $max > $maxVal2);
        }
      }
      my $offset=@outfooter*10;
      my $j=0;
      my $outD2="";
      for (my $i=0;$i<@value2;$i++) {
        if (defined $value2[$i]{dim}) {
          ($outDescript,$outplot,$outfooter) = plot ($value2[$i],[$min2,$minVal2],[$max2,$maxVal2],$minColor2,$maxColor2,$dec2,$func2,$steps,$x_prop,$chart_dim, $j == 0 ? $noColor:-1,$lmm,$ln,$lr,$plot,$bwidth,$noFooter eq "1" ? 0:84+$offset+$j*10,undef,$chart_dim+3,"start",(defined $unit2[$i]?(split(",",$unit2[$i]))[1] : undef),(defined $unit2[$i] ? ( split(",",$unit2[$i]))[0] : undef));
          $j++;
          $outD2.=$outDescript if ($outD2 eq "");
          $outP.=$outplot;
          push (@outfooter,$outfooter);
        }
      }
      $outD.=$outD2;
    }
    $out.=$outD.$outP;
    $out.= '</g>';
    $out.= '</svg>';

    if ($hring eq "") {
      $out.=sprintf('<g transform="translate(%s,6)">',$bwidth-49);
      if (@colcount >= 2 ) {
        my ($r_min1,$r_max1,$r_minColor1,$r_maxColor1,$r_unit1,$r_func1,$r_decfont1,$r_model)=r_details($min,$max,$minColor,$maxColor,$unit1[$colcount[0]],$unit1[$colcount[0]],$func,$decfont,$model,\%{$value1[$colcount[0]]});  
        my ($r_min2,$r_max2,$r_minColor2,$r_maxColor2,$r_unit2,$r_func2,$r_decfont2)=r_details($min,$max,$minColor,$maxColor,$unit1[$colcount[1]],$unit1[$colcount[1]],$func,$decfont,$model,\%{$value1[$colcount[1]]});  
        $out.= ui_Table::ring2($value1[$colcount[0]]{value},$r_min1,$r_max1,$r_minColor1,$r_maxColor1,$r_unit1,92,$r_func1,$r_decfont1,
               $value1[$colcount[1]]{value},$r_min2,$r_max2,$r_minColor2,$r_maxColor2,$r_unit2,$r_func2,$r_decfont2,$lightness,(defined $head or !defined $icon) ? undef: $icon,$r_model);
      } elsif (@colcount == 0 and @col2count >= 2 ) {
        my ($r_min1,$r_max1,$r_minColor1,$r_maxColor1,$r_unit1,$r_func1,$r_decfont1,$r_model)=r_details($min2,$max2,$minColor2,$maxColor2,$unit2[$col2count[0]],$unit2[$col2count[0]],$func2,$decfont2,$model,\%{$value2[$colcount[0]]});  
        my ($r_min2,$r_max2,$r_minColor2,$r_maxColor2,$r_unit2,$r_func2,$r_decfont2)=r_details($min2,$max2,$minColor2,$maxColor2,$unit2[$col2count[1]],$unit2[$col2count[1]],$func2,$decfont2,$model,\%{$value2[$colcount[1]]});  
        $out.= ui_Table::ring2($value2[$col2count[0]]{value},$r_min1,$r_max1,$r_minColor1,$r_maxColor1,$r_unit1,92,$r_func1,$r_decfont1,
               $value2[$col2count[1]]{value},$r_min2,$r_max2,$r_minColor2,$r_maxColor2,$r_unit2,$r_func2,$r_decfont2,$lightness,(defined $head or !defined $icon) ? undef: $icon,$r_model);
      } elsif (@colcount == 1 and @col2count >= 1) {
        my ($r_min1,$r_max1,$r_minColor1,$r_maxColor1,$r_unit1,$r_func1,$r_decfont1,$r_model)=r_details($min,$max,$minColor,$maxColor,$unit1[$colcount[0]],$unit1[$colcount[0]],$func,$decfont,$model,\%{$value1[$colcount[0]]});  
        my ($r_min2,$r_max2,$r_minColor2,$r_maxColor2,$r_unit2,$r_func2,$r_decfont2)=r_details($min2,$max2,$minColor2,$maxColor2,$unit2[$col2count[0]],$unit2[$col2count[0]],$func2,$decfont2,$model,\%{$value2[$col2count[0]]});  
        $out.= ui_Table::ring2($value1[$colcount[0]]{value},$r_min1,$r_max1,$r_minColor1,$r_maxColor1,$r_unit1,92,$r_func1,$r_decfont1,
               $value2[$col2count[0]]{value},$r_min2,$r_max2,$r_minColor2,$r_maxColor2,$r_unit2,$r_func2,$r_decfont2,$lightness,(defined $head or !defined $icon) ? undef: $icon,$r_model);
      } elsif (@colcount == 1 and @col2count == 0) {
        my ($r_min,$r_max,$r_minColor,$r_maxColor,$r_unit,$r_func,$r_decfont,$r_model)=r_details($min,$max,$minColor,$maxColor,$unit1[$colcount[0]],$unit1[$colcount[0]],$func,$decfont,$model,\%{$value1[$colcount[0]]});  
        $out.= ui_Table::ring($value1[$colcount[0]]{value},$r_min,$r_max,$r_minColor,$r_maxColor,$r_unit,92,$r_func,$r_decfont,$r_model,$lightness,(defined $head or !defined $icon) ? undef: $icon);
      } elsif (@colcount == 0 and @col2count == 1) { 
        my ($r_min,$r_max,$r_minColor,$r_maxColor,$r_unit,$r_func,$r_decfont,$r_model)=r_details($min2,$max2,$minColor2,$maxColor2,$unit2[$col2count[0]],$unit2[$col2count[0]],$func2,$decfont2,$model,\%{$value2[$col2count[0]]});  
        $out.= ui_Table::ring($value2[$col2count[0]]{value},$r_min,$r_max,$r_minColor,$r_maxColor,$r_unit,92,$r_func,$r_decfont,$r_model,$lightness,(defined $head or !defined $icon) ? undef: $icon);
      }
      $out.='</g>';
      $out.=sprintf('<text text-anchor="middle" x="%s" y="68" style="fill:#CCCCCC;font-size:8px">%s</text>',$bwidth-21,::strftime("%H:%M:%S",localtime($time)));
    }
  } # col
  if ($noFooter ne "1") {
    for (my $i=0;$i < @outfooter;$i++) {
      $out.=$outfooter[$i];
    }
  }
  $out.='</g>';
  $out.= '</svg>';
  return ($out);
}

sub bar
{
  my ($val,$min,$max,$header,$minColor,$maxColor,$unit,$bwidth,$bheight,$size,$func,$decfont,$model,$lr,$ln,$icon) = @_;
  my $out;
  my $trans=0;
  my ($format,$value);
  my ($ic,$iscale,$ix,$iy,$rotate);
  my $minCol=$minColor;
  my $ypos;
  
  my ($dec,$fontformat,$unitformat);
  ($dec,$fontformat,$unitformat)=split (/,/,$decfont) if (defined $decfont);
  $fontformat="" if (!defined $fontformat);
  $unitformat="" if (!defined $unitformat);
 
  
  if (defined $lr) {
    if (!defined $ln) {
       $ln=$lr;
    }
  } 
  
  $unit="" if (!defined $unit);
  if (!defined $bheight) {
    if (defined ($icon)) {
      $bheight=75;
    } else {
      $bheight=60;
    }
  }  
  my $height=$bheight-10;
 
  if (!defined $header or $header eq "") {
    $trans = -1;
  } else {
    $bwidth= 63 if (!defined $bwidth);
    $trans = 14;
    $bheight += 14;
  }
  
  $bwidth=63 if (!defined $bwidth);
  $min=0 if (!defined $min);
  $max=100 if (!defined $max);
  
  $dec=1 if (!defined $dec);
  
  
  $ypos= (defined ($icon) and $bheight >= 75) ? int($height/2-3):int($height/2+3);

  ($format,$value,$val)=format_value($val,$min,$dec);

  if (defined $func) {
    $minColor=&{$func}($min);
    $maxColor=&{$func}($max);
  } else {
    $minColor=120 if (!defined $minColor);
    $maxColor=0 if (!defined $maxColor);
  }
  $minCol=$minColor;
  $value=$max if($value>$max);
  $value=$min if ($value<$min);
  $size=100 if (!defined $size);
  
  my $prop=($value-$min)/($max-$min);
  my $val1=int($prop*$height+0.5);
  my $y=$height+6-$val1;
  my $currColor;

  if (defined $func) {
    if (defined($model)) {
      $minColor=&{$func}($value);
    }
    $currColor=&{$func}($value);
  } else {
    if ($minColor < $maxColor) {
      $currColor=$prop*($maxColor-$minColor)+$minColor;
    } else {
      $currColor=(1-$prop)*($minColor-$maxColor)+$maxColor;
    }
    if (defined($model)) {
      $minColor=$currColor;
    }
  }
  
  if (defined ($icon)) {
    ($ic,$iscale,$ix,$iy,$rotate)=split(",",$icon);
    if (defined ($ix)) {
      $ix+=$bwidth/2+3;
    } else {
      $ix=$bwidth/2+3;
    };
    if (defined ($iy)) {
      $iy+=($ypos-14);
    } else {
      $iy=($ypos-14);
    };
    $rotate=0 if (!defined $rotate);
    $iscale=1 if (!defined $iscale);
    $ic="" if (!defined($ic));
  }

   
  my $svg_width=int($size/100*$bwidth);
  my $svg_height=int($size/100*$bheight);
 
  $out.= sprintf ('<svg class="DOIF_bar" xmlns="http://www.w3.org/2000/svg" viewBox="10 0 %d %d" width="%d" height="%d" style="width:%dpx; height:%dpx;">',$bwidth,$bheight,$svg_width,$svg_height,$svg_width,$svg_height);
  $out.= '<defs>';
  $out.= '<linearGradient id="gradbarfont" x1="0" y1="1" x2="0" y2="0"><stop offset="0" style="stop-color:white;stop-opacity:0.3"/><stop offset="1" style="stop-color:rgb(255, 255, 255);stop-opacity:0.1"/></linearGradient>';
  $out.= '<linearGradient id="gradbackg" x1="0" y1="0" x2="1" y2="0"><stop offset="0" style="stop-color:rgb(255,255,255);stop-opacity:0.3"/><stop offset="1" style="stop-color:rgb(0, 0, 0);stop-opacity:0.3"/></linearGradient>';
  $out.= '<linearGradient id="gradbackbar" x1="0" y1="1" x2="0" y2="0"><stop offset="0" style="stop-color:rgb(40,40,40);stop-opacity:1"/><stop offset="1" style="stop-color:rgb(64,64,64);stop-opacity:1"/></linearGradient>';
  $out.= sprintf('<linearGradient id="gradbar_%d_%d_%d" x1="0" y1="0" x2="0" y2="1"><stop offset="0" style="stop-color:%s;stop-opacity:1"/><stop offset="1" style="stop-color:%s;stop-opacity:0.5"/></linearGradient>',$currColor,$minColor,(defined $lr ? $lr:-1),color($currColor,$lr),color($minColor,$lr));
  $out.= '</defs>';
  $out.= sprintf('<rect x="11" y="0" width="%d" height="%d" rx="2" ry="2" fill="url(#gradbackbar)"/>',$bwidth-3,$bheight);
  $out.= sprintf('<text text-anchor="middle" x="%d" y="13" style="fill:white; font-size:14px">%s</text>',$bwidth/2+10,$header) if (defined $header and $header ne ""); 
  $out.= sprintf('<g transform="translate(0,%d)">',$trans);
  my $nullColor;
  my $null;
  if ($min < 0 and $max > 0) {
    $null=$max/($max-$min)*$height+7 if ($min <0);
    if (defined $func) {
      $nullColor=&{$func}(0);
    } else {
      if ($minColor < $maxColor) {
        $nullColor=-$min/($max-$min)*($maxColor-$minColor);
      } else {
        $nullColor=(1+$min/($max-$min))*($minColor-$maxColor);
      }
    }
  }

  $ic="$ic\@".color($currColor,$ln) if (defined($icon) and $icon !~ /@/);

  $out.= sprintf('<text x="23" y="10" style="fill:%s;font-size:9px;">%s</text>',color($maxColor,$ln),sprintf($format,$max));
  $out.= sprintf('<text x="23" y="%d" style="fill:%s;font-size:9px;">%s</text>',$height+9,color($minCol,$ln),sprintf($format,$min));
  $out.= sprintf('<rect x="15" y="%d" width="5" height="%d" rx="1" ry="1" fill="url(#gradbar_%d_%d_%d)"/>',$y,$val1,$currColor,$minColor,(defined $lr ? $lr:-1));
  $out.= sprintf('<rect x="15" y="6" width="5" height="%d" rx="1" ry="1" fill="url(#gradbackg)"/>',$height);
  $out.= sprintf('<line  x1="15.5"  y1="%d" x2="19.5" y2="%d" fill="none" stroke="rgb(192,192,192)" stroke-width="1"/>',$null,$null) if ($min < 0 and $max > 0);;

  if (defined $icon and $icon ne "" and  $icon ne " ") {
    my $svg_icon=::FW_makeImage($ic);
    if(!($svg_icon =~ s/\sheight="[^"]*"/ height="22"/)) {
        $svg_icon =~ s/svg/svg height="22"/ 
    }
    if(!($svg_icon =~ s/\swidth="[^"]*"/ width="22"/)) {
        $svg_icon =~ s/svg/svg width="22"/ 
    }
    $out.='<g transform="translate('.$ix.', '.$iy.') translate(11, 11) scale('.$iscale.') translate(-11, -11) rotate('.$rotate.',11,11) ">';
    $out.= $svg_icon;
    $out.='</g>';
  }
  my ($valInt,$valDec)=split(/\./,sprintf($format,$val));
  
  
  if ($bheight>=75 or !defined ($icon) and $bheight >= 50) {
    if (defined $valDec) {
      $out.= sprintf('<text text-anchor="middle" x="%d" y="%d" style="fill:%s"><tspan style="font-size:16px;font-weight:bold;%s">%s<tspan style="font-size:85%%;">.%s</tspan></tspan></text>',
             $bwidth/2+15,(defined ($icon) ? $ypos+24:$ypos+5),color($currColor,$ln),$fontformat,$valInt,$valDec);
 
      $out.= sprintf('<text text-anchor="middle" x="%d" y="%d" style="fill:%s"><tspan style="font-size:10px;%s">%s</tspan></text>',
             $bwidth/2+15,(defined ($icon) ? $ypos+35:$ypos+16),color($currColor,$ln),$unitformat,$unit);
    } else {
      $out.= sprintf('<text text-anchor="middle" x="%d" y="%d" style="fill:%s"><tspan style="font-size:16px;font-weight:bold;%s">%s</tspan></text>',
             $bwidth/2+15,(defined ($icon) ? $ypos+24:$ypos+5),color($currColor,$ln),$fontformat,$valInt);
      
      $out.= sprintf('<text text-anchor="middle" x="%d" y="%d" style="fill:%s"><tspan style="font-size:10px;%s">%s</tspan></text>',
             $bwidth/2+15,(defined ($icon) ? $ypos+35:$ypos+16),color($currColor,$ln),$unitformat,$unit);
    }
  } else {
    if (defined $valDec) {
      $out.= sprintf('<text text-anchor="middle" x="%d" y="%d" style="fill:%s"><tspan style="font-size:16px;font-weight:bold;%s">%s<tspan style="font-size:85%%;">.%s</tspan></tspan><tspan dx="2" style="font-size:10px;%s">%s</tspan></text>',
             $bwidth/2+15,(defined ($icon) ? $height/2+25:$height/2+12),color($currColor,$ln),$fontformat,$valInt,$valDec,$unitformat,$unit);
    } else {
      $out.= sprintf('<text text-anchor="middle" x="%d" y="%d" style="fill:%s"><tspan style="font-size:16px;font-weight:bold;%s">%s</tspan><tspan dx="2" style="font-size:10px;%s">%s</tspan></text>',
             $bwidth/2+15,(defined ($icon) ? $height/2+25:$height/2+12),color($currColor,$ln),$fontformat,$valInt,$unitformat,$unit);
    }
  }
  
  $out.= '</g>';
 	$out.= '</svg>';
return ($out);
}
 
sub temp_bar {
  my ($value,$min,$max,$header,$width,$height,$size,$lightbar,$lightnumber,$decfont) = @_;
  $min=-20 if (!defined $min or $min eq "");
  $max=60  if (!defined $max or $max eq "");
  $decfont=1 if (!defined $decfont);
  return(bar($value,$min,$max,$header,undef,undef,"°C",$width,$height,$size,\&temp_hue,$decfont,undef,$lightbar,$lightnumber));
} 

sub temp_mbar {
  my ($value,$min,$max,$header,$width,$height,$size,$lightbar,$lightnumber,$decfont) = @_;
  $min=-20 if (!defined $min or $min eq "");
  $max=60  if (!defined $max or $max eq "");
  $decfont=1 if (!defined $decfont);
  return(bar($value,$min,$max,$header,undef,undef,"°C",$width,$height,$size,\&temp_hue,$decfont,1,$lightbar,$lightnumber));
} 

sub icon_temp_bar {
  my ($icon,$value,$min,$max,$header,$width,$height,$size,$lightbar,$lightnumber,$decfont) = @_;
  $min=-20 if (!defined $min or $min eq "");
  $max=60  if (!defined $max or $max eq "");
  $decfont=1 if (!defined $decfont);
  return(bar($value,$min,$max,$header,undef,undef,"°C",$width,$height,$size,\&temp_hue,$decfont,undef,$lightbar,$lightnumber,$icon));
} 

sub icon_temp_mbar {
  my ($icon,$value,$min,$max,$header,$width,$height,$size,$lightbar,$lightnumber,$decfont) = @_;
  $min=-20 if (!defined $min or $min eq "");
  $max=60  if (!defined $max or $max eq "");
  $decfont=1 if (!defined $decfont);
  return(bar($value,$min,$max,$header,undef,undef,"°C",$width,$height,$size,\&temp_hue,$decfont,1,$lightbar,$lightnumber,$icon));
} 


sub hum_bar {
  my ($value,$header,$width,$height,$size,$lightbar,$lightnumber,$decfont) = @_;
  $decfont=0 if (!defined $decfont);
  return(bar($value,0,100,$header,undef,undef,"%",$width,$height,$size,\&hum_hue,$decfont,undef,$lightbar,$lightnumber));
} 

sub hum_mbar {
  my ($value,$header,$width,$height,$size,$lightbar,$lightnumber,$decfont) = @_;
  $decfont=0 if (!defined $decfont);
  return(bar($value,0,100,$header,undef,undef,"%",$width,$height,$size,\&hum_hue,$decfont,1,$lightbar,$lightnumber));
} 

sub icon_hum_bar {
  my ($icon,$value,$header,$width,$height,$size,$lightbar,$lightnumber,$decfont) = @_;
  $decfont=0 if (!defined $decfont);
  return(bar($value,0,100,$header,undef,undef,"%",$width,$height,$size,\&hum_hue,$decfont,undef,$lightbar,$lightnumber,$icon));
} 

sub icon_hum_mbar {
  my ($icon,$value,$header,$width,$height,$size,$lightbar,$lightnumber,$decfont) = @_;
  $decfont=0 if (!defined $decfont);
  return(bar($value,0,100,$header,undef,undef,"%",$width,$height,$size,\&hum_hue,$decfont,1,$lightbar,$lightnumber,$icon));
}

sub icon_bar {
  my ($icon,$val,$min,$max,$minColor,$maxColor,$unit,$dec,$header,$bwidth,$bheight,$size,$func,$lr,$ln) = @_;
  return (bar($val,$min,$max,$header,$minColor,$maxColor,$unit,$bwidth,$bheight,$size,$func,$dec,undef,$lr,$ln,$icon));
}  

sub icon_mbar {
  my ($icon,$val,$min,$max,$minColor,$maxColor,$unit,$dec,$header,$bwidth,$bheight,$size,$func,$lr,$ln) = @_;
  return (bar($val,$min,$max,$header,$minColor,$maxColor,$unit,$bwidth,$bheight,$size,$func,$dec,1,$lr,$ln,$icon));
}

sub  polarToCartesian {
  my ($centerX,$centerY,$radius,$angleInDegrees)=@_;
  my $angleInRadians = ($angleInDegrees-230) * ::pi() / 180.0;
  my $x= sprintf('%1.2f',$centerX + ($radius * cos($angleInRadians)));
  my $y= sprintf('%1.2f',$centerY + ($radius * sin($angleInRadians)));
  return($x,$y);
}

sub  tangens {
  my ($arcBegin,$arcEnd)=@_;
  my $deg=($arcBegin + $arcEnd)/2;
  my $neg=$arcBegin > $arcEnd;
  my $x;
  my $y;
  my $tan;
  my $realDeg=$deg-230+90;
  $realDeg%=360;
  my $quadrant=int((($realDeg + 45) / 90));
  my $tanDeg=($quadrant==1 or $quadrant==3 ? $realDeg-90: $realDeg);
  my $angleInRadians = $tanDeg* ::pi() / 180.0;
  $tan=int(::tan($angleInRadians)*10)/10;
  my $maxDefl=35;
  my $maxVal=50+$maxDefl;
  my $null=100-$maxVal;
  if ($quadrant == 4 or $quadrant == 0) {
    $y=100-(50+$tan*$maxDefl);
    $x=$maxVal;
  } elsif ($quadrant == 2) {  
    $y=50+$tan*$maxDefl;
    $x=$null;
  } elsif ($quadrant == 3 ) {
    $x=50+$tan*$maxDefl;
    $y=$maxVal;
  } elsif ($quadrant == 1) {
    $x=100-(50+$tan*$maxDefl);
    $y=$null;
  }
  if (!$neg) {
    return(int(100-$x),int($y),int($x),int(100-$y));
  } else {
    return(int($x),int(100-$y),int(100-$x),int($y));
  }  
}

sub describeArc {
  my ($x, $y, $radius,$startAngle, $endAngle)=@_;
  if ($startAngle > $endAngle) {
    my $end=$startAngle;
    $startAngle=$endAngle;
    $endAngle=$end;
  }
  my ($start_x,$start_y) = polarToCartesian($x, $y, $radius, $endAngle);
  my ($end_x,$end_y) = polarToCartesian($x, $y, $radius, $startAngle);
  my $largeArcFlag = $endAngle - $startAngle <= 180 ? "0" : "1";
  return ('<path d="M '.$start_x." ".$start_y." A ".$radius." ".$radius." 0 ".$largeArcFlag." 0 ".$end_x." ".$end_y.'" />');
}

sub color {

  my ($hue,$lightness)=@_;
  if (substr($hue,0,1) eq "#") {
   return ($hue);
  }
  my $l;
  my $diff;
  if (defined $lightness and $lightness ne "") {
    $diff=$lightness-50;
  } else {
    $diff=0;
  }
  
  if ($hue>180 and $hue<290) {
    $l=70+$diff;
  } else {
    $l=50+$diff;
  }
  return ("hsl($hue,100%,".$l."%)");
}

sub temp_uring {
  my ($value,$min,$max,$size,$type,$lightring,$lightnumber,$icon,$decfont) = @_;
  $min=-20 if (!defined $min);
  $max=60  if (!defined $max);
  $size=85 if (!defined $size);
  $decfont=1 if (!defined $decfont);
  if (defined($lightnumber)) {
    $lightring="" if (!defined ($lightring));
    $lightring="$lightring,,,,$lightnumber";
  }  
  return(ring($value,$min,$max,undef,undef,"°C",$size,\&temp_hue,$decfont,$type,$lightring,$icon));
}

sub temp_ring{
  my ($value,$min,$max,$size,$lightring,$lightnumber,$decfont) = @_;
  return(temp_uring($value,$min,$max,$size,undef,$lightring,$lightnumber,undef,$decfont));
}

sub temp_mring{
  my ($value,$min,$max,$size,$lightring,$lightnumber,$decfont) = @_;
  return(temp_uring($value,$min,$max,$size,1,$lightring,$lightnumber,undef,$decfont));
}
sub icon_temp_ring{
  my ($icon,$value,$min,$max,$size,$lightring,$lightnumber,$decfont) = @_;
  $size=100 if (!defined $size);
  return(temp_uring($value,$min,$max,$size,undef,$lightring,$lightnumber,$icon,$decfont));
}

sub icon_temp_mring{
  my ($icon,$value,$min,$max,$size,$lightring,$lightnumber,$decfont) = @_;
  $size=100 if (!defined $size);
  return(temp_uring($value,$min,$max,$size,1,$lightring,$lightnumber,$icon,$decfont));
}

sub hum_uring {
  my ($value,$size,$type,$lightring,$lightnumber,$icon,$decfont) = @_;
  $size=85 if (!defined $size);
  $decfont=0 if (!defined $decfont);
  if (defined($lightnumber)) {
    $lightring="" if (!defined ($lightring));
    $lightring="$lightring,,,,$lightnumber";
  }  
  return(ring($value,0,100,undef,undef,"%",$size,\&hum_hue,$decfont,$type,$lightring,$icon));
} 

sub hum_ring{
  my ($value,$size,$lightring,$lightnumber,$decfont) = @_;
  return(hum_uring($value,$size,undef,$lightring,$lightnumber,undef,$decfont));
}

sub hum_mring{
  my ($value,$size,$lightring,$lightnumber,$decfont) = @_;
  return(hum_uring($value,$size,1,$lightring,$lightnumber,undef,$decfont));
}

sub icon_hum_ring{
  my ($icon,$value,$size,$lightring,$lightnumber,$decfont) = @_;
  $size=100 if (!defined $size);
  return(hum_uring($value,$size,undef,$lightring,$lightnumber,$icon,$decfont));
}

sub icon_hum_mring{
  my ($icon,$value,$size,$lightring,$lightnumber,$decfont) = @_;
  $size=100 if (!defined $size);
  return(hum_uring($value,$size,1,$lightring,$lightnumber,$icon,$decfont));
}

sub temp_hum_ring {
  my ($value,$value2,$min,$max,$size,$lightring,$lightnumber,$decfont1,$decfont2) = @_;
  $min=-20 if (!defined $min);
  $max=60  if (!defined $max);
  $size=90 if (!defined $size);
  $decfont1=1 if (!defined $decfont1);
  $decfont2=0 if (!defined $decfont2);
  if (defined($lightnumber)) {
    $lightring="" if (!defined ($lightring));
    $lightring="$lightring,,,,$lightnumber";
  }  
  return(ring2($value,$min,$max,undef,undef,"°C",$size,\&temp_hue,$decfont1,$value2,0,100,0,0,"%",\&hum_hue,$decfont2,$lightring));
} 

sub temp_temp_ring {
  my ($value,$value2,$min,$max,$size,$lightring,$lightnumber,$decfont1,$decfont2) = @_;
  $min=-20 if (!defined $min);
  $max=60  if (!defined $max);
  $size=90 if (!defined $size);
  $decfont1=1 if (!defined $decfont1);
  $decfont2=1 if (!defined $decfont2);
  if (defined($lightnumber)) {
    $lightring="" if (!defined ($lightring));
    $lightring="$lightring,,,,$lightnumber";
  }  
  return(ring2($value,$min,$max,undef,undef,"°C",$size,\&temp_hue,$decfont1,$value2,$min,$max,undef,undef,"°C",\&temp_hue,$decfont2,$lightring));
} 

sub icon_ring {
  my ($icon,$val,$min,$max,$minColor,$maxColor,$unit,$decfont,$size,$func,$l,$model) = @_;
  return(ring ($val,$min,$max,$minColor,$maxColor,$unit,$size,$func,$decfont,$model,$l,$icon));
}

sub icon_mring {
  my ($icon,$val,$min,$max,$minColor,$maxColor,$unit,$decfont,$size,$func,$l) = @_;
  return(ring ($val,$min,$max,$minColor,$maxColor,$unit,$size,$func,$decfont,1,$l,$icon));
}

sub icon_uring {
  my ($model,$icon,$val,$min,$max,$minColor,$maxColor,$unit,$decfont,$size,$func,$l) = @_;
  return(ring ($val,$min,$max,$minColor,$maxColor,$unit,$size,$func,$decfont,$model,$l,$icon));
}

sub mring
{
  my ($val,$min,$max,$minColor,$maxColor,$unit,$size,$func,$decfont,$l) = @_;
  return(ring($val,$min,$max,$minColor,$maxColor,$unit,$size,$func,$decfont,1,$l));
}

sub uring
{
  my ($model,$val,$min,$max,$minColor,$maxColor,$unit,$size,$func,$decfont,$l) = @_;
  return(ring($val,$min,$max,$minColor,$maxColor,$unit,$size,$func,$decfont,$model,$l));
}

sub icon_ring2 {
    my ($icon,$val,$min,$max,$minColor,$maxColor,$unit,$size,$func,$dec,$val2,$min2,$max2,$minColor2,$maxColor2,$unit2,$func2,$dec2,$l,$model) = @_;
    return (ring2($val,$min,$max,$minColor,$maxColor,$unit,$size,$func,$dec,$val2,$min2,$max2,$minColor2,$maxColor2,$unit2,$func2,$dec2,$l,$icon,$model));
}


sub icon_temp_hum_ring {
  my ($icon,$value,$value2,$min,$max,$size,$lightring,$lightnumber,$decfont1,$decfont2) = @_;
  $min=-20 if (!defined $min);
  $max=60  if (!defined $max);
  $size=100 if (!defined $size);
  $decfont1=1 if (!defined $decfont1);
  $decfont2=0 if (!defined $decfont2);
  if (defined($lightnumber)) {
    $lightring="" if (!defined ($lightring));
    $lightring="$lightring,,,,$lightnumber";
  }  
  return(ring2($value,$min,$max,undef,undef,"°C",$size,\&temp_hue,$decfont1,$value2,0,100,0,0,"%",\&hum_hue,$decfont2,$lightring,$icon));
} 

sub icon_temp_temp_ring {
  my ($icon,$value,$value2,$min,$max,$size,$lightring,$lightnumber,$decfont1,$decfont2) = @_;
  $min=-20 if (!defined $min);
  $max=60  if (!defined $max);
  $size=100 if (!defined $size);
  $decfont1=1 if (!defined $decfont1);
  $decfont2=1 if (!defined $decfont2);
  if (defined($lightnumber)) {
    $lightring="" if (!defined ($lightring));
    $lightring="$lightring,,,,$lightnumber";
  }  
  return(ring2($value,$min,$max,undef,undef,"°C",$size,\&temp_hue,$decfont1,$value2,$min,$max,undef,undef,"°C",\&temp_hue,$decfont2,$lightring,$icon));
} 

sub ring_param {
  
  my ($val,$min,$max,$minColor,$maxColor,$unit,$func,$decfont,$model,$sizeHalf) = @_;
  my $out;
  my $val_color;
  my $nullColor;
  
  my ($size,$half);
  ($size,$half)=split (/,/,$sizeHalf) if (defined $sizeHalf);
  $size=100 if (!defined $size or $size eq "");
  $half="" if (!defined $half);

  my ($monochrom,$minMax,$innerRing,$pointer,$mode);
  ($monochrom,$minMax,$innerRing,$pointer,$mode)=split (/,/,$model) if (defined $model);
  if (!defined $monochrom or $monochrom eq "gradient") {
    $monochrom="";
  } elsif ($monochrom eq "nogradient") {
    $monochrom=1;
  }
  if (!defined $minMax or $minMax eq "nominmaxvalue") {
    $minMax="";
  } elsif ($minMax eq "minmaxvalue") {
    $minMax=1;
  }
  
  
  if (!defined $innerRing or $innerRing eq "noinnerring") {
    $innerRing=""; 
  } elsif ($innerRing eq "innerring") {
      $innerRing=1;
  }      
  
  $pointer="" if (!defined $pointer or $pointer eq "nopointer");

  if (!defined $mode or $mode eq "minmax") {
    $mode="";
  } elsif ($mode eq "negzeropos") {
    $mode=1;
  } elsif ($mode eq "zeronegpos") {
    $mode=2;
  }
 
  my ($dec,$fontformat,$unitformat,$unittext);
  ($dec,$fontformat,$unitformat,$unittext)=split (/,/,$decfont,4) if (defined $decfont);
  $dec="" if (!defined $dec);
  $fontformat="" if (!defined $fontformat);
  $unitformat="" if (!defined $unitformat);
  $unittext="" if (!defined $unittext);
  
  $min=0 if (!defined $min);
  $max=100 if (!defined $max);
  
  $dec=1 if ($dec eq "");
  
  my ($format,$value);
  ($format,$value,$val)=format_value($val,$min,$dec);
 
  $value=$max if ($value>$max);
  $value=$min if ($value<$min);
  
  my ($m,$n);

  my $currColor;
  
  if (ref($func) eq "CODE") {
    $minColor=&{$func}($min);
    $maxColor=&{$func}($max);
    $nullColor=&{$func}(0);
    $currColor=&{$func}($value);
  } elsif (ref($func) eq "ARRAY") {
    $minColor=${$func}[1];
    $maxColor=${$func}[-1];
    for (my $i=0;$i<@{$func};$i+=2) {
      if ($value <= ${$func}[$i]) {
        $currColor=${$func}[$i+1];
        last;
      }
    }
    for (my $i=0;$i<@{$func};$i+=2) {
      if (${$func}[$i]>=0) {
        $nullColor=${$func}[$i+1];
        last;
      }
    }
  } else {
    $minColor=120 if (!defined $minColor);
    $maxColor=0 if (!defined $maxColor);
    ($m,$n)=m_n($min,$minColor,$max,$maxColor);
    $currColor=$value*$m+$n;
    $nullColor=$n;
  }
  
  my $minCol=$minColor;
  my $maxCol=$maxColor;
  
  my ($minArc,$maxArc);
  if ($half eq "1") {
    $maxArc=230;
    $minArc=50;
  } else {
    $maxArc=280;
    $minArc=0;
  }

  if ($mode eq "2") {
     my $maximum=$max;
     if ($value < 0) {
       $maximum=abs($min);
     }
    ($m,$n)=m_n(0,$minArc,$maximum,$maxArc);
  } else {
    ($m,$n)=m_n($min,$minArc,$max,$maxArc);
  }
  my ($arcBegin,$arcEnd);

  my $beginColor=$minColor;
  my $endColor=$currColor;
 
  if ($pointer) {
    $arcBegin =  int(($value*$m+$n-$pointer/2)*10)/10;
    $arcEnd = int(($value*$m+$n+$pointer/2)*10)/10;
  } else {
    if ($mode eq "") {
      $arcBegin = $minArc;
      $arcEnd = int(($value*$m+$n)*10)/10;
    } elsif ($mode eq "1") {
      $arcBegin = int($n*10)/10;
      $arcEnd = int(($value*$m+$n)*10)/10;
      $beginColor = $nullColor;
      if ($arcBegin< $minArc) {
        $arcBegin=$minArc ;
        $beginColor=$minColor;
      }
      $arcEnd=$minArc if ($arcEnd < $minArc);
    } elsif ($mode eq "2") {
      $arcBegin = $minArc;
      $arcEnd = $value < 0 ? int((-$value*$m+$n)*10)/10:int(($value*$m+$n)*10)/10;
      $beginColor = $nullColor;
      if ($value < 0) {
        $maxCol=$minCol;
        $max=$min;
      }
      $min=0;
      $minCol=$nullColor;
    }
  }
  
  
return ($min,$max,$beginColor,$endColor,$minCol,
       $maxCol,$nullColor,$minArc, $maxArc,$arcBegin,$arcEnd,$currColor,
       $dec,$fontformat,$unitformat,$unittext,$format,$val,
       $monochrom,$minMax,$innerRing,$pointer,$mode,$half,$size
       );
}  

sub ring
{
  my ($val_a,$minVal,$maxVal,$minColor,$maxColor,$unit,$sizeHalf,$func,$decfont,$model,$lightness,$icon) = @_;
  
  my ($min,$max,$beginColor,$endColor,$minCol,
       $maxCol,$nullColor,$minArc, $maxArc,$arcBegin,$arcEnd,$currColor,
       $dec,$fontformat,$unitformat,$unittext,$format,$val,
       $monochrom,$minMax,$innerRing,$pointer,$mode,$half,$size
      )=ring_param($val_a,$minVal,$maxVal,$minColor,$maxColor,$unit,$func,$decfont,$model,$sizeHalf);
  my $out;
 
  my ($lr,$lir,$lmm,$lu,$ln,$li);
  ($lr,$lir,$lmm,$lu,$ln,$li)=split (/,/,$lightness) if (defined $lightness);
  $lr=50 if (!defined $lr or $lr eq "");
  $lir=50 if (!defined $lir or $lir eq "");
  $lmm=40 if (!defined $lmm or $lmm eq "");
  $lu=40 if (!defined $lu or $lu eq "");
  $ln=50 if (!defined $ln or $ln eq "");
  $li=40 if (!defined $li or $li eq "");


  my ($div,$yNum,$yUnit,$high);
  if ($half eq "1") {
    $div=2;
    $yNum=28;
    $yUnit=15;
    $high=29;
  } else {
    $div=1;
    $yNum=34;
    $yUnit=47;
    $high=58;
  }
  my $width=int($size/100*63);
  my $height=int($size/100*58);

  my ($ic,$iscale,$ix,$iy,$rotate)=();
  if (defined ($icon)) {
    ($ic,$iscale,$ix,$iy,$rotate)=split(/,/,$icon);
    if (defined ($ix)) {
      $ix+=32;
    } else {
      $ix=32;
    };
    if (defined ($iy)) {
      $iy+=8.5;
    } else {
      $iy=8.5;
    };
    $rotate=0 if (!defined $rotate);
    $iscale=1 if (!defined $iscale);
    $ic="" if (!defined($ic));
  }
  
  if (defined $icon and $icon ne "") {
    $ic="$ic\@".color($currColor,$li) if ($ic !~ /@/); 
  }

  if ($monochrom eq "1") {
    $beginColor=$currColor;
  }
  
  $out.= sprintf('<svg class="DOIF_ring" xmlns="http://www.w3.org/2000/svg" viewBox="10 0 63 %d" width="%d" height="%d" style="width:%dpx; height:%dpx">',$high,$width,$height/$div,$width,$height/$div);
  $out.= '<defs>';
  $out.= '<linearGradient id="gradbackring1" x1="0" y1="1" x2="0" y2="0"><stop offset="0" style="stop-color:rgb(64,64,64);stop-opacity:1"/><stop offset="1" style="stop-color:rgb(40, 40, 40);stop-opacity:1"/></linearGradient>';
  if (!$pointer) {
    $out.= sprintf('<linearGradient id="grad_ring1_%s_%s_%s_%s_%s_%s" x1="%s%%" y1="%s%%" x2="%s%%" y2="%s%%"><stop offset="0" style="stop-color:%s; stop-opacity:0.6"/>\
    <stop offset="1" style="stop-color:%s;stop-opacity:1"/></linearGradient>',$beginColor,$endColor,$arcBegin,$arcEnd,(defined $lr ? $lr:0),$mode,tangens($arcBegin,$arcEnd),color($beginColor,$lr),color($endColor,$lr));
  } 
  if ($innerRing and ref($func) ne "ARRAY") {
    $out.= sprintf('<linearGradient id="grad_ring_max_%s_%s_%s" x1="%s%%" y1="%s%%" x2="%s%%" y2="%s%%"><stop offset="0" style="stop-color:%s; stop-opacity:1"/>\
    <stop offset="1" style="stop-color:%s;stop-opacity:1"/></linearGradient>',$minCol,$maxCol,(defined $lir ? $lir:0),tangens($minArc, $maxArc),color($minCol,$lir),color($maxCol,$lir),);
  }
  $out.= '<linearGradient id="grad_ring1stroke" x1="1" y1="0" x2="0" y2="0"><stop offset="0" style="stop-color:rgb(80,80,80); stop-opacity:0.9"/>\
  <stop offset="1" style="stop-color:rgb(48,48,48); stop-opacity:0.9"/></linearGradient>';
  $out.='</defs>';
  $out.='<circle cx="41" cy="30" r="26.5" fill="url(#gradbackring1)" />';
  $out.='<g stroke="url(#grad_ring1stroke)" fill="none" stroke-width="3.5">';
  $out.=describeArc(41, 30, 28, $minArc, $maxArc);
  $out.='</g>';
  
  if ($pointer) {
    $out.='<g stroke="'.color($currColor,$lr).'" fill="none" stroke-width="3.5">';
  } else {
    $out.=sprintf('<g stroke="url(#grad_ring1_%s_%s_%s_%s_%s_%s)" fill="none" stroke-width="2.5">',$beginColor,$endColor,$arcBegin,$arcEnd,(defined $lr ? $lr:0),$mode);
  }
  $out.=describeArc(41, 30, 28, $arcBegin, $arcEnd);
  $out.='</g>';
  
  if ($innerRing) {
    if (ref($func) eq "ARRAY"){
      my $from=$minArc;
      my $diff=$max-$min;
      for (my $i=0;$i<@{$func};$i+=2) {
        my $curr=${$func}[$i];
        my $color=${$func}[$i+1];
        my $to=int((($curr-$min)/$diff*($maxArc-$minArc)+$minArc)*10)/10;
        $to-=1 if ($to > $minArc+1 and not($to == $maxArc));
        $out.=sprintf('<g stroke="%s" fill="none" stroke-width="0.7" style="%s">',color($color,$lir),($innerRing eq "1" ? "":$innerRing));
        $out.=describeArc(41, 30, 25.5, $from, $to);
        $out.='</g>';
        $from=$to+2;
      }
    } else {
      $out.=sprintf('<g stroke="url(#grad_ring_max_%s_%s_%s)" fill="none" stroke-width="0.7" style="%s">',$minCol,$maxCol,(defined $lir ? $lir:0),($innerRing eq "1" ? "":$innerRing));
      $out.=describeArc(41, 30, 25.5, $minArc, $maxArc);
      $out.='</g>';
    }
  }
 
  if (defined $icon and $icon ne "" and  $icon ne " ") {
    my $svg_icon=::FW_makeImage($ic);
    if(!($svg_icon =~ s/\sheight="[^"]*"/ height="18"/)) {
        $svg_icon =~ s/svg/svg height="18"/ }
    if(!($svg_icon =~ s/\swidth="[^"]*"/ width="18"/)) {
        $svg_icon =~ s/svg/svg width="18"/ }
    $out.='<g transform="translate('.$ix.', '.$iy.') translate(9, 9) scale('.$iscale.') translate(-9, -9) rotate('.$rotate.',9,9) ">';
    $out.= $svg_icon;
    $out.='</g>';
  }
  
  my $icflag = (defined ($icon) and $icon ne "") ? 1:0;
  my ($valInt,$valDec)=split(/\./,sprintf($format,$val));

  if (defined $valDec) {
      $out.= sprintf('<text text-anchor="middle" x="41" y="%s" style="fill:%s;font-size:%spx;font-weight:bold;%s">%s<tspan style="font-size:85%%;">.%s</tspan><tspan style="fill:%s;font-size:60%%;font-weight:normal;">%s</tspan></text>',
                     ($icflag ? 41:$yNum),color($currColor,$ln),(defined $icon or $half eq "1") ? 14:15,$fontformat,$valInt,$valDec,color($currColor,$lu),$unittext);
  } else {
    $out.= sprintf('<text text-anchor="middle" x="41" y="%s" style="fill:%s;font-size:%spx;font-weight:bold;%s">%s<tspan style="fill:%s;font-size:60%%;font-weight:normal;">%s</tspan></text>',
                   ($icflag ? 41:$yNum),color($currColor,$ln),(defined $icon or $half eq "1") ? 14:15,$fontformat,$valInt,color($currColor,$lu),$unittext);
  }
  $out.= sprintf('<text text-anchor="middle" x="41" y="%s" style="fill:%s;font-size:%spx;%s">%s</text>',
                 ($icflag ? 50.5:$yUnit),color($currColor,$lu),($icflag or $half eq "1") ? 8:8,$unitformat,$unit) if (defined $unit);
  
  if ($minMax) {
    $out.= sprintf('<text text-anchor="middle" x="23" y="58" style="fill:%s;font-size:6px;%s">%s</text>',color($minCol,$lmm),($minMax eq "1" ? "":$minMax),$min);
    $out.= sprintf('<text text-anchor="middle" x="59" y="58" style="fill:%s;font-size:6px;%s">%s</text>',color($maxCol,$lmm),($minMax eq "1" ? "":$minMax),$max);
  }
  $out.= '</svg>';
 
  return ($out);
}

sub ring2
{
  my ($val_a,$minVal,$maxVal,$minColor,$maxColor,$unit,$size,$func,$decfont,$val_a2,$minVal2,$maxVal2,$minColor2,$maxColor2,$unit2,$func2,$decfont2,$lightness,$icon,$model) = @_;
  
  my ($min,$max,$beginColor,$endColor,$minCol,
       $maxCol,$nullColor,$minArc, $maxArc,$arcBegin,$arcEnd,$currColor,
       $dec,$fontformat,$unitformat,$unittext,$format,$val,
       $monochrom,$minMax,$innerRing,$pointer,$mode
     ) = ring_param($val_a,$minVal,$maxVal,$minColor,$maxColor,$unit,$func,$decfont,$model);

  my ($min2,$max2,$beginColor2,$endColor2,$minCol2,
       $maxCol2,$nullColor2,$minArc2,$maxArc2,$arcBegin2,$arcEnd2,$currColor2,
       $dec2,$fontformat2,$unitformat2,$unittext2,$format2,$val2
     ) = ring_param($val_a2,$minVal2,$maxVal2,$minColor2,$maxColor2,$unit2,$func2,$decfont2,$model);
  
  if ($monochrom eq "" or $monochrom eq "1") {
    $beginColor=$currColor;
    $beginColor2=$currColor2;
  }
  
  my $out;
  
  my ($lr,$lir,$lmm,$lu,$ln,$li);
  ($lr,$lir,$lmm,$lu,$ln,$li)=split (/,/,$lightness) if (defined $lightness);
  $lr=50 if (!defined $lr or $lr eq "");
  $lir=50 if (!defined $lir or $lir eq "");
  $lmm=40 if (!defined $lmm or $lmm eq "");
  $lu=40 if (!defined $lu or $lu eq "");
  $ln=50 if (!defined $ln or $ln eq "");
  $li=40 if (!defined $li or $li eq "");
  
  $size=100 if (!defined $size or $size eq "");
  my $width=int($size/100*63);
  my $height=int($size/100*58);
 
  my ($ic,$iscale,$ix,$iy,$rotate)=();
  if (defined ($icon)) {
    ($ic,$iscale,$ix,$iy,$rotate)=split(",",$icon);
    if (defined ($ix)) {
      $ix+=20;
    } else {
      $ix=20;
    };
    if (defined ($iy)) {
      $iy+=23;
    } else {
      $iy=23;
    };
    $rotate=0 if (!defined $rotate);
    $iscale=1 if (!defined $iscale);
    $ic="" if (!defined($ic));
  }
  
  if (defined $icon and $icon ne "") {
    if ($ic !~ /@/) {
      $ic="$ic\@".color($currColor,$li);
    } elsif ($ic =~ /^(.*\@)colorVal1/) {
      $ic="$1".color($currColor,$li);
    } elsif ($ic =~ /^(.*\@)colorVal2/) {
        $ic="$1".color($currColor2,$li);
    }
  }
  
  $out.= sprintf('<svg class="DOIF_ring" xmlns="http://www.w3.org/2000/svg" viewBox="10 0 63 58" width="%d" height="%d" style="width:%dpx; height:%dpx">',$width,$height,$width,$height);
  $out.= '<defs>';
  $out.= '<linearGradient id="gradbackring2" x1="0" y1="1" x2="0" y2="0"><stop offset="0" style="stop-color:rgb(64,64,64);stop-opacity:1"/><stop offset="1" style="stop-color:rgb(40,40,40);stop-opacity:1"/></linearGradient>';

  if ($innerRing and ref($func) ne "ARRAY") {
    $out.= sprintf('<linearGradient id="grad_ring_max_%s_%s_%s" x1="%s%%" y1="%s%%" x2="%s%%" y2="%s%%"><stop offset="0" style="stop-color:%s; stop-opacity:1"/>\
    <stop offset="1" style="stop-color:%s;stop-opacity:1"/></linearGradient>',$minCol,$maxCol,(defined $lir ? $lir:0),tangens($minArc, $maxArc),color($minCol,$lir),color($maxCol,$lir),);
  }
  
  $out.= sprintf('<linearGradient id="grad2_ring1_%s_%s_%s_%s_%s_%s" x1="%s%%" y1="%s%%" x2="%s%%" y2="%s%%"><stop offset="0" style="stop-color:%s; stop-opacity:0.6"/>\
        <stop offset="1" style="stop-color:%s;stop-opacity:1"/></linearGradient>',$beginColor,$endColor,$arcBegin,$arcEnd,(defined $lr ? $lr:0),$mode,tangens($arcBegin,$arcEnd),color($beginColor,$lr),color($endColor,$lr));
  $out.= sprintf('<linearGradient id="grad2_ring2_%s_%s_%s_%s_%s_%s" x1="%s%%" y1="%s%%" x2="%s%%" y2="%s%%"><stop offset="0" style="stop-color:%s; stop-opacity:0.6"/>\
        <stop offset="1" style="stop-color:%s;stop-opacity:1"/></linearGradient>',$beginColor2,$endColor2,$arcBegin2,$arcEnd2,(defined $lr ? $lr:0),$mode,tangens($arcBegin2,$arcEnd2),color($beginColor2,$lr),color($endColor2,$lr));
  $out.= '<linearGradient id="grad_ring2stroke" x1="1" y1="0" x2="0" y2="0"><stop offset="0" style="stop-color:rgb(80,80,80); stop-opacity:1"/>\
  <stop offset="1" style="stop-color:rgb(48,48,48); stop-opacity:0.9"/></linearGradient>';
  $out.='</defs>';
  $out.='<circle cx="41" cy="30" r="26.5" fill="url(#gradbackring2)" />';
  $out.='<g stroke="url(#grad_ring2stroke)" fill="none" stroke-width="3.5">';
  $out.=describeArc(41, 30, 28, $minArc, $maxArc);
  $out.='</g>';

  my ($stroke1,$radius1,$stroke2,$radius2);
  if ($innerRing) {
    ($stroke1,$radius1,$stroke2,$radius2)=(2,28.5,2,24.9);
    if (ref($func) eq "ARRAY"){
      my $from=$minArc;
      my $diff=$max-$min;
      for (my $i=0;$i<@{$func};$i+=2) {
        my $curr=${$func}[$i];
        my $color=${$func}[$i+1];
        my $to=int((($curr-$min)/$diff*($maxArc-$minArc)+$minArc)*10)/10;
        $to-=1 if ($to > $minArc+1 and not($to == $maxArc));
        $out.=sprintf('<g stroke="%s" fill="none" stroke-width="0.7" style="%s">',color($color,$lir),($innerRing eq "1" ? "":$innerRing));
        $out.=describeArc(41, 30, 26.7, $from, $to);
        $out.='</g>';
        $from=$to+2;
      }
    } else {
      $out.=sprintf('<g stroke="url(#grad_ring_max_%s_%s_%s)" fill="none" stroke-width="0.7" style="%s">',$minCol,$maxCol,(defined $lir ? $lir:0),($innerRing eq "1" ? "":$innerRing));
      $out.=describeArc(41, 30, 26.7, $minArc, $maxArc);
      $out.='</g>';
    }
  } else {
    ($stroke1,$radius1,$stroke2,$radius2)=(2.3,28.2,2,25.2);
  }
  
  if ($pointer) {
    $out.='<g stroke="'.color($currColor,$lr).'" fill="none" stroke-width="3.3">';
  } else {
    $out.=sprintf('<g stroke="url(#grad2_ring1_%s_%s_%s_%s_%s_%s)" fill="none" stroke-width="%s">',$beginColor,$endColor,$arcBegin,$arcEnd,(defined $lr ? $lr:0),$mode,$stroke1);
  }
  
  $out.=describeArc(41, 30, $radius1, $arcBegin, $arcEnd);
  $out.='</g>';

  if ($pointer) {
    $out.='<g stroke="'.color($currColor2,$lr).'" fill="none" stroke-width="3">';
  } else {
    $out.=sprintf('<g stroke="url(#grad2_ring2_%s_%s_%s_%s_%s_%s)" fill="none" stroke-width="%s">',$beginColor2,$endColor2,$arcBegin2,$arcEnd2,(defined $lr ? $lr:0),$mode,$stroke2);
  }
  $out.=describeArc(41, 30, $radius2, $arcBegin2, $arcEnd2);
  $out.='</g>';
  
  if (defined $icon and $icon ne "" and  $icon ne " ") {
    my $svg_icon=::FW_makeImage($ic);
    if(!($svg_icon =~ s/\sheight="[^"]*"/ height="15"/)) {
        $svg_icon =~ s/svg/svg height="15"/ }
    if(!($svg_icon =~ s/\swidth="[^"]*"/ width="15"/)) {
        $svg_icon =~ s/svg/svg width="15"/ }
    $out.='<g transform="translate('.$ix.', '.$iy.') translate(7.5, 7.5) scale('.$iscale.') translate(-7.5, -7.5) rotate('.$rotate.',7.5,7.5)">';
    $out.= $svg_icon;
    $out.='</g>';
 }

  my $icflag = (defined ($icon) and $icon ne "") ? 1:0;
  my ($valInt,$valDec)=split(/\./,sprintf($format,$val));  

  if (defined $valDec) {
    $out.= sprintf('<text text-anchor="middle" x="%s" y="29.5" style="fill:%s;font-size:%spx;font-weight:bold;%s">%s<tspan style="font-size:85%%;">.%s</tspan><tspan style="fill:%s;font-size:60%%;font-weight:normal;">%s</tspan></text>',
                   ($icflag ? 50:41),color($currColor,$ln),(defined ($icon) ? 13:14),$fontformat,$valInt,$valDec,color($currColor,$lu),$unittext);
  } else {
    $out.= sprintf('<text text-anchor="middle" x="%s" y="29.5" style="fill:%s;font-size:%spx;font-weight:bold;%s">%s<tspan style="fill:%s;font-size:60%%;font-weight:normal;">%s</tspan></text>',
                   ($icflag ? 50:41),color($currColor,$ln),(defined ($icon) ? 13:14),$fontformat,$valInt,color($currColor,$lu),$unittext);
  }
  $out.= sprintf('<text text-anchor="middle" x="41" y="16.5" style="fill:%s;font-size:8px;%s">%s</text>',color($currColor,$lu),$unitformat,$unit) if (defined $unit);
  
  my ($valInt2,$valDec2)=split(/\./,sprintf($format2,$val2));  
  
  if (defined $valDec2) {
    $out.= sprintf('<text text-anchor="middle" x="%s" y="%s" style="fill:%s;font-size:%spx;font-weight:bold;%s">%s<tspan style="font-size:85%%;">.%s</tspan><tspan style="fill:%s;font-size:60%%;font-weight:normal;">%s</tspan></text>',
                   ($icflag ? 50:41),($icflag ? 41:42.5),color($currColor2,$ln),(defined ($icon) ? 12:13),$fontformat2,$valInt2,$valDec2,color($currColor2,$lu),$unittext2);
  } else {
    $out.= sprintf('<text text-anchor="middle" x="%s" y="%s" style="fill:%s;font-size:%spx;font-weight:bold;%s">%s<tspan style="fill:%s;font-size:60%%;font-weight:normal;">%s</tspan></text>',
                   ($icflag ? 50:41),($icflag ? 41:42.5),color($currColor2,$ln),(defined ($icon) ? 12:13),$fontformat2,$valInt2,color($currColor2,$lu),$unittext2);
  }
  $out.= sprintf('<text text-anchor="middle" x="41" y="%s" style="fill:%s;font-size:8px;%s">%s</text>',($icflag ? 50:52),color($currColor2,$lu),$unitformat2,$unit2) if (defined $unit2);
  
  if ($minMax) {
    $out.= sprintf('<text text-anchor="middle" x="23" y="58" style="fill:%s;font-size:6px;%s">%s</text>',color($minCol,$lmm),($minMax eq "1" ? "":$minMax),$min);
    $out.= sprintf('<text text-anchor="middle" x="59" y="58" style="fill:%s;font-size:6px;%s">%s</text>',color($maxCol,$lmm),($minMax eq "1" ? "":$minMax),$max);
  }

  
  $out.= '</svg>';
  return ($out);
}

sub dec 
{
  my ($format,$value)=@_;
  return(split(/\./,sprintf($format,$value)));
}

sub y_h
{
  my ($value,$min,$max,$height,$val_sum,$mode) = @_;
  my $offset=4;
  $offset=0 if ($mode == 0);
  if ($value > $max) {
    $value=$max;
  } elsif ($value < $min) {
    $value=$min;
  }
  
  if ($min > 0 and $max > 0) {
    $max-=$min;
    $value-=$min;
    $min=0;
  } elsif ($min < 0 and $max < 0) {
    $min-=$max;
    $value-=$max;
    $max=0;
  }
  
  my $prop=$value/($max-$min);
  my $h=int(abs($prop*($height))+$offset);
  my $y;
  my $null;
 
  $null=$max/($max-$min)*$height;
  if ($value <= 0) {
    if ($mode==2){
      $y=int($null-$val_sum);
    } else {
      $y=$null;
    }
  } else {
  if ($mode==2){
    $y=int($null+$offset-$val_sum-$h);
   } else {
    $y=int($null+$offset-$h);
   }
  }
  $null=undef if ($max == 0 or $min == 0);
  return ($y,$h,$null);
}


sub hsl_color 
{
  my ($color,$corr_light)=@_;
  my ($hue,$sat,$light)=split(/\./,$color);
  $sat=100 if (!defined $sat);
  $light=50 if (!defined $light);
  $light+=$corr_light if (defined $corr_light);
  $light=0 if ($light < 0);
  $light=100 if ($light > 100);
  return("hsl($hue,$sat%,$light%)");
}
  
sub cylinder_bars { 
  my ($header,$min,$max,$unit,$bwidth,$height,$size,$dec,@values) = @_;
  return(cylinder_mode ($header,$min,$max,$unit,$bwidth,$height,$size,$dec,0,@values));
}  

sub cylinder {  
  my ($header,$min,$max,$unit,$bwidth,$height,$size,$dec,@values) = @_;
  return(cylinder_mode ($header,$min,$max,$unit,$bwidth,$height,$size,$dec,1,@values));
}  

sub cylinder_s {  
  my ($header,$min,$max,$unit,$bwidth,$height,$size,$dec,@values) = @_;
  return(cylinder_mode ($header,$min,$max,$unit,$bwidth,$height,$size,$dec,2,@values));
}

sub cylinder_mode
{
  my ($header,$min,$max,$unit,$bwidth,$height,$size,$dec,$mode,@values) = @_;

  my $out;
  my $ybegin;
  my $bheight;
  my $trans=0;
  my $heightval=10;
 
  $size=100 if (!defined $size or $size eq "");
  $dec=1 if (!defined $dec);
  my $format='%1.'.$dec.'f';  
  
  my $heightcal=10+@values*10;
  
  if (!defined $height or $height eq "") {
    if (@values/3 > 4) {
      $heightval=5;
      $height=10+@values*5;
    } else {
      $height=$heightcal;
    }
  } else {
     if ($height < $heightcal) {
       $heightval=5;
     }
  }   
  
  if (!defined $header or $header eq "") {
    $trans=5;
    $bheight=$height-26;
  } else {
    $trans=22;
    $bheight=$height-10;
  }
  my $width=30;
  my $heightoffset=4;
  
  if ($mode == 0) {
    $width=7;
  }
  
  if (!defined $bwidth or $bwidth eq "") {
    my $lenmax=0;
    for (my $i=0;$i<@values;$i+=3){
      $values[$i+2]="" if (!defined $values[$i+2]);
      $lenmax=length($values[$i+2]) if (length($values[$i+2]) > $lenmax);
    }
    if ($mode == 0) {
      $bwidth=@values/3*($width+2)+60+$lenmax*4.3;
    } else {
      $bwidth=90+$lenmax*4.3;
    }
    if ($heightval==5) {
      $bwidth=$bwidth*1.3;
    }
  }
  
  my ($y,$val1,$null);
  
  my $svg_width=int($size/100*$bwidth);
  my $svg_height=int($size/100*($bheight+40));
   
  $out.= sprintf ('<svg class="DOIF_cylinder" xmlns="http://www.w3.org/2000/svg" viewBox="10 0 %d %d" width="%d" height="%d" style="width:%dpx; height:%dpx;">',$bwidth,$bheight+40,$svg_width,$svg_height,$svg_width,$svg_height);
  $out.= '<defs>';
  $out.= '<linearGradient id="grad0" x1="0" y1="0" x2="1" y2="0"><stop offset="0" style="stop-color:grey;stop-opacity:0.5"/><stop offset="1" style="stop-color:rgb(64, 64, 64);stop-opacity:0.5"/></linearGradient>';
  $out.= '<linearGradient id="grad3" x1="0" y1="0" x2="1" y2="0"><stop offset="0" style="stop-color:grey;stop-opacity:0.2"/><stop offset="1" style="stop-color:rgb(0, 0, 0);stop-opacity:0.2"/></linearGradient>';
  for (my $i=0;$i<@values;$i+=3){  
    my $color=$values[$i+1];
    $out.= sprintf('<linearGradient id="grad1_%s" x1="0" y1="0" x2="1" y2="0"><stop offset="0" style="stop-color:%s;stop-opacity:0.9"/><stop offset="1" style="stop-color:%s;stop-opacity:0.3"/></linearGradient>',$color,hsl_color($color),hsl_color($color));
  }
  $out.= '<linearGradient id="gradbackcyl" x1="0" y1="1" x2="0" y2="0"><stop offset="0" style="stop-color:rgb(40,40,40);stop-opacity:1"/><stop offset="1" style="stop-color:rgb(64, 64, 64);stop-opacity:1"/></linearGradient>';
  $out.= '<linearGradient id="gradbackbars" x1="0" y1="1" x2="0" y2="0"><stop offset="0" style="stop-color:rgb(64,64,64);stop-opacity:1"/><stop offset="1" style="stop-color:rgb(48, 48, 48);stop-opacity:1"/></linearGradient>';

  $out.= '</defs>';

  $out.= sprintf('<rect x="11" y="0" width="%d" height="%d" rx="5" ry="5" fill="url(#gradbackcyl)"/>',$bwidth-2, $bheight+40);  
  $out.= sprintf('<text text-anchor="middle" x="%d" y="13" style="fill:white; font-size:14px">%s</text>',$bwidth/2+11,$header) if ($header ne "");  
  
  $out.= sprintf('<g transform="translate(0,%d)">',$trans);
  if ($mode == 0) {
	  $out.= sprintf('<rect x="15" y="0"  width="%d" height="%d" rx="3" ry="3" fill="url(#gradbackbars)"/>',@values/3*($width+2)+2,$height+$heightoffset+2);
	} else {
    $out.= sprintf('<rect x="15" y="0"  width="%d" height="%d" rx="20" ry="2" fill="url(#grad3)"/>',$width,$height+$heightoffset);
    $out.= sprintf('<rect x="15" y="%d" width="%d" height="4" rx="20" ry="2" fill="url(#grad0)"/>',$height,$width);
    $out.= sprintf('<rect x="15" y="0"  width="%d" height="4" rx="20" ry="2" fill="url(#grad0)"/>',$width);
  }

  ($y,$val1,$null)=y_h(0,$min,$max,$height,0,$mode);
  my $xLeft=15;
  my $xBegin=$xLeft+33;
  $xBegin=@values/3*($width+2)+20 if($mode == 0);
  
  $out.= sprintf('<text x="%d" y="%d" style="fill:white; font-size:10px">%s</text>',$xBegin,$height+$heightoffset+1,$min);
  $out.= sprintf('<text x="%d" y="%d" style="fill:white; font-size:10px">%s</text>',$xBegin,$null+$heightoffset+2,0) if (defined $null);
  $out.= sprintf('<text x="%d" y="%d" style="fill:white; font-size:10px">%s</text>',$xBegin,+$heightoffset,$max);  

  my $yBegin=14+($height-@values*$heightval)/2;
  my $xValue=$xLeft;
  my $yValue=$yBegin+$heightval-1;
  my $val_sum_pos=0;
  my $val_sum_neg=0;
  
  for (my $i=0;$i<@values;$i+=3){
 
    my $value=$values[$i];
    my $val=$value;
    
    $xValue=$xLeft+$i/3*($width+2)+2 if ($mode == 0);

    if (!defined $value or $value eq "") {
      $val="N/A";
      $value=0;
    }
    my $color=$values[$i+1];
    my $text=$values[$i+2];
    
    ($y,$val1,$null)=y_h($value,$min,$max,$height,($value > 0 ? $val_sum_pos: $val_sum_neg),$mode);

    if ($mode) {
      $out.= sprintf('<rect x="%d" y="%d" width="%d" height="4" rx="20" ry="2" fill="none" stroke="#999999" stroke-width="0.3"/>',$xValue,$y,$width);
      $out.= sprintf('<rect x="%d" y="%d" width="%d" height="%d" rx="20" ry="2" fill="url(#grad1_%s)"/>',$xValue,$y,$width,$val1,$color);
    ##  $out.= sprintf('<rect x="%d" y="%d" width="%d" height="%d" rx="20" ry="2" fill="url(#grad1_%s)"/>',$xValue,$y,$width,$val1,$color);
    } else {
      $out.= sprintf('<rect x="%d" y="%d" width="%d" height="%d" rx="1" ry="1" fill="url(#grad1_%s)"/>',$xValue,$y+2,$width,$val1+2,$color);
    }
    my $yText;
    if (defined $text and $text ne "") {
      $out.= sprintf('<text x="%d" y="%d" style="fill:%s; font-size:12px">%s</text>',$xBegin+10,$yBegin+$i*$heightval,hsl_color($color),$text.":");
      if ($heightval == 10) {
        $yText=$yValue+7;
      } else {
        $yText=$yValue-4;
      }
    } else {
      $yText=$yValue-4;
    }
    $out.= sprintf('<text text-anchor="end" x="%d" y="%d" style="fill:%s";><tspan style="font-size:14px;font-weight:bold;">%s</tspan><tspan dx="2" style="font-size:10px">%s</tspan></text>',$bwidth+5, $yText+$i*$heightval,hsl_color ($color),($val eq "N/A" ? $val:sprintf($format,$val)),$unit);
    if ($mode == 2) {
      if ($value> 0) {
        $val_sum_pos+=($val1-4);
      } else {
        $val_sum_neg-=($val1-4);
      }
    }
  }  

  $out.= '</g>';
  $out.= '</svg>';
  return ($out);
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
Syntax FHEM-Mode:<br>
<br>
<ol><code>define &lt;name&gt; DOIF (&lt;condition&gt;) (&lt;commands&gt;) DOELSEIF (&lt;condition&gt;) (&lt;commands&gt;) DOELSEIF ... DOELSE (&lt;commands&gt;)</code></ol>
<br>
Syntax Perl-Mode:<br>
<br>
<ol><code>define &lt;name&gt; DOIF &lt;Blockname&gt; {&lt;Perl with DOIF-Syntax&gt;} &lt;Blockname&gt; {&lt;Perl with DOIF-Syntax&gt;} ...</code></ol>
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
+ weekday control: <code>[&lt;time&gt;|0123456789]</code> or <code>[&lt;begin&gt;-&lt;end&gt;|0123456789]</code> (0-6 corresponds to Sunday through Saturday) such as 7 for $we, 8 for !$we, 9 for $we tomorrow ($twe) <br>
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
DOIF (ausgeprochen: du if, übersetzt: tue wenn) ist ein universelles Modul mit <a href="https://wiki.fhem.de/wiki/DOIF/uiTable_Schnelleinstieg">Web-Interface</a>, welches ereignis- und zeitgesteuert in Abhängigkeit definierter Bedingungen Anweisungen ausführt.<br>
<br>
Mit diesem Modul ist es möglich, einfache wie auch komplexere Automatisierungsvorgänge zu definieren oder in Perl zu programmieren.
Ereignisse, Zeittrigger, Readings oder Status werden durch DOIF-spezifische Angaben in eckigen Klammern angegeben. Sie führen zur Triggerung des Moduls und damit zur Auswertung und Ausführung der definierten Anweisungen.<br>
<br>
Das Modul verfügt über zwei Modi: FHEM-Modus und <a href="#DOIF_Perl_Modus"><b>Perl-Modus</b></a>. Der Modus eines definierten DOIF-Devices wird automatisch aufgrund der Definition vom Modul erkannt
(FHEM-Modus beginnt mit einer runden Klammer auf).
Der Perl-Modus kommt weitgehend ohne Attribute aus, er ist aufgrund seiner Flexibilität,
der Möglichkeit strukturiert zu programmieren und seiner hohen Performance insb. bei umfangreichen Automatisierungsaufgaben dem FHEM-Modus vorzuziehen. Hier geht´s zum <a href="#DOIF_Perl_Modus"><b>Perl-Modus</b></a>.
Beide Modi sind innerhalb eines DOIF-Devices nicht miteinander kombinierbar.<br> 
<br>
Syntax FHEM-Modus:<br>
<br>
<ol><code>define &lt;name&gt; DOIF (&lt;Bedingung&gt;) (&lt;Befehle&gt;) DOELSEIF (&lt;Bedingung&gt;) (&lt;Befehle&gt;) DOELSEIF ... DOELSE (&lt;Befehle&gt;)</code></ol>
<br>
Die Angaben werden immer von links nach rechts abgearbeitet. Logische Abfragen werden in DOIF/DOELSEIF-Bedingungen vornehmlich mit Hilfe von and/or-Operatoren erstellt. 
Zu beachten ist, dass nur die Bedingungen überprüft werden,
die zum ausgelösten Event das dazughörige Device bzw. die dazugehörige Triggerzeit beinhalten.
Kommt ein Device in mehreren Bedingungen vor, so wird immer nur ein Kommando ausgeführt, und zwar das erste,
für das die dazugehörige Bedingung in der abgearbeiteten Reihenfolge wahr ist.<br><br>
Das DOIF-Modul arbeitet mit Zuständen. Jeder Ausführungszweig DOIF/DOELSEIF..DOELSEIF/DOELSE stellt einen eigenen Zustand dar (cmd_1, cmd_2, usw.).
Das Modul merkt sich den zuletzt ausgeführten Ausführungszweig und wiederholt diesen standardmäßig nicht.
Ein Ausführungszweig wird erst dann wieder ausgeführt, wenn zwischenzeitlich ein anderer Ausführungszweig ausgeführt wurde, also ein Statuswechsel des DOIF-Moduls stattgefunden hat.
Dieses Verhalten ist sinnvoll, um zu verhindern, dass zyklisch sendende Sensoren (Temperatur, Feuchtigkeit, Helligkeit, usw.) zu ständiger Wiederholung des selben Befehls oder Befehlsabfolge führen.
Das Verhalten des Moduls im FHEM-Modus kann durch diverse Attribute verändert werden. Im FHEM-Modus wird maximal nur ein Zweig pro Ereignis- oder Zeit-Trigger ausgeführt, es gibt nur einen Wait-Timer.<br>
<br>
<a name="DOIF_Einfache_Anwendungsbeispiele"></a>
<u>Einfache Anwendungsbeispiele</u><ol>
<br>
Fernbedienung (Ereignissteuerung)<br>
<br>
<code>define di_rc_tv DOIF ([remotecontol:"on"]) (set tv on) DOELSE (set tv off)</code><br>
<br>
Zeitschaltuhr (Zeitsteuerung)<br>
<br>
<code>define di_clock_radio DOIF ([06:30|Mo Di Mi] or [08:30|Do Fr Sa So]) (set radio on) DOELSEIF ([08:00|Mo Di Mi] or [09:30|Do Fr Sa So]) (set radio off)</code><br>
<br>
Kombinierte Ereignis- und Zeitsteuerung<br>
<br>
<code>define di_lamp DOIF ([06:00-09:00] and [sensor:brightness] &lt; 40) (set lamp on) DOELSE (set lamp off)</code><br>
</ol><br>
Eine ausführliche Erläuterung der obigen Anwendungsbeispiele kann hier nachgelesen werden:
<a href="https://wiki.fhem.de/wiki/DOIF/Einsteigerleitfaden,_Grundfunktionen_und_Erl%C3%A4uterungen#Erste_Schritte_mit_DOIF:_Zeit-_und_Ereignissteuerung">Erste Schritte mit DOIF</a><br><br>
<br>
<a name="DOIF_Inhaltsuebersicht"></a>
<b>Inhaltsübersicht</b> (Beispiele im Perl-Modus sind besonders gekennzeichnet)<br>
<ul><br>
  <a href="#DOIF_Lesbarkeit_der_Definitionen">Lesbarkeit der Definitionen</a><br>
  <a href="#DOIF_Ereignissteuerung">Ereignissteuerung</a><br>
  <a href="#DOIF_Teilausdruecke_abfragen">Teilausdrücke abfragen</a><br>
  <a href="#DOIF_Ereignissteuerung_ueber_Auswertung_von_Events">Ereignissteuerung über Auswertung von Events</a><br>
  <a href="#DOIF_Angaben_im_Ausfuehrungsteil">Angaben im Ausführungsteil</a><br>
  <a href="#DOIF_Filtern_nach_Zahlen">Filtern nach Ausdrücken mit Ausgabeformatierung</a><br>
  <a href="#DOIF_Reading_Funktionen">Durchschnitt, Median, Differenz, Änderungsrate, anteiliger Anstieg</a><br>
  <a href="#DOIF_aggregation">Aggregieren von Werten</a><br>
  <a href="#DOIF_Zeitsteuerung">Zeitsteuerung</a><br>
  <a href="#DOIF_Relative_Zeitangaben">Relative Zeitangaben</a><br>
  <a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet">Zeitangaben nach Zeitraster ausgerichtet</a><br>
  <a href="#DOIF_Relative_Zeitangaben_nach_Zeitraster_ausgerichtet">Relative Zeitangaben nach Zeitraster ausgerichtet</a><br>
  <a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet_alle_X_Stunden">Zeitangaben nach Zeitraster ausgerichtet alle X Stunden</a><br>
  <a href="#DOIF_Wochentagsteuerung">Wochentagsteuerung</a><br>
  <a href="#DOIF_Zeitsteuerung_mit_Zeitintervallen">Zeitsteuerung mit Zeitintervallen</a><br>
  <a href="#DOIF_Indirekten_Zeitangaben">Indirekten Zeitangaben</a><br>
  <a href="#DOIF_Zeitsteuerung_mit_Zeitberechnung">Zeitsteuerung mit Zeitberechnung</a><br>
  <a href="#DOIF_Intervall-Timer">Intervall-Timer</a><br>
  <a href="#DOIF_Zeitsteuerung_alle_X_Tage">Zeittrigger alle X Tage</a><br>
  <a href="#DOIF_Kombination_von_Ereignis_und_Zeitsteuerung_mit_logischen_Abfragen">Kombination von Ereignis- und Zeitsteuerung mit logischen Abfragen</a><br>
  <a href="#DOIF_Zeitintervalle_Readings_und_Status_ohne_Trigger">Zeitintervalle, Readings und Status ohne Trigger</a><br>
  <a href="#DOIF_Nutzung_von_Readings_Status_oder_Internals_im_Ausfuehrungsteil">Nutzung von Readings, Status oder Internals im Ausführungsteil</a><br>
  <a href="#DOIF_Berechnungen_im_Ausfuehrungsteil">Berechnungen im Ausführungsteil</a><br>
  <a href="#DOIF_notexist">Ersatzwert für nicht existierende Readings oder Status</a><br>
  <a href="#DOIF_wait">Verzögerungen</a><br>
  <a href="#DOIF_timerWithWait">Verzögerungen von Timern</a><br>
  <a href="#DOIF_do_resetwait">Zurücksetzen des Waittimers für das gleiche Kommando</a><br>
  <a href="#DOIF_repeatcmd">Wiederholung von Befehlsausführung</a><br>
  <a href="#DOIF_cmdpause">Zwangspause für das Ausführen eines Kommandos seit der letzten Zustandsänderung</a><br>
  <a href="#DOIF_repeatsame">Begrenzung von Wiederholungen eines Kommandos</a><br>
  <a href="#DOIF_waitsame">Ausführung eines Kommandos nach einer Wiederholung einer Bedingung</a><br>
  <a href="#DOIF_waitdel">Löschen des Waittimers nach einer Wiederholung einer Bedingung</a><br>
  <a href="#DOIF_checkReadingEvent">Readingauswertung bei jedem Event des Devices</a><br>
  <a href="#DOIF_addStateEvent">Eindeutige Statuserkennung</a><br>
  <a href="#DOIF_selftrigger">Triggerung durch selbst ausgelöste Events</a><br>
  <a href="#DOIF_timerevent">Setzen der Timer mit Event</a><br>
  <a href="#DOIF_Zeitspanne_eines_Readings_seit_der_letzten_Aenderung">Zeitspanne eines Readings seit der letzten Änderung</a><br>
  <a href="#DOIF_setList__readingList">Darstellungselement mit Eingabemöglichkeit im Frontend und Schaltfunktion</a><br>
  <a href="#DOIF_cmdState">Status des Moduls</a><br>
  <a href="#DOIF_uiTable">uiTable, DOIF Web-Interface</a><br>
  <a href="#DOIF_uiState">uiState, DOIF Web-Interface im Status</a><br>
  <a href="#DOIF_Reine_Statusanzeige_ohne_Ausfuehrung_von_Befehlen">Reine Statusanzeige ohne Ausführung von Befehlen</a><br>
  <a href="#DOIF_state">Anpassung des Status mit Hilfe des Attributes <code>state</code></a><br>
  <a href="#DOIF_DOIF_Readings">Erzeugen berechneter Readings<br>
  <a href="#DOIF_initialize">Vorbelegung des Status mit Initialisierung nach dem Neustart mit dem Attribut <code>initialize</code></a><br>
  <a href="#DOIF_disable">Deaktivieren des Moduls</a><br>
  <a href="#DOIF_setcmd">Bedingungslose Ausführen von Befehlszweigen</a><br>
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
  <a href="#DOIF_addStateEvent">addStateEvent</a> &nbsp;
  <a href="#DOIF_checkall">checkall</a> &nbsp;
  <a href="#DOIF_checkReadingEvent">checkReadingEvent</a> &nbsp;
  <a href="#DOIF_cmdpause">cmdpause</a> &nbsp;
  <a href="#DOIF_cmdState">cmdState</a> &nbsp;
  <a href="#DOIF_DOIF_Readings">DOIF_Readings</a> &nbsp;
  <a href="#DOIF_disable">disable</a> &nbsp;
  <a href="#DOIF_do_always">do always</a> &nbsp;
  <a href="#DOIF_do_resetwait">do resetwait</a> &nbsp;
  <a href="#DOIF_event_Readings">event_Readings</a> &nbsp;
  <a href="#DOIF_initialize">initialize</a> &nbsp;
  <a href="#DOIF_notexist">notexist</a> &nbsp;
  <a href="#DOIF_repeatcmd">repeatcmd</a> &nbsp;
  <a href="#DOIF_repeatsame">repeatsame</a> &nbsp;
  <a href="#DOIF_selftrigger">selftrigger</a> &nbsp;
  <a href="#DOIF_setList__readingList">readingList</a> &nbsp;
  <a href="#DOIF_setList__readingList">setList</a> &nbsp;
  <a href="#DOIF_startup">startup</a> &nbsp;
  <a href="#DOIF_state">state</a> &nbsp;
  <a href="#DOIF_timerevent">timerevent</a> &nbsp;
  <a href="#DOIF_timerWithWait">timerWithWait</a> &nbsp;
  <a href="#DOIF_uiTable">uiTable</a> &nbsp;
  <a href="#DOIF_uiState">uiState</a> &nbsp;
  <a href="#DOIF_wait">wait</a> &nbsp;
  <a href="#DOIF_waitdel">waitdel</a> &nbsp;
  <a href="#DOIF_waitsame">waitsame</a> &nbsp;
  <a href="#DOIF_weekdays">weekdays</a> &nbsp;
  <br><a href="#readingFnAttributes">readingFnAttributes</a> &nbsp;
  </ul>
<br>
  <a href="#DOIF_setBefehle"><b>Set Befehle</b></a><br>
  <ul>
  <a href="#DOIF_setcheckall">checkall</a> &nbsp;
  <a href="#DOIF_setdisable">disable</a> &nbsp;
  <a href="#DOIF_setenable">enable</a> &nbsp;
  <a href="#DOIF_Initialisieren_des_Moduls">initialize</a> &nbsp;
  <a href="#DOIF_setcmd">cmd</a> &nbsp;
  </ul>
<br>
  <a href="#DOIF_getBefehle"><b>Get Befehle</b></a><br>
  <ul>
  <a href="#HTML-Code von uiTable">html</a> 
  </ul>
<br>
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
<table>
<tr><td><code>define di_Modul DOIF ([Switch1] eq "on" and [Switch2] eq "on")</code></td><td>&nbsp;<code>## wenn Schalter 1 und Schalter 2 on ist</code><br></td></tr>
<tr><td><ol><code>(set lamp on)</code>                                             </td><td>&nbsp;<code>## wird Lampe eingeschaltet</code></ol></td></tr>
<tr><td><code>DOELSE</code>                                                        </td><td>&nbsp;<code>## im sonst-Fall, also wenn einer der Schalter off ist</code><br></td></tr>
<tr><td><ol><code>(set lamp off)</code>                                            </td><td>&nbsp;<code>## wird die Lampe ausgeschaltet</code></ol></td></tr>
<br>
</table><br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<table>
<code>define di_Modul DOIF </code>
<tr><td>{<code>&nbsp;if ([Switch1] eq "on" and [Switch2] eq "on") {</code></td><td>&nbsp;<code>## wenn Schalter 1 und Schalter 2 on ist</code><br></td></tr>
<tr><td><ol><code>fhem_set "lamp on"</code>               </td><td>&nbsp;<code>## wird Lampe eingeschaltet</code></ol></td></tr>
<tr><td><code>&nbsp;&nbsp;}&nbsp;else {</code>            </td><td>&nbsp;<code>## im sonst-Fall, also wenn einer der Schalter off ist</code><br></td></tr>
<tr><td><ol><code>fhem_set "lamp off"</code>              </td><td>&nbsp;<code>## wird die Lampe ausgeschaltet</code></ol></td></tr>
<tr><td><code>&nbsp;&nbsp;}</code><br></td></tr>
<tr><td><code>}</code><br></td></tr>
</table>
<br>
Im Folgenden wird die Funktionalität des Moduls im Einzelnen an vielen praktischen Beispielen erklärt.<br>
<br>
<a name="DOIF_Ereignissteuerung"></a><br>
<b>Ereignissteuerung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Vergleichende Abfragen werden in der Bedingung, mit Perl-Operatoren <code>==, !=, <, <=, >, >=</code> bei Zahlen und mit <code>eq, ne, lt, le, gt, ge, =~, !~</code> bei Zeichenketten angegeben.
Logische Verknüpfungen sollten zwecks Übersichtlichkeit mit <code>and</code> bzw. <code>or</code> vorgenommen werden.
Die Reihenfolge der Auswertung wird, wie in höheren Sprachen üblich, durch runde Klammern beeinflusst.
Status werden mit <code>[&lt;devicename&gt;]</code>, Readings mit <code>[&lt;devicename&gt;:&lt;readingname&gt;]</code>,
Internals mit <code>[&lt;devicename&gt;:&&lt;internal&gt;]</code> angegeben.<br>
<br>
<u>Anwendungsbeispiel</u>: Einfache Ereignissteuerung, "remotecontrol" ist hier ein Device, es wird in eckigen Klammern angegeben. Ausgewertet wird der Status des Devices - nicht das Event.<br>
<br>
<code>define di_garage DOIF ([remotecontrol] eq "on") (set garage on) DOELSEIF ([remotecontrol] eq "off") (set garage off)</code><br>
<br>
Das Modul wird getriggert, sobald das angegebene Device hier "remotecontrol" ein Event erzeugt. Das geschieht, wenn irgendein Reading oder der Status von "remotecontrol" aktualisiert wird.
Ausgewertet wird hier der Zustand des Status von remotecontrol nicht das Event selbst. Im FHEM-Modus arbeitet das Modul mit Zuständen, indem es den eigenen Status auswertet.
Die Ausführung erfolgt standardmäßig nur ein mal, bis ein anderer DOIF-Zweig und damit eine Ändernung des eigenen Status erfolgt.
Das bedeutet, dass ein mehrmaliges Drücken der Fernbedienung auf "on" nur einmal "set garage on" ausführt. Die nächste mögliche Ausführung ist "set garage off", wenn Fernbedienung "off" liefert.
<a name="DOIF_do_always"></a><br>
Wünscht man eine Ausführung des gleichen Befehls mehrfach nacheinander bei jedem Trigger, unabhängig davon welchen Status das DOIF-Modul hat,
weil z. B. Garage nicht nur über die Fernbedienung geschaltet wird, dann muss man das per "do always"-Attribut angeben:<br>
<br>
<code>attr di_garage do always</code><br>
<br>
Bei der Angabe von zyklisch sendenden Sensoren (Temperatur, Feuchtigkeit, Helligkeit usw.) wie z. B.:<br>
<br>
<code>define di_heating DOIF ([sens:temperature] &lt 20) (set heating on)</code><br>
<br>
ist die Nutzung des Attributes <code>do always</code> nicht sinnvoll, da das entsprechende Kommando hier: "set heating on" jedes mal ausgeführt wird,
wenn der Temperatursensor in regelmäßigen Abständen eine Temperatur unter 20 Grad sendet.
Ohne <code>do always</code> wird hier dagegen erst wieder "set heating on" ausgeführt, wenn der Zustand des Moduls auf "cmd_2" gewechselt hat, also die Temperatur zwischendurch größer oder gleich 20 Grad war.<br>
<br>
Soll bei Nicht-Erfüllung aller Bedingungen ein Zustandswechsel erfolgen, so muss man ein DOELSE am Ende der Definition anhängen. Ausnahme ist eine einzige Bedingung ohne do always, wie im obigen Beispiel,
 hierbei wird intern ein virtuelles DOELSE angenommen, um bei Nicht-Erfüllung der Bedingung einen Zustandswechsel in cmd_2 zu provozieren, da sonst nur ein einziges Mal geschaltet werden könnte, da das Modul aus dem cmd_1-Zustand nicht mehr herauskäme.<br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<br>
Im Perl-Modus arbeitet das DOIF-Modul im Gegensatz zum FHEM-Modus ohne den eigenen Status auszuwerten. Es kommt immer zur Auswertung des definierten Block, wenn er getriggert wird.
Diese Verhalten entspricht dem Verhalten mit dem Attribut do always im FHEM-Modus. Damit bei zyklisch sendenden Sensoren nicht zum ständigen Schalten kommt, muss das Schalten unterbunden werden. Das obige Beispiel lässt sich, wie folgt definieren:<br>
<br>
<code>define di_heating DOIF {if ([sens:temperature] &lt 20) {if (Value("heating") ne "on") {fhem_set"heating on"}}}</code><br>
<br> 
<a name="DOIF_Teilausdruecke_abfragen"></a><br>
<b>Teilausdrücke abfragen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Abfragen nach Vorkommen eines Wortes innerhalb einer Zeichenkette können mit Hilfe des Perl-Operators <code>=~</code> vorgenommen werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Garage soll beim langen Tastendruck öffnen, hier: wenn das Wort "Long" im Status vorkommt (bei HM-Komponenten stehen im Status noch weitere Informationen).<br>
<br>
<code>define di_garage DOIF ([remotecontrol] =~ "Long") (set garage on)<br>
attr di_garage do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_garage DOIF {if ([remotecontrol] =~ "Long") {fhem_set"garage on"}}</code><br>
<br>
Weitere Möglichkeiten bei der Nutzung des Perl-Operators: <code>=~</code>, insbesondere in Verbindung mit regulären Ausdrücken, können in der Perl-Dokumentation nachgeschlagen werden.<br>
<br>
<a name="DOIF_Ereignissteuerung_ueber_Auswertung_von_Events"></a><br>
<b>Ereignissteuerung über Auswertung von Events</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Eine Alternative zur Auswertung von Status oder Readings ist das Auswerten von Ereignissen (Events) mit Hilfe von regulären Ausdrücken. Der Suchstring wird als regulärer Ausdruck in Anführungszeichen angegeben.
Die Syntax lautet: <code>[&lt;devicename&gt;:"&lt;regex&gt;"]</code><br>
<br>
<u>Anwendungsbeispiel</u>: wie oben, jedoch wird hier nur das Ereignis (welches im Eventmonitor erscheint) ausgewertet und nicht der Status von "remotecontrol" wie im vorherigen Beispiel<br>
<br>
<code>define di_garage DOIF ([remotecontrol:"on"]) (set garage on) DOELSEIF ([remotecontrol:"off"]) (set garage off)</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_garage DOIF {if ([remotecontrol:"on"]) {fhem_set"garage on"} elsif ([remotecontrol:"off"]) {fhem_set"garage off"}}</code><br>
<br>
In diesem Beispiel wird nach dem Vorkommen von "on" innerhalb des Events gesucht.
Falls "on" gefunden wird, wird der Ausdruck wahr und der if-Fall wird ausgeführt, ansonsten wird der else-if-Fall entsprechend ausgewertet.
Die Auswertung von reinen Ereignissen bietet sich dann an, wenn ein Modul keinen Status oder Readings benutzt, die man abfragen kann, wie z. B. beim Modul "sequence".
Die Angabe von regulären Ausdrücken kann recht komplex werden und würde die Aufzählung aller Möglichkeiten an dieser Stelle den Rahmen sprengen.
Weitere Informationen zu regulären Ausdrücken sollten in der Perl-Dokumentation nachgeschlagen werden.
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
[":^temp"] triggert auf beliebige Devices, die im Event mit "temp" beginnen <br>
["^FS$:^temp$"] triggert auf Devices, die genau "FS" heißen und im Event genau "temp" vorkommt <br>
[""] triggert auf alles<br>
<br>
In der Bedingung und im Ausführungsteil werden die Schlüsselwörter $SELF durch den eigenen Namen des DOIF-Moduls, $DEVICE durch das aktuelle Device, $EVENT durch die passende Eventzeile, $EVENTS kommagetrennt durch alle Eventzeilen des Triggers ersetzt.<br>
<br>
Entsprechend können Perl-Variablen in der DOIF-Bedingung ausgewertet werden, sie werden in Kleinbuchstaben geschrieben. Sie lauten: $device, $event, $events<br>
<br>
<u>Anwendungsbeispiele</u>:<br>
<br>
"Fenster offen"-Meldung<br>
<br>
<code>define di_window_open DOIF (["^window_:open"]) (set Pushover msg 'alarm' 'open windows $DEVICE' '' 2 'persistent' 30 3600)<br>
attr di_window_open do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_window_open DOIF {if (["^window_:open"]) {fhem_set"Pushover msg 'alarm' 'open windows $DEVICE' '' 2 'persistent' 30 3600"}}</code><br>
<br>
Hier werden alle Fenster, die mit dem Device-Namen "window_" beginnen auf "open" im Event überwacht.<br>
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
<code>define di_warning DOIF ([":^temperature",0] &lt 0) (set pushmsg danger of frost $DEVICE)</code><br>
<code>attr di_warning do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_warning DOIF {if ([":^temperature",0] &lt 0) {fhem_set"pushmsg danger of frost $DEVICE}}</code><br>
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
Die Angaben zum Filter und Output funktionieren, wie die beim Reading-Filter. Siehe: <a href="#DOIF_Filtern_nach_Zahlen">Filtern nach Ausdrücken mit Ausgabeformatierung</a><br>
<br>
Wenn kein Filter, wie obigen Beispiel, angegeben wird, so wird intern folgende Regex vorbelegt: "[^\:]*: (.*)"  Damit wird der Wert hinter der Readingangabe genommen.
Durch eigene Regex-Filter-Angaben kann man beliebige Teile des Events herausfiltern, ggf. über Output formatieren und in der Bedingung entsprechend auswerten,
 ohne auf Readings zurückgreifen zu müssen.<br>
<br>
<a name="DOIF_Filtern_nach_Zahlen"></a><br>
<b>Filtern nach Ausdrücken mit Ausgabeformatierung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Syntax: <code>[&lt;device&gt;:&lt;reading&gt;|&lt;internal&gt;:d&lt;number&gt|"&lt;regex&gt;":&lt;output&gt;]</code><br>
<br>
d - Der Buchstabe "d" ist ein Synonym für das Filtern nach Dezimalzahlen, es entspricht intern dem regulären Ausdruck "(-?\d+(\.\d+)?)". Ebenfalls lässt sich eine Dezimalzahl auf eine bestimmte Anzahl von Nachkommastellen runden. Dazu wird an das "d" eine Ziffer angehängt. Mit der Angabe d0 wird die Zahl auf ganze Zahlen gerundet.<br>
&lt;Regex&gt;- Der reguläre Ausdruck muss in Anführungszeichen angegeben werden. Dabei werden Perl-Mechanismen zu regulären Ausdrücken mit Speicherung der Ergebnisse in Variablen $1, $2 usw. genutzt.<br>
&lt;Output&gt; - ist ein optionaler Parameter, hier können die in den Variablen $1, $2, usw. aus der Regex-Suche gespeicherten Informationen für die Aufbereitung genutzt werden. Sie werden in Anführungszeichen bei Texten oder in Perlfunktionen angegeben. Wird kein Output-Parameter angegeben, so wird automatisch $1 genutzt.<br>
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
Es soll die Zahl aus einem Reading auf 3 Nachkommastellen formatiert werden:<br>
<br>
<code>[mydevice:myreading:d3]</code><br>
<br>
Es soll aus einem Text eine Zahl herausgefiltert werden und anschließend gerundet auf zwei Nachkommastellen mit der Einheit °C ausgeben werden:<br>
<br>
<code>... (set mydummy [mydevice:myreading:d2:"$1 °C"])</code><br>
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
<a name="DOIF_Reading_Funktionen"></a><br>
<b>Durchschnitt, Median, Differenz, Änderungsrate, anteiliger Anstieg</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Die folgenden Funktionen werden auf die letzten gesendeten Werte eines Readings angewendet. Das angegebene Reading muss Events liefern, damit seine Werte intern im Modul gesammelt und die Berechnung der angegenen Funktion erfolgen kann.<br>
<br>
Syntax<br>
<br>
<code>[&lt;device&gt;:&lt;reading&gt;:&lt;function&gt;&lt;number of last values&gt;]</code><br>
<br>
&lt;number of last values&gt; ist optional. Wird sie nicht angegeben, so werden bei Durchschnitt/Differenz/Änderungsrate/Anstieg die letzten beiden Werte, bei Median die letzten drei Werte, ausgewertet.<br>
<br>
<u>Durchschnitt</u><br>
<br>
Funktion: <b>avg</b><br>
<br>
Bsp.:<br>
<br>
<code>define di_cold DOIF ([outdoor:temperature:avg5] &lt; 10)(set cold on)</code><br>
<br>
Wenn der Durchschnitt der letzten fünf Werte unter 10 Grad ist, dann wird die Anweisung ausgeführt.<br>
<br>
<u>Median</u><br>
<br>
Mit Hilfe des Medians können punktuell auftretende Ausreißer eliminiert werden.<br>
<br>
Funktion: <b>med</b><br>
<br>
Bsp.:<br>
<br>
<code>define di_frost DOIF ([$SELF:outTempMed] &lt; 0) (set warning frost)<br>
<br>
attr di_frost event_Readings outTempMed:[outdoor:temperature:med]</code><br>
<br>
Die Definition über das Attribut event_Readings hat den Vorteil, dass der bereinigte Wert im definierten Reading visualisiert und geloggt werden kann (med entspricht med3).<br>
<br>
<u>Differenz</u><br>
<br>
Es wird die Differenz zwischen dem letzten und dem x-ten zurückliegenden Wert berechnet.<br>
<br>
Funktion: <b>diff</b><br>
<br>
Bsp.:<br>
<br>
<code>define temp_abfall DOIF ([outdoor:temperature:diff5] &lt; -3) (set temp fall in temperature)</code><br>
<br>
Wenn die Temperaturdifferenz zwischen dem letzten und dem fünftletzten Wert um mindestens drei Grad fällt, dann Anweisung ausführen.<br>
<br>
<u>Änderungsrate</u><br>
<br>
Es wird die Änderungsrate (Veränderung pro Zeit) zwischen dem letzten und dem x-ten zurückliegenden Wert berechnet. Es wird der Differenzenquotient von zwei Werten und deren Zeitdifferenz gebildet. 
Mit Hilfe dieser Funktion können momentane Verbräuche von Wasser, elektrischer Energie, Gas usw. bestimmt, ausgewertet oder visualisiert werden.<br>
<br>
Funktion: <b>diffpsec</b><br>
<br>
Berechnung:<br>
<br>
(letzter Wert - zurückliegender Wert)/(Zeitpunkt des letzten Wertes - Zeitpunkt des zurückliegenden Wertes)<br>
<br>
Bsp.:<br>
<br>
<code>define di_pv DOIF ([pv:total_feed:diffpsec]*3600 &gt; 1) (set heating on) DOELSE (set heating off)</code><br>
<br>
Wenn die momentane PV-Einspeise-Leistung mehr als 1 kW beträgt, dann soll die Heizung eingeschaltet werden, sonst soll sie ausgeschaltet werden. Das total_feed-Reading beinhaltet den PV-Ertrag in Wh.<br>
<br>
<u>anteiliger Anstieg</u><br>
<br>
Funktion: <b>inc</b><br>
<br>
Berechnung:<br>
<br>
(letzter Wert - zurückliegender Wert)/zurückliegender Wert<br>
<br>
Bsp.:<br>
<br>
<code>define humidity_warning DOIF ([bathroom:humidiy:inc] &gt; 0.1) (set bath speak open window)</code><br>
<br>
Wenn die Feuchtigkeit im Bad der letzten beiden Werte um über zehn Prozent ansteigt, dann Anweisung ausführen (inc entspricht inc2).<br>
<br>
Zu beachten:<br>
<br>
Differenz/Änderungsrate/Anstieg werden gebildet, sobald zwei Werte eintreffen. Die intern gesammelten Werte werden nicht dauerhaft gespeichert, nach einem Neustart sind sie gelöscht. 
Die angegebenen Readings werden intern automatisch für die Auswertung nach Zahlen gefiltert.<br> 
<br>
<a name="DOIF_Angaben_im_Ausfuehrungsteil"></a><br>
<b>Angaben im Ausführungsteil (gilt nur für FHEM-Modus)</b>:&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Der Ausführungsteil wird durch runde Klammern eingeleitet. Es werden standardmäßig FHEM-Befehle angegeben, wie z. B.: <code>...(set lamp on)</code><br>
<br>
Sollen mehrere FHEM-Befehle ausgeführt werden, so werden sie mit Komma statt mit Semikolon angegeben <code>... (set lamp1 on, set lamp2 off)</code><br>
<br>
Falls ein Komma nicht als Trennzeichen zwischen FHEM-Befehlen gelten soll, so muss der FHEM-Ausdruck zusätzlich in runde Klammern gesetzt werden: <code>...((set lamp1,lamp2 on),set switch on)</code><br>
<br>
Perlbefehle werden in geschweifte Klammern gesetzt: <code>... {system ("wmail Peter is at home")}</code>. In diesem Fall können die runden Klammern des Ausführungsteils weggelassen werden.<br>
<br>
Perlcode kann im DEF-Editor wie gewohnt programmiert werden: <code>...{my $name="Peter"; system ("wmail $name is at home");}</code><br>
<br>
FHEM-Befehle lassen sich mit Perl-Befehlen kombinieren: <code>... ({system ("wmail Peter is at home")}, set lamp on)</code><br>
<br>
<a name="DOIF_aggregation"></a><br>
<b>Aggregieren von Werten</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit Hilfe der Aggregationsfunktion können mehrere gleichnamige Readings im System ausgewertet werden, die einem bestimmten Kriterium entsprechen. Sie wird in eckigen Klammern durch ein # (aggregierter Wert) oder @ (Liste der passeden Devices) eingeleitet.
Es kann bestimmt werden: die Anzahl der Readings bzw. Devices, Durchschnittswert, Summe, höchster Wert, niedrigster Wert oder eine Liste der dazugehörigen Devices.
Die Aggregationsfunktion kann in einer DOIF-Bedingungen, im Ausführungsteil oder mit Hilfe des state-Attributs im Status angegeben werden. In der Bedingung und im Status reagiert sie auf Ereignistrigger. Das lässt sich durch ein vorangestelltes Fragezeichen unterbinden.
Die Angabe des Readings kann weggelassen werden, dann wird lediglich nach entsprechenden Devices gesucht.<br>
<br>
Syntax:<br>
<br>
<code>[&lt;function&gt;:&lt;format&gt;:"&lt;regex device&gt;:&lt;regex event&gt;":&lt;reading&gt;|"&lt;regex reading&gt;":&lt;condition&gt;,&lt;default&gt;]</code><br>
<br>
&lt;function&gt;:<br>
<br>
<b>#</b>  Anzahl der betroffenen Devices, der folgende Doppelpunkt kann weggelassen werden<br>
<b>@</b>  kommagetrennte Liste Devices, der folgende Doppelpunkt kann weggelassen werden<br>
<b>#sum</b> Summe <br>
<b>#max</b>  höchster Wert<br>
<b>#min</b>  niedrigster Wert<br>
<b>#average</b>  Durchschnitt<br>
<b>#median</b> Medianwert<br>
<b>@max</b>  Device des höchsten Wertes<br>
<b>@min</b>  Device de niedrigsten Wertes<br>
<br>
&lt;format&gt; <code>d&lt;number&gt</code> zum Runden des Wertes mit Nachkommastellen, <code>a</code> für Aliasnamen bei Devicelisten, <code>s(&lt;splittoken&gt)</code> &lt;splittoken&gt sind Trennzeichen in der Device-Liste<br> 
<br> 
"&lt;regex Device&gt;:&lt;regex Event&gt;" spezifiziert sowohl die betroffenen Devices, als auch den Ereignistrigger, die Syntax entspricht der DOIF-Syntax für Ereignistrigger.<br>
Die Angabe &lt;regex Event&gt; ist im Ausführungsteil nicht sinnvoll und sollte weggelassen werden.<br>
<br>
&lt;reading&gt; Reading, welches überprüft werden soll<br>
<br>
"&lt;regex reading&gt"; Regex für Readings, die überprüft werden sollen<br>
<br>
&lt;condition&gt;  Aggregations-Bedingung, $_ ist der Platzhalter für den aktuellen Wert des internen Schleifendurchlaufs, Angaben in Anführungszeichen der Art "&lt;value&gt;" entsprechen $_ =~ "&lt;value&gt;" , hier sind alle Perloperatoren möglich.<br>
<br>
&lt;default&gt; Default-Wert, falls kein Device gefunden wird, entspricht der Syntax des Default-Wertes bei Readingangaben<br>
<br>
&lt;format&gt;, &lt;reading&gt;, &lt;condition&gt;,  &lt;default&gt; sind optional<br>
<br>
<u>Syntax-Beispiele im Ausführungteil</u><br>
<br>
Anzahl der Devices, die mit "window" beginnen:<br>
<br>
<code>[#"^window"]</code><br>
<br>
Liste der Devices, die mit "window" beginnen, es werden Aliasnamen ausgegeben, falls definiert:<br>
<br>
<code>[@:a"^window"]</code><br>
<br>
Liste der Devices, die mit "windows" beginnen und ein Reading "myreading" beinhalten:<br>
<br>
<code>[@"^window":myreading]</code><br>
<br>
Liste der Devices, die mit "windows" beginnen und im Status das Wort "open" vorkommt:<br>
<br>
<code>[@"^window":state:"open"]</code><br>
<br>
entspricht:<br>
<br>
<code>[@"^window":state:$_ =~ "open"]</code> siehe Aggregationsbedingung.<br>
<br>
Kleinster Wert der Readings des Devices "abfall", in deren Namen "Gruenschnitt" vorkommt und die mit "_days" enden:<br>
<br>
<code>[#min:"^abfall$":"Gruenschnitt.*_days$"]</code><br>
<br>
Durchschnitt von Readings aller Devices, die mit "T_" beginnen, in deren Reading-Namen "temp" vorkommt:<br>
<br>
<code>[#average:"^T_":"temp"]</code><br>
<br>
Medianwert (gewichtetes Mittel) von Readings aller Devices, die mit "T_" beginnen, in deren Reading-Namen "temp" vorkommt:<br>
<br>
<code>[#median:"^T_":"temp"]</code><br>
<br>
In der Aggregationsbedingung <condition> können alle in FHEM definierten Perlfunktionen genutzt werden. Folgende Variablen sind vorbelegt und können ebenfalls benutzt werden:<br>
<br>
<b>$_</b> Inhalt des angegebenen Readings (s.o.)<br>
<b>$number</b>  Nach Zahl gefilteres Reading<br>
<b>$name</b>  Name des Devices<br>
<b>$TYPE</b>  Devices-Typ<br>
<b>$STATE</b>  Status des Devices (nicht das Reading state)<br>
<b>$room</b>  Raum des Devices<br>
<b>$group</b>  Gruppe des Devices<br>
<br>
<u>Beispiele für Definition der Aggregationsbedingung &lt;condition&gt;:</u><br>
<br>
Liste der Devices, die mit "rooms" enden und im Reading "temperature" einen Wert größer 20 haben:<br>
<br>
<code>[@"rooms$":temperature:$_ &gt 20]</code><br>
<br>
Liste der Devices im Raum "livingroom", die mit "rooms" enden und im Reading "temperature" einen Wert größer 20 haben:<br>
<br>
<code>[@"rooms$":temperature:$_ &gt 20 and $room eq "livingroom"]</code><br>
<br>
Liste der Devices in der Gruppe "windows", die mit "rooms" enden, deren Status (nicht state-Reading) "on" ist:<br>
<br>
<code>[@"rooms$"::$STATE eq "on" and $group eq "windows"]</code><br>
<br>
Liste der Devices, deren state-Reading "on" ist und das Attribut disable nicht auf "1" gesetzt ist:<br>
<br>
<code>[@"":state:$_ eq "on" and AttrVal($name,"disable","") ne "1"]</code><br>
<br>
<br>
Aggregationsangaben in der DOIF-Bedingung reagieren zusätzlich auf Ereignistrigger, hier sollte die regex-Angabe für das Device um eine regex-Angabe für das zu triggernde Event erweitert werden.<br>
<br>
Anzahl der Devices, die mit "window" beginnen. Getriggert wird, wenn eine Eventzeile beginnend mit "window" und dem Wort "open" vorkommt:<br>
<br>
<code>[#"^window:open"]</code><br>
<br>
<u>Anwendungsbeispiele</u><br>
<br>
Statusanzeige: Offene Fenster:<br>
<br>
<code>define di_window DOIF<br>
<br>
attr di_window state Offene Fenster: [@"^window:open":state:"open","keine"]</code><br>
<br>
Statusanzeige: Alle Devices, deren Batterie nicht ok ist:<br>
<br>
<code>define di_battery DOIF<br>
<br>
attr di_battery state [@":battery":battery:$_ ne "ok","alle OK"]</code><br>
<br>
Statusanzeige: Durchschnittstemperatur aller Temperatursensoren in der Gruppe "rooms":<br>
<br>
<code>define di_average_temp DOIF<br>
<br>
attr di_average_temp state [#average:d2:":temperature":temperature:$group eq "rooms"]</code><br>
<br>
Fenster Status/Meldung:<br>
<br>
<code>define di_Fenster DOIF (["^Window:open"]) <br>
(push "Fenster $DEVICE wurde geöffnet. Es sind folgende Fenster offen: [@"^Window":state:"open"]")<br>
DOELSEIF ([#"^Window:closed":state:"open"] == 0)<br>
(push "alle Fenster geschlossen")<br>
<br>
attr di_Fenster do always<br>
attr di_Fenster cmdState [$SELF:Device] zuletzt geöffnet|alle geschlossen</code><br>
<br>
Raumtemperatur-Überwachung:<br>
<br>
<code>define di_temp DOIF (([08:00] or [20:00]) and [?#"^Rooms":temperature: $_ &lt 20] != 0)<br>
  (push "In folgenden Zimmern ist zu kalt [@"^Rooms":temperature:$_ &lt 20,"keine"]")<br>
DOELSE<br>
  (push "alle Zimmmer sind warm")<br>  
<br>
attr di_temp do always<br>
attr di_Raumtemp state In folgenden Zimmern ist zu kalt: [@"^Rooms":temperature:$_ &lt 20,"keine"])</code><br>
<br>
Es soll beim Öffnen eines Fensters eine Meldung über alle geöffneten Fenster erfolgen:<br>
<br>
<code>define di_Fenster DOIF (["^Window:open"]) (push "Folgende Fenster: [@"^Window:state:"open"] sind geöffnet")</code><br>
attr di_Fenster do always<br>
<br>
Wenn im Wohnzimmer eine Lampe ausgeschaltet wird, sollen alle anderen Lampen im Wohnzimmer ebenfalls ausgeschaltet werden, die noch an sind:<br>
<br>
<code>define di_lamp DOIF (["^lamp_livingroom: off"]) (set [@"^lamp_livingroom":state:"on","defaultdummy"] off)<br>
attr di_lamp DOIF do always</code><br>
<br>
Mit der Angabe des Default-Wertes "defaultdummy", wird verhindert, dass der set-Befehl eine Fehlermeldung liefert, wenn die Device-Liste leer ist. Der angegebene Default-Dummy muss zuvor definiert werden.<br>
<br>
Für reine Perlangaben gibt es eine entsprechende Perlfunktion namens <code>AggrDoIf(&lt;function&gt;,&lt;regex Device&gt;,&lt;reading&gt;,&lt;condition&gt;,&lt;default&gt;)</code> diese liefert bei der Angabe @ ein Array statt einer Stringliste,  dadurch lässt sie sich gut bei foreach-Schleifen verwenden.<br>
<br>
<u>Beispiele</u><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_Fenster DOIF {if (["^Window:open"]) {foreach (AggrDoIf('@','^windows','state','"open"')) {Log3 "di_Fenster",3,"Das Fenster $_ ist noch offen"}}}</code><br>
<br>
<code>define di_Temperature DOIF {if (["^room:temperature"]) {foreach (AggrDoIf('@','^room','temperature','$_ &lt 15')) {Log3 "di_Temperatur",3,"im Zimmer $_ ist zu kalt"}}</code><br>
<br>
<a name="DOIF_Zeitsteuerung"></a><br>
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
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_light DOIF<br>
{[08:00];fhem_set"switch on"}<br>
{[10:00];fhem_set"switch on"}<br>
</code><br>
<br>
Zeitsteuerung mit mehreren Zeitschaltpunkten:<br>
<br>
<code>define di_light DOIF ([08:00] or [10:00] or [20:00]) (set switch on) DOELSEIF ([09:00] or [11:00] or [00:00]) (set switch off)</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_light DOIF<br>
{if ([08:00] or [10:00] or [20:00]) {fhem_set"switch on"}}<br>
{if ([09:00] or [11:00] or [00:00]) {fhem_set"switch off"}}</code><br>
<br>
<a name="DOIF_Relative_Zeitangaben"></a><br>
<b>Relative Zeitangaben</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Zeitangaben, die mit Pluszeichen beginnen, werden relativ behandelt, d. h. die angegebene Zeit wird zum aktuellen Zeitpunkt hinzuaddiert.<br>
<br>
<u>Anwendungsbeispiel</u>: Automatisches Speichern der Konfiguration im Stundentakt:<br>
<br>
<code>define di_save DOIF ([+01:00]) (save)<br>
attr di_save do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_save DOIF {[+01:00];fhem"save"}</code><br>
<br>
Ebenfalls lassen sich relative Angaben in Sekunden angeben. [+01:00] entspricht [+3600];
<br>
<a name="DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet"></a><br>
<b>Zeitangaben nach Zeitraster ausgerichtet</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Das Format lautet: [:MM] MM sind Minutenangaben zwischen 00 und 59.<br>
<br>
<u>Anwendungsbeispiel</u>: Viertelstunden-Gong<br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_gong DOIF<br>
 {[:00];system"mplayer /opt/fhem/Sound/BigBen_00.mp3 -volume 90 −really−quiet &"}<br>
 {[:15];system"mplayer /opt/fhem/Sound/BigBen_15.mp3 -volume 90 −really−quiet &"}<br>
 {[:30];system"mplayer /opt/fhem/Sound/BigBen_30.mp3 -volume 90 −really−quiet &"}<br>
 {[:45];system"mplayer /opt/fhem/Sound/BigBen_45.mp3 -volume 90 −really−quiet &"}</code><br>
<br>
<a name="DOIF_Relative_Zeitangaben_nach_Zeitraster_ausgerichtet"></a><br>
<b>Relative Zeitangaben nach Zeitraster ausgerichtet</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Das Format lautet: [+:MM] MM sind Minutenangaben zwischen 00 und 59.<br>
<br>
<u>Anwendungsbeispiel</u>: Gong alle fünfzehn Minuten um XX:00 XX:15 XX:30 XX:45<br>
<br>
<code>define di_gong DOIF ([+:15]) (set Gong_mp3 playTone 1)<br>
attr di_gong do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_gong DOIF {[+:15];fhem_set"Gong_mp3 playTone 1"}</code><br>
<br>
<a name="DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet_alle_X_Stunden"></a><br>
<b>Zeitangaben nach Zeitraster ausgerichtet alle X Stunden</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Format: [+[h]:MM] mit: h sind Stundenangaben zwischen 1 und 23 und MM Minuten zwischen 00 und 59<br>
<br>
<u>Anwendungsbeispiel</u>: Es soll immer fünf Minuten nach einer vollen Stunde alle 2 Stunden eine Pumpe eingeschaltet werden, die Schaltzeiten sind 00:05, 02:05, 04:05 usw.<br>
<br>
<code>define di_gong DOIF ([+[2]:05]) (set pump on-for-timer 300)<br>
attr di_gong do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_gong DOIF {[+[2]:05];fhem_set"pump on-for-timer 300"}</code><br>
<br>
<a name="DOIF_Wochentagsteuerung"></a><br>
<b>Wochentagsteuerung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Hinter der Zeitangabe kann ein oder mehrere Wochentage getrennt mit einem Pipezeichen | angegeben werden. Die Syntax lautet:<br>
<br>
<code>[&lt;time&gt;|0123456789X]</code> mit 0 Sonntag, 1 Montag, ... bis 6 Samstag, 7 Wochenende und Feiertage (entspricht $we), 8 Arbeitstag (entspricht !$we),9 Wochenende oder Feiertag morgen (entspricht intern $twe), X Arbeitstag morgen (entspricht intern !$twe)<br>
<br>
alternativ mit Buchstaben-Kürzeln:<br>
<br>
<code>[&lt;time&gt;|So Mo Di Mi Do Fr Sa WE AT MWE MAT]</code> WE entspricht der Ziffer 7, AT der Ziffer 8, MWE der Ziffer 9, MAT dem Buchstaben X<br>
<br>
oder entsprechend mit englischen Bezeichnern:<br>
<br>
<code>[&lt;time&gt;|Su Mo Tu We Th Fr Sa WE WD TWE TWD]</code><br>
<br>
<li><a name="DOIF_weekdays"></a>
Mit Hilfe des Attributes <code>weekdays</code> können beliebige Wochentagbezeichnungen definiert werden.<br>
<a name="weekdays"></a><br>
Die Syntax lautet:<br>
<br>
<code>weekdays &lt;Bezeichnung für Sonntag&gt;,&lt;Bezeichnung für Montag&gt;,...,&lt;Bezeichnung für Wochenende oder Feiertag&gt;,&lt;Bezeichnung für Arbeitstag&gt;,&lt;Bezeichnung für Wochenende oder Feiertag morgen&gt;,&lt;Bezeichnung für Arbeitstag morgen&gt;</code><br>
<br>
Beispiel: <code>di_mydoif attr weekdays Son,Mon,Die,Mit,Don,Fre,Sam,Wochenende,Arbeitstag,WochenendeMorgen,ArbeitstagMorgen</code><br>
<br>
<u>Anwendungsbeispiel</u>: Radio soll am Wochenende und an Feiertagen um 08:30 Uhr eingeschaltet und um 09:30 Uhr ausgeschaltet werden. Am Montag und Mittwoch soll das Radio um 06:30 Uhr eingeschaltet und um 07:30 Uhr ausgeschaltet werden. Hier mit englischen Bezeichnern:<br>
<br>
<code>define di_radio DOIF ([06:30|Mon Wochenende] or [08:30|Wochenende]) (set radio on) DOELSEIF ([07:30|Mon Wochenende] or [09:30|Wochenende]) (set radio off)</code><br>
<code>attr di_radio weekdays Son,Mon,Die,Mit,Don,Fre,Sam,Wochenende,Arbeitstag,WochenendeMorgen</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_radio DOIF<br>
{if ([06:30|Mo We] or [08:30|WE]) {fhem_set"radio on"}}<br>
{if ([07:30|Mo We] or [09:30|WE]) {fhem_set"radio off"}}</code><br>
<br>
Bemerkung: Es ist unerheblich wie die definierten Wochenttagbezeichner beim Timer angegeben werden. Sie können mit beliebigen Trennzeichen oder ohne Trennzeichen direkt aneinander angegeben werden.<br>
<br>
Anstatt einer direkten Wochentagangabe, kann ein Status oder Reading in eckigen Klammern angegeben werden. Dieser muss zum Triggerzeitpunkt mit der gewünschten Angabe für Wochentage, wie oben definiert, belegt sein.<br>
<br>
<u>Anwendungsbeispiel</u>: Der Wochentag soll über einen Dummy bestimmt werden.<br>
<br>
<code>define dummy myweekday<br>
set myweekday monday wednesday thursday weekend<br>
<br>
define di_radio DOIF ([06:30|[myweekday]]) (set radio on) DOELSEIF ([07:30|[myweekday]]) (set radio off)<br>
attr di_radio weekdays sunday,monday,thuesday,wednesday,thursday,friday,saturday,weekend,workdays,weekendtomorrow</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_radio DOIF<br>
{[06:30|[myweekday]];fhem_set"radio on"}<br>
{[07:30|[myweekday]];fhem_set"radio off"}<br><br>
attr di_radio weekdays sunday,monday,thuesday,wednesday,thursday,friday,saturday,weekend,workdays,weekendtomorrow</code><br>
<br>
</li><a name="DOIF_Zeitsteuerung_mit_Zeitintervallen"></a><br>
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
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_radio DOIF {if ([08:00-10:00]) {fhem_set"radio on"} else {fhem_set"radio off"}}</code><br>
<br>
mit mehreren Zeitintervallen:<br>
<br>
<code>define di_radio DOIF ([08:00-10:00] or [20:00-22:00]) (set radio on) DOELSE (set radio off) </code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_radio DOIF {if ([08:00-10:00] or [20:00-22:00]) {fhem_set"radio on"} else {fhem_set"radio off"}}</code><br>
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
Zeitintervalle über mehrere Tage müssen als Zeitpunkte angegeben werden.<br>
<br>
Einschalten am Freitag ausschalten am Montag:<br>
<br>
<code>define di_light DOIF ([22:00|5]) (set light on) DOELSEIF ([10:00|1]) (set light off) </code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_light DOIF<br>
{[22:00|5];fhem_set"light on"}<br>
{[10:00|1];fhem_set"light off"}</code><br>
<br>
Schalten mit Zeitfunktionen, hier: bei Sonnenaufgang und Sonnenuntergang:<br>
<br>
<code>define di_light DOIF ([{sunrise(900,"06:00","08:00")}]) (set outdoorlight off) DOELSEIF ([{sunset(900,"17:00","21:00")}]) (set outdoorlight on)</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_light DOIF<br>
{[{sunrise(900,"06:00","08:00")}];fhem_set"outdoorlight off"}<br>
{[{sunset(900,"17:00","21:00")}];fhem_set"outdoorlight on"}</code><br>
<br>
<a name="DOIF_Indirekten_Zeitangaben"></a><br>
<b>Indirekte Zeitangaben</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Statt fester Zeitangaben kann ein Status oder ein Reading angegeben werden, welches eine Zeitangabe beinhaltet. Die Angaben werden in doppelte eckige Klammern gesetzt. Eine Änderung der Zeit im angegebenen Reading bzw. Status führt zu sofortiger Neuberechnung der Zeit im DOIF.<br>
<br>
Syntax:<br>
<br>
<code>[[&lt;Device&gt;:&lt;Reading&gt;]]</code> bzw. bei Statusangabe <code>[[&lt;Device&gt;]]</code><br>
<br>
Bei relativen Zeitangaben (hier wird die Zeitangabe zu aktueller Zeit hinzuaddiert):<br>
<br>
<code>[+[&lt;Device&gt;:&lt;Reading&gt;]]</code> bzw. bei Statusangabe <code>[+[&lt;Device&gt;]]</code><br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll zu einer bestimmten Zeit eingeschaltet werden. Die Zeit soll über den Dummy <code>time</code> einstellbar sein:<br>
<br>
<code>define time dummy<br>
set time 08:00<br>
<br>
define di_time DOIF ([[time]])(set lamp on)<br>
attr di_time do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_time DOIF {[[time]];fhem_set"lamp on"}</code><br>
<br>
Die indirekte Angabe kann ebenfalls mit einer Zeitfunktion belegt werden. Z. B. <br>
<br>
<code>set time {sunset()}</code><br>
<br>
Das Dummy kann auch mit einer Sekundenzahl belegt werden, oder als relative Zeit angegeben werden, hier z. B. schalten alle 300 Sekunden:<br>
<br>
<code>define time dummy<br>
set time 300<br>
<br>
define di_time DOIF ([+[time]])(save)<br>
attr di_time do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_time DOIF {[+[time]];fhem"save"}</code><br>
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
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_time DOIF {if([[begin]-[end]]) {fhem_set"radio on"} else {fhem_set"radio off"}}</code><br>
<br>
Indirekte Zeitangaben können auch als Übergabeparameter für Zeitfunktionen, wie z. B. sunset oder sunrise übergeben werden:<br>
<br>
<code>define di_time DOIF ([{sunrise(0,"[begin]","09:00")}-{sunset(0,"18:00","[end]")}]) (set lamp off) DOELSE (set lamp on) </code><br>
<br>
Bei einer Änderung des angegebenen Status oder Readings wird die geänderte Zeit sofort im Modul aktualisiert.<br>
<br>
Angabe eines Readings als Zeitangabe. Beispiel: Schalten anhand eines Twilight-Readings:<br>
<br>
<code>define di_time DOIF ([[myTwilight:ss_weather]])(set lamp on)</code><br>
<code>attr di_timer do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_time DOIF {[[myTwilight:ss_weather]];fhem_set"lamp on"}</code><br>
<br>
Indirekte Zeitangaben lassen sich mit Wochentagangaben kombinieren, z. B.:<br>
<br>
<code>define di_time DOIF ([[begin]-[end]|7]) (set radio on) DOELSE (set radio off)</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_time DOIF {if ([[begin]-[end]|7]) {fhem_set"radio on"} else {fhem_set"radio off"}}</code><br>
<br>
<a name="DOIF_Zeitsteuerung_mit_Zeitberechnung"></a><br>
<b>Zeitsteuerung mit Zeitberechnung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Zeitberechnungen werden innerhalb der eckigen Klammern zusätzlich in runde Klammern gesetzt. Die berechneten Triggerzeiten können absolut oder relativ mit einem Pluszeichen vor den runden Klammern angegeben werden.
Es können beliebige Ausdrücke der Form HH:MM und Angaben in Sekunden als ganze Zahl in Perl-Rechenoperationen kombiniert werden.
Perlfunktionen, wie z. B. sunset(), die eine Zeitangabe in HH:MM liefern, werden in geschweifte Klammern gesetzt.
Zeiten im Format HH:MM bzw. Status oder Readings, die Zeitangaben in dieser Form beinhalten werden in eckige Klammern gesetzt.<br>
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
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_light DOIF<br>
{[({sunset()}+900+int(rand(600)))];;fhem_set"lamp on"}<br>
{[([23:00]+int(rand(600)))];;fhem_set"lamp off"}<br>
</code><br>
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
<a name="DOIF_Intervall-Timer"></a><br>
<b>Intervall-Timer</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Syntax:<br>
<br>
<code>[&lt;begin&gt-&lt;end&gt,&lt;relative timer&gt]</code><br>
<br>
Innerhalb des definierten Zeitintervalls, triggert der definierte Timer. Außerhalb des Zeitintervall wird kein Timer gesetzt.<br>
<br>
<u>Anwendungsbeispiel</u>: Zwischen 08:00 und 22:00 Uhr soll eine Pumpe jede halbe Stunde für fünf Minuten eingeschaltet werden:<br>
<br>
<code>define di_pump DOIF ([08:00-22:00,+:30])(set pump on-for-timer 300)<br>
attr di_pump do always </code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_pump DOIF {[08:00-22:00,+:30];;fhem_set"pump on-for-timer 300"}</code><br>
<br>
Es wird um 08:00, 08:30, 09:00, ..., 21:30 Uhr die Anweisung ausgeführt. Um 22:00 wird das letzte Mal getriggert, das Zeitintervall ist zu diesem Zeitpunkt nicht mehr wahr.<br>
<br>
Es lassen sich ebenso indirekte Timer, Timer-Funktionen, Zeitberechnungen sowie Wochentage miteinander kombinieren.<br>
<br>
<code>define di_rand_lamp DOIF ([{sunset()}-[end:state],+(rand(600)+900)|Sa So])(set lamp on-for-timer 300)<br>
attr di_rand_lamp do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_rand_lamp DOIF {[{sunset()}-[end:state],+(rand(600)+900)|Sa So];;fhem_set"lamp on-for-timer 300"}</code><br>
<br>
<a name="DOIF_Zeitsteuerung_alle_X_Tage"></a><br>
<b>Zeittrigger alle X Tage</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit Hilfe der Zeitberechnung kann ein Zeitpunkt statt täglich alle X Tage triggern.<br>
<br>
Syntax:<br>
<br>
<code>[([&lt;time&gt;]+&lt;days&gt;*[24:00])]</code><br>
<br>
<u>Anwendungsbeispiel</u>: Alle zwei Tage sollen Pflanzen um 21:00 Uhr gewässert werden:<br>
<br>
<code>define di_water_plants DOIF ([([21:00]+2*[24:00])])(set water on-for-timer 60)<br>
attr di_water_plants do always </code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_water_plants DOIF {[([21:00]+2*[24:00])];;fhem_set"water on-for-timer 60"}</code><br>
<br>
<a name="DOIF_Kombination_von_Ereignis_und_Zeitsteuerung_mit_logischen_Abfragen"></a><br>
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
<a name="DOIF_Zeitintervalle_Readings_und_Status_ohne_Trigger"></a><br>
<b>Zeitintervalle, Readings und Status ohne Trigger</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Angaben in eckigen Klammern, die mit einem Fragezeichen beginnen, führen zu keiner Triggerung des Moduls, sie dienen lediglich der Abfrage.<br>
<br>
<u>Anwendungsbeispiel</u>: Licht soll zwischen 06:00 und 10:00 angehen, getriggert wird nur durch den Taster nicht um 06:00 bzw. 10:00 Uhr und nicht durch das Device Home<br>
<br>
<code>define di_motion DOIF ([?06:00-10:00] and [button] and [?Home] eq "present")(set lamp on-for-timer 600)<br>
attr di_motion do always</code><br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define di_motion DOIF {if ([?06:00-10:00] and [button] and [?Home] eq "present"){fhem_set"lamp on-for-timer 600"}}</code><br>
<br>
<a name="DOIF_Nutzung_von_Readings_Status_oder_Internals_im_Ausfuehrungsteil"></a><br>
<b>Nutzung von Readings, Status oder Internals im Ausführungsteil</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<u>Anwendungsbeispiel</u>: Wenn ein Taster betätigt wird, soll Lampe1 mit dem aktuellen Zustand der Lampe2 geschaltet werden:<br>
<br>
<code>define di_button DOIF ([button]) (set lamp1 [lamp2])<br>
attr di_button do always</code><br>
<br>
<u>Anwendungsbeispiel</u>: Benachrichtigung beim Auslösen eines Alarms durch Öffnen eines Fensters:<br>
<br>
<code>define di_pushmsg DOIF ([window] eq "open" and [alarm] eq "armed") (set Pushover msg 'alarm' 'open windows [window:LastDevice]' '' 2 'persistent' 30 3600)</code><br>
<br>
<a name="DOIF_Berechnungen_im_Ausfuehrungsteil"></a><br>
<b>Berechnungen im Ausführungsteil</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Berechnungen können in geschweiften Klammern erfolgen. Aus Kompatibilitätsgründen, muss die Berechnung unmittelbar mit einer runden Klammer beginnen.
Innerhalb der Perlberechnung können Readings, Status oder Internals wie gewohnt in eckigen Klammern angegeben werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Es soll ein Vorgabewert aus zwei verschiedenen Readings ermittelt werden und an das set Kommando übergeben werden:<br>
<br>
<code>define di_average DOIF ([08:00]) (set TH_Modul desired {([default:temperature]+[outdoor:temperature])/2})<br>
attr di_average do always</code><br>
<br>
<li><a name="DOIF_notexist"></a>
<b>Ersatzwert für nicht existierende Readings oder Status</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="notexist"></a>
Es kommt immer wieder vor, dass in der Definition des DOIF-Moduls angegebene Readings oder Status zur Laufzeit nicht existieren. Der Wert ist dann leer.
Bei der Definition von Status oder Readings kann für diesen Fall ein Vorgabewert oder sogar eine Perlberechnung am Ende des Ausdrucks kommagetrennt angegeben werden.<br>
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
</li><li><a name="DOIF_wait"></a>
<b>Verzögerungen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="wait"></a>
Verzögerungen für die Ausführung von Kommandos werden pro Befehlsfolge über das Attribut "wait" definiert. Syntax:<br>
<br>
<code>attr &lt;DOIF-module&gt; wait &lt;Sekunden für Befehlsfolge des ersten DO-Falls&gt;:&lt;Sekunden für Befehlsfolge des zweiten DO-Falls&gt;:...<br></code>
<br>
Sollen Verzögerungen innerhalb von Befehlsfolgen stattfinden, so müssen diese Kommandos in eigene Klammern gesetzt werden, das Modul arbeitet dann mit Zwischenzuständen.<br>
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
Statt Sekundenangaben können ebenfalls Status, Readings in eckigen Klammern, Perl-Funktionen sowie Perl-Berechnung angegeben werden. Dabei werden die Trennzeichen Komma und Doppelpunkt in Klammern geschützt und gelten dort nicht als Trennzeichen.
Diese Angaben können ebenfalls bei folgenden Attributen gemacht werden: cmdpause, repeatcmd, repeatsame, waitsame, waitdel<br>
<br>
Beispiel:<br>
<br>
<code>attr my_doif wait 1:[mydummy:state]*3:rand(600)+100,Attr("mydevice","myattr","")</code><br>
<br>
</li><li><a name="DOIF_timerWithWait"></a>
<b>Verzögerungen von Timern</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="timerWithWait"></a>
Verzögerungen können mit Hilfe des Attributs <code>timerWithWait</code> auf Timer ausgeweitet werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll zufällig nach Sonnenuntergang verzögert werden.<br>
<br>
<code>define di_rand_sunset DOIF ([{sunset()}])(set lamp on)<br>
attr di_rand_sunset wait rand(1200)<br>
attr di_rand_sunset timerWithWait 1<br>
attr di_rand_sunset do always</code><br>
<br>
<u>Anwendungsbeispiel</u>: Benachrichtigung "Waschmaschine fertig", wenn Verbrauch mindestens 5 Minuten unter 2 Watt (Perl-Code wird in geschweifte Klammern gesetzt):<br>
<br>
<code>define di_washer DOIF ([power:watt]&lt;2) ({system("wmail washer finished")})<br>
attr di_washer wait 300</code><br>
<br>
Eine erneute Benachrichtigung wird erst wieder ausgelöst, wenn zwischendurch der Verbrauch über 2 Watt angestiegen war.<br>
<br>
<u>Anwendungsbeispiel</u>: Rollladen um 20 Minuten zeitverzögert bei Sonne runter- bzw. hochfahren (wenn der Zustand der Sonne wechselt, wird die Verzögerungszeit zurückgesetzt):<br>
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
</li><li><a name="DOIF_do_resetwait"></a>
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
</li><li><a name="DOIF_repeatcmd"></a>
<b>Wiederholung von Befehlsausführung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<a name="repeatcmd"></a>
<br>
Wiederholungen der Ausführung von Kommandos werden pro Befehlsfolge über das Attribut <code>repeatcmd</code> definiert. Syntax:<br>
<br>
<code>attr &lt;DOIF-modul&gt; repeatcmd &lt;Sekunden für Befehlsfolge des ersten DO-Falls&gt;:&lt;Sekunden für Befehlsfolge des zweiten DO-Falls&gt;:...<br></code>
<br>
Statt Sekundenangaben können ebenfalls Status in eckigen Klammen oder Perlbefehle angegeben werden.<br>
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
</li><li><a name="DOIF_cmdpause"></a>
<b>Zwangspause für das Ausführen eines Kommandos seit der letzten Zustandsänderung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<a name="cmdpause"></a>
<br>
Mit dem Attribut <code>cmdpause &lt;Sekunden für cmd_1&gt;:&lt;Sekunden für cmd_2&gt;:...</code> wird die Zeitspanne in Sekunden angegeben für eine Zwangspause seit der letzten Zustandsänderung.
In der angegebenen Zeitspanne wird ein Kommando nicht ausgeführt, auch wenn die dazugehörige Bedingung wahr wird.<br>
<br>
<u>Anwendungsbeispiel</u>: Meldung über Frostgefahr alle 60 Minuten<br>
<br>
<code>define di_frost DOIF ([outdoor:temperature] &lt 0) (set pushmsg "danger of frost")<br>
attr di_frost cmdpause 3600<br>
attr di_frost do always</code><br>
<br>
</li><li><a name="DOIF_repeatsame"></a>
<b>Begrenzung von Wiederholungen eines Kommandos</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<a name="repeatsame"></a>
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
</li><li><a name="DOIF_waitsame"></a>
<b>Ausführung eines Kommandos nach einer Wiederholung einer Bedingung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<a name="waitsame"></a>
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
</li><li><a name="DOIF_waitdel"></a>
<b>Löschen des Waittimers nach einer Wiederholung einer Bedingung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<a name="waitdel"></a>
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
</li><li><a name="DOIF_checkReadingEvent"></a>
<b>Readingauswertung bei jedem Event des Devices</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<a name="checkReadingEvent"></a><br>
Bei Angaben der Art <code>[&lt;Device&gt;:&lt;Reading&gt;]</code> wird das Modul getriggert, wenn ein Ereignis zum angegebenen Device und Reading kommt. Soll das Modul, wie bei Statusangaben der Art <code>[&lt;Device&gt;]</code>, auf alle Ereignisse des Devices reagieren, so muss das Attribut auf Null gesetzt werden.<br>
<br>
Bemerkung: In früheren Versionen des Moduls war <code>checkReadingEvent 0</code> die Voreinstellung des Moduls. Da die aktuelle Voreinstellung des Moduls <code>checkReadingEvent 1</code> ist, hat das Setzen von 
<code>checkReadingEvent 1</code> keine weitere Funktion mehr.<br>
<br>
</li><li><a name="DOIF_addStateEvent"></a>
<b>Eindeutige Statuserkennung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<a name="addStateEvent"></a>
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
</li><li><a name="DOIF_selftrigger"></a>
<b>Triggerung durch selbst ausgelöste Events</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<a name="selftrigger"></a>
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
</li><li><a name="DOIF_timerevent"></a>
<b>Setzen der Timer mit Event</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="timerevent"></a>
Wenn das Attribut <code>timerevent</code> ungleich Null gesetzt ist, wird beim Setzen der Timer im DOIF-Modul ein Event erzeugt. Das kann z. B. bei FHEM2FHEM nützlich sein, um die Timer-Readings zeitnah zu aktualisieren.<br>
<br>
</li><li><a name="DOIF_Zeitspanne_eines_Readings_seit_der_letzten_Aenderung"></a>
<b>Zeitspanne eines Readings seit der letzten Änderung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Bei Readingangaben kann die Zeitspanne mit <code>[&lt;Device&gt;:&lt;Reading&gt;:sec]</code> in Sekunden seit der letzten Änderung bestimmt werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Überwachung eines Temperatursensors<br>
<br>
<code>define di_monitor DOIF ([+01:00] and [?sensor:temperature:sec]>3600)(set pushbullet message sensor failed)<br>
attr di_monitor do always</code><br>
<br>
Wenn der Temperatursensor seit über einer Stunde keinen Temperaturwert geliefert hat, dann soll eine Nachricht erfolgen.<br>
<br>
</li><li><a name="DOIF_checkall"></a>
<b>Alle Bedingungen prüfen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="checkall"></a>
Bei der Abarbeitung der Bedingungen, werden nur die Bedingungen überprüft,
die zum ausgelösten Event das dazughörige Device bzw. die dazugehörige Triggerzeit beinhalten. Mit dem Attribut <b>checkall</b> lässt sich das Verhalten so verändern,
dass bei einem Event-Trigger auch Bedingungen geprüft werden, die das triggernde Device nicht beinhalten.
Folgende Parameter können angegeben werden:<br>
<br>
<code>checkall event</code> Es werden alle Bedingungen geprüft, wenn ein Event-Trigger auslöst.<br>
<code>checkall timer</code> Es werden alle Bedingungen geprüft, wenn ein Timer-Trigger auslöst.<br>
<code>checkall all&nbsp;&nbsp;</code> Es werden grundsätzlich alle Bedingungen geprüft.<br>
<br>
Zu beachten ist, dass bei einer wahren Bedingung die dazugehörigen Befehle ausgeführt werden und die Abarbeitung immer beendet wird -
 es wird also grundsätzlich immer nur ein Befehlszweig ausgeführt und niemals mehrere.<br>
<br>
</li><li><a name="DOIF_setList__readingList"></a>
<b>Darstellungselement mit Eingabemöglichkeit im Frontend und Schaltfunktion</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="setList"></a>
Die unter <i>Dummy</i> beschriebenen Attribute <i>readingList</i> und <i>setList</i> stehen auch im DOIF zur Verf&uuml;gung. Damit wird erreicht, dass DOIF im Web-Frontend als Eingabeelement mit Schaltfunktion dienen kann. Zus&auml;tzliche Dummys sind nicht mehr erforderlich. Es k&ouml;nnen im Attribut <i>setList</i>, die in <i>FHEMWEB</i> angegebenen Modifier des Attributs <i>widgetOverride</i> verwendet werden.<br>
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
<u>Anwendungsbeispiel</u>: Ausführung von Befehlen abhängig einer Auswahl ohne Zusatzreading<br>
<br>
<code>define di_web DOIF ([$SELF:"myInput first"]) (do something) DOELSEIF ([$SELF:"myInput second"]) (do something else)<br>
<br>
attr di_web setList myInput:first,second</code><br>
<br>
<u>Links</u><br>
<a href="#readingList">readingList</a><br>
<a href="#setList">setList</a><br>
<a href="#webCmd">webCmd</a><br>
<a href="#webCmdLabel">webCmdLabel</a><br>
<a href="#widgetOverride">widgetOverride</a><br>
<a href="http://www.fhemwiki.de/wiki/DOIF/Ein-_und_Ausgabe_in_FHEMWEB_und_Tablet-UI_am_Beispiel_einer_Schaltuhr">weiterf&uuml;hrendes Beispiel für Tablet-UI</a><br>
<a href="#DOIF_Benutzerreadings">benutzerdefinierte Readings</a><br>
<a href="#DOIF_setcmd">Bedingungsloses Ausf&uuml;hren von Befehlen</a><br>
<br>
</li><li><a name="DOIF_uiTable"></a>
<b>uiTable, DOIF Web-Interface</a></b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="uiTable"></a>
Mit dem Attribut uiTable kann innerhalb eines DOIF-Moduls ein Web-Interface zur Visualisierung und Steuerung von Geräten in Form einer Tabelle erstellt werden.<br> 
<br> 
Die Dokumentation zu diesem Attribut wurde mit bebilderten Beispielen im FHEM-Wiki erstellt: <a href="https://wiki.fhem.de/wiki/DOIF/uiTable_Schnelleinstieg">uiTable/uiState Dokumentation</a><br>
<br>
Anwendungsbeispiele für Fortgeschrittene: <a href="https://wiki.fhem.de/wiki/DOIF/uiTable">uiTable für Fortgeschrittene im FHEM-Wiki</a><br>
<br>
</li><li><a name="DOIF_uiState"></a>
<b>uiState</a></b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="uiState"></a>
Die Syntax des uiState-Attributes entspricht der des uiTable-Attributes. Die definierte Tabelle wird jedoch in der Statuszeile des DOIF-Devices dargestellt.<br>
<br> 
Siehe Dokumentation: <a href="https://wiki.fhem.de/wiki/DOIF/uiTable_Schnelleinstieg">uiTable/uiState Dokumentation</a><br>
<br>
</li><li><a name="DOIF_cmdState"></a>
<b>Status des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="cmdState"></a>
Der Status des Moduls wird standardmäßig mit cmd_1, cmd_2, usw., bzw. cmd1_1 cmd1_2 usw. für Befehlssequenzen belegt. Dieser lässt sich über das Attribut "cmdState" mit Komma bzw. | getrennt umdefinieren:<br>
<br>
attr &lt;DOIF-modul&gt; cmdState  &lt;Status für cmd1_1&gt;,&lt;Status für cmd1_2&gt;,...| &lt;Status für cmd2_1&gt;,&lt;Status für cmd2_2&gt;,...|...<br>
<br>
Beispiele:<br>
<br>
<code>attr di_lamp cmdState on|off</code><br>
<br>
Pro Status können ebenfalls Status oder Readings in eckigen Klammern oder Perlfunktionen sowie Berechnungen in Klammern der Form {(...)} angegeben werden.<br>
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
</li><li><a name="DOIF_state"></a>
<b>Anpassung des Status mit Hilfe des Attributes <code>state</code></b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="state"></a>
Es können beliebige Reading und Status oder Internals angegeben werden.<br>
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
</li><li><a name="DOIF_DOIF_Readings"></a>
<a name="DOIF_Readings"></a>
<b>Erzeugen berechneter Readings ohne Events</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit Hilfe des Attributes DOIF_Readings können eigene Readings innerhalb des DOIF definiert werden, auf die man im selben DOIF-Device zugreifen kann.
Die Nutzung ist insbesondere dann sinnvoll, wenn zyklisch sendende Sensoren, im Perl-Modus oder mit dem Attribut do always, abgefragt werden.
DOIF_Readings-Berechnungen funktionieren ressourcenschonend ohne Erzeugung FHEM-Events nach außen. Änderungen dieser Readings triggern intern das eigene DOIF-Modul, allerdings nur, wenn sich deren Inhalt ändert.<br>
<br>
Syntax<br>
<br>
<code>attr &lt;DOIF-Modul&gt; DOIF_Readings &lt;readingname1&gt;:&lt;definiton&gt;, &lt;readingname2&gt;:&lt;definition&gt;,...</code><br>
<br>
<code>&lt;definition&gt;</code>: Beliebiger Perlausdruck ergänzt um DOIF-Syntax in eckigen Klammern. Angaben in eckigen Klammern wirken triggernd und aktualisieren das definierte Reading.<br>
<br>
Beispiel<br>
<br>
<a href="#DOIF_Perl_Modus"><b>Perl-Modus</b>:</a><br>
<code>define heating DOIF {if ([switch] eq "on" and [$SELF:frost]) {fhem_set"heating on"} else {fhem_set"heating off"}}<br>
attr heating DOIF_Readings frost:([outdoor:temperature] &lt 0)</code><br>
<br>
Das Reading frost triggert nur dann die definierte Abfrage, wenn sich sein Zustand ändert. Dadurch wird sichergestellt, dass ein wiederholtes Schalten der Heizung vermieden wird, obwohl der Sensor outdoor zyklisch sendet.<br>
<br>
Beispiel: Push-Mitteilung über die durchschnittliche Temperatur aller Zimmer<br>
<br>
<code>define di_temp DOIF ([$SELF:temperature]&gt;20) (push "Die Durchschnittstemperatur ist höher als 20 Grad, sie beträgt [$SELF:temperature]")<br>
<br>
attr di_temp DOIF_Readings temperature:[#average:d2:":temperature":temperature]<br></code>
<br>
Hierbei wird der aufwändig berechnete Durchschnittswert nur einmal berechnet, statt zwei mal, wenn man die Aggregationsfunktion direkt in der Bedingung und im Ausführungsteil angeben würde.<br>
<br>
</li><li>
<a name="DOIF_event_Readings"></a>
<a name="event_Readings"></a>
<b>Erzeugen berechneter Readings mit Events</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit Hilfe des Attributes event_Readings können eigene Readings innerhalb des DOIF definiert werden. Dieses Atrribut hat die gleiche Syntax wie <a href="#DOIF_DOIF_Readings">DOIF_Readings</a>. Der Unterschied besteht darin, dass event_Readings im Gegensatz zu DOIF_Readings beim Setzen der definierten Readings jedes mal Events produziert.
Die Nutzung von event_Readings ist insb. dann sinnvoll, wenn man eventgesteuert außerhalb des Moduls auf die definierten Readings zugreifen möchte.<br>
<br>
Syntax<br>
<br>
<code>attr &lt;DOIF-Modul&gt; event_Readings &lt;readingname1&gt;:&lt;definiton&gt;, &lt;readingname2&gt;:&lt;definition&gt;,...</code><br>
<br>
<code>&lt;definition&gt;</code>: Beliebiger Perlausdruck ergänzt um DOIF-Syntax in eckigen Klammern. Angaben in eckigen Klammern wirken triggernd und aktualisieren das definierte Reading.<br>
<br>
Bsp.:<br>
<br>
<code>define outdoor DOIF ##<br>
<br>
attr outdoor event_Readings\<br>
median:[outdoor:temperature:med],\<br>
average:[outdoor:temperature:avg10],\<br>
diff: [outdoor:temperature:diff],\<br>
increase: [outdoor:temperature:inc]</code><br>
<br>
Auf die definierten Readings des Moduls outdoor (hier: median, average, diff und increase) kann in anderenen Modulen eventgesteuert zugegriffen werden.<br>
<br>
Bemerkung: Sind Events des definierten Readings nicht erforderlich und nur die interne Triggerung des eigenen DOIF-Moduls interessant,
dann sollte man das Attribut <a href="#DOIF_DOIF_Readings">DOIF_Readings</a> nutzen, da es durch die interne Triggerung des Moduls weniger das System belastet als event_Readings.<br>
<br>
</li><li><a name="DOIF_initialize"></a>
<b>Vorbelegung des Status mit Initialisierung nach dem Neustart</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="initialize"></a>
Mit dem Attribut <code>initialize</code> Wird der Status vorbelegt, mit Initialisierung nach dem Neustart.<br>
<br>
<u>Anwendungsbeispiel</u>: Nach dem Neustart soll der Zustand von <code>di_lamp</code> mit "initialized" vorbelegt werden. Das Reading <code>cmd_nr</code> wird auf 0 gesetzt, damit wird ein Zustandswechsel provoziert, das Modul wird initialisiert - der nächste Trigger führt zum Ausführen eines Kommandos.<br>
<br>
<code>attr di_lamp initialize initialized</code><br>
<br>
Das ist insb. dann sinnvoll, wenn das System ohne Sicherung der Konfiguration (unvorhergesehen) beendet wurde und nach dem Neustart die zuletzt gespeicherten Zustände des Moduls nicht mit den tatsächlichen übereinstimmen.<br>
<br>
</li><li><a name="DOIF_startup"></a>
<b>Ausführen von Befehlsketten beim Starten von FHEM</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="startup"></a>
Beim Hochfahren von FHEM lässt sich eine bestimme Aktion ausführen. Es kann dazu genutzt werden, um sofort nach dem Hochfahren des Systems einen definierten Zustand des Moduls zu erreichen.
Dabei wird sichergestellt, dass die angegebenen Befehle erst dann ausgeführt werden, wenn FHEM komplett hochgefahren ist.<br>
<br>
Symtax:<br>
<br>
<code>attr &lt;DOIF-Modul&gt; startup &lt;FHEM-Befehl oder Perl-Befehl in geschweiften Klammern mit DOIF-Syntax&gt;</code><br>
<br>
Die Syntax entspricht der eines DOIF-Ausführungsteils (runde Klammern brauchen nicht angegeben werden).<br>
<br>
Beispiele:<br>
<br>
<code>attr di_test startup set $SELF cmd_1</code><br>
<code>attr di_test startup set $SELF checkall</code><br>
<code>attr di_test startup sleep 60;set lamp1 off;set lamp2 off</code><br>
<code>attr di_test startup {myfunction()},set lamp1 on,set lamp2 on</code><br>
<br>
</li><li><a name="DOIF_disable"></a>
<b>Deaktivieren des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="disable"></a>
Ein DOIF-Modul kann mit Hilfe des Attributes disable, deaktiviert werden. Dabei werden alle Timer und Readings des Moduls gelöscht.
Soll das Modul nur vorübergehend deaktiviert werden, so kann das durch <code>set &lt;DOIF-modul&gt; disable</code> geschehen.
<br>
<br>
</li><a name="DOIF_setBefehle"></a>
<b>Set-Befehle</b><br>
<br>
<li><a name="DOIF_setcheckall"></a>
<b>Überprüfung aller DOIF-Bedingungen mit Ausführung eines DOIF-Zweiges</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="checkall"></a>
Mit dem set-Befehl <code>checkall</code> werden wie beim gleichnamigen Attribut alle DOIF-Bedingung überprüft, sobald eine Bedingung als wahr geprüft ist, wird das dazugehörige Kommando ausgeführt.
Zu beachten ist, dass nur der erste wahre DOIF-Zweig ausgeführt wird und dass nur Zustandsabfragen sowie Zeitintervalle sinnvoll überprüft werden können.
Ereignisabfragen sowie Zeitpunkt-Definitionen, sind zum Zeitpunkt der checkall-Abfrage normalerweise nicht wahr.<br>
<br>
Beispiel:<br>
<br>
<code>attr di_test startup set $SELF checkall</code><br>
<br>
</li><li><a name="DOIF_setdisable"></a>
<b>Inaktivieren des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="disable"></a>
Mit dem set-Befehl <code>disable</code> wird ein DOIF-Modul inaktiviert. Hierbei bleiben alle Timer aktiv, sie werden aktualisiert - das Modul bleibt im Takt, allerdings werden keine Befehle ausgeführt.
Das Modul braucht mehr Rechenzeit, als wenn es komplett über das Attribut <code>disable</code> deaktiviert wird. Ein inaktiver Zustand bleibt nach dem Neustart erhalten.
Ein inaktives Modul kann über set-Befehle <code>enable</code> bzw. <code>initialize</code> (im FHEM-Modus) wieder aktiviert werden.<br>
<br>
</li><li><a name="DOIF_setenable"></a>
<b>Aktivieren des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="enable"></a>
Mit dem set-Befehl <code>enable</code> wird ein inaktives DOIF-Modul wieder aktiviert. Im FHEM-Modus: Im Gegensatz zum set-Befehl <code>initialize</code> wird der letzte Zustand vor der Inaktivierung des Moduls wieder hergestellt.<br>
<br>
</li><li><a name="DOIF_setinitialize"></a>
<a name="DOIF_Initialisieren_des_Moduls"></a>
<b>Initialisieren des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
mit dem set-Befehl <code>initialize</code> wird ein DOIF-Modul initialisiert. Ein inaktives DOIF-Modul wieder aktiviert.
Im Gegensatz zum set-Befehl <code>enable</code> wird der letzte Zustand des Moduls gelöscht, damit wird ein Zustandswechsel herbeigeführt, der nächste Trigger führt zur Ausführung eines wahren DOIF-Zweiges.
Diese Eigenschaft kann auch dazu genutzt werden, ein bereits aktives Modul zu initialisieren.<br>
<br>
</li><li><a name="DOIF_setcmd"></a>
<b>Auführen von Befehlszweigen ohne Auswertung der Bedingung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<a name="cmd_1"></a>
Mit <code>set &lt;DOIF-modul&gt; cmd_&lt;nr&gt</code> lässt sich ein Befehlszweig (cmd_1, cmd_2, usw.) bedingunglos ausführen.<br>
<br>
Der Befehl hat folgende Eigenschaften:<br>
<br>
1) der set-Befehl übersteuert alle Attribute wie z. B. wait, do, usw.<br>
2) bei wait wird der erste Timer einer Sequenz ignoriert, alle folgenden Timer einer Sequenz werden jedoch beachtet<br>
3) ein laufender Wait-Timer wird unterbrochen<br>
4) beim deaktivierten oder im Modus disable befindlichen Modul wird der set Befehl ignoriert<br>
<br>
<u>Anwendungsbeispiel</u>: Schaltbare Lampe über Fernbedienung und Webinterface<br>
<br>
<code>
define di_lamp DOIF ([FB:"on"]) (set lamp on) DOELSEIF ([FB:"off"]) (set lamp off)<br>
<br>
attr di_lamp devStateIcon cmd_1:on:cmd_2 initialized|cmd_2:off:cmd_1<br>
</code><br>
Mit der Definition des Attributes <code>devStateIcon</code> führt das Anklicken des on/off-Lampensymbol zum Ausführen von <code>set di_lamp cmd_1</code> bzw. <code>set di_lamp cmd_2</code> und damit zum Schalten der Lampe.<br>
<br>
Wenn mit <code>cmdState</code> eigene Zuständsbezeichnungen definiert werden, so können diese ebenfalls per set-Befehl angegeben werden.<br>
<br>
<code>
define di_lamp DOIF ([FB:"on"]) (set lamp on) DOELSEIF ([FB:"off"]) (set lamp off)<br>
<br>
attr di_lamp cmdState on|off<br>
attr di_lamp setList on off<br>
</code>
<br>
<code>set di_lamp on</code> entspricht hier <code>set di_lamp cmd_1</code> und <code>set di_lamp off set di_lamp cmd_2</code><br>
Zusätzlich führt die Definition von <code>setList</code> zur Ausführung von <code>set di_lamp on/off</code> durch das Anlicken des Lampensymbols wie im vorherigen Beispiel.<br>
<br>
<br>
</li><a name="DOIF_Weitere_Anwendungsbeispiele"></a>
<b>Weitere Anwendungsbeispiele</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Zweipunktregler a la THRESHOLD<br>
<br>
<code>define di_threshold DOIF ([sensor:temperature] &lt [$SELF:desired]-1)<br>
  (set heating on)<br>
DOELSEIF ([sensor:temperature]>[$SELF:desired])<br>
  (set heating off)<br>
<br>
attr di_threshold cmdState on|off<br>
attr di_threshold readingList desired<br>
attr di_threshold setList desired:17,18,19,20,21,22<br>
attr di_threshold webCmd desired<br>
</code><br>
Die Hysterese ist hier mit einem Grad vorgegeben. Die Vorwahltemperatur wird per Dropdown-Auswahl eingestellt.<br>
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
<a name="DOIF_Zu_beachten"></a><br>
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
<a name="DOIF_Kurzreferenz"></a><br>
<b>Kurzreferenz</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<ul>
&lang;&rang; kennzeichnet optionale Angaben
</ul>
<br>
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
<br>
<u>Readings</u>
<ul>
<dl>
        <dt>Device</dt>
                <dd>Name des ausl&ouml;senden Ger&auml;tes</dd>
<br>
        <dt>block_&lt;block name&gt;</dt>
                <dd>Zeigt die Ausführung eines Perl-Blocks an (Perl).</dd>
<br>
        <dt>cmd</dt>
                <dd>Nr. des letzten ausgef&uuml;hrten Befehls als Dezimalzahl oder 0 nach Initialisierung des DOIF, in der Form &lt;Nr. des Befehlszweiges&gt;&lang;.&lt;Nr. der Sequenz&gt;&rang;</dd>
<br>
        <dt>cmd_event</dt>
                <dd>Angabe des ausl&ouml;senden Ereignisses</dd>
<br>
        <dt>cmd_nr</dt>
                <dd>Nr. des letzten ausgef&uuml;hrten Befehlszweiges</dd>
<br>
        <dt>cmd_seqnr</dt>
                <dd>Nr. der letzten ausgef&uuml;hrten Befehlssequenz</dd>
<br>
        <dt>e_&lt;Device&gt;_&lt;Reading&gt;|&lt;Internal&gt;|Events</dt>
                <dd>Bezeichner und Wert der ausl&ouml;senden Ger&auml;te mit Readings, Internals oder Events</dd>
<br>
        <dt>error</dt>
                <dd>Enthält Fehlermeldungen oder R&uuml;ckgabewerte von Befehlen, siehe <a href="http://www.fhemwiki.de/wiki/DOIF/Tools_und_Fehlersuche#Besonderheit_des_Error-Reading">Besonderheit des Error-Reading</a></dd>
<br>
        <dt>last_cmd</dt>
                <dd>letzter Status</dd>
<br>
        <dt>matched_event_c&lt;lfd. Nr. der Bedingung&gt;_&lt;lfd. Nr. des Events&gt;</dt>
                <dd>Wert, der mit dem Regul&auml;ren Ausdruck &uuml;bereinstimmt</dd>
<br>
        <dt>mode</dt>
                <dd>der Modus, in dem sich DOIF befindet: &lt;enabled|disabled|deactivated&gt;</dd>
<br>
        <dt>state</dt>
                <dd>Status des DOIF nach Befehlsausf&uuml;hrung, Voreinstellung: cmd_&lt;Nr. des Befehlszweiges&gt;&lang;_&lt;Nr. der Befehlssequenz&gt;&rang;</dd>
<br>
        <dt>timer_&lt;lfd. Nr.&gt;_c&lt;Nr. des Befehlszweiges&gt;</dt>
                <dd>verwendete Timer mit Angabe des n&auml;chsten Zeitpunktes</dd>
<br>
        <dt>timer_&lt;timer name&gt;</dt>
                <dd>verwendete, benannte Timer mit Angabe des n&auml;chsten Zeitpunktes (Perl)</dd>
<br>
        <dt>wait_timer</dt>
                <dd>Angabe des aktuellen Wait-Timers</dd>
<br>
        <dt>warning</dt>
                <dd>Perl-Warnung bei der Auswertung einer Bedingung</dd>
<br>

  <a name="DOIF_Benutzerreadings"></a>
        <dt>&lt;A-Z&gt;_&lt;readingname&gt;</dt>
                <dd>Readings, die mit einem Großbuchstaben und nachfolgendem Unterstrich beginnen, sind für User reserviert und werden auch zuk&uuml;nftig nicht vom Modul selbst benutzt.</dd>
</dl>
<br>
</ul>
<a name="DOIF_Operanden"></a>
<u>Operanden in der Bedingung und den Befehlen und im Perl-Modus</u>
<ul>
<dl>
        <dt><a href="#DOIF_Ereignissteuerung">Status</a> <code><b>[</b>&lt;Device&gt;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
                <dd></dd>
<br>
        <dt><a href="#DOIF_Ereignissteuerung">Readings</a> <code><b>[</b>&lt;Device&gt;<b>:</b>&lt;Reading&gt;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
                <dd></dd>
<br>
        <dt><a href="#DOIF_Ereignissteuerung">Internals</a> <code><b>[</b>&lt;Device&gt;<b>:&amp;</b>&lt;Internal&gt;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
                <dd></dd>
<br>
        <dt><a href="#DOIF_Filtern_nach_Zahlen">Filtern allgemein</a> nach Ausdr&uuml;cken mit Ausgabeformatierung: <code><b>[</b>&lt;Device&gt;:&lt;Reading&gt;|&lt;Internal&gt;:"&lt;Filter&gt;"&lang;:&lt;Output&gt;&rang;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
<br>
        <dt><a href="#DOIF_Filtern_nach_Zahlen">Filtern einer Zahl</a> <code><b>[</b>&lt;Device&gt;<b>:</b>&lt;Reading&gt;<b>:d</b>&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
<br>
        <dt><a href="#DOIF_Zeitspanne_eines_Readings_seit_der_letzten_Aenderung">Zeitspanne eines Readings seit der letzten &Auml;nderung</a> <code><b>[</b>&lt;Device&gt;<b>:</b>&lt;Reading&gt;<b>:sec</b>&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
<br>
        <dt>$DEVICE</dt>
                <dd>f&uuml;r den Ger&auml;tenamen</dd>
<br>
        <dt>$EVENT</dt>
                <dd>f&uuml;r das zugeh&ouml;rige Ereignis</dd>
<br>
        <dt>$EVENTS</dt>
                <dd>f&uuml;r alle zugeh&ouml;rigen Ereignisse eines Triggers</dd>
<br>
        <dt>$SELF</dt>
                <dd>f&uuml;r den Ger&auml;tenamen des DOIF</dd>
<br>
        <dt>&lt;Perl-Funktionen&gt;</dt>
                <dd>vorhandene und selbsterstellte Perl-Funktionen</dd>
</dl>
<br>
</ul>

<u>Operanden in der Bedingung und im Perl-Modus</u>
<ul>
<dl>
        <dt><a href="#DOIF_Ereignissteuerung_ueber_Auswertung_von_Events">Events</a> <code><b>[</b>&lt;Device&gt;<b>:"</b>&lt;Regex-Events&gt;"<b>]</b></code> oder <code><b>["</b>&lt;Regex-Devices&gt;<b>:</b>&lt;Regex-Events&gt;<b>"]</b></code> oder <code><b>["</b>&lt;Regex-Devices&gt;<b>"</b>&lang;<b>:"</b>&lt;Regex-Filter&gt;<b>"</b>&rang;&lang;<b>:</b>&lt;Output&gt;&rang;<b>,</b>&lt;Default&gt;<b>]</b></code></dt>
                <dd>f&uuml;r <code>&lt;Regex&gt;</code> gilt: <code><b>^</b>&lt;ist eindeutig&gt;<b>$</b></code>, <code><b>^</b>&lt;beginnt mit&gt;</code>, <code>&lt;endet mit&gt;<b>$</b></code>, <code><b>""</b></code> entspricht <code><b>".*"</b></code>, Regex-Filter ist mit <code><b>[^\:]*: (.*)</b></code> vorbelegt siehe auch <a target=blank href="https://wiki.selfhtml.org/wiki/Perl/Regul%C3%A4re_Ausdr%C3%BCcke">Regul&auml;re Ausdr&uuml;cke</a> und Events des Ger&auml;tes <a target=blank href="#global">global</a>
                </dd>
<br>
        <dt><a href="#DOIF_Zeitsteuerung">Zeitpunkte</a> <code><b>[</b>&lt;time&gt;<b>]</b> </code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl] </b></code> in Sekunden nach Mitternacht</dd>
<br>
        <dt><a href="#DOIF_Zeitsteuerung_mit_Zeitintervallen">Zeitintervalle</a> <code><b>[</b>&lt;begin&gt;<b>-</b>&lt;end&gt;<b>]</b></code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl]</b></code> in Sekunden nach Mitternacht</dd>
<br>
        <dt><a href="#DOIF_Indirekten_Zeitangaben">indirekte Zeitangaben</a> <code><b>[[</b>&lt;indirekte Zeit&gt;<b>]]</b></code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl]</b></code> in Sekunden nach Mitternacht, <code>&lt;indirekte Zeit&gt;</code> ist ein Status, Reading oder Internal</dd>
<br>
        <dt><a href="#DOIF_Relative_Zeitangaben">relative Zeitangaben</a> <code><b>[+</b>&lt;time&gt;<b>]</b></code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl]</b></code> in Sekunden</dd>
<br>
        <dt><a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet">ausgerichtete Zeitraster</a> <code><b>[:MM]</b></code></dt>
                <dd>in Minuten zwischen 00 und 59</dd>
<br>
        <dt><a href="#DOIF_Relative_Zeitangaben_nach_Zeitraster_ausgerichtet">rel. Zeitraster ausgerichtet</a> <code><b>[+:MM]</b></code></dt>
                <dd>in Minuten zwischen 1 und 59</dd>
<br>
        <dt><a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet_alle_X_Stunden">rel. Zeitraster ausgerichtet alle X Stunden</a> <code><b>[+[h]:MM]</b></code></dt>
                <dd><b>MM</b> in Minuten zwischen 1 und 59, <b>h</b> in Stunden zwischen 2 und 23</dd>
<br>
        <dt><a href="#DOIF_Wochentagsteuerung">Wochentagsteuerung</a> <code><b>[</b>&lt;time&gt;<b>|0123456789]</b></code>, <code><b>[</b>&lt;begin&gt;<b>-</b>&lt;end&gt;<b>]</b><b>|0123456789]</b></code></dt>
                <dd>Pipe, gefolgt von ein o. mehreren Ziffern. Bedeutung: 0 bis 6 f&uuml;r So. bis Sa., 7 f&uuml;r $we, Wochenende oder Feiertag, 8 f&uuml;r !$we, Werktags, 9 f&uuml;r $twe, Wochenende oder Feiertag morgen.</dd>
<br>
        <dt><a href="#DOIF_Zeitsteuerung_mit_Zeitberechnung">berechnete Zeitangaben</a> <code><b>[(</b>&lt;Berechnung, gibt Zeit in Sekunden zur&uuml;ck, im Sinne von <a target=blank href="http://perldoc.perl.org/functions/time.html">time</a>&gt;<b>)]</b></code></dt>
                <dd>Berechnungen sind mit runden Klammern einzuschliessen. Perlfunktionen, die HH:MM zur&uuml;ckgeben sind mit geschweiften Klammern einzuschliessen.</dd>
<br>
        <dt><a href="#DOIF_Intervall-Timer">Intervall-Timer</a> <code><b>[</b>&lt;begin&gt;<b>-</b>&lt;end&gt;<b>,</b>&lt;relativ timer&gt;<b>]</b></code></dt>
                <dd>L&ouml;st zu den aus &lt;relativ timer&gt; berechneten Zeitpunkten im angegebenen Zeitintervall &lt;begin&gt;-&lt;end&gt; aus.</dd>
<br>
        <dt><a href="#DOIF_Zeitintervalle_Readings_und_Status_ohne_Trigger">Trigger verhindern</a> <code><b>[?</b>&lt;devicename&gt;<b>]</b></code>, <code><b>[?</b>&lt;devicename&gt;<b>:</b>&lt;readingname&gt;<b>]</b></code>, <code><b>[?</b>&lt;devicename&gt;<b>:&amp;</b>&lt;internalname&gt;<b>]</b></code>, <code><b>[?</b>&lt;time specification&gt;<b>]</b></code></dt>
                <dd>Werden Status, Readings, Internals und Zeitangaben in der Bedingung mit einem Fragezeichen eingeleitet, triggern sie nicht.</dd>
<br>
        <dt>$device, $event, $events</dt>
                <dd>Perl-Variablen mit der Bedeutung der Schl&uuml;sselworte $DEVICE, $EVENT, $EVENTS</dd>
<br>
        <dt>$cmd</dt>
                <dd>Perl-Variablen mit der Bedeutung [$SELF:cmd]</dd>
<br>
        <dt>&lt;Perl-Zeitvariablen&gt;</dt>
                <dd>Variablen f&uuml;r Zeit- und Datumsangaben, $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst, $week, $hms, $hm, $md, $ymd, $we, $twe</dd>
</dl>
<br>
</ul>
<u>set-Befehle</u>
<ul>
<dl>
        <dt><a href="#DOIF_setcheckall">disable</a> <code><b> set </b>&lt;name&gt;<b> checkall</b></code></dt>
                <dd>Überprüfung aller DOIF-Bedingungen mit Ausführung eines wahren DOIF-Zweiges</dd>
<br>
        <dt><a href="#DOIF_setdisable">disable</a> <code><b> set </b>&lt;name&gt;<b> disable</b></code></dt>
                <dd>blockiert die Befehlsausf&uuml;hrung</dd>
<br>
        <dt><a href="#DOIF_Initialisieren_des_Moduls">initialize</a> <code><b> set </b>&lt;name&gt;<b> initialize</b></code></dt>
                <dd>initialisiert das DOIF und aktiviert die Befehlsausf&uuml;hrung</dd>
<br>
        <dt><a href="#DOIF_setenable">enable</a> <code><b> set </b>&lt;name&gt;<b> enable</b></code></dt>
                <dd>aktiviert die Befehlsausf&uuml;hrung, im Gegensatz zur obigen Initialisierung bleibt der letzte Zustand des Moduls erhalten</dd>
<br>
        <dt><a href="#DOIF_setcmd">cmd_&lt;nr&gt</a> <code><b> set </b>&lt;name&gt;<b> cmd_&lt;nr&gt;</b></code></dt>
                <dd>führt ohne Auswertung der Bedingung den Befehlszweig mit der Nummer &lt;nr&gt; aus</dd>
</dl>
<br>
</ul>
<a name="DOIF_getBefehle"></a>
<u>get-Befehle</u>
<ul>
<dl>
        <dt><a name="HTML-Code von uiTable">html</a></dt>
        <dd>liefert HTML-Code einer definierten uiTable zurück.</dd>
</dl>
<br>
</ul>

<a name="DOIF_Attribute_kurz"></a>
<u>Attribute</u>
<ul>
<dl>
        <dt><a href="#DOIF_wait">Verz&ouml;gerungen</a> <code><b>attr</b> &lt;name&gt; <b>wait </b>&lt;timer_1_1&gt;<b>,</b>&lt;timer_1_2&gt;<b>,...:</b>&lt;timer_2_1&gt;<b>,</b>&lt;timer_2_2&gt;<b>,...:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, ein Doppelpunkt trennt die Timer der Bedingungsweige, ein Komma die Timer der Befehlssequenzen eines Bedingungszweiges.</dd>
<br>
        <dt><a href="#DOIF_timerWithWait">Verz&ouml;gerung von Timern</a> <code><b>attr</b> &lt;name&gt; <b>timerWithWait</b></code></dt>
                <dd>erweitert <code>wait</code> auf Zeitangaben</dd>
<br>
<li><a name="do"></a>
        <dt><code><b>attr</b> &lt;name&gt; <b>do </b>&lt;<b>always</b>|<b>resetwait</b>&gt;</code></dt>
                <dd><code>always</code> wiederholt den Ausf&uuml;hrungsteil, wenn die selbe Bedingung wiederholt wahr wird.<br>
                    <code>resetwait</code> setzt den Waittimer zurück, wenn die selbe Bedingung wiederholt wahr wird.<br>
                </dd>
</li>
<br>
        <dt><a href="#DOIF_repeatcmd">Befehle wiederholen</a> <code><b>attr</b> &lt;name&gt; <b>repeatcmd </b>&lt;timer Bedingungszweig 1&gt;<b>:</b>&lt;timer Bedingungszweig 2&gt;<b>:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, nach der Befehle wiederholt werden.</dd>
<br>
        <dt><a href="#DOIF_cmdpause">Pause f&uuml;r Wiederholung</a> <code><b>attr</b> &lt;name&gt; <b>cmdpause </b>&lt;Pause cmd_1&gt;<b>:</b>&lt;Pause cmd_2&gt;<b>:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, blockiert die Befehlsausf&uuml;hrung w&auml;hrend der Pause.</dd>
<br>
        <dt><a href="#DOIF_repeatsame">Begrenzung von Wiederholungen</a> <code><b>attr</b> &lt;name&gt; <b>repeatsame </b>&lt;maximale Anzahl von cmd_1&gt;<b>:</b>&lt;maximale Anzahl von cmd_2&gt;<b>:...</b></code></dt>
                <dd>Anzahl als direkte Angabe oder Berechnung, begrenzt die maximale Anzahl unmittelbar folgender Befehlsausf&uuml;hrungen.</dd>
<br>
        <dt><a href="#DOIF_waitsame">Warten auf Wiederholung</a> <code><b>attr</b> &lt;name&gt; <b>waitsame </b>&lt;Wartezeit cmd_1&gt;<b>:</b>&lt;Wartezeit cmd_2&gt;<b>:...</b></code></dt>
                <dd>Wartezeit in Sekunden als direkte Angabe oder Berechnung, f&uuml;r ein unmittelbar wiederholtes Zutreffen einer Bedingung.</dd>
<br>
        <dt><a href="#DOIF_waitdel">L&ouml;schen des Waittimers</a> <code><b>attr</b> &lt;name&gt; <b>waitdel </b>&lt;timer_1_1&gt;<b>,</b>&lt;timer_1_2&gt;<b>,...:</b>&lt;timer_2_1&gt;<b>,</b>&lt;timer_2_2&gt;<b>,...:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, ein laufender Timer wird gel&ouml;scht und die Befehle nicht ausgef&uuml;hrt, falls eine Bedingung vor Ablauf des Timers wiederholt wahr wird.</dd>
<br>
        <dt><a href="#DOIF_checkReadingEvent">Readingauswertung bei jedem Event des Devices</a> <code><b>attr</b> &lt;name&gt; <b>checkReadingEvent </b>&lt;<b>0</b>|<b>1</b>&gt;</code></dt>
                <dd>0 deaktiviert, 1 keine Funktion mehr, entspricht internen der Voreinstellung des Moduls.</dd>
<br>
        <dt><a href="#DOIF_selftrigger">Selbsttriggerung</a> <code><b>attr</b> &lt;name&gt; <b>selftrigger </b>&lt;<b>wait</b>|<b>all</b>&gt;</code></dt>
                <dd>lässt die Triggerung des Gerätes durch sich selbst zu. <code>wait</code> zugelassen für verzögerte Befehle, <code>all</code> zugelassen auch für nicht durch wait verzögerte Befehle; es ist nur eine Rekusion möglich</dd>
<br>
        <dt><a href="#DOIF_timerevent">Event beim Setzen eines Timers</a> <code><b>attr</b> &lt;name&gt; <b>timerevent </b>&lt;<b>0</b>|<b>ungleich Null</b>&gt;</code></dt>
                <dd>erzeugt beim Setzen eines Timers ein Event. ungleich Null aktiviert, 0 deaktiviert</dd>
<br>
        <dt><a href="#DOIF_cmdState">Ger&auml;testatus ersetzen</a> <code><b>attr</b> &lt;name&gt; <b>cmdState </b>&lt;Ersatz cmd_1_1&gt;<b>,</b>...<b>,</b>&lt;Ersatz cmd_1&gt;<b>|</b>&lt;Ersatz cmd_2_1&gt;<b>,</b>...<b>,</b>&lt;Ersatz cmd_2&gt;<b>|...</b></code></dt>
                <dd>ersetzt die Standartwerte des Ger&auml;testatus als direkte Angabe oder Berechnung, die Ersatzstatus von Befehlssequenzen werden durch Kommata, die von Befehlszweigen durch Pipe Zeichen getrennt.</dd>
<br>
        <dt><a href="#DOIF_startup">Befehle bei FHEM-Start ausf&uuml;hren </a> <code><b>attr</b> &lt;name&gt; <b>startup </b>&lt;FHEM-Befehle&gt;|<b>{</b>&lt;Perl-Befehle mit DOIF-Syntax&gt;<b>}</b></code></dt>
                <dd></dd>
<br>
        <dt><a href="#DOIF_state">dynamischer Status </a> <code><b>attr</b> &lt;name&gt; <b>state </b>&lt;content&gt;</code></dt>
                <dd>&lt;content&gt; ist das Ergebnis eines Perl-Ausdrucks, DOIF-Syntax ([&lt;device&gt;:&lt;reading&gt;], usw.) triggert bei Event die Berechnung.</dd>
<br>
        <dt><a href="#DOIF_DOIF_Readings">Erzeugen berechneter Readings </a> <code><b>attr</b> &lt;name&gt; <b>DOIF_Readings </b>&lt;readingname_1&gt;<b>:</b>&lt;content_1&gt;<b>,</b>&lt;readingname_2&gt;<b>:</b>&lt;content_2&gt; ...</code></dt>
                <dd>&lt;content_n&gt; ist das Ergebnis von Perl-Ausdrücken, DOIF-Syntax ([&lt;device&gt;:&lt;reading&gt;], usw.) triggert bei Event die Berechnung.</dd>
<br>
        <dt><a href="#DOIF_notexist">Ersatzwert für nicht existierende Readings oder Status</a> <code><b>attr</b> &lt;name&gt; <b>notexist </b>"&lt;Ersatzwert&gt;"</code></dt>
                <dd></dd>
<br>
        <dt><a href="#DOIF_initialize">Status Initialisierung nach Neustart</a> <code><b>attr</b> &lt;name&gt; <b>initialize </b>&lt;Status nach Neustart&gt;</code></dt>
                <dd></dd>
<br>
        <dt><a href="#DOIF_disable">Ger&auml;t vollst&auml;ndig deaktivieren</a> <code><b>attr</b> &lt;name&gt; <b>disable </b>&lt;<b>0</b>|<b>1</b>&gt;</code></dt>
                <dd>1 deaktiviert das Modul vollst&auml;ndig, 0 aktiviert es.</dd>
<br>
        <dt><a href="#DOIF_checkall">Alle Bedingungen pr&uuml;fen</a> <code><b>attr</b> &lt;name&gt; <b>checkall </b>&lt;<b>event</b>|<b>timer</b>|<b>all</b>&gt;</code></dt>
                <dd><code>event</code> Alle Bedingungen werden geprüft, wenn ein Event-Trigger (Ereignisauslöser) auslöst.<br>
                    <code>timer</code> Alle Bedingungen werden geprüft, wenn ein Timer-Trigger (Zeitauslöser) auslöst.<br>
                    <code>all&nbsp;&nbsp;</code> Alle Bedingungen werden gepr&uuml;ft.<br>
                    Die Befehle nach der ersten wahren Bedingung werden ausgef&uuml;hrt.
                </dd>
<br>
        <dt><a href="#DOIF_addStateEvent">Eindeutige Statuserkennung</a> <code><b>attr</b> &lt;name&gt; <b>addStateEvent </b>&lt;<b>0</b>|<b>ungleich Null</b>&gt;</code></dt>
                <dd>fügt einem Ger&auml;testatus-Event "state:" hinzu. ungleich Null aktiviert, 0 deaktiviert, siehe auch <a href="#addStateEvent">addStateEvent</a></dd>
<br>
<li><a name="readingList"></a>
        <dt><code><b>attr</b> &lt;name&gt; <b>readingList </b>&lt;Reading1&gt;&nbsp;&lt;Reading2&gt; ...</code></dt>
                <dd>fügt zum set-Befehl direkt setzbare, durch Leerzeichen getrennte Readings hinzu.</dd>
<br>
        <dt><code><b>attr</b> &lt;name&gt; <b>setList </b>&lt;Reading1&gt;<b>:</b>&lang;&lt;Modifier1&gt;<b>,</b>&rang;&lt;Value1&gt;<b>,</b>&lt;Value2&gt;<b>,</b>&lt;...&gt;<b> </b>&lt;Reading2&gt;<b>:</b>&lang;&lt;Modifier2&gt;<b>,</b>&rang;&lt;Value1&gt;<b>,</b>&lt;Value2&gt;<b>,</b>&lt;...&gt; ...</code></dt>
                <dd>fügt einem Reading einen optionalen Widgetmodifier und eine Werteliste (, getrennt) hinzu. <a href="#setList">setList</a>, <a href="#widgetOverride">widgetOverride</a>, und <a href="#webCmd">webCmd</a></dd>
</li><br>
  <dt><a href="#DOIF_uiTable">User Interface f&uuml;r DOIF</a> <code><b>attr</b> &lt;name&gt; <b>uiTable</b> &lang;<b>{</b>&lt;perl code (format specification, template specification, function definition, control variable, ...)&gt;<b>}\n</b>&rang;&lt;template file import, method definition, table definition&gt;</code></dt>
    <dd><u>format specification:</u></dd>
    <dd><code>$TABLE = "&lt;CSS-Attribute&gt;"</code> ergänzt das table-Elemente um CSS-Attribute.</dd>
    <dd><code>$TD{&lt;rows&gt;}{&lt;columns&gt;} = "&lt;HTML Attribute&gt;"</code> ergänzt td-Elemente um HTML-Attribute.</dd>
    <dd><code>$TR{&lt;rows&gt;} = "&lt;HTML Attribute&gt;"</code> ergänzt tr-Elemente um HTML-Attribute.</dd>
    <dd><code>$TC{&lt;columns&gt;} = "&lt;HTML Attribute&gt;"</code> ergänzt zu columns gehörende td-Elemente um HTML-Attribute.</dd>
    <dd><u>template specification:</u></dd>
    <dd><code>$TPL{&lt;name&gt;} = "&lt;Zeichenkette&gt;"</code> speichert ein Template.</dd>
    <dd><u>function definition:</u></dd>
    <dd><code>sub FUNC_&lt;name&gt; {&lt;function BLOCK&gt;}</code> definiert eine Funktion.</dd>
    <dd><u>control variables:</u></dd>
    <dd><code>$ATTRIBUTESFIRST = 1;</code> organisiert die Detailansicht um.</dd>
    <dd><code>$SHOWNOSTATE = 1;</code> blendet den Status in der Gerätezeile aus.</dd>
    <dd><code>$SHOWNODEVICELINE = "&lt;regex room&gt;";</code> blendet die Gerätezeile aus, wenn &lt;regex room&gt; zum Raumnamen passt, gilt nicht für den Raum <i>Everything</i>.</dd>
    <dd><code>$SHOWNODEVICELINK = 1;</code> schaltet das Ersetzen des Gerätenamen durch einen Link auf die Detailseite aus.</dd>
    <br>
    <dd><u>template file import:</u></dd>
    <dd><code>IMPORT &lt;path with filename&gt;</code> importiert eine Templatedatei.</dd>
    <dd><u>method definition:</u></dd>
    <dd><code>DEF TPL_&lt;name&gt;(&lt;definition with place holder $1,$2 usw.&gt;)</code> erzeugt ein Methodentemplate zur wiederholten Nutzung in der Tabellendefinition.</dd>
    <dd><u>table definition:</u></dd>
    <dd>Schreiben die nachstehenden Elemente HTML-Code in die Tabellenzelle, so wird er interpretiert.</dd>
    <dd><code>&crarr;</code> oder <code>&crarr;&crarr;</code> trennt Tabellenzeilen.</dd>
    <dd><code>|</code> oder <code>|&crarr;</code> trennt Tabellenzellen.</dd>
    <dd><code>&gt;&crarr;</code> oder <code>,&crarr;</code> sind zur Textstrukturierung zugelassen.</dd>
    <dd><code>WID([&lt;device&gt;:&lt;reading&gt;],"&lt;widget modifier&gt;"&lang;,"&lt;command&gt;"&rang;)</code> bindet ein Widget an &lt;device&gt;:&lt;reading&gt;, &lt;command&gt; steht für <i>set</i> oder <i>setreading</i>, siehe <a href="#widgetOverride"> widgetOverride </a> und <a href="https://wiki.fhem.de/wiki/FHEMWEB/Widgets"> FHEMWEB-Widgets </a></dd>
    <dd><code>STY(&lt;content&gt;,&lt;CSS style attributes&gt;)</code> schreibt den Inhalt von &lt;content&gt; in die Zelle und formatiert ihn mit &lt;CSS style attributes&gt;.</dd>
    <dd><code>&lt;content&gt;</code> schreibt den Inhalt von &lt;content&gt; in die Zelle.</dd>
    <dd>&lt;content&gt; und &lt;CSS style attributes&gt; sind das Ergebnis von Perl-Ausdrücken. Enthalten sie DOIF-Syntax ([&lt;device&gt;:&lt;reading&gt;], usw.), werden sie dynamisch erzeugt.</dd>
    <dd><code>PUP(&lt;DOIF-name to show interface table&gt;, &lt;iconname[@color number]&gt;)</code></dd>
    <dd>gibt ein Link zum Öffnen eines Popup-Fensters zurück.</dd>
    <dd>&lt;DOIF-name to show interface table&gt; Name des DOIF-Gerätes dessen Benutzerschnittstelle angezeigt werden soll.</dd>
    <dd>&lt;iconname[@color number]|string&gt; gibt ein Icon an, wenn das Icon nicht verfügbar ist, wird &lt;string&gt; angezeigt.</dd>
<br>
        <dt><a href="#readingFnAttributes">readingFnAttributes</a></dt>
                <dd></dd>
</dl>
<br>
</ul>
<a name="DOIF_PerlFunktionen_kurz"></a>
<u>Perl-Funktionen</u>
<ul>
  <dl>
    <dt><code>DOIF_hsv(&lt;current value&gt;, &lt;lower value&gt;, &lt;upper value&gt;, &lt;lower HUE value&gt;, &lt;upper HUE value&gt;, &lt;saturation&gt;, &lt;lightness&gt;)</code></dt>
    <dd>gibt eine im HSV-Raum interpolierte HTML Farbnummer zurück, mit Prefix <b>#</b></dd>
    <dd>&lt;current value&gt; aktueller Wert, für den die Farbnummer erzeugt wird.</dd>
    <dd>&lt;lower value&gt; unterer Wert, des Bereiches auf den die Farbnummer skaliert wird.</dd>
    <dd>&lt;upper value&gt; oberer Wert, des Bereiches auf den die Farbnummer skaliert wird.</dd>
    <dd>&lt;lower HUE value&gt; unterer HUE-Wert, der mit dem unteren Wert korrespondiert (0-360).</dd>
    <dd>&lt;upper HUE value&gt; oberer HUE-Wert, der mit dem oberen Wert korrespondiert (0-360).</dd>
    <dd>&lt;saturation&gt; Farbsättigung (0-100).</dd>
    <dd>&lt;lightness&gt; Hellwert (0-100).</dd>
<br>
    <dt><code>DOIF_rgb(&lt;start color number&gt;, &lt;end color number&gt;, &lt;lower value&gt;, &lt;upper value&gt;, &lt;current value&gt;)</code></dt>
    <dd>gibt eine linear interpolierte RGB Farbnummer zurück, abhängig vom Prefix der Start- o. Endfarbnummer mit oder ohne Prefix <b>#</b>.</dd>
    <dd>&lt;start color number&gt; Startfarbnummer des Farbbereiches, mit oder ohne Prefix <b>#</b>.</dd>
    <dd>&lt;end color number&gt; Endfarbnummer des Farbbereiches, mit oder ohne Prefix <b>#</b>.</dd>
    <dd>&lt;lower value&gt; unterer Wert, des Bereiches auf den die Farbnummer skaliert wird.</dd>
    <dd>&lt;upper value&gt; oberer Wert, des Bereiches auf den die Farbnummer skaliert wird.</dd>
    <dd>&lt;current value&gt; aktueller Wert, für den die Farbnummer erzeugt wird.</dd>
<br>
    <dt><code>FW_makeImage(&lt;iconname[@color number]&gt;)</code></dt>
    <dd>gibt HTML-Code zurück, der ein FHEM icon einbindet.</dd>
    <dd>&lt;color number&gt; optionale Farbnummer in Großschreibung, mit oder ohne Prefix <b>#</b>.</dd>
    <dd>weitere Infos im Quelltext von 01_FHEMWEB.pm.</dd>
  </dl>
</ul>
<!-- Ende der Kurzreferenz -->
<br>
<a name="DOIF_Perl_Modus"></a>
<b>Perl Modus</b><br>
<br>
<u><a href="https://wiki.fhem.de/wiki/DOIF/Perl-Modus">Dokumentation zum DOIF-Perl-Modus</a></u><br>
</ul>
=end html_DE
=cut
