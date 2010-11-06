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
  "CUL_EM:.*"      => { GPLOT => "cul_em:Power,", FILTER => "%NAME:CNT:.*" },
  "CUL_WS:.*"      => { GPLOT => "hms:Temp/Hum,",  FILTER => "%NAME" },
  "CUL_FHTTK:.*"   => { GPLOT => "fht80tf:Window,", FILTER => "%NAME" },
  "FHT:.*"         => { GPLOT => "fht:Temp/Act,", FILTER => "%NAME" },
  "HMS:HMS100TFK_.*" => { GPLOT => "fht80tf:Contact,", FILTER => "%NAME" },
  "HMS:HMS100T._.*" => { GPLOT => "hms:Temp/Hum,", FILTER => "%NAME:T:.*" },
  "KS300:.*"       => { GPLOT => "ks300:Temp/Rain,ks300_2:Wind/Hum,", 
                                                 FILTER => "%NAME:T:.*" },
  # Oregon sensors: 
  # * temperature
  "OREGON:(THR128|THWR288A|THN132N).*"  => { GPLOT => "oregon_hms_t:Temp,",  FILTER => "%NAME" },
  # * temperature, humidity
  "OREGON:(THGR228N|THGR810|THGR918|THGR328N|RTGR328N|WTGR800_T).*"  => { GPLOT => "oregon_hms:Temp/Hum,",  FILTER => "%NAME" },
  # * temperature, humidity, pressure
  "OREGON:(BTHR918N|BTHR918|BTHR918N).*"  => { GPLOT => "oregon_temp_press:Temp/Press,oregon_hms:Temp/Hum,",  FILTER => "%NAME" },
  # * anenometer
  "OREGON:(WGR800|WGR918|WTGR800_A).*"  => { GPLOT => "oregon_wind:WindDir/WindSpeed,",  FILTER => "%NAME" },
  # * Oregon sensors: Rain gauge
  "OREGON:(PCR800|RGR918).*"  => { GPLOT => "oregon_rain:RainRate",  FILTER => "%NAME" },
);

#####################################
sub
autocreate_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn} = "autocreate_Define";
  $hash->{NotifyFn} = "autocreate_Notify";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6 " . 
                     "autosave filelog device_room weblink weblink_room";
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
  my $max = int(@{$dev->{CHANGED}});
  my $ret = "";
  my $nrcreated;

  for (my $i = 0; $i < $max; $i++) {

    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));

    ################
    if($s =~ m/^UNDEFINED ([^ ]*) ([^ ]*) (.*)$/) {
      my ($name, $type, $arg) = ($1, $2, $3);
      my $lctype = lc($type);

      ####################
      my $cmd = "$name $type $arg";
      Log GetLogLevel($me,2), "autocreate: define $cmd";
      my $ret = CommandDefine(undef, $cmd);
      if($ret) {
        Log GetLogLevel($me,1), "ERROR: $ret";
        last;
      }
      my $hash = $defs{$name};
      $nrcreated++;
      my $room = replace_wildcards($hash, $attr{$me}{device_room});
      $attr{$name}{room} = $room if($room);

      ####################
      my $fl = replace_wildcards($hash, $attr{$me}{filelog});
      next if(!$fl);
      my $flname = "FileLog_$name";
      my ($gplot, $filter) = ("", $name);
      foreach my $k (keys %flogpar) {
        next if("$type:$name" !~ m/^$k$/);
        $gplot = $flogpar{$k}{GPLOT};
        $filter = replace_wildcards($hash, $flogpar{$k}{FILTER});
      }
      $cmd = "$flname FileLog $fl $filter";
      Log GetLogLevel($me,2), "autocreate: define $cmd";
      $ret = CommandDefine(undef, $cmd);
      if($ret) {
        Log GetLogLevel($me,1), "ERROR: $ret";
        last;
      }
      $attr{$flname}{room} = $room if($room);
      $attr{$flname}{logtype} = "${gplot}text";


      ####################
      next if(!$attr{$me}{weblink} || !$gplot);
      $room = replace_wildcards($hash, $attr{$me}{weblink_room});
      my $wlname = "weblink_$name";
      my $gplotfile;
      my $stuff;
      ($gplotfile, $stuff) = split(/:/, $gplot);
      $cmd = "$wlname weblink fileplot $flname:$gplotfile:CURRENT";
      Log GetLogLevel($me,2), "autocreate: define $cmd";
      $ret = CommandDefine(undef, $cmd);
      if($ret) {
        Log GetLogLevel($me,1), "ERROR: $ret";
        last;
      }
      $attr{$wlname}{room} = $room if($room);
      $attr{$wlname}{label} = '"' . $name .
                ' Min $data{min1}, Max $data{max1}, Last $data{currval1}"';
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
        Log GetLogLevel($me,2),
                "autocreate: renamed FileLog_$old to FileLog_$new";
        $nrcreated++;
      }

      if($defs{"weblink_$old"}) {
        CommandRename(undef, "weblink_$old weblink_$new");
        my $hash = $defs{"weblink_$new"};
        $hash->{LINK} =~ s/$old/$new/g;
        $hash->{DEF} =~ s/$old/$new/g;
        $attr{"weblink_$new"}{label} =~ s/$old/$new/g;
        Log GetLogLevel($me,2),
                "autocreate: renamed weblink_$old to weblink_$new";
        $nrcreated++;
      }
    }

  }
  CommandSave(undef, undef) if(!$ret && $nrcreated && $attr{$me}{autosave});
  return $ret;
}

#####################################
# Test code. Use {dp "xxx"} to fake a device specific message
# FS20: 81xx04yy0101a00180c1020013
sub
dp($)
{
  Dispatch($defs{CUL}, shift, undef);
}

1;
