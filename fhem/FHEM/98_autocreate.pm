##############################################
package main;

use strict;
use warnings;

# Problems:
# - Not all CUL_EM devices return a power
# - Not all CUL_WS devices return a temperature
# - No plot files for BS/CUL_FHTTK/USF1000/X10/WS300
# - check "UNDEFINED" parameters for BS/USF1000/X10

my %flogpar = (
  "CUL_EM:.*"
      => { GPLOT => "cul_em:Power,", FILTER => "%NAME:CNT:.*" },
  "CUL_WS:.*"
      => { GPLOT => "hms:Temp/Hum,",  FILTER => "%NAME" },
  "CUL_FHTTK:.*"
      => { GPLOT => "fht80tf:Window,", FILTER => "%NAME" },
  "FHT:.*"
      => { GPLOT => "fht:Temp/Act,", FILTER => "%NAME" },
  "HMS:HMS100TFK_.*"
      => { GPLOT => "fht80tf:Contact,", FILTER => "%NAME" },
  "HMS:HMS100T._.*"
      => { GPLOT => "hms:Temp/Hum,", FILTER => "%NAME:T:.*" },
  "KS300:.*"
      => { GPLOT => "ks300:Temp/Rain,ks300_2:Wind/Hum,",
           FILTER => "%NAME:T:.*" },

  # Oregon sensors: 
  # * temperature
  "OREGON:(THR128|THWR288A|THN132N).*"
      => { GPLOT => "oregon_hms_t:Temp,",  FILTER => "%NAME" },
  # * temperature, humidity
  "OREGON:(THGR228N|THGR810|THGR918|THGR328N|RTGR328N|WTGR800_T).*"
      => { GPLOT => "oregon_hms:Temp/Hum,",  FILTER => "%NAME" },
  # * temperature, humidity, pressure
  "OREGON:(BTHR918N|BTHR918|BTHR918N).*"
      => { GPLOT => "oregon_temp_press:Temp/Press,oregon_hms:Temp/Hum,",
           FILTER => "%NAME" },
  # * anenometer
  "OREGON:(WGR800|WGR918|WTGR800_A).*"
      => { GPLOT => "oregon_wind:WindDir/WindSpeed,",  FILTER => "%NAME" },
  # * Oregon sensors: Rain gauge
  "OREGON:(PCR800|RGR918).*"
      => { GPLOT => "oregon_rain:RainRate",  FILTER => "%NAME" },

  # HomeMatic
  "CUL_HM:THSensor"
      => { GPLOT => "hms:Temp/Hum,",
           FILTER => "%NAME:T:.*" },
  "CUL_HM:KS550"
      => { GPLOT => "ks300:Temp/Rain,ks300_2:Wind/Hum,",
           FILTER => "%NAME:T:.*" },
);

#####################################
sub
autocreate_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn} = "autocreate_Define";
  $hash->{NotifyFn} = "autocreate_Notify";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6 " . 
                     "autosave filelog device_room weblink weblink_room " .
                     "disable";
  my %ahash = ( Fn=>"CommandCreateLog",
                Hlp=>"<device>,create log/weblink for <device>" );
  $cmds{createlog} = \%ahash;
}

#####################################
sub
autocreate_Define($$)
{
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  $hash->{STATE} = "active";
  $attr{global}{autoload_undefined_devices} = 1; # Make sure we work correctly
  return undef;
}

sub
replace_wildcards($$)
{
  my ($hash, $str) = @_;
  return "" if(!$str);
  my $t = $hash->{TYPE}; $str =~ s/%TYPE/$t/g;
  my $n = $hash->{NAME}; $str =~ s/%NAME/$n/g;
  return $str;
}

