##############################################
# $Id: attrTmqtt2_ebus_Utils.pm 2021-07-15 Beta-User $
#

package FHEM::aTm2u_ebus;    ## no critic 'Package declaration'

use strict;
use warnings;

use JSON qw(decode_json);
use Scalar::Util qw(looks_like_number);

use GPUtils qw(GP_Import);

#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          json2nameValue
          AttrVal
          InternalVal
          CommandGet
          CommandSet
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          ReadingsVal
          ReadingsNum
          ReadingsAge
          json2nameValue
          defs
          Log3
          )
    );
}

sub ::attrTmqtt2_ebus_Utils_Initialize { goto &Initialize }
sub ::attrTmqtt2_ebus_createBarView { goto &createBarView }

# initialize ##################################################################
sub Initialize {
    my $hash = shift;
    return;
}
# Enter you functions below _this_ line.

sub j2nv {
    my $EVENT = shift // return;
    my $pre   = shift;
    my $filt  = shift;
    my $not   = shift;
    $EVENT=~ s{[{]"value":\s("[^"]+")[}]}{$1}g;
    return json2nameValue($EVENT, $pre, $filt, $not);
}

sub send_weekprofile {
    my $name       = shift;
    my $wp_name    = shift;
    my $wp_profile = shift // return;
    my $model      = shift // ReadingsVal($name,'week','selected'); #selected,Mo-Fr,Mo-So,Sa-So? holiday to set actual $wday to sunday program?
    my $topic      = shift // AttrVal($name,'devicetopic','') . '/hcTimer.$wkdy/set ';

    my $onLimit    = shift // '20';

    my $hash = $defs{$name};

    my $wp_profile_data = CommandGet(undef,"$wp_name profile_data $wp_profile 0");
    if ($wp_profile_data =~ m{(profile.*not.found|usage..profile_data..name)}xms ) {
        Log3( $hash, 3, "[$name] weekprofile $wp_name: no profile named \"$wp_profile\" available" );
        return;
    }

    my @Dl = ("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday");
    my @D = ("Sun","Mon","Tue","Wed","Thu","Fri","Sat");

    my $payload;
    my @days = (0..6);
    my $text = decode_json($wp_profile_data);

    ( $model, @days ) = split m{:}xms, $model;
    (my $sec,my $min,my $hour,my $mday,my $mon,my $year,my $wday,my $yday,my $isdst) = localtime;

    @days = ( $model eq 'Mo-Fr' || $model eq 'Mo-So' ) ? (1) : ($model eq 'Sa-So' || $model eq 'holiday' ) ? (0) :  (0..6) if !@days;

    for my $i (@days) {
        $payload = q{};
        my $pairs = 0;
        my $onOff = 'off';

        for my $j (0..20) {
            my $time = '00:00';
            if (defined $text->{$D[$i]}{time}[$j]) {
                $time = $text->{$D[$i]}{time}[$j-1] // '00:00';
                my $val = $text->{$D[$i]}{temp}[$j];
                if ( $val eq $onOff || (looks_like_number($val) && _compareOnOff( $val, $onOff, $onLimit ) ) ) {
                    $time = '00:00' if !$j;
                    $payload .= qq{$time;;$text->{$D[$i]}{time}[$j];;};
                    $pairs++;
                    $val = $val eq 'on' ? 'off' : 'on';
                }
            }
            while ( $pairs < 3 && !defined $text->{$D[$i]}{time}[$j] ) {
                #fill up the three pairs with last time
                $time = $text->{$D[$i]}{time}[$j-1];
                $pairs++;
                $payload .= qq{-:-;;-:-;;};
            }
            last if $pairs == 3;
        }

        if ( $model eq 'holiday' ) {
            $payload .= 'selected';
            CommandSet($defs{$name},"$name $Dl[$wday] $payload")
        } else {
            $payload .= $model;
            CommandSet($defs{$name},"$name $Dl[$i] $payload");
        }
    }

    readingsSingleUpdate( $defs{$name}, 'weekprofile', "$wp_name $wp_profile",1);
    return;
}

sub _compareOnOff {
    my $val   = shift // return;
    my $onOff = shift // return;
    my $lim   = shift;

    if ( $onOff eq 'on' ) {
        return $val < $lim;
    } else {
        return $val >= $lim;
    }
    return;
}

sub createBarView {
  my ($val,$maxValue,$color) = @_;
  $maxValue = $maxValue//100;
  $color = $color//"red";
  my $percent = $val / $maxValue * 100;
  # Definition des valueStyles
  my $stylestring = 'style="'.
    'width: 200px; '.
    'text-align:center; '.
    'border: 1px solid #ccc ;'. 
    "background-image: -webkit-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '.
    "background-image:    -moz-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '. 
    "background-image:     -ms-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '. 
    "background-image:      -o-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '. 
    "background-image:         linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%);"';
    # Rückgabe des definierten Strings
  return $stylestring;
}

1;

__END__
=pod
=begin html

<a name="attrTmqtt2_ebus_Utils"></a>
<h3>attrTmqtt2_ebus_Utils</h3>
<ul>
  <b>Functions to support attrTemplates for ebusd</b><br> 
</ul>
<ul>
  <li><b>aTm2u_ebus::j2nv</b><br>
  <code>aTm2u_ebus::j2nv($,$$$)</code><br>
  This ist just a wrapper to fhem.pl json2nameValue() to prevent the "_value" postfix. It will first clean the first argument by applying <code>$EVENT=~ s{[{]"value":\s("[^"]+")[}]}{$1}g;</code>. 
  </li>
  <li><b>aTm2u_ebus::createBarView</b><br>
  <code>aTm2u_ebus::createBarView($,$$)</code><br>
  Parameters are 
  <ul>
    <li>$value (required)</li> 
    <li>$maxvalue (optional), defaults to 100</li> 
    <li>$color, (optional), defaults to red</li> 
  </ul>
  For compability reasons, function will also be exported as attrTmqtt2_ebus_createBarView(). Better use package version to call it... 
  </li>
</ul><br>
=end html
=cut
