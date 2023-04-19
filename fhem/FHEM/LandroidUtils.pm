##############################################
# $Id$
use strict;
use warnings;

# https://github.com/iobroker-community-adapters/ioBroker.worx
# https://forum.fhem.de/index.php?topic=111959
#
# Usage:
#   define m2c MQTT2_CLIENT xx
#   attr m2c username a@bc.de
#   attr m2c connectFn {use LandroidUtils;;Landroid_connect($NAME,"worx",1)}
#   set m2c password mySecret
# If the last parameter to Landroid_connect is 1, devices will be autocreated
# For debugging use "attr m2c verbose 4"
# 
# Developer stuff:
# - access_token is a three-part entity, it is used for HTTP requesting data
#   or MQTT-Connect, it is valid for 1h
# - refresh_token is used to get a new access_token, validity period unclear
# - auth with user/pw should be avoided, unclear why

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

# Step 1: check parameters, request & parse the access_token
sub
Landroid_connect($$;$$)
{
  my ($m2c_name, $type, $autocreate, $noToCheck) = @_;
  my $m2c = $defs{$m2c_name}; 

  if(!$noToCheck && $m2c->{".CONNECT_TO"} &&
     gettimeofday() < $m2c->{".CONNECT_TO"}) {
    delete($m2c->{inConnectFn});
    $readyfnlist{"$m2c_name.$m2c->{DeviceName}"} = $m2c;
    return;
  }
  $m2c->{".CONNECT_TO"} = gettimeofday()+AttrVal($m2c_name,"nextOpenDelay",180);

  my $errPrefix = "ERROR: Landroid_connect $m2c_name -";
  my $usr = AttrVal($m2c_name, "username", "");
  my $pwd = getKeyValue($m2c_name);

  return Log 1, "$errPrefix no such definition" if(!$m2c);
  return Log 1, "$errPrefix no username attribute" if(!$usr);
  return Log 1, "$errPrefix no password set" if(!$pwd);
  return Log 1, "$errPrefix unknown type $type" if(!$types{$type});

  $m2c->{landroidType} = $type;
  $m2c->{autocreate} = $autocreate ? 1 : 0;
  my $t = $types{$type};

  if(ReadingsVal($m2c_name, ".access_token", undef) &&
       ReadingsAge($m2c_name, ".access_token", 0) <
       ReadingsVal($m2c_name, ".expires_in", 0)) {
    Log3 $m2c, 4, "$m2c_name: reusing the acess_token";
    return Landroid_connect2($m2c_name);
  }

  my $rt = ReadingsVal($m2c_name, ".refresh_token", undef);
  my $data;
  if($rt) { # try refresh first
    $data = { grant_type=>"refresh_token", refresh_token=>$rt,
             client_id=>$t->{clientId}, scope=>"*" };

  } else {
    $data = { grant_type=>"password", username=>$usr, password=>$pwd, 
             client_id=>$t->{clientId}, scope=>"*" };
  }

  HttpUtils_NonblockingGet({
    url=>"https://$t->{loginUrl}/oauth/token",
    timeout=>60,
    callback=> sub($$$){
      my ($h,$e,$d) = @_;
      return Landroid_retry($m2c, "$errPrefix $e") if($e);
      return Landroid_retry($m2c, "$errPrefix no data") if(!$d);
      Log3 $m2c, 5, $d;
      my $auth = json2nameValue($d);
      if(!$auth->{access_token}) {
        if($data->{grant_type} eq "refresh_token") {
          readingsDelete($m2c, ".refresh_token");
          Log3 $m2c, 4, "$errPrefix refresh_token failed, trying full auth";
          Landroid_connect($m2c_name, $type, $autocreate, 1);
        } else {
          Landroid_retry($m2c, "$errPrefix got no access_token", $d);
        }
        return;
      }

      Log3 $m2c, 4, "$m2c_name: Got auth info, type ".$data->{grant_type};
      map { setReadingsVal($m2c, ".$_", $auth->{$_}, TimeNow()) }
            ( "refresh_token", "access_token", "expires_in", "token_type");
      Landroid_connect2($m2c_name);
    },
    header => {
      "Accept"=>"application/json",
      "Content-Type"=>"application/json",
    },
    data => toJSON($data)
  });
}

# Step 2: get userId
sub
Landroid_connect2($)
{
  my ($m2c_name) = @_;
  my $m2c = $defs{$m2c_name};

  my $errPrefix = "ERROR: Landroid_connect2 $m2c_name -";
  my $t = $types{$m2c->{landroidType}};

  HttpUtils_NonblockingGet({
    url => "https://$t->{url}/api/v2/users/me",
    header => { 
      "Accept"=>"application/json",
      "Authorization"=>"Bearer ".ReadingsVal($m2c_name,".access_token","")
    },
    callback=>sub($$$){
      my ($h,$e,$d) = @_;
      return Landroid_retry($m2c, "$errPrefix $e") if($e);
      return Landroid_retry($m2c, "$errPrefix no data") if(!$d);
      Log3 $m2c, 5, $d;
      my $me = json2nameValue($d);
      if(!$me->{id}) {
        if($m2c->{authRetry}) {
          Landroid_retry($m2c, "$errPrefix no userId after auth retry", $d);
        } else {
          $m2c->{authRetry} = 1;
          readingsDelete($m2c, ".access_token");
          Log3 $m2c, 4, "$errPrefix no userId, retrying auth / $d";
          Landroid_connect($m2c_name,$m2c->{landroidType},$m2c->{autocreate},1);
        }
        return;
      }
      delete($m2c->{authRetry});
      Log3 $m2c, 4, "$m2c_name: Got userId: $me->{id}";
      $m2c->{userId} = $me->{id};
      Landroid_connect3($m2c_name);
    }
  });
}

