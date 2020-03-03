# $Id$
###############################################################################
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#
###############################################################################

package main;

use 5.018;
use feature qw( lexical_subs );

use strict;
use warnings;
use utf8;
use Time::HiRes qw( gettimeofday tv_interval );
use HttpUtils;

sub GSI_Initialize {
	my ($hash) = @_;

	$hash->{'DefFn'}				= 'GSI_Define';
	$hash->{'UndefFn'}				= 'GSI_Undef';
	$hash->{'NotifyFn'}				= 'GSI_Notify';
	$hash->{'FW_detailFn'}			= 'GSI_FW_detailFn';
	$hash->{'AttrList'}				= "$readingFnAttributes ";
	$hash->{'NOTIFYDEV'}			= 'TYPE=Global';
	return undef;
};

sub GSI_Define {
	my ($hash, $def) = @_;
	my ($name, $type, $plz) = split /\s/, $def;

	my $cvsid = '$Id$';
	$cvsid =~ s/^.*pm\s//;
	$cvsid =~ s/Z\s\S+\s\$$//;	

	return "German ZIP code required" unless ($plz =~ m/\d{5}/);
	$hash->{'ZIP'} = $plz;
	$hash->{'SVN'} = $cvsid;

	$attr{$name}{'devStateIcon'} = '{GSI::devStateIcon($name)}';
	GSI_Run($hash) if ($init_done);
	return undef;
};

sub GSI_Undef {
	my ($hash) = @_;

	RemoveInternalTimer($hash, \&GSI_ApiRequest);
	RemoveInternalTimer($hash, \&GSI_doReadings);
	return undef;
};

sub GSI_Notify {
	my ($hash, $dev) = @_;
	my $name = $hash->{'NAME'};
	return undef if(IsDisabled($name));

	my $events = deviceEvents($dev, 1);
	return if(!$events);

	foreach my $event (@{$events}) {
		my @e = split /\s/, $event;
		Log3 ($name, 5, sprintf('[%s] event:[%s], device:[%s]', $name, $event, $dev->{'NAME'}));
		if ($dev->{'TYPE'} eq 'Global') {
			if ($e[0] and $e[0] eq 'INITIALIZED') {
				GSI_Run($hash);
			};
		};
	};
};

sub GSI_FW_detailFn {
	my ($FW_wname, $name, $FW_room) = @_;
	my $hash = $defs{$name};

	my $ret;

	if (exists($hash->{'forecast'}) and scalar @{$hash->{'forecast'}})  {
		my $fc = $hash->{'forecast'};

		$ret = '<div class="makeTable wide gsiforecast"><table class="block wide gsiforecast"><thead>';
		$ret .= sprintf(<<'HTML', 'Zeit', 'Index (EE)', 'Co2 (EE)', 'Co2 (Std.Mix)');
<tr>
	<th><div class="col_header">%s</div></th>
	<th><div class="col_header">%s</div></th>
	<th><div class="col_header">%s</div></th>
	<th><div class="col_header">%s</div></td>
</tr>
HTML
		$ret .= '</thead><tbody>';
		my $i = 0;
		foreach my $e (@{$fc}) {
			last if ($i++ == 24);
			my $p0 = ($i % 2 == 1)?'odd':'even';
			my $p1 = POSIX::strftime('%a %R (%D)', localtime($e->{'epochtime'}));
			my $p2 = $e->{'eevalue'};
			my $p3 = $e->{'co2_g_oekostrom'};
			my $p4 = $e->{'co2_g_standard'};
			$ret .= sprintf(<<'HTML', $p0, $p1, $i, $p2, $i, $p3, $i, $p4);
<tr class="%s">
	<td><div class="dname" data-name="gsi">%s</div></td>
	<td><div class="dval" informid="gsi-gsi%s" align="right">%i</div></td>
	<td><div class="dval" informid="gsi-fcCo2ee%s" align="right">%s g/kWh</div></td>
	<td><div class="dval" informid="gsi-fcCo2std%s" align="right">%s g/kWh</div></td>
</tr>
HTML
		};
		return "$ret</body></table></div>";
	};
};

