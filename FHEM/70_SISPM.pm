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

###########################
# 70_SISPM.pm
# Module for FHEM
#
# Contributed by Kai 'wusel' Siering <wusel+fhem@uu.org> in 2010
# Based in part on work for FHEM by other authors ...
# $Id: 70_SISPM.pm,v 1.4 2010-01-20 01:04:01 painseeker Exp $
###########################

package main;

use strict;
use warnings;


#####################################
sub
SISPM_Initialize($)
{
  my ($hash) = @_;

# Consumer
  $hash->{DefFn}   = "SISPM_Define";
  $hash->{Clients} =
        ":SIS_PMS:";
  my %mc = (
    "1:SIS_PMS"   => "^socket ..:..:..:..:.. . state o.*",
  );
  $hash->{MatchList} = \%mc;
  $hash->{AttrList}= "model:SISPM loglevel:0,1,2,3,4,5,6";
  $hash->{ReadFn}  = "SISPM_Read";
  $hash->{WriteFn} = "SISPM_Write";
  $hash->{UndefFn} = "SISPM_Undef";
}

#####################################
sub FixSISPMSerial($) {
    my $serial=$_[0];

    if(length($serial)!=length("..:..:..:..:..")){
	my ($sn1, $sn2, $sn3, $sn4, $sn5) = split(":", $serial);
	$serial=sprintf("%2s:%2s:%2s:%2s:%2s", substr($sn1, -2, 2), substr($sn2, -2, 2), substr($sn3, -2, 2), substr($sn4, -2, 2), substr($sn5, -2, 2));
	$serial =~ s/ /0/g;
    }

    return $serial;
}

#####################################
sub
SISPM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $numdetected=0;
  my $currentdevice=0;

  return "Define the /path/to/sispmctl as a parameter" if(@a != 3);

  my $FH;
  my $dev = sprintf("%s", $a[2]);
  Log 3, "SISPM using \"$dev\" as parameter to open(); trying ...";
  my $tmpdev=sprintf("%s -s 2>&1 |", $dev);
  open($FH, $tmpdev);
  if(!$FH) {
      return "SISPM Can't start $dev: $!";
  }
  $hash->{NUMUNITS}=0;
  local $_;
  while (<$FH>) {
      if(/^(No GEMBIRD SiS-PM found.)/) {
	  Log 3, "SISPM woops? $1";
      }
   
      if(/^Gembird #(\d+) is USB device (\d+)./) {
	  Log 3, "SISPM found SISPM device number $1 as USB $2";
	  $hash->{UNITS}{$1}{USB}=$2;
	  $currentdevice=$1;
	  $numdetected++;
 	  $hash->{NUMUNITS}=$numdetected;
      }

      if(/^This device has a serial number of (.*)/) {
	  my $serial=$1;
	  Log 3, "SISPM device number " . $currentdevice . " has serial $serial";
	  if(length($serial)!=length("..:..:..:..:..")){
	      $serial = FixSISPMSerial($serial);
	      Log 3, "SISPM: Whoopsi, weird serial format; fixing to $serial.";
	  }
	  $hash->{UNITS}{$currentdevice}{SERIAL}=$serial;
 	  $hash->{SERIALS}{$serial}{UNIT}=$currentdevice;
  	  $hash->{SERIALS}{$serial}{USB}=$hash->{UNITS}{$currentdevice}{USB};
    }
  }
  close($FH);
  Log 3, "SISPM initial read done";

  if ($numdetected==0) {
      return "SISPM no SIMPM devices found.";
  }

  $hash->{NumPMs} = $numdetected;
  $hash->{DeviceName} = $dev;
  $hash->{Timer} = 30;  # just a keepalive for now

  Log 3, "SISPM setting callback timer";

  my $oid = $init_done;
  $init_done = 1;
  InternalTimer(gettimeofday()+ $hash->{Timer}, "SISPM_GetStatus", $hash, 1);
  $init_done = $oid;

  Log 3, "SISPM initialized";

  $hash->{STATE} = "initialized";
  return undef;
}

