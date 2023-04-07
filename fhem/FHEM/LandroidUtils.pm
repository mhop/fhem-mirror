##############################################
# $Id$
use strict;
use warnings;

# https://github.com/iobroker-community-adapters/ioBroker.worx
# https://forum.fhem.de/index.php?topic=111959

my %types = (
   worx => {
	url => "api.worxlandroid.com",
	loginUrl => "id.eu.worx.com",
	clientId => "150da4d2-bb44-433b-9429-3773adc70a2a", # OAuth Client ID
	mqttPrefix => "WX",
    },
    kress => {
	url => "api.kress-robotik.com",
	loginUrl => "id.eu.kress.com",
	clientId => "931d4bc4-3192-405a-be78-98e43486dc59",
	mqttPrefix => "KR",
    },
    landxcape => {
	url => "api.landxcape-services.com",
	loginUrl => "id.landxcape-services.com",
	clientId => "dec998a9-066f-433b-987a-f5fc54d3af7c",
	mqttPrefix => "LX",
    },
    ferrex => {
	url => "api.watermelon.smartmower.cloud",
	loginUrl => "id.watermelon.smartmower.cloud",
	clientId => "10078D10-3840-474A-848A-5EED949AB0FC",
	mqttPrefix => "FE",
    }
);

# Step 1: request & parse the access_token
sub
Landroid_connect($$)
{
  my ($m2c_name, $type) = @_;
  my $errPrefix = "ERROR: Landroid_connect $m2c_name -";
  my $m2c = $defs{$m2c_name}; 
  my $usr = AttrVal($m2c_name, "username", "");
  my $pwd = getKeyValue($m2c_name);

  return Log 1, "$errPrefix no such definition" if(!$m2c);
  return Log 1, "$errPrefix no username attribute" if(!$usr);
  return Log 1, "$errPrefix no password set" if(!$pwd);
  return Log 1, "$errPrefix unknown type $type" if(!$types{$type});

  $m2c->{landroidType} = $type;
  my $t = $types{$type};
  RemoveInternalTimer("landroidTmr_$m2c_name");

  my $rt = ReadingsVal($m2c_name, ".refresh_token", undef);
  my $ra = ReadingsAge($m2c_name, ".refresh_token", 0);
  my $data;
  if($rt && $ra < 1800) { # refresh
    $data = { grant_type=>"refresh_token", refresh_token=>$rt,
             client_id=>$t->{clientId}, scope=>"*" };
    $ra = 3600-$ra;

  } else {
    $data = { grant_type=>"password", username=>$usr, password=>$pwd, 
             client_id=>$t->{clientId}, scope=>"*" };
    $ra = 3600;
  }

  HttpUtils_NonblockingGet({
    url=>"https://$t->{loginUrl}/oauth/token",
    callback=> sub($$$){
      my ($h,$e,$d) = @_;
      return Log3 $m2c, 1, "$errPrefix: $e" if($e);
      return Log3 $m2c, 1, "$errPrefix: no data" if(!$d);
      Log3 $m2c, 5, $d;
      $m2c->{".auth"} = json2nameValue($d);
      return Log3 $m2c, 1, "$errPrefix: no access_token"
        if(!$m2c->{".auth"}{access_token});
      Log3 $m2c, 4, "$m2c_name: Got auth info";
      setReadingsVal($m2c, ".refresh_token",
                     $m2c->{".auth"}{refresh_token}, TimeNow());
      InternalTimer(gettimeofday()+$ra-60,
        sub(){ Landroid_connect($m2c_name, $type)}, "landroidTmr_$m2c_name", 0);
      Landroid_connect2($m2c_name);
    },
    header => {
      "Accept"=>"application/json",
      "Content-Type"=>"application/json",
    },
    data => toJSON($data)
  });
}

# Step 2: get userId & mqttEndpoint
sub
Landroid_connect2($)
{
  my ($m2c_name) = @_;
  my $m2c = $defs{$m2c_name};

  my $errPrefix = "ERROR: Landroid_connect2 $m2c_name -";
  my $t = $types{$m2c->{landroidType}};
  my $p = $m2c->{".auth"};

  HttpUtils_NonblockingGet({
    url => "https://$t->{url}/api/v2/users/me",
    header => { 
      "Accept"=>"application/json",
      "Authorization"=>"Bearer ".$p->{access_token},
    },
    callback=>sub($$$){
      my ($h,$e,$d) = @_;
      return Log3 $m2c, 1, "$errPrefix: $e" if($e);
      return Log3 $m2c, 1, "$errPrefix: no data" if(!$d);
      Log3 $m2c, 5, $d;
      my $me = json2nameValue($d);
      return Log3 $m2c, 1, "$errPrefix: no userId/mqttEndpoint"
        if(!$me->{userId} || !$me->{mqttEndpoint});
      Log3 $m2c, 4, "$m2c_name: Got userId/mqttEndpoint";
      $m2c->{userId} = $me->{id};
      $m2c->{mqttEndpoint} = $me->{mqtt_endpoint};
      Landroid_connect3($m2c);
    }
  });
}

