
# $Id$

package main;

use strict;
use warnings;

use FHEM::Meta;

use CoProcess;
require "$attr{global}{modpath}/FHEM/30_HUEBridge.pm";

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
tradfri_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}   = "tradfri_Read";
  $hash->{WriteFn}  = "tradfri_Write";

  $hash->{DefFn}    = "tradfri_Define";
  $hash->{NotifyFn} = "tradfri_Notify";
  $hash->{UndefFn}  = "tradfri_Undefine";
  $hash->{DelayedShutdownFn} = "tradfri_DelayedShutdown";
  $hash->{ShutdownFn} = "tradfri_Shutdown";
  $hash->{SetFn}    = "tradfri_Set";
  $hash->{GetFn}    = "tradfri_Get";
  $hash->{AttrFn}   = "tradfri_Attr";
  $hash->{AttrList} = "tradfriFHEM-cmd ".
                      "tradfriFHEM-params ".
                      "tradfriFHEM-securityCode ".
                      "tradfriFHEM-sshHost tradfriFHEM-sshUser ".
                      "disable:1 disabledForIntervals ".
                      "createGroupReadings:1,0 ".
                      $readingFnAttributes;

  return FHEM::Meta::InitMod( __FILE__, $hash );
}

#####################################

sub
tradfri_AttrDefaults($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

}

sub
tradfri_Define($$)
{
  my ($hash, $def) = @_;

  return $@ unless ( FHEM::Meta::SetInternals($hash) );


  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> tradfri"  if(@a != 2);

  my $name = $a[0];
  $hash->{NAME} = $name;

  my $d = $modules{$hash->{TYPE}}{defptr};
  return "$hash->{TYPE} device already defined as $d->{NAME}." if( defined($d) && $name ne $d->{NAME} );
  $modules{$hash->{TYPE}}{defptr} = $hash;

  tradfri_AttrDefaults($hash);

  $hash->{NOTIFYDEV} = "global,global:npmjs.*tradfri-fhem.*";

  if( !AttrVal($name, 'devStateIcon', undef ) ) {
    CommandAttr(undef, "$name createGroupReadings 0");
    CommandAttr(undef, "$name stateFormat tradfri-fhem");
    CommandAttr(undef, "$name devStateIcon stopped:control_home\@red:start stopping:control_on_off\@orange running.*:control_on_off\@green:stop")
  }

  $hash->{CoProcess} = {   name => 'tradfri-fhem',
                          cmdFn => 'tradfri_getCmd',
                       };

  $hash->{helper}{scenes} = {} if( !$hash->{helper}{scenes} );

  if( $init_done ) {
     CoProcess::start($hash);
  } else {
    $hash->{STATE} = 'active';
  }

  return undef;
}

sub
tradfri_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");

  if( grep(m/^npmjs:BEGIN.*tradfri-fhem.*/, @{$dev->{CHANGED}}) ) {
    CoProcess::stop($hash);
    return undef;

  } elsif( grep(m/^npmjs:FINISH.*tradfri-fhem.*/, @{$dev->{CHANGED}}) ) {
    CoProcess::start($hash);
    return undef;

  } elsif( grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}) ) {
    CoProcess::start($hash);
    return undef;
  }

  return undef;
}

sub
tradfri_Undefine($$)
{
  my ($hash, $name) = @_;

  CoProcess::terminate($hash);

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}
sub
tradfri_DelayedShutdown($)
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
tradfri_Shutdown($)
{
  my ($hash) = @_;

  CoProcess::terminate($hash);

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}

