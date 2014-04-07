
# $Id$

package main;

use strict;
use warnings;

use vars qw($FW_ME);

sub
Color_Initialize()
{
  FHEM_colorpickerInit();
}

sub
FHEM_colorpickerInit()
{
  $data{webCmdFn}{colorpicker} = "FHEM_colorpickerFn";
  $data{FWEXT}{colorpicker}{SCRIPT} = "/jscolor/jscolor.js";
}

sub
FHEM_colorpickerFn($$$)
{
  my ($FW_wname, $d, $FW_room, $cmd, $values) = @_;

  my @args = split("[ \t]+", $cmd);

  return undef if($values !~ m/^colorpicker,(.*)$/);
  my ($mode) = ($1);
  $mode = "RGB" if( !defined($mode) );
  my $srf = $FW_room ? "&room=$FW_room" : "";
  my $cv = CommandGet("","$d $cmd");
  $cmd = "" if($cmd eq "state");
  if( $args[1] ) {
    my $c = "cmd=set $d $cmd$srf";

    return '<td align="center">'.
             "<div onClick=\"FW_cmd('$FW_ME?XHR=1&$c')\" style=\"width:32px;height:19px;".
             'border:1px solid #fff;border-radius:8px;background-color:#'. $args[1] .';"></div>'.
           '</td>' if( AttrVal($FW_wname, "longpoll", 1));

    return '<td align="center">'.
             "<a href=\"$FW_ME?$c\">".
               '<div style="width:32px;height:19px;'.
               'border:1px solid #fff;border-radius:8px;background-color:#'. $args[1] .';"></div>'.
             '</a>'.
           '</td>';
  } elsif(AttrVal($d,"realtimePicker",0)) {
    my $c = "$FW_ME?XHR=1&cmd=set $d $cmd %$srf";
    my $ci = $c;
    $ci = "$FW_ME?XHR=1&cmd=set $d $cmd % : transitiontime 0 : noUpdate$srf" if($defs{$d}->{TYPE} eq "HUEDevice");
    return '<td align="center">'.
             "<input maxlength='6' size='6' id='colorpicker.$d-RGB' class=\"color {pickerMode:'$mode',pickerFaceColor:'transparent',pickerFace:3,pickerBorder:0,pickerInsetColor:'red',command:'$ci',onImmediateChange:'colorpicker_setColor(this)'}\" value='$cv' onChange='colorpicker_setColor(this,\"$mode\",\"$c\")'>".
           '</td>';
  } else {
    my $c = "$FW_ME?XHR=1&cmd=set $d $cmd %$srf";
    return '<td align="center">'.
             "<input maxlength='6' size='6' id='colorpicker.$d-RGB' class=\"color {pickerMode:'$mode',pickerFaceColor:'transparent',pickerFace:3,pickerBorder:0,pickerInsetColor:'red'}\" value='$cv' onChange='colorpicker_setColor(this,\"$mode\",\"$c\")'>".
           '</td>';
  }
}

my %dim_values = (
   0 => "dim06%",
   1 => "dim12%",
   2 => "dim18%",
   3 => "dim25%",
   4 => "dim31%",
   5 => "dim37%",
   6 => "dim43%",
   7 => "dim50%",
   8 => "dim56%",
   9 => "dim62%",
  10 => "dim68%",
  11 => "dim75%",
  12 => "dim81%",
  13 => "dim87%",
  14 => "dim93%",
);
sub
Color_devStateIcon($)
{
  my ($rgb) = @_;

  my @channels = Color::RgbToChannels($rgb,3);
  my $dim = Color::ChannelsToBrightness(@channels);
  my $percent = $dim->{bri};
  my $RGB = Color::ChannelsToRgb(@{$dim->{channels}});

  return ".*:off:toggle"
         if( $rgb eq "off" || $rgb eq "000000" || $percent == 0 );

  $percent = 100 if( $rgb eq "on" );

  my $s = $dim_values{int($percent/7)};
  $s="on" if( $percent eq "100" );

  return ".*:$s@#$RGB:toggle" if( $percent < 100 );
  return ".*:on@#$rgb:toggle";
}

package Color;
require Exporter;
our @ISA = qw(Exporter);
our  %EXPORT_TAGS = (all => [qw(RgbToChannels ChannelsToRgb ChannelsToBrightness BrightnessToChannels)]);
Exporter::export_tags('all');

sub
RgbToChannels($$) {
  my ($rgb,$numChannels) = @_;
  my @channels = ();
  foreach my $channel (unpack("(A2)[$numChannels]",$rgb)) {
    push @channels,hex($channel);
  }
  return @channels;
}

sub
ChannelsToRgb(@) {
  my @channels = @_;
  return sprintf("%02X" x @_, @_);
}

sub
ChannelsToBrightness(@) {
  my (@channels) = @_;

  my $max = 0;
  foreach my $value (@channels) {
    $max = $value if ($max < $value);
  }

  my @bri = ();
  if( $max == 0) {
    @bri = (0) x @channels;
  } else {
    my $norm = 255/$max;
    foreach my $value (@channels) {
      push @bri,int($value*$norm);
    }
  }

  return {
    bri => int($max/2.55),
    channels  => \@bri,
  }
}

sub
BrightnessToChannels($) {
  my $arg = shift;
  my @channels = ();
  my $bri = $arg->{bri};
  foreach my $value (@{$arg->{channels}}) {
    push @channels,$value*$bri/100;
  }
  return @channels;
}


# COLOR SPACE: HSV & RGB(dec)
# HSV > h=float(0, 1), s=float(0, 1), v=float(0, 1)
# RGB > r=int(0, 255), g=int(0, 255), b=int(0, 255)
#

