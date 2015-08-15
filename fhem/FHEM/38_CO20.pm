
# $Id$

# basic idea from http://code.google.com/p/airsensor-linux-usb

package main;

use strict;
use warnings;

use Device::USB;

sub
CO20_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "CO20_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "CO20_Notify";
  $hash->{UndefFn}  = "CO20_Undefine";
  $hash->{SetFn} = "CO20_Set";
  $hash->{GetFn}    = "CO20_Get";
  $hash->{AttrFn}   = "CO20_Attr";
  $hash->{AttrList} = "disable:1 ".
                      "advanced:1 ".
                      "interval ".
                      "retries ".
                      "timeout ".
                      $readingFnAttributes;
}

#####################################

sub
CO20_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> CO20 [bus:device]"  if(@a < 2);

  delete $hash->{ID};

  my $name = $a[0];

  $hash->{tag} = undef;
  $hash->{ID} = $a[2] if( defined($a[2]));

  $hash->{NAME} = $name;

  $hash->{fail} = 0;
  $hash->{seq2} = 0x67;
  $hash->{seq4} = 0x0001;

  if( $init_done ) {
    CO20_Disconnect($hash);
    CO20_Connect($hash);
  } elsif( $hash->{STATE} ne "???" ) {
    $hash->{STATE} = "Initialized";
  }

  return undef;
}

sub
CO20_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  CO20_Connect($hash);
}

my $VENDOR = 0x03eb;
my $PRODUCT = 0x2013;


sub
CO20_SetStickData($$)
{

  my ($hash, $data) = @_;
  my $name = $hash->{NAME};

  my $strlen = length($data);
  my $ind = 0;
Log3 $name, 5, "datalen $strlen";

  if($strlen == 240) {
    $ind = index($data, "warn1")+22;
    $hash->{KNOB_CO2_VOC_level_warn1} = ord(substr($data,$ind+1,1))*256 + ord(substr($data,$ind,1));
    $ind = index($data, "warn2")+22;
    $hash->{KNOB_CO2_VOC_level_warn2} = ord(substr($data,$ind+1,1))*256 + ord(substr($data,$ind,1));
    $ind = index($data, "Reg_Set")+20;
    $hash->{KNOB_Reg_Set} = ord(substr($data,$ind+1,1))*256 + ord(substr($data,$ind,1));
    $ind = index($data, "Reg_P")+19;
    $hash->{KNOB_Reg_P} = ord(substr($data,$ind+1,1))*256 + ord(substr($data,$ind,1));
    $ind = index($data, "Reg_I")+19;
    $hash->{KNOB_Reg_I} = ord(substr($data,$ind+1,1))*256 + ord(substr($data,$ind,1));
    $ind = index($data, "Reg_D")+19;
    $hash->{KNOB_Reg_D} = ord(substr($data,$ind+1,1))*256 + ord(substr($data,$ind,1));
    $ind = index($data, "LogInterval")+27;
    $hash->{KNOB_LogInterval} = ord(substr($data,$ind+1,1))*256 + ord(substr($data,$ind,1));
    $ind = index($data, "ui16StartupBits")+30;
    $hash->{KNOB_ui16StartupBits} = ord(substr($data,$ind+1,1))*256 + ord(substr($data,$ind,1));
  } elsif($strlen == 32) {
    $ind = index($data, ";");
    $hash->{FLAG_WARMUP} = ord(substr($data,$ind+3,1))*256 + ord(substr($data,$ind+2,1));
    $hash->{FLAG_BURN_IN} = ord(substr($data,$ind+7,1))*256 + ord(substr($data,$ind+6,1));
    $hash->{FLAG_RESET_BASELINE} = ord(substr($data,$ind+11,1))*256 + ord(substr($data,$ind+10,1));
    $hash->{FLAG_CALIBRATE_HEATER} = ord(substr($data,$ind+15,1))*256 + ord(substr($data,$ind+14,1));
    $hash->{FLAG_LOGGING} = ord(substr($data,$ind+19,1))*256 + ord(substr($data,$ind+18,1));
  } elsif($strlen == 1) {
    delete( $hash->{KNOB_CO2_VOC_level_warn1} );
    delete( $hash->{KNOB_CO2_VOC_level_warn2} );
    delete( $hash->{KNOB_Reg_Set} );
    delete( $hash->{KNOB_Reg_P} );
    delete( $hash->{KNOB_Reg_I} );
    delete( $hash->{KNOB_Reg_D} );
    delete( $hash->{KNOB_LogInterval} );
    delete( $hash->{KNOB_ui16StartupBits} );
    delete( $hash->{FLAG_WARMUP} );
    delete( $hash->{FLAG_BURN_IN} );
    delete( $hash->{FLAG_RESET_BASELINE} );
    delete( $hash->{FLAG_CALIBRATE_HEATER} );
    delete( $hash->{FLAG_LOGGING} );
  }

  return undef;
}

