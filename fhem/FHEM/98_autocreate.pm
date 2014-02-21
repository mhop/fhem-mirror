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
  # Oregon sensors: 
  # * temperature
  "(THR128|THWR288A|THN132N|THGR132N).*"
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
  $hash->{AttrFn}   = "autocreate_Attr";
  $hash->{AttrList}= "autosave filelog device_room weblink weblink_room " .
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
  $hash->{NOTIFYDEV} = "global";
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
      next if(AttrVal($me, "disable", undef));

      my $it = AttrVal($me, "ignoreTypes", undef);
      next if($it && $name =~ m/$it/i);

      my ($cmd, $ret);
      my $hash = $defs{$name};  # Called from createlog

      ####################
      if(!$hash) {
        $cmd = "$name $type $arg";
        Log3 $me, 2, "autocreate: define $cmd";
        $ret = CommandDefine(undef, $cmd);
        if($ret) {
          Log3 $me, 1, "ERROR: $ret";
          last;
        }
      }
      $hash = $defs{$name};
      $nrcreated++;
      my $room = replace_wildcards($hash, AttrVal($me, "device_room", "%TYPE"));
      # preserve room for createlog
      $room = $attr{$name}{room} if($attr{$name} && $attr{$name}{room}); 
      $attr{$name}{room} = $room if($room);

      # BlackList processing
      my $blfound;
      foreach my $bl (@flog_blacklist) {
        $blfound = 1 if($name  =~ m/^$bl$/);
      }
      last if($blfound);

      ####################
      my $fl = replace_wildcards($hash, AttrVal($me, "filelog", ""));
      my $flname = "FileLog_$name";
      delete($defs{$flname}) if($fl); # If we are re-creating it with createlog.
      my ($gplot, $filter, $devattr) = ("", $name, "");

      my $fp = $modules{$hash->{TYPE}}{AutoCreate};
      $fp = \%flogpar if(!$fp);
      
      foreach my $k (keys %{$fp}) {
        next if($name  !~ m/^$k$/);
        $gplot = $fp->{$k}{GPLOT};
        $filter = replace_wildcards($hash, $fp->{$k}{FILTER});
        $devattr = $fp->{$k}{ATTR};
        last;
      }

      if($fl) {
        $cmd = "$flname FileLog $fl $filter";
        Log3 $me, 2, "autocreate: define $cmd";
        $ret = CommandDefine(undef, $cmd);
        if($ret) {
          Log3 $me, 1, "ERROR: $ret";
          last;
        }
        $attr{$flname}{room} = $room if($room);
        $attr{$flname}{logtype} = "${gplot}text";
      }
      if($devattr) {
        foreach my $attrNV (split(" ", $devattr)) {
          my ($an, $av) = split(":", $attrNV, 2);
          CommandAttr(undef, "$name $an $av");
        }
      }

      ####################
      next if(!AttrVal($me, "weblink", 1) || !$gplot || !$fl);
      $room = replace_wildcards($hash, AttrVal($me, "weblink_room", "Plots"));
      my $wnr = 1;
      foreach my $wdef (split(/,/, $gplot)) {
        next if(!$wdef);
        my ($gplotfile, $stuff) = split(/:/, $wdef);
        next if(!$gplotfile);
        my $wlname = "SVG_$name";
        $wlname .= "_$wnr" if($wnr > 1);
        $wnr++;
        delete($defs{$wlname});   # If we are re-creating it with createlog.
        $cmd = "$wlname SVG $flname:$gplotfile:CURRENT";
        Log3 $me, 2, "autocreate: define $cmd";
        $ret = CommandDefine(undef, $cmd);
        if($ret) {
          Log3 $me, 1, "ERROR: $ret";
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
        Log3 $me, 2, "autocreate: renamed FileLog_$old to FileLog_$new";
        $nrcreated++;
      }

      if($defs{"SVG_$old"}) {
        CommandRename(undef, "SVG_$old SVG_$new");
        my $hash = $defs{"SVG_$new"};
        $hash->{LINK} =~ s/$old/$new/g;
        $hash->{DEF} =~ s/$old/$new/g;
        $attr{"SVG_$new"}{label} =~ s/$old/$new/g;
        Log3 $me, 2, "autocreate: renamed SVG_$old to SVG_$new";
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
      matchList => ['cu.usbmodem.*(.)$', 'ttyACM.*(.)$'],
      DeviceName=> "DEVICE\@9600",
      flush     => "\n",
      request   => "V\n",
      response  => "^V .* CU.*",
      define    => "CUL_PARAM CUL DEVICE\@9600 1PARAM34", },

    { NAME      => "CUL",       # TuxRadio/RPi: CSM
      matchList => ["ttySP(.*)", "ttyAMA(.*)", ],
      DeviceName=> "DEVICE\@38400",
      flush     => "\n",
      request   => "V\n",
      response  => "^V .* CSM.*",
      define    => "CUL_PARAM CUL DEVICE\@38400 1PARAM34", },

    { NAME      => "TCM310",
      matchList => ["cu.usbserial(.*)", "cu.usbmodem(.*)",
                    "ttyUSB(.*)", "ttyACM(.*)", "ttyAMA(.*)"],
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

    { NAME      => "ZWDongle",
      matchList => ["cu.PL2303-0000(.*)", "ttyUSB(.*)"],
      DeviceName=> "DEVICE\@115200",
      request   => pack("H*", "01030020dc"),   # GetStatus 
      response  => "^\x06.*",
      define    => "ZWDongle_PARAM ZWDongle DEVICE\@115200", },

    { NAME      => "FRM",
      matchList => ["cu.usbserial(.*)", "cu.usbmodem(.*)",
                    "ttyUSB(.*)", "ttyACM(.*)", "ttyAMA(.*)"],
      DeviceName=> "DEVICE\@57600",
      init      => pack("H*", "F9"),   # Reset
      timeout   => 5.0, # StandardFirmata blink takes time
      request   => pack("H*", "F079F7"),   # Query firmware version and filename START_SYSEX (0xF0), queryFirmware (0x79), END_SYSEX (0xF7)
      response  => "^\xF0\x79(.*)\xF7",    # Response Sysex xF0 x78 (2 Byte version) (n Byte filename) Endsysex xF7
      define    => "FRM_PARAM FRM DEVICE\@57600", },
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

  Log3 undef, 1, "usb $n starting";
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
        Log3 undef, 2, $msg; $ret .= $msg . "\n";
        if(!$scan) {
          AnalyzeCommand(undef, "culflash none $culType"); # Enable autoload
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
          Log3 undef, 4, $msg; $ret .= $msg . "\n";

          # Check if it already used
          foreach my $d (keys %defs) {
            if($defs{$d}{DeviceName} &&
               $defs{$d}{FD}) {

              my $dn = $defs{$d}{DeviceName};
              my $match = ($dn =~ m/$dev/);
              if(!$match) {
                $dn =~ s/@.*//;
                $match = (readlink($dn) =~ m/$dev/) if(-l $dn);
              }

              if($match) {
                $msg = "already used by the fhem device $d";
                Log3 undef, 4, $msg; $ret .= $msg . "\n";
                goto NEXTDEVICE;
              }
            }
          }

          # Open the device
          my $dname = $thash->{DeviceName};
          $dname =~ s,DEVICE,$dir/$dev,g;
          my $hash = { NAME=>$name, DeviceName=>$dname, DevioText=>"Probing" };
          DevIo_OpenDev($hash, 0, 0);
          if(!defined($hash->{USBDev})) {
            DevIo_CloseDev($hash);      # remove the ReadyFn loop
            $msg = "cannot open the device";
            Log3 undef, 4, $msg; $ret .= $msg . "\n";
            goto NEXTDEVICE;
          }

          # Send reset (optional)
          if(defined($thash->{init})) {
            DevIo_SimpleWrite($hash, $thash->{init}, 0);
            DevIo_TimeoutRead($hash, $thash->{timeout} ? $thash->{timeout}:0.5);
          }

          # Clear the USB buffer
          DevIo_SimpleWrite($hash, $thash->{flush}, 0) if($thash->{flush});
          DevIo_TimeoutRead($hash, 0.1);
          DevIo_SimpleWrite($hash, $thash->{request}, 0);
          my $answer = DevIo_TimeoutRead($hash, 0.1);
          DevIo_CloseDev($hash);

          if($answer !~ m/$thash->{response}/) {
            $msg = "got wrong answer for a $name";
            Log3 undef, 4, $msg; $ret .= $msg . "\n";
            next;
          }

          my $define = $thash->{define};
          $define =~ s/PARAM/$PARAM/g;
          $define =~ s,DEVICE,$dir/$dev,g;
          $msg = "create as a fhem device with: define $define";
          Log3 undef, 4, $msg; $ret .= $msg . "\n";

          if(!$scan) {
            Log3 undef, 1, "define $define";
            CommandDefine($cl, $define);
          }

          goto NEXTDEVICE;
        }
      }
    }
