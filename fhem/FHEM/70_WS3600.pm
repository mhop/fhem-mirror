################################################################
#
#  Copyright notice
#
#  (c) 2009 Copyright: Kai 'wusel' Siering (wusel+fhem at uu dot org)
#  All rights reserved
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
################################################################
package main;
###########################
# 70_WS3600.pm
# Modul for FHEM
#
# Contributed by Kai 'wusel' Siering <wusel+fhem@uu.org> in 2009/2010
# Based in part on work for FHEM by other authors ...
# $Id$
###########################
# 15.06.2013 Josch (Josch at abwesend dot de) some debugging
# 25.06.2013 Josch combined Date/Time-Records supported
# 12.07.2013 Josch documentation reworked
# 15.07.2013 Josch state handling improved (shows conn problems)
# 16.08.2013 Josch Logging improved: Level relative to verbosity level
# 27.08.2013 Josch Change to Log3, loglevel removed
# 02.10.2013 Josch check if rawreading defined (empty lines)
# 22.10.2013 Josch update readings with readingsBulkUpdate()
use strict;
use warnings;
#use Device::SerialPort;

# all records except Time- and Date/Time-Records
my %TranslatedCodes = (
    "Date"    => "DTime",
    "Ti"      => "Temp-inside",
    "Timin"   => "Temp-inside-min",
    "Timax"   => "Temp-inside-max",
    "DTimin"  => "Temp-inside-min-DTime",
    "DTimax"  => "Temp-inside-max-DTime",
    "To"      => "Temp-outside",
    "Tomin"   => "Temp-outside-min",
    "Tomax"   => "Temp-outside-max",
    "DTomin"  => "Temp-outside-min-DTime",
    "DTomax"  => "Temp-outside-max-DTime",
    "DP"      => "Dew-Point",
    "DPmin"   => "Dew-Point-min",
    "DPmax"   => "Dew-Point-max",
    "DDPmin"  => "Dew-Point-min-DTime",
    "DDPmax"  => "Dew-Point-min-DTime",
    "RHi"     => "rel-Humidity-inside",
    "RHimin"  => "rel-Humidity-inside-min",
    "RHimax"  => "rel-Humidity-inside-max",
    "DRHimin" => "rel-Humidity-inside-min-DTime",
    "DRHimax" => "rel-Humidity-inside-max-DTime",
    "RHo"     => "rel-Humidity-outside",
    "RHomin"  => "rel-Humidity-outside-min",
    "RHomax"  => "rel-Humidity-outside-max",
    "DRHomin" => "rel-Humidity-outside-min-DTime",
    "DRHomax" => "rel-Humidity-outside-max-DTime",
    "WS"      => "Wind-Speed",
    "DIRtext" => "Wind-Direction-Text",
    "DIR0"    => "Wind-DIR0",
    "DIR1"    => "Wind-DIR1",
    "DIR2"    => "Wind-DIR2",
    "DIR3"    => "Wind-DIR3",
    "DIR4"    => "Wind-DIR4",
    "DIR5"    => "Wind-DIR5",
    "WC"      => "Wind-Chill",
    "WCmin"   => "Wind-Chill-min",
    "WCmax"   => "Wind-Chill-max",
    "DWCmin"  => "Wind-Chill-min-DTime",
    "DWCmax"  => "Wind-Chill-max-DTime",
    "WSmin"   => "Wind-Speed-min",
    "WSmax"   => "Wind-Speed-max",
    "DWSmin"  => "Wind-Speed-min-DTime",
    "DWSmax"  => "Wind-Speed-max-DTime",
    "R1h"     => "Rain-1h",
    "R1hmax"  => "Rain-1h-hmax",
    "DR1hmax" => "Rain-1h-hmax-DTime",
    "R24h"    => "Rain-24h",
    "R24hmax" => "Rain-24-hmax",
    "DR24hmax"=> "Rain-24h-max-DTime",
    "R1w"     => "Rain-1w",
    "R1wmax"  => "Rain-1w-max",
    "DR1wmax" => "Rain-1w-max-DTime",
    "R1m"     => "Rain-1M",
    "R1mmax"  => "Rain-1M-max",
    "DR1mmax" => "Rain-1M-max-DTime",
    "Rtot"    => "Rain-total",
    "DRtot"   => "Rain-total-DTime",
    "RP"      => "rel-Pressure",
    "AP"      => "abs-Pressure",
    "RPmin"   => "rel-Pressure-min",
    "RPmax"   => "rel-Pressure-max",
    "DRPmin"  => "rel-Pressure-min-DTime",
    "DRPmax"  => "rel-Pressure-max-DTime",
    "Tendency"=> "Tendency",
    "Forecast"=> "Forecast",
#added for WS-0101 / WS-1080
    "WG"      => "Wind-Gust",
    "DIR"     => "Wind-Dir",
    "state"   => "State",
);

