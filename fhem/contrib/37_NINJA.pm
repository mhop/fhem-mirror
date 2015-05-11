# $Id: $
#
# TODO:

package main;

my $dl = 4;

##########################
# This block is only needed when FileLog is checked outside fhem
#
sub Log3($$$);
sub Log($$);
sub RemoveInternalTimer($);
use vars qw(%attr);
use vars qw(%defs);
use vars qw(%modules);
use vars qw($readingFnAttributes);
use vars qw($reread_active);

##########################

use strict;
use warnings;
use SetExtensions;

use vars qw(%ninjaDevice);
use vars qw(%ninjaTypes);
use vars qw(%ninjaGroups);

sub NINJA_Parse($$);
sub NINJA_Send($$@);

sub
NINJA_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^.+";
  $hash->{SetFn}     = "NINJA_Set";
  #$hash->{GetFn}     = "NINJA_Get";
  $hash->{DefFn}     = "NINJA_Define";
  $hash->{UndefFn}   = "NINJA_Undef";
  $hash->{FingerprintFn}   = "NINJA_Fingerprint";
  $hash->{ParseFn}   = "NINJA_Parse";
  $hash->{AttrFn}    = "NINJA_Attr";
  $hash->{AttrList}  = "IODev"
                       ." readonly:1"
                       ." forceOn:1"
                       ." $readingFnAttributes";
}

sub
NINJA_Define__($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 4 ) {
    my $msg = "wrong syntax: define <name> NINJA <g> <vendor>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  $a[2] =~ m/^([\da-f]{6})$/i;
  return "$a[2] is not a valid NINJA address" if( !defined($1) );

  $a[3] =~ m/^([\da-f]{2})$/i;
  return "$a[3] is not a valid NINJA channel" if( !defined($1) );

  my $name = $a[0];
  my $addr = $a[2];
  my $channel = $a[3];

  #return "$addr is not a 1 byte hex value" if( $addr !~ /^[\da-f]{2}$/i );
  #return "$addr is not an allowed address" if( $addr eq "00" );

  return "NINJA device $addr already used for $modules{NINJA}{defptr}{$addr}->{NAME}." if( $modules{NINJA}{defptr}{$addr}
                                                                                             && $modules{NINJA}{defptr}{$addr}->{NAME} ne $name );

  $hash->{addr} = $addr;
  $hash->{channel} = $channel;

  $modules{NINJA}{defptr}{$addr} = $hash;

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  #$attr{$name}{devStateIcon} = 'on:on:toggle off:off:toggle set.*:light_question:off' if( !defined( $attr{$name}{devStateIcon} ) );
  #$attr{$name}{webCmd} = 'on:off:toggle:statusRequest' if( !defined( $attr{$name}{webCmd} ) );
  #CommandAttr( undef, "$name userReadings consumptionTotal:consumption monotonic {ReadingsVal(\$name,'consumption',0)}" ) if( !defined( $attr{$name}{userReadings} ) );

  #NINJA_Send($hash, $addr, "00" );

  return undef;
}

sub
NINJA_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  Log3 undef, 0, "NINJA_define: $def";

  if(@a != 3 ) {
    my $msg = "wrong syntax: define <name> NINJA <addr>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  $a[2] =~ m/^(.+)$/i;
  return "$a[2] is not a valid NINJA address" if( !defined($1) );

  my $name = $a[0];
  my $addr = $a[2];

  #return "$addr is not a 1 byte hex value" if( $addr !~ /^[\da-f]{2}$/i );
  return "$addr is not an allowed address" if( $addr eq "0" );

  return "NINJA device $addr already used for $modules{NINJA}{defptr}{$addr}->{NAME}."
      if( $modules{NINJA}{defptr}{$addr} && $modules{NINJA}{defptr}{$addr}->{NAME} ne $name );

  $hash->{addr} = $addr;

  $modules{NINJA}{defptr}{$addr} = $hash;

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  #$attr{$name}{devStateIcon} = 'on:on:toggle off:off:toggle *.:light_question:off' if( !defined( $attr{$name}{devStateIcon} ) );
  #$attr{$name}{webCmd} = 'on:off:toggle:statusRequest' if( !defined( $attr{$name}{webCmd} ) );
  #CommandAttr( undef, "$name userReadings consumptionTotal:consumption monotonic {ReadingsVal(\$name,'consumption',0)}" ) if( !defined( $attr{$name}{userReadings} ) );

  return undef;
}