sub
tradfri_processEvent($$) {
  my ($hash,$decoded) = @_;
  my $name = $hash->{NAME};

  my $id = $decoded->{id} ;

  if( $decoded->{r} eq 'scene' ) {
    if( $decoded->{t} eq 'remove' ) {
      delete $hash->{helper}{scenes}{$id};
      Log3 $name, 4, "$name: deleted scene $id";
    } else {
      Log3 $name, 4, "$name: ". ($hash->{helper}{scenes}{$id}?'updated':'added') ." scene $id";
      $hash->{helper}{scenes}{$id} = $decoded;
    }
    return;
  }

  my $code = '';
  $code = $name ."-". $id if( $decoded->{r} eq 'lights' );
  $code = $name ."-G". $id if( $decoded->{r} eq 'group' );
  $code = $name ."-S". $id if( $decoded->{r} eq 'sensor' );

  my $chash = $modules{HUEDevice}{defptr}{$code};

  if( $decoded->{t} eq 'remove' ) {
    if( $chash ) {
      fhem( "delete $chash->{NAME} " );
    }
    return;
  }

  if( defined($chash) ) {
    HUEDevice_Parse($chash,$decoded);
    HUEBridge_updateGroups($hash, $chash->{ID}) if( !$chash->{helper}{devtype} );

  } else {

    my $group;
    my $cname;
    my $define;
    if( $decoded->{r} eq 'lights' ) {
      $group = 'HUEDevice';
      $cname = "HUEDevice" . $id;
      #$cname = $name ."_". $cname if( $hash->{helper}{count} );
      $define= "$cname HUEDevice $id IODev=$name";
    } elsif( $decoded->{r} eq 'group' ) {
      $group = 'HUEGroup';
      $cname = "HUEGroup" . $id;
      #$cname = $name ."_". $cname if( $hash->{helper}{count} );
      $define= "$cname HUEDevice group $id IODev=$name";
    } elsif( $decoded->{r} eq 'sensor' ) {
      $group = 'HUESensor';
      $cname = "HUESensor" . $id;
      #$cname = $name ."_". $cname if( $hash->{helper}{count} );
      $define= "$cname HUEDevice sensor $id IODev=$name";
    }


    if( $define ) {
      Log3 $name, 4, "$name: create new device '$cname' for address '$id'";
      Log3 $name, 5, "$name:   $define";

      if( my $ret = CommandDefine(undef,$define) ) {
        Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $ret";

      } else {
        CommandAttr(undef,"$cname alias ".$decoded->{name}) if( $decoded->{name} );
        CommandAttr(undef,"$cname room Tradfri");
        #CommandAttr(undef,"$cname IODev $name");

        CommandAttr(undef, "$name createGroupReadings 1") if( $decoded->{r} eq 'group' );

        CommandAttr(undef,"$cname subType blind") if( $decoded->{type} eq 'blind' );

        HUEDeviceSetIcon($cname);
        $defs{$cname}{helper}{fromAutocreate} = 1 ;

        CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

        my $chash = $modules{HUEDevice}{defptr}{$code};
        if( defined($chash) ) {
          HUEDevice_Parse($chash,$decoded);
          HUEBridge_updateGroups($hash, $chash->{ID}) if( !$chash->{helper}{devtype} );
        }
      }

    } else {
      Log3 $name, 4, "$name: message for unknow device received: $code: ". Dumper $decoded;
    }
  }
}

sub
tradfri_Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf = CoProcess::readFn($hash);
  return undef if( !$buf );

  my $data = $hash->{helper}{PARTIAL};
  $data .= $buf;

  while($data =~ m/\n/) {
    ($buf,$data) = split("\n", $data, 2);

    Log3 $name, 5, "$name: read: $buf";

    if( $buf =~ m/^\*\*\* ([^\s]+) (.+)/ ) {
      my $service = $1;
      my $message = $2;

      if( $service eq 'FHEM:' ) {
        if( $message =~ m/^connection failed(, (.*))?/ ) {
          my $reason = $2;

          $hash->{reason} = 'failed to connect to gateway';
          $hash->{reason} .= ": $reason" if( $reason );

          if( $reason eq 'credentials wrong' ) {
            fhem( "deletereading $name identity" );
            fhem( "deletereading $name psk" );

            CoProcess::start($hash);

          } elsif( $reason eq 'credentials missing' ) {
            CoProcess::stop($hash);

          } elsif( $reason ) { #secret wrong
            CoProcess::stop($hash);

          } else {
            CoProcess::start($hash);

          }

        } elsif( $message =~ m/^identity: (.*)/ ) {
          my $identity = $1;
          readingsSingleUpdate($hash, 'identity', tradfri_encrypt($identity), 1 );

        } elsif( $message =~ m/^psk: (.*)/ ) {
          my $psk = $1;
          readingsSingleUpdate($hash, 'psk', tradfri_encrypt($psk), 1 );

        } else {
          Log3 $name, 4, "$name: unhandled message: $message";
        }
      }

    } elsif( $buf =~ m/this is tradfri-fhem (.*)/ ) {
      $hash->{'tradfri-fhem version'} = $1;

    } elsif( $buf =~ m/^\{.*\}/ ) {
      if( my $decoded = eval { JSON->new->utf8(0)->decode($buf) } ) {
        tradfri_processEvent($hash,$decoded);

      } else {
        Log3 $name, 2, "$name: json error: $@ in $buf";

      }

    } else {
      Log3 $name, 4, "$name: $buf";
    }
  }

  $hash->{PARTIAL} = $data;

  return undef;
}

