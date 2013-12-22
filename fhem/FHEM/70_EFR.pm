##############################################################################
#
# 70_EFR.pm
#
# a module to show smartmeter data
#
# written 2013 by Gabriel Bentele <gabriel at bentele.de>>
#
# $Id: 70_EFR.pm 3799 2013-08-26 18:15:33Z bentele $
#
# Version = 0.5
#
##############################################################################
#
# define <name> EFR <host> <port> [<interval> [<timeout>]]
#
# If <interval> is positive, new values are read every <interval> seconds.
# If <interval> is 0, new values are read whenever a get request is called
# on <name>. The default for <interval> is 300 (i.e. 5 minutes).
#
# get <name> <key>
#
##############################################################################
#	 { "obis":"8181C78227FF","value":""},								[03]	Kundennummer
#	{ "obis":"8181C78205FF","value":"xxxxx"},							[04]	Vorname
#	{ "obis":"8181C78206FF","value":"xxxxx"},							[05]	Nachname
#	{ "obis":"8181C78207FF","value":"xxxxx"},							[06]	Anschrift
#	{ "obis":"0100000000FF","value":"xxxxx"},							[07]	Eigentums- bzw. Zählernummer
#	{ "obis":"010000090B00","value":"dd.mm.yyyy,hh:mm"}], "values" : [	[08]	Zeitangabe (Datum , Uhrzeit)
#	{"obis":"0101010800FF","value":41.42,"unit":"kWh" },				[09]	BEZUG Wirkleistung Energiezählwerk - Summenzählwerk abrechnungsrelevant (Tariflos)
#	{"obis":"0101010801FF","value":33.53,"unit":"kWh"},					[10		BEZUG Wirkleistung Energiezählwerk NT
#	{"obis":"0100010700FF","value":313.07,"unit":"W"},					[11]	Momentanleistung über alle 3 Phasen saldierend
#	{"obis":"0100150700FF","value":209.40,"unit":"W"},					[12]	Momentanleistung Phase L1
#	{"obis":"0100290700FF","value":14.27,"unit":"W"},					[13]	Momentanleistung Phase L2
#	{"obis":"01003D0700FF","value":89.40,"unit":"W"},					[14]	Momentanleistung Phase L3
#	{"obis":"010020070000","value":237.06,"unit":"V"},					[15]	Phasenspannung U1
#	{"obis":"010034070000","value":236.28,"unit":"V"},					[16]	Phasenspannung U2
#	{"obis":"010048070000","value":236.90,"unit":"V"},					[17]	Phasenspannung U3
#	{"obis":"01000E070000","value":49.950,"unit":"Hz"} ] }}				[18]	Netzfrequenz
##############################################################################

package main;
use strict;
use IO::Socket::INET;

my @gets = ('lastPower','PowerTotal','Power_L1','Power_L2','Power_L3');

sub
EFR_Initialize($)
{
my ($hash) = @_;

 $hash->{DefFn}    = "energy_Define";
 $hash->{UndefFn}  = "energy_Undef";
 $hash->{GetFn}    = "energy_Get";
 $hash->{StateFn}  = "energy_State";
 $hash->{SetFn}    = "energy_Set";
}

sub
energy_State($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
	$hash->{READINGS}{$vt}{VAL} = $val;
	$hash->{READINGS}{$vt}{TIME} = TimeNow();
	Log3 $hash, 4, "energy_State: time: $tim name: $vt value: $val";
  return undef;
}

sub
energy_Set($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
	Log3 $hash, 4, "SET device: $tim name: $vt value: $val";
	$hash->{READINGS}{$vt}{VAL} = $val;
	$hash->{READINGS}{$vt}{TIME} = TimeNow();
 if ( $vt eq "?"){
 	return "Unknown argument ?, choose one of Interval";
 }
 if ( $vt eq "Interval"){
	$hash->{Interval} = $val;
 }
  return undef;
}

sub
energy_Define($$)
{
 my ($hash, $def) = @_;

 my @args = split("[ \t]+", $def);

 if (int(@args) < 3)
 {
  return "energy_Define: too few arguments. Usage:\n" .
         "define <name> EFR <host> [<interval> [<timeout>]]";
 }

 $hash->{Host}     = $args[2];
 $hash->{Port}     = 80;
 $hash->{Interval} = int(@args) >= 4 ? int($args[3]) : 300;
 $hash->{Timeout}  = int(@args) >= 5 ? int($args[4]) : 4;

 Log3 $hash, 4, "$hash->{NAME} will read from EFR at $hash->{Host}:$hash->{Port} " ;
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

 Log3 $hash, 3, "$hash->{NAME} will read from EFR at $hash->{Host}:$hash->{Port} " ; 
 return undef;
}

