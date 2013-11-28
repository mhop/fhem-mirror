########################################################################
#*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA 
# 95_RRD_Log.pm
# Feedback: http://groups.google.com/group/fhem-users 
# Logging to RRDs
# Autor: a[PUNKT]r[BEI]oo2p[PUNKT]net
# Stand: 13.04.2010
# Version: 0.9.0
#*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA
#######################################################################
#*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA
# First:
# Install Perl-RRDs-Lib:
# debian/Ubunut: apt-get install librrds-perl
#
# Usage:
# define <NAME< RRD_Log <path_to_rrd>
# set <NAME> ADD/DEL <DEV-NAME> READING_1:READING_2 ...
#
# For each READING one RRD-File
# Beispiel FHT-Name: FHT001
# set <My-RRDLOG> ADD FHT001 measured_temperature:desired_temperature:actuator
# Created RRD-Files
# measured-temp => <path_to_rrd>/FHT001/measured_temperature.rrd
# desired-temp => <path_to_rrd>/FHT001/desired_temperature.rrd
# actuator => <path_to_rrd>/FHT001/actuator.rrd
#
# => To view the Files: http://web.taranis.org/drraw/
#
# For each READINNG you can create seperate RRD-Definitions:
# %data{RRD_LOG}{DEV_TYPE}{READINGS} = RRD_LOG_TYPE
# 
# Update :
#
# - keine Ueberpruefung ob READING vorhanden ist im SET
#
# attr -> IODEVSTATS
# If set RRD_Log will log RSSI and MSGCNT
# <IDOEV-Name>/<DEVICE_Name>_rssi RRD: RRD_Log_5minGAUGE
# <IDOEV-Name>/<DEVICE_Name>_msgcnt RRD: RRD_Log_5minCOUNTER
# also
# <IDOEV-Name>_MSGCNT -> Counter for received Messeages by this IODEV
# <IDOEV-Name>/RAWMSGCOUNT.rrd
#
# ADDTYPE
# set RRDLog ADDTYPE HMS
# es werden alle Devices des Types HMS dem RRDLog zugeordnet
# enpstrechend den konfigurierten READINGs in $data{RRD_LOG}{READING}
#
#
#*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA*BETA
#######################################################################
package main;
use strict;
use warnings;
use POSIX;
use Data::Dumper;
use RRDs;
use vars qw(%data);
#######################################################################
sub
RRD_Log_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "RRD_Log_Define";
  $hash->{SetFn}    = "RRD_Log_Set";
  $hash->{NotifyFn} = "RRD_Log_Notify";
  $hash->{AttrList}  = "do_not_notify:0,1 loglevel:0,5 disable:0,1 IODEVSTATS";
  
  # Global RRDLog conf
  # Mapping READING to RRD-File-Config
  # %data{RRD_LOG}{DEV_TYPE}{READINGS} = RRD_LOG_TYPE
  #FHT
  $data{RRD_LOG}{READING}{FHT}{'measured-temp'} = "RRD_Log_15minGAUGE";
  $data{RRD_LOG}{READING}{FHT}{'desired-temp'} = "RRD_Log_15minGAUGE";
  $data{RRD_LOG}{READING}{FHT}{'actuator'} = "RRD_Log_5minGAUGE";
  #HMS
  $data{RRD_LOG}{READING}{HMS}{'temperature'} = "RRD_Log_5minGAUGE";
  $data{RRD_LOG}{READING}{HMS}{'humidity'} = "RRD_Log_5minGAUGE";
  # KS300
  $data{RRD_LOG}{READING}{KS300}{'rain_15min'} = "RRD_Log_15minGAUGE";
  $data{RRD_LOG}{READING}{KS300}{'rain_now'} = "RRD_Log_5minGAUGE";
  $data{RRD_LOG}{READING}{KS300}{'rain'} = "RRD_Log_5minCOUNTER";
  $data{RRD_LOG}{READING}{KS300}{'temperature'} = "RRD_Log_5minGAUGE";
  $data{RRD_LOG}{READING}{KS300}{'humidity'} = "RRD_Log_5minGAUGE";
  $data{RRD_LOG}{READING}{KS300}{'wind'} = "RRD_Log_5minGAUGE";
  # CUL_WS => S55TH&S300TH
  $data{RRD_LOG}{READING}{CUL_WS}{'temperature'} = "RRD_Log_5minGAUGE";
  $data{RRD_LOG}{READING}{CUL_WS}{'humidity'} = "RRD_Log_5minGAUGE";
  #CUL_EM
  $data{RRD_LOG}{READING}{CUL_EM}{'current'} = "RRD_Log_5minGAUGE";
  #FS20
  $data{RRD_LOG}{READING}{FS20}{'state'} = "RRD_Log_10secGAUGE";
  # IODEVSTATS=CUL
  $data{RRD_LOG}{READING}{CUL}{'msg'} = "RRD_Log_5minCOUNTER";
  $data{RRD_LOG}{READING}{CUL}{'rssi'} = "RRD_Log_5minGAUGE";
  $data{RRD_LOG}{READING}{CUL}{'RAWMSGCOUNT'} = "RRD_Log_5minGAUGE";
  # IODEVSTATS=FHZ
  $data{RRD_LOG}{READING}{FHZ}{'msg'} = "RRD_Log_5minCOUNTER";
  $data{RRD_LOG}{READING}{FHZ}{'rssi'} = "RRD_Log_5minGAUGE";
  $data{RRD_LOG}{READING}{FHZ}{'RAWMSGCOUNT'} = "RRD_Log_5minGAUGE";
  # IODEVSTATS=CUL_RFR
  $data{RRD_LOG}{READING}{CUL_RFR}{'msg'} = "RRD_Log_5minCOUNTER";
  $data{RRD_LOG}{READING}{CUL_RFR}{'rssi'} = "RRD_Log_5minGAUGE";
  $data{RRD_LOG}{READING}{CUL_RFR}{'RAWMSGCOUNT'} = "RRD_Log_5minGAUGE";
  #WBS
  $data{RRD_LOG}{READING}{WBS}{'Temperature'} = "RRD_Log_5minGAUGE";
  # ALL4000T
  $data{RRD_LOG}{READING}{ALL4000T}{'Temperature'} = "RRD_Log_5minGAUGE";
  # temp. save Path to RRDs
  # $data{RRD_LOG}{RRDS}{<DEVICE-NAME>}{<READING>} = $rrd_path
  # reset RRS
  delete $data{RRD_LOG}{RRDS};
  #RESET RAWMSGCNT
  delete $data{RRD_LOG}{RAWMSGCOUNT}
}
#######################################################################
sub RRD_Log_Define()
{
 # define RRD001 RRD_Log <path_to_rrd>
    my ($self, $defs) = @_;
    my @a = split(/ /, $defs);
    my($package, $filename, $line, $subroutine) = caller(3);
    Log 5, "RRDLOG[Define]: $package: $filename LINE: $line SUB: $subroutine \n";
    return "RRDLOG[Define::ERROR] Unknown argument count " . int(@a) . " , usage set <name> RRD_Log <Path>"  if(int(@a) != 3);
    # RRDPath
    my $rrdpath = $a[2];
    if(!-d $rrdpath) {
        return "RRDLOG[Define::ERROR] Invalid Path: $rrdpath";}
    $self->{RRDPATH} = $a[2];
    #RRD Startdate
    $self->{RRD_Start_Date_tsecs} =  time();
    $self->{RRD_Start_Date} =  TimeNow();
    #LogLevel auf 5
    my $my_name = $self->{NAME};
    $attr{$my_name}{'loglevel'} = '5';
    return undef;
}
#######################################################################
sub RRD_Log_Set() {
  # set <NAME> ADD/DEL <DEVICENAME> READING_1:READING_2:READING_3
  my ($hash, @a) = @_ ;
  return "" if($attr{$hash->{NAME}} && $attr{$hash->{NAME}}{disable});
  # FHEMWEB Frage....Auswahliste
  return "RRDLOG[SET::ERROR] Unknown argument $a[1], choose one of ". join(" ",sort keys %{$hash->{READINGS}}) if($a[1] eq "?");
  #LogLevel
  my $ll = $attr{$hash->{NAME}}{'loglevel'};
  # Pruefen Uebergabeparameter
  # @a => a[0]:<NAME>; a[1]=ADD oder DEL; a[2]= DeviceName;
  # a[3]=READING_1:READING_2:READING_3
  # READINGS setzten oder löschen
  if($a[1] eq "DEL")
    {
    Log $ll,"RRDLOG[SET] DELETE: A0= ". $a[0] . " A1= " . $a[1] . " A2=" . $a[2];
    if(defined($hash->{READINGS}{$a[2]}))
      {
      delete($hash->{READINGS}{$a[2]})
      }
    }
    if($a[1] eq "ADDTYPE") {
        my $add_type = $a[2];
        if(!defined($data{RRD_LOG}{READING}{$add_type})) {return "RRDLOG[SET::ERROR] $a[2] => Unkown Type";}
        my ($reading,$reading_list);
        foreach $reading (keys %{$data{RRD_LOG}{READING}{$add_type}}) {
            $reading_list .= ":" . $reading;
        }
        $reading_list = reverse($reading_list);
        chop($reading_list);
        $reading_list = reverse($reading_list);
        my ($device);
        foreach $device (sort keys %defs) {
            next if($defs{$device}{TYPE} ne $add_type);
            $hash->{READINGS}{$device}{TIME} = TimeNow();
            $hash->{READINGS}{$device}{VAL} = $reading_list;
        }
    }
    if($a[1] eq "ADD") {
        # Device check
        if(!defined($defs{$a[2]})) {return "RRDLOG[SET::ERROR] $a[2] => Unkown Device";}
        # Mindestens 3 Parameter
        my @readings = split(/:/, $a[3]);
        return "RRDLOG[SET::ERROR] No READING found "  if(int(@readings) < 1);
        # Reading check
        my $def_type = $defs{$a[2]}{TYPE};
        foreach my $reading (@readings){
            # if(!defined($defs{$a[2]}{READINGS}{$reading})) {return "RRDLOG[SET::ERROR] $a[2] => $reading => Unkown";}
            if(!defined($data{RRD_LOG}{READING}{$def_type}{$reading})) {return "RRDLOG[SET::ERROR] $a[2]  => $reading => not supported";}
            }
        $hash->{READINGS}{$a[2]}{TIME} = TimeNow();
        $hash->{READINGS}{$a[2]}{VAL} = $a[3];
        $hash->{CHANGED}[0] = $a[1];
        $hash->{STATE} = $a[1];
    }
  return undef; 
}
#######################################################################
sub RRD_Log_Notify() {
    my ($self, $changed_device) = @_;
    my $my_name = $self->{NAME};
    return "" if($attr{$my_name} && $attr{$my_name}{disable});
    #LogLevel
    my $ll = $attr{$my_name}{'loglevel'};
#    Log $ll, "RRDLOG[DEF::DUMPER]" . Dumper($changed_device);
    
    my $dev_name = $changed_device->{NAME};
    # Not Undefined Devices
    if(lc($dev_name) eq "undefined") {
        Log $ll,"RRDLOG[Notify::ERROR] Undefined Device";
        return undef;}
    # Device configured
    if(!defined($defs{$my_name}{READINGS}{$dev_name})){
        Log $ll,"RRDLOG[Notify::ERROR] $dev_name => Not configured";
        return undef;}
    # Readings configured
    ### if $d_reading =~ m//
    my %dev_name_readings;
    foreach my $d_reading (split(/:/,$defs{$my_name}{READINGS}{$dev_name}{VAL})) {
        $dev_name_readings{$d_reading} = 1 ;
        }
    my $max = int(@{$defs{$dev_name}{CHANGED}});
    my ($changed_reading, $changed_value);
    #FS20 => CHANGED => [on],
    my $timestamp = time();
    # IODEVSTATS
    if(defined($attr{$my_name}{IODEVSTATS}) && defined($defs{$dev_name}{LASTIODev})){
        Log $ll,"RRDLOG|IODEVSTATS|$dev_name: " . $defs{$dev_name}{LASTIODev};
        # 'LASTIODev' => 'MyCUL',MyCUN_MSGCNT' => 1,MyCUN_RSSI' => '-79.5',
        # Aufruf RRD_Log_disptach_reading(RRD_LOG,LASTIODev,READING,VALUE,$timestamp);
        # Maximal 19 Zeichen DS-Name
        my $LASTIODev = $defs{$dev_name}{LASTIODev};
        my $iostat_reading = $dev_name . "_rssi";
        my $iostat_index = $LASTIODev . "_RSSI";
        $iostat_reading =~ s/\./_/g ;
        my $cul_rssi_return;
        if(defined($defs{$dev_name}{$iostat_index})){
            my $iodev_rssi = $defs{$dev_name}{$iostat_index};
        # RSSI ist negativ...wollen aber nur positive Werte
        if($iodev_rssi =~ m/-/){$iodev_rssi =~ s/-//;}
            Log $ll,"RRDLOG|IODEVSTATS|RSSI|RRD_Log_disptach_reading: $self,$LASTIODev,$iostat_reading ,$iodev_rssi,$timestamp";
            $cul_rssi_return = &RRD_Log_disptach_reading($self,$LASTIODev,$iostat_reading ,$iodev_rssi,$timestamp);
        }
        $iostat_index = $LASTIODev . "_MSGCNT";
        $iostat_reading = $dev_name . "_msg";
        $iostat_reading =~ s/\./_/g ;
        my $iodev_msgcnt = $defs{$dev_name}{$iostat_index };
        Log $ll,"RRDLOG|IODEVSTATS|MSGCNT|RRD_Log_disptach_reading: $self,$LASTIODev,$iostat_reading ,$iodev_msgcnt,$timestamp";
        $cul_rssi_return = &RRD_Log_disptach_reading($self,$LASTIODev,$iostat_reading ,$iodev_msgcnt,$timestamp);
        #RAWMSGCOUNT
        # 5min Werte = 300sec
        if(defined($defs{$LASTIODev}{"${LASTIODev}_MSGCNT"})){
        #INIT
        my $tsecs = time();
        my $secs = 300;
        my $msgcnt = $defs{$LASTIODev}{"${LASTIODev}_MSGCNT"};
        if(!defined($data{RRD_LOG}{RAWMSGCOUNT}{$LASTIODev})){
          $data{RRD_LOG}{RAWMSGCOUNT}{$LASTIODev}{TSECS} = $tsecs;
          $data{RRD_LOG}{RAWMSGCOUNT}{$LASTIODev}{CNT} = $msgcnt;
          Log $ll,"RRDLOG|IODEVSTATS|RAWMSGCOUNT|$LASTIODev|INIT:" . $msgcnt;
          }
        #Calculate
        my $calc_next =  $tsecs - $data{RRD_LOG}{RAWMSGCOUNT}{$LASTIODev}{TSECS};
        Log $ll,"RRDLOG|IODEVSTATS|RAWMSGCOUNT|$LASTIODev|calc_next: $calc_next";
        if($calc_next > $secs) {
          $iodev_msgcnt = $msgcnt - $data{RRD_LOG}{RAWMSGCOUNT}{$LASTIODev}{CNT};
          $iostat_reading = "RAWMSGCOUNT";
          Log $ll,"RRDLOG|IODEVSTATS|RAWMSGCOUNT|$LASTIODev|RRD_Log_disptach_reading: $self,$LASTIODev,$iostat_reading ,$iodev_msgcnt,$timestamp";
          $cul_rssi_return = &RRD_Log_disptach_reading($self,$LASTIODev,$iostat_reading ,$iodev_msgcnt,$timestamp);
          $data{RRD_LOG}{RAWMSGCOUNT}{$LASTIODev}{TSECS} = $tsecs;
          $data{RRD_LOG}{RAWMSGCOUNT}{$LASTIODev}{CNT} = $msgcnt;
          $data{RRD_LOG}{RAWMSGCOUNT}{$LASTIODev}{LAST} = $iodev_msgcnt;
          Log $ll,"RRDLOG|IODEVSTATS|RAWMSGCOUNT|$LASTIODev|Update: $tsecs|" . $msgcnt . "|$iodev_msgcnt";
          }
        }
        #RAWMSGCOUNT
        }
    # IODEVSTATS
    # Loop $def{<NAME>}{CHANGED}[i]
    for(my $i = 0; $i < $max; $i++) {
        Log $ll,"RRDLOG[Notify] $dev_name => " . $defs{$dev_name}{CHANGED}[$i];
        # Handle Changed READINGS
        # Abzweig falls eine Funktion für READING angegeben wurde...foreach
        if($defs{$dev_name}{TYPE} eq "FS20"){
            $changed_reading = "state";
            $changed_value = $defs{$dev_name}{CHANGED}[$i];
            }
        else {
            ($changed_reading, $changed_value) = split(/:/,$defs{$dev_name}{CHANGED}[$i]);
        }
        if(!defined($defs{$dev_name}{READINGS}{$changed_reading})) {
          Log 0, "RRDLOG[NOTIFY::ERROR] $dev_name => $changed_reading => Unkown";
          next;}
          Log $ll, "RRDLOG[Notify] $dev_name => $changed_reading => $changed_value";
          #Trim
          if($changed_reading =~ m/^\s+/) {$changed_reading =~ s/^\s+//;}
          if($changed_reading =~ m/\s+$/) {$changed_reading =~ s/\s+$//;}
          if($changed_reading =~ m/^\s+/) {$changed_value =~ s/^\s+//;}
          if($changed_reading =~ m/\s+$/) {$changed_value =~ s/\s+$//;}
          next if (!defined($dev_name_readings{$changed_reading}));
          my $rrd_dispatch_return = &RRD_Log_disptach_reading($self,$dev_name,$changed_reading,$changed_value,$timestamp);
    }
}
########################################################################
sub RRD_Log_disptach_reading($$$) {
    my ($self,$changed_device,$changed_reading,$changed_value,$changed_timestamp ) = @_;
    #LogLevel
    my $ll = $attr{$self->{NAME}}{'loglevel'};
    Log $ll, "RRDLOG[Disptach] $changed_device => $changed_reading => $changed_value";
    # Reading To Number
    $changed_value = &RRD_Log_ReadingToNumber($changed_value,$ll);
    Log $ll, "RRDLOG[Disptach] $changed_device => $changed_reading => $changed_value";
    if(!defined($changed_value)) {
        Log 0, "RRDLOG[Disptach::ERROR] Invalid Value = $changed_value";
        return undef;
    }
    # Exists
    my $rrd_file;
    if(defined($data{RRD_LOG}{RRDS}{$changed_device}{$changed_reading})) {
        # Get RRD File
        $rrd_file = $data{RRD_LOG}{RRDS}{$changed_device}{$changed_reading};
        #File exists
        if(-e $rrd_file) {
            Log $ll, "RRDLOG[Disptach] $changed_device => $changed_reading => $changed_value";
            # Update Values in RRD
            my $rrd_last = RRDs::last ($rrd_file);
            my $rrd_update = "$changed_timestamp:$changed_value";
            Log $ll, "RRDLOG[Disptach] $changed_device => $changed_reading => RRD-Update: $rrd_update";
            RRDs::update ($rrd_file , $rrd_update);
            my $rrd_new = RRDs::last ($rrd_file);
            Log $ll, "RRDLOG[Disptach] $changed_device => $changed_reading => RRDS $rrd_last => $rrd_new";
            return undef;
        }
        else {
            Log 0, "RRDLOG[Disptach::ERROR] DISPATCHER => File not found => $rrd_file";
            return undef;}
    }
    # Create New RRD or Add to hash
    my $changed_device_type = $defs{$changed_device}{TYPE};
    #CUL-Weiche
    if($changed_device_type eq "CUL" && $changed_device_type eq "FHZ" && $changed_device_type eq "CUL_RFR"){
    if(!defined($data{RRD_LOG}{READING}{$changed_device_type})) {
        Log $ll, "RRDLOG|Disptach|CUL_WEICHE: $changed_device Type $changed_device_type not configured";
        return undef;}
    }
    Log $ll, "RRDLOG[Disptach] $changed_device => Type => $changed_device_type";
    
    # Pruefen on File bereits existiert und nur im HASH nachgetragen werden muss
    # Falls nein => NEU ANLAGE
    # File exists
    # Timestamp 
    my $timestamp = $self->{RRD_Start_Date_tsecs};
    my $rrd_path = $self->{RRDPATH};
    # Backslash
    $rrd_path =~ s/\/$//;
    $rrd_path = $rrd_path . "/" . $changed_device;
    $rrd_file = $rrd_path . "/" . $changed_reading . ".rrd";
    # RRD-file exists => ADD to HASH
    if(-e $rrd_file) {
        # Add to hash
        $data{RRD_LOG}{RRDS}{$changed_device}{$changed_reading} = $rrd_file;
        # Update Values in RRD
        my $rrd_last = 0;
        my $rrd_new = 0;
        $rrd_last = RRDs::last ($rrd_file);
        my $rrd_update = "$changed_timestamp:$changed_value";
        Log $ll, "RRDLOG[Disptach] $changed_device => $changed_reading => RRD-Update: $rrd_update";
        RRDs::update ($rrd_file , $rrd_update);
        $rrd_new = RRDs::last ($rrd_file);
        Log $ll, "RRDLOG[Disptach] $changed_device => $changed_reading => RRDS $rrd_last => $rrd_new";
        return undef;
        }
    # NEU ANLAGE
    # Create Directoty
    my $rrd_path_ok;
    if(!-d $rrd_path) {
        $rrd_path_ok=mkdir($rrd_path,0777);
        }
    no strict "refs";
    
    my $rrd_create_func;
    if($changed_device_type eq "CUL" || $changed_device_type eq "FHZ" || $changed_device_type eq "CUL_RFR"){
        my $cul_reading;
        if(lc($changed_reading) =~ m/_rssi$/){$cul_reading = "rssi";}
        if(lc($changed_reading) =~ m/_msg$/){$cul_reading = "msg";}
        if(lc($changed_reading) eq "RAWMSGCOUNT"){$cul_reading = "RAWMSGCOUNT";}
        $rrd_create_func = $data{RRD_LOG}{READING}{"CUL"}{$cul_reading};
        Log $ll, "RRDLOG[Disptach] CUL -> rrd_create_func = $rrd_create_func";
        }
    else {$rrd_create_func =  $data{RRD_LOG}{READING}{$changed_device_type}{$changed_reading};}
    if(!defined($rrd_create_func)){
      Log $ll, "RRDLOG[ERRROR] dispatch rrd_create_func $changed_device_type:$changed_reading Function not defined";
      return undef;
    }
    $rrd_file = &$rrd_create_func($self,$changed_device,$changed_reading,$rrd_file,$timestamp);
    use strict "refs";
    if($rrd_file) {
        # Add to hash
        $data{RRD_LOG}{RRDS}{$changed_device}{$changed_reading} = $rrd_file;
        # Update Values in RRD
        my $rrd_last = 0;
        my $rrd_new = 0;
        $rrd_last = RRDs::last ($rrd_file);
        my $rrd_update = "$changed_timestamp:$changed_value";
        Log $ll, "RRDLOG[Disptach] $changed_device => $changed_reading => RRD-Update: $rrd_update";
        RRDs::update ($rrd_file , $rrd_update);
        $rrd_new = RRDs::last ($rrd_file);
        Log $ll, "RRDLOG[Disptach] $changed_device => $changed_reading => RRDS $rrd_last => $rrd_new";
    }
    
}
########################################################################
sub RRD_Log_ReadingToNumber($$)
{
# Input: reading z.B. 21.1 (Celsius) oder dim10%, on-for-oldtimer etc.
# Output: 21.1 oder 10
# ERROR = undef
# Alles außer Nummern loeschen $t =~ s/[^0123456789.]//g; 
	my ($in,$ll) = @_;
	Log $ll, "RRDLOG[ReadingToNumber] In => $in";
	# Bekannte READINGS FS20 Devices oder FHT
	if($in =~ /^on|Switch.*on|israining:.*yes|^yes/i) {$in = 10;}
	if($in =~ /^off|Switch.*off|toggle|israining:.*no|^no/i) {$in = 5;}
    if($in =~ /lime-protection|syncnow/i) {$in = 0;}
	# Keine Zahl vorhanden
	if($in !~ /\d{1}/) {
        Log $ll, "RRDLOG[ReadingToNumber] No Number: $in";
        return undef;}
	# Mehrfachwerte in READING z.B. CUM_DAY: 5.040 CUM: 334.420 COST: 0.00
	my @b = split(' ', $in);
	if(int(@b) gt 2) {
        Log $ll, "RRDLOG[ReadingToNumber] CUM_DAY: $in";
        return undef;}
	# Nur noch Zahlen z.B. dim10% = 10 oder 21.1 (Celsius) = 21.1
    if (int(@b) eq 2){
        Log $ll, "RRDLOG[ReadingToNumber] Split:WhiteSpace-0- $b[0]";
        $in = $b[0];
        }
    $in =~ s/[^0123456789\.-]//g;
	Log $ll, "RRDLOG[ReadingToNumber] Out => $in";
	return scalar($in);
}
################################################################################
sub RRD_Log_5minGAUGE($$$){
    my ($self,$changed_device,$changed_reading,$rrd_file,$timestamp) = @_;
    # Log 0, "RRDLOG-5min- $self,$changed_device,$changed_reading,$rrd_file,$timestamp";
    # Create RRD
    # Tagesverlauf: Alle 5 min ein neuer Wert 
    # --step 300
    # min Value = -30
    # max Value = 100
    # 3 Werte = 15min koennen ausfallen => Hartbeat 900
    # DS:<temp>:GAUGE:900:-20:100
    # 5 min Werte 5 Tag speicherne => 12 Werte/h * 24 * 5  = 1440
    # RRA:AVERAGE:0.5:1:1440
    # 15min Werte 6 Monat lang speichern
    # 15min/5min = 3, 4 Werte/h * 24 * 30 * 6 = 17280
    # RRA:AVERAGE:0.5:3:17280
    # 30min  Werte 5 Jahre speichern
    # 30min/5min = 6; 6 Werte/h * 24 * 365 * 5 = 262800
    # RRA:AVERAGE:0.5:6:262800
    # Min/Max Werte = 4 pro Tag für 5 Jahre
    # (4*60)/5min =  48; 4 Werte/Tag * 365 * 5 = 7300
    # RRA:MIN:0.5:48:7300
    # RRA:MAX:0.5:48:7300
    # Last 100 Werte
    # RRD:LAST:1:1:100
    Log 0, "RRDLOG[5minCOUNTER] => NEW RRD-FILE => $rrd_file => Start: $timestamp";
    RRDs::create($rrd_file,
    "--step=120",
    "--start=$timestamp",
    "DS:$changed_reading:GAUGE:900:-20:100",
    "RRA:MIN:0.5:48:7300",
    "RRA:MAX:0.5:48:7300",
    "RRA:AVERAGE:0.5:3:17280",
    "RRA:AVERAGE:0.5:6:262800",
    "RRA:AVERAGE:0.5:1:1440");
    my $ERR=RRDs::error;
    if (defined($ERR)) {
        Log 0, "RRDLOG[5minGAUGE]::ERROR Create RRD: $ERR";
        return undef;}  
    else {return $rrd_file;}
}
################################################################################
sub RRD_Log_5minCOUNTER($$$){
    my ($self,$changed_device,$changed_reading,$rrd_file,$timestamp) = @_;
    # Create RRD
    # Tagesverlauf: Alle 5 min ein neuer Wert 
    # --step 300
    # min Value = -30
    # max Value = 100
    # 3 Werte = 15min koennen ausfallen => Hartbeat 900
    # DS:<temp>:GAUGE:900:-20:100
    # 5 min Werte 5 Tag speicherne => 12 Werte/h * 24 * 5  = 1440
    # RRA:AVERAGE:0.5:1:1440
    # 15min Werte 6 Monat lang speichern
    # 15min/5min = 3, 4 Werte/h * 24 * 30 * 6 = 17280
    # RRA:AVERAGE:0.5:3:17280
    # 30min  Werte 5 Jahre speichern
    # 30min/5min = 6; 6 Werte/h * 24 * 365 * 5 = 262800
    # RRA:AVERAGE:0.5:6:262800
    # Min/Max Werte = 4 pro Tag für 5 Jahre
    # (4*60)/5min =  48; 4 Werte/Tag * 365 * 5 = 7300
    
    Log 0, "RRDLOG[5minCOUNTER] => NEW RRD-FILE => $rrd_file => Start: $timestamp";
    RRDs::create($rrd_file,
    "--step=120",
    "--start=$timestamp",
    "DS:$changed_reading:COUNTER:900:0:1000",
    "RRA:AVERAGE:0.5:3:17280",
    "RRA:AVERAGE:0.5:6:262800",
    "RRA:AVERAGE:0.5:1:1440");
    my $ERR=RRDs::error;
    if (defined($ERR)) {
        Log 0, "RRDLOG[5minCOUNTER]::ERROR Create RRD: $ERR";
        return undef;}  
    else {return $rrd_file;}
}
################################################################################
sub RRD_Log_15minGAUGE($$$){
    my ($self,$changed_device,$changed_reading,$rrd_file,$timestamp) = @_;
    # FHT => measured-temp ~ 4 Werte/Stunde
    # Create RRD
    # Tagesverlauf: Alle 15 min ein neuer Wert 
    # --step 900
    # min Value = 0
    # max Value = 100
    # 3 Werte = 45min koennen ausfallen => Hartbeat 2700
    # DS:<temp>:GAUGE:1800:0:70
    # 15 min Werte 30 Tag speicherne => 4 Werte/h * 24 * 30  = 2880
    # RRA:AVERAGE:0.5:1:2880
    # 30min Werte 5 Jahre lang speichern
    # 30min/15min = 2, 2 Werte/h * 24 * 30 * 6 * 5 = 43200
    # RRA:AVERAGE:0.5:2:43200
    # Min/Max Werte = 4 pro Tag (alle 6h) )für 5 Jahre
    # 6h/15min =  12; 4 Werte/Tag * 365 * 5 = 7300
    # RRA:MIN:0.5:12:7300
    # RRA:MAX:0.5:12:7300

    
    Log 0, "RRDLOG[5minCOUNTER] => NEW RRD-FILE => $rrd_file => Start: $timestamp";
    RRDs::create($rrd_file,
    "--step=900",
    "--start=$timestamp",
    "DS:$changed_reading:GAUGE:2700:0:70",
    "RRA:MIN:0.5:12:7300",
    "RRA:MAX:0.5:12:7300",
    "RRA:AVERAGE:0.5:1:2880",
    "RRA:AVERAGE:0.5:2:43400",
    "RRA:AVERAGE:0.5:1:1880");
    my $ERR=RRDs::error;
    if (defined($ERR)) {
        Log 0, "RRDLOG[15minGAUGE]::ERROR Create RRD: $ERR";
        return undef;}  
    else {return $rrd_file;}
}
################################################################################
sub RRD_Log_10secGAUGE($$$){
    my ($self,$changed_device,$changed_reading,$rrd_file,$timestamp) = @_;
    #
    # RRSI 
    # alle 10sec einen Wert 8640 Werte pro Tag
    # für 5 Tage = 43200
    # Archiv 15min für 6 Monate
    # 90 => 4/h * 24 * 30 * 6 = 17280
    
    Log 0, "RRDLOG[10secGAUGE] => NEW RRD-FILE => $rrd_file => Start: $timestamp";
    RRDs::create($rrd_file,
    "--step=10",
    "--start=$timestamp",
    "DS:$changed_reading:GAUGE:10:-100:100",
    "RRA:AVERAGE:0.5:1:43200",
    "RRA:AVERAGE:0.5:90:17280");
    my $ERR=RRDs::error;
    if (defined($ERR)) {
        Log 0, "RRDLOG[10secGAUGE]::ERROR Create RRD: $ERR";
        return undef;}  
    else {return $rrd_file;}
}
################################################################################
sub RRD_Log_10minDERIVE($$$){
    my ($self,$changed_device,$changed_reading,$rrd_file,$timestamp) = @_;
    print "$self,$changed_device,$changed_reading,$rrd_file,$timestamp\n";
    # 30 Tage 10min Werte => 4320
    # 5 Jahre 30min Werte => 86700
    # 4 Max-Werte pro tag für 5 Jahre = 6h/30min = 12 => 7300
    #    "RRA:MAX:0.5:1:7300","RRA:AVERAGE:0.5:12:7300"
    Log 0, "RRDLOG[5minCOUNTER] => NEW RRD-FILE => $changed_reading => $rrd_file => Start: $timestamp";
    RRDs::create($rrd_file,
        "--step=60",
        "--start=$timestamp",
        "DS:$changed_reading:DERIVE:120:0:1000",
        "RRA:MAX:0.5:1:7300",
        "RRA:AVERAGE:0.5:12:7300",
        "RRA:AVERAGE:0.5:1:4320");
    my $ERR=RRDs::error;
    if (defined($ERR)) {
        Log 0, "RRDLOG[10minDERIVE]::ERROR Create RRD: $ERR";
        return undef;}  
    else {return $rrd_file;}
}
1;
