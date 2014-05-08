########################################################################################
#
# OWX_DS2480.pm
#
# FHEM module providing hardware dependent functions for the DS9097 interface of OWX
#
# Prof. Dr. Peter A. Henning
# Norbert Truchsess
#
# $Id: 11_OWX_SER.pm 2013-03 - pahenning $
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

use constant {
  QUERY_TIMEOUT => 1.0
};

use vars qw/@ISA/;
@ISA='OWX_SER';

use ProtoThreads;
no warnings 'deprecated';

sub new($) {
  my ($class,$serial) = @_;
  
  $serial->{pt_reset} = PT_THREAD(\&pt_reset);
  $serial->{pt_block} = PT_THREAD(\&pt_block);
  $serial->{pt_search} = PT_THREAD(\&pt_search);
  
  return bless $serial,$class;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a DS9097 bus interface
#
########################################################################################
# 
# Block_9097 - Send data block (
#
# Parameter hash = hash of bus master, data = string to send
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub pt_block ($) {
  my ($thread,$self,$data) =@_;
  PT_BEGIN($thread);
  my $data2="";
  my $res=0;
  for (my $i=0; $i<length($data);$i++){
    $res = $self->TouchByte_9097(ord(substr($data,$i,1)));
    $data2 = $data2.chr($res);
  }
  PT_EXIT($data2);
  PT_END;
}

########################################################################################
#
# Query_9097 - Write to and read from the 1-Wire bus
# 
# Parameter: hash = hash of bus master, cmd = string to send to the 1-Wire bus
#
# Return: string received from the 1-Wire bus
#
########################################################################################

sub Query_9097 ($) {

  my ($self,$cmd) = @_;
  my ($i,$j,$k);
  #-- get hardware device 
  my $hwdevice = $self->{hwdevice};
  
  return undef unless (defined $hwdevice);
  
  $hwdevice->baudrate($self->{baud});
  $hwdevice->write_settings;
  
  if( $main::owx_debug > 2){
    my $res = "OWX_SER::Query_9097 Sending out ";
    for($i=0;$i<length($cmd);$i++){  
      $j=int(ord(substr($cmd,$i,1))/16);
      $k=ord(substr($cmd,$i,1))%16;
      $res.=sprintf "0x%1x%1x ",$j,$k;
    }
    main::Log3($self->{name},3, $res);
  } 
	
  my $count_out = $hwdevice->write($cmd);

  main::Log3($self->{name},1, "OWX_SER::Query_9097 Write incomplete $count_out ne ".(length($cmd))."") if ( $count_out != length($cmd) );
  #-- sleeping for some time
  select(undef,undef,undef,0.01);
 
  #-- read the data
  my ($count_in, $string_in) = $hwdevice->read(48);
  return undef if (not defined $string_in);
    
  if( $main::owx_debug > 2){
    my $res = "OWX_SER::Query_9097 Receiving ";
    for($i=0;$i<$count_in;$i++){  
      $j=int(ord(substr($string_in,$i,1))/16);
      $k=ord(substr($string_in,$i,1))%16;
      $res.=sprintf "0x%1x%1x ",$j,$k;
    }
    main::Log3($self->{name},3, $res);
  }
	
  #-- sleeping for some time
  select(undef,undef,undef,0.01);
 
  return($string_in);
}

########################################################################################
# 
# ReadBit_9097 - Read 1 bit from 1-wire bus  (Fig. 5/6 from Maxim AN214)
#
# Parameter hash = hash of bus master
#
# Return bit value
#
########################################################################################

sub ReadBit_9097 () {
  my ($self) = @_;
  
  #-- set baud rate to 115200 and query!!!
  my $sp1="\xFF";
  $self->{baud}=115200;
  my $res=$self->Query_9097($sp1);
  return undef if (not defined $res);
  $self->{baud}=9600;
  #-- process result
  if( substr($res,0,1) eq "\xFF" ){
    return 1;
  } else {
    return 0;
  } 
}

########################################################################################
# 
# OWX_Reset_9097 - Reset the 1-Wire bus (Fig. 4 of Maxim AN192)
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub pt_reset () {

  my ($thread,$self)=@_;

  #-- Reset command \xF0
  my $cmd="\xF0";
  #-- write 1-Wire bus
  PT_BEGIN($thread);
  #-- write 1-Wire bus
  my $res = $self->Query_9097($cmd);
  PT_EXIT if (not defined $res);
  #-- TODO: process result
  #-- may vary between 0x10, 0x90, 0xe0
  PT_EXIT(1);
  PT_END;
}

########################################################################################
#
# Search_9097 - Perform the 1-Wire Search Algorithm on the 1-Wire bus using the existing
#              search state.
#
# Parameter hash = hash of bus master, mode=alarm,discover or verify
#
# Return 1 : device found, ROM number in owx_ROM_ID and pushed to list (LastDeviceFlag=0) 
#                                     or only in owx_ROM_ID (LastDeviceFlag=1)
#        0 : device not found, or ot searched at all
#
########################################################################################

sub pt_search ($) {
  my ($thread,$self,$mode)=@_;

  PT_BEGIN($thread);
  my ($sp1,$sp2,$response,$search_direction,$id_bit_number);
  
  #-- Response search data parsing operates bitwise
  $id_bit_number = 1;
  my $rom_byte_number = 0;
  my $rom_byte_mask = 1;
  my $last_zero = 0;

  #-- issue search command
  $self->{baud}=115200;
  #TODO: add specific command to search alarmed devices only
  $sp2="\x00\x00\x00\x00\xFF\xFF\xFF\xFF";
  $response = $self->Query_9097($sp2);
  return undef if (not defined $response);
  $self->{baud}=9600;
  #-- issue the normal search command \xF0 or the alarm search command \xEC 
  #if( $mode ne "alarm" ){
  #  $sp1 = 0xF0;
  #} else {
  #  $sp1 = 0xEC;
  #}
      
  #$response = OWX_TouchByte($hash,$sp1); 

  #-- clear 8 byte of device id for current search
  @{$self->{ROM_ID}} =(0,0,0,0 ,0,0,0,0); 

  while ( $id_bit_number <= 64) {
    #loop until through all ROM bytes 0-7  
    my $id_bit     = $self->TouchBit_9097(1);
    my $cmp_id_bit = $self->TouchBit_9097(1);
     
    #print "id_bit = $id_bit, cmp_id_bit = $cmp_id_bit\n";
     
    if( ($id_bit == 1) && ($cmp_id_bit == 1) ){
      #print "no devices present at id_bit_number=$id_bit_number \n";
      next;
    }
    if ( $id_bit != $cmp_id_bit ){
      $search_direction = $id_bit;
    } else {
      # hä ? if this discrepancy if before the Last Discrepancy
      # on a previous next then pick the same as last time
      if ( $id_bit_number < $self->{LastDiscrepancy} ){
        if ((@{$self->{ROM_ID}}[$rom_byte_number] & $rom_byte_mask) > 0){
          $search_direction = 1;
        } else {
          $search_direction = 0;
        }
      } else {
        # if equal to last pick 1, if not then pick 0
        if ($id_bit_number == $self->{LastDiscrepancy}){
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
          $self->{LastFamilyDiscrepancy} = $last_zero;
        }
      }
    }
    # print "search_direction = $search_direction, last_zero=$last_zero\n";
    # set or clear the bit in the ROM byte rom_byte_number
    # with mask rom_byte_mask
    #print "ROM byte mask = $rom_byte_mask, search_direction = $search_direction\n";
    if ( $search_direction == 1){
      @{$self->{ROM_ID}}[$rom_byte_number] |= $rom_byte_mask;
    } else {
      @{$self->{ROM_ID}}[$rom_byte_number] &= ~$rom_byte_mask;
    }
    # serial number search direction write bit
    $response = $self->WriteBit_9097($search_direction);
    # increment the byte counter id_bit_number
    # and shift the mask rom_byte_mask--
    $id_bit_number++;
    $rom_byte_mask <<= 1;
    #-- if the mask is 0 then go to new rom_byte_number and
    if ($rom_byte_mask == 256){
      $rom_byte_number++;
      $rom_byte_mask = 1;
    } 
    $self->{LastDiscrepancy} = $last_zero;
  }
  PT_EXIT(1);
  PT_END; 
}

########################################################################################
# 
# TouchBit_9097 - Write/Read 1 bit from 1-wire bus  (Fig. 5-8 from Maxim AN 214)
#
# Parameter hash = hash of bus master
#
# Return bit value
#
########################################################################################

sub TouchBit_9097 ($) {
  my ($self,$bit) = @_;
  
  my $sp1;
  #-- set baud rate to 115200 and query!!!
  if( $bit == 1 ){
    $sp1="\xFF";
  } else {
    $sp1="\x00";
  }
  $self->{baud}=115200;
  my $res=$self->Query_9097($sp1);
  return undef if (not defined $res);
  $self->{baud}=9600;
  #-- process result
  my $sp2=substr($res,0,1);
  if( $sp1 eq $sp2 ){
    return 1;
  }else {
    return 0;
  }
}

########################################################################################
# 
# TouchByte_9097 - Write/Read 8 bit from 1-wire bus 
#
# Parameter hash = hash of bus master
#
# Return bit value
#
########################################################################################

sub TouchByte_9097 ($) {
  my ($self,$byte) = @_;
  
  my $loop;
  my $result=0;
  my $bytein=$byte;
  
  for( $loop=0; $loop < 8; $loop++ ){
    #-- shift result to get ready for the next bit
    $result >>=1;
    #-- if sending a 1 then read a bit else write 0
    if( $byte & 0x01 ){
      if( $self->ReadBit_9097() ){
        $result |= 0x80;
      }
    } else {
      $self->WriteBit_9097(0);
    }
    $byte >>= 1;
  }
  return $result;
}

########################################################################################
# 
# WriteBit_9097 - Write 1 bit to 1-wire bus  (Fig. 7/8 from Maxim AN 214)
#
# Parameter hash = hash of bus master
#
# Return bit value
#
########################################################################################

sub WriteBit_9097 ($) {
  my ($self,$bit) = @_;
  
  my $sp1;
  #-- set baud rate to 115200 and query!!!
  if( $bit ==1 ){
    $sp1="\xFF";
  } else {
    $sp1="\x00";
  }
  $self->{baud}=115200;
  my $res=$self->Query_9097($sp1);
  return undef if (not defined $res);
  $self->{baud}=9600;
  #-- process result
  if( substr($res,0,1) eq $sp1 ){
    return 1;
  } else {
    return 0;
  } 
};

# dummy implementation of read - data is actually read within methods above.
sub read() {
  return 1;
}

1;
