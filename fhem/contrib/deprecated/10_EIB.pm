##############################################
# $Id$
# MH various changes/fixes from forum e.g dpt9, 0 is not necessarily off, ...
# MH 20140313 changed Log to Log3, verbose instead of loglevel
# MH 20140313 testing setstate....
# MH 20141202 changing to readingsupdate
# MH 20150518 . based on SVN 10_EIB.pm 8584 2015-05-15 18:46:52Z andi291 
# ABU 20150617 added dpt1, removed special handling of dpt5, added default-values for messages without dpt, changed retVal of EIB_ParseByDatapointType
# MH 20150622 added getGx/setGx Readings and Attr EIBreadingX
# ABU 20150617 cleanup unused lines, finalized dpt-handling, cleanup logging, added debug-par
# ABU 20150729 removed special handling DPT7 in write, fixed DPT7 encoding
# ABU 20150812 renamed return-value for autocreate; added attribute for reading containing sender; fixed HTML-Doku
# ABU 20150917 cleaned up, implemented DPT16 for sending, implemented DPT6, added EIBanswerOnRead, changed time/date-handling, fixed DPT14-sending, removed Root-Causes for several warnings
# ABU 20150919 fixed set string containing letter g
# ABU 20150920 removed ne-warning, added attribute eventMarker, fixed behaviour if no model defined
# ABU 20150922 fixed DPT14, restructured DPT9, fixed datum and time
# ABU 20150923 improved failure-tolerance for none / wrong model
# ABU 20150924 fixed date/time again
# ABU 20150926 removed eventMarker, removed no get for dummies
# ABU 20151207 added dpt3, fixed doku-section myDimmer
# ABU 20151213 added dpt13
# ABU 20151221 added multiple group support for get according thread 45954
# ABU 20160111 added feature EIBreadingRegex, EIBwritingRegex, Fixed some doku
# ABU 20160116 fixed motd-error due to debug-mode
# ABU 20160122 fixed doku, changed return value for EIB_Set from undef to "", reintegrated multiple group sending
# ABU 20160123 fixed issue for sending with additional groups
# ABU 20180311 added summary in description

package main;

use strict;
use warnings;

my $debug=0;

# Open Tasks
#  - precision for model percent to 0,1
#  - allow defined groups that are only used for sending of data (no status shown)

my %eib_c2b = (
	"off" => "00",
	"on" => "01",
	"on-for-timer" => "01",
	"on-till" => "01",
	"raw" => "",
	"value" => "",#value must be last.. because of slider functionality in Set
	"string" => "" #value must be last.. because of slider functionality in Set
);

my %codes = (
	"00" => "off",
	"01" => "on",
	"" => "value",
);

my %readonly = (
	"dummy" => 1,
);

my $eib_simple ="off on value on-for-timer on-till";
my %models = (
);

my %eib_dpttypes = (
  #Binary value
  "dpt1" 		=> {"CODE"=>"dpt1", "UNIT"=>"",  "factor"=>1},
  
  
  #Step value (four-bit)
  "dpt3" 		=> {"CODE"=>"dpt3", "UNIT"=>"",  "factor"=>1},

  # 1-Octet unsigned value
  "dpt5" 		=> {"CODE"=>"dpt5", "UNIT"=>"",  "factor"=>1},
  "percent" 	=> {"CODE"=>"dpt5", "UNIT"=>"%", "factor"=>100/255, "slider"=>"0,1,100"},
  "dpt5.003" 	=> {"CODE"=>"dpt5", "UNIT"=>"&deg;", "factor"=>360/255},
  "angle" 		=> {"CODE"=>"dpt5", "UNIT"=>"&deg;", "factor"=>360/255}, # alias for dpt5.003
  "dpt5.004" 	=> {"CODE"=>"dpt5", "UNIT"=>"%", "factor"=>1},
  "percent255" 	=> {"CODE"=>"dpt5", "UNIT"=>"%", "factor"=>1 , "slider"=>"0,1,255"}, #alias for dpt5.004
  "dpt5.Slider"	=> {"CODE"=>"dpt5", "UNIT"=>"",  "factor"=>100/255, "slider"=>"0,1,100"}, ##MH same as percent w.o. unit
	
  # 1-Octet signed value
  "dpt6" 		=> {"CODE"=>"dpt6", "UNIT"=>"",  "factor"=>1},
  "dpt6.001" 		=> {"CODE"=>"dpt6", "UNIT"=>"%",  "factor"=>1},
  "dpt6.010" 		=> {"CODE"=>"dpt6", "UNIT"=>"",  "factor"=>1},

  # 2-Octet unsigned Value (current, length, brightness)
  "dpt7" 		=> {"CODE"=>"dpt7", "UNIT"=>""},
  "length-mm" 		=> {"CODE"=>"dpt7", "UNIT"=>"mm"},
  "current-mA" 		=> {"CODE"=>"dpt7", "UNIT"=>"mA"},
  "brightness"		=> {"CODE"=>"dpt7", "UNIT"=>"lux"},
  "timeperiod-ms"		=> {"CODE"=>"dpt7", "UNIT"=>"ms"},
  "timeperiod-min"		=> {"CODE"=>"dpt7", "UNIT"=>"min"},
  "timeperiod-h"		=> {"CODE"=>"dpt7", "UNIT"=>"h"},

  # 2-Octet Float  Value (Temp / Light)
  "dpt9" 		=> {"CODE"=>"dpt9", "UNIT"=>""},
  "tempsensor"  => {"CODE"=>"dpt9", "UNIT"=>"&deg;C"},
  "lightsensor" => {"CODE"=>"dpt9", "UNIT"=>"Lux"},
  "speedsensor" => {"CODE"=>"dpt9", "UNIT"=>"m/s"},
  "speedsensor-km/h" => {"CODE"=>"dpt9", "UNIT"=>"km/h"},
  "pressuresensor" => {"CODE"=>"dpt9", "UNIT"=>"Pa"},
  "rainsensor" => {"CODE"=>"dpt9", "UNIT"=>"l/m²"},
  "time1sensor" => {"CODE"=>"dpt9", "UNIT"=>"s"},
  "time2sensor" => {"CODE"=>"dpt9", "UNIT"=>"ms"},
  "humiditysensor" => {"CODE"=>"dpt9", "UNIT"=>"%"},
  "airqualitysensor" => {"CODE"=>"dpt9", "UNIT"=>"ppm"},
  "voltage-mV" => {"CODE"=>"dpt9", "UNIT"=>"mV"},
  "current-mA2" => {"CODE"=>"dpt9", "UNIT"=>"mA"},
  "power" => {"CODE"=>"dpt9", "UNIT"=>"kW"},
  "powerdensity" => {"CODE"=>"dpt9", "UNIT"=>"W/m²"},
  
  # Time of Day
  "dpt10"		=> {"CODE"=>"dpt10", "UNIT"=>""},
  "dpt10_no_seconds" => {"CODE"=>"dpt10_ns", "UNIT"=>""},
  "time"		=> {"CODE"=>"time", "UNIT"=>""},
  
  # Date
  "dpt11"		=> {"CODE"=>"dpt11", "UNIT"=>""},
  "date"		=> {"CODE"=>"date", "UNIT"=>""},
  
  # 4-Octet unsigned value (handled as dpt7)
  "dpt12" 		=> {"CODE"=>"dpt12", "UNIT"=>""},
  
  # 4-Octet Signed Value
  "dpt13" 		=> {"CODE"=>"dpt13", "UNIT"=>"",  "factor"=>1},
  "dpt13.010" 		=> {"CODE"=>"dpt13", "UNIT"=>"W/h",  "factor"=>1},
  "dpt13.013" 		=> {"CODE"=>"dpt13", "UNIT"=>"kW/h",  "factor"=>1},

  # 4-Octet single precision float
  "dpt14"         => {"CODE"=>"dpt14", "UNIT"=>""},

  # 14-Octet String
  "dpt16"         => {"CODE"=>"dpt16", "UNIT"=>""},
);

