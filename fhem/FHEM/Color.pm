
# $Id$

package main;

use strict;
use warnings;

use vars qw(%defs);
use vars qw($FW_ME);
sub Log3($$$);

sub
Color_Initialize()
{
  #FHEM_colorpickerInit();
}

sub
FHEM_colorpickerInit()
{
  #$data{FWEXT}{colorpicker}{SCRIPT} = "/jscolor/jscolor.js";
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
# RGB > r=float(0, 1), g=float(0, 1), b=float(0, 1)
#

sub
rgb2hsv($$$) {
  my( $r, $g, $b ) = @_;
  my( $h, $s, $v );

  main::Log3 undef, 1, "Color::rgb2hsv value our of range [$r,$g,$b]. should be in 0..1." if( $r > 1 || $g > 1 || $b > 1 );
  $r /= 255.0 if( $r > 1 );
  $g /= 255.0 if( $g > 1 );
  $b /= 255.0 if( $b > 1 );

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

  main::Log3 undef, 1, "Color::hsv2rgb value our of range [$h,$s,$v]. should be in 0..1." if( $h > 1 || $s > 1 || $v > 1 );
  $h /= 356.0 if( $h > 1 );
  $s /= 100.0 if( $s > 1 );
  $v /= 100.0 if( $v > 1 );

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

    return ( $r, $g, $b );
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
    my ($r,$g,$b) = Color::hsv2rgb( $h, $s, $v );

    return Color::rgb2hex( $r*255, $g*255, $b*255 );
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

sub
ct2rgb($)
{
  my ($ct) = @_;

  # calculation from http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code

  # kelvin -> mired
  $ct = 1000000/$ct if( $ct > 1000 );

  # adjusted by 1000K
  my $temp = (1000000/$ct)/100 + 10;

  my $r = 0;
  my $g = 0;
  my $b = 0;

  $r = 255;
  $r = 329.698727446 * ($temp - 60) ** -0.1332047592 if( $temp > 66 );
  $r = 0 if( $r < 0 );
  $r = 255 if( $r > 255 );

  if( $temp <= 66 ) {
    $g = 99.4708025861 * log($temp) - 161.1195681661;
  } else {
    $g = 288.1221695283 * ($temp - 60) ** -0.0755148492;
  }
  $g = 0 if( $g < 0 );
  $g = 255 if( $g > 255 );

  $b = 255;
  $b = 0 if( $temp <= 19 );
  if( $temp < 66 ) {
    $b = 138.5177312231 * log($temp-10) - 305.0447927307;
  }
  $b = 0 if( $b < 0 );
  $b = 255 if( $b > 255 );

  return( $r, $g, $b );
}


# COLOR SPACE: xyY & RGB(dec)
# xyY > h=float(0, 1), s=float(0, 1), v=float(0, 1)
# RGB > r=float(0, 1), g=float(0, 1), b=float(0, 1)
#

sub
xyY2rgb($$$)
{
  # calculation from http://www.brucelindbloom.com/index.html
  my ($x,$y,$Y) = @_;
#Log 3, "xyY:". $x . " " . $y ." ". $Y;

  my $r = 0;
  my $g = 0;
  my $b = 0;

  if( $y > 0 ) {
    my $X = $x * $Y / $y;
    my $Z = (1 - $x - $y)*$Y / $y;

    if( $X > 1
        || $Y > 1
        || $Z > 1 ) {
      my $f = main::maxNum($X,$Y,$Z);
      $X /= $f;
      $Y /= $f;
      $Z /= $f;
    }
#Log 3, "XYZ: ". $X . " " . $Y ." ". $Y;

    $r =  0.7982 * $X + 0.3389 * $Y - 0.1371 * $Z;
    $g = -0.5918 * $X + 1.5512 * $Y + 0.0406 * $Z;
    $b =  0.0008 * $X + 0.0239 * $Y + 0.9753 * $Z;

    if( $r > 1
        || $g > 1
        || $b > 1 ) {
      my $f = main::maxNum($r,$g,$b);
      $r /= $f;
      $g /= $f;
      $b /= $f;
    }
#Log 3, "rgb: ". $r . " " . $g ." ". $b;

    #$r *= 255;
    #$g *= 255;
    #$b *= 255;
  }

  return( $r, $g, $b );
}

# COLOR SPACE: xyY & RGB(hex)
# xyY > h=float(0, 1), s=float(0, 1), v=float(0, 1)
# RGB > r=hex(00, FF), g=hex(00, FF), b=hex(00, FF)
sub
xyY2hex($$$) {
  my ($x,$y,$Y) = @_;
    my ($r,$g,$b) = Color::xyY2rgb( $x, $y, $Y );

    return Color::rgb2hex( $r*255, $g*255, $b*255 );
}


sub
devStateIcon($$@)
{
  my($hash,$type,$rgb,$pct,$onoff) = @_;
  $hash = $::defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );

  my $name = $hash->{NAME};

  if( $type && $type eq "switch" ) {
    my $value;
    if( $onoff ) {
      $value = ::ReadingsVal($name,$onoff,undef);
      $value = ::CommandGet("","$name $onoff") if( !$value );
      $value = "on" if( $value && $value eq "1" );
      $value = "off" if( $value && $value eq "0" );

    } else {
      $value = ::Value($name);
    }

    my $s = $value;

    return ".*:light_question" if( !$s );
    return ".*:$s:toggle";

  } elsif( $type && $type eq "dimmer" ) {
    my $percent;
    if( $pct ) {
      $percent = ::ReadingsVal($name,$pct, undef);
      $percent = ::CommandGet("","$name $pct") if( !defined($percent) );

    } else {
      $percent = ::Value($name);
    }

    return ".*:light_question" if( !defined($percent) );

    return ".*:on:toggle" if( $percent eq "on" );
    return ".*:off:toggle" if( $percent eq "off" );

    $percent =~ s/[^\d]//g if( $percent );

    my $s = $dim_values{int($percent/7)};
    $s="off" if( $percent eq "0" );
    $s="on" if( $percent eq "100" );

    return ".*:$s:toggle";

  } elsif( $type && $type eq "rgb" ) {
    my $value;
    if( $rgb ) {
      $value = ::ReadingsVal($name,$rgb,undef);
      $value = ::CommandGet("","$name $rgb") if( !$value );

    } else {
      $value = ::Value($name);

    }

    return ".*:light_question" if( !defined($value) );
    return ".*:on:toggle" if( $value eq "on" );
    return ".*:off:toggle" if( $value eq "off" );

    my $s = 'on';
    if( $pct ) {
      my $percent = ::ReadingsVal($name,$pct, undef);
      $percent = ::CommandGet("","$name $pct") if( !$percent );
      return ".*:off:toggle" if( $percent eq "off" );
      $percent = 100 if( $percent eq "on" );
      $s = $dim_values{int($percent/7)} if( $percent && $percent < 100 );
    }

    return ".*:$s@#$value:toggle";
  }

  return undef;
}

# see: http://forum.fhem.de/index.php/topic,30128.msg261174.html#msg261174
sub pahColor {
  my ($starttemp,$midtemp,$endtemp,$temp,$colors,$opacity) = @_;

  my @models = ([   0,255,255 ,
                   30, 80,255 ,
                   40,255, 60 ,
                  160,128, 10 ,
                  255, 69,  0 ],

                [   0,255,255 ,
                  120,120,120 ,
                   40,255, 60 ,
                  255,255,  0 ,
                  255, 69,  0 ],

                [   0,69, 255 ,
                  120,180,180 ,
                   40,255, 60 ,
                  255,255,  0 ,
                  255, 69,  0 ],);

  $opacity //= 255;     # set to 255 if no opacity provided in call

  if( ref($colors) ne "ARRAY" ) {
    my $model = $colors // 0;      # set to 0 if no model provided in call
    $model = ($model < 0 || $model > int(@models)-1) ? 0 : $model; # check valid model
    $colors = $models[$model];
  }

  my( $startcolorR, $startcolorG, $startcolorB,
      $midcolor1R,$midcolor1G,$midcolor1B,
      $midcolor2R,$midcolor2G,$midcolor2B,
      $midcolor3R,$midcolor3G,$midcolor3B,
      $endcolorR,$endcolorG,$endcolorB ) = @{$colors};

  return sprintf("%02X%02X%02X%02X",$startcolorR,$startcolorG,$startcolorB,$opacity) if ($temp < $starttemp);
  return sprintf("%02X%02X%02X%02X",$endcolorR,$endcolorG,$endcolorB,$opacity)       if ($temp > $endtemp);

  sub interpol($$$$) {
    my ($u,$c1,$c2,$c3) = @_;

    my $c = $c1*(1-$u)**2 + $c2*2*(1-$u)*$u + $c3*$u**2;

    return (100*$c+0.5)/100;
  }

  if ($temp <= $midtemp) {
     my $u  = ($temp - $starttemp) / ($midtemp - $starttemp);

     my $r = interpol($u,$startcolorR,$midcolor1R,$midcolor2R);
     my $g = interpol($u,$startcolorG,$midcolor1G,$midcolor2G);
     my $b = interpol($u,$startcolorB,$midcolor1B,$midcolor2B);

     return sprintf("%02X%02X%02X%02X",$r+0.5,$g+0.5,$b+0.5,$opacity);
   }

   if ($temp <= $endtemp) {
     my $u  = ($temp - $midtemp) / ($endtemp - $midtemp);

     my $r = interpol($u,$midcolor2R,$midcolor3R,$endcolorR);
     my $g = interpol($u,$midcolor2G,$midcolor3G,$endcolorG);
     my $b = interpol($u,$midcolor2B,$midcolor3B,$endcolorB);

     return sprintf("%02X%02X%02X%02X",$r+0.5,$g+0.5,$b+0.5,$opacity);
  }
}

1;
