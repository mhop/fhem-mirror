#  $Id$

################################################################
#
#  Copyright notice
#
#  (c) 2026 - today
#  Copyright: betateilchen (betateilchen dot quantentunnel dot de)
#  All rights reserved
#
#  This program is part of FHEM; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License V2.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
#  See the GNU General Public License V2 for more details.
#
################################################################

package FHEM::MiniSIP::Utils;

use strict;
use warnings;
use JSON::XS;
use Data::Dumper;

use Exporter ('import');
our @EXPORT_OK = qw( _log3 
                     build_200_short
                     backup_peers
                     restore_peers
                     extract_peer
                     havepeer
                     savepeer
                     makeTable
                 );
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

use GPUtils         qw(:all);
BEGIN {
    GP_Import( qw(
        data
        AttrVal
        Log3
        Debug
        readingsSingleUpdate
        toJSON
        json2nameValue
        getKeyValue
        setKeyValue
      )
    );
};

my $p = __PACKAGE__;
$::data{modules}{version}{$p} = '$Id$';


###------------------------------------------------------------------
#
# sub _log3($hash,$loglevel,$text) (exported)
#
# log extended data based on Log3 syntax
#
###------------------------------------------------------------------

sub _log3 {
	my ($hash,$loglevel,$text) = @_;
	my $xline       = ( caller(0) )[2];
	my $xsubroutine = ( caller(1) )[3]; 
		 $xsubroutine =~ s/^main:://; 
	my @sub         = split( '::', $xsubroutine);
	my $count       = scalar @sub;
	my $sub         = ($count == 1)
										? $sub[0]
										: "$sub[$count-2].$sub[$count-1]";
	my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : "MiniSIP";
	Log3 $hash, $loglevel, "$instName: $sub.$xline " . $text;
}

###------------------------------------------------------------------
#
# sub parsemsgbody($hash,$peer,$body) (exported)
#
# log extended data based on Log3 syntax
#
###------------------------------------------------------------------

sub parsemsgbody {
	my ($hash,$peer,$body) = @_;
	my $name      = $hash->{NAME};
	my $parsetype = $hash->{peers}->{$peer}->{parsetype};
	my $input;

	my $fn = AttrVal($name,'parseFn',undef);

	if(defined($fn)) {
		_log3($hash,3,"use external parser: $fn");
		no strict "refs";
		eval { $input = &{$fn}($body); };
		$input = $@ if ($@);
		use strict "refs";
		_log3($hash,3,"msg parsed: $input");
	} elsif ($parsetype eq 'snom') { 
		($input) = $body =~ m/k=(\d+)/;
	} elsif ($parsetype eq 'grandstream') {
		$input = "grandstream dummy";
	} else {
		_log3($hash,1,"unknown message type");
		return undef;
	}
	return $input;
}

###------------------------------------------------------------------
#
# sub build_200_short($hash,$req)
# 
# build a simple '200 OK' message from incoming packet
#
###------------------------------------------------------------------


sub build_200_short {
	my ($hash,$req) = @_;

	my $res = Net::SIP::Response->new(
			200,
			'OK',
		 { 'Via'            => [ $req->get_header('Via') ],
			 'From'           => $req->get_header('From'),
			 'To'             => $req->get_header('To'),
			 'Call-ID'        => $req->get_header('Call-ID'),
			 'CSeq'           => $req->get_header('CSeq'),
			 'Contact'        => $req->get_header('Contact') // $hash->{server}->{local},
			 'Expires'        => 300,
#       'Expires'        => $req->get_header('Expires') // 300,
			 'Content-Length' => '0',
		 }
		);
		return $res;
}

###------------------------------------------------------------------
#
# sub backup_peers($hash)
# 
# store all registered peers in keystore
#
###------------------------------------------------------------------

sub backup_peers {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  _log3($hash,4,"backup peers");
  setKeyValue($name,toJSON($hash->{peers}));
}

###------------------------------------------------------------------
#
# sub restore_peers($hash)
# 
# restore peers from keystore
# a peer will only be restored if
# - last registration not expired
# - peer not registered already
#
###------------------------------------------------------------------

sub restore_peers {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  _log3($hash,4,"restore peers");

  my $peers  = getKeyValue($name);
  return unless (defined($peers));
     $peers  = decode_json($peers);

  my %p = ();

  for my $key (keys %$peers) {
    my $peer = $peers->{$key};
    next unless ref $peer eq 'HASH';
    for my $field (keys %$peer) {
      my $value = $peer->{$field};
      $p{$key}{$field} = (defined $value ? $value : 'undef');
    }

    # check for valid registration based on time and expiry
    my $ts     = time();
    my $reg = $p{$key}{registered};
    my $exp = $p{$key}{expires};
    if (($reg+$exp) < $ts) {
      delete $p{$key};
    }
  }

  # only add peers that are not registered
  $hash->{peers}{$_} = $p{$_} for 
        grep { not exists $hash->{peers}{$_} } keys %p;
}

###------------------------------------------------------------------
#
# sub havepeer($hash;$peer) (exported)
# 
# if optional parameter $peer given: check if $peer is registered,
# return corresponding state of $peer
#
# if optional parameter $peer missing: 
# return current number of registerd peers
#
###------------------------------------------------------------------

sub havepeer {
	my ($hash,$peer) = @_;
	my $havepeer = 0;

	if (defined($peer) && $peer ne '') {
		$havepeer = defined($hash->{peers}->{$peer});
	} else {
		$havepeer = scalar keys %{$hash->{peers}};
	}
	return $havepeer;
}

