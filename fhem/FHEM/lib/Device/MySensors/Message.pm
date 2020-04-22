package Device::MySensors::Message;

use Device::MySensors::Constants qw(:all);

use Exporter ('import');
@EXPORT = ();
@EXPORT_OK = qw(parseMsg createMsg dumpMsg);
%EXPORT_TAGS = (all => [@EXPORT_OK]);

use strict;
use warnings;

sub parseMsg {
    my $txt = shift;

    use bytes;

    return if ($txt !~ m{\A
               (?<nodeid>  [0-9]+);
               (?<childid> [0-9]+);
               (?<command> [0-4]);
               (?<ack>     [01]);
               (?<type>    [0-9]{1,2});
               (?<payload> .*)
               \z}xms);

    return {
        radioId => $+{nodeid}, # docs speak of "nodeId"
        childId => $+{childid},
        cmd     => $+{command},
        ack     => $+{ack},
        subType => $+{type},
        payload => $+{payload}
    };
}

sub createMsg {
  my %msgRef = @_;
  my @fields = ( $msgRef{'radioId'} // -1,
                 $msgRef{'childId'} // -1,
                 $msgRef{'cmd'} // -1,
                 $msgRef{'ack'} // -1,
                 $msgRef{'subType'} // -1,
                 $msgRef{'payload'}  // "");
  return join(';', @fields);
}

sub dumpMsg {
	my $msgRef = shift;
	my $cmd = defined $msgRef->{'cmd'} ? commandToStr($msgRef->{'cmd'}) : "''";
	my $st = (defined $msgRef->{'cmd'} and defined $msgRef->{'subType'}) ? subTypeToStr( $msgRef->{'cmd'}, $msgRef->{'subType'} ) : "''";
	return sprintf("Rx: fr=%03d ci=%03d c=%03d(%-14s) st=%03d(%-16s) ack=%d %s\n", $msgRef->{'radioId'} // -1, $msgRef->{'childId'} // -1, $msgRef->{'cmd'} // -1, $cmd, $msgRef->{'subType'} // -1, $st, $msgRef->{'ack'} // -1, "'".($msgRef->{'payload'} // "")."'");
}

sub gettime {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year += 1900;
	$mon++;
	return sprintf("%04d%02d%02d-%02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec);
}

1;