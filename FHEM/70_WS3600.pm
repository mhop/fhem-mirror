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
###############################################
package main;
###########################
# 70_WS3600.pm
# Modul for FHEM
#
# Contributed by Kai 'wusel' Siering <wusel+fhem@uu.org> in 2009/2010
# Based in part on work for FHEM by other authors ...
# $Id$
###########################

use strict;
use warnings;
#use Device::SerialPort;

my %sets = (
  "cmd"       => "",
  "freq"      => "",
);

my %TranslatedCodes = (
    "Date" => "Date",
    "Time" => "Time",
    "Ti" => "Temp-inside",
    "Timin" => "Temp-inside-min",
    "Timax" => "Temp-inside-max",
    "TTimin" => "Temp-inside-min-Time",
    "DTimin" => "Temp-inside-min-Date",
    "TTimax" => "Temp-inside-max-Time",
    "DTimax" => "Temp-inside-max-Date",
    "To" => "Temp-outside",
    "Tomin" => "Temp-outside-min",
    "Tomax" => "Temp-outside-max",
    "TTomin" => "Temp-outside-min-Time",
    "DTomin" => "Temp-outside-min-Date",
    "TTomax" => "Temp-outside-max-Time",
    "DTomax" => "Temp-outside-max-Date",
    "DP" => "Dew-Point",
    "DPmin" => "Dew-Point-min",
    "DPmax" => "Dew-Point-max",
    "TDPmin" => "Dew-Point-min-Time",
    "DDPmin" => "Dew-Point-min-Date",
    "TDPmax" => "Dew-Point-min-Time",
    "DDPmax" => "Dew-Point-min-Date",
    "RHi" => "rel-Humidity-inside",
    "RHimin" => "rel-Humidity-inside-min",
    "RHimax" => "rel-Humidity-inside-max",
    "TRHimin" => "rel-Humidity-inside-min-Time",
    "DRHimin" => "rel-Humidity-inside-min-Date",
    "TRHimax" => "rel-Humidity-inside-max-Time",
    "DRHimax" => "rel-Humidity-inside-max-Date",
    "RHo" => "rel-Humidity-outside",
    "RHomin" => "rel-Humidity-outside-min",
    "RHomax" => "rel-Humidity-outside-max",
    "TRHomin" => "rel-Humidity-outside-min-Time",
    "DRHomin" => "rel-Humidity-outside-min-Date",
    "TRHomax" => "rel-Humidity-outside-max-Time",
    "DRHomax" => "rel-Humidity-outside-max-Date",
    "WS" => "Wind-Speed",
    "DIRtext" => "Wind-Direction-Text",
    "DIR0" => "Wind-DIR0",
    "DIR1" => "Wind-DIR1",
    "DIR2" => "Wind-DIR2",
    "DIR3" => "Wind-DIR3",
    "DIR4" => "Wind-DIR4",
    "DIR5" => "Wind-DIR5",
    "WC" => "Wind-Chill",
    "WCmin" => "Wind-Chill-min",
    "WCmax" => "Wind-Chill-max",
    "TWCmin" => "Wind-Chill-min-Time",
    "DWCmin" => "Wind-Chill-min-Date",
    "TWCmax" => "Wind-Chill-max-Time",
    "DWCmax" => "Wind-Chill-max-Date",
    "WSmin" => "Wind-Speed-min",
    "WSmax" => "Wind-Speed-max",
    "TWSmin" => "Wind-Speed-min-Time",
    "DWSmin" => "Wind-Speed-min-Date",
    "TWSmax" => "Wind-Speed-max-Time",
    "DWSmax" => "Wind-Speed-max-Date",
    "R1h" => "Rain-1h",
    "R1hmax" => "Rain-1h-hmax",
    "TR1hmax" => "Rain-1h-hmax-Time",
    "DR1hmax" => "Rain-1h-hmax-Date",
    "R24h" => "Rain-24h",
    "R24hmax" => "Rain-24-hmax",
    "TR24hmax" => "Rain-24h-max-Time",
    "DR24hmax" => "Rain-24h-max-Date",
    "R1w" => "Rain-1w",
    "R1wmax" => "Rain-1w-max",
    "TR1wmax" => "Rain-1w-max-Time",
    "DR1wmax" => "Rain-1w-max-Date",
    "R1m" => "Rain-1M",
    "R1mmax" => "Rain-1M-max",
    "TR1mmax" => "Rain-1M-max-Time",
    "DR1mmax" => "Rain-1M-max-Date",
    "Rtot" => "Rain-total",
    "TRtot" => "Rain-total-Time",
    "DRtot" => "Rain-total-Date",
    "RP" => "rel-Pressure",
    "AP" => "abs-Pressure",
    "RPmin" => "rel-Pressure-min",
    "RPmax" => "rel-Pressure-max",
    "TRPmin" => "rel-Pressure-min-Time",
    "DRPmin" => "rel-Pressure-min-Date",
    "TRPmax" => "rel-Pressure-max-Time",
    "DRPmax" => "rel-Pressure-max-Date",
    "Tendency" => "Tendency",
    "Forecast" => "Forecast",
);

