# $Id$

package main;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use HttpUtils;

use vars qw(%modules);
use vars qw(%defs);
use vars qw(%attr);
use vars qw($readingFnAttributes);
sub Log($$);
sub Log3($$$);

sub
UnifiProtect_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}   = "UnifiProtect_Read";

  $hash->{DefFn}    = "UnifiProtect_Define";
  $hash->{NotifyFn} = "UnifiProtect_Notify";
  $hash->{UndefFn}  = "UnifiProtect_Undefine";
  $hash->{SetFn}    = "UnifiProtect_Set";
  $hash->{GetFn}    = "UnifiProtect_Get";
  $hash->{AttrFn}   = "UnifiProtect_Attr";
  $hash->{AttrList} = "disable filePath user password ".
                      "sshUser ".
                      $readingFnAttributes;

  $hash->{FW_detailFn}  = "UnifiProtect_detailFn";

  $data{FWEXT}{"/protect"}{FUNC} = "UnifiProtect_CGI";
  #$data{FWEXT}{"/protect"}{FORKABLE} = 1;
}

#####################################


sub
UnifiProtect_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> UnifiProtect <ip> <users> <password>"  if(@a < 3);

  my $name = $a[0];
  $hash->{NAME} = $name;

  my $host = $a[2];

  my $d = $modules{$hash->{TYPE}}{defptr};
  return "$hash->{TYPE} device already defined as $d->{NAME}." if( defined($d) && $name ne $d->{NAME} );
  $modules{$hash->{TYPE}}{defptr} = $hash;

  $hash->{NOTIFYDEV} = "global";

  $hash->{HOST} = $host;
  $hash->{DEF} = $host;

  $hash->{STATE} = 'active';

  CommandAttr(undef,"$name user $a[3]" ) if( defined( $a[3]) );
  CommandAttr(undef,"$name password $a[4]" ) if( defined( $a[4]) );

  if( $init_done ) {
    UnifiProtect_Connect($hash);
  } else {
    readingsSingleUpdate($hash, 'state', 'initialized', 1 );
  }

  return undef;
}

sub
UnifiProtect_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  UnifiProtect_Connect($hash);

  return undef;
}

sub
UnifiProtect_Undefine($$)
{
  my ($hash, $arg) = @_;

  UnifiProtect_killLogWatcher($hash);
  RemoveInternalTimer($hash, "UnifiProtect_Connect");

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}

sub
UnifiProtect_detailFn()
{
  my ($FW_wname, $d, $room, $extPage) = @_; # extPage is set for summaryFn.
  my $hash = $defs{$d};

  return UnifiProtect_2html($hash);
}

