#######################################################################
#
# 95_PachLog.pm
#
# Logging to www.pachube.com
# Autor: a[PUNKT]r[BEI]oo2p[PUNKT]net
# Stand: 09.09.2009
# Version: 0.9
#######################################################################
# Vorausetzung: Account bei www.pachube.com mit API-Key
#######################################################################
#
# FHEM: Neues Pachube-Device erstelle: define <NAME> PachLog API-Key
#       "define PACH001 PachLog 1234kliceee77hgtzuippkk99"
#
# PACHUBE: FEED erstellen -> FEED-NR: DATASTREAM-ID:TAGS
#          Beispiel: HMS_TF (Temperatur und Feuchte Sensor)
#          FEED-NR: 1234
#          ID 0 => Temperatur (temperature)
#          ID 1 => rel. Luftfeuchte (humidity)
#
# FHEM: PachLog-Devices: PACH01
#       HMS_DEVICE: HMS_TF01
#       FEED-NR: 1234
#       ID 0 => Temperatur (temperature)
#       ID 1 => rel. Luftfeuchte (humidity)
#       "set PACH01 ADD HMS_TF01 1234:0:temperature:1:humidity"
#
# Hinweise:
# Ein FEED kann nur komplett upgedated werden:
# FEED 3456 -> ID 0 -> DEVICE A
# FEED 3456 -> ID 1 -> DEVICE B
# => geht nicht
#
# Es werden nur READINGS mit einfach Werten und Zahlen unterst?tzt.
# Beispiele: NICHT unterst?tze READINGS
# cum_month => CUM_MONTH: 37.173 CUM: 108.090 COST: 0.00
# cum_day => 2009-09-09 00:03:19 T: 1511725.6 H: 4409616 W: 609.4 R: 150.4
# israining	no => (yes/no)
#######################################################################
# $Id$



package main;
use strict;
use warnings;
use POSIX;
use Data::Dumper;
use LWP;
use LWP::UserAgent;
use HTTP::Request::Common;