sub
CO20_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  $hash->{USB} = Device::USB->new() if( !$hash->{USB} );

  if( $hash->{ID} && $hash->{ID} =~ m/(\d.*):(\d.*)/ ) {
    my $dirname = $1;
    my $filename = $2;
    delete $hash->{DEV};
    foreach my $bus ($hash->{USB}->list_busses()) {
      next if( $bus->{dirname} != $dirname );

      foreach my $device (@{$bus->{devices}}) {
        next if( $device->idVendor() != $VENDOR );
        next if( $device->idProduct() != $PRODUCT );
        next if( $device->{filename} != $filename );
        $hash->{DEV} = $device;
        last;
      }
      last if( $hash->{DEV} );
    }

  } else {
    $hash->{DEV} = $hash->{USB}->find_device( $VENDOR, $PRODUCT );
  }

  if( $hash->{DEV} ) {
    $hash->{STATE} = "found";
    Log3 $name, 3, "$name: CO20 device found";

    $hash->{DEV}->open();

    $hash->{manufacturer} = $hash->{DEV}->manufacturer();
    $hash->{product} = $hash->{DEV}->product();

    if( $hash->{manufacturer} && $hash->{product} ) {
       $hash->{DEV}->detach_kernel_driver_np(0) if( $hash->{DEV}->get_driver_np(0) );
       my $ret = $hash->{DEV}->claim_interface( 0 );
       if( $ret == -16 ) {
         $hash->{STATE} = "waiting";
         Log3 $name, 3, "$name: waiting for CO20 device";
         return;
       } elsif( $ret != 0 ) {
         Log3 $name, 3, "$name: failed to claim CO20 device";
         CO20_Disconnect($hash);
         return;
       }

      $hash->{STATE} = "opened";
      Log3 $name, 3, "$name: CO20 device opened";

      my $interval = AttrVal($name, "interval", 300);
      $hash->{retries} = AttrVal($name,"retries",3);
      $hash->{timeout} = AttrVal($name,"timeout",10);

      $hash->{INTERVAL} = $interval;

      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+10, "CO20_poll", $hash, 0);

      my $buf;
      $hash->{DEV}->interrupt_read(0x00000081, $buf, 0x0000010, 1000);

    } else {
      Log3 $name, 3, "$name: failed to open CO20 device";
      CO20_Disconnect($hash);
    }
  } else {
    Log3 $name, 3, "$name: failed to find CO20 device";
  }
}

sub
CO20_Disconnect($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash);

  return if( !$hash->{USB} );
  if( $hash->{manufacturer} && $hash->{product} ) {
    $hash->{DEV}->release_interface(0);
  }

  delete( $hash->{USB} );
  delete( $hash->{DEV} );
  delete( $hash->{manufacturer} );
  delete( $hash->{product} );

  delete( $hash->{BLOCKED} );
  delete $hash->{FIRMWARE};
  CO20_SetStickData($hash,"X");

  $hash->{STATE} = "disconnected";
  Log3 $name, 3, "$name: disconnected";
}

sub
CO20_Undefine($$)
{
  my ($hash, $arg) = @_;

  CO20_Disconnect($hash);
  $hash->{fail} = 0;

  return undef;
}

sub
CO20_identify($)
{
  my ($hash) = @_;
  CO20_dataread($hash,"stickdata");
}

