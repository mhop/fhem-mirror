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
use POSIX qw{strftime};

my %OBIS_channels = ( "21"=>"power_L1",
                 "41"=>"power_L2",
                 "61"=>"power_L3",
                 "32"=>"voltage_L1",
                 "52"=>"voltage_L2",
                 "72"=>"voltage_L3",
                 "31"=>"current_L1",
                 "51"=>"current_L2",
                 "71"=>"current_L3",
                 "8.1"=>"total_consumption",
                 "8.2"=>"total_feed",
                 "2"=>"feed_L1",
                 "4"=>"feed_L2",
                 "6"=>"feed_L3",
                 "1"=>"power");
                 
my %OBIS_codes = (	"Serial" 		=> qr/0-0:96\.1\.255\*255\((.*?)\).*/,
					"Owner" 		=> qr/1-0:0\.0\.0\*255\((.*?)\).*/,
					"Status" 		=> qr/1-0:96\.5\.5\*255\((.*?)\).*/,
					"Channels_sum" 	=> qr/1-0:([246])\.1\.7\*255\(([-+]?\d+\.?\d*).*/,
					"Channels"		=> qr/1-0:(\d+)\.7\.\d*\*\d*\(([-+]?\d+\.?\d*).*/,
					"Counter"		=> qr/1-0:([12])\.(8)\.\d\*255\((-?\d+\.?\d*).*/
				);
#{"21"=>"energy_L1","41"=>"energy_L2","61"=>"energy_L3","31"=>"power_L1","51"=>"power_L2","71"=>"power_L3","1"=>"energy_current","8.1"=>"energy_total","8.2"=>"feed_total"}
    
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
  $hash->{AttrList}= "do_not_notify:1,0 interval offset_feed offset_energy IODev channels alignTime pollingMode:on,off ".
  					  $readingFnAttributes;
}

#####################################
sub OBIS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return 'wrong syntax: define <name> OBIS devicename@baudrate[,databits,parity,stopbits]|none [MeterType]'
    if(@a < 3);
#				Log 3,Dumper(%readyfnlist);
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
#    Name,      Init-String,           interval,  2ndInit
    "Unknown"=>["",                        -1,    ""],
    "VSM102"=> ["/?!".chr(13).chr(10),    600,    chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10)],
    "E110"=>   ["/?!".chr(13).chr(10),    600,    chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10)],
    "Hager"=>  ["",                        60,    ""],
    );
      Log3 $hash,4,"OBIS ($name) - Baudrate is $baudrate";
    if (!$devs{$type}) {return 'unknown meterType. Must be one of <nothing>, VSM102, E110, Hager'};
    $devs{$type}[1] = $hash->{helper}{DEVICES}[1] // $devs{$type}[1];
    $hash->{helper}{DEVICES} =$devs{$type};
    $hash->{helper}{TRIGGERTIME}=gettimeofday();
	my $t=OBIS_adjustAlign($hash,AttrVal($name,"alignTime",undef),$hash->{helper}{DEVICES}[1]);
    Log3 ($hash,4,"OBIS ($name) - Internal timer set to ".FmtDateTime($t)) if ($hash->{helper}{DEVICES}[1]>0);
  InternalTimer($t, "GetUpdate", $hash, 0) if ($hash->{helper}{DEVICES}[1]>0);
	$hash->{helper}{EoM}=-1;
  
  	Log3 $hash,4,"OBIS ($name) - Opening device...";
  	  return DevIo_OpenDev($hash, 0, "OBIS_Init");
}

# Update-Routine
sub GetUpdate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $type= $hash->{MeterType};
	RemoveInternalTimer($hash);

	my $t=OBIS_adjustAlign($hash,AttrVal($name,"alignTime",undef),$hash->{helper}{DEVICES}[1]);
    Log3 ($hash,4,"OBIS ($name) - Internal timer set to ".FmtDateTime($t)) if ($hash->{helper}{DEVICES}[1]>0);
	InternalTimer($t, "GetUpdate", $hash, 1)  if ($hash->{helper}{DEVICES}[1]>0);
	$hash->{helper}{EoM}=-1;
	if ($hash->{helper}{DEVICES}[1] eq "") {return undef;}
	DevIo_SimpleWrite($hash,$hash->{helper}{DEVICES}[0],undef) ;
}

sub OBIS_Init($)
{
  return undef;
}
#####################################
sub OBIS_Undef($$)
{
  my ($hash, $arg) = @_;
  RemoveInternalTimer($hash);  
  DevIo_CloseDev($hash) if $hash->{DeviceName} ne "none";
  return undef;
}

