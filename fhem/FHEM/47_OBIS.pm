###############################################
#
# 47_OBIS.pm 
# 
# maintained by gvzdus, however ~95% of code and functions created by
# icinger. gvzdus accepts full accountability for the bugs, but the credits
# for brilliance go to icinger :-)
# 
# Other credits:
# hdgucken, 02/2021: non-blocking extension, optimize ser2net integration
# 
# Original credits by Icinger, main developer until 02/2021:
# Thanks to matzefizi for letting me merge this with 70_SMLUSB.pm and for testing
# Thanks to immi for testing and supporting help and tips
# 
# $Id$

package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday usleep);
use Scalar::Util qw(looks_like_number);
use POSIX qw{strftime};
use DevIo;
no warnings 'portable';  # Support for 64-bit ints required

my %OBIS_channels = (
		"21"  =>"power_L1", # Positive active instantaneous power
		"36"  =>"power_L1", # Sum active instantaneous power
		"41"  =>"power_L2",
		"56"  =>"power_L2",
		"61"  =>"power_L3",
		"76"  =>"power_L3",
		"12"  =>"voltage_avg",
		"32"  =>"voltage_L1",
		"52"  =>"voltage_L2",
		"72"  =>"voltage_L3",
		"11"  =>"current_sum",
		"31"  =>"current_L1",
		"51"  =>"current_L2",
		"71"  =>"current_L3",
		"1.8" =>"total_consumption",
		"2.8" =>"total_feed",
		"2"   =>"feed_L1",
		"4"   =>"feed_L2",
		"6"   =>"feed_L3",
		"1"   =>"power",    # Positive active instantaneous power
		"15"  =>"power",    # Absolute active instantaneous power
		"16"  =>"power",    # Sum active instantaneous power
		"24"  =>"Gas",
);

my %OBIS_codes = (
		"Serial" 		=> qr{^0-0:96.1.255(?:.\d+)?\((.*?)\).*},
		"Serial"		=> qr{^(?:1-0:)?0\.0\.[1-9]+(?:.\d+)?\((.*?)\).*},
		"Owner" 		=> qr{^1.0.0.0.0(?:.\d+)?\((.*?)\).*}x,
		"Status" 		=> qr{^1.0.96.5.5(?:.\d+)?\((.*?)\).*}x,
		"Powerdrops"	=> qr{^0.0.96.7.\d(?:.\d+)?\((.*?)\).*},
		"Time_param"	=> qr{^0.0.96.2.1(?:.\d+)?\((.*?)\).*},
		"Time_current"	=> qr{^0.0.1.0.0(?:.\d+)?\((.*?)\).*},
		"Channel_sum" 	=> qr{^(?:1.0.)?(\d+).1.7(?:.0|.255)?(?:\(.*?\))?\((<|>)?([-+]?\d+\.?\d*)\*?(.*)\).*},
		"Channels"		=> qr{^(?:\d.0.)?(\d+).7\.\d+(?:.0|.255)?(?:\(.*?\))?\((<|>)?([-+]?\d+\.?\d*)\*?(.*)\).*},
		"Channels2"		=> qr{^(?:0.1.)?(\d+).2\.\d+(?:.0|.255)?(?:\(.*?\))?\((<|>)?(-?\d+\.?\d*)\*?(.*)\).*},
		"Counter"		=> qr{^(?:1.\d.)?(\d).(8)\.(\d).(\d+)?(?:\(.*?\))?\((<|>)?(-?\d+\.?\d*)\*?(.*)\).*},    #^(?:1.\d.)?(\d).(8)\.(\d)(?:.\d+)?(?:\(.*?\))?\((<|>)?(-?\d+\.?\d*)\*?(.*)\).*
		"ManufID"		=> qr{^129-129:199\.130\.3(?:.\d+)?\((.*?)\).*},
		"PublicKey"		=> qr{^129-129:199\.130\.5(?:.\d+)?\((.*?)\).*},
		"ManufID2"	    => qr{^1.0.96.50.1(?:.\d+)?\((.*?)\).*}
);