sub
CO20_poll($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "CO20_poll", $hash, 0);
  }

  if($hash->{BLOCKED}) {
    return undef;
  }

  if( $hash->{manufacturer} && $hash->{product} ) {



    my $buf = "@".sprintf("%c",$hash->{seq2})."TRF?\n@@@@@@@@@";

    Log3 $name, 5, "$name: sent $buf / ".ord(substr($buf,0,1));

    my $ret = $hash->{DEV}->interrupt_write(0x00000002, $buf, 0x0000010, $hash->{timeout});
    if( $ret != 16 ) {
      my $ret2 = $hash->{DEV}->interrupt_write(0x00000002, "@@@@@@@@@@@@@@@@", 0x0000010, $hash->{timeout});
      $hash->{fail} = $hash->{fail}+1;
      Log3 $name, 4, "$name: write error $ret/$ret2 ($hash->{fail})";
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+30, "CO20_poll", $hash, 1);
      if($hash->{fail} >= $hash->{retries}) {
        $hash->{fail} = 0;
        CO20_Disconnect($hash);
        $hash->{RECONNECT} = 1;
        CO20_Connect($hash);
      }
      return undef;
    }
    if ($hash->{seq2} < 0xFF){ $hash->{seq2}++} else {$hash->{seq2} = 0x67};

my $data="";
for( $a = 1; $a <= 3; $a = $a + 1 ){
    $ret=$hash->{DEV}->interrupt_read(0x00000081, $buf, 0x0000010, $hash->{timeout});
    if( $ret != 16 and $ret != 0 ) {
      Log3 $name, 4, "$name: read error $ret";
    }
    $data.=$buf;
}
Log3 $name, 4, "$name got $data / ".length($data)." / ".ord(substr($data,0,1));

    if( $ret != 16 and $ret != 0 and length($data) < 16 ) {
      $hash->{fail} = $hash->{fail}+1;
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+30, "CO20_poll", $hash, 1);
      Log3 $name, 4, "$name: readloop error $ret ($hash->{fail})";
      if($hash->{fail} >= $hash->{retries}) {
        $hash->{fail} = 0;
        CO20_Disconnect($hash);
        $hash->{RECONNECT} = 1;
        CO20_Connect($hash);
      }
      return undef;
    }


    if(  length($data) >= 16 ) {

      $data = "@".$data if(ord(substr($data,0,1)) > 64);

      $hash->{fail} = 0;
      my $voc = ord(substr($data,3,1))*256 + ord(substr($data,2,1));
      my $dbg = ord(substr($data,5,1))*256 + ord(substr($data,4,1));
      my $pwm = ord(substr($data,7,1))*256 + ord(substr($data,6,1));
      my $rh = ord(substr($data,9,1))*256 + ord(substr($data,8,1));
      my $rs = ord(substr($data,14,1))*65536 + ord(substr($data,13,1))*256 + ord(substr($data,12,1));
      if (ord(substr($data,3,1)) < 128) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "voc", $voc, 1 );
        readingsBulkUpdate( $hash, "debug", $dbg, 1 );
        readingsBulkUpdate( $hash, "pwm", $pwm, 1 );
        readingsBulkUpdate( $hash, "r_h", $rh/100, 1 );
        readingsBulkUpdate( $hash, "r_s", $rs, 1 );
        readingsEndUpdate($hash,1);
      }

#my $bufdec = ord(substr($buf,0,1))." ".ord(substr($buf,1,1))." ".ord(substr($buf,2,1))." ".ord(substr($buf,3,1))." ".ord(substr($buf,4,1))." ".ord(substr($buf,5,1))." ".ord(substr($buf,6,1))." ".ord(substr($buf,7,1))." ".ord(substr($buf,8,1))." ".ord(substr($buf,9,1))." ".ord(substr($buf,10,1))." ".ord(substr($buf,11,1))." ".ord(substr($buf,12,1))." ".ord(substr($buf,13,1))." ".ord(substr($buf,14,1))." ".ord(substr($buf,15,1))." ".ord(substr($buf,16,1));
#      Log3 $name, 5, "$name: read 1 success\n$bufdec";


    } else {
      $hash->{fail} = $hash->{fail}+1;
      Log3 $name, 2, "$name: read failed $ret ($hash->{fail})";
      if($hash->{fail} >= $hash->{retries}) {
        $hash->{fail} = 0;
      CO20_Disconnect($hash);
        $hash->{RECONNECT} = 1;
      CO20_Connect($hash);
    }
    }

    $hash->{LAST_POLL} = FmtDateTime( gettimeofday() );
  } else {
    Log3 $name, 2, "$name: no device";
    $hash->{fail} = 0;
    CO20_Disconnect($hash);
    $hash->{RECONNECT} = 1;
    CO20_Connect($hash);
  }
}


