##############################################
# $Id$$$ 2018-11-01
#
#  98_livetracking.pm
#
#  2018 Markus Moises < vorname at nachname . de >
#
#  This module provides livetracking data from OwnTracks, OpenPaths and Swarm (FourSquare)
#
#
##############################################################################
#
# define <name> livetracking <openpaths_key> <openpaths_secret> <swarm_token>
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
                                $readingFnAttributes;


}

sub livetracking_Define($$$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> livetracking <openpaths_key> <openpaths_secret> <swarm_token>" if(int(@a) < 2 || int(@a) > 7 );
  my $name = $hash->{NAME};

  $hash->{OAuth_exists} = $libcheck_hasOAuth if($libcheck_hasOAuth);

  if(int(@a) == 4 ) {
    $hash->{helper}{openpaths_key} = $a[2];# if($hash->{OAuth_exists});
    $hash->{helper}{openpaths_secret} = $a[3];# if($hash->{OAuth_exists});
  }
  elsif(int(@a) == 3 ) {
    $hash->{helper}{swarm_token} = $a[2];
  }
  elsif(int(@a) == 5 ) {
    $hash->{helper}{openpaths_key} = $a[2];# if($hash->{OAuth_exists});
    $hash->{helper}{openpaths_secret} = $a[3];# if($hash->{OAuth_exists});
    $hash->{helper}{swarm_token} = $a[4];
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

  #$hash->{STATE} = "Initialized";

  return undef;
}

sub livetracking_Undefine($$) {
  my ($hash, $arg) = @_;
  RemoveInternalTimer($hash);
  return undef;
}


sub livetracking_Set($$@) {
  my ($hash, $name, $command, @parameters) = @_;

  my $usage = "Unknown argument $command, choose one of";
  if(defined($attr{$name}{owntracksDevice}))
  {
    $usage .= " owntracksMessage";
  }
  else{
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

  return undef;
}

sub livetracking_Get($@) {
  my ($hash, @a) = @_;
  my $command = $a[1];
  my $parameter = $a[2];# if(defined($a[2]));
  my $name = $hash->{NAME};


  my $usage = "Unknown argument $command, choose one of All:noArg OpenPaths:noArg Swarm:noArg";
  $usage .= " owntracksLocation:noArg owntracksSteps:noArg" if(defined($attr{$name}{owntracksDevice}));
  $usage .= " address";

  return $usage if $command eq '?';

  RemoveInternalTimer($hash);

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
     if(defined($location[1])) {
       my($err,$data) = HttpUtils_BlockingGet({
         url => "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=".$location[0]."&lon=".$location[1]."&addressdetails=1&limit=1",
         noshutdown => 1,
       });
       return "data error" if($err);
       return "invalid json" if( $data !~ m/^{.*}$/ && $data !~ m/^\[.*\]$/ );
       my $json = eval { JSON->new->utf8(0)->decode($data) };
       return "invalid json evaluation" if($@);
       if( $parameter eq "short" && defined($json->{display_name}) ) {
         return $json->{display_name};
       } elsif( defined($json->{address}) ) {
         my $addr = "";
         $addr .= $json->{address}->{road}." " if(defined($json->{address}->{road}));
         $addr .= $json->{address}->{path}." " if(defined($json->{address}->{path}) && !defined($json->{address}->{road}));
         $addr .= $json->{address}->{bridleway}." " if(defined($json->{address}->{bridleway}) && !defined($json->{address}->{road}) && !defined($json->{address}->{path}) && !defined($json->{address}->{path}));
         $addr .= $json->{address}->{footway}." " if(defined($json->{address}->{footway}) && !defined($json->{address}->{road}) && !defined($json->{address}->{path}) && !defined($json->{address}->{bridleway}));
         $addr .= $json->{address}->{house_number} if(defined($json->{address}->{house_number}));
         $addr .= "\n".$json->{address}->{neighbourhood} if(defined($json->{address}->{neighbourhood}) && $parameter eq "long");
         $addr .= "\n".$json->{address}->{suburb} if(defined($json->{address}->{suburb}) && $parameter eq "long");
         $addr .= "\n" if(defined($json->{address}->{postcode}) || defined($json->{address}->{city}) || defined($json->{address}->{town}));
         $addr .= $json->{address}->{postcode}." " if(defined($json->{address}->{postcode}));
         $addr .= $json->{address}->{city} if(defined($json->{address}->{city}));
         $addr .= $json->{address}->{town}." " if(defined($json->{address}->{town}) && !defined($json->{address}->{city}));
         $addr .= $json->{address}->{village}." " if(defined($json->{address}->{village}) && !defined($json->{address}->{city}) && !defined($json->{address}->{town}));
         $addr .= "\n".$json->{address}->{county} if(defined($json->{address}->{county}) && $parameter eq "long");
         $addr .= "\n" if((defined($json->{address}->{state_district}) || defined($json->{address}->{state})) && $parameter eq "long");
         $addr .= $json->{address}->{state_district}." " if(defined($json->{address}->{state_district}) && $parameter eq "long");
         $addr .= $json->{address}->{state} if(defined($json->{address}->{state}) && $parameter eq "long");
         $addr .= "\n".$json->{address}->{country} if(defined($json->{address}->{country}));
         #Log3 ($name, 3, "$name: ".Dumper($json));
         return $addr;
       } elsif( defined($json->{display_name}) ) {
         return $json->{display_name};
       } else {
         return "no data";
       }
     } else {
       return "invalid coordinates";
     }
     return undef;
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

  return undef;
}


sub livetracking_GetOpenPaths($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #RemoveInternalTimer($hash);

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
  InternalTimer( gettimeofday() + $interval, "livetracking_GetAll", $hash, 0);
  $hash->{UPDATED} = FmtDateTime(time());

  return undef;
}



sub livetracking_GetSwarm($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #RemoveInternalTimer($hash);

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


  my $interval = AttrVal($hash->{NAME}, "interval", 1800);
  #RemoveInternalTimer($hash);
  InternalTimer( gettimeofday() + $interval, "livetracking_GetAll", $hash, 0);
  $hash->{UPDATED} = FmtDateTime(time());

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


    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{t});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
    readingsBulkUpdate($hash, "location", $dataset->{lat}.",".$dataset->{lon});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
    #setReadingsVal($hash, "location", $dataset->{lat}.",".$dataset->{lon}, FmtDateTime($dataset->{t}));
    #push(@{$hash->{CHANGED}}, "location: ".$dataset->{lat}.",".$dataset->{lon});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));


    if(defined($dataset->{alt}) && $dataset->{alt} ne '0')
    {
      my $newaltitude = livetracking_roundfunc($dataset->{alt}/$altitudeRound)*$altitudeRound;
      #Log3 ($name, 0, "$name SwarmRound: ".$dataset->{alt}."/".$altitudeRound." = ".livetracking_roundfunc($dataset->{alt}/$altitudeRound)." *".$altitudeRound);

      if($altitude ne $newaltitude)
      {
        #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{t});
        #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
        readingsBulkUpdate($hash, "altitude", $newaltitude);
        $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
        #setReadingsVal($hash, "altitude", $newaltitude." m", FmtDateTime($dataset->{t}));
        #push(@{$hash->{CHANGED}}, "altitude: ".$newaltitude." m");
        #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
        $altitude = $newaltitude;
      }
    }
    if(defined($dataset->{device}) && $dataset->{device} ne $device)
    {
      #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{t});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
      readingsBulkUpdate($hash, "deviceOpenPaths", $dataset->{device});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
      #setReadingsVal($hash, "deviceOpenPaths", $dataset->{device}, FmtDateTime($dataset->{t}));
      #push(@{$hash->{CHANGED}}, "deviceOpenPaths: ".$dataset->{device});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
    }
    if(defined($dataset->{os}) && $dataset->{os} ne $os)
    {
      #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{t});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
      readingsBulkUpdate($hash, "osOpenPaths", $dataset->{os});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
      #setReadingsVal($hash, "osOpenPaths", $dataset->{os}, FmtDateTime($dataset->{t}));
      #push(@{$hash->{CHANGED}}, "osOpenPaths: ".$dataset->{os});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
    }
    if(defined($dataset->{version}) && $dataset->{version} ne $version)
    {
      #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{t});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
      readingsBulkUpdate($hash, "versionOpenPaths", $dataset->{version});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
      #setReadingsVal($hash, "versionOpenPaths", $dataset->{version}, FmtDateTime($dataset->{t}));
      #push(@{$hash->{CHANGED}}, "versionOpenPaths: ".$dataset->{version});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
    }
    if(defined($attr{$name}{home}))
    {
      #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{t});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
      readingsBulkUpdate($hash, "distance", livetracking_distance($hash,$dataset->{lat}.",".$dataset->{lon},$attr{$name}{home}));
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
      #setReadingsVal($hash, "distance", livetracking_distance($hash,$dataset->{lat}.",".$dataset->{lon},$attr{$name}{home})." km", FmtDateTime($dataset->{t}));
      #push(@{$hash->{CHANGED}}, "distance: ".livetracking_distance($hash,$dataset->{lat}.",".$dataset->{lon},$attr{$name}{home})." km");
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{t}));
    }
    $updated = 1;

    #$hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{t});
    readingsEndUpdate($hash, 1); # End update readings
  }



  if($updated == 1)
  {
    #readingsSingleUpdate($hash,"lastOpenPaths",$lastreading,1);
    #$hash->{CHANGED} = ();
    #$hash->{CHANGETIME} = ();
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

    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{createdAt});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{createdAt}));
    readingsBulkUpdate($hash, "location", $loc);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});
    #setReadingsVal($hash, "location", $loc, FmtDateTime($dataset->{createdAt}));
    #push(@{$hash->{CHANGED}}, "location: ".$loc);
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{createdAt}));

    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{createdAt});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{createdAt}));
    readingsBulkUpdate($hash, "place", $place);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});
    #setReadingsVal($hash, "place", $dataset->{venue}->{name}, FmtDateTime($dataset->{createdAt}));
    #push(@{$hash->{CHANGED}}, "place: ".$dataset->{venue}->{name});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{createdAt}));


    if(defined($dataset->{source}->{name}) && $dataset->{source}->{name} ne $device)
    {
      #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{createdAt});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{createdAt}));
      readingsBulkUpdate($hash, "deviceSwarm", $dataset->{source}->{name});
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});
      #setReadingsVal($hash, "deviceSwarm", $dataset->{source}->{name}, FmtDateTime($dataset->{createdAt}));
      #push(@{$hash->{CHANGED}}, "deviceSwarm: ".$dataset->{source}->{name});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{createdAt}));
    }
    if(defined($attr{$name}{home}))
    {
      #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{createdAt});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{createdAt}));
      readingsBulkUpdate($hash, "distance", livetracking_distance($hash,$loc,$attr{$name}{home})." km");
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{createdAt});
      #setReadingsVal($hash, "distance", livetracking_distance($hash,$loc,$attr{$name}{home})." km", FmtDateTime($dataset->{createdAt}));
      #push(@{$hash->{CHANGED}}, "distance: ".livetracking_distance($hash,$loc,$attr{$name}{home})." km");
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{createdAt}));
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
    }
    elsif(($dev->{CHANGED}[0] =~ m/position":[ ]?{/))
    {
      $invaliddata = 0;#traccar
    }
    if($invaliddata == 1){
      Log3 ($name, 5, "WRONG MQTT TYPE ".Dumper($dev->{CHANGED}[0]));
      return undef;
    }

    $data= substr($dev->{CHANGED}[0],index($dev->{CHANGED}[0], ": {")+2);
    $dataset = JSON->new->utf8(0)->decode($data);

  } else {
    Log3 ($name, 5, "livetracks: Notify ignored from ".$devName);
    return undef;
  }




  if($dev->{CHANGED}[0] =~ m/_type":[ ]?"steps/)
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

  if($dev->{CHANGED}[0] =~ m/_type":[ ]?"beacon/)
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


  my $accurate = 1;
  $accurate = 0 if(defined($attr{$name}{filterAccuracy}) and defined($dataset->{acc}) and $attr{$name}{filterAccuracy} < $dataset->{acc});

  readingsBeginUpdate($hash); # Start update readings
  $hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
  my $changeindex = 0;

  Log3 ($name, 4, "$name OwnTracks: ".FmtDateTime($dataset->{tst})."  ".$data);

  #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
  #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
  if($accurate)
  {
    readingsBulkUpdate($hash, "location", $dataset->{lat}.",".$dataset->{lon});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  else
  {
    Log3 ($name, 3, "$name OwnTracks: Inaccurate reading ignored: ".$dataset->{lat}.",".$dataset->{lon}." (".$dataset->{acc}.")");
  }
  #setReadingsVal($hash, "location", $dataset->{lat}.",".$dataset->{lon}, FmtDateTime($dataset->{tst}));
  #push(@{$hash->{CHANGED}}, "location: ".$dataset->{lat}.",".$dataset->{lon});
  #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));


  if(defined($dataset->{alt}) and $dataset->{alt} != 0 and $accurate)
  {
    my $altitudeRound = AttrVal($hash->{NAME}, "roundAltitude", 1);
    my $newaltitude = livetracking_roundfunc($dataset->{alt}/$altitudeRound)*$altitudeRound;
    #Log3 ($name, 0, "$name OTRound: ".$dataset->{alt}."/".$altitudeRound." = ".livetracking_roundfunc($dataset->{alt}/$altitudeRound)."*".$altitudeRound);

    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
    readingsBulkUpdate($hash, "altitude", $newaltitude);
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    #setReadingsVal($hash, "altitude", $newaltitude." m", FmtDateTime($dataset->{tst}));
    #push(@{$hash->{CHANGED}}, "altitude: ".$newaltitude." m");
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
  }
  if(defined($dataset->{tid}) and $dataset->{tid} ne "")
  {
    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
    readingsBulkUpdate($hash, "id", $dataset->{tid});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    #setReadingsVal($hash, "id", $dataset->{tid}, FmtDateTime($dataset->{tst}));
    #push(@{$hash->{CHANGED}}, "id: "$dataset->{tid});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
  }
  if(defined($dataset->{doze}) and $dataset->{doze} ne "")
  {
    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
    readingsBulkUpdate($hash, "doze", $dataset->{doze});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    #setReadingsVal($hash, "doze", $dataset->{doze}, FmtDateTime($dataset->{tst}));
    #push(@{$hash->{CHANGED}}, "doze: "$dataset->{doze});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
  }
  if(defined($dataset->{acc}) and $dataset->{acc} > 0)# and $accurate)
  {
    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
    readingsBulkUpdate($hash, "accuracy", $dataset->{acc});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    #setReadingsVal($hash, "accuracy", $dataset->{acc}." m", FmtDateTime($dataset->{tst}));
    #push(@{$hash->{CHANGED}}, "accuracy: ".$dataset->{acc}." m");
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
  }
  if(defined($dataset->{vel}) and $dataset->{vel} >= 0 and $accurate)
  {
    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
    readingsBulkUpdate($hash, "velocity", $dataset->{vel});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    #setReadingsVal($hash, "velocity", $dataset->{vel}." km/h", FmtDateTime($dataset->{tst}));
    #push(@{$hash->{CHANGED}}, "velocity: ".$dataset->{vel}." km/h");
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
  }
  #else
  #{
  #  fhem( "deletereading $name velocity" );
  #}
  if(defined($dataset->{cog}) and $dataset->{cog} >= 0 and $accurate)
  {
    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
    readingsBulkUpdate($hash, "heading", $dataset->{cog});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    #setReadingsVal($hash, "heading", $dataset->{cog}." deg", FmtDateTime($dataset->{tst}));
    #push(@{$hash->{CHANGED}}, "heading: ".$dataset->{cog}." deg");
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
  }
  #else
  #{
  #  fhem( "deletereading $name heading" );
  #}
  if(defined($dataset->{batt}))
  {
    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
    readingsBulkUpdate($hash, "batteryPercent", $dataset->{batt});
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    readingsBulkUpdate($hash, "batteryState", (int($dataset->{batt}) <= int(AttrVal($name, "batteryWarning" , "20")))?"low":"ok");
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    #setReadingsVal($hash, "battery", $dataset->{batt}." %", FmtDateTime($dataset->{tst}));
    #push(@{$hash->{CHANGED}}, "battery: ".$dataset->{batt}." %");
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
  }
  if(defined($dataset->{conn}))
  {
    readingsBulkUpdate($hash, "connection", (($dataset->{conn} eq "m")?"mobile":($dataset->{conn} eq "w")?"wifi":($dataset->{conn} eq "o")?"offline":"unknown"));
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  }
  if(defined($dataset->{p}) and $dataset->{p} > 0)
  {
    readingsBulkUpdate($hash, "pressure", $dataset->{p}*10);
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
      #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
      readingsBulkUpdate($hash, "place", $place);
      $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
      #setReadingsVal($hash, "place", $dataset->{desc}, FmtDateTime($dataset->{tst}));
      #push(@{$hash->{CHANGED}}, "place: ".$dataset->{desc});
      #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
      foreach my $placenumber (@placenumbers)
      {
        #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
        #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
        readingsBulkUpdate($hash, "zone_".$placenumber,"active");
        $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
        #readingsSingleUpdate($hash,"zone_".$placenumber,"active",1);
      }
    }
      else
    {
      #fhem( "deletereading $name place" ) if(ReadingsVal($name,"place","undefined") eq $dataset->{desc});
      foreach my $placenumber (@placenumbers)
      {
        #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
        #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
        readingsBulkUpdate($hash, "zone_".$placenumber,"inactive");
        $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
        #readingsSingleUpdate($hash,"zone_".$placenumber,"inactive",1);
      }
    }
  }
  if(defined($attr{$name}{home}) and $accurate)
  {
    #$hash->{".updateTimestamp"} = FmtDateTime($dataset->{tst});
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
    readingsBulkUpdate($hash, "distance", livetracking_distance($hash,$dataset->{lat}.",".$dataset->{lon},$attr{$name}{home}));
    $hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
    #setReadingsVal($hash, "distance", livetracking_distance($hash,$dataset->{lat}.",".$dataset->{lon},$attr{$name}{home})." km", FmtDateTime($dataset->{tst}));
    #push(@{$hash->{CHANGED}}, "distance: ".livetracking_distance($hash,$dataset->{lat}.",".$dataset->{lon},$attr{$name}{home})." km");
    #push(@{$hash->{CHANGETIME}}, FmtDateTime($dataset->{tst}));
  }

  #$hash->{CHANGETIME}[$changeindex++] = FmtDateTime($dataset->{tst});
  readingsEndUpdate($hash, 1);

  readingsSingleUpdate($hash,".lastOwnTracks",$dataset->{tst},1);

  $hash->{helper}{lastOwnTracks} = $dataset->{tst};

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
      return undef;
    }

    my $json;
    $json = JSON->new->utf8(0)->decode($data);


    if( $param->{type} eq 'openpathsdata' ) {
      livetracking_ParseOpenPaths($hash,$json);
    } elsif( $param->{type} eq 'swarmdata' ) {
      livetracking_ParseSwarm($hash,$json);
    }
  }
}


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
=item summary Position tracking via OwnTracks, OpenPaths and Swarm
=begin html

<a name="livetracking"></a><h3>livetracking</h3>
<ul>
  This modul provides livetracking data from OpenPaths and Swarm (FourSquare).<br/>
  Swarm Token: https://foursquare.com/oauth2/authenticate?client_id=EFWJ0DNVIREJ2CY1WDIFQ4MAL0ZGZAZUYCNE0NE0XZC3NCPX&response_type=token&redirect_uri=http://localhost&display=wap
  <br/><br/>

  <a name="livetrackingdefine"></a><b>Define</b>
  <ul>
    <code>define &lt;name&gt; livetracking &lt;...&gt;</code>
    <br>
    Example: <code>define livetrackingdata livetracking [openpaths_key] [openpaths_secret] [swarm_token]</code><br/>
    Either both, just OpenPaths, just Swarm or none of them can be defined.
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
      <li><a name="#address">address [short/long/lat,lng]</a>
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
  </ul>

  <br>
  <a name="livetrackingreadings"></a><b>Readings</b>
   <ul>
      <li><code>location</code>
      <br>
      GPS position
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

  </ul>
</ul>
=end html
=cut