#####################################
sub
NINJA_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $addr = $hash->{addr};

  delete( $modules{NINJA}{defptr}{$addr} );

  return undef;
}

#####################################
sub
NINJA_Set($@)
{
  my ($hash, $name, @aa) = @_;

  my $cnt = @aa;

  return "\"set $name\" needs at least one parameter" if($cnt < 1);

  my $cmd = $aa[0];
  my $arg = $aa[1];
  my $arg2 = $aa[2];
  my $arg3 = $aa[3];

  my $readonly = AttrVal($name, "readonly", "0" );

  #my $list = "identify:noArg reset:noArg statusRequest:noArg";
  #$list .= " off:noArg on:noArg toggle:noArg" if( !$readonly );
  my $list = "";

  if( $cmd eq 'toggle' ) {
    $cmd = ReadingsVal($name,"state","on") eq "off" ? "on" :"off";
  }

  if( !$readonly && $cmd eq 'off' ) {
    readingsSingleUpdate($hash, "state", "set-$cmd", 1);
    #NINJA_Send( $hash, 0x05, 0x00 );
  } elsif( !$readonly && $cmd eq 'on' ) {
    readingsSingleUpdate($hash, "state", "set-$cmd", 1);
    #NINJA_Send( $hash, 0x05, 0x01 );
  } elsif( $cmd eq 'statusRequest' ) {
    readingsSingleUpdate($hash, "state", "set-$cmd", 1);
    #NINJA_Send( $hash, 0x04, 0x00 );
  } elsif( $cmd eq 'reset' ) {
    readingsSingleUpdate($hash, "state", "set-$cmd", 1);
    #NINJA_Send( $hash, 0x04, 0x01 );
  #} elsif( $cmd eq 'identify' ) {
  #  NINJA_Send( $hash, 0x06, 0x00 );
  } elsif ($cmd eq 'offset' ) {
    if (defined $arg2) {
      readingsSingleUpdate($hash, ".offset.$arg", $arg2, 0);
    } else {
      delete $hash->{READINGS}{".offset.$arg"};
    }
  } else {
    #TODO: understand
    return SetExtensions($hash, $list, $name, @aa);
  }

  return undef;
}

