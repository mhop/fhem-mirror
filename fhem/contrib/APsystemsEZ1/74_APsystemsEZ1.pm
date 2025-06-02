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
################################################################################

package FHEM::APsystemsEZ1;
my $cvsid = '$Id$';
use strict;
use warnings;
use POSIX;
use GPUtils qw(:all);
use Time::HiRes qw(gettimeofday);
use Time::Local;
my $EMPTY = q{};
my $missingModul = $EMPTY;
## no critic (ProhibitConditionalUseStatements)
eval { use Readonly; 1 } or $missingModul .= 'Readonly ';

Readonly my $APIPORT        => '8050';
Readonly my $SPACE          => q{ };
Readonly    $EMPTY          => q{};
Readonly my $MAIN_INTERVAL  => 30;
Readonly my $LONG_INTERVAL  => 600;
Readonly my $YEARSEC        => 31536000;

eval { use JSON; 1 } or $missingModul .= 'JSON ';
## use critic
require HttpUtils;

BEGIN {
    GP_Import(
        qw(
          AttrVal
          FW_ME
          SVG_FwFn
          getKeyValue
          InternalTimer
          InternalVal
          IsDisabled
          Log3
          Log
          attr
          defs
          init_done
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
          )
    );
}

GP_Export(
    qw(
      Initialize
      )
);

##############################################################
sub Initialize() {
  my ($hash) = @_;

  $hash->{DefFn}        = \&Define;
  $hash->{UndefFn}      = \&Undefine;
  $hash->{DeleteFn}     = \&Delete;
  $hash->{SetFn}        = \&Set;
  $hash->{FW_detailFn}  = \&FW_detailFn;
  $hash->{AttrFn}       = \&Attr;
  $hash->{AttrList}     = 
                          'activeArea ' .
                          'intervalMultiplier:textField-long ' .
                          'energyDecimalPlaces:0,1,2,3,4 ' .
                          'disable:1,0 ' .
                          'disabledForIntervals ' .
                          'SVG_PlotsToShow:textField-long ' .
                          $::readingFnAttributes;

  return;
}

