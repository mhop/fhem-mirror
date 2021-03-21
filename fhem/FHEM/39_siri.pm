
# $Id$

package main;

use strict;
use warnings;

use CoProcess;

use HttpUtils;

use vars qw(%modules);
use vars qw(%defs);
use vars qw(%attr);
use vars qw($readingFnAttributes);
use vars qw($FW_ME);

sub Log($$);
sub Log3($$$);

sub
siri_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}   = "siri_Read";

  $hash->{DefFn}    = "siri_Define";
  $hash->{NotifyFn} = "siri_Notify";
  $hash->{UndefFn}  = "siri_Undefine";
  $hash->{DelayedShutdownFn} = "siri_DelayedShutdownFn";
  $hash->{ShutdownFn} = "siri_Shutdown";
  $hash->{SetFn}    = "siri_Set";
  #$hash->{GetFn}    = "siri_Get";
  $hash->{AttrFn}   = "siri_Attr";
  $hash->{AttrList} = "homebridgeFHEM-cmd ".
                      #"homebridgeFHEM-config ".
                      #"homebridgeFHEM-home ".
                      "homebridgeFHEM-log ".
                      "homebridgeFHEM-params ".
                      #"homebridgeFHEM-auth ".
                      #"homebridgeFHEM-filter ".
                      "homebridgeFHEM-host homebridgeFHEM-sshUser ".
                      "nrarchive ".
                      "disable:1 disabledForIntervals ".
                      $readingFnAttributes;

  $hash->{FW_detailFn} = "siri_detailFn";
  $hash->{FW_deviceOverview} = 1;

  if( 0 ) {
    my $m = 'homebridge-fhem';
    my ($defptr, $ldata);
    if($modules{$m}) {
      $defptr = $modules{$m}{defptr};
      $ldata = $modules{$m}{ldata};
    }
    $modules{$m} = $hash;
    $modules{$m}{ORDER} = 39;
    $modules{$m}{LOADED} = 1;
    $modules{$m}{defptr} = $defptr if($defptr);
    $modules{$m}{ldata} = $ldata if($ldata);
  }
}

#####################################

sub
siri_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> siri"  if(@a != 2);

  my $name = $a[0];
  $hash->{NAME} = $name;

  my $d = $modules{$hash->{TYPE}}{defptr};
  #return "$hash->{TYPE} device already defined as $d->{NAME}. please use homebridge-fhem for other instances." if( defined($d) && $hash->{TYPE} eq 'siri' );
  return "$hash->{TYPE} device already defined as $d->{NAME}." if( defined($d) );
  $modules{$hash->{TYPE}}{defptr} = $hash;

  addToAttrList("$hash->{TYPE}Name");
  $hash->{STATE} = 'active';

  $hash->{NOTIFYDEV} = "global,global:npmjs.*homebridge.*";

  if( $attr{global}{logdir} ) {
    CommandAttr(undef, "$name homebridgeFHEM-log %L/homebridgeFHEM-%Y-%m-%d.log") if( !AttrVal($name, 'homebridgeFHEM-log', undef ) );
  } else {
    CommandAttr(undef, "$name homebridgeFHEM-log ./log/homebridgeFHEM-%Y-%m-%d.log") if( !AttrVal($name, 'homebridgeFHEM-log', undef ) );
  }

  #CommandAttr(undef, "$name homebridgeFHEM-filter homebridgeFHEM=..*") if( !AttrVal($name, 'homebridgeFHEM-filter', undef ) );

  if( !AttrVal($name, 'devStateIcon', undef ) ) {
    CommandAttr(undef, "$name stateFormat homebridge");
    CommandAttr(undef, "$name devStateIcon stopped:control_home\@red:start stopping:control_on_off\@orange running.*:control_on_off\@green:stop")
  }


  $hash->{CoProcess} = {  name => 'homebridge',
                         cmdFn => 'siri_getCMD',
                       };

  if( $init_done ) {
    CoProcess::start($hash);
  } else {
    $hash->{STATE} = 'active';
  }

  return undef;
}

