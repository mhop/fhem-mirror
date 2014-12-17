package UPnP::Common;

use 5.006;
use strict;
use warnings;

use HTTP::Headers;
use IO::Socket;

use     vars qw(@EXPORT $VERSION @ISA $AUTOLOAD);

require Exporter;

our @ISA = qw(Exporter);
our $VERSION = '0.03';

my %XP_CONSTANTS = (
    SSDP_IP => "239.255.255.250",
    SSDP_PORT => 1900,
    CRLF => "\015\012",
    IP_LEVEL => getprotobyname('ip') || 0,
);

#ALW - Changed from 'MSWin32' => [3,5],
my @MD_CONSTANTS = qw(IP_MULTICAST_TTL IP_ADD_MEMBERSHIP);
my %MD_CONSTANT_VALUES = (
	'MSWin32' => [10,12],
	'cygwin' => [3,5],
	'darwin' => [10,12],
	'linux' => [33,35],
	'default' => [33,35],
);

@EXPORT = qw();

use constant PROBE_IP => "239.255.255.251";
use constant PROBE_PORT => 8950;

my $ref = $MD_CONSTANT_VALUES{$^O};
if (!defined($ref)) {
	$ref = $MD_CONSTANT_VALUES{default};
}
my $consts;
for my $name (keys %XP_CONSTANTS) {
	$consts .= "use constant $name => \'" . $XP_CONSTANTS{$name} . "\';\n";
}
for my $index (0..$#MD_CONSTANTS) {
	my $name = $MD_CONSTANTS[$index];
	$consts .= "use constant $name => \'" . $ref->[$index] . "\';\n";
}

#warn $consts; # for development
eval $consts;
push @EXPORT, (keys %XP_CONSTANTS, @MD_CONSTANTS);

#findLocalIP();

my %typeMap = (
	'ui1' => 'int',
	'ui2' => 'int',
	'ui4' => 'int',
	'i1' => 'int',
	'i2' => 'int',
	'i4' => 'int',
	'int' => 'int',
	'r4' => 'float',
	'r8' => 'float',
	'number' => 'float',
	'fixed' => 'float',
	'float' => 'float',
	'char' => 'string',
	'string' => 'string',
	'date' => 'timeInstant',
	'dateTime.tz' => 'timeInstant',
	'time' => 'timeInstant',
	'time.tz' => 'timeInstant',
	'boolean' => 'boolean',
	'bin.base64' => 'base64Binary',
	'bin.hex' => 'hexBinary',
	'uri' => 'uriReference',
	'uuid' => 'string',
);

BEGIN {
	use SOAP::Lite;
	$SOAP::Constants::DO_NOT_USE_XML_PARSER = 1;
}

sub getLocalIP {
    if (defined $UPnP::Common::LocalIP) {
        return $UPnP::Common::LocalIP;
    }

    my $probeSocket = IO::Socket::INET->new(Proto => 'udp',
                                             Reuse => 1);

    my $listenSocket = IO::Socket::INET->new(Proto => 'udp',
                                             Reuse => 1,
                                             LocalPort => PROBE_PORT);
    my $ip_mreq = inet_aton(PROBE_IP) . INADDR_ANY;
    setsockopt($listenSocket, 
                       getprotobyname('ip'),
                       $ref->[1],
                       $ip_mreq);

    my $destaddr = sockaddr_in(PROBE_PORT, inet_aton(PROBE_IP));
    send($probeSocket, "Test", 0, $destaddr);

    my $buf = '';
    my $peer = recv($listenSocket, $buf, 2048, 0);
    my ($port, $addr) = sockaddr_in($peer);
    
    $probeSocket->close;
    $listenSocket->close;

    setLocalIP($addr);
    return $UPnP::Common::LocalIP;
}

sub setLocalIP {
    my ($addr) = @_;
    $UPnP::Common::LocalIP = inet_ntoa($addr);
}