# Date/Time-Records
my %TranslatedDateTimeCodes = (
    "DTime"    => "DTime",
    "DTTimin"  => "Temp-inside-min-DTime",
    "DTTimax"  => "Temp-inside-max-DTime",
    "DTTomin"  => "Temp-outside-min-DTime",
    "DTTomax"  => "Temp-outside-max-DTime",
    "DTDPmin"  => "Dew-Point-min-DTime",
    "DTDPmax"  => "Dew-Point-min-DTime",
    "DTRHimin" => "rel-Humidity-inside-min-DTime",
    "DTRHimax" => "rel-Humidity-inside-max-DTime",
    "DTRHomin" => "rel-Humidity-outside-min-DTime",
    "DTRHomax" => "rel-Humidity-outside-max-DTime",
    "DTWCmin"  => "Wind-Chill-min-DTime",
    "DTWCmax"  => "Wind-Chill-max-DTime",
    "DTWSmin"  => "Wind-Speed-min-DTime",
    "DTWSmax"  => "Wind-Speed-max-DTime",
    "DTR1hmax" => "Rain-1h-hmax-DTime",
    "DTR24hmax"=> "Rain-24h-max-DTime",
    "DTR1wmax" => "Rain-1w-max-DTime",
    "DTR1mmax" => "Rain-1M-max-DTime",
    "DTRtot"   => "Rain-total-DTime",
    "DTRPmin"  => "rel-Pressure-min-DTime",
    "DTRPmax"  => "rel-Pressure-max-DTime",
);

# Time-Records (will be appended to Date-Record)
my %TranslatedTimeCodes = (
    "Time"    => "DTime",
    "TTimin"  => "Temp-inside-min-DTime",
    "TTimax"  => "Temp-inside-max-DTime",
    "TTomin"  => "Temp-outside-min-DTime",
    "TTomax"  => "Temp-outside-max-DTime",
    "TDPmin"  => "Dew-Point-min-DTime",
    "TDPmax"  => "Dew-Point-min-DTime",
    "TRHimin" => "rel-Humidity-inside-min-DTime",
    "TRHimax" => "rel-Humidity-inside-max-DTime",
    "TRHomin" => "rel-Humidity-outside-min-DTime",
    "TRHomax" => "rel-Humidity-outside-max-DTime",
    "TWCmin"  => "Wind-Chill-min-DTime",
    "TWCmax"  => "Wind-Chill-max-DTime",
    "TWSmin"  => "Wind-Speed-min-DTime",
    "TWSmax"  => "Wind-Speed-max-DTime",
    "TR1hmax" => "Rain-1h-hmax-DTime",
    "TR24hmax"=> "Rain-24h-max-DTime",
    "TR1wmax" => "Rain-1w-max-DTime",
    "TR1mmax" => "Rain-1M-max-DTime",
    "TRtot"   => "Rain-total-DTime",
    "TRPmin"  => "rel-Pressure-min-DTime",
    "TRPmax"  => "rel-Pressure-max-DTime",
);