#########################
sub Define{
  my ( $hash, $def ) = @_;
  my @val = split( "[ \t]+", $def );
  my $name = $val[0];
  my $type = $val[1];
  my $iam = "$type $name Define:";
  my $ip = '';
  my $tod = gettimeofday();

  return "$iam Cannot define $type device. Perl modul $missingModul is missing." if ( $missingModul );

  return "$iam too few parameters: define <NAME> $type <email>" if( @val < 3 );

  $ip = $val[2];

  %$hash = (%$hash,
    helper => {
      cmds                      => {
        getOutputData           => {
          lasttime              => 0,
          interval              => $MAIN_INTERVAL * 10,
          readings              => {
            p1                  => 'line1_currentPower',
            e1                  => 'line1_todayEnergy',
            te1                 => 'line1_lifeTimeEnergy',
            p2                  => 'line2_currentPower',
            e2                  => 'line2_todayEnergy',
            te2                 => 'line2_lifeTimeEnergy'
          },
        },
        getDeviceInfo           => {
          lasttime              => 0,
          interval              => $YEARSEC,
          readings              => {
            deviceId            => 'inverter_Id',
            devVer              => 'inverter_Version',
            ssid                => 'inverter_SSID',
            ipAddr              => 'inverter_IpAddress',
            minPower            => 'inverter_MinPower',
            maxPower            => 'inverter_MaxPower'
          },
        },
        getMaxPower             => {
          lasttime              => 0,
          interval              => $YEARSEC,
          readings              => {
            maxPower            => 'inverter_ActiveMaxPower'
          },
        },
        setMaxPower             => {
          lasttime              => 0,
          interval              => $YEARSEC,
          quantity              => 'p',
          readings              => {
            maxPower            => 'inverter_ActiveMaxPower'
          },
        },
        getAlarm                => {
          lasttime              => 0,
          interval              => $LONG_INTERVAL,
          readings              => {
            og                  => 'alarm_OffGrid',
            isce1               => 'alarm1_DCShortCircuitError',
            isce2               => 'alarm2_DCShortCircuitError',
            oe                  => 'alarm_OutputError'
          },
        },
        getOnOff                => {
          lasttime              => 0,
          interval              => $YEARSEC,
          readings              => {
            status              => 'inverter_Status'
          },
        },
        setOnOff                => {
          lasttime              => 0,
          interval              => $YEARSEC,
          quantity              => 'status',
          readings              => {
            status              => 'inverter_Status'
          },
        },
      },
      timeout_                  => 2,
      retry_count               => 0,
      retry_max                 => 6,
      call_delay                => 3,
      callStack                 => [
                                  'getOutputData',
                                  'getDeviceInfo',
                                  'getMaxPower',
                                  'getAlarm', 
                                  'getOnOff'
        ],
      url                       => "http://${ip}:${APIPORT}/",
      inverter                  => {
        start                   => $tod,
        stop                    => $tod,
        duration                => 0
      }
    }
  );

#  $attr{$name}{disabledForIntervals} = '{sunset_abs("HORIZON=0")}-24 00-{sunrise_abs("HORIZON=0")}' if( !defined( $attr{$name}{disabledForIntervals} ) );
  $attr{$name}{stateFormat} = 'Power' if( !defined( $attr{$name}{stateFormat} ) );
  $attr{$name}{room} = 'APsystemsEZ1' if( !defined( $attr{$name}{room} ) );
  $attr{$name}{icon} = 'inverter' if( !defined( $attr{$name}{icon} ) );
  ( $hash->{VERSION} ) = $cvsid =~ /\.pm (.*)Z/;

  readingsSingleUpdate( $hash, '.associatedWith', $attr{$name}{SVG_PlotsToShow}, 0 ) if ( defined $attr{$name}{SVG_PlotsToShow} );

  RemoveInternalTimer($hash);
  InternalTimer( gettimeofday() + 2, \&callAPI, $hash, 1);

  readingsSingleUpdate( $hash, 'state', 'defined', 1 );

  return;

}

