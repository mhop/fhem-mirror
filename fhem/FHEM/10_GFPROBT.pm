##################################################################
#
# GFPROBT.pm (c) by Dominik Karall, 2019
# dominik karall at gmail dot com
# $Id$
#
# FHEM module to communicate with G.F.Pro Bluetooth Eco Watering
#
##################################################################

package main;

use strict;
use warnings;

use Encode;
use SetExtensions;
use Expect;
use JSON;
use Blocking;

sub GFPROBT_Initialize($) {
    my ($hash) = @_;
    
    $hash->{DefFn}    = 'GFPROBT_Define';
    $hash->{UndefFn}  = 'GFPROBT_Undef';
    $hash->{GetFn}    = 'GFPROBT_Get';
    $hash->{SetFn}    = 'GFPROBT_Set';
    $hash->{AttrFn}   = 'GFPROBT_Attribute';
    $hash->{AttrList}  = 'blockingCallLoglevel '.
                            $readingFnAttributes;
    
    return undef;
}

sub GFPROBT_Define($$) {
    #save BTMAC address
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my $name = $a[0];
    my $mac;
    my $sshHost;
    
    $hash->{NAME} = $name;
    $hash->{STATE} = "initialized";
    $hash->{VERSION} = "1.0.0";
    $hash->{loglevel} = 4;
    Log3 $hash, 3, "GFPROBT: G.F.Pro Eco Watering Bluetooth ".$hash->{VERSION};
    
    if (int(@a) > 4) {
        return 'GFPROBT: Wrong syntax, must be define <name> GFPROBT <mac address>';
    } elsif(int(@a) == 3) {
        $mac = $a[2];
        $hash->{MAC} = $a[2];
    } elsif(int(@a) == 4) {
        $mac = $a[2];
        $hash->{MAC} = $a[2];
        $attr{$name}{sshHost} = $a[3];
    }
    
    GFPROBT_updateHciDevicelist($hash);
    
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+10, "GFPROBT_updateStatus", $hash, 0);
    
    return undef;
}

sub GFPROBT_updateHciDevicelist {
    my ($hash) = @_;
    my $name    = $hash->{NAME};
    #check for hciX devices
    $hash->{helper}{hcidevices} = ();
    my @btDevices;
    my $sshHost     = AttrVal($name,"sshHost","none");
    
    if( $sshHost ne 'none' ) {
        @btDevices = split("\n", qx(ssh $sshHost 'hcitool dev'));
    } else {
        @btDevices = split("\n", qx(hcitool dev));
    }
    
    foreach my $btDevLine (@btDevices) {
        if($btDevLine =~ /hci(.)/) {
            push(@{$hash->{helper}{hcidevices}}, $1);
        }
    }
    $hash->{helper}{currenthcidevice} = 0;
    readingsSingleUpdate($hash, "bluetoothDevice", "hci".$hash->{helper}{hcidevices}[$hash->{helper}{currenthcidevice}], 1);
    return undef;
}

sub GFPROBT_Attribute($$$$) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};
    
    if($cmd eq "set") {
        if( $attrName eq "blockingCallLoglevel" ) {
            $hash->{loglevel} = $attrVal;
            Log3 $name, 3, "GFPROBT ($name) - set blockingCallLoglevel to $attrVal";
        }
    
    } elsif($cmd eq "del") {
        if( $attrName eq "blockingCallLoglevel" ) {
            $hash->{loglevel} = 4;
            Log3 $name, 3, "GFPROBT ($name) - set blockingCallLoglevel to $attrVal";
        }
    }
    
    return undef;
}

sub GFPROBT_Set($@) {
    my ($hash, $name, @params) = @_;
    my $workType = shift(@params);
    my $list = "on off";

    # check parameters for set function
    if($workType eq "?") {
        return SetExtensions($hash, $list, $name, $workType, @params);
    }

    if($workType eq "on") {
        GFPROBT_setOn($hash);
    } elsif($workType eq "off") {
        GFPROBT_setOff($hash);
    } else {
        return SetExtensions($hash, $list, $name, $workType, @params);
    }
    
    return undef;
}