#####################################
sub OBIS_Read($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
    my $buf = DevIo_SimpleRead($hash);
    if ($hash->{helper}{EoM}!=1) {OBIS_Parse($hash,$buf);}
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

		if($rmsg=~/^([23456789]+)-.*/) {
			Log3 $hash,3,"OBIS ($name) - Unknown OBIS-Message, please report: $rmsg";
		}

# End of Message
		if ($rmsg=~/!.*/) {
			if ($type eq "Hager") {
				$rmsg="1-0:1.7.255*255(".$hash->{helper}{PHSUM}."*kW)"; 
				$hash->{helper}{PHSUM}=0 if ($hash->{helper}{DEVICES}[1]>0);
			};
			$hash->{helper}{EoM}+=1 if ($hash->{helper}{DEVICES}[1]>0);
		}

#Version
		if ($rmsg=~ /.*\/(.*)/) {
		  	DevIo_SimpleWrite($hash,$hash->{helper}{DEVICES}[2],undef) if (!$hash->{helper}{DEVICES}[2] eq "");
	  		if (ReadingsVal($name,"Version","") ne $1) {readingsBulkUpdate($hash, "Version"  ,$1); }
 			$hash->{helper}{EoM}=0;
	  	}
	  	if ($hash->{helper}{EoM}!=-1) {
			for my $code (keys %OBIS_codes) {
				if ($rmsg =~ $OBIS_codes{$code}) {
					if ($code eq "Channels_sum") {
			    		my $L=$hash->{helper}{Channels}{$1} // $OBIS_channels{$1} // "Unknown_Channel_$1";
	  					readingsBulkUpdate($hash, "sum_$L",$2+0); 
					}
					 
					elsif ($code eq "Channels") {
			    		my $L=$hash->{helper}{Channels}{$1} // $OBIS_channels{$1} // "Unknown_Channel_$1";
			  			readingsBulkUpdate($hash, $L,$2+0); 
			    		my $a=$2;
			    		if ($1 =~ /(?:21|41|61)/) {$hash->{helper}{PHSUM} += ($a+0)}
					}
					
					elsif ($code eq "Counter") {
						my $L=$hash->{helper}{Channels}{$2.".".$1} // $OBIS_channels{$2.".".$1} // "Unknown_Channel_$2.$1";
						if($1==1) {
							readingsBulkUpdate($hash, $L  ,$3 +AttrVal($name,"offset_energy",0)); 
						} elsif ($1==2) {
							readingsBulkUpdate($hash, $L  ,$3 +AttrVal($name,"offset_feed",0)); 				
						}
						
					} elsif (ReadingsVal($name,$code,"") ne $1) 
						{readingsBulkUpdate($hash, $code  ,$1); }
	     		}
   			}
	  	}
       $hash->{helper}{BUFFER} = substr($hash->{helper}{BUFFER}, index($hash->{helper}{BUFFER},chr(13).chr(10))+2);;
#       $hash->{helper}{BUFFER} =~ s/^.*\r\n(.*)/$1/g;
#		Log 3,"Buffer is now: $hash->{helper}{BUFFER}";
    }
    readingsEndUpdate($hash,1);
#    Log 3,"Size of Buffer: ".length($hash->{helper}{BUFFER});
	if($hash->{helper}{EoM}==1) { $hash->{helper}{BUFFER}="";}
    return $name;
}

