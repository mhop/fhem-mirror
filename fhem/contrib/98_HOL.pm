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
  $hash->{UndefFn} = "HOL_Undef";
}

sub 
HOL_Set {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $v = join(" ", @a);
  
  my $currentState = $hash->{STATE};
  return "state is already $v" if $currentState eq $v;
  
  if ($v eq "on" || $v eq "off" || $v eq "switch") {
    if($v eq "on") {
      $hash->{STATE} = "on";
      HOL_switch($hash);
    } elsif ($v eq "off") {
      $hash->{STATE} = "off";
      HOL_turnOffCurrentDevice($hash);
    } elsif ($v eq "switch") {
      my $state = "$hash->{STATE}";
      return "can only switch if state is on" if ($state ne "on");
      HOL_switch($hash);
    }
    return $v;
  } else {
    return "unknown set value, choose one of on off switch";
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
  my ($hash) = @_;
  
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
  InternalTimer($nextTrigger, "HOL_switch", $hash, 0);
  
  return 1;
}

sub
HOL_Undef($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
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

=pod
=begin html

<a name="HOL"></a>
<h3>HOL</h3>
<ul>
  <tr>The HOL module attempts to simulate your presence using your FHEM devices.<br/>
  Device support: All devices that are able to handle on-for-timer and on commands.<br />
  Currently the device can be found within the <i>contrib/</i> folder.<td>

  <br /><br />
  <a name="HOLdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HOL</code><br>
    <br>
    To make the module find the devices you want to switch in holiday mode, 
    you have to specify a global user attribute (attr global userattr holidaySwitchTime).
    The attribute tells the HOL module how long each device should be switched on.
    If you want to switch a device in your FHEM configuration, just add this attribute as device attribute
    with your defined duration.
    When being switched to on, the module chooses a random defined device
    having the <i>holidaySwitchTime</i> attribute and trigger it to on-for-timer.
    After the on-timespan, this device is switched to off and another random one triggered to on-for-timer.
  </ul>
  <br>

  <a name="HOLset"></a>
  <b>Set</b>
  <ul>
    <li>on</li>
    <li>off</li>
  </ul>
</ul>


=end html
=cut