#####################################
sub
WS3600_Initialize($)
{
  my ($hash) = @_;

# Consumer
  $hash->{DefFn}   = "WS3600_Define";
  $hash->{AttrList}= "model:WS3600,WS2300,WS1080";
#  $hash->{ReadFn}  = "WS3600_Read";
  $hash->{UndefFn} = "WS3600_Undef";
}

#####################################
sub
WS3600_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("\"", $def);
  my $dev;
  my $Timer = 60;	# call every 64 seconds; normal wireless update interval
                  # is 128 sec, on wind >10 m/s 32 sec. 64 sec should ensure
                  # quite current data.

  if(@a==1) {
    @a = split("[ \t][ \t]*", $def);	#compatibility for old syntax
    return "wrong syntax: define <name> WS3600 \"</path/to/extprog [<options>]>\" [<readinterval in s>]" if(@a!=3);
    $dev = $a[2];
  }
  else {
    return "wrong syntax: define <name> WS3600 \"</path/to/extprog [<options>]>\" [<readinterval in s>]" if(@a < 2 || @a > 3);
    $dev   = $a[1];
    $Timer = $a[2] if((@a==3)&&($a[2]>=10));
  }

  my $name = $hash->{NAME};
  my $ret = `$dev`;	#call external program
  Log3 $name, 4, "WS3600(Dbg): $name ret=$ret";

  return "WS3600(Err): Can't start $dev: $!" if(!defined($ret));

#  Log3 $name, 3, "WS3600 $dev started";

  $hash->{DeviceName} = $dev;
  $hash->{Timer}      = $Timer;

  my $nt = gettimeofday() + $hash->{Timer};
  $nt -= $nt % $hash->{Timer};	# round
  Log3 $name, 3, "WS3600(Msg): $name initialized, setting callback timer to " . FmtTime($nt) . "(+ $Timer s)";

  RemoveInternalTimer($hash);
  InternalTimer($nt, "WS3600_Read", $hash, 0);

  $hash->{STATE} = "initialized";
  return undef;
}

#####################################
sub
WS3600_Undef($$)
{
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);
  $hash->{STATE}='undefined';
  Log3 $name, 3, "WS3600(Msg): $name shutdown complete";
  return undef;
}

#####################################
sub
WS3600_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};
  my @lines;
  my $tn = TimeNow();
  my $reading;
  my $AnythingRead = 0;

  $hash->{LastRead} = $tn;
  readingsBeginUpdate($hash);
  if(defined($defs{$name}{READINGS}{"State"})) {
    readingsBulkUpdate($hash,"State", 0xFF);
  }

#  Log 4-GetLogLevel($name,0), "WS3600(Dbg): (4) Info";
#  Log 3-GetLogLevel($name,0), "WS3600(Msg): (3) Msg";
#  Log 2-GetLogLevel($name,0), "WS3600(Wng): (2) Warning";
#  Log 1-GetLogLevel($name,0), "WS3600(Err): (1) Error";

