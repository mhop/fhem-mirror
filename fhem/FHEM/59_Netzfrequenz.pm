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
use Carp qw(croak carp);
use HttpUtils;
use Scalar::Util qw ( looks_like_number );
use Time::HiRes qw ( gettimeofday );

sub Netzfrequenz_Initialize {
	my ($hash) = @_;

	my @attrList;
	{
		no warnings qw( qw );
	 	@attrList = qw(
			disable:0,1
			interval
			processing
		);
	};

	$hash->{'DefFn'}				= 'Netzfrequenz_Define';
	$hash->{'UndefFn'}				= 'Netzfrequenz_Undef';
	$hash->{'DeleteFn'}				= 'Netzfrequenz_Delete';
	#$hash->{'SetFn'}				= 'Netzfrequenz_Set';
	#$hash->{'GetFn'}				= 'Netzfrequenz_Get';
	$hash->{'AttrFn'}				= 'Netzfrequenz_Attr';
	#$hash->{'NotifyFn'}				= 'Netzfrequenz_Notify';
	$hash->{'RenameFn'}				= 'Netzfrequenz_Rename';
	$hash->{'AttrList'}				= join(' ', @attrList)." $readingFnAttributes ";

	return undef;
};

sub Netzfrequenz_Define {
	my ($hash) = @_;

	my $cvsid = '$Id$';
	$cvsid =~ s/^.*pm\s//;
	$cvsid =~ s/Z\s\S+\s\$$/ UTC/;
	$hash->{'SVN'} = $cvsid;
	
	return "no FUUID, is fhem up to date?" if (not $hash->{'FUUID'});
	InternalTimer(0, \&Netzfrequenz_Run, $hash);
	return;
};

# reread / temporary remove
sub Netzfrequenz_Undef {
	my ($hash, $name) = @_;
	Netzfrequenz_StopTimer($hash);
	return;
};

# delete / permanently remove
sub Netzfrequenz_Delete {
	my ($hash, $name) = @_;
	my $error;
	Netzfrequenz_StopTimer($hash);
	return $error;
};

sub Netzfrequenz_Run {
	my ($hash) = @_;
	my $name = $hash->{'NAME'};
	return if IsDisabled($name);
	Netzfrequenz_StartTimer($hash, 1);
	return;
};

sub Netzfrequenz_Set {
	my ($hash, $name, $cmd, @args) = @_;

	my @cmds = qw( );
	return sprintf ("Unknown argument $cmd, choose one of %s", join(' ', @cmds)) unless (any {$cmd eq $_} @cmds);
	return;
};

sub Netzfrequenz_Attr {
	my ($cmd, $name, $attrName, $attrValue) = @_;
	my $hash = $defs{$name};
	$attrValue //= '';

	if ($cmd eq 'set') {
		if ($attrName eq 'disable') {

		};
		if ($attrName eq 'interval') {

		};

		if (($attrName eq 'processing') and ($attrValue !~ m/^\s*{.*}\s*$/s)) {
			return 'must be perl code enclosed in curly brackets';
		};
	};
	if ($cmd eq 'del') {
		if ($attrName eq 'disable') {

		};
		if ($attrName eq 'interval') {
		
		};
	};
	return;
};

sub  Netzfrequenz_Rename {
	my ($name) = @_;
	my $hash;

	if (exists($defs{$name})) {
		$hash = $defs{$name};
	} else {
		# should not happen
		croak('cannot find me..');
	};
	
	if (ref($hash->{param}) eq 'HASH') {
		$hash->{param}->{name} = $name;
	};
};

sub Netzfrequenz_StartTimer {
	my ($hash, $timeout) = @_;
	my $ts = gettimeofday() + $timeout;
	InternalTimer($ts, \&Netzfrequenz_ApiRequest, $hash);
	return;
};

sub Netzfrequenz_StopTimer {
	my ($hash) = @_;
	RemoveInternalTimer($hash, \&Netzfrequenz_ApiRequest);
	return;
};

sub Netzfrequenz_ApiRequest {
	my ($hash) = @_;

	$hash->{param} //= {
		url => "https://www.netzfrequenz.info/json/act.json",
		timeout => 5,
		name => $hash->{NAME}, # prevent circular ref
		method => "GET",
		keepalive => 1,
		header => "User-Agent: fhem/Netzfrequenz $hash->{SVN}\r\nccept-Charset: utf-8, iso-8859-1",
		httpversion => "1.1",
		callback => \&Netzfrequenz_ApiResponse
	};

	HttpUtils_NonblockingGet($hash->{param});
	return;
};

sub Netzfrequenz_ApiResponse {
	my ($param, $err, $data) = @_;

	#use Data::Dumper;
	#print Dumper $param;
	
	my $name = $param->{name};
	my $hash;
	
	if (exists($defs{$name})) {
		$hash = $defs{$name};
	};

	# should not happen
	croak('cannot find me..') unless $hash;

	my $timeout = 1;

	if ($data and looks_like_number($data)) {
		my $actual = sprintf('%.3f', $data);

		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'frequency', $actual);
		readingsEndUpdate($hash, 1);

		if (my $p = AttrVal($name, 'processing', undef)) {
			local $_ = $actual;
			if ($p =~ m/^\s*{.*}\s*$/s) {
				eval $p;
			# } else {
			# 	$p =~ s/\$_/$actual/g;
			# 	eval "fhem $p";
			# 	say "fhem '$p'";
			# 	say $@ if $@;
			};
		};
	} else {
		$timeout = 60;
	};

	Netzfrequenz_StartTimer($hash, $timeout);
	return;
};

1;

=pod
=item device
=item summary 		shows the actual frenquency of the german power grid
=item summary_DE	zeigt die aktuelle Netzfrequenz an
=begin html

<a name="Netzfrequenz"></a>
<h3>Netzfrequenz</h3>
<ul>
	displays the actual frenquency of the german power grid
</ul>

<ul>
	<a name="Netzfrequenzdefine"></a>
	<b>Define</b>
	<ul>
    	<code>define &lt;name&gt; Netzfrequenz</code>
    	<br><br>
    	defines the device.
	</ul>
</ul>

=end html

=cut
