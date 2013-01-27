##############################################
# $Id$
package main;

use strict;
use warnings;
use SetExtensions;

sub EnOcean_Define($$);
sub EnOcean_Initialize($);
sub EnOcean_Parse($$);
sub EnOcean_Set($@);
sub EnOcean_MD15Cmd($$$);

my %EnO_rorgname = ("F6"=>"switch",     # RPS
                    "D5"=>"contact",    # 1BS
                    "A5"=>"sensor",     # 4BS
                   );
my @EnO_ptm200btn = ("AI", "A0", "BI", "B0", "CI", "C0", "DI", "D0");
my %EnO_ptm200btn;

# Some Manufacturers (e.g. Jaeger Direkt) also sell EnOcean products without an
# intry in the table below. This table is only needed for A5 category devices
my %EnO_manuf = (
  "001" => "Peha",
  "002" => "Thermokon",
  "003" => "Servodan",
  "004" => "EchoFlex Solutions",
  "005" => "Omnio AG",
  "006" => "Hardmeier electronics",
  "007" => "Regulvar Inc",
  "008" => "Ad Hoc Electronics",
  "009" => "Distech Controls",
  "00A" => "Kieback + Peter",
  "00B" => "EnOcean GmbH",
  "00C" => "Probare",
  "00D" => "Eltako",
  "00E" => "Leviton",
  "00F" => "Honeywell",
  "010" => "Spartan Peripheral Devices",
  "011" => "Siemens",
  "012" => "T-Mac",
  "013" => "Reliable Controls Corporation",
  "014" => "Elsner Elektronik GmbH",
  "015" => "Diehl Controls",
  "016" => "BSC Computer",
  "017" => "S+S Regeltechnik GmbH",
  "018" => "Masco Corporation",
  "019" => "Intesis Software SL",
  "01A" => "Res.",
  "01B" => "Lutuo Technology",
  "01C" => "CAN2GO",
);

my %EnO_subType = (
  "A5.20.01" => "MD15",
  1          => "switch",
  2          => "contact",
  3          => "sensor",
  4          => "windowHandle",
  5          => "eltakoDimmer",
  6          => "eltakoShutter",
  7          => "FAH",
  8          => "FBH",
  9          => "FTF",
 10          => "SR04",
);

my @EnO_models = qw (
  other
  MD15-FtL-HE 
  SR04 SR04P SR04PT SR04PST SR04PMS
  FAH60 FAH63 FIH63
  FABH63 FBH63 FIBH63
  PM101
  FTF55
  FSB61
  FSM61
);

sub
EnOcean_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^EnOcean:";
  $hash->{DefFn}     = "EnOcean_Define";
  $hash->{ParseFn}   = "EnOcean_Parse";
  $hash->{SetFn}     = "EnOcean_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:0,1 " .
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 ".
                       "model:".join(",",@EnO_models)." ".
                       "subType:".join(",",values %EnO_subType)." ".
                       "subDef actualTemp dimTime shutTime ".
                       $readingFnAttributes;

  for(my $i=0; $i<@EnO_ptm200btn;$i++) {
    $EnO_ptm200btn{$EnO_ptm200btn[$i]} = "$i:30";
  }
  $EnO_ptm200btn{released} = "0:20";
  return undef;
}

#############################
sub
EnOcean_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};
  return "wrong syntax: define <name> EnOcean 8-digit-hex-code"
    if(int(@a)!=3 || $a[2] !~ m/^[A-F0-9]{8}$/i);

  $modules{EnOcean}{defptr}{uc($a[2])} = $hash;
  AssignIoPort($hash);
  # Help FHEMWEB split up devices
  $attr{$name}{subType} = $1 if($name =~ m/EnO_(.*)_$a[2]/);
  return undef;
}