sub
EIB_Initialize($) {
	my ($hash) = @_;

	$hash->{Match}     = "^B.*";
	$hash->{GetFn}     = "EIB_Get";
	$hash->{SetFn}     = "EIB_Set";
	$hash->{StateFn}   = "EIB_SetState";
	$hash->{DefFn}     = "EIB_Define";
	$hash->{UndefFn}   = "EIB_Undef";
	$hash->{ParseFn}   = "EIB_Parse";
	$hash->{AttrFn}   = "EIB_Attr";
	$hash->{AttrList}  = 	"IODev do_not_notify:1,0 ignore:0,1 dummy:1,0 showtime:1,0 " .
							"EIBreadingX:1,0 " .
							"EIBreadingSender:1,0 " .
							"EIBanswerReading:1,0 " .
							"EIBreadingRegex " .
							"EIBwritingRegex " .
							"$readingFnAttributes " .
							"model:".join(",", keys %eib_dpttypes);
}

#############################
sub
EIB_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	my $u = "wrong syntax: define <name> EIB <group name> [<read group names>*]";

	return $u if(int(@a) < 3);
	return "Define $a[0]: wrong group name format: specify as 0-15/0-15/0-255 or as hex" if( ($a[2] !~ m/^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{1,3}$/i)  && (lc($a[2]) !~ m/^[0-9a-f]{4}$/i));

	my $groupname = eib_name2hex(lc($a[2]));

	$hash->{GROUP} = lc($groupname);

	my $code = "$groupname";
	my $ncode = 1;
	my $name = $a[0];

	$hash->{CODE}{$ncode++} = $code;
	
	# add read group names
	if(int(@a)>3) {
		for (my $count = 3; $count < int(@a); $count++) {
			$hash->{CODE}{$ncode++} = eib_name2hex(lc($a[$count]));;
		}
	}
	$modules{EIB}{defptr}{$code}{$name}   = $hash;
	AssignIoPort($hash);
}

#############################
sub
EIB_Undef($$) {
	my ($hash, $name) = @_;

	foreach my $c (keys %{ $hash->{CODE} } ) 
	{
		$c = $hash->{CODE}{$c};

		# As after a rename the $name may be different from the $defptr{$c}{$n}
		# we look for the hash.
		foreach my $dname (keys %{ $modules{EIB}{defptr}{$c} }) 
		{
			delete($modules{EIB}{defptr}{$c}{$dname}) if($modules{EIB}{defptr}{$c}{$dname} == $hash);
		}
	}
	
	return undef;
}

#####################################
sub
EIB_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  
  #debug
  print "Name: $name, Attribut: $aName, Wert: $aVal\n" if ($debug eq 1);
  
  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value
  if ($cmd eq "set") 
  {
  } 
  elsif ($cmd eq "del") 
  {
  } 
  return undef;
}

#####################################
sub
EIB_SetState($$$$) {
	my ($hash, $tim, $vt, $val) = @_;
	Log3 $hash, 5,"EIB setState for $hash->{NAME} tim: $tim vt: $vt  $val";

	$val = $1 if($val =~ m/^(.*) \d+$/);

	return undef if(!defined($eib_c2b{$val}));
}

###################################
sub
EIB_Get($@) {
	#my ($hash, @a) = @_;
	##return "No get for dummies" if(IsDummy($hash->{NAME}));
	#return "" if($a[1] && $a[1] eq "?");  # Temporary hack for FHEMWEB
	##send read-request to the bus
	#IOWrite($hash, "B", "r" . $hash->{GROUP});
	#return "Current value for $hash->{NAME} ($hash->{GROUP}) requested.";
	
	my ($hash, @a, $str) = @_;
	my $na = int(@a);
	my $value = $a[1];
	
	return "" if($a[1] && $a[1] eq "?");  # Temporary hack for FHEMWEB

  	my $groupnr = 1;
	
	# the command can be send to any of the defined groups indexed starting by 1
	# optional last argument starting with g indicates the group
	# execute only for non-strings. Otherwise a "g" is interpreted to execute this group-send-mechanism...
	if (defined($value) and ($value ne "string"))
	{
		$groupnr = $1 if($na=2 && $a[1]=~ m/g([0-9]*)/);
		#return, if unknown group
		return "groupnr $groupnr not known." if(!$hash->{CODE}{$groupnr}); 
	}
	my $groupcode = $hash->{CODE}{$groupnr};

  	#send read-request to the bus
	IOWrite($hash, "B", "r" . $groupcode);
  
	return "Current value for $hash->{NAME} ($groupcode) requested.";
}

