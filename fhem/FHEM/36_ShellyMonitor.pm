##############################################
# 36_ShellyMonitor.pm
#
# Parses the MultiCast "COAP" messages of Shellys and updates
# devices accordingly
#
# $Id$
#

package main;
use strict;
use warnings;
no warnings 'portable';  # Support for 64-bit ints required

use vars qw{%attr %defs};

my $COIOT_OPTION_GLOBAL_DEVID = 3332;
my $COIOT_OPTION_STATUS_VALIDITY = $COIOT_OPTION_GLOBAL_DEVID+80;
my $COIOT_OPTION_STATUS_SERIAL = $COIOT_OPTION_GLOBAL_DEVID+88;

my $SHELLY_DEF_SEN = {
# Old version 1:
"111" => { "type"=>"P", "desc"=>"power_0", "unit"=>"W"},
"121" => { "type"=>"P", "desc"=>"power_1", "unit"=>"W"},
"131" => { "type"=>"P", "desc"=>"power_2", "unit"=>"W"},
"141" => { "type"=>"P", "desc"=>"power_3", "unit"=>"W"},
"112" => { "type"=>"S", "desc"=>"output_0"},
"122" => { "type"=>"S", "desc"=>"output_1"},
"132" => { "type"=>"S", "desc"=>"output_2"},
"142" => { "type"=>"S", "desc"=>"output_3"},
"113" => { "type"=>"T", "desc"=>"deviceTemp", "unit"=>"C"},
"114" => { "type"=>"T", "desc"=>"deviceTemp", "unit"=>"F"},
"214" => { "type"=>"E", "desc"=>"energy_0", "unit"=>"Wmin"},
# Version 2, since FW >= 1.6
"1101" => { "type"=>"S", "desc"=>"output_0"},
# Used by Shelly 2 SHSW-21 roller-mode, Shelly 2.5 SHSW-25 roller-mode:
"1102" => { "type"=>"S", "desc"=>"roller"},
# Used by Shelly 2 SHSW-21 roller-mode, Shelly 2.5 SHSW-25 roller-mode:
"1103" => { "type"=>"S", "desc"=>"rollerPos"},
# Used by Shelly Air SHAIR-1:
"1104" => { "type"=>"S", "desc"=>"totalWorkTime", "unit"=>"s"},
# Used by Shelly Gas SHGS-1:
"1105" => { "type"=>"S", "desc"=>"valve"},
# Used by Shelly 2.5 SHSW-25 relay-mode, Shelly 2 SHSW-21 relay-mode, Shelly RGBW2-white SHRGBW2-white, Shelly 2LED SH2LED-1:
"1201" => { "type"=>"S", "desc"=>"output_1"},
# Used by Shelly RGBW2-white SHRGBW2-white:
"1301" => { "type"=>"S", "desc"=>"output_2"},
# Used by Shelly RGBW2-white SHRGBW2-white:
"1401" => { "type"=>"S", "desc"=>"output_3"},
"2101" => { "type"=>"S", "desc"=>"input_0"},
"2102" => { "type"=>"EV", "desc"=>"inputEvent_0"},
"2103" => { "type"=>"EVC", "desc"=>"inputEventCnt_0"},
"2201" => { "type"=>"S", "desc"=>"input_1"},
"2202" => { "type"=>"EV", "desc"=>"inputEvent_1"},
"2203" => { "type"=>"EVC", "desc"=>"inputEventCnt_1"},
# Used by Shelly i3 SHIX3-1:
"2301" => { "type"=>"S", "desc"=>"input_2"},
# Used by Shelly i3 SHIX3-1:
"2302" => { "type"=>"EV", "desc"=>"inputEvent_2"},
# Used by Shelly i3 SHIX3-1:
"2303" => { "type"=>"EVC", "desc"=>"inputEventCnt_2"},
"3101" => { "type"=>"T", "desc"=>"extTemp_0", "unit"=>"C"},
"3102" => { "type"=>"T", "desc"=>"extTemp_0", "unit"=>"F"},
"3103" => { "type"=>"H", "desc"=>"humidity"},
"3104" => { "type"=>"T", "desc"=>"deviceTemp", "unit"=>"C"},
"3105" => { "type"=>"T", "desc"=>"deviceTemp", "unit"=>"F"},
# Used by Shelly Sense SHSEN-1, Shelly Door Window SHDW-1, Shelly Door Window 2 SHDW-2:
"3106" => { "type"=>"L", "desc"=>"luminosity", "unit"=>"lux"},
# Used by Shelly Gas SHGS-1:
"3107" => { "type"=>"C", "desc"=>"concentration", "unit"=>"ppm"},
# Used by Shelly Door Window SHDW-1, Shelly Door Window 2 SHDW-2:
"3108" => { "type"=>"S", "desc"=>"dwIsOpened"},
# Used by Shelly Door Window SHDW-1, Shelly Door Window 2 SHDW-2:
"3109" => { "type"=>"S", "desc"=>"tilt", "unit"=>"deg"},
# Used by Shelly Door Window SHDW-1, Shelly Door Window 2 SHDW-2:
"3110" => { "type"=>"S", "desc"=>"luminosityLevel"},
"3111" => { "type"=>"B", "desc"=>"battery"},
# Used by Shelly Sense SHSEN-1, Shelly Button SHBTN-1:
"3112" => { "type"=>"S", "desc"=>"charger"},
# Used by Shelly Gas SHGS-1:
"3113" => { "type"=>"S", "desc"=>"sensorOp"},
# Used by Shelly Gas SHGS-1:
"3114" => { "type"=>"S", "desc"=>"selfTest"},
"3115" => { "type"=>"S", "desc"=>"sensorError"},
# Used by Shelly Spot SHSPOT-1, Shelly Spot 2 SHSPOT-2:
"3116" => { "type"=>"S", "desc"=>"dayLight"},
"3117" => { "type"=>"S", "desc"=>"extInput"},
"3201" => { "type"=>"T", "desc"=>"extTemp_1", "unit"=>"C"},
"3202" => { "type"=>"T", "desc"=>"extTemp_1", "unit"=>"F"},
"3301" => { "type"=>"T", "desc"=>"extTemp_2", "unit"=>"C"},
"3302" => { "type"=>"T", "desc"=>"extTemp_2", "unit"=>"F"},
"4101" => { "type"=>"P", "desc"=>"power_0", "unit"=>"W"},
# Used by Shelly 2 SHSW-21 roller-mode, Shelly 2.5 SHSW-25 roller-mode:
"4102" => { "type"=>"P", "desc"=>"rollerPower", "unit"=>"W"},
"4103" => { "type"=>"E", "desc"=>"energy_0", "unit"=>"Wmin"},
# Used by Shelly 2 SHSW-21 roller-mode, Shelly 2.5 SHSW-25 roller-mode:
"4104" => { "type"=>"E", "desc"=>"rollerEnergy", "unit"=>"Wmin"},
# Used by Shelly 3EM SHEM-3, Shelly EM SHEM:
"4105" => { "type"=>"P", "desc"=>"power_0", "unit"=>"W"},
# Used by Shelly 3EM SHEM-3, Shelly EM SHEM:
"4106" => { "type"=>"E", "desc"=>"energy_0", "unit"=>"Wh"},
# Used by Shelly 3EM SHEM-3, Shelly EM SHEM:
"4107" => { "type"=>"E", "desc"=>"energyReturned_0", "unit"=>"Wh"},
# Used by Shelly 3EM SHEM-3, Shelly EM SHEM:
"4108" => { "type"=>"V", "desc"=>"voltage_0", "unit"=>"V"},
# Used by Shelly 3EM SHEM-3:
"4109" => { "type"=>"I", "desc"=>"current_0", "unit"=>"A"},
# Used by Shelly 3EM SHEM-3:
"4110" => { "type"=>"S", "desc"=>"powerFactor_0"},
# Used by Shelly 2.5 SHSW-25 relay-mode, Shelly RGBW2-white SHRGBW2-white:
"4201" => { "type"=>"P", "desc"=>"power_1", "unit"=>"W"},
# Used by Shelly 2.5 SHSW-25 relay-mode, Shelly RGBW2-white SHRGBW2-white:
"4203" => { "type"=>"E", "desc"=>"energy_1", "unit"=>"Wmin"},
# Used by Shelly 3EM SHEM-3, Shelly EM SHEM:
"4205" => { "type"=>"P", "desc"=>"power_1", "unit"=>"W"},
# Used by Shelly 3EM SHEM-3, Shelly EM SHEM:
"4206" => { "type"=>"E", "desc"=>"energy_1", "unit"=>"Wh"},
# Used by Shelly 3EM SHEM-3, Shelly EM SHEM:
"4207" => { "type"=>"E", "desc"=>"energyReturned_1", "unit"=>"Wh"},
# Used by Shelly 3EM SHEM-3, Shelly EM SHEM:
"4208" => { "type"=>"V", "desc"=>"voltage_1", "unit"=>"V"},
# Used by Shelly 3EM SHEM-3:
"4209" => { "type"=>"I", "desc"=>"current_1", "unit"=>"A"},
# Used by Shelly 3EM SHEM-3:
"4210" => { "type"=>"S", "desc"=>"powerFactor_1"},
# Used by Shelly RGBW2-white SHRGBW2-white:
"4301" => { "type"=>"P", "desc"=>"power_2", "unit"=>"W"},
# Used by Shelly RGBW2-white SHRGBW2-white:
"4303" => { "type"=>"E", "desc"=>"energy_2", "unit"=>"Wmin"},
# Used by Shelly 3EM SHEM-3:
"4305" => { "type"=>"P", "desc"=>"power_2", "unit"=>"W"},
# Used by Shelly 3EM SHEM-3:
"4306" => { "type"=>"E", "desc"=>"energy_2", "unit"=>"Wh"},
# Used by Shelly 3EM SHEM-3:
"4307" => { "type"=>"E", "desc"=>"energyReturned_2", "unit"=>"Wh"},
# Used by Shelly 3EM SHEM-3:
"4308" => { "type"=>"V", "desc"=>"voltage_2", "unit"=>"V"},
# Used by Shelly 3EM SHEM-3:
"4309" => { "type"=>"I", "desc"=>"current_2", "unit"=>"A"},
# Used by Shelly 3EM SHEM-3:
"4310" => { "type"=>"S", "desc"=>"powerFactor_2"},
# Used by Shelly RGBW2-white SHRGBW2-white:
"4401" => { "type"=>"P", "desc"=>"power_3", "unit"=>"W"},
# Used by Shelly RGBW2-white SHRGBW2-white:
"4403" => { "type"=>"E", "desc"=>"energy_3", "unit"=>"Wmin"},
"5101" => { "type"=>"S", "desc"=>"brightness_0"},
"5102" => { "type"=>"S", "desc"=>"gain"},
"5103" => { "type"=>"S", "desc"=>"colorTemp", "unit"=>"K"},
# Used by Shelly Duo SHBDUO-1:
"5104" => { "type"=>"S", "desc"=>"whiteLevel"},
"5105" => { "type"=>"S", "desc"=>"red"},
"5106" => { "type"=>"S", "desc"=>"green"},
"5107" => { "type"=>"S", "desc"=>"blue"},
"5108" => { "type"=>"S", "desc"=>"white"},
# Used by Shelly RGBW2-white SHRGBW2-white, Shelly 2LED SH2LED-1:
"5201" => { "type"=>"S", "desc"=>"brightness_1"},
# Used by Shelly RGBW2-white SHRGBW2-white:
"5301" => { "type"=>"S", "desc"=>"brightness_2"},
# Used by Shelly RGBW2-white SHRGBW2-white:
"5401" => { "type"=>"S", "desc"=>"brightness_3"},
"6101" => { "type"=>"A", "desc"=>"overtemp"},
"6102" => { "type"=>"A", "desc"=>"overpower_0"},
# Used by Shelly 2 SHSW-21 roller-mode, Shelly 2.5 SHSW-25 roller-mode:
"6103" => { "type"=>"A", "desc"=>"rollerStopReason"},
# Used by Shelly Dimmer SHDM-1, Shelly Dimmer W1 SHDIMW-1:
"6104" => { "type"=>"A", "desc"=>"loadError"},
# Used by Shelly Smoke 2 SHSM-02, Shelly Smoke SHSM-01:
"6105" => { "type"=>"A", "desc"=>"smoke"},
# Used by Shelly Flood SHWT-1:
"6106" => { "type"=>"A", "desc"=>"flood"},
# Used by Shelly Sense SHSEN-1, Shelly Spot SHSPOT-1, Shelly Spot 2 SHSPOT-2:
"6107" => { "type"=>"A", "desc"=>"motion"},
# Used by Shelly Gas SHGS-1:
"6108" => { "type"=>"A", "desc"=>"gas"},
"6109" => { "type"=>"P", "desc"=>"overpowerValue", "unit"=>"W"},
# Used by Shelly Door Window SHDW-1, Shelly Door Window 2 SHDW-2:
"6110" => { "type"=>"A", "desc"=>"vibration"},
# Used by Shelly 2.5 SHSW-25 relay-mode, Shelly 2 SHSW-21 relay-mode:
"6202" => { "type"=>"A", "desc"=>"overpower_1"},
"9101" => { "type"=>"S", "desc"=>"mode"},
"9102" => { "type"=>"EV", "desc"=>"wakeupEvent"},
"9103" => { "type"=>"EVC", "desc"=>"cfgChanged"}
};