#  Log3 $name, 4, "WS3600(Dbg): $name Read started using \"$dev\"";
  Log3 $name, 3, "WS3600(Msg): $name Read started";
  @lines = `$dev`;	# call external program

  foreach my $inputline ( @lines ) {
    $inputline =~ s/\s+$//;
    my ($rawreading, $val, $val2) = split(/ /, $inputline);
    if(defined($rawreading)) {
    Log3 $name, 4, "WS3600(Dbg): $name read $inputline|$rawreading|$val|$val2";
	    if(defined($TranslatedCodes{$rawreading})) {
	      $reading = $TranslatedCodes{$rawreading};
              readingsBulkUpdate($hash,$reading, $val);
	      $AnythingRead = 1;
	    }
	    # write Date/Time-Records
	    elsif(defined($TranslatedDateTimeCodes{$rawreading})) {
	      $reading = $TranslatedDateTimeCodes{$rawreading};
              readingsBulkUpdate($hash,$reading, $val . " " . $val2);
	      $AnythingRead = 1;
	    }
	    # append Time-Record to Date-Record (managed by same Name)
	    elsif(defined($TranslatedTimeCodes{$rawreading})) {
	      $reading = $TranslatedTimeCodes{$rawreading};
	      $defs{$name}{READINGS}{$reading}{VAL}  .= " " . $val;
	      $defs{$name}{READINGS}{$reading}{TIME} = $tn;
	      $AnythingRead = 1;
	    }
    }
  }
  if($AnythingRead) {
    $hash->{STATE} =  "T: "  . $defs{$name}{READINGS}{"Temp-outside"}{VAL}
	                 . " H: "  . $defs{$name}{READINGS}{"rel-Humidity-outside"}{VAL}
	                 . " W: "  . $defs{$name}{READINGS}{"Wind-Speed"}{VAL}
	                 . " R: "  . $defs{$name}{READINGS}{"Rain-total"}{VAL}
	                 . " Ti: " . $defs{$name}{READINGS}{"Temp-inside"}{VAL}
	                 . " Hi: " . $defs{$name}{READINGS}{"rel-Humidity-inside"}{VAL};

    $hash->{CHANGED}[0] = $hash->{STATE};
  }
  else {
    $hash->{STATE} = "no data received";
  }
  readingsEndUpdate($hash,1);
  # Call us in n seconds again.
  my $nt = gettimeofday() + $hash->{Timer};
  $nt -= $nt % $hash->{Timer};	# round
  RemoveInternalTimer($hash);
  InternalTimer($nt, "WS3600_Read", $hash, 0);
 
  return $hash->{STATE};
}

1;

=pod
=begin html

<a name="WS3600"></a>
<h3>WS3600</h3>
<ul>
  Defines a weather station, which is queried by means of an external
  program. That program is executed by FHEM and is expected to deliver the
  data at stdout in the format of a WS3600 series weather station (details
  see below).<br>
  <br>
  <a name="WS3600define"></a> <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WS3600 "&lt;wsreaderprog&gt;
      [&lt;options&gt;]" [&lt;interval&gt;]</code> <br>
    <br>
    <ul>
      <dl>
        <dt>&lt;wsreaderprog&gt;</dt>
        <dd>full path to the executable which queries the weatherstation
          (for WS3600 series fetch3600 should be used)</dd>
        <dt>&lt;options&gt;</dt>
        <dd>options for &lt;wsreaderprog&gt;, if necessary</dd>
        <dt>&lt;interval&gt;</dt>
        <dd>this optional parameter is the time between subsequent calls to
          &lt;wsreaderprog&gt;. It defaults to 60s.</dd>
      </dl>
    </ul>
    <br>
    Supported Stations are:<br>
    <ul>
      <li>WS3600 series weather station (Europe Supplies, technotrade, etc;
        refer to <a href="http://wiki.wetterstationen.info/index.php?title=LaCrosse_WS3600">Wetterstationen.info</a>
        (german) for details on this model) with fetch3600 from the
        toolchain <a href="http://open3600.fast-mail.nl/tiki-index.php">open3600</a>).
        Fetch3600 delivers the current readings line by line as
        reading-value-pairs. These are read periodically and translated into
        more readable names for FHEM by the module WS3600.pm. </li>
      <li><a href="http://wiki.wetterstationen.info/index.php?title=LaCrosse_WS2300">WS2300</a>
        with toolchain <a href="http://www.lavrsen.dk/twiki/bin/view/Open2300/WebHome">open2300</a>,
        because it is rather similar to the WS3600.</li>
      <li><a href="http://wiki.wetterstationen.info/index.php?title=WS1080">WS1080</a>
        (and other stations which come with the EasyWeather windows
        application) with <a href="https://code.google.com/p/fowsr/">fowsr</a>
        (version 2.0 or above)</li>
    </ul>
    <br>
    Currently, it is expected that the WS is attached to the local computer
    and &lt;wsreaderprog&gt; is run locally. Basically the executable called
    needs to supply on stdout an output similar to what fetch3600 returns;
    how to implement a "networked setup" is left as an excercise to the
    reader. <br>
    For the records, this is an output of fetch3600:<br>
    <div style="height: 120px; width: 215px; border: 1px solid #cccccc; overflow: auto;">
      <pre>Date 14-Nov-2009