###################################
sub
EIB_Set($@) {
	my ($hash, @a, $str) = @_;
	#my $ret = undef;
	my $ret = "";
	my $na = int(@a);

	#return, if no set value specified
	return "no set value specified" if($na < 2);# || $na > 4);
	#return, if this is a readonly-device
	return "Readonly value $a[1]" if(defined($readonly{$a[1]}));
	#return, if this is a dummy device
	return "No $a[1] for dummies" if(IsDummy($hash->{NAME}));

	my $name  = $a[0];
	my $value = $a[1];
	my $arg1  = undef;
	my $arg2  = undef;
  
	$arg1 = $a[2] if($na>2);
	$arg2 = $a[3] if($na>3);
	my $model = $attr{$name}{"model"};
	my $sliderdef = !defined($model)?undef:$eib_dpttypes{"$model"}{"slider"};

	my $c = $eib_c2b{$value};
	if(!defined($c)) 
	{
		my $resp = "Unknown argument $value, choose one of " . join(" ", sort keys %eib_c2b);
		$resp = $resp . ":slider,$sliderdef" if(defined $sliderdef);
		return $resp;
	}
  
  	my $groupnr = 1;
	my $extGroupNr = undef;
	
	# the command can be send to any of the defined groups indexed starting by 1
	# optional last argument starting with g indicates the group
	$extGroupNr = $1 if($na>2 && $a[$na-1]=~ m/g([0-9]*)/);
	
	if (defined ($extGroupNr))
	{
		$groupnr = $extGroupNr;
		print ("Found supplied group-no.: $extGroupNr\n") if ($debug eq 1);
	}

	return "groupnr $groupnr not known." if(!$hash->{CODE}{$groupnr}); 
		
	my $v = join(" ", @a);
	Log3 $name, 5, "EIB set $v";
	(undef, $v) = split(" ", $v, 2);	# Not interested in the name...

	if($value eq "raw" && defined($arg1)) 
	{ 
		# complex value command.
		# the additional argument is transfered alone.
		$c = $arg1;
	} 
	elsif ($value eq "value" && defined($arg1)) 
	{
		# value to be translated according to datapoint type
		$c = EIB_EncodeByDatapointType($hash,$name,$arg1,$groupnr); #MH add group in call
  	
		# set the value to the back translated value
		$v = EIB_ParseByDatapointType($hash,$name,$c,$groupnr); # MH probably stupid - but required!!!!
	}
	elsif ($value eq "string" && ($na>2)) 
	{
		my $str = "";
		
		#append all following args...
		my $argLen = $na;
		#...except the last argument is a group-no
		$argLen -= 1 if (defined $extGroupNr);
		
		#join string
		for (my $i=2;$i<$argLen;$i++)
		{
		  $str.= $a[$i]." ";		  
		}
		
		#trim whitespaces at the end
		$str =~ s/^\s+|\s+$//g;

		return "String too long, max. 14 chars allowed" if(length($str) > 14); 
		
		Log3 $name, 5, "set string $str";
		
		# value to be translated according to datapoint type
		$c = EIB_EncodeByDatapointType($hash,$name,$str,$groupnr);
  	
		# set the value to the back translated value
		$v = EIB_ParseByDatapointType($hash,$name,$c,$groupnr);
	}

	my $groupcode = $hash->{CODE}{$groupnr};
	$model = $attr{$name}{"model"}; ##MH 
	$model = "" unless defined($model); ##MH avoid uninit msg

	my $code = $eib_dpttypes{"$model"}{"CODE"};
  
	#send new value
	IOWrite($hash, "B", "w" . $groupcode . $c);
  
	###########################################
	# Delete any timer for on-for_timer
	if($modules{EIB}{ldata}{$name}) 
	{
		CommandDelete(undef, $name . "_timer");
		delete $modules{EIB}{ldata}{$name};
	}
   
	###########################################
	# Add a timer if any for-timer command has been chosen
	if($value =~ m/for-timer/ && defined($arg1)) 
	{
		my $dur = $arg1;
		my $to = sprintf("%02d:%02d:%02d", $dur/3600, ($dur%3600)/60, $dur%60);
		$modules{EIB}{ldata}{$name} = $to;
		Log3 $name, 4, "Follow: +$to set $name off g$groupnr"; 
		CommandDefine(undef, $name . "_timer at +$to set $name off g$groupnr");
	}

	###########################################
	# Delete any timer for on-till
	if($modules{EIB}{till}{$name}) 
	{
		CommandDelete(undef, $name . "_till");
		delete $modules{EIB}{till}{$name};
	}
  
	###########################################
	# Add a timer if on-till command has been chosen
	if($value =~ m/on-till/ && defined($arg1)) 
	{
		my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($arg1);
		if($err) 
		{
			Log3 $name, 2, "Error trying to parse timespec for $a[0] $a[1] $a[2] : $err";
		}
		else 
		{
			my @lt = localtime;
			my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
			my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
			if($hms_now ge $hms_till) 
			{
				Log3 $name, 4, "on-till: won't switch as now ($hms_now) is later than $hms_till";
			}
			else 
			{
				$modules{EIB}{till}{$name} = $hms_till;
				Log3 $name, 4, "Follow: $hms_till set $name off g$groupnr";
				CommandDefine(undef, $name . "_till at $hms_till set $name off g$groupnr");
			}
		}
	}
  
	##########################
	# Look for all devices with the same code, and set state, timestamp
	$code = "$hash->{GROUP}"; ##MH reuse variable
	my $tn = TimeNow();

	my $defptr = $modules{EIB}{defptr}{$code};
	foreach my $n (keys %{ $defptr })
	{
		my $regAttr = $attr{$n}{"EIBwritingRegex"};
		if ($regAttr)
		{
			#substitute contents of state, if desired
			#
			#get array of given attributes
			my @reg = split("[ ]", $regAttr);
			#format reading as input for regex
			my $tempVal = "setG$groupnr:$v";
								
			#loop over all regex
			for (my $i = 0; $i < int(@reg); $i++)
			{
				#get search / replaye parts
				my @regInner = split("\/", $reg[$i]);
				$tempVal =~ s/$regInner[0]/$regInner[1]/g;
									
				#log it
				Log (5, "modified set with regex s/$regInner[0]/$regInner[1]/g to value $tempVal");
				print ("modified set with regex s/$regInner[0]/$regInner[1]/g to value $tempVal\n") if ($debug eq 1);
			}
			
			#process result
			readingsSingleUpdate($defptr->{$n},"state",$tempVal,1);
		} else
		{
			#process regular reading
			readingsSingleUpdate($defptr->{$n},"state",$v,1);
		}

		#debug
		print "setg = $defptr->{$n}{NAME} , $groupnr , attr = AttrVal($defptr->{$n}{NAME},'EIBreadingX',0)n" if ($debug eq 1);
		#process extended reading - mark as set
		readingsSingleUpdate($defptr->{$n},"setG" . $groupnr,$v,1) if (AttrVal($defptr->{$n}{NAME},'EIBreadingX',0) == 1);    
	}
	
	return $ret;
}