sub GSI_Run {
	my ($hash) = @_;
	GSI_ApiRequest($hash);
	return undef;
};

sub GSI_doReadings {
	my ($hash) = @_;

	$hash->{'NEXT_EVENT'} = undef;

	if (exists($hash->{'forecast'}) and (ref($hash->{'forecast'}) eq 'ARRAY') 
			and (scalar @{$hash->{'forecast'}} > 1))  {

		my $fc = $hash->{'forecast'};
		my $t = gettimeofday();

		while ((scalar @{$hash->{'forecast'}} > 1) and ($t > $fc->[1]->{'epochtime'})) {
			shift @{$fc};
		};
		return undef if (not scalar @{$hash->{'forecast'}} > 1);


		my sub linearInterpolate {
			my ($x, $x1, $x2, $y1, $y2) = @_;
			# eval for safety reasons, in case json input is broken
			eval {
				my $m = ($x - $x1) / ($x2 - $x1);
				my $r = ($y1 * (1 - $m) + $y2 * $m);
				# negativ clipping
				$r = 0 if ($r < 0);
				return $r;
				1;
			} or do {
				Log3 ($hash, 2, sprintf('[%s] GSI LinearInterpolate error: %s', $hash->{'NAME'}, $@));
				return $y1; 
			};
		};

		# right after start the actual hour is not available
		# create a 'fake' entry based on backward projection of hr+2 and hr+1
		if ($t < $fc->[0]->{'epochtime'}) {
			my $e;
			# easy way to get the last full hr
			$e->{'epochtime'} = $fc->[0]->{'epochtime'} - 3600;
			$e->{'eevalue'} = linearInterpolate($e->{'epochtime'}, $fc->[0]->{'epochtime'}, 
				$fc->[1]->{'epochtime'}, $fc->[0]->{'eevalue'}, $fc->[1]->{'eevalue'});
			# clipping
			$e->{'eevalue'} = 100 if ($e->{'eevalue'} >100);
			$e->{'co2_g_oekostrom'} = linearInterpolate($e->{'epochtime'}, $fc->[0]->{'epochtime'},
				$fc->[1]->{'epochtime'}, $fc->[0]->{'co2_g_oekostrom'}, $fc->[1]->{'co2_g_oekostrom'});
			$e->{'co2_g_standard'} = linearInterpolate($e->{'epochtime'}, $fc->[0]->{'epochtime'},
				$fc->[1]->{'epochtime'}, $fc->[0]->{'co2_g_standard'}, $fc->[1]->{'co2_g_standard'});
			unshift @{$fc}, $e;
		};

		my sub readingsBulkUpdateGSI {
			my ($readingName, $dataName) = @_;
			my $val = linearInterpolate($t, $fc->[0]->{'epochtime'}, 
						$fc->[1]->{'epochtime'}, $fc->[0]->{$dataName}, $fc->[1]->{$dataName});
			my $diff = abs(ReadingsVal($hash->{'NAME'}, $readingName, 0) - $val);
			if ($diff >= 1) {
				readingsBulkUpdate($hash, $readingName, sprintf('%.f', $val));
			};
		};

		readingsBeginUpdate($hash);
		readingsBulkUpdateGSI('state', 'eevalue');
		readingsBulkUpdateGSI('oeko_co2', 'co2_g_oekostrom');
		readingsBulkUpdateGSI('standard_co2', 'co2_g_standard');
		readingsEndUpdate($hash, 1);

		my sub calcNext {
			my ($id, $timeframe) = @_;
			if (my $s = abs($fc->[0]->{$id} - $fc->[1]->{$id})) {
				# stepwide in sec
				my $p0 = $timeframe / $s; 
				# time spend in timeframe div stepwide
				my $p1 = (($t - $fc->[0]->{'epochtime'}) / $p0);
				# time to next
				return $p0 - (($p1 - int($p1)) * $p0);
			} else {
				return $timeframe;
			};
		};

		my $next = 3600;
		foreach my $item ('eevalue', 'co2_g_oekostrom', 'co2_g_standard') {
			my $n = calcNext($item, 3600);
			$next = $n if ($n < $next);
		};
		$hash->{'NEXT_EVENT'} = int($t + $next);
		InternalTimer($t + $next, \&GSI_doReadings, $hash);
	};

	return undef;
};