#####################################
sub OBIS_Ready($)
{
  my ($hash) = @_;
  return DevIo_OpenDev($hash, 1, "OBIS_Init")
                if($hash->{STATE} eq "disconnected");

     my $name = $hash->{NAME}; 
    my $dev=$hash->{DeviceName};
  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  return if (!$po);
  ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

sub OBIS_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;
  	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
    my $hash  = $defs{$name};
    my $dev=$hash->{DeviceName};
	if ($cmd eq "del") {
		if ($aName eq "channels") { $hash->{helper}{Channels}=undef;}
		if ($aName eq "interval") {
		  		RemoveInternalTimer($hash);
				$hash->{helper}{DEVICES}[1]=0;
		}
		if ($aName eq "pollingMode") {
				$hash->{FD}=$hash->{helper}{FD2};
				delete($readyfnlist{"$name.$dev"});
				$selectlist{"$name.$dev"} = $hash;
		}		
	}
	if ($cmd eq "set") {
		if ($aName eq "channels") {
	      $hash->{helper}{Channels}=eval $aVal;
			if ($@) {
				Log3 $name, 3, "OBIS ($name) - X: Invalid regex in attr $name $aName $aVal: $@";
				$hash->{helper}{Channels}=undef;
			}
		}
		if ($aName eq "interval") {
			if ($aVal=~/^[1-9][0-9]*$/) {
			    $hash->{helper}{TRIGGERTIME}=gettimeofday();
		  		RemoveInternalTimer($hash);
				$hash->{helper}{DEVICES}[1]=$aVal;
#  				InternalTimer(gettimeofday()+2, "GetUpdate", $hash, 1) if ($aVal>0);
				my $t=OBIS_adjustAlign($hash,AttrVal($name,"alignTime",undef),$hash->{helper}{DEVICES}[1]);
			    Log3 ($hash,4,"OBIS ($name) - Internal timer set to ".FmtDateTime($t)) if ($hash->{helper}{DEVICES}[1]>0);
				InternalTimer($t, "GetUpdate", $hash, 0)  if ($hash->{helper}{DEVICES}[1]>0);
			} else {
				return $name, 3, "OBIS ($name) - $name: attr interval must be a number -> $aVal";
			}
		}
		if ($aName eq "alignTime") {
			 if ($hash->{helper}{DEVICES}[1]>0) {
		  		RemoveInternalTimer($hash);
			    $hash->{helper}{TRIGGERTIME}=gettimeofday();
				my $t=OBIS_adjustAlign($hash,$aVal,$hash->{helper}{DEVICES}[1]);
			    Log3 ($hash,4,"OBIS ($name) - Internal timer set to ".FmtDateTime($t));
				InternalTimer($t, "GetUpdate", $hash, 0);
			 } else {
 				return $name, 3, "OBIS ($name) - $name: attr alignTime is useless, if no interval is specified";
			 }			
		}
		if ($aName eq "pollingMode")
		{
			if ($aVal eq "on") {
				delete $hash->{FD};
				delete($selectlist{"$name.$dev"});
				$readyfnlist{"$name.$dev"} = $hash;
			} elsif ($aVal eq "off") {
				delete($readyfnlist{"$name.$dev"});
				$selectlist{"$name.$dev"} = $hash;
				 DevIo_CloseDev($hash);
				DevIo_OpenDev($hash, 0, "OBIS_Init");
			} 
		}
		
	}
	return undef;
}

sub OBIS_adjustAlign($$$)
{
  my($hash, $attrVal, $interval) = @_;
#  return gettimeofday()+$interval;
  if (!$attrVal) {return gettimeofday()+$interval;}
  my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($attrVal); # "00:00"
  return "$hash->{NAME} alignTime: $alErr" if($alErr);
  my $tspec=strftime("\%H:\%M:\%S", gmtime($interval));
  
  my (undef, $hr, $min, $sec, undef) = GetTimeSpec($tspec);
  my $now = time();
  my $step = ($hr*60+$min)*60+$sec;
  my $alTime = ($alHr*60+$alMin)*60+$alSec;#-fhemTzOffset($now);	
  
  my $ttime = int($hash->{helper}{TRIGGERTIME});
  my $off = ($ttime % 86400) - 86400;
  if ($off >= $alTime) {
	  $ttime = gettimeofday();#-86400;
	  $off -=  86400;
  }
  my $off2=$off;
  while($off < $alTime) {
    $off += $step;
  }
  $ttime += ($alTime-$off);
  $ttime += $step if($ttime < $now);
  $hash->{NEXT} = FmtDateTime($ttime);
  $hash->{helper}{TRIGGERTIME} = ($off2<=$alTime) ? $ttime : (gettimeofday());#-fhemTzOffset($now));
  
  return $hash->{helper}{TRIGGERTIME};
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
      <li>E110 -&gt; Landis&&;Gyr E110</li>
      <li>Hager -&gt; Hager-Family</li></ul>
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
      <code>attr myOBIS channels {"2"=>"L1", "4"=>"L2", "6"=>"L3"}></code>
      <br><br></li><li>
   <code>interval</code><br>
      The polling-interval in seconds 
      </li>
  <br>
</ul>

=end html

=begin html_DE

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
      <li>E110 -&gt; Landis&&;Gyr E110</li>
      <li>Hager -&gt; Smartmeter der Hager-Familie</li></ul>
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
      <code>attr myOBIS channels {"2"=>"L1", "4"=>"L2", "6"=>"L3"}></code>
      <br><br></li><li>
   <code>interval</code><br>
      Abrufinterval der Daten. 
      </li><li>
   <code>aglignTime</code><br>
      Richtet den Zeitpunkt von <interval> nach einer bestimmten Uhrzeit aus. 
      </li><li>
   <code>pollingMode</code><br>
      Hiermit wird von Direktbenachrichtigung auf Polling umgestellt.
      Bei Smartmetern, welche von selbst im Sekundentakt senden,
      kann das zu einer spürbaren Senkung der Prozessorleistung führen.  
      </li>
  <br>
</ul>

=end html_DE

=cut