###################################
sub
EIB_Parse($$) {
	my ($hash, $msg) = @_;
  
	# Msg format: 
	# B(w/r/p)<group><value> i.e. Bw00000101
	# we will also take reply telegrams into account, 
	# as they will be sent if the status is asked from bus 	
	#split message into parts
	$msg =~ m/^B(.{4})(.{1})(.{4})(.*)$/;
	my $src = $1;
	my $cmd = $2;
	my $dev = $3;
	my $val = $4;

	my $v = $codes{$val};
	$v = "$val" if(!defined($v));
	my $rawv = $v;

	my @list;
	my $found = 0;
	
	# check if the code is within the read groups
	# we will inform all definitions subsribed to this code	
	foreach my $mod (keys %{$modules{EIB}{defptr}})
	{
		my $def = $modules{EIB}{defptr}{"$mod"};
		if($def) 
		{
			foreach my $n (keys %{ $def }) 
			{
				my $lh = $def->{$n};
				foreach my $gnr (keys %{ $lh->{CODE} })
				{
					my $c = $lh->{CODE}{$gnr};
					if($c eq $dev)
					{
						$n = $lh->{NAME};        # It may be renamed
						next if(IsIgnored($n));   # Little strange.
			
						push(@list, $n);
						$found = 1;

						# handle write and reply messages		
						if($cmd =~ /[w|p]/)
						{
							# parse/translate by datapoint type
							$v = EIB_ParseByDatapointType($lh,$n,$rawv,$gnr); # MH added optional groupnr
							$lh->{RAWSTATE} = $rawv;
							$lh->{LASTGROUP} = $dev;							
							
							my $regAttr = $attr{$n}{"EIBreadingRegex"};
							if ($regAttr)
							{
								#substitute contents of state, if desired
								#
								#get array of given attributes
								my @reg = split("[ ]", $regAttr);
								#format reading as input for regex
								my $tempVal = "getG$gnr:$v";
								
								#loop over all regex
								for (my $i = 0; $i < int(@reg); $i++)
								{
									#get search / replaye parts
									my @regInner = split("\/", $reg[$i]);
									$tempVal =~ s/$regInner[0]/$regInner[1]/g;
									
									#log it
									Log (5, "modified set with regex s/$regInner[0]/$regInner[1]/g to value $tempVal");
									print ("modified set with regex s/$regInner[0]/$regInner[1]/g to value $tempVal\n") if ($debug eq 1);
								}
								
								#process result
								readingsSingleUpdate($lh,"state",$tempVal,1);
							}
							else
							{
								#process regular reading
								readingsSingleUpdate($lh,"state",$v,1);
							}
	
							#debug
							print "getg = $n , group= $gnr , EIBreadingX = AttrVal($def->{$n}{NAME},'EIBreadingX',0)\n"  if ($debug eq 1);
							#process extended reading - mark as "get"
							readingsSingleUpdate($lh,'getG' . $gnr,$v,1) if (AttrVal($def->{$n}{NAME},'EIBreadingX',0) == 1);

							#process output of sender
							if (AttrVal($def->{$n}{NAME},'EIBreadingSender',0) == 1)
							{
								my $srcName = eib_hex2name($src);
								#debug
								print "sender = $srcName, group= $gnr, EIBreadingSender = AttrVal($def->{$n}{NAME},'EIBreadingSender',0)\n"  if ($debug eq 1);
								readingsSingleUpdate($lh,'sender',$srcName,1);
							}
				    
							Log3 $n, 5, "EIB parse write message $n $v";
						}
						# handle read messages, if Attribute is set				  			  
						elsif (($cmd =~ /[r]/) && (AttrVal($def->{$n}{NAME},'EIBanswerReading',0) == 1))
						{
							#debug
							print "group= $c, EIBanswerReading = AttrVal($def->{$n}{NAME},'EIBanswerReading',0)\n"  if ($debug eq 1);
							#convert value from state
							my $tmp = EIB_EncodeByDatapointType($hash, $n, $lh->{STATE}, $gnr);
							#write answer
							TUL_Write($hash, "B", "p" . $c . $tmp);

							Log3 $n, 5, "EIB parse read message $n $v";			  
						}
					}
				}
			}
		}
	} 

	return @list if $found>0;
    		
	if($found==0)
	{
		my $dev_name = eib_hex2name($dev);
		Log3 $dev, 3, "EIB Unknown device $dev ($dev_name), Value $val, please define it";
		return "UNDEFINED EIB_$dev EIB $dev_name";
	}	
}