Time 10:50:22
Ti 22.8
Timin 20.8
Timax 27.9
TTimin 10:27
DTimin 15-10-2009
TTimax 23:31
DTimax 20-08-2009
To 14.2
Tomin -0.4
Tomax 35.6
TTomin 07:03
DTomin 15-10-2009
TTomax 16:52
DTomax 20-08-2009
DP 9.2
DPmin -2.2
DPmax 20.3
TDPmin 07:03
DDPmin 15-10-2009
TDPmax 11:58
DDPmax 20-08-2009
RHi 48
RHimin 32
RHimax 57
TRHimin 17:03
DRHimin 21-10-2009
TRHimax 22:24
DRHimax 07-10-2009
RHo 72
RHomin 27
RHomax 96
TRHomin 16:41
DRHomin 20-08-2009
TRHomax 06:28
DRHomax 02-11-2009
WS 0.0
DIRtext WSW
DIR0 247.5
DIR1 247.5
DIR2 247.5
DIR3 247.5
DIR4 247.5
DIR5 247.5
WC 14.2
WCmin -0.4
WCmax 35.6
TWCmin 07:03
DWCmin 15-10-2009
TWCmax 16:52
DWCmax 20-08-2009
WSmin 0.0
WSmax 25.6
TWSmin 10:44
DWSmin 14-11-2009
TWSmax 19:08
DWSmax 24-09-2009
R1h 0.00
R1hmax 24.34
TR1hmax 22:34
DR1hmax 07-10-2009
R24h 0.00
R24hmax 55.42
TR24hmax 07:11
DR24hmax 08-10-2009
R1w 29.00
R1wmax 95.83
TR1wmax 00:00
DR1wmax 12-10-2009
R1m 117.58
R1mmax 117.58
TR1mmax 00:00
DR1mmax 01-11-2009
Rtot 3028.70
TRtot 03:29
DRtot 18-09-2005
RP 992.200
AP 995.900
RPmin 970.300
RPmax 1020.000
TRPmin 05:25
DRPmin 04-11-2009
TRPmax 09:19
DRPmax 11-09-2009
Tendency Falling
Forecast Cloudy</pre>
    </div>
    There is no expectation on the readings received from the fetch3600
    binary; so, in essence, if you have a similar setup (unsupported,
    attached weather station and a means to get it's reading into an output
    similar to above's), you <em>should be able</em> to use WS3600.pm with
    a custom written script to interface FHEM with your station as well.
    WS3600.pm <em>only recognizes the above readings</em> (and translates
    these into, e. g., <code>Temp-inside</code> for <code>Ti</code> for
    use within FHEM), other lines are silently dropped on the floor. Note:
    To step down the number of readings date and time records will now be
    merged to one reading containing date and time. This now also allows
    records with merged date / time values delivered from
    &lt;wsreaderprog&gt; - detected by prefix <code>DT</code> (e.g. <code>Date</code>
    + <code>Time</code> --&gt; <code>DTime</code>, <code>DRPmin</code> +
    <code>TRPmin</code> --&gt; <code>DTRPmin</code> and so on). <br>
    fetch3600 is available as binary for the Windows OS as well, <em>but
      operation under that OS isn't tested yet.</em> <br>
    <br>
    Examples:
    <ul>
      <code>define myWS3600 W3600 /usr/local/bin/fetch360</code><br>
      <code>define myWS1080 W3600 "/usr/local/bin/fowsr -c" 300</code><br>
    </ul>
    <br>
  </ul>
  <a name="WS3600set"></a> <b>Set</b>
  <ul>
    N/A
  </ul>
  <br>
  <a name="WS3600get"></a> <b>Get</b>
  <ul>
    N/A
  </ul>
  <br>
  <a name="WS3600attr"></a> <b>Attributes</b>
  <ul>
    <li><a href="#model">model</a>&nbsp;&nbsp;&nbsp;&nbsp; WS3600, WS2300,
      WS1080 (not used for anything, yet)</li>
  </ul>
  <br>
</ul>

=end html
=begin html_DE

<a name="WS3600"></a>
<h3>WS3600</h3>
<ul>
  Definiert eine Wetterstation, die über ein externes Programm ausgelesen
  wird. Dieses Programm wird zyklisch durch FHEM aufgerufen. Es muss die
  Daten im gleichen Format wie fetch3600 (Details siehe unten) auf der
  Standardausgabe liefern.<br>
  <br>
  <a name="WS3600define"></a> <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WS3600 "&lt;wsreaderprog&gt;
      [&lt;options&gt;]" [&lt;interval&gt;]</code> <br>
    <br>
    <ul>
      <dl>
        <dt>&lt;wsreaderprog&gt;</dt>
        <dd>kompletter Pfad zum Ausleseprogramm (für Wetterstationen Typ
          WS3600 fetch3600 verwenden)</dd>
        <dt>&lt;options&gt;</dt>
        <dd>Kommandozeilenparameter für &lt;wsreaderprog&gt;, falls
          erforderlich</dd>
        <dt>&lt;interval&gt;</dt>
        <dd>optionaler Parameter für das Aufrufintervall [s]. Defaultwert
          ist 60s.</dd>
      </dl>
    </ul>
    <br>
    &nbsp; Unterstützte Stationen sind:<br>
    <ul>
      <li>WS3600 Serie (Europe Supplies, technotrade, usw.; s.a. <a href="http://wiki.wetterstationen.info/index.php?title=LaCrosse_WS3600">Wetterstationen.info</a>
        (deutsch) für Details) in Verbindung mit fetch3600 aus dem Paket <a
          href="http://open3600.fast-mail.nl/tiki-index.php">open3600</a>).
        Fetch3600 liefert die aktuellen Werte zeilenweise als
        Name-Wert-Paare. Diese werden durch FHEM zyklisch eingelesen, mit
        besser lesbaren Bezeichnungen versehen und als Readings zur
        Verfügung gestellt. </li>
      <li><a href="http://wiki.wetterstationen.info/index.php?title=LaCrosse_WS2300">WS2300</a>
        Serie in Verbindung mit dem Paket <a href="http://www.lavrsen.dk/twiki/bin/view/Open2300/WebHome">open2300</a>
        (ähnlich zu open3600).</li>
      <li><a href="http://wiki.wetterstationen.info/index.php?title=WS1080">WS1080</a>
        (und andere Stationen, die mit der Windows-Software "Easy Weather"
        ausgeliefert werden) in Verbindung mit <a href="https://code.google.com/p/fowsr/">fowsr</a>
        (ab Version 2.0)</li>
    </ul>
    <br>
    Es wird vorausgesetzt, dass die Wetterstation am lokalen Computer
    angeschlossen ist und &lt;wsreaderprog&gt; deshalb lokal läuft.
    &lt;wsreaderprog&gt; muss grundsätzlich eine zu fetch3600 vergleichbare
    Ausgabe auf der Standardausgabe liefern. <br>
    Als Beispiel für das erwartete Format hier die Ausgabe von fetch3600:<br>
    <div style="height: 120px; width: 215px; border: 1px solid #cccccc; overflow: auto;">
      <pre>Date 14-Nov-2009
