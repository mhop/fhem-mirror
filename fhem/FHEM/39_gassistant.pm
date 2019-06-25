
# $Id: 39_gassistant.pm 18283 2019-01-16 16:58:23Z justme1968 $

package main;

use strict;
use warnings;

use CoProcess;

use JSON;
use Data::Dumper;

use POSIX;
use Socket;

use vars qw(%modules);
use vars qw(%defs);
use vars qw(%attr);
use vars qw($readingFnAttributes);
use vars qw($FW_ME);

sub Log($$);
sub Log3($$$);

sub
gassistant_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}   = "gassistant_Read";

  $hash->{DefFn}    = "gassistant_Define";
  $hash->{NotifyFn} = "gassistant_Notify";
  $hash->{UndefFn}  = "gassistant_Undefine";
  $hash->{DelayedShutdownFn} = "gassistant_DelayedShutdownFn";
  $hash->{ShutdownFn} = "gassistant_Shutdown";
  $hash->{SetFn}    = "gassistant_Set";
  $hash->{GetFn}    = "gassistant_Get";
  $hash->{AttrFn}   = "gassistant_Attr";
  $hash->{AttrList} = "articles prepositions ".
                      "gassistantFHEM-cmd ".
                      "gassistantFHEM-config ".
                      "gassistantFHEM-home ".
                      "gassistantFHEM-log ".
                      "gassistantFHEM-params ".
                      "gassistantFHEM-auth ".
                      #"gassistantFHEM-filter ".
                      #"gassistantFHEM-sshHost gassistantFHEM-sshUser ".
                      "nrarchive ".
                      "disable:1 disabledForIntervals ".
                      $readingFnAttributes;

  $hash->{FW_detailFn} = "gassistant_detailFn";
  $hash->{FW_deviceOverview} = 1;
}

#####################################

sub
gassistant_AttrDefaults($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

}

sub
gassistant_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> gassistant"  if(@a != 2);

  my $name = $a[0];
  $hash->{NAME} = $name;


  my $d = $modules{$hash->{TYPE}}{defptr};
  return "$hash->{TYPE} device already defined as $d->{NAME}." if( defined($d) && $name ne $d->{NAME} );
  $modules{$hash->{TYPE}}{defptr} = $hash;

  gassistant_AttrDefaults($hash);

  $hash->{NOTIFYDEV} = "global,global:npmjs.*gassistant-fhem.*";

  if( $attr{global}{logdir} ) {
    CommandAttr(undef, "$name gassistantFHEM-log %L/gassistant-%Y-%m-%d.log") if( !AttrVal($name, 'gassistantFHEM-log', undef ) );
  } else {
    CommandAttr(undef, "$name gassistantFHEM-log ./log/gassistant-%Y-%m-%d.log") if( !AttrVal($name, 'gassistantFHEM-log', undef ) );
  }

  #CommandAttr(undef, "$name gassistantFHEM-filter room=GoogleAssistant") if( !AttrVal($name, 'gassistantFHEM-filter', undef ) );

  if( !AttrVal($name, 'devStateIcon', undef ) ) {
    CommandAttr(undef, "$name stateFormat gassistant-fhem");
    CommandAttr(undef, "$name devStateIcon stopped:control_home\@red:start stopping:control_on_off\@orange running.*:control_on_off\@green:stop")
  }

  if( 0 && !AttrVal($name, 'room', undef ) ) {
    $attr{$hash->{NAME}}{room} = "GoogleAssistant";
    #create dummy on/off device
    CommandDefine(undef, "GoogleAssistant_dummy dummy");
    CommandAttr(undef, "GoogleAssistant_dummy alias Testlight");
    CommandAttr(undef, "GoogleAssistant_dummy genericDeviceType light");
    CommandAttr(undef, "GoogleAssistant_dummy setList on off");
    CommandAttr(undef, "GoogleAssistant_dummy room GoogleAssistant");
  }

  $hash->{CoProcess} = {  name => 'gassistant-fhem',
                         cmdFn => 'gassistant_getCMD',
                       };

  if( $init_done ) {
    setKeyValue('gassistantFHEM.loginURL', '' );
    readingsSingleUpdate($hash, 'gassistantFHEM.loginURL', 'Waiting for login url from gassistant-fhem', 1 );
    CoProcess::start($hash);
  } else {
    $hash->{STATE} = 'active';
  }

  return undef;
}