sub parseHTTPHeaders {
	my $buf = shift;
	my $headers = HTTP::Headers->new;
	
	# Header parsing code borrowed from HTTP::Daemon
	my($key, $val);
  HEADER:
	while ($buf =~ s/^([^\012]*)\012//) {
	    $_ = $1;
	    s/\015$//;
	    if (/^([^:\s]+)\s*:\s*(.*)/) {
			$headers->push_header($key => $val) if $key;
			($key, $val) = ($1, $2);
	    }
	    elsif (/^\s+(.*)/) {
			$val .= " $1";
	    }
	    else {
			last HEADER;
	    }
	}
	$headers->push_header($key => $val) if $key;

	return $headers;
}

sub UPnPToSOAPType {
	my $upnpType = shift;
	return $typeMap{$upnpType};
}

# ----------------------------------------------------------------------

package UPnP::Common::DeviceLoader;

use strict;

sub new {
	my $self = shift;
	my $class = ref($self) || $self;

    return bless {
		_parser => UPnP::Common::Parser->new,
	}, $class;
}

sub parser {
	my $self = shift;
	return $self->{_parser};
}

sub parseServiceElement {
	my $self = shift;
	my $element = shift;
	my($name, $attrs, $children) = @$element;

	my $service = $self->newService(%{$_[1]});
	for my $childElement (@$children) {
		my $childName = $childElement->[0];

		if (UPnP::Common::Service::isProperty($childName)) {
			my $value = $childElement->[2];
			$service->$childName($value);
		}
	}

	return $service;
}

sub parseDeviceElement {
	my $self = shift;
	my $element = shift;
	my $parent = shift;
	my($name, $attrs, $children) = @$element;

	my $device = $self->newDevice(%{$_[0]});
	$device->parent($parent);
	for my $childElement (@$children) {
		my $childName = $childElement->[0];

		if ($childName eq 'deviceList') {
			my $childDevices = $childElement->[2];
                        next if (ref $childDevices ne "ARRAY");
			for my $deviceElement (@$childDevices) {
				my $childDevice = $self->parseDeviceElement($deviceElement, 
															$device,
															@_);
				if ($childDevice) {
					$device->addChild($childDevice);
				}
			}
		}
		elsif ($childName eq 'serviceList') {
			my $services = $childElement->[2];
			for my $serviceElement (@$services) {
				my $service = $self->parseServiceElement($serviceElement,
														 @_);
				if ($service) {
					$device->addService($service);
				}
			}
		}
		elsif (UPnP::Common::Device::isProperty($childName)) {
			my $value = $childElement->[2];
			$device->$childName($value);
		}
	}

	return $device;
}

sub parseDeviceDescription {
	my $self = shift;
	my $description = shift;
	my ($base, $device);

	my $parser = $self->parser;
	my $element = $parser->parse($description);
	if (defined($element) && ref $element eq 'ARRAY') {
		my($name, $attrs, $children) = @$element;
		for my $child (@$children) {
			my ($childName) = @$child;
			if ($childName eq 'URLBase') {
				$base = $child->[2];
			}
			elsif ($childName eq 'device') {
				$device = $self->parseDeviceElement($child, 
													undef,
													@_);
			}
		}
	}

	return ($device, $base);
}

# ----------------------------------------------------------------------

package UPnP::Common::Device;

use strict;

use Carp;
use Scalar::Util qw(weaken);

use vars qw($AUTOLOAD %deviceProperties);
for my $prop (qw(deviceType friendlyName manufacturer 
				 manufacturerURL modelDescription modelName 
				 modelNumber modelURL serialNumber UDN
				 presentationURL UPC location)) {
	$deviceProperties{$prop}++;
}

sub new {
	my $self = shift;
	my $class = ref($self) || $self;
	my %args = @_;

    $self = bless {}, $class;
	if ($args{Location}) {
		$self->location($args{Location});
	}

	return $self;
}

sub addChild {
    my $self = shift;
	my $child = shift;

	push @{$self->{_children}}, $child;
}

