package Geo::Mirror;

use strict;
use vars qw($VERSION);

$VERSION = '1.01';

use constant PI => 3.14159265358979323846;

our (%lat, %lon, $geo_ip_pkg);

BEGIN {
  if (eval { require Geo::IP }) {
    $geo_ip_pkg = "Geo::IP";
  }
  else {
    require Geo::IP::PurePerl;
    $geo_ip_pkg = "Geo::IP::PurePerl";
  }
  $geo_ip_pkg->import('GEOIP_STANDARD');
}

{
  local $_;
  while (<DATA>) {
    my ($country, $lat, $lon) = split(':');

    $lat{$country} = $lat;
    $lon{$country} = $lon;
  }
}

sub new {
  my ($class, %h) = @_;
  my $self = \%h;
  bless $self, $class;
  $self->_init;
  return $self;
}

sub _init {
  my $self = shift;
  my $mirror_file = $self->{mirror_file};
  local $_;
  open MIRROR, "$mirror_file" or die $!;
  while(<MIRROR>) {
    my ($url, $country, $fresh) = split(' ');
    push @{$self->{mirror}->{$country}}, $url;
    $self->{fresh}{$url} = $fresh || 0;
  }
  close MIRROR;
}

sub _random_mirror {
  my ($self, $country, $fresh) = @_;

  my @mirror = grep { $self->{fresh}{$_} >= $fresh } @{$self->{mirror}->{$country}};

  my $num = scalar @mirror or return;

  return $mirror[ rand($num) ];
}

sub find_mirror_by_country {
  my ($self, $country, $fresh) = @_;
  my $url;

  $fresh ||= 0;

  if (exists $self->{mirror}->{$country}) {
    $url = $self->_random_mirror($country, $fresh);
  }

  if (!$url) {
    my $nearby = $self->{nearby_cache}->{$country} ||= $self->_find_nearby_countries($country);
    foreach my $new_country (@$nearby) {
      $url = $self->_random_mirror($new_country, $fresh) and last;
    }
  }

  return $url;
}

sub find_mirror_by_addr {
  my ($self, $addr, $fresh) = @_;

  unless($self->{gi}) {
    if ($self->{database_file}) {
      $self->{gi} = $geo_ip_pkg->open($self->{database_file}, GEOIP_STANDARD);
    } else {
      $self->{gi} = $geo_ip_pkg->new(GEOIP_STANDARD);
    }
  }

  # default to US if country not found
  my $country = lc($self->{gi}->country_code_by_addr($addr)) || 'us';
  $country = 'us' if $country eq '--';
  return $self->find_mirror_by_country($country, $fresh);
}

sub _find_nearby_countries {
  my ($self, $country) = @_;

  my %distance = map { ($_, $self->_calculate_distance($country, $_)) } keys %{$self->{mirror}};
  delete $distance{$country};

  [ sort { $distance{$a} <=> $distance{$b} } keys %distance ];
}

sub _calculate_distance {
  my ($self, $country1, $country2) = @_;

  my $lat_1 = $lat{$country1};
  my $lat_2 = $lat{$country2};
  my $lon_1 = $lon{$country1};
  my $lon_2 = $lon{$country2};

  # Convert all the degrees to radians
  $lat_1 *= PI/180;
  $lon_1 *= PI/180;
  $lat_2 *= PI/180;
  $lon_2 *= PI/180;

  # Find the deltas
  my $delta_lat = $lat_2 - $lat_1;
  my $delta_lon = $lon_2 - $lon_1;

  # Find the Great Circle distance
  my $temp = sin($delta_lat/2.0)**2 + cos($lat_1) * cos($lat_2) * sin($delta_lon/2.0)**2;
  return atan2(sqrt($temp),sqrt(1-$temp));
}

1;

=head1 NAME

Geo::Mirror - Find closest Mirror

=head1 SYNOPSIS

  use Geo::Mirror;

  my $gm = Geo::Mirror->new(mirror_file => '/path/to/mirrors.txt');

  my $mirror = $gm->closest_mirror_by_country('us', $freshness);       # $freshness optional, see description below
  my $mirror = $gm->closest_mirror_by_addr('24.24.24.24', $freshness); # $freshness optional, see description below

=head1 DESCRIPTION

This module finds the closest mirror for an IP address.  It uses L<Geo::IP>
to identify the country that the IP address originated from.  If
the country is not represented in the mirror list, then it finds the
closest country using a latitude/longitude table.

The mirror file should be a space separate list of URL, Country, and mirror freshness.
The mirror freshness is optional and can be used by user
request a mirror with a minimum freshness.

