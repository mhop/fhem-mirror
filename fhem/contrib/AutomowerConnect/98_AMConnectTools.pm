###############################################################################
#
# $Id$
# 
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
#
# Husqvarnas unofficial app API is used to in crease websocket events
# 
################################################################################

package FHEM::AMConnectTools;
our $cvsid = '$Id$';
use strict;
use warnings;
use POSIX;
use GPUtils qw(:all);
use FHEM::Core::Authentication::Passwords qw(:ALL);
use Time::HiRes qw(gettimeofday);
use Time::Local;
use Storable qw(dclone retrieve store);

BEGIN {
    GP_Import(
        qw(
          AttrVal
          CommandAttr
          CommandDeleteReading
          FmtDateTime
          FW_ME
          getKeyValue
          InternalTimer
          InternalVal
          IsDisabled
          Log3
          Log
          attr
          defs
          devspec2array
          deviceEvents
          init_done
          minNum
          maxNum
          modules
          readingFnAttributes
          readingsBeginUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsDelete
          readingsEndUpdate
          ReadingsNum
          readingsSingleUpdate
          ReadingsVal
          RemoveInternalTimer
          setKeyValue
          setNotifyDev
          )
    );
}

GP_Export(
    qw(
      Initialize
      )
);

my $missingModul = "";

eval "use JSON;1" or $missingModul .= "JSON ";
require HttpUtils;

use constant { 
  AUTHURL       => 'https://iam-api.dss.husqvarnagroup.net/api/v3/',
  APIURL        => 'https://amc-api.dss.husqvarnagroup.net/app/v1/',
};

##############################################################
sub Initialize() {
  my ($hash) = @_;

  $hash->{DefFn}      = \&Define;
  $hash->{UndefFn}    = \&Undefine;
  $hash->{DeleteFn}   = \&Delete;
  $hash->{RenameFn}   = \&Rename;
  $hash->{NotifyFn}   = \&Notify;
  $hash->{SetFn}      = \&Set;
  $hash->{AttrFn}     = \&Attr;
  $hash->{AttrList}   = "disable:1,0 " .
                        "notifiedByMowerDevices " .
                        $::readingFnAttributes;

  return undef;
}

#########################
sub Define{
  my ( $hash, $def ) = @_;
  my @val = split( "[ \t]+", $def );
  my $name = $val[0];
  my $type = $val[1];
  my $iam = "$type $name Define:";
  my $username = '';

  return "$iam multiple definitions are not allowed." if( scalar devspec2array( "TYPE=$type" ) > 1 );

  return "$iam Cannot define $type device. Perl modul $missingModul is missing." if ( $missingModul );

  return "$iam too few parameters: define <NAME> $type <email>" if( @val < 3 );

  $username = $val[2];

  %$hash = (%$hash,
    helper => {
      passObj                   => FHEM::Core::Authentication::Passwords->new($type),
      calltype                  => 'status',
      interval                  => 440,
      timeout_apiauth           => 5,
      timeout_getmower          => 5,
      retry_interval_apiauth    => 120,
      retry_count_apiauth       => 0,
      retry_max_apiauth         => 10,
      retry_interval_getmower   => 60,
      retry_int_getmowerstatus  => 60,
      username                  => $username
    }
  );

  $attr{$name}{room} = 'AutomowerConnect' if( !defined( $attr{$name}{room} ) );
  $attr{$name}{icon} = 'helper_automower' if( !defined( $attr{$name}{icon} ) );
  $attr{$name}{notifiedByMowerDevices} = 'TYPE=AutomowerConnect' if( !defined( $attr{$name}{notifiedByMowerDevices} ) );
  ( $hash->{VERSION} ) = $cvsid =~ /\.pm (.*)Z/;
  setNotifyDev( $hash, 'global,' . $attr{$name}{notifiedByMowerDevices} );

  if( $hash->{helper}->{passObj}->getReadPassword($name) ) {

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, \&APIAuth, $hash, 1);

      readingsSingleUpdate( $hash, 'state', 'defined', 1 );

  } else {

      readingsSingleUpdate( $hash, 'state', 'defined - client_secret missing', 1 );

  }
  if ( $init_done ) {

    my $paw = join( ' ', devspec2array( "TYPE=AutomowerConnect" ) );
    readingsSingleUpdate( $hash, '.associatedWith', $paw, 0 );

  }

  return undef;

}