my %WantedCodesForStatus = (
    "Ti" => "Ti:",
    "To" => "T:",
    "DP" => "DP:",
    "RHi" => "Hi:",
    "RHo" => "H:",
    "WS" => "W:",
    "DIRtext" => "Dir:",
    "WC" => "WC:",
    "R1h" => "R:",
    "RP" => "P:",
    "Tendency" => "Tendency:",
    "Forecast" => "Forecast:",
);

#####################################
sub
WS3600_Initialize($)
{
  my ($hash) = @_;

# Consumer
  $hash->{DefFn}   = "WS3600_Define";
  $hash->{AttrList}= "model:WS3600,WS2300 loglevel:0,1,2,3,4,5,6";
  $hash->{ReadFn}  = "WS3600_Read";
  $hash->{UndefFn} = "WS3600_Undef";
}

#####################################
sub
WS3600_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Define the /path/to/fetch3600 as a parameter" if(@a != 3);

  my $FH;
  my $dev = sprintf("%s |", $a[2]);
  Log 3, "WS3600 using \"$dev\" as parameter to open(); trying ...";
  open($FH, $dev);
  if(!$FH) {
      return "WS3600 Can't start $dev: $!";
  }
  local $_;
  while (<$FH>) {
#      my ($reading, $val)=split(/ /, $_);
      
      if(/^(Date) (.*)/ || /^(Time) (.*)/ || /^(Ti) (.*)/ || /^(To) (.*)/) {
	  Log 3, "WS3600 initial read: $1 $2";
      }
  }
  close($FH);
  Log 3, "WS3600 initial read done";

  $hash->{DeviceName} = $dev;
  $hash->{Timer} = 64;  # call every 64 seconds; normal wireless update interval
                        # is 128 sec, on wind >10 km/h 32 sec. 64 sec should ensure
                        # quite current data.

#  my $tn = TimeNow();
#  $hash->{READINGS}{"freq"}{TIME} = $tn;
#  $hash->{READINGS}{"freq"}{VAL} = $hash->{Timer};
#  $hash->{CHANGED}[0] = "freq: $hash->{Timer}";

  # InternalTimer blocks if init_done is not true
#  my $oid = $init_done;
#  $init_done = 1;
# WS3600_GetStatus($hash);
#  $init_done = $oid;

  Log 3, "WS3600 setting callback timer";

  my $oid = $init_done;
  $init_done = 1;
  InternalTimer(gettimeofday()+ $hash->{Timer}, "WS3600_GetStatus", $hash, 1);
  $init_done = $oid;

  Log 3, "WS3600 initialized";

  $hash->{STATE} = "initialized";
  $hash->{TMPSTATE} = "";
  return undef;
}

#####################################
sub
WS3600_Undef($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  if(defined($hash->{FD})) {
      close($hash->{FD});
      delete $hash->{FD};
  }
  delete $selectlist{"$name.pipe"};

  $hash->{STATE}='undefined';
  Log GetLogLevel($name,3), "$name shutdown complete";
  return undef;
}


