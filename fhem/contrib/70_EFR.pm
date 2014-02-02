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
# Version = 1.3
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
use Blocking;
use MIME::Base64;

my @gets = ('xxx');

sub
EFR_Initialize($)
{
my ($hash) = @_;

 $hash->{DefFn}    = "energy_efr_Define";
 $hash->{UndefFn}  = "energy_efr_Undef";
 $hash->{GetFn}    = "energy_efr_Get";
 $hash->{StateFn}  = "energy_efr_State";
 $hash->{SetFn}    = "energy_efr_Set";
 $hash->{AttrFn}   = "energy_efr_Attr";
 $hash->{AttrList} = "URL FELDER FELDERNAME";

}
sub
energy_efr_Attr($@)
{
    my (@a) = @_;
    my $hash = $defs{$a[1]};
    my $name = $hash->{NAME};
    if($a[0] eq "set"){
	Log3 $hash, 3,"set attribute: $name attribute: $a[1] value:$a[2]";

    }
    elsif($a[0] eq "del")
    {
	# delete attribute
	Log3 $hash, 3,"del attribute: $name attribute: $a[1] value:$a[2]";
    }
    return undef;

} # energy_efr_Attr ende

sub
energy_efr_State($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
	$hash->{READINGS}{$vt}{VAL} = $val;
	$hash->{READINGS}{$vt}{TIME} = TimeNow();
	Log3 $hash, 4, "energy_efr_State: time: $tim name: $vt value: $val";
  return undef;
}

sub
energy_efr_Set($$$$)
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
energy_efr_Define($$)
{
 my ($hash, $def) = @_;

 my @args = split("[ \t]+", $def);

 if (int(@args) < 3)
 {
  return "energy_efr_Define: too few arguments. Usage:\n" .
         "define <name> EFR <host> [<interval> [<timeout>]]";
 }
 my $name = $args[0];
 $hash->{NAME} = $name;
 $hash->{Host}     = $args[2];
 $hash->{Port}     = 80;
 $hash->{Interval} = int(@args) >= 4 ? int($args[3]) : 300;
 $hash->{Timeout}  = int(@args) >= 5 ? int($args[4]) : 4;

 Log3 $hash, 4, "$hash->{NAME} will read from EFR at $hash->{Host}:$hash->{Port} " ;
 $hash->{Rereads}    =  2;    # number of retries when reading curPwr of 0
 $hash->{UseSVTime}  = '';    # use the SV time as timestamp (else: TimeNow())

 $hash->{STATE} = 'Initializing';
 
 my $timenow = TimeNow();

 RemoveInternalTimer($hash);
 InternalTimer(gettimeofday()+$hash->{Interval}, "energy_Update", $hash, 0);

 Log3 $hash, 3, "$hash->{NAME} will read from EFR at $hash->{Host}:$hash->{Port} " ; 
 return undef;
}

sub
energy_Update($)
{
 my ($hash) = @_;
 my $name = $hash->{NAME};
 my $ip = $hash->{Host};
 my $port = $hash->{Port};
 my $interval = $hash->{Interval};
 
 if ( defined($attr{$name}{"URL"}) ){
  my $url = $attr{$name}{"URL"};
  $hash->{helper}{RUNNING_PID} = BlockingCall("energy_DoUpdate", $name."|".$ip."|".$port."|".$interval."|".$url, "energy_energyDone", 120, "energy_energyAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
 }else{
   Log3 $hash, 3, "$hash->{NAME} please define a valid URL as attribute" ; 
  }
}

sub
energy_DoUpdate($){
 
 my ($string) = @_;
 my ($name, $ip, $port,$interval,$url) = split("\\|", $string); 
 my $success  = 0;
 my %readings = ();
 my $timenow  = TimeNow();
 my $timeout = 10;
 my $counts = 0 ;
 my $summary = 0 ;
 #my $url="/json.txt?LogName=user\&LogPSWD=user";
 #my $url="/efr/efr.txt";
 my $socket ;
 my $buf ;
 my $message ;

   Log3 $name, 4, "EFR $name ip: $ip port: $port URL: $url" ; 
$socket = new IO::Socket::INET (
              PeerAddr => $ip,
              PeerPort => $port,
              Proto    => 'tcp',
              Reuse    => 0,
              Timeout  => $timeout
              );

if (defined ($socket) and $socket and $socket->connected())
{
	print $socket "GET $url HTTP/1.0\r\n\r\n";
	$socket->autoflush(1);
	while ((read $socket, $buf, 1024) > 0)
	{
      		$message .= $buf;
			Log3 $name, 5, "buf: $buf";
	}
	$socket->close();
	Log3 $name, 4, "Socket closed";
	$success = 0;
}else{
  	Log3 $name, 3, "$name Cannot open socket ...";
        $success = 1;
}

	$message = encode_base64($message,"");
 if ( $success == 0 ){
	my $back = $name ."|". $message;
	return "$name|$message" ;
 }else{
	return "$name|-1";
 }
}

sub
energy_energyDone($)
{
  my ($string) = @_;
  return unless(defined($string));
  my (@a) = split("\\|", $string);
  my $hash = $defs{$a[0]};
  my $message = decode_base64($a[1]);
  my @array;
  my $log = "";
  my $timenow = TimeNow();
  my $name = $hash->{NAME};
  my $felder = $attr{$name}{"FELDER"};
  Log3 $name, 4, "name: $name felder: $felder"; 
  
  delete($hash->{helper}{RUNNING_PID});
  
  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{Interval}, "energy_Update", $hash, 1);
  }
  if ($hash->{Interval} > 0) {
   InternalTimer(gettimeofday() + $hash->{Interval}, "energy_Update", $hash, 0);
  }