Time 10:50:22
Ti 22.8
Timin 20.8
Timax 27.9
TTimin 10:27
DTimin 15-10-2009
TTimax 23:31
DTimax 20-08-2009
To 14.2
Tomin -0.4
Tomax 35.6
TTomin 07:03
DTomin 15-10-2009
TTomax 16:52
DTomax 20-08-2009
DP 9.2
DPmin -2.2
DPmax 20.3
TDPmin 07:03
DDPmin 15-10-2009
TDPmax 11:58
DDPmax 20-08-2009
RHi 48
RHimin 32
RHimax 57
TRHimin 17:03
DRHimin 21-10-2009
TRHimax 22:24
DRHimax 07-10-2009
RHo 72
RHomin 27
RHomax 96
TRHomin 16:41
DRHomin 20-08-2009
TRHomax 06:28
DRHomax 02-11-2009
WS 0.0
DIRtext WSW
DIR0 247.5
DIR1 247.5
DIR2 247.5
DIR3 247.5
DIR4 247.5
DIR5 247.5
WC 14.2
WCmin -0.4
WCmax 35.6
TWCmin 07:03
DWCmin 15-10-2009
TWCmax 16:52
DWCmax 20-08-2009
WSmin 0.0
WSmax 25.6
TWSmin 10:44
DWSmin 14-11-2009
TWSmax 19:08
DWSmax 24-09-2009
R1h 0.00
R1hmax 24.34
TR1hmax 22:34
DR1hmax 07-10-2009
R24h 0.00
R24hmax 55.42
TR24hmax 07:11
DR24hmax 08-10-2009
R1w 29.00
R1wmax 95.83
TR1wmax 00:00
DR1wmax 12-10-2009
R1m 117.58
R1mmax 117.58
TR1mmax 00:00
DR1mmax 01-11-2009
Rtot 3028.70
TRtot 03:29
DRtot 18-09-2005
RP 992.200
AP 995.900
RPmin 970.300
RPmax 1020.000
TRPmin 05:25
DRPmin 04-11-2009
TRPmax 09:19
DRPmax 11-09-2009
Tendency Falling
Forecast Cloudy</pre>
    </div>
    Welche der vorgenannten Wertepaare durch &lt;wsreaderprog&gt;&nbsp;
    geliefert werden, ist egal. Jedes bekannte wird übersetzt (z.B. <code>Ti</code>
    nach <code>Temp-inside</code>) und als Reading angezeigt, alle
    unbekannten werden kommentarlos verworfen. Mittels geeignetem Programm
    oder Script sollte sich also jede beliebige Wetterstation anschließen
    lassen. <br>
    Anmerkung: Um die Anzahl Readings zu reduzieren, werden jetzt Date- und
    Time-Wertepaare zusammengefasst. Es ist jetzt auch zulässig, dass
    &lt;wsreaderprog&gt; schon kombinierte Wertepaare liefert. Diese sind
    mit dem Prefix <code>DT</code> zu kennzeichnen, also z.B. <code>Date</code>
    + <code>Time</code> --&gt; <code>DTime</code>, <code>DRPmin</code> +
    <code>TRPmin</code> --&gt; <code>DTRPmin</code> usw.).<br>
    <em>Fetch3600 ist auch unter Windows verfügbar, ob das Zusammenspiel mit
      FHEM dort auch funktioniert, wurde noch nicht getestet.</em> <br>
    <br>
    Beispiele:
    <ul>
      <code>define myWS3600 W3600 /usr/local/bin/fetch360</code><br>
      <code>define myWS1080 W3600 "/usr/local/bin/fowsr -c" 300</code><br>
    </ul>
    <br>
  </ul>
  <a name="WS3600set"></a> <b>Set</b>
  <ul>
    N/A
  </ul>
  <br>
  <a name="WS3600get"></a> <b>Get</b>
  <ul>
    N/A
  </ul>
  <br>
  <a name="WS3600attr"></a> <b>Attributes</b>
  <ul>
    <li><a href="#model">model</a>&nbsp;&nbsp;&nbsp;&nbsp; WS3600, WS2300,
      WS1080 (z.Zt (noch) ohne Wirkung)</li>
  </ul>
  <br>
</ul>

=end html_DE
=cut