### resetErrorCounters ###
sub GFPROBT_setResetErrorCounters {
    my ($hash) = @_;
    
    foreach my $reading (keys %{ $hash->{READINGS} }) {
        if($reading =~ /errorCount-.*/) {
            readingsSingleUpdate($hash, $reading, 0, 1);
        }
    }

    return undef;
}

### updateStatus ###
sub GFPROBT_updateStatus {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $name."|".$hash->{MAC}."|updateStatus", "GFPROBT_processGatttoolResult", 300, "GFPROBT_updateStatusFailed", $hash);
}

sub GFPROBT_updateStatusSuccessful {
    my ($hash) = @_;
    InternalTimer(gettimeofday()+140+int(rand(60)), "GFPROBT_updateStatus", $hash, 0);
    return undef;
}

sub GFPROBT_updateStatusRetry {
    my ($hash) = @_;
    GFPROBT_updateStatus($hash);
    return undef;
}

sub GFPROBT_updateStatusFailed {
    my ($hash) = @_;
    InternalTimer(gettimeofday()+170+int(rand(60)), "GFPROBT_updateStatus", $hash, 0);
    return undef;
}

### setOn ###
sub GFPROBT_setOn {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    readingsSingleUpdate($hash, "state", "sending", 1);
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $name."|".$hash->{MAC}."|setOn", "GFPROBT_processGatttoolResult", 300, "GFPROBT_killGatttool", $hash);
    return undef;
}

sub GFPROBT_setOnSuccessful {
    my ($hash) = @_;
    return undef;
}

sub GFPROBT_setOnFailed {
    my ($hash) = @_;
    readingsSingleUpdate($hash, "state", "failed", 1);
    return undef;
}

sub GFPROBT_setOnRetry {
    my ($hash) = @_;
    GFPROBT_retryGatttool($hash, "setOn");
    return undef;
}

### setOff ###
sub GFPROBT_setOff {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    readingsSingleUpdate($hash, "state", "sending", 1);
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $name."|".$hash->{MAC}."|setOff", "GFPROBT_processGatttoolResult", 300, "GFPROBT_killGatttool", $hash);
    return undef;
}

sub GFPROBT_setOffSuccessful {
    my ($hash) = @_;
    
    return undef;
}

sub GFPROBT_setOffFailed {
    my ($hash) = @_;
    readingsSingleUpdate($hash, "state", "failed", 1);
    return undef;
}

sub GFPROBT_setOffRetry {
    my ($hash) = @_;
    GFPROBT_retryGatttool($hash, "setOff");
    return undef;
}

### Gatttool functions ###
sub GFPROBT_retryGatttool {
    my ($hash, $workType) = @_;
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $hash->{NAME}."|".$hash->{MAC}."|$workType", "GFPROBT_processGatttoolResult", 300, "GFPROBT_killGatttool", $hash);
    return undef;
}

