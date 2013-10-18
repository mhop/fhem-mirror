package Device::Firmata::Base;

use strict 'vars', 'subs';
use vars qw/
    $AUTOLOAD
    $FIRMATA_DEBUG_LEVEL
    $FIRMATA_ERROR_CLASS
    $FIRMATA_ERROR
    $FIRMATA_ATTRIBS
    $FIRMATA_DEBUGGING
    $FIRMATA_LOCALE
    $FIRMATA_LOCALE_PATH
    $FIRMATA_LOCALE_MESSAGES
/;

=head1 NAME

Device::Firmata::Base -- Abstract baseclass for Device::Firmata modules

=cut

$FIRMATA_DEBUGGING = 1;
$FIRMATA_ATTRIBS = {};
$FIRMATA_LOCALE = 'en';
$FIRMATA_LOCALE_PATH = '.';
$FIRMATA_DEBUG_LEVEL = 0;
$FIRMATA_ERROR_CLASS = 'Device::Firmata::Error';

=head1 METHODS

=head2 import

Ease setting of configuration options

=cut

sub import {
  my $self = shift;
  my $pkg  = caller;
  my $config_opts = {
    debugging       => $FIRMATA_DEBUGGING,
  };

  if ( @_ ) {
    my $opts = $self->parameters( @_ );
    if ( my $attrs = $opts->{FIRMATA_ATTRIBS} ) {
      *{$pkg.'::FIRMATA_ATTRIBS'} = \$attrs;
    }

    unless ( ref *{$pkg.'::ISA'} eq 'ARRAY' and @${$pkg.'::ISA'}) {
      my @ISA = ref $opts->{ISA} ? @{$opts->{ISA}} :
        $opts->{ISA} ? $opts->{ISA} :
         __PACKAGE__;
      *{$pkg.'::ISA'} = \@ISA;
    }
    use strict;
    $self->SUPER::import( @_ );
  }
}

=head2 new

=cut

sub new {
    my $pkg = shift;
    my $basis = copy_struct( $pkg->init_class_attribs );
    my $self = bless $basis, $pkg;

    @_ = $self->pre_init( @_ ) if $self->{_biofunc_pre_init};

    if ( $self->{_biofunc_init} ) {
        $self->init( @_ );
    }
    else {
        $self->init_instance_attribs( @_ );
    }

    return $self->post_init if $self->{_biofunc_post_init};
    return $self;
}

=head2 create

A soft new as some objects will override new and
we don't want to cause problems but still want
to invoice our creation code

=cut

sub create {
    my $self = shift;
    my $basis = copy_struct( $self->init_class_attribs );

    @$self{ keys %$basis } = values %$basis;

    @_ = $self->pre_init( @_ ) if $self->{_biofunc_pre_init};

    if ( $self->{_biofunc_init} ) {
        $self->init( @_ );
    }
    else {
        $self->init_instance_attribs( @_ );
    }

    return $self->post_init if $self->{_biofunc_post_init};
    return $self;
}

=head2 init_instance_attribs

=cut

sub init_instance_attribs {
# --------------------------------------------------
    my $self = shift;
    my $opts = $self->parameters( @_ );

    foreach my $k ( keys %$self ) {
        next unless exists $opts->{$k};
        next if $k =~ /^_biofunc/;
        $self->{$k} = $opts->{$k};
    }

    return $self;
}

=head2 init_class_attribs

=cut

sub init_class_attribs {
# --------------------------------------------------
    my $class       = ref $_[0] || shift;
    my $track       = { $class => 1, @_ ? %{$_[0]} : () };

    return ${"${class}::ABSOLUTE_ATTRIBS"} if ${"${class}::ABSOLUTE_ATTRIBS"};

    my $u = ${"${class}::FIRMATA_ATTRIBS"} || {};

    for my $c ( @{"${class}::ISA"} ) {
        next unless ${"${c}::FIRMATA_ATTRIBS"};

        my $h;
        if ( ${"${c}::ABSOLUTE_ATTRIBS"} ) {
            $h = ${"${c}::ABSOLUTE_ATTRIBS"};
        }
        else {
            $c->fatal( "Cyclic dependancy!" ) if $track->{$c};
            $h = $c->init_class_attribs( $c, $track );
        }

        foreach my $k ( keys %$h ) {
            next if exists $u->{$k};
            $u->{$k} = copy_struct( $h->{$k} );
        }
    }

    foreach my $f ( qw( pre_init init post_init ) ) {
        $u->{"_biofunc_" . $f} = $class->can( $f ) ? 1 : 0;
    }

    ${"${class}::ABSOLUTE_ATTRIBS"} = $u;

    return $u;
}

