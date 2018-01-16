
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
UnifiVideo_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}   = "UnifiVideo_Read";

  $hash->{DefFn}    = "UnifiVideo_Define";
  $hash->{NotifyFn} = "UnifiVideo_Notify";
  $hash->{UndefFn}  = "UnifiVideo_Undefine";
  $hash->{SetFn}    = "UnifiVideo_Set";
  $hash->{GetFn}    = "UnifiVideo_Get";
  $hash->{AttrFn}   = "UnifiVideo_Attr";
  $hash->{AttrList} = "filePath apiKey ".
                      "sshUser ".
                      $readingFnAttributes;

  $hash->{FW_detailFn}  = "UnifiVideo_detailFn";
}

#####################################


sub
UnifiVideo_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> UnifiVideo <ip> [<apiKey>]"  if(@a < 3);

  my $name = $a[0];
  my $host = $a[2];
  $hash->{NAME} = $name;

  my $d = $modules{$hash->{TYPE}}{defptr};
  return "$hash->{TYPE} device already defined as $d->{NAME}." if( defined($d) && $name ne $d->{NAME} );
  $modules{$hash->{TYPE}}{defptr} = $hash;

  $hash->{NOTIFYDEV} = "global";

  $hash->{HOST} = $host;
  $hash->{DEF} = $host;

  $hash->{STATE} = 'active';

  CommandAttr(undef,"$name apiKey $a[3]" ) if( defined($a[3]) );

  if( $init_done ) {
    UnifiVideo_Connect($hash);
  }

  return undef;
}

sub
UnifiVideo_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  UnifiVideo_Connect($hash);

  return undef;
}

sub
UnifiVideo_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash, "UnifiVideo_Connect");

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}

sub
UnifiVideo_detailFn()
{
  my ($FW_wname, $d, $room, $extPage) = @_; # extPage is set for summaryFn.
  my $hash = $defs{$d};

  return UnifiVideo_2html($hash);
}

sub
UnifiVideo_2html($;$$)
{
  my ($hash,$cams,$width) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );
  return undef if( !defined($hash) );
  $width = 200 if( !$width );
  my $name = $hash->{NAME};

  my @cams = split(',', $cams) if( defined($cams) );

  my $apiKey = AttrVal($name, 'apiKey', undef);
  return undef if( !$apiKey );
  $apiKey = UnifiVideo_decrypt( $apiKey );

  my $json = $hash->{helper}{json};
  return undef if( !$json );

  my $javascriptText = "<script type='text/javascript'>
    function loadImages() {
      var tags = document.getElementsByClassName('unifiSnap');
      for(var i = 0;i < tags.length; i++) {
          var img = tags[i];
        var nvrIp = img.getAttribute('nvrIp');
        var cameraId = img.getAttribute('cameraId');
        var apiKey = img.getAttribute('apiKey');
        var width = img.width;
        tags[i].src='http://'+ nvrIp +':7080/api/2.0/snapshot/camera/'+cameraId+'?force=true&width='+width+'&apiKey='+apiKey+'&'+Date.now();
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
  foreach my $entry (@{$json->{data}}) {
    next if( $entry->{deleted} );
    next if( $entry->{state} eq 'DISCONNECTED' );
    if( defined($cams) ) {
      foreach my $cam (@cams) {
        if( ( $cam =~ m/[0-9]+/ && int($cam) == $i )
            || $entry->{_id} eq $cam
            || $entry->{name} =~ m/$cam/ ) {
          $html .= "\n" if( $html );
          $html .= "  <img width='$width' class='unifiSnap' nvrIp='$hash->{HOST}' apiKey='$apiKey' cameraId='$entry->{_id}'>";
        }
      }
    } else {
      $html .= "\n" if( $html );
      $html .= "  <img width='200' class='unifiSnap' nvrIp='$hash->{HOST}' apiKey='$apiKey' cameraId='$entry->{_id}'>";
    }

    ++$i;
  }
  $html .= "\n" if( $html );
  $html .= "</div>";

#Log 1, $html;
  return $html;
}

sub
UnifiVideo_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "reconnect:noArg snapshot apiKey";

  if( $cmd eq 'reconnect' ) {
    $hash->{".triggerUsed"} = 1;

    UnifiVideo_Connect($hash);

    return undef;

  } elsif( $cmd eq 'snapshot' ) {
    my $json = $hash->{helper}{json};
    return "not jet connected" if( !$json );

    my ($param_a, $param_h) = parseParams(\@args);
    my $cam = $param_h->{cam};
    my $width = $param_h->{width};
    return "usage: snapshot cam=<cam> [width=<width>] [fileName=<fileName>]" if( !defined($cam) );
    my $i = 0;
    foreach my $entry (@{$json->{data}}) {
      next if( $entry->{deleted} );
      next if( $entry->{state} eq 'DISCONNECTED' );
      if( ( $cam =~ m/[0-9]+/ && int($cam) == $i )
          || $entry->{_id} eq $cam
          || $entry->{name} =~ m/$cam/ ) {
        $cam = $entry->{_id};
        #Log 1, "$i $entry->{name}: $entry->{_id}";
        last;
      }
      ++$i;
    }

    return "no such cam: $cam" if( $i >= $json->{meta}{totalCount} );

    my $apiKey = AttrVal($name, 'apiKey', undef);
    $apiKey = UnifiVideo_decrypt( $apiKey );

    my $url = "http://$hash->{HOST}:7080/api/2.0/snapshot/camera/$cam?force=true&apiKey=$apiKey";
    $url .= "&width=$width" if( $width );
    my $param = {
      url => $url,
      method => 'GET',
      timeout => 5,
      noshutdown => 0,
      hash => $hash,
      key => 'snapshot',
      cam => $cam,
      fileName => $param_h->{fileName} ,
      index => $i,
    };

    Log3 $name, 4, "$name: fetching data from $url";

    $param->{callback} = \&UnifiVideo_parseHttpAnswer;
    HttpUtils_NonblockingGet( $param );

    return undef;

  } elsif( $cmd eq 'apiKey' ) {

    return CommandAttr(undef,"$name apiKey $args[0]" );
  }

  return "Unknown argument $cmd, choose one of $list";
}