###################################
sub
EIB_EncodeByDatapointType($$$$) {
	my ($hash, $name, $value, $gnr) = @_;
	my @model_array = split(" ",$attr{$name}{"model"}) if (defined($attr{$name}{"model"}));
	my $model = $model_array[0];
	my $transval = undef;

	#no model defined
	if (!defined($model)) 
	{
		$model = "dpt1";
		Log3 $hash, 3,"EIB encode: no model defined for $name. Replaced with DPT1.";
	}
	
	#no gnr defined
	if (defined($gnr)) 
	{
		$model = $model_array[$gnr-1] if (defined($model_array[$gnr-1]));
	}
	else
	{
		Log3 $hash, 2,"EIB encode no gnr defined";
		return undef;
	}
	
	my $code = $eib_dpttypes{"$model"}{"CODE"};
	
	#invalid model defined
	if (!defined($code)) 
	{
		Log3 $hash, 1,"EIB encode: invalid model defined for $name. Breaking up...";
		return undef;	
	}
	
	if (!defined($value)) 
	{
		Log3 $hash, 2,"EIB encode no value defined";
		return undef;
	}
	
	Log3 $hash, 5,"EIB_EncodeByDatapointType: $name, Value= $value, model= $model";
	
	my $dpt = $eib_dpttypes{"$model"};
	my $unit = $eib_dpttypes{"$model"}{"UNIT"};
	my $adjustment = $eib_dpttypes{"$model"}{"ADJUSTMENT"};
	
	if (defined ($adjustment) && defined ($unit))
	{
		Log3 $hash, 4,"EIB encode $value for $name model: $model dpt: $code unit: $unit";
	}
	
	#start with model-selection. Go through DPT's
	if ($code eq "dpt1") 
	{
		my $fullval = "";
		
		#replace on/off
		$fullval = "00" if ($value eq "off"); 
		$fullval = "01" if ($value eq "on"); 
		
		#return value, if encode was successful
		if ($fullval ne "")
		{
			$transval = $fullval;
		}
		#if not return hex-data
		else
		{
			$transval = sprintf("%x", $value);
		}
				
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";
	}
	elsif ($code eq "dpt3") 
	{
		#4-bit steps
		my $rawval = $value;
		my $sign = undef;
		my $fullval = undef;
		
		#determine dim-direction, assuming positive direction by default
		if ($value =~ /^-/)
		{
			$value = -$value;
			$sign = 0;
		}
		else
		{
			$sign = 1;
		}
		
		#determine value
		if ($value >= 75)
		{
			#adjust 100%
			$fullval = 01;
		}
		elsif ($value >= 50)
		{
			#adjust 50%
			$fullval = 02;
		}
		elsif ($value >= 25)
		{
			#adjust 25%
			$fullval = 03;
		}
		elsif ($value >= 12)
		{
			#adjust 12%
			$fullval = 04;
		}
		elsif ($value >= 6)
		{
			#adjust 6%
			$fullval = 05;
		}
		elsif ($value >= 3)
		{
			#adjust 3%
			$fullval = 06;
		}
		elsif ($value >= 1)
		{
			#adjust 1%
			$fullval = 07;
		}
		elsif ($value >= 0)
		{
			#adjust 0%
			$fullval = 00;
		}
		else 
		{
			#do nothing
			$fullval = undef;
		}

		#place signe
		if (defined ($fullval) && ($sign eq 1))
		{
			$fullval = $fullval | 8;
		}

		#make it hex
		$transval = sprintf("0%.1x",$fullval);
		
		Log3 $hash, 5,"EIB $code encode $rawval = sign $sign value $value to $fullval. Translated to hex $transval.";
	}
	elsif ($code eq "dpt5") 
	{
		#1-byte unsigned
		my $dpt5factor = $eib_dpttypes{"$model"}{"factor"};
		my $fullval = sprintf("00%.2x",($value/$dpt5factor));
	  
		$transval = $fullval;
		Log3 $hash, 5,"EIB $code encode $value = $fullval factor = $dpt5factor translated: $transval";
	}
	elsif ($code eq "dpt6") 
	{
	  #1-byte signed
	  my $dpt6factor = $eib_dpttypes{"$model"}{"factor"};
	  my $fullval = int($value/$dpt6factor);
      $fullval += 256 if ($fullval < 0);
      $fullval = 0 if ($fullval < 0);
      $fullval = 0xFF if ($fullval > 0xFF);
	  $transval = sprintf("00%.2x",$fullval);

	  Log3 $hash, 5,"EIB $code encode $value = $fullval factor = $dpt6factor translated: $transval";
	}
	elsif ($code eq "dpt7") 
	{
		#2-byte unsigned
		my $fullval = "";
		
		if($adjustment eq "255") 
		{
			$fullval = sprintf("00%.4x",($value/2.55));			
		} 
		else 
		{
			$fullval = sprintf("00%.4x",$value);
		}
		
		$transval = $fullval;		
		Log3 $hash, 5,"EIB $code encode $value = $fullval translated: $transval";
	} 
	elsif($code eq "dpt9") 
	{
		#2-byte float
		my $fullval;

		my $sign = ($value <0 ? 0x8000 : 0);
		my $exp  = 0;
		my $mant = 0;

		$mant = int($value * 100.0);
		while (abs($mant) > 2047) {
			$mant /= 2;
			$exp++;
		}
		$fullval = $sign | ($exp << 11) | ($mant & 0x07ff);
	
		$transval = sprintf("00%.4x",$fullval);
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";
	} 
	elsif ($code eq "dpt10") 
	{
		# Time
		my $fullval = 0;
		my ($hh, $mm, $ss) = split /:/, $value;
		
		$fullval = $ss + ($mm<<8) + (($hh)<<16);
	
		$transval = sprintf("00%.6x",$fullval);
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";
	} 
	elsif ($code eq "dpt10_ns") 
	{
		# Time, seconds = zero
		my $fullval = 0;
		my ($hh, $mm, $ss) = split /:/, $value;
		$ss = 0;
		
		$fullval = $ss + ($mm<<8) + (($hh)<<16);
	
		$transval = sprintf("00%.6x",$fullval);
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";
	} 
	elsif ($code eq "time")
	{
		# current Time
		my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		$year+=1900;
		$mon++;

		my $fullval = 0;
		
		# calculate offset for weekday
		$wday = 7 if ($wday eq "0");
		my $hoffset = 32*$wday;
		
		$fullval = $secs + ($mins<<8) + (($hoffset + $hours)<<16);
		
		$value =  sprintf("%02d:%02d:%02d",$hours,$mins,$secs); # value for log
			
		$transval = sprintf("00%.6x",$fullval);
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";
	}
	elsif ($code eq "dpt11")
	{
		# Date
		my $fullval = 0;
		my ($dd, $mm, $yyyy) = split /\./, $value;
		
		$fullval = ($yyyy - 2000) + ($mm<<8) + ($dd<<16);
	
		$transval = sprintf("00%.6x",$fullval);
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";
	}
	elsif ($code eq "date") 
	{
		# current Date
		my ($secs,$mins,$hours,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);
		$year+=1900;
		$month++;
		
		my $fullval = 0;
		
		#encode current date
		$fullval = ($year-2000) + ($month<<8) + ($day<<16);
		$transval = sprintf("00%.6x",$fullval);
		Log3 $hash, 5,"EIB $code encode $value = $fullval day: $day month: $month year: $year translated: $transval";
	} 
	elsif ($code eq "dpt12") 
	{
		#4-byte unsigned
		my $fullval = sprintf("00%.8x",$value);
		$transval = $fullval;
		Log3 $hash, 5,"EIB $code encode $value" . '=' . " $fullval translated: $transval";
	}
	elsif ($code eq "dpt13") 
	{
	  #4-byte signed
	  my $dpt13factor = $eib_dpttypes{"$model"}{"factor"};
	  my $fullval = int($value/$dpt13factor);
      $fullval += 4294967296 if ($fullval < 0);
      $fullval = 0 if ($fullval < 0);
      $fullval = 0xFFFFFFFF if ($fullval > 0xFFFFFFFF);
	  $transval = sprintf("00%.8x",$fullval);

	  Log3 $hash, 5,"EIB $code encode $value = $fullval factor = $dpt13factor translated: $transval";
	} 
	elsif($code eq "dpt14") 
	{
		#4-byte float
		my $fullval;
		$fullval = unpack("L",  pack("f", $value));
		
		$transval = sprintf("00%.8x", $fullval); 
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";		
	}
	elsif ($code eq "dpt16") 
	{
		#text
		my $dat = $value;

		#convert to hex-string
		$dat =~ s/(.)/sprintf("%x",ord($1))/eg;
		#format for 14-byte-length
		$dat = sprintf("%-028s",$dat);
		#append leading zeros
		$dat = "00" . $dat;
		
		$transval = $dat;
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";	
	} 
	elsif ($code eq "dptxx") 
	{
	}
	
	# set state to translated value
	if(defined($transval))
	{
		Log3 $hash, 4,"EIB $name translated $value to $transval";
		$value = "$transval";
	}

	return $value;
}

