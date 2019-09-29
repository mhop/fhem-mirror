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
use Time::Piece;

sub GFPROBT_Initialize($) {
    my ($hash) = @_;

    $hash->{parseParams} = 1;

    $hash->{DefFn}    = 'GFPROBT_Define';
    $hash->{UndefFn}  = 'GFPROBT_Undef';
    $hash->{GetFn}    = 'GFPROBT_Get';
    $hash->{SetFn}    = 'GFPROBT_Set';
    $hash->{AttrFn}   = 'GFPROBT_Attribute';
    $hash->{AttrList}  = 'blockingCallLoglevel '.
                            $readingFnAttributes;
    
    return undef;
}

sub GFPROBT_Define($$$) {
    #save BTMAC address
    my ($hash, $a, $h) = @_;
    my $name = shift @$a;
    my $type = shift @$a;
    my $mac;
    my $sshHost;
    
    $hash->{NAME} = $name;
    $hash->{STATE} = "initialized";
    $hash->{VERSION} = "2.0.0";
    $hash->{loglevel} = 4;
    Log3 $hash, 3, "GFPROBT: G.F.Pro Eco Watering Bluetooth ".$hash->{VERSION};
    
    if (int(@{$a}) > 2) {
        return 'GFPROBT: Wrong syntax, must be define <name> GFPROBT <mac address>';
    } elsif(int(@{$a}) == 1) {
        $mac = shift @$a;
        $hash->{MAC} = $mac;
    } elsif(int(@{$a}) == 2) {
        $mac = shift @$a;
        $hash->{MAC} = $mac;
        $attr{$name}{sshHost} = shift @$a;
    }
    
    $hash->{helper}{currenthcidevice} = -1;
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
    $hash->{helper}{currenthcidevice} += 1;
    if ($hash->{helper}{currenthcidevice} >= int(@{$hash->{helper}{hcidevices}})) {
      $hash->{helper}{currenthcidevice} = 0;
    }
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

sub GFPROBT_Set($$$) {
    my ($hash, $a, $h) = @_;
    my $name = shift @$a;
    my $workType = shift @$a;
    my $list = "on off devicename addTimer deleteTimer editTimer eco adjust";

    # check parameters for set function
    if($workType eq "?") {
        return SetExtensions($hash, $list, $name, $workType, $a);
    }

    if($workType eq "on") {
        if (int(@$a) == 0) {
          GFPROBT_setOn($hash);
        } else {
          GFPROBT_setOnSeconds($hash, $a);
        }
    } elsif($workType eq "off") {
        GFPROBT_setOff($hash);
    } elsif($workType eq "devicename") {
        GFPROBT_setDevicename($hash, $a);
    } elsif($workType eq "addTimer") {
        GFPROBT_addTimer($hash, $h);
    } elsif($workType eq "deleteTimer") {
        GFPROBT_deleteTimer($hash, $a);
    } elsif($workType eq "editTimer") {
        GFPROBT_editTimer($hash, $h);
    } elsif($workType eq "adjust") {
        GFPROBT_setAdjust($hash, $a);
    } else {
        return SetExtensions($hash, $list, $name, $workType, $a);
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

### addTimer ###
sub GFPROBT_addTimer {
    my ($hash, $h) = @_;
    my $name = $hash->{NAME};
    readingsSingleUpdate($hash, "state", "sending", 1);
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $name."|".$hash->{MAC}."|addTimer|".$h->{'start'}."|".$h->{'duration'}."|".$h->{'weekdays'}, "GFPROBT_processGatttoolResult", 300, "GFPROBT_killGatttool", $hash);
    return undef;
}

### editTimer ###
sub GFPROBT_editTimer {
    my ($hash, $h) = @_;
    my $name = $hash->{NAME};
    readingsSingleUpdate($hash, "state", "sending", 1);
    
    if (!defined($h->{'timer'})) {
      $h->{'timer'} = "all";
    }
    if (!defined($h->{'start'})) {
      $h->{'start'} = "-:-";
    }
    if (!defined($h->{'duration'})) {
      $h->{'duration'} = "-";
    }
    if (!defined($h->{'weekdays'})) {
      $h->{'weekdays'} = "-";
    }
    
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $name."|".$hash->{MAC}."|editTimer|".$h->{'timer'}."|".$h->{'start'}."|".$h->{'duration'}."|".$h->{'weekdays'}, "GFPROBT_processGatttoolResult", 300, "GFPROBT_killGatttool", $hash);
    return undef;
}

### deleteTimer ###
sub GFPROBT_deleteTimer {
    my ($hash, $opt) = @_;
    my $name = $hash->{NAME};
    my $timerNr = shift(@$opt);
    readingsSingleUpdate($hash, "state", "sending", 1);
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $name."|".$hash->{MAC}."|deleteTimer|".$timerNr, "GFPROBT_processGatttoolResult", 300, "GFPROBT_killGatttool", $hash);
    return undef;
}