#########################
sub Notify {
  my ($hash, $dev_hash) = @_;
  my $name = $hash->{NAME}; # me
  return if ( IsDisabled( $name ) == 1 );
  my $dev_name = $dev_hash->{NAME};

  my $events = deviceEvents($dev_hash,1);
  return if( !$events );

  my $runningDevices = ReadingsVal( $name, 'runningDevices', '' );

  foreach my $event (@{$events}) {

    $event = '' if(!defined($event));

    if ( $event =~ /^mower_activity: (LEAVING|MOWING|GOING_HOME)$/ ) {

      readingsBeginUpdate($hash);

        if ( !$runningDevices ) {

          RemoveInternalTimer( $hash );
          InternalTimer( gettimeofday() + 2, \&APIAuth, $hash, 0 );
          readingsBulkUpdateIfChanged( $hash, 'state', 'update' );

        }

        $runningDevices .= $dev_name . ' ' if ( $runningDevices !~ /(^|\s)$dev_name\s/ );
        readingsBulkUpdateIfChanged( $hash, 'runningDevices', $runningDevices );

      readingsEndUpdate( $hash, 1);

    } elsif ( $event =~ /^mower_activity: PARKED_IN_CS$/ ) {

      $runningDevices =~ s/(^|\s)$dev_name\s/$1/;

      if ( !$runningDevices ) {

       readingsDelete( $hash, 'runningDevices' );
       readingsSingleUpdate( $hash, 'state', 'inactive', 1 );

      }

    } elsif ( $dev_name eq 'global' && $event =~ /^(INITIALIZED|MODIFIED $name|ATTR $name disable 0|DELETEATTR $name disable)$/ ) {

      foreach my $keyx ( devspec2array('TYPE=AutomowerConnect') ) {

        if ( !defined( $defs{$keyx}->{VERSION_AMConnectTools} ) || defined( $defs{$keyx}->{VERSION_AMConnectTools} ) && $defs{$keyx}->{VERSION_AMConnectTools} ne $defs{AMConnectTools}->{VERSION} ) {

          $defs{$keyx}->{VERSION_AMConnectTools} = $defs{AMConnectTools}->{VERSION}

        }

      }

      my $runningDevices = '';
      my @mowers = devspec2array( AttrVal( $name, 'notifiedByMowerDevices', '' ) );

      for my $item ( @mowers ) {

        if ( ReadingsVal( $item, 'mower_activity', '' ) =~ /^(LEAVING|MOWING|GOING_HOME)$/ ) {

          $runningDevices .= $item . ' ';

        }

      }

      if ( !$runningDevices ) {

        readingsDelete( $hash, 'runningDevices' );
        readingsSingleUpdate( $hash, 'state', 'inactive', 1 );

      } else {

        readingsSingleUpdate( $hash, 'runningDevices', $runningDevices, 1 );
 
      }

    }

  }

}

