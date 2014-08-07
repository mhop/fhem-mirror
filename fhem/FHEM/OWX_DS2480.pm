########################################################################################
#
# OWX_DS2480.pm
#
# FHEM module providing hardware dependent functions for the DS2480 interface of OWX
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

package OWX_DS2480;

use strict;
use warnings;
use Time::HiRes qw( gettimeofday tv_interval usleep );
use ProtoThreads;
no warnings 'deprecated';

use vars qw/@ISA/;
@ISA='OWX_SER';

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
  return PT_THREAD(sub {
    my ($thread) = @_;
    
    PT_BEGIN($thread);
    
    $self->reset() if ($reset);
  
    if (defined $writedata or $numread) {
  
      my $select;
    
      #-- has match ROM part
      if( $dev ) {
            
        #-- ID of the device
        my $owx_rnf = substr($dev,3,12);
        my $owx_f   = substr($dev,0,2);
    
        #-- 8 byte 1-Wire device address
        my @rom_id  =(0,0,0,0 ,0,0,0,0); 
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
      #-- has receive data part
      if( $numread ) {
        #$numread += length($data);
        for( my $i=0;$i<$numread;$i++){
          $select .= "\xFF";
        };
      }
      
      #-- for debugging
      if( $main::owx_async_debug > 1){
        main::Log3($self->{name},5,"OWX_SER::Execute: Sending out ".unpack ("H*",$select));
      }
      $self->block($select);
    }
    
    main::OWX_ASYNC_TaskTimeout($self->{hash},gettimeofday+main::AttrVal($self->{name},"timeout",2));
    PT_WAIT_UNTIL($self->response_ready());
    
    if ($reset and !$self->reset_response()) {
      die "reset failure";
    }
  
    my $res = $self->{string_in};
    #-- for debugging
    if( $main::owx_async_debug > 1){
      main::Log3($self->{name},5,"OWX_SER::Execute: Receiving ".unpack ("H*",$res));
    }
  
    if (defined $res) {
      my $writelen = defined $writedata ? split (//,$writedata) : 0;
      my @result = split (//, $res);
      my $readdata = 9+$writelen < @result ? substr($res,9+$writelen) : "";
      PT_EXIT($readdata);
    }
    PT_END;
  });
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a DS2480 bus interface
#
#########################################################################################
# 
# Block_2480 - Send data block (Fig. 6 of Maxim AN192)
#
# Parameter hash = hash of bus master, data = string to send
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub block ($) {
  my ($serial,$data) =@_;
  my $data2="";
  
  my $len = length($data);
  
  #-- if necessary, prepend E1 character for data mode
  if( substr($data,0,1) ne '\xE1') {
    $data2 = "\xE1";
  }
  #-- all E3 characters have to be duplicated
  for(my $i=0;$i<$len;$i++){
    my $newchar = substr($data,$i,1);
    $data2=$data2.$newchar;
    if( $newchar eq '\xE3'){
      $data2=$data2.$newchar;
    }
  }
  #-- write 1-Wire bus as a single string
  $serial->query($data2,$len);
}

########################################################################################
#
# query - Write to the 1-Wire bus
# 
# Parameter: cmd = string to send to the 1-Wire bus, retlen = expected len of the response
#
# Return: 1 when write was successful. undef otherwise
#
########################################################################################

sub query ($$$) {
  my ($serial,$cmd,$retlen) = @_;
  main::DevIo_SimpleWrite($serial->{hash},$cmd,0);
  $serial->{retlen} += $retlen;
}

########################################################################################
#
# read - read response from the 1-Wire bus
#        to be called from OWX ReadFn.
# 
# Parameter: -
#
# Return: 1 when at least 1 byte was read. undef otherwise
#
########################################################################################

sub read() {
  my ($serial) = @_;
  #-- read the data
  my $string_part = main::DevIo_DoSimpleRead($serial->{hash});
  $serial->{num_reads}++;
  #return undef unless defined $string_part;
  if (defined $string_part) {
    my $count_in = length ($string_part);
    $serial->{string_in} .= $string_part;
    $serial->{retcount} += $count_in;
    main::Log3($serial->{name},5, "OWX_DS2480 read: Loop no. $serial->{num_reads}, Receiving: ".unpack("H*",$string_part)) if( $main::owx_async_debug > 1 );
    return $count_in > 0 ? 1 : undef;
  } elsif ($main::owx_async_debug > 2) {
    main::Log3($serial->{name},5, "OWX_DS2480 read: Loop no. $serial->{num_reads}, no data read:");
    foreach my $i (0..6) {
      my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash) = caller($i);
      main::Log3($serial->{name},5, "$subroutine $filename $line");
    }
  }
  return undef;
}

sub response_ready() {
  my ($serial) = @_;
  if ($serial->{retcount} >= $serial->{retlen}) {
    main::Log3($serial->{name},5, "OWX_DS2480 read: After loop no. $serial->{num_reads} received: ".unpack("H*",$serial->{string_in}));
    return 1;
  }
  if (($serial->{num_reads} > 1) and (tv_interval($serial->{starttime}) > $serial->{timeout})) {
    main::Log3($serial->{name},5, "OWX_DS2480 read: After loop no. $serial->{num_reads} received: ".unpack("H*",$serial->{string_in}). " -> TIMEOUT");
    die "OWX_DS2480 read timeout, bytes read: $serial->{retcount}, expected: $serial->{retlen}" ;
  }
  return 0;
}

sub start_query() {
  my ($serial) = @_;
  #read and discard any outstanding data from previous commands:
  while($serial->poll()) {};

  $serial->{string_in} = "";
  $serial->{num_reads} = 0;
  $serial->{retlen} = 0;
  $serial->{retcount} = 0;
  $serial->{starttime} = [gettimeofday];
}

########################################################################################
# 
# reset - Reset the 1-Wire bus (Fig. 4 of Maxim AN192)
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub reset() {

  my ($serial) = @_;
  my ($res,$r1,$r2);
  my $name = $serial->{name};
  $serial->start_query();

  #-- if necessary, prepend \xE3 character for command mode
  #-- Reset command \xC5
  #-- write 1-Wire bus
  $serial->query("\xE3\xC5",1);
  #-- sleeping for some time (value of 0.07 taken from original OWX_Query_DS2480)
  select(undef,undef,undef,0.07);
}

sub reset_response() {
  my ($serial) = @_;

  my $res = ord(substr($serial->{string_in},0,1));
  my $name = $serial->{name};
  
  if( !($res & 192) ) {
    main::Log3($name,4, "OWX_DS2480 reset failure on bus $name");
    return 0;
  }
  
  if( ($res & 3) == 2 ) {
    main::Log3($name,4, "OWX_DS2480 reset Alarm presence detected on bus $name");
    $serial->{ALARMED} = "yes";
  } else {
    $serial->{ALARMED} = "no";
  }
  $serial->{string_in} = substr($serial->{string_in},1);
  return 1;
}

########################################################################################
#
# Search_2480 - Perform the 1-Wire Search Algorithm on the 1-Wire bus using the existing
#              search state.
#
# Parameter hash = hash of bus master, mode=alarm,discover or verify
#
# Return 1 : device found, ROM number in owx_ROM_ID and pushed to list (LastDeviceFlag=0) 
#                                     or only in owx_ROM_ID (LastDeviceFlag=1)
#        0 : device not found, or ot searched at all
#
########################################################################################

sub pt_next ($$) {

  my ($serial,$context,$mode)=@_;

  my $id_bit_number = 1;
  my $rom_byte_number = 0;
  my $rom_byte_mask = 1;
  my $last_zero = 0;
  my ($sp1,$sp2,$pt_query,$search_direction);

  return PT_THREAD(sub {
    my ( $thread ) = @_;
    PT_BEGIN($thread);
    #-- clear 16 byte of search data
    $context->{search} = [0,0,0,0 ,0,0,0,0, 0,0,0,0, 0,0,0,0];
    #-- Output search data construction (Fig. 9 of Maxim AN192)
    #   operates on a 16 byte search response = 64 pairs of two bits
    while ( $id_bit_number <= 64) {
      #-- address single bits in a 16 byte search string
      my $newcpos = int(($id_bit_number-1)/4);
      my $newimsk = ($id_bit_number-1)%4;
      #-- address single bits in a 8 byte id string
      my $newcpos2 = int(($id_bit_number-1)/8);
      my $newimsk2 = ($id_bit_number-1)%8;
  
      if( $id_bit_number <= $context->{LastDiscrepancy}){
        #-- first use the ROM ID bit to set the search direction  
        if( $id_bit_number < $context->{LastDiscrepancy} ) {
          $search_direction = ($context->{ROM_ID}->[$newcpos2]>>$newimsk2) & 1;
          #-- at the last discrepancy search into 1 direction anyhow
        } else {
          $search_direction = 1;
        } 
        #-- fill into search data;
        $context->{search}->[$newcpos]+=$search_direction<<(2*$newimsk+1);
      }
      #--increment number
      $id_bit_number++;
    }
    #-- issue data mode \xE1, the normal search command \xF0 or the alarm search command \xEC 
    #   and the command mode \xE3 / start accelerator \xB5 
    if( $mode ne "alarm" ){
      $sp1 = "\xE1\xF0\xE3\xB5";
    } else {
      $sp1 = "\xE1\xEC\xE3\xB5";
    }
    #-- issue data mode \xE1, device ID, command mode \xE3 / end accelerator \xA5
    $sp2=sprintf("\xE1%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c\xE3\xA5",@{$context->{search}});
    $serial->reset();
    $serial->query($sp1,1);
    $serial->query($sp2,16);
    main::OWX_ASYNC_TaskTimeout($serial->{hash},gettimeofday+main::AttrVal($serial->{name},"timeout",2));
    PT_WAIT_UNTIL($serial->response_ready());
    die "reset failed" unless $serial->reset_response();

    my $response = substr($serial->{string_in},1);
    #-- interpret the return data
    if( length($response)!=16 ) {
      die "OWX_DS2480: Search 2nd return has wrong parameter with length = ".(length($response)."");
    }
    #-- Response search data parsing (Fig. 11 of Maxim AN192)
    #   operates on a 16 byte search response = 64 pairs of two bits
    $id_bit_number = 1;
    #-- clear 8 byte of device id for current search
    $context->{ROM_ID} = [0,0,0,0 ,0,0,0,0]; 

    while ( $id_bit_number <= 64) {
      #-- adress single bits in a 16 byte string
      my $newcpos = int(($id_bit_number-1)/4);
      my $newimsk = ($id_bit_number-1)%4;

      #-- retrieve the new ROM_ID bit
      my $newchar = substr($response,$newcpos,1);

      #-- these are the new bits
      my $newibit = (( ord($newchar) >> (2*$newimsk) ) & 2) / 2;
      my $newdbit = ( ord($newchar) >> (2*$newimsk) ) & 1;

      #-- discrepancy=1 and ROM_ID=0
      if( ($newdbit==1) and ($newibit==0) ){
          $context->{LastDiscrepancy}=$id_bit_number;
          if( $id_bit_number < 9 ){
          	$context->{LastFamilyDiscrepancy}=$id_bit_number;
          }
      } 
      #-- fill into device data; one char per 8 bits
      $context->{ROM_ID}->[int(($id_bit_number-1)/8)]+=$newibit<<(($id_bit_number-1)%8);

      #-- increment number
      $id_bit_number++;
      main::Log3 ($serial->{name},5,"id_bit_number: $id_bit_number, LastDiscrepancy: $context->{LastDiscrepancy} ROM_ID: ".sprintf("%02X.%02X%02X%02X%02X%02X%02X.%02X",@{$context->{ROM_ID}})) if ($main::owx_async_debug > 2);
    }
    PT_END;
  });
}

1;