#####################################
sub
NINJA_Get($@)
{
  my ($hash, $name, $cmd, @args) = @_;

  return "\"get $name\" needs at least one parameter" if(@_ < 3);

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
NINJA_Fingerprint($$)
{
  my ($name, $msg) = @_;

  return ( "", $msg );
}

sub
NINJA_ForceOn($)
{
  my ($hash) = @_;

  #NINJA_Send( $hash, 0x05, 0x01 );
}

sub
NINJA_Parse($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  #return undef if( $msg !~ m/^[\dA-F]{12,}$/ );

  if (0) { ##---------------------------------------------------
  if( $msg =~ m/^L/ ) {
    my @parts = split( ' ', substr($msg, 5), 4 );
    $msg = "OK 24 $parts[3]";
  }

  my( @bytes, $channel,$cmd,$addr,$data,$power,$consumption );
  if( $msg =~ m/^OK/ ) {
    @bytes = split( ' ', substr($msg, 6) );

    $channel = sprintf( "%02X", $bytes[0] );
    $cmd = $bytes[1];
    $addr = sprintf( "%02X%02X%02X", $bytes[2], $bytes[3], $bytes[4] );
    $data = $bytes[5];
    return "" if( $cmd == 0x04 && $bytes[6] == 170 && $bytes[7] == 170 && $bytes[8] == 170 && $bytes[9] == 170 ); # ignore commands from display unit
    return "" if( $cmd == 0x05 && ( $bytes[6] != 170 || $bytes[7] != 170 || $bytes[8] != 170 || $bytes[9] != 170 ) ); # ignore commands not from the plug
  } elsif ( $msg =~ m/^TX/ ) {
    # ignore TX
    return "";
  } else {
    DoTrigger($name, "UNKNOWNCODE $msg");
    Log3 $name, 3, "$name: Unknown code $msg, help me!";
    return "";
  }
  } #------------------------------------------------

  my $jsonref = NinjaPiCrust_ParseJSON($msg);
  my %datagram = %$jsonref;
  #Log3 $name, $dl, "NinjaPiCrust_Parse: \%datagram is @{[%datagram]}";

  my $msgtype = (keys %datagram)[0];

  Log3 $name, $dl, "$name: got message type '$msgtype'";
  my %data = %{$datagram{$msgtype}[0]};
  $data{MSGTYPE} = $msgtype;
  Log3 $name, $dl, "$name: Got $msgtype $data{G} $data{V} $data{D} $data{DA} from $msg"
    if (defined $data{G} and defined $data{V} and defined $data{D} and defined $data{DA});

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} = TimeNow();
  $hash->{RAWMSG} = $msg;

  # from here on, adhere to PCA301 logic for now:
  my $raddr = $data{G};
  my $rhash = $modules{NINJA}{defptr}{$raddr};
  my $rname = $rhash?$rhash->{NAME}:$raddr;

  if ( !$modules{NINJA}{defptr}{$raddr} ) {
    Log3 $name, 3, "NINJA Unknown device $rname, please define it";

    return "UNDEFINED NINJA_$rname NINJA $raddr";# $channel";
  }

  #CommandAttr( undef, "$rname userReadings consumptionTotal:consumption monotonic {ReadingsVal($rname,'consumption',0)}" ) if( !defined( $attr{$rname}{userReadings} ) );

  my @list;
  push(@list, $rname);

  $rhash->{NINJA_lastRcv} = TimeNow();

  Log3 $rhash, $dl, "$rname: identified module, commencing";

  #if( $rhash->{channel} ne $channel ) {
  #  Log3 $rname, 3, "NINJA $rname, channel changed from $rhash->{channel} to $channel";
  #
  #  $rhash->{channel} = $channel;
  #  $rhash->{DEF} = "$rhash->{addr} $rhash->{channel}";
  #  CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
  #}

  my $readonly = AttrVal($rname, "readonly", "0" );
  my $state = "";

  #if( $cmd eq 0x04 ) {
  #  $state = $data==0x00?"off":"on";
  #  my $power = ($bytes[6]*256 + $bytes[7]) / 10.0;
  #  my $consumption = ($bytes[8]*256 + $bytes[9]) / 100.0;
  #  my $state = $state; $state = $power if( $readonly );
  #  readingsBeginUpdate($rhash);
  #  readingsBulkUpdate($rhash, "power", $power) if( $power != ReadingsVal($rname,"power",0) );
  #  readingsBulkUpdate($rhash, "consumption", $consumption) if( $consumption != ReadingsVal($rname,"consumption",0) );
  #  readingsBulkUpdate($rhash, "state", $state) if( $state ne ReadingsVal($rname,"state","") );
  #  readingsEndUpdate($rhash,1);
  #} elsif( $cmd eq 0x05 ) {
  #  $state = $data==0x00?"off":"on";
  #
  #  readingsSingleUpdate($rhash, "state", $state, 1)
  #}

  if( AttrVal($rname, "forceOn", 0 ) == 1
      && $state eq "off"  ) {
    readingsSingleUpdate($rhash, "state", "set-forceOn", 1);
    InternalTimer(gettimeofday()+3, "NINJA_ForceOn", $rhash, 0);
  }

  my $key = "$data{V}:$data{D}";
  unless (exists $ninjaDevice{$key}) {
    Log3 $rname, 0, "$rname: unknown VID:DID '$key'";
    return;
  }
  my %ndev = %{$ninjaDevice{$key}};
  unless ($ndev{sens}) {
    Log3 $rname, 0, "$rname: Not a sensor: VID:DID '$key' ($ndev{hint})";
    return;
  }
  if (!exists $ninjaTypes{$ndev{type}}) {
    Log3 $rname, 0, "$rname: Unsupported sensor VID:DID '$key' ($ndev{hint})";
    readingsSingleUpdate($rhash, $ndev{hint}, $data{DA}, 1);
    return;

  } else {
    # figure out which reding we are actually dealing with
    # and create update event.
    my %ntype = %{$ninjaTypes{$ndev{type}}};
    my $ntname = $ntype{name};
    my $now = gettimeofday();
    $rhash->{".reading.timestamp.$ntname"} = $now;
    my $val = $data{DA};
    my $offset = ReadingsVal($rname,".offset.$ntname",0.0);
    $val = $val + $offset unless ($offset == 0); 
    my $fmt = $ntype{format};
    $val = sprintf($fmt,$val) if (defined $fmt);
    readingsSingleUpdate($rhash, $ntname, $val, 1);
    # if we expect more than one reading as defined by a group,
    # check if we have enough information to compile the group reading
    #
    # TODO: In this case we may want to deferr the individual updates
    #       and use readingsBulkUpdate, instead
    if (exists $ntype{group} and exists $ninjaGroups{$ntype{group}}) {
      my %ngroup = %{$ninjaGroups{$ntype{group}}};
      Log3 $rname, $dl, "$rname: reading '$ntype{name}' is of group '$ntype{group}'";
      my $format = $ngroup{format};
      my $reading = $format;
      my $valid = 1;
      while ($format =~ /\{([^\}]+)\}/g) {
        my $rn = $1;
        Log3 $rname, $dl, "$rname: found in template: $rn";
        
        if (exists $rhash->{".reading.timestamp.$rn"}) {
          my $rval = ReadingsVal($rname,$rn,undef); 
          $reading =~ s/\{$rn\}/$rval/;
          $valid = 0 unless (($now - $rhash->{".reading.timestamp.$rn"}) < 0.5);
        } else {
          $valid = 0;
        }
      }
      Log3 $rname, $dl, "$rname: got '$reading' from '$format'";
      readingsSingleUpdate($rhash, $ngroup{name}, $reading, 1) if ($valid);
    }
  }

  return @list;
}