#########################
sub APIAuth {
  my ( $hash, $update ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name APIAuth:";
  my @states = ('undefined', 'disabled', 'temporarily disabled', 'inactive' );

  if( IsDisabled( $name ) ) {
    readingsSingleUpdate( $hash, 'state', $states[ IsDisabled( $name ) ], 1 ) if ( ReadingsVal( $name, 'state', '' ) !~ /disabled|inactive/ );
    RemoveInternalTimer( $hash );
    InternalTimer( gettimeofday() + $hash->{helper}{interval}, \&APIAuth, $hash, 0 );
    return undef;

  }

  if ( !$update && $::init_done ) {

    if ( ReadingsVal( $name,'.token','' ) and gettimeofday() < (ReadingsVal( $name, '.token_expires', 0 ) - $hash->{helper}{interval} - 45 ) ) {

      readingsSingleUpdate( $hash, 'state', 'update', 1 );

      if ( !ReadingsVal( $name,'.apiMowerFound','' ) ) {

        getMower( $hash );

      } else {

        getMowerStatus( $hash );

      }

    } else {

      readingsSingleUpdate( $hash, 'state', 'authentification', 1 );
      my $username = $hash->{helper}->{username};
      my $password = $hash->{helper}->{passObj}->getReadPassword( $name );
      my $timeout = $hash->{helper}->{timeout_apiauth};

      my $header = "Content-Type: application/json\r\nAccept: application/json";
      my $data = '{
        "data" : {
          "type" : "token",
          "attributes" : {
            "username" : "' . $username. '",
            "password" : "' . $password. '"
          }
        }
      }';

      ::HttpUtils_NonblockingGet( {
        url         => AUTHURL . 'token',
        timeout     => $timeout,
        hash        => $hash,
        method      => 'POST',
        header      => $header,
        data        => $data,
        callback    => \&APIAuthResponse,
        t_begin     => scalar gettimeofday()
      } );

    }

  } else {

    RemoveInternalTimer( $hash, \&APIAuth );
    InternalTimer( gettimeofday() + $hash->{helper}{interval}, \&APIAuth, $hash, 0 );

  }
  return undef;
}

#########################
sub APIAuthResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // '';
  my $iam = "$type $name APIAuthResponse:";

  Log3 $name, 4, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s';
  Log3 $name, 4, "$iam \$statuscode >$statuscode< \$err >$err< \$param->url $param->{url}\n\$data >$data<\n";

  if( !$err && $statuscode == 201 && $data ) {

    my $result = eval { decode_json( $data ) };
    if ($@) {

      Log3 $name, 2, "$iam JSON error [ $@ ]";
      readingsSingleUpdate( $hash, 'state', 'error JSON', 1 );

    } else {

      $hash->{helper}->{auth} = $result->{data};
      $hash->{helper}{auth}{expires} = gettimeofday() + $hash->{helper}{auth}{attributes}{expires_in};
      my $paw = join( ' ', devspec2array( "TYPE=AutomowerConnect" ) );
      $hash->{helper}{retry_count_apiauth} = 0;
      
      # Update readings
      readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged($hash,'.associatedWith', $paw, 0 ) if ( $paw );
        readingsBulkUpdateIfChanged($hash,'.token', $hash->{helper}{auth}{id}, 0 );
        readingsBulkUpdateIfChanged($hash,'.provider', $hash->{helper}{auth}{attributes}{provider}, 0 );
        readingsBulkUpdateIfChanged($hash,'.user_id', $hash->{helper}{auth}{attributes}{user_id}, 0 );
        readingsBulkUpdateIfChanged($hash,'.scope', $hash->{helper}{auth}{attributes}{scope}, 0 );
        readingsBulkUpdateIfChanged($hash,'.client_id', $hash->{helper}{auth}{attributes}{client_id}, 0 );
        readingsBulkUpdateIfChanged($hash,'.refresh_token', $hash->{helper}{auth}{attributes}{expires_in}, 0 );
        readingsBulkUpdateIfChanged($hash,'.expires_in', $hash->{helper}{auth}{attributes}{expires_in}, 0 );

        readingsBulkUpdateIfChanged($hash,'.token_expires',$ hash->{helper}{auth}{expires}, 0 );
        readingsBulkUpdateIfChanged($hash,'token_expires_fmt', FmtDateTime( $hash->{helper}{auth}{expires}), 0 );
        readingsBulkUpdateIfChanged($hash,'state', 'authenticated');
      readingsEndUpdate($hash, 1);

      RemoveInternalTimer( $hash, \&getMower );
      InternalTimer( gettimeofday() + 1.5, \&getMower, $hash, 0 );
      return undef;
    }

  } else {

    readingsSingleUpdate( $hash, 'state', "error statuscode $statuscode", 1 );
    Log3 $name, 1, "$iam \$statuscode >$statuscode< \$err >$err< \$param->url $param->{url}\n\$data >$data<\n";

    if ( $statuscode == 400 ) {

      $hash->{helper}{retry_count_apiauth}++;
      
      if ( $hash->{helper}{retry_count_apiauth} > $hash->{helper}{retry_max_apiauth} ) {

        CommandAttr( $hash, "$name disable 1" );
        $hash->{helper}{retry_count_apiauth} = 0;

    }

    } elsif ( $statuscode == 429 ) {

      CommandAttr( $hash, "$name disable 1" );
      $hash->{helper}{retry_count_apiauth} = 0;

    }

    RemoveInternalTimer( $hash, \&APIAuth );
    InternalTimer( gettimeofday() + $hash->{helper}{retry_interval_apiauth}, \&APIAuth, $hash, 0 );
    Log3 $name, 1, "$iam failed retry in $hash->{helper}{retry_interval_apiauth} seconds.";
    return undef;

  }

}

