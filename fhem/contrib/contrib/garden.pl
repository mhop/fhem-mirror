#!/usr/bin/perl

use warnings;
use strict;
use IO::Socket::INET;
use IO::Handle;

STDOUT->autoflush(1);

#################
# Formula:
# Compute for the last <navg> days + today the avarage temperature and the
# sum of rain, then compute the multiplier: (temp/20)^2 - rain/5
# Now multiply the duration of each vent with this multiplier
# If the value is less than a minimum, then store the value and add it
# the next day
#################

my $test = 0;                   # Test only, do not switch anything
my $fhzport = 7072;             # Where to contact it
my $avg = "/home/rudi/log/avg.log";	   # KS300 avarage log file
my $navg = 2;                   # Number of last avg_days to consider
my $min = 300;			# If the duration is < min (sec) then collect
my $col = "/home/rudi/log/gardencoll.log"; # File where it will be collected
my $pmp = "GPumpe";             # Name of the water pump, will be switched in first
my $maxmult = 4;		# Maximum factor (corresponds to 40 degree avg.
                                # temp over $navg days, no rain)

if(@ARGV) {
  if($ARGV[0] eq "test") {
    $test = 1;
  } else {
    print "Usage: garden.pl [test]\n";
    exit(1);
  }
}

my %list = (
  GVent1 => { Nr => 1, Dur => 720 },
  GVent2 => { Nr => 2, Dur => 480 },
  GVent3 => { Nr => 3, Dur => 720 },
  GVent4 => { Nr => 4, Dur => 720 },
  GVent6 => { Nr => 5, Dur => 720 },
  GVent7 => { Nr => 6, Dur => 480 },
  GVent8 => { Nr => 7, Dur => 480 },
);

##############################
# End of config

sub fhzcommand($);
sub doswitch($$);
sub donext($$);

my ($nlines, $temp, $rain) = (0, 0, 0);
my ($KS300name, $server, $last);

my @t = localtime;
printf("%04d-%02d-%02d %02d:%02d:%02d\n",
      $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);

###########################
# First read in the last avg_days
open(FH, $avg) || die("$avg: $!\n");
my @avg = <FH>;
close(FH);

my @tarr; # Want the printout in the right order
while(my $l = pop(@avg)) {
  next if($l !~ m/avg_day/);
  my @v = split(" ", $l);
  push(@tarr, "$v[0]: T: $v[4], R: $v[10]") if($test);
  $temp += $v[4]; $rain += $v[10];
  $KS300name = $v[1];
  $nlines++;
  last if($nlines >= $navg);
}

###########################
# Now get the current day
foreach my $l (split("\n", fhzcommand("list $KS300name"))) {
  next if($l !~ m/avg_day/);
  my @v = split(" ", $l);
  print("$v[0] $v[1]: T: $v[4], R: $v[10]\n") if($test);
  $temp += $v[4]; $rain += $v[10];
  $nlines++;
  last;
}

if($test) {
  foreach my $l (@tarr) {
    print "$l\n";
  }
}


###########################
# the collected data
my %coll;
if(open(FH, $col)) {
  while(my $l = <FH>) {
    my ($k, $v) = split("[ \n]", $l);
    $coll{$k} = $v;
  }
  close(FH);
}

###########################
# The formula
$temp /= $nlines;
$rain /= $nlines;

# safety measures
$rain =  0 if($rain <  0);
$temp =  0 if($temp <  0);
$temp = 40 if($temp > 40);
my $mult = exp( 2.0 * log( $temp / 20 )) - $rain/5;
$mult = $maxmult if($mult > $maxmult);

if($mult <= 0) {
  print("Multiplier is not positive ($mult), exiting\n");
  exit(0);
}

printf("Multiplier is %.2f (T: $temp, R: $rain)\n", $mult, $temp, $rain);

my $have = 0;
if(!$test) {
  open(FH, ">$col") || die("Can't open $col: $!\n");
}
foreach my $a (sort { $list{$a}{Nr} <=> $list{$b}{Nr} } keys %list) {
  my $dur = int($list{$a}{Dur} * $mult);

  if(defined($coll{$a})) {
    $dur += $coll{$a};
    printf("   $a: $dur ($coll{$a})\n");
  } else {
    printf("   $a: $dur\n");
  }

  if($dur > $min) {
    $list{$a}{Act} = $dur;
    $have += $dur;
  } else {
    print FH "$a $dur\n" if(!$test);
  }
}

print("Total time is $have\n");
exit(0) if($test);
close(FH);

if($have) {
  doswitch($pmp, "on") if($pmp);
  sleep(3) if(!$test);
  foreach my $a (sort { $list{$a}{Nr} <=> $list{$b}{Nr} } keys %list) {
    next if(!$list{$a}{Act});
    donext($a, $list{$a}{Act});
  }
  donext("", 0);
  doswitch($pmp, "off") if($pmp);
}

###########################
# Switch the next dev on and  the last one off
sub
donext($$)
{
  my ($dev, $sl) = @_;
  doswitch($dev, "on");
  doswitch($last, "off");
  $last = $dev;
  if($test) {
    print "sleeping $sl\n";
  } else {
    sleep($sl);
  }
}

###########################
# Paranoid setting.
sub
doswitch($$)
{
  my ($dev, $how) = @_;
  return if(!$dev || !$how);

  if($test) {
    print "set $dev $how\n";
    return;
  }
  fhzcommand("set $dev $how");
  sleep(1);
  fhzcommand("set $dev $how");
}

###########################
sub
fhzcommand($)
{
  my $cmd = shift;

  my ($ret, $buf) = ("", "");
  $server = IO::Socket::INET->new(PeerAddr => "localhost:$fhzport");
  die "Can't connect to the server at port $fhzport\n" if(!$server);
  syswrite($server, "$cmd;quit\n");
  while(sysread($server, $buf, 256) > 0) {
    $ret .= $buf;
  }
  close($server);
  return $ret;
}