### deleteOnTimer ###
sub GFPROBT_deleteOnTimer {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $timer = $hash->{'deleteOnTimer'};
    delete($hash->{'deleteOnTimer'});
    readingsSingleUpdate($hash, "state", "sending", 1);
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $name."|".$hash->{MAC}."|deleteOnTimer|".$timer->{'hour'}."|".$timer->{'minute'}."|".$timer->{'duration'}, "GFPROBT_processGatttoolResult", 300, "GFPROBT_killGatttool", $hash);
    return undef;
}

### setAdjust ###
sub GFPROBT_setAdjust {
    my ($hash, $opt) = @_;
    my $name = $hash->{NAME};
    my $perc = shift(@$opt);
    my $days = shift(@$opt);
    readingsSingleUpdate($hash, "state", "sending", 1);
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $name."|".$hash->{MAC}."|setAdjust|".$perc."|".$days, "GFPROBT_processGatttoolResult", 300, "GFPROBT_killGatttool", $hash);
    return undef;
}

### setDevicename ###
sub GFPROBT_setDevicename {
    my ($hash, $param) = @_;
    my $name = $hash->{NAME};
    readingsSingleUpdate($hash, "state", "sending", 1);
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $name."|".$hash->{MAC}."|setDevicename|".@$param[0], "GFPROBT_processGatttoolResult", 300, "GFPROBT_killGatttool", $hash);
    return undef;
}

sub GFPROBT_setDevicenameSuccessful {
    my ($hash) = @_;
    return undef;
}

sub GFPROBT_setDevicenameFailed {
    my ($hash) = @_;
    readingsSingleUpdate($hash, "state", "failed", 1);
    return undef;
}

