##############################################
# $Id$$$ 2018-11-01
#
#  98_livetracking.pm
#
#  2019 Markus Moises < vorname at nachname . de >
#
#  This module provides livetracking data from OwnTracks, OpenPaths, Life360 and Swarm (FourSquare)
#
#
##############################################################################
#
# define <name> livetracking <life360_user> <life360_pass> <openpaths_key> <openpaths_secret> <swarm_token>
#
##############################################################################

package main;

use strict;
use warnings;
no warnings qw(redefine);

#use Math::Round;
#use Net::OAuth;

use JSON;
use Time::Local;
use URI::Escape;
use Data::Dumper;
use Encode qw(encode_utf8 decode_utf8);

use utf8;

my $libcheck_hasOAuth = 1;

##############################################################################


sub livetracking_Initialize($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  eval "use Net::OAuth;";
  $libcheck_hasOAuth = 0 if($@);

  $hash->{DefFn}            =   "livetracking_Define";
  $hash->{UndefFn}          =   "livetracking_Undefine";
  $hash->{GetFn}            =   "livetracking_Get";
  $hash->{SetFn}            =   "livetracking_Set";
  $hash->{AttrFn}           =   "livetracking_Attr";
  $hash->{NotifyFn}         =   "livetracking_Notify";
  $hash->{NotifyOrderPrefix}=   "999-";
  $hash->{DbLog_splitFn}    =   "livetracking_DbLog_splitFn";
  $hash->{AttrList}         =   "disable:1 ".
                                "roundAltitude ".
                                "roundDistance ".
                                "filterAccuracy ".
                                "interval ".
                                "home ".
                                "swarmHome ".
                                "owntracksDevice ".
                                "beacon_0 ".
                                "beacon_1 ".
                                "beacon_2 ".
                                "beacon_3 ".
                                "beacon_4 ".
                                "beacon_5 ".
                                "beacon_6 ".
                                "beacon_7 ".
                                "beacon_8 ".
                                "beacon_9 ".
                                "zonename_0 ".
                                "zonename_1 ".
                                "zonename_2 ".
                                "zonename_3 ".
                                "zonename_4 ".
                                "zonename_5 ".
                                "zonename_6 ".
                                "zonename_7 ".
                                "zonename_8 ".
                                "zonename_9 ".
                                "batteryWarning:5,10,15,20,25,30,35,40 ".
                                "addressLanguage:de,en,fr,es,it,nl ".
                                "addressReading:0,1 ".
                                "osmandServer:0,1 ".
                                "osmandId ".
                                "life360_userid ".
                                "life360_circle ".
                                $readingFnAttributes;


}

sub livetracking_Define($$$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> livetracking <life360_user> <life360_pass> <openpaths_key> <openpaths_secret> <swarm_token>" if(int(@a) < 2 || int(@a) > 7 );
  my $name = $hash->{NAME};

  #$hash->{OAuth_exists} = $libcheck_hasOAuth if($libcheck_hasOAuth);

  if(int(@a) == 4 ) {
    if ($a[2] =~ /@/) {
      $hash->{helper}{life360_user} = $a[2];
      $hash->{helper}{life360_pass} = $a[3];
    } else {
      $hash->{helper}{openpaths_key} = $a[2];# if($hash->{OAuth_exists});
      $hash->{helper}{openpaths_secret} = $a[3];# if($hash->{OAuth_exists});
    }
  }
  elsif(int(@a) == 3 ) {
    $hash->{helper}{swarm_token} = $a[2];
  }
  elsif(int(@a) == 5 ) {
    if ($a[2] =~ /@/) {
      $hash->{helper}{life360_user} = $a[2];
      $hash->{helper}{life360_pass} = $a[3];
    } else {
      $hash->{helper}{openpaths_key} = $a[2];# if($hash->{OAuth_exists});
      $hash->{helper}{openpaths_secret} = $a[3];# if($hash->{OAuth_exists});
    }
    $hash->{helper}{swarm_token} = $a[4];
  }
  elsif(int(@a) == 7 ) {
    $hash->{helper}{life360_user} = $a[2];
    $hash->{helper}{life360_pass} = $a[3];
    $hash->{helper}{openpaths_key} = $a[4];# if($hash->{OAuth_exists});
    $hash->{helper}{openpaths_secret} = $a[5];# if($hash->{OAuth_exists});
    $hash->{helper}{swarm_token} = $a[6];
  }


  my $req = eval
  {
    require XML::Simple;
    XML::Simple->import();
    1;
  };

  if($req)
  {
    $hash->{NOTIFYDEV} = AttrVal($name, "owntracksDevice" , "owntracks");
  }
  else
  {
    $hash->{STATE} = "XML::Simple is required!";
    $attr{$name}{disable} = "1";
    return undef;
  }


  # my $resolve = inet_aton("api.foursquare.com");
  # if(!defined($resolve) && defined($hash->{helper}{swarm_token}))
  # {
  #   $hash->{STATE} = "DNS error";
  #   InternalTimer( gettimeofday() + 1800, "livetracking_GetAll", $hash, 0);
  #   return undef;
  # }

  InternalTimer( gettimeofday() + 60, "livetracking_GetSwarm", $hash, 0) if(defined($hash->{helper}{swarm_token}));

  # $resolve = inet_aton("openpaths.cc");
  # if(!defined($resolve) && defined($hash->{helper}{openpaths_key}))
  # {
  #   $hash->{STATE} = "DNS error";
  #   InternalTimer( gettimeofday() + 1800, "livetracking_GetAll", $hash, 0);
  #   return undef;
  # }

  InternalTimer( gettimeofday() + 90, "livetracking_GetOpenPaths", $hash, 0) if(defined($hash->{helper}{openpaths_key}));


  if (!defined($attr{$name}{stateFormat}))
  {
    $attr{$name}{stateFormat} = 'location';
  }

  livetracking_BootstrapLife360($hash) if(defined($hash->{helper}{life360_user}));


  livetracking_addExtension($hash) if(AttrVal($name, "osmandServer", 0) == 1);

  #$hash->{STATE} = "Initialized";

  return undef;
}

sub livetracking_Undefine($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer($hash);
  livetracking_removeExtension($hash) if(AttrVal($name, "osmandServer", 0) == 1);
  return undef;
}


sub livetracking_Set($$@) {
  my ($hash, $name, $command, @parameters) = @_;

  my $usage = "Unknown argument $command, choose one of";
  if(defined($attr{$name}{owntracksDevice}))
  {
    $usage .= " owntracksMessage";
  }
  if(defined($hash->{helper}{life360_user}))
  {
    $usage .= "  BootstrapLife360:noArg";
  }

  if(!defined($hash->{helper}{life360_user}) && !defined($attr{$name}{owntracksDevice}))
  {
    $usage = undef;
  }

  return $usage if $command eq '?';

  my $devname=AttrVal($name, "owntracksDevice" , "owntracks" );

  if($command eq 'owntracksMessage') {
    my $messagetext = join( ' ', @parameters );
    my $notifytext = '';
    $notifytext = '"notify":"FHEM: ' . join( ' ', @parameters ).'",' if($messagetext !~ /</ || $messagetext !~ />/);
    if($messagetext eq "")
    {
      $messagetext = '';
    }
    elsif($messagetext !~ /</ || $messagetext !~ />/)
    {
      $messagetext = '"content":"'.FmtDateTime(time()).'<br/>FHEM: <br/><br/>'.$messagetext.'",';
    }

    fhem('set '.$devname.' cmd {"_type":"cmd","action":"action",'.$messagetext.$notifytext.'"tst":'.time().'}');
    #fhem('set '.$devname.' msg {"_type":"cmd","action":"notify", "content":"'.$notifytext.'","tst":'.time().'}') if($notifytext ne "");
  }
  elsif($command eq "BootstrapLife360")
  {
    $hash->{helper}{life360_script} = "";
    $hash->{helper}{life360_secret} = "";
    $hash->{helper}{life360_token} = "";
    livetracking_BootstrapLife360($hash);
  }

  return undef;
}