sub
CO20_dataread($$)
{
  my ($hash, $readingstype) = @_;
  my $name = $hash->{NAME};


  my $reqstr = "";
  my $retcount = 16;
  if($readingstype eq "knobdata") {
    $reqstr = "KNOBPRE?";
    $retcount = 16;
  } elsif ($readingstype eq "flagdata") {
    $reqstr = "FLAGGET?";
    $retcount = 3;
  } elsif ($readingstype eq "stickdata") {
    $reqstr = "*IDN?";
    $retcount = 8;
  } else {
    return undef;
  }

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "CO20_poll", $hash, 1);

  if( $hash->{manufacturer} && $hash->{product} ) {



    my $seq = sprintf("%04X",$hash->{seq4});
    my $seqstr = sprintf("%c",hex substr($seq,2,2)).sprintf("%c",hex substr($seq,0,2));
    $hash->{seq4} = ($hash->{seq4} +1) & 0xFFFF;

    my $buf = substr("@".$seq.$reqstr."\n@@@@@@@@@@@@@@@@",0,16);
    my $ret = $hash->{DEV}->interrupt_write(0x00000002, $buf, 0x0000010, $hash->{timeout});
Log3 $name, 4, "getdata write $ret" if($ret != 16);


my $data = "";
my $intdata = "";
if($ret == 16) {
for( $a = 1; $a <= $retcount; $a = $a + 1 ){
    $hash->{DEV}->interrupt_read(0x00000081, $buf, 0x0000010, $hash->{timeout});
    $data.=$buf;
Log3 $name, 4, "getdata read $ret" if($ret != 16);
      $intdata = ord(substr($buf,0,1))." ".ord(substr($buf,1,1))." ".ord(substr($buf,2,1))." ".ord(substr($buf,3,1))." ".ord(substr($buf,4,1))." ".ord(substr($buf,5,1))." ".ord(substr($buf,6,1))." ".ord(substr($buf,7,1))." ".ord(substr($buf,8,1))." ".ord(substr($buf,9,1))." ".ord(substr($buf,10,1))." ".ord(substr($buf,11,1))." ".ord(substr($buf,12,1))." ".ord(substr($buf,13,1))." ".ord(substr($buf,14,1))." ".ord(substr($buf,15,1));
Log3 $name, 5, "$intdata\n$buf";
}
Log3 $name, 5, length($data);

}


  if($readingstype eq "knobdata") {
    CO20_SetStickData($hash,$data);
  } elsif ($readingstype eq "flagdata") {
    CO20_SetStickData($hash,$data);
  } elsif ($readingstype eq "stickdata") {
    if ($data =~ /\bStick\b(.*?)\bMCU\b/) {
      $hash->{FIRMWARE} = $1;
    }
    if ($data =~ /\bS\/N:\b(.*?)\b;bI\b/) {
      $hash->{SERIALNUMBER} = $1;
    }
  }


  }

}


sub
CO20_flashread($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};


