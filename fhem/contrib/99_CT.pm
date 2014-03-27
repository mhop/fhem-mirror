# $Id$
package main;

use strict;
use warnings;

# define items and where/how they can be found
my %handles = (

   # for each item define something like this:
   # ITEM     => [
   #   'path containing the data we need',
   #   'regular expression matching the (bits) we need',
   #   sub { to process the bits found by the regex },
   # ],

   # Clock frequency of CPU in Hz, e.g. 800000
   CPU0FREQ  => [
      '/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq',
      '(\d+)',
      sub { shift },
   ],

   # Clock frequency of CPU in Hz, e.g. 800000
   CPU1FREQ  => [
      '/sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq',
      '(\d+)',
      sub { shift },
   ],

   # MAC address of wired ethernet connection
   LMAC      => [
      '/sys/class/net/eth0/address',
      '(.*)',
      sub { shift },
   ],
   
   # MAC address of wireless ethernet connection
   WMAC      => [
      '/sys/class/net/wlan0/address',
      '(.*)',
      sub { shift },
   ],
   
   # Serial number
   SERIAL   => [
      '/proc/cpuinfo',
      'Serial\s+:\s+(\S+)\s*$',
      sub { shift },
   ],
   
   # Revision id
   REV      => [
      '/proc/cpuinfo',
      'Revision\s+:\s+(\S+)\s*$',
      sub { shift },
   ],
   
);

sub CT {
   my $item = uc(shift); # not case sensitive
   my $value = undef;    # result is undef unless success
   
   # if we know how to find the requested item
   if ( exists $handles{$item} ) {
   
      # open file
      if ( open my $fh, $handles{$item}[0] ) {
         my $regex = $handles{$item}[1];
         while ( <$fh> ) {
         
            # regex matches: process and set resulting value
            /$regex/ and $value = &{$handles{$item}[2]}($1) and last;
         }
         close $fh;
      }
      
      # complain: failed to open file
      else {
         warn "Could not read $item: $!\n";
      }
   }
   
   # complain: don't know requested item
   else {
      warn "Don't know how to find $item\n";
   }

   return $value;
};

sub CT_Initialize($) {
	my ($hash) = @_;
}

1;