#####################################
sub
SISPM_Undef($$)
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
SISPM_GetStatus($)
{
    my ($hash) = @_;
    my $dnr = $hash->{DEVNR};
    my $name = $hash->{NAME};
    my $dev = $hash->{DeviceName};
    my $FH;
    my $i;

    # Call us in n seconds again.
#    InternalTimer(gettimeofday()+ $hash->{Timer}, "SISPM_GetStatus", $hash, 1);

    Log 4, "SISPM contacting device";

    my $tmpdev=sprintf("%s -s ", $dev);

    for($i=0; $i<$hash->{NUMUNITS}; $i++) {
	$tmpdev=sprintf("%s -d %d -g all ", $tmpdev, $i);
    }
    $tmpdev=sprintf("%s 2>&1 |", $tmpdev);
    open($FH, $tmpdev);
    if(!$FH) {
	return "SISPM Can't open pipe: $dev: $!";
    }

    $hash->{FD}=$FH;
    $selectlist{"$name.pipe"} = $hash;
    Log 4, "SISPM pipe opened";
    $hash->{STATE} = "running";
    $hash->{pipeopentime} = time();
#    InternalTimer(gettimeofday() + 6, "SISPM_Read", $hash, 1);
#    return $hash->{STATE};
}

#####################################
sub
SISPM_Read($)
{
    my ($hash) = @_;
    my $dnr = $hash->{DEVNR};
    my $name = $hash->{NAME};
    my $dev = $hash->{DeviceName};
    my $FH;
    my $inputline;

    Log 4, "SISPM Read entered";

    if(!defined($hash->{FD})) {
	Log 3, "Oops, SISPM FD undef'd";
	return undef;
    }
    if(!$hash->{FD}) {
	Log 3, "Oops, SISPM FD empty";
	return undef;
    }
    $FH = $hash->{FD};

    Log 4, "SISPM reading started";

    my @lines;
    my $eof;
    my $i=0;
    my $tn = TimeNow();
    my $reading;
    my $readingforstatus;
    my $currentserial="none";
    my $currentdevice=0;
    my $currentusbid=0;
    my $renumbered=0;
    my $newPMfound=0;

    ($eof, @lines) = nonblockGetLinesSISPM($FH);

    if(!defined($eof)) {
	Log 4, "SISPM FIXME: eof undefined?!";
	$eof=0;
    }
    Log 4, "SISPM reading ended with eof==$eof";

    # FIXME! Current observed behaviour is "would block", then read of only EOF.
    #        Not sure if it's always that way; more correct would be checking
    #        for empty $inputline or undef'd $rawreading,$val. -wusel, 2010-01-04 
    if($eof != 1) {
    foreach my $inputline ( @lines ) {
	$inputline =~ s/\s+$//;

	# wusel, 2010-01-16: Seems as if reading not always works as expected;
	#                    throw away the whole readings if there's a NULL
	#                    serial number.
	if($currentserial eq "00:00:00:00:00") {
	    next;
	}

# wusel, 2010-01-19: Multiple (2) SIS PM do work now. But USB renumbering will still
#                    break things rather badly. Thinking about dropping it altogether,
#                    that is wipe old state data ($hash->{UNITS} et. al.) and rebuild
#                    data each time from scratch. That should work as SIS_PMS uses the
#                    serial as key; unfortunately, sispmctl doesn't offer this (and it
#                    wont work due to those FFFFFFxx readings), so we need to keep
#                    track of unit number <-> serial ... But if between reading this
#                    data and a "set" statement something changes, we still could switch
#                    the wrong socket.
#
#                    As sispmctl 2.7 is broken already for multiple invocations with -d,
#                    I consider fixing both the serial number issue as well as add the
#                    serial as selector ... Drat. Instead of getting the ToDo list shorter,
#                    it just got longer ;-)

	if($inputline =~ /^(No GEMBIRD SiS-PM found.)/) {
	    Log 3, "SISPM Whoopsie? $1";
	    next;
	}

	if($inputline =~ /^Gembird #(\d+) is USB device (\d+)\./ || 
	   $inputline =~ /^Accessing Gembird #(\d+) USB device (\d+)/) {
	    Log 5, "SISPM found SISPM device number $1 as USB $2";
	    if($1 < $hash->{NUMUNITS}) {
		if($hash->{UNITS}{$1}{USB}!=$2) {
		    Log 3, "SISPM: USB ids changed (unit $1 is now USB $2 but was " .  $hash->{UNITS}{$1}{USB} . "); will fix.";
		    $renumbered=1;
		}   
	    } else { # Something wonderful has happened, we have a new SIS PM!
		Log 3, "SISPM: Wuuuhn! Found a new unit $1 as USB $2. Will assimilate it.";
		$newPMfound=1;
	    }
	    $currentdevice=$1;
	    $currentusbid=$2;
	    $currentserial="none";
	    if(defined($hash->{UNITS}{$currentdevice}{SERIAL})) {
		$currentserial=$hash->{UNITS}{$currentdevice}{SERIAL};
	    }
	}

	if($inputline =~ /^This device has a serial number of (.*)/) {
	    $currentserial=FixSISPMSerial($1);
	    if($currentserial eq "00:00:00:00:00") {
		Log 3, "SISPM Whooopsie! Your serial nullified ($currentserial). Skipping ...";
		next;
	    }

	    if($newPMfound==1) {
		$hash->{UNITS}{$currentdevice}{USB}=$currentusbid;
		$hash->{UNITS}{$currentdevice}{SERIAL}=$currentserial;
		$hash->{SERIALS}{$currentserial}{UNIT}=$currentdevice;
		$hash->{SERIALS}{$currentserial}{USB}=$currentusbid;
		$hash->{NUMUNITS}+=1;
	    }
	}

	if($inputline =~ /^Status of outlet (\d):\s+(.*)/) {
	    if($currentserial ne "none") {
		Log 5, "SISPM found socket $1 on $currentserial, state $2";
		my $dmsg="socket " . $currentserial . " $1 state " . $2;
		my %addvals;
		Dispatch($hash, $dmsg, \%addvals);
	    } else {
		Log 3, "SISPM Whooopsie! Found socket $1, state $2, but no serial (serial is $currentserial)?";
	    }
	}
    }
    }

    if($eof) {
	close($FH);
	delete $hash->{FD};
	delete $selectlist{"$name.pipe"};
	InternalTimer(gettimeofday()+ $hash->{Timer}, "SISPM_GetStatus", $hash, 1);
	$hash->{STATE} = "read";
	Log 4, "SISPM done reading pipe";
    } else {
	$hash->{STATE} = "reading";
	Log 4, "SISPM (further) reading would block";
    }
}