sub addService {
    my $self = shift;
	my $service = shift;

	push @{$self->{_services}}, $service;
}

sub parent {
    my $self = shift;

	if (@_) {
		$self->{_parent} = shift;
		weaken($self->{_parent});
	}

	return $self->{_parent};
}

sub children {
    my $self = shift;
	
	if (ref $self->{_children}) {
		return @{$self->{_children}};
	}

	return ();
}

sub services {
    my $self = shift;
	
	if (ref $self->{_services}) {
		return @{$self->{_services}};
	}

	return ();
}

sub getService {
    my $self = shift;
	my $id = shift;

	for my $service ($self->services) {
		if ($id && 
			($id eq $service->serviceId) ||
			($id eq $service->serviceType)) {
			return $service;
		}
	}

	return undef;
}

sub isProperty {
	my $prop = shift;
	return $deviceProperties{$prop};
}

sub AUTOLOAD {
    my $self = shift;
    my $attr = $AUTOLOAD;
    $attr =~ s/.*:://;
    return if $attr eq 'DESTROY';   

    croak "invalid attribute method: ->$attr()" unless $deviceProperties{$attr};

	$self->{uc $attr} = shift if @_;
	return $self->{uc $attr};
}

# ----------------------------------------------------------------------

package UPnP::Common::Service;

use strict;

use SOAP::Lite;
use Carp;

use vars qw($AUTOLOAD %serviceProperties);
for my $prop (qw(serviceType serviceId SCPDURL controlURL
				 eventSubURL base)) {
	$serviceProperties{$prop}++;
}

sub new {
	my $self = shift;
	my $class = ref($self) || $self;

    return bless {}, $class;
}

sub AUTOLOAD {
    my $self = shift;
    my $attr = $AUTOLOAD;
    $attr =~ s/.*:://;
    return if $attr eq 'DESTROY';   

    croak "invalid attribute method: ->$attr()" unless $serviceProperties{$attr};

	$self->{uc $attr} = shift if @_;
	return $self->{uc $attr};
}

sub isProperty {
	my $prop = shift;
	return $serviceProperties{$prop};
}

sub addAction {
	my $self = shift;
	my $action = shift;

	$self->{_actions}->{$action->name} = $action;
}

sub addStateVariable {
	my $self = shift;
	my $var = shift;

	$self->{_stateVariables}->{$var->name} = $var;
}

sub actions {
	my $self = shift;

	$self->_loadDescription;
	
	if (defined($self->{_actions})) {
		return values %{$self->{_actions}};
	}

	return ();
}

sub getAction {
 	my $self = shift;
	my $name = shift;

	$self->_loadDescription;

	if (defined($self->{_actions})) {
		return $self->{_actions}->{$name};
	}

	return undef;
}

sub stateVariables {
 	my $self = shift;

	$self->_loadDescription;

	if (defined($self->{_stateVariables})) {
		return values %{$self->{_stateVariables}};
	}

	return ();
}

sub getStateVariable {
 	my $self = shift;
	my $name = shift;

	$self->_loadDescription;

	if (defined($self->{_stateVariables})) {
		return $self->{_stateVariables}->{$name};
	}

	return undef;
}

sub getArgumentType {
	my $self = shift;
	my $arg = shift;

	$self->_loadDescription;

	my $var = $self->getStateVariable($arg->relatedStateVariable);
	if ($var) {
		return $var->SOAPType;
	}

	return undef;
}

sub _parseArgumentList {
	my $self = shift;
	my $list = shift;
	my $action = shift;

        return if (! ref $list);

	for my $argumentElement (@$list) {
		my($name, $attrs, $children) = @$argumentElement;
		if ($name eq 'argument') {
			my $argument = UPnP::Common::Argument->new;
			for my $argumentChild (@$children) {
				my ($childName) = @$argumentChild;
				if ($childName eq 'name') {
					$argument->name($argumentChild->[2]);
				}
				elsif ($childName eq 'direction') {
					my $direction = $argumentChild->[2];
					if ($direction eq 'in') {
						$action->addInArgument($argument);
					}
					elsif ($direction eq 'out') {
						$action->addOutArgument($argument);
					}
				}
				elsif ($childName eq 'relatedStateVariable') {
					$argument->relatedStateVariable($argumentChild->[2]);
				}
				elsif ($childName eq 'retval') {
					$action->retval($argument);
				}
			}
		}
	}
}