### setOnSeconds ###
sub GFPROBT_setOnSeconds {
    my ($hash, $opt) = @_;
    my $onseconds = shift @$opt;
    my $name = $hash->{NAME};
    readingsSingleUpdate($hash, "state", "sending", 1);
    $hash->{helper}{RUNNING_PID} = BlockingCall("GFPROBT_execGatttool", $name."|".$hash->{MAC}."|setOnSeconds|$onseconds", "GFPROBT_processGatttoolResult", 300, "GFPROBT_killGatttool", $hash);
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

### Gatttool functions ###
sub GFPROBT_execGatttool($) {
    my ($string) = @_;
    my ($name, $mac, $workType, @params) = split("\\|", $string);
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
        #$hash->{gattProc}->log_stdout(0);
        
        while (!$ret and $retries < 10) {
            $hash->{gattProc}->send("connect\r");
            $ret = $hash->{gattProc}->expect(15, "Connection successful");
            if (!$ret) {
              sleep(3);
            }
            $retries += 1;
            if (!$ret and $retries > 9) {
                $hash->{gattProc}->hard_close();
                return "$name|$mac|error|$workType|failed to connect";
            }
        }

        #write password
        $hash->{gattProc}->send("char-write-req 0x0048 313233343536\r");
        $hash->{gattProc}->expect(5, "Characteristic value was written successfully");
        
        #read watering
        $hash->{gattProc}->send("char-read-hnd 0x0015\r");
        $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
        if ($ret) {
          $json{'watering'} = GFPROBT_convertHexToInt($hash, $hash->{gattProc}->exp_after());
        
          #read battery
          $hash->{gattProc}->send("char-read-hnd 0x0039\r");
          $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
          if ($ret) {
            $json{'batteryVoltage'} = GFPROBT_convertHexToIntReverse($hash, $hash->{gattProc}->exp_after());
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
          
          #read complete status
          #$hash->{gattProc}->send("char-read-hnd 0x0050\r");
          #$ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
          #if ($ret) {
          #  $json{'status'} = GFPROBT_getHexString($hash, $hash->{gattProc}->exp_after());
          #}
          
          #read ECO1
          #$hash->{gattProc}->send("char-read-hnd 0x0033\r");
          #$ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
          #if ($ret) {
          #  $json{'eco'} = GFPROBT_getHexString($hash, $hash->{gattProc}->exp_after());
          #}
          
          #read ECO2
          #$hash->{gattProc}->send("char-read-hnd 0x0045\r");
          #$ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
          #if ($ret) {
          #  $json{'eco'} .= " ".GFPROBT_getHexString($hash, $hash->{gattProc}->exp_after());
          #}
          
          #read time offset
          $hash->{gattProc}->send("char-read-hnd 0x0035\r");
          $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
          if ($ret) {
            my @hexarr = GFPROBT_getHexOutput($hash, $hash->{gattProc}->exp_after());
            $json{'deviceTime'} = GFPROBT_convertHexArrToSeconds($hash, \@hexarr);
          }
          
          #read MAC
          $hash->{gattProc}->send("char-read-hnd 0x004a\r");
          $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
          if ($ret) {
            my @mac = GFPROBT_getHexOutput($hash, $hash->{gattProc}->exp_after());;
            $json{'mac'} = join(":", reverse(@mac));
          }
          
          #read timers
          my %timers;
          $hash->{'timerHnd'} = ["0x0017", "0x0019", "0x001b", "0x001d", "0x001f", "0x0021", "0x0023", "0x0031", "0x0025", "0x0027", "0x0029",
                          "0x002b", "0x002d", "0x002f"];
          my $stop = 0;
          my $storageCnt = 0;
          foreach my $hnd (@{$hash->{'timerHnd'}}) {
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
                $storageCnt += 1;
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
          
          #write timers
          if ($workType eq "addTimer") {
            if ($storageCnt >= 28) {
                #check timer storage (28max)
                return "$name|$mac|error|$workType|max of 28 single timers reached";
            }
            my $newhour = (split(":", $params[0]))[0];
            my $newminute = (split(":", $params[0]))[1];
            my $newduration = $params[1];
            my @newweekdays = ();
            if (!defined($params[2])) {
              @newweekdays = ("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su");
            } else {
              @newweekdays = split(",", $params[2])
            }
            my %newtime = (hour=>$newhour, minute=>$newminute, duration=>$newduration, weekdays=>\@newweekdays);
            GFPROBT_addTimerToTimers($hash, \%timers, \%newtime);
            
            GFPROBT_saveTimers($hash, \%timers);
            
          } elsif ($workType eq "editTimer") {
            my $timernr = $params[0]; #nr or all
            my $paramhour = (split(":", $params[1]))[0]; #hour or - if no change
            my $paramminute = (split(":", $params[1]))[1]; #minute or - if no change
            my $paramduration = $params[2]; #duration or - if no change
            my @paramweekdays = split(",", $params[3]); #weekdays or - if no change
            
            my @nrArr = split(",", $timernr);
            if ($params[0] eq "all") {
              @nrArr = (1..28);
            }
            foreach my $i (@nrArr) {
              my $delTime = ReadingsVal($hash->{NAME}, "timer".$i."-Start", 0);
              if ($delTime eq "0") {
                last;
              }
              my $delHour = int((split(":", $delTime))[0]);
              my $delMin = int((split(":", $delTime))[1]);
              my $delDur = ReadingsVal($hash->{NAME}, "timer".$i."-Duration", 0);
              my $delWeekdays = ReadingsVal($hash->{NAME}, "timer".$i."-Weekdays", "Mo,Tu,We,Th,Fr,Sa,Su");
              my $newhour = 0;
              my $newminute = 0;
              my $newduration = 0;
              my @newweekdays = ();
              
              if ($paramhour eq "-") {
                $newhour = $delHour;
              } else {
                $newhour = $paramhour;
              }
              if ($paramminute eq "-") {
                $newminute = $delMin;
              } else {
                $newminute = $paramminute;
              }
              if ($paramduration eq "-") {
                $newduration = $delDur;
              } else {
                $newduration= $paramduration;
              }
              if ($paramweekdays[0] eq "-") {
                @newweekdays = split(",", $delWeekdays);
              } else {
                @newweekdays = @paramweekdays;
              }
              delete($timers{$delHour}{$delMin}{$delDur});
              my %newtime = (hour=>$newhour, minute=>$newminute, duration=>$newduration, weekdays=>\@newweekdays);
              GFPROBT_addTimerToTimers($hash, \%timers, \%newtime);
            }
            
            GFPROBT_saveTimers($hash, \%timers);
          } elsif ($workType eq "deleteTimer") {
            my @nrArr = split(",", $params[0]);
            if ($params[0] eq "all") {
              @nrArr = (1..28);
            }
            foreach my $i (@nrArr) {
              my $delTime = ReadingsVal($hash->{NAME}, "timer".$i."-Start", 0);
              if ($delTime eq "0") {
                last;
              }
              my $delHour = int((split(":", $delTime))[0]);
              my $delMin = int((split(":", $delTime))[1]);
              my $delDur = ReadingsVal($hash->{NAME}, "timer".$i."-Duration", 0);
              delete($timers{$delHour}{$delMin}{$delDur});
            }
            
            
            GFPROBT_saveTimers($hash, \%timers);
          } elsif ($workType eq "deleteOnTimer") {
            my $delHour = int($params[0]);
            my $delMin = int($params[1]);
            my $delDur = $params[2];
            delete($timers{$delHour}{$delMin}{$delDur});
            
            GFPROBT_saveTimers($hash, \%timers);
          } elsif ($workType eq "setEco") {
            #localtime->week
            
          } elsif ($workType eq "setAdjust") {
            my $percHex = GFPROBT_convertIntToHexReverse($hash, $params[0]);
            my $daysHex = GFPROBT_convertIntToHexReverse($hash, $params[1]*86400);
            $percHex = substr($percHex, 0, 4);
            my $hex = $daysHex.$percHex;

            $hash->{gattProc}->send("char-write-req 0x0043 $hex\r");
            $hash->{gattProc}->expect(2, "Characteristic value was written successfully");

            GFPROBT_commitCode($hash);
            
          } elsif ($workType eq "setOnSeconds") {
            if ($storageCnt >= 28) {
                #check timer storage (28max)
                return "$name|$mac|error|$workType|max of 28 single timers reached";
            }
            my $onseconds = $params[0];
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
            my @day = ("Su", "Mo", "Tu", "We", "Th", "Fr", "Sa");
            #onseconds+1 to reduce the chance of duplicate timers
            my @onwday = ($day[$wday]);
            my %newtime = (hour=>$hour, minute=>$min, duration=>$sec+$onseconds+1, weekdays=>\@onwday);
            GFPROBT_addTimerToTimers($hash, \%timers, \%newtime);
            
            GFPROBT_saveTimers($hash, \%timers);
            
            #delete timer when finished (call function after $duration+3 min)
            $json{'DATA'} = {
              'deleteOnTimer' => {
                'hour' => $hour,
                'minute' => $min,
                'duration' => $sec+$onseconds+1
              }
            };
          } elsif ($workType eq "setDevicename") {
            my $devname = $params[0];
            for (my $i=length($devname); $i<20; $i++) {
              $devname .= " ";
            }
            my $devnameHex = GFPROBT_convertStringToHex($hash, $devname);
            $hash->{gattProc}->send("char-write-req 0x0052 $devnameHex\r");
            $hash->{gattProc}->expect(2, "Characteristic value was written successfully");
          } elsif ($workType eq "setOff" or $workType eq "setOn") {
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
          }
          
          #read timers again
          %timers = ();
          $stop = 0;
          $storageCnt = 0;
          foreach my $hnd (@{$hash->{'timerHnd'}}) {
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
                $storageCnt += 1;
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
          foreach my $hour (sort { $a <=> $b } keys %timers) {
            foreach my $minute (sort { $a <=> $b } keys %{$timers{$hour}}) {
              foreach my $duration (sort { $a <=> $b } keys %{$timers{$hour}{$minute}}) {
                $json{'timer'.$timercnt."-Start"} = sprintf("%02d:%02d", $hour, $minute);
                $json{'timer'.$timercnt."-Duration"} = int($duration);
                $json{'timer'.$timercnt."-Weekdays"} = join(",", @{$timers{$hour}{$minute}{$duration}});
                $timercnt += 1;
              }
            }
          }
          
          #read increase/reduce
          $hash->{gattProc}->send("char-read-hnd 0x0043\r");
          $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
          if ($ret) {
            my @hexarr = GFPROBT_getHexOutput($hash, $hash->{gattProc}->exp_after());
            my @hextime = @hexarr[0,1,2,3];
            my @hexpercentage = @hexarr[4,5];
            my $perc = GFPROBT_convertHexArrToIntReverse($hash, \@hexpercentage);
            if ($perc > 65536/2) {
              $perc -= 65536;
            }
            $json{'adjustPercentage'} = $perc;
            if ($json{'adjustPercentage'} !=0 ) {
              my $seconds = GFPROBT_convertHexArrToSeconds($hash, \@hextime);
              my $till = time() + $seconds;
              $json{'adjustTill'} = sprintf("%s", scalar localtime($till));
            } else {
              $json{'adjustTill'} = "-";
            }
          }
          
          #re-read watering
          $hash->{gattProc}->send("char-read-hnd 0x0015\r");
          $ret = $hash->{gattProc}->expect(2, "Characteristic value/descriptor: ");
          if ($ret) {
            $json{'watering'} = GFPROBT_convertHexToInt($hash, $hash->{gattProc}->exp_after());
          }
          
          if ($json{'watering'} == 1) {
            $json{'state'} = 'on';
          } else {
            $json{'state'} = 'off';
          }
          
          $hash->{gattProc}->send("disconnect\r");
          $hash->{gattProc}->send("exit\r");
        }

        $hash->{gattProc}->hard_close();
        
        my $jsonString = encode_json \%json;
        
        return "$name|$mac|ok|$workType|$jsonString";
    } else {
        return "$name|$mac|error|$workType|no gatttool binary found. Please check if bluez-package is properly installed";
    }
}

sub GFPROBT_saveTimers($$) {
    my ($hash, $timers) = @_;
    
    #writeTimers
    GFPROBT_writeTimers($hash, $timers);
    
    #writeOffset
    GFPROBT_writeOffset($hash);
    
    #commitCode
    GFPROBT_commitCode($hash);
    
    #write statusbyte
    #GFPROBT_writeStatusByte($hash);
}

sub GFPROBT_writeTimers($$) {
    my ($hash, $timers) = @_;
    
    my %dayToNr = (
      'Mo' => 0,
      'Tu' => 1,
      'We' => 2,
      'Th' => 3,
      'Fr' => 4,
      'Sa' => 5,
      'Su' => 6
    );
    my %startDuration;
    my @startTime;
    foreach my $hour (sort keys %{$timers}) {
      foreach my $minute (sort keys %{$timers->{$hour}}) {
        foreach my $duration (sort keys %{$timers->{$hour}{$minute}}) {
          foreach my $day (@{$timers->{$hour}{$minute}{$duration}}) {
            my $startT = $dayToNr{$day}*3600*24+$hour*3600+$minute*60;
            $startDuration{$startT} = $duration;
            push(@startTime, $startT);
          }
        }
      }
    }
    
    @startTime = sort { $a <=> $b } @startTime;
    
    my @timerPairs = ();
    my $hexString = "";
    foreach my $startT (@startTime) {
      #calculate seconds and convert to hex
      my $secFromMondayHex = GFPROBT_convertIntToHexReverse($hash, $startT);
      #add duration
      my $durationHex = GFPROBT_convertIntToHexReverse($hash, $startDuration{$startT});
      $durationHex = substr($durationHex, 0, 4);
      $hexString .= $secFromMondayHex.$durationHex;
      if (length($hexString) > 12) {
        push(@timerPairs, $hexString);
        Log3 $hash, 3, "Hex: ".$hexString;
        $hexString = "";
      }
    }
    
    if (length($hexString) > 0) {
      $hexString .= "ffffffff0000";
      push(@timerPairs, $hexString);
    }
    
    #write other timer HNDs FF FF FF FF 00 00
    for (my $i=@timerPairs; $i<14; $i++) {
      push(@timerPairs, "ffffffff0000ffffffff0000");
    }
    
    #write 2 timers to 1 HND
    my $i = 0;
    foreach my $timer(@timerPairs) {
      my $hnd = @{$hash->{'timerHnd'}}[$i];
      $hash->{gattProc}->send("char-write-req $hnd $timer\r");
      $hash->{gattProc}->expect(3, "Characteristic value was written successfully");
      $i += 1;
    }
}

sub GFPROBT_addTimerToTimers($$$) {
    my ($hash, $timers, $newtimer) = @_;
    
    if (!exists($timers->{$newtimer->{'hour'}})) {
        $timers->{$newtimer->{'hour'}} = {
          $newtimer->{'minute'} => {
            $newtimer->{'duration'} => $newtimer->{'weekdays'}
          }
        };
    } elsif (!exists($timers->{$newtimer->{'hour'}}{$newtimer->{'minute'}})) {
        $timers->{$newtimer->{'hour'}}{$newtimer->{'minute'}} = {
          $newtimer->{'duration'} => $newtimer->{'weekdays'}
        };
    } elsif (!exists($timers->{$newtimer->{'hour'}}{$newtimer->{'minute'}}{$newtimer->{'duration'}})) {
        $timers->{$newtimer->{'hour'}}{$newtimer->{'minute'}}{$newtimer->{'duration'}} = $newtimer->{'weekdays'};
    } else {
        push(@{$timers->{$newtimer->{'hour'}}{$newtimer->{'minute'}}{$newtimer->{'duration'}}}, $newtimer->{'weekdays'});
    }
}

sub GFPROBT_writeOffset($) {
    my ($hash) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    $wday -= 1;
    if ($wday < 0) {
      $wday = 6;
    }
    my $secFromMonday = $wday*3600*24 +  $hour*3600 + $min*60 + $sec;
    my $secFromMondayHex = GFPROBT_convertIntToHexReverse($hash, $secFromMonday);
    $hash->{gattProc}->send("char-write-req 0x0035 $secFromMondayHex\r");
    $hash->{gattProc}->expect(10, "Characteristic value was written successfully");
}

sub GFPROBT_commitCode($) {
    my ($hash) = @_;
    $hash->{gattProc}->send("char-write-req 0x0037 00\r");
    $hash->{gattProc}->expect(5, "Characteristic value was written successfully");
    $hash->{gattProc}->send("char-write-req 0x0037 01\r");
    $hash->{gattProc}->expect(5, "Characteristic value was written successfully");
}

sub GFPROBT_writeStatusByte($) {
    my ($hash) = @_;
    $hash->{gattProc}->send("char-write-req 0x0050 0000000000000000000000000000000000000000\r");
    $hash->{gattProc}->expect(5, "Characteristic value was written successfully");
}

sub GFPROBT_convertIntToHexReverse($$) {
    my ($hash, $input) = @_;
    return unpack "H*", pack "I", $input;
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

sub GFPROBT_getHexString($$) {
    my ($hash, $input) = @_;
    my @hexarr = GFPROBT_getHexOutput($hash, $input);
    
    return join(" ", @hexarr);
}

sub GFPROBT_convertHexToTimer($$) {
    my ($hash, $input) = @_;
    my @hexarr = @{$input};
    my @hextime = @hexarr[0,1,2,3];
    my $seconds = GFPROBT_convertHexArrToSeconds($hash, \@hextime);
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

sub GFPROBT_convertHexArrToSeconds($$) {
    my ($hash, $input) = @_;
    my @hexarr = @{$input};
    my $seconds = unpack "I", pack "H*", join("", @hexarr);
    return $seconds;
}

sub GFPROBT_convertHexToTemp($$) {
    my ($hash, $input) = @_;
    my @hexarr = GFPROBT_getHexOutput($hash, $input);
    
    return hex("0x".$hexarr[0]) + hex("0x".$hexarr[1])/100;
}

sub GFPROBT_convertStringToHex($$) {
    my ($hash, $input) = @_;
    return unpack "H*", $input;
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

sub GFPROBT_convertHexArrToIntReverse($$) {
    my ($hash, $input) = @_;
    my @hexarr = @{$input};

    for (my $length=@hexarr; $length<4; $length++) {
        push @hexarr, "00";
    }

    return unpack "I", pack "H*", join("",@hexarr);
}

sub GFPROBT_convertHexToIntReverse($$) {
    my ($hash, $input) = @_;
    my $val;
    if ($input =~ /(.*)$/m) {
        $val = $1;
    }
    $val =~ s/\s//g;
    for (my $length = length($val); $length < 8; $length++) {
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
    } else {
        #call WorkTypeFailed function
        readingsSingleUpdate($hash, 'errorCount-'.$workType, ReadingsVal($hash->{NAME}, 'errorCount-'.$workType, 0) + 1, 1);
        my $call = "GFPROBT_".$workType."Failed";
        no strict "refs";
        eval {
            &{$call}($hash);
        };
        use strict "refs";
        
        #update hci devicelist
        GFPROBT_updateHciDevicelist($hash);
    }
    
    return undef;
}

sub GFPROBT_processJson {
    my ($hash, $json) = @_;
    my $dataref = decode_json($json);
    my %data = %$dataref;
    
    readingsBeginUpdate($hash);
    foreach my $i (1..28) {
      readingsDelete($hash, "timer".$i."-Start");
      readingsDelete($hash, "timer".$i."-Duration");
      readingsDelete($hash, "timer".$i."-Weekdays");
    }
    foreach my $reading (keys %data) {
      if ($reading ne "DATA") {
        readingsBulkUpdate($hash, $reading, $data{$reading});
      }
    }
    readingsEndUpdate($hash, 1);
    
    #start timer for timer deletion
    if (defined($data{"DATA"})) {
      if (defined($data{"DATA"}{"deleteOnTimer"})) {
        $hash->{'deleteOnTimer'} = $data{"DATA"}{"deleteOnTimer"};
        InternalTimer(gettimeofday()+$data{"DATA"}{"deleteOnTimer"}{"duration"}+10, "GFPROBT_deleteOnTimer", $hash, 0);
      }
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
  sudo cpanm Expect DateTime
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
          <li><code><b>on</b> </code> &nbsp;&nbsp;[seconds]&nbsp;&nbsp; switch on watering, optional for X seconds</li>
          <li><code><b>off</b> </code> &nbsp;&nbsp;-&nbsp;&nbsp; switch off watering</li>
          <li><code><b>addTimer</b> </code> &nbsp;&nbsp;duration=300 start=8:00 weekdays=Mo,Tu,We,Th,Fr,Sa,Su&nbsp;&nbsp; add timer with duration in seconds, starttime and weekdays (default all weekdays)</li>
          <li><code><b>editTimer</b> </code> &nbsp;&nbsp;timer=1 duration=300 start=8:00 weekdays=Mo,Fr&nbsp;&nbsp; update timer 1 to duration, start, weekdays. Parameters not provided will remain unchanged</li>
          <li><code><b>deleteTimer</b> </code> &nbsp;&nbsp;number or all&nbsp;&nbsp; delete one, more or all timers</li>
          <li><code><b>adjust</b> </code> &nbsp;&nbsp;percentage days&nbsp;&nbsp; adjust percentage for x days</li>
          <li><code><b>devicename</b> </code> &nbsp;&nbsp;name&nbsp;&nbsp; set devicename</li>
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