#######################################################################
sub
PachLog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "PachLog_Define";
  $hash->{SetFn}    = "PachLog_Set";
  $hash->{GetFn}    = "PachLog_Get";
  $hash->{NotifyFn} = "PachLog_Notify";
  $hash->{AttrList}  = "do_not_notify:0,1 loglevel:0,5 disable:0,1";
}
#######################################################################
sub PachLog_Define($@)
{
# define <NAME> PachLog Pachube-X-API-Key
  my ($hash, @a) = @_;
  # X-API-Key steht im DEF %defs{<NAME>}{DEF}
  # Alternativ nach $defs{<NAME>}{XAPIKEY}
  my($package, $filename, $line, $subroutine) = caller(3);
  # Log 0 , "PachLog_Define => $package: $filename LINE: $line SUB: $subroutine \n";
  Log 5, Dumper(@_) . "\n";
  return "Unknown argument count " . int(@a) . " , usage set <name> dataset value or set <name> delete dataset"  if(int(@a) != 1);
  return undef;


}
#######################################################################
sub PachLog_Set($@)
{
# set <NAME> ADD/DEL <DEVICENAME> FEED:STREAM:VALUE:STREAM:VALUE&FEED-2:STEAM,VALUE
  my ($hash, @a) = @_ ;
  # FHEMWEB Frage....Auswahliste
  return "Unknown argument $a[1], choose one of ". join(" ",sort keys %{$hash->{READINGS}}) if($a[1] eq "?");
  # Pruefen Uebergabeparameter
  # @a => a[0]:<NAME>; a[1]=ADD oder DEL; a[2]= DeviceName;
  # a[3]=FEED:STREAM:VALUE:STREAM:VALUE&FEED-2:STREAM,VALUE
  # READINGS setzten oder l?schen
  if($a[1] eq "DEL")
    {
    GetLogLevel($a[0],2),"PACHLOG -> DELETE: A0= ". $a[0] . " A1= " . $a[1] . " A2=" . $a[2];
    if(defined($hash->{READINGS}{$a[2]}))
      {
      delete($hash->{READINGS}{$a[2]})
      }
    }
   if($a[1] eq "ADD")
    {
    if(!defined($defs{$a[2]})) {return "PACHLOG[". $a[2] . "] => Unkown Device";}
    # Mindestens 3 Parameter
    my @b = split(/:/, $a[3]);
    return "PACHLOG[". $a[2] . "] => Argumenete: " . $a[3] . " nicht eindeutig => mind. 3 => FEED-NR:DATASTREAM:READING"  if(int(@b) < 3);
	my $feednr = shift(@b);
	#FEED-Nr darf nur Zahlen enthalten
	if($feednr !~ /^\d+$/) {return "PACHLOG[". $a[2] . "] => FEED-Nr >" . $feednr . "< ist ungueltig";}
    # ??? Pruefen ob READING vorhanden ???
	my ($i,$j);
	for ($i=0;$i<@b;$i++)
		{
		#Stream nur Zahlen
		if($b[$i] !~ /^\d+$/) {return "PACHLOG => FEED-Nr[" . $feednr ."] Stream-ID >" . $b[$i] . "< ungueltig";}
		# Reading existiert
		$j = $i + 1;
		if(!defined($defs{$a[2]}{READINGS}{$b[$j]})) {return "PACHLOG[". $a[2] . "] => Unkown READING >" . $b[$j] . "<";}
		# READING-Value validieren
		my $r = $defs{$a[2]}{READINGS}{$b[$j]}{VAL};
		my $rn = &ReadingToNumber($r);
		if(!defined($rn)) {return "PACHLOG[". $a[$i] . "] => READING not supported >" . $b[$j] . "<";}
		$i = $j;
		}
    $hash->{READINGS}{$a[2]}{TIME} = TimeNow();
    $hash->{READINGS}{$a[2]}{VAL} = $a[3];
    }
  $hash->{CHANGED}[0] = $a[1];
  $hash->{STATE} = $a[1];
  return undef;
  return "Unknown argument count " . int(@a) . " , usage set <name> ADD/DEL <DEVICE-NAME> FEED:STREAM:VALUE:STREAM:VALUE&FEED-2:STREAM,VALUE"  if(int(@a) != 4);

}
#######################################################################
sub PachLog_Get()
{
# OHNE FUNKTION ....
  my ($name, $x_key) = @_;
  my($package, $filename, $line, $subroutine) = caller(3);
  Log 5, "PachLog_Get => $package: $filename LINE: $line SUB: $subroutine \n";
  Log 5, Dumper(@_) . "\n";
}
#######################################################################
sub PachLog_Notify ($$)
{
  my ($me, $trigger) = @_;
  my $d = $me->{NAME};
  return "" if($attr{$d} && $attr{$d}{disable});
  my $t = $trigger->{NAME};
  #LogLevel
  my $ll;
  if(defined($attr{$d}{'loglevel'})){$ll = $attr{$d}{'loglevel'};}
  else {$ll = 5;}
  # Eintrag fuer Trigger-Device vorhanden
  if(!defined($defs{$d}{READINGS}{$t}))
  {
    Log $ll, ("PACHLOG[INFO] => " . $t .  " => Nicht definiert");
    return undef;}

  # Umwandeln 1234:0:temperature:1:humidity => %feed
  # Struktur:
  # %feed{FEED-NR}{READING}{VAL}
  # %feed{FEED-NR}{READING}{DATASTREAM}
  my ($dat,@a,$feednr,$i,$j);
  my %feed = ();
  $dat = $defs{$d}{READINGS}{$t}{VAL};
  @a = split(/:/, $dat);
  $feednr = shift(@a);
  for ($i=0;$i<@a;$i++)
    {
    $j = $i + 1;
    $feed{$feednr}{$a[$j]}{STREAM} = $a[$i];
    $i = $j;
    }
  # Werte aus Trigger-Device
  foreach my $r (keys %{$feed{$feednr}})
  {
    $i = $defs{$t}{READINGS}{$r}{VAL};
    # Werte Normalisieren
    # Einheit -> 21,1 (celsius) -> 21,1
    # FS20: VAL = on => 1 && VAL = off => 0
    # @a = split(' ', $i);
    # $feed{$feednr}{$r}{VAL} = &ReadingToNumber($a[0]) ;
    $feed{$feednr}{$r}{VAL} = &ReadingToNumber($i,$ll) ;

  }
  #  Log $ll, "PACHLOG => dumper(FEED) => " .Dumper(%feed);

  # CVS-Data
  my @cvs = ();
  foreach my $r (keys %{$feed{$feednr}}) {
    $cvs[$feed{$feednr}{$r}{STREAM}] = $feed{$feednr}{$r}{VAL};
   }
  my $cvs_data = join(',',@cvs);
  Log $ll, "PACHLOG[CVSDATA] => $cvs_data";

  # Aufbereiten %feed als EEML-Data
  my $eeml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  $eeml .= "<eeml xmlns=\"http://www.eeml.org/xsd/005\">\n";
  $eeml .= "<environment>\n";
    foreach my $r (keys %{$feed{$feednr}})
      {
      $eeml .= "<data id=\"" . $feed{$feednr}{$r}{STREAM} . "\">\n";
      $eeml .= "<value>" . $feed{$feednr}{$r}{VAL} . "</value>\n";
	  # Unit fuer EEML: <unit symbol="C" type="derivedSI">Celsius</unit>
		my ($u_name,$u_symbol,$u_type,$u_tag) = split(',',&PachLog_ReadingToUnit($r,$ll));
		if(defined($u_name)) {
		$eeml .= "<tag>". $u_tag . "</tag>\n";
		$eeml .= "<unit symbol=\"" . $u_symbol. "\" type=\"" . $u_type. "\">" . $u_name . "<\/unit>\n";
		}
      $eeml .= "</data>\n";
      }
  $eeml .= "</environment>\n";
  $eeml .= "</eeml>\n";
  Log $ll, "PACHLOG -> " . $t . " EEML => " . $eeml;
  # Pachube-Update per EEML -> XML
  my ($res,$ret,$ua,$apiKey,$url);
  $apiKey = $defs{$d}{DEF};
  $url   = "http://www.pachube.com/api/feeds/" . $feednr . ".xml";
  $ua  = new LWP::UserAgent;
  $ua->default_header('X-PachubeApiKey' => $apiKey);
  #Timeout 3 sec ... default 180sec
  $ua->timeout(3);
  $res = $ua->request(PUT $url,'Content' => $eeml);
    # Ueberpruefen wir, ob alles okay war:
    if ($res->is_success())
    {
        Log 5,("PACHLOG => Update[" . $t ."]: " . $cvs_data . " >> SUCCESS\n");
        # Time setzten
        $defs{$d}{READINGS}{$t}{TIME} = TimeNow();
    }
    else {Log 0,("PACHLOG => Update[" . $t ."] ERROR: " . ($res->as_string) . "\n");}
}
################################################################################
sub PachLog_ReadingToUnit($$)
{
# Unit fuer EEML: <unit symbol="C" type="derivedSI">Celsius</unit>
# Input: READING z.B. temperature
# Output: Name,symbol,Type,Tag z.B. Celsius,C,derivedSI
# weiters => www.eeml.org
# No Match = undef
	my ($in,$ll) = @_;
	my %unit = ();
	%unit = (
		'temperature' => "Celsius,C,derivedSI,Temperature",
      'dewpoint'    => "Celsius,C,derivedSI,Temperature",
		'current'     => "Power,kW,derivedSI,EnergyConsumption",
		'humidity'    => "Humidity,rel%,contextDependentUnits,Humidity",
		'rain'        => "Rain,l/m2,contextDependentUnits,Rain",
      'rain_now'    => "Rain,l/m2,contextDependentUnits,Rain",
		'wind'        => "Wind,m/s,contextDependentUnits,Wind",
		);
	if(defined($unit{$in})) {
		Log $ll ,("PACHLOG[ReadingToUnit] " . $in . " >> " . $unit{$in} );
		return $unit{$in};}
	else {return undef;}
}
################################################################################
sub ReadingToNumber($$)
{
# Input: reading z.B. 21.1 (Celsius) oder dim10%, on-for-oldtimer etc.
# Output: 21.1 oder 10
# ERROR = undef
# Alles au?er Nummern loeschen $t =~ s/[^0123456789.-]//g;
	my ($in,$ll) = @_;
	Log $ll, "PACHLOG[ReadingToNumber] => in => $in";
	# Bekannte READINGS FS20 Devices oder FHT
	if($in =~ /^on|Switch.*on/i) {$in = 1;}
	if($in =~ /^off|Switch.*off|lime-protection/i) {$in = 0;}
	# Keine Zahl vorhanden
	if($in !~ /\d{1}/) {
        Log $ll, "PACHLOG[ReadingToNumber] No Number: $in";
        return undef;}
	# Mehrfachwerte in READING z.B. CUM_DAY: 5.040 CUM: 334.420 COST: 0.00
	my @b = split(' ', $in);
	if(int(@b) gt 2) {
        Log $ll, "PACHLOG[ReadingToNumber] Not Supportet Reading: $in";
        return undef;}
	# Nur noch Zahlen z.B. dim10% = 10 oder 21.1 (Celsius) = 21.1
	if (int(@b) eq 2){
		Log $ll, "PACHLOG[ReadingToNumber] Split:WhiteSpace-0- $b[0]";
		$in = $b[0];
		}
	$in =~ s/[^0123456789.-]//g;
	Log $ll, "PACHLOG[ReadingToNumber] => out => $in";
	return $in
}
1;

