########################################################################################
#
# OWX_DS2480.pm
#
# FHEM module providing hardware dependent functions for the DS9097 interface of OWX
#
# Prof. Dr. Peter A. Henning
# Norbert Truchsess
#
# $Id$
#
########################################################################################
#
# Provides the following methods for OWX
#
# Alarms
# Complex
# Define
# Discover
# Init
# Reset
# Verify
#
########################################################################################

package OWX_DS9097;

use strict;
use warnings;
use Time::HiRes qw( gettimeofday );

use vars qw/@ISA/;
@ISA='OWX_SER';

use ProtoThreads;
no warnings 'deprecated';

sub new($) {
  my ($class,$serial) = @_;
  return bless $serial,$class;
}

########################################################################################
# 
# Complex - Send match ROM, data block and receive bytes as response
#
# Parameter hash    = hash of bus master, 
#           owx_dev = ROM ID of device
#           data    = string to send
#           numread = number of bytes to receive
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub get_pt_execute($$$$) {
  my ($self, $reset, $dev, $writedata, $numread) = @_;
  my $pt_query;
  return PT_THREAD(sub {
    my ($thread) = @_;
    my $select;
    PT_BEGIN($thread);
    $self->reset() if ($reset);
    if (defined $writedata or $numread) {
      #-- has match ROM part
      if( $dev ) {
        #-- 8 byte 1-Wire device address
        my @rom_id; 
        #-- from search string to byte id
        $dev=~s/\.//g;
        for(my $i=0;$i<8;$i++){
           $rom_id[$i]=hex(substr($dev,2*$i,2));
        }
        $select=sprintf("\x55%c%c%c%c%c%c%c%c",@rom_id); 
      #-- has no match ROM part, issue skip ROM command (0xCC:)
      } else {
        $select="\xCC";
      }
      if (defined $writedata) {
        $select.=$writedata;
      }
      #-- for debugging
      if( $main::owx_async_debug > 1){
        main::Log3($self->{name},5,"OWX_DS9097::pt_execute: Sending out ".unpack ("H*",$select));
      }
      $self->block($select);
    }
    #-- has receive data part
    if( $numread ) {
      $select = "";
      #$numread += length($data);
      for( my $i=0;$i<$numread;$i++){
        $select .= "11111111";
      };
      $pt_query = $self->pt_query($select);
      PT_WAIT_THREAD($pt_query);
      die $pt_query->PT_CAUSE() if ($pt_query->PT_STATE() == PT_ERROR || $pt_query->PT_STATE() == PT_CANCELED);
      my $res = pack "b*",$pt_query->PT_RETVAL();
      main::Log3($self->{name},5,"OWX_DS9097::pt_execute: Receiving ".unpack ("H*",$res)) if( $main::owx_async_debug > 1);
      PT_EXIT($res);
    } else {
      PT_EXIT("");
    }
    PT_END;
  });
}

sub reset() {
  my ( $serial ) = @_;

  if (defined (my $hwdevice = $serial->{hash}->{USBDev})) {

    $hwdevice->baudrate(9600);
    $hwdevice->write_settings;
    main::Log3($serial->{name},5, "OWX_DS9097 9600 baud") if ( $main::owx_async_debug > 2 );
    $hwdevice->write("\xF0");
    main::Log3($serial->{name},5, "OWX_DS9097 reset") if ( $main::owx_async_debug > 1 );
    while ($serial->poll()) {};
    $hwdevice->baudrate(115200);
    $hwdevice->write_settings;
    main::Log3($serial->{name},5, "OWX_DS9097 115200 baud") if ( $main::owx_async_debug > 2 );
  }
}

sub block($) {
  my ( $serial, $block ) = @_;
  main::Log3($serial->{name},5, "OWX_DS9097 block: ".unpack "H*",$block) if ( $main::owx_async_debug > 1 );
  foreach my $bit (split //,unpack "b*",$block) {
    $serial->bit($bit);
  }
}

sub bit($) {
  my ( $serial, $bit ) = @_;
  if (defined (my $hwdevice = $serial->{hash}->{USBDev})) {
    my $sp1 = $bit == 1 ? "\xFF" : "\x00";
    main::Log3($serial->{name},5, sprintf("OWX_DS9097 bit: %02x",ord($sp1))) if ( $main::owx_async_debug > 2 );
    $hwdevice->write($sp1);
  } else {
    die "no USBDev";
  }
}

