###############################################
#
# 47_OBIS.pm
#
# 
# $Id$

package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday usleep);

my %OBIS_channels = ( "21"=>"energy_L1",
                 "41"=>"energy_L2",
                 "61"=>"energy_L3",
                 "32"=>"voltage_L1",
                 "52"=>"voltage_L2",
                 "72"=>"voltage_L3",
                 "31"=>"power_L1",
                 "51"=>"power_L2",
                 "71"=>"power_L3",
                 "2"=>"feed_L1",
                 "4"=>"feed_L2",
                 "6"=>"feed_L3",
                 "1"=>"energy_current");

    
#####################################
sub OBIS_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{Match}     = ".*";
  $hash->{ReadFn}  = "OBIS_Read";
  $hash->{ReadyFn}  = "OBIS_Ready";
  $hash->{DefFn}   = "OBIS_Define";
  $hash->{ParseFn}   = "OBIS_Parse";
  $hash->{UndefFn} = "OBIS_Undef";
  $hash->{AttrFn}	= "OBIS_Attr";
  $hash->{AttrList}= "do_not_notify:1,0 interval offset_feed offset_energy IODev channels ".
  					  $readingFnAttributes;
  Log3 $hash,4,"OBIS - Initialize done...";
}

#####################################
sub OBIS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return 'wrong syntax: define <name> OBIS devicename@baudrate[,databits,parity,stopbits]|none [MeterType]'
    if(@a < 3);

  DevIo_CloseDev($hash);
  RemoveInternalTimer($hash);  
  my $name = $a[0];
  my $dev = $a[2];
  my $type = $a[3]//"Unknown";
  Log3 $hash,4,"OBIS ($name) - Define called...";
  $hash->{DeviceName} = $dev;
  $hash->{MeterType}=$type if (defined($type)); 
  my $device_name = "OBIS_".$name;
  $modules{OBIS}{defptr}{$device_name} = $hash;
  Log3 $hash,4,"OBIS ($name) - Starting $name with Device $dev (Type $type).";
  
  if($dev eq "none") {
    AssignIoPort($hash);
    Log3 ($hash,1, "OBIS ($name) - OBIS device is none, commands will be echoed only");
   return undef;
  }
  my $baudrate;
  my $devi;
  ($devi, $baudrate) = split("@", $dev);
   if($baudrate =~ m/(\d+)(,([78])(,([NEO])(,([012]))?)?)?/) {
    $baudrate = $1 if(defined($1));
  }
  if ($baudrate==300) {$hash->{helper}{SPEED}="0"}
  if ($baudrate==600) {$hash->{helper}{SPEED}="1"}
  if ($baudrate==1200) {$hash->{helper}{SPEED}="2"}
  if ($baudrate==2400) {$hash->{helper}{SPEED}="3"}
  if ($baudrate==4800) {$hash->{helper}{SPEED}="4"}
  if ($baudrate==9600) {$hash->{helper}{SPEED}="5"}
  my %devs= (
#    Name, Init-String, repeat,2ndInit
    "Unknown"=>[ "", -1,""],
    "MT681"=>[ "", -1,""],
    # Voltcraft VSM 102
    "VSM102"=>["/?!".chr(13).chr(10), 1,chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10)],
    # Landis & Gyr E110
    "E110"=>["/?!".chr(13).chr(10), 1,chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10)],
    );
      Log3 $hash,4,"OBIS ($name) - Baudrate is $baudrate";
    $hash->{helper}{DEVICES} =$devs{$type};
#    Log 3,Dumper($hash->{helper}{DEVICES});
  InternalTimer(gettimeofday()+2, "GetUpdate", $hash, 0) if (exists $hash->{helper}{DEVICES}[1]);
    Log3 ($hash,4,"OBIS ($name) - Internal timer set.") if (exists $hash->{helper}{DEVICES}[1]);
  
  	Log3 $hash,4,"OBIS ($name) - Opening device...";
    return DevIo_OpenDev($hash, 0, "OBIS_Init");
}

# Update-Routine
sub GetUpdate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $type= $hash->{MeterType};
	if (!exists $hash->{helper}{DEVICES}[1]) {return undef;}
	DevIo_SimpleWrite($hash,$hash->{helper}{DEVICES}[0],undef) ;
	InternalTimer(gettimeofday()+AttrVal($name,"interval",600), "GetUpdate", $hash, 1) if ($hash->{helper}{DEVICES}[1]!=-1);
}

sub OBIS_Init($)
{
  #nothing here yet
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $type= $hash->{MeterType};
	my $dev=  $hash->{DeviceName};
  ($dev, undef) = split("@", $dev);
  return undef;
}
#####################################
sub OBIS_Undef($$)
{
  my ($hash, $arg) = @_;
  RemoveInternalTimer($hash);  
  DevIo_CloseDev($hash) if $hash->{DeviceName} != "none";
  return undef;
}

