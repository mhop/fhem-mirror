########################################################################################
#
# OWX_SER.pm
#
# FHEM module providing hardware dependent functions for the serial (USB) interface of OWX
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

package OWX_SER;

use strict;
use warnings;

use vars qw/@ISA/;

require "$main::attr{global}{modpath}/FHEM/DevIo.pm";

use Time::HiRes qw( gettimeofday );
use ProtoThreads;
no warnings 'deprecated';

########################################################################################
# 
# Constructor
#
########################################################################################

sub new() {
  my $class = shift;
  my $self = {
    interface => "serial",
    #-- module version
    version => 5.1,
    alarmdevs => [],
    devs => [],
    fams => [],
    timeout => 1.0, #default timeout 1 sec.
  };
  return bless $self,$class;
}

sub poll() {
  my ( $self ) = @_;
  my $hash = $self->{hash};
  if(defined($hash->{FD})) {
    my ($rout, $rin) = ('', '');
    vec($rin, $hash->{FD}, 1) = 1;
    select($rout=$rin, undef, undef, 0.1);
    my $mfound = vec($rout, $hash->{FD}, 1);
    if ($mfound) {
      if ($self->read()) {
        return 1;
      } else {
        main::OWX_ASYNC_Disconnect($hash);
      }
    }
  }
  return undef;
}

########################################################################################
# 
# Public methods
#
########################################################################################
#
# Define - Implements Define method
# 
# Parameter def = definition string
#
# Return undef if ok, otherwise error message
#
########################################################################################

sub Define ($$) {
  my ($self,$hash,$def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $self->{name} = $hash->{NAME};

  #-- check syntax
  if(int(@a) < 3){
    return "OWX_SER: Syntax error - must be define <name> OWX <serial-device>"
  }
  my $dev = $a[2];

  my $device;
  #-- network attached serial:
  if ( $dev =~ m/^(.+):([0-9]+)$/ ) {
    $hash->{DeviceName} = $dev;
    $device = $dev;
  } else {
    #-- when the specified device name contains @<digits> already, use it as supplied
    if ( $dev !~ m/\@\d*/ ){
      $hash->{DeviceName} = $dev."\@9600";
    }
    my $baudrate;
    ($device,$baudrate) = split('@',$dev);
    $self->{baud} = $baudrate ? $baudrate : 9600;
  }
  #-- let fhem.pl MAIN call OWX_Ready when setup is done.
  $main::readyfnlist{"$hash->{NAME}.$device"} = $hash;
  $self->{hash} = $hash;
  return undef;
}

########################################################################################
#
# Alarms - Find devices on the 1-Wire bus, which have the alarm flag set
#
# Return number of alarmed devices
#
########################################################################################

sub get_pt_alarms() {
  my ($self) = @_;
  my $pt_next;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $thread->{alarmdevs} = [];
    #-- Discover all alarmed devices on the 1-Wire bus
    $self->first($thread);
    do {
      $pt_next = $self->pt_next($thread,"alarms");
      PT_WAIT_THREAD($pt_next);
      die $pt_next->PT_CAUSE() if ($pt_next->PT_STATE() == PT_ERROR || $pt_next->PT_STATE() == PT_CANCELED);
      $self->next_response($thread,"alarms");
    } while( $thread->{LastDeviceFlag}==0 );
    main::Log3($self->{name},5, " Alarms = ".join(' ',@{$thread->{alarmdevs}}));
    PT_EXIT($thread->{alarmdevs});
    PT_END;
  });
}

########################################################################################
#
# Discover - Find devices on the 1-Wire bus
#
# Parameter hash = hash of bus master
#
# Return 1, if alarmed devices found, 0 otherwise.
#
########################################################################################

sub get_pt_discover() {
  my ($self) = @_;
  my $pt_next;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    #-- Discover all alarmed devices on the 1-Wire bus
    $self->first($thread);
    do {
      $pt_next = $self->pt_next($thread,"discover");
      PT_WAIT_THREAD($pt_next);
      die $pt_next->PT_CAUSE() if ($pt_next->PT_STATE() == PT_ERROR || $pt_next->PT_STATE() == PT_CANCELED);
      $self->next_response($thread,"discover");
    } while( $thread->{LastDeviceFlag}==0 );
    PT_EXIT($thread->{devs});
    PT_END;
  });
}

########################################################################################
# 
# Init - Initialize the 1-wire device
#
# Parameter hash = hash of bus master
#
# Return 1 or Errormessage : not OK
#        0 or undef : OK
#
########################################################################################