sub pt_query($) {
  my ( $serial, $query ) = @_;
  my @bitsout = split //,$query;
  my $numbits = @bitsout;
  my $bitsin = "";
  my $bit;
  return PT_THREAD(sub {
    my ( $thread ) = @_;
    PT_BEGIN($thread);
    main::Log3($serial->{name},5, "OWX_DS9097 pt_query out: ".$query) if( $main::owx_async_debug );
    while ($serial->poll()) {};
    $serial->{string_raw} = "";
    while (defined ($bit = shift @bitsout)) {
      $serial->bit($bit);
    };
    main::OWX_ASYNC_TaskTimeout($serial->{hash},gettimeofday+1);
    PT_WAIT_UNTIL(length($serial->{string_raw}) >= $numbits);
    $bitsin = join "", map { ($_ == 0xFF) ? "1" : "0" } unpack "C*",$serial->{string_raw};
    main::Log3($serial->{name},5,"OWX_DS9097 pt_query in: ".$bitsin) if ( $main::owx_async_debug );
    PT_EXIT($bitsin);
    PT_END;
  });
}

sub read() {
  my ($serial) = @_;
  if (defined (my $hwdevice = $serial->{hash}->{USBDev})) {
    my $string_part = $hwdevice->input();
    if (defined $string_part and length($string_part) > 0) {
      $serial->{string_raw} .= $string_part;
      main::Log3($serial->{name},5, "OWX_DS9097 read: Loop no. $serial->{num_reads}, Receiving: ".unpack("H*",$string_part)) if( $main::owx_async_debug > 1 );
      return 1;
    } elsif ($main::owx_async_debug > 2) {
      main::Log3($serial->{name},5, "OWX_DS9097 read: Loop no. $serial->{num_reads}, no data read:");
      foreach my $i (0..6) {
        my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash) = caller($i);
        main::Log3($serial->{name},5, "$subroutine $filename $line");
      }
    }
  }
  return undef;
}

sub pt_next ($$) {

  my ($serial,$context,$mode)=@_;

  my $id_bit_number = 1;
  my $rom_byte_number = 0;
  my $rom_byte_mask = 1;
  my $last_zero = 0;
  my ($pt_query,$search_direction);

  return PT_THREAD(sub {
    my ( $thread ) = @_;
    PT_BEGIN($thread);
    $serial->reset();
    #-- issue the normal search command \xF0 or the alarm search command \xEC 
    if( $mode ne "alarm" ){
      $serial->block("\xF0");
    } else {
      $serial->block("\xEC");
    }

    #-- Response search data parsing operates bitwise

    while ( $id_bit_number <= 64) {
      #loop until through all ROM bytes 0-7
      $pt_query = $serial->pt_query("11");
      PT_WAIT_THREAD($pt_query);
      die $pt_query->PT_CAUSE() if ($pt_query->PT_STATE() == PT_ERROR || $pt_query->PT_STATE() == PT_CANCELED);
      my $ret = $pt_query->PT_RETVAL();

      my ($id_bit,$cmp_id_bit) = split //,$ret;
       
      if( ($id_bit == 1) && ($cmp_id_bit == 1) ){
        main::Log3 ($serial->{name},5, "no devices present at id_bit_number=$id_bit_number");
        last;
      }
      if ( $id_bit != $cmp_id_bit ){
        $search_direction = $id_bit;
      } else {
        # hä ? if this discrepancy if before the Last Discrepancy
        # on a previous next then pick the same as last time
        if ( $id_bit_number < $context->{LastDiscrepancy} ){
          if (($context->{ROM_ID}->[$rom_byte_number] & $rom_byte_mask) > 0){
            $search_direction = 1;
          } else {
            $search_direction = 0;
          }
        } else {
          # if equal to last pick 1, if not then pick 0
          if ($id_bit_number == $context->{LastDiscrepancy}){
            $search_direction = 1;
          } else {
            $search_direction = 0;
          }   
        }
        # if 0 was picked then record its position in LastZero
        if ($search_direction == 0){
          $last_zero = $id_bit_number;
          # check for Last discrepancy in family
          if ($last_zero < 9) {
            $context->{LastFamilyDiscrepancy} = $last_zero;
          }
        }
      }
      # set or clear the bit in the ROM byte rom_byte_number
      # with mask rom_byte_mask
      if ( $search_direction == 1){
        $context->{ROM_ID}->[$rom_byte_number] |= $rom_byte_mask;
      } else {
        $context->{ROM_ID}->[$rom_byte_number] &= ~$rom_byte_mask;
      }
      # serial number search direction write bit
      $serial->bit($search_direction);
      main::Log3 ($serial->{name},5,"id_bit_number: $id_bit_number, search_direction: $search_direction, LastDiscrepancy: $last_zero ROM_ID: ".sprintf("%02X.%02X%02X%02X%02X%02X%02X.%02X",@{$context->{ROM_ID}})) if ($main::owx_async_debug);
      # increment the byte counter id_bit_number
      # and shift the mask rom_byte_mask
      $id_bit_number++;
      $rom_byte_mask <<= 1;
      #-- if the mask is 0 then go to new rom_byte_number and
      if ($rom_byte_mask == 256){
        $rom_byte_number++;
        $rom_byte_mask = 1;
      } 
    }
    $context->{LastDiscrepancy} = $last_zero;
    PT_END;
  });
}

1;