sub GFPROBT_execGatttool($) {
    my ($string) = @_;
    my ($name, $mac, $workType) = split("\\|", $string);
    my $wait = 1;
    my $hash = $main::defs{$name};
    my $sshHost     = AttrVal($name,"sshHost","none");
    my $gatttool;   # = qx(which gatttool);
    my $ret = undef;
    my %json;
    my $retries = 0;
    
    $gatttool                               = qx(which gatttool) if($sshHost eq 'none');
    $gatttool                               = qx(ssh $sshHost 'which gatttool') if($sshHost ne 'none');
    chomp $gatttool;
    
    if(defined($gatttool) and ($gatttool)) {
        my $gtResult;
        my $cmd;
        my $hciDevice = "hci".$hash->{helper}{hcidevices}[$hash->{helper}{currenthcidevice}];
    
        $hash->{gattProc} = Expect->spawn('gatttool -b '.$hash->{MAC}.' -i '.$hciDevice. ' -I');
        $hash->{gattProc}->raw_pty(1);
        $hash->{gattProc}->log_stdout(0);
        
        while (!$ret and $retries < 10) {
            $hash->{gattProc}->send("connect\r");
            $ret = $hash->{gattProc}->expect(15, "Connection successful");
            if (!$ret) {
              sleep(3);
            }
            $retries += 1;
            if ($retries > 10) {
                $hash->{gattProc}->hard_close();
                return "$name|$mac|error|$workType|failed to connect";
            }
        }

        #write password
        $hash->{gattProc}->send("char-write-req 0x0048 313233343536\r");
        $hash->{gattProc}->expect(5, "Characteristic value was written successfully");
        #read current state
        $hash->{gattProc}->send("char-read-hnd 0x0015\r");
        $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
        if ($ret) {
          $json{'watering'} = GFPROBT_convertHexToInt($hash, $hash->{gattProc}->exp_after());
        }
        
        #read battery
        $hash->{gattProc}->send("char-read-hnd 0x0039\r");
        $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
        if ($ret) {
          $json{'batteryVoltage'} = GFPROBT_convertHexToIntReverse($hash, $hash->{gattProc}->exp_after(), 2);
          if ($json{'batteryVoltage'} > 3575) {
            $json{'battery'} = 100
          } else {
            $json{'battery'} = int(($json{'batteryVoltage'} - 2900) / 6.75);
          }
        }
        
        #read temperature
        $hash->{gattProc}->send("char-read-hnd 0x003b\r");
        $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
        if ($ret) {
          $json{'temperature'} = GFPROBT_convertHexToTemp($hash, $hash->{gattProc}->exp_after());
        }
        
        #read min temperature
        $hash->{gattProc}->send("char-read-hnd 0x003d\r");
        $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
        if ($ret) {
          $json{'min-temperature'} = GFPROBT_convertHexToTemp($hash, $hash->{gattProc}->exp_after());
        }
        
        #read max temperature
        $hash->{gattProc}->send("char-read-hnd 0x003f\r");
        $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
        if ($ret) {
          $json{'max-temperature'} = GFPROBT_convertHexToTemp($hash, $hash->{gattProc}->exp_after());
        }
        
        #read firmware version
        $hash->{gattProc}->send("char-read-hnd 0x004e\r");
        $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
        if ($ret) {
          $json{'firmware'} = GFPROBT_getFirmware($hash, $hash->{gattProc}->exp_after());
        }
        
        #read device name
        $hash->{gattProc}->send("char-read-hnd 0x0052\r");
        $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
        if ($ret) {
          $json{'devicename'} = GFPROBT_convertHexToString($hash, $hash->{gattProc}->exp_after());
        }
        
        #read timers
        foreach my $i ((1,2,3,4)) {
          $json{"timer".$i."-Start"} = "-";
          $json{"timer".$i."-Duration"} = "-";
          $json{"timer".$i."-Weekdays"} = "-";
        }
        my %timers;
        my @timerHnd = ("0x0017", "0x0019", "0x001b", "0x001d", "0x001f", "0x0021", "0x0023", "0x0025", "0x0027", "0x0029",
                        "0x002b", "0x002d", "0x002f", "0x0031");
        my $stop = 0;
        foreach my $hnd (@timerHnd) {
          if ($stop == 1) {
            last;
          }
          $hash->{gattProc}->send("char-read-hnd $hnd\r");
          $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
          if ($ret) {
            foreach my $i ((0,6)) {
              my @hexarr = GFPROBT_getHexOutput($hash, $hash->{gattProc}->exp_after());
              my @hexarr2 = @hexarr[$i,$i+1,$i+2,$i+3,$i+4,$i+5];
              my ($weekday, $hour, $minute, $duration) = GFPROBT_convertHexToTimer($hash, \@hexarr2);
              if (!defined($weekday)) {
                $stop = 1;
                last;
              }
              if (!exists($timers{$hour})) {
                $timers{$hour} = {
                  $minute => {
                      $duration => [$weekday]
                  }
                };
              } elsif (!exists($timers{$hour}{$minute})) {
                $timers{$hour}{$minute} = { $duration => [$weekday] };
              } elsif (!exists($timers{$hour}{$minute}{$duration})) {
                $timers{$hour}{$minute}{$duration} = [$weekday];
              } else {
                push(@{$timers{$hour}{$minute}{$duration}}, $weekday);
              }
            }
          }
        }
        my $timercnt = 1;
        foreach my $hour (keys %timers) {
          foreach my $minute (keys %{$timers{$hour}}) {
            foreach my $duration (keys %{$timers{$hour}{$minute}}) {
              $json{'timer'.$timercnt."-Start"} = sprintf("%02d:%02d", $hour, $minute);
              $json{'timer'.$timercnt."-Duration"} = int($duration/60);
              $json{'timer'.$timercnt."-Weekdays"} = join(",", @{$timers{$hour}{$minute}{$duration}});
              $timercnt += 1;
            }
          }
        }
        
        #write timers
        if ($workType eq "addTimer") {
            my $newhour;
            my $newminute;
            my $newduration;
            my @newweekdays;
            if ($timercnt > 4) {
                return "$name|$mac|error|$workType|limit of 4 timers reached, delete one timer first";
            }
            if (!exists($timers{$newhour})) {
                $timers{$newhour} = {
                  $newminute = {
                    $newduration => @newweekdays
                  }
                };
            } elsif (!exists($timers{$newhour})) {
                $timers{$newhour}{$newminute} = {
                  $newduration => @newweekdays
                };
            } elsif (!exists($timers{$newhour}{$newminute}{$newduration})) {
                $timers{$newhour}{$newminute}{$newduration} = @newweekdays;
            } else {
                push(@{$timers{$newhour}{$newminute}{$newduration}}, @newweekdays);
            }
            
            #writeOffset
            #commitCode
        }
        
        if (($json{'watering'} == 1 and $workType eq "setOff") or
            ($json{'watering'} == 0 and $workType eq "setOn")) {
            #switch on/off
            $hash->{gattProc}->send("char-write-req 0x0013 00\r");
            $hash->{gattProc}->expect(2, "Characteristic value was written successfully");
            $hash->{gattProc}->send("char-write-req 0x0013 01\r");
            $hash->{gattProc}->expect(2, "Characteristic value was written successfully");
            
            #read current state
            $hash->{gattProc}->send("char-read-hnd 0x0015\r");
            $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
            $json{'watering'} = GFPROBT_convertHexToInt($hash, $hash->{gattProc}->exp_after());
        }
        
        if ($json{'watering'} == 1) {
          $json{'state'} = 'on';
        } else {
          $json{'state'} = 'off';
        }
        
        $hash->{gattProc}->send("disconnect");
        $hash->{gattProc}->send("exit");
        $hash->{gattProc}->hard_close();
        
        my $jsonString = encode_json \%json;
        
        return "$name|$mac|ok|$workType|$jsonString";
    } else {
        return "$name|$mac|error|$workType|no gatttool binary found. Please check if bluez-package is properly installed";
    }
}