#############################
sub
EnOcean_Set($@)
{
  my ($hash, @a) = @_;
  return "no set value specified" if(@a < 2);

  my $updateState = 1;
  my $name = $hash->{NAME};
  my $st = AttrVal($name, "subType", "");
  my $ll2 = GetLogLevel($name, 2);

  shift @a;
  my $tn = TimeNow();

  for(my $i = 0; $i < @a; $i++) {
    my $cmd = $a[$i];

    #####################
    # See also http://www.oscat.de/community/index.php/topic,985.30.html
    if($st eq "MD15") {
      my %sets = (
        "desired-temp"   => "\\d+(\\.\\d)?",
        "actuator"       => "\\d+",
        "unattended"     => "",
        "initialize"     => "",
      );
      my $re = $sets{$a[0]};
      return "Unknown argument $cmd, choose one of ".join(" ", sort keys %sets)
        if(!defined($re));
      return "Need a parameter" if($re && @a < 2);
      return "Argument $a[1] is incorrect (expect $re)"
        if($re && $a[1] !~ m/^$re$/);

      $hash->{CMD} = $cmd;
      $hash->{READINGS}{CMD}{TIME} = $tn;
      $hash->{READINGS}{CMD}{VAL} = $cmd;

      my $arg = "true";
      if($re) {
        $arg = $a[1];
        shift(@a);
      }

      $hash->{READINGS}{$cmd}{TIME} = $tn;
      $hash->{READINGS}{$cmd}{VAL} = $arg;

	###########################
    } elsif($st eq "eltakoDimmer") {

      my $sendDimCmd=0;
      my $dimTime=AttrVal($name, "dimTime", 0);
      my $onoff=1;
      my $subDef = AttrVal($name, "subDef", "");
      my $dimVal=$hash->{READINGS}{dimValue}{VAL};

      if($cmd eq "teach") {
        my $data=sprintf("A502000000%s00", $subDef);
        Log $ll2, "EnOcean: set $name $cmd SenderID: $subDef";
        # len:000a optlen:00 pakettype:1(radio)
        IOWrite($hash, "000A0001", $data);

      } elsif($cmd eq "dim") {
        return "Usage: $cmd percent [dimspeed 1-100]" if(@a<2 or $a[1]>100);
        # for eltako relative (0-100) (but not compliant to EEP because DB0.2
        # is 0)
        $dimVal=$a[1];
        shift(@a);
        if(defined($a[1])) { 
          $dimTime=sprintf("%x",(($a[1]*2.55)-255)*-1); 
          shift(@a); 
        }
        $sendDimCmd=1;

      } elsif($cmd eq "dimup") {
        return "Usage: $cmd percent [dimspeed 1-100]" if(@a<2 or $a[1]>100);
        $dimVal+=$a[1];
        shift(@a);
        if(defined($a[1])) {
          $dimTime=$a[1];
          shift(@a);
        }
        $sendDimCmd=1;

      } elsif($cmd eq "dimdown") {
        return "Usage: $cmd percent [dimspeed 1-100]" if(@a<2 or $a[1]>100);
        $dimVal-=$a[1];
        shift(@a);
          if(defined($a[1])) { $dimTime=$a[1]; shift(@a); }
        $sendDimCmd=1;

      } elsif($cmd eq "on" || $cmd eq "B0") {
        $dimTime=1;
        $sendDimCmd=1;
        $dimVal=100;

      } elsif($cmd eq "off" || $cmd eq "BI") {
        $dimTime=1;
        $onoff=0;
        $sendDimCmd=1;
        $dimVal=0;

      } else {
        my $list = "dim:slider,0,1,100 dimup:slider,0,1,100 ".
                   "dimdown:slider,0,1,100 on off teach";
        return SetExtensions($hash, $list, $name, @a);

      }
	  
      if($sendDimCmd) {
        $updateState = 0;
        $a[0]="on";
          if($dimVal >  100) { $dimVal=100; }
          if($dimVal <= 0)   { $dimVal=0; $onoff=0; $a[0]="off" }
        ReadingsVal($name, "dimValue", $dimVal); 
        my $data=sprintf("A502%02X%02X%02X%s00",
                $dimVal, $dimTime, $onoff|0x08, $subDef);
        IOWrite($hash, "000A0001", $data);
        Log $ll2, "EnOcean: set $name $cmd $dimVal";
      }
	  
    ###########################
    } elsif($st eq "eltakoShutter") {
      my $shutTime=AttrVal($name, "shutTime", 0);
      my $subDef = AttrVal($name, "subDef", "");
      my $shutCmd = 0x00; 
      if($cmd eq "teach") {
        my $data=sprintf("A5FFF80D80%s00", $subDef);
        Log $ll2, "EnOcean: set $name $cmd SenderID: $subDef";
        # len:000a optlen:00 pakettype:1(radio)
        IOWrite($hash, "000A0001", $data);

      } elsif($cmd eq "stop") {
        $shutCmd = 0x00;

      } elsif($cmd eq "up" || $cmd eq "B0") {
        my $position = 100;
        if($a[1]) { 
          $shutTime = $shutTime/100*$a[1]; 
          $position = $hash->{READINGS}{position}{VAL}+$a[1];
            if($position > 100) { $position = 100; };
        }
        $hash->{READINGS}{position}{TIME} = $tn;
        $hash->{READINGS}{position}{VAL} = $position;
        $shutCmd = 0x01;

      } elsif($cmd eq "down" || $cmd eq "BI") {
        my $position = 0;
        if($a[1]) { 
          $shutTime = $shutTime/100*$a[1]; 
          $position = $hash->{READINGS}{position}{VAL}-$a[1];
            if($position <= 0) { $position = 0; };
        }
        $hash->{READINGS}{position}{TIME} = $tn;
        $hash->{READINGS}{position}{VAL} = $position;
        $shutCmd = 0x02;
      } else { 
        return "Unknown argument " . $cmd . ", choose one of up down stop teach"
      }
      shift(@a);
      if($shutCmd || ($cmd eq "stop")) {
        $updateState = 0;
        # EEP: A5/3F/7F Universal ???
        my $data = sprintf("A5%02X%02X%02X%02X%s00",
                        0x00, $shutTime, $shutCmd, 0x08, $subDef);
        IOWrite($hash, "000A0001", $data);
        Log $ll2, "EnOcean: set $name $cmd";
      }    

    ###########################
    } else {                                          # Simulate a PTM
      my ($c1,$c2) = split(",", $cmd, 2);

      if(!defined($EnO_ptm200btn{$c1}) ||
          ($c2 && !defined($EnO_ptm200btn{$c2}))) {
        my $list = join(" ", sort keys %EnO_ptm200btn);
        return SetExtensions($hash, $list, $name, @a);
      }

      my ($db_3, $status) = split(":", $EnO_ptm200btn{$c1}, 2);
      $db_3 <<= 5;
      $db_3 |= 0x10 if($c1 ne "released"); # set the pressed flag
      if($c2) {
        my ($d2, undef) = split(":", $EnO_ptm200btn{$c2}, 2);
        $db_3 |= ($d2<<1) | 0x01;
      }
      IOWrite($hash, "",
              sprintf("6B05%02X000000%s%s", $db_3, $hash->{DEF}, $status));

    }

    select(undef, undef, undef, 0.2);   # Tested by joerg. He prefers 0.3 :)
  }

  if($updateState == 1) {
    readingsSingleUpdate($hash, "state", join(" ", @a), 1);
    return undef;
  }
}