#####################################
sub
WS3600_GetStatus($)
{
    my ($hash) = @_;
    my $dnr = $hash->{DEVNR};
    my $name = $hash->{NAME};
    my $dev = $hash->{DeviceName};
    my $FH;

    # Call us in n seconds again.
#    InternalTimer(gettimeofday()+ $hash->{Timer}, "WS3600_GetStatus", $hash, 1);

    Log GetLogLevel($name,4), "WS3600 contacting station";
 
    open($FH, $dev);
    if(!$FH) {
	return "WS3600 Can't start $dev: $!";
    }

    $hash->{FD}=$FH;
    $selectlist{"$name.pipe"} = $hash;
    Log GetLogLevel($name,4), "WS3600 pipe opened";
#    $hash->{STATE} = "running";
    $hash->{pipeopentime} = time();
#    InternalTimer(gettimeofday() + 6, "WS3600_Read", $hash, 1);
    return $hash->{STATE};
}

#####################################
sub
WS3600_Read($)
{
    my ($hash) = @_;
    my $dnr = $hash->{DEVNR};
    my $name = $hash->{NAME};
    my $dev = $hash->{DeviceName};
    my $FH;
    my $inputline;

    Log GetLogLevel($name,4), "WS3600 Read entered";

    if(!defined($hash->{FD})) {
	Log GetLogLevel($name,3), "Oops, WS3600 FD undef'd";
	return undef;
    }
    if(!$hash->{FD}) {
	Log GetLogLevel($name,3), "Oops, WS3600 FD empty";
	return undef;
    }
    $FH = $hash->{FD};

    Log GetLogLevel($name,4), "WS3600 reading started";

    my @lines;
    my $eof;
    my $i=0;
    my $tn = TimeNow();
    my $StateString=$hash->{TMPSTATE};
    my $HumidString="";
    my $TempsString="";
    my $OtherString="";
    my $reading;
    my $readingforstatus;

    ($eof, @lines) = nonblockGetLines($FH);

    if(!defined($eof)) {
	Log GetLogLevel($name,4), "WS3600 FIXME: eof undefined?!";
	$eof=0;
    }
    Log GetLogLevel($name,4), "WS3600 reading ended with eof==$eof";

    # FIXME! Current observed behaviour is "would block", then read of only EOF.
    #        Not sure if it's always that way; more correct would be checking
    #        for empty $inputline or undef'd $rawreading,$val. -wusel, 2010-01-04 
    if($eof != 1) {
    foreach my $inputline ( @lines ) {
	$inputline =~ s/\s+$//;
	my ($rawreading, $val)=split(/ /, $inputline);
	Log GetLogLevel($name,5), "WS3600 read $inputline:$rawreading:$val";
	if(defined($TranslatedCodes{$rawreading})) {

#	    delete $defs{$name}{READINGS}{"  $rawreading"};

	    $reading=$TranslatedCodes{$rawreading};

	    $defs{$name}{READINGS}{$reading}{VAL} = $val;
	    $defs{$name}{READINGS}{$reading}{TIME} = $tn;
#
# -wusel, 2010-01-30: BIG CHANGE: only put into CHANGED[] what will be in
#                     STATE as well; this is done to reduce the burden on
#                     the notification framework (each one currently leads
#                     to a separate notify which will in turn lead a call
#                     of EVERY NotifyFn()) and to improve FHEMs overall
#                     performance.
#                     Every value is still be stored in READINGS though.
#
#	    $hash->{CHANGED}[$i++] = "$reading: $val";

	    if(defined($WantedCodesForStatus{$rawreading})) {
		$readingforstatus=$WantedCodesForStatus{$rawreading};
		$StateString=sprintf("%s %s %s", $StateString, $readingforstatus, $val);
		$hash->{CHANGED}[$i++] = "$reading: $val";
	    }
#	    if($rawreading =~ m/^(Tendency|Forecast)/) {
#		$hash->{CHANGED}[$i++] = "$reading: $val";
#		$StateString=sprintf("%s %s: %s", $StateString, $reading, $val);
#	    }
#	    if($rawreading =~ m/^(Ti$|To$|WC$)/) {
#		$hash->{CHANGED}[$i++] = "$reading: $val";
#		$TempsString=sprintf("%s %s: %s °C", $TempsString, $reading, $val);
#	    }
#	    if($rawreading =~ m/^(RHi$|RHo$)/) {
#		$hash->{CHANGED}[$i++] = "$reading: $val";
#		$HumidString=sprintf("%s %s: %s %%", $HumidString, $reading, $val);
#	    }
#	    if($rawreading =~ m/^(R1h$|R24h$)/) {
#		$hash->{CHANGED}[$i++] = "$reading: $val";
#		$OtherString=sprintf("%s %s: %s mm", $OtherString, $reading, $val);
#	    }
#	    if($rawreading =~ m/^(RP$|AP$)/) {
#		$hash->{CHANGED}[$i++] = "$reading: $val";
#		$OtherString=sprintf("%s %s: %s hPa", $OtherString, $reading, $val);
#	    }
	}
    }
    $hash->{TMPSTATE} = $StateString;
    }

    if($eof) {
	close($FH);
	delete $hash->{FD};
	delete $selectlist{"$name.pipe"};
	InternalTimer(gettimeofday()+ $hash->{Timer}, "WS3600_GetStatus", $hash, 1);
	Log GetLogLevel($name,4), "WS3600 done reading pipe";
    } else {
	Log GetLogLevel($name,4), "WS3600 (further) reading would block";
    }

#    $OtherString =~ s/^\s+//;
#    $HumidString =~ s/^\s+//;
#    $TempsString =~ s/^\s+//;
#    $StateString =~ s/^\s+//;
#
#    $defs{$name}{READINGS}{"Humidity"}{VAL} = $HumidString;
#    $defs{$name}{READINGS}{"Humidity"}{TIME} = $tn;
#    $hash->{CHANGED}[$i++] = $HumidString;
#    $defs{$name}{READINGS}{"Temperatures"}{VAL} = $TempsString;
#    $defs{$name}{READINGS}{"Temperatures"}{TIME} = $tn;
#    $hash->{CHANGED}[$i++] = $TempsString;
#    $defs{$name}{READINGS}{"Rain/Pressure"}{VAL} = $OtherString;
#    $defs{$name}{READINGS}{"Rain/Pressure"}{TIME} = $tn;
#    $hash->{CHANGED}[$i++] = $OtherString;
#    $defs{$name}{READINGS}{"Forecast"}{VAL} = $StateString;
#    $defs{$name}{READINGS}{"Forecast"}{TIME} = $tn;
#    $hash->{CHANGED}[$i++] = $StateString;

# -wusel, 2010-01-06: FIXME: does this logic with STATE work?
# -wusel, 2010-01-30: Removed setting STATE to "reading".

    if($eof) {
#	$hash->{CHANGED}[$i++] = "Status: $StateString";
	$hash->{STATE} = $hash->{TMPSTATE};
	$hash->{TMPSTATE} = "";
	DoTrigger($name, undef);
#    } else {
#	$hash->{STATE} = "reading";
    }

    return $hash->{STATE};
}