sub
energy_Update($)
{
 my ($hash) = @_;

 if ($hash->{Interval} > 0) {
  InternalTimer(gettimeofday() + $hash->{Interval}, "energy_Update", $hash, 0);
 }

 Log3 $hash, 4, "$hash->{NAME} tries to contact EFR at $hash->{Host}:$hash->{Port}";
 
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
 my $url="/json.txt?LogName=user\&LogPSWD=user";
 #my $url="/efr.txt";
 my $socket ;
 my $buf ;
 my $message ;
 my @array;
 my $last;
 my $avg;
 my $min = 20000;
 my $max = 0;
 my $log = "";

Log3 $hash, 4, "$hash->{NAME} $ip : $port $url";
$socket = new IO::Socket::INET (
              PeerAddr => $ip,
              PeerPort => $port,
              Proto    => 'tcp',
              Reuse    => 0,
              Timeout  => $timeout
              );

Log3 $hash, 4, "$hash->{NAME} socket new";
if (defined ($socket) and $socket and $socket->connected())
{
  	Log3 $hash, 4,  "$hash->{NAME} Connected ...";
	print $socket "GET $url HTTP/1.0\r\n\r\n";
	$socket->autoflush(1);
	while ((read $socket, $buf, 1024) > 0)
	{
      		Log 5,"buf: $buf";
      		$message .= $buf;
	}
	$socket->close();
	Log3 $hash, 4, "$hash->{NAME} Socket closed";
	$success = 0;
}else{
  	Log3 $hash, 3, "$hash->{NAME} Cannot open socket ...";
        $success = 1;
      	return 0;
}

Log3 $hash, 5, "reading done.";

if ( $success == 0 )
{
	@array=split(/\{/,$message);
	my $powernow = $array[11];
	$powernow =~ m/value":(.*),"unit":/;
	$powernow = $1;

	$hash->{READINGS}{lastPower}{VAL}  = $powernow;
	$hash->{READINGS}{lastPower}{TIME}  = $timenow;
	
	my $powercounter = $array[10];
	$powercounter =~ m/value":(.*),"unit":/;
	$powercounter = $1;

	$hash->{READINGS}{PowerTotal}{VAL}  = $powercounter;
	$hash->{READINGS}{PowerTotal}{TIME}  = $timenow;
	
	my $powerU1 = $array[12];
	$powerU1 =~ m/value":(.*),"unit":/;
	$powerU1 = $1;

	$hash->{READINGS}{Power_L1}{VAL}  = $powerU1;
	$hash->{READINGS}{Power_L1}{TIME}  = $timenow;
	
	my $powerU2 = $array[13];
	$powerU2 =~ m/value":(.*),"unit":/;
	$powerU2 = $1;

	$hash->{READINGS}{Power_L2}{VAL}  = $powerU2;
	$hash->{READINGS}{Power_L2}{TIME}  = $timenow;
	
	my $powerU3 = $array[14];
	$powerU3 =~ m/value":(.*),"unit":/;
	$powerU3 = $1;

	$hash->{READINGS}{Power_L3}{VAL}  = $powerU3;
	$hash->{READINGS}{Power_L3}{TIME}  = $timenow;

	$log = "PowerTotal: $powercounter lastPower: $powernow Power_L1: $powerU1 Power_L2: $powerU2 Power_L3: $powerU3";
	
     	push @{$hash->{CHANGED}}, $log;
     	DoTrigger($hash->{NAME}, undef) if ($init_done);
     	Log3 $hash, 4, "$hash->{NAME} write log file: $log";
	if ( $hash->{STATE} eq 'Initializing' || $hash->{STATE} eq 'disconnected' ){
	 	$hash->{STATE} = 'Connected';
	}
}else{
	$hash->{STATE} = 'disconnected';
     	Log3 $hash, 3, "$hash->{NAME} can't update - device send a error";
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
 	return "Unknown argument ?, choose one of lastPower PowerTotal Power_L1 Power_L2 Power_L3";
 }
 Log3 $hash, 3, "$args[0] $get => $val";

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

<a name="EFR"></a>

<h3>EFR</h3>
<ul><p>
This module supports EFR Power Meter.<br>
The electricity meter will be polled in a defined interval for new values.
</p>
 <b>Define</b><br>
  <code>define &lt;name&gt; EFR &lt;host&gt; &lt;port&gt; [&lt;interval&gt; &lt;timeout&gt;]</code><br>
  <p>
  Example:<br>
  define StromZ1 EFR 192.168.178.20 <br>
  define StromZ2 EFR 192.168.10.25 300 60 <br>
  </p>

  <b>Set</b><br>
  set &lt;name&gt; &lt;value&gt; &lt;nummber&gt;<br>where value is one of:<br><br>
  <ul>
  <li><code>Interval</code> </li>
   </ul>
   <br>Example:<br>
  set &lt;name&gt; not implemented <br><br>

 <b>Get</b><br>
 get &lt;name&gt; &lt;value&gt; <br>where value is one of:<br>
  <ul>
  <li><code>lastPower  </code></li>
  <li><code>PowerTotal  </code></li>
  <li><code>Power_L1  </code></li>
  <li><code>Power_L2  </code></li>
  <li><code>Power_L3  </code></li>
  <li><code>Interval </code> </li>
   </ul>
 <br>Example:<br>
  get &lt;name&gt; lastPower<br><br>
  
</ul>

=end html
=cut