sub GSI_ApiRequest {
	my ($hash) = @_;
	my $plz = $hash->{'ZIP'};
	my $param = {
		'hash'		=>		$hash,
		'url'		=>		"https://api.corrently.io/core/gsi?plz=$plz",
		'timeout'	=>		30,
		'callback'	=>		\&GSI_ApiResponse
	};
	HttpUtils_NonblockingGet($param);
};

sub GSI_ApiResponse {
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};

	$hash->{'API__LAST_RES'} = int(gettimeofday());

	my sub doError {
		my ($msg) = @_;
		$hash->{'API__LAST_MSG'} = $msg;
		my $next = gettimeofday() + 600;
		$hash->{'API__NEXT_REQ'} = $next;
		return InternalTimer($next, \&GSI_ApiRequest, $hash);
	};

	# in case of error
	if ($err) {
		return doError($err);
	};

	my $rs = GSI::JSON::StreamReader->new()->parse($data);
	if (not $rs or (ref($rs) ne 'HASH')) {
		return doError('invalid server response');
	};
	# no plz, message "Internal server error"
	if (exists($rs->{'message'}) and $rs->{'message'} =~ m/error/) {
		return doError($rs->{'message'});
	} elsif ((exists($rs->{'forecast'}) and ref($rs->{'forecast'}) eq 'ARRAY') 
			and scalar @{$rs->{'forecast'}})  {
		my $fc = $rs->{'forecast'};
		$hash->{'API__LAST_MSG'} = sprintf ('ok with %s items', scalar @{$fc});
		# sort for safety reasons
		@{$fc} = sort {$a->{'epochtime'} <=> $b->{'epochtime'}} @{$fc};
		# insert actual 
		if (exists($hash->{'forecast'}) and (ref($hash->{'forecast'}) eq 'ARRAY'))  {
			my $e;
			while ($e = shift @{$hash->{'forecast'}}	
				and ($e->{'epochtime'} < $fc->[0]->{'epochtime'})) {
					unshift @{$fc}, $e;
			};
		};
		# store it
		$hash->{'forecast'} = $fc;

		# schedule
		my $next = (int(gettimeofday() / 3600) * 3600) + (3600 + 1800 + int(rand(1200)));
		$hash->{'API_NEXT_REQ'} = $next;
		InternalTimer($next, \&GSI_ApiRequest, $hash);

		if ($hash->{'NEXT_EVENT'} and $hash->{'NEXT_EVENT'} > gettimeofday()) {
			return undef;
		} else {
			RemoveInternalTimer($hash, \&GSI_doReadings);
			GSI_doReadings($hash);
			return undef;
		};
	} else {
		return doError('invalid server response');
	};
	return doError('unknown');
};

###############################################################################
package GSI;

use strict;
use warnings;
use utf8;

use Carp qw( longmess cluck confess );

sub devStateIcon {
	my ($name, $icon) = @_;
	$icon //= 'message_socket_on_off';
	my $gsi = main::ReadingsVal($name, 'state', 0);
	return $gsi if (not $icon);

	if ($gsi < 40) {
		return ".*:$icon\@black";
	} elsif ($gsi < 60) {
		return ".*:$icon\@orange";
	} else {
		return ".*:$icon\@green";
		#return ".*:message_socket_on_off\@green";
	};	
};