###------------------------------------------------------------------
#
# sub savepeer($hash,$pkt)
# 
# save registered peer into $hash
#
###------------------------------------------------------------------

sub savepeer {
  my ($hash,$pkt) = @_;
  my ($peer,$ip,$port) = extract_peer($hash,$pkt,1);

	if (defined($peer) && $peer ne '') {
		my $ts = time();
		$hash->{peers}->{$peer} = { 'peer'       => $peer,
																'peer_ip'    => $ip,
																'peer_port'  => $port,
																'registered' => $ts,
															};

		my $c = $pkt->get_header('contact');
		$c //= '';
		$c =~ s/</&lt;/g; $c =~ s/>/&gt;/g; # die <> müssen ersetzt werden, um eine Darstellung im Get zu haben
		$hash->{peers}->{$peer}->{contact}    = $c if (defined($c) && $c);      

		my $e = $pkt->get_header('expires');
		$hash->{peers}->{$peer}->{expires}    = $e if (defined($e) && $e);      

		my $u = $pkt->get_header('user-agent');
		$hash->{peers}->{$peer}->{user_agent} = $u if (defined($u) && $u);
		($u) = $u =~ m/^(snom)/i;
		$hash->{peers}->{$peer}->{parsetype} = $u if (defined($u) && $u);

		my $x = $pkt->get_header('x-real-ip');
		$hash->{peers}->{$peer}->{x_real_ip}  = $x if (defined($x) && $x);
		readingsSingleUpdate($hash,'state',"registered peer: $peer",1);
	}

}

###------------------------------------------------------------------
#
# sub extract_peer()
#
# get peer data from incoming request
# first try to extract from 'contact' header
# if not found, try to find data in 'from' and 'via' headers
#
###------------------------------------------------------------------

sub extract_peer {
	my ($hash,$pkt,$log) = @_;
	$log //= 1;
	my ($peer,$ip,$port,$contact);
	$contact = $pkt->get_header('contact');
	if (defined($contact) && $contact ne '') {
		($peer,$ip,$port) = $contact =~ m/<sip:(.*)@(\d+\.\d+\.\d+\.\d+):(\d+)/;
	} else {
		$contact = $pkt->get_header('from');
		($peer,$ip) = $contact =~ m/<sip:(.*)@(\d+\.\d+\.\d+\.\d+)/;
		$contact = $pkt->get_header('via');
		($port) = $contact =~ m/\d+\.\d+\.\d+\.\d+:(\d+)/;
	}
	_log3($hash,4,"found peer: $peer") if $log;
	return ($peer,$ip,$port);
}

###------------------------------------------------------------------
#
# sub makeTableFromPeers()
#
# make table from hash for peers
# based on HTML::HashTable
#
###------------------------------------------------------------------

{
	my $output;
	my $depth;
	
	sub makeTable {
		my ($hash,$data) = @_;
		my $table = tablify({
				 BORDER      => 1, 
				 DATA        => $data,
				 SORTBY      => 'key', 
				 ORDER       => 'asc'}
		 );
		return "<html>$table</html>";
	}
	
	
	sub tablify {
		$output = '';
		$depth = 0;
		my $tsref = shift;
					$tsref->{SORTBY} ||= "key";
					$tsref->{ORDER}  ||= "asc";
					$tsref->{BORDER} = 1 unless (defined $tsref->{BORDER});
		make_table($tsref);
		return $output;
	}
	
	sub recurse_through {
		my $tsref = shift;
		my $thingy = shift;
		if (ref($thingy) eq 'ARRAY') {
			foreach (@$thingy) {
				recurse_through($tsref, $_);
			}
		} elsif (ref($thingy) eq 'HASH') {
			my $newref = {%$tsref};
			$newref->{DATA} = $thingy;
			open_cell();
			make_table($newref);
			close_cell($depth);
		} else {	# plain old scalar data
			open_cell();
			$output .= $thingy;
			close_cell(0);
		}
	}
	
	sub open_table {
		my $tsref = shift;
		$output .= "\n";
		$output .= "\t" x $depth;
		$output .= $tsref->{BORDER} ? "<table border=1>\n" : "<table border=0>\n";
	}
	
	sub close_table {
		$output .= "\t" x $depth;
		$output .= "</table>\n";
	}
	
	sub open_row {
		$output .= "\t" x ($depth);
		$output .= "<tr>\n";
		$depth++;
	}
	
	sub close_row {
		$depth--;
		$output .= "\t" x ($depth);
		$output .= "</tr>\n";
	}
	
	sub open_cell {
		$output .= "\t" x ($depth);
		$output .= "<td>";
		$depth++;
	}
	
	sub close_cell {
		my $d = shift;
		$d-- if $d;
		$output .= "\t" x ($d);
		$output .= "</td>\n";
		$depth--;
	}
		
	sub make_table {
		my $tsref = shift;
		open_table($tsref);
		foreach my $key (sort { 
			if ($tsref->{SORTBY} eq "value") {
				if ($tsref->{ORDER} eq 'asc') {
					${$tsref->{DATA}}{$a} cmp ${$tsref->{DATA}}{$b};
				} else { 
					${$tsref->{DATA}}{$b} cmp ${$tsref->{DATA}}{$a};
				}
			} else {
				if ($tsref->{ORDER} eq 'asc') {
					$a cmp $b;
				} else {
					$b cmp $a;
				}
			}
		} keys %{$tsref->{DATA}}) {
			open_row;
			open_cell;
			$output .= $key;
			close_cell(0);
			recurse_through($tsref, ${$tsref->{DATA}}{$key});
			close_row;
		}
		close_table;
	}	

}

1;

__END__