NEXTDEVICE:
  }
  Log3 undef, 1, "usb $n end";
  return ($scan ? $ret : undef);
}

###################################
sub
autocreate_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");

  return undef;
}


1;

=pod
=begin html

<a name="autocreate"></a>
<h3>autocreate</h3>
<ul>

  Automatically create not yet defined fhem devices upon reception of a message
  generated by this device. Note: devices which are polled (like the EMEM/EMWZ
  accessed through the EM1010PC) will NOT be automatically created.

  <br>

  <a name="autocreatedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; autocreate</code><br>
    <br>
    <ul>
      By defining an instance, the global attribute <a href=
      "#autoload_undefined_devices">autoload_undefined_devices</a>
      is set, so that modules for unknnown devices are automatically loaded.
      The autocreate module intercepts the UNDEFINED event generated by each
      module, creates a device and optionally also FileLog and SVG
      entries.<br>
      <b>Note 1:</b> devices will be created with a unique name, which contains
      the type and a unique id for this type. When <a href="#rename">renaming
      </a> the device, the automatically created filelog and SVG devices
      will also be renamed.<br>
      <b>Note 2:</b> you can disable the automatic creation by setting the
      <a href="#disable">disable</a> attribute, in this case only the rename
      hook is active, and you can use the  <a href="#createlog">createlog</a>
      command to add FileLog and SVG to an already defined device.
      <b>Note 3:</b> It makes no sense to create more than one instance of this
      module.

    </ul>
    <br>

    Example:<PRE>
    define autocreate autocreate
    attr autocreate autosave
    attr autocreate device_room %TYPE
    attr autocreate filelog test2/log/%NAME-%Y.log
    attr autocreate weblink
    attr autocreate weblink_room Plots
    </PRE>
  </ul>


  <a name="autocreateset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="autocreateget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="autocreateattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="autosave"></a>
    <li>autosave<br>
        After creating a device, automatically save the config file with the
        command <a href="#save">save</a> command. Default is 1 (i.e. on), set
        it to 0 to switch it off.</li><br>

    <a name="device_room"></a>
    <li>device_room<br>
        "Put" the newly created device in this room. The name can contain the
        wildcards %TYPE and %NAME, see the example above.</li><br>

    <a name="filelogattr"></a>
    <li>filelog<br>
        Create a filelog associated with the device. The filename can contain
        the wildcards %TYPE and %NAME, see the example above. The filelog will
        be "put" in the same room as the device.</li><br>

    <a name="weblinkattr"></a>
    <li>weblink<br>
        Create an SVG associated with the device/filelog.</li><br>

    <a name="weblink_room"></a>
    <li>weblink_room<br>
        "Put" the newly created SVG in this room. The name can contain the
        wildcards %TYPE and %NAME, see the example above.</li><br>

    <li><a href="#disable">disable</a></li>
      <br>

    <a name="ignoreTypes"></a>
    <li>ignoreTypes<br>
        This is a regexp, to ignore certain devices, e.g. you neighbours FHT.
        You can specify more than one, with usual regexp syntax, e.g.<br>
        attr autocreate ignoreTypes CUL_HOERMANN.*|FHT_1234|CUL_WS_7
        </li>

  </ul>
  <br>

  <a name="createlog"></a>
  <b>createlog</b>
  <ul>
      Use this command to manually add a FileLog and an SVG to an existing
      device. 
      This command is part of the autocreate module.
  </ul>
  <br>

  <a name="usb"></a>
  <b>usb</b>
  <ul>
      Usage:
      <ul><code>
        usb scan<br>
        usb create<br>
      </code></ul>
      This command will scan the /dev directory for attached USB devices, and
      will try to identify them. With the argument scan you'll get back a list
      of fhem commands to execute, with the argument create there will be no
      feedback, and the devices will be created instead.<br><br>

      Note that switching a CUL to HomeMatic mode is still has to be done
      manually.<br><br>

      On Linux it will also check with the lsusb command, if unflashed CULs are
      attached. If this is the case, it will call CULflash with the appropriate
      parameters (or display the CULflash command if scan is specified). The
      usb command will only flash one device per call.<br><br>

      This command is part of the autocreate module.
  </ul>