sub
siri_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");

  if( grep(m/^npmjs:BEGIN.*homebridge.*/, @{$dev->{CHANGED}}) ) {
    CoProcess::stop($hash);
    return undef;

  } elsif( grep(m/^npmjs:FINISH.*homebridge.*/, @{$dev->{CHANGED}}) ) {
    CoProcess::start($hash);
    return undef;

  } elsif( grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}) ) {
    CoProcess::start($hash);
    return undef;
  }

  return undef;
}

sub
siri_Undefine($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  if( $hash->{PID} ) {
    $hash->{undefine} = 1;
    $hash->{undefine} = $hash->{CL} if( $hash->{CL} );

    $hash->{reason} = 'delete';
    CoProcess::stop($hash);

    return "$name will be deleted after homebridge has stopped or after 5 seconds. whatever comes first.";
  }

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}
sub
siri_DelayedShutdownFn($)
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
siri_Shutdown($)
{
  my ($hash) = @_;

  CoProcess::terminate($hash);

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}

sub
siri_detailFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};
  my $name = $hash->{NAME};

  my $ret;

  my $logfile = AttrVal($name, 'homebridgeFHEM-log', 'FHEM' );
  if( $logfile && $logfile ne 'FHEM' ) {
    my $name = 'homebridgeFHEMlog';
    $ret .= "<a href=\"$FW_ME?detail=$name\">". AttrVal($name, "alias", "Logfile") ."</a><br>";
  }

  if( $hash->{PID} ) {
    if( $hash->{helper}{Code} ) {
      $hash->{helper}{Code} =~ s/[^0-9\-]//g;
      $ret .= "<br>" if( $ret );
      $ret .= "Code: <code>$hash->{helper}{Code}</code><br>";
    }

    if( $hash->{helper}{'Setup Payload'} ) {
      $ret .= "<br>" if( $ret );
      $ret .= "Setup: <a href=\"$hash->{helper}{'Setup Payload'}\">$hash->{helper}{'Setup Payload'}</a><br>";
    }

    if( $hash->{helper}{'Setup Payload'} ) {
      $ret .= "<br>" if( $ret );
      $ret .= "<img src=\"//chart.apis.google.com/chart?chs=200x200&cht=qr&chld=L&chl=";
      $ret .= urlEncode($hash->{helper}{'Setup Payload'});
      $ret .= "\"/><br>";

      #https://developers.google.com/chart/infographics/docs/qr_codes
      #https://chart.googleapis.com/chart?chs=150x150&cht=qr&chl=Hello%20world&choe=UTF-8
      #http://chart.apis.google.com/chart?chs=200x200&cht=qr&chld=L&chl=
      #http://goqr.me/api/doc/create-qr-code/
      #https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=Example
    }
  }


  return $ret;
}

sub
siri_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf = CoProcess::readFn($hash);
  return undef if( !$buf );

  my $data = $hash->{helper}{PARTIAL};
  $data .= $buf;

  while($data =~ m/\n/) {
    ($buf,$data) = split("\n", $data, 2);

    #Log3 $name, 5, "$name: read: $buf";


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

    } elsif( $buf =~ /^\[/ ) {
      delete $hash->{helper}{next};

    } elsif( 1 && $buf =~ '^X-HM://' ) {
      $hash->{helper}{'Setup Payload'} = $buf;

    } elsif( 0 && $buf =~ /^Setup Payload:$/ ) {
      $hash->{helper}{next} = 'Setup Payload';
      delete $hash->{helper}{$hash->{helper}{next}};

    } elsif( 0 && $buf =~ /^Scan this code/ ) {
      $hash->{helper}{next} = 'QR-Code';
      delete $hash->{helper}{$hash->{helper}{next}};

    } elsif( $buf =~ /enter this code with your HomeKit app/ ) {
      $hash->{helper}{next} = 'Code';
      delete $hash->{helper}{$hash->{helper}{next}};

    } elsif( $hash->{helper}{next} ) {
      $hash->{helper}{$hash->{helper}{next}} .= "\n" if( $hash->{$hash->{helper}{next}} );
      $hash->{helper}{$hash->{helper}{next}} .= $buf;

    }
  }

  $hash->{PARTIAL} = $data;

  return undef;
}