sub
EIB_ParseByDatapointType($$$$)
{
	my ($hash, $name, $value, $gnr) = @_; #MH
	my @model_array = split(" ",$attr{$name}{"model"}) if (defined($attr{$name}{"model"}));
	my $model = $model_array[0];
	
	# nothing to do if no model is given
	#return $value if(!defined($model));
	
	if (defined($gnr)) 
	{
		$model = $model_array[$gnr-1] if defined ($model_array[$gnr-1]);
	}
	
	#debug
	print "EIB_ParseByDatapointType: $name, val= $value, Group= $gnr, Model= $model \n" if ($debug eq 1);
	
	#no model defined
	if (!defined($model)) 
	{
		$model = "dpt1";
		Log3 $hash, 3,"EIB encode: no model defined for $name. Replaced with DPT1.";
	}

	my $code = $eib_dpttypes{"$model"}{"CODE"};
	
	#invalid model defined
	if (!defined($code)) 
	{
		Log3 $hash, 1,"EIB encode: invalid model defined for $name. Breaking up....";	
		return undef;
	}
	
	my $dpt = $eib_dpttypes{"$model"};
	my $unit = $eib_dpttypes{"$model"}{"UNIT"};
	my $transval = undef;
	
	Log3 $hash, 5,"EIB parse $value for $name model: $model dpt: $code unit: $unit";
	#debug
	print "EIB_ParseByDatapointType: $name, val= $value, Group= $gnr, Model= $model, code= $code, unit= $unit \n"  if ($debug eq 1);
	
	#moved to the front... - execute if DPT is NOT 1
	if ($code ne "dpt1")
	{
	    $value = 0 if ($value eq "off"); 
		$value = 1 if ($value eq "on"); 
	}
	
	#correct value in realtion to potential non-compatible states
	if ($code eq "dpt1") 
	{
		#1-bit
		$value = "off" if ($value eq 0); 
		$value = "on" if ($value eq 1); 
		$transval = $value;	
	}
	elsif ($code eq "dpt3") 
	{
		#4-bit steps
		my $rawval = $value;
		my $sign = undef;
		my $fullval = undef;
		
		#make it decimal
		$value = hex ($value);
		
		#determine dim-direction
		if ($value & 8)
		{
			$sign = "+";
		}
		else
		{
			$sign = "-";
		}
		
		#mask it...
		$value = $value & 7; 
		
		#determine value
		if ($value == 7)
		{
			#adjust 1%
			$fullval = 1;
		}
		elsif ($value == 6)
		{
			#adjust 3%
			$fullval = 3;
		}
		elsif ($value == 5)
		{
			#adjust 6%
			$fullval = 6;
		}
		elsif ($value == 4)
		{
			#adjust 12%
			$fullval = 12;
		}
		elsif ($value == 3)
		{
			#adjust 25%
			$fullval = 25;
		}
		elsif ($value == 2)
		{
			#adjust 50%
			$fullval = 50;
		}
		elsif ($value == 1)
		{
			#adjust 100%
			$fullval = 100;
		}
		elsif ($value == 0)
		{
			#adjust 0%
			$fullval = 0;
		}
		else 
		{
			#do nothing
			$fullval = undef;
		}
		
		if (defined ($sign) && defined ($fullval))
		{
			$transval = "$sign$fullval";
		}
		
		Log3 $hash, 5,"EIB $code decode $rawval = sign $sign value $value to $fullval";
	}
	elsif ($code eq "dpt5") 
	{
		#1-byte unsigned
		my $dpt5factor = $eib_dpttypes{"$model"}{"factor"};
		my $fullval = hex($value);
		$transval = $fullval;
		$transval = sprintf("%.0f",$transval * $dpt5factor) if($dpt5factor != 0);		
	}
	elsif ($code eq "dpt6") 
	{
		my $dpt6factor = $eib_dpttypes{"$model"}{"factor"};
		my $fullval = hex($value);
		$transval = $fullval;
		$transval -= 256 if $transval >= 0x80;
		$transval = sprintf("%.0f",$transval * $dpt6factor) if($dpt6factor != 0);
	}
	elsif ($code eq "dpt7") 
	{
		#2-byte unsigned
		my $fullval = hex($value);
		$transval = $fullval;		
	} 
	elsif($code eq "dpt9") 
	{
		#2-bate float
		my $fullval = hex($value);
		my $sign = 1;
		$sign = -1 if(($fullval & 0x8000)>0);
		my $exp = ($fullval & 0x7800)>>11;
		my $mant = ($fullval & 0x07FF);
		$mant = -(~($mant-1)&0x07FF) if($sign==-1);
		$transval = (1<<$exp)*0.01*$mant;
	} 
	elsif ($code eq "dpt10") 
	{
		# Time
		my $fullval = hex($value);
		my $hours = ($fullval & 0x1F0000)>>16;
		my $mins  = ($fullval & 0x3F00)>>8;
		my $secs  = ($fullval & 0x3F);
		$transval = sprintf("%02d:%02d:%02d",$hours,$mins,$secs);
	} 
	elsif ($code eq "dpt10_ns") 
	{
		# Time without seconds
		my $fullval = hex($value);
		my $hours = ($fullval & 0x1F0000)>>16;
		my $mins  = ($fullval & 0x3F00)>>8;
		my $secs  = ($fullval & 0x3F);
		$transval = sprintf("%02d:%02d",$hours,$mins);
	} 
	elsif ($code eq "time") 
	{
		# Time
		my $fullval = hex($value);
		my $hours = ($fullval & 0x1F0000)>>16;
		my $mins  = ($fullval & 0x3F00)>>8;
		my $secs  = ($fullval & 0x3F);
		$transval = sprintf("%02d:%02d:%02d",$hours,$mins,$secs);
	} 
	elsif ($code eq "dpt11") 
	{
		# Date
		my $fullval = hex($value);
		my $day = ($fullval & 0x1F0000)>>16;
		my $month  = ($fullval & 0x0F00)>>8;
		my $year  = ($fullval & 0x7F);
		#translate year (21st cent if <90 / else 20th century)
		$year += 1900 if($year>=90);
		$year += 2000 if($year<90);
		$transval = sprintf("%02d.%02d.%04d",$day,$month,$year);
	} 
	elsif ($code eq "date") 
	{
		# Date
		my $fullval = hex($value);
		my $day = ($fullval & 0x1F0000)>>16;
		my $month  = ($fullval & 0x0F00)>>8;
		my $year  = ($fullval & 0x7F);
		#translate year (21st cent if <90 / else 20th century)
		$year += 1900 if($year>=90);
		$year += 2000 if($year<90);
		$transval = sprintf("%02d.%02d.%04d",$day,$month,$year);
	} 
	elsif ($code eq "dpt12") 
	{
		#4-bate unsigned
		my $fullval = hex($value);
		$transval = $fullval;		
	} 
	elsif ($code eq "dpt13") 
	{
		my $dpt13factor = $eib_dpttypes{"$model"}{"factor"};
		my $fullval = hex($value);
		$transval = $fullval;
		$transval -= 4294967296 if $transval >= 0x80000000;
		$transval = sprintf("%.0f",$transval * $dpt13factor) if($dpt13factor != 0);
	}	
	elsif ($code eq "dpt14")
    {
        # 4-byte float
		my $fullval;
		$fullval = unpack "f", pack "L", hex $value;		
		$transval = sprintf ("%f","$fullval");
	} 
	elsif ($code eq "dpt16") 
	{
		#text
		$transval = "";
		for (my $i=0;$i<14;$i++) 
		{
			my $c = hex(substr($value,$i*2,2));
		
			if ($c eq 0) 
			{
				$i = 14;
			} 
			else 
			{
				$transval .=  sprintf("%c", $c);
			}
		}
	} 
	elsif ($code eq "dptxx") 
	{	
	}
	
	# set state to translated value
	if(defined($transval))
	{
		Log3 $hash, 4, "EIB_ParseByDatapointType: $name, origval= $value, transval= $transval, Group= $gnr, Model= $model, code= $code, unit= $unit";
		print "EIB_ParseByDatapointType: $name, origval= $value, transval= $transval, Group= $gnr, Model= $model, code= $code, unit= $unit \n" if ($debug eq 1);
		$value = "$transval $unit";
		$value =~ s/^\s+|\s+$//g;
	}
	else
	{
		Log3 $hash, 4, "EIB_ParseByDatapointType: $name, origval= $value could not be translated, Group= $gnr, Model= $model, code= $code, unit= $unit"; #MH
	}
	
	return $value;
}