sub greenPower {
	my ($name, $duration, $timeframe) = @_;

	($duration) = ($duration||'2' =~ m/^(\d+)$/);
	($timeframe) = ($timeframe||'12' =~ m/^(\d+)$/);

	if (not $duration or not $timeframe) {
		main::Log3(undef, 2, sprintf('GSI::greenPower usage: devicename, duration, timeframe'));
		return undef;
	};
	$timeframe = ($timeframe > 24)?24:$timeframe;
	$duration = ($duration > $timeframe)?$timeframe:$duration;
	
	if ($name and exists($main::defs{$name})) {
		my $hash = $main::defs{$name};
		if (exists($hash->{'forecast'}) and (ref($hash->{'forecast'}) eq 'ARRAY') 
			and (scalar @{$hash->{'forecast'}} > 1))  {
			my $fc = $hash->{'forecast'};
			my $ds = scalar @{$hash->{'forecast'}};

			if ($timeframe >= $ds) {
				return greenPower($name, $duration, $ds -1);
			};

			my %list;
			for (my $i=1; $i <= ($timeframe - $duration +1); $i++) {
				my $r = 0;
				for (my $j=0; $j < ($duration); $j++) {
					$r += $fc->[$i + $j]->{'eevalue'};
				};
				$list{$fc->[$i]->{'epochtime'}} = $r;
			};
			my @timelist;
			foreach my $ts (sort { $list{$a} <=> $list{$b} } keys %list) {
				push @timelist, POSIX::strftime ('%H:%M', localtime($ts));
				@timelist = reverse @timelist;
			};
			if (wantarray) {
				return @timelist;
			} elsif (defined(wantarray)) {
				return $timelist[0];
			};
		};
	};
	return undef;
};


###############################################################################
# credits to David Oswald
# http://cpansearch.perl.org/src/DAVIDO/JSON-Tiny-0.58/lib/JSON/Tiny.pm
package GSI::JSON::StreamWriter;

use strict;
use warnings;
use utf8;
use B;

my ($escape, $reverse);

BEGIN {
	eval "use JSON::XS;1;" or do {
		if (not $main::_JSON_PP_WARN) {
			main::Log3 (undef, 3, sprintf('json [%s] is PP. Consider installing JSON::XS', __PACKAGE__));
			$main::_JSON_PP_WARN = 1;
		};			
	};
};

BEGIN {
	%{$escape} =  (
		'"'     => '"',
		'\\'    => '\\',
		'/'     => '/',
		'b'     => "\x08",
		'f'     => "\x0c",
		'n'     => "\x0a",
		'r'     => "\x0d",
		't'     => "\x09",
		'u2028' => "\x{2028}",
		'u2029' => "\x{2029}"
	);
	%{$reverse} = map { $escape->{$_} => "\\$_" } keys %{$escape};
	for(0x00 .. 0x1f) {
		my $packed = pack 'C', $_;
		$reverse->{$packed} = sprintf '\u%.4X', $_ unless defined $reverse->{$packed};
	};
};

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	return $self;
};

sub parse {
	my ($self, $data) = @_;
	my $stream;

	# use JSON::XS if available
	my $xs = eval 'JSON::XS::encoode_json($data)';
	return $xs if ($xs);

	if (my $ref = ref $data) {
		use Encode;
		return Encode::encode_utf8($self->addValue($data));
	};
};

sub addValue {
	my ($self, $data) = @_;
	if (my $ref = ref $data) {
		return $self->addONode($data) if ($ref eq 'HASH');
		return $self->addANode($data) if ($ref eq 'ARRAY');
	};
	return 'null' unless defined $data;
	return $data
		if B::svref_2object(\$data)->FLAGS & (B::SVp_IOK | B::SVp_NOK)
		# filter out "upgraded" strings whose numeric form doesn't strictly match
		&& 0 + $data eq $data
		# filter out inf and nan
		&& $data * 0 == 0;
	# String
	return $self->addString($data);
};