# Step 3: get device list & create MQTT2_DEVICEs if necessary
sub
Landroid_connect3($)
{
  my ($m2c_name) = @_;
  my $m2c = $defs{$m2c_name};
  my $t = $types{$m2c->{landroidType}};
  my $errPrefix = "ERROR: Landroid_connect3 $m2c_name -";

  HttpUtils_NonblockingGet({
    url => "https://$t->{url}/api/v2/product-items?status=1",
    header => { 
      "Accept"=>"application/json",
      "Authorization"=>"Bearer ".ReadingsVal($m2c_name,".access_token","")
    },
    callback => sub(){
      my ($h,$e,$d) = @_;
      return Landroid_retry($m2c, "$errPrefix $e") if($e);
      return Landroid_retry($m2c, "$errPrefix no data") if(!$d);
      Log3 $m2c, 5, $d;
      my $dl = json2nameValue($d); # DeviceList
      return Landroid_retry($m2c, "$errPrefix no devicelist") if(!$dl);
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
        if(!$m2d && $m2c->{autocreate}) {
          my $m2d_name = makeDeviceName($m2c_name."_".$dl->{$i1."_name"});
          DoTrigger("global", "UNDEFINED $m2d_name MQTT2_DEVICE $sn");
          $m2d = $defs{$m2d_name};
          $attr{$m2d_name}{IODev} = $m2c->{NAME} if($m2d);
        }
         my $m2d_name = $m2d ? $m2d->{NAME} : "";

        for my $key (keys %{$dl}) {
          next if($key =~ m/^${i1}_(auto_schedule|last_status)/);
          next if($key !~ m/^${i1}_(.*)/);
          my $readingName = $1;
          my $val = $dl->{$key};
          next if(!defined($val));
          $val =~ s,\\/,/,g; # Bug in the backend?
          setReadingsVal($m2d, $readingName,$val,$now)
                if($m2c->{autocreate} && $m2d);
          push @cmds, $val if($readingName eq "mqtt_topics_command_in");
          if($readingName eq "mqtt_topics_command_out") {
            push @subs, $val;
            $attr{$m2d_name}{readingList}="$val:.* {json2nameValue(\$EVENT)}"
                if($m2c->{autocreate} && $m2d &&
                   !AttrVal($m2d_name, "readingList", undef));
          }
          $m2c->{mqttEndpoint} = $val if($readingName eq "mqtt_endpoint");
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

  my $at = ReadingsVal($m2c_name, ".access_token", "");
  $at =~ tr,_-,/+,; # base64 url-safe to standard base64 
  my @token = map { urlEncode($_) } split('[.]', $at);
  $m2c->{".usr"} = "FHEM?jwt=$token[0].$token[1]&".
                   "x-amz-customauthorizer-signature=$token[2]";
  $m2c->{".pwd"} = "";
  $m2c->{DeviceName} = "$m2c->{mqttEndpoint}:443";
  $m2c->{sslargs}{SSL_alpn_protocols} = "mqtt";
  $m2c->{SSL} = 1;
  $m2c->{devioLoglevel} = AttrVal($m2c_name, "verbose", 4);

  my $wxid = ReadingsVal($m2c_name, "wxid", undef);
  if(!defined($wxid)) {
    $wxid = genUUID();
    setReadingsVal($m2c, "wxid", $wxid, TimeNow());
  }
  my $prefix = $types{$m2c->{landroidType}}{mqttPrefix};
  $m2c->{clientId} = "$prefix/USER/$m2c->{userId}/FHEM/$wxid";

  my $a = $attr{$m2c_name};
  $a->{keepaliveTimeout} = 600
        if(!defined(AttrVal($m2c_name, "keepaliveTimeout", undef)));
  $a->{maxFailedConnects} =  20
        if(!defined(AttrVal($m2c_name, "maxFailedConnects", undef)));
  $a->{nextOpenDelay} = 180
        if(!defined(AttrVal($m2c_name, "nextOpenDelay", undef)));

  MQTT2_CLIENT_Disco($m2c); # Make sure reconnect will work
  delete $readyfnlist{"$m2c_name.".$m2c->{DeviceName}};
  delete $m2c->{DevIoJustClosed};
  MQTT2_CLIENT_connect($m2c, 1);
}

# Log error, and retry it later, triggered from ReadyFn
sub
Landroid_retry($$;$)
{
  my ($m2c, $err, $debug) = @_;
  Log3 $m2c, 1, $err;
  Log3 $m2c, 4, $debug if($debug);
  delete($m2c->{inConnectFn});
  $readyfnlist{"$m2c->{NAME}.$m2c->{DeviceName}"} = $m2c;
}

1;