# Copied from 36_Shelly, keep up to date..:
my %shelly_models = (
    #(relays,rollers,dimmers,meters)
    "generic" => [4,4,4,4],
    "shellygeneric" => [4,4,4,4],
    "shelly1" => [1,0,0,0],
    "shelly1pm" => [1,0,0,1],
    "shelly2" => [2,1,0,1],
    "shelly2.5" => [2,1,0,2],
    "shellyplug" => [1,0,0,1],
    "shelly4" => [4,0,0,4],
    "shellyrgbw" => [0,0,4,1],
    "shellydimmer" => [0,0,1,1],
    "shellyem" => [1,0,0,2],
    "shellybulb" => [0,0,1,1],
    );

my %shelly_models_by_mod_shelly = ();

# Mapping of DeviceId in Multicast to Shelly model attr
my %DEVID_MODEL = (
    "SHPLG-S"  => "shellyplug",
    "SHSW-PM"  => "shelly1pm",
    "SHSW-L"   => "shelly1pm",
    "SHSW-1"   => "shelly1",
    "SHSW-21"  => "shelly2",
    "SHSW-25"  => "shelly2.5",
    "SHDM-2"   => "shellydimmer",
    "SHSW-44"  => "shelly4",
    "SHRGBW2"  => "shellyrgbw",
    "SHBLB-1"  => "shellybulb",
    "SHBDUO-1" => "shellybulb"
);