sub GFPROBT_getHexOutput($$) {
    my ($hash, $input) = @_;
    my $val;
    if ($input =~ /(.*)$/m) {
        $val = $1;
    }
    return split(" ", $val);
}

sub GFPROBT_getFirmware($$) {
    my ($hash, $input) = @_;
    my @hexarr = GFPROBT_getHexOutput($hash, $input);
    
    return hex("0x".$hexarr[1]).".".hex("0x".$hexarr[0]);
}

sub GFPROBT_convertHexToTimer($$) {
    my ($hash, $input) = @_;
    my @hexarr = @{$input};
    my $seconds = unpack "I", pack "H*", join("", @hexarr[0,1,2,3]);
    if ($seconds == 4294967295) {
      #FF FF FF FF
      return (undef, undef, undef, undef);
    }
    my @day = ("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su");
    my $weekday = $day[int($seconds/(3600*24))];
    my $hour = int(($seconds%(3600*24))/3600);
    my $minutes = int(($seconds%(3600*24) - $hour*3600) / 60);
    $seconds = $seconds%60;
    my $duration = unpack "I", pack "H*", join("", @hexarr[4,5])."0000";
    return ($weekday, $hour, $minutes, $duration);
}

sub GFPROBT_convertHexToTemp($$) {
    my ($hash, $input) = @_;
    my @hexarr = GFPROBT_getHexOutput($hash, $input);
    
    return hex("0x".$hexarr[0]) + hex("0x".$hexarr[1])/100;
}