my %SML_specialities = (
		"TIME"			=> [qr{0.0.96.2.1
							|0.0.1.0.0		}x, sub{return strftime("%d-%m-%Y %H:%M:%S", localtime(unpack("i", pack("I", hex(@_)))))}],
		"HEX2"			=> [qr{1-0:0\.0\.[0-9]	}x, sub{my $a=shift;
							if ( $a =~ /^[0-9a-fA-F]+$/ ) {$a=~s/(..)/$1-/g;$a=~s/-$//};
							return $a;}],
		"HEX4"			=> [qr{1.0.96.5.5
							|0.0.96.240.\d+
							|129.129.199.130.5}x, sub{my $a=shift;
							if ( $a =~ /^[0-9a-fA-F]+$/ ) {$a=~s/(....)/$1-/g;$a=~s/-$//};
							return $a;}],
		"INFO"			=> [qr{1-0:0\.0\.[0-9]
							|129.129.199.130.3}x, ""],
);

# Mapping for historical energy consumption, used with 1-0:1.8.0
my %Ext_Channel_Postfix = (
		"255"			=> "",
		"0"				=> "",
		"96"			=> "_last1d",
		"97"			=> "_last7d",
		"98"			=> "_last30d",
		"99"			=> "_last365d",
		"100"			=> "_since_rst"
);

my $SML_ENDTAG = chr(0x1B) . chr(0x1B) . chr(0x1B) . chr(0x1B) . chr(0x1A);
my $SML_START  = chr(0x1B) . chr(0x1B) . chr(0x1B) . chr(0x1B) . 
                 chr(0x01) . chr(0x01) . chr(0x01) . chr(0x01);
    
#####################################
sub OBIS_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^\/(?s:.*)\!\$";
  $hash->{ReadFn}  = "OBIS_Read";
  $hash->{ReadyFn}  = "OBIS_Ready";
  $hash->{DefFn}   = "OBIS_Define";
  $hash->{ParseFn}   = "OBIS_Parse";
  $hash->{GetFn} = "OBIS_Get";
  $hash->{UndefFn} = "OBIS_Undef";
  $hash->{AttrFn}	= "OBIS_Attr";
  $hash->{AttrList}= "do_not_notify:1,0 interval offset_feed offset_energy IODev channels directions alignTime pollingMode:on,off extChannels:on,off,auto unitReadings:on,off ignoreUnknown:on,off valueBracket:first,second,both resetAfterNoDataTime createPreValues:on,off ".
  					  $readingFnAttributes;
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
  
  $hash->{DeviceName} = $dev;
  $hash->{MeterType}=$type if (defined($type)); 

  my $device_name = "OBIS_".$name;
  $modules{OBIS}{defptr}{$device_name} = $hash;
  
# If device="none", prepare for an external IO-Module
  if($dev=~/none|ext/) {
  	if (@a == 4){
	  	my $device_name = "OBIS.".$a[4];
	  	$hash->{CODE} = $a[4];
	  	$modules{OBIS}{defptr}{$device_name} = $hash;
  	}
    AssignIoPort($hash);
    Log3 $hash, 1, "OBIS ($name) - OBIS device is none, commands will be echoed only";
    return undef;
  }

  my $baudrate;
  my $devi;
  ($devi, $baudrate) = split("@", $dev);
  $hash->{helper}{SPEED}="0";
  if (defined($baudrate)) {   ## added for ser2net connection
	if($baudrate =~ m/(\d+)(,([78])(,([NEO])(,([012]))?)?)?/) {
	  $baudrate = $1 if(defined($1));
	}
	my %bd=("300"=>"0","600"=>"1","1200"=>"2","2400"=>"3","4800"=>"4","9600"=>"5","18200"=>"6","36400"=>"7","57600"=>"8","115200"=>"9");
	$hash->{helper}{SPEED}=$bd{$baudrate};
	$hash->{helper}{SPEED2}=$bd{$a[4]//$baudrate};
  }
  else { 
    $baudrate=9600;
    $hash->{helper}{SPEED}="5";
    $hash->{helper}{NETDEV}= $dev =~ /:\d+$/ ? 1 : 0;
  }
  
  my %devs= (
#   Name,      Init-String,                 interval,  2ndInit
    "none"		=>	["",                        -1,    ""],
    "Unknown"	=>	["",                        -1,    ""],
    "SML"		=>	["",                        -1,    ""],
    "Ext"		=>	["",                        -1,    ""],
    "Standard"	=>	["",                        -1,    ""],
    "VSM102"	=> 	["/?!".chr(13).chr(10),    600,    chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10)],
    "E110"		=>  ["/?!".chr(13).chr(10),    600,    chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10)],
    "E350USB"	=>  ["/?!".chr(13).chr(10),    600,    chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10)],
    "AS1440"	=> 	["/2!".chr(13).chr(10),    600,    chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10)]
    );
  if (!$devs{$type}) {return 'unknown meterType. Must be one of <nothing>, SML, Standard, VSM102, E110'};
  $devs{$type}[1] = $hash->{helper}{DEVICES}[1] // $devs{$type}[1];
  $hash->{helper}{DEVICES} =$devs{$type};
  $hash->{helper}{RULECACHE} = {};
  $hash->{helper}{TRIGGERTIME}=gettimeofday();

  if ($hash->{helper}{DEVICES}[1]>0) {
	my $t=OBIS_adjustAlign($hash,AttrVal($name,"alignTime",undef),$hash->{helper}{DEVICES}[1]);
    Log3 $hash, 5, "OBIS ($name) - Internal timer set to ".FmtDateTime($t);
	InternalTimer($t, "GetUpdate", $hash, 0);
  }
  InternalTimer(gettimeofday()+60, "CheckNoData", $hash, 0) if ($hash->{helper}{NETDEV});
  $hash->{helper}{EoM}=-1;
  
  Log3 $hash, 5, "OBIS ($name) - Opening device...";

  if (! -f $dev) {
    DevIo_OpenDev($hash, 0, "OBIS_Init", $hash->{helper}{NETDEV} ? "OBIS_Callback" : undef);
  } else {
    # Debug mode: Open a FHEM debug session and process it...
    Log3 $hash, 1, "OBIS ($name) - Replaying session";
    open (FH, $dev);
    $attr{$name}{"verbose"} = 5;
    my $t1 = gettimeofday();
    my $lines = 0;
    while (<FH>) {
      next unless /^\d{4}.\d\d.\d\d \d\d:\d\d:\d\d .: OBIS.*Full message->\s*(.*)$/;
      OBIS_Parse ($hash, (pack 'H*', $1));
      $lines++;
    }
    my $dt = gettimeofday()-$t1;
    readingsSingleUpdate($hash, "state",
      $lines . ' lines in ' . $dt . ' seconds = ' . int($lines/$dt + 0.5) . ' lines per second', 0);
    close FH;
  }

  return;
}

#####################################
# will be executed if connection establishment fails (see DevIo_OpenDev())
sub OBIS_Callback($$)
{
    my ($hash, $error) = @_;
    my $name = $hash->{NAME};

    # create a log entry with the error message
    if ($error) {
      Log3 $name, 4, "OBIS ($name) - error while connecting: $error";
    } 
    return;
}

#####################################
sub OBIS_Get($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $opt = shift @a;
	
  if ($opt eq "update") {
  	GetUpdate($hash);
  } else 
  
  {return "Unknown argument $opt, choose one of update";}
  
}

#####################################
sub OBIS_Set($@)
{
	my ( $hash, @a ) = @_;
	my $name = shift @a;
	my $opt = shift @a;
	my $value = join("", @a);
	my $teststr="";
	my %bd=("300"=>"0","600"=>"1","1200"=>"2","2400"=>"3","4800"=>"4","9600"=>"5","18200"=>"6","36400"=>"7","57600"=>"8","115200"=>"9");
	
	if ($opt eq "setSpeed") {
		if ($bd{$value} ne $hash->{helper}{SPEED}) {
			$hash->{helper}{BUFFER}="";
			
			$hash->{helper}{SPEED}=$bd{$value};
			print "old Helper: $hash->{helper}{DEVICES}[2] \r\n";
			$hash->{helper}{DEVICES}[2]=$hash->{helper}{DEVICES}[2] eq "" ? "" : chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10);
			print "new Helper: $hash->{helper}{DEVICES}[2] \r\n";
			
			$hash->{helper}{SpeedChange}=$value;
			DevIo_SimpleWrite($hash,$hash->{helper}{DEVICES}[0],undef) ;
			print "Wrote $hash->{helper}{DEVICES}[0]\r\n";
		}		
		
	}
	return;
}

# Update-Routine
sub GetUpdate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $type= $hash->{MeterType};
	RemoveInternalTimer($hash, "GetUpdate");

	$hash->{helper}{EoM}=-1;
	if ($hash->{helper}{DEVICES}[1] eq "") {return undef;}
	if( $init_done ) {
		DevIo_SimpleWrite($hash,$hash->{helper}{DEVICES}[0],undef) ;
		Log3 $hash, 4, "OBIS ($name) - Wrote $hash->{helper}{DEVICES}[0]";
	}
	my $t=OBIS_adjustAlign($hash,AttrVal($name,"alignTime",undef),$hash->{helper}{DEVICES}[1]);
    Log3 ($hash,5,"OBIS ($name) - Internal timer set to ".FmtDateTime($t)) if ($hash->{helper}{DEVICES}[1]>0);
	InternalTimer($t, "GetUpdate", $hash, 0)  if ($hash->{helper}{DEVICES}[1]>0);
}