#####################################
sub SISPM_Write($$$) {
    my ($hash,$fn,$msg) = @_;
    my $dev = $hash->{DeviceName};

#    Log 3, "SISPM_Write entered for $hash->{NAME} with $fn and $msg";

    my ($serial, $socket, $what) = split(' ', $msg);

    my $deviceno;
    my $cmdline;
    my $cmdletter="t";

    if($what eq "on") {
	$cmdletter="o";
    } elsif($what eq "off") {
	$cmdletter="f";
    }

    if(defined($hash->{SERIALS}{$serial}{UNIT})) {
	$deviceno=($hash->{SERIALS}{$serial}{UNIT});
	$cmdline=sprintf("%s -d %d -%s %d 2>&1 >/dev/null", $dev, $deviceno, $cmdletter, $socket);
	system($cmdline);
    } else {
	Log 2, "SISPM_Write can not find SISPM device with serial $serial";
    }
    return;
}


# From http://www.perlmonks.org/?node_id=713384 / http://davesource.com/Solutions/20080924.Perl-Non-blocking-Read-On-Pipes-Or-Files.html
#
# Used, hopefully, with permission ;)
#
# An non-blocking filehandle read that returns an array of lines read
# Returns:  ($eof,@lines)
my %nonblockGetLines_lastSISPM;
sub nonblockGetLinesSISPM {
  my ($fh,$timeout) = @_;

  $timeout = 0 unless defined $timeout;
  my $rfd = '';
  $nonblockGetLines_lastSISPM{$fh} = ''
        unless defined $nonblockGetLines_lastSISPM{$fh};

  vec($rfd,fileno($fh),1) = 1;
  return unless select($rfd, undef, undef, $timeout)>=0;
    # I'm not sure the following is necessary?
  return unless vec($rfd,fileno($fh),1);
  my $buf = '';
  my $n = sysread($fh,$buf,1024*1024);
  # If we're done, make sure to send the last unfinished line
  return (1,$nonblockGetLines_lastSISPM{$fh}) unless $n;
    # Prepend the last unfinished line
  $buf = $nonblockGetLines_lastSISPM{$fh}.$buf;
    # And save any newly unfinished lines
  $nonblockGetLines_lastSISPM{$fh} =
        (substr($buf,-1) !~ /[\r\n]/ && $buf =~ s/([^\r\n]*)$//)
            ? $1 : '';
  $buf ? (0,split(/\n/,$buf)) : (0);
}


1;