#############################
sub
eib_hex2name($)
{
  my $v = shift;
  
  my $p1 = hex(substr($v,0,1));
  my $p2 = hex(substr($v,1,1));
  my $p3 = hex(substr($v,2,2));
  
  my $r = sprintf("%d/%d/%d", $p1,$p2,$p3);
  return $r;
}

#############################
sub
eib_name2hex($)
{
  my $v = shift;
  my $r = $v;
#  Log(5, "name2hex: $v");
  if($v =~ /^([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{1,3})$/) {
  	$r = sprintf("%01x%01x%02x",$1,$2,$3);
  }
  elsif($v =~ /^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,3})$/) {
  	$r = sprintf("%01x%01x%02x",$1,$2,$3);
  }  
    
  return $r;
}

1;

=pod
=item summary    Communicates to EIB via TUL (deprecated, use KNX)
=item summary_DE Kommuniziert mit EIB über TUL (veraltet, nutze KNX)
=begin html

<a name="EIB"></a>
<h3>EIB / KNX</h3>
<div>
<p>EIB/KNX is a standard for building automation / home automation.
  It is mainly based on a twisted pair wiring, but also other mediums (ip, wireless) are specified.</p>

<p>While the module <a href="#TUL">TUL</a> represents the connection to the EIB network,
  the EIB modules represent individual EIB devices. This module provides a basic set of operations (on, off, on-till, etc.)
  to switch on/off EIB devices. Sophisticated setups can be achieved by combining a number of
  EIB module instances or by sending raw hex values to the network (set &lt;devname&gt; raw &lt;hexval&gt;).</p>

