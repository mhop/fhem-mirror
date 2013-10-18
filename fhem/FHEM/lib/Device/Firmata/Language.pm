package Device::Firmata::Language;
# ==================================================================

=head1 NAME

Device::Firmata::Language - Localization

=cut

use strict;
use vars qw/
        $FIRMATA_LOCALE
        $FIRMATA_LOCALE_PATH
        $FIRMATA_LOCALE_MESSAGES
    /;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
        messages => {},
    };

$FIRMATA_LOCALE_MESSAGES = {
};
$FIRMATA_LOCALE = 'en';
$FIRMATA_LOCALE_PATH = '.';


=head2 numbers

=cut

sub numbers {
# --------------------------------------------------
}


=head2 date

=cut

sub date {
# --------------------------------------------------
}


=head2 language

=cut

sub language {
# --------------------------------------------------
    my $self = shift;

    my $messages = $FIRMATA_LOCALE_MESSAGES->{$FIRMATA_LOCALE} ||= do {
        my $target_fpath = "$FIRMATA_LOCALE_PATH/$FIRMATA_LOCALE.txt";

        my $m;
        require Symbol;
        my $fh = Symbol::gensym();

        if ( -f $target_fpath ) {
            open $fh, "<$target_fpath" or die $!;
        }
        else {
            $fh = \*DATA;
        }

        while ( my $l = <$fh>  ) {
            next if $l =~ /^\s*$/;
            $l =~ /([^\s]*)\s+(.*)/;
            ( $m ||= {} )->{$1} = $2;
        }
        close $fh;
        $m;
    };

# This will parse messages coming through such that it will
# be possible to encode a language string with a code in the
# following formats:
#
#      ->language( "CODE", $parametrs ...  )
#      ->language( "CODE:Default Message %s", $parametrs ...  )
#
    my $message = shift or return;
    $message    =~ s/^([\w_]+)\s*:?\s*//;
    my $key     = $1;
    my $message_template;

# Get the message template in the following order:
#   1. The local object if available
#   2. The global message object
#   3. The provided default message
#
    ref $self and $message_template = $self->{messages}{$key};
    $message_template ||= $messages->{$key} || $message;
    return sprintf( $message_template, @_ );
}

1;

__DATA__
FIRMATA__unhandled        Unhandled attribute '%s' called
FIRMATA__unknown          Unknown/Unhandled error encountered: %s

FIRMATA__separator ,