sub
gassistant_Notify($$)
{
  my ($hash,$dev) = @_;
   
  return if($dev->{NAME} ne "global");
   
  if( grep(m/^npmjs:BEGIN.*gassistant-fhem.*/, @{$dev->{CHANGED}}) ) {
    CoProcess::stop($hash);
    return undef;
   
  } elsif( grep(m/^npmjs:FINISH.*gassistant-fhem.*/, @{$dev->{CHANGED}}) ) {
    CoProcess::start($hash);
    return undef;
   
  } elsif( grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}) ) {
    CoProcess::start($hash);
    return undef;
  }
   
  return undef;
}

sub
gassistant_Undefine($$)
{
  my ($hash, $name) = @_;

  if( $hash->{PID} ) {
    $hash->{undefine} = 1;
    $hash->{undefine} = $hash->{CL} if( $hash->{CL} );

    $hash->{reason} = 'delete';
    CoProcess::stop($hash);

    return "$name will be deleted after gassistant-fhem has stopped or after 5 seconds. whatever comes first.";
  }

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}
sub
gassistant_DelayedShutdownFn($)
{
  my ($hash) = @_;

  if( $hash->{PID} ) {
    $hash->{shutdown} = 1;
    $hash->{shutdown} = $hash->{CL} if( $hash->{CL} );

    $hash->{reason} = 'shutdown';
    CoProcess::stop($hash);

    return 1;
  }

  return undef;
}
sub
gassistant_Shutdown($)
{
  my ($hash) = @_;

  CoProcess::terminate($hash);

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}

sub
gassistant_detailFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};
  my $name = $hash->{NAME};

  my $ret;

  my $logfile = AttrVal($name, 'gassistantFHEM-log', 'FHEM' );
  if( $logfile && $logfile ne 'FHEM' ) {
    my $name = 'gassistantFHEMlog';
    $ret .= "<a href=\"$FW_ME?detail=$name\">". AttrVal($name, "alias", "Logfile") ."</a><br>";
  }

  #  $ret .= "<a href=\"$url\">Login</a><br>";
  #}

  return $ret;
}

sub
gassistant_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf = CoProcess::readFn($hash);
  return undef if( !$buf );

  if( $buf =~ m/^\*\*\* ([^\s]+) (.+)/ ) {
    my $service = $1;
    my $message = $2;

    if( $service eq 'FHEM:' ) {
      if( $message =~ m/^connection failed(: (.*))?/ ) {
        my $reason = $2;

        $hash->{reason} = 'failed to connect to fhem';
        $hash->{reason} .= ": $reason" if( $reason );
        CoProcess::stop($hash);
      }
    }
  }

  return undef;
}