sub
UnifiVideo_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "apiKey:noArg";

  if( $cmd eq 'apiKey' ) {
    my $apiKey = AttrVal($name, 'apiKey', undef);
    return 'no apiKey set' if( !$apiKey );

    $apiKey = UnifiVideo_decrypt( $apiKey );

    return "apiKey: $apiKey";
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
UnifiVideo_Parse($$;$)
{
  my ($hash,$data,$peerhost) = @_;
  my $name = $hash->{NAME};
}
sub
UnifiVideo_parseHttpAnswer($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if( $err ) {
    Log3 $name, 2, "$name: http request ($param->{url}) failed: $err";

    return undef;
  }

  return undef if( !$data );

  Log3 $name, 5, "$name: received $data";
  if( $param->{key} eq 'json' ) {
    my $json = eval { decode_json($data) };
    Log3 $name, 2, "$name: json error: $@ in $json" if( $@ );

    #Log 1, Dumper $json;
    $hash->{helper}{json} = $json;

    if( !defined( $json->{meta} ) ) {
      Log3 $name, 2, "$name: received unknown data";
      return undef;
    }

    my $apiKey = AttrVal($name, 'apiKey', undef);
    $apiKey = UnifiVideo_decrypt( $apiKey );

    my $totalCount = $json->{meta}{totalCount};
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'totalCount', $totalCount, 1);
    my $i = 0;
    foreach my $entry (@{$json->{data}}) {
      if( !$entry->{deleted} ) {
      #Log 1, Dumper $entry->{_id};
        readingsBulkUpdateIfChanged($hash, "cam${i}name", $entry->{name}, 1);
        readingsBulkUpdateIfChanged($hash, "cam${i}id", $entry->{_id}, 1);
        readingsBulkUpdateIfChanged($hash, "cam${i}state", $entry->{state}, 1);
        #readingsBulkUpdateIfChanged($hash, "cam${i}snapshotURL", "http://$hash->{HOST}:7080/api/2.0/snapshot/camera/$entry->{_id}?force=true&apiKey=$apiKey" , 1);
      }
      ++$i;
    }
    readingsEndUpdate($hash,1);

    RemoveInternalTimer($hash, "UnifiVideo_Connect");
    InternalTimer(gettimeofday() + 900, "UnifiVideo_Connect", $hash) 

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

  } else {
    Log3 $name, 2, "parseHttpAnswer: unhandled key";

  }

  return undef;
}

sub
UnifiVideo_Read($)
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
    UnifiVideo_killLogWatcher($hash);
  }

  my $data = $hash->{PARTIAL};
  $data .= $buf;

  while($data =~ m/\n/) {
    my $line;
    ($line,$data) = split("\n", $data, 2);

    if( $line =~ m/password/ ) {
      UnifiVideo_killLogWatcher($hash);

    } elsif( $line =~ m/Camera\[([^\]]+)\].*type:([^\s]+)/ ) {
      my $cam = $1;
      my $type = $2;

      if( $type eq 'start' ) {
        my $json = $hash->{helper}{json};
        $json = [] if( !$json );
        my $i = 0;
        foreach my $entry (@{$json->{data}}) {
          next if( $entry->{deleted} );
          last if( $entry->{mac} eq $cam );
          ++$i;
          }
          if( $i >= $json->{meta}{totalCount} ) {
            Log3 $name, 2, "$name: got motion event for unknown cam: $cam";

          } else {
            readingsSingleUpdate($hash, "cam${i}motion", $type, 1);
          }

        } elsif( $type eq 'stop' ) {
        } else {
          Log3 $name, 2, "$name: got unknown event type from cam: $cam";
        }

    } else {
      Log3 $name, 2, "$name: got unknown event: $line";
    }
  }

  $hash->{PARTIAL} = $data

  #UnifiVideo_Parse($hash, $buf, $hash->{CD}->peerhost);
}