sub addString {
	my ($self, $str) = @_;
	$str =~ s!([\x00-\x1f\x{2028}\x{2029}\\"/])!$reverse->{$1}!gs;
	return "\"$str\"";
};

sub addONode {
	my ($self, $object) = @_;
	my @pairs = map { $self->addString($_) . ':' . $self->addValue($object->{$_}) }
		sort keys %$object;
	return '{' . join(',', @pairs) . '}';
};

sub addANode {
	my ($self, $array) = @_;
	return '[' . join(',', map { $self->addValue($_) } @{$array}) . ']';
};

###############################################################################
# credits to David Oswald
# http://cpansearch.perl.org/src/DAVIDO/JSON-Tiny-0.58/lib/JSON/Tiny.pm
package GSI::JSON::StreamReader;
use strict;
use warnings;
use utf8;

BEGIN {
	eval "use JSON::XS;1;" or do {
		if (not $main::_JSON_PP_WARN) {
			main::Log3 (undef, 3, sprintf('json [%s] is PP. Consider installing JSON::XS', __PACKAGE__));
			$main::_JSON_PP_WARN = 1;
		};			
	};
};

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	return $self;
};

sub parse {
	my ($self, $in) = @_;
	my $TRUE = 1;
	my $FALSE = 0;

	local *exception = sub {
		my ($e) = @_;
		# Leading whitespace
		m/\G[\x20\x09\x0a\x0d]*/gc;
		# Context
		my $context = 'Malformed JSON: ' . shift;
		if (m/\G\z/gc) { 
		  $context .= ' before end of data';
		} else {
		  my @lines = split "\n", substr($_, 0, pos);
		  $context .= ' at line ' . @lines . ', offset ' . length(pop @lines || '');
		};
		die "$context";
	};

	local *_decode_string = sub {
		my $pos = pos;

		# Extract string with escaped characters
		m!\G((?:(?:[^\x00-\x1f\\"]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4})){0,32766})*)!gc; # segfault on 5.8.x in t/20-mojo-json.t
		my $str = $1;

		# Invalid character
		unless (m/\G"/gc) { #"
			exception('Unexpected character or invalid escape while parsing string')
			if m/\G[\x00-\x1f\\]/;
			exception('Unterminated string');
		};

		# Unescape popular characters
		if (index($str, '\\u') < 0) {
			#no warnings;
			$str =~ s!\\(["\\/bfnrt])!$self->{'ESCAPE'}->{$1}!gs;
			return $str;
		};

		# Unescape everything else
		my $buffer = '';
		while ($str =~ m/\G([^\\]*)\\(?:([^u])|u(.{4}))/gc) {
			$buffer .= $1;
			# Popular character
			if ($2) { 
				$buffer .= $self->{'ESCAPE'}->{$2};
			} else { # Escaped
				my $ord = hex $3;
				# Surrogate pair
				if (($ord & 0xf800) == 0xd800) {
					# High surrogate
					($ord & 0xfc00) == 0xd800
						or pos($_) = $pos + pos($str), exception('Missing high-surrogate');
					# Low surrogate
					$str =~ m/\G\\u([Dd][C-Fc-f]..)/gc
						or pos($_) = $pos + pos($str), exception('Missing low-surrogate');
					$ord = 0x10000 + ($ord - 0xd800) * 0x400 + (hex($1) - 0xdc00);
				};
				# Character
				$buffer .= pack 'U', $ord;
			};
		};
		# The rest
		return $buffer . substr $str, pos $str, length $str;
	};

	local *_decode_object = sub {
		my %hash;
		until (m/\G[\x20\x09\x0a\x0d]*\}/gc) {
			# Quote
			m/\G[\x20\x09\x0a\x0d]*"/gc
			or exception('Expected string while parsing object');
			# Key
			my $key = _decode_string();
			# Colon
			m/\G[\x20\x09\x0a\x0d]*:/gc
			or exception('Expected colon while parsing object');
			# Value
			$hash{$key} = _decode_value();
			# Separator
			redo if m/\G[\x20\x09\x0a\x0d]*,/gc;
			# End
			last if m/\G[\x20\x09\x0a\x0d]*\}/gc;
			# Invalid character
			exception('Expected comma or right curly bracket while parsing object');
		};
		return \%hash;
	};

	local *_decode_array = sub {
		my @array;
		until (m/\G[\x20\x09\x0a\x0d]*\]/gc) {
			# Value
			push @array, _decode_value();
			# Separator
			redo if m/\G[\x20\x09\x0a\x0d]*,/gc;
			# End
			last if m/\G[\x20\x09\x0a\x0d]*\]/gc;
			# Invalid character
			exception('Expected comma or right square bracket while parsing array');
		};
		return \@array;
	};

	local *_decode_value = sub {
		# Leading whitespace
		m/\G[\x20\x09\x0a\x0d]*/gc;
		# String
		return _decode_string() if m/\G"/gc;
		# Object
		return _decode_object() if m/\G\{/gc;
		# Array
		return _decode_array() if m/\G\[/gc;
		# Number 
		# jh: failed with 0123 
		#my ($i) = /\G([-]?(?:0(?!\d)|[1-9][0-9]*)(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?)/gc;
		my ($i) = /\G(?=.)([+-]?([0-9]*)(\.([0-9]+))?)([eE][+-]?\d+)?/gc;
		return 0 + $i if defined $i;
		# True
		{ no warnings;
			return $TRUE if m/\Gtrue/gc;
			# False
			return $FALSE if m/\Gfalse/gc;
		};
		# Null
		return undef if m/\Gnull/gc;  ## no critic (return)
		# Invalid character
		exception('Expected string, array, object, number, boolean or null');
	};

	local *_decode = sub {
		my $valueref = shift;
		eval {
			# Missing input
			die "Missing or empty input\n" unless length( local $_ = shift );
			# UTF-8
			$_ = eval { Encode::decode('UTF-8', $_, 1) } unless shift;
			die "Input is not UTF-8 encoded\n" unless defined $_;
			# Value
			$$valueref = _decode_value();
			# Leftover data
			return m/\G[\x20\x09\x0a\x0d]*\z/gc || exception('Unexpected data');
		} ? return undef : chomp $@;
		return $@;
	};

	# use JSON::XS if available
	my $xs = eval 'JSON::XS::decode_json($in)';
	return $xs if ($xs);

	my $err = _decode(\my $value, $in, 1);
	return defined $err ? $err : $value;
};

1;

=pod
=item helper
=item summary 		green power index (Energy and carbon consumption)
=item summary_DE	Gruen Strom Index (Energie und Co2)
=begin html

<a name="GSI"></a>
<h3>GSI</h3>
<ul>
	GSI shows the share of renewable energies in the power grid for any location 
	in Germany at the current time and a forecast for the next 24 hours.
	At the same time, Co2 emissions for generation are displayed. Co2 values 
	for the regular electricity mix and Co2 values for tariffs with 100% renewable 
	energy are available.
	<br><br>
	In addition, based on the prediction of the electricity composition, 
	the energy consumption can be planned for periods with a high proportion 
	of renewable energies and thus low Co2 emissions.
	<br><br>
	The energy forecasts are provided by 'corrently', in cooperation with 
	the network operators, based on the network topology and weather 
	forecasts. 
	<br><br>

	<a name="GSIdefine"></a>
	<b>Define</b>
	<ul>
    	<code>define &lt;name&gt; GSI &lt;zip&gt;</code>
    	<br><br>
    	defines the device for the given (german only) zip code.
	</ul>
	<br>

	<a name="GSIset"></a>
	<b>Set</b>
	<ul>
		N/A
	</ul>
	<br>

	<a name="GSIget"></a>
	<b>Get</b>
	<ul>
		N/A
	</ul>
	<br>

	<a name="GSIattr"></a>
	<b>Attributes</b>
	<ul>
    	<a name="cmdStateIcon"></a>
    	<li>cmdStateIcon<br>
    		preset to the function
    		<ul><li><code>{GSI::devStateIcon($name)}</code></li></ul>
    		and can be advanced to 
    		<ul><li><code>{GSI::devStateIcon($name,'other_valid_svg_icon_name')}</code></li></ul>
    		The icon will be colored based on share of renewable energy (GSI) available:
    		<ul>
    			<li>0..39: black</li>
    			<li>40..59: orange</li>
    			<li>60..100: green</li>
			</ul><br>
		</li>
	</ul>

	<a name="GSIschedule"></a>
	<b>Consumption schedule</b>
	<ul>
		<a name="Predictive switching"></a>
		The prediction (forecast) can be used to automatically control electrical consumers 
		based in the amount of renewable energy expected:<br>
		<ul><li><code>define name at {GSI::greenPower('name_of_gsi_device',2,18)} set consumer on-for-timer 720</code></li></ul><br>
		This example requests the 2 consecutive hours with the highest share of renewable energy within the next 18 hours. 
		This is used for the definition of an 'at' which switches on a consumer for 2 hours (720 seconds) at the best possible time.
	</ul>
</ul>
=end html

=cut