sub
gassistant_getLocalIP()
{
  my $socket = IO::Socket::INET->new(
        Proto       => 'udp',
        PeerAddr    => '8.8.8.8:53',    # google dns
        #PeerAddr    => '198.41.0.4:53', # a.root-servers.net
    );
  return '<unknown>' if( !$socket );

  my $ip = $socket->sockhost;
  close( $socket );

  return $ip if( $ip );

  #$ip = inet_ntoa( scalar gethostbyname( hostname() || 'localhost' ) );
  #return $ip if( $ip );

  return '<unknown>';
}
sub
gassistant_configDefault($;$)
{
  my ($hash,$force) = @_;
  my $name = $hash->{NAME};

  my $json;
  my $fh;

  my $configfile = $attr{global}{configfile};
  $configfile = substr( $configfile, 0, rindex($configfile,'/')+1 );
  $configfile .= 'gassistant-fhem.cfg';

  local *gassistant_readAndBackup = sub() {
    if( -e $configfile ) {
      my $json;
      if( open( my $fh, "<$configfile") ) {
        Log3 $name, 3, "$name: found old config at $configfile";

        local $/;
        $json = <$fh>;
        close( $fh );
      } else {
        Log3 $name, 2, "$name: can't read $configfile";
      }

      if( rename( $configfile, $configfile.".previous" ) ) {
        Log3 $name, 4, "$name: renamed $configfile to $configfile.previous";
      } else {
        Log3 $name, 2, "$name: could not rename $configfile to $configfile.previous :$!";
      }

      return $json;
    }
  };

  $json = gassistant_readAndBackup();
  if( !open( $fh, ">$configfile") ) {
    Log3 $name, 2, "$name: can't write $configfile";

    $configfile = $attr{global}{statefile};
    $configfile = substr( $configfile, 0, rindex($configfile,'/')+1 );
    $configfile .= 'gassistant-fhem.cfg';

    $json = gassistant_readAndBackup();
    if( !open( $fh, ">$configfile") ) {
      Log3 $name, 2, "$name: can't write $configfile";
      $configfile = '/tmp/gassistant-fhem.cfg';

      $json = gassistant_readAndBackup();
      if( !open( $fh, ">$configfile") ) {
        Log3 $name, 2, "$name: can't write $configfile";

        return "";
      }
    }
  }

  if( $fh ) {
    my $ip = '127.0.0.1';
    if( AttrVal($name, 'gassistantFHEM-sshHost', undef ) ) {
      $ip = gassistant_getLocalIP();
    }

    my $conf;
    $conf = eval { decode_json($json) } if( $json && !$force );

    if( !$conf->{gassistant} ) {
      $conf->{gassistant} = { description => 'FHEM Connect',
                          };
    }

    $conf->{connections} = [{}] if( !$conf->{connections} );
    $conf->{connections}[0]->{name} = 'FHEM' if( !$conf->{connections}[0]->{name} );
    $conf->{connections}[0]->{server} = $ip if( !$conf->{connections}[0]->{server} );
    $conf->{connections}[0]->{filter} = 'room=GoogleAssistant' if( !$conf->{connections}[0]->{filter} );
    $conf->{connections}[0]->{uid} = $< if( $conf->{sshproxy} );

    my $web = $defs{WEB};
    if( !$web ) {
      if( my @names = devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') ) {
        $web = $defs{$names[0]} if( defined($defs{$names[0]}) );

        Log3 $name, 4, "$name: using $names[0] as FHEMWEB device." if( $web );
      }
    } else {
      Log3 $name, 4, "$name: using WEB as FHEMWEB device." if( $web );
    }

    if( $web ) {
      $conf->{connections}[0]->{port} = $web->{PORT} if( !$conf->{connections}[0]->{port} );
      $conf->{connections}[0]->{webname} = AttrVal( 'WEB', 'webname', 'fhem' ) if( !$conf->{connections}[0]->{webname} );
    } else {
      Log3 $name, 2, "$name: no FHEMWEB device found. please adjust config file manualy.";
    }

    $json = JSON->new->pretty->utf8->encode($conf);
    print $fh $json;
    close( $fh );

    if( index($configfile,'/') == 0 ) {
      system( "ln -sf $configfile $attr{global}{modpath}/FHEM/gassistant-fhem.cfg" );
    } else {
      system( "ln -sf `pwd`/$configfile $attr{global}{modpath}/FHEM/gassistant-fhem.cfg" );
    }
  }

  $configfile = "./$configfile" if( index($configfile,'/') == -1 );

  Log3 $name, 2, "$name: created default configfile: $configfile";

  CommandAttr(undef, "$name gassistantFHEM-config $configfile") if( !AttrVal($name, 'gassistantFHEM-config', undef ) );
  CommandAttr(undef, "$name nrarchive 10") if( !AttrVal($name, 'nrarchive', undef ) );

  CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

  return $configfile;
}

