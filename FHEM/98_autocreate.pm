##############################################
# $Id$
package main;

use strict;
use warnings;

# Problems:
# - Not all CUL_EM devices return a power
# - Not all CUL_WS devices return a temperature
# - No plot files for BS/CUL_FHTTK/USF1000/X10/WS300
# - check "UNDEFINED" parameters for BS/USF1000/X10

my %flogpar = (
  "CUL_EM.*"
      => { GPLOT => "power8:Power,", FILTER => "%NAME:CNT.*" },
  "CUL_WS.*"
      => { GPLOT => "temp4hum6:Temp/Hum,",  FILTER => "%NAME:T:.*" },
  "CUL_FHTTK.*"
      => { GPLOT => "fht80tf:Window,", FILTER => "%NAME" },
  "FHT.*"
      => { GPLOT => "fht:Temp/Act,", FILTER => "%NAME" },
  "HMS100TFK_.*"
      => { GPLOT => "fht80tf:Contact,", FILTER => "%NAME" },
  "HMS100T_.*"
      => { GPLOT => "temp4hum6:Temp/Hum,", FILTER => "%NAME:T:.*" },
  "KS300.*"
      => { GPLOT => "temp4rain10:Temp/Rain,hum6wind8:Wind/Hum,",
           FILTER => "%NAME:T:.*" },

  # Oregon sensors: 
  # * temperature
  "(THR128|THWR288A|THN132N).*"
      => { GPLOT => "temp4:Temp,",  FILTER => "%NAME" },
  # * temperature, humidity
  "(THGR228N|THGR810|THGR918|THGR328N|RTGR328N|WTGR800_T|WT450H).*"
      => { GPLOT => "temp4hum4:Temp/Hum,",  FILTER => "%NAME" },
  # * temperature, humidity, pressure
  "(BTHR918N|BTHR918|BTHR918N).*"
      => { GPLOT => "rain4press4:Temp/Press,temp4hum4:Temp/Hum,",
           FILTER => "%NAME" },
  # * anenometer
  "(WGR800|WGR918|WTGR800_A).*"
      => { GPLOT => "wind4windDir4:WindDir/WindSpeed,",  FILTER => "%NAME" },
  # * Oregon sensors: Rain gauge
  "(PCR800|RGR918).*"
      => { GPLOT => "rain4:RainRate",  FILTER => "%NAME" },

  # X10 sensors received by RFXCOM
  "(RFXX10SEC|TRX_DS10A).*"
      => { GPLOT => "fht80tf:Window,", FILTER => "%NAME" },
  # X10 Window sensors received by RFXTRX
  "TRX_DS10A.*"
       => { GPLOT => "fht80tf:Window,", FILTER => "%NAME" },
  # TX3 temperature sensors received by RFXTRX
  "TX3.*"
       => { GPLOT => "temp4hum4:Temp/Hum,",  FILTER => "%NAME" },


  # USB-WDE1
  "USBWX_[0-8]"
      => { GPLOT => "temp4hum6:Temp/Hum,",  FILTER => "%NAME" },
  "USBWX_ks300"
      => { GPLOT => "temp4hum6:Temp/Hum,temp4rain10:Temp/Rain,hum6wind8:Wind/Hum,",
           FILTER => "%NAME:T:.*" },

  # HomeMatic
  "CUL_HM_THSensor.*"
      => { GPLOT => "temp4hum6:Temp/Hum,", FILTER => "%NAME:T:.*" },
  "CUL_HM_KS550.*"
      => { GPLOT => "temp4rain10:Temp/Rain,hum6wind8:Wind/Hum,",
           FILTER => "%NAME:T:.*" },
  "CUL_HM_HM-CC-TC.*"
      => { GPLOT => "temp4hum6:Temp/Hum,", FILTER => "%NAME:T:.*" },

  # Lacrosse TX
  "CUL_TX.*"
      => { GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME" },
);

# Do not create FileLog for the following devices.
my @flog_blacklist = (
  "CUL_RFR.*"
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
                     "disable ignoreTypes";
  my %ahash = ( Fn=>"CommandCreateLog",
                Hlp=>"<device>,create log/weblink for <device>" );
  $cmds{createlog} = \%ahash;

  my %bhash = ( Fn=>"CommandUsb",
                Hlp=>"[scan|create],display or create fhem-entries for USB devices" );
  $cmds{usb} = \%bhash;
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

      my $it = AttrVal($me, "ignoreTypes", undef);
      next if($it && $name =~ m/$it/i);

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
      my $room = replace_wildcards($hash, AttrVal($me, "device_room", "%TYPE"));
      $attr{$name}{room} = $room if($room);

      # BlackList processing
      my $blfound;
      foreach my $bl (@flog_blacklist) {
        $blfound = 1 if($name  =~ m/^$bl$/);
      }
      last if($blfound);

      ####################
      my $fl = replace_wildcards($hash, AttrVal($me, "filelog", ""));
      next if(!$fl);
      my $flname = "FileLog_$name";
      delete($defs{$flname});   # If we are re-creating it with createlog.
      my ($gplot, $filter) = ("", $name);
      foreach my $k (keys %flogpar) {
        next if($name  !~ m/^$k$/);
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
      next if(!AttrVal($me, "weblink", 1) || !$gplot);
      $room = replace_wildcards($hash, AttrVal($me, "weblink_room", "Plots"));
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

  CommandSave(undef, undef) if(!$ret && $nrcreated && AttrVal($me,"autosave",1));
  return $ret;
}

# TODO: fix it if the device is renamed.
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


##########################
# Table for automatically creating IO devices
# PARAM in define will be replaced with the $1 from matchList
my @usbtable = (
    { NAME      => "CUL",
      matchList => ["cu.usbmodem(.*)", "ttyACM(.*)"],
      DeviceName=> "DEVICE\@9600",
      flush     => "\n",
      request   => "V\n",
      response  => "^V .* CU.*",
      define    => "CUL_PARAM CUL DEVICE\@9600 1PARAM34", },

    { NAME      => "CUL",
      matchList => ["ttySP(.*)"],
      DeviceName=> "DEVICE\@38400",
      flush     => "\n",
      request   => "V\n",
      response  => "^V .* CSM.*",
      define    => "CUL_PARAM CUL DEVICE\@38400 1PARAM34", },

    { NAME      => "TCM310",
      matchList => ["cu.usbserial(.*)", "cu.usbmodem(.*)", "ttyUSB(.*)", "ttyACM(.*)"],
      DeviceName=> "DEVICE\@57600",
      request   => pack("H*", "5500010005700838"),   # get idbase
      response  => "^\x55\x00\x05\x01",
      define    => "TCM310_PARAM TCM 310 DEVICE\@57600", },

    { NAME      => "TCM120",
      matchList => ["ttyUSB(.*)"],
      DeviceName=> "DEVICE\@9600",
      request   => pack("H*", "A55AAB5800000000000000000003"),   # get idbase
      response  => "^\xA5\x5A............",
      define    => "TCM120_PARAM TCM 120 DEVICE\@9600", },

    { NAME      => "FHZ",
      matchList => ["cu.usbserial(.*)", "ttyUSB(.*)"],
      DeviceName=> "DEVICE\@9600",
      request   => pack("H*", "8105044fc90185"),   # get fhtbuf
      response  => "^\x81........",
      define    => "FHZ_PARAM FHZ DEVICE", },

    { NAME      => "TRX",
      matchList => ["cu.usbserial(.*)", "ttyUSB(.*)"],
      DeviceName=> "DEVICE\@38400",
      init      => pack("H*", "0D00000000000000000000000000"),   # Reset 
      request   => pack("H*", "0D00000102000000000000000000"),   # GetStatus 
      response  => "^\x0d\x01\x00...........",
      define    => "TRX_PARAM TRX DEVICE\@38400", },

);


sub
CommandUsb($$)
{
  my ($cl, $n) = @_;

  return "Usage: usb [scan|create]" if("$n" !~ m/^(scan|create)$/);
  my $scan = 1 if($n eq "scan");
  my $ret = "";
  my $msg;
  my $dir = "/dev";

  if($^O =~ m/Win/) {
    return "This command is not yet supported on windows";
  }

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  ################
  # First try to flash unflashed CULs
  if($^O eq "linux") {
    # One device at a time to avoid endless loop
    my $lsusb = `lsusb`;
    if($lsusb) {
      my $culType;
      $culType = "CUL_V4" if($lsusb =~ m/VID=03eb.PID=2ff0/s); # FritzBox
      $culType = "CUL_V3" if($lsusb =~ m/VID=03eb.PID=2ff4/s); # FritzBox
      $culType = "CUL_V2" if($lsusb =~ m/VID=03eb.PID=2ffa/s); # FritzBox
      $culType = "CUL_V4" if($lsusb =~ m/03eb:2ff0/);
      $culType = "CUL_V3" if($lsusb =~ m/03eb:2ff4/);
      $culType = "CUL_V2" if($lsusb =~ m/03eb:2ffa/);
      if($culType) {
        $msg = "$culType: flash it with: CULflash none $culType";
        Log 4, $msg; $ret .= $msg . "\n";
        if(!$scan) {
          CommandCULflash(undef, "none $culType");
          sleep(4);      # Leave time for linux to load th drivers
        }
      }
    }
  }

  ################
  # Now the /dev scan
  foreach my $dev (sort split("\n", `ls $dir`)) {
    foreach my $thash (@usbtable) {
      foreach my $ml (@{$thash->{matchList}}) {
        if($dev =~ m/$ml/) {
          my $PARAM = $1;
          $PARAM =~ s/[^A-Za-z0-9]//g;
          my $name = $thash->{NAME};
          $msg = "### $dev: checking if it is a $name";
          Log 4, $msg; $ret .= $msg . "\n";

          # Check if it already used
          foreach my $d (keys %defs) {
            if($defs{$d}{DeviceName} &&
               $defs{$d}{DeviceName} =~ m/$dev/ &&
               $defs{$d}{FD}) {
              $msg = "already used by the $d fhem device";
              Log 4, $msg; $ret .= $msg . "\n";
              goto NEXTDEVICE;
            }
          }

          # Open the device
          my $dname = $thash->{DeviceName};
          $dname =~ s,DEVICE,$dir/$dev,g;
          my $hash = { NAME=>$name, DeviceName=>$dname };
          DevIo_OpenDev($hash, 0, 0);
          if(!defined($hash->{USBDev})) {
            DevIo_CloseDev($hash);      # remove the ReadyFn loop
            $msg = "cannot open the device";
            Log 4, $msg; $ret .= $msg . "\n";
            goto NEXTDEVICE;
          }

          # Send reset (optional)
          if(defined($thash->{init})) {
            DevIo_SimpleWrite($hash, $thash->{init}, 0);
            DevIo_TimeoutRead($hash, 0.5);
          }

          # Clear the USB buffer
          DevIo_SimpleWrite($hash, $thash->{flush}, 0) if($thash->{flush});
          DevIo_TimeoutRead($hash, 0.1);
          DevIo_SimpleWrite($hash, $thash->{request}, 0);
          my $answer = DevIo_TimeoutRead($hash, 0.1);
          DevIo_CloseDev($hash);

          if($answer !~ m/$thash->{response}/) {
            $msg = "got wrong answer for a $name";
            Log 4, $msg; $ret .= $msg . "\n";
            next;
          }

          my $define = $thash->{define};
          $define =~ s/PARAM/$PARAM/g;
          $define =~ s,DEVICE,$dir/$dev,g;
          $msg = "create as a fhem device with: define $define";
          Log 4, $msg; $ret .= $msg . "\n";

          if(!$scan) {
            Log 1, "define $define";
            CommandDefine($cl, $define);
          }

          goto NEXTDEVICE;
        }
      }
    }
NEXTDEVICE:
  }
  return ($scan ? $ret : undef);
}

1;
