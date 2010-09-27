#!/usr/bin/perl -w

#
# RSSImonitor.pl
# (c) 2010 Dr. Boris Neubert
# omega at online dot de
#
#
# This perl script evaluates the RSSI information from
# your devices in order to help you finding the best
# location to place your CUL or CUN device.
#
# Instructions:
#
# 1. Make your CUN or CUL create additional events:
#	attr CUN addvaltrigger
#
# 2. Log the RSSI events to a single file:
#	define RSSI.log FileLog /path/to/RSSI.log .*:RSSI.*
#
# 3. Wait some time until all devices have sent something.
#
# 4. Run the log file through RSSImonitor:
#	RSSImonitor.pl < /path/to/RSSI.log
#
# 5. The output lists any device from the log together with
#	the minimum, maximum and average RSSI as well as its
#	standard deviation.
#
#
# type perldoc perldsc to learn about hashes of arrays
#


use strict;

my %RSSI;

sub storeRSSI {
  my ($device, $value)= @_;
  if(!($RSSI{$device})) {
    $RSSI{$device}= [];
    #print "new device $device\n";
  }
  push @{ $RSSI{$device} }, $value;
  #print "device: $device, value: $value\n";
}

sub readRSSI {
  while( <> ) {
    my ($timestamp, $device, $keyword, $value)= split;
    if($keyword eq "RSSI:") {
      storeRSSI($device, $value);
    }
  }
}

sub calcStats {
  my ($device)= @_;
  my $min= 100.;
  my $max= -100.;
  my $m1= 0.;
  my $m2= 0.;
  my $n= $#{ $RSSI{$device} }+1;
  my ($i, $value);
  my ($avg, $sigma);
  foreach $i ( 0 .. $#{ $RSSI{$device} } ) {
    $value= $RSSI{$device}[$i];
    if($value< $min) { $min= $value; }
    if($value> $max) { $max= $value; }
    $m1+= $value;
    $m2+= $value*$value;
  }
  $avg= $m1/$n;
  $sigma= sqrt($m2/$n-$avg*$avg);
  return ($min, $max, $avg, $sigma);
}

#
# main
#

readRSSI;

my $device;
printf("%12s\t%s\t%s\t%s\t%s\n", "Device", "Min", "Max", "Avg", "StdDev");
foreach $device (keys %RSSI) {
  my ($min, $max, $avg, $sigma)= calcStats($device);
  printf("%12s\t%.1f\t%.1f\t%.1f\t%.1f\n", $device, $min, $max, $avg, $sigma);
}