sub
UnifiProtect_2html($;$$)
{
  my ($hash,$cams,$width) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );
  return undef if( !defined($hash) );
  $width = 200 if( !$width );
  my $name = $hash->{NAME};

  my @cams;
     @cams = split(',', $cams) if( defined($cams) );

  my $auth = $hash->{helper}{auth};

  my $json = $hash->{helper}{json};
  return undef if( !$json );

  my $javascriptText = "<script type='text/javascript'>
    var keys = {};

    function updateKeys() {
      keys = {};

      var tags = document.getElementsByClassName('unifiProtectSnap');
      for(var i = 0;i < tags.length; i++) {
        var img = tags[i];
        var nvrIp = img.getAttribute('nvrIp');
        var cameraId = img.getAttribute('cameraId');
        var auth = img.getAttribute('auth');

        if( auth === undefined ) continue;
        if( keys[auth] !== undefined ) continue;

        keys[auth] = '';

        var xhr = new XMLHttpRequest();
        xhr.open( 'POST', 'https://'+ nvrIp +':7443/api/auth/access-key' );
        xhr.setRequestHeader( 'Authorization', 'Bearer '+ auth );
        xhr.onload = function() {
          if (xhr.readyState === xhr.DONE) {
            if (xhr.status === 200) {
              keys[auth] = JSON.parse(xhr.responseText).accessKey;

            } else {
              console.log( xhr.status );
            }
          } else {
            console.log( xhr.readyState );
          }

          delete xhr;
        };
        xhr.send();
      }

      setTimeout( function() {updateKeys()}, 1000*60 );
    }

    function loadImages() {
      var tags = document.getElementsByClassName('unifiProtectSnap');
      for(var i = 0;i < tags.length; i++) {
        var img = tags[i];
        var nvrIp = img.getAttribute('nvrIp');
        var cameraId = img.getAttribute('cameraId');
        var auth = img.getAttribute('auth');
        var width = img.width;

        if( auth && keys[auth] === undefined ) { updateKeys(); continue; }
        if( auth && keys[auth] === '' ) continue;

        if( auth )
          tags[i].src='https://'+ nvrIp +':7443/api/cameras/'+cameraId+'/snapshot?accessKey='+keys[auth]+'&w='+width+'&ts='+Date.now()/1000;
        else {
          var name = img.getAttribute('name');
          tags[i].src=nvrIp + '/protect/?name='+name+'&cam='+cameraId+'&width='+width+'&ts='+Date.now()/1000;
        }
      }

      setTimeout( function() {loadImages()}, 1000 );
    }
  </script>";
  $javascriptText =~ s/\n/ /g;
  $javascriptText =~ s/ +/ /g;
  my $html = "$javascriptText<div onload='loadImages()'>";
  $html .= "\n" if( $html );
  $html .= '<iframe style="display:none" onload="loadImages()"></iframe>';
  my $i = 0;
  foreach my $entry (@{$json}) {
    next if( $entry->{deleted} );
    next if( $entry->{state} eq 'DISCONNECTED' );
    my $auth = '';
       $auth = "auth='$hash->{helper}{auth}'" if( $hash->{helper}{auth} );
    my $nvrIp = $FW_ME;
       $nvrIp = $hash->{HOST} if( $hash->{helper}{auth} );
    my $n = '';
       $n = "name='$name'" if( $hash->{helper}{isUnifiOS} );
    if( defined($cams) ) {
      foreach my $cam (@cams) {
        if( ( $cam =~ m/^[0-9]+$/ && int($cam) == $i )
            || $entry->{id} eq $cam
            || $entry->{name} =~ m/$cam/ ) {
          $html .= "\n" if( $html );
          $html .= "  <img width='$width' class='unifiProtectSnap' nvrIp='$nvrIp' cameraId='$entry->{id}' $n $auth>";
        }
      }
    } else {
      $html .= "\n" if( $html );
      $html .= "  <img width='200' class='unifiProtectSnap' nvrIp='$nvrIp' cameraId='$entry->{id}' $n $auth>";
    }

    ++$i;
  }
  $html .= "\n" if( $html );
  $html .= "</div>";

#Log 1, $html;
  return $html;
}

sub
UnifiProtect_CGI(@)
{
  my ($cgi) = @_;
  my ($cmd, $c) = FW_digestCgi($cgi);
  my $name = $FW_webArgs{name};

  $c = $defs{$FW_cname}->{CD};

  if( !$name
      || !defined($defs{$name})
      || $defs{$name}->{TYPE} ne 'UnifiProtect' ) {
    print $c "HTTP/1.1 400 Bad Request\r\n". "Content-Length: 11\r\n\r\n";
    print $c "Bad Request";
    return undef;
  }
  
  my $hash = $defs{$name};

  Log3 $name, 5, "$name: CGI:". Dumper \%FW_webArgs;

  $c = $defs{$FW_cname}->{CD};


  my $json = $hash->{helper}{json};
  return "not jet connected" if( !$json );

  my $cam = $FW_webArgs{cam};
  my $width = $FW_webArgs{width};
  return "usage: snapshot cam=<cam> [width=<width>] [fileName=<fileName>]" if( !defined($cam) );
  my $i = 0;
  my $found;
  foreach my $entry (@{$json}) {
    next if( $entry->{deleted} );
    next if( $entry->{state} eq 'DISCONNECTED' );
    if( ( $cam =~ m/^[0-9]+$/ && int($cam) == $i )
        || $entry->{id} eq $cam
        || $entry->{name} =~ m/$cam/ ) {
      $cam = $entry->{id};
      $found = 1;
      #Log 1, "$i $entry->{name}: $entry->{id}";
      last;
    }
    ++$i;
  }

  return "no such cam: $cam" if( !$found );

  my $url = "https://$hash->{HOST}". ($hash->{helper}{isUnifiOS} ? "/proxy/protect/api/cameras/$cam/snapshot"
                                                                 : ":7443/api/cameras/$cam/snapshot");
  $url .= "?w=$width" if( $width );
  my $param = {
    url => $url,
    method => 'GET',
    timeout => 5,
    hash => $hash,
    key => 'snap',
    cname => $FW_cname,
    header => { 'Authorization' => "Bearer $hash->{helper}{auth}",
                'X-CSRF-Token' => $hash->{helper}{csrfToken}, 'Cookie' => $hash->{helper}{cookie} },
  };

  Log3 $name, 4, "$name: fetching data from $url";
  $param->{callback} = \&UnifiProtect_parseHttpAnswer;
  HttpUtils_NonblockingGet( $param );
  return undef;

  my ($err,$ret) = HttpUtils_BlockingGet( $param );

  print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: image/jpeg\r\n",
            "Content-Length: ". length($ret) ."\r\n",
            "Connection: close\r\n",
            "\r\n",
            $ret;

  return undef;
}

