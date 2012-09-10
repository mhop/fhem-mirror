package main;
use strict;
use warnings;
use POSIX;
use Time::HiRes qw(gettimeofday);

sub CommandHOL($$);

#####################################
sub
HOL_Initialize($$) {
  my ($hash) = @_;

  $hash->{SetFn} = "HOL_Set";
  $hash->{DefFn} = "HOL_Define";
}

sub 
HOL_Set {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $v = join(" ", @a);
  
  my $currentState = $hash->{STATE};
  return "state is already $v" if $currentState eq $v;
  
  if ($v eq "on" || $v eq "off") {
    if($v eq "on") {
      $hash->{STATE} = "on";
      HOL_switch($hash->{NAME});
    } elsif ($v eq "off") {
      $hash->{STATE} = "off";
      HOL_turnOffCurrentDevice($hash);
    }
    return $v;
  } else {
    return "unknown set value, choose one of on off";
  }
}

sub
HOL_Define($$) {
  my ($hash, $def) = @_;
  return undef;
}

sub
HOL_turnOffCurrentDevice {
  my ($hash) = @_;
  RemoveInternalTimer($hash);
  if (defined($hash->{currentSwitchDevice})) {
    my $currentDeviceName = $hash->{currentSwitchDevice};
    fhem "set $currentDeviceName off";
  }
}

sub
HOL_switch {
  my ($deviceName) = @_;
  my $hash = $defs{$deviceName};
  
  HOL_turnOffCurrentDevice($hash);
  
  my $state = $hash->{STATE}; 
  Log 2, "holiday state is  $state";
  return undef if ($state eq "off");
  
  my $deviceName;
  
  if (defined($hash->{currentSwitchDevice}) &&
    defined($attr{$hash->{currentSwitchDevice}}{holidaySwitchFollowUp})) {

    my $followUp = $attr{$hash->{currentSwitchDevice}}{holidaySwitchFollowUp};
    Log 2, "possible follow up devices  $followUp";
    my @possibleDevices = split(/,/, $followUp);
    $deviceName = HOL_GetRandomItemInArray(@possibleDevices);
    
    Log 2, "follow up $deviceName";
  } else {
    my @switchDevices = HOL_getHolidaySwitchDeviceNames();
    $deviceName = HOL_GetRandomItemInArray(@switchDevices);
    
    Log 2, "no follow up, chose $deviceName";
  }

  my $switchTime = $attr{$deviceName}{holidaySwitchTime};
  
  my $waitTime = int(rand(10)) + 5;
  
  $hash->{currentSwitchDevice} = $deviceName;
  $hash->{currentSwitchTime} = $switchTime;
  
  my $nextTrigger = gettimeofday()+$switchTime+$waitTime;
  $hash->{lastTrigger} = TimeNow();
  $hash->{nextTrigger} = FmtDateTime($nextTrigger);
  
  fhem "set $deviceName on-for-timer $switchTime";
  InternalTimer($nextTrigger, "HOL_switch", $deviceName, 0);
  
  return 1;
}

sub
HOL_GetRandomItemInArray {
  my (@arr) = @_;
  my $arrayPosition = int(rand(scalar(@arr)));
  return $arr[$arrayPosition];
}

sub HOL_getHolidaySwitchDeviceNames() {
  my @devices = ();
  my $device;
  
  for my $deviceKey (keys %defs) {
    $device = $defs{$deviceKey};
    next if $device->{TYPE} ne "FS20" || ! defined($attr{$deviceKey}{holidaySwitchTime});
    push (@devices, $device->{NAME});
  }
  
  return @devices;
}

1;