#########################
sub getMower {
  
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name getMower:";
  my $token = ReadingsVal($name,'.token','');
  my $provider = ReadingsVal($name,'.provider','');
  my $client_id = $hash->{helper}->{client_id};
  my $timeout = $hash->{helper}->{timeout_getmower};

  my $header = "Content-Type: application/json\r\nAccept: application/json\r\nAuthorization: Bearer " . $token . "\r\nAuthorization-Provider: " . $provider;
  Log3 $name, 5, "$iam \$header >$header<";

  ::HttpUtils_NonblockingGet({
    url        => APIURL . 'mowers',
    timeout    => $timeout,
    hash       => $hash,
    method     => "GET",
    header     => $header,  
    callback   => \&getMowerResponse,
    t_begin    => scalar gettimeofday()
  });

  return undef;
}

#########################
sub getMowerResponse {
  
  my ( $param, $err, $data ) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // '';
  my $iam = "$type $name getMowerResponse:";
  
  Log3 $name, 4, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s';
  Log3 $name, 4, "$iam response \$statuscode >$statuscode<, \$err >$err<, \$param->url $param->{url} \n\$data >$data<";
  
  if( !$err && $statuscode == 200 && $data) {
    
    if ( $data eq "[]" ) {
      
      Log3 $name, 2, "$iam no mower data present";
      
    } else {

      my $result = eval { decode_json($data) };
      if ($@) {

        Log3( $name, 2, "$iam - JSON error while request: $@");

      } else {

        my @mowers = @{ dclone( $result ) };
        my $mcnt = @mowers;
        my $fMs = '';

        map {

          $fMs .= $_->{id} .' ';

        } @mowers;

        chop $fMs;
        Log3 $name, 4, "$iam found $fMs";

        readingsBeginUpdate($hash);

          readingsBulkUpdateIfChanged($hash, '.apiMowerFound', $fMs, 0 );
          readingsBulkUpdate($hash, 'state', 'connected' );

        readingsEndUpdate($hash, 1);

        RemoveInternalTimer( $hash, \&getMowerStatus );
        InternalTimer( gettimeofday() + 1.5, \&getMowerStatus, $hash, 0 );

        return undef;

      }

    }
    
  } else {

    readingsSingleUpdate( $hash, 'state', "error statuscode $statuscode", 1 );
    Log3 $name, 1, "$iam \$statuscode >$statuscode<, \$err >$err<, \$param->url $param->{url} \n\$data >$data<";

  }

  RemoveInternalTimer( $hash, \&APIAuth );
  InternalTimer( gettimeofday() + $hash->{helper}{retry_interval_getmower}, \&APIAuth, $hash, 0 );
  Log3 $name, 1, "$iam failed retry in $hash->{helper}{retry_interval_getmower} seconds.";
  return undef;

}

#########################
sub getMowerStatus {
  
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name getMowerStatus:";
  my $token = ReadingsVal($name,'.token','');
  my $provider = ReadingsVal($name,'.provider','');
  my @mower_id = split( / /, ReadingsVal( $name,'.apiMowerFound','' ) );
  my $timeout = $hash->{helper}{timeout_getmower};

  my $header = "Content-Type: application/json\r\nAccept: application/json\r\nAuthorization: Bearer " . $token . "\r\nAuthorization-Provider: " . $provider;
  Log3 $name, 5, "$iam \$header >$header<";

  ::HttpUtils_NonblockingGet({
    url        => APIURL . 'mowers/' . $mower_id[0] . '/status',
    timeout    => $timeout,
    hash       => $hash,
    method     => "GET",
    header     => $header,  
    callback   => \&getMowerStatusResponse,
    t_begin    => scalar gettimeofday()
  });

  return undef;
}