sub initialize() {
  my ($self) = @_;
  my ($i,$j,$k,$l,$res,$ret,$ress);
  #-- Second step in case of serial device: open the serial device to test it
  my $hash = $self->{hash};
  my $msg = "OWX_SER: Serial device $hash->{DeviceName}";
  main::DevIo_OpenDev($hash,$self->{reopen},undef);
  return undef unless $hash->{STATE} eq "opened";

  #-- Third step detect busmaster on serial interface

  my $name = $self->{name};
  my $ress0 = "OWX_SER::Detect 1-Wire bus $name: interface ";
  $ress     = $ress0;

  my $interface;
  
  require "$main::attr{global}{modpath}/FHEM/OWX_DS2480.pm";
  my $ds2480 = OWX_DS2480->new($self);

  if (defined (my $hwdevice = $hash->{USBDev})) {
    #force master reset in DS2480
    $hwdevice->reset_error();
    $hwdevice->purge_all;
    $hwdevice->baudrate(4800);
    $hwdevice->write_settings;
    $hwdevice->write("\x00");
    select(undef,undef,undef,0.5);
    #-- timing byte for DS2480
    $ds2480->start_query();
    $hwdevice->baudrate(9600);
    $hwdevice->write_settings;
    $ds2480->query("\xC1",0);
    $hwdevice->baudrate($self->{baud});
    $hwdevice->write_settings;
  } else {
    #-- for serial over network we cannot reset but just send the timing byte
    $ds2480->start_query();
    $ds2480->query("\xC1",0);
  }

  #-- Max 4 tries to detect an interface
  for($l=0;$l<100;$l++) {
    #-- write 1-Wire bus (Fig. 2 of Maxim AN192)
    $ds2480->start_query();
    $ds2480->query("\x17\x45\x5B\x0F\x91",5);
    eval {   #ignore timeout
      do {
        $ds2480->read();
      } while (!$ds2480->response_ready());
    };
    $res = $ds2480->{string_in};
    #-- process 4/5-byte string for detection
    if( !defined($res)){
      $res="";
      $ret=1;
    }elsif( ($res eq "\x16\x44\x5A\x00\x90") || ($res eq "\x16\x44\x5A\x00\x93")){
      $ress .= "master DS2480 detected for the first time";
      $interface="DS2480";
      $ret=0;
    } elsif( $res eq "\x17\x45\x5B\x0F\x91"){
      $ress .= "master DS2480 re-detected";
      $interface="DS2480";
      $ret=0;
    } elsif( ($res eq "\x17\x0A\x5B\x0F\x02") || ($res eq "\x00\x17\x0A\x5B\x0F\x02") || ($res eq "\x30\xf8\x00") || ($res eq "\x06\x00\x09\x07\x80") || ($res eq "\x17\x41\xAB\x20\xFC")){
      $ress .= "passive DS9097 detected";
      $interface="DS9097";
      $ret=0;
    } else {
      $ret=1;
    }
    last 
      if( $ret==0 );
    $ress .= "not found, answer was ";
    for($i=0;$i<length($res);$i++){
      $j=int(ord(substr($res,$i,1))/16);
      $k=ord(substr($res,$i,1))%16;
      $ress.=sprintf "0x%1x%1x ",$j,$k;
    }
    main::Log3($hash->{NAME},4, $ress);
    $ress = $ress0;
    #-- sleeping for some time
    select(undef,undef,undef,0.5);
  }
  if( $ret == 1 ){
    $interface=undef;
    $ress .= "not detected, answer was ";
    for($i=0;$i<length($res);$i++){
      $j=int(ord(substr($res,$i,1))/16);
      $k=ord(substr($res,$i,1))%16;
      $ress.=sprintf "0x%1x%1x ",$j,$k;
    }
  }
  $self->{interface} = $interface;
  main::Log3($hash->{NAME},3, $ress);
  if ($interface eq "DS2480") {
    return $ds2480;
  } elsif ($interface eq "DS9097") {
    require "$main::attr{global}{modpath}/FHEM/OWX_DS9097.pm";
    return OWX_DS9097->new($self);
  } else {
    die $ress;
  }
}

sub exit($) {
  my ($self) = @_;
  main::DevIo_Disconnected($self->{hash});
  $self->{interface} = "serial";
  $self->{reopen} = 1;
}

########################################################################################
#
# Verify - Verify a particular device on the 1-Wire bus
#
# Parameter hash = hash of bus master, dev =  8 Byte ROM ID of device to be tested
#
# Return 1 : device found
#        0 : device not
#
########################################################################################