# From http://www.perlmonks.org/?node_id=713384 / http://davesource.com/Solutions/20080924.Perl-Non-blocking-Read-On-Pipes-Or-Files.html
#
# Used, hopefully, with permission ;)
#
# An non-blocking filehandle read that returns an array of lines read
# Returns:  ($eof,@lines)
my %nonblockGetLines_last;
sub nonblockGetLines {
  my ($fh,$timeout) = @_;

  $timeout = 0 unless defined $timeout;
  my $rfd = '';
  $nonblockGetLines_last{$fh} = ''
        unless defined $nonblockGetLines_last{$fh};

  vec($rfd,fileno($fh),1) = 1;
  return unless select($rfd, undef, undef, $timeout)>=0;
    # I'm not sure the following is necessary?
  return unless vec($rfd,fileno($fh),1);
  my $buf = '';
  my $n = sysread($fh,$buf,1024*1024);
  # If we're done, make sure to send the last unfinished line
  return (1,$nonblockGetLines_last{$fh}) unless $n;
    # Prepend the last unfinished line
  $buf = $nonblockGetLines_last{$fh}.$buf;
    # And save any newly unfinished lines
  $nonblockGetLines_last{$fh} =
        (substr($buf,-1) !~ /[\r\n]/ && $buf =~ s/([^\r\n]*)$//)
            ? $1 : '';
  $buf ? (0,split(/\n/,$buf)) : (0);
}

1;

=pod
=begin html

<a name="WS3600"></a>
<h3>WS3600</h3>
<ul>
  <br>

  <a name="WS3600define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WS3600 &lt;/path/to/fetch3600&gt;</code>
    <br><br>

    Define a WS3600 series weather station (Europe Supplies, technotrade, etc; refer to
    <a href="http://www.wetterstationsforum.de/ws3600_master-touch.php">Wetterstationen.info</a>
    (german) for details on this model); the station is queried by means of an external program,
    fetch3600. It talks to the attached weather station (several WS do supply an RS323 interface
    but seem to use some kind of "morse code" on the RTS, CTS wires instead of using propper
    serial communication (RX, TX); it's no use to recode that crap into FHEM when there is a
    stable package of tools to talk to the station available: <a href=http://open3600.fast-mail.nl/tiki-index.php>open3600</a>)
    and delivers the current readings line by line as reading-value-pairs. These are read in
    and translated into more readable names for FHEM by the module WS3600.pm.<br><br>
    As the WS3600 is rather similar to the <a href=http://www.wetterstationsforum.de/ws2300_matrix.php>WS2300</a>
    and open3600 basically is a modified offspring of <a href=http://www.lavrsen.dk/twiki/bin/view/Open2300/WebHome>open2300</a>, by exchanging the /path/to/fetch3600 with /path/to/fetch2300 this module
    should be able to handle the WS2300 was well.<br><br>
    Currently, it is expected that the WS is attached to the local computer and fetch3600 is run
    locally. Basically the executable called needs to supply on stdout an output similar to what
    fetch3600 returns; how to implement a "networked setup" is left as an excercise to the reader.
    <br>
    For the records, this is an output of fetch3600:<pre>
Date 14-Nov-2009
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

    There is no expectation on the readings received from the fetch3600 binary; so, in
    essence, if you have a similar setup (unsupported, attached weather station and a
    means to get it's reading into an output similar to above's), you <em>should be able</em>
    to use WS3600.pm with a custom written script to interface FHEM with your station
    as well. WS3600.pm <em>only recognizes the above readings</em> (and translates these
    into, e. g., <code>Temp-inside</code> for <code>Ti</code> for use within FHEM), other
    lines are silently dropped on the floor.<br><br>

    fetch3600 is available as binary for the Windows OS as well, <em>but I haven't tested operation
    under that OS, use it at your own risk and you mileage may vary ...</em>
    <br>Note: Currently this device does not support a "set" function nor anything to "get". The
    later would be possible to implement if neccessary, though.
    <br><br>

    Implementation of WS3600.pm tries to be nice, that is it reads from the pipe only
    non-blocking (== if there is data), so it should be safe even to use it via ssh or
    a netcat-pipe over the Internet, but this, as well, has not been tested yet.
    <br><br>

    Attributes:
    <ul>
      <li><code>model</code>: <code>WS3600</code> or <code>WS2300</code> (not used for anything, yet)</li>
    </ul>
    <br>
    Example:
    <ul>
      <code>define my3600 W36000 /usr/local/bin/fetch360</code><br>
    </ul>
    <br>
  </ul>

  <a name="WS3600set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="WS3600get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="WS3600attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#model">model</a> (WS3600, WS2300)</li>
  </ul>
  <br>
</ul>

=end html
=cut