%ninjaTypes = (
  "temperature" => { name=>"temperature", group=>"TD", format=>"%.1f" },
  "humidity"    => { name=>"humidity",    group=>"TD" }
);

%ninjaGroups = (
  "TD" => { name=>"state", format=>"T: {temperature} H: {humidity}" }
);

#
# from devids.cvs :
# VID;DID;Device Type;Default Name;State;Actuator;Sensor;Silent;Has Sub Device;Time Series data
# cat ~/ninja/devids.csv | tr "; \r" "\t_ " |while read a b c d e f g h i j k; do key="\"$a:$b\"       " key=${key:0:10}; type="\"$c\"                        "; type=${type:0:25}; echo "$key => {st=>$e, act=>$f, sens=>$g, sil=>$h, sub=>$i, tds=>$j, type=>$type, hint=>\"$d\" },"; done
#
# key is VID:DID
# type:Device Type
# hint:Default Name
# st:State
# act:Actuator
# sens:Sensor
# sil:Silent
# sub:Has Sub Device
# tsd:Time Series data
%ninjaDevice = (
  "0:1"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"temperature"            , hint=>"Block_Temperature" },
  "0:2"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"linear_acceleration"    , hint=>"Block_Accelerometer" },
  "0:3"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"jiggle"                 , hint=>"Block_Jiggle" },
  "0:5"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"button"                 , hint=>"Push_Button" },
  "0:6"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"light_level"            , hint=>"Light_Sensor" },
  "0:7"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"pir"                    , hint=>"PIR_Motion_Sensor" },
  "0:8"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"humidity"               , hint=>"Humidity" },
  "0:9"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"temperature"            , hint=>"Temperature" },
  "0:11"     => {st=>0, act=>1, sens=>1, sil=>0, sub=>1, tds=>0, type=>"rf433"                  , hint=>"RF_433Mhz" },
  "0:12"     => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"sound"                  , hint=>"Sound_Sensor" },
  "0:13"     => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"temperature"            , hint=>"La_Crosse_Temp_TX3/6" },
  "0:14"     => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"hid"                    , hint=>"Unknown_HID_Device" },
  "0:20"     => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"temperature"            , hint=>"La_Crosse_Temp_WS2355" },
  "0:21"     => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"humidity"               , hint=>"La_Crosse_Humidity_WS2355" },
  "0:22"     => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"rainfall"               , hint=>"La_Crosse_Rainfall_WS2355" },
  "0:23"     => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"direction"              , hint=>"La_Crosse_Wind_Direction" },
  "0:24"     => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"speed"                  , hint=>"La_Crosse_Wind_Speed" },
  "0:30"     => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"humidity"               , hint=>"Humidity" },
  "0:31"     => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"temperature"            , hint=>"Temperature" },
  "0:101"    => {st=>0, act=>1, sens=>1, sil=>1, sub=>0, tds=>0, type=>"twitter"                , hint=>"Twitter" },
  "0:102"    => {st=>0, act=>1, sens=>1, sil=>1, sub=>0, tds=>0, type=>"facebook"               , hint=>"Facebook" },
  "0:103"    => {st=>0, act=>1, sens=>1, sil=>1, sub=>0, tds=>0, type=>"sms"                    , hint=>"SMS" },
  "0:104"    => {st=>0, act=>1, sens=>1, sil=>1, sub=>0, tds=>0, type=>"dropbox"                , hint=>"Dropbox" },
  "0:105"    => {st=>0, act=>1, sens=>1, sil=>1, sub=>0, tds=>0, type=>"googledrive"            , hint=>"Google_Drive" },
  "0:106"    => {st=>0, act=>1, sens=>1, sil=>1, sub=>0, tds=>0, type=>"email"                  , hint=>"Email" },
  "0:107"    => {st=>0, act=>1, sens=>1, sil=>1, sub=>0, tds=>0, type=>"salesforce"             , hint=>"Salesforce" },
  "0:108"    => {st=>0, act=>1, sens=>1, sil=>1, sub=>1, tds=>0, type=>"webhook"                , hint=>"Webhook" },
  "0:200"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"button"                 , hint=>"Push_Button" },
  "0:201"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"momentary_switch"       , hint=>"Reed_Switch" },
  "0:202"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"temperature"            , hint=>"Temperature" },
  "0:203"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"humidity"               , hint=>"Humidity" },
  "0:204"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"pir"                    , hint=>"PIR_Motion_Sensor" },
  "0:205"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"switch_sensor"          , hint=>"Switch_Sensor" },
  "0:206"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"switch_actuator"        , hint=>"Switch_Actuator" },
  "0:207"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>1, type=>"switch"                 , hint=>"Switch" },
  "0:208"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"orientation"            , hint=>"Orientation" },
  "0:209"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"jiggle"                 , hint=>"Jiggle" },
  "0:210"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"gesture"                , hint=>"Gesture" },
  "0:211"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"keyboard"               , hint=>"Keyboard" },
  "0:212"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"code_reader"            , hint=>"Barcode_Scanner" },
  "0:213"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"code_reader"            , hint=>"QR_code_Scanner" },
  "0:214"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"distance"               , hint=>"Distance" },
  "0:215"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"sound"                  , hint=>"Sound" },
  "0:216"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"microphone"             , hint=>"Microphone" },
  "0:217"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>1, tds=>0, type=>"hid"                    , hint=>"HID_Device" },
  "0:218"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>1, tds=>0, type=>"rfid"                   , hint=>"RFID_Reader" },
  "0:219"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"proximity"              , hint=>"Proximity_Sensor" },
  "0:220"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"camera_still"           , hint=>"Camera" },
  "0:221"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"camera_video"           , hint=>"Video_Camera" },
  "0:222"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"compass"                , hint=>"Compass" },
  "0:223"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"location"               , hint=>"Location" },
  "0:224"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"light"                  , hint=>"Light" },
  "0:225"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"moisture"               , hint=>"Moisture" },
  "0:226"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"ph"                     , hint=>"pH_Sensor" },
  "0:227"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"geiger"                 , hint=>"Geiger_Counter" },
  "0:228"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>1, tds=>0, type=>"rf"                     , hint=>"RF_Transceiver" },
  "0:229"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>1, tds=>0, type=>"zigbee"                 , hint=>"Zigbee_Transceiver" },
  "0:230"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>1, tds=>0, type=>"zwave"                  , hint=>"Z-wave_Transceiver" },
  "0:231"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"alarm"                  , hint=>"Alarm" },
  "0:232"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"speaker"                , hint=>"Speaker" },
  "0:233"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"light_onoff"            , hint=>"Light" },
  "0:233"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"light_switch"           , hint=>"Light" },
  "0:234"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"light_dim"              , hint=>"Light_(Dimmable)" },
  "0:235"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"rgbled8"                , hint=>"RGB_Light_(Basic)" },
  "0:236"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"rgbled"                 , hint=>"RGB_Light" },
  "0:237"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"servo"                  , hint=>"Servo" },
  "0:238"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"relay"                  , hint=>"Relay" },
  "0:239"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"stepper"                , hint=>"Stepper" },
  "0:240"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"display_text"           , hint=>"Text_Display" },
  "0:241"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"display_image"          , hint=>"Image_Display" },
  "0:242"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"energy"                 , hint=>"Energy" },
  "0:243"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"power"                  , hint=>"Power" },
  "0:244"    => {st=>1, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"state"                  , hint=>"Generic_State_Device" },
  "0:255"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"screen_capture"         , hint=>"Screen_Capture" },
  "0:256"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"screen_capture"         , hint=>"Mac_Screen_Capture" },
  "0:260"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"presence"               , hint=>"Presence" },
  "0:261"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"presence"               , hint=>"Presence_-_Wifi_AP" },
  "0:262"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"presence"               , hint=>"Presence_-_Wifi_Client" },
  "0:263"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"presence"               , hint=>"Presence_-_Bluetooth" },
  "0:264"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"presence"               , hint=>"Presence_-_USB" },
  "0:265"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"presence"               , hint=>"Presence_-_IP" },
  "0:266"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"presence"               , hint=>"Presence_-_UPNP" },
  "0:267"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"presence"               , hint=>"Presence_-_Zeroconf" },
  "0:268"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"presence"               , hint=>"Presence_-_MAC" },
  "0:269"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"presence"               , hint=>"Presence_-_Xbox_Live" },
  "0:280"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"mediaplayer"            , hint=>"Media_Player" },
  "0:281"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"mediaplayer"            , hint=>"Media_Player_-_Xbmc" },
  "0:282"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"mediaplayer"            , hint=>"Media_Player_-_VLC" },
  "0:283"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"mediaplayer"            , hint=>"Media_Player_-_iTunes" },
  "0:284"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"mediaplayer"            , hint=>"Media_Player_-_Spotify" },
  "0:300"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"openurl"                , hint=>"Open_URL" },
  "0:310"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"notification"           , hint=>"Notification" },
  "0:311"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"notification"           , hint=>"Mac_Notification" },
  "0:320"    => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"lock-screen"            , hint=>"Lock_Screen" },