sub _parseActionList {
	my $self = shift;
	my $list = shift;

	for my $actionElement (@$list) {
		my($name, $attrs, $children) = @$actionElement;
		if ($name eq 'action') {
			my $action = UPnP::Common::Action->new;
			for my $actionChild (@$children) {
				my ($childName) = @$actionChild;
				if ($childName eq 'name') {
					$action->name($actionChild->[2]);
				}
				elsif ($childName eq 'argumentList') {
					$self->_parseArgumentList($actionChild->[2],
											  $action);
				}
			}
			$self->addAction($action);
		}
	}
}

sub _parseStateTable {
	my $self = shift;
	my $list = shift;

	for my $varElement (@$list) {
		my($name, $attrs, $children) = @$varElement;
		if ($name eq 'stateVariable') {
			my $var = UPnP::Common::StateVariable->new(exists $attrs->{sendEvents} && ($attrs->{sendEvents} eq 'yes'));
			for my $varChild (@$children) {
				my ($childName) = @$varChild;
				if ($childName eq 'name') {
					$var->name($varChild->[2]);
				}
				elsif ($childName eq 'dataType') {
					$var->type($varChild->[2]);
				}
			}
			$self->addStateVariable($var);
		}
	}
}

sub parseServiceDescription {
	my $self = shift;
	my $parser = shift;
	my $description = shift;

	my $element = $parser->parse($description);
	if (defined($element) && ref $element eq 'ARRAY') {
		my($name, $attrs, $children) = @$element;
		for my $child (@$children) {
			my ($childName) = @$child;
			if ($childName eq 'actionList') {
				$self->_parseActionList($child->[2]);
			}
			elsif ($childName eq 'serviceStateTable') {
				$self->_parseStateTable($child->[2]);
			}
		}
	}
	else {
		carp("Malformed SCPD document");
	}
}

# ----------------------------------------------------------------------

package UPnP::Common::Action;

use strict;

use Carp;

use vars qw($AUTOLOAD %actionProperties);
for my $prop (qw(name retval)) {
	$actionProperties{$prop}++;
}

sub new {
	return bless {}, shift;
}

sub AUTOLOAD {
    my $self = shift;
    my $attr = $AUTOLOAD;
    $attr =~ s/.*:://;
    return if $attr eq 'DESTROY';   

    croak "invalid attribute method: ->$attr()" unless $actionProperties{$attr};

	$self->{uc $attr} = shift if @_;
	return $self->{uc $attr};
}

sub addInArgument {
	my $self = shift;
	my $argument = shift;

	push @{$self->{_inArguments}}, $argument;
}

sub addOutArgument {
	my $self = shift;
	my $argument = shift;

	push @{$self->{_outArguments}}, $argument;
}

sub inArguments {
	my $self = shift;

	if (defined $self->{_inArguments}) {
		return @{$self->{_inArguments}};
	}

	return ();
}

sub outArguments {
	my $self = shift;

	if (defined $self->{_outArguments}) {
		return @{$self->{_outArguments}};
	}

	return ();
}

sub arguments {
	my $self = shift;

	return ($self->inArguments, $self->outArguments);
}

# ----------------------------------------------------------------------

package UPnP::Common::Argument;

use strict;

use Carp;

use vars qw($AUTOLOAD %argumentProperties);
for my $prop (qw(name relatedStateVariable)) {
	$argumentProperties{$prop}++;
}

sub new {
	return bless {}, shift;
}