#########################
sub getMowerStatusResponse {
  
  my ( $param, $err, $data ) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // '';
  my $iam = "$type $name getMowerStatusResponse:";
  
  Log3 $name, 4, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s';
  Log3 $name, 4, "$iam response \$statuscode >$statuscode<, \$err >$err<, \$param->url $param->{url} \n\$data >$data<";
  
  if( !$err && $statuscode == 200 && $data) {
    
    if ( !$data ) {
      
      Log3 $name, 2, "$iam no mower data present";
      
    } else {

      my $result = eval { decode_json($data) };
      if ($@) {

        Log3( $name, 2, "$iam - JSON error while request: $@");

      } else {

        readingsBeginUpdate($hash);

          readingsBulkUpdate($hash,'nextRound', FmtDateTime( time() + $hash->{helper}{interval} ) );
          readingsBulkUpdate($hash, 'state', 'connected' );

        readingsEndUpdate($hash, 1);

        # schedule next round
        RemoveInternalTimer( $hash, \&APIAuth );
        InternalTimer( gettimeofday() + $hash->{helper}{interval}, \&APIAuth, $hash, 0 );

        return undef;

      }

    }
    
  } else {

    readingsSingleUpdate( $hash, 'state', "error statuscode $statuscode", 1 );
    Log3 $name, 1, "$iam \$statuscode >$statuscode<, \$err >$err<, \$param->url $param->{url} \n\$data >$data<";

  }

  RemoveInternalTimer( $hash, \&APIAuth );
  InternalTimer( gettimeofday() + $hash->{helper}{retry_int_getmowerstatus}, \&APIAuth, $hash, 0 );
  Log3 $name, 1, "$iam failed retry in $hash->{helper}{retry_int_getmowerstatus} seconds.";
  return undef;

}

#########################
sub Set {
  my ($hash,@val) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};
  my $iam = "$type $name Set:";

  return "$iam: needs at least one argument" if ( @val < 2 );
  return "Unknown argument, $iam is disabled, choose one of none:noArg" if ( IsDisabled( $name ) );

  my ($pname,$setName,$setVal,$setVal2,$setVal3) = @val;

  Log3 $name, 4, "$iam called with $setName " . ($setVal ? $setVal : "") if ($setName !~ /^(\?|password)$/);

  if ( $setName eq 'password' ) {
    if ( $setVal ) {

      my ($passResp, $passErr) = $hash->{helper}->{passObj}->setStorePassword($name, $setVal);
      Log3 $name, 1, "$iam error: $passErr" if ($passErr);
      return "$iam $passErr" if( $passErr );

      readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, '.access_token', '', 0 );
        readingsBulkUpdateIfChanged( $hash, 'state', 'initialized');
      readingsEndUpdate($hash, 1);
      
      RemoveInternalTimer($hash, \&APIAuth);
      APIAuth($hash);
      return undef;
    }

  }

  my $ret = " password ";
  return "Unknown argument $setName, choose one of".$ret;
  
}

#########################
sub Undefine {

  my ( $hash, $arg )  = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  RemoveInternalTimer( $hash );
  readingsSingleUpdate( $hash, 'state', 'disconnected', 1 );
  return undef;
}