<p>EIB/KNX defines a series of Datapoint Type as standard data types used
  to allow general interpretation of values of devices manufactured by different companies.
  These datatypes are used to interpret the status of a device, so the state in FHEM will then
  show the correct value.</p>

  <p><a name="EIBdefine"></a> <b>Define</b></p>
  <div>
    <code>define &lt;name&gt; EIB &lt;main group&gt; [&lt;additional group&gt; ..]</code>
    
    <p>Define an EIB device, connected via a <a href="#TUL">TUL</a>. The
    &lt;group&gt; parameters are either a group name notation (0-15/0-15/0-255) or the hex representation of the value (0-f0-f0-ff).
    The &lt;main group&gt;  is used for sending of commands to the EIB network.</p>
    <p>The state of the instance will be updated when a new state is received from the network for any of the given groups.
    This is useful for example for toggle switches where a on command is send to one group and the real state (on or off) is
    responded back on a second group.</p>

    <p>For actors and sensors the <a href="#autocreate">autocreate</a> module may help.</p>
    <p>Example:</p>
      <pre>
      define lamp1 EIB 0/10/12
      define lamp1 EIB 0/10/12 0/0/5
      define lamp1 EIB 0A0C
      </pre>
  </div>
  
  <p><a name="EIBset"></a> <b>Set</b></p>
  <div>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt; g&lt;groupnr&gt;]</code>
    <p>where value one of:</p>
	  <li><b>on</b> switch on device</li>
	  <li><b>off</b> switch off device</li>
	  <li><b>on-for-timer</b> &lt;secs&gt; switch on the device for the given time. After the specified seconds a switch off command is sent.</li>
	  <li><b>on-till</b> &lt;time spec&gt; switches the device on. The device will be switched off at the given time.</li>
      <li><b>raw</b> &lt;hexvalue&gt; sends the given value as raw data to the device.</li>
      <li><b>value</b> &lt;decimal value&gt; transforms the value according to the chosen model and send the result to the device.</li>
    <p>Example:</p>
    <pre>
      set lamp1 on
      set lamp1 off
      set lamp1 on-for-timer 10
      set lamp1 on-till 13:15:00
      set lamp1 raw 234578
      set lamp1 value 23.44
    </pre>

	<p>When as last argument a g&lt;groupnr&gt; is present, the command will be sent
	to the EIB group indexed by the groupnr (starting by 1, in the order as given in Define).</p>
	<pre>
      define lamp1 EIB 0/10/01 0/10/02
      set lamp1 on g2 (will send "on" to 0/10/02)
	</pre>

	<p>A dimmer can be used with a slider as shown in following example:</p>
	<pre>
      define dim1 EIB 0/0/5
      attr dim1 model percent
      attr dim1 webCmd value
	</pre>
	
	<p>The current date and time can be sent to the bus by the following settings:</p>
	<pre>
      define timedev EIB 0/0/7
      attr timedev model time
      attr timedev eventMap /value now:now/
      attr timedev webCmd now
      
      define datedev EIB 0/0/8
      attr datedev model date
      attr datedev eventMap /value now:now/
      attr datedev webCmd now
      
      # send every midnight the new date
      define dateset at *00:00:00 set datedev value now
      
      # send every hour the current time
      define timeset at +*01:00:00 set timedev value now
	</pre>	
  </div>
 
  <p><a name="EIBget"></a> <b>Get</b></p>
  <div>
  <p>If you execute get for a EIB/KNX-Element there will be requested a state from the device. The device has to be able to respond to a read - this is not given for all devices.<br>
	The answer from the bus-device is not shown in the toolbox, but is treated like a regular telegram.</p>
  </div>
  
  <p><a name="EIBattr"></a> <b>Attributes</b></p>
  <div>
    <a href="#IODev">IODev</a><br>
    <a href="#alias">alias</a><br>
    <a href="#comment">comment</a><br>
    <a href="#devStateIcon">devStateIcon</a><br>
    <a href="#devStateStyle">devStateStyle</a><br>
    <a href="#do_not_notify">do_not_notify</a><br>
    <a href="#dummy">dummy</a><br>
    <a href="#readingFnAttributes">readingFnAttributes</a><br>
    <a href="#event-aggregator">event-aggregator</a><br>
    <a href="#event-min-interval">event-min-interval</a><br>
    <a href="#event-on-change-reading">event-on-change-reading</a><br>
    <a href="#event-on-update-reading">event-on-update-reading</a><br>
    <a href="#eventMap">eventMap</a><br>
    <a href="#group">group</a><br>
    <a href="#icon">icon</a><br>
    <a href="#ignore">ignore</a><br>
    <a href="#room">room</a><br>
    <a href="#showtime">showtime</a><br>
    <a href="#sortby">sortby</a><br>
    <a href="#stateFormat">stateFormat</a><br>
    <a href="#userReadings">userReadings</a><br>
    <a href="#userattr">userattr</a><br>
    <a href="#verbose">verbose</a><br>
    <a href="#webCmd">webCmd</a><br>
    <a href="#widgetOverride">widgetOverride</a><br>
	<br>
	
	<p><a name="EIBreadingX"></a> <b>EIBreadingX</b></p>
	<div>
    Enable additional readings for this EIB-device. With this Attribute set, a reading setG&lt;x&gt; will be updated when a set command is issued from FHEM, a reading getG&lt;x&gt; will be updated as soon a Value is received from EIB-Bus (&lt;x&gt; stands for the groupnr. - see define statement). The logic for the state reading remains unchanged. This is especially useful when the define statement contains more than one group parameter. 
    <p>If set to 1, the following additional readings will be available:</p>
      <pre>
      setGx will be updated on a SET command issued by FHEM. &lt;x&gt; stands for the groupnr. - see define statement
      getGx will be updated on reception of a message from EIB-bus.
      </pre>
      <p>Example:</p>
      <pre>
      define myDimmer EIB 0/1/1 0/1/2
      attr myDimmer EIBreadingX 1
      attr myDimmer model dpt1 dpt5 # GA 0/1/1 will be interpreted as on/off, GA 0/1/2 will be handled as dpt5
      attr myDimmer stateFormat getG2 % # copies actual dim-level (as received from dimmer) into STATE 
      </pre>    
	 <p>If the EIBreadingX is set, you can specify multiple blank separated models to cope with multiple groups in the define statement. The setting cannot be done thru the pulldown-menu, you have to specify them with <code>attr &lt;device&gt; model &lt;dpt1&gt; &lt;dpt2&gt; &lt;dpt3&gt;</code></p> 
	</div>
	
	<p><a name="EIBreadingSender"></a> <b>EIBreadingSender</b></p>
	<div>
    Enable an additional reading for this EIB-device. With this Attribute set, a reading sender will be updated any time a new telegram arrives.
    <p>If set to 1, the following additional reading will be available: <pre>sender</pre></p>
      <pre>
      sender will be updated any time a new telegram arrives at this group-adress
      </pre>
      <p>Example:</p>
      <pre>
      define myDimmer EIB 0/1/1
      attr myDimmer EIBreadingSender 1
      </pre>    
	</div>

	<p><a name="EIBanswerReading"></a> <b>EIBanswerReading</b></p>
	<div>
    If enabled, FHEM answers on read requests. The content of state is send to the bus as answer.
    <p>If set to 1, read-requests are answered</p>
      <p>Example:</p>
      <pre>
      define myValue EIB 0/1/1
      attr myValue EIBanswerReading 1
      </pre>    
	</div>

	<p><a name="EIBreadingRegex"></a> <b>EIBreadingRegex</b></p>
	<div>
    You can pass n pairs of regex-pattern and string to replace, seperated by a slash. Internally the "new" state is always in the format getG[n]:[state]. The substitution is done every time, a new object is received. You can use this function for converting, adding units, having more fun with icons, ... 
	This function has only an impact on the content of state - no other functions are disturbed.
      <p>Example:</p>
      <pre>
      define myLamp EIB 0/1/1 0/1/2 0/1/2
      attr myLamp EIBreadingRegex getG[1]:/steuern: getG[2]:/status: getG[3]:/sperre:
	  attr myLamp EIBreadingRegex devStateIcon status.on:general_an status.off:general_aus sperre.on:lock
      </pre>    
    </div>	 

	<p><a name="EIBwritingRegex"></a> <b>EIBwritingRegex</b></p>
    You can pass n pairs of regex-pattern and string to replace, seperated by a slash. Internally the "new" state is always in the format setG1:[state]. The substitution is done every time, after an object is send. You can use this function for converting, adding units, having more fun with icons, ... 
	This function has only an impact on the content of state - no other functions are disturbed.
      <p>Example:</p>
      <pre>
      define myLockObject EIB 0/1/1
      attr myLamp EIBwritingRegex setG1:on/LOCKED setG1:/UNLOCKED
      </pre>    
    </div>	 

	<p><a name="model"></a> <b>model</b></p>
	<div>
	<p>This attribute is mandatory!</p>
	Set the model according to the datapoint types defined by the (<a href="http://www.sti.uniurb.it/romanell/110504-Lez10a-KNX-Datapoint%20Types%20v1.5.00%20AS.pdf" target="_blank">EIB / KNX specifications</a>). The device state in FHEM is interpreted and shown according to the specification.<br>
        <br>
		<U>dpt1</U> - 1 bit<br>
		Will be interpreted as on/off, 1=on 0=off and vice versa<br>
		<br>
		<U>dpt3</U> - Discrete Dim-Message<br>
		Usage: set value to +/-0..100. -54 means dim down by 50%<br>
      	<br>
		<U>dpt5</U> - 1 byte unsigned<br>
      	dpt5.003 - angle in degrees<br>
      	angle - same as dpt5.003<br>
      	dpt5.004 - percent<br>
      	percent - same as above<br>
      	percent255 - scaled percentage: 255=100%<br>
		<br>
      	<U>dpt6</U> - 1 byte signed <br>
		dpt6.001 - percent<br>
      	dpt6.010<br>		
		<br>
      	<U>dpt7</U> - 2 byte unsigned<br>
      	length - mm<br>
      	current - mA<br>
      	brightness<br>
      	timeperiod - ms<br>
      	timeperiod - min<br>
      	timeperiod - h<br>
		<br>
      	<U>dpt9</U> - 2 byte float<br>
      	tempsensor<br>
      	lightsensor<br>
      	speedsensor<br>
      	speedsensor-km/h<br>
      	pressuresensor<br>
      	rainsensor<br>
      	time1sensor<br>
      	time2sensor<br>
      	humiditysensor<br>
      	airqualitysensor<br>
      	voltage-mV<br>
      	current-mA2<br>
      	current-mA2<br>
      	power<br>
      	powerdensity<br>
		<br>
      	<U>dpt10</U> - time hh:mm:ss<br>
		dpt10_ns - same as DPT10, seconds always 0<br>
      	time - receiving has no effect, sending any value contains actual system time. For examle use set timedev value now<br>
		<br>
      	<U>dpt11</U> - date dd.mm.yyyy<br>
      	date - receiving has no effect, sending any value contains actual system date. For examle use set timedev value now<br>
		<br>
      	<U>dpt12</U> - 4 byte unsigned<br>
		<br>
		<U>dpt13</U> - 4 byte signed<br>
      	<br>
		<U>dpt14</U> - 4 byte float<br>
      	<br>
		<U>dpt16</U>  - text, use with "string": set textdev string Hallo Welt<br>
	</div>
</div>


=end html
=cut