sub GFPROBT_convertHexToString($$) {
    my ($hash, $input) = @_;
    my @hexarr = GFPROBT_getHexOutput($hash, $input);
    return Encode::encode('UTF-8', pack("H*", join("",@hexarr)));
}

sub GFPROBT_convertHexToInt($$) {
    my ($hash, $input) = @_;
    my $val;
    if ($input =~ /(.*)$/m) {
        $val = $1;
    }
    $val =~ s/\s//g;
    return hex("0x".$val);
}

sub GFPROBT_convertHexToIntReverse($$$) {
    my ($hash, $input, $length) = @_;
    my $val;
    if ($input =~ /(.*)$/m) {
        $val = $1;
    }
    $val =~ s/\s//g;
    for (;$length <= 4; $length++) {
      $val = $val."0";
    }
    $val = unpack "I", pack "H*", $val;
    return $val;
}

sub GFPROBT_processGatttoolResult($) {
    my ($string) = @_;
    
    return unless(defined($string));
    
    my @a = split("\\|", $string);
    my $name = $a[0];
    my $hash = $defs{$name};
    
    Log3 $hash, 3, "GFPROBT ($name): gatttool return string: $string";
    
    my $mac = $a[1];
    my $ret = $a[2];
    my $workType = $a[3];
    my $json = $a[4];
    
    delete($hash->{helper}{RUNNING_PID});
    
    if($ret eq "ok") {
        #process notification
        if(defined($json)) {
            GFPROBT_processJson($hash, $json);
        }
        #if($workType =~ /set.*/) {
        #    readingsSingleUpdate($hash, "lastChangeBy", "FHEM", 1);
        #}
        #call WorkTypeSuccessful function
        my $call = "GFPROBT_".$workType."Successful";
        no strict "refs";
        eval {
            &{$call}($hash);
        };
        use strict "refs";
        RemoveInternalTimer($hash, "GFPROBT_".$workType."Retry");
        $hash->{helper}{"retryCounter$workType"} = 0;
    } else {
        $hash->{helper}{"retryCounter$workType"} = 0 if(!defined($hash->{helper}{"retryCounter$workType"}));
        $hash->{helper}{"retryCounter$workType"}++;
        Log3 $hash, 4, "GFPROBT ($name): $workType failed ($json)";
        if ($hash->{helper}{"retryCounter$workType"} > AttrVal($name, "maxRetries", 20)) {
            my $errorCount = ReadingsVal($hash->{NAME}, "errorCount-$workType", 0);
            readingsSingleUpdate($hash, "errorCount-$workType", $errorCount+1, 1);
            Log3 $hash, 3, "GFPROBT ($name): $workType, failed 20 times.";
            $hash->{helper}{"retryCounter$workType"} = 0;
            $hash->{helper}{"retryCounterHci".$hash->{helper}{currenthcidevice}} = 0;
            #call WorkTypeFailed function
            my $call = "GFPROBT_".$workType."Failed";
            no strict "refs";
            eval {
                &{$call}($hash);
            };
            use strict "refs";
            
            #update hci devicelist
            GFPROBT_updateHciDevicelist($hash);
        } else {
            $hash->{helper}{"retryCounterHci".$hash->{helper}{currenthcidevice}} = 0 if(!defined($hash->{helper}{"retryCounterHci".$hash->{helper}{currenthcidevice}}));
            $hash->{helper}{"retryCounterHci".$hash->{helper}{currenthcidevice}}++;
            if ($hash->{helper}{"retryCounterHci".$hash->{helper}{currenthcidevice}} > 7) {
                #reset error counter
                $hash->{helper}{"retryCounterHci".$hash->{helper}{currenthcidevice}} = 0;
                #use next hci device next time
                $hash->{helper}{currenthcidevice} += 1;
                my $maxHciDevices = @{ $hash->{helper}{hcidevices} } - 1;
                if($hash->{helper}{currenthcidevice} > $maxHciDevices) {
                    $hash->{helper}{currenthcidevice} = 0;
                }
                #update reading
                readingsSingleUpdate($hash, "bluetoothDevice", "hci".$hash->{helper}{hcidevices}[$hash->{helper}{currenthcidevice}], 1);
            }
            InternalTimer(gettimeofday()+3+int(rand(5)), "GFPROBT_".$workType."Retry", $hash, 0);
        }
    }
    
    return undef;
}

