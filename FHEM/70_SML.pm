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
# Version = 2.1
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
# where <key> is one of minPower, maxPower, lastPower, avgPower, DAYPOWER, MONTHPOWER, YEARPOWER, TOTALPOWER
##############################################################################


package main;
use IO::Socket::INET;

my @gets = ('minPower',  # min value
      'maxPower',        # max value
      'lastPower',       # last value
      'avgPower',       # avagare value in interval
      'DAYPOWER',       
      'MONTHPOWER',    
      'YEARPOWER',    
      'TOTALPOWER'); 

sub
SML_Initialize($)
{
my ($hash) = @_;

 $hash->{DefFn}    = "energy_Define";
 $hash->{UndefFn}  = "energy_Undef";
 $hash->{GetFn}    = "energy_Get";
 $hash->{StateFn}  = "energy_State";	
 $hash->{SetFn}    = "energy_Set";	
 $hash->{AttrList} = "loglevel:0,1,2,3,4,5";
}

sub
energy_State($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
	Log 4, "time: $tim";
	Log 4, "name: $vt";
	Log 4, "value: $val";
	$hash->{READINGS}{$vt}{VAL} = $val;
	$hash->{READINGS}{$vt}{TIME} = TimeNow();
	Log 4, "$hash->{NAME} VAL: $hash->{READINGS}{$vt}{VAL}";
  return undef;
}
sub
energy_Set($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
	Log 4, "time: $tim";
	Log 4, "name: $vt";
	Log 4, "value: $val";
	$hash->{READINGS}{$vt}{VAL} = $val;
	$hash->{READINGS}{$vt}{TIME} = TimeNow();
	Log 4, "$hash->{NAME} VAL: $hash->{READINGS}{$vt}{VAL}";
 if ( $vt eq "?"){
 	return "Unknown argument ?, choose one of DAYPOWER MONTHPOWER YEARPOWER TOTALPOWER";
 }
  return undef;
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
 $hash->{Invalid}    = -1;    # default value for invalid readings
 $hash->{Rereads}    =  2;    # number of retries when reading curPwr of 0
 $hash->{UseSVTime}  = '';    # use the SV time as timestamp (else: TimeNow())

 $hash->{STATE} = 'Initializing';
 
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
 my $log = "";

Log 4, "$hash->{NAME} $url";

$socket = new IO::Socket::INET (
              PeerAddr => $ip,
              PeerPort => $port,
              Proto    => 'tcp',
              Reuse    => 0,
              Timeout  => $timeout
              );

Log 4, "$hash->{NAME} socket new";
if (defined ($socket) and $socket and $socket->connected())
{
  	Log 4, "$hash->{NAME} Connected ...";
	print $socket "GET $url HTTP/1.0\r\n\r\n";
	$socket->autoflush(1);
	while ((read $socket, $buf, 1024) > 0)
	{
      		Log 5,"buf: $buf";
      		$message .= $buf;
	}
	$socket->close();
	Log 4, "$hash->{NAME} Socket closed";

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
  	Log 3, "$hash->{NAME} Cannot open socket ...";
        $success = 1;
      	return 0;
}

Log 5, "reading done.";
if ( $success == 0 and $summary > 0 and $counts > 0)
{
	$avg = $summary/$counts;
  	$avg =sprintf("%.2f",$avg);
	$hash->{READINGS}{minPower}{VAL}  = $min;
	$hash->{READINGS}{minPower}{TIME}  = $timenow;
	$hash->{READINGS}{maxPower}{VAL}  = $max;
	$hash->{READINGS}{maxPower}{TIME}  = $timenow;
	$hash->{READINGS}{lastPower}{VAL}  = $last;
	$hash->{READINGS}{lastPower}{TIME}  = $timenow;
  	$hash->{READINGS}{avgPower}{VAL}  = $avg;
  	$hash->{READINGS}{avgPower}{TIME}  = $timenow;
	$log = "min: $min max: $max last: $last avg: $avg";
    $hash->{STATE} = "min: $min max: $max last: $last avg: $avg";
    my $newpower = $avg/(3600/$interval);
    $newpower = $newpower/1000;
    $newpower =sprintf("%.6f",$newpower);
    my ($date, $month, $day, $hour, $min, $sec) = $timenow =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
#    ######### DAYPOWER
    if ( $hash->{READINGS}{DAYPOWER}{VAL} eq "-1" ){
    	$hash->{READINGS}{DAYPOWER}{VAL} = $newpower;
     }else{   
    	my ($dateLast, $monthLast, $dayLast, $hourLast, $minLast, $secLast) = $hash->{READINGS}{DAYPOWER}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
    	my ($powLast) = $hash->{READINGS}{DAYPOWER}{VAL} =~ /^(.*)$/;
    	Log 4, "$hash->{NAME} myhour: $dateLast $monthLast $dayLast $hourLast $minLast $secLast $powLast";
    	$hash->{READINGS}{DAYPOWER}{TIME} = $timenow;
    	if ( $dayLast eq $day ){ # es ist der gleiche Tag
    		$powLast += $newpower ;
    		$hash->{READINGS}{DAYPOWER}{VAL} = $powLast;
    		Log 4, "$hash->{NAME} same day timenow: $timenow newpower $newpower powlast $powLast";
    		$log .= " day: $powLast";
    	}else{					# es ist eine Tag vergangen
    		$hash->{READINGS}{DAYPOWER}{VAL} = $newpower;
    		Log 4, "$hash->{NAME} new day timenow: $timenow newpower $newpower powlast $powLast";
    		$log .= " day: $newpower";
    	}
      }
#    ######### MONTH
    if ( $hash->{READINGS}{MONTHPOWER}{VAL} eq "-1" ){
    	$hash->{READINGS}{MONTHPOWER}{VAL}  = $newpower;
     }else{   
    	my ($dateLast, $monthLast, $dayLast, $hourLast, $minLast, $secLast) = $hash->{READINGS}{MONTHPOWER}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
    	my ($powLast) = $hash->{READINGS}{MONTHPOWER}{VAL} =~ /^(.*)$/;
    	Log 4, "$hash->{NAME} myhour: $dateLast $monthLast $dayLast $hourLast $minLast $secLast $powLast";
    	$hash->{READINGS}{MONTHPOWER}{TIME} = $timenow;
    	if ( $monthLast eq $month ){ # es ist der gleiche Monat
    		$powLast += $newpower ;
    		$hash->{READINGS}{MONTHPOWER}{VAL} = $powLast;
    		Log 4, "$hash->{NAME} Gleicher Monat timenow: $timenow newpower $newpower powlast $powLast";
    		$log .= " month: $powLast";
    	}else{					# es ist eine Monat vergangen
    		$hash->{READINGS}{MONTHPOWER}{VAL} = $newpower;
    		Log 4, "$hash->{NAME} Neuer Monat timenow: $timenow newpower $newpower powlast $powLast";
    		$log .= " month: $newpower";
    	}
      }    
#	######### YEARPOWER
    if ( $hash->{READINGS}{YEARPOWER}{VAL} eq "-1" ){
    	$hash->{READINGS}{YEARPOWER}{VAL}  = $newpower;
     }else{   
    	my ($dateLast, $monthLast, $dayLast, $hourLast, $minLast, $secLast) = $hash->{READINGS}{YEARPOWER}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
    	my ($powLast) = $hash->{READINGS}{YEARPOWER}{VAL} =~ /^(.*)$/;
    	Log 4, "$hash->{NAME} myhour: $dateLast $monthLast $dayLast $hourLast $minLast $secLast $powLast";
    	$hash->{READINGS}{YEARPOWER}{TIME} = $timenow;
    	if ( $yearhLast eq $year ){ # es ist das gleiche Jahr
    		$powLast += $newpower ;
    		$hash->{READINGS}{YEARPOWER}{VAL} = $powLast;
    		Log 4, "$hash->{NAME} Gleiches Jahr timenow: $timenow newpower $newpower powlast $powLast";
    		$log .= " year: $powLast";
    	}else{					# es ist eine Jahr vergangen
    		$hash->{READINGS}{YEARPOWER}{VAL} = $newpower;
    		Log 4, "$hash->{NAME} Neues Jahr timenow: $timenow newpower $newpower powlast $powLast";
    		$log .= " year: $newpower";
    	}
      }    
#	######### TOTALPOWER
    	$hash->{READINGS}{TOTALPOWER}{TIME} = $timenow;
     if ( $hash->{READINGS}{TOTALPOWER}{VAL} eq "-1" ){
    	$hash->{READINGS}{TOTALPOWER}{VAL}  = $newpower;
     }else{   
    	my ($dateLast, $monthLast, $dayLast, $hourLast, $minLast, $secLast) = $hash->{READINGS}{TOTALPOWER}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
    	my ($powLast) = $hash->{READINGS}{TOTALPOWER}{VAL} =~ /^(.*)$/;
    	Log 4, "$hash->{NAME} total: $dateLast $monthLast $dayLast $hourLast $minLast $secLast $powLast";
    	$powLast += $newpower ;
    	$hash->{READINGS}{TOTALPOWER}{VAL} = $powLast;
    	$log .= " total: $powLast";
     }
     push @{$hash->{CHANGED}}, $log;
     DoTrigger($hash->{NAME}, undef) if ($init_done);
     Log 3, "$hash->{NAME} write log file: $log";
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
 if ( $get eq "?"){
 return "Unknown argument ?, choose one of minPower maxPower lastPower avgPower DAYPOWER MONTHPOWER YEARPOWER TOTALPOWER";
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

1;

=pod
=begin html

<a name="SML"></a>

<h3>SML</h3>
<ul><p>
This module supports "Intelligenter Strom Zhler"(ENBW) and "Sparzhler" (Yellow Strom).<br>
The electricity meter will be polled in a defined interval for new values.
</p>
 <b>Define</b><br>
  <code>define &lt;name&gt; SML &lt;host&gt; &lt;port&gt; [&lt;interval&gt; &lt;timeout&gt;]</code><br>
  <p>
  Example:<br>
  define StromZ1 SML 192.168.178.20 <br>
  define StromZ2 SML 192.168.10.25 300 60 <br>
  </p>

  <b>Set</b><br>
  set &lt;name&gt; &lt;value&gt; &lt;nummber&gt;<br>where value is one of:<br><br>
  <ul>
  <li><code>TOTALPOWER</code> </li>
  <li><code>YEARPOWER </code> </li>
  <li><code>MONTHPOWER</code> </li>
  <li><code>DAYPOWER  </code> </li>
  <li><code>Interval </code> </li>
   </ul>
   <br>Example:<br>
  set &lt;name&gt; TOTALPOWER 12345 <br><br>

 <b>Get</b><br>
 get &lt;name&gt; &lt;value&gt; <br>where value is one of:<br>
  <ul>
  <li><code>TOTALPOWER</code></li>
  <li><code>YEARPOWER </code></li>
  <li><code>MONTHPOWER</code></li>
  <li><code>DAYPOWER  </code></li>
  <li><code>Interval </code> </li>
   </ul>
 <br>Example:<br>
  get &lt;name&gt; DAYPOWER<br>
  get &lt;name&gt; YEARPOWER<br><br>
  
</ul>

=end html
=cut
