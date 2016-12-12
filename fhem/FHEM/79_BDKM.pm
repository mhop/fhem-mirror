# $Id$
##############################################################################
#
#     79_BDKM.pm
#
#     This file is part of FHEM.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     BDKM is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with FHEM.  If not, see <http://www.gnu.org/licenses/>.
#
#     Written by Arno Augustin
##############################################################################

package main;

use strict;
use POSIX;
use warnings;
#use Blocking;
#use HttpUtils;
use Encode;
use JSON;
use Time::HiRes qw(gettimeofday);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use base qw( Exporter );
use MIME::Base64;
use LWP::UserAgent;
use Crypt::Rijndael;


my @BaseDirs = qw(
    /
    /dhwCircuits
    /gateway
    /heatingCircuits
    /heatSources
    /notifications
    /recordings
    /solarCircuits
    /system
);
#@BaseDirs = qw(/system/sensors/temperatures /dhwCircuits);

my %WdToNum = qw(Mo 1 Tu 2 We 3 Th 4 Fr 5 Sa 6 Su 7);



my @RC300DEFAULTS = 

# ID:POLL EVERY x CYCLE:MINDELTA:READINGNAME
# all gateway IDs are polled (gathered) once on startup
#*:1:0:*   poll every cycle, difference 0 => update on difference 0 (allways)
#*:1::*    poll every cycle, no difference set => update on change only
#*:0::*    poll on startup only and update reading on change only
#*:1:0.5:* poll every cycle, difference set to 0.5 => update only if difference to last read is >= 0.5
#*:15::*   poll on startup and every 15th cylce, update reading if changed
#*:::*     update reading on (get/set) only if value changed
#*::0:*    update reading on (get/set) always
#*         ID only, no ":", poll every cycle, update reading allways (same as *:1:0:*)

qw(/dhwCircuits/dhw1/actualTemp:1:0.2:WaterTemp
   /dhwCircuits/dhw1/currentSetpoint:1::WaterDesiredTemp
   /dhwCircuits/dhw1/operationMode:1::WaterMode 
   /dhwCircuits/dhw1/status:0::WaterStatus
   /dhwCircuits/dhw1/switchPrograms/A/1-Mo:0:0:WaterProgram-1-Mo
   /dhwCircuits/dhw1/switchPrograms/A/2-Tu:0:0:WaterProgram-2-Tu
   /dhwCircuits/dhw1/switchPrograms/A/3-We:0:0:WaterProgram-3-We
   /dhwCircuits/dhw1/switchPrograms/A/4-Th:0:0:WaterProgram-4-Th
   /dhwCircuits/dhw1/switchPrograms/A/5-Fr:0:0:WaterProgram-5-Fr
   /dhwCircuits/dhw1/switchPrograms/A/6-Sa:0:0:WaterProgram-6-Sa
   /dhwCircuits/dhw1/switchPrograms/A/7-Su:0:0:WaterProgram-7-Su
   /dhwCircuits/dhw1/temperatureLevels/high:1::WaterDayTemp
   /dhwCircuits/dhw1/waterFlow:::waterFlow
   /dhwCircuits/dhw1/workingTime:::WaterWorkingTime
   /gateway/DateTime:0:0:DateTime
   /gateway/instAccess:0:0:InstAccess
   /gateway/uuid:::Uuid
   /gateway/versionFirmware:::FirmwareVersion
   /heatSources/ChimneySweeper:::ChimneySweeper
   /heatSources/flameCurrent:::FlameCurrent
   /heatSources/gasAirPressure:0:0:GasAirPressure
   /heatSources/hs1/energyReservoir:::EnergyReservoir
   /heatSources/hs1/flameStatus:::FlameStatus
   /heatSources/hs1/fuel/caloricValue:0:0:CaloricValue
   /heatSources/hs1/fuel/density:0:0:FuelDensity
   /heatSources/hs1/fuelConsmptCorrFactor:0:0:FuelConsmptCorrFactor
   /heatSources/hs1/info:::HeatSourceInfo
   /heatSources/hs1/nominalFuelConsumption:0:0:FuelConsumption
   /heatSources/hs1/reservoirAlert:0:0:ReservoirAlert
   /heatSources/hs1/supplyTemperatureSetpoint:0:0:SupplyTemperatureSetpoint
   /heatSources/hs1/type:::HeatSourceType
   /heatSources/info:::HeatSourceInfo
   /heatSources/numberOfStarts:0:0:NumberOfStarts
   /heatSources/systemPressure:20:0.2:SystemPressure
   /heatSources/workingTime/centralHeating:0:0:CentralHeatingWorkingTime
   /heatSources/workingTime/secondBurner:0:0:SecondBurnerWorkingTime
   /heatSources/workingTime/totalSystem:0:0:SystemWorkingTime
   /heatingCircuits/hc1/activeSwitchProgram:0:0:ActiveSwitchProgram
   /heatingCircuits/hc1/actualSupplyTemperature:0:0:HC1SupplyTemp
   /heatingCircuits/hc1/currentRoomSetpoint:1::RoomDesiredTemp
   /heatingCircuits/hc1/fastHeatupFactor:0:0:HeatupFactor
   /heatingCircuits/hc1/manualRoomSetpoint:10::RoomManualDesiredTemp
   /heatingCircuits/hc1/operationMode:10::HeatMode 
   /heatingCircuits/hc1/pumpModulation:1:10:PumpModulation
   /heatingCircuits/hc1/status:0:0:Status 
   /heatingCircuits/hc1/switchPrograms/A/1-Mo:0:0:ProgramA1-Mo
   /heatingCircuits/hc1/switchPrograms/A/2-Tu:0:0:ProgramA2-Tu
   /heatingCircuits/hc1/switchPrograms/A/3-We:0:0:ProgramA3-We
   /heatingCircuits/hc1/switchPrograms/A/4-Th:0:0:ProgramA4-Th
   /heatingCircuits/hc1/switchPrograms/A/5-Fr:0:0:ProgramA5-Fr
   /heatingCircuits/hc1/switchPrograms/A/6-Sa:0:0:ProgramA6-Sa
   /heatingCircuits/hc1/switchPrograms/A/7-Su:0:0:ProgramA7-Su
   /heatingCircuits/hc1/switchPrograms/B/1-Mo:0:0:ProgramB1-Mo
   /heatingCircuits/hc1/switchPrograms/B/2-Tu:0:0:ProgramB2-Tu
   /heatingCircuits/hc1/switchPrograms/B/3-We:0:0:ProgramB3-We
   /heatingCircuits/hc1/switchPrograms/B/4-Th:0:0:ProgramB4-Th
   /heatingCircuits/hc1/switchPrograms/B/5-Fr:0:0:ProgramB5-Fr
   /heatingCircuits/hc1/switchPrograms/B/6-Sa:0:0:ProgramB6-Sa
   /heatingCircuits/hc1/switchPrograms/B/7-Su:0:0:ProgramB7-Su
   /heatingCircuits/hc1/temperatureLevels/comfort2:10::ComfortTemp
   /heatingCircuits/hc1/temperatureLevels/eco:10::EcoTemp
   /heatingCircuits/hc1/temporaryRoomSetpoint:1::RoomTemporaryDesiredTemp
   /notifications:0:0:Notifications
   /system/brand:0:0:SystemBrand
   /system/bus:::BusType
   /system/healthStatus:10::Health
   /system/heatSources/hs1/actualModulation:1::PowerModulation
   /system/heatSources/hs1/actualPower:1::Power
   /system/holidayModes/hm1/assignedTo:0:0:Holiday1Assign
   /system/holidayModes/hm1/dhwMode:0:0:Holiday1WaterMode
   /system/holidayModes/hm1/hcMode:0:0:Holiday1HeatMode
   /system/holidayModes/hm1/startStop:0:0:Holiday1
   /system/holidayModes/hm2/assignedTo:0:0:Holiday2Assign
   /system/holidayModes/hm2/dhwMode:0:0:Holiday2WaterMode
   /system/holidayModes/hm2/hcMode:0:0:Holiday2HeatMode
   /system/holidayModes/hm2/startStop:0:0:Holiday2
   /system/holidayModes/hm3/assignedTo:0:0:Holiday3Assign
   /system/holidayModes/hm3/dhwMode:0:0:Holiday3WaterMode
   /system/holidayModes/hm3/hcMode:0:0:Holiday3HeatMode
   /system/holidayModes/hm3/startStop:0:0:Holiday3
   /system/holidayModes/hm4/assignedTo:0:0:Holiday4Assign
   /system/holidayModes/hm4/dhwMode:0:0:Holiday4WaterMode
   /system/holidayModes/hm4/hcMode:0:0:Holiday4HeatMode
   /system/holidayModes/hm4/startStop:0:0:Holiday4
   /system/holidayModes/hm5/assignedTo:0:0:Holiday5Assign
   /system/holidayModes/hm5/dhwMode:0:0:Holiday5WaterMode
   /system/holidayModes/hm5/hcMode:0:0:Holiday5HeatMode
   /system/holidayModes/hm5/startStop:0:0:Holiday5
   /system/info:::SystemInfo
   /system/minOutdoorTemp:0:0:MinOutdoorTemp
   /system/sensors/temperatures/outdoor_t1:1:0.5:OutdoorTemp
   /system/sensors/temperatures/return:1:0.5:ReturnTemp
   /system/sensors/temperatures/supply_t1:1:0.5:SupplyTemp
   /system/sensors/temperatures/supply_t1_setpoint:1:0.5:DesiredSupplyTemp
   /system/systemType:::SystemType
);
# I don't know anything about RC30 and RC35 - feel free to fill with knowledge:
my @RC30DEFAULTS = 
    qw(/gateway/DateTime:0:0:DateTime
);

