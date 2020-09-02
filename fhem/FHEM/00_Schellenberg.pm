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

# Thanks to hypfer for doing the basic research 

package main;

use 5.018;
use feature qw( lexical_subs );

use strict;
use warnings;
use utf8;
use DevIo;

no warnings qw( experimental::lexical_subs );

sub Schellenberg_Initialize {
	my ($hash) = @_;

	$hash->{'DefFn'}				= 'Schellenberg_Define';
	$hash->{'UndefFn'}				= 'Schellenberg_Undef';
	#$hash->{'DeleteFn'}				= 'Schellenberg_Delete';
	$hash->{'SetFn'}				= 'Schellenberg_Set';
	#$hash->{'ReadFn'}				= "Schellenberg_Read";
	$hash->{'ReadyFn'}				= 'Schellenberg_Ready';

	$hash->{'Clients'}				= "Schellenberg.+";
	$hash->{'MatchList'}			= {
		'0:SchellenbergHandle'		=> '^ss[[:xdigit:]]{1}4[[:xdigit:]]{16}'
	};
	$hash->{'AttrList'}				= $readingFnAttributes;

	return;
};

sub Schellenberg_Define {
	my ($hash, $def) = @_;
	my ($name, $type, $device) = split /\s/, $def, 3;

	my $cvsid = '$Id$';
	$cvsid =~ s/^.*pm\s//;
	$cvsid =~ s/Z\s\S+\s\$$/ UTC/;
	$hash->{'SVN'} = $cvsid;

	return "no interface given" unless($device);
	DevIo_CloseDev($hash) if (DevIo_IsOpen($hash));
	$device .= '@38400' if ($device !~ m/\@\d+$/);
	$hash->{'DeviceName'} = $device;

	my $result = DevIo_OpenDev($hash, 0, "Schellenberg_Init"); 

	return;
};

sub Schellenberg_Init {
	my ($hash) = @_;

	# my ($p, $id, $cmd, $counter) = unpack ('(H)(H3)', '14CB413E1A02D914A9');

	# use Data::Dumper;
	# print Dumper $p;
	# print Dumper $id;

	my $function;

	# forward
	sub expectVersion;
	sub expectOK;
	sub expectSome;

	#my $test = 0;

	my sub expectSome {
		my ($msg) = @_;

		my $found = Dispatch($hash, $msg);
		return;
	};

	my sub expectOK {
		my ($msg) = @_;
		#print "incoming OK -----> msg $msg\r";
		$function = \&expectSome;
		DevIo_SimpleWrite($hash, "OK\r\n", 2);
	};

	my sub expectVersion {
		my ($msg) = @_;
		#print "incoming VERSION -----> msg $msg\r";
		$function = \&expectOK;
		DevIo_SimpleWrite($hash, "!G\r\n", 2);
	};

	my sub receive {
		my $data = DevIo_SimpleRead($hash);

		#say "receive";

		$hash->{'PARTIAL'} .= $data;
		while ($hash->{'PARTIAL'} =~ m/\r\n/) {
			(my $msg, $hash->{'PARTIAL'}) = split (/\r\n/, $hash->{'PARTIAL'}, 2);
			$function->($msg);
		};
	};

	$hash->{'directReadFn'} = \&receive;
	$function = \&expectVersion;
	DevIo_SimpleWrite($hash, "!?\r\n", 2);
};

sub Schellenberg_Undef {
	my ($hash) = @_;

	RemoveInternalTimer($hash, \&SSchellenberg_ResetPairTimer);
	DevIo_CloseDev($hash);
	return undef;
};

sub Schellenberg_Set {
	my ($hash, $name, $cmd, @args) = @_;

	return "Unknown argument $cmd, choose one of pair" if ($cmd eq '?');

	if ($cmd eq 'send' and $args[0]) {
			DevIo_SimpleWrite($hash, "$args[0]\r\n", 2);
	} elsif ($cmd eq 'pair') {
		my $t = $args[0] || 60;
		return 'missing time (seconds)' if ($t !~ m/[0-9]+/);
		$hash->{'PAIRING'} = 1;
		InternalTimer(Time::HiRes::time() + $t, \&Schellenberg_ResetPairTimer, $hash);
	};

	return;
};

sub Schellenberg_ResetPairTimer {
	my ($hash) = @_;

	delete $hash->{'PAIRING'};
	return;
};

sub Schellenberg_Ready {
	my ($hash) = @_;

	return DevIo_OpenDev($hash, 1, "Schellenberg_Init");
};


1;

=pod
=item device
=item summary 		Schellenberg USB RF-Dongle Receiver
=item summary_DE	Schellenberg USB Funk-Stick Empfänger
=begin html

<a name="Schellenberg"></a>
<h3>Schellenberg</h3>
<ul>
	Schellenberg USB RF Dongle.
</ul>
<ul>
	<a name="Schellenbergdefine"></a>
	<b>Define</b>
	<ul>
    	<code>define &lt;name&gt; Schellenberg &lt;/dev/serial/by-id/usb-schellenberg_ENAS_000000000000-if00&gt;</code>
    	<br><br>
    	defines the device and set the port
	</ul>
	<br>

	<a name="Schellenbergset"></a>
	<b>Set</b>
	<ul>
		<li>pair
			<ul>
				<code>set &lt;name&gt; pair &lt;seconds&gt;</code>
				<br><br>
				enable pair mode for seconds
			</ul>
		</li>
	</ul>
	<br>
</ul>
=end html

=cut