#############################
# "EnOcean:F6:50000000:0011C8D4:FF" -> EnO_switch on (BI)
sub
EnOcean_Parse($$)
{
  my ($iohash, $msg) = @_;
  my (undef,$rorg,$data,$id,$status,$odata) = split(":", $msg);

  my $rorgname = $EnO_rorgname{$rorg};
  if(!$rorgname) {
    Log 2, "Unknown EnOcean RORG ($rorg) received from $id";
    return "";
  }

  my $hash = $modules{EnOcean}{defptr}{$id}; 
  if(!$hash) {
    Log 3, "EnOcean Unknown device with ID $id, please define it";
    return "UNDEFINED EnO_${rorgname}_$id EnOcean $id";
  }

  my $name = $hash->{NAME};
  my $ll4 = GetLogLevel($name, 4);
  Log $ll4, "$name: ORG:$rorg DATA:$data ID:$id STATUS:$status";

  my @event;
  #push @event, "1:rp_counter:".(hex($status)&0xf);

  my $dl = length($data);
  my $db_3 = hex substr($data,0,2);
  my $db_2 = hex substr($data,2,2) if($dl > 2);
  my $db_1 = hex substr($data,4,2) if($dl > 4);
  my $db_0 = hex substr($data,6,2) if($dl > 6);
  my $st = AttrVal($name, "subType", "");
  my $model = AttrVal($name, "model", "");

  #################################
  # RPS: PTM200 based switch/remote or a windowHandle
  if($rorg eq "F6") {
    my $nu =  ((hex($status)&0x10)>>4);

    # unused flags (AFAIK)
    #push @event, "1:T21:".((hex($status)&0x20)>>5);
    #push @event, "1:NU:$nu";

    if($nu) {

      # Theoretically there can be a released event with some of the A0,BI
      # pins set, but with the plastic cover on this wont happen.
      $msg  = $EnO_ptm200btn[($db_3&0xe0)>>5];
      $msg .= ",".$EnO_ptm200btn[($db_3&0x0e)>>1] if($db_3 & 1);
      $msg .= " released" if(!($db_3 & 0x10));

    } else {

      if($db_3 == 112) { # KeyCard, not tested
        $msg = "keycard inserted";

      # Only the windowHandle is setting these bits when nu=0
      } elsif($db_3 & 0xC0) {
        $msg = "closed"           if($db_3 == 0xF0);
        $msg = "open"             if($db_3 == 0xE0);
        $msg = "tilted"           if($db_3 == 0xD0);
        $msg = "open from tilted" if($db_3 == 0xC0);

      } else {
        if($st eq "keycard") {
          $msg = "keycard removed";
          
        } else {
          $msg = (($db_3&0x10) ? "pressed" : "released");

        }

      }
      
    }

    # released events are disturbing when using a remote, since it overwrites
    # the "real" state immediately.
    # In the case of an ElTako FSB61 the state should remain released (by Thomas)
    my $event = "state";
    $event = "buttons" if($msg =~ m/released$/ &&
                          $model ne "FSB61" &&
                          $model ne "FSM61");

    push @event, "3:$event:$msg";

  #################################
  # 1BS. Only contact is defined in the EEP2.1 for 1BS
  } elsif($rorg eq "D5") {
    push @event, "3:state:" . ($db_3&1 ? "closed" : "open");
    push @event, "3:learnBtn:on" if(!($db_3&0x8));

  #################################
  } elsif($rorg eq "A5") {
    if(($db_0 & 0x08) == 0) {
      if($db_0 & 0x80) {
        my $fn = sprintf "%02x", ($db_3>>2);
        my $tp = sprintf "%02X", ((($db_3&3) << 5) | ($db_2 >> 3));
        my $mf = sprintf "%03X", ((($db_2&7) << 8) | $db_1);
        $mf = $EnO_manuf{$mf} if($EnO_manuf{$mf});
        my $m = "teach-in:class A5.$fn.$tp (manufacturer: $mf)";
        Log 1, $m;
        push @event, "3:$m";
        my $st = "A5.$fn.$tp";
        $st = $EnO_subType{$st} if($EnO_subType{$st});
        $attr{$name}{subType} = $st;

        if("$fn.$tp" eq "20.01" && $iohash->{pair}) {      # MD15
          select(undef, undef, undef, 0.1);                # max 10 Seconds
          EnOcean_A5Cmd($hash, "800800F0", "00000000");
          select(undef, undef, undef, 0.5);
          EnOcean_MD15Cmd($hash, $name, 128); # 128 == 20 degree C
        }

      } else {
        push @event, "3:teach-in:no type/manuf. data transmitted";

      }

    } elsif($model =~ m/^SR04/ || $st eq "SR04") {
      my ($fspeed, $temp, $present, $solltemp);
      $fspeed = 3;
      $fspeed = 2      if($db_3 >= 145);
      $fspeed = 1      if($db_3 >= 165);
      $fspeed = 0      if($db_3 >= 190);
      $fspeed = "Auto" if($db_3 >= 210);
      $temp   = sprintf("%0.1f", 40-$db_1/6.375);      # 40..0
      $present= $db_0&0x1 ? "no" : "yes";
      $solltemp= sprintf("%0.1f", $db_2/6.375);

      push @event, "3:state:temperature $temp";
      push @event, "3:set_point: $solltemp";
      push @event, "3:fan:$fspeed";
      push @event, "3:present:$present" if($present eq "yes");
      push @event, "3:learnBtn:on" if(!($db_0&0x8));
      push @event, "3:T:$temp SP: $db_3 F: $fspeed P: $present";

    } elsif($st eq "MD15") {
      push @event, "3:state:$db_3 %";
      push @event, "3:currentValue:$db_3";
      push @event, "3:serviceOn:"    . (($db_2 & 0x80) ? "yes" : "no");
      push @event, "3:energyInput:"  . (($db_2 & 0x40) ? "enabled":"disabled");
      push @event, "3:energyStorage:". (($db_2 & 0x20) ? "charged":"empty");
      push @event, "3:battery:"      . (($db_2 & 0x10) ? "ok" : "empty");
      push @event, "3:cover:"        . (($db_2 & 0x08) ? "open" : "closed");
      push @event, "3:tempSensor:"   . (($db_2 & 0x04) ? "failed" : "ok");
      push @event, "3:window:"       . (($db_2 & 0x02) ? "open" : "closed");
      push @event, "3:actuatorStatus:".(($db_2 & 0x01) ? "obstructed" : "ok");
      push @event, "3:measured-temp:". sprintf "%0.1f", ($db_1*40/255);
      EnOcean_MD15Cmd($hash, $name, $db_1);
      
    } elsif($model eq "PM101") {
      ####################################
      # Ratio Presence Sensor Eagle PM101, code by aicgazi
      ####################################
      my $lux = sprintf "%3d", $db_2;
      # content  of $db_2 is the illuminance where max value 0xFF stands for 1000 lx
      $lux = sprintf "%04.2f", ( $lux * 1000 / 255 ) ;
      push @event, "3:brightness:$lux";
      push @event, "3:channel1:" . ($db_0 & 0x01 ? "off" : "on");
      push @event, "3:channel2:" . ($db_0 & 0x02 ? "off" : "on");

    } elsif($st eq "FAH" || $model =~ /^(FAH60|FAH63|FIH63)$/) {
      ####################################
      # Eltako FAH60+FAH63+FIH63
      # (EEP: 07-06-01 plus Data_byte3)
      ####################################
      # $db_3 is the illuminance where min 0x00 = 0 lx, max 0xFF = 100 lx;
      # $db_2 must be 0x00

      if($db_2 eq 0x00) {
        my $luxlow = sprintf "%3d", $db_3;
        $luxlow = sprintf "%d", ( $luxlow * 100 / 255 ) ;
        push @event, "3:brightness:$luxlow";
        push @event, "3:state:$luxlow";
      } else {
        # $db_2 is the illuminance where min 0x00 = 300 lx, max 0xFF = 30000 lx
        my $lux = sprintf "%3d", $db_2;
        $lux = sprintf "%d", (( $lux * 116.48) + 300 ) ;
        push @event, "3:brightness:$lux";
        push @event, "3:state:$lux";
      }

    } elsif($st eq "FBH" || $model =~ /^(FABH63|FBH55|FBH63|FIBH63)$/) {
      ####################################
      # Eltako FABH63+FBH55+FBH63+FIBH63
      # (EEP: similar 07-08-01)
      ####################################
      # $db_0 motion detection where 0x0D = motion and 0x0F = no motion
      # (DB0_Bit1 = 1 or 0)

      if($db_0 eq 0x0D) {
        push @event, "3:motion:yes";
        push @event, "3:state:yes";
      }
      if($db_0 eq 0x0F) {
        push @event, "3:motion:no";
        push @event, "3:state:no";
      }
      # $db_2 is the illuminance where min 0x00 = 0 lx, max 0xFF = 2048 lx
      my $lux = sprintf "%3d", $db_2;
      $lux = sprintf "%d", ( $lux * 2048 / 255 ) ;
      push @event, "3:brightness:$lux";
      # $db_3 is voltage in EEP 07-08-01 but not used by Eltako !?
      # push @event, "3:voltage:$db_3";

    } elsif($st eq "FTF" || $model eq "FTF55") {
      ####################################
      # Eltako FTF55
      # (EEP: 07-02-05)
      ####################################
      # $db_1 is the temperature where 0x00 = 40?C and 0xFF 0?C
      my $temp = sprintf "%3d", $db_1;
      $temp = sprintf "%0.1f", ( 40 - $temp * 40 / 255 ) ;
      push @event, "3:temperature:$temp";
      push @event, "3:state:$temp";
	  
    } elsif($st eq "eltakoDimmer") {
      # todo: create a more general solution for the central-command responses
      if($db_3 eq 0x02) { # dimm
        push @event, "3:state:" . ($db_0 & 0x01 ? "on" : "off");
        push @event, "3:dimValue:" . $db_2;
      }
    } else {
      push @event, "3:state:$db_3";
      push @event, "3:sensor1:$db_3";
      push @event, "3:sensor2:$db_2";
      push @event, "3:sensor3:$db_1";
      push @event, "3:D3:".(($db_0&0x8)?1:0);
      push @event, "3:D2:".(($db_0&0x4)?1:0);
      push @event, "3:D1:".(($db_0&0x2)?1:0);
      push @event, "3:D0:".(($db_0&0x1)?1:0);

    }

  }

  readingsBeginUpdate($hash);
  for(my $i = 0; $i < int(@event); $i++) {
    # Flag & 1: reading, Flag & 2: changed. Currently ignored.
    my ($flag, $vn, $vv) = split(":", $event[$i], 3);
    readingsBulkUpdate($hash, $vn, $vv);
  }
  readingsEndUpdate($hash, 1);
  
  return $name;
}