sub
UnifiProtect_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "reconnect:noArg snapshot";

  if( $cmd eq 'reconnect' ) {
    $hash->{".triggerUsed"} = 1;

    UnifiProtect_Connect($hash);

    return undef;

  } elsif( $cmd eq 'snapshot' ) {
    my $json = $hash->{helper}{json};
    return "not jet connected" if( !$json );

    my ($param_a, $param_h) = parseParams(\@args);
    my $cam = $param_h->{cam};
    my $width = $param_h->{width};
    return "usage: snapshot cam=<cam> [width=<width>] [fileName=<fileName>]" if( !defined($cam) );
    my $i = 0;
    my $found;
    foreach my $entry (@{$json}) {
      next if( $entry->{deleted} );
      next if( $entry->{state} eq 'DISCONNECTED' );
      if( ( $cam =~ m/^[0-9]+$/ && int($cam) == $i )
          || $entry->{id} eq $cam
          || $entry->{name} =~ m/$cam/ ) {
        $cam = $entry->{id};
        $found = 1;
        #Log 1, "$i $entry->{name}: $entry->{id}";
        last;
      }
      ++$i;
    }

    return "no such cam: $cam" if( !$found );

    my $url = "https://$hash->{HOST}". ($hash->{helper}{isUnifiOS} ? "/proxy/protect/api/cameras/$cam/snapshot"
                                                                   : ":7443/api/cameras/$cam/snapshot");
    $url .= "?w=$width" if( $width );
    my $param = {
      url => $url,
      method => 'GET',
      timeout => 5,
      hash => $hash,
      key => $cmd,
      cam => $cam,
      fileName => $param_h->{fileName} ,
      index => $i,
      header => { 'Authorization' => "Bearer $hash->{helper}{auth}",
                  'X-CSRF-Token' => $hash->{helper}{csrfToken}, 'Cookie' => $hash->{helper}{cookie} },
    };

    Log3 $name, 4, "$name: fetching data from $url";

    $param->{callback} = \&UnifiProtect_parseHttpAnswer;
    HttpUtils_NonblockingGet( $param );

    return undef;

  } elsif( $cmd eq 'user' ) {
    return CommandAttr(undef,"$name $cmd $args[0]" );

  } elsif( $cmd eq 'password' ) {
    return CommandAttr(undef,"$name $cmd $args[0]" );
  }

  return "Unknown argument $cmd, choose one of $list";
}