# 40 30 30 31 31 52 45 43 4F 52 44 53 3F 0A 40 40   @0011RECORDS?.@@
#
# 40 30 30 31 32 4C 42 53 49 5A 45 3F 0A 40 40 40   @0012LBSIZE?.@@@
#
# 40 30 30 31 33 46 4C 53 54 4F 50 0A 40 40 40 40   @0013FLSTOP.@@@@
#
# 40 30 30 31 34 4C 42 53 49 5A 45 3F 0A 40 40 40   @0014LBSIZE?.@@@
#
# 40 30 30 31 35 2A 49 44 4E 3F 0A 40 40 40 40 40   @0015*IDN?.@@@@@
#
# 40 30 30 31 36 4C 42 41 56 47 3B 31 30 30 0A 40   @0016LBAVG;100.@
#
# 40 6A 4C 42 52 0A 40 40 40 40 40 40 40 40 40 40   @jLBR.@@@@@@@@@@ n times ?
#
# 40 30 30 31 37 46 4C 53 54 41 52 54 0A 40 40 40   @0017FLSTART.@@@ n times ?
#
# 2 reads each






}

sub
CO20_dataset($$$)
{
  my ($hash, $cmd, $val) = @_;
  my $name = $hash->{NAME};

  my $reqstr = "";
  if($cmd eq "flag_WARMUP") {
    $reqstr = "FLAGSET;WARMUP="; # 0000
  } elsif($cmd eq "flag_BURN-IN") {
    $reqstr = "FLAGSET;BURN-IN="; # 0000
  } elsif($cmd eq "flag_RESET_BASELINE") {
    $reqstr = "FLAGSET;RESET BASELINE="; # 0000
  } elsif($cmd eq "flag_CALIBRATE_HEATER") {
    $reqstr = "FLAGSET;CALIBRATE HEATER="; # 0000
  } elsif($cmd eq "flag_LOGGING") {
    $reqstr = "FLAGSET;LOGGING="; # 0000
  } elsif($cmd eq "knob_CO2/VOC_level_warn1") {
    $reqstr = "KNOBSET;CO2/VOC level_warn1=";
  } elsif($cmd eq "knob_CO2/VOC_level_warn2") {
    $reqstr = "KNOBSET;CO2/VOC level_warn2=";
  } elsif($cmd eq "knob_Reg_Set") {
    $reqstr = "KNOBSET;Reg_Set="; # 9100
  } elsif($cmd eq "knob_Reg_P") {
    $reqstr = "KNOBSET;Reg_P="; # 0300
  } elsif($cmd eq "knob_Reg_I") {
    $reqstr = "KNOBSET;Reg_I="; # 0A00
  } elsif($cmd eq "knob_Reg_D") {
    $reqstr = "KNOBSET;Reg_D="; # 0000
  } elsif($cmd eq "knob_LogInterval") {
    $reqstr = "KNOBSET;LogInterval="; # 0000
  } elsif($cmd eq "knob_ui16StartupBits") {
    $reqstr = "KNOBSET;ui16StartupBits="; # 0000
  } elsif($cmd eq "recalibrate_heater") {
    $reqstr = "FLAGSET;CALIBRATE HEATER="; # 0180
  } elsif($cmd eq "reset_baseline") {
    $reqstr = "FLAGSET;RESET BASELINE="; # 0180
  } elsif($cmd eq "reset_device") {
    $reqstr = "*RST";
  }

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "CO20_poll", $hash, 1);

  if( $hash->{manufacturer} && $hash->{product} ) {

    my $seq = sprintf("%04X",$hash->{seq4});
    $hash->{seq4} = ($hash->{seq4} +1) & 0xFFFF;

    my $buf = "@".$seq.$reqstr;
    if($cmd ne "reset_device") {
      $buf .= "\x02";
      if($cmd eq "recalibrate_heater" or $cmd eq "reset_baseline") {
        $buf .= "\x01\x80";
      } else {
        my $h = sprintf("%04X",$val & 0xFFFF);
        $buf .= sprintf("%c",hex substr($h,2,2)).sprintf("%c",hex substr($h,0,2));
Log3 $name, 5, "$val $h \n";
      }
    }
    if (index($reqstr, "KNOBSET") != -1) {
      $buf .= ";";
    }
    $buf .= "\n";

    my $buflen = length($buf);
    $buf .= "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@";


    my $ret = $hash->{DEV}->interrupt_write(0x00000002, substr($buf,0,16), 0x0000010, $hash->{timeout});
    Log3 $name, 4, "setdata write $ret" if($ret != 16);


    if($ret == 16 and ($buflen > 16 or $cmd eq "reset_device")) {
      $ret = $hash->{DEV}->interrupt_write(0x00000002, substr($buf,16,16), 0x0000010, $hash->{timeout});
      Log3 $name, 4, "setdata write $ret" if($ret != 16);
    }

    if($ret == 16 and $buflen > 32) {
      $ret = $hash->{DEV}->interrupt_write(0x00000002, substr($buf,32,16), 0x0000010, $hash->{timeout});
      Log3 $name, 4, "setdata write $ret" if($ret != 16);
    }


    if($ret == 16) {
      $hash->{DEV}->interrupt_read(0x00000081, $buf, 0x0000010, $hash->{timeout});
      Log3 $name, 5, "getdata read $ret";
      my $intdata .= ord(substr($buf,0,1))." ".ord(substr($buf,1,1))." ".ord(substr($buf,2,1))." ".ord(substr($buf,3,1))." ".ord(substr($buf,4,1))." ".ord(substr($buf,5,1))." ".ord(substr($buf,6,1))." ".ord(substr($buf,7,1))." ".ord(substr($buf,8,1))." ".ord(substr($buf,9,1))." ".ord(substr($buf,10,1))." ".ord(substr($buf,11,1))." ".ord(substr($buf,12,1))." ".ord(substr($buf,13,1))." ".ord(substr($buf,14,1))." ".ord(substr($buf,15,1));
      Log3 $name, 4, "$buf";
    } else {
      Log3 $name, 4, "set data failed: $buf";
      return undef;
    }





  }




     return undef;


}