sub
EnOcean_MD15Cmd($$$)
{
  my ($hash, $name, $db_1) = @_;
  my $cmd = ReadingsVal($name, "CMD", undef);
  if($cmd) {
    my $msg;        # Unattended
    my $arg1 = ReadingsVal($name, $cmd, 0); # Command-Argument

    if($cmd eq "actuator") {
      $msg = sprintf("%02X000000", $arg1);

    } elsif($cmd eq "desired-temp") {
      $msg = sprintf("%02X%02X0400", $arg1*255/40, 
                     AttrVal($name, "actualTemp", ($db_1*40/255)) * 255/40);

    } elsif($cmd eq "initialize") {
      $msg = sprintf("00006400");

    }

    if($msg) {
      select(undef, undef, undef, 0.2);
      EnOcean_A5Cmd($hash, $msg, "00000000");
      if($cmd eq "initialize") {
        delete($defs{$name}{READINGS}{CMD});
        delete($defs{$name}{READINGS}{$cmd});
      }
    }
  }
}

sub
EnOcean_A5Cmd($$$)
{
  my ($hash, $msg, $org) = @_; 
  IOWrite($hash, "000A0701", # varLen=0A optLen=07 msgType=01=radio, 
          sprintf("A5%s%s0001%sFF00",$msg,$org,$hash->{DEF}));
          # type=A5 msg:4 senderId:4 status=00 subTelNum=01 destId:4 dBm=FF Security=00
}