sub
gassistant_getCMD($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !$init_done );

  my $url = ReadingsVal($name, 'gassistantFHEM.loginURL', undef);
  if( !$url ) {
    my $url = getKeyValue('gassistantFHEM.loginURL');
    readingsSingleUpdate($hash, 'gassistantFHEM.loginURL', $url, 1 ) if( $url );
  }
  my $token = ReadingsVal($name, 'gassistantFHEM.refreshToken', undef);
  if( !$token ) {
    my $token = getKeyValue('gassistantFHEM.refreshToken');
    readingsSingleUpdate($hash, 'gassistantFHEM.refreshToken', $token, 1 ) if( $token );
  } elsif( $token !~ m/^crypt:/ ) {
    fhem( "set $name refreshToken $token" );
  }


  if( !AttrVal($name, 'gassistantFHEM-config', undef ) ) {
    gassistant_configDefault($hash);
  }

  return undef if( IsDisabled($name) );
  #return undef if( ReadingsVal($name, 'gassistant-fhem', 'unknown') =~ m/^running/ );


  my $ssh_cmd;
  if( my $host = AttrVal($name, 'gassistantFHEM-sshHost', undef ) ) {
    my $ssh = qx( which ssh ); chomp( $ssh );
    if( my $user = AttrVal($name, 'gassistantFHEM-sshUser', undef ) ) {
      $ssh_cmd = "$ssh $user \@$host";
    } else {
      $ssh_cmd = "$ssh $host";
    }

    Log3 $name, 3, "$name: using ssh cmd $ssh_cmd";
  }

  my $cmd;
  if( $ssh_cmd ) {
    $cmd = AttrVal( $name, "gassistantFHEM-cmd", qx( $ssh_cmd which gassistant-fhem ) );
  } else {
    $cmd = AttrVal( $name, "gassistantFHEM-cmd", qx( which gassistant-fhem ) );
  }
  chomp( $cmd );

  if( !$ssh_cmd && !(-X $cmd) ) {
    my $msg = "gassistant-fhem not installed. install with 'sudo npm install -g gassistant-fhem --unsafe-perm'.";
    $msg = "$cmd does not exist" if( $cmd );
    return (undef, $msg);
  }

  $cmd = "$ssh_cmd $cmd" if( $ssh_cmd );

  if( my $home = AttrVal($name, 'gassistantFHEM-home', undef ) ) {
    $home = $ENV{'PWD'} if( $home eq 'PWD' );
    $ENV{'HOME'} = $home;
    Log3 $name, 2, "$name: setting \$HOME to $home";
  }
  if( my $config = AttrVal($name, 'gassistantFHEM-config', undef ) ) {
    if( $ssh_cmd ) {
      qx( $ssh_cmd "cat > /tmp/gassistant-fhem.cfg" < $config );
      $cmd .= " -c /tmp/gassistant-fhem.cfg";
    } else {
      $cmd .= " -c $config";
    }
  }
  if( my $auth = AttrVal($name, 'gassistantFHEM-auth', undef ) ) {
    $auth = gassistant_decrypt( $auth );
    $cmd .= " -a $auth";
  }
  if( my $ssl = AttrVal('WEB', "HTTPS", undef ) ) {
    $cmd .= " -s";
  }
  if( my $params = AttrVal($name, 'gassistantFHEM-params', undef ) ) {
    $cmd .= " $params";
  }

  if( AttrVal( $name, 'verbose', 3 ) == 5 ) {
    Log3 $name, 2, "$name: starting gassistant-fhem: $cmd";
  } else {
    my $msg = $cmd;
    $msg =~ s/-a\s+[^:]+:[^\s]+/-a xx:xx/g;
    Log3 $name, 2, "$name: starting gassistant-fhem: $msg";
  }

  return $cmd;

}

sub
gassistant_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "authcode refreshToken createDefaultConfig:noArg clearCredentials:noArg unregister:noArg reload:noArg";

  if( $cmd eq 'reload' ) {
    $hash->{".triggerUsed"} = 1;
    if( @args ) {
      FW_directNotify($name, "reload $args[0]");
    } else {
      FW_directNotify($name, 'reload');
    }
    DoTrigger( $name, "reload" );

    return undef;

  } elsif( $cmd eq 'createDefaultConfig' ) {
    my $force = 0;
    $force = 1 if( $args[0] && $args[0] eq 'force' );
    my $config = gassistant_configDefault($hash, $force);

    return "created default config: $config";

  } elsif( $cmd eq 'loginURL' ) {
    return "usage: set $name $cmd <url>" if( !@args );
    my $url = $args[0];
 
    $url = "<html><a href=\"$url\" target=\"_blank\">Click here to login (new window/tab)</a><br></html>";
    
    $hash->{".triggerUsed"} = 1;

    setKeyValue('gassistantFHEM.loginURL', $url );
    readingsSingleUpdate($hash, 'gassistantFHEM.loginURL', $url, 1 );

    CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

    return undef;

  } elsif( $cmd eq 'authcode' ) {
    return "usage: set $name $cmd <authcode>" if( !@args );
    my $authcode = $args[0];

    $hash->{".triggerUsed"} = 1;

    DoTrigger( $name, "authcode: $authcode" );

    return undef;

  } elsif( $cmd eq 'refreshToken' ) {
    return "usage: set $name $cmd <key>" if( !@args );
    my $token = $args[0];

    $hash->{".triggerUsed"} = 1;

    $token = gassistant_encrypt($token);
    setKeyValue('gassistantFHEM.refreshToken', $token );
    readingsSingleUpdate($hash, 'gassistantFHEM.refreshToken', $token, 1 );

    CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

    return undef;

  } elsif( $cmd eq 'clearCredentials' ) {
    setKeyValue('gassistantFHEM.loginURL', undef );
    setKeyValue('gassistantFHEM.refreshToken', undef );

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'gassistantFHEM.loginURL', '', 1 );
    readingsBulkUpdate($hash, 'gassistantFHEM.refreshToken', '', 1 );
    readingsEndUpdate($hash,1);

    CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

    FW_directNotify($name, 'clearCredentials');

    return undef;

  } elsif( $cmd eq 'unregister' ) {
    FW_directNotify($name, 'unregister');
    DoTrigger( $name, "unregister" );

    fhem( "set $name clearCredentials" );

    CommandAttr( undef, '$name disable 1' );

    CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

    return undef;
  } elsif( $cmd eq 'start' || $cmd eq 'stop' || $cmd eq 'restart' ) {
    setKeyValue('gassistantFHEM.loginURL', '' );
    readingsSingleUpdate($hash, 'gassistantFHEM.loginURL', 'Waiting for login url from gassistant-fhem', 1 );
  }

  return CoProcess::setCommands($hash, $list, $cmd, @args);

  return "Unknown argument $cmd, choose one of $list";
}