sub livetracking_Get($@) {
  my ($hash, @a) = @_;
  my $command = $a[1];
  my $parameter = $a[2];# if(defined($a[2]));
  my $name = $hash->{NAME};


  my $usage = "Unknown argument $command, choose one of All:noArg";
  $usage .= " OpenPaths:noArg" if(defined($hash->{helper}{openpaths_key}));
  $usage .= " Swarm:noArg" if(defined($hash->{helper}{swarm_token}));
  $usage .= " owntracksLocation:noArg owntracksSteps:noArg" if(defined($attr{$name}{owntracksDevice}));
  $usage .= " address";
  $usage .= " Life360:noArg" if(defined($hash->{helper}{life360_user}));

  return $usage if $command eq '?';

  if(AttrVal($name, "disable", 0) eq 1)
  {
    return "livetracking $name is disabled. Aborting...";
  }

  my $devname = AttrVal($name, "owntracksDevice" , "owntracks" );

  if($command eq "All")
  {
    livetracking_GetAll($hash);
  }
  elsif($command eq "OpenPaths")
  {
    livetracking_GetOpenPaths($hash);
  }
  elsif($command eq "Swarm")
  {
    livetracking_GetSwarm($hash);
  }
  elsif($command eq 'owntracksLocation') {
     fhem('set '.$devname.' cmd {"_type":"cmd","action":"reportLocation"}');
     return undef;
  }
  elsif($command eq 'owntracksSteps') {
     fhem('set '.$devname.' cmd {"_type":"cmd","action":"reportSteps"}');
     return undef;
  }
  elsif($command eq 'address') {
     my @location = split(",",ReadingsVal($name,"location","0,0"));
     $parameter = "" if(!defined($parameter));
     if($parameter =~ /,/){
       @location = split(",",$parameter);
     }
     my $lang = AttrVal($name,"addressLanguage","en");
     if(defined($location[1])) {
       my($err,$data) = HttpUtils_BlockingGet({
         url => "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=".$location[0]."&lon=".$location[1]."&addressdetails=1&accept-language=$lang",
         noshutdown => 1,
       });
       return "data error" if($err);
       return "invalid json" if( $data !~ m/^{.*}$/ && $data !~ m/^\[.*\]$/ );
       my $json = eval { JSON->new->utf8(0)->decode($data) };
       return "invalid json evaluation" if($@);
       if( $parameter eq "short" && defined($json->{display_name}) ) {
         readingsSingleUpdate($hash,"address",livetracking_utf8clean($json->{display_name}),1) if(AttrVal($name,"addressReading",0));
         return livetracking_utf8clean($json->{display_name});
       } elsif( defined($json->{address}) ) {
         my $addr = "";
         if($parameter eq "long"){
           $addr .= $json->{address}->{housename}."\n" if(defined($json->{address}->{housename}));
           $addr .= $json->{address}->{parking}."\n" if(defined($json->{address}->{parking}));
           $addr .= $json->{address}->{locality}."\n" if(defined($json->{address}->{locality}));
         }
         $addr .= $json->{address}->{road}." " if(defined($json->{address}->{road}));
         $addr .= $json->{address}->{path}." " if(defined($json->{address}->{path}) && !defined($json->{address}->{road}));
         $addr .= $json->{address}->{bridleway}." " if(defined($json->{address}->{bridleway}) && !defined($json->{address}->{road}) && !defined($json->{address}->{path}));
         $addr .= $json->{address}->{footway}." " if(defined($json->{address}->{footway}) && !defined($json->{address}->{road}) && !defined($json->{address}->{path}) && !defined($json->{address}->{bridleway}));
         $addr .= $json->{address}->{square}." " if(defined($json->{address}->{square}) && !defined($json->{address}->{road}) && !defined($json->{address}->{path}) && !defined($json->{address}->{bridleway}) && !defined($json->{address}->{footway}));
         $addr .= $json->{address}->{neighbourhood}." " if(defined($json->{address}->{neighbourhood}) && !defined($json->{address}->{road}) && !defined($json->{address}->{path}) && !defined($json->{address}->{bridleway}) && !defined($json->{address}->{footway}) && !defined($json->{address}->{square}));
         $addr .= $json->{address}->{city_block}." " if(defined($json->{address}->{city_block}) && !defined($json->{address}->{road}) && !defined($json->{address}->{path}) && !defined($json->{address}->{bridleway}) && !defined($json->{address}->{footway}) && !defined($json->{address}->{square}) && !defined($json->{address}->{neighbourhood}));
         $addr .= $json->{address}->{hamlet}." " if(defined($json->{address}->{hamlet}) && !defined($json->{address}->{road}) && !defined($json->{address}->{path}) && !defined($json->{address}->{bridleway}) && !defined($json->{address}->{footway}) && !defined($json->{address}->{square}) && !defined($json->{address}->{neighbourhood}) && !defined($json->{address}->{city_block}));
         $addr .= $json->{address}->{isolated_dwelling}." " if(defined($json->{address}->{isolated_dwelling}) && !defined($json->{address}->{road}) && !defined($json->{address}->{path}) && !defined($json->{address}->{bridleway}) && !defined($json->{address}->{footway}) && !defined($json->{address}->{square}) && !defined($json->{address}->{neighbourhood}) && !defined($json->{address}->{city_block}) && !defined($json->{address}->{hamlet}));
         $addr .= $json->{address}->{farm}." " if(defined($json->{address}->{farm}) && !defined($json->{address}->{road}) && !defined($json->{address}->{path}) && !defined($json->{address}->{bridleway}) && !defined($json->{address}->{footway}) && !defined($json->{address}->{square}) && !defined($json->{address}->{neighbourhood}) && !defined($json->{address}->{city_block}) && !defined($json->{address}->{hamlet}) && !defined($json->{address}->{isolated_dwelling}));
         $addr .= $json->{address}->{house_number} if(defined($json->{address}->{house_number}));
         #$addr .= "\n".$json->{address}->{neighbourhood} if(defined($json->{address}->{neighbourhood}) && $parameter eq "long");
         #if($parameter eq "long"){
         #  $addr .= "\n".$json->{address}->{suburb} if(defined($json->{address}->{suburb}));
         #}
         $addr .= (($parameter eq "singleline")?", ":"\n") if(defined($json->{address}->{postcode}) || defined($json->{address}->{city}) || defined($json->{address}->{town}) || defined($json->{address}->{village}) || defined($json->{address}->{hamlet}) || defined($json->{address}->{suburb}));
         $addr .= $json->{address}->{postcode}." " if(defined($json->{address}->{postcode}));
         $addr .= $json->{address}->{city} if(defined($json->{address}->{city}));
         $addr .= $json->{address}->{town}." " if(defined($json->{address}->{town}) && !defined($json->{address}->{city}));
         $addr .= $json->{address}->{village}." " if(defined($json->{address}->{village}) && !defined($json->{address}->{city}) && !defined($json->{address}->{town}));
         $addr .= $json->{address}->{borough}." " if(defined($json->{address}->{borough}) && !defined($json->{address}->{city}) && !defined($json->{address}->{town}) && !defined($json->{address}->{village}));
         $addr .= $json->{address}->{suburb}." " if(defined($json->{address}->{suburb}) && !defined($json->{address}->{city}) && !defined($json->{address}->{town}) && !defined($json->{address}->{village}) && !defined($json->{address}->{borough}));
         $addr .= $json->{address}->{quarter}." " if(defined($json->{address}->{quarter}) && !defined($json->{address}->{city}) && !defined($json->{address}->{town}) && !defined($json->{address}->{village}) && !defined($json->{address}->{borough}) && !defined($json->{address}->{suburb}));
         $addr .= $json->{address}->{municipality}." " if(defined($json->{address}->{municipality}) && !defined($json->{address}->{city}) && !defined($json->{address}->{town}) && !defined($json->{address}->{village}) && !defined($json->{address}->{borough}) && !defined($json->{address}->{suburb}) && !defined($json->{address}->{quarter}));
         $addr .= $json->{address}->{hamlet}." " if(defined($json->{address}->{hamlet}) && !defined($json->{address}->{city}) && !defined($json->{address}->{town}) && !defined($json->{address}->{village}) && !defined($json->{address}->{borough}) && !defined($json->{address}->{suburb}) && !defined($json->{address}->{quarter}) && !defined($json->{address}->{municipality}));
         if($parameter eq "long"){
           $addr .= "\n".$json->{address}->{county} if(defined($json->{address}->{county}));
           $addr .= "\n" if((defined($json->{address}->{state_district}) || defined($json->{address}->{state})));
           $addr .= $json->{address}->{state_district}." " if(defined($json->{address}->{state_district}));
           $addr .= $json->{address}->{state} if(defined($json->{address}->{state}));
         }
         $addr .= (($parameter eq "singleline")?", ":"\n").$json->{address}->{country} if(defined($json->{address}->{country}));
         Log3 ($name, 4, "$name: address received\n".Dumper($json));
         readingsSingleUpdate($hash,"address",livetracking_utf8clean($addr),1) if(AttrVal($name,"addressReading",0));
         return livetracking_utf8clean($addr);
       } elsif( defined($json->{display_name}) ) {
         readingsSingleUpdate($hash,"address",livetracking_utf8clean($json->{display_name}),1) if(AttrVal($name,"addressReading",0));
         return livetracking_utf8clean($json->{display_name});
       } else {
         return "no data";
       }
     } else {
       return "invalid coordinates";
     }
     return undef;
  }


  elsif($command eq "Life360")
  {
    livetracking_GetLife360($hash);
  }



  return undef;
}


sub livetracking_Attr(@) {
  my ($command, $name, $attr, $val) = @_;
  my $hash = $defs{$name};
  if ($attr && $attr eq 'owntracksDevice') {
    $hash->{NOTIFYDEV} = $val if defined $val;
  }
  elsif ($attr && $attr =~ /^(zonename_)([0-9]+)/) {
    fhem( "deletereading $name zone_".$2 );
  }
  elsif ($attr && $attr =~ /^(beacon_)([0-9]+)/) {
    fhem( "deletereading $name beacon_".$2.".*" );
  }
  elsif ($attr && $attr eq 'osmandServer') {
    if($command eq "set" && $val == 1){
      livetracking_addExtension($hash);
    } else {
      livetracking_removeExtension($hash);
    }
  }
  return undef;
}


sub livetracking_GetAll($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);

  if(AttrVal($name, "disable", 0) eq 1)
  {
    Log3 ($name, 4, "livetracking $name is disabled, data update cancelled.");
    return undef;
  }

  if(defined($attr{$name}{owntracksDevice}))
  {
    my $devname=AttrVal($name, "owntracksDevice" , "owntracks" );
    fhem('set '.$devname.' cmd {"_type":"cmd","action":"reportLocation"}');
  }

  # my $resolve = inet_aton("api.foursquare.com");
  # if(!defined($resolve) && defined($hash->{helper}{swarm_token}))
  # {
  #   $hash->{STATE} = "DNS error";
  #   InternalTimer( gettimeofday() + 3600, "livetracking_GetAll", $hash, 0);
  #   return undef;
  # }

  InternalTimer( gettimeofday() + 5, "livetracking_GetSwarm", $hash, 0) if(defined($hash->{helper}{swarm_token}));

  # $resolve = inet_aton("openpaths.cc");
  # if(!defined($resolve) && defined($hash->{helper}{openpaths_key}))
  # {
  #   $hash->{STATE} = "DNS error";
  #   InternalTimer( gettimeofday() + 3600, "livetracking_GetAll", $hash, 0);
  #   return undef;
  # }

  InternalTimer( gettimeofday() + 10, "livetracking_GetOpenPaths", $hash, 0) if(defined($hash->{helper}{openpaths_key}));


  InternalTimer( gettimeofday() + 20, "livetracking_GetLife360", $hash, 0) if(defined($hash->{helper}{life360_user}));

  return undef;
}



