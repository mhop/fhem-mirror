##############################################
# $Id$
# contributed by DeeSPe, https://forum.fhem.de/index.php/topic,98880.msg1192196.html#msg1192196

package FHEM::attrT_WLED_Utils;    ## no critic 'Package declaration'

use strict;
use warnings;

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
  GP_Import(
    qw(
      defs
      InternalVal
      ReadingsVal
      ReadingsNum
      AttrVal
      readingsBeginUpdate
      readingsBulkUpdate
      readingsBulkUpdateIfChanged
      readingsEndUpdate
      HttpUtils_NonblockingGet
    )
  );
}

sub ::attrT_WLED_Utils_Initialize { goto &Initialize }

# initialize ##################################################################
sub Initialize {
  my $hash = shift;
  return;
}

# Enter you functions below _this_ line.

sub WLED_get {
  my $dev = shift // return;
  my $event = shift // undef;
  my $c;
  my $h = {
    sx => 'speed',
    ix => 'intensity',
    fp => 'palette',
    fx => 'effect',
    ps => 'preset'
  };
  for (keys %{$h}) {
    next if $event !~ m/(?<=<$_>)([\d]+)(?=<\/$_>)/x;
    if ($1 != ReadingsNum($dev,$h->{$_},-2)){
      $c->{$h->{$_}} = $1;
    }
  }
  my $io = InternalVal($dev,'LASTInputDev',AttrVal($dev,'IODev',InternalVal($dev,'IODev',undef)->{NAME})) // return defined $event ? $c : undef;
  my $ip = InternalVal($dev,$io.'_CONN',ReadingsVal($dev,'ip', undef)) =~ m/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/x ? $1 : return defined $event ? $c : undef;
  HttpUtils_NonblockingGet({
    url=>"http://$ip/json",
    callback=>sub($$$){
      my ($hash,$err,$data) = @_;
      WLED_setReadings($dev,$data);
    }
  });
  return defined $event ? $c : undef;
}

sub WLED_setReadings {
  my $dev  = shift // return;
  my $data = shift // return;
  my $fx   = $data =~  m/effects..\[([^[]*?)]/x ? WLED_subst($1) : '';
  my $pl   = $data =~ m/palettes..\[([^[]*?)]/x ? WLED_subst($1) : '';
  my $hash = $defs{$dev};
  my @f    = split m{,}, $fx;
  my @p    = split m{,}, $pl;
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,'effectname',$f[ReadingsNum($dev,'effect',0)]);
  readingsBulkUpdate($hash,'palettename',$p[ReadingsNum($dev,'palette',0)]);
  readingsEndUpdate($hash,1);
  readingsBeginUpdate($hash);
  readingsBulkUpdateIfChanged($hash,'.effectscount',(scalar @f)-1);
  readingsBulkUpdateIfChanged($hash,'.effects',$fx);
  readingsBulkUpdateIfChanged($hash,'.palettescount',(scalar @p)-1);
  readingsBulkUpdateIfChanged($hash,'.palettes',$pl);
  readingsEndUpdate($hash,0);
  return;
}

sub WLED_subst {
  my $s = shift;
  $s =~ s/["\n]//gx;
  $s =~ s/[\s\&]/_/gx;
  $s =~ s/\+/Plus/gx;
  return $s;
}

sub WLED_set {
  my $dev  = shift // return;
  my $read = shift // return;
  my $val  = shift // return;
  my $wled = lc(InternalVal($dev,'CID',undef)) // return;
  my $arr  = ReadingsVal($dev,'.'.$read.'s',undef) // return WLED_get($dev);
  $wled =~ s/_/\//;
  my $top  = $wled.'/api F';
  $top .= $read eq 'effect'?'X=':'P=';
  my $id;
  my $i = 0;
  for (split(',',$arr)){
    if ($_ ne $val) {
      $i++;
      next;
    } else {
      $id = $i;
      last;
    }
  }
  return defined $id ? $top.$id : undef;
}

1;

__END__


=pod
=item summary helper functions needed for WLED MQTT2_DEVICE
=item summary_DE needed Hilfsfunktionen für WLED MQTT2_DEVICE
=begin html

<a id="attrT_WLED_Utils"></a>
<h3>attrT_WLED_Utils</h3>
<ul>
  <b>Functions to support attrTemplates for WLEDs</b><br> 
</ul>
<ul>
  <li><b>FHEM::attrT_WLED_Utils::WLED_get</b><br>
  <code>FHEM::attrT_WLED_Utils::WLED_get($$)</code><br>
  This is used to provide some readings from the API.
  </li>
</ul>
<ul>
  <li><b>FHEM::attrT_WLED_Utils::WLED_set</b><br>
  <code>FHEM::attrT_WLED_Utils::WLED_set($$$)</code><br>
  This is used to set the effects and palettes with their names.
  </li>
</ul>
=end html
=cut