##########################
sub Delete {

  my ( $hash, $arg ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam ="$type $name Delete: ";
  Log3( $name, 5, "$iam called" );

  foreach my $keyx ( devspec2array('TYPE=AutomowerConnect') ) {

    delete( $defs{$keyx}->{VERSION_AMConnectTools} ) if ( defined( $defs{$keyx}->{VERSION_AMConnectTools} ) );

  }

  my ($passResp,$passErr) = $hash->{helper}->{passObj}->setDeletePassword($name);
  Log3( $name, 1, "$iam error: $passErr" ) if ($passErr);

  return;
}

##########################
sub Rename {

  my ( $newname, $oldname ) = @_;
  my $hash = $defs{$newname};
  my $type = $hash->{TYPE};

  my ( $passResp, $passErr ) = $hash->{helper}->{passObj}->setRename( $newname, $oldname );
  Log3 $newname, 2, "$newname password rename error: $passErr" if ($passErr);

  return undef;
}

#########################
sub Attr {

  my ( $cmd, $name, $attrName, $attrVal ) = @_;
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $iam = "$type $name Attr:";
  ##########
  if ( $attrName eq "disable" ) {

    if( $cmd eq "set" and $attrVal eq "1" ) {

      RemoveInternalTimer( $hash );
      readingsSingleUpdate( $hash,'state','disabled',1);
      readingsDelete( $hash, 'runningDevices' );
      Log3 $name, 3, "$iam $cmd $attrName disabled";

    } elsif( $cmd eq "del" or $cmd eq 'set' and !$attrVal ) {

      RemoveInternalTimer( $hash, \&APIAuth);
      InternalTimer( gettimeofday() + 1, \&APIAuth, $hash, 0 );
      Log3 $name, 3, "$iam $cmd $attrName enabled";

    }

  }
  ##########
  if ( $attrName eq "notifiedByMowerDevices" ) {

    if( $cmd eq "set" ) {

      setNotifyDev( $hash, 'global,' . $attrVal );
      my $paw = join( ' ', devspec2array( "TYPE=AutomowerConnect" ) );
      readingsSingleUpdate( $hash, '.associatedWith', $paw, 0 );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      setNotifyDev( $hash, 'global' );
      readingsDelete( $hash, 'runningDevices' );
      Log3 $name, 3, "$iam $cmd $attrName deleted";

    }

  }
  ##########
}
##############################################################


1;

__END__

=pod

=item helper
=item summary    Increases the number of websocket events for the module AutomowerConnect
=item summary_DE Erhöht die Zahl der Websocketevents für das Modul AutomowerConnect

=begin html

<a id="AMConnectTools" ></a>
<h3>AMConnectTools</h3>
<ul>
  <u><b>FHEM-FORUM:</b></u> <a target="_blank" href="https://forum.fhem.de/index.php/topic,131661.0.html"> AutomowerConnect</a><br>
  <br><br>
  <u><b>Introduction</b></u>
  <br><br>
  <ul>
    <li>This module increases the number of websocket events for the module AutomowerConnect if the mower activity is LEAVING, MOWING or GOING_HOME just by questioning the unoffical smartphone app API.</li>
  </ul>
  <br>
  <u><b>Requirements</b></u>
  <br><br>
  <ul>
    <li>To get access to the API use your smartphone apps username and password.</li>
  </ul>
  <br>
  <a id="AMConnectToolsDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;device name&gt; AMConnectTools &lt;email adress&gt;</code><br>
    Example:<br>
    <code>define AMCT AMConnectTools &lt;email adress&gt;</code><br>
    It has to be set a <b>password</b>. Use your smartphone app's username and password.<br>
    <code>set AMCT &lt;password&gt;</code>
    <br>
  </ul>
  <br>

  <a id="AMConnectToolsSet"></a>
  <b>Set</b>
  <ul>
    <li><a id='AMConnectTools-set-password'>password</a><br>
      <code>set &lt;name&gt; password &lt;password&gt;</code><br>
      Sets the mandatory password.</li>
    <br>
  </ul>
  <br>

  <a id="AMConnectToolsAttributes"></a>
  <b>Attributes</b>
  <ul>
    <li><a id='AMConnectTools-attr-notifiedByMowerDevices'>notifiedByMowerDevice</a><br>
      <code>attr &lt;name&gt; notifiedByMowerDevice &lt;devspec for automower devices&gt;</code><br>
      Sets the notify devices and starts increasing websocket events on first running mower's event LEAVING and stops it with the last running mower's event PARKED_IN_CS </li>

    <li><a href="disable">disable</a></li>
    <br><br>
  </ul>
  <br>


  <a id="AMConnectToolsReadings"></a>
  <b>Readings</b>
  <ul>
    <li>nextRound - time of the next API call.</li>
    <li>state - state of device</li>
    <li>token_expires_fmt - formated token expiration time</li>
  </ul>
</ul>

=end html