# Mapping of DeviceId in Multicast to suggested generic name
my %DEVID_PREFIX = (
    "SHPLG-S"  => "shelly_plug_s",
    "SHSW-PM"  => "shelly_1pm",
    "SHSW-1"   => "shelly_1",
    "SHSW-21"  => "shelly_2",
    "SHSW-25"  => "shelly_25",
    "SHDM-2"   => "shelly_dimmer",
    "SHSW-44"  => "shelly_4",
    "SHRGBW2"  => "shelly_rgbw",
    "SHBLB-1"  => "shelly_bulb",
    "SHBDUO-1" => "shelly_duo"
);

# Mapping of DeviceId in Multicast to additional attributes on creation
my %DEVID_ATTRS = (
    "SHDM-2"   => "webCmd pct:on:off",
    "SHBDUO-1" => "widgetOverride ct:colorpicker,CT,2700,10,6500"
);


# SHWT-1 = Shelly Flood, should go to generic

my %ROLLER_STATUS_MAP = (
    "open" => "moving_up",
    "close" => "moving_down",
    "stop" => "stopped"
);

#####################################
sub ShellyMonitor_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}   = "^\/(?s:.*)\!\$";
  $hash->{ReadFn}  = "ShellyMonitor_Read";
  $hash->{ReadyFn} = "ShellyMonitor_Ready";
  $hash->{DefFn}   = "ShellyMonitor_Define";
  $hash->{UndefFn} = "ShellyMonitor_Undef";
  $hash->{AttrFn}  = "ShellyMonitor_Attr";
  $hash->{NotifyFn}= "ShellyMonitor_Notify";
  $hash->{SetFn}= "ShellyMonitor_Set";
  $hash->{AttrList}= "ignoreDevices ".  $readingFnAttributes;
  $hash->{FW_detailFn} = "ShellyMonitor_detailFn";

  # Check which models are available in Mod_Shelly
  LoadModule "Shelly";
  my $fn = $modules{"Shelly"}{"AttrList"};
  if($fn && $fn=~/ model:([^ ]+)( |$)/) {
    map { $shelly_models_by_mod_shelly{$_} = 1 } split (/,/, $1);
    Log3 $hash->{NAME}, 2, "Shelly-Module loaded supports models: " . join(',', keys %shelly_models_by_mod_shelly);
  }
}

sub MCast_Open($$) {
  my ($hash, $interface) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{".McastInterface"};
  my $reopen = 0;

  my $conn;
  my $err;
  eval {
    $err = "Perl-Module IO::Socket::Multicast not found. Either execute \"sudo apt-get install libio-socket-multicast-perl\" (for Raspbian Buster), or \"sudo cpan install IO::Socket::Multicast\"";
    require IO::Socket::Multicast;
    $err = "Perl-Module JSON. Either execute \"sudo apt-get install libjson-perl\" (for Raspbian Buster), or \"sudo cpan install JSON\"";
    require JSON;
    $conn = IO::Socket::Multicast->new(LocalPort=>5683, ReuseAddr=>1) or $err = "Cannot open Multicast socket: $^E";
    if (defined $interface) {
      $err = "Error adding mcast interface $interface";
      $conn->mcast_add('224.0.1.187', $interface);
    } else {
      $err = "Error adding mcast interface";
      $conn->mcast_add('224.0.1.187') or $err = "Cannot open Multicast socket: $^E";
    }
    $err = undef;
    $hash->{".JSON"} = JSON->new->utf8;
    1;
  };
  if($@) {
    Log3 $name, 1, $err;
    return $err;
#    return &$doCb($@);
  }

  if(!$conn) {
    Log3 $name, 1, "$name: Can't connect to $dev: $^E" if(!$reopen);
    $readyfnlist{"$name.$dev"} = $hash;
#    DevIo_setStates($hash, "disconnected");
    return $err;
#    return &$doCb("");
  }
  $hash->{MCastDev} = $conn;
  $hash->{FD} = $conn->fileno();

  $dev = "" if (! defined $dev);
  delete($readyfnlist{"$name.$dev"});
  $selectlist{"$name.$dev"} = $hash;
  return undef;
}