sub livetracking_GetLife360($) {

  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, "livetracking_GetLife360");

  if(IsDisabled($name))
  {
    Log3 ($name, 4, "livetracking $name is disabled, data update cancelled.");
    return undef;
  }

  if(!defined($hash->{helper}{life360_user}))
  {
    return undef;
  }

  if(!defined($hash->{helper}{life360_token}) or $hash->{helper}{life360_token} eq "")
  {
    livetracking_BootstrapLife360($hash);
    return undef;
  }

  my $lastupdate = ReadingsVal($name,".lastLife360",time()-3600);
  $lastupdate = (time()-3600*6) if($lastupdate < (time()-3600*6));
  my $circle = $attr{$name}{life360_circle};
  my $userid = $attr{$name}{life360_userid};

  my $url = "https://www.life360.com/v3/circles/".$circle."/members/".$userid."/history?time=".int($lastupdate);

    HttpUtils_NonblockingGet({
      url => $url,
      header => "Authorization: Bearer ".$hash->{helper}{life360_token},
      noshutdown => 1,
      hash => $hash,
      type => 'life360data',
      callback => \&livetracking_dispatch,
    });


  my $interval = AttrVal($hash->{NAME}, "interval", 1800);
  #RemoveInternalTimer($hash);
  InternalTimer( gettimeofday() + $interval, "livetracking_GetLife360", $hash, 0);
  $hash->{UPDATED} = FmtDateTime(time());

  return undef;
}


sub livetracking_GetOpenPaths($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #RemoveInternalTimer($hash);
  RemoveInternalTimer($hash, "livetracking_GetOpenPaths");

  if(AttrVal($name, "disable", 0) eq 1)
  {
    Log3 ($name, 4, "livetracking $name is disabled, data update cancelled.");
    return undef;
  }

  if(!defined($hash->{helper}{openpaths_key}))
  {
    return undef;
  }


  my $nonce = "";
  for (my $i=0;$i<32;$i++) {
    my $r = int(rand(62));
    if ($r<10) { $r += 48; }
    elsif ($r<36) { $r += 55; }
    else { $r += 61; }
    $nonce .= chr($r);
  }

  my $request = Net::OAuth->request("request token")->new(
    consumer_key => $hash->{helper}{openpaths_key},
    consumer_secret => $hash->{helper}{openpaths_secret},
    request_url => 'https://openpaths.cc/api/1',
    request_method => 'GET',
    signature_method => 'HMAC-SHA1',
    timestamp => livetracking_roundfunc(time()),
    nonce => $nonce,
  );
  $request->sign;


  my $lastupdate = livetracking_roundfunc(ReadingsVal($name,".lastOpenPaths",time()-3600));

  my $url = $request->to_url."&start_time=".$lastupdate."&num_points=50"; # start_time/end_time/num_points
  Log3 ($name, 4, "livetracking OpenPaths URL: ".$url);

    HttpUtils_NonblockingGet({
      url => $url,
      timeout => 10,
      noshutdown => 1,
      hash => $hash,
      type => 'openpathsdata',
      callback => \&livetracking_dispatch,
    });



  my $interval = AttrVal($hash->{NAME}, "interval", 1800);
  #RemoveInternalTimer($hash);
  InternalTimer( gettimeofday() + $interval, "livetracking_GetOpenPaths", $hash, 0);
  $hash->{UPDATED} = FmtDateTime(time());

  return undef;
}



sub livetracking_GetSwarm($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #RemoveInternalTimer($hash);
  RemoveInternalTimer($hash, "livetracking_GetSwarm");

  if(AttrVal($name, "disable", 0) eq 1)
  {
    Log3 ($name, 4, "livetracking $name is disabled, data update cancelled.");
    return undef;
  }

  if(!defined($hash->{helper}{swarm_token}))
  {
    return undef;
  }

  my $lastupdate = livetracking_roundfunc(ReadingsVal($name,".lastSwarm",time()-3600));

  my $url = "https://api.foursquare.com/v2/users/self/checkins?oauth_token=".$hash->{helper}{swarm_token}."&v=20150516&sort=oldestfirst&limit=25&afterTimestamp=".$lastupdate;

    HttpUtils_NonblockingGet({
      url => $url,
      timeout => 10,
      noshutdown => 1,
      hash => $hash,
      type => 'swarmdata',
      callback => \&livetracking_dispatch,
    });


  my $interval = AttrVal($hash->{NAME}, "interval", 900);
  #RemoveInternalTimer($hash);
  InternalTimer( gettimeofday() + $interval, "livetracking_GetSwarm", $hash, 0);
  $hash->{UPDATED} = FmtDateTime(time());

  return undef;
}



sub livetracking_ParseLife360($$) {
  my ($hash,$json) = @_;
  my $name = $hash->{NAME};

  my $updated = 0;

  my $lastreading = ReadingsVal($name,".lastLife360",time()-300);

  Log3 ($name, 5, "$name Life360 data: /n".Dumper($json));

  my $battery = -1;
  my $charge = -1;
  my $tst = int(time);

  foreach my $dataset (reverse(@{$json->{locations}}))
  {
    next if(!defined($dataset->{latitude}));

    if(defined($dataset->{battery}) && defined($dataset->{endTimestamp}))
    {
      $battery = $dataset->{battery};
      $charge = $dataset->{charge};
      $tst = $dataset->{endTimestamp};
    }

    next if($lastreading > $dataset->{startTimestamp});

    Log3 ($name, 2, "$name new l360 data: /n".Dumper($dataset));

    my $accurate = 1;
    $accurate = 0 if(defined($attr{$name}{filterAccuracy}) and defined($dataset->{accuracy}) and $attr{$name}{filterAccuracy} < $dataset->{accuracy});

    Log3 ($name, 5, "$name Life360: ".$dataset->{latitude}.",".$dataset->{longitude});

    $lastreading = $dataset->{endTimestamp}+1;

    readingsBeginUpdate($hash); # Begin update readings
    $hash->{".updateTimestamp"} = FmtDateTime($dataset->{endTimestamp});
    my $changeindex = 0;


    if($accurate){
      readingsBulkUpdate($hash, "latitude", $dataset->{latitude});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
      readingsBulkUpdate($hash, "longitude", $dataset->{longitude});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
      readingsBulkUpdate($hash, "location", $dataset->{latitude}.",".$dataset->{longitude});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
    }

    if(defined($dataset->{speed}) and $dataset->{speed} >= 0 and $accurate)
    {
      readingsBulkUpdate($hash, "velocity", $dataset->{speed});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
    }

    readingsBulkUpdate($hash, "accuracy", $dataset->{accuracy});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});


    if(defined($dataset->{name}) and $dataset->{name} ne "")
    {
      readingsBulkUpdate($hash, "place", $dataset->{name});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
    }
    elsif(defined($dataset->{shortAddress}) and $dataset->{shortAddress} ne "")
    {
      readingsBulkUpdate($hash, "place", $dataset->{shortAddress});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
    }
    elsif(defined($dataset->{address1}) and $dataset->{address1} ne "")
    {
      readingsBulkUpdate($hash, "place", $dataset->{address1});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
    }

    if(defined($attr{$name}{home}) && $accurate)
    {
      readingsBulkUpdate($hash, "distance", livetracking_distance($hash,$dataset->{latitude}.",".$dataset->{longitude},$attr{$name}{home}));
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
    }

    if(defined($dataset->{battery}))
    {
      readingsBulkUpdate($hash, "batteryPercent", $dataset->{battery});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
      readingsBulkUpdate($hash, "batteryState", (int($dataset->{battery}) <= int(AttrVal($name, "batteryWarning" , "20")))?"low":"ok");
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
      readingsBulkUpdate($hash, "batteryCharge", ($charge == -1)?"unknown":($charge == 1)?"charge":"discharge");
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{endTimestamp});
    }

    $updated = 1;

    readingsEndUpdate($hash, 1);

  }

  if($battery >= 0 && $updated == 0)
  {
    readingsBeginUpdate($hash);
    $hash->{".updateTimestamp"} = FmtDateTime($tst);
    readingsBulkUpdate($hash, "batteryPercent", $battery);
    $hash->{CHANGETIME}[0] = FmtDateTime($tst);
    readingsBulkUpdate($hash, "batteryState", (int($battery) <= int(AttrVal($name, "batteryWarning" , "20")))?"low":"ok");
    $hash->{CHANGETIME}[1] = FmtDateTime($tst);
    readingsBulkUpdate($hash, "batteryCharge", ($charge == -1)?"unknown":($charge == 1)?"charge":"discharge");
    $hash->{CHANGETIME}[0] = FmtDateTime($tst);
    readingsEndUpdate($hash, 1);
  }

  if($updated == 1)
  {
    readingsSingleUpdate($hash,".lastLife360",$lastreading,1);
    $hash->{helper}{lastLife360} = $lastreading;
  }

  return undef;
}


sub livetracking_ParseOpenPaths($$) {
  my ($hash,$json) = @_;
  my $name = $hash->{NAME};

  my $updated = 0;

  my $lastreading = ReadingsVal($name,".lastOpenPaths",time()-300);
  my $device = ReadingsVal($name,"deviceOpenPaths","");
  my $os = ReadingsVal($name,"osOpenPaths","");
  my $version = ReadingsVal($name,"versionOpenPaths","");
  my $altitude = ReadingsVal($name,"altitude","0");
  my $altitudeRound = AttrVal($hash->{NAME}, "roundAltitude", 1);

  Log3 ($name, 6, "$name OpenPaths data: /n".Dumper($json));


  foreach my $dataset (@{$json})
  {
    Log3 ($name, 5, "$name OpenPaths: at ".FmtDateTime($dataset->{t})." / ".$dataset->{lat}.",".$dataset->{lon});

    $lastreading = $dataset->{t}+1;

    readingsBeginUpdate($hash); # Begin update readings
    $hash->{".updateTimestamp"} = FmtDateTime($dataset->{t});
    my $changeindex = 0;


    readingsBulkUpdate($hash, "latitude", $dataset->{lat});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
    readingsBulkUpdate($hash, "longitude", $dataset->{lon});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
    readingsBulkUpdate($hash, "location", $dataset->{lat}.",".$dataset->{lon});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});


    if(defined($dataset->{alt}) && $dataset->{alt} ne '0')
    {
      my $newaltitude = livetracking_roundfunc($dataset->{alt}/$altitudeRound)*$altitudeRound;
      #Log3 ($name, 0, "$name SwarmRound: ".$dataset->{alt}."/".$altitudeRound." = ".livetracking_roundfunc($dataset->{alt}/$altitudeRound)." *".$altitudeRound);

      if($altitude ne $newaltitude)
      {
        readingsBulkUpdate($hash, "altitude", $newaltitude);
        $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
        $altitude = $newaltitude;
      }
    }
    if(defined($dataset->{device}) && $dataset->{device} ne $device)
    {
      readingsBulkUpdate($hash, "deviceOpenPaths", $dataset->{device});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
    }
    if(defined($dataset->{os}) && $dataset->{os} ne $os)
    {
      readingsBulkUpdate($hash, "osOpenPaths", $dataset->{os});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
    }
    if(defined($dataset->{version}) && $dataset->{version} ne $version)
    {
      readingsBulkUpdate($hash, "versionOpenPaths", $dataset->{version});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
    }
    if(defined($attr{$name}{home}))
    {
      readingsBulkUpdate($hash, "distance", livetracking_distance($hash,$dataset->{lat}.",".$dataset->{lon},$attr{$name}{home}));
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
    }
    $updated = 1;

    readingsEndUpdate($hash, 1); # End update readings
  }



  if($updated == 1)
  {
    readingsSingleUpdate($hash,".lastOpenPaths",$lastreading,1);
    $hash->{helper}{lastOpenPaths} = $lastreading;
  }

  return undef;
}