# "0:500"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"location"               , hint=>"Browser_GPS" },
# "0:500"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"cpu"                    , hint=>"CPU_Usage" },
  "0:501"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"cpu"                    , hint=>"NinjaBlock_CPU_Usage" },
  "0:502"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"cpu"                    , hint=>"Mac_CPU_Usage" },
  "0:503"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"cpu"                    , hint=>"Raspberry_Pi_CPU_Usage" },
  "0:510"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"temperature"            , hint=>"CPU_Temperature" },
  "0:511"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"temperature"            , hint=>"Raspberry_Pi_CPU_Temperature" },
  "0:512"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"temperature"            , hint=>"NinjaBlock_CPU_Temperature" },
  "0:513"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"temperature"            , hint=>"Mac_CPU_Temperature" },
  "0:520"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"ram"                    , hint=>"RAM_Usage" },
  "0:521"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"ram"                    , hint=>"NinjaBlock_RAM_Usage" },
  "0:522"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"ram"                    , hint=>"Mac_RAM_Usage" },
  "0:523"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"ram"                    , hint=>"Raspberry_Pi_RAM_Usage" },
  "0:530"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"network-activity"       , hint=>"Incoming_Network_Activity" },
  "0:531"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"network-activity"       , hint=>"NinjaBlock_Incoming_Network_Activity" },
  "0:532"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"network-activity"       , hint=>"Mac_Incoming_Network_Activity" },
  "0:533"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"network-activity"       , hint=>"Raspberry_Pi_Incoming_Network_Activity" },
  "0:540"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"network-activity"       , hint=>"Outgoing_Network_Activity" },
  "0:541"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"network-activity"       , hint=>"NinjaBlock_Outgoing_Network_Activity" },
  "0:542"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"network-activity"       , hint=>"Mac_Outgoing_Network_Activity" },
  "0:543"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"network-activity"       , hint=>"Raspberry_Pi_Outgoing_Network_Activity" },
  "0:550"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"battery"                , hint=>"Battery" },
  "0:551"    => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"battery"                , hint=>"Mac_Battery" },
  "0:600"    => {st=>1, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"ias_zone"               , hint=>"IAS_Zone" },
  "0:999"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"rgbled"                 , hint=>"On_Board_RGB_LED_v2" },
