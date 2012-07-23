##############################################################################
#
# 70_SML.pm
#
# a module to show smartmeter data
#
# written 2012 by Gabriel Bentele <gabriel at bentele.de>>
#
# $Id$
#
# Version = 1.0
#
##############################################################################
#
# define <name> SML <host> <port> [<interval> [<timeout>]]
#
# If <interval> is positive, new values are read every <interval> seconds.
# If <interval> is 0, new values are read whenever a get request is called
# on <name>. The default for <interval> is 300 (i.e. 5 minutes).
#
# get <name> <key>
#
# where <key> is one of minPower, maxPower, lastPower, avgPower
##############################################################################


package main;
use IO::Socket::INET;

my @gets = ('minPower',  # min value
      'maxPower',        # max value
      'lastPower',       # last value
      'avgPower');       # avagare value in interval

sub
SML_Initialize($)
{
my ($hash) = @_;

 $hash->{DefFn}    = "energy_Define";
 $hash->{UndefFn}  = "energy_Undef";
 $hash->{GetFn}    = "energy_Get";
 $hash->{AttrList} = "loglevel:0,1,2,3,4,5";
}

sub
energy_Define($$)
{
 my ($hash, $def) = @_;

 my @args = split("[ \t]+", $def);

 if (int(@args) < 4)
 {
  return "energy_Define: too few arguments. Usage:\n" .
         "define <name> SML <host> <port> [<interval> [<timeout>]]";
 }

 $hash->{Host}     = $args[2];
 $hash->{Port}     = $args[3];
 $hash->{Interval} = int(@args) >= 5 ? int($args[4]) : 300;
 $hash->{Timeout}  = int(@args) >= 6 ? int($args[5]) : 4;

 Log 3, "$hash->{NAME} will read from SML at $hash->{Host}:$hash->{Port} " ;
 # config variables
 $hash->{Invalid}    = -1;    # default value for invalid readings
 $hash->{Rereads}    =  2;     # number of retries when reading curPwr of 0
 $hash->{UseSVTime}  = '';    # use the SV time as timestamp (else: TimeNow())

 $hash->{STATE} = 'Initializing';
# $hash->{DAYPOWER} = '0';
# $hash->{WEEKPOWER} = '0';
# $hash->{MONTHPOWER} = '0';
# $hash->{YEARPOWER} = '0';

 my $timenow = TimeNow();

 for my $get (@gets)
 {
  $hash->{READINGS}{$get}{VAL}  = $hash->{Invalid};
  $hash->{READINGS}{$get}{TIME} = $timenow;
 }

 energy_Update($hash);

 Log 3, "$hash->{NAME} will read from SML at $hash->{Host}:$hash->{Port} " .
       ($hash->{Interval} ? "every $hash->{Interval} seconds" : "for every 'get $hash->{NAME} <key>' request");

 return undef;
}

sub
energy_Update($)
{
 my ($hash) = @_;

 if ($hash->{Interval} > 0) {
  InternalTimer(gettimeofday() + $hash->{Interval}, "energy_Update", $hash, 0);
 }

 Log 3, "$hash->{NAME} tries to contact SML at $hash->{Host}:$hash->{Port}";

 my $success  = 0;
 my %readings = ();
 my $timenow  = TimeNow();
 my $rereads  = $hash->{Rereads};
 my $ip = $hash->{Host};
 my $port = $hash->{Port};
 my $interval = $hash->{Interval};
 my $timeout = $hash->{Timeout};
 my $counts = 0 ;
 my $summary = 0 ;
 my $url =  "/InstantView/request/getPowerProfile.html?ts=0\&n=$interval\&param=Wirkleistung\&format=1";
 my $socket ;
 my $buf ;
 my $message ;
 my @array;
 my $last;
 my $avg;
 my $min = 20000;
 my $max = 0;

Log 4, "$url";

$socket = new IO::Socket::INET (
              PeerAddr => $ip,
              PeerPort => $port,
              Proto    => 'tcp',
              Reuse    => 0,
              Timeout  => $timeout
              );

Log 4, "socket new";
if (defined ($socket) and $socket and $socket->connected())
{
  	Log 4, "Connected ...";
	print $socket "GET $url HTTP/1.0\r\n\r\n";
	$socket->autoflush(1);
	while ((read $socket, $buf, 1024) > 0)
	{
      		Log 5,"buf: $buf";
      		$message .= $buf;
	}
	$socket->close();
	Log 4, "Socket closed";

	@array = split(/\n/,$message);
	foreach (@array){
 	    if ( $_ =~ /<v>(.*)<\/v>/ )
  	    {
  		Log 5, "$hash->{NAME} got fresh values from $ip ($1)";
      		$last = $1;
      		$counts++ ;
      		$summary += $1;
		if ($last < $min) {$min = $last};
                if ($last > $max) {$max = $last};
            }
 	    if ( $_ =~ /<error>(.*)<\/error>/ )
  	    {
      		if ( $1 eq "true" )
      	    	{
          	     $success = 1;
          	     Log 4, "$hash->{NAME} error from the $ip ($1)";
      	    	}
  	    }
	}
}else{ 
  	Log 3, "Cannot open socket ...";
        $success = 1;
      	return 0;
}

Log 5, "reading done.";
if ( $success == 0 and $summary > 0 and $counts > 0)
{
	$avg = $summary/$counts;
  	$avg =sprintf("%.2f",$avg);
	$hash->{READINGS}{$gets[0]}{VAL}  = $min;
	$hash->{READINGS}{$gets[0]}{TIME}  = $timenow;
	$hash->{READINGS}{$gets[1]}{VAL}  = $max;
	$hash->{READINGS}{$gets[1]}{TIME}  = $timenow;
	$hash->{READINGS}{$gets[2]}{VAL}  = $last;
	$hash->{READINGS}{$gets[2]}{TIME}  = $timenow;
  	$hash->{READINGS}{$gets[3]}{VAL}  = $avg;
  	$hash->{READINGS}{$gets[3]}{TIME}  = $timenow;
	push @{$hash->{CHANGED}}, "min: $min max: $max last: $last avg: $avg";
  	DoTrigger($hash->{NAME}, undef) if ($init_done);
  	$hash->{STATE} = $hash->{READINGS}{minPower}{VAL}.' W, '.$hash->{READINGS}{maxPower}{VAL}.' W ' .$hash->{READINGS}{lastPower}{VAL}.' W '.$hash->{READINGS}{avgPower}{VAL}.' W';

}else{
  	Log 3, "$hash->{NAME} can't update - device send a error";
}

return undef;
}

sub
energy_Get($@)
{

my ($hash, @args) = @_;

 return 'energy_Get needs two arguments' if (@args != 2);

energy_Update($hash) unless $hash->{Interval};

 my $get = $args[1];
 my $val = $hash->{Invalid};

 if (defined($hash->{READINGS}{$get})) {
  $val = $hash->{READINGS}{$get}{VAL};
 } else {
  return "energy_Get: no such reading: $get";
 }

 Log 3, "$args[0] $get => $val";

 return $val;
}

sub
energy_Undef($$)
{
 my ($hash, $args) = @_;

 RemoveInternalTimer($hash) if $hash->{Interval};

 return undef;
}