</ul>
<br>

=end html

=begin html_DE

<a name="autocreate"></a>
<h3>autocreate</h3>
<ul>

  Erzeugt f&uuml;r noch nicht definierte fhem-Ger&auml;te automatisch die
  geignete Definition (define). Diese Definition wird aus einer Nachricht
  gewonnen, die von diesen neuen Ger&auml;ten empfangen wurde. Hinweis:
  Ger&auml;te, die mit Polling arbeiten (wie z.B. der Zugriff auf EMEM/EMWZ
  &uuml;ber EM1010PC) werden NICHT automatisch erzeugt.
  <br><br>

  <a name="autocreatedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; autocreate</code><br>
    <br>
    <ul>
      Durch die Definition dieser Instanz wird das globale Attribut <a
      href="#autoload_undefined_devices">autoload_undefined_devices</a>
      gesetzt, sodass die Module f&uuml;r unbekannte Ger&auml;te automatisch
      nachgeladen werden. Das autocreate-Modul interpretiert das
      UNDEFINED-event, welches von jedem Modul gestartet wird, erzeugt ein
      Ger&auml;t (device) und bei Bedarf ein FileLog sowie
      SVG-Eintr&auml;ge.<br>

      <b>Hinweis 1:</b> Ger&auml;te werden mit einem eindeutigen Namen erzeugt,
      der den Typ und eine individuelle ID f&uuml;r diesen Typ enth&auml;lt.
      Wird ein Ger&auml;t umbenannt (<a href="#rename">rename</a>), wird
      gleichzeitig das automatisch erzeugte FileLog und die SVG Ger&auml;te
      unbenannt.<br>

      <b>Hinweis 2:</b> Durch das Setzen des <a
      href="#disable">disable</a>-Attributes kann die automatische Erzeugung
      ausgeschaltet werden. In diesem Fall ist ausschlie&szlig;lich die oben
      erl&auml;uterte Umbenennung aktiv. Der <a
      href="#createlog">createlog</a>-Befehl kann zum Hinzuf&uuml;gen von
      FileLog und SVG eines bereits definierten Ger&auml;tes benutzt werden.
      <br>

      <b>Hinweis 3:</b>Es macht keinen Sinn, die Instanz dieses Moduls mehrmals
      zu erzeugen.

    </ul>
    <br>

    Beispiel:<PRE>
    define autocreate autocreate
    attr autocreate autosave
    attr autocreate device_room %TYPE
    attr autocreate filelog test2/log/%NAME-%Y.log
    attr autocreate weblink
    attr autocreate weblink_room Plots
    </PRE>
  </ul>


  <a name="autocreateset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="autocreateget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="autocreateattr"></a>
  <b>Attribute</b>
  <ul>
    <a name="autosave"></a>
    <li>autosave<br>
        Nach der Erzeugung eines neuen Ger&auml;tes wird automatisch die
        Konfigurationsdatei mit dem Befehl <a href="#save">save</a>
        gespeichert. Der Standardwert ist 1 (d.h. aktiviert), eine 0 schaltet
        die automatische Speicherung aus.</li><br>

    <a name="device_room"></a>
    <li>device_room<br>
        "Schiebt" das neu erstellte Ger&auml;t in diesen Raum. Der Name kann
        die Wildcards %NAME und %TYPE enthalten, siehe oben stehendes
        Beispiel.</li><br>

    <a name="filelogattr"></a>
    <li>filelog<br>
        Erstellt ein Filelog welches zu einem Ger&auml;t geh&ouml;rt. Der
        Dateiname darf die Wildcards %NAME und %TYPE enthalten, siehe oben
        stehendes Beispiel. Das Filelog wird in den gleichen Raum "geschoben"
        wie das zugeh&ouml;rige Ger&auml;t.</li><br>

    <a name="weblinkattr"></a>
    <li>weblink<br>
        Erzeugt ein SVG, welches mit dem Ger&auml;t/Filelog verkn&uuml;pft
        ist.</li><br>

    <a name="weblink_room"></a>
    <li>weblink_room<br>
        "Schiebt" das neu erstellte SVG in den bezeichneten Raum. Der Name kann
        die Wildcards %NAME und %TYPE enthalten, siehe oben stehendes
        Beispiel.</li><br>

    <li><a href="#disable">disable</a></li>
      <br>

    <a name="ignoreTypes"></a>
    <li>ignoreTypes<br>
        Dies ist ein Regexp, um bestimmte Ger&auml;te zu ignorieren, z.b. der
        Funk-Heizungsthermostat (FHT) des Nachbarn. In dem Ausdruck k&ouml;nnen
        mehr als ein Ger&auml;t &uuml;ber die normale Regexp-Syntax angegeben
        werden.<br>

        Beispiel:<br>
        <code>
        attr autocreate ignoreTypes CUL_HOERMANN.*|FHT_1234|CUL_WS_7
        </code>
        </li>

  </ul>
  <br>

  <a name="createlog"></a>
  <b>createlog</b>
  <ul>
      Dieser Befehl wird f&uuml;r ein manuelles Hinzuf&uuml;gen eines Logfile
      oder eines SVG zu einem vorhandenen Ger&auml;t verwendet.
      <br><br>
      Dieser Befehl ist Bestandteilteil des autocreate-Modules.
  </ul>
  <br>

  <a name="usb"></a>
  <b>usb</b>
  <ul>
      Verwendung:
      <ul><code>
        usb scan<br>
        usb create<br>
      </code></ul>
      Dieser Befehl durchsucht das /dev-Verzeichnis nach angeschlossenen
      USB-Ger&auml;ten und versucht gleichzeitig sie zu identifizieren. Mit dem
      Argument scan wird eine Liste von ausf&uuml;hrbaren fhem-Befehlen
      zur&uuml;ckgegeben. Das Argument create gibt keine Liste o.&auml;.
      zur&uuml;ck, die Ger&auml;te werden stattdessen erzeugt.<br><br>

      Es ist zu beachten, dass ein CUL immer noch manuell in den
      HomeMatic-Modus umgeschaltet werden muss. <br><br>

      Unter Linux wird gleichzeitig mit dem lsusb-befehl &uuml;berpr&uuml;ft,
      ob nichtgeflashte CULs angeschlossen sind. Ist dies der Fall, ruft Linux
      CULflash mit den geeigneten Parametern auf (oder zeigt den
      CULflash-Befehl an, falls scan aufgef&uuml;hrt wurde).
      Pro usb Befehl wird nur ein Ger&auml;t geflasht.<br><br>

      Dieser Befehl ist Bestandteilteil des autocreate-Modules. 
  </ul>
</ul> <!-- End of autocreate -->
<br>

=end html_DE

=cut