my %pair;
my $out = "";
my $feldername = "";
my $f = "";
if ( $message ne "-1"  ){
    @array=split(/\{/,$message);
    if ( $felder ne "" ){  # FELDER zu namen mappen und dann loggen
	my @field=split(/\|/,$felder); 
	foreach $f (@field){ 
	     my $value =$array[$f];
	     $value =~ m/value":(.*)"unit":/;
	     if ( $1 ne "" ){
		$out = $1;
		$out =~ s/\,//;
		# felder in namen mappen
  		my $feldername = $attr{$name}{"FELDERNAME"};
    		if ( $feldername ne "" ){
			%pair = map{split /=/, $_}(split /\|/, $feldername);
		   if ($pair{$f} ne ""){
              		$hash->{READINGS}{$pair{$f}}{VAL} = $out;
  			$hash->{READINGS}{$pair{$f}}{TIME} = $timenow;
     			push @{$hash->{CHANGED}}, "$pair{$f} $out" ;
			$log .= $pair{$f}.": ". $out;
     		    	Log3 $hash, 4, "$name feld: $f value: $out hash: $pair{$f} mapped!";
		   }else{
              		$hash->{READINGS}{$f}{VAL} = $out;
  			$hash->{READINGS}{$f}{TIME} = $timenow;
     			push @{$hash->{CHANGED}}, "$f $out" ;
			$log .= $f.": ". $out;
     		    Log3 $hash, 4, "$name feld: $f value: $out ";

		   }
		 $log .= " ";
		}else{
			$log .= $f.": 0 ";
		}
	     }
	} # for ende
    }else{
		my $count = "0";
		foreach my $f (@array){
			$count += 1;
			$f =~ m/value":(.*)"unit":/;
			$log = "Attribute FELDER not defined please define it with one or more of them:\n";
			if ( $1 ne "" ){
				my $out = $1;
				$out =~ s/\,//;
				$log .= "FELDER: ".$count.": ".$out ." ";
			 }
		}
	}
     	Log3 $hash, 5, "$name write log file: $log";

	## felder in namen mappen
  	#my $feldername = $attr{$name}{"FELDERNAME"};
     	#Log3 $hash, 5, "$name : $feldername";
    	#if ( $feldername ne "" ){
	#	my %pair = map{split /=/, $_}(split /\|/, $feldername);
    	#	while ( my ($key, $value) = each(%pair) ) {
     	#	Log3 $hash, 5, "$name xx $key => $value";
	#	$log =~ s/$key:/$value/g;  
    	#	}
	#}
	
     	#push @{$hash->{CHANGED}}, $log;
     	DoTrigger($hash->{NAME}, undef) if ($init_done);
     	#Log3 $hash, 4, "$hash->{NAME} write log file: $log";
	if ( $hash->{STATE} eq 'Initializing' || $hash->{STATE} eq 'disconnected' ){
	 	$hash->{STATE} = 'Connected';
	}
	$hash->{STATE} = $log;
}else{
	$hash->{STATE} = 'disconnected';
     	Log3 $hash, 3, "$hash->{NAME} can't update - device send a error";
}

 Log3 $hash, 5, "$hash->{NAME} loop done " ; 
return undef;
}

sub
energy_energyAborted($)
{
  my ($hash) = @_;
  
  Log3 $hash->{NAME}, 3, "BlockingCall for ". $hash->{NAME} ." was aborted";
   
  RemoveInternalTimer($hash);
  delete($hash->{helper}{RUNNING_PID});
}

sub
energy_efr_Get($@)
{
  my ($hash, @args) = @_;

  return 'energy_efr_Get needs two arguments' if (@args != 2);

  energy_Update($hash) unless $hash->{Interval};

  my $get = $args[1];
  my $val = -1;
  my $name = $hash->{NAME};
  my $felder = $attr{$name}{"FELDER"};

  if ( $felder ne "" ){
	$felder =~ s/\|/ /g;
  	my $feldername = $attr{$name}{"FELDERNAME"};
     	Log3 $hash, 4, "felder: $felder $name : $feldername";
    	if ( $feldername ne "" ){
	    my %pair = map{split /=/, $_}(split /\|/, $feldername);
    	    while ( my ($key, $value) = each(%pair) ) {
     		Log3 $hash, 4, "$name xx $key => $value felder: $felder feldername: $feldername";
		$felder =~ s/$key/$value/g;
    	    }
	}
  }

  if (defined($hash->{READINGS}{$get})) {
	$val = $hash->{READINGS}{$get}{VAL};
  } else {
	return "energy_efr_Get: no such reading: $get";
  }
  if ( $get eq "?"){
	 return "Unknown argument ?, choose one of $felder";
	 my $felder = $attr{$name}{"FELDER"};
	 Log3 $name, 3, "felder: $felder"; 
 }
 Log3 $hash, 3, "$args[0] $get => $val";

 return $val;
}

sub
energy_efr_Undef($$)
{
 my ($hash, $args) = @_;

 RemoveInternalTimer($hash) if $hash->{Interval};

 BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

 return undef;
}

1;

=pod
=begin html

<a name="EFR"></a>

<h3>EFR</h3>
<ul><p>
This module supports EFR Power Meter. <br>
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
 get &lt;name&gt; &lt;value&gt; <br>where value is one of the defined FELDER:<br>
  <ul>
  <li><code>11</code></li>
   </ul>
 <br>Example:<br>
  get &lt;name&gt; 14<br><br>
  
</ul>

=end html
=cut

