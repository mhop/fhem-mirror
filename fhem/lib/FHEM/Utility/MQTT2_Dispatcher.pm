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

###############################################################################
#
#     MQTT2_Dispatcher permits any fhem module to act as a MQTT2 Device
#
#
###############################################################################

package FHEM::Utility::MQTT2_Dispatcher;

use 5.018;
use feature qw( lexical_subs );

use strict;
use warnings;
use utf8;
use Carp;
use Encode qw(encode decode find_encoding);

use constant {
	L_SUBSCRIPTION	=> 0,
	L_TEMPLATE		=> 1,
	L_FUNCTION		=> 2,
};

sub import {
	my $import_options = join(' ', @_[1..$#_]);
	my ($package, $filename, $line) = caller;
	
	if (not exists($main::modules{'MQTT2_Dispatcher'})) {
		$main::modules{'MQTT2_Dispatcher'} = __PACKAGE__->new();	
	};

	no strict "refs";

	if ($import_options =~ qr/\bDEFAULT\b/) {
		# on_mqtt
		*{$package.'::on_mqtt'} = sub {
			my ($topic, $fn) = @_;
			if (exists($main::modules{'MQTT2_Dispatcher'})) {
				return $main::modules{'MQTT2_Dispatcher'}->add_listener($topic, $fn);
			};
			return;
		};
		
		# del_mqtt
		*{$package.'::del_mqtt'} = sub {
			my ($fn) = @_;
			if (exists($main::modules{'MQTT2_Dispatcher'})) {
				return $main::modules{'MQTT2_Dispatcher'}->del_listener($fn);
			};
			return;
		};
	};

	_init();
};

sub _init {
	if (exists($main::modules{'MQTT2_Dispatcher'}) and (not $main::modules{'MQTT2_Dispatcher'}->{Pendig})) {
		$main::modules{'MQTT2_Dispatcher'}->{Pendig} = 1;
		main::InternalTimer(0, \&_find_MQTT2, undef);
	};
};

sub _find_MQTT2 {
	foreach my $device (keys %main::defs) {
		if ($main::defs{$device}->{TYPE} =~ qr/^MQTT2_SERVER$|^MQTT2_CLIENT$/) {
			_patch_MQTT2($device);
		};
	};
	$main::modules{'MQTT2_Dispatcher'}->{Pendig} = 0;
};

sub _patch_MQTT2 {
	my ($io_name) = @_;
	my $io_dev = $main::defs{$io_name};

	return if ($io_dev->{Clients} =~ qr/:MQTT2_Dispatcher:/);

	# modify io
	$io_dev->{Clients} = ':MQTT2_Dispatcher'.$io_dev->{Clients};
	$io_dev->{MatchList} = []; # force rebuild

	# also anchor permanently at 'attr clientOrder delete'.
	no warnings qw(redefine prototype);
	
	if (($io_dev->{TYPE}) eq 'MQTT2_CLIENT' and not $io_dev->{'._io_patched'}) {
		my $fn = \&main::MQTT2_CLIENT_resetClients;
		*main::MQTT2_CLIENT_resetClients = sub {
			$fn->(@_);
			$_[0]->{Clients} = ':MQTT2_Dispatcher'.$_[0]->{Clients};
		};
		$io_dev->{'._io_patched'} = 1;
	};

	if (($io_dev->{TYPE}) eq 'MQTT2_SERVER' and not $io_dev->{'._io_patched'}) {
		my $fn = \&main::MQTT2_SERVER_resetClients;
		*main::MQTT2_SERVER_resetClients = sub {
			$fn->(@_);
			$_[0]->{Clients} = ':MQTT2_Dispatcher'.$_[0]->{Clients};
		};
		$io_dev->{'._io_patched'} = 1;
	};

	return;
};

sub _parse {
	my ($io_dev, $dmsg) = @_;
	my @msg = split(/\0/, $dmsg);
	# print "parse $msg[2] $msg[3]\n";
	# UTF-8 to UNICODE converation
	eval {$msg[2] = decode(find_encoding('UTF-8'), $msg[2], Encode::FB_CROAK)};
	if (exists($main::modules{'MQTT2_Dispatcher'})) {
		my $dispatcher = $main::modules{'MQTT2_Dispatcher'};
		# query listener
		foreach my $listener (@{$dispatcher->{Listener}}) {
			if ($msg[2] =~ $listener->[L_TEMPLATE]) {
				# need to call it async, otherwise trigger wont work
				main::InternalTimer(0, sub {
					eval {$listener->[L_FUNCTION]->($msg[2], $msg[3], $io_dev->{NAME})};
					warn $@ if $@;
				}, undef);
			};
		};
	};
	return;
};

sub new {
	my ($class) = @_;

	my $self = {
		Match		=>	qr/^.*/,
		ParseFn		=>	\&_parse,
		Listener	=>	[],
		LOADED		=>	1,
	};

	bless $self, $class;
	return $self;
};

sub add_listener {
	my ($self, $subscription, $fn) = @_;

	# rereadcfg could have wiped the io patch
	if (not $self->{Pendig} and not $main::init_done) {
		$main::modules{'MQTT2_Dispatcher'}->{Pendig} = 1;
		main::InternalTimer(0, \&_find_MQTT2, undef);
	};
	
	my @parts = split('/', $subscription);
	my $template = '^';
	my $seperator = '';

	eval {
		while (defined(my $p = shift @parts)) {
			if ($p eq '#') {
				$template .= '(?:$|'.$seperator.'.+)';
				croak(q('#' must be the last character)) if (scalar @parts);
			} elsif ($p eq '+') {
				$template .= $seperator.'(?:[^\/]*)';
				$seperator = '\/';
			} elsif ($p eq '') {
				$template .= $seperator;
				$seperator = '\/';
			} else {
				croak(q('#' and '+' cannot be part of a topic name)) if ($p =~ m/[#+]/);
				# escape Special Regex Characters
				$p =~ s/([\.\+\*\?\^\$\(\)\[\]\{\}\|\\])/\\$1/g;
				$template .= $seperator.$p;
				$seperator = '\/';
			};
		};
		$template .= '$';
	} or do {
		return;
	};

	my $r = qr/$template/;

	push @{$self->{Listener}}, [$subscription, $r, $fn];
	return $fn;
};

sub del_listener {
	my ($self, $fn) = @_;
	if ($fn and exists($main::modules{'MQTT2_Dispatcher'})) {
		my $dispatcher = $main::modules{'MQTT2_Dispatcher'};
		@{$dispatcher->{Listener}} = grep {$_->[L_FUNCTION] ne $fn} @{$dispatcher->{Listener}};
	};
	return;
};

sub DESTROY {
	my $self = shift;
	$self->SUPER::DESTROY if $self->can("SUPER::DESTROY");
	return;
};

1;
__END__

=head1 NAME

FHEM::Utility::MQTT2_Dispatcher - Subscribe to MQTT messages in fhem modules

=head1 SYNOPSIS

	package main;
	
	use FHEM::Utility::MQTT2_Dispatcher qw( :DEFAULT );

	sub X_Define {
		...

		$hash->{Listener} = on_mqtt('home/#', sub {
			X_MQTT($hash, @_);
		}) or do {
			Log3($hash, 2, $@);
		};
	};
	
	sub X_MQTT {
		my ($hash, $topic, $value, $io_name) = @_;
	};

	# required for rereadcfg etc
	sub X_Undef {
		...
		del_mqtt($hash->{Listener});
		return;
	};

=head1 DESCRIPTION
 
This module provides a couple of helper functions to let a fhem module 
subscripe to MQTT topics using a defined MQTT2_SERVER or MQTT2_CLIENT.
 
=head1 FUNCTIONS

=over 4
 
=item C<on_mqtt ($topic, sub {})>
 
This function subscribes to a given C<$topic>. MQTT wildcards are allowed. The 
MQTT2 IO device, of course, must receive that topic. The coderef can be 
an anonyious sub or a variable holding one. This function receive 3 params: 
the C<$topic> (unicode), the C<$value> (raw) and the C<$name> of the receiving 
IO device.
 
Returns an identifier that is used to delete that handler at any time. Undef 
in case of an error.

Multiple handlers can be installed at the same time.
 
=item C<del_mqtt ($id)>
 
This function removes (deletes) the handler specified with C<$id>. It must be 
called in C<X_Undef> function of the embedding fhem module.
 
=back
 
=head1 AUTHOR
 
Joerg Herrmann
 
=head1 COPYRIGHT AND LICENSE
 
This file is part of fhem.

Fhem is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 2 of the License, or
(at your option) any later version.

Fhem is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with fhem.  If not, see <http://www.gnu.org/licenses/>.
 
=cut