# Periodic check for dead connections (no data send for some time)
sub CheckNoData 
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	RemoveInternalTimer($hash, "CheckNoData");
    my $t = gettimeofday();
    my $maxSilence = AttrVal($name,"resetAfterNoDataTime",90);
    if ( $hash->{helper}{LastPacketTime} && $hash->{helper}{LastPacketTime} < $t-$maxSilence) {
      Log3 $hash, 3, "OBIS ($name) - No data received for " . (int ($t-$hash->{helper}{LastPacketTime})) . 
           " seconds, resetting connection";
	  DevIo_CloseDev($hash);
      DevIo_OpenDev($hash, 1, "OBIS_Init", $hash->{helper}{NETDEV} ? "OBIS_Callback" : undef);
    }
	InternalTimer($t+60, "CheckNoData", $hash);
}

sub OBIS_Init($)
{
    my ($hash) = @_;
	Log3 $hash, 3, "OBIS ($hash->{NAME}) - Init done";
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
	if( $init_done ) {
		my $name = $hash->{NAME};
	
    	my $buf = DevIo_SimpleRead($hash);
        return if(!defined($buf));
    	if ( !defined($hash->{helper}{SpeedChange}) ||  ($hash->{helper}{SpeedChange} eq ""))
    	{
    		OBIS_Parse($hash,$buf) if ($hash->{helper}{EoM}!=1);
    	} else
    	{
#			if ($hash->{helper}{SpeedChange2} eq "")
#			{
#				Log3 $hash,4,"Part 1";
##				$hash->{helper}{SPEED}=$bd{$value};
#				DevIo_SimpleWrite($hash,$hash->{helper}{DEVICES}[2],undef) ;
#				Log3 $hash,4,"Writing ".$hash->{helper}{DEVICES}[2];
#				$hash->{helper}{SpeedChange2}="1";
#			} elsif ($hash->{helper}{SpeedChange2} eq "1")
#			{	
#				if ($buf ne hex(15)) {
#					Log3 $hash,4,"Part 2";
#			    	my $sp=$hash->{helper}{SPEED};
#					my $d=$hash->{DeviceName};
#					my $repl=$sp;
#					Log3 $hash,4,"Old Dev: $d";
#					$d=~/(.*@)(\d*)(.*)/;
#					my $d2=$1.$hash->{helper}{SpeedChange}.$3;
#			#		$d=~s/(.*@)(\d*)(.*)/$repl$2/ee;
#					
#					Log3 $hash,4, "Replaced dev: $d2";
#					RemoveInternalTimer($hash);  
#					DevIo_CloseDev($hash) if $hash->{DeviceName} ne "none";
#					$hash->{DeviceName} = $d2; 
#					$hash->{helper}{EoM}=-1;
#				  	Log3 $hash,5,"OBIS ($name) - Opening device...";
#					my $t=OBIS_adjustAlign($hash,AttrVal($name,"alignTime",undef),$hash->{helper}{DEVICES}[1]);
#			    	Log3 ($hash,5,"OBIS ($name) - Internal timer set to ".FmtDateTime($t)) if ($hash->{helper}{DEVICES}[1]>0);
#					InternalTimer($t, "GetUpdate", $hash, 0) if ($hash->{helper}{DEVICES}[1]>0);
#				  	DevIo_OpenDev($hash, 1, "OBIS_Init");
#				} else
#				{	
#					Log3 $hash,4,"Recieved NAK from Meter"; 	
#				}	
#				$hash->{helper}{SpeedChange2}="";
#				$hash->{helper}{SpeedChange}="";    	
#				Log3 $hash,4, "Cleared helper\r\n";			    	
#			}
    	}
	}
    return(undef);
}

my @pow10plus5 = ( 0.00001, 0.0001, 0.001, 0.01, 0.1, 1, 10, 100, 1000, 10000, 100000 );
my %unitmap = (
  0x1E => "Wh",
  0x1B => "W",
  0x21 => "A",
  0x23 => "V",
  0x2C => "Hz",
  0x01 => "",
  0x1D => "varh",
);

# Input: devhash, textoutput, reverse byte buffer, maxelements

sub OBIS_Parse_List 
{
  my $hash = $_[0];
  my $elements = $_[2];
  my @result;

#Log3 $hash, 3, "OBIS_Parse_List : Scan for $elements element";
  my $cntdown = $elements;
  my $isobis = ($elements == 7) ? 1 : 0;
  while ($cntdown>0 && (length $_[3])) {
    
	my $tl = ord chop($_[3]);
    $isobis &= ($tl == 0x7) if ($cntdown == $elements);
#Log3 $hash, 3, "OBIS_Parse_List : TL is " . sprintf("%02X", $tl);
	my $len = $tl & 0xf;
	my $tltype = $tl & 0x70;
    my $tllast = $tl;
	while ($tllast & 0x80) {
	  $tllast = ord chop($_[3]);
	  if ($tl & 0x70) {
		Log3 $hash, 3, "2nd TL-byte != 0, reserved according spec";
      }
      $len = ($len*16) + ($tllast & 0xf);
	}
    $len--;
    return undef if ($len>length $_[3] || $len<0);

    if ($tltype == 0) {
      # String
      if ($len<=0) {
        push @result, "";
      } elsif (($len==6) && ($cntdown==$elements)) {
        push @result, sprintf("%d-%d:%d.%d.%d*%d",
				ord chop($_[3]), ord chop($_[3]),
				ord chop($_[3]), ord chop($_[3]),
				ord chop($_[3]), ord chop($_[3]));
      } else {
        my $str;
		while ($len--) {
		  $str .= sprintf ("%02X", ord chop($_[3]));
        }
        if ($elements==7 && $#result==4) {
		  if($result[0]=~$SML_specialities{"HEX4"}[0]) {
			$str=$SML_specialities{"HEX4"}[1]->($str)
		  } elsif($result[0]=~$SML_specialities{"HEX2"}[0]) {
			$str=$SML_specialities{"HEX2"}[1]->($str)
		  } else {
			$str=~s/([A-F0-9]{2})/chr(hex($1))/eg;
			$str=~s/[^!-~\s\r\n\t]//g;
          }
        }
        push @result, $str;
      }
    } elsif ($tltype == 0x50 || $tltype == 0x60) {
      # Signed (5) or Unsigned (6) Int
      my $num = 0;
      if ($tltype==0x60 && $len>3 && $result[0]=~/^1-0:16\.7\.0/ && $hash->{helper}{DZGHACK}) {
		$tltype = 0x50;
      }
      $num = ord chop($_[3]) if ($len--);
	  my $subme = ($tltype == 0x50) && ($num & 0x80) ? ( 1 << (8*($len+1)) ) : 0;
	  while ($len-- > 0) {
		$num = ($num<<8) | ord chop($_[3]);
      }
      push @result, ($num-$subme);
    } elsif ($tltype == 0x40) {
      push @result, (ord chop($_[3]) != 0);
    } elsif ($tltype == 0x70) {
      push @result, ref OBIS_Parse_List($hash, $_[1], $len+1, $_[3]);
    }
	$cntdown--;
  }
  my $i = 0;
  return @result if (!$isobis);

  # We should have now an 7 element array: reading(0), status(1), valTime(2), unit(3), scaler(4), data(5)
  if ($result[4] && looks_like_number($result[4]) && looks_like_number($result[5])) {
    $result[5] *= ($result[4]<-5 || $result[4]>5) ? 10**$result[4] : $pow10plus5[$result[4]+5];
  }
  if (looks_like_number($result[3])) {
    my $repl = $unitmap{$result[3]};
    $result[3] = $repl // "var";
  }
  if (looks_like_number($result[1])) {
    $result[5] = (($result[1] == 0xA2) ? "<" : (($result[1] == 0x82) ? ">" : "")) . $result[5];
  }

  my $line = $result[0] . "(" . $result[5] . ($result[3] eq "" ? "" : "*".$result[3]) . ")\r\n";
  $hash->{helper}{DZGHACK} = 1 if ($line=~/^1-0:96\.50\.1\*255\(DZG\)/);
  $_[1] .= $line;
  return undef;

#  Log3 $hash,3,"OBIS line is " . $line . $line2 . ")";
# $line.$line2.")\r\n"
#  while ($i < scalar @result) {
#    Log3 $hash,3,"List element $i is " . $result[$i];
#    $i++;
#  }
}