=pod
=begin html

<a name="PachLog"></a>
<h3>PachLog</h3>
<ul>
  The PachLog-Module Logs SensorData like (temperature and humidity) to <a href=http://www.pachube.com>www.pachube.com</a>.
  <br><br>
  Note: this module needs the HTTP::Request and LWP::UserAgent perl modules.
  <br><br>
  <a name="PachLogdefine"></a>
  <b>Define</b>
  <ul>
    <br><code>define &lt;name&gt; PachLog &lt;Pachube-API-Key&gt;</code> <br>
    <br>
    &lt;Pachube-API-Key&gt;:<br>
    The Pachube-API-Key however is what you need in your code to authenticate your application's access the Pachube service.<br>
    Don't share this with anyone: it's just like any other password.<br>
    <a href=http://www.pachube.com>www.pachube.com</a><br>

  </ul>
  <br>

  <a name="PachLogset"></a>
  <b>Set</b>
    <ul>
        <br>
        Add a new Device for Logging to www.pachube.com<br><br>
        <code>set &lt;NAME&gt; ADD &lt;FHEM-DEVICENAME&gt; FEED-NR:ID:READING:ID:READING</code><br><br>
        Example: KS300-Weather-Data<br><br>
        READINGS: temperature humidity wind rain<br><br>
        1. Generate Input-Feed on www.pachube.com => Yout get your FEED-NR: 1234<br>
        2. Add Datastreams to the Feed:<br>
        <ul>
        <table>
        <tr><td>ID</td><td>0</td><td>temperature</td></tr>
        <tr><td>ID</td><td>1</td><td>humidity</td></tr>
        <tr><td>ID</td><td>2</td><td>wind</td></tr>
        <tr><td>ID</td><td>3</td><td>rain</td></tr></table><br>
        </ul>
        3. Add the KS300 to your PachLog-Device<br><br>
        <code>set &lt;NAME&gt; ADD &lt;My-KS300&gt; 1234:0temperature:1:humidity:2:wind:3:rain</code><br><br>
        Delete a Device form Logging to www.pachube.com<br><br>
        <code>set &lt;NAME&gt; DEL &lt;FHEM-DEVICENAME&gt;</code><br><br>
    </ul>
    <br>

  <a name="PachLogget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="PachLogattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
    <li>disable<br>
        Disables PachLog.
        Nor more Logging to www.pachube.com
   </ul><br>


</ul>

=end html
=cut