# logging/exception functions



# Utilty functions

=head2 parameters

=cut

sub parameters {
# --------------------------------------------------
    return {} unless @_ > 1;

    if ( @_ == 2 ) {
        return $_[1] if ref $_[1];
        return; # something wierd happened
    }

    @_ % 2 or $_[0]->warn( "Even number of elements were not passed to call.", join( " ", caller() )  );

    shift;

    return {@_};
}

=head2 copy_struct

=cut

sub copy_struct {
# --------------------------------------------------
    my $s = shift;

    if ( ref $s ) {
        if ( UNIVERSAL::isa( $s, 'HASH' ) ) {
            return {
                map { my $v = $s->{$_}; (
                    $_ => ref $v ? copy_struct( $v ) : $v
                )} keys %$s
            };
        }
        elsif ( UNIVERSAL::isa( $s, 'ARRAY' ) ) {
            return [
                map { ref $_ ? copy_struct($_) : $_ } @$s
            ];
        }
        die "Cannot copy struct! : ".ref($s);
    }

    return $s;
}

=head2 locale

=cut

sub locale {
# --------------------------------------------------
    @_ >= 2 and shift;
    $FIRMATA_LOCALE = shift;
}

=head2 locale_path

=cut

sub locale_path {
# --------------------------------------------------
    @_ >= 2 and shift;
    $FIRMATA_LOCALE_PATH = shift;
}

=head2 language

=cut

sub language {
# --------------------------------------------------
    my $self = shift;
    require Device::Firmata::Language;
    return Device::Firmata::Language->language(@_);
}

=head2 error

=cut

sub error {
# --------------------------------------------------
# Handle any error messages
#
    my $self = shift;
    if ( @_ ) {
        my $err_msg = $self->init_error->error(@_);
        $self->{error} = $err_msg;
        return;
    }

    my $err_msg = $self->{error};
    $self->{error} = '';
    return $err_msg;
}

=head2 init_error

Creates the global error object that will collect
all error messages generated on the system. This
function can be called as many times as desired.

=cut

sub init_error {
# --------------------------------------------------
#
    $FIRMATA_ERROR and return $FIRMATA_ERROR;

    if ( $FIRMATA_ERROR_CLASS eq 'Device::Firmata::Error' ) {
        require Device::Firmata::Error;
        return $FIRMATA_ERROR = $FIRMATA_ERROR_CLASS;
    }

# Try and load the file. Use default if fails
    eval "require $FIRMATA_ERROR_CLASS";
    $@ and return $FIRMATA_ERROR = $FIRMATA_ERROR_CLASS;

# Try and init the error object. Use default if fails
    eval { $FIRMATA_ERROR = $FIRMATA_ERROR_CLASS->new(); };
    $@ and return $FIRMATA_ERROR = $FIRMATA_ERROR_CLASS;
    return $FIRMATA_ERROR;
}

=head2 fatal

Handle tragic and unrecoverable messages

=cut

sub fatal {
# --------------------------------------------------
#
    my $self = shift;
    return $self->error( -1, @_ );
}

=head2 warn

Handle tragic and unrecoverable messages

=cut

sub warn {
# --------------------------------------------------
#
    my $self = shift;
    return $self->error( 0, @_ );
}

=head2 debug

=cut

sub debug {
# --------------------------------------------------
    my ( $self, $debug ) = @_;
    $FIRMATA_DEBUG_LEVEL = $debug;
}

=head2 DESTROY

=cut

sub DESTROY {
# --------------------------------------------------
    my $self = shift;
}

=head2 AUTOLOAD

=cut

sub AUTOLOAD {
# --------------------------------------------------
    my $self = shift;
    my ($attrib) = $AUTOLOAD =~ /::([^:]+)$/;

    if ( $self and UNIVERSAL::isa( $self, 'Device::Firmata::Base' ) ) {
        $self->error( FIRMATA__unhandled => $attrib, join( " ", caller() ) );
        die $self->error;
    }
    else {
        die "Tried to call function '$attrib' via object '$self' @ ", join( " ", caller(1) ), "\n";
    }

}

####################################################
# Object instantiation code
####################################################

=head2 object_load

Load the appropriate package and attempt to initialize
the object as well

=cut

sub object_load {
# --------------------------------------------------
    my $self         = shift;
    my $object_class = shift;
    return unless $object_class =~ /^\w+(?:::\w+)*$/; # TODO ERROR MESSAGE
    eval "require $object_class; 1" or die $@;
    my $object      = $object_class->new(@_);
    return $object;
}


1;
