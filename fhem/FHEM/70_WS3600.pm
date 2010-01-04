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
# $Id: 70_WS3600.pm,v 1.2 2010-01-04 23:07:35 painseeker Exp $
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
  Log 3, "$name shutdown complete";
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

    Log 4, "WS3600 contacting station";
 
    open($FH, $dev);
    if(!$FH) {
	return "WS3600 Can't start $dev: $!";
    }

    $hash->{FD}=$FH;
    $selectlist{"$name.pipe"} = $hash;
    Log 4, "WS3600 pipe opened";
    $hash->{STATE} = "running";
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

    Log 4, "WS3600 Read entered";

    if(!defined($hash->{FD})) {
	Log 3, "Oops, WS3600 FD undef'd";
	return undef;
    }
    if(!$hash->{FD}) {
	Log 3, "Oops, WS3600 FD empty";
	return undef;
    }
    $FH = $hash->{FD};

    Log 4, "WS3600 reading started";

    my @lines;
    my $eof;
    my $i=0;
    my $tn = TimeNow();
    my $StateString="";
    my $HumidString="";
    my $TempsString="";
    my $OtherString="";
    my $reading;

    ($eof, @lines) = nonblockGetLines($FH);

    if(!defined($eof)) {
	Log 4, "WS3600 FIXME: eof undefined?!";
	$eof=0;
    }
    Log 4, "WS3600 reading ended with eof==$eof";

    # FIXME! Current observed behaviour is "would block", then read of only EOF.
    #        Not sure if it's always that way; more correct would be checking
    #        for empty $inputline or undef'd $rawreading,$val. -wusel, 2010-01-04 
    if($eof != 1) {
    foreach my $inputline ( @lines ) {
	$inputline =~ s/\s+$//;
	my ($rawreading, $val)=split(/ /, $inputline);
	Log 5, "WS3600 read $inputline:$rawreading:$val";
	if(defined($TranslatedCodes{$rawreading})) {

#	    delete $defs{$name}{READINGS}{"  $rawreading"};

	    $reading=$TranslatedCodes{$rawreading};

	    $defs{$name}{READINGS}{$reading}{VAL} = $val;
	    $defs{$name}{READINGS}{$reading}{TIME} = $tn;
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
    }

    if($eof) {
	close($FH);
	delete $hash->{FD};
	delete $selectlist{"$name.pipe"};
	InternalTimer(gettimeofday()+ $hash->{Timer}, "WS3600_GetStatus", $hash, 1);
	Log 4, "WS3600 done reading pipe";
    } else {
	Log 4, "WS3600 (further) reading would block";
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

    if($eof) {
	$hash->{CHANGED}[$i++] = "Status: updated";
	DoTrigger($name, undef);
	$hash->{STATE} = "updated";
    } else {
	$hash->{STATE} = "reading";
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

#####################################
sub
WS3600_OldGetStatus($)
{
    my ($hash) = @_;
    my $dnr = $hash->{DEVNR};
    my $name = $hash->{NAME};
    my $dev = $hash->{DeviceName};

    # Call us in n seconds again.
    InternalTimer(gettimeofday()+ $hash->{Timer}, "WS3600_GetStatus", $hash, 1);

    my %vals;
    #my $result = WS3600_GetLine($hash->{DeviceName}, $hash->{Cmd});

    my $FH;
    Log 3, "WS3600 contacting station";
 
    open($FH, $dev);
    if(!$FH) {
	return "WS3600 Can't start $dev: $!";
    }
    local $_;
    my $i=0;
    my $tn = TimeNow();
    my $StateString="";
    my $HumidString="";
    my $TempsString="";
    my $OtherString="";
    while (<$FH>) {
	$_ =~ s/\s+$//;
	my ($reading, $val)=split(/ /, $_);
	$defs{$name}{READINGS}{$reading}{VAL} = $val;
	$defs{$name}{READINGS}{$reading}{TIME} = $tn;
	if($reading =~ m/^(Tendency|Forecast)/) {
	    $hash->{CHANGED}[$i++] = "$reading: $val";
	    $StateString=sprintf("%s %s: %s", $StateString, $reading, $val);
	}
	if($reading =~ m/^(Ti$|To$|WC$)/) {
	    $hash->{CHANGED}[$i++] = "$reading: $val";
	    $TempsString=sprintf("%s %s: %s °C", $TempsString, $reading, $val);
	}
 	if($reading =~ m/^(RHi$|RHo$)/) {
	    $hash->{CHANGED}[$i++] = "$reading: $val";
	    $HumidString=sprintf("%s %s: %s %%", $HumidString, $reading, $val);
	}
	if($reading =~ m/^(R1h$|R24h$)/) {
	    $hash->{CHANGED}[$i++] = "$reading: $val";
	    $OtherString=sprintf("%s %s: %s mm", $OtherString, $reading, $val);
	}
	if($reading =~ m/^(RP$|AP$)/) {
	    $hash->{CHANGED}[$i++] = "$reading: $val";
	    $OtherString=sprintf("%s %s: %s hPa", $OtherString, $reading, $val);
	}
    }
    close($FH);
    Log 3, "WS3600 fetched station's data";
    
    $OtherString =~ s/^\s+//;
    $HumidString =~ s/^\s+//;
    $TempsString =~ s/^\s+//;
    $StateString =~ s/^\s+//;

    $defs{$name}{READINGS}{"Humidity"}{VAL} = $HumidString;
    $defs{$name}{READINGS}{"Humidity"}{TIME} = $tn;
    $defs{$name}{READINGS}{"Temperatures"}{VAL} = $TempsString;
    $defs{$name}{READINGS}{"Temperatures"}{TIME} = $tn;
    $defs{$name}{READINGS}{"Rain/Pressure"}{VAL} = $OtherString;
    $defs{$name}{READINGS}{"Rain/Pressure"}{TIME} = $tn;
    $defs{$name}{READINGS}{"Forecast"}{VAL} = $StateString;
    $defs{$name}{READINGS}{"Forecast"}{TIME} = $tn;

    DoTrigger($name, undef) if($init_done);

    $hash->{STATE} = $StateString;
    return $hash->{STATE};
}

1;
