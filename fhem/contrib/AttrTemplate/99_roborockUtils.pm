##############################################
# $Id$
# from myUtilsTemplate.pm 21509 2020-03-25 11:20:51Z rudolfkoenig
# utils for Xiaomi Vaccum MQTT Implementation
# They are then available in every Perl expression.

package main;

use strict;
use warnings;
use JSON;

sub
roborockUtils_Initialize {
  my $hash = shift;
  return;
}
# Enter you functions below _this_ line.

# strip the names for spots and zones and return a list 
sub valetudoREdest {
my $EVENT = shift;
my ($text,%h);
$text=from_json($EVENT);
for ('spots','zones') {
    my @a;
    for my $i (0..$#{$text->{$_}}) {
      push @a, $text->{$_}->[$i]->{name}
    }
    $h{$_} = join q{,}, @a
  }
 return \%h
}

# return the last part topic and payload for mqtt message for certain custom_commands
sub valetudoRE {
my $EVENT = shift;
my $ret = 'error';
my ($cmd,$load) = split(q{ }, $EVENT,2);
# my $topic = ReadingsVal($NAME,'devicetopic','valetudo/rockrobo');
if (@_) {Log 1,"sub valetudoRE - Befehl:$cmd Load:$load";return q{}}
my (@zid,@l,%consum);

if ($cmd eq 'zone') {@zid = split q{,},$load}
if ($cmd eq 'map') {@l = split q{ },$load}
for (qw(main_brush_work_time side_brush_work_time filter_work_time sensor_dirty_time))
    {$consum{(split q{_})[0]}=$_};

 my %Hcmd = (
    goto =>     { command => 'go_to',spot_id => $load },
    get_dest => { command => 'get_destinations' },
    map =>      { command => $l[0].'_map',name => $l[1] },
    reset_consumable => { command => 'reset_consumable',consumable => $consum{$load} },
    zone =>     { command => 'zoned_cleanup',zone_ids => \@zid },
  );
 if ($cmd eq 'x_raw_payload') {$ret=$load}
 else {$ret = toJSON $Hcmd{$cmd}}
return '/custom_command '.$ret
}

1;
=pod
=item summary    generic MQTT2 Xiaomi Roborock Devices rooted with valetudo RE
=item summary_DE generische MQTT2 Xiaomi Roborock Ger&#228;t gerootet mit valetudo RE
=begin html

Some Subroutines for generic MQTT2 Xiaomi Roborock Devices rooted with valetudo RE.
<a id="MQTT2 Xiaomi Roborock"></a>
<h3>MQTT2 Xiaomi Roborock</h3>
<ul>
  RoboRockUtils.
  <br> <br>

  <a id="MQTT2_DEVICE-setList"></a>
  <b>attr</b>
  <ul>
    <code>{valetudoRE($EVENT)}</code>
    <br><br>
    To enable below.<br>
  </ul>
  <br>
</ul>

=end html
=begin html_DE

Enthaelt einige Subroutinen fuer generische MQTT2 Xiaomi Roborock Ger&#228;te gerootet mit valetudo RE.

=end html_DE
=cut