sub livetracking_ParseSwarm($$) {
  my ($hash,$json) = @_;
  my $name = $hash->{NAME};

  my $updated = 0;

  my $lastreading = ReadingsVal($name,".lastSwarm",time()-300);
  my $device = ReadingsVal($name,"deviceSwarm","");

  Log3 ($name, 6, "$name Swarm data: /n".Dumper($json));


  foreach my $dataset (@{$json->{response}->{checkins}->{items}})
  {
    next if(!defined($dataset->{type}) || $dataset->{type} ne "checkin");


    readingsBeginUpdate($hash);
    $hash->{".updateTimestamp"} = FmtDateTime($dataset->{createdAt});
    my $changeindex = 0;

    $lastreading = $dataset->{createdAt}+1;

    my $place = livetracking_utf8clean($dataset->{venue}->{name});

    Log3 ($name, 4, "$name Swarm: ".$place." at ".FmtDateTime($dataset->{createdAt})." / ".$dataset->{venue}->{location}->{lat}.",".$dataset->{venue}->{location}->{lng});

    my $loc = $dataset->{venue}->{location}->{lat}.",".$dataset->{venue}->{location}->{lng};

    if(defined($attr{$name}{swarmHome}) and defined($attr{$name}{home}))
    {
      my $shl = $attr{$name}{swarmHome};
      my $home = $attr{$name}{home};
      $loc =~ s/$shl/$home/g;
    }

    readingsBulkUpdate($hash, "latitude", $dataset->{venue}->{location}->{lat});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});
    readingsBulkUpdate($hash, "longitude", $dataset->{venue}->{location}->{lng});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});
    readingsBulkUpdate($hash, "location", $loc);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});

    readingsBulkUpdate($hash, "place", $place);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});

    if(defined($dataset->{source}->{name}) && $dataset->{source}->{name} ne $device)
    {
      readingsBulkUpdate($hash, "deviceSwarm", $dataset->{source}->{name});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});
    }
    if(defined($attr{$name}{home}))
    {
      readingsBulkUpdate($hash, "distance", livetracking_distance($hash,$loc,$attr{$name}{home})." km");
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});
    }
    $updated = 1;

    #$hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});
    readingsEndUpdate($hash, 1);

  }

  if($updated == 1)
  {
    #readingsSingleUpdate($hash,"lastSwarm",$lastreading,1);
    #$hash->{CHANGED} = ();
    #$hash->{CHANGETIME} = ();
    readingsSingleUpdate($hash,".lastSwarm",$lastreading,1);
    $hash->{helper}{lastSwarm} = $lastreading;
  }

  return undef;
}