sub
CO20_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "update:noArg";
  $list = "update:noArg air_data:noArg knob_data:noArg flag_data:noArg stick_data:noArg" if( AttrVal($name, "advanced", 0 ) == 1 );

  if( $cmd eq "air_data" or $cmd eq "update" ) {
      $hash->{LOCAL} = 1;
      CO20_poll($hash);
      delete $hash->{LOCAL};
      return undef;
  } elsif( $cmd eq "knob_data" ) {
      $hash->{BLOCKED} = 1;
      CO20_dataread($hash,"knobdata");
      delete $hash->{BLOCKED};
      return undef;
  } elsif( $cmd eq "flag_data" ) {
      $hash->{BLOCKED} = 1;
      CO20_dataread($hash,"flagdata");
      delete $hash->{BLOCKED};
      return undef;
  } elsif( $cmd eq "stick_data" ) {
      $hash->{BLOCKED} = 1;
      CO20_dataread($hash,"stickdata");
      delete $hash->{BLOCKED};
      return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
CO20_Set($$$$)
{
  my ($hash, $name, $cmd, $val) = @_;

  my $list = "";
 $list = "flag_WARMUP flag_BURN-IN flag_RESET_BASELINE flag_CALIBRATE_HEATER flag_LOGGING knob_CO2/VOC_level_warn1 knob_CO2/VOC_level_warn2 knob_Reg_Set knob_Reg_P knob_Reg_I knob_Reg_D knob_LogInterval knob_ui16StartupBits recalibrate_heater:noArg reset_baseline:noArg reset_device:noArg" if( AttrVal($name, "advanced", 0 ) == 1 );
  if (index($list, $cmd) != -1) {
      $hash->{BLOCKED} = 1;
      CO20_dataset($hash,$cmd,$val);
      delete $hash->{BLOCKED};
      return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
CO20_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval" || $attrName eq "retries" || $attrName eq "timeout");
  $attrVal = 30 if($attrName eq "interval" && $attrVal < 30 && $attrVal != 0);
  $attrVal = 3 if($attrName eq "retries" && ($attrVal < 0 || $attrVal > 60));
  $attrVal = 1000 if($attrName eq "timeout" && ($attrVal < 500 || $attrVal > 10000));

  if( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" && $attrVal ne "0" ) {
      CO20_Disconnect($hash);
    } else {
      $attr{$name}{$attrName} = 0;
      CO20_Disconnect($hash);
      CO20_Connect($hash);
    }
  } elsif( $attrName eq "interval" ) {
    my $hash = $defs{$name};
    $hash->{INTERVAL} = $attrVal;
    CO20_poll($hash) if( $init_done );
  } elsif( $attrName eq "retries" ) {
    my $hash = $defs{$name};
    $hash->{retries} = $attrVal;
  } elsif( $attrName eq "timeout" ) {
    my $hash = $defs{$name};
    $hash->{timeout} = $attrVal;
  }

  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}

1;

=pod
=begin html

<a name="CO20"></a>
<h3>CO20</h3>
<ul>
  Module for measuring air quality with usb sticks based on the AppliedSensor iAQ-Engine sensor.
  Products currently know to work are the VOLTCRAFT CO-20, the Sentinel Haus Institut RaumluftW&auml;chter
  and the VELUX Raumluftf&uuml;hler.<br>
  Probably works with all devices recognized as iAQ Stick (0x03eb:0x2013).<br><br>

  Notes:
  <ul>
    <li>Device::USB hast to be installed on the FHEM host.<br>
        It can be installed with '<code>cpan install Device::USB</code>'<br>
        or on debian with '<code>sudo apt-get install libdevice-usb-perl'</code>'</li>
    <li>FHEM has to have permissions to open the device. To configure this with udev
        rules see here: <a href="https://code.google.com/p/usb-sensors-linux/wiki/Install_AirSensor_Linux">Install_AirSensor_Linux
usb-sensors-linux</a></li>
    <li>Advanced features are only available after setting the attribute <i>advanced</i>.<br>
        Almost all the hidden settings from the Windows application are implemented in this mode.<br>
        Readout of values gathered in standalone mode is not possible yet.</li>
  </ul><br>

  <a name="CO20_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CO20 [bus:device]</code><br>
    <br>

    Defines a CO20 device. bus:device hast to be used if more than one sensor is connected to the same host.<br><br>

    Examples:
    <ul>
      <code>define CO20 CO20</code><br>
    </ul>
  </ul><br>

  <a name="CO20_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>voc<br>
      CO2 equivalents in ppm</li>
    <li>debug<br>
      debug value</li>
    <li>pwm<br>
      pwm value</li>
    <li>r_h<br>
      resistance of heating element in Ohm (?)</li>
    <li>r_s<br>
      resistance of sensor element in Ohm (?)</li>
  </ul><br>

  <a name="CO20_Get"></a>
  <b>Get</b>
  <ul>
    <li>update / air_data<br>
      trigger an update</li>
    <li>flag_data<br>
      get internal flag values</li>
    <li>knob_data<br>
      get internal knob values</li>
    <li>stick_data<br>
      get stick information</li>
  </ul><br>

  <a name="CO20_Set"></a>
  <b>Set</b>
  <ul>
    <li>KNOB_CO2_VOC_level_warn1<br>
      sets threshold for yellow led</li>
    <li>KNOB_CO2_VOC_level_warn2<br>
      sets threshold for red led</li>
    <li>KNOB_Reg_Set<br>
      internal value, affects voc reading</li>
    <li>KNOB_Reg_P<br>
      internal pid value</li>
    <li>KNOB_Reg_I<br>
      internal pid value</li>
    <li>KNOB_Reg_D<br>
      internal pid value</li>
    <li>KNOB_LogInterval<br>
      log interval for standalone mode</li>
    <li>KNOB_ui16StartupBits<br>
      set to 0 for no automatic calibration on startup</li>
    <li>FLAG_WARMUP<br>
      warmup time left in minutes</li>
    <li>FLAG_BURN_IN<br>
      burn in time left in minutes</li>
    <li>FLAG_RESET_BASELINE<br>
      reset voc baseline value</li>
    <li>FLAG_CALIBRATE_HEATER<br>
      trigger calibration / burn in</li>
    <li>FLAG_LOGGING<br>
      value count from external logging</li>
  </ul><br>

  <a name="CO20_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>interval<br>
      the interval in seconds used to read updates. the minimum and default ist 60.</li>
    <li>advanced<br>
      1 -> enables most of the advanced settings and readings described here</li>
    <li>disable<br>
      1 -> disconnect and stop polling</li>
  </ul>
</ul>

=end html
=cut
