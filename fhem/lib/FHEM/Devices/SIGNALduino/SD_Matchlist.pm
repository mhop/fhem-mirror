# $Id$
# The file is part of the SIGNALduino project.
# Matchlist functions for Signalduino device.

package FHEM::Devices::SIGNALduino::SD_Matchlist;

use strict;
use warnings;

require FHEM::Devices::SIGNALduino::SD_Logger;
require FHEM::Devices::SIGNALduino::SD_Clients;

my %matchList = (
      '1:IT'                => '^i......',
      '2:CUL_TCM97001'      => '^s[A-Fa-f0-9]+',
      '3:SD_RSL'            => '^P1#[A-Fa-f0-9]{8}',
      '5:CUL_TX'            => '^TX..........',                       # Need TX to avoid FHTTK
      '6:SD_AS'             => '^P2#[A-Fa-f0-9]{7,8}',                # Arduino based Sensors, should not be default
      '4:OREGON'            => '^(3[8-9A-F]|[4-6][0-9A-F]|7[0-8]).*',
      '7:Hideki'            => '^P12#75[A-F0-9]+',
      '9:CUL_FHTTK'         => '^T[A-F0-9]{8}',
      '10:SD_WS07'          => '^P7#[A-Fa-f0-9]{6}[AFaf][A-Fa-f0-9]{2,3}',
      '11:SD_WS09'          => '^P9#F[A-Fa-f0-9]+',
      '12:SD_WS'            => '^W\d+x{0,1}#.*',
      '13:RFXX10REC'        => '^(20|29)[A-Fa-f0-9]+',
      '14:Dooya'            => '^P16#[A-Fa-f0-9]+',
      '15:SOMFY'            => '^Ys[0-9A-F]+',
      '16:SD_WS_Maverick'   => '^P47#[A-Fa-f0-9]+',
      '17:SD_UT'            => '^P(?:14|20|24|26|29|30|34|46|56|68|69|76|78|81|83|86|90|91|91.1|92|93|95|97|99|104|105|114|118|121|127|128)#.*', # universal - more devices with different protocols
      '18:FLAMINGO'         => '^P13\.?1?#[A-Fa-f0-9]+',              # Flamingo Smoke
      '19:CUL_WS'           => '^K[A-Fa-f0-9]{5,}',
      '20:Revolt'           => '^r[A-Fa-f0-9]{22}',
      '21:FS10'             => '^P61#[A-F0-9]+',
      '22:Siro'             => '^P72#[A-Fa-f0-9]+',
      '23:FHT'              => '^81..(04|09|0d)..(0909a001|83098301|c409c401)..',
      '24:FS20'             => '^81..(04|0c)..0101a001',
      '25:CUL_EM'           => '^E0.................',
      '26:Fernotron'        => '^P82#.*',
      '27:SD_BELL'          => '^P(?:15|32|41|42|57|79|96|98|112)#.*',
      '28:SD_Keeloq'        => '^P(?:87|88)#.*',
      '29:SD_GT'            => '^P49#[A-Fa-f0-9]+',
      '30:LaCrosse'         => '^(\\S+\\s+9 |OK\\sWS\\s)',
      '31:KOPP_FC'          => '^kr\w{18,}',
      '32:PCA301'           => '^\\S+\\s+24',
      '33:SD_Rojaflex'      => '^P109#[A-Fa-f0-9]+',
      'X:SIGNALduino_un'    => '^[u]\d+#.*',
);

sub getMatchListasRef { 
    return \%matchList; 
}

sub UpdateMatchList {
    my ($hash, $user_match_list_ref) = @_;

    if( ref($user_match_list_ref) eq 'HASH' ) {
     $hash->{MatchList} = { %matchList , %$user_match_list_ref };          ## Allow incremental addition of an entry to existing matchlist
    } else {
     $hash->{MatchList} = getMatchListasRef();                                      ## Set defaults
     FHEM::Devices::SIGNALduino::SD_Logger::Log($hash, 2, $hash->{NAME} .": Attr, $user_match_list_ref: not a HASH using defaults") if( $user_match_list_ref );
    }
}

sub UpdateFromClients { 
    my ($hash, $user_match_list_ref) = @_;

    if (ref($hash) ne 'HASH') {
        return;
    }

    my $all_clients_str = FHEM::Devices::SIGNALduino::SD_Clients::getClientsasStr();
    
    if (defined($hash->{Clients}) && length($hash->{Clients}) > 0) {
        $all_clients_str .= $hash->{Clients} . ':';
    }
    
    my %active_clients = ();
    foreach my $client (split(/:/, $all_clients_str)) {
        $client =~ s/^\s+|\s+$//g;
        if (length($client) > 0) {
            $active_clients{$client} = 1;
        }
    }
    
    my $all_protocols_ref = getMatchListasRef(); 
    my %new_match_list = ();

    foreach my $protocol_client_key (keys %$all_protocols_ref) {
        my ($id, $client_name) = split(/:/, $protocol_client_key, 2);
        
        if (defined $client_name && exists $active_clients{$client_name}) {
            $new_match_list{$protocol_client_key} = $all_protocols_ref->{$protocol_client_key};
        }
    }

    $hash->{MatchList} = \%new_match_list;
}

1;

=pod

=head1 NAME

FHEM::Devices::SIGNALduino::SD_Matchlist - Matchlist management for SIGNALduino

=head1 SYNOPSIS

    use FHEM::Devices::SIGNALduino::SD_Matchlist;
    my $matchlist = FHEM::Devices::SIGNALduino::SD_Matchlist::getMatchListasRef();

=head1 DESCRIPTION

This module manages the regex matchlist used to identify different protocols supported by SIGNALduino.

=head1 FUNCTIONS

=head2 getMatchListasRef()

Returns a reference to the default matchlist hash.

=head2 UpdateMatchList($hash, $user_match_list_ref)

Updates the device's matchlist. If C<$user_match_list_ref> is provided, it merges it with the default list.
Otherwise, it sets the default matchlist.

=head2 UpdateFromClients($hash)

Updates the matchlist based on the clients defined in C<$hash->{Clients}>.
Only protocols for active clients will be included in the matchlist.

=cut