=head1 AUTHOR

Copyright (c) 2004, MaxMind LLC, support@maxmind.com

All rights reserved.  This package is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=cut

__DATA__
af:33:65
al:41:20
dz:28:3
as:-14:-170
ad:42:1
ao:-12:18
ai:18:-63
aq:-90:0
ag:17:-61
ar:-34:-64
am:40:45
aw:12:-69
au:-27:133
at:47:13
az:40:47
bs:24:-76
bh:26:50
bd:24:90
bb:13:-59
by:53:28
be:50:4
bz:17:-88
bj:9:2
bm:32:-64
bt:27:90
bo:-17:-65
ba:44:18
bw:-22:24
bv:-54:3
br:-10:-55
io:-6:71
vg:18:-64
bg:43:25
bf:13:-2
bi:-3:30
kh:13:105
cm:6:12
ca:60:-95
cv:16:-24
ky:19:-80
cf:7:21
td:15:19
cl:-30:-71
cn:35:105
cx:-10:105
cc:-12:96
co:4:-72
km:-12:44
cd:0:25
cg:-1:15
ck:-21:-159
cr:10:-84
ci:8:-5
hr:45:15
cu:21:-80
cy:35:33
cz:49:15
dk:56:10
dj:11:43
dm:15:-61
do:19:-70
ec:-2:-77
eg:27:30
sv:13:-88
gq:2:10
er:15:39
ee:59:26
et:8:38
fk:-51:-59
fo:62:-7
fj:-18:175
fi:64:26
fr:46:2
gf:4:-53
pf:-15:-140
ga:-1:11
gm:13:-16
ge:42:43
de:51:9
eu:48:10
gh:8:-2
gi:36:-5
gr:39:22
gl:72:-40
gd:12:-61
gp:16:-61
gu:13:144
gt:15:-90
gn:11:-10
gw:12:-15
gy:5:-59
ht:19:-72
hm:-53:72
va:41:12
hn:15:-86
hk:22:114
hu:47:20
is:65:-18
in:20:77
id:-5:120
ir:32:53
iq:33:44
ie:53:-8
il:31:34
it:42:12
jm:18:-77
sj:71:-8
jp:36:138
jo:31:36
ke:1:38
ki:1:173
kp:40:127
kr:37:127
kw:29:45
kg:41:75
lv:57:25
lb:33:35
ls:-29:28
lr:6:-9
ly:25:17
li:47:9
lt:56:24
lu:49:6
mo:22:113
mk:41:22
mg:-20:47
mw:-13:34
my:2:112
mv:3:73
ml:17:-4
mt:35:14
mh:9:168
mq:14:-61
mr:20:-12
mu:-20:57
yt:-12:45
mx:23:-102
fm:6:158
mc:43:7
mn:46:105
ms:16:-62
ma:32:-5
mz:-18:35
na:-22:17
nr:-0:166
np:28:84
nl:52:5
an:12:-68
nc:-21:165
nz:-41:174
ni:13:-85
ne:16:8
ng:10:8
nu:-19:-169
nf:-29:167
mp:15:145
no:62:10
om:21:57
pk:30:70
pw:7:134
pa:9:-80
pg:-6:147
py:-23:-58
pe:-10:-76
ph:13:122
pn:-25:-130
pl:52:20
pt:39:-8
pr:18:-66
qa:25:51
re:-21:55
ro:46:25
ru:60:100
rw:-2:30
sh:-15:-5
kn:17:-62
lc:13:-60
pm:46:-56
vc:13:-61
ws:-13:-172
sm:43:12
st:1:7
sa:25:45
sn:14:-14
sc:-4:55
sl:8:-11
sg:1:103
sk:48:19
si:46:15
sb:-8:159
so:10:49
za:-29:24
gs:-54:-37
es:40:-4
lk:7:81
sd:15:30
sr:4:-56
sj:78:20
sz:-26:31
se:62:15
ch:47:8
sy:35:38
tj:39:71
tz:-6:35
th:15:100
tg:8:1
tk:-9:-172
to:-20:-175
tt:11:-61
tn:34:9
tr:39:35
tm:40:60
tc:21:-71
tv:-8:178
ug:1:32
ua:49:32
ae:24:54
gb:54:-2
us:38:-97
uy:-33:-56
uz:41:64
vu:-16:167
ve:8:-66
vn:16:106
vi:18:-64
wf:-13:-176
eh:24:-13
ye:15:48
yu:44:21
zm:-15:30
zw:-20:30
tw:23:121