#####################################
sub
autocreate_Notify($$)
{
  my ($ntfy, $dev) = @_;

  my $me = $ntfy->{NAME};
  my ($ll1, $ll2) = (GetLogLevel($me,1), GetLogLevel($me,2));
  my $max = int(@{$dev->{CHANGED}});
  my $ret = "";
  my $nrcreated;

  for (my $i = 0; $i < $max; $i++) {

    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));

    ################
    if($s =~ m/^UNDEFINED ([^ ]*) ([^ ]*) (.*)$/) {
      my ($name, $type, $arg) = ($1, $2, $3);
      next if(AttrVal($me, "disable", undef));

      my $lctype = lc($type);
      my ($cmd, $ret);
      my $hash = $defs{$name};  # Called from createlog

      ####################
      if(!$hash) {
        $cmd = "$name $type $arg";
        Log $ll2, "autocreate: define $cmd";
        $ret = CommandDefine(undef, $cmd);
        if($ret) {
          Log $ll1, "ERROR: $ret";
          last;
        }
      }
      $hash = $defs{$name};
      $nrcreated++;
      my $room = replace_wildcards($hash, $attr{$me}{device_room});
      $attr{$name}{room} = $room if($room);

      ####################
      my $fl = replace_wildcards($hash, $attr{$me}{filelog});
      next if(!$fl);
      my $flname = "FileLog_$name";
      delete($defs{$flname});   # If we are re-creating it with createlog.
      my ($gplot, $filter) = ("", $name);
      foreach my $k (keys %flogpar) {
        my $model = AttrVal($name, "model", "");
        next if("$type:$name"  !~ m/^$k$/ && 
                "$type:$model" !~ m/^$k$/);
        $gplot = $flogpar{$k}{GPLOT};
        $filter = replace_wildcards($hash, $flogpar{$k}{FILTER});
      }
      $cmd = "$flname FileLog $fl $filter";
      Log $ll2, "autocreate: define $cmd";
      $ret = CommandDefine(undef, $cmd);
      if($ret) {
        Log $ll1, "ERROR: $ret";
        last;
      }
      $attr{$flname}{room} = $room if($room);
      $attr{$flname}{logtype} = "${gplot}text";


      ####################
      next if(!$attr{$me}{weblink} || !$gplot);
      $room = replace_wildcards($hash, $attr{$me}{weblink_room});
      my $wnr = 1;
      foreach my $wdef (split(/,/, $gplot)) {
        next if(!$wdef);
        my ($gplotfile, $stuff) = split(/:/, $wdef);
        next if(!$gplotfile);
        my $wlname = "weblink_$name";
        $wlname .= "_$wnr" if($wnr > 1);
        $wnr++;
        delete($defs{$wlname});   # If we are re-creating it with createlog.
        $cmd = "$wlname weblink fileplot $flname:$gplotfile:CURRENT";
        Log $ll2, "autocreate: define $cmd";
        $ret = CommandDefine(undef, $cmd);
        if($ret) {
          Log $ll1, "ERROR: $ret";
          last;
        }
        $attr{$wlname}{room} = $room if($room);
        $attr{$wlname}{label} = '"' . $name .
                ' Min $data{min1}, Max $data{max1}, Last $data{currval1}"';
      }
    }


    ################
    if($s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
      my ($old, $new) = ($1, $2);

      if($defs{"FileLog_$old"}) {
        CommandRename(undef, "FileLog_$old FileLog_$new");
        my $hash = $defs{"FileLog_$new"};
        my $oldlogfile = $hash->{currentlogfile};

        $hash->{REGEXP} =~ s/$old/$new/g;
        $hash->{logfile} =~ s/$old/$new/g;
        $hash->{currentlogfile} =~ s/$old/$new/g;
        $hash->{DEF} =~ s/$old/$new/g;

        rename($oldlogfile, $hash->{currentlogfile});
        Log $ll2, "autocreate: renamed FileLog_$old to FileLog_$new";
        $nrcreated++;
      }

      if($defs{"weblink_$old"}) {
        CommandRename(undef, "weblink_$old weblink_$new");
        my $hash = $defs{"weblink_$new"};
        $hash->{LINK} =~ s/$old/$new/g;
        $hash->{DEF} =~ s/$old/$new/g;
        $attr{"weblink_$new"}{label} =~ s/$old/$new/g;
        Log $ll2, "autocreate: renamed weblink_$old to weblink_$new";
        $nrcreated++;
      }
    }

  }
  CommandSave(undef, undef) if(!$ret && $nrcreated && $attr{$me}{autosave});
  return $ret;
}

sub
CommandCreateLog($$)
{
  my ($cl, $n) = @_;
  my $ac;

  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "autocreate");
    $ac = $d;
    last;
  }
  return "Please define an autocreate device with attributes first " .
        "(it may be disabled)" if(!$ac);

  return "No device named $n found" if(!$defs{$n});

  my $acd = $defs{$ac};
  my $disabled = AttrVal($ac, "disable", undef);
  delete $attr{$ac}{disable} if($disabled);

  $acd->{CHANGED}[0] = "UNDEFINED $n $defs{$n}{TYPE} none";
  autocreate_Notify($acd, $acd);
  delete $acd->{CHANGED};

  $attr{$ac}{disable} = 1 if($disabled);
}

1;
