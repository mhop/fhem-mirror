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
  my @fields = split(/;/,$txt);
  my $msgRef = { radioId => $fields[0],
                 childId => $fields[1],
                 cmd     => $fields[2],
                 ack     => $fields[3],
                 subType => $fields[4],
                 payload => $fields[5] };
  return $msgRef;
}

sub createMsg(%) {
  my %msgRef = @_;
  my @fields = ( $msgRef{'radioId'},
                 $msgRef{'childId'},
                 $msgRef{'cmd'},
                 $msgRef{'ack'},
                 $msgRef{'subType'},
                 defined($msgRef{'payload'}) ? $msgRef{'payload'} : "" );
  return join(';', @fields);
}

sub dumpMsg($) {
  my $msgRef = shift;
  my $cmd = commandToStr($msgRef->{'cmd'});
  my $st = subTypeToStr( $msgRef->{'cmd'}, $msgRef->{'subType'} );
  return sprintf("Rx: fr=%03d ci=%03d c=%03d(%-14s) st=%03d(%-16s) ack=%d %s\n", $msgRef->{'radioId'}, $msgRef->{'childId'}, $msgRef->{'cmd'}, $cmd, $msgRef->{'subType'}, $st, $msgRef->{'ack'}, defined($msgRef->{'payload'}) ? "'".$msgRef->{'payload'}."'" : "");
}

sub gettime {
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year += 1900;
  $mon++;
  return sprintf("%04d%02d%02d-%02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec);
}

1;