sub
tradfri_Write($@)
{
  my ($hash,$chash,$cname,$id,$obj)= @_;
  my $name = $hash->{NAME};

  return undef if( IsDisabled($name) );

  #$id =~ s'/.*''g;
  #$obj->{id} = $id;

  $id = $1 if( $id =~ m/^G(\d+)/ );
  $id = $1 if( $id =~ m/^(\d+)/ );

  $obj->{id} = $id;

  $obj->{t} = 'lights';
  $obj->{t} = 'group' if( $chash->{helper}{devtype} eq 'G' );

  if( $hash->{FH} ) {
    my $encoded = encode_json($obj);

    Log3 $name, 5, "$name: writing: $encoded";

    $encoded .= "\n";
    syswrite( $hash->{FH}, $encoded );
  } else {
    Log3 $name, 3, "$name: not connected";
  }

  return undef;
}


sub
tradfri_getCmd($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !$init_done );

  my $ssh_cmd;
  if( my $host = AttrVal($name, 'tradfriFHEM-sshHost', undef ) ) {
    my $ssh = qx( which ssh ); chomp( $ssh );
    if( my $user = AttrVal($name, 'tradfriFHEM-sshUser', undef ) ) {
      $ssh_cmd = "$ssh $user\@$host";
    } else {
      $ssh_cmd = "$ssh $host";
    }

    Log3 $name, 3, "$name: using ssh cmd $ssh_cmd";
  }

  my $cmd;
  if( $ssh_cmd ) {
    $cmd = AttrVal( $name, "tradfriFHEM-cmd", qx( $ssh_cmd which tradfri-fhem ) );
  } else {
    $cmd = AttrVal( $name, "tradfriFHEM-cmd", qx( which tradfri-fhem ) );
  }
  chomp( $cmd );

  if( !$ssh_cmd && !(-X $cmd) ) {
    my $msg = "tradfri-fhem not installed. install with 'sudo npm install -g tradfri-fhem'.";
    $msg = "$cmd does not exist" if( $cmd );
    return (undef, $msg);
  }

  $cmd = "$ssh_cmd $cmd" if( $ssh_cmd );

  if( my $security_code = AttrVal($name, 'tradfriFHEM-securityCode', undef ) ) {
     $cmd .= ' -s '. tradfri_decrypt($security_code);
  } else {
    my $msg = 'security code missing';
    return (undef, $msg);
  }

  if( my $identity = ReadingsVal($name, 'identity', undef ) ) {
    $cmd .= " -i ". tradfri_decrypt($identity) ;
  }

  if( my $psk = ReadingsVal($name, 'psk', undef ) ) {
    $cmd .= " -p ". tradfri_decrypt($psk) ;
  }

  if( my $params = AttrVal($name, 'tradfriFHEM-params', undef ) ) {
    $cmd .= " $params";
  }

  if( AttrVal( $name, 'verbose', 3 ) == 5 ) {
    Log3 $name, 2, "$name: starting tradfri-fhem: $cmd";
  } else {
    my $msg = $cmd;
    $msg =~ s/-s\s+[^\s]+/-s sssss/g;
    $msg =~ s/-i\s+[^\s]+/-i iiiii/g;
    $msg =~ s/-p\s+[^\s]+/-p ppppp/g;
    Log3 $name, 2, "$name: starting tradfri-fhem: $msg";
  }

  return $cmd;
}

sub
tradfri_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "";

  if( $cmd eq 'scene' ) {
    return "usage: scene <id>" if( @args != 1 );

    my $id = $args[0];
    if( !defined($hash->{helper}{scenes}{$id}) ) {
    foreach my $key ( keys %{$hash->{helper}{scenes}} ) {
      if( $id eq $hash->{helper}{scenes}{$key}{name} ) {
        $id = $key;
        last;
      }
    }

      return "no such scene" if( !defined($hash->{helper}{scenes}{$id}) );
    }

    my $scene = $hash->{helper}{scenes}{$id};

    my $obj = { 'sceneId' => 0+$id };

    my $code = $name ."-G". $scene->{group};
    my $chash = $modules{HUEDevice}{defptr}{$code};
    tradfri_Write($hash, $chash, $chash->{NAME}, $chash->{ID} , $obj);

    return undef;

  } elsif( $cmd eq 'statusRequest' ) {
    #unused
    return undef;

  }

  my $scenes;
  foreach my $key ( sort {$a cmp $b} keys %{$hash->{helper}{scenes}} ) {
    $scenes .=',' if( $scenes );
    my $name = $hash->{helper}{scenes}{$key}{name};
    $name =~ s/ /#/g;
    $scenes .= $name;
  }
  if( $scenes ) {
    $list .= " " if( $list );
    $list .= " scene:$scenes";
  }

  return CoProcess::setCommands($hash, $list, $cmd, @args);
}