1;

=pod
=begin html

<a name="EnOcean"></a>
<h3>EnOcean</h3>
<ul>
  Devices sold by numerous hardware verndors (e.g. Eltako, Peha, etc), using
  the RF Protocol provided by the EnOcean Alliance.
  <br><br>
  <a name="EnOceandefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EnOcean &lt;ID&gt;</code>
    <br><br>

    Define an EnOcean device, connected via a <a href="#TCM">TCM</a>. The
    &lt;ID&gt; parameter is an 8 digit hex number. For remotes and sensors the
    <a href="#autocreate">autocreate</a> module may help you.<br>

    Example:
    <ul>
      <code>define switch1 EnOcean ffc54500</code><br>
    </ul>
  </ul>
  <br>

  <a name="EnOceanset"></a>
  <b>Set</b>
  <ul>
    <br>
    <li>MD15 commands. Note: The command is not sent until the MD15
    wakes up and sends a mesage, usually every 10 minutes.
    <ul>
      <li>actuator &lt;value&gt;<br>
         Set the actuator to the specifed percent value (0-100)</li>
      <li>desired-temp &lt;value&gt;<br>
         Use the builtin PI regulator, and set the desired temperature to the
         specified degree. The actual value will be taken from the temperature
         reported by the MD15 or from the attribute actualTemp if it is set</li>
      <li>unattended<br>
         Do not regulate the MD15.</li>
    </ul></li>

    <li>subType eltakoDimmer, tested with Eltako devices only
    <ul>
      <li>teach<br>
        initiate teach-in mode</li>
      <li>dimm percent [time 1-100]<br>
        issue dim command.</li>
      <li>dimmup percent [time 1-100]<br>
        issue dim command.</li>
      <li>dimmdown percent [time 1-100]<br>
        issue dim command.</li>
      <li>dimm on<br>
        issue switch on command.</li>
      <li>dimm off<br>
        issue switch off command.</li>
    </ul>
    </li>
	
    <li>subType eltakoShutter, tested with Eltako devices only
    <ul>
      <li>teach<br>
        initiate teach-in mode</li>
      <li>up [percent]<br>
        issue roll up command.</li>
      <li>down [percent]<br>
        issue roll down command.</li>
      <li>stop<br>
        issue stop command.</li>
    </ul>
    </li>

    <li>all other:
    <ul>
    <code>set switch1 &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of A0,AI,B0,BI,C0,CI,D0,DI, combinations of
    these and released, in fact we are trying to emulate a PTM100 type remote.
    <br>

    If you define an <a href="#eventMap">eventMap</a> attribute with on/off,
    then you'll be able to easily set the device from the <a
    href="#FHEMWEB">WEB</a> frontend.<br><br>
    In order to control devices, you cannot reuse the ID's of other devices
    (like remotes), instead you have to create your own, which must be in the
    allowed ID-Range of the underlying IO device. For this first query the
    TCM with the "<code>get &lt;tcm&gt; idbase</code>" command. You can use
    up to 128 ID's starting with the base shown there. If you are using an
    ID outside of the allowed range, you'll see an ERR_ID_RANGE message in the
    fhem log.<br>

    Example:
    <ul><code>
      set switch1 BI<br>
      set switch1 B0,CI<br>
      attr eventMap BI:on B0:off<br>
      set switch1 on<br>
    </code></ul>
    <b>Note</b>: <a href="#setExtensions">set extensions</a> are supported,
        if the corresponding <a href="#eventMap">eventMap</a> specifies 
        the on and off mappings.
    <br>
    </li>

    </ul>
  </ul>
  <br>

  <a name="EnOceanget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="EnOceanattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#model">model</a></li>
    <li><a href="#subType">subType</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a name="actualTemp">actualTemp</a><br>
      The value of the actual temperature, used when controlling MD15 devices.
      Should by filled via a notify from a distinct temperature sensor. If
      absent, the reported temperature from the MD15 is used.
      </li>
  </ul>
  <br>

  <a name="EnOceanevents"></a>
  <b>Generated events:</b>
  <ul>
     <li>switch. Switches (remotes) with more than one (pair) of buttons
         are separate devices with separate address.
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>C0</li>
         <li>CI</li>
         <li>D0</li>
         <li>DI</li>
         <li>A0,BI</li>
         <li>&lt;BtnX,BtnY&gt; where BtnX and BtnY is one of the above, e.g.
             A0,BI or D0,CI</li>
         <li>buttons:released</li>
         <li>buttons:<BtnX> released</li>
         <br>
     </ul></li>

     <li>FSB61/FSM61 (set model to FSB61 or FSM61 manually)<br>
     <ul>di
        <li>released<br>
          The status of the device may become "released", this is not the case
          for a normal switch.</li>
     </ul></li>

     <li>windowHandle (HOPPE SecuSignal). Set the subType attr to windowHandle.
     <ul>
         <li>closed</li>
         <li>open</li>
         <li>tilted</li>
         <li>open from tilted</li>
     </ul></li>

     <li>keycard. Set the subType attr to keycard. (untested)
     <ul>
         <li>keycard inserted</li>
         <li>keycard removed</li>
     </ul></li>

     <li>STM-250 Door and window contact.
     <ul>
         <li>closed</li>
         <li>open</li>
         <li>learnBtn: on</li>
     </ul></li>

     <li>SR04* (Temp sensor + Presence button and desired temp dial).<br>
          Set the
          model attribute to one of SR04 SR04P SR04PT SR04PST SR04PMS or the
          subType attribute to SR04.
     <ul>
         <li>temperature: XY.Z</li>
         <li>set_point: [0..255]</li>
         <li>fan: [0|1|2|3|Auto]</li>
         <li>present: yes</li>
         <li>learnBtn: on</li>
         <li>T: XY.Z SP: [0..255] F: [0|1|2|3|Auto] P: [yes|no]</li>
     </ul></li>

     <li>MD15-FtL-HE (Heating/Valve-regulator)<br>
         The subType attibute must be MD15. This is done if the device was created by
         autocreate.<br>
     <ul>
       <li>$actuator %</li>
       <li>currentValue: $actuator</li>
       <li>serviceOn: [yes|no]</li>
       <li>energyInput: [enabled|disabled]</li>
       <li>energyStorage: [charged|empty]</li>
       <li>battery: [ok|empty]</li>
       <li>cover: [open|closed]</li>
       <li>tempSensor: [failed|ok]</li>
       <li>window: [open|closed]</li>
       <li>actuator: [ok|obstructed]</li>
       <li>temperature: $tmp</li>
     </ul></li>

     <li>Ratio Presence Sensor Eagle PM101.<br>
         Set the model attribute to PM101<br>
     <ul>
       <li>brightness: $lux</li>
       <li>channel1: [on|off]</li>
       <li>channel2: [on|off]</li>
     </ul></li>

     <li>FAH60,FAH63,FIH63 brigthness senor.<br>
         Set subType to FAH or model to FAH60/FAH63/FIH63 manually.<br>
     <ul>
       <li>brightness: $lux</li>
       <li>state: $lux</li>
     </ul></li>

     <li>FABH63,FBH55,FBH63,FIBH63 Motion/brightness sensor.<br>
         Set subType to FBH or model to FABH63/FBH55/FBH63/FIBH63 manually.<br>
     <ul>
       <li>brightness: $lux</li>
       <li>motion:[yes|no]</li>
       <li>state: [motion: yes|no]</li>
     </ul></li>

     <li>FTF55 Temperature sensor.<br>
         Set subType to FTF or model to FTF55 manually.<br>
     <ul>
       <li>temperature: $temp</li>
       <li>state: $temp</li>
     </ul></li>

     <li>eltakoDimmer<br>
     <ul>
     </ul></li>
     
     <li>eltakoShutter<br>
     <ul>
        <li>B0<br>
          The status of the device will become B0 after the TOP endpoint is
          reached, or it has finished an "up %%" command.</li>
        <li>BI<br>
          The status of the device will become BI if the BOTTOM endpoint is
          reached</li>
        <li>released<br>
          The status of the device may become "released", this is not the case
          for a normal switch.</li>
     </ul></li>

  </ul>
</ul>

=end html
=cut