# "0:999"    => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"rgbled8"                , hint=>"Status_Light" },
  "0:1000"   => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"rgbled8"                , hint=>"On_Board_RGB_LED" },
  "0:1002"   => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>1, type=>"relay"                  , hint=>"Relay_Board" },
  "0:1003"   => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"system"                 , hint=>"Arduino_Version" },
  "0:1004"   => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"webcam"                 , hint=>"Web_Cam" },
  "0:1005"   => {st=>0, act=>1, sens=>1, sil=>1, sub=>0, tds=>0, type=>"network"                , hint=>"Network" },
  "0:1006"   => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"speech"                 , hint=>"USB_Text_to_Speech" },
  "0:1007"   => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"rgbled"                 , hint=>"Nina's_Eyes" },
  "0:1008"   => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"light"                  , hint=>"Philips_Hue" },
  "0:1009"   => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"relay"                  , hint=>"Belkin_WeMo_Socket" },
  "0:1010"   => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"light"                  , hint=>"ZigBee_Light" },
  "0:1011"   => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"light"                  , hint=>"Limitless_LED_RGB" },
  "0:1012"   => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"light"                  , hint=>"Limitless_LED_White" },
  "0:1020"   => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"speech"                 , hint=>"Text-to-Speech" },
  "0:1021"   => {st=>0, act=>1, sens=>0, sil=>0, sub=>0, tds=>0, type=>"speech"                 , hint=>"Mac_Text-to-Speech" },
  "0:2000"   => {st=>0, act=>1, sens=>1, sil=>0, sub=>1, tds=>1, type=>"sandbox"                , hint=>"Sandbox" },
  "0:3680"   => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"html"                   , hint=>"HTML" },
  "0:7000"   => {st=>0, act=>1, sens=>0, sil=>1, sub=>0, tds=>0, type=>"matrix_display"         , hint=>"LED_Board" },
  "0:9001"   => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"metric"                 , hint=>"Connected_Blocks" },
  "0:9002"   => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"metric"                 , hint=>"Redis_Response_Time" },
  "0:9003"   => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"metric"                 , hint=>"MySQL_Response_Time" },
  "0:10000"  => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"led"                    , hint=>"Browser_LED" },
  "2:9714"   => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"airconditioner"         , hint=>"Air_Conditioner" },
  "3:1"      => {st=>0, act=>1, sens=>1, sil=>0, sub=>0, tds=>0, type=>"relay"                  , hint=>"Power_Socket_Switch" },
  "3:2"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"power"                  , hint=>"Power_Usage" },
  "3:3"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"switch_sensor"          , hint=>"NetVox_Switch" },
  "3:11"     => {st=>0, act=>1, sens=>1, sil=>0, sub=>1, tds=>0, type=>"rf433"                  , hint=>"Camera_Control" },
  "4:2"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"meeting_length"         , hint=>"Meeting_Length" },
  "4:3"      => {st=>0, act=>0, sens=>1, sil=>0, sub=>0, tds=>1, type=>"room_utilisation"       , hint=>"Room_Utilisation" },
  "4:4"      => {st=>1, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"battery_alarm"          , hint=>"Battery_Alarm" },
  "4:5"      => {st=>1, act=>0, sens=>1, sil=>0, sub=>0, tds=>0, type=>"alarm"                  , hint=>"Zone_Alarm" }
);