sub
rgb2hsv($$$) {
  my( $r, $g, $b ) = @_;
  my( $h, $s, $v );

  my $M = ::maxNum( $r, $g, $b );
  my $m = ::minNum( $r, $g, $b );
  my $c = $M - $m;

  if ( $c == 0 ) {
    $h = 0;
  } elsif ( $M == $r ) {
    $h = ( 60 * ( ( $g - $b ) / $c ) % 360 ) / 360;
  } elsif ( $M == $g ) {
    $h = ( 60 * ( ( $b - $r ) / $c ) + 120 ) / 360;
  } elsif ( $M == $b ) {
    $h = ( 60 * ( ( $r - $g ) / $c ) + 240 ) / 360;
  }

  if ( $M == 0 ) {
    $s = 0;
  } else {
    $s = $c / $M;
  }

  $v = $M;

  return( $h,$s,$v );
}

sub
hsv2rgb($$$) {
  my ( $h, $s, $v ) = @_;
  my $r = 0.0;
  my $g = 0.0;
  my $b = 0.0;

  if ( $s == 0 ) {
    $r = $v;
    $g = $v;
    $b = $v;
  } else {
    my $i = int( $h * 6.0 );
    my $f = ( $h * 6.0 ) - $i;
    my $p = $v * ( 1.0 - $s );
    my $q = $v * ( 1.0 - $s * $f );
    my $t = $v * ( 1.0 - $s * ( 1.0 - $f ) );
    $i = $i % 6;

    if ( $i == 0 ) {
      $r = $v;
      $g = $t;
      $b = $p;
    } elsif ( $i == 1 ) {
      $r = $q;
      $g = $v;
      $b = $p;
    } elsif ( $i == 2 ) {
      $r = $p;
      $g = $v;
      $b = $t;
    } elsif ( $i == 3 ) {
      $r = $p;
        $g = $q;
      $b = $v;
    } elsif ( $i == 4 ) {
      $r = $t;
      $g = $p;
      $b = $v;
    } elsif ( $i == 5 ) {
      $r = $v;
      $g = $p;
      $b = $q;
    }
  }

  return( $r,$g,$b );
}


# COLOR SPACE: HSB & RGB(dec)
# HSB > h=int(0, 65535), s=int(0, 255), b=int(0, 255)
# RGB > r=int(0, 255), g=int(0, 255), b=int(0, 255)
#

sub
hsb2rgb ($$$) {
    my ( $h, $s, $bri ) = @_;

    my $h2   = $h / 65535.0;
    my $s2   = $s / 255.0;
    my $bri2 = $bri / 255.0;

    my @rgb = Color::hsv2rgb( $h2, $s2, $bri2 );
    my $r   = int( $rgb[0] * 255 );
    my $g   = int( $rgb[1] * 255 );
    my $b   = int( $rgb[2] * 255 );

    return ( $h, $s, $bri );
}

sub
rgb2hsb ($$$) {
    my ( $r, $g, $b ) = @_;

    my $r2 = $r / 255.0;
    my $g2 = $g / 255.0;
    my $b2 = $b / 255.0;

    my @hsv = Color::rgb2hsv( $r2, $g2, $b2 );
    my $h   = int( $hsv[0] * 65535 );
    my $s   = int( $hsv[1] * 255 );
    my $bri = int( $hsv[2] * 255 );

    return ( $h, $s, $bri );
}


# COLOR SPACE: RGB(hex) & HSV
# RGB > r=hex(00, FF), g=hex(00, FF), b=hex(00, FF)
# HSV > h=float(0, 1), s=float(0, 1), v=float(0, 1)
#

sub
hex2hsv($) {
    my ($hex) = @_;
    my @rgb = Color::hex2rgb($hex);

    return Color::rgb2hsv( $rgb[0], $rgb[1], $rgb[2] );
}

sub
hsv2hex($$$) {
    my ( $h, $s, $v ) = @_;
    my @rgb = Color::hsv2rgb( $h, $s, $v );

    return Color::rgb2hex( $rgb[0], $rgb[1], $rgb[2] );
}


# COLOR SPACE: RGB(hex) & HSB
# RGB > r=hex(00, FF), g=hex(00, FF), b=hex(00, FF)
# HSB > h=int(0, 65535), s=int(0, 255), b=int(0, 255)
#

sub
hex2hsb($) {
    my ($hex) = @_;
    my @rgb = Color::hex2rgb($hex);

    return Color::rgb2hsb( $rgb[0], $rgb[1], $rgb[2] );
}

sub
hsb2hex($$$) {
    my ( $h, $s, $b ) = @_;
    my @rgb = Color::hsb2rgb( $h, $s, $b );

    return Color::rgb2hex( $rgb[0], $rgb[1], $rgb[2] );
}


# COLOR SPACE: RGB(hex) & RGB(dec)
# hex > r=hex(00, FF), g=hex(00, FF), b=hex(00, FF)
# dec > r=int(0, 255), g=int(0, 255), b=int(0, 255)
#

sub
hex2rgb($) {
    my ($hex) = @_;
    if ( uc($hex) =~ /^(..)(..)(..)$/ ) {
        my ( $r, $g, $b ) = ( hex($1), hex($2), hex($3) );

        return ( $r, $g, $b );
    }
}

sub
rgb2hex($$$) {
    my ( $r, $g, $b ) = @_;
    my $return = sprintf( "%2.2X%2.2X%2.2X", $r, $g, $b );

    return uc($return);
}

1;
