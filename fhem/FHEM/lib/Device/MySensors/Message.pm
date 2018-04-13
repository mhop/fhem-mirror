package Device::MySensors::Message;

use Device::MySensors::Constants qw(:all);

use Exporter ('import');
@EXPORT = ();
@EXPORT_OK = qw(parseMsg createMsg dumpMsg);
%EXPORT_TAGS = (all => [@EXPORT_OK]);

use strict;
use warnings;

sub parseMsg($) {
  my $txt = shift;
  if ($txt =~ /^(\d+);(\d+);(\d+);(\d+);(\d+);(.*)$/) {
    return { radioId => $1,
             childId => $2,
             cmd     => $3,
             ack     => $4,
             subType => $5,
             payload => $6 };
  } else {
    return undef;
  };
}

sub createMsg(%) {
  my %msgRef = @_;
  my @fields = ( $msgRef{'radioId'} // -1,
                 $msgRef{'childId'} // -1,
                 $msgRef{'cmd'} // -1,
                 $msgRef{'ack'} // -1,
                 $msgRef{'subType'} // -1,
                 $msgRef{'payload'}  // "");
  return join(';', @fields);
}

sub dumpMsg($) {
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