sub
gassistant_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "loginURL refreshToken";

  if( $cmd eq 'loginURL' ) {
    my $url = ReadingsVal($name, 'gassistantFHEM.loginURL', undef);

    return $url;

  } elsif( $cmd eq 'refreshToken' ) {
    my $token = ReadingsVal($name, 'gassistantFHEM.refreshToken', undef);

    return gassistant_decrypt($token);


  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
gassistant_Parse($$;$)
{
  my ($hash,$data,$peerhost) = @_;
  my $name = $hash->{NAME};
}

sub
gassistant_encrypt($)
{
  my ($decoded) = @_;
  my $key = getUniqueId();

  return "" if( !$decoded );
  return $decoded if( $decoded =~ /^crypt:(.*)/ );

  my $encoded;
  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'. $encoded;
}
sub
gassistant_decrypt($)
{
  my ($encoded) = @_;
  my $key = getUniqueId();

  return "" if( !$encoded );

  $encoded = $1 if( $encoded =~ /^crypt:(.*)/ );

  my $decoded;
  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
}

sub
gassistant_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  my $hash = $defs{$name};
  if( $attrName eq 'disable' ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" && $attrVal ne "0" ) {
      $attrVal = 1;
      CoProcess::stop($hash);

    } else {
      $attr{$name}{$attrName} = 0;
      CoProcess::start($hash);

    }

  } elsif( $attrName eq 'disabledForIntervals' ) {
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  } elsif( $attrName eq 'gassistantFHEM-log' ) {
    if( $cmd eq "set" && $attrVal && $attrVal ne 'FHEM' ) {
      fhem( "defmod -temporary gassistantFHEMlog FileLog $attrVal fakelog" );
      CommandAttr( undef, 'gassistantFHEMlog room hidden' );
      #if( my $room = AttrVal($name, "room", undef ) ) {
      #  CommandAttr( undef,"gassistantFHEMlog room $room" );
      #}
      $hash->{logfile} = $attrVal;
    } else {
      fhem( "delete gassistantFHEMlog" );
    }

    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  } elsif( $attrName eq 'gassistantFHEM-auth' ) {
    if( $cmd eq "set" && $attrVal ) {
      $attrVal = gassistant_encrypt($attrVal);
    }
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

    if( $cmd eq "set" && $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return "stored obfuscated auth data";
    }

  } elsif( $attrName eq 'gassistantFHEM-params' ) {
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  } elsif( $attrName eq 'gassistantFHEM-sshHost' ) {
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  } elsif( $attrName eq 'gassistantFHEM-sshUser' ) {
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  }


  if( $cmd eq 'set' ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return "stored modified value";
    }

  } else {
    delete $attr{$name}{$attrName};

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday(), "gassistant_AttrDefaults", $hash, 0);
  }

  return;
}


1;

=pod
=item summary    Module to control the FHEM/Google Assistant integration
=item summary_DE Modul zur Konfiguration der FHEM/Google Assistant Integration
=begin html

<a name="gassistant"></a>
<h3>gassistant</h3>
<ul>
  Module to control the integration of Google Assistant devices with FHEM.<br><br>

  Notes:
  <ul>
    <li>HOWTO for public FHEM Connect action: <a href='https://wiki.fhem.de/wiki/Google_Assistant_FHEM_Connect'>Google Assistant FHEM Connect</a></li>
  </ul>

  <a name="gassistant_Set"></a>
  <b>Set</b>
  <ul>
    <li>reload<br>
      Reloads the devices and sends them to Google.
      </li>

    <li>createDefaultConfig<br>
    creates a default gassistant-fhem.cfg file
    gassistantFHEM-config attribut if not already set.</li>

    <li>clearCredentials<br>
    clears all stored credentials</li>
    
    <li>unregister<br>
    unregister and delete all data in FHEM Connect</li>
    <br>
  </ul>

  <a name="gassistant_Get"></a>
  <b>Get</b>
  <ul>
  </ul>

  <a name="gassistant_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>gassistantFHEM-auth<br>
      the user:password combination to use to connect to fhem.</li>
    <li>gassistantFHEM-cmd<br>
      The command to use as gassistant-fhem.</li>
    <li>gassistantFHEM-config<br>
      The config file to use for gassistant-fhem.</li>
    <li>gassistantFHEM-log<br>
      The log file to use for gassistant-fhem. For possible %-wildcards see <a href="#FileLog">FileLog</a>.</li>.
    <li>nrarchive<br>
      see <a href="#FileLog">FileLog</a></li>.
    <li>gassistantFHEM-params<br>
      Additional gassistant-fhem cmdline params.</li>

    <li>gassistantName<br>
      The name to use for a device with gassistant.</li>
    <li>realRoom<br>
      The room name to use for a device with gassistant.</li>
  </ul>
</ul><br>

=end html
=cut