sub MCast_Close($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{".McastInterface"};
  my $conn = $hash->{MCastDev};

  $conn->close() if ($conn);
  return unless defined $dev;
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
  delete($hash->{EXCEPT_FD});
  delete($hash->{PARTIAL});
  delete($hash->{NEXT_OPEN});
}

#####################################
sub ShellyMonitor_Define($$)
{
  my ($hash, $def) = @_;
  my ($a, $h) = parseParams($def);

  return 'wrong syntax: define <name> ShellyMonitor [interface]' if(@{$a} < 2);
  MCast_Close($hash);
  RemoveInternalTimer($hash);  
  my $name = ${$a}[0];
  my $dev;
  my $wantAuto;
  if (@{$a}>2) {
    $wantAuto = (${$a}[2]=~/^auto/);
    $dev = $wantAuto ? (@{$a}>3 ? ${$a}[3] : undef ) : ${$a}[2];
  }
 
  $hash->{NAME} = $name; 
  $hash->{".McastInterface"} = $dev;
  $hash->{".Ignored"}=0;
  $hash->{".Received"}=0;
  $hash->{".ReceivedBroken"}=0;
  $hash->{".ReceivedByIp"}=();
  $hash->{".ip2device"}=();
  $hash->{NOTIFYDEV} = "global";

#  if ($wantAuto && !AttrVal( $name, 'alexaMapping', undef ) ) {
#    CommandAttr(undef,"$name autoCreate Shelly");
#  }

  my $device_name = "ShellyMonitor_".$name;
  $modules{ShellyMonitor}{defptr}{$device_name} = $hash;
  
  Log3 $hash,5,"ShellyMonitor ($name) - Opening device...";
  return MCast_Open($hash, $dev);
}

sub ShellyMonitor_Init($)
{
  Log 3,"Init done";
  return undef;
}

#####################################
sub ShellyMonitor_Undef($$)
{
  my ($hash, $arg) = @_;
  MCast_Close($hash);
  return undef;
}

