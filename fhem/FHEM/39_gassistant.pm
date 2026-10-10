
# $Id: 39_gassistant.pm 18283 2019-01-16 16:58:23Z justme1968 $

package main;

use strict;
use warnings;

use CoProcess;
use Blocking;

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
                      "gassistantFHEM-runtime:local,system ".
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

  # during FHEM start the attributes of fhem.cfg are not set yet, the default is set after INITIALIZED
  gassistant_defaultLog($hash) if( $init_done );

  #CommandAttr(undef, "$name gassistantFHEM-filter room=GoogleAssistant") if( !AttrVal($name, 'gassistantFHEM-filter', undef ) );

  if( !AttrVal($name, 'stateFormat', undef )) {
    CommandAttr(undef, "$name stateFormat gassistant-fhem-connection");
    CommandAttr(undef, "$name devStateIcon { my \$error = ReadingsVal(\$name,\"gassistant-fhem-lastServerError\",\"none\") eq \"none\"?\"10px-kreis-gruen\":\"10px-kreis-rot\";; my \$onoff = substr(ReadingsVal(\$name, \"gassistant-fhem\", \"running\"),0,7) eq \"running\"?\"control_on_off\\\@green\":\"control_on_off\\\@red\";; my \$reload = ReadingsVal(\$name, \"gassistant-fhem-connection\", \"connected\") eq \"connected\"?\"audio_repeat\\\@green\":\"audio_repeat\\\@orange\";;\"<div><a>\".FW_makeImage(\$error).\"<\/a> <a href=\\\"\/fhem?cmd.dummy=set \$name reload&XHR=1\\\">\".FW_makeImage(\$reload, \"reload\").\"<\/a><a href=\\\"\/fhem?cmd.dummy=set \$name restart&XHR=1\\\">&nbsp;&nbsp;\".FW_makeImage(\$onoff, \"restart\").\"<\/a><\/div>\"}");
    CommandAttr(undef, "$name icon gassistant");
  }

  if( !AttrVal($name, 'room', undef ) ) {
    $attr{$hash->{NAME}}{room} = "GoogleAssistant";
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
gassistant_defaultLog($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if( AttrVal($name, 'gassistantFHEM-log', undef ) );

  if( $attr{global}{logdir} ) {
    CommandAttr(undef, "$name gassistantFHEM-log %L/gassistant-%Y-%m-%d.log");
  } else {
    CommandAttr(undef, "$name gassistantFHEM-log ./log/gassistant-%Y-%m-%d.log");
  }
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
    gassistant_defaultLog($hash);
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

# Node.js major version of the local runtime
my $gassistant_nodeMajor = 22;

# gassistant-fhem is installed by this module with an own Node.js in
# <home>/.fhemconnect/runtime, independent of the system Node.js and without root.
sub
gassistant_managedRuntime($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return 0 if( $^O eq 'MSWin32' );
  return 0 if( AttrVal($name, 'gassistantFHEM-cmd', undef) );
  return 0 if( AttrVal($name, 'gassistantFHEM-sshHost', undef) );
  return AttrVal($name, 'gassistantFHEM-runtime', 'local') eq 'local';
}

sub
gassistant_runtimeDir($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $home = AttrVal($name, 'gassistantFHEM-home', undef);
  $home = $ENV{'PWD'} if( $home && $home eq 'PWD' );
  $home = $ENV{'HOME'} if( !$home );
  $home = '.' if( !$home );

  return "$home/.fhemconnect/runtime";
}

# command of the local installation, undef if not installed
sub
gassistant_localCmd($)
{
  my ($hash) = @_;

  my $node = gassistant_runtimeDir($hash) .'/node';
  my $bin = "$node/lib/node_modules/gassistant-fhem/bin/gassistant-fhem";

  # start with the own node, the #! line of bin/gassistant-fhem would use the system node
  return "$node/bin/node $bin" if( -X "$node/bin/node" && -f $bin );
  return undef;
}

# installs Node.js (if missing or outdated) and gassistant-fhem@<version> in the background
sub
gassistant_install($$)
{
  my ($hash, $version) = @_;
  my $name = $hash->{NAME};

  return "installation already running" if( $hash->{helper}{installPid} );

  delete $hash->{helper}{installFailed};
  my $dir = gassistant_runtimeDir($hash);
  readingsSingleUpdate($hash, 'gassistant-fhem-install', "installing gassistant-fhem\@$version...", 1 );
  Log3 $name, 3, "$name: installing gassistant-fhem\@$version in $dir, log: $dir/install.log";

  my $bc = BlockingCall( 'gassistant_installRun', "$name|$dir|$version", 'gassistant_installDone',
                         1800, 'gassistant_installAborted', $name );
  $hash->{helper}{installPid} = $bc->{pid} if( $bc );
  return undef;
}

# runs in a forked process
sub
gassistant_installRun($)
{
  my ($string) = @_;
  my ($name, $dir, $version) = split( /\|/, $string, 3 );

  # low CPU and IO priority, FHEM and the running gassistant-fhem should not be slowed down
  setpriority( 0, 0, 19 );
  system( "ionice -c2 -n7 -p $$ >/dev/null 2>&1" ) if( qx(command -v ionice 2>/dev/null) );

  my $result = eval { gassistant_installSteps($name, $dir, $version) };
  if( $@ ) {
    my $err = $@;
    $err =~ s/[\r\n|]+/ /g;
    $err =~ s/\s+at \S+ line \d+\.?\s*$//;
    return "$name|error|$err";
  }
  return "$name|ok|$result";
}

sub
gassistant_installSteps($$$)
{
  my ($name, $dir, $version) = @_;

  my $q = sub { my $s = shift; $s =~ s/'/'\\''/g; return "'$s'" };

  system( 'mkdir -p '. $q->("$dir/tmp") ) == 0 or die "can't create $dir\n";
  my $log = "$dir/install.log";
  open( my $fh, '>', $log ) or die "can't write $log: $!\n";
  close( $fh );
  my $progress = sub {
    my ($msg) = @_;
    open( my $l, '>>', $log ); print $l '# '. localtime() ." $msg\n"; close( $l );
    BlockingInformParent( 'gassistant_installProgress', [$name, $msg], 0 );
  };
  my $run = sub {
    my ($cmd, $err) = @_;
    open( my $l, '>>', $log ); print $l "\$ $cmd\n"; close( $l );
    system( "$cmd >> ". $q->($log) ." 2>&1" ) == 0 or die "$err, see $log\n";
  };

  my $get;
  if( qx(command -v curl 2>/dev/null) ) {
    $get = sub { my ($url, $file) = @_; $run->( 'curl -fsSL --retry 2 -o '. $q->($file) .' '. $q->($url), "download of $url failed" ) };
  } elsif( qx(command -v wget 2>/dev/null) ) {
    $get = sub { my ($url, $file) = @_; $run->( 'wget -q -O '. $q->($file) .' '. $q->($url), "download of $url failed" ) };
  } else {
    die "curl or wget is required\n";
  }

  # Node.js build for this system
  my $machine = qx(uname -m); chomp( $machine );
  my %arch = ( x86_64 => 'x64', amd64 => 'x64', aarch64 => 'arm64', arm64 => 'arm64', armv7l => 'armv7l', armv6l => 'armv6l' );
  die "unsupported architecture $machine\n" if( !$arch{$machine} );
  die "unsupported OS $^O\n" if( $^O ne 'linux' && $^O ne 'darwin' );
  my @musl = $^O eq 'linux' ? glob('/lib/ld-musl-*') : ();
  my $musl = @musl ? 1 : 0;
  my $dist = "$^O-$arch{$machine}". ($musl ? '-musl' : '');
  my %official = map { $_ => 1 } qw(linux-x64 linux-arm64 linux-armv7l linux-x64-musl darwin-x64 darwin-arm64);

  my $node = "$dir/node";
  my $current = -X "$node/bin/node" ? qx('$node/bin/node' --version 2>/dev/null) : '';
  chomp( $current );

  # latest Node.js of the major version
  $progress->( "checking Node.js $gassistant_nodeMajor..." );
  my ($latest, $url);
  eval {
    if( $official{$dist} ) {
      $get->( "https://nodejs.org/dist/latest-v$gassistant_nodeMajor.x/SHASUMS256.txt", "$dir/tmp/SHASUMS256.txt" );
      $url = "https://nodejs.org/dist";
    } else {
      # e.g. armv6l (Raspberry Pi Zero/1): unofficial builds
      $get->( 'https://unofficial-builds.nodejs.org/download/release/index.json', "$dir/tmp/index.json" );
      open( my $i, '<', "$dir/tmp/index.json" ) or die "index.json: $!\n";
      my $index = decode_json( join('', <$i>) );
      close( $i );
      my ($rel) = grep { $_->{version} =~ m/^v$gassistant_nodeMajor\./ && grep( { $_ eq $dist } @{$_->{files}} ) } @{$index};
      die "no Node.js $gassistant_nodeMajor for $dist\n" if( !$rel );
      $url = "https://unofficial-builds.nodejs.org/download/release";
      $get->( "$url/$rel->{version}/SHASUMS256.txt", "$dir/tmp/SHASUMS256.txt" );
    }
    open( my $s, '<', "$dir/tmp/SHASUMS256.txt" ) or die "SHASUMS256.txt: $!\n";
    while( my $line = <$s> ) {
      $latest = { version => $2, sha => $1 } if( $line =~ m/^([0-9a-f]{64})\s+node-(v[0-9.]+)-$dist\.tar\.gz$/ );
    }
    close( $s );
    die "no Node.js for $dist\n" if( !$latest );
  };
  my $err = $@;
  die $err if( $err && !$current ); # without Node.js nothing can be installed

  my $target = $node;
  if( $latest && $current ne $latest->{version} ) {
    my $file = "$dir/tmp/node-$latest->{version}-$dist.tar.gz";
    $progress->( "downloading Node.js $latest->{version}..." );
    $get->( "$url/$latest->{version}/node-$latest->{version}-$dist.tar.gz", $file );

    require Digest::SHA;
    my $sha = Digest::SHA->new(256)->addfile($file, 'b')->hexdigest;
    die "checksum of $file is wrong\n" if( $sha ne $latest->{sha} );

    $target = "$dir/node.new";
    $progress->( "extracting Node.js $latest->{version}..." );
    $run->( 'rm -rf '. $q->($target) .' '. $q->("$dir/tmp/x") .' && mkdir -p '. $q->("$dir/tmp/x") .
            ' && tar -xzf '. $q->($file) .' -C '. $q->("$dir/tmp/x") .
            ' && mv '. $q->("$dir/tmp/x/node-$latest->{version}-$dist") .' '. $q->($target), "extracting Node.js failed" );
  }

  # gassistant-fhem as global package of the own Node.js (also updates from FHEM work with it)
  local $ENV{'npm_config_update_notifier'} = 'false';
  local $ENV{'NODE_ENV'} = 'production';
  $progress->( "installing gassistant-fhem\@$version with npm (can take several minutes)..." );
  my $ok = eval {
    $run->( $q->("$target/bin/node") .' '. $q->("$target/lib/node_modules/npm/bin/npm-cli.js") .
            ' install -g --prefix '. $q->($target) .' '. $q->("gassistant-fhem\@$version") .
            ' --no-audit --no-fund --maxsockets=4', "npm install gassistant-fhem\@$version failed" );
    1;
  };
  if( !$ok ) {
    my $e = $@;
    system( 'rm -rf '. $q->("$dir/node.new") ) if( $target ne $node );
    die $e;
  }

  # switch to the new Node.js
  if( $target ne $node ) {
    $run->( 'rm -rf '. $q->("$dir/node.old") .
            ( -e $node ? ' && mv '. $q->($node) .' '. $q->("$dir/node.old") : '' ) .
            ' && mv '. $q->($target) .' '. $q->($node) .' && rm -rf '. $q->("$dir/node.old") .' '. $q->("$dir/tmp"),
            "switching to the new Node.js failed" );
  }

  my $nodeVersion = qx('$node/bin/node' --version 2>/dev/null); chomp( $nodeVersion );
  my $gaVersion = '';
  if( open( my $p, '<', "$node/lib/node_modules/gassistant-fhem/package.json" ) ) {
    my $pkg = eval { decode_json( join('', <$p>) ) };
    close( $p );
    $gaVersion = $pkg->{version} if( $pkg );
  }
  my $warn = $err ? " (Node.js update check failed: $err)" : '';
  $warn =~ s/[\r\n|]+/ /g;
  return "$nodeVersion|$gaVersion|$warn";
}

sub
gassistant_installProgress($$)
{
  my ($name, $msg) = @_;
  my $hash = $defs{$name};
  return if( !$hash );

  readingsSingleUpdate($hash, 'gassistant-fhem-install', $msg, 1 );
}

sub
gassistant_installDone($)
{
  my ($string) = @_;
  my ($name, $status, @r) = split( /\|/, $string );
  my $hash = $defs{$name};
  return if( !$hash );

  delete $hash->{helper}{installPid};

  if( $status ne 'ok' ) {
    $hash->{helper}{installFailed} = 1;
    readingsSingleUpdate($hash, 'gassistant-fhem-install', "failed: $r[0]", 1 );
    Log3 $name, 2, "$name: installation of gassistant-fhem failed: $r[0]";
    CoProcess::start($hash) if( !$hash->{PID} );
    return;
  }

  my ($node, $version, $warn) = @r;
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, 'gassistant-fhem-install', "installed $version, Node.js $node". ($warn // ''), 1 );
  readingsBulkUpdate($hash, 'gassistant-fhem-node', $node, 1 );
  readingsEndUpdate($hash, 1);
  Log3 $name, 3, "$name: installed gassistant-fhem $version with Node.js $node";

  # starts or restarts gassistant-fhem with the local installation
  CoProcess::start($hash);
}

sub
gassistant_installAborted($)
{
  my ($name) = @_;
  my $hash = $defs{$name};
  return if( !$hash );

  delete $hash->{helper}{installPid};
  $hash->{helper}{installFailed} = 1;
  readingsSingleUpdate($hash, 'gassistant-fhem-install', 'failed: timeout', 1 );
  Log3 $name, 2, "$name: installation of gassistant-fhem aborted (timeout)";
  CoProcess::start($hash) if( !$hash->{PID} );
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
  } elsif( gassistant_managedRuntime($hash) ) {
    $cmd = gassistant_localCmd($hash);
    if( !$cmd ) {
      # not installed yet (new or existing installation): install it in the background,
      # a global installation is used until the installation is finished
      gassistant_install($hash, 'latest') if( !$hash->{helper}{installFailed} );
      $cmd = qx( which gassistant-fhem );
      chomp( $cmd );
      if( !$cmd || !(-X $cmd) ) {
        return (undef, "installing gassistant-fhem, see reading gassistant-fhem-install") if( $hash->{helper}{installPid} );
        return (undef, "installation of gassistant-fhem failed, see ". gassistant_runtimeDir($hash) ."/install.log. retry with 'set $name update'.");
      }
      Log3 $name, 3, "$name: using $cmd until the installation in ". gassistant_runtimeDir($hash) ." is finished" if( $hash->{helper}{installPid} );
    }
  } else {
    $cmd = AttrVal( $name, "gassistantFHEM-cmd", qx( which gassistant-fhem ) );
  }
  chomp( $cmd );

  my ($exec) = split( ' ', $cmd, 2 );
  if( !$ssh_cmd && !($exec && -X $exec) ) {
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

  my $list = "authcode refreshToken createDefaultConfig:noArg clearCredentials:noArg unregister:noArg reload:noArg update";

  if( $cmd eq 'reload' ) {
    $hash->{".triggerUsed"} = 1;
    if( @args ) {
      FW_directNotify($name, "reload $args[0]");
    } else {
      FW_directNotify($name, 'reload');
    }
    DoTrigger( $name, "reload" );

    return undef;

  } elsif( $cmd eq 'update' ) {
    my $version = $args[0] // 'latest';
    return "usage: set $name $cmd [version]" if( $version !~ m/^[0-9A-Za-z][0-9A-Za-z.+-]*$/ );

    # local installation: installed by this module, gassistant-fhem is restarted afterwards
    return gassistant_install($hash, $version) if( gassistant_managedRuntime($hash) );

    # otherwise gassistant-fhem updates its global npm installation and restarts itself with 'set $name restart'
    $hash->{".triggerUsed"} = 1;
    DoTrigger( $name, "update: $version" );

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

    #create dummy on/off device
    if (!$main::defs{'GoogleAssistant_dummy'}) {
      CommandDefine(undef, "GoogleAssistant_dummy dummy");
      CommandAttr(undef, "GoogleAssistant_dummy alias Testlight");
      CommandAttr(undef, "GoogleAssistant_dummy genericDeviceType light");
      CommandAttr(undef, "GoogleAssistant_dummy setList on off");
      CommandAttr(undef, "GoogleAssistant_dummy room GoogleAssistant");
    }

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
    if ($cmd eq 'start') {
      readingsSingleUpdate($hash, 'gassistant-fhem-connection', 'starting...', 1 );
    }
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
      # defmod -temporary fails for an existing device ("Define -temporary first")
      if( $defs{gassistantFHEMlog} ) {
        fhem( "modify gassistantFHEMlog $attrVal fakelog" );
      } else {
        fhem( "define -temporary gassistantFHEMlog FileLog $attrVal fakelog" );
      }
      CommandAttr( undef, 'gassistantFHEMlog room hidden' );
      #if( my $room = AttrVal($name, "room", undef ) ) {
      #  CommandAttr( undef,"gassistantFHEMlog room $room" );
      #}
      $hash->{logfile} = $attrVal;
    } else {
      fhem( "delete gassistantFHEMlog" ) if( $defs{gassistantFHEMlog} );
      delete $hash->{logfile};
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

    <li>update [version]<br>
      Updates gassistant-fhem (default: latest version) and restarts it.<br>
      With gassistantFHEM-runtime local (default) gassistant-fhem and Node.js are installed by this module in
      &lt;home&gt;/.fhemconnect/runtime, the latest Node.js 22 is also updated.
      The progress is shown in the reading gassistant-fhem-install.<br>
      Otherwise the npm of the Node.js installation running gassistant-fhem is used (global installation),
      the progress is shown in the reading gassistant-fhem-update.</li>

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
    <li>gassistantFHEM-runtime local|system<br>
      local (default): this module installs gassistant-fhem with an own Node.js in &lt;home&gt;/.fhemconnect/runtime
      (no root rights needed, independent of the Node.js version of the system, needs curl or wget).
      An existing global installation is used until the local installation is finished.<br>
      system: use the global installation (which gassistant-fhem).<br>
      Not used with gassistantFHEM-cmd.</li>

    <li>gassistantName<br>
      The name to use for a device with gassistant.</li>
    <li>realRoom<br>
      The room name to use for a device with gassistant.</li>
  </ul>
</ul><br>

=end html
=cut