sub GFPROBT_processJson {
    my ($hash, $json) = @_;
    my $dataref = decode_json($json);
    my %data = %$dataref;
    
    foreach my $reading (keys %data) {
      readingsSingleUpdate($hash, $reading, $data{$reading}, 1);
    }

    return undef;
}

sub GFPROBT_readingsSingleUpdateIfChanged {
  my ($hash, $reading, $value, $setLastChange) = @_;
  my $curVal = ReadingsVal($hash->{NAME}, $reading, "");
  
  if($curVal ne $value) {
      readingsSingleUpdate($hash, $reading, $value, 1);
      if(defined($setLastChange)) {
          readingsSingleUpdate($hash, "lastChangeBy", "Thermostat", 1);
      }
  }
}

sub GFPROBT_killGatttool($) {

}

sub GFPROBT_Undef($) {
    my ($hash) = @_;

    #remove internal timer
    RemoveInternalTimer($hash);

    return undef;
}

sub GFPROBT_Get($$) {
    return undef;
}

1;

=pod
=item device
=item summary Control G.F.Pro Bluetooth Eco Watering
=item summary_DE Steuerung der G.F.Pro Bluetooth Eco Watering Bew&auml;sserung
=begin html

<a name="GFPROBT"></a>
<h3>GFPROBT</h3>
<ul>
  GFPROBT is used to control a G.F.Pro Bluetooth Eco Watering irrigation control<br><br>
		
  <br>
  <b>Required packages</b>
  <br>
  sudo apt install libio-tty-perl bluez
  <br>
  sudo cpanm install Expect
  <br>
  <br>
  <b>Note:</b> GFPro LED must blink during define! Please check if gatttool executable is available on your system.
	<br>
  <br>
  <a name="GFPROBTdefine" id="GFPROBTdefine"></a>
    <b>Define</b>
  <ul>
    <code>define &lt;name&gt; GFPROBT &lt;mac address&gt;</code><br>
    <br>
    Example:
    <ul>
      Remove battery and insert it again<br>
      Check if LED is blinking<br>
      <code>define watering GFPROBT 00:33:44:33:22:11</code><br>
    </ul>
  </ul>
  
  <br>

  <a name="GFPROBTset" id="GFPROBTset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
               The following commands are defined:<br><br>
        <ul>
          <li><code><b>on</b> </code> &nbsp;&nbsp;-&nbsp;&nbsp; switch on watering</li>
          <li><code><b>off</b> </code> &nbsp;&nbsp;-&nbsp;&nbsp; switch off watering</li>
        </ul>
    <br>
    </ul>
          
    <a name="GFPROBTget" id="GFPROBTget"></a>
       <b>Get</b>
         <ul>
           <code>n/a</code>
        </ul>
        <br>
        
    <!--<a name="GFPROBTattr" id="GFPROBTattr"></a>
        <b>attr</b>
        <ul>
            <li>sshHost - FQD-Name or IP of ssh remote system / you must configure your ssh system for certificate authentication. For better handling you can config ssh Client with .ssh/config file</li>
        </ul>
    <br>-->

</ul>

=end html
=cut
