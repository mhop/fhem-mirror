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

use vars qw/@ISA/;
@ISA='OWX_SER';

sub new($) {
  my ($class,$serial) = @_;
  
  return bless $serial,$class;
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
  my ($i,$j,$k,$l,$m,$n);
  
  #-- get hardware device
  my $hwdevice = $serial->{hwdevice};
  
  die "OWX_DS2480: query with no hwdevice" unless (defined $hwdevice);
  
  $hwdevice->baudrate($serial->{baud});
  $hwdevice->write_settings;

  main::Log3($serial->{name},5, "OWX_DS2480.query sending out: ".unpack ("H*",$cmd));
  
  my $count_out = $hwdevice->write($cmd);

  die "OWX_DS2480: Write incomplete ".(defined $count_out ? $count_out : "undefined")." not equal ".(length($cmd))."" if (!(defined $count_out) or ($count_out ne length($cmd)));

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
  my $serial = shift;
  my ($i,$j,$k);

  #-- get hardware device
  my $hwdevice = $serial->{hwdevice};
  return undef unless (defined $hwdevice);

  #-- read the data - looping for slow devices suggested by Joachim Herold
  my ($count_in, $string_part) = $hwdevice->read(255);  
  return undef if (not defined $count_in or not defined $string_part);
  $serial->{string_in} .= $string_part;                            
  $serial->{retcount} += $count_in;		
  $serial->{num_reads}++;
  if( $main::owx_async_debug > 1){
    if ($count_in>0) {
      main::Log3($serial->{name},5, "OWX_DS2480 read: Loop no. $serial->{num_reads}, Receiving: ".unpack("H*",$string_part));
    } else {
      main::Log3($serial->{name},5, "OWX_DS2480 read: Loop no. $serial->{num_reads}");
    }
  }
  return $count_in > 0 ? 1 : undef;
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
  while($serial->read(255)) {};

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
    main::Log3($name,3, "OWX_DS2480 reset failure on bus $name");
    return 0;
  }
  
  if( ($res & 3) == 2 ) {
    main::Log3($name,1, "OWX_DS2480 reset Alarm presence detected on bus $name");
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

sub search ($) {
  my ($serial,$mode)=@_;
  
  my ($sp1,$sp2,$search_direction,$id_bit_number);
    
  #-- Response search data parsing operates bytewise
  $id_bit_number = 1;
  
  #select(undef,undef,undef,0.5);
  
  #-- clear 16 byte of search data
  @{$serial->{search}}=(0,0,0,0 ,0,0,0,0, 0,0,0,0, 0,0,0,0);
  #-- Output search data construction (Fig. 9 of Maxim AN192)
  #   operates on a 16 byte search response = 64 pairs of two bits
  while ( $id_bit_number <= 64) {
    #-- address single bits in a 16 byte search string
    my $newcpos = int(($id_bit_number-1)/4);
    my $newimsk = ($id_bit_number-1)%4;
    #-- address single bits in a 8 byte id string
    my $newcpos2 = int(($id_bit_number-1)/8);
    my $newimsk2 = ($id_bit_number-1)%8;

    if( $id_bit_number <= $serial->{LastDiscrepancy}){
      #-- first use the ROM ID bit to set the search direction  
      if( $id_bit_number < $serial->{LastDiscrepancy} ) {
        $search_direction = ($serial->{ROM_ID}->[$newcpos2]>>$newimsk2) & 1;
        #-- at the last discrepancy search into 1 direction anyhow
      } else {
        $search_direction = 1;
      } 
      #-- fill into search data;
      @{$serial->{search}}[$newcpos]+=$search_direction<<(2*$newimsk+1);
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
  $sp2=sprintf("\xE1%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c\xE3\xA5",@{$serial->{search}});
  $serial->reset();
  $serial->query($sp1,1);
  $serial->query($sp2,16);
}

sub search_response($) {
  my ($serial) = @_;
  
  return undef unless $serial->reset_response();
  
  my $response = substr($serial->{string_in},1);
  #-- interpret the return data
  if( length($response)!=16 ) {
    main::Log3($serial->{name},3, "OWX_DS2480: Search 2nd return has wrong parameter with length = ".(length($response).""));
    return 0;
  }
  #-- Response search data parsing (Fig. 11 of Maxim AN192)
  #   operates on a 16 byte search response = 64 pairs of two bits
  my $id_bit_number = 1;
  #-- clear 8 byte of device id for current search
  $serial->{ROM_ID} = [0,0,0,0 ,0,0,0,0]; 

  while ( $id_bit_number <= 64) {
    #-- adress single bits in a 16 byte string
    my $newcpos = int(($id_bit_number-1)/4);
    my $newimsk = ($id_bit_number-1)%4;

    #-- retrieve the new ROM_ID bit
    my $newchar = substr($response,$newcpos,1);
 
    #-- these are the new bits
    my $newibit = (( ord($newchar) >> (2*$newimsk) ) & 2) / 2;
    my $newdbit = ( ord($newchar) >> (2*$newimsk) ) & 1;

    #-- output for test purpose
    #print "id_bit_number=$id_bit_number => newcpos=$newcpos, newchar=0x".int(ord($newchar)/16).
    #      ".".int(ord($newchar)%16)." r$id_bit_number=$newibit d$id_bit_number=$newdbit\n";
    
    #-- discrepancy=1 and ROM_ID=0
    if( ($newdbit==1) and ($newibit==0) ){
        $serial->{LastDiscrepancy}=$id_bit_number;
        if( $id_bit_number < 9 ){
        	$serial->{LastFamilyDiscrepancy}=$id_bit_number;
        }
    } 
    #-- fill into device data; one char per 8 bits
    $serial->{ROM_ID}->[int(($id_bit_number-1)/8)]+=$newibit<<(($id_bit_number-1)%8);
  
    #-- increment number
    $id_bit_number++;
  }
  return 1;
}

########################################################################################
# 
# Level_2480 - Change power level (Fig. 13 of Maxim AN192)
#
# Parameter hash = hash of bus master, newlevel = "normal" or something else
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub Level_2480 ($) {
  my ($self,$newlevel) =@_;
  my $cmd="";
  my $retlen=0;
  #-- if necessary, prepend E3 character for command mode
  $cmd = "\xE3";
 
  #-- return to normal level
  if( $newlevel eq "normal" ){
    $cmd=$cmd."\xF1\xED\xF1";
    $retlen+=3;
    #-- write 1-Wire bus
    my $res = $self->Query_2480($cmd,$retlen);
    return undef if (not defined $res);
    #-- process result
    my $r1  = ord(substr($res,0,1)) & 236;
    my $r2  = ord(substr($res,1,1)) & 236;
    if( ($r1 eq 236) && ($r2 eq 236) ){
      main::Log3($self->{name},5, "OWX_SER: Level change to normal OK");
      return 1;
    } else {
      main::Log3($self->{name},3, "OWX_SER: Failed to change to normal level");
      return 0;
    }
  #-- start pulse  
  } else {    
    $cmd=$cmd."\x3F\xED";
    $retlen+=2;
    #-- write 1-Wire bus
    my $res = $self->Query_2480($cmd,$retlen);
    return undef if (not defined $res);
    #-- process result
    if( $res eq "\x3E" ){
      main::Log3($self->{name},5, "OWX_SER: Level change OK");
      return 1;
    } else {
      main::Log3($self->{name},3, "OWX_SER: Failed to change level");
      return 0;
    }
  }
}

########################################################################################
# 
# WriteBytePower_2480 - Send byte to bus with power increase (Fig. 16 of Maxim AN192)
#
# Parameter hash = hash of bus master, dbyte = byte to send
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub WriteBytePower_2480 ($) {

  my ($self,$dbyte) =@_;
  
  my $cmd="\x3F";
  my $ret="\x3E";
  #-- if necessary, prepend \xE3 character for command mode
  $cmd = "\xE3".$cmd;
  
  #-- distribute the bits of data byte over several command bytes
  for (my $i=0;$i<8;$i++){
    my $newbit   = (ord($dbyte) >> $i) & 1;
    my $newchar  = 133 | ($newbit << 4);
    my $newchar2 = 132 | ($newbit << 4) | ($newbit << 1) | $newbit;
    #-- last command byte still different
    if( $i == 7){
      $newchar = $newchar | 2;
    }
    $cmd = $cmd.chr($newchar);
    $ret = $ret.chr($newchar2);
  }
  #-- write 1-Wire bus
  my $res = $self->Query($cmd);
  #-- process result
  if( $res eq $ret ){
    main::Log3($self->{name},5, "OWX_SER::WriteBytePower OK");
    return 1;
  } else {
    main::Log3($self->{name},3, "OWX_SER::WriteBytePower failure");
    return 0;
  }
}

1;