sub
tradfri_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = 'scenes:noArg';

  if( $cmd eq 'scenes' ) {
    my $ret;
    foreach my $key ( sort {$a cmp $b} keys %{$hash->{helper}{scenes}} ) {
      my $scene = $hash->{helper}{scenes}{$key};

      my $group = $scene->{group};
      my $code = $name ."-G". $scene->{group};
      if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
        $group = AttrVal( $chash->{NAME}, 'alias', $group );
      }

      $ret .= sprintf( "%-20s %-20s %-20s", $key, $group, $scene->{name} );
      $ret .= sprintf( " %s\n", join( ",", @{$scene->{lights}} ) );
    }
    if( $ret ) {
      my $header = sprintf( "%-20s %-20s %-20s", "ID", "GROUP", "NAME" );
      $header .= sprintf( " %s\n", "LIGHTS" );
      $ret = $header . $ret;
    }
    return $ret;

  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
tradfri_Parse($$;$)
{
  my ($hash,$data,$peerhost) = @_;
  my $name = $hash->{NAME};
}

sub
tradfri_encrypt($)
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
tradfri_decrypt($)
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
tradfri_Attr($$$)
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

  } elsif( $attrName eq 'tradfriFHEM-params' ) {
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  } elsif( $attrName eq 'tradfriFHEM-sshHost' ) {
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  } elsif( $attrName eq 'tradfriFHEM-sshUser' ) {
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  } elsif( $attrName eq 'tradfriFHEM-securityCode' ) {
    if( $cmd eq "set" && $attrVal ) {
      $attrVal = tradfri_encrypt($attrVal);
    }
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

    if( $cmd eq "set" && $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return "stored obfuscated security code";
    }

  }


  if( $cmd eq 'set' ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return "stored modified value";
    }

  } else {
    delete $attr{$name}{$attrName};

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday(), "tradfri_AttrDefaults", $hash, 0);
  }

  return;
}


1;

=pod
=item summary    Module to control the FHEM/tradfri integration
=item summary_DE Modul zur Konfiguration der FHEM/tradfri Integration
=begin html

<a name="tradfri"></a>
<h3>tradfri</h3>
<ul>
  Module to control the integration of IKEA tradfri devices with FHEM.<br><br>

  Notes:
  <ul>
    <li>JSON has to be installed on the FHEM host.</li>
    <li>tradfri-fhem node executable hast do be installed with <code>sudo npm install -g tradfri-fhem</code></li>
  </ul>

  <a name="tradfri_Set"></a>
  <b>Set</b>
  <ul>
    <li>scene &lt;name|id&gt;<br>
    </li>
  </ul>

  <a name="tradfri_Get"></a>
  <b>Get</b>
  <ul>
    <li>scenes<br>
      </li>
  </ul>

  <a name="tradfri_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>tradfriFHEM-securityCode<br>
      the security code on the back of the gateway</li>
    <li>tradfriFHEM-cmd<br>
      The command to use as tradfri-fhem</li>
    <li>tradfriFHEM-params<br>
      Additional tradfri-fhem cmdline params.</li>
  </ul>
</ul><br>

=end html

=encoding utf8
=for :application/json;q=META.json 30_tradfri.pm
{
  "abstract": "Module to control the FHEM/Tradfri integration",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Konfiguration der FHEM/Tradfri Integration"
    }
  },
  "keywords": [
    "fhem-mod",
    "fhem-mod-device",
    "tradfri",
    "tradfri-fhem",
    "zigbee",
    "nodejs",
    "node"
  ],
  "release_status": "stable",
  "x_fhem_maintainer": [
    "justme1968"
  ],
  "x_fhem_maintainer_github": [
    "justme-1968"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014, 
        "Meta": 0,
        "CoProcess": 0,
        "JSON": 0,
        "Data::Dumper": 0
      },
      "recommends": {
      },
      "suggests": {
        "HUEDevice": 0
      }
    }
  },
  "x_prereqs_nodejs": {
    "runtime": {
      "requires": {
        "node": 8.0,
        "tradfri-fhem": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json
=cut