# Step 3: get device list & create devices if necessary
sub
Landroid_connect3($)
{
  my ($m2c_name) = @_;
  my $m2c = $defs{$m2c_name};
  my $p = $m2c->{".auth"};
  my $t = $types{$m2c->{landroidType}};
  my $errPrefix = "ERROR: Landroid_connect3 $m2c_name -";

  HttpUtils_NonblockingGet({
    url => "https://$t->{url}/api/v2/product-items?status=1",
    header => { 
      "Accept"=>"application/json",
      "Authorization"=>"Bearer ".$p->{access_token},
    },
    callback => sub(){
      my ($h,$e,$d) = @_;
      return Log3 $m2c, 1, "$errPrefix: $e" if($e);
      return Log3 $m2c, 1, "$errPrefix: no data" if(!$d);
      Log3 $m2c, 5, $d;
      my $dl = json2nameValue($d); # DeviceList
      return Log3 $m2c, 1, "$errPrefix - no devicelist" if(!$dl);
      Log3 $m2c, 4, "$m2c_name: Got device info";
      my %sn;
      for my $d (keys %defs) {
        my $sn = ReadingsVal($d, "serial_number", "");
        $sn{$sn} = $defs{$d} if($sn);
      }

      # Write the readings to the right MQTT2_DEVICE instance
      my (@cmds, @subs);
      my $now = TimeNow();
      for(my $i1=1; ; $i1++) {
        my $sn = $dl->{$i1."_serial_number"};
        last if(!$sn);
        my $m2d = $sn{$sn};
        if(!$m2d) {
          my $m2d_name = makeDeviceName($m2c_name."_".$dl->{$i1."_name"});
          DoTrigger("global", "UNDEFINED $m2d_name MQTT2_DEVICE $sn");
          $m2d = $defs{$m2d_name};
          next if(!$m2d);
          $attr{$m2d_name}{IODev} = $m2c->{NAME};
        }

        for my $key (keys %{$dl}) {
          next if($key =~ m/^${i1}_(auto_schedule|last_status)/);
          next if($key !~ m/^${i1}_(.*)/);
          my $readingName = $1;
          my $val = $dl->{$key};
          next if(!defined($val));
          $val =~ s,\\/,/,g; # Bug in the backend?
          setReadingsVal($m2d, $readingName, $val, $now);
          push @subs, $val if($readingName eq "mqtt_topics_command_out");
          if($readingName eq "mqtt_topics_command_in") {
            push @cmds, $val;
            $attr{$m2d->{NAME}}{readingList}="$val:.* {json2nameValue(\$EVENT)}"
              if(!$attr{$m2d->{NAME}}{readingList});
          }
        }
      }
      my $a = $attr{$m2c_name};
      $a->{subscriptions} = join(" ", @subs);
      $a->{execAfterConnect} = '{ my $h=$defs{$NAME};'. # } vim needs it
        join(";", map { "MQTT2_CLIENT_doPublish(\$h,'$_','{}')" } @cmds).'}';
      Landroid_connect4($m2c_name);
    }
  });
}

# Step4: prepare MQTT2_CLIENT
sub
Landroid_connect4($)
{
  my ($m2c_name) = @_;
  my $m2c = $defs{$m2c_name};

  my $at = $m2c->{".auth"}{access_token};
  $at =~ tr,_-,/+,; # base64 url-safe to standard base64 
  my @token = map { urlEncode($_) } split('[.]', $at);
  $m2c->{".usr"} = "FHEM?jwt=$token[0].$token[1]&".
                   "x-amz-customauthorizer-signature=$token[2]";
  $m2c->{".pwd"} = "";
  $m2c->{DeviceName} = "$m2c->{mqttEndpoint}:443";
  $m2c->{sslargs}{SSL_alpn_protocols} = "mqtt";
  $m2c->{SSL} = 1;

  my $wxid = ReadingsVal($m2c_name, "wxid", undef);
  if(!defined($wxid)) {
    $wxid = genUUID();
    setReadingsVal($m2c, "wxid", $wxid, TimeNow());
  }
  my $prefix = $types{$m2c->{landroidType}}{mqttPrefix};
  $m2c->{clientId} = "$prefix/USER/$m2c->{userId}/FHEM/$wxid";

  my $a = $attr{$m2c_name};
  $a->{keepaliveTimeout} = 600;
  $a->{maxFailedConnects} = 1;
  #MQTT2_CLIENT_connect($defs{$m2c_name}, 1);
}

1;