#####################################
sub OBIS_Read($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $tn = TimeNow();

    my $buf = DevIo_SimpleRead($hash);
	OBIS_Parse($hash,$buf);
    return(undef);
}

sub OBIS_Parse($$)
{
	my ($hash, $buf) = @_;
	$hash->{helper}{BUFFER} .= $buf;
	return undef if(index($hash->{helper}{BUFFER},chr(13).chr(10)) == -1);
	my $type= $hash->{MeterType};
	my $name = $hash->{NAME};  
	readingsBeginUpdate($hash);
    while(index($hash->{helper}{BUFFER},chr(13).chr(10)) ne -1)
    {
      my $rmsg="";
      $rmsg = substr($hash->{helper}{BUFFER}, 0, index($hash->{helper}{BUFFER},chr(13).chr(10)));
		Log3 $hash,5,"OBIS ($name) - Msg-Parse: $rmsg";
		if ($rmsg=~ /.*\/(.*)/) {
		  	DevIo_SimpleWrite($hash,$hash->{helper}{DEVICES}[2],undef) if (!$hash->{helper}{DEVICES}[2] eq "");
	  	}
	  	
		if($rmsg=~/^([23456789]+)-.*/) {
			Log3 $hash,3,"OBIS ($name) - Unknown OBIS-Message, please report: $rmsg";
		}
# Summe eingespeister Phase: 1-0:2.1.7*255(07568.01*kWh)
      	if ($rmsg=~ /1-0:([246])\.1\.7\*255\((-?\d+\.?\d*).*/) {
      		my $L=$1;
    		if (exists $OBIS_channels{$1}) {$L="sum_".$OBIS_channels{$1}} else {$L="Unknown_Channel"};
			Log3 $hash,5,"OBIS ($name) - Set reading ".$L." to value ".($2+0);
  			readingsBulkUpdate($hash, $L,$2+0); 
		};
      	
# Einspeisung und Bezug der einzelnen Phasen
      	if ($rmsg=~ /1-0:(\d+)\.7\.\d*\*\d*\((-?\d+\.?\d*).*/) {
      		my $L=$1;
    		if (exists $OBIS_channels{$1}) {$L=$OBIS_channels{$1}} else {$L="Unknown_Channel"};
			Log3 $hash,5,"OBIS ($name) - Set reading ".$L." to value ".($2+0);
  			readingsBulkUpdate($hash, $L,$2+0); 
      	};

# Seriennummer
	  	if ($rmsg=~ /0-0:96\.1\.255\*255\((.*?)\).*/)   {  
	  		Log3 $hash,5,"OBIS ($name) - Set reading Serial to value ".$1;
	  		readingsBulkUpdate($hash, "Serial"  ,$1); }
      	
# Eigentumsnummer --> 1-0:0.0.0*255(GETTONE)
	  	if ($rmsg=~ /1-0:0\.0\.0\*255\((.*?)\).*/)   {  
	  		Log3 $hash,5,"OBIS ($name) - Set reading Owner to value ".$1;
	  		readingsBulkUpdate($hash, "Owner"  ,$1); }

# Statusbyte
	  	if ($rmsg=~ /1-0:96\.5\.5\*255\((.*?)\).*/)   {  
	  		Log3 $hash,5,"OBIS ($name) - Set reading Status to value ".$1;
	  		readingsBulkUpdate($hash, "Status"  ,$1); }

#Version
		if ($rmsg=~ /\/(.*)/) {  
  			Log3 $hash,5,"OBIS ($name) - Set reading Version to value ".$1;
			readingsBulkUpdate($hash, "Version"  ,$1); }

# Zählerstand --> 1-0:1.8.0*255(17483.88*kWh)
		if ($rmsg=~ /1-0:([12])\.8\.\d\*255\((-?\d+\.?\d*).*/) {
			if($1==1) {
  				Log3 $hash,5,"OBIS ($name) - Set reading energy_total to value ".$2." with offset ".AttrVal($name,"offset_energy",0);
				readingsBulkUpdate($hash, "energy_total"  ,$2 +AttrVal($name,"offset_energy",0)); 
			} elsif ($1==2) {
  				Log3 $hash,5,"OBIS ($name) - Set reading feed_total to value ".$2." with offset ".AttrVal($name,"offset_energy",0);
				readingsBulkUpdate($hash, "feed_total"  ,$2 +AttrVal($name,"offset_feed",0)); 				
			}
		}
       $hash->{helper}{BUFFER} = substr($hash->{helper}{BUFFER}, index($hash->{helper}{BUFFER},chr(13).chr(10))+2);;
    }
    readingsEndUpdate($hash,1);
    return $name;
}

#####################################
sub OBIS_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "OBIS_Init")
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

sub OBIS_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;
  	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
    my $hash  = $defs{$name};
	
	if ($cmd eq "set") {
		if ($aName eq "channels") {
	      %OBIS_channels = eval $aVal;
			if ($@) {
				Log3 $name, 3, "OBIS ($name) - X: Invalid regex in attr $name $aName $aVal: $@";
			}
		}
		if ($aName eq "interval") {
			if ($aVal=~/^[1-9][0-9]*$/) {
		  		RemoveInternalTimer($hash);
				my $type= $hash->{MeterType};
  				InternalTimer(gettimeofday()+2, "GetUpdate", $hash, 1) if ($hash->{helper}{DEVICES}[1]!=-1);
			} else {
				Log3 $name, 3, "OBIS ($name) - $name: attr interval must be a number -> $aVal";
			}
		}
		
	}
	return undef;
}

#####################################

"Cogito, ergo sum.";

=pod
=item device
=begin html

<a name="OBIS"></a>
<h3>OBIS</h3>
  This module is for SmartMeter, that report thier data in OBIS-Standard.
  <br>
  <b>Define</b>
    <code>define &lt;name&gt; OBIS device|none [MeterType] </code><br>
    <br>
      &lt;device&gt; specifies the serial port to communicate with the smartmeter.
      Normally on Linux the device will be named /dev/ttyUSBx, where x is a number.
      For example /dev/ttyUSB0. You may specify the baudrate used after the @ char.<br>
      <br><br>
      Optional:MeterType can be of
      <ul><li>VSM102 -&gt; Voltcraft VSM102</li>
      <li>E110 -&gt; Landis&&;Gyr E110</li></ul>
      <br>
      Example: <br>
    <code>define myPowerMeter OBIS /dev/ttyPlugwise@@9600,7,E,1 VSM102</code>
      <br>
    <br>
 
  <b>Attributes</b>
  <ul><li>
    <code>offset_feed <br>offset_energy</code><br>
      If your smartmeter is BEHIND the meter of your powersupplier, then you can hereby adjust
      the total-reading of your SM to that of your official one.
      <br><br>
      </li>
      <li>
   <code>channels</code><br>
      With this, you can adjust the reported channels.
      OBIS-Standard is 
      <ul>
      <li>1-->Sum of all phases</li>
      <li>21-->Phase 1</li>
      <li>41-->Phase 2</li> 
      <li>61-->Phase 3</li></ul>
      You can change that for example to:
      <code>attr myOBIS channels "2"=>"L1", "4"=>"L2", "6"=>"L3"></code>
      <br><br></li><li>
   <code>interval</code><br>
      The polling-interval in seconds (only if metertype is set) 
      </li>
  <br>
</ul>

=end html

=begin html


<a name="OBIS"></a>
<h3>OBIS</h3>
  Modul für Smartmeter, die ihre Daten im OBIS-Standard senden.
  <br>
  <b>Define</b>
    <code>define &lt;name&gt; OBIS device|none [MeterType] </code><br>
    <br>
      &lt;device&gt; gibt den seriellen Port an.
      <br><br>
      Optional:MeterType kann sein:
      <ul><li>VSM102 -&gt; Voltcraft VSM102</li>
      <li>E110 -&gt; Landis&&;Gyr E110</li></ul>
      <br>
      Beispiel: <br>
    <code>define myPowerMeter OBIS /dev/ttyPlugwise@@9600,7,E,1 VSM102</code>
      <br>
    <br>
 
  <b>Attribute</b>
  <ul><li>
    <code>offset_feed <br>offset_energy</code><br>
      Wenn das Smartmeter hinter einem Zähler des EVU's sitzt, kann hiermit der Zähler des
      Smartmeters an den des EVU's angepasst werden.
      <br><br>
      </li>
      <li>
   <code>channels</code><br>
      Hiermit können die einzelnen Kanal-Readings angepasst werden.
      OBIS-Standard ist 
      <ul>
      <li>1-->Summe aller Phasen</li>
      <li>21-->Phase 1</li>
      <li>41-->Phase 2</li> 
      <li>61-->Phase 3</li></ul>
      Beispiel:
      <code>attr myOBIS channels "2"=>"L1", "4"=>"L2", "6"=>"L3"></code>
      <br><br></li><li>
   <code>interval</code><br>
      Abrufinterval der Daten. (greift nur, wenn ein metertype angegeben wurde) 
      </li>
  <br>
</ul>

=end html_DE

=cut