sub ShellyMonitor_DoRead($)
{
    my ($hash) = @_;

    my $name = $hash->{NAME};
    my $conn = $hash->{MCastDev};
    my $data;
    my $pinfo = $conn->recv($data,1400);
    my ($port, $ip_address) = unpack_sockaddr_in $pinfo;
    my $sending_ip = inet_ntoa ($ip_address);

    Log3 ($name, 4, "Received data from $sending_ip");
    $hash->{".Received"}++;
    $hash->{".ReceivedByIp"}->{$sending_ip}++;

    my $ip2devicesDirty = 0;
    my $ip2devices = $hash->{".ip2device"}->{$sending_ip};
    my @devices = ();
    if (! defined $ip2devices ) {
      Log3 ($name, 4, "$sending_ip not found in cache");
      my @devNames = devspec2array("TYPE=Shelly:FILTER=DEF=$sending_ip");
      foreach ( @devNames ) { 
        my %d = ( 
          name       => $_ ,
          isDefined  => 1,
          model      => AttrVal($_, "model", "generic"), 
          mode       => AttrVal($_, "mode", undef)
        );
        push @devices, \%d;
      }
      $ip2devices = \@devices;
      $hash->{".ip2device"}->{$sending_ip} = $ip2devices;
      $ip2devicesDirty = 1;
    } else {
      @devices = @{$ip2devices};
      # Panic line, as FHEM crashed here:
      map { 
        if (ref $_ ne "HASH") { 
          @devices = ();
          delete $hash->{".ip2device"}->{$sending_ip};
          Log3 $name, 1, "Panic, it happened: Cache for $sending_ip did contain a none-hash";
        }
      } @devices;
      Log3 $name, 4, "$sending_ip: in cache, devices=" . join (' ', map { scalar $_->{name} } @devices) . " (size=" . scalar @devices . ")";
    }
    my $autoCreate = (defined $hash->{".autoCreate"}) ? 1 : 0;

    # Now lets unpack the raw packet data...

    my ($b1,$b2,$msgid,$opt1byte,$remain) = unpack('CCSB8A*', $data);
    if ($b1 != 0x50) {
      Log3 $name, 3, "Unexpected byte at pos 0: " . sprintf("0x%X", $b1) . ", expecting Non-Confirm. w/o token";
      $hash->{".ReceivedBroken"}++;
      return undef;
    }
    if ($b2 != 30) {
      $hash->{".ReceivedBroken"}++;
      Log3 $name, 3, "Unexpected byte at pos 1: " . sprintf("0x%X", $b2) . ", expecting Code 30";
      return undef;
    }
    my $option = 0;

    my $uri = "";
    my $global_devid;
    my $validity;
    my $serial;

    # Parsing the options in COAP format...
    while ($opt1byte ne "11111111") {
      my $optiondelta = oct('0b' . substr($opt1byte, 0, 4));
      my $optionlen = oct('0b' . substr($opt1byte, 4));
      if ($optiondelta == 13) {
        ($optiondelta,$remain) = unpack('CA*', $remain);
        $optiondelta += 13;
      } elsif ($optiondelta == 14) {
        ($optiondelta,$remain) = unpack('nA*', $remain);
        $optiondelta += 269;
      }
      if ($optionlen == 13) {
        ($optionlen,$remain) = unpack('CA*', $remain);
        $optionlen += 13;
      } elsif ($optionlen == 14) {
        ($optionlen,$remain) = unpack('nA*', $remain);
        $optionlen += 269;
      }
      $option += $optiondelta;
      if ($option == 11) {
        my $str;
        ($str,$opt1byte,$remain) = unpack ('A' . $optionlen . 'B8A*', $remain);
        $uri .= '/' . $str;
      } elsif ($option == $COIOT_OPTION_GLOBAL_DEVID) {
        ($global_devid,$opt1byte,$remain) = unpack ('A' . $optionlen . 'B8A*', $remain);
      } elsif ($option == $COIOT_OPTION_STATUS_VALIDITY) {
        ($validity,$opt1byte,$remain) = unpack ('nB8A*', $remain);
        if ($validity & 1) {
          $validity *= 4;
        } else {
          $validity /= 10;
        }
      } elsif ($option == $COIOT_OPTION_STATUS_SERIAL) {
        ($serial,$opt1byte,$remain) = unpack ('vB8A*', $remain);
      } else {
        $hash->{".ReceivedBroken"}++;
        Log3 $name, 3, "Unexpected option $option, only CoIoT V2-options supported";
        return undef;
      }
    }

    foreach ( @devices ) {
      $_->{expires} = time()+$validity;
    }

    # Header parsed, processing data...
    my ($devtype, $devid, $devversion) = split (/#/, $global_devid);

    # Handle ignoring of devices
    my $ignoreRegexp = $hash->{".ignoreDevices"};
    if ($ignoreRegexp) {
      @devices = grep { $_->{name} !~ qr/$ignoreRegexp/ } @devices;
      Log3 ($name, 4, "Applied RegExp $ignoreRegexp");
      if (! @devices || scalar @devices == 0) {
        Log3 ($name, 4, "Shelly-devices found by IP match ignoreRule");
        $hash->{".Ignored"}++;
        return undef;
      }
    }

    Log3 $name, 5, "URI: $uri, global_devid = $global_devid, validity=$validity, serial=$serial";
    my $json = $hash->{".JSON"};
    return undef unless ($json);
    $data = $json->decode($remain);

    my $shellyCoIoTModel;
    my $shellyId;
    if ($global_devid=~ /(SH[^#]+)#([A-F0-9]{6,12})#/) {
      $shellyCoIoTModel = $1;
      $shellyId = $2; 
    }
    # Iterate over Shellys found by IP and x-check ID
    foreach ( @devices ) {
      $_->{expires} = time()+$validity;
      next unless $_->{isDefined};
      my $device = $defs{$_->{name}};
      next unless ($device);
      if (defined $device->{SHELLYID}) {
         if ($device->{SHELLYID} !~ qr/.*$shellyId$/) {
           Log3 $name, 1, "Device $_ has ID " . $device->{SHELLYID} . " which does not match $shellyId";
           my $dName = $_;
           @devices = grep { $_->{name} ne $dName } @devices;
         }
      } else {
        $device->{SHELLYID} = $shellyId;
        Log3 $name, 1, "Assigning device $_->{name} SHELLYID $shellyId";
      }
    }
    my %devModel = ();
    my $haveAutoCreated = 0;

    # Hopefully, all Shellys have an ID with 6-12 Chars...
    if (scalar @devices==0 && $global_devid=~ /(SH[^#]+)#([A-F0-9]{6,12})#/) {
      my $shellyCoIoTModel = $1;
      my $shellyId = $2;
      my @devsByShellyId = devspec2array("TYPE=Shelly:FILTER=SHELLYID=.*".$shellyId);
      if (scalar @devsByShellyId == 1 ) {

        # The Shelly-device is already existing, but has changed IP, so lets change the IP
        my $oname = $devsByShellyId[0];
        delete $hash->{".ip2device"}->{$sending_ip};
        my $oldip = $defs{$oname}->{DEF};
        CommandDefMod ( undef , $oname . " Shelly $sending_ip");
        if (defined $oldip && $oldip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
          delete $hash->{".ip2device"}->{$oldip};
          Log3 $name, 2, "Removing old ip $oldip for device $oname";
        }
        my %d = (
          name       => $oname,
          isDefined  => 1,
          model      => AttrVal($oname, "model", "generic"),
          mode       => AttrVal($oname, "mode", undef)
        );
	push @devices, \%d;
        $ip2devicesDirty = 1;
        Log3 $name, 2, "Changed IP for device '" . $oname . "' to $sending_ip";

      } else {

        # No Shelly known by IP nor ID, so lets create a dummy
        my $model = $DEVID_MODEL{$shellyCoIoTModel};
        my $dname;
        if (defined $model) {
          $dname = $DEVID_PREFIX{$shellyCoIoTModel};
        } else {
          $dname = "shelly_generic_" . lc($shellyCoIoTModel);
          $dname =~ s/-/_/g;
          $dname =~ s/[^a-zA-Z0-9_]//g;
          $model = "generic";
        }
        $dname .= '_' . lc($shellyId);
        Log3 $name, 2, "Defined shadow device $dname for $sending_ip as model $model";
        my %d = (
          name       => $dname,
          isDefined  => 0,
          model      => $model,
	  expires    => time()+$validity,
          attrs      => $DEVID_ATTRS{$shellyCoIoTModel}
        );
	push @devices, \%d;
        $ip2devicesDirty = 1;
      } 
    }

    foreach ( @devices ) {
      my $device = $defs{$_->{name}};
      next unless ($device);
      if ($_->{isDefined}) {
        readingsBeginUpdate($device);
        $_->{model} = AttrVal($_->{name}, "model", undef);
        Log3 $name, 5, "Found device $_->{name}, model $_->{model}";
      }
    }
    foreach my $i ( keys %{$data}) {
      if ($i ne "G") {
        Log3 $name, 4, "Unexpected JSON array '$i' in data";
        next;
      }
      my $arr = $data->{"G"};
      foreach my $j ( @{$arr}) {
        my $channel = @{$j}[0];
        my $sensorid = @{$j}[1];
        my $svalue = @{$j}[2];
        my $defarr = $SHELLY_DEF_SEN->{$sensorid};

        if (defined $defarr) {
          my $rname = $defarr->{"desc"};
          #$rname .= "(" . $defarr->{"unit"} . ")" if ($defarr->{"unit"});

          if ($rname =~ /^(power|output|energy|brightness)_(.).*/ || $rname =~ /^(roller.*|mode)$/) {
            my $rtype = $1;
            my $rno = $2;

            foreach ( @devices ) {
	      # We want to set the mode also for shadow devices
              my $model = $_->{model};
              if ($rtype eq "mode") {
                 $_->{mode} = $svalue unless $_->{isDefined}==1;
              }
              next unless $_->{isDefined}==1;

	      # Only real devices from here on..
              my $device = $defs{$_->{name}};
              next unless ($device);
              if ($rtype eq "power") {
                my $subs = ($shelly_models{$model}[3] ==1) ? "" : "_".$rno;
                readingsBulkUpdateIfChanged($device, "power" . $subs, $svalue);
              } elsif ($rtype eq "energy") {
                my $subs = ($shelly_models{$model}[3] ==1) ? "" : "_".$rno;
                readingsBulkUpdateIfChanged($device, "energy" . $subs, int($svalue/6)/10);
              } elsif ($rtype eq "output") {
                my $subs = ($shelly_models{$model}[0] ==1) ? "" : "_".$rno;
                my $state = ( $svalue == 0 ? "off" : ( $svalue == 1 ? "on" : undef ));
                if ($state) {
                  readingsBulkUpdateIfChanged($device, "relay" . $subs, $state);
                }
              } elsif ($rtype eq "brightness") {
                my $subs = ($shelly_models{$model}[3] ==1) ? "" : "_".$rno;
                readingsBulkUpdateIfChanged($device, "pct" . $subs, $svalue);
              } elsif ($rtype eq "rollerStopReason") {
                readingsBulkUpdateIfChanged($device, "stop_reason", $svalue);
              } elsif ($rtype eq "rollerEnergy") {
                readingsBulkUpdateIfChanged($device, "energy", int($svalue/6)/10);
              } elsif ($rtype eq "rollerPower") {
                readingsBulkUpdateIfChanged($device, "power", $svalue);
              } elsif ($rtype eq "rollerPos") {
                readingsBulkUpdateIfChanged($device, "pct", $svalue);
                my $v = $svalue;
                $v = "open" if ($svalue == 100);
                $v = "closed" if ($svalue == 0);
                readingsBulkUpdateIfChanged($device, "position", $v);
              } elsif ($rtype eq "roller") {
                my $v = $ROLLER_STATUS_MAP{$svalue};
                $v = $svalue unless defined $v;
                readingsBulkUpdateIfChanged($device, "state", $v);
                readingsBulkUpdateIfChanged($device, "last_dir", "down") if ($svalue eq "close") ;
                readingsBulkUpdateIfChanged($device, "last_dir", "up") if ($svalue eq "open") ;
              } elsif ($rtype eq "mode" && $haveAutoCreated==1) {
		CommandAttr ( undef, $_->{name} . ' mode ' . $svalue);
              }
            }
          } else {
            # Generic Shelly Device gets any reading in native form
            foreach ( @devices ) {
	      # We want to set the mode also for shadow devices
              my $model = $_->{model};
              my $device = $defs{$_->{name}};
              readingsBulkUpdateIfChanged($device, $rname, $svalue)
                if (defined $device && (( ! defined $model ) || ($model eq "generic")));
            }
          }
          Log3 $name, 5, "$rname = $svalue";
        } else {
          Log3 $name, 4, "Unknown: c=$channel, sensorid=$sensorid, value=$svalue";
        }
      }
    }
    foreach ( @devices ) {
      if ($_->{isDefined}) {
        my $device = $defs{$_->{name}};
        readingsEndUpdate($device, 1) if ($device);
      }
    }

    my $nstate = "Statistics: " . $hash->{".Received"} . " msg received, " . $hash->{".ReceivedBroken"} . 
" broken, " . $hash->{".Ignored"} . " ignored, " . (0 + (keys %{$hash->{".ReceivedByIp"}})) . " devices";
    readingsSingleUpdate ($hash, "state", $nstate, 0);
    FW_directNotify("FILTER=$name", "#FHEMWEB:WEB", "location.reload('true')", "") if ($ip2devicesDirty>0);

    return(undef);
}

sub ShellyMonitor_detailFn($$$) {
  my ($FW_wname, $deviceName, $FW_room) = @_;
  my $hash = $defs{$deviceName};
  my $haveUnsupported = 0;
  my $nstate = "<script type=\"text/javascript\">\n" . 'function checkInput(id) { var n=document.getElementById("dn" + id).value; var re=/^[a-z0-9._]+$/i; if (n.match(re)) { document.getElementById("ds" + id).value = document.getElementById("ds" + id).value.concat(n); return true; } else { alert("DeviceName " + n + " is invalid"); return false }};' . "\n</script>\n";
  $nstate .= "<div class='makeTable wide'><span class='mkTitle'>Identified Devices</span><table class='block wide'><tr class='odd'><th>IP</th><th>Name</th><th>Model</th><th></th></tr>";

  my $cnt = 0;
  my @ips = ( keys %{$hash->{".ip2device"}} );
  @ips = map substr($_, 4), sort map pack('C4a*', split(/\./), $_), @ips;
  my $now = time();
  my $formNo = 1;
  foreach my $ip ( @ips ) {
    my @devices = @{$hash->{".ip2device"}->{$ip}};
    foreach my $dev ( @devices ) {
      if ($dev->{expires} < $now) {
        Log3 $hash->{NAME}, 1, "Device " . $dev->{name} . " has expired, no messages seen";
        if (scalar @devices == 1) {
          delete $hash->{".ip2device"}->{$ip};
        } else {
          @devices = grep { $_->{expires} > $now } @devices;
          $hash->{".ip2device"}->{$ip} = \ @devices;
        }
        next;
      }
      
      $nstate .= "<form action=\"$FW_ME\"><input type=\"hidden\" name=\"cmd\" value=\"set $deviceName create $ip \" id=\"ds$formNo\">" unless ($dev->{isDefined});
      if ($FW_CSRF =~ /^[&?]([^=]+)=(.*)$/) {
        $nstate .= "<input type=\"hidden\" name=\"$1\" value=\"$2\" />";
      }
      $nstate .= "<tr class='" . (($cnt++)%2==0 ? "even" : "odd") . 
        "'><td>$ip</td><td>";
      if ($dev->{isDefined}) {
        $nstate .= "<b><a href=\"fhem?detail=" . $dev->{name} . "\"></b>" . $dev->{name} . "</a></b>";
      } else {
        $nstate .= "<input type=\"text\" value=\"$dev->{name}\" id=\"dn$formNo\"/>";
      }
      $nstate .= "</td><td>$dev->{model}";
      if (! defined $shelly_models_by_mod_shelly{$dev->{model}} && $dev->{model} ne "generic") {
        $nstate .= ", n.s.";
        $haveUnsupported = 1;
      } else {
        $nstate .= " $dev->{mode}" if (defined $dev->{mode});
      }
      if ($dev->{isDefined}) { 
        $nstate .= "</td><td></td></tr>";
      } else {
        $nstate .= "</td><td><input type=\"submit\" value=\"Create\" onClick=\"return checkInput($formNo);\"></td></tr></form>";
        $formNo++;
      }
#	($dev->{isDefined} ? "" : "<a href=\"$FW_ME?cmd=set $deviceName autocreate $ip".$FW_CSRF."\">Create</a>" ) .
    }
  }
  $nstate .= "</table>";
  $nstate .= "<i>n.s. = not supported by Mod_Shelly</i><br/>" if ($haveUnsupported);
  $nstate .= "</div>";
  return $nstate;
}


#####################################
sub ShellyMonitor_Read($)
{
  my ($hash) = @_;
  if( $init_done ) {
    ShellyMonitor_DoRead($hash);
#    my $new_state = "Statistics: " . $hash->{".Received"} . " msg received, " . $hash->{".ReceivedBroken"} . " broken, " . $hash->{".Ignored"} . " ignored, " . (0 + (keys %{$hash->{".ReceivedByIp"}})) . " devices";
#    readingsSingleUpdate($hash,"state",$new_state,1);
  }
  return(undef);
}

#####################################
sub ShellyMonitor_Notify($$)
{
  my ($hash, $dev_hash) = @_;
  my $ownName = $hash->{NAME}; # own name / hash

  return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled

  my $devName = $dev_hash->{NAME}; # Device that created the events

  my $events = deviceEvents($dev_hash,1);
  return if( !$events );
  my $ip2devicesDirty = 0;

  foreach my $event (@{$events}) {
    $event = "" if(!defined($event));
    next unless ($event =~ /^(RENAMED|DELETED|DEFINED|MODIFIED).*/);
    my ($evType, $evDev1, $evDev2) = split (/ /, $event);
    my @ips = ( keys %{$hash->{".ip2device"}} );
    $ip2devicesDirty = 0;
    foreach my $ip ( @ips ) {
      my @devices = @{$hash->{".ip2device"}->{$ip}};
      foreach my $dev ( @devices ) {
        next unless ($dev->{name} eq $evDev1);
        $ip2devicesDirty = 1;
        delete $hash->{".ip2device"}->{$ip} if ($evType eq "DELETED");
        $dev->{name} = $evDev2 if ($evType eq "RENAMED");
        $dev->{isDefined} = 1 if ($evType eq "DEFINED");
      }
    }
    if ($ip2devicesDirty==0) {
      Log3 $hash->{NAME}, 4, "Did not find device $evDev1 in cache...";
      my $ohash = $defs{$evDev1};
      if (defined $ohash && $ohash->{TYPE} eq "Shelly") {
        # We did not find it, and it was something about Shellys:
        # Be paranoic, clear cache...
        Log3 $hash->{NAME}, 4, "... but its a shelly, so clear cache";
        $hash->{".ip2device"} = ();
        $ip2devicesDirty = 1
      }
    }
    Log3 $hash->{NAME}, 4, "Modified ip2device-cache on event: $event";
  }
  FW_directNotify("#FHEMWEB:WEB", "location.reload('true')", "") if ($ip2devicesDirty>0);
}


#####################################
sub ShellyMonitor_Ready($)
{
  my ($hash) = @_;

  my $name = $hash->{NAME}; 
  my $dev=$hash->{".McastInterface"};
  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  return if (!$po);
  ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

sub ShellyMonitor_Set(@)
{
  my ($hash, $name, $sName, $sValue, $devName) = @_;

  return "autocreate create" if ($sName eq "?");
  return "only autocreate and create vailable" if ($sName !~ /(auto|)create/);

  if ($sName eq "autocreate") {
    $sValue = ".*" unless (defined $sValue);
    return "autocreate only takes an IP address pattern as optional value" if (defined $devName);
  } else {
    $sValue = '^' . $sValue . '$';
    $sValue =~ s/\./\\./g;
  }
  my $created = 0;
  my @ips = grep { $_ =~ qr/^$sValue$/ } ( keys %{$hash->{".ip2device"}} );
  return "Provided IP $sValue did not match any IPs" unless (scalar @ips>=1);
  foreach my $ip ( @ips ) {
    my $ip2devices = $hash->{".ip2device"}->{$ip};
    my $device = @{$ip2devices}[0];
    next if ($device->{isDefined});
    Log3 $name, 1, "AutoCreate called for IP $ip, ip2devices=" . scalar @{$ip2devices};
    my $dname = defined $devName ? $devName : $device->{name};
    $device->{name} = $dname;
    my $model = $device->{model};
    my $mode = $device->{mode};
    my $r;
    if ($sName eq "autocreate") {
      $r = DoTrigger("global", "UNDEFINED $dname Shelly $ip");
    } else {
      $r = CommandDefine(undef, "$dname Shelly $ip");
    }
    Log3 $name, 1, "AutoCreating $dname returned $r" if ($r);
    if (defined $shelly_models_by_mod_shelly{$model}) {
      CommandAttr ( undef, $dname . ' model ' . $model);
    } elsif ($shelly_models_by_mod_shelly{"shellygeneric"}) {
      CommandAttr ( undef, $dname . ' model shellygeneric');
    }
    return "Creation of device '$dname' failed" unless ($defs{$dname});

    my $attrs = $device->{attrs};
    if (defined $attrs) {
      my @a = split / /, $attrs;
      while (my $aname = shift @a) {
        CommandAttr ( undef, $dname . " $aname " . shift @a );
      }
    }
    if (defined $mode) {
      CommandAttr ( undef, $dname . ' mode ' . $mode) if ($model ne "generic");;
      if ($model =~ /shellybulb/) {
        CommandAttr ( undef, $dname . ' webCmd ' . ($mode eq "white" ? 'pct:ct:on:off' : 'rgb:on:off' ) );
      }
      if ($model =~ /shellyrgb.*/ && ($mode eq "color") ) {
        CommandAttr ( undef, $dname . ' webCmd rgb:on:off' );
      }
    }
    if ($model =~ /shellydimmer.*/) {
      CommandAttr ( undef, $dname . ' webCmd pct:on:off' );
    }
    CommandAttr ( undef, $dname . ' interval 600' );
    $created++;
  }
  FW_directNotify("#FHEMWEB:WEB", "location.reload('true')", "") if ($created>0);
  return undef;
}



sub ShellyMonitor_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value
  my $hash  = $defs{$name};
  my $dev=$hash->{".McastInterface"};
  if ($aName eq "ignoreDevices") { 
    $hash->{".ignoreDevices"} = ($cmd eq "set" ) ? $aVal : undef;
#  } elsif ($aName eq "autoCreate") { 
#    $hash->{".autoCreate"} = ($cmd eq "set" && $aVal eq "Shelly") ? $aVal : undef;
  }
  return undef;
}


1;

=pod
=item device
=item summary Listens to CoIoT-Messages sent by Shellys and updates readings
=item summary_DE Wertet CoIoT-Pakete von Shelly-Geräten aus und aktualisiert die Readings
=begin html

<a name="ShellyMonitor"></a>
<h3>ShellyMonitor</h3>
<ul>
  This module is for Shelly-devices, that report their data in the CoIoT-"standard" (based on COAP).
  Defined devices are updated in their readings, non-defined devices found are displayed in FHEMWEB
  in a table, where they might be created with a click.
  <br><br>
  <h4>Define</h4>
  <ul>
    <code>define &lt;name&gt; ShellyMonitor [interface]</code><br>
    <br>
      &lt;interface&gt; is necessary if the computers primary interface is not the one
      with the multicast messages. E.g., it might be "wlan0".
    <br>
  </ul>

  <h4>Set</h4>
  <ul>
    <li><code>set &lt;name&gt; autocreate [&lt;ip regexp&gt;]</code><br>
    Setting this command triggers the creation of all discovered, but not yet defined
    devices that have an IP address matching to pattern. Without a pattern,
    all devices are created.<br>
    Creation implies:
     <ul>
     <li>a <b>define</b> via the autocreate module mechanism with the systematic name displayed in the WEB table</li>
     <li>setting the <b>model</b> attribute for the device</li>
     <li>setting the <b>mode</b> attribute if applicable</li>
     <li>setting the <b>webCmd</b> attribute if applicable</li>
    </ul>
    </li>

    <li><code>set &lt;name&gt; create &lt;ip address&gt; [&lt;device name&gt;]</code><br>
    The device specified by its IP address is created with the optionally given
    device name. Unlike <code>autocreate</code>, a direct <code>define</code> is 
    executed, and the features of the autocreate module (FileLog-device, room-attribute)
    are not assigned.<br/>
    The other attributes described for the <code>autocreate</code>-set command are assigned.
  
    </li>
  </ul>

  <h4>Attributes</h4>
  <ul><li>
   <code>ignoreDevices</code><br>
      Regular expression for Shelly device (names) that shall be ignored.
      E.g., setting this to "<code>.*</code>" will not update any devices
      </li>
      
  <br>
</ul></ul>

=end html

=begin html_DE

<a name="ShellyMonitor"></a>
<h3>ShellyMonitor</h3>
<ul>
  Dieses Modul aktualisiert die Readings von Shelly-Geräten, die ihre Daten im CoIoT-"Standard" (Abwandlung von COAP) im Netzwerk versenden. Die gefundenen Ger&auml;te werden in FHEMWEB in einer Tabelle angezeigt, wo sie sich
  mit einem Klick erzeugen und anschlie&szlig;end ggf. umbenennen lassen.
  <br><br>
  <h4>Define</h4>
  <ul>
    <code>define &lt;name&gt; ShellyMonitor [interface]</code><br>
    <br>
      &lt;interface&gt; ist nötig, falls das primäre Netzwerk-Interface nicht das
      Netz ist, in dem die Multicast-Pakete versendet werden.
      Beispielsweise "wlan0" oder "eth0"
    <br>
  </ul>

  <h4>Set</h4>
  <ul>
    <li><code>set &lt;name&gt; autocreate [&lt;ip regexp&gt;]</code><br>
    Mit diesem Kommando werden alle gefundenen Shelly-Ger&auml;te, die noch nicht angelegt
    wurden, erzeugt, sofern ihre aktuelle IP-Adresse dem regul&auml;ren Ausdruck entspricht.
    Ohne diesen Parameter werden alle gefundenen Ger&auml;te erzeugt.
    <br>
    Die Erzeugung umfasst:
     <ul>
     <li>a <b>define</b> &uuml;ber das autocreate-Modul mit dem systematischen Namen, der in
     der Tabelle angezeigt wird</li>
     <li>Setzen des <b>model</b>-Attributs f&uuml;r das Ger&auml;t</li>
     <li>Setzen des <b>mode</b>-Attributs, sofern beim Ger&auml;t vorhanden</li>
     <li>Setzen eines <b>webCmd</b>-Attributs, falls sinnvoll</li>
    </ul>
    </li>
    <li><code>set &lt;name&gt; create &lt;ip address&gt; [deviceName]</code><br>
    Mit diesem Kommando wird das durch die angegebene IP-Adresse spezifizierte Ger&auml;t
    unter dem als <i>deviceName</i> optional angegebenen Namen erzeugt.
    Anders als bei <code>autocreate</code> wird das Ger&auml;t nicht &uuml;ber das
    autocreate-Modul erzeugt. Es wird daher kein Raum zugewiesen und kein FileLog-Device
    angelegt. Die Attribute werden hingegen wie bei <code>autocreate</code> beschrieben zugewiesen.
    </li>
  </ul>

  <h4>Attribute</h4>
  <ul><li>
   <code>ignoreDevices</code><br>
      Regulärer Ausdruck, welche Shelly-Geräte nicht aktualisiert werden sollen.
      Beispielsweise werden mit "<code>.*</code>" alle Geräte ignoriert.
      Der Ausdruck bezieht sich auf den Ger&auml;tenamen.
      </li>
      
  <br>
</ul></ul>

=end html_DE

=cut