sub livetracking_ParseOwnTracks
{
  my ($hash,$data) = @_;
  my $name = $hash->{NAME};

  my $dataset = eval { JSON->new->utf8(0)->decode($data) };
  if($@)
    {
    Log3 $name, 2, "$name: invalid json evaluation on ParseOwnTracks".Dumper($data);
    #Log3 $name, 2, "$name: ".$param->{url}." / ".Dumper($data) if( $param->{type} eq 'life360data' );
    return undef;
  }


    if($data =~ m/_type":[ ]?"steps/)
  {
    readingsBeginUpdate($hash); # Start update readings
    $hash->{".updateTimestamp"} = FmtDateTime($dataset->{to});
    readingsBulkUpdate($hash, "steps", int($dataset->{steps}));
    $hash->{CHANGETIME}[0] = FmtDateTime($dataset->{to});
    readingsBulkUpdate($hash, "walking", int($dataset->{distance}));
    $hash->{CHANGETIME}[1] = FmtDateTime($dataset->{to});
    readingsBulkUpdate($hash, "floorsup", int($dataset->{floorsup}));
    $hash->{CHANGETIME}[2] = FmtDateTime($dataset->{to});
    readingsBulkUpdate($hash, "floorsdown", int($dataset->{floorsdown}));
    $hash->{CHANGETIME}[3] = FmtDateTime($dataset->{to});
    readingsEndUpdate($hash, 1);
    readingsSingleUpdate($hash,".lastOwnTracks",$dataset->{tst},1);
    $hash->{helper}{lastOwnTracks} = $dataset->{tst};
    return undef;
  }

    if($data =~ m/_type":[ ]?"beacon/)
  {
    my $beaconid = $dataset->{uuid}.",".$dataset->{major}.",".$dataset->{minor};

    readingsBeginUpdate($hash); # Start update readings
    $hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});

    readingsBulkUpdate($hash, "beacon", $beaconid);
    $hash->{CHANGETIME}[0] = FmtDateTime($dataset->{tst});

    for(my $i=9;$i>=0;$i--)
    {
      next if(!defined($attr{$name}{"beacon_$i"}));
      if($beaconid eq $attr{$name}{"beacon_$i"})
      {
        readingsBulkUpdate($hash, "beacon_".$i."_proximity", $dataset->{prox});
        $hash->{CHANGETIME}[1] = FmtDateTime($dataset->{tst});
        readingsBulkUpdate($hash, "beacon_".$i."_accuracy", $dataset->{acc});
        $hash->{CHANGETIME}[2] = FmtDateTime($dataset->{tst});
        readingsBulkUpdate($hash, "beacon_".$i."_rssi", $dataset->{rssi});
        $hash->{CHANGETIME}[3] = FmtDateTime($dataset->{tst});
        last;
      }
    }

    readingsEndUpdate($hash, 1);
    readingsSingleUpdate($hash,".lastOwnTracks",$dataset->{tst},1);
    $hash->{helper}{lastOwnTracks} = $dataset->{tst};
    return undef;
  }



  #{"position":{"id":566,"attributes":{"batteryLevel":66,"distance":25.79,"totalDistance":20665.79,"motion":false},"deviceId":1,"type":null,"protocol":"osmand","serverTime":"2019-01-06T11:39:41.279+0000","deviceTime":"2019-01-06T11:39:41.000+0000","fixTime":"2019-01-06T11:39:41.000+0000","outdated":false,"valid":true,"latitude":53.xxxxx,"longitude":8.xxxxx,"altitude":0,"speed":0,"course":0,"address":null,"accuracy":24.04000091552734,"network":null},"device":{"id":1,"attributes":{},"groupId":0,"name":"SomeName","uniqueId":"SomeID,"status":"online","lastUpdate":"2019-01-06T11:39:41.279+0000","positionId":565,"geofenceIds":[],"phone":"","model":"","contact":"","category":null,"disabled":false}}


  my $accurate = 1;
  $accurate = 0 if(defined($attr{$name}{filterAccuracy}) and defined($dataset->{acc}) and $attr{$name}{filterAccuracy} < $dataset->{acc});

  readingsBeginUpdate($hash); # Start update readings
  $hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
  my $changeindex = 0;

  Log3 ($name, 4, "$name OwnTracks: ".FmtDateTime($dataset->{tst})."  ".$data);

  if($accurate)
  {
      readingsBulkUpdate($hash, "latitude", $dataset->{lat});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
      readingsBulkUpdate($hash, "longitude", $dataset->{lon});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    readingsBulkUpdate($hash, "location", $dataset->{lat}.",".$dataset->{lon});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  else
  {
    Log3 ($name, 3, "$name OwnTracks: Inaccurate reading ignored: ".$dataset->{lat}.",".$dataset->{lon}." (".$dataset->{acc}.")");
  }


  if(defined($dataset->{alt}) and $dataset->{alt} != 0 and $accurate)
  {
    my $altitudeRound = AttrVal($hash->{NAME}, "roundAltitude", 1);
    my $newaltitude = livetracking_roundfunc($dataset->{alt}/$altitudeRound)*$altitudeRound;
    #Log3 ($name, 0, "$name OTRound: ".$dataset->{alt}."/".$altitudeRound." = ".livetracking_roundfunc($dataset->{alt}/$altitudeRound)."*".$altitudeRound);
    readingsBulkUpdate($hash, "altitude", $newaltitude);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  if(defined($dataset->{tid}) and $dataset->{tid} ne "")
  {
    readingsBulkUpdate($hash, "id", $dataset->{tid});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  if(defined($dataset->{doze}) and $dataset->{doze} ne "")
  {
    readingsBulkUpdate($hash, "doze", $dataset->{doze});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  if(defined($dataset->{acc}) and $dataset->{acc} > 0)# and $accurate)
  {
    readingsBulkUpdate($hash, "accuracy", $dataset->{acc});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  if(defined($dataset->{vel}) and $dataset->{vel} >= 0 and $accurate)
  {
    readingsBulkUpdate($hash, "velocity", $dataset->{vel});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  #else
  #{
  #  fhem( "deletereading $name velocity" );
    #  readingsBulkUpdate($hash, "velocity", 0);
    #  $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  #}
  if(defined($dataset->{cog}) and $dataset->{cog} >= 0 and $accurate)
  {
    readingsBulkUpdate($hash, "heading", $dataset->{cog});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  #else
  #{
  #  fhem( "deletereading $name heading" );
    #  readingsBulkUpdate($hash, "heading", 0);
    #  $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  #}
  if(defined($dataset->{batt}))
  {
    readingsBulkUpdate($hash, "batteryPercent", $dataset->{batt});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    readingsBulkUpdate($hash, "batteryState", (int($dataset->{batt}) <= int(AttrVal($name, "batteryWarning" , "20")))?"low":"ok");
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  if(defined($dataset->{conn}))
  {
    readingsBulkUpdate($hash, "connection", (($dataset->{conn} eq "m")?"mobile":($dataset->{conn} eq "w")?"wifi":($dataset->{conn} eq "o")?"offline":"unknown"));
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  if(defined($dataset->{p}) and $dataset->{p} > 0)
  {
    readingsBulkUpdate($hash, "pressure", sprintf("%.2f", $dataset->{p}*10));
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  if(defined($dataset->{desc}) and defined($dataset->{event}))
  {
    Log3 ($name, 3, "$name OwnTracks Zone Event: ".$dataset->{event}." ".$dataset->{desc});

    my $place = livetracking_utf8clean($dataset->{desc});

    my @placenumbers;
    for(my $i=9;$i>=0;$i--)
    {
      next if(!defined($attr{$name}{"zonename_$i"}));
      push @placenumbers, $i if($place =~ m/^($attr{$name}{"zonename_$i"})$/);
    }

    if($dataset->{event} eq "enter")
    {
      readingsBulkUpdate($hash, "place", $place);
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
      foreach my $placenumber (@placenumbers)
      {
        readingsBulkUpdate($hash, "zone_".$placenumber,"active");
        $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
      }
    }
      else
    {
      #fhem( "deletereading $name place" ) if(ReadingsVal($name,"place","undefined") eq $dataset->{desc});
      foreach my $placenumber (@placenumbers)
      {
        readingsBulkUpdate($hash, "zone_".$placenumber,"inactive");
        $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
      }
    }
  }

  if(defined($dataset->{t}))
  {
    my $trigger = "unknown";
    $trigger = "ping" if($dataset->{t} eq "p");
    $trigger = "region" if($dataset->{t} eq "c");
    $trigger = "beacon" if($dataset->{t} eq "b");
    $trigger = "request" if($dataset->{t} eq "r");
    $trigger = "manual" if($dataset->{t} eq "u");
    $trigger = "timer" if($dataset->{t} eq "t");
    $trigger = "frequent" if($dataset->{t} eq "v");
    readingsBulkUpdate($hash, "trigger",$trigger);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  } else {
    readingsBulkUpdate($hash, "trigger","automatic");
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }


  if(defined($dataset->{inregions}))
  {
    my @placenumbersactive;
    my @placenumbersinactive;
      for(my $i=9;$i>=0;$i--)
      {
        next if(!defined($attr{$name}{"zonename_$i"}));
      my $active = 0;
      foreach my $regionname ( @{$dataset->{inregions}} )
      {
        $active = 1 if($regionname =~ m/^($attr{$name}{"zonename_$i"})$/);
      }
      if($active){
          Log3 ($name, 4, "$name OwnTracks region active: ".Dumper($attr{$name}{"zonename_$i"}));
          push @placenumbersactive, $i;
        } else {
          Log3 ($name, 4, "$name OwnTracks region inactive: ".Dumper($attr{$name}{"zonename_$i"}));
          push @placenumbersinactive, $i;
        }
      }

    foreach my $placenumber (@placenumbersactive)
    {
      readingsBulkUpdate($hash, "zone_".$placenumber,"active");
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    }
    foreach my $placenumber (@placenumbersinactive)
    {
      readingsBulkUpdate($hash, "zone_".$placenumber,"inactive");
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    }

  }

  if(defined($attr{$name}{home}) and $accurate)
  {
    readingsBulkUpdate($hash, "distance", livetracking_distance($hash,$dataset->{lat}.",".$dataset->{lon},$attr{$name}{home}));
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }

  readingsEndUpdate($hash, 1);

  readingsSingleUpdate($hash,".lastOwnTracks",$dataset->{tst},1);

  $hash->{helper}{lastOwnTracks} = $dataset->{tst};

  return undef;
}

sub livetracking_Notify($$)
{
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  my $devName = $dev->{NAME};

  my $dataset = "";
  my $data = "";

  # Ignore wrong notifications
  if($devName eq AttrVal($name, "owntracksDevice" , "owntracks"))
  {
    Log3 ($name, 6, "$name OwnTracks data: /n".Dumper($dev));

    my $invaliddata = 1;
    if(($dev->{CHANGED}[0] =~ m/_type":[ ]?"location/ || $dev->{CHANGED}[0] =~ m/_type":[ ]?"position/ || $dev->{CHANGED}[0] =~ m/_type":[ ]?"transition/ || $dev->{CHANGED}[0] =~ m/_type":[ ]?"steps/ || $dev->{CHANGED}[0] =~ m/_type":[ ]?"beacon/ ))
    {
      $invaliddata = 0;#owntracks
      Log3 ($name, 4, "$name Detected OwnTracks data from MQTT device notify");
    }
    elsif(($dev->{CHANGED}[0] =~ m/position":[ ]?{/))
    {
      #{"position":{"id":14935,"attributes":{"batteryLevel":61,"distance":0.06,"totalDistance":4132002.73,"motion":false},"deviceId":1,"type":null,"protocol":"osmand","serverTime":"2018-10-31T22:14:10.290+0000","deviceTime":"2018-10-31T22:14:07.000+0000","fixTime":"2018-10-31T22:14:07.000+0000","outdated":false,"valid":true,"latitude":12.3456789,"longitude":12.3456789,"altitude":0,"speed":0,"course":0,"address":null,"accuracy":19.23500061035156,"network":null},"device":{"id":1,"attributes":{},"groupId":0,"name":"XXX","uniqueId":"YYY","status":"online","lastUpdate":"2018-10-31T22:14:10.290+0000","positionId":14935,"geofenceIds":[2],"phone":"","model":"","contact":"","category":"person","disabled":false}}
      #{"position":{"id":566,"attributes":{"batteryLevel":66,"distance":25.79,"totalDistance":20665.79,"motion":false},"deviceId":1,"type":null,"protocol":"osmand","serverTime":"2019-01-06T11:39:41.279+0000","deviceTime":"2019-01-06T11:39:41.000+0000","fixTime":"2019-01-06T11:39:41.000+0000","outdated":false,"valid":true,"latitude":53.xxxxx,"longitude":8.xxxxx,"altitude":0,"speed":0,"course":0,"address":null,"accuracy":24.04000091552734,"network":null},"device":{"id":1,"attributes":{},"groupId":0,"name":"SomeName","uniqueId":"SomeID,"status":"online","lastUpdate":"2019-01-06T11:39:41.279+0000","positionId":565,"geofenceIds":[],"phone":"","model":"","contact":"","category":null,"disabled":false}}
      $invaliddata = 0;#traccar
      Log3 ($name, 4, "$name Detected Traccar data from MQTT device notify");
    }
    if($invaliddata == 1){
      Log3 ($name, 4, "WRONG MQTT TYPE ".Dumper($dev->{CHANGED}[0]));
      return undef;
    }

  #Log3 ($name, 1, "MQTT ".Dumper($dev->{CHANGED}[0]));

    $data = substr($dev->{CHANGED}[0],index($dev->{CHANGED}[0], ": {")+2);

  } else {
    Log3 ($name, 5, "livetracks: Notify ignored from ".$devName);
    return undef;
  }

  livetracking_ParseOwnTracks($hash,$data);

  return undef;

}


##########################

sub livetracking_dispatch($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};


  if( $err )
  {
    Log3 $name, 2, "$name: http request failed: $err";
  }
  elsif( $data )
  {
    Log3 $name, 5, "$name: $data";


    $data =~ s/\n//g;
    if( $data !~ /{.*}/ )
    {
      Log3 $name, 3, "$name: invalid json detected: >>$data<< " . $param->{type} if($data ne "[]");
      #$hash->{helper}{life360_token} = "" if( $param->{type} eq 'life360data' );
      return undef;
    }

    my $json = eval { JSON->new->utf8(0)->decode($data) };
    if($@)
    {
      Log3 $name, 2, "$name: invalid json evaluation on dispatch type ".$param->{type}." ".$@;
      #Log3 $name, 2, "$name: ".$param->{url}." / ".Dumper($data) if( $param->{type} eq 'life360data' );
      return undef;
    }


    if( $param->{type} eq 'life360data' ) {
      livetracking_ParseLife360($hash,$json);
    } elsif( $param->{type} eq 'openpathsdata' ) {
      livetracking_ParseOpenPaths($hash,$json);
    } elsif( $param->{type} eq 'swarmdata' ) {
      livetracking_ParseSwarm($hash,$json);
    }
  }
}

##############################

sub livetracking_BootstrapLife360($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!defined($hash->{helper}{life360_user}))
  {
    return undef;
  }

  if(!defined($hash->{helper}{life360_script}) or $hash->{helper}{life360_script} eq "")
  {
    my $url = "https://www.life360.com/circles/#/";

    HttpUtils_NonblockingGet({
      url => $url,
      noshutdown => 1,
      hash => $hash,
      type => 'scriptdata',
      callback => \&livetracking_bootstrap,
    });
    return undef;
  }

  if(!defined($hash->{helper}{life360_secret}) or $hash->{helper}{life360_secret} eq "")
  {
    my $url = "https://www.life360.com/circles/scripts/".$hash->{helper}{life360_script}.".scripts.js";
    Log3 $name, 1, "$name: $url";

    HttpUtils_NonblockingGet({
      url => $url,
      noshutdown => 1,
      hash => $hash,
      type => 'secretdata',
      callback => \&livetracking_bootstrap,
    });
    return undef;
  }

  if(!defined($hash->{helper}{life360_token}) or !defined($attr{$name}{life360_userid}) or $hash->{helper}{life360_token} eq "" or $attr{$name}{life360_userid} eq "")
  {
    my $url = "https://www.life360.com/v3/oauth2/token.json";

    HttpUtils_NonblockingGet({
      url => $url,
      method => "POST",
      header => "Content-Type: application/x-www-form-urlencoded\r\nAuthorization: Basic ".$hash->{helper}{life360_secret},
      data => "countryCode=1&password=".uri_escape($hash->{helper}{life360_pass})."&username=".uri_escape($hash->{helper}{life360_user})."&persist=true&grant_type=password",
      noshutdown => 1,
      hash => $hash,
      type => 'tokendata',
      callback => \&livetracking_bootstrap,
    });
    Log3 $name, 1, "$name: "."countryCode=1&password=".uri_escape($hash->{helper}{life360_pass})."&username=".uri_escape($hash->{helper}{life360_user})."&persist=true&grant_type=password";

    return undef;
  }

  if(!defined($attr{$name}{life360_circle}) or $attr{$name}{life360_circle} eq "")
  {
    my $url = "https://www.life360.com/v3/circles";

    HttpUtils_NonblockingGet({
      url => $url,
      header => "Authorization: Bearer ".$hash->{helper}{life360_token},
      noshutdown => 1,
      hash => $hash,
      type => 'circledata',
      callback => \&livetracking_bootstrap,
    });
    return undef;
  }


  livetracking_GetLife360($hash);

}

sub livetracking_bootstrap($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};


  if( $err ) {
    Log3 $name, 2, "$name: http request failed: $err";
    return undef;
  } elsif( $data ) {
    Log3 $name, 5, "$name: $data";


    if( $param->{type} eq 'scriptdata' )
    {
      if ($data =~ /\bscripts\/\b(.*?)\b.scripts.js\b/)
      {
        $hash->{helper}{life360_script} = $1;
        Log3 $name, 4, "$name: life360 script ".$hash->{helper}{life360_script};
        InternalTimer( gettimeofday() + 1, "livetracking_BootstrapLife360", $hash, 0);
      }
      return undef;
    }
    elsif( $param->{type} eq 'secretdata' )
    {
      if ($data =~ /CLIENT_SECRET = "(.*?)";/)
      {
        $hash->{helper}{life360_secret} = $1;
        Log3 $name, 4, "$name: life360 secret ".$hash->{helper}{life360_secret};
        InternalTimer( gettimeofday() + 1, "livetracking_BootstrapLife360", $hash, 0);
      }
      return undef;
    }
    elsif( $param->{type} eq 'tokendata' )
    {
      my $json = eval { JSON->new->utf8(0)->decode($data) };
      if($@)
      {
        Log3 $name, 2, "$name: invalid json evaluation on dispatch type ".$param->{type}." ".$@;
        return undef;
      }

      $hash->{helper}{life360_token} = $json->{access_token};
      $attr{$name}{life360_userid} = $json->{user}->{id};

      Log3 $name, 3, "$name: life360 token ".$json->{access_token};
      InternalTimer( gettimeofday() + 1, "livetracking_BootstrapLife360", $hash, 0);
      return undef;
    }
    elsif( $param->{type} eq 'circledata' )
    {
      my $json = eval { JSON->new->utf8(0)->decode($data) };
      if($@)
      {
        Log3 $name, 2, "$name: invalid json evaluation on dispatch type ".$param->{type}." ".$@;
        return undef;
      }
      $attr{$name}{life360_circle} = $json->{circles}[0]->{id} if($json->{circles}[0]->{id} ne "");
      InternalTimer( gettimeofday() + 1, "livetracking_BootstrapLife360", $hash, 0);

      foreach my $dataset (@{$json->{circles}})
      {
        Log3 $name, 5, "$name: Life360 Circle: ".$dataset->{name}.", ID: ".$dataset->{id};
        my $url = "https://www.life360.com/v3/circles/".$dataset->{id};

        HttpUtils_NonblockingGet({
          url => $url,
          header => "Authorization: Bearer ".$hash->{helper}{life360_token},
          noshutdown => 1,
          hash => $hash,
          type => 'familydata',
          callback => \&livetracking_bootstrap,
        });


      }
      #Log3 $name, 2, "$name: Life360 : ".Dumper($data);
      return undef;
    }
    elsif( $param->{type} eq 'familydata' )
    {
      my $json = eval { JSON->new->utf8(0)->decode($data) };
      if($@)
      {
        Log3 $name, 2, "$name: invalid json evaluation on dispatch type ".$param->{type}." ".$@;
        return undef;
      }
      InternalTimer( gettimeofday() + 1, "livetracking_GetLife360", $hash, 0);

      foreach my $dataset (@{$json->{members}})
      {
        Log3 $name, 2, "$name: Life360 User: ".$dataset->{loginEmail}.", ID: ".$dataset->{id};
      }
      #Log3 $name, 5, "$name: Life360 : ".Dumper($data);

    }


    return undef;


  }
}

##########################

sub livetracking_getHistory($$$$$)
{
  my ($param,$f,$t,$srcDesc,$showData) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  my (@da, $ret, @vals);
  my @keys = ("min","mindate","max","maxdate","currval","currdate",
              "firstval","firstdate","avg","cnt","lastraw");

  foreach my $src (@{$srcDesc->{order}}) {
    my $s = $srcDesc->{src}{$src};
    my $fname = ($src eq $defs{$name}{LOGDEVICE} ? $defs{$name}{LOGFILE} : "CURRENT");
    my $cmd = "get $src $fname INT $f $t ".$s->{arg};
    FW_fC($cmd, 1);
    if($showData) {
      $ret .= "\n$cmd\n\n";
      $ret .= $$internal_data if(ref $internal_data eq "SCALAR");

    } else {
      push(@da, $internal_data);
      for(my $i = 0; $i<=$s->{idx}; $i++) {
        my %h;
        foreach my $k (@keys) {
          $h{$k} = $data{$k.($i+1)};
        }
        push @vals, \%h;
      }

    }
  }

  # Reorder the $data{maxX} stuff
  my ($min, $max) = (999999, -999999);
  my $no = int(keys %{$srcDesc->{rev}});
  for(my $oi = 0; $oi < $no; $oi++) {
    my $nl = int(keys %{$srcDesc->{rev}{$oi}});
    for(my $li = 0; $li < $nl; $li++) {
      my $r = $srcDesc->{rev}{$oi}{$li}+1;
      my $val = shift @vals;
      foreach my $k (@keys) {
        $min = $val->{$k} if($k eq "min" && defined($val->{$k}) &&
                        $val->{$k} =~ m/[-+]?\d*\.?\d+/ && $val->{$k} < $min);
        $max = $val->{$k} if($k eq "max" && defined($val->{$k}) &&
                        $val->{$k} =~ m/[-+]?\d*\.?\d+/ && $val->{$k} > $max);
        $data{"$k$r"} = $val->{$k};
      }
    }
  }
  $data{maxAll} = $max;
  $data{minAll} = $min;

  return $ret if($showData);
  return \@da;
}



#########################
sub livetracking_addExtension($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #livetracking_removeExtension() ;
  my $url = "/osmand";
  delete $data{FWEXT}{$url} if($data{FWEXT}{$url});

  Log3 $name, 2, "Enabling livetracking url for $name ".AttrVal($name, "osmandId", "");
  $data{FWEXT}{$url}{deviceName} = $name;
  $data{FWEXT}{$url}{FUNC}       = "livetracking_Webcall";
  $data{FWEXT}{$url}{LINK}       = "livetracking";

  $modules{"livetracking"}{defptr}{"webcall".AttrVal($name, "osmandId", "")} = $hash;

}

#########################
sub livetracking_removeExtension($) {
  my ($hash) = @_;

  my $url  = "/osmand";
  my $name = $data{FWEXT}{$url}{deviceName};
  $name = $hash->{NAME} if(!defined($name));
  Log3 $name, 2, "Disabling livetracking url for $name ".AttrVal($name, "osmandId", "");
  delete $data{FWEXT}{$url};
  delete $modules{"livetracking"}{defptr}{"webcall".AttrVal($name, "osmandId", "")};
}

#########################
sub livetracking_Webcall() {
  my ($request) = @_;

  $request =~ /id=(.*?)(&|$)/;
  my $id = $1 || "";

  if($id eq ""){
    $request =~ /"tid":"(.*?)"/;
    $id = $1 || "";
  }
  Log3 "livetracking", 5, "OsmAnd id incoming: ".$id;

  my $hash = $modules{"livetracking"}{defptr}{"webcall".$id};
  if(!defined($hash)){
    $hash = $modules{"livetracking"}{defptr}{"webcall"} ;
    Log3 "livetracking", 4, "OsmAnd webcall generic" if(defined($hash));
  } else {
    Log3 "livetracking", 4, "OsmAnd webcall for specific id";
  }

  if(!defined($hash)){
    Log3 "livetracking", 1, "OsmAnd webcall hash not defined!";
    return ( "text/plain; charset=utf-8",
        "undefined" );
  }
  my $name = $hash->{NAME};

  my $osmandid = AttrVal($name, "osmandId", undef);
  if($id ne"" && defined($osmandid) && $osmandid ne $id){
    Log3 "livetracking", 4, "OsmAnd webcall for wrong id";
    return undef;
  }


  if($request =~ /"_type"/){
    $request =~ s/\/osmand&//g;
    $request =~ s/\/osmand\/&//g;
    Log3 $name, 4, "OwnTracks HTTP request:\n".$request;
    livetracking_ParseOwnTracks($hash,$request) if(($request =~ /_type":[ ]?"location/ || $request =~ /_type":[ ]?"position/ || $request =~ /_type":[ ]?"transition/ || $request =~ /_type":[ ]?"steps/ || $request =~ /_type":[ ]?"beacon/ ));
    return undef;
  }


  Log3 $name, 5, "OsmAnd webcall request:\n".$request;

  my ($tst) = $request =~ /tamp=(.*?)(&|$)/;
  my ($hdop) = $request =~ /hdop=(.*?)(&|$)/ || 0;
  my ($lat) = $request =~ /lat=(.*?)(&|$)/;
  my ($lon) = $request =~ /lon=(.*?)(&|$)/;
  my ($speed) = $request =~ /speed=(.*?)(&|$)/;
  my ($bearing) = $request =~ /bearing=(.*?)(&|$)/;
  my ($altitude) = $request =~ /altitude=(.*?)(&|$)/;
  my ($battery) = $request =~ /batt=(.*?)(&|$)/;

  if(!defined($tst))
  {
    return ( "text/plain; charset=utf-8",
        "timestamp missing" );
  }

  my $accurate = 1;
  $accurate = 0 if(defined($attr{$name}{filterAccuracy}) and defined($hdop) and $attr{$name}{filterAccuracy} < $hdop);

  my $changeindex = 0;
  readingsBeginUpdate($hash); # Start update readings
  $hash->{".updateTimestamp"} = FmtDateTime($tst);
  Log3 ($name, 4, "$name OsmAnd Server: ".FmtDateTime($tst));

  if($accurate && defined($lat) && defined($lon))
  {
    readingsBulkUpdate($hash, "latitude", $lat);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($tst);
    readingsBulkUpdate($hash, "longitude", $lon);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($tst);
    readingsBulkUpdate($hash, "location", $lat.",".$lon);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($tst);
  }
  else
  {
    Log3 ($name, 3, "$name OsmAnd: Inaccurate reading ignored: ".$lat.",".$lon." (".$hdop.")");
  }

  if($accurate && defined($speed) && $speed >= 0)
  {
    readingsBulkUpdate($hash, "velocity", $speed);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($tst);
  }
  if($accurate && defined($bearing) && $bearing >= 0)
  {
    readingsBulkUpdate($hash, "heading", $bearing);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($tst);
  }
  if($accurate && defined($altitude) and $altitude != 0)
  {
    my $altitudeRound = AttrVal($hash->{NAME}, "roundAltitude", 1);
    my $newaltitude = livetracking_roundfunc($altitude/$altitudeRound)*$altitudeRound;
    readingsBulkUpdate($hash, "altitude", $newaltitude);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($tst);
  }
  if(defined($hdop) && $hdop > 0)
  {
    readingsBulkUpdate($hash, "accuracy", $hdop);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($tst);
  }
  if(defined($battery))
  {
    readingsBulkUpdate($hash, "batteryPercent", $battery);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($tst);
    readingsBulkUpdate($hash, "batteryState", (int($battery) <= int(AttrVal($name, "batteryWarning" , "20")))?"low":"ok");
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($tst);
  }
  if($accurate && defined($attr{$name}{home}) and defined($lat) && defined($lon))
  {
    readingsBulkUpdate($hash, "distance", livetracking_distance($hash,$lat.",".$lon,$attr{$name}{home}));
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($tst);
  }

  readingsEndUpdate($hash, 1);
  readingsSingleUpdate($hash,".lastOsmAnd",$tst,1);
  $hash->{helper}{lastOsmAnd} = $tst;


  if(defined($lat) && defined($lon))
  {
    return ( "application/json; charset=UTF-8",
        "[]" );
  } else {
    return ( "text/plain; charset=utf-8",
        "no data" );
  }

  return undef;
}


##########################
sub livetracking_DbLog_splitFn($)
{
  my ($event) = @_;
  my ($reading, $value, $unit) = "";

  Log3 ("dbsplit", 5, "event ".$event);

  my @parts = split(/ /,$event,3);
  $reading = $parts[0];
  $reading =~ tr/://d;
  $value = $parts[1];

  #Log3 ("dbsplit", 5, "split ".$parts[0]." / ".$parts[1]." / ".$parts[2]);
  Log3 ("dbsplit", 5, "split ".$event);

  if($event =~ m/altitude/)
  {
    $reading = 'altitude';
    $unit = 'm';
  }
  elsif($event =~ m/accuracy/)
  {
    $reading = 'accuracy';
    $unit = 'm';
  }
  elsif($event =~ m/distance/)
  {
    $reading = 'distance';
    $unit = 'km';
  }
  elsif($event =~ m/velocity/)
  {
    $reading = 'velocity';
    $unit = 'km/h';
  }
  elsif($event =~ m/heading/)
  {
    $reading = 'heading';
    $unit = 'deg';
  }
  elsif($event =~ m/batteryPercent/)
  {
    $reading = 'batteryPercent';
    $unit = '%';
  }
  elsif($event =~ m/batteryState/)
  {
    $reading = 'batteryState';
    $unit = '';
  }
  elsif($event =~ m/steps/)
  {
    $reading = 'steps';
    $unit = 'steps';
  }
  elsif($event =~ m/walking/)
  {
    $reading = 'walking';
    $unit = 'm';
  }
  elsif($event =~ m/floorsup/)
  {
    $reading = 'floorsup';
    $unit = 'floors';
  }
  elsif($event =~ m/floorsdown/)
  {
    $reading = 'floorsdown';
    $unit = 'floors';
  }
  elsif($event =~ m/pressure/)
  {
    $reading = 'pressure';
    $unit = 'mbar';
  }
  else
  {
    $value = $parts[1];
    $value = $value." ".$parts[2] if(defined($parts[2]));
  }
  #Log3 ("dbsplit", 5, "output ".$reading." / ".$value." / ".$unit);

  return ($reading, $value, $unit);
}

##########################

sub livetracking_distance($$$) {
  my ($hash, $loc1, $loc2) = @_;
  my $name = $hash->{NAME};

  my @location1 = split(',', $loc1);
  my @location2 = split(',', $loc2);
  my $lat1 = $location1[0];
  my $lon1 = $location1[1];
  my $lat2 = $location2[0];
  my $lon2 = $location2[1];
  my $theta = $lon1 - $lon2;
  my $dist = sin(livetracking_deg2rad($lat1)) * sin(livetracking_deg2rad($lat2)) + cos(livetracking_deg2rad($lat1)) * cos(livetracking_deg2rad($lat2)) * cos(livetracking_deg2rad($theta));
  $dist  = livetracking_acos($dist);
  $dist = livetracking_rad2deg($dist);
  my $round = AttrVal($hash->{NAME}, "roundDistance", 0.1);
  $dist = $dist * 60 / $round * 1.85316;
  #Log3 ($name, 0, "$name DistRound: ".$dist."=".livetracking_roundfunc($dist)."*".$round);
  return livetracking_roundfunc($dist)*$round;
}

sub livetracking_roundfunc($) {
  my ($number) = @_;
  return sprintf("%.0f", $number);
  #return Math::Round::round($number);
}

sub livetracking_acos($) {
  my ($rad) = @_;
  my $ret = atan2(sqrt(1 - $rad**2), $rad);
  return $ret;
}

sub livetracking_deg2rad($) {
  my ($deg) = @_;
  my $pi = atan2(1,1) * 4;
  return ($deg * $pi / 180);
}

sub livetracking_rad2deg($) {
  my ($rad) = @_;
  my $pi = atan2(1,1) * 4;
  return ($rad * 180 / $pi);
}
##########################

sub livetracking_utf8clean($) {
  my ($string) = @_;
  my $log = "";

  return $string if(utf8::is_utf8($string));
  return encode_utf8($string);


  if($string !~ m/^[\w\.,!@#$%^&*()\\|<>"' _:;\/?=+-]+$/)
  {
    $log .= $string."(standard) ";
    $string =~ s/Ä/Ae/g;
    $string =~ s/Ö/Oe/g;
    $string =~ s/Ü/Ue/g;
    $string =~ s/ä/ae/g;
    $string =~ s/ö/oe/g;
    $string =~ s/ü/ue/g;
    $string =~ s/ß/ss/g;
  }
  if($string !~ m/^[\w\.,!@#$%^&*()\\|<>"' _:;\/?=+-]+$/)
  {
    $log .= $string."(single) ";
    $string =~ s/Ã„/Ae/g;
    $string =~ s/Ã–/Oe/g;
    $string =~ s/Ãœ/Ue/g;
    $string =~ s/Ã¤/ae/g;
    $string =~ s/Ã¶/oe/g;
    $string =~ s/Ã¼/ue/g;
    $string =~ s/ÃŸ/ss/g;
  }
  if($string !~ m/^[\w\.,!@#$%^&*()\\|<>"' _:;\/?=+-]+$/)
  {
    $log .= $string."(double) ";
    $string =~ s/Ãƒâ€ž/Ae/g;
    $string =~ s/Ãƒâ€“/Oe/g;
    $string =~ s/ÃƒÅ“/Ue/g;
    $string =~ s/ÃƒÂ¤/ae/g;
    $string =~ s/ÃƒÂ¶/oe/g;
    $string =~ s/ÃƒÂ¼/ue/g;
    $string =~ s/ÃƒÅ¸/ss/g;
  }
  if($string !~ m/^[\w\.,!@#$%^&*()\\|<>"' _:;\/?=+-]+$/)
  {
    $log .= $string."(unknown)";
    $string =~ s/[ÀÁÂÃĀĂȦẢÅǍȀȂĄẠḀẦẤẪẨẰẮẴẲǠǞǺẬẶȺⱭⱯⱰÆǼǢ]/A/g;
    $string =~ s/[ḂƁḄḆƂƄɃℬ]/B/g;
    $string =~ s/[ĆĈĊČƇÇḈȻ©℃]/C/g;
    $string =~ s/[ḊƊḌḎḐḒĎÐĐƉƋ]/D/g;
    $string =~ s/[ÈÉÊẼĒĔĖËẺĚȄȆẸȨĘḘḚỀẾỄỂḔḖỆḜƎɆƐƏ]/E/g;
    $string =~ s/[ḞƑ℉]/F/g;
    $string =~ s/[ǴĜḠĞĠǦƓĢǤ]/G/g;
    $string =~ s/[ĤḦȞḤḨḪĦⱧⱵǶℌ]/H/g;
    $string =~ s/[ÌÍÎĨĪĬİÏỈǏỊĮȈȊḬƗḮℑ]/I/g;
    $string =~ s/[ĲĴɈ]/J/g;
    $string =~ s/[ḰǨḴƘḲĶⱩ]/K/g;
    $string =~ s/[ĹḺḶĻḼĽĿŁḸȽⱠⱢ]/L/g;
    $string =~ s/[ḾṀṂⱮƜℳ]/M/g;
    $string =~ s/[ǸŃÑṄŇŊƝṆŅṊṈȠ№]/N/g;
    $string =~ s/[ÒÓÔÕŌŎȮỎŐǑȌȎƠǪỌƟØỒỐỖỔȰȪȬṌṐṒỜỚỠỞỢǬǾƆŒƢ]/O/g;
    $string =~ s/[ṔṖƤⱣ℗]/P/g;
    $string =~ s/[Ɋ]/Q/g;
    $string =~ s/[ŔṘŘȐȒṚŖṞṜƦɌⱤ®Ω]/R/g;
    $string =~ s/[ŚŜṠŠṢȘŞⱾṤṦṨƧ℠]/S/g;
    $string =~ s/[ṪŤƬƮṬȚŢṰṮŦȾ™]/T/g;
    $string =~ s/[ÙÚÛŨŪŬỦŮŰǓȔȖƯỤṲŲṶṴṸṺǛǗǕǙỪỨỮỬỰɄ]/U/g;
    $string =~ s/[ṼṾƲɅ]/V/g;
    $string =~ s/[ẀẂŴẆẄẈⱲ]/W/g;
    $string =~ s/[ẊẌ]/X/g;
    $string =~ s/[ỲÝŶỸȲẎŸỶƳỴɎ]/Y/g;
    $string =~ s/[ŹẐŻŽȤẒẔƵⱿⱫℨ]/Z/g;

    $string =~ s/[àáâãāăȧäảåǎȁȃąạḁẚầấẫẩằắẵẳǡǟǻậặⱥɑɐɒæǽǣª]/a/g;
    $string =~ s/[ḃɓḅḇƀƃƅ]/b/g;
    $string =~ s/[ćĉċčƈçḉȼ]/c/g;
    $string =~ s/[ḋɗḍḏḑḓďđƌȡÞþ]/d/g;
    $string =~ s/[èéêẽēĕėëẻěȅȇẹȩęḙḛềếễểḕḗệḝɇɛǝⱸⱻ]/e/g;
    $string =~ s/[ḟƒ]/f/g;
    $string =~ s/[ǵĝḡğġǧɠģǥℊ]/g/g;
    $string =~ s/[ĥḣḧȟḥḩḫẖħⱨⱶƕ]/h/g;
    $string =~ s/[ìíîĩīĭıïỉǐịįȉȋḭɨḯℹ︎]/i/g;
    $string =~ s/[ĳĵǰȷɉ]/j/g;
    $string =~ s/[ḱǩḵƙḳķĸⱪ]/k/g;
    $string =~ s/[ĺḻḷļḽľŀłƚḹȴⱡ]/l/g;
    $string =~ s/[ḿṁṃɱɯ]/m/g;
    $string =~ s/[ǹńñṅňŋɲṇņṋṉŉƞȵ]/n/g;
    $string =~ s/[òóôõōŏȯöỏőǒȍȏơǫọɵøồốỗổȱȫȭṍṏṑṓờớỡởợǭộǿɔœƍⱷⱺƣº]/o/g;
    $string =~ s/[ṕṗƥ]/p/g;
    $string =~ s/[ɋ]/q/g;
    $string =~ s/[ŕṙřȑȓṛŗṟṝɍⱹ]/r/g;
    $string =~ s/[śŝṡšȿṥṧṩƨßſẛ]/s/g;
    $string =~ s/[ṫẗťƭʈƫṭțţṱṯŧⱦȶ]/t/g;
    $string =~ s/[ùúûũūŭüủůűǔȕưụṳųṷṵṹṻǜǘǖǚừứữửựʉµ]/u/g;
    $string =~ s/[ṽṿⱱⱴʌ]/v/g;
    $string =~ s/[ẁẃŵẇẅẘẉⱳ]/w/g;
    $string =~ s/[ẋẍ]/x/g;
    $string =~ s/[ỳýŷȳẏÿỷẙƴỵɏ]/y/g;
    $string =~ s/[źẑżžȥẓẕƶɀⱬ]/z/g;

    #$string =~ s/[^!-~\s]//g;
    $string =~ s/[^\w\.,!@#$%^&*()\\|<>"' _:;\/?=+-]//g;
  }
  Log3 "utf8clean", 4, "Cleaned $string // $log" if($log ne "");
  return $string;}
1;

=pod
=item device
=item summary Position tracking via OwnTracks, Life360 and Swarm
=begin html

<a name="livetracking"></a><h3>livetracking</h3>
<ul>
  This modul pulls livetracking data from Life360 and Swarm (FourSquare).<br/>
  Data can also be pushed from OwnTracks or Traccar (iOS).<br/>
  Swarm Token: https://foursquare.com/oauth2/authenticate?client_id=EFWJ0DNVIREJ2CY1WDIFQ4MAL0ZGZAZUYCNE0NE0XZC3NCPX&response_type=token&redirect_uri=http://localhost&display=wap
  <br/><br/>

  <a name="livetrackingdefine"></a><b>Define</b>
  <ul>
    <code>define &lt;name&gt; livetracking &lt;...&gt;</code>
    <br>
    Example: <code>define livetrackingdata livetracking [life360_email] [life360_pass] [openpaths_key] [openpaths_secret] [swarm_token]</code><br/>
    Any combination of these services can be defined as long as their order is correct.
    <br>&nbsp;
    <li><code>...</code>
      <br>
      Reverse geocoding: Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright
    </li><br>
  </ul>

  <br>
  <a name="livetrackingget"></a><b>Get</b>
   <ul>
      <li><a name="#All">All</a>
      <br/>
      Manually trigger a data update for all sources (OpenPaths/Swarm)
      </li><br>
      <li><a name="#OpenPaths">OpenPaths</a>
      <br/>
      Manually trigger a data update for OpenPaths
      </li><br>
      <li><a name="#Life360">Life360</a>
      <br/>
      Manually trigger a data update for Life360
      </li><br>
      <li><a name="#Swarm">Swarm</a>
      <br/>
      Manually trigger a data update for Swarm
      </li><br>
      <li><a name="#owntracksLocation">owntracksLocation</a>
      <br/>
      Request position from OwnTracks
      </li><br>
      <li><a name="#owntracksSteps">owntracksSteps</a>
      <br/>
      Request steps data from OwnTracks
      </li><br>
      <li><a name="#address">address [&lt;lat,lng&gt;/short/long]</a>
      <br/>
      Get an address from coordinates<br/>
      </li><br>
  </ul>

  <br>
  <a name="livetrackingset"></a><b>Set</b>
   <ul>
      <li><a name="#owntracksMessage">owntracksMessage</a>
      <br>
      Send a message to OwnTracks
      </li><br>
   <li><a name="#bootstrapLife360">bootstrapLife360</a>
   <br>
   Re-initialize Life360 login data
   </li><br>
  </ul>

  <br>
  <a name="livetrackingreadings"></a><b>Readings</b>
   <ul>
      <li><code>location</code>
      <br>
      GPS position
      </li><br>
      <li><code>latitude</code>
      <br>
      GPS position - latitude
      </li><br>
      <li><code>longitude</code>
      <br>
      GPS position - longitude
      </li><br>
      <li><code>distance</code> (km)
      <br>
      GPS distance from home
      </li><br>
      <li><code>accuracy</code> (m)
      <br>
      GPS accuracy
      </li><br>
      <li><code>altitude</code> (m)
      <br>
      GPS altitude
      </li><br>
      <li><code>velocity</code> (km/h)
      <br>
      GPS velocity
      </li><br>
      <li><code>heading</code> (deg)
      <br>
      GPS heading
      </li><br>
      <li><code>place</code>
      <br>
      Swarm place name
      </li><br>
      <li><code>steps</code> (steps)
      <br>
      iOS walked steps
      </li><br>
      <li><code>walking</code> (m)
      <br>
      iOS walked distance
      </li><br>
      <li><code>floorsup</code> (floors)
      <br>
      iOS floors walked up
      </li><br>
      <li><code>floorsdown</code> (floors)
      <br>
      iOS floors walked down
      </li><br>
      <li><code>zone_N</code> (active/inactive)
      <br>
      Zone status in OwnTracks
      </li><br>
      <li><code>beacon</code>
      <br>
      Beacon ID from OwnTracks
      </li><br>
      <li><code>beacon_N_X</code>
      <br>
      Beacon data for saved beacons for indoor positioning
      </li><br>
      <li><code>batteryState</code> (ok/low)
      <br>
      Battery state (can be set through attribute batteryWarning )
      </li><br>
      <li><code>batteryPercent</code> (%)
      <br>
      Battery percentage
      </li><br>
      <li><code>connection</code> (mobile/wifi/offline/unknown)
      <br>
      Phone connection type from OwnTracks at last position
      </li><br>
  </ul>


  <br>
  <a name="livetrackingattr"></a><b>Attributes</b>
   <ul>
      <li><a name="batteryWarning">batteryWarning</a> (%)
         <br>
         Set battery ok/low threshold
      </li><br>
      <li><a name="beacon_0">beacon_N</a>
         <br>
         Saved beacon IDs from OwnTracks for indoor positioning, e.g.:<br/>
         FDA50693-A4E2-4FB1-AFCF-C6EB07647825,19789,1
      </li><br>
      <li><a name="zonename_0">zonename_N</a>
         <br>
         Assign zone name from OwnTracks
      </li><br>
      <li><a name="home">home</a> (lat,lon)
         <br>
         Home location
      </li><br>
      <li><a name="swarmHome">swarmHome</a> (lat,lon)
         <br>
         Fake home location (that is assigned to private homes for security reasons) of your Swarm home (exact position)
      </li><br>
      <li><a name="filterAccuracy">filterAccuracy</a> (m)
         <br>
         Minimum accuracy of GPS location to update any readings
      </li><br>
      <li><a name="roundDistance">roundDistance</a> (km)
         <br>
         Rounding for distance reading to prevent too many changes
      </li><br>
      <li><a name="roundAltitude">roundAltitude</a> (m)
         <br>
         Rounding for altitude reading to prevent too many changes
      </li><br>
      <li><a name="owntracksDevice">owntracksDevice</a>
         <br>
         OwnTracks MQTT device to look for notifies from
      </li><br>
      <li><a name="addressLanguage">addressLanguage</a> (de/en/fr/es/it/nl)
         <br>
         Preferred language used to return reverse geocoding results
      </li><br>
      <li><a name="addressReading">createAddressReading</a> (0/1)
         <br>
         Write reverse geocoding results to address reading
      </li><br>
      <li><a name="osmandServer">osmandServer</a> (0/1)
         <br>
         Starts an OsmAnd compatible listener on FHEM which can be entered into traccar-client directly.<br/>
         This is also compatible with OwnTracks HTTP mode.<br/>
         Traccar for Android supports no authentication, OwnTracks may need separate fields instead of <i>user:pass</i> in the address<br/>
         <code>https://user:pass@your.fhem.ip/fhem/osmand</code> (address to be entered in the client)
      </li><br>
      <li><a name="osmandId">osmandId</a> (if more than one instance is used)
         <br>
         The device identifier that is set in the OsmAnd client and transmitted in the request as <i>id</i><br/>
         If OwnTracks HTTP mode is used, this can be the TrackerID
      </li><br>

  </ul>
</ul>
=end html
=cut
