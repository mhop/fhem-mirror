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

use Exporter ('import');
our @EXPORT_OK = qw( _log 
                     build_200_short
                     getpeer
                     havepeer
                     savepeer
                     makeTableFromPeers
                 );
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

use GPUtils         qw(:all);
BEGIN {
    GP_Import( qw(
        Log3
        Debug
        readingsSingleUpdate
      )
    );
};

###------------------------------------------------------------------
#
# sub _log()
#
# log data based on Log3 syntax
#
###------------------------------------------------------------------

{
	sub _log {
		my ($hash,$loglevel,$text ) = @_;
		my $xline       = ( caller(0) )[2];
		my $xsubroutine = ( caller(1) )[3];
		my @sub         = split( '::', $xsubroutine);
		my $sub         = "$sub[2].$sub[3]";
		my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : "MiniSIP";
		Log3 $hash, $loglevel, "$instName: $sub.$xline " . $text;
	}
}

###------------------------------------------------------------------
#
# sub build_200_short()
# 
# build a simple '200 OK' message from incoming packet
#
###------------------------------------------------------------------

{
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
				 'Contact'        => $req->get_header('Contact') // $hash->{SIP}->{LOCAL_CONTACT},
				 'Expires'        => 300,
	#       'Expires'        => $req->get_header('Expires') // 300,
				 'Content-Length' => '0',
			 }
			);
			return $res;
	}
}

sub havepeer {
  my ($hash) = @_;
  my $count = scalar keys %{$hash->{peers}};
  return $count;
}

sub savepeer {
  my ($hash,$pkt) = @_;
  my ($peer,$ip,$port) = getpeer($hash,$pkt);

	if (defined($peer) && $peer ne '') {
#    my $ts                  = strftime("%a, %d %b %Y %H:%M:%S", localtime(time()));
		my $ts = time();
		$hash->{peers}->{$peer} = { 'peer'       => $peer,
																'peer_ip'    => $ip,
																'peer_port'  => $port,
																'registered' => $ts,
															};

		my $c = $pkt->get_header('contact');
		$c =~ s/</&lt;/g; $c =~ s/>/&gt;/g; # die <> müssen ersetzt werden, um eine Darstellung im Get zu haben
		$hash->{peers}->{$peer}->{contact}    = $c if (defined($c) && $c);      

		my $e = $pkt->get_header('expires');
		$hash->{peers}->{$peer}->{expires}    = $e if (defined($e) && $e);      

		my $u = $pkt->get_header('user_agent');
		$hash->{peers}->{$peer}->{user_agent} = $u if (defined($u) && $u);

		my $x = $pkt->get_header('x-real-ip');
		$hash->{peers}->{$peer}->{x_real_ip}  = $x if (defined($x) && $x);
		#Debug toJSON($hash->{peers}->{$peer});
		readingsSingleUpdate($hash,'state',"registered peer: $peer",1);
	}

}

###------------------------------------------------------------------
#
# sub getpeer()
#
# get peer data from
# first try to extract from 'contact' header
# if not found, try to find data in 'from' and 'via' headers
#
###------------------------------------------------------------------

{
	sub getpeer {
		my ($hash,$pkt) = @_;
		my $contact = $pkt->get_header('contact');
		my ($peer,$ip,$port) = $contact =~ m/<sip:(.*)@(\d+\.\d+\.\d+\.\d+):(\d+)/;
		if ($peer eq '') {
			$contact = $pkt->get_header('from');
			($peer,$ip) = $contact =~ m/<sip:(.*)@(\d+\.\d+\.\d+\.\d+)/;
			$contact = $pkt->get_header('via');
			($port) = $contact =~ m/\d+\.\d+\.\d+\.\d+:(\d+)/;
		}
		_log($hash,4,"found peer: $peer");
		return ($peer,$ip,$port);
	}
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
	
	sub makeTableFromPeers {
		my ($hash) = @_;
		my $table = tablify({
				 BORDER      => 1, 
				 DATA        => $hash->{peers},
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