sub AUTOLOAD {
    my $self = shift;
    my $attr = $AUTOLOAD;
    $attr =~ s/.*:://;
    return if $attr eq 'DESTROY';   

    croak "invalid attribute method: ->$attr()" unless $argumentProperties{$attr};

	$self->{uc $attr} = shift if @_;
	return $self->{uc $attr};
}

# ----------------------------------------------------------------------

package UPnP::Common::StateVariable;

use strict;

use Carp;

use vars qw($AUTOLOAD %varProperties);
for my $prop (qw(name type evented)) {
	$varProperties{$prop}++;
}

sub new {
	my $self = bless {}, shift;
	$self->evented(shift);
	return $self;
}

sub SOAPType {
	my $self = shift;
	return UPnP::Common::UPnPToSOAPType($self->type);
}

sub AUTOLOAD {
    my $self = shift;
    my $attr = $AUTOLOAD;
    $attr =~ s/.*:://;
    return if $attr eq 'DESTROY';   

    croak "invalid attribute method: ->$attr()" unless $varProperties{$attr};

	$self->{uc $attr} = shift if @_;
	return $self->{uc $attr};
}


# ----------------------------------------------------------------------

package UPnP::Common::Parser;

use XML::Parser::Lite;

# Parser code borrowed from SOAP::Lite. This package uses the
# event-driven XML::Parser::Lite parser to construct a nested data
# structure - a poor man's DOM. Each XML element in the data structure
# is represented by an array ref, with the values (listed by subscript
# below) corresponding with:
# 0 - The element name.
# 1 - A hash ref representing the element attributes.
# 2 - An array ref holding either child elements or concatenated
#     character data.

sub new {
	my $class = shift;

	return bless { _parser => XML::Parser::Lite->new }, $class;
}

sub parse { 
	my $self = shift;
	my $parser = $self->{_parser};

	$parser->setHandlers(Final => sub { shift; $self->final(@_) },
						 Start => sub { shift; $self->start(@_) },
						 End   => sub { shift; $self->end(@_)   },
						 Char  => sub { shift; $self->char(@_)  },);
	$parser->parse(shift);
}

sub final { 
  my $self = shift; 
  my $parser = $self->{_parser};

  # clean handlers, otherwise ControlPoint::Parser won't be deleted: 
  # it refers to XML::Parser which refers to subs from ControlPoint::Parser
  undef $self->{_values};
  $parser->setHandlers(Final => undef, 
					   Start => undef, 
					   End   => undef, 
					   Char  => undef,);
  $self->{_done};
}

sub start { push @{shift->{_values}}, [shift, {@_}] }

sub char { push @{shift->{_values}->[-1]->[3]}, shift }

sub end { 
  my $self = shift; 
  my $done = pop @{$self->{_values}};
  $done->[2] = defined $done->[3] ? join('',@{$done->[3]}) : '' unless ref $done->[2];
  undef $done->[3]; 
  @{$self->{_values}} ? (push @{$self->{_values}->[-1]->[2]}, $done)
                      : ($self->{_done} = $done);
}

1;
__END__

=head1 NAME

UPnP::Common - Internal modules and methods for the UPnP
implementation. The C<UPnP::ControlPoint> and C<UPnP::DeviceManager>
modules should be used.

=head1 DESCRIPTION

Part of the Perl UPnP implementation suite.

=head1 SEE ALSO

UPnP documentation and resources can be found at L<http://www.upnp.org>.

The C<SOAP::Lite> module can be found at L<http://www.soaplite.com>.

UPnP implementations in other languages include the UPnP SDK for Linux
(L<http://upnp.sourceforge.net/>), Cyberlink for Java
(L<http://www.cybergarage.org/net/upnp/java/index.html>) and C++
(L<http://sourceforge.net/projects/clinkcc/>), and the Microsoft UPnP
SDK
(L<http://msdn.microsoft.com/library/default.asp?url=/library/en-us/upnp/upnp/universal_plug_and_play_start_page.asp>).

=head1 AUTHOR

Vidur Apparao (vidurapparao@users.sourceforge.net)

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Vidur Apparao

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