# Input: devhash, bytesequence
# Output: decoded text, remaining buffer
sub OBIS_trySMLdecode($$)
{
	my ( $hash, $remainingSML ) = @_;
    my $name = $hash->{NAME};
    my $ll = AttrVal($name, "verbose", 3);
	my $t=$remainingSML;
	if ($remainingSML=~m/SML\((.*)\)/g) {
		$remainingSML=$1
	};
	return $remainingSML
		if($remainingSML!~/[\x00-\x09|\x10-\x1F]/g);
	$hash->{MeterType}="SML";

    # Fast fail for messages w/o end tag
	my $newMsg="";
    do {
      # 1) endTag has to be found, 2) startTag has to be found, 3) end behind start:
	  my $endtagIdx = index ($remainingSML, $SML_ENDTAG);
	  return ("", $remainingSML)
		if ($endtagIdx<0 || ((length $remainingSML)-$endtagIdx) < 8);
      my $startIdx = index ($remainingSML, $SML_START);
	  return ("", substr($remainingSML, $endtagIdx+8))
		if ($startIdx<0);
	  return ("", substr($remainingSML, $startIdx))
		if ($startIdx>=$endtagIdx);

	  my $msg=substr($remainingSML, $startIdx, $endtagIdx+8-$startIdx);
      Log3 $hash,5,"OBIS ($name) - SML-Parse " . uc(unpack('H*',$msg)) if ($ll>=5);
	  if (OBIS_CRC16($hash,$msg) == 1) {
		$remainingSML=""; #reset possible further messages if actual CRC ok; if someone misses some messages, we remove it. 
		my $OBISmsg="";
		my $initstr="/";
		Log3 $hash,5,"OBIS ($name) - Full message-> " . uc(unpack('H*',$msg)) if ($ll>=5);

		OBIS_Parse_List($hash, $newMsg, 9999, scalar reverse substr($msg, 8, $endtagIdx-8));

		$initstr=~s/\\$//;
		$newMsg=$initstr.chr(13).chr(10).$newMsg;
		$newMsg.="!".chr(13).chr(10);
		Log3 $hash,4,"OBIS ($name) - MSG IS: \r\n$newMsg" if ($ll>=4);
	  } else {
		$hash->{CRC_Errors}+=1;
		Log3 $hash,4,"OBIS ($name) - CRC Error in Input" if ($ll>=4);
		$remainingSML = substr($remainingSML, $endtagIdx+8);
	  }
	} while (length ($remainingSML)>4);
	return ($newMsg,$remainingSML);
}