sub
UnifiProtect_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "user:noArg password:noArg";

  if( $cmd eq 'user' ) {
    my $user = AttrVal($name, 'user', undef);
    return 'no user set' if( !$user );

    $user = UnifiProtect_decrypt( $user );

    return "user: $user";

  } elsif( $cmd eq 'password' ) {
    my $password = AttrVal($name, 'password', undef);
    return 'no password set' if( !$password );

    $password = UnifiProtect_decrypt( $password );

    return "password: $password";

  } elsif( $cmd eq 'events' ) {
    my $url = "https://$hash->{HOST}". ($hash->{helper}{isUnifiOS} ? "/proxy/protect/api/events"
                                                                   : ":7443/api/events");
    $url .= '?type=motion';
    $url .= '&limit=2';
    #$url .= '&start=<timestamp>';
    #$url .= '&end=<timestamp>';
    my $param = {
      url => $url,
      method => 'GET',
      timeout => 5,
      hash => $hash,
      key => 'events',
      header => { 'Authorization' => "Bearer $hash->{helper}{auth}",
                  'X-CSRF-Token' => $hash->{helper}{csrfToken}, 'Cookie' => $hash->{helper}{cookie} },
    };

    Log3 $name, 4, "$name: fetching data from $url";

    $param->{callback} = \&UnifiProtect_parseHttpAnswer;
    HttpUtils_NonblockingGet( $param );

    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
UnifiProtect_Parse($$;$)
{
  my ($hash,$data,$peerhost) = @_;
  my $name = $hash->{NAME};
}
sub
UnifiProtect_parseHttpAnswer($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if( $err ) {
    Log3 $name, 2, "$name: http request ($param->{url}) failed: $err";

    return undef;
  }

  return undef if( !$data );

  my $decoded;
     $decoded = eval { JSON->new->utf8(0)->decode($data) } if( $data =~ m/\{.*\}/s );

  Log3 $name, 5, Dumper $param;
  Log3 $name, 5, "$name: received $data";
  if( $param->{key} eq 'auth' ) {
    if( $decoded && $decoded->{errors} ) {
      Log3 $name, 2, "$name: failed to get authorization: ". join( ',', @{$decoded->{errors}} );

    } elsif( $param->{httpheader} =~ m/X-CSRF-Token:\s?(.*)\r\n/i ) {
      $hash->{helper}{csrfToken} = $1;

      if( $param->{httpheader} =~ m/Set-Cookie:\s?(.*)\r\n/i ) {
        $hash->{helper}{cookie} = $1;
      }

      my $url = "https://$hash->{HOST}/proxy/protect/api/cameras";
      my $param = {
        url => $url,
        method => 'GET',
        timeout => 5,
        hash => $hash,
        key => 'cameras',
        header => { 'X-CSRF-Token' => $hash->{helper}{csrfToken}, 'Cookie' => $hash->{helper}{cookie} },
      };

      Log3 $name, 4, "$name: fetching data from $url";

      $param->{callback} = \&UnifiProtect_parseHttpAnswer;
      HttpUtils_NonblockingGet( $param );

    } elsif( $param->{httpheader} =~ m/Authorization: (.*)\r/ ) {
      $hash->{helper}{auth} = $1;
      $hash->{STATE} = 'connected';

      Log3 $name, 4, "$name: got authorization: $hash->{helper}{auth}";

      my $url = "https://$hash->{HOST}:7443/api/cameras";
      my $param = {
        url => $url,
        method => 'GET',
        timeout => 5,
        hash => $hash,
        key => 'cameras',
        header => { 'Authorization' => "Bearer $hash->{helper}{auth}"  },
      };

      Log3 $name, 4, "$name: fetching data from $url";

      $param->{callback} = \&UnifiProtect_parseHttpAnswer;
      HttpUtils_NonblockingGet( $param );

    } else {
      Log3 $name, 2, "$name: failed to get authorization";
    }

  } elsif( $param->{key} eq 'cameras' ) {
    my $json = eval { decode_json($data) };
    Log3 $name, 2, "$name: json error: $@ in $json" if( $@ );
    Log3 $name, 2, "$name: error: $json->{error}" if( ref($json) eq 'HASH' &&  defined($json->{error} ) );

    $hash->{helper}{json} = $json;

    readingsBeginUpdate($hash);
    my $i = 0;
    foreach my $entry (@{$json}) {
      if( !$entry->{deleted} ) {
      #Log 1, Dumper $entry->{id};
        readingsBulkUpdateIfChanged($hash, "cam${i}name", $entry->{name}, 1);
        readingsBulkUpdateIfChanged($hash, "cam${i}id", $entry->{id}, 1);
        readingsBulkUpdateIfChanged($hash, "cam${i}state", $entry->{state}, 1);
      }
      ++$i;
    }
    readingsBulkUpdateIfChanged($hash, 'totalCount', $i, 1);
    readingsEndUpdate($hash,1);

    RemoveInternalTimer($hash, "UnifiProtect_Connect");
    InternalTimer(gettimeofday() + 900, "UnifiProtect_Connect", $hash);

  } elsif( $param->{key} eq 'snap' ) {
    if( !defined($defs{$param->{cname}}) ) {
      Log 1, "gone";
      return;
    }
    my  $c = $defs{$param->{cname}}->{CD};

    print $c "HTTP/1.1 200 OK\r\n",
              "Content-Type: image/jpeg\r\n",
              "Content-Length: ". length($data) ."\r\n",
              "Connection: close\r\n",
              "\r\n",
              $data;

  } elsif( $param->{key} eq 'snapshot' ) {
    my $modpath = $attr{global}{modpath};
    my $filePath = AttrVal($name, 'filePath', "$modpath/www/snapshots" );

    if(! -d $filePath) {
      my $ret = mkdir "$filePath";
      if($ret == 0) {
        Log3 $name, 1,  "Error while creating filePath $filePath $!";
        return undef;
      }
    }

    my $fileName = $param->{fileName};
    $fileName = $param->{cam} if( !$fileName );
    $fileName .= '.jpg';

    if(!open(FH, ">$filePath/$fileName")) {
      Log3 $name, 1, "Can't write $filePath/$fileName $!";
      return undef;
    }
    print FH $data;
    close(FH);
    Log3 $name, 4, "snapshot $filePath/$fileName written.";

    DoTrigger( $name, "newSnapshot: $param->{index} $filePath/$fileName" );

  } elsif( $param->{key} eq 'events' ) {
    my $json = eval { decode_json($data) };
    Log3 $name, 2, "$name: json error: $@ in $json" if( $@ );
    Log3 $name, 2, "$name: error: $json->{error}" if( ref($json) eq 'HASH' &&  defined($json->{error} ) );

    Log 1, Dumper $json;

    #/api/thumbnails/[hex thumbnail id]?accessKey=[key returned from 'access-key' request above]

  } else {
    Log3 $name, 2, "parseHttpAnswer: unhandled key $param->{key}";

  }

  return undef;
}

sub
UnifiProtect_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf;
  my $ret = sysread($hash->{FH}, $buf, 65536 );
  my $err = int($!);

  if(!defined($ret) && $err == EWOULDBLOCK) {
    return;
  }

#Log 1, $ret;
#Log 1, $buf;
#Log 1, $err;

  if( $ret == 0 && !defined($hash->{PARTIAL}) ) {
    UnifiProtect_killLogWatcher($hash);
  }

  my $data = $hash->{PARTIAL};
  $data .= $buf;

  while($data =~ m/\n/) {
    my $line;
    ($line,$data) = split("\n", $data, 2);

    my($cam, $type);
    if( $line =~ m/password/ ) {
      UnifiProtect_killLogWatcher($hash);

    } elsif( $line =~ m/motion.start ([^[])* / ) {
      $cam = $1;
      $type = 'start';

    } elsif( $line =~ m/motion.stop ([^[])* / ) {
      $cam = $1;
      $type = 'stop';

    } else {
      Log3 $name, 4, "$name: got unknown event: $line";
    }
    if( $cam && $type ) {
      if( $type eq 'start' ) {
        my $json = $hash->{helper}{json};
        $json = [] if( !$json );
        my $i = 0;
        foreach my $entry (@{$json}) {
          last if( $entry->{name} eq $cam );
          ++$i;
        }
        if( $i != 1 ) {
          Log3 $name, 2, "$name: got motion event for unknown cam: $cam";

        } else {
          readingsSingleUpdate($hash, "cam${i}motion", $type, 1);
        }

      } elsif( $type eq 'stop' ) {
      } else {
        Log3 $name, 2, "$name: got unknown event type from cam: $cam";
      }
    }

  }

  $hash->{PARTIAL} = $data

  #UnifiProtect_Parse($hash, $buf, $hash->{CD}->peerhost);
}

sub
UnifiProtect_killLogWatcher($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  kill( 9, $hash->{PID} ) if( $hash->{PID} );

  close($hash->{FH}) if($hash->{FH});
  delete($hash->{FH});
  delete($hash->{FD});

  return if( !$hash->{PID} );
  delete $hash->{PID};

  readingsSingleUpdate($hash, 'state', 'running', 1 );
  Log3 $name, 3, "$name: stopped logfile watcher";

  delete $hash->{PARTIAL};
  delete($selectlist{$name});
}
sub
UnifiProtect_startLogWatcher($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  UnifiProtect_killLogWatcher($hash);

  my $user = AttrVal($name, "sshUser", undef);
  return if( !$user );
  my $logfile = AttrVal($name, "logfile", "/srv/unifi-protect/logs/events.cameras.log" );
  my $cmd = qx(which ssh);
  chomp( $cmd );
  $cmd .= ' -q ';
  $cmd .= $user."\@" if( defined($user) );
  $cmd .= $hash->{HOST};
  $cmd .= " tail  -n 0 -F $logfile";
  #my $cmd = "tail -f /tmp/x";
  Log3 $name, 3, "$name: using $cmd to watch logfile";
  if( my $pid = open( my $fh, '-|', $cmd ) ) {
    $fh->blocking(0);
    $hash->{FH}  = $fh;
    $hash->{FD}  = fileno($fh);
    $hash->{PID} = $pid;

    $selectlist{$name} = $hash;

    readingsSingleUpdate($hash, 'state', 'watching', 1 );

    Log3 $name, 3, "$name: started logfile watcher";
  } else {
    Log3 $name, 2, "$name: failed to start logfile watcher";

  }
}

sub
UnifiProtect_isUnifiOS($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url = "https://$hash->{HOST}/";
  my $param = {
    url => $url,
    method => 'GET',
    timeout => 2,
    #sslargs => { SSL_verify_mode => 0 },
    hash => $hash,
    key => 'check',
  };
  my ($err,$ret) = HttpUtils_BlockingGet( $param );

  if( defined($err) && $err ) {
    Log3 $name, 3, "UnifiProtect_isUnifiOS: error detecting OS: ".$err;
    return;
  }

  delete $hash->{helper}{auth};
  delete $hash->{helper}{cookie};
  if( $param->{httpheader} =~ m/X-CSRF-Token:\s?(.*)\r\n/i ) {
    $hash->{helper}{isUnifiOS} = 1;
    $hash->{helper}{csrfToken} = $1;

  } else {
    $hash->{helper}{isUnifiOS} = 0;
    delete $hash->{helper}{csrfToken};
  }

  Log3 $name, 3, "$name: is UnifiOS: $hash->{helper}{isUnifiOS}";
}

sub
UnifiProtect_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  delete $hash->{helper}{auth};

  return if( IsDisabled($name) );

  UnifiProtect_isUnifiOS( $hash );

  my $user = AttrVal($name, 'user', undef);
  my $password = AttrVal($name, 'password', undef);
  if( !$user ) {
    $hash->{STATE} = 'disconnected';
    Log3 $name, 2, "$name: can't connect without user";
    return undef;
  }
  if( !$password ) {
    $hash->{STATE} = 'disconnected';
    Log3 $name, 2, "$name: can't connect without password";
    return undef;
  }

  $user = UnifiProtect_decrypt( $user );
  $password = UnifiProtect_decrypt( $password );

  my $url = "https://$hash->{HOST}". ($hash->{helper}{isUnifiOS} ? "/api/auth/login"
                                                                 : ":7443/api/auth");
  my $param = {
    url => $url,
    method => 'POST',
    timeout => 5,
    hash => $hash,
    key => 'auth',
    header => { 'Content-Type' => 'application/json' },
    data => "{ \"username\": \"$user\", \"password\": \"$password\" }",
  };

  if( $hash->{helper}{isUnifiOS} ) {
    $param->{header}{'X-CSRF-Token'} = $hash->{helper}{csrfToken};
  }

  Log3 $name, 4, "$name: fetching data from $url";

  $param->{callback} = \&UnifiProtect_parseHttpAnswer;
  HttpUtils_NonblockingGet( $param );

  UnifiProtect_startLogWatcher( $hash ) if( !$hash->{PID} );

  return undef;
}

sub
UnifiProtect_encrypt($)
{
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ m/^crypt:(.*)/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'. $encoded;
}
sub
UnifiProtect_decrypt($)
{
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  $encoded = $1 if( $encoded =~ m/^crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ m/(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
}

sub
UnifiProtect_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  my $hash = $defs{$name};
  if( $attrName eq 'disable' ) {
    if( $cmd eq "set" && $attrVal ) {
      UnifiProtect_killLogWatcher($hash);
      readingsSingleUpdate($hash, 'state', 'disabled', 1 );

    } else {
      readingsSingleUpdate($hash, 'state', 'running', 1 );
      $attr{$name}{$attrName} = 0;
      UnifiProtect_Connect($hash);

    }

  } elsif( $attrName eq 'sshUser' ) {
    if( $cmd eq "set" && $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
    } else {
      delete $attr{$name}{$attrName};
      UnifiProtect_killLogWatcher($hash);
    }

    UnifiProtect_Connect($hash);

  } elsif( $attrName eq 'user'
           || $attrName eq 'password' ) {
    if( $cmd eq "set" && $attrVal ) {

      return if( $attrVal =~ m/^crypt:/ );

      $attrVal = UnifiProtect_encrypt($attrVal);

      if( $orig ne $attrVal ) {
        $attr{$name}{$attrName} = $attrVal;

        UnifiProtect_Connect($hash);

        return "stored obfuscated $attrName";
      }
    }
  }


  if( $cmd eq 'set' ) {

  } else {
    delete $attr{$name}{$attrName};
  }

  return;
}


1;

=pod
=item summary    Module to integrate FHEM with UnifiProtect
=item summary_DE Modul zur Integration von FHEM mit UnifiProtect
=begin html

<a name="UnifiProtect"></a>
<h3>UnifiProtect</h3>
<ul>
  Module to integrate UnifiProtect devices with FHEM.<br><br>

  define &lt;name&gt; UnifiProtect &lt;ip&gt; &lt;user&gt; &lt;password&gt; <br><br>

  Notes:
  <ul>
    <li>JSON has to be installed on the FHEM host.</li>
    <li>create protect read only user: users-&gt;invite users-&gt;local access only</li>
    <li><code>define &lt;name&gt; webLink htmlCode {UnifiProtect_2html('&lt;nvr&gt;','&lt;cam&gt;[,&lt;cam2&gt;,..]'[,&lt;width&gt;])}</code></li>
  </ul><br>

  <a name="UnifiProtect_Set"></a>
  <b>Set</b>
  <ul>
    <li>snapshot cam=&lt;cam&gt; width=&lt;width&gt; fileName=&lt;fileName&gt;<br>
      takes a snapshot from &lt;cam&gt; with optional &lt;width&gt; and stores it with the optional &lt;fileName&gt;<br>
      &lt;cam&gt; can be the number of the camera, its id or a regex that is matched against the name.
      </li>
    <li>reconnect<br>
      </li>
  </ul>

  <a name="UnifiProtect_Get"></a>
  <b>Get</b>
  <ul>
    <li>user<br>
      shows the configured user.</li>
    <li>password<br>
      shows the configured password.</li>
  </ul>

  <a name="UnifiProtect_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>filePath<br>
      path to store the snapshot images to. default: .../www/snapshots
      </li>
    <li>user<br>
      user to use for nvr access </li>
    <li>password<br>
      password to use for nvr access </li>
  </ul>
</ul><br>

=end html
=cut
