# $Id$
##############################################################################
#
##############################################################################

package FHEM::Volumio;    ## no critic

use strict;
use warnings;
use JSON qw( decode_json );
use Data::Dumper;

use GPUtils qw(GP_Import GP_Export);

## Import der FHEM Funktionen

BEGIN {
    # Import from main context
    GP_Import(
        qw( attr
            AttrVal
            BlockingInformParent
            CommandDefine
            CommandDeleteReading
            Debug
            defs
            HttpUtils_NonblockingGet
            init_done
            InternalTimer
            IsDisabled
            json2reading
            Log3
            parseParams
            readingFnAttributes
            readingsBeginUpdate
            readingsBulkUpdate
            readingsEndUpdate
            readingsSingleUpdate
            ReadingsVal
            RemoveInternalTimer )
    );
}

#-- Export to main context with different name
GP_Export(qw( Initialize ));

sub Initialize {
    my ($hash) = @_;

    $hash->{DefFn}   = \&Define;
    $hash->{UndefFn} = \&Undef;
    $hash->{SetFn}   = \&Set;
#    $hash->{AttrFn}  = \&Attr;
    $hash->{AttrList} =
          'disable:1,0 '
        . 'disabledForIntervals '
        . $readingFnAttributes;

    return;
}

sub Discover {
  my $hash = shift;
  
  unless $init_done {
     InternalTimer(time()+3, \&Discover, $hash, 0);  
  } else {
    my $param = {
     url        => "http://volumio.local/api/v1/getzones",
     timeout    => 5,
     hash       => $hash,                                                                                
     method     => "GET",
     callback   => \&ParseGetzones
     };
    HttpUtils_NonblockingGet($param);

    sub ParseGetzones{
      my ($param, $err, $data) = @_;
      if ($err ne '') {
        readingsSingleUpdate( $param->{hash}, 'state', $err, 0 );
      } else {
        json2reading($param->{hash}{NAME},$data);
        my $json_object = decode_json($data);
        for my $item( @{$json_object->{zones}} ){
          my $n = $item->{name};
          my $i = $item->{id}; $i =~ s/-//g;
          my $h = $item->{host};
          my $v = $item->{state}->{volume};
          my $t = $item->{type};
          my $defString = "$n"."_$i Volumio host=$h volume=$v type=$t";
          CommandDefine(undef,$defString);
        }
      }
    }
  }
  return;
}

sub Define {
  my $hash = shift;
  my $def  = shift;
  my $name = $hash->{NAME};

  my ( $arrayref, $hashref ) = parseParams($def);
  my @a = @{$arrayref};
  my %h = %{$hashref};

  if (exists $h{host}) {
     $hash->{host} = $h{host};
     my $param = {
     name       => $hash->{NAME},
     type       => $h{type},
     volume     => $h{volume},
     url        => "$h{host}/api/v1/getSystemVersion",
     timeout    => 5,
     hash       => $hash,
     method     => "GET",
     callback   => sub {
                    my ($param, $err, $data) = @_;
                    my $n = $param->{name};
                    my $h = $param->{hash};
                    $h->{DEF} = "host=$h{host}";
                    #$h->{TEMPORARY} = 1;
                    json2reading($n,$data);
                    readingsBeginUpdate($h);
                    readingsBulkUpdate($h,'type',$param->{type});
                    readingsBulkUpdate($h,'volume',$param->{volume});
                    readingsEndUpdate($h, 0);
                   }
     };
     HttpUtils_NonblockingGet($param);
  } else {
     InternalTimer(time()+3, \&Discover, $hash, 0);
  }

  return;
}

sub Undef {
  my $hash = shift;
  RemoveInternalTimer($hash);
  return;
}

sub Set {
  my $hash = shift;
  my $name = shift;
  my $cmd  = shift;
  my $val  = shift; $val //= '';

  return "Unknown argument $cmd, choose one of volume mute:noArg unmute:noArg "
        ."play:noArg pause:noArg play/pause:noArg stop:noArg" if ($cmd eq '?');

my $host = $hash->{host};

  my $url  = "$host/api/v1/commands/?cmd=";
     $url .= "volume&volume=mute"   if(lc($cmd) eq 'mute');
     $url .= "volume&volume=unmute" if(lc($cmd) eq 'unmute');
     $url .= "volume&volume=$val"   if(lc($cmd) eq 'volume');
     $url .= "play"                 if(lc($cmd) eq 'play');
     $url .= "pause"                if(lc($cmd) eq 'pause');
     $url .= "toggle"               if(lc($cmd) eq 'play/pause');
     $url .= "stop"                 if(lc($cmd) eq 'stop');

  my $param = {
   url        => $url,
   timeout    => 5,
   hash       => $hash,                                                                                
   method     => "GET",
   callback   => \&ParseSetResponse,
   cmd        => $cmd,
   val        => $val,
   };
  HttpUtils_NonblockingGet($param);

  sub ParseSetResponse{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    if ($err ne '') {
      readingsSingleUpdate( $param->{hash}, 'state', $err, 1 );
    } else {
      if ($param->{cmd} eq 'volume' && $param->{val} !~ m/mute/) {
         readingsSingleUpdate($hash, 'volume', $param->{val}, 0) 
      }
    }
  }
}

1;

################################################################################
#
# Documentation
#
################################################################################

=pod

=encoding utf8

=item helper
=item summary Control Volumio Media Player
=item summary_DE Steuerung des Volumio Media Player

=begin html

<a name="Volumio" id="Volumio"></a>
<h3>WUup</h3>
<ul>
    <a name="Volumiodefine" id="Volumiodefine"></a>
    <b>Define</b>
</ul>

=end html

=cut