sub
UnifiVideo_killLogWatcher($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  close($hash->{FH}) if($hash->{FH});
  delete($hash->{FH});
  delete($hash->{FD});

  return if( !$hash->{PID} );

  kill( 9, $hash->{PID} );
  delete $hash->{PID};

  Log3 $name, 3, "$name: stopped logfile watcher";

  delete $hash->{PARTIAL};
  delete($selectlist{$name});
}
sub
UnifiVideo_startLogWatcher($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  UnifiVideo_killLogWatcher($hash);

  my $user = AttrVal($name, "sshUser", undef);
  return if( !$user );
  my $logfile = AttrVal($name, "logfile", "/var/log/unifi-video/motion.log" );
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

    Log3 $name, 3, "$name: started logfile watcher";
  } else {
    Log3 $name, 2, "$name: failed to start logfile watcher";

  }
}


sub
UnifiVideo_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $apiKey = AttrVal($name, 'apiKey', undef);
  if( !$apiKey ) {
    $hash->{STATE} = 'disconnected';
    Log3 $name, 2, "$name: can't connect without apiKey";
    return undef;
  }

  $apiKey = UnifiVideo_decrypt( $apiKey );

  my $url = "http://$hash->{HOST}:7080/api/2.0/camera?apiKey=$apiKey";
  my $param = {
    url => $url,
    method => 'GET',
    timeout => 5,
    noshutdown => 0,
    hash => $hash,
    key => 'json',
  };

  Log3 $name, 4, "$name: fetching data from $url";

  $param->{callback} = \&UnifiVideo_parseHttpAnswer;
  HttpUtils_NonblockingGet( $param );

  UnifiVideo_startLogWatcher( $hash );

  return undef;
}

sub
UnifiVideo_encrypt($)
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
UnifiVideo_decrypt($)
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
UnifiVideo_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  my $hash = $defs{$name};
  if( $attrName eq "disable" ) {
  } elsif( $attrName eq "sshUser" ) {
    if( $cmd eq "set" && $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
    } else {
      delete $attr{$name}{$attrName};
    }

    UnifiVideo_Connect($hash);

  } elsif( $attrName eq 'apiKey' ) {
    if( $cmd eq "set" && $attrVal ) {

      if( $attrVal =~ m/^crypt:/ ) {
        return;

      }

      $attrVal = UnifiVideo_encrypt($attrVal);

      if( $orig ne $attrVal ) {
        $attr{$name}{$attrName} = $attrVal;

        UnifiVideo_Connect($hash);

        return "stored obfuscated apiKey";
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
=item summary    Module to integrate FHEM with UnifiVideo
=item summary_DE Modul zur Integration von FHEM mit UnifiVideo
=begin html

<a name="UnifiVideo"></a>
<h3>UnifiVideo</h3>
<ul>
  Module to integrate UnifiVideo devices with FHEM.<br><br>

  define &lt;name&gt; UnifiVideo &lt;ip&gt; [&lt;apiKey&gt;] <br><br>

  Notes:
  <ul>
    <li>JSON has to be installed on the FHEM host.</li>
    <li>create nvr api key: admin-&gt;my account-&gt;api access</li>
    <li><code>define <name> webLink htmlCode {UnifiVideo_2html('&lt;nvr&gt;','&lt;cam&gt;[,&lt;cam2&gt;,..]'[,&lt;width&gt;])}</code></li>
  </ul><br>

  <a name="UnifiVideo_Set"></a>
  <b>Set</b>
  <ul>
    <li>snapshot cam=&lt;cam&gt; width=&lt;width&gt; fileName=&lt;fileName&gt;<br>
      takes a snapshot from &lt;cam&gt; with optional &lt;width&gt; and stores it with the optional &lt;fileName&gt;<br>
      &lt;cam&gt; can be the number of the cammera, its id or a regex that is matched against the name.
      </li>
    <li>reconnect<br>
      </li>
  </ul>

  <a name="UnifiVideo_Get"></a>
  <b>Get</b>
  <ul>
    <li>apiKey<br>
      shows the configured apiKey.</li>
  </ul>

  <a name="UnifiVideo_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>filePath<br>
      path to store the snapshot images to. default: .../www/snapshots
      </li>
    <li>apiKey<br>
      apiKey to use for nvr access
      </li>
    <li>ssh_user<br>
      ssh user for nvr logfile access. used to fhem events after motion detection.
      </li>
  </ul>
</ul><br>

=end html
=cut