#########################
sub FW_detailFn { 
  my ($FW_wname, $name, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $iam = "$type $name FW_detailFn:";
  return if ( !AttrVal( $name, 'SVG_PlotsToShow', 0 ) || AttrVal( $name, 'disable', 0 ) || !$init_done || !$FW_ME );

  my @plots = split( " ", AttrVal( $name, 'SVG_PlotsToShow', 0 ) );
  my $ret = "<div id='${type}_${name}_plots' ><table>";

  for my $plot ( @plots ) {

    $ret .= '<tr><td>' . SVG_FwFn( $FW_wname, $plot, "", {} ) . '</td></tr>';

  }

  $ret .= '</table></div>';
  return $ret;

}

#########################
sub callAPI {
  my ( $hash, $update ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name callAPI:";
  my @states = ('undefined', 'disabled', 'temporarily disabled', 'inactive' );
  my $tod = gettimeofday();

  if( IsDisabled( $name ) ) {

    readingsSingleUpdate( $hash, 'state', $states[ IsDisabled( $name ) ], 1 ) if ( ReadingsVal( $name, 'state', '' ) !~ /disabled|inactive/ );
    RemoveInternalTimer( $hash );
    InternalTimer( $tod + $MAIN_INTERVAL, \&callAPI, $hash, 0 );
    return;

  }

  if ( scalar @{ $hash->{helper}{callStack} } == 0 ) {

    my @cmds = qw( getDeviceInfo getMaxPower getAlarm getOnOff getOutputData );

    for ( @cmds ) {

      push @{ $hash->{helper}{callStack} }, $_ if ( ( $hash->{helper}{cmds}{$_}{lasttime} + $hash->{helper}{cmds}{$_}{interval} ) < $tod );

    }

    if ( scalar @{ $hash->{helper}{callStack} } == 0 ) {

      RemoveInternalTimer( $hash, \&callAPI );
      InternalTimer( gettimeofday() + $MAIN_INTERVAL, \&callAPI, $hash, 0 );
      return;

    }

  }

  if ( !$update && $::init_done ) {

    readingsSingleUpdate( $hash, 'state', 'initialized', 1 ) if ( $hash->{READINGS}{state}{VAL} !~ /initialized|connected/ );
    my $url = $hash->{helper}{url};
    my $timeout = $hash->{helper}{timeout_api};
    my $command = $hash->{helper}{callStack}[0];
#    Log3 $name, 1, join(" | ", @{ $hash->{helper}{callStack} } ) . "\n$url$command";
  
    ::HttpUtils_NonblockingGet( {
      url         => $url . $command,
      timeout     => $timeout,
      hash        => $hash,
      method      => 'GET',
      callback    => \&APIresponse,
      t_begin     => $tod
    } );

  } else {

    RemoveInternalTimer( $hash, \&callAPI );
    InternalTimer( gettimeofday() + $MAIN_INTERVAL, \&callAPI, $hash, 0 );

  }

  return;

}

#########################
sub APIresponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // '';
  my $call_delay = $hash->{helper}{call_delay};
  my $iam = "$type $name APIresponse:";
  my $tod = gettimeofday();
  my $duration = sprintf( "%.2f", ( $tod - $param->{t_begin} ) );

  Log3 $name, 4, "$iam response time ". $duration . ' s';
  Log3 $name, 4, "$iam \$statuscode >$statuscode< \$err >$err< \$param->url $param->{url}\n\$data >$data<\n";

  if ( !$err && $statuscode == 200 && $data ) {

    my $result = eval { decode_json( $data ) };
    if ($@) {

      Log3 $name, 2, "$iam JSON error [ $@ ]";
      readingsSingleUpdate( $hash, 'state', 'error JSON', 1 );

    } else {

      if ( $hash->{READINGS}{state}{VAL} ne 'connected' ) {

        $hash->{helper}{inverter}{start} = $tod;
        readingsSingleUpdate( $hash, 'state', "connected", 1 );

      }

      $hash->{helper}{inverter}{duration} = $tod - $hash->{helper}{inverter}{start};

      my $cmd = $hash->{helper}{callStack}[0];
      $cmd = $1 if ( $cmd =~ /(.*)\?/ );
      $hash->{helper}->{response}{$cmd} = $result;

      if ( $result->{message} eq 'SUCCESS' ) {

        $hash->{helper}{cmds}{$cmd}{lasttime} = $tod;

        readingsBeginUpdate($hash);

          for  my $ky ( keys %{ $result->{data} } ) {

            if ( "$cmd$ky" =~ /getOutputDatap(1|2)|MaxPower/ ) {

              readingsBulkUpdateIfChanged( $hash, $hash->{helper}{cmds}{$cmd}{readings}{$ky}, $result->{data}{$ky} );

            } elsif ( "$cmd" =~ /OnOff/ ) {

              readingsBulkUpdateIfChanged( $hash, $hash->{helper}{cmds}{$cmd}{readings}{$ky}, ( $result->{data}{$ky} ? 'off' : 'on' ) );

            } elsif ( "$cmd" =~ /Alarm/ ) {

              readingsBulkUpdateIfChanged( $hash, $hash->{helper}{cmds}{$cmd}{readings}{$ky}, ( $result->{data}{$ky} ? 'alarm' : 'normal' ) );

            } elsif ( "$cmd$ky" =~ /getOutputDatae(1|2)/ ) {

              readingsBulkUpdateIfChanged( $hash, $hash->{helper}{cmds}{$cmd}{readings}{$ky}, sprintf( "%.1f", $result->{data}{$ky} ) );

            } elsif ( "$cmd$ky" =~ /getOutputDatate(1|2)/ ) {

              readingsBulkUpdate( $hash, $hash->{helper}{cmds}{$cmd}{readings}{$ky}, sprintf( "%.1f", $result->{data}{$ky} ), 0 );

            } else {

              readingsBulkUpdate( $hash, $hash->{helper}{cmds}{$cmd}{readings}{$ky}, $result->{data}{$ky}, 0 );

            }

          }

          if ( $hash->{helper}{callStack}[0] eq 'getOutputData' ) {

            readingsBulkUpdate( $hash, 'inverter_OnlineTime', int( $hash->{helper}{inverter}{duration} / 3600 ) , 0 );
            readingsBulkUpdateIfChanged( $hash, 'Power', $result->{data}{p1} + $result->{data}{p2} );
            readingsBulkUpdateIfChanged( $hash, 'TodayEnergy', sprintf( "%.".AttrVal( $name, 'energyDecimalPlaces', 1 )."f", $result->{data}{e1} + $result->{data}{e2} ) );
            readingsBulkUpdateIfChanged( $hash, 'LifeTimeEnergy', sprintf( "%.1f", $result->{data}{te1} + $result->{data}{te2} ) );
            readingsBulkUpdate( $hash, 'PowerDensity', int( ( $result->{data}{p1} + $result->{data}{p2} ) / AttrVal( $name, 'activeArea', 4.10592 ) ), 0 ) if ( AttrVal( $name, 'activeArea', 0 ) );

          }

        readingsEndUpdate($hash, 1);

        shift @{ $hash->{helper}{callStack} };

        if ( scalar @{ $hash->{helper}{callStack} } ) {

          RemoveInternalTimer( $hash, \&calAPI );
          InternalTimer( $tod + $call_delay, \&callAPI, $hash, 0 );
          return;

        }

        RemoveInternalTimer( $hash, \&calAPI );
        InternalTimer( $tod + $MAIN_INTERVAL, \&callAPI, $hash, 0 );
        return;

      }

      $hash->{helper}{retry_count}++;
      
      if ( $hash->{helper}{retry_count} > $hash->{helper}{retry_max} - 1 ) {

        shift @{ $hash->{helper}{callStack} };
        $hash->{helper}{retry_count} = 0;

        if ( scalar @{ $hash->{helper}{callStack} } ) {

          RemoveInternalTimer( $hash, \&calAPI );
          InternalTimer( $tod + $call_delay, \&callAPI, $hash, 0 );
          return;

        }

        RemoveInternalTimer( $hash, \&calAPI );
        InternalTimer( $tod + ( $result->{data}{p1} + $result->{data}{p2} < 1 ? $LONG_INTERVAL : $MAIN_INTERVAL ), \&callAPI, $hash, 0 );
        return;

      }

    }

  } elsif ( !$statuscode && !$data && $err =~ /\(113\)$|timed out/ ) {

    if ( $hash->{READINGS}{state}{VAL} ne 'disconnected' ) {

      $hash->{helper}{inverter}{stop} = $tod;
      $hash->{helper}{inverter}{duration} = $tod - $hash->{helper}{inverter}{start};
      readingsSingleUpdate( $hash, 'state', "disconnected", 1 );

    }

    RemoveInternalTimer( $hash, \&callAPI );
    InternalTimer( $tod + $LONG_INTERVAL, \&callAPI, $hash, 0 );
    return;

  }

  readingsSingleUpdate( $hash, 'state', "error", 1 );
  Log3 $name, 1, "$iam \$statuscode >$statuscode< \$err >$err< \$param->url $param->{url}\n\$data >$data<\n";

  $hash->{helper}{retry_count}++;
  
  if ( $hash->{helper}{retry_count} > $hash->{helper}{retry_max} ) {

    CommandAttr( $hash, "$name disable 1" );
    $hash->{helper}{retry_count} = 0;

  }

  RemoveInternalTimer( $hash, \&callAPI );
  InternalTimer( $tod + $MAIN_INTERVAL, \&callAPI, $hash, 0 );
  my $txt = AttrVal( $name, 'disable', $EMPTY ) ? "$iam: Device is disabled now." : "$iam failed, retry in $MAIN_INTERVAL seconds.";
  Log3 $name, 1, $txt;
  return;

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

  Log3 $name, 4, "$iam called with $setName";

  my $minpow = ReadingsNum( $name, 'minPower', 30 );
  my $maxpow = ReadingsNum( $name, 'maxPower', 800 );
  $setVal = 0 if ( defined( $setVal ) && $setVal eq 'on' );
  $setVal = 1 if ( defined( $setVal ) && $setVal eq 'off' );

  if ( $setName eq 'setOnOff' && ( $setVal == 0 || $setVal == 1 ) || $setName eq 'setMaxPower' && $setVal >= $minpow && $setVal <= $maxpow ) {

    my $cmd = $setName . '?' . $hash->{helper}{cmds}{$setName}{quantity} . '=' . $setVal;
    unshift @{ $hash->{helper}{callStack} }, $cmd;
#    Log3 $name, 1, "$iam called with $cmd | ".join(" | ", @{ $hash->{helper}{callStack} } );
    return;

  } elsif ( $setName eq 'getUpdate') {

    my @cmds = qw( getDeviceInfo getMaxPower getAlarm getOnOff getOutputData );
    push @{ $hash->{helper}{callStack} }, @cmds;
    return;

  }
  my $ret = ' setMaxPower:selectnumbers,' . $minpow . ',10,' . $maxpow . ',0,lin setOnOff:on,off getUpdate:noArg ';
  return "Unknown argument $setName, choose one of".$ret;
  
}

#########################
sub Undefine {

  my ( $hash, $arg )  = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  RemoveInternalTimer( $hash );
  readingsSingleUpdate( $hash, 'state', 'undefined', 1 );
  return;
}

##########################
sub Delete {

  my ( $hash, $arg ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam ="$type $name Delete: ";
  Log3( $name, 5, "$iam called" );

  return;
}

##########################
sub Attr {

  my ( $cmd, $name, $attrName, $attrVal ) = @_;
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $iam = "$type $name Attr:";
  ##########
  if ( $attrName eq 'disable' ) {

    if( $cmd eq "set" and $attrVal eq "1" ) {

      readingsSingleUpdate( $hash,'state','disabled',1);
      Log3 $name, 3, "$iam $cmd $attrName disabled";

    } elsif( $cmd eq "del" or $cmd eq 'set' and !$attrVal ) {

      RemoveInternalTimer( $hash, \&callAPI);
      InternalTimer( gettimeofday() + 1, \&callAPI, $hash, 0 );
      Log3 $name, 3, "$iam $cmd $attrName enabled";

    }

    return;

  ##########
  } elsif ( $attrName eq 'SVG_PlotsToShow' ) {

    readingsSingleUpdate( $hash, '.associatedWith', $attrVal, 0 ) if ( $cmd eq 'set' && $attrVal );
    delete $hash->{READINGS}{'.associatedWith'} if ( $cmd eq 'del' );
    return;

  ##########
  } elsif ( $attrName eq 'intervalMultiplier' ) {

    if( $cmd eq 'set' ) {

      my @ivals = split( /\R/, $attrVal );

      for my $ival (@ivals) {

        if ( my ($cm, $val) = $ival =~ /^(getDeviceInfo|getMaxPower|getAlarm|getOnOff|getOutputData)=(\d+)$/ ) {

          $hash->{helper}{cmds}{$cm}{interval} = $MAIN_INTERVAL * $val;

        } else {

          Log3 $name, 1, "$iam $cmd $attrName wrong syntax for $ival, default is used.";

        }

      }

    } elsif( $cmd eq 'del' ) {

      my @ivals = qw( getDeviceInfo=1051200 getMaxPower=1051200 getAlarm=20 getOnOff=1051200 getOutputData=10 );

    for my $ival ( @ivals ) {

        if ( my ($cm, $val) = $ival =~ /^(getDeviceInfo|getMaxPower|getAlarm|getOnOff|getOutputData)=(\d+)$/ ) {

          $hash->{helper}{cmds}{$cm}{interval} = $MAIN_INTERVAL * $val;

        }

      }

    }

    Log3 $name, 3, "$iam $cmd $attrName to default interval multiplier.";

    return;

  }

  return;

}
##############################################################


1;

__END__

=pod

=item helper
=item summary    Serve the APsystems EZ1 inverter API
=item summary_DE Bedient die API des APsystems EZ1 Wechselrichters

=begin html

<a id="APsystemsEZ1" ></a>
<h3>APsystemsEZ1</h3>
<ul>
  <u><b>FHEM-FORUM:</b></u> <a target="_blank" href="https://forum.fhem.de/index.php?topic=141576.0"> APsystemsEZ1</a><br>
  <br><br>
  <u><b>Introduction</b></u>
  <br><br>
  <ul>
    <li>The module serves the APsystem inverter EZ1. The local API is called periodically.</li>
  </ul>
  <br>
  <u><b>Requirements</b></u>
  <br><br>
  <ul>
    <li>To get access to the API use the APsystem EasyPower app in direct mode via WLAN and activate the local mode and get the IP address.</li>
  </ul>
  <br>
  <a id="APsystemsEZ1Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;device name&gt; APsystemsEZ1 &lt;inverter ip address&gt;</code><br>
    Example:<br>
    <code>define EZ1 APsystemsEZ1 &lt;ip address&gt;</code><br>
    <br>
  </ul>
  <br>

  <a id="APSystemsEZ1Set"></a>
  <b>Set</b>
  <ul>
    <li><a id='APsystemsEZ1-set-setMaxPower'>setMaxPower</a><br>
      <code>set &lt;name&gt; setMaxPower &lt;integer value between inverter_MinPower and inverter_MaxPower&gt;</code><br>
      Sets the active maximum power.</li>
    <br>

    <li><a id='APsystemsEZ1-set-setOnOff'>setOnOff</a><br>
      <code>set &lt;name&gt; setOnOff &lt;on|off&gt;</code><br>
      Switches the inverter on or off.</li>
    <br>

    <li><a id='APsystemsEZ1-set-getUpdate'>getUpdate</a><br>
      <code>set &lt;name&gt; getUpdate</code><br>
      Updates all values the inverter provides.</li>
    <br>

  </ul>
  <br>

  <a id="APsystemsEZ1Attributes"></a>
  <b>Attributes</b>
  <ul>
    <li><a id='APsystemsEZ1-attr-activeArea'>activeArea</a><br>
      <code>attr &lt;name&gt; activeArea &lt;active cell area in square meter&gt;</code><br>
      Calculates the power density if set.</li>

    <li><a id='APsystemsEZ1-attr-intervalMultiplier'>intervalMultiplier</a><br>
      <code>attr &lt;name&gt; intervalMultiplier &lt;line break separated pairs of endpoint=multiplier&gt;</code><br>
      Changes the default polling interval for each endpoint based on the main interval of 30 s.<br>
      Defaults:
      <ul>
      <code>
        getDeviceInfo=1051200<br>
        getMaxPower=1051200<br>
        getAlarm=20<br>
        getOnOff=1051200<br>
        getOutputData=10<br>
      </code>
      </ul>
    </li>

    <li><a id='APsystemsEZ1-attr-SVG_PlotsToShow'>SVG_PlotsToShow</a><br>
      <code>attr &lt;name&gt; SVG_PlotsToShow &lt;plot name1&gt; &lt;plot name2&gt; &lt;plot name3&gt; ...</code><br>
      Show plots in detail view, space separated list of plot names.</li>

    <li><a href="disable">disable</a></li>

    <li><a href="disabledForIntervals">disabledForIntervals</a><br>
    Example: <code>attr &lt;name&gt; disabledForIntervals {sunset_abs('HORIZON=0')}-24 00-{sunrise_abs('HORIZON=0')}</code><br>
    Disables api calls between sunset and sunrise.</li>
    <br><br>
  </ul>
  <br>


  <a id="APsystemsEZ1Readings"></a>
  <b>Readings</b>
  <ul>
    <li>There ist a reading for each data element as described in the APsystems <a target='_blank' href='https://file.apsystemsema.com:8083/apsystems/apeasypower/resource/APsystems%20EZ1%20Local%20API%20User%20Manual.pdf' >EZ1 Local API User Manual</a>.</li>
  </ul>
</ul>

=end html
