###############################################################################
#
# Developed with Kate
#
#  (c) 2021 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################

package FHEM::Core::Authentication::Passwords;

use 5.008;

use strict;
use warnings;


### eigene Funktionen exportieren
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
                     new
                     setStorePassword
                     setDeletePassword
                     getReadPassword
                     setRename
);
our %EXPORT_TAGS = (
    ALL => [
        qw(
            new
            setStorePassword
            setDeletePassword
            getReadPassword
            setRename
          )
    ],
);


sub new {
    my $class = shift;
    my $self  = {
                  name  => undef,
                };

    bless $self, $class;
    return $self;
}

sub setStorePassword {
    my $self        = shift;
    my $name        = shift;
    my $password    = shift // return(undef,q{no password given});

    my $index   = $::defs{$name}->{TYPE} . '_' . $name . '_passkey';
    my ($x,$y)  = ::gettimeofday();
    my $salt    = substr(sprintf("%08X", rand($y)*rand($x)),0,8);
    my $key     = ::getUniqueId() . $index . $salt;
    my $enc_pwd = '';

    if ( eval q{use Digest::SHA;1} ) {

        $key = Digest::SHA::sha256_hex( unpack "H*", $key );
        $key .= Digest::SHA::sha256_hex($key);
    }

    for my $char ( split //, $password ) {

        my $encode = chop($key);
        $enc_pwd .= sprintf( "%.2x", ord($char) ^ ord($encode) );
        $key = $encode . $key;
    }

    my $err;
    $err = ::setKeyValue( $index, $salt . $enc_pwd );

    return(undef,$err)
      if ( defined($err) );

    return(1);
}

sub setDeletePassword {
    my $self = shift;
    my $name = shift;

    my $err; 
    $err = ::setKeyValue( $::defs{$name}->{TYPE} . '_' . $name . '_passkey', undef );

    return(undef,$err)
      if ( defined($err) );

    return(1);
}

sub getReadPassword {
    my $self    = shift;
    my $name    = shift;

    my $index   = $::defs{$name}->{TYPE} . '_' . $name . '_passkey';
    my ( $password, $err, $salt );

    ::Log3($name, 4, qq{password Keystore handle for Device ($name) - Read password from file});

    ( $err, $password ) = ::getKeyValue($index);

    if ( defined($err) ) {

        ::Log3($name, 1,
qq{password Keystore handle for Device ($name) - unable to read password from file: $err});

        return undef;
    }

    if (  defined($password)
      and $password =~ m{\A(.{8})(.*)\z}xms )
    {
        $salt       = $1;
        $password   = $2;
        
        my $key     = ::getUniqueId() . $index . $salt;

        if ( eval q{use Digest::SHA;1} ) {

            $key = Digest::SHA::sha256_hex( unpack "H*", $key );
            $key .= Digest::SHA::sha256_hex($key);
        }

        my $dec_pwd = '';

        for my $char ( map { pack( 'C', hex($_) ) } ( $password =~ /(..)/g ) ) {

            my $decode = chop($key);
            $dec_pwd .= chr( ord($char) ^ ord($decode) );
            $key = $decode . $key;
        }

        return $dec_pwd;
    }
    else {

        ::Log3($name, 1, qq{password Keystore handle for Device ($name) - No password in file});
        return undef;
    }
}

sub setRename {
    my $self        = shift;
    my $newname     = shift;
    my $oldname     = shift;

    my ($resp,$err);
    
    ($resp,$err) = $self->setStorePassword($newname,$self->getReadPassword($oldname));     # set new password value
    return(0,$err)
      if ( !defined($resp)
       and defined($err)
      );
    
    ($resp,$err) = $self->setDeletePassword($oldname);     # remove old password value
    return(0,$err)
      if ( !defined($resp)
       and defined($err)
      );

    return(1);
}

1;


__END__

=head1 NAME

FHEM::Core::Authentication::Passwords - FHEM extension for password handling

=head1 VERSION

This document describes FHEM::Core::Authentication::Passwords version 0.9

=head1 CONSTRUCTOR

FHEM::Core::Authentication::Passwords->new();

=head1 SYNOPSIS

  use FHEM::Core::Authentication::Passwords qw(:ALL);
  our $passwd = FHEM::Core::Authentication::Passwords->new();
  
  you can also save the password object in the instance hash
  our $hash->{helper}->{passwdobj} = FHEM::Core::Authentication::Passwords->new();

=head1 DESCRIPTION

Store new Password
$hash->{helper}->{passwdobj}->setStorePassword('PASSWORD');

Read Password
$hash->{helper}->{passwdobj}->getReadPassword();




=head1 EXPORT

The following functions are exported by this module: 
C<setStorePassword>,C<setDeletePassword>, C<getReadPassword>, C<setRename>

=over 4

=back

=head1 OBJECTS

=head1 NOTES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Marko Oldenburg E<lt>fhemdevelopment AT cooltux DOT netE<gt>

=head1 LICENSE

FHEM::Core::Authentication::Passwords is released under the same license as FHEM.

=cut