my @RC35DEFAULTS = 
    qw(/gateway/DateTime:0:0:DateTime
);

# extra valid value not in range which is set by gateway
my %extra_value=
qw(/heatingCircuits/hc1/fastHeatupFactor 0
   /heatingCircuits/hc1/temporaryRoomSetpoint -1
   /gateway/DateTime now);

sub BDKM_Define($$);
sub BDKM_Undefine($$);

sub BDKM_Initialize($)
{
    my ($hash) = @_;
    
    $hash->{STATE}           = "Init";
    $hash->{DefFn}           = "BDKM_Define";
    $hash->{UndefFn}         = "BDKM_Undefine";
    $hash->{SetFn}           = "BDKM_Set";
    $hash->{GetFn}           = "BDKM_Get";
    $hash->{AttrFn}          = "BDKM_Attr";
    $hash->{DeleteFn}        = "BDKM_Undefine";

    $hash->{AttrList}        = 
        "BaseInterval " .
        "PollIds:textField-long  " .
        "HttpTimeout " .
        $readingFnAttributes;
    return undef;
}

sub BDKM_Define($$)
{
    my ($hash, $def) = @_;
    my @a            = split(/\s+/, $def);
    my $name                    = $a[0];

    # salt will be removed in future versions and must be set by user in fhem.cfg
    my $salt = "";
    my $cryptkey="";
    my $usage="usage: \"define <devicename> BDKM <IPv4-address|hostname>  <GatewayPassword> <PrivatePassword> <md5salt>\" or\n".
        "\"define <devicename> BDKM <IPv4-address|hostname>  <AES-Key (see:https://ssl-account.com/km200.andreashahn.info)>\"";

    (@a == 4 or @a ==6) or return "$name $usage"; 

    $hash->{NAME}               = $name;
    $hash->{STATE}              = "define";

    my $ip                      = $a[2];
    ($ip =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ and 
     $1<256 and $2<256 and $3<256 and $4<256) or 
     ($ip =~ m/(?=^.{1,253}$)(^(((?!-)[a-zA-Z0-9-]{1,63}(?<!-))|((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63})$)/) or
     return "$name IP or hostname invalid, $usage";
    
    if(@a == 6) {
        my @passwd                  = ($a[3],$a[4]); # gateway,private passwd
        
        $salt=$a[5];
   
        if(!($passwd[0] =~ /-/)) { # must be base64
            my $i;
            foreach $i ((0,1)) {
                $_ = decode_base64($passwd[$i]);
                s/[\r\n]//g;
                $passwd[$i] = $_;
            }
        }
        $passwd[0] =~ tr/-//d;
        if(length($passwd[0]) != 16 or 
           length($passwd[1]) == 0) {
            Log3 $name, 1, "$name please check passwords";
            return "$name ERROR gateway password needs format ".
                "\"aaaa-bbbb-cccc-dddd\"\n".
                "password may be encoded base64 to make it less human readable";
        }
        $salt = pack('H*',$salt);
        $cryptkey =  md5($passwd[0].$salt).md5($salt.$passwd[1]);
    } elsif (@a == 4) { 
        # complete AES-Key from define. Can be generated here:
        # https://ssl-account.com/km200.andreashahn.info
        $cryptkey = pack('H*',$a[3]);
    } 
    
    Log3 $name, 3, "$name using AES-Key: ".unpack("H*",$cryptkey)."\n";

    $hash->{CRYPT} = 
        Crypt::Rijndael->new($cryptkey, Crypt::Rijndael::MODE_ECB() );

    $hash->{NAME}                             = $name;
    $hash->{IP}                               = $ip;
    $hash->{SEQUENCE}                         = 0;
    $hash->{POLLIDS}                          = {}; # from attr PollIds
    $hash->{UPDATES}                          = []; # Ids to check for update reading after polling
    $hash->{REALTOUSER}                       = {}; # Hash to transform real IDs to readings
    $hash->{USERTOREAL}                       = {}; # Hash to readings to real IDs
    $hash->{IDS}                              = {}; # Hash containing IDS of first full poll
    $hash->{VERSION}                          = '$Id$';    
    # init attrs to defaults:
    map {BDKM_Attr("del",$name,$_)} qw(BaseInterval ReadBackDelay HttpTimeout);

    BDKM_reInit($hash);
    return undef;
}

sub BDKM_Attr(@)
{
    my ($cmd,$name,$attr,$val)  = @_;
    my $hash                    = $defs{$name};
    my $error                   = "$name: ERROR attribute $attr ";
    my $del                     = $cmd =~ /del/;
    local $_;

    defined $val or $val="";
    
    if ($attr eq "BaseInterval") {
        $del and $val = 120; # default
        if($val !~ /^\d+$/ or $val < 30) {
            return $error."needs interger value >= 30";
        } else {
            $hash->{BASEINTERVAL} = $val;            
            BDKM_reInit($hash);
        } 
    } elsif($attr eq "ReadBackDelay") {
        $del and $val = 500;
        if($val !~ /^\d+$/ or $val < 100 or $val > 2000) {
            return $error."needs interger value (milliseconds) between 100 and 2000";
        } else {
            $hash->{READBACKDELAY} = $val;
        } 
    } elsif ($attr eq "HttpTimeout") {
        $del and $val = 10; # default
        $val =~ /^([0-9]+|[0-9]+\.?[0.9]+)$/ or return $error."needs numeric value";
        $hash->{HTTPTIMEOUT} = $val;
    } elsif($attr eq "PollIds") {
        $hash->{POLLIDS}      = {}; # no more polling
        $hash->{UPDATES}      = []; # no updates for possibly running poll
        $del and return undef;
        $hash->{REALTOUSER}   = {};
        $hash->{USERTOREAL}   = {};
        my @ids=();
        # add defaults if set 
        $val =~ s|RC300DEFAULTS||g and push(@ids, @RC300DEFAULTS);
        $val =~ s|RC35DEFAULTS||g  and push(@ids, @RC35DEFAULTS);
        $val =~ s|RC30DEFAULTS||g  and push(@ids, @RC30DEFAULTS);
        push(@ids,split(/\s+/s,$val));
        my $err = $error."needs space separated valid gateway IDs like\n".
            "/system/sensors/temperatures/return:2:0.5:ReturnTemp\nor just\n".
            "/system/sensors/temperatures/return:::\nor just\n".
            "/system/sensors/temperatures/return\n";

        foreach (@ids) {
            s|\s+||gs;
            /[A-z]/ or next;
            my($id,$modulo,$delta,$replace);

            if(m|(^/[A-z0-9\-_/]+[A-z0-9])$|) { # no ":"
                # poll id every cycle, no delta check (allways update), no replacement
                ($id,$modulo,$delta,$replace) = ($1,1,0,"");
            } else { # colon separated extras id:modulo:delta:replace
                unless(($id,$modulo,$delta,$replace) = 
                  m|(^/[A-z0-9\-_/]+[A-z0-9]):[-]*(\d*):([0-9]*\.?[0-9]*):(.*)$|) {
                    return $err;
                }
                ($modulo eq "" or $modulo =~ '-') and $modulo = -1;
            }
            # check pathes:
            my $ok = 0;
            foreach my $dir (@BaseDirs) {
                $dir eq "/" and next;
                !index($id,$dir,0) and $ok=1 and last;
            }
            $ok or return $error."$id is not a valid gateway ID";

            
            defined $hash->{POLLIDS}{$id} and
                Log3 $hash, 4, "$name attr PollIds - Overwritig definition of $id";
                
            $delta eq "" or $delta += 0.0;
            $hash->{POLLIDS}{$id}{MODULO} =int($modulo);
            $hash->{POLLIDS}{$id}{DELTA}  = $delta;
            if($replace) {
                $hash->{REALTOUSER}{$id}=$replace;
                $hash->{USERTOREAL}{$replace}=$id;
            } else {
                # remove replacements for IDs if overwritten.
                if(defined  $hash->{REALTOUSER}{$id}) {
                     delete $hash->{REALTOUSER}{$id};
                     map {
                         $hash->{USERTOREAL}{$_} eq $id and delete $hash->{USERTOREAL}{$_}
                     } keys %{$hash->{USERTOREAL}};
                }
            }
        }
    }
    
    return undef;
}

sub BDKM_reInit($)
{
    my ($hash)                                = @_;
    BDKM_RemoveTimer($hash);
    $hash->{UPDATES} = [];
    if($hash->{ISPOLLING}) {
        # let sequence finish and try again
        BDKM_Timer($hash,29,"BDKM_reInit");
        return;
    }
    if(!$hash->{SEQUENCE}) { # init
        # delay start to have a chance that all attrs are set
        BDKM_Timer($hash,5,"BDKM_doSequence");
    } else {
        BDKM_Timer($hash,$hash->{BASEINTERVAL},"BDKM_doSequence");
    }
}

sub BDKM_doSequence($)
{
    my ($hash)                 = @_;
    
    # restart timer for next sequence
    BDKM_Timer($hash,$hash->{BASEINTERVAL},"BDKM_doSequence");
    # only start polling if we are not polling (e.g. due to network promlems)
    $hash->{ISPOLLING} and return;
    $hash->{ISPOLLING}=1;
    my $seq = $hash->{SEQUENCE};
    my $h   = $hash->{POLLIDS};

    Log3 $hash, 4, "$hash->{NAME} starting polling sequence #".$seq;

    if(!$seq) { # do full poll and init $hash->{IDS}
        @{$hash->{JOBQUEUE}} = @BaseDirs;
        # update only modulos >= 0
        @{$hash->{UPDATES}}  =
            sort grep {$h->{$_}{MODULO} >= 0} keys(%$h);
    } else {
        $h or return; # no ids to poll
        # only poll known IDs which are in turn
        @{$hash->{UPDATES}} =
            sort grep {$h->{$_}{MODULO} > 0 and $seq % $h->{$_}{MODULO} == 0 and defined $hash->{IDS}{$_}} keys(%$h);
        # JOBQUEUE: remove special switchPrograms and transform to the real base reading:
        my %seen=(); 
        @{$hash->{JOBQUEUE}} = BDKM_MapSwitchPrograms($hash->{UPDATES});
    }
    Log3 $hash, 6, $hash->{NAME}." jobqueue is:".join(" ",@{$hash->{JOBQUEUE}})."\n";
    Log3 $hash, 6, $hash->{NAME}." elements to update after polling: ".join(" ",@{$hash->{UPDATES}})."\n";
    readingsSingleUpdate($hash, "state", "polling", 0);
    BDKM_JobQueueNextId($hash);
}

sub BDKM_JobQueueNextId($)
{
    my ($hash)                 = @_;
    
    if(@{$hash->{JOBQUEUE}}) { # still ids to poll
        my $id = (@{$hash->{JOBQUEUE}})[0];
        Log3 $hash, 5, "$hash->{NAME} reading $id";
        # get next type
        BDKM_HttpGET($hash,$id,\&BDKM_JobQueueNextIdHttpDone);
    } else { 
        BDKM_UpdateReadings($hash,$hash->{UPDATES});
        $hash->{SEQUENCE}++;
        $hash->{ISPOLLING}=0;
        Log3 $hash, 4, $hash->{NAME}." update  ".join(" ",@{$hash->{UPDATES}})."\n";
        readingsSingleUpdate($hash, "state", "idle", 0);
    }
}

sub BDKM_JobQueueNextIdHttpDone($)
{
    my ($param, $err, $data)     = @_;
    my $hash                     = $param->{hash};
    my $name                     = $hash ->{NAME};
    my $json;

    if($err) {
        readingsSingleUpdate($hash, "state", 
                             "reading ids ERROR - retrying every 60s", 1);
        Log3 $name, 2, "$name communication ERROR in state $hash->{STATE}: $err";
        # try again in 60s
        BDKM_Timer($hash,60,"BDKM_JobQueueNextId");
        return; 
    }
    my $hth= $param->{httpheader};
    $hth =~ s/[\r\n]//g;
    Log3 $name, 5, "$name HTTP done @{$hash->{JOBQUEUE}}[0],$hth";
    # did this type, remove from job queue:
    my $id = shift(@{$hash->{JOBQUEUE}});

    ($json,$data) = BDKM_decode_http_data($hash,$data);

    if($json) {
        if (!$hash->{SEQUENCE} and $json and $json->{type} eq "refEnum") { # init only
            # new type
            foreach my $item (@{$json->{references}}) {
                my $entry = $item->{id};
                #exists $hash->{IGNOREIDS}{$entry} and next; # ignore
                # push to job queue
                push(@{$hash->{JOBQUEUE}},$entry);
            }
        } else {
            BDKM_update_id_from_json($hash,$json);
        }
    } else {
        if(!$hash->{SEQUENCE}) {
            if($id ne "/") {
                $hash->{IDS}{$id}{RAWDATA} = 1;
                $hth =~ s|HTTP/...|HTTP|;
                $hth =~ s/\s+/_/g;
                $hth =~ /200/ or $hash->{IDS}{$id}{HTTPHEADER} = $hth;
            }
                
            Log3 $hash, 4, "$name $id - no JSON data available - raw data: $data";
        }
    }
    BDKM_JobQueueNextId($hash); # get next id

    return;
}

sub BDKM_UpdateReadings($$)
{
    my ($hash,$listref)  = @_;

    readingsBeginUpdate($hash);
    foreach my $id (@$listref) {
        my $val = $hash->{IDS}{$id}{VALUE};
        defined $val or next;
        Log3 $hash, 5, "Check reading update for $id $val";

        my $reading = defined $hash->{REALTOUSER}{$id} ?  
            $hash->{REALTOUSER}{$id} : $id;
        my $rdval = $hash->{READINGS}{$reading}{VAL}; 
        if(defined($rdval) and defined $hash->{POLLIDS}{$id}) {
            my $delta = $hash->{POLLIDS}{$id}{DELTA};
            # same as last - skip
            $delta eq "" and $rdval eq $val and next;
            # difference too small - skip
            $delta and abs($rdval-$val) < $delta and next;
        }
        Log3 $hash, 4, "$hash->{NAME} update reading $reading $val";
        readingsBulkUpdate($hash,$reading,$val);
    }
    readingsEndUpdate($hash,1);

}

sub BDKM_Undefine($$)
{
    my ($hash, $def)  = @_;
    my $name = $hash->{NAME};   

    BDKM_RemoveTimer($hash);
    return undef;
}


sub BDKM_GetInfo
{
    my ($hash, $matches) = @_;

    no warnings 'uninitialized';
    my $fmt="%-50.50s %-25.25s %-23.23s %s %-30.30s %-10.10s %-10.10s\n";
    my $header =sprintf($fmt,
                        "Gateway ID", "FHEM Reading (Alias)", "Last Value Read", "TW", 
                        "Valid Values", "Poll", "Rd.Update");
    my $llll = ("-" x length($header))."\n";
    my @ids;
    if($matches) {
        # loop over all possible IDs and aliases and check if
        # they match given regexp inputs
        my %seen=();
        map { 
            my $regex = qr/$_/;
            map {
                if($_ =~ $regex) { # match on input to INFO
                    my $realid = defined $hash->{USERTOREAL}{$_} ?
                        $hash->{USERTOREAL}{$_} : $_;
                    !$seen{$realid}++ and push(@ids,$realid);
                } 
            } (keys %{$hash->{IDS}}, keys %{$hash->{USERTOREAL}});
        } split(/\s+/,$matches);
    } else {
        # use all IDs
        @ids = keys %{$hash->{IDS}};
    }

    my @lines= sort map {
        my $id=$_;
        my $h=$hash->{IDS}{$id};
        my $p=$hash->{POLLIDS}{$id};
        my $m = $p->{MODULO};
        my $d = $p->{DELTA};
        my $u = $h->{UNIT};
        my $type = substr($h->{TYPE},0,1);
        my $flags = ($type ? $type : " ").($h->{WRITEABLE} ? '+' : '-');
            
        my $a = defined $h->{RAWDATA} ? $h->{HTTPHEADER} : $h->{ALLOWED};
        $u =~ s/µ/u/g;
        $a =~ s/ /,/g;
        sprintf($fmt,
                $id,
                $hash->{REALTOUSER}{$id},
                $h->{VALUE}.($u ? " $u":""),
                $flags,
                defined $a                ? $a          : 
                $h->{MIN} ? "[$h->{MIN}:$h->{MAX}]"     : "",
                (!defined $m or $m  <  0) ? ""          :
                $m == 0                   ? "once"      :
                $m == 1                   ? "always"    :
                $m  >1                    ? "every $m"  : "",
                (!defined $d or $d eq "") ? "on change" : 
                $d  == 0                  ? "always"    : "Δ >= $d"
         );
    } @ids;

    my $footer= $matches ? "" :
q(* The table shows all known gateway IDs.  A "+" sign in the W column means the ID is writeable.
  Long entries may be cut due to formating.
  Ranges for Valid  Values ranges are shown as: [from:to] 
  When no JSON data can be fetched the HTTP error is shown.
  Temperatures are normaly allowed to set in 0.5 C steps only.
  On startup all IDs are gathered once but do not automatically generate a fhem reading.
  IDs which shoud generate readings not only with the set/get command need to be defined with the "PollIds" attribute.
  Poll:
        always  => ID is polled every cycle (PollIds setting *:1:*:*)
        every X => ID is only polled every Xth cycle (PollIds setting *:X:*:*)
        once    => After gathering process on startup this ID is checked for reading update (PollIds setting *:0:*:*)       
        ''      => update checks only on get/set command (PollIds setting *::*:* or not set)

  Redings Udate:
        always    => Reading Update is always done on value update (PollIds setting *:*:0:*)
        Δ >= X    => Reading Update is done when difference to last reading was at least X (PollIds setting *:*:X:*)
        on change => Reading Update is done when value has changed to last reading (PollIds setting *:*::*)
);

    return "\n".$header.$llll.join("",@lines).$llll.$footer;
}


sub BDKM_Set($@)
{
    my ( $hash, $name, $id, @values) = @_;
    
    if(!defined $hash->{IDS}{$id} and !defined $hash->{USERTOREAL}{$id}) {
        no warnings 'uninitialized';
        # only print aliased commands:
        my @writeable=sort grep {
            $hash->{IDS}{$hash->{USERTOREAL}{$_}}{WRITEABLE}
        } keys %{$hash->{USERTOREAL}};
        my @cmds=map {
            my @vals=();
            my $realid=$hash->{USERTOREAL}{$_};
            defined $extra_value{$realid} and push (@vals,$extra_value{$realid});
            my $h=$hash->{IDS}{$realid}; 
            if ($realid =~ /HeatupFactor/) {
                push(@vals,(10,20,30,40,50,60,70,80,90,100));
            } elsif(defined $h->{ALLOWED}) {
                $h->{TYPE} ne "arrayData" and push(@vals,split(/\s+/,$h->{ALLOWED}));
            } elsif (defined $h->{MAX}) {
                if($h->{UNIT} eq "C") {                    
                    for(my $i=$h->{MIN}; $i <= $h->{MAX}; $i+=0.5) {
                        push(@vals,$i);
                    }
                }
            }
            if (@vals) {
                $_.=":".join(',',@vals);
            } else {
                $_;
            }
        } @writeable;
        return "Unknown argument $id, choose one of ".join(" ",@cmds);
    }

    @values or
        return "usage: set $hash->{NAME} <ID> <value ...>";

    my $value=join(" ",@values);
    my $ret;
    $ret = BDKM_SetId($hash, $id, $value);
    $ret !~ /Unable to set/ and return $ret;
    BDKM_msleep(2000);
    $ret = BDKM_SetId($hash, $id, $value);
    return $ret;
}

sub BDKM_HttpTest
{
    my ($hash,$id,$method,$data)   = @_;
    my $param = {
        url           => "http://" . $hash->{IP} . $id,
        hash          => $hash,
        data          => $data,
        method        => $method,
        header        => "agent: PortalTeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
    };
   
    $param->{timeout} = 3;
    my @a= HttpUtils_BlockingGet($param); #returns ($err, $data)
    $param->{hash}=0;
  
}

sub BDKM_SetId($@)
{
    my ($hash,$id,$value)   = @_;
    my $name=$hash->{NAME};

    defined $hash->{USERTOREAL}{$id} and $id = $hash->{USERTOREAL}{$id};
    # set getway time to host time:
    $id eq "/gateway/DateTime" and $value eq "now" and
        $value=strftime("%Y-%m-%dT%H:%M:%S", localtime);

    my $data;
    my $err;

    if($value =~ /\s+test$/ or defined $hash->{IDS}{$id}{RAWDATA}) {
        # we dont know anything about that...yet
        # try raw data send
        $value =~ s/\s+test$//g;
        $id =~ /firmware/i and return; # better...if we don't know what we do.
        
        Log3 $name, 3, "$name set rawpost $id value $value";
        $data = BDKM_Encrypt($hash,$value);
        Log3 $name, 3, "$name http PUT $id encrypted data $data";
        my $a;
        ($data,$err,$a) = BDKM_HttpTest($hash,$id,"PUT",$data);
        return "+1+$data+2+$err+3+\n";
    } elsif($value =~ /\s+raw$/) {
        $value =~ s/\s+raw$//g;
        Log3 $name, 3, "$name set raw $id value $value";
        $data = BDKM_Encrypt($hash,$value);
        ($data,$err) = BDKM_HttpPUT($hash,$id,$data);
        return $data.$err;
    } else {
        Log3 $name, 3, "$name set raw $id value $value";
        my $rawdata = BDKM_GetId($hash,$id,"raw") or
            return "unable to set $id because the value can not be read";  
        
        defined $hash->{IDS}{$id}{VALUE} or return "ID $id is unknown";
        
        my $h=$hash->{IDS}{$id};
        my $type=$h->{TYPE};
        
        defined $h->{WRITEABLE} and $h->{WRITEABLE} or return "ID $id is not writeable";
        my $allowed=defined $h->{ALLOWED} ? $h->{ALLOWED} : "";
        
        my $json={};
        if($type eq "floatValue") {
            $value =~ s/\"//;
            $value =~ /^-?\d+\.?\d*$/ or return "$id needs a float/integer value";
            Log3 $name, 3, "$name $id set floatValue $value";
            my $ok = (defined $extra_value{$id} and $extra_value{$id} eq $value);
            !$ok and defined $h->{MIN} and defined $h->{MAX} and
                ($value < $h->{MIN} || $value > $h->{MAX}) and
                return "allowed values for $id are: interger/float in range $h->{MIN} to $h->{MAX}";
            $json->{value} =  ($value + 0.0); # make number from it!
        } elsif ($type eq "stringValue") {
            Log3 $name, 3, "$name $id set stringValue $value";
            $allowed and $allowed !~ /$value/ and 
                return "allowed values for $id are: one of $allowed";
            $json->{value} =  $value;
            Log3 $name, 3, "$name set $id float value $value";
        } elsif ($type eq "arrayData") { # RC300 only for /system/holidayModes/hm[1-5]/assignedTo
            Log3 $name, 3, "$name $id set arrayData $value";
            my @a=split(/\s+/,$value);
            foreach(@a) {
                $allowed and $allowed !~ /$_/ and 
                    return "allowed values for $id are: one or more of $allowed";
            }
            $json->{values} =  \@a;
        } 
        if ($type eq "switchProgram") {
            Log3 $name, 3, "$name $id set switchProgram $value";
            my $postid=$id;
            $postid =~ s|/\d-([A-z][A-z])$||;
            $data=BDKM_makeSwitchPointData($rawdata,$1, $value);
            $data =~ /setpoint/ or return $data;
            $data = BDKM_Encrypt($hash,$data);
            ($data,$err) = BDKM_HttpPUT($hash,$postid,$data);
        } else {
            $data = BDKM_encode_http_data($hash,$json);
            BDKM_msleep($hash->{READBACKDELAY});
            ($data,$err) = BDKM_HttpPUT($hash,$id,$data);
        }
        BDKM_msleep($hash->{READBACKDELAY});
        my $ret = BDKM_GetId($hash,$id);

        $ret ne $value and $id ne "/gateway/DateTimeteTime" and
            return "$name Unable to set +$value+ to $id (readback: +$ret+)";
        return $ret;
    }
}

sub BDKM_Get($@)
{
    my ( $hash, $name, $id, $opt) = @_;

    # specials
    $id eq "INFO" and return BDKM_GetInfo($hash, $opt);
    if(defined $opt and $opt eq "rawforce")  {
        $opt="raw";
    } else {
        if(!defined $hash->{IDS}{$id} and !defined $hash->{USERTOREAL}{$id}
           or (defined($opt) and $opt ne "raw" and $opt ne "json")) {
            # only print aliased and special commands (like INFO):
            my @getable=qw(INFO);
            push(@getable, keys %{$hash->{USERTOREAL}});
            return "Unknown argument $id, choose one of ".join(" ",@getable);
        }
    }  
    return BDKM_GetId($hash, $id, $opt);
}

sub BDKM_GetId($@)
{
    my ($hash,$id,$opt)   = @_;
    my $name=$hash->{NAME};
    
    defined $hash->{USERTOREAL}{$id} and $id = $hash->{USERTOREAL}{$id};
    my $json;
    
    defined $opt or $opt = "";
    
    my $realid=$id;
    if($id =~ m|/\d-[MTWTFS][ouehrau]$|) { 
        # one of our pseudo switch program id
        # map to a real gateway id
        ($realid) =  BDKM_MapSwitchPrograms([$id]);
    }
    # blocking http get:
    my($err,$data, $httpheader) = BDKM_HttpGET($hash,$realid);
    if($err) {
        Log3 $name, 2, "$name unable to fetch ID $id - $err";
        return "$name unable to fetch ID $id - $err";
    } else {   
        ($json,$data) = BDKM_decode_http_data($hash,$data);
        Log3 $name, 2, "$name get $id - HTTP: $httpheader, data: $data";
        if($json) {
            BDKM_update_id_from_json($hash,$json);
            # always check for reading update when id was read
            BDKM_UpdateReadings($hash,[$id]);
            $opt eq "json" and return $json;
        }
        if($opt eq "raw") {
            return $data;
        }
        defined $hash->{IDS}{$id}{VALUE} and return $hash->{IDS}{$id}{VALUE};
    }
    return "";
}

# this routine takes the raw http json data of a switch program,
# the week day and the setpointstring to be set like
# "0700 comfort2 2200 eco"
# It then patches the new setpoints for that day to the json data (sorted!).

sub BDKM_makeSwitchPointData
{
    my ($data, $weekday, $setpointstr) =@_;
    my @setpoints=();
    my $timeraster=0;
    map {
        s/\}.*//;
        /switchPointTimeRaster.*?(\d+)/ and $timeraster=$1;
        /setpoint[^A-z]/ and !/\"$weekday\"/ and push(@setpoints,'{'.$_.'}');
    } split(/{/,$data);
    
    my @a=split(/\s+/,$setpointstr);
    while(@a) {
        $_=shift(@a);
        s|:||;
        my ($hr,$min)=/^(\d\d)(\d\d)$/ or return "invalid time format - use: HHMM";
        ($hr > 23 or $min > 59) and return "$hr$min use a valid time between 0000 and 2359";
        $timeraster and $min % $timeraster and 
            return "switch point $_ not allowed: switchpoint raster is 15 minutes";
        @a or return "$hr$min missing set point type";
        $_=shift(@a);
        my $time = $hr*60+$min;
        push(@setpoints, '{"dayOfWeek":"'.$weekday.'","setpoint":"'.$_.'","time":'.$time.'}'); # add weekday
    }
    return '['.join(',',
                sort {
                    # by day num
                    $WdToNum{($a =~ /dayOfWeek[^A-z]+([A-z][A-z])/)[0]} <=> 
                        $WdToNum{($b =~/dayOfWeek[^A-z]+([A-z][A-z])/)[0]} ||
                        # and time
                        ($a =~ /time[^\d]+(\d+)/)[0] <=> 
                        ($b =~ /time[^\d]+(\d+)/)[0] 
                } @setpoints).']';
}

############################## Helpers ###################################
sub BDKM_HttpPostOrGet
{
    my ($hash,$id,$method,$data,$callback)   = @_;
    my $param = {
        url           => "http://" . $hash->{IP} . $id,
        hash          => $hash,
        data          => $data,
        method        => $method,
        header        => "agent: PortalTeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
    };
    if(defined($callback)) {
        Log3 $hash, 5, "$hash->{NAME} async $method $param->{url}";
        $param->{timeout} = $hash->{HTTPTIMEOUT};
        $param->{callback} = $callback;
        HttpUtils_NonblockingGet($param);
        return undef;
    } else {
        $param->{timeout} = 3;
        Log3 $hash, 5, "$hash->{NAME} sync $method $param->{url}";
        return (HttpUtils_BlockingGet($param),$param->{httpheader}); #returns ($err, $data)
    }
}

sub BDKM_HttpGET
{
    my ($hash,$id,$callback)   = @_;
    return BDKM_HttpPostOrGet($hash,$id,"GET",undef,$callback);
}

sub BDKM_HttpPOST
{
    my ($hash,$id,$data,$callback)   = @_;
    return BDKM_HttpPostOrGet($hash,$id,"POST",$data,$callback);
}

sub BDKM_HttpPUT
{
    my ($hash,$id,$data,$callback)   = @_;
    return BDKM_HttpPostOrGet($hash,$id,"PUT",$data,$callback);
}

sub BDKM_Timer
{
    my ($hash,$secs,$callback) = @_;
    InternalTimer(gettimeofday()+$secs, $callback, $hash, 0);
}
sub BDKM_RemoveTimer
{
    RemoveInternalTimer($_[0]);
}

sub BDKM_Decrypt($$)
{
    my ($hash, $data)  = @_;

    $data = decode_base64($data);
    length($data) & 0xF and return ""; # must be 16byte blocked. if not decryt calls exit()!!!

    $data = $hash->{CRYPT}->decrypt( $data );
    my $len = length($data);
    
    ($len & 0xF) and return $data;

    # 16 byte block, remove padding
    my $i;
    for($i=0; $i < $len && ord(substr($data,-1-$i,1)) == 0; $i++){};
    if($i) {
        return substr($data,0,$len-$i);
    } else {
        # 16byte blocks not zero padded
        # check if RFC PKCS #7 padded and remove padding
        my $padchar = substr($data,($len - 1),1); #last char
        my $num = ord($padchar);
        if($num <= 16) {
            substr($data,$len - $num, $num) eq ($padchar x $num) and
                return substr($data,0,$len - $num);
        }
    }
    return $data;
}

sub BDKM_Encrypt($$)
{
    my ($hash, $data)           = @_;
    my $crypt                   =  $hash->{CRYPT};
    my $blocksize               =  $crypt->blocksize();
    # pad data to block size before encrypting - see RFC 5652
    my $numpad =  $blocksize - length($data)%$blocksize;

    return
        encode_base64($crypt->encrypt($data.(chr($numpad) x $numpad)));
}
sub BDKM_msleep
{
    select(undef, undef, undef, $_[0]/1000);
}


sub BDKM_decode_http_data
{
    my ($hash, $data) = @_;
    my $json="";
    Log3 $hash, 6, "$hash->{NAME} raw crypted HTTP data: $data";
    $data =~ /^\s*$/s and return ("","");
    $data = BDKM_Decrypt($hash,$data);
    my $len = length($data);
    Log3 $hash, 4, "$hash->{NAME} deocded $len bytes HTTP data: $data";
    if($data) {
        eval {$json = decode_json(encode_utf8($data)); 1;  } or do {
            $json="";
        }
    }
    return ($json,$data);
}

sub BDKM_encode_http_data
{
    my ($hash, $json) = @_;
    my $data = encode_json($json);
    Log3 $hash, 3, "$hash->{NAME} raw HTTP data: $data";
    $data = BDKM_Encrypt($hash,$data);
    Log3 $hash, 6, "$hash->{NAME} encocded HTTP data: $data";
    return $data;
}



sub BDKM_update_id_from_json
{
    my ($hash,$json) = @_;
    
    if ($json) {
        my $id       = $json->{id};
        my $type     = $json->{type};

        Log3 $hash, 6, "$hash->{NAME} update JSON $id $type";

        defined ($hash->{IDS}{$id}) or $hash->{IDS}{$id}={};

        my $h = $hash->{IDS}{$id};
        if($type eq "stringValue" or $type eq "floatValue"){
            if(!defined($h->{WRITEABLE})) { # initial
                $h->{WRITEABLE} = $json->{writeable};     
                $h->{TYPE}=$type;
                defined($json->{unitOfMeasure}) and $h->{UNIT}    = $json->{unitOfMeasure};
                defined($json->{minValue})      and $h->{MIN}     = $json->{minValue};
                defined($json->{maxValue})      and $h->{MAX}     = $json->{maxValue};
                defined($json->{allowedValues}) and $h->{ALLOWED} = join(" ",@{$json->{allowedValues}});
            }
            $h->{VALUE}     = $json->{value};
        } elsif ($type eq "switchProgram") {
            my @prog=();
            my $weekday;         
            foreach my $sp (@{$json->{switchPoints}}) {
                $weekday = $sp->{dayOfWeek};
                my $t = $sp->{time};
                my $h = int($t/60);
                my $entry = sprintf("%02d%02d %s",$h,$t-($h*60),$sp->{setpoint});
                my $num = $WdToNum{$weekday};
                $prog[$num] = defined $prog[$num] ? $prog[$num]." ".$entry : $entry;
                Log3 $hash, 5, "$hash->{NAME} update switchProgram $weekday $entry $sp->{time}";
            }
            my $i=1;
            foreach $weekday (qw(Mo Tu We Th Fr Sa Su)) {
                my $newid = "$id/$i-".$weekday;
                if(!defined $hash->{IDS}{$newid}) {
                    $hash->{IDS}{$newid}={
                        ID         => $newid,
                        TYPE       => $type,
                        WRITEABLE  => 1
                    }
                }
                $hash->{IDS}{$newid}{VALUE}  = $prog[$i++];
            } 
        } elsif ($type eq "errorList") {
            ### Sort list by timestamps
            my $err="";
            if(defined $json->{values}) {
                foreach my $entry (sort ( @{$json->{values}} )) {
                    $err .= sprintf("%-20.20s %-3.3s %-4.4s %-2.2s\n",
                                    $entry->{t}, $entry->{dcd}, $entry->{ccd}, $entry->{cat});
                }
            }
            if(!defined($h->{WRITEABLE})) { # initial
                $h->{WRITEABLE} = $json->{writeable};
                $h->{TYPE}      = "arrayData"; #is also arraydata
            }
            $h->{VALUE}     = $err;
        } elsif ($type eq "systeminfo" or $type eq "arrayData") {
            my $info="";
            if(defined $json->{values}) {
                foreach my $val (@{$json->{values}}) {
                    if(ref($val) eq 'HASH') {
                        $info .=join(" ", map { $_.":".$val->{$_} } keys %{$val})." ";
                    } else {
                        $info .= $val." ";
                    }
                }
                $info =~ s/ $//;
            }
            if(!defined($h->{WRITEABLE})) { # initial
                defined($json->{allowedValues}) and $h->{ALLOWED} = join(" ",@{$json->{allowedValues}});
                $h->{WRITEABLE} = $json->{writeable};
                $h->{TYPE}= "arrayData"; # info is also arraydata
            }
            $h->{VALUE}     = $info;
        } elsif ($type eq "yRecording") {
            defined $h->{TYPE} or $h->{TYPE}="Recroding";
            # ignore recordings - fhem records :-)
        } elsif ($type eq "refEnum") { # ignore directory entry
        } else {
            Log3 $hash, 2, "$hash->{NAME}: unknown type $type for $id";
        }
    } else {
        Log3 $hash, 5, "$hash->{NAME}: no JSON data available";
    }
}

sub BDKM_MapSwitchPrograms
{
    # translate all /dhwCircuits/dhw1/switchPrograms/A/\d-[A-z][A-z]$ forms to
    # one real reading like /dhwCircuits/dhw1/switchPrograms/A
    my $aref=$_[0];
    my %seen=();
    my $x;
    # substitution needs $x becaus because $_ would modify original array!!
    return grep {!$seen{$_}++} map {$x=$_; $x =~ s|/\d-[MTWTFS][ouehrau]$||;$x} @$aref;
}


1;

# perl ./contrib/commandref_join.pl FHEM/79_BDKM.pm
# perl ./contrib/commandref_join.pl 

=pod
=item device
=item summary support for Buderus KM-Gateways
=item summary_DE Unterst&uuml;tzung f&uuml;r Buderus KM-Gateways
=begin html

<a name="BDKM"></a>
<h3>BDKM</h3>
<ul>
    BDKM is a module supporting Buderus Logamatic KM gateways similar
    to the <a href="#km200">km200</a> module. For installation of the
    gateway see fhem km200 internet wiki<br> 

    Compared with the km200 module the code of the BDKM module is more
    compact and has some extra features.  It has the ablility to
    define how often a gateway ID is polled, which FHEM reading
    (alias) is generated for a gateway ID and which minimum difference
    to the last reading must exist to generate a new reading (see
    attributes).<br>  

    It determines value ranges, allowed values and writeability from
    the gateway supporting FHEMWEB and readingsGroup when setting
    Values (drop down value menues).<br>  

    On definition of a BDKM device the gateway is connected and a full
    poll collecting all IDs is done. This takes about 20 to 30
    seconds. After that the module knows all IDs reported
    by the gateway. To examine these IDs just type:<BR>
    <code>get myBDKM INFO</code><BR>

    These IDs can be used with the PollIds attribute to define if and
    how the IDs are read during the poll cycle. <br> All IDs can be
    mapped to own short readings. 
    <br><br>

  <a name="BDKMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; BDKM &lt;IP-address|hostname&gt; &lt;GatewayPassword&gt;
    &lt;PrivatePassword&gt; &lt;MD5-Salt&gt;</code><br> 
    or <br>
    <code>define &lt;name&gt; BDKM &lt;IP-address|hostname&gt;  &lt;AES-Key&gt;</code><br> 
    <br><br>
    <code>&lt;name&gt;</code> : 
        Name of device<br>
    <code>&lt;IP-address&gt;</code> : 
        The IP adress of your Buderus gateway<br>
    <code>&lt;GatewayPassword&gt;</code> : 
       The gateway password as printed on case of the gateway s.th. 
       of the form: xxxx-xxxx-xxxx-xxxx<br>
    <code>&lt;PrivatePassword&gt;</code>  : The private password as 
       set with the buderus App<br>
    <code>&lt;MD5-Salt&gt;</code>  : MD5 salt for the crypt 
    algorithm you want to use (hex string like 867845e9.....). Have a look for km200 salt 86 ... <br>
    AES-Key can be generated here:<br>
    https://ssl-account.com/km200.andreashahn.info<br>
    <br>
  </ul>
  <a name="BDKMset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;ID&gt; &lt;value&gt; ...</code>
    <br><br>
    where <code>ID</code> is a valid writeable gateway ID (See list command, 
    or "<code>get myBDKM INFO</code>")<br>
    The set command first reads the the ID from the gateway and also
    triggers a FHEM readings if necessary.  After that it is checked if the
    value is valid. Then the ID and value(s) are transfered to to the
    gateway. After waiting (attr ReadBackDelay milliseconds) the value
    is read back and checked against value to be set. If necessary again
    a FHEM reading may be triggered. The read back value or an error is 
    returned by the command. <br>

    Examples:
    <ul>
      <code>set myBDKM /heatingCircuits/hc1/temporaryRoomSetpoint 22.0</code><br>
      or the aliased version of it (if 
      /heatingCircuits/hc1/temporaryRoomSetpointee is aliased to 
      RoomTemporaryDesiredTemp):<br>
      <code>set myBDKM RoomTemporaryDesiredTemp 22.0</code><br>
      special to set time of gateway to the hosts date:<br>
      <code>set myBDKM /gateway/DateTime now</code><br>
      aliased:<br>
      <code>set myBDKM DateTime now</code><br>
    </ul>
    <br>
  </ul>
  <br>
  <a name="BDKMget"></a>
  <b>Get </b>
  <ul>
    <code>get &lt;name&gt; &lt;ID&gt; &lt;[raw|json]&gt;...</code><br><br> 
    where <code>ID</code> is a valid gateway ID or an alias to it.
    (See list command)<br> The get command reads the the ID from the
    gateway, triggeres readings if necessarry, and returns the value
    or an error if s.th. went wrong.  While polling is done
    asychronously with a non blocking HTTP GET. The set and get
    functions use a blocking HTTP GET/POST to be able to return a
    value directly to the user. Normaly get and set are only used by
    command line or when setting values via web interface.<br>
    With the <code>raw</code> option the whole original decoded data of the
    ID (as read from the gateway) is returned as a string.<br>  With
    the <code>json</code> option a perl hash reference pointing to the
    JSON data is returned (take a look into the module if you want to
    use that)<br>
    <br>

    Examples:
    <ul>
      <code>get myBDKM /heatingCircuits/hc1/temporaryRoomGetpoint</code><br>
      or the aliased version of it (see attr below):<br>
      <code>get myBDKM RoomTemporaryDesiredTemp</code><br>
      <code>get myBDKM DateTime</code><br>
      <code>get myBDKM /gateway/instAccess</code><br>
      Spacial to get Infos about IDs known by the gateway and own
      configurations:<BR>
      <code>get myBDKM INFO</code><br>
      Everything matching /temp/
      <code>get myBDKM INFO temp</code><br>
      Everything matching /Heaven/ or /Hell/
      <code>get myBDKM INFO Heaven Hell</code><br>
      Everything known:
      <code>get myBDKM INFO .*</code><br>
      Arguments to <code>INFO</code> are reqular expressions
      which are matched against all IDs and all aliases.
    </ul>
    <br>
  </ul>
  <br>

  <a name="BDKMattr"></a>
  <b>Attributes</b>
  <ul>
    <li>BaseInterval<br>
      The interval time in seconds between poll cycles.
      It defaults to 120 seconds. Which means that every 120 seconds a
      new poll collects values of IDs which turn it is.
    </li><br>
    <li>ReadBackDelay<br>
      Read back delay for the set command in milliseconds.  This value
      defaults to 500 (0.5s).  After setting a value, the gateway need
      some time before the value can be read back.  If this delay is
      too short after writing you will get back the old value and not
      the expected new one. The default should work in most cases.
    </li><br>
    <li>HttpTimeout<br>
      Timeout for all HTTP requests in seconds (polling, set,
      get). This defaults to 10s.  If there is no answer from the
      gateway for HttpTimeout time an error is returned. If a HTTP 
      request expires while polling an error log (level 2) is 
      generated and the request is automatically restarted after 60 
      seconds.
    </li><br>
    <li>PollIds<br>
      Without this attribute FHEM readings are NOT generated 
      automatically! <br>
      This attribute defines how and when IDs are polled within
      a base interval (set by atrribute <code>BaseInterval</code>).<br>
      The attribute contains list of space separated IDs and options 
      written as <br>
      <code>GatewayID:Modulo:Delta:Alias</code>
      <br>
      Where Gateway is the real gateway ID like "/gateway/DateTime".<br>
      Modulo is the value which defines how often the GatewayID is
      polled from the gateway and checked for FHEM readings update.
      E.g. a value of 4 means that the ID is polled only every 4th cycle.<br>
      Delta defines the minimum difference a polled value must have to the 
      previous reading, before a FHEM reading with the new value is generated.<br>
      Alias defines a short name for the GatewayID under which the gateway ID
      can be accessed. Also readings (Logfile entries) are generated with this
      short alias if set. If not set, the original ID is used.<br>
      In detail:<br>
      <code>ID:1:0:Alias</code> - poll every cycle, when difference >= 0 to previous reading (means always, also for strings) trigger FHEM reading to "Alias"<br>
      <code>ID:1::Alias</code> -  poll every cycle, no Delta set => trigger FHEM reading to "Alias" on value change only<br>
      <code>ID:0::Alias</code> -  update reading on startup once if reading changed (to the one prevously saved in fhem.save)<br>
      <code>ID:1:0.5:Alias</code> - poll every cycle, when difference => 0.5 trigger a FHEM reading to "Alias"<br>
      <code>ID:15::Alias</code> - poll every 15th cylce, update reading only if changed<br>
      <code>ID:::Alias</code> - update reading on (get/set) only and only if value changed<br>
      <code>ID::0:Alias</code> - update reading on (get/set) only and trigger reading always on get/set<br>
      <code>ID</code> - without colons ":", poll every cycle, update reading allways (same as <code>ID:1:0:</code>)<br>
      Also some usefull defaults can be set by the special keyword RC300DEFAULTS, RC35DEFAULTS, RC30DEFAULTS.<br>
      As I don't know anything about RC35 or RC30 the later keywords are currently empty (please send me some info with "get myBDKM INFO" :-)<br>
      Definitions set by the special keywords (see the module code for it) are overwritten by definitions later set in the attribute definition<br>
      Example:
      <ul>
        <code>attr myBDKM PollIds \<br>
                RC300DEFAULTS \<br>
                /gateway/DateTime:0::Date \<br>
                /system/info:0:0:\<br>
                /dhwCircuits/dhw1/actualTemp:1:0.2:WaterTemp
        </code><br>
      </ul>
        Which means: Use RC300DEFAULTS, trigger FHEM reading "Date" when date has changed on startup only. Trigger FHEM reading "/system/info" (no aliasing) always on startup, poll water temperature every cycle and trigger FHEM reading "WaterTemp" when difference to last reading was at least 0.2 degrees.
      <br>
    </li><br>
    </ul>
</ul>

=end html