sub
siri_getCMD($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !$init_done );

  if( 0 && !AttrVal($name, 'homebridgeFHEM-config', undef ) ) {
    siri_configDefault($hash);
  }

  delete $hash->{helper}{Code};
  delete $hash->{helper}{'QR-Code'};
  delete $hash->{helper}{'Setup Paload'};

  return undef if( IsDisabled($name) );
  #return undef if( ReadingsVal($name, 'homebridge', 'unknown') =~ m/^running/ );


  my $ssh_cmd;
  if( my $host = AttrVal($name, 'homebridgeFHEM-host', undef ) ) {
    my $ssh = qx( which ssh ); chomp( $ssh );
    if( my $user = AttrVal($name, 'homebridgeFHEM-sshUser', undef ) ) {
      $ssh_cmd = "$ssh $user\@$host";
    } else {
      $ssh_cmd = "$ssh $host";
    }

    Log3 $name, 3, "$name: using ssh cmd $ssh_cmd";
  }

  my $cmd;
  if( $ssh_cmd ) {
    $cmd = AttrVal( $name, "homebridgeFHEM-cmd", qx( $ssh_cmd which homebridge ) );
  } else {
    $cmd = AttrVal( $name, "homebridgeFHEM-cmd", qx( which homebridge ) );
  }
  chomp( $cmd );

  if( !$ssh_cmd && !(-X $cmd) ) {
    my $msg = "homebridge not installed. install with 'sudo npm install -g homebridge homebridge-fhem'.";
    $msg = "$cmd does not exist" if( $cmd );
    return (undef, $msg);
  }

  $cmd = "$ssh_cmd $cmd" if( $ssh_cmd );

  if( my $home = AttrVal($name, 'homebridgeFHEM-home', undef ) ) {
    $home = $ENV{'PWD'} if( $home eq 'PWD' );
    $ENV{'HOME'} = $home;
    Log3 $name, 2, "$name: setting \$HOME to $home";
  }
  if( my $config = AttrVal($name, 'homebridgeFHEM-config', undef ) ) {
    if( $ssh_cmd ) {
      qx( $ssh_cmd "cat > /tmp/homebridge.cfg" < $config );
      $cmd .= " -c /tmp/homebridge.cfg";
    } else {
      $cmd .= " -c $config";
    }
  }
  if( my $params = AttrVal($name, 'homebridgeFHEM-params', undef ) ) {
    $cmd .= " $params";
  }

  Log3 $name, 2, "$name: starting homebridge $cmd";

  return $cmd;

}

sub
siri_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "";

  return CoProcess::setCommands($hash, $list, $cmd, @args);

  return "Unknown argument $cmd, choose one of $list";
}

sub
siri_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}


sub
siri_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  my $hash = $defs{$name};
  if( $attrName eq 'homebridgeFHEM-log' ) {
    if( $cmd eq "set" && $attrVal && $attrVal ne 'FHEM' ) {
      fhem( "defmod -temporary homebridgeFHEMlog FileLog $attrVal fakelog" );
      CommandAttr( undef, 'homebridgeFHEMlog room hidden' );
      #if( my $room = AttrVal($name, "room", undef ) ) {
      #  CommandAttr( undef,"homebridgeFHEMlog room $room" );
      #}
      $hash->{logfile} = $attrVal;
    } else {
      fhem( "delete homebridgeFHEMlog" );
    }

    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);
  } elsif( $attrName eq 'homebridgeFHEM-params' ) {
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  } elsif( $attrName eq 'homebridgeFHEM-host' ) {
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  } elsif( $attrName eq 'homebridgeFHEM-sshUser' ) {
    $attr{$name}{$attrName} = $attrVal;

    CoProcess::start($hash);

  }



  if( $cmd eq 'set' ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}


1;

=pod
=item summary    Module to control the FHEM/Siri integration
=item summary_DE Modul zur Konfiguration der FHEM/Siri Integration
=begin html

<a name="siri"></a>
<h3>siri</h3>
<ul>
  Module to control the FHEM/Siri integration.<br><br>

  Notes:
  <ul>
    <li><br>
    </li>
  </ul>

  <a name="siri_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>siriName<br>
    The name to use for a device with siri.</li>
  </ul>
</ul><br>

=end html
=cut