sub OBIS_Parse($$)
{
	my ($hash, $buf) = @_;
	my $name = $hash->{NAME};

# gvz Unsure what this is for
#	my $buf2=uc(unpack('H*',$buf));
#	if($hash->{MeterType}!~/SML|Unknown/ && $buf2=~m/7701([0-9A-F]*?)01/g) {
#		Log3 $hash, 3, "OBIS ($name) - OBIS_Ext called";
#		my (undef,undef,$OBISid,undef)=OBIS_decodeTL($1);
#		
#	  	my $device_name = "OBIS.".$OBISid;
#  		Log3 $hash,5,"OBIS ($name) - New Devicename: $device_name";
#  		my $def = $modules{OBIS}{defptr}{"$device_name"};
#  		if(!$def) {
#        	Log3 $hash, 3, "OBIS ($name) - Unknown device $device_name, please define it";
#        	return "UNDEFINED $device_name OBIS none Ext $OBISid";
#  		}
#	}
	$hash->{helper}{BUFFER} .= $buf;
	if (length($hash->{helper}{BUFFER}) >10000) { #longer than 3 messages, this is a traffic jam
	  	$hash->{helper}{BUFFER}  =substr( $hash->{helper}{BUFFER} , -10000);
	}	
	my %dir=("<"=>"out",">"=>"in");
	my $buffer=$hash->{helper}{BUFFER};
	my $remainingSML;
	($buffer,$remainingSML) = OBIS_trySMLdecode($hash,$buffer) if ($hash->{MeterType}=~/SML|Ext|Unknown/);
	my $type= $hash->{MeterType};
	$buf='/'.$buf;  
	$buf =~ /!((?!\/).*)$/gmsi;
	$buf=$1;
    my $ll = AttrVal($name, "verbose", 3);
	
    my $crlfPos = index($buffer,chr(13).chr(10));
	if($crlfPos > -1){
		readingsBeginUpdate($hash);
		my $ignoreUnknownOff = AttrVal($name,"ignoreUnknown","off") eq "off";
		my $unitReadingsOff = AttrVal($name,"unitReadings","off") eq "off";
		my $extChannels = AttrVal($name,"extChannels","auto");
		my $ruleCache = $hash->{helper}{RULECACHE};
		
	    while($crlfPos > -1)
	    {
		    my $rmsg="";
		    $rmsg = substr($buffer, 0, $crlfPos);
			Log3 $hash,5,"OBIS ($name) - Msg-Parse: $rmsg" if ($ll>=5);
				my $channel=" ";
				if($rmsg=~/\/.*|^((?:\d{1,3}-\d{1,3}:)?(?:\d{1,3}|[CF]).\d{1,3}(?:.\d{1,3})?(?:\*\d{1,3})?)(?:\(.*?\))?\(.*?\)|!/) { # old regex: \/.*|\d-\d{1,3}:\d{1,3}.\d{1,3}.\d{1,3}\*\d{1,3}\(.*?\)|!
					if (length $1) {
						$channel=$1;
						$channel=~tr/:*-/.../;
#						Log 3,"Channel would be: $channel";
					}
					if ($hash->{MeterType} eq "Unknown") {$hash->{MeterType}="Standard"}
			
			# End of Message
					if ($rmsg=~/^!.*/) {
						$hash->{helper}{EoM}+=1 if ($hash->{helper}{DEVICES}[1]>0);
					}
			#Version
					elsif ($rmsg=~ /.*\/(.*)/) {
					  	DevIo_SimpleWrite($hash,$hash->{helper}{DEVICES}[2],undef) if (!$hash->{helper}{DEVICES}[2] eq "");
				  		if (ReadingsVal($name,"Version","") ne $1) {readingsBulkUpdate($hash, "Version"  ,$1); }
			 			$hash->{helper}{EoM}=0;
				  	}
				  	elsif ($hash->{helper}{EoM}!=1) {
				  		my $found=0;
						# Check superseeding settings in channels attribute:
				  		if (!($hash->{helper}{Channels}{$channel} //$hash->{helper}{Channels}{$1})) {
							my $cache_code = $rmsg;
							$cache_code =~ s/\(.*$//;
							my $code = $ruleCache->{$cache_code};
#				  			Log3 $hash,3,"OBIS ($name) - Cache result for " . $cache_code . " is " . $code;
							if (! defined $code) {
							    for my $c (keys %OBIS_codes) {
									if ($rmsg =~ $OBIS_codes{$c}) {
										$ruleCache->{$cache_code} = $c;
				  						Log3 $hash,4,"OBIS ($name) - Storing $c for $cache_code in Cache";
										$hash->{helper}{RULECACHE} = $ruleCache;
										$code = $c;
									}
								}
							}
							if (defined $code && $code ne "unknown") {
									if ($rmsg =~ $OBIS_codes{$code}) {
										Log3 $hash,5,"OBIS ($name) - Msg $rmsg is of type $code" if ($ll>=5);
										if (rindex ($code, "Channel_sum", 0) eq 0) {
								    		my $L= $hash->{helper}{Channels}{$channel} //$hash->{helper}{Channels}{$1} // "sum_$OBIS_channels{$1}" //$channel;
    										if ($ignoreUnknownOff || $L ne $channel) {
							  					readingsBulkUpdate($hash, $L,(looks_like_number($3) ? $3+0 : $3).($unitReadingsOff?"":" $4"));
							  					readingsBulkUpdate($hash, "dir_$L",$hash->{helper}{directions}{$2} // $dir{$2}) if (length $2);
    										}
										}
										 
										elsif (rindex ($code, "Channels", 0) eq 0) {
								    		my $L=$hash->{helper}{Channels}{$channel} //$hash->{helper}{Channels}{$1} //  $OBIS_channels{$1} //$channel;
    										if ($ignoreUnknownOff || $L ne $channel) {
							  					readingsBulkUpdate($hash, "$L",(looks_like_number($3) ? $3+0 : $3).($unitReadingsOff?"":" $4"));
							  					readingsBulkUpdate($hash, "dir_$L",$hash->{helper}{directions}{$2} // $dir{$2}) if (length $2);
    										}
										}
										
										elsif (rindex ($code, "Counter", 0) eq 0) {
											my $L=$hash->{helper}{Channels}{$channel} //$hash->{helper}{Channels}{$1.".".$2} // $OBIS_channels{$1.".".$2} // $channel;
											my $chan=$3+0 > 0 ? "_Ch$3" : "";
											if ($extChannels eq "auto" && defined $4) {
												my $ecp = $Ext_Channel_Postfix{$4};
												$chan.= $ecp // ".$4";
											} elsif ($extChannels eq "on") {
												$chan.=".$4" if $4;
											}
    										if ($ignoreUnknownOff || $L ne $channel) {
												if($1==1) {
    												Log3($hash,4,"OBIS ($name) - Set ".$L.$chan." to ".((looks_like_number($3) ? $6+0 : $5) +AttrVal($name,"offset_energy",0))) if ($ll>=4);

													readingsBulkUpdate($hash, $L.$chan  ,(looks_like_number($3) ? $6+0 : $5) +AttrVal($name,"offset_energy",0).($unitReadingsOff?"":" $7")); 
												} elsif ($1==2) {
													readingsBulkUpdate($hash, $L.$chan  ,(looks_like_number($3) ? $6+0 : $5) +AttrVal($name,"offset_feed",0).($unitReadingsOff?"":" $7")); 				
												}
							  					readingsBulkUpdate($hash, "dir_$L",$hash->{helper}{directions}{$4} // $dir{$4}) if (length $4);
    										}											
										} else {
											my $data=$1;
											if (rindex ($code, "Time", 0) eq 0) {
		    									if($rmsg=~$SML_specialities{"TIME"}[0]) {
		    										$data=~/(\d+)/;
		    										$data=$SML_specialities{"TIME"}[1]->($1)
		    									}
											} elsif ($code eq "Status" || $code eq "PublicKey") {
												if ($rmsg=~$SML_specialities{"HEX4"}[0]) {
		    				    					$data=$SML_specialities{"HEX4"}[1]->($data)
												}
											} elsif ($code eq "Owner" || $code eq "Serial") {
	    										$data=$SML_specialities{"HEX2"}[1]->($data)
		    								} 

											my $userChannelName = $hash->{helper}{Channels}{$channel};
											$code = $userChannelName if (defined $userChannelName);
											if (defined $1) {
												$userChannelName = $hash->{helper}{Channels}{$1};
												$code = $userChannelName if (defined $userChannelName);
											}
											readingsBulkUpdate($hash, $code  ,$data);
										}
										$found=1;
									}
								} else {
									if (! $code) {
						  			  Log3 $hash,3,"OBIS ($name) - Unknown Message: $rmsg";
                                      $ruleCache->{$cache_code} = "unknown";
                                      $hash->{helper}{RULECACHE} = $ruleCache;
									}
								}
				  			}
				     		if ($found==0) {
#				     			Log 3,"Found a Channel-Attr";
				     			$rmsg=~/^((?:\d{1,3}-\d{1,3}:)?(?:\d{1,3}|[CF]).\d{1,3}(?:.\d{1,3})?(?:\*\d{1,3})?)(?:\((.*?)\))?\((.*?)\)/;
    							my $chan=$hash->{helper}{Channels}{$channel} //$hash->{helper}{Channels}{$1} //  $OBIS_channels{$1} //$channel;
    							my $chan1=$chan;
    							my $chan2=$chan."_2";
#    							Log 3,"Setting $chan";
    							my $v1=$3;
    							my $v2;
								my $valueBracket = AttrVal($name,"valueBracket","second");
    							if ($valueBracket eq "first") {
    								$v1=length $2 ? $2 : $3;
    							} elsif ($valueBracket eq "both") {
    								$v2=$2;
    								($v1,$v2)=($v2,$v1);
    								if (!length $v1 and length $v2) {$v1=$v2;$v2=""}
    								$chan1.="_1" if length $2;
    							}
    							if ($unitReadingsOff) {
    								$v1=~s/(.*)\*.*/$1/;
    								if ($v2) {$v2=~s/(.*)\*.*/$1/};
    							}
    							$v1+=0 if (looks_like_number($v1));
    							$v2+=0 if (looks_like_number($v2));
								
    							if ($ignoreUnknownOff || $chan ne $channel) {
									readingsBulkUpdate($hash, $chan1  ,$v1) if length $v1;
									readingsBulkUpdate($hash, $chan2  ,$v2) if length $v2;
								}
				     		}
#			   			}
				  	}
		   			if ($hash->{helper}{EoM}==1) {last;}
			  	}
	       $buffer = substr($buffer, $crlfPos+2);
		   $crlfPos = index($buffer,chr(13).chr(10));
    	}
    	readingsEndUpdate($hash,1);
        $hash->{helper}{LastPacketTime} = gettimeofday;
	}
    if (defined($remainingSML)) {$hash->{helper}{BUFFER}=$remainingSML}
    	else{$hash->{helper}{BUFFER}=$buffer;}
	if($hash->{helper}{EoM}==1) { $hash->{helper}{BUFFER}="";}
    return $name;
}


#####################################
sub OBIS_Ready($)
{
  my ($hash) = @_;
  return DevIo_OpenDev($hash, 1, "OBIS_Init", $hash->{helper}{NETDEV} ? "OBIS_Callback" : undef)
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
    #{$hash->{"test"}->{SetFn} = "OBIS_Set"}
    if ($cmd eq "del") {
		if ($aName eq "channels") { $hash->{helper}{Channels}=undef;}
		if ($aName eq "interval") {
		  		RemoveInternalTimer($hash,"GetUpdate");
				$hash->{helper}{DEVICES}[1]=0;
		}
		if ($aName eq "pollingMode") {
				delete($readyfnlist{"$name.$dev"});
				$selectlist{"$name.$dev"} = $hash;
				DevIo_CloseDev($hash);
				DevIo_OpenDev($hash, 0, "OBIS_Init");
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
		
		if ($aName eq "directions") {
	      $hash->{helper}{directions}=eval $aVal;
			if ($@) {
				Log3 $name, 3, "OBIS ($name) - X: Invalid regex in attr $name $aName $aVal: $@";
				$hash->{helper}{directions}=undef;
			}
		}
		if ($aName eq "interval") {
			if ($aVal=~/^[1-9][0-9]*$/) {
			    $hash->{helper}{TRIGGERTIME}=gettimeofday();
		  		RemoveInternalTimer($hash,"GetUpdate");
				$hash->{helper}{DEVICES}[1]=$aVal;
				my $t=OBIS_adjustAlign($hash,AttrVal($name,"alignTime",undef),$hash->{helper}{DEVICES}[1]);
			    Log3 ($hash,5,"OBIS ($name) - Internal timer set to ".FmtDateTime($t)) if ($hash->{helper}{DEVICES}[1]>0);
				InternalTimer($t, "GetUpdate", $hash, 0)  if ($hash->{helper}{DEVICES}[1]>0);
			} else {
				return "OBIS ($name) - $name: attr interval must be a number -> $aVal";
			}
		}
		if ($aName eq "alignTime") {
			 if ($hash->{helper}{DEVICES}[1]>0 || !$init_done) {
			 	if ($aVal=~/\d+/) {
			  		RemoveInternalTimer($hash,"GetUpdate");
				    $hash->{helper}{TRIGGERTIME}=gettimeofday();
					my $t=OBIS_adjustAlign($hash,$aVal,$hash->{helper}{DEVICES}[1]);
				    Log3 ($hash,5,"OBIS ($name) - Internal timer set to ".FmtDateTime($t));
					InternalTimer($t, "GetUpdate", $hash, 0);
			 	} else {return "OBIS ($name): attr alignTime must be a Value >0"}
			 } else {
			 	if ($init_done) {
 					return "OBIS ($name): attr alignTime is useless, if no interval is specified";
			 	}
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
  if (!$attrVal) {return gettimeofday()+$interval;}
  my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($attrVal);
  return "$hash->{NAME} alignTime: $alErr" if($alErr);
  my $tspec=strftime("\%H:\%M:\%S", gmtime($interval));
#  Obis_adjustAlignTimetest2($hash,AttrVal($hash->{NAME},"alignTime",undef),$hash->{helper}{DEVICES}[1]);
  
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
  $ttime += $step if($ttime <= $now);
  $hash->{NEXT} = FmtDateTime($ttime);
  $hash->{helper}{TRIGGERTIME} = ($off2<=$alTime) ? $ttime : (gettimeofday());
  
  return $hash->{helper}{TRIGGERTIME};
}

sub OBIS_hex2int {
    my ($hexstr) = @_;
    return 0  
      if $hexstr !~ /^[0-9A-Fa-f]{1,35}$/;
    my $num = hex($hexstr);
    return $num >> 31 ? $num - 2 ** 32 : $num;
}

sub OBIS_CRC16($$) {
	my ($hash,$buff)=@_;
	my @crc16 = ( 0x0000, 0x1189, 0x2312, 0x329b, 0x4624, 0x57ad, 0x6536, 0x74bf, 0x8c48,
		0x9dc1, 0xaf5a, 0xbed3, 0xca6c, 0xdbe5, 0xe97e, 0xf8f7, 0x1081, 0x0108, 0x3393, 0x221a, 0x56a5, 0x472c,
		0x75b7, 0x643e, 0x9cc9, 0x8d40, 0xbfdb, 0xae52, 0xdaed, 0xcb64, 0xf9ff, 0xe876, 0x2102, 0x308b, 0x0210,
		0x1399, 0x6726, 0x76af, 0x4434, 0x55bd, 0xad4a, 0xbcc3, 0x8e58, 0x9fd1, 0xeb6e, 0xfae7, 0xc87c, 0xd9f5,
		0x3183, 0x200a, 0x1291, 0x0318, 0x77a7, 0x662e, 0x54b5, 0x453c, 0xbdcb, 0xac42, 0x9ed9, 0x8f50, 0xfbef,
		0xea66, 0xd8fd, 0xc974, 0x4204, 0x538d, 0x6116, 0x709f, 0x0420, 0x15a9, 0x2732, 0x36bb, 0xce4c, 0xdfc5,
		0xed5e, 0xfcd7, 0x8868, 0x99e1, 0xab7a, 0xbaf3, 0x5285, 0x430c, 0x7197, 0x601e, 0x14a1, 0x0528, 0x37b3,
		0x263a, 0xdecd, 0xcf44, 0xfddf, 0xec56, 0x98e9, 0x8960, 0xbbfb, 0xaa72, 0x6306, 0x728f, 0x4014, 0x519d,
		0x2522, 0x34ab, 0x0630, 0x17b9, 0xef4e, 0xfec7, 0xcc5c, 0xddd5, 0xa96a, 0xb8e3, 0x8a78, 0x9bf1, 0x7387,
		0x620e, 0x5095, 0x411c, 0x35a3, 0x242a, 0x16b1, 0x0738, 0xffcf, 0xee46, 0xdcdd, 0xcd54, 0xb9eb, 0xa862,
		0x9af9, 0x8b70, 0x8408, 0x9581, 0xa71a, 0xb693, 0xc22c, 0xd3a5, 0xe13e, 0xf0b7, 0x0840, 0x19c9, 0x2b52,
		0x3adb, 0x4e64, 0x5fed, 0x6d76, 0x7cff, 0x9489, 0x8500, 0xb79b, 0xa612, 0xd2ad, 0xc324, 0xf1bf, 0xe036,
		0x18c1, 0x0948, 0x3bd3, 0x2a5a, 0x5ee5, 0x4f6c, 0x7df7, 0x6c7e, 0xa50a, 0xb483, 0x8618, 0x9791, 0xe32e,
		0xf2a7, 0xc03c, 0xd1b5, 0x2942, 0x38cb, 0x0a50, 0x1bd9, 0x6f66, 0x7eef, 0x4c74, 0x5dfd, 0xb58b, 0xa402,
		0x9699, 0x8710, 0xf3af, 0xe226, 0xd0bd, 0xc134, 0x39c3, 0x284a, 0x1ad1, 0x0b58, 0x7fe7, 0x6e6e, 0x5cf5,
		0x4d7c, 0xc60c, 0xd785, 0xe51e, 0xf497, 0x8028, 0x91a1, 0xa33a, 0xb2b3, 0x4a44, 0x5bcd, 0x6956, 0x78df,
		0x0c60, 0x1de9, 0x2f72, 0x3efb, 0xd68d, 0xc704, 0xf59f, 0xe416, 0x90a9, 0x8120, 0xb3bb, 0xa232, 0x5ac5,
		0x4b4c, 0x79d7, 0x685e, 0x1ce1, 0x0d68, 0x3ff3, 0x2e7a, 0xe70e, 0xf687, 0xc41c, 0xd595, 0xa12a, 0xb0a3,
		0x8238, 0x93b1, 0x6b46, 0x7acf, 0x4854, 0x59dd, 0x2d62, 0x3ceb, 0x0e70, 0x1ff9, 0xf78f, 0xe606, 0xd49d,
		0xc514, 0xb1ab, 0xa022, 0x92b9, 0x8330, 0x7bc7, 0x6a4e, 0x58d5, 0x495c, 0x3de3, 0x2c6a, 0x1ef1, 0x0f78);
		
	my $crc=0xFFFF;
	my $a=reverse substr($buff,0,-2);
	my $b=substr($buff,-2);
	my $crc2=OBIS_hex2int(uc(unpack('H*',$b)));
	while (length $a) {
		$crc = ($crc >> 8) ^ $crc16[($crc ^ ord(chop $a)) & 0xff];
	}
	$crc ^= 0xffff;
    $crc = (($crc & 0xff) << 8) | (($crc & 0xff00) >> 8);
	return $crc2==$crc ? 1 : 0;
}
 
1;

=pod
=item device
=item summary    Collects data from Smartmeters that report in OBIS-Standard
=item summary_DE Wertet Smartmeter aus, welche ihre Daten im OBIS-Standard senden
=begin html

<a name="OBIS"></a>
<h3>OBIS</h3>
<ul>
  This module is for SmartMeters, that report their data in OBIS-Standard. It doesn't matter,
  whether the data comes as PlainText or SML-encoded.
  <br><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OBIS device|none [MeterType] </code><br>
    <br>
      &lt;device&gt; specifies the serial port or hostname/ip-address:port
      to communicate with the smartmeter.
      In case of a <b>serial device</b> and with Linux:
      <ul>
      <li>the device will be named /dev/ttyUSBx, where x is a number.</li>
      <li>or - to avoid wrong numbering on server reboots - use the ID of the USB device, e.g.
      /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A106Q3OW-if00-port0</li>
      </ul>
      You may specify the baudrate used after the @ char, 9600 is common<br>
      <br>
      If you use a ser2net connection, &lt;device&gt; is ip-address:port or hostname:port.<br>
      <br>
      Optional: MeterType can be of
      <ul><li>VSM102 -&gt; Voltcraft VSM102</li>
      <li>E110 -&gt; Landis&&;Gyr E110</li>
      <li>E350USB -&gt; Landis&&;Gyr E350 USB-Version</li>
      <li>Standard -&gt; Data comes as plainText</li>
      <li>SML -&gt; Smart Message Language</li></ul>
      <br>
      Example: <br>
    <code>define myPowerMeter OBIS /dev/ttyPlugwise@9600,7,E,1 VSM102</code><br>
    <code>define myPowerMeter OBIS 192.168.0.12:1234 Standard</code>
      <br>
    <br>
  </ul>
  <b>Attributes</b>
  <ul><li>
    <code>offset_feed <br>offset_energy</code><br>
      If your smartmeter is BEHIND the meter of your powersupplier, then you can hereby adjust
      the total-reading of your SM to that of your official one.
      </li><li>
   <code>channels</code><br>
      With this, you can rename the reported channels.<BR>e.g.: 
      <code>attr myOBIS channels {"1.0.96.5.5.255"=>"Status","1.0.0.0.0.255"=>"Info","16.7"=>"Verbrauch"}</code>
      </li><li>
   <code>directions</code><br>
      Some Meters report feeding/comnsuming of power in a statusword.
      If this is set, you get an extra reading dir_total_consumption which defaults to "in" and "out".<BR>
      Here, you can change this text with, e.g.: 
      <code>attr myOBIS directions {">" => "pwr consuming", "<"=>"pwr feeding"}</code>
      </li><li>
   <code>extChannels</code><br>
      Possible values:<br>
	  <code>auto</code> (default). The values 0 and 255 will give the base counter name like with off.
	  Values from 96 to 100 add a postfix "_last1d" / "_last7d", "_last30d", "_last365d" and
	  "_since_rst" to the reading. Other values lead to results like "on".<br/>
	  <code>off</code> Historical values are not considered and might overwrite current values.<br/>
	  <code>on</code> Every counter-reading gets appended by the extChannel-number, e.g.
      <code>total_consumption</code> becomes <code>total_consumption.255</code>
      </li><li>
   <code>interval</code><br>
      The polling-interval in seconds. (Only useful in Polling-Mode)
      </li><li>
   <code>alignTime</code><br>
      Aligns the intervals to a given time. Each interval is repeatedly calculated.
      So if alignTime=00:00 and interval=600 aligns the interval to xx:00:00, xx:10:00, xx:20:00 etc....
      </li><li>  
   <code>pollingMode</code><br>
      Changes from direct-read to polling-mode.
      Useful with meters, that send a continous datastream. 
      Reduces CPU-load.  
      </li><li>
   <code>unitReadings</code><br>
      Adds the units to the readings like w, wH, A etc.
      </li><li>  
   <code>valueBracket</code><br>
      Sets, if to use the value from the first or the second bracket, if applicable.
      Standard is "second"
      </li><li>  
   <code>resetAfterNoDataTime</code><br>
      If on a TCP-connection no data was received for the given time, the connection is
      closed and reopened
      </li>
      
  <br>
</ul></ul>

=end html

=begin html_DE

<a name="OBIS"></a>
<h3>OBIS</h3>
<ul>
  Modul für Smartmeter, die ihre Daten im OBIS-Standard senden. Hierbei ist es egal, ob die Daten als reiner Text oder aber SML-kodiert kommen.
  <br><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OBIS device|none [MeterType] </code><br>
    <br>
      &lt;device&gt; gibt den seriellen Port oder den Hostnamen/die IP-Adresse:Port an. <br>
      Bei <b>seriellem Port</b> (USB) und Linux gibt man hier entweder
      <ul>
      <li>als Ger&auml;t etwas wie /dev/ttyUSBx, an (x eine Zahl)</li>
      <li>oder - um nach einem Neustart der Hardware keine ge&auml;nderte Reihenfolge zu riskieren -
      sucht man die passende ID unter /dev/serial/by-id/, also z.B.
      /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A106Q3OW-if00-port0</li>
      </ul>
      <br><br>
      Optional: MeterType kann sein:
      <ul><li>VSM102 -&gt; Voltcraft VSM102</li>
      <li>E110 -&gt; Landis&&;Gyr E110</li>
      <li>E350USB -&gt; Landis&&;Gyr E350 USB-Version</li>
      <li>Standard -&gt; Daten kommen als plainText</li>
      <li>SML -&gt; Smart Message Language</li></ul>
      <br>
      Beispiel: <br>
    <code>define myPowerMeter OBIS /dev/ttyPlugwise@9600,7,E,1 VSM102</code><br>
    <code>define myPowerMeter OBIS 192.168.0.12:1234 Standard</code>
      <br>
    <br>
  </ul>
  <b>Attribute</b>
  <ul><li>
    <code>offset_feed <br>offset_energy</code><br>
      Wenn das Smartmeter hinter einem Zähler des EVU's sitzt, kann hiermit der Zähler des
      Smartmeters an den des EVU's angepasst werden.
      </li><li>
   <code>channels</code><br>
      Hiermit können die einzelnen Kanal-Readings mittels RegExes umbenannt werden.<BR>
      Beispiel: <code>attr myOBIS channels {"1.0.96.5.5.255"=>"Status","1.0.0.0.0.255"=>"Info","16.7"=>"Verbrauch"}</code>
      </li><li>
   <code>directions</code><br>
      Manche SmartMeter senden im Statusbyte die Stromrichtung.
      In diesem Fall gibt es ein extra Reading "dir_total_consumption" welches standardmäßig "in" and "out" beinhaltet<BR>
      Hiermit kann dieser Text geändert werden, z.B.:
      <code>attr myOBIS directions {">" => "pwr consuming", "<"=>"pwr feeding"}</code>
      </li><li>
   <code>extChannels</code><br>
      M&ouml;gliche Werte:<br>
	  <code>auto</code> (default). Die Werte 0 und 255 werden wie bei extChannels off geschrieben.
	  Die Werte 96-100 f&uuml;hren zu Postfix "_last1d" / "_last7d", "_last30d", "_last365d" und
	  "_since_rst". Andere Werte werden wie bei "on" geschrieben.<br/>
	  <code>off</code> Historische Werte werden nicht ber&uuml;cksichtigt und 
	  &uuml;berschreiben ggf. aktuelle Werte.<br/>
	  <code>on</code> Jedem Counter-Wert wird die extChannel-Nummer angeh&auml;ngt, aus
      <code>total_consumption</code> wird z.B. <code>total_consumption.255</code>
      </li><li>
   <code>interval</code><br>
      Abrufinterval der Daten. (Bringt nur im Polling-Mode was)
      </li><li>
   <code>alignTime</code><br>
      Richtet den Zeitpunkt von <interval> nach einer bestimmten Uhrzeit aus. 
      </li><li>
   <code>pollingMode</code><br>
      Hiermit wird von Direktbenachrichtigung auf Polling umgestellt.
      Bei Smartmetern, welche von selbst im Sekundentakt senden,
      kann das zu einer spürbaren Senkung der Prozessorleistung führen.
      </li><li>  
   <code>unitReadings</code><br>
      Hängt bei den Readings auch die Einheiten an, zB w, wH, A usw.
      </li><li>  
   <code>valueBracket</code><br>
      Legt fest, ob der Wert aus dem ersten oder zweiten Klammernpaar genommen wird. 
      Standard ist "second"
      </li><li>  
   <code>resetAfterNoDataTime</code><br>
      Bei TCP-Verbindungen wird nach der angegebenen Zahl Sekunden die Verbindung
      geschlossen und neu ge&ouml;ffnet, wenn keine Daten empfangen wurden
      </li>
  <br>
</ul></ul>

=end html_DE

=cut