sub
NINJA_Send($$@)
{
  my ($hash, $cmd, $data) = @_;

  $hash->{NINJA_lastSend} = TimeNow();

  my $msg = sprintf( "%i,%i,%i,%i,%i,%i,255,255,255,255s", hex($hash->{channel}),
                                                           $cmd,
                                                           hex(substr($hash->{addr},0,2)), hex(substr($hash->{addr},2,2)), hex(substr($hash->{addr},4,2)),
                                                           $data );

  IOWrite( $hash, $msg );
}

sub
NINJA_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return undef;
}

1;

=pod
=begin html

<a name="NINJA"></a>
<h3>NINJA</h3>
<ul>

  <tr><td>
  The NINJA is a RF controlled AC mains plug with integrated power meter functionality from ELV.<br><br>

  It can be integrated in to FHEM via a <a href="#JeeLink">JeeLink</a> as the IODevice.<br><br>

  The JeeNode sketch required for this module can be found in .../contrib/arduino/36_NINJA-pcaSerial.zip.<br><br>

  <a name="NINJADefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NINJA &lt;addr&gt; &lt;channel&gt;</code> <br>
    <br>
    addr is a 6 digit hex number to identify the NINJA device.
    channel is a 2 digit hex number to identify the NINJA device.<br><br>
    Note: devices are autocreated on reception of the first message.<br>
  </ul>
  <br>

  <a name="NINJA_Set"></a>
  <b>Set</b>
  <ul>
    <li>on</li>
    <li>off</li>
    <li>identify<br>
      Blink the status led for ~5 seconds.</li>
    <li>reset<br>
      Reset consumption counters</li>
    <li>statusRequest<br>
      Request device status update.</li>
    <li><a href="#setExtensions"> set extensions</a> are supported.</li>
  </ul><br>

  <a name="NINJA_Get"></a>
  <b>Get</b>
  <ul>
  </ul><br>

  <a name="NINJA_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>power</li>
    <li>consumption</li>
    <li>consumptionTotal<br>
      will be created as a default user reading to have a continous consumption value that is not influenced
      by the regualar reset or overflow of the normal consumption reading</li>
  </ul><br>

  <a name="NINJA_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>readonly<br>
    if set to a value != 0 all switching commands (on, off, toggle, ...) will be disabled.</li>
    <li>forceOn<br>
    try to switch on the device whenever an off status is received.</li>
  </ul><br>
</ul>

=end html
=cut