sub get_pt_verify($) {
  my ($self,$dev) = @_;
  my $pt_next;
  return PT_THREAD(sub {
    my ($thread) = @_;
    my $i;
    PT_BEGIN($thread);  
    #-- from search string to byte id
    my $devs=$dev;
    $devs=~s/\.//g;
    for($i=0;$i<8;$i++){
      $thread->{ROM_ID}->[$i]=hex(substr($devs,2*$i,2));
    }
    #-- reset the search state
    $thread->{LastDiscrepancy} = 64;
    $thread->{LastDeviceFlag} = 0;
    $thread->{LastFamilyDiscrepancy} = 0;
    
    #-- now do the search
    $pt_next = $self->pt_next($thread,"verify");
    PT_WAIT_THREAD($pt_next);
    die $pt_next->PT_CAUSE() if ($pt_next->PT_STATE() == PT_ERROR || $pt_next->PT_STATE() == PT_CANCELED);
    $self->next_response($thread,"verify");
    my $dev2=sprintf("%02X.%02X%02X%02X%02X%02X%02X.%02X",@{$thread->{ROM_ID}});
    #-- reset the search state
    $thread->{LastDiscrepancy} = 0;
    $thread->{LastDeviceFlag} = 0;
    $thread->{LastFamilyDiscrepancy} = 0;
    #-- check result
    if ($dev eq $dev2){
      PT_EXIT(1);
    }else{
      PT_EXIT(0);
    }
    PT_END;
  });
};

#######################################################################################
#
# First - Find the 'first' devices on the 1-Wire bus
#
# Parameter hash = hash of bus master, mode
#
# Return 1 : device found, ROM number pushed to list
#        0 : no device present
#
########################################################################################

sub first($) {
  my ($self,$thread) = @_;
  #-- reset the search state
  $thread->{LastDiscrepancy} = 0;
  $thread->{LastDeviceFlag} = 0;
  $thread->{LastFamilyDiscrepancy} = 0;
  $thread->{ROM_ID} = [0,0,0,0,0,0,0,0];
}

sub next_response($) {
  my ($self,$thread,$mode) = @_;

  #-- character version of device ROM_ID, first byte = family 
  my $dev=sprintf("%02X.%02X%02X%02X%02X%02X%02X.%02X",@{$thread->{ROM_ID}});

  #--check if we really found a device
  if( main::OWX_CRC($thread->{ROM_ID})!= 0){
    #-- reset the search
    main::Log3($self->{name},1, "OWX_SER::Search CRC failed : $dev");
    $thread->{LastDiscrepancy} = 0;
    $thread->{LastDeviceFlag} = 0;
    $thread->{LastFamilyDiscrepancy} = 0;
    die "OWX_SER::Search CRC failed : $dev";
  }
  
  #-- for some reason this does not work - replaced by another test, see below
  #if( $self->{LastDiscrepancy}==0 ){
  #    $self->{LastDeviceFlag}=1;
  #}
  #--
  if( $thread->{LastDiscrepancy}==$thread->{LastFamilyDiscrepancy} ){
      $thread->{LastFamilyDiscrepancy}=0;    
  }
    
  #-- mode was to verify presence of a device
  if ($mode eq "verify") {
    main::Log3($self->{name},5, "OWX_SER::Search: device verified $dev");
  #-- mode was to discover devices
  } elsif( $mode eq "discover" ) {
    #-- check families
    my $famfnd=0;
    foreach (@{$self->{fams}}){
      if( substr($dev,0,2) eq $_ ){
        #-- if present, set the fam found flag
        $famfnd=1;
        last;
      }
    }
    push(@{$self->{fams}},substr($dev,0,2)) if( !$famfnd );
    foreach (@{$thread->{devs}}){
      if( $dev eq $_ ){        
        #-- if present, set the last device found flag
        $thread->{LastDeviceFlag}=1;
        last;
      }
    }
    if( $thread->{LastDeviceFlag}!=1 ){
      #-- push to list
      push(@{$thread->{devs}},$dev);
      main::Log3($self->{name},5, "OWX_SER::Search: new device found $dev");
    }
  #-- mode was to discover alarm devices 
  } else {
    for(my $i=0;$i<@{$thread->{alarmdevs}};$i++){
      if( $dev eq ${$thread->{alarmdevs}}[$i] ){        
        #-- if present, set the last device found flag
        $thread->{LastDeviceFlag}=1;
        last;
      }
    }
    if( $thread->{LastDeviceFlag}!=1 ){
    #--push to list
      push(@{$thread->{alarmdevs}},$dev);
      main::Log3($self->{name},5, "OWX_SER::Search: new alarm device found $dev");
    }
  }
  return 1;
}

1;
