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
	"value" => "" #value must be last.. because of slider functionality in Set
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

  # 1-Octet unsigned value
  "dpt5" 		=> {"CODE"=>"dpt5", "UNIT"=>"",  "factor"=>1},
  "percent" 	=> {"CODE"=>"dpt5", "UNIT"=>"%", "factor"=>100/255, "slider"=>"0,1,100"},
  "dpt5.003" 	=> {"CODE"=>"dpt5", "UNIT"=>"&deg;", "factor"=>360/255},
  "angle" 		=> {"CODE"=>"dpt5", "UNIT"=>"&deg;", "factor"=>360/255}, # alias for dpt5.003
  "dpt5.004" 	=> {"CODE"=>"dpt5", "UNIT"=>"%", "factor"=>1},
  "percent255" 	=> {"CODE"=>"dpt5", "UNIT"=>"%", "factor"=>1 , "slider"=>"0,1,255"}, #alias for dpt5.004
  "dpt5.Slider"	=> {"CODE"=>"dpt5", "UNIT"=>"",  "factor"=>100/255, "slider"=>"0,1,100"}, ##MH same as percent w.o. unit

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
  "time"		=> {"CODE"=>"dpt10", "UNIT"=>""},
  
  # Date
  "dpt11"		=> {"CODE"=>"dpt11", "UNIT"=>""},
  "date"		=> {"CODE"=>"dpt11", "UNIT"=>""},
  
  # 4-Octet unsigned value (handled as dpt7)
  "dpt12" 		=> {"CODE"=>"dpt12", "UNIT"=>""},
  
  # 4-Octet single precision float
  "dpt14"         => {"CODE"=>"dpt14", "UNIT"=>""},

  # 14-Octet String
  "dpt16"         => {"CODE"=>"dpt16", "UNIT"=>""},
);


sub
EIB_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^B.*";
  $hash->{GetFn}     = "EIB_Get";
  $hash->{SetFn}     = "EIB_Set";
  $hash->{StateFn}   = "EIB_SetState";
  $hash->{DefFn}     = "EIB_Define";
  $hash->{UndefFn}   = "EIB_Undef";
  $hash->{ParseFn}   = "EIB_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:1,0 showtime:1,0 " .
						"EIBreadingX:1,0 " .
						"$readingFnAttributes " .
						"model:".join(",", keys %eib_dpttypes);
}


#############################
sub
EIB_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> EIB <group name> [<read group names>*]";

  return $u if(int(@a) < 3);
  return "Define $a[0]: wrong group name format: specify as 0-15/0-15/0-255 or as hex"
  		if( ($a[2] !~ m/^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{1,3}$/i)  && (lc($a[2]) !~ m/^[0-9a-f]{4}$/i));

  my $groupname = eib_name2hex(lc($a[2]));

  $hash->{GROUP} = lc($groupname);

  my $code = "$groupname";
  my $ncode = 1;
  my $name = $a[0];

  $hash->{CODE}{$ncode++} = $code;
  # add read group names
  if(int(@a)>3) 
  {
  	for (my $count = 3; $count < int(@a); $count++) 
  	{
 	   $hash->{CODE}{$ncode++} = eib_name2hex(lc($a[$count]));;
 	}
  }
  $modules{EIB}{defptr}{$code}{$name}   = $hash;
  AssignIoPort($hash);
}

#############################
sub
EIB_Undef($$)
{
  my ($hash, $name) = @_;

  foreach my $c (keys %{ $hash->{CODE} } ) {
    $c = $hash->{CODE}{$c};

    # As after a rename the $name may be different from the $defptr{$c}{$n}
    # we look for the hash.
    foreach my $dname (keys %{ $modules{EIB}{defptr}{$c} }) {
      delete($modules{EIB}{defptr}{$c}{$dname})
        if($modules{EIB}{defptr}{$c}{$dname} == $hash);
    }
  }
  return undef;
}

#####################################
sub
EIB_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  Log3 $hash, 5,"EIB setState for $hash->{NAME} tim: $tim vt: $vt val: $val";

  $val = $1 if($val =~ m/^(.*) \d+$/);
  #return "Undefined value from EIBsetstate $val" if(!defined($eib_c2b{$val}));
  #return undef;
  return undef if(!defined($eib_c2b{$val}));
}

###################################
sub
EIB_Get($@)
{
  my ($hash, @a) = @_;

  return "" if($a[1] && $a[1] eq "?");  # Temporary hack for FHEMWEB

  IOWrite($hash, "B", "r" . $hash->{GROUP});
  return "Current value for $hash->{NAME} ($hash->{GROUP}) requested.";	  
}

###################################
sub
EIB_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);

  return "no set value specified" if($na < 2 || $na > 4);
  return "Readonly value $a[1]" if(defined($readonly{$a[1]}));
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
  if(!defined($c)) {
  	my $resp = "Unknown argument $value, choose one of " . join(" ", sort keys %eib_c2b);
  	$resp = $resp . ":slider,$sliderdef" if(defined $sliderdef);
  	return $resp;
  }
  
  # the command can be send to any of the defined groups indexed starting by 1
  # optional last argument starting with g indicates the group
  my $groupnr = 1;
  $groupnr = $1 if($na>2 && $a[$na-1]=~ m/g([0-9]*)/);
  return "groupnr $groupnr not known." if(!$hash->{CODE}{$groupnr}); 

  my $v = join(" ", @a);
  Log3 $name, 5, "EIB set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

  if($value eq "raw" && defined($arg1)) {                                
  	# complex value command.
  	# the additional argument is transfered alone.
    $c = $arg1;
  } elsif ($value eq "value" && defined($arg1)) {
  	# value to be translated according to datapoint type
  	$c = EIB_EncodeByDatapointType($hash,$name,$arg1,$groupnr); #MH add group in call
  	
  	# set the value to the back translated value
  	$v = EIB_ParseByDatapointType($hash,$name,$c,$groupnr); # MH probably stupid - but required!!!!
  }

  my $groupcode = $hash->{CODE}{$groupnr};
  $model = $attr{$name}{"model"}; ##MH 
  $model = "" unless defined($model); ##MH avoid uninit msg

  my $code = $eib_dpttypes{"$model"}{"CODE"};
  if (defined($code) && $code eq 'dpt7') { #MH avoid uninit msg
    IOWrite($hash, "B", "b" . $groupcode . $c);
  }
  else {
    IOWrite($hash, "B", "w" . $groupcode . $c);
  }

  ###########################################
  # Delete any timer for on-for_timer
  if($modules{EIB}{ldata}{$name}) {
    CommandDelete(undef, $name . "_timer");
    delete $modules{EIB}{ldata}{$name};
  }
   
  ###########################################
  # Add a timer if any for-timer command has been chosen
  if($value =~ m/for-timer/ && defined($arg1)) {
    my $dur = $arg1;
    my $to = sprintf("%02d:%02d:%02d", $dur/3600, ($dur%3600)/60, $dur%60);
    $modules{EIB}{ldata}{$name} = $to;
    Log3 $name, 4, "Follow: +$to set $name off g$groupnr"; 
    CommandDefine(undef, $name . "_timer at +$to set $name off g$groupnr");
  }

  ###########################################
  # Delete any timer for on-till
  if($modules{EIB}{till}{$name}) {
    CommandDelete(undef, $name . "_till");
    delete $modules{EIB}{till}{$name};
  }
  
  ###########################################
  # Add a timer if on-till command has been chosen
  if($value =~ m/on-till/ && defined($arg1)) {
	  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($arg1);
	  if($err) {
	  	Log3 $name, 2, "Error trying to parse timespec for $a[0] $a[1] $a[2] : $err";
	  }
	  else {
		  my @lt = localtime;
		  my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
		  my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
		  if($hms_now ge $hms_till) {
		    Log3 $name, 4, "on-till: won't switch as now ($hms_now) is later than $hms_till";
		  }
		  else {
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
  foreach my $n (keys %{ $defptr }) {
    readingsSingleUpdate($defptr->{$n}, "state", $v, 1);
    readingsSingleUpdate($defptr->{$n},"setG" . $groupnr,$v,1) if (AttrVal($defptr->{$n}{NAME},'EIBreadingX',0) == 1); #MH reading setGroup
    print "setg = $defptr->{$n}{NAME} , $groupnr , attr = " . AttrVal($defptr->{$n}{NAME},'EIBreadingX',0) .  " \n" if ($debug eq 1);
  }
  return $ret;
}


sub
EIB_Parse($$)
{
  my ($hash, $msg) = @_;

  # Msg format: 
  # B(w/r/p)<group><value> i.e. Bw00000101
  # we will also take reply telegrams into account, 
  # as they will be sent if the status is asked from bus 
  if($msg =~ m/^B(.{4})[w|p](.{4})(.*)$/)
  {
  	# only interested in write / reply group messages
  	my $src = $1;
  	my $dev = $2;
  	my $val = $3;

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
	    if($def) {
		    foreach my $n (keys %{ $def }) {
		      my $lh = $def->{$n};
			  foreach my $gnr (keys %{ $lh->{CODE} } ) #MH
		      {
	    	    my $c = $lh->{CODE}{$gnr}; #MH
	    	    if($c eq $dev)
	    	    {
			      $n = $lh->{NAME};        # It may be renamed
			
			      next if(IsIgnored($n));   # Little strange.
			
				  # parse/translate by datapoint type
			      $v = EIB_ParseByDatapointType($lh,$n,$rawv,$gnr); # MH added optional groupnr
			
			      $lh->{RAWSTATE} = $rawv;
			      $lh->{LASTGROUP} = $dev;
				  
				  readingsSingleUpdate($lh,"state",$v,1);
				  readingsSingleUpdate($lh,'getG' . $gnr,$v,1) if (defined($attr{$n}{"EIBreadingX"}) && $attr{$n}{"EIBreadingX"} == 1); #MH get readingsvalue
				  print "GETG = $n , group= $gnr , attr = " . $attr{$n}{"EIBreadingX"} .  " \n"  if ($debug eq 1);
				  
				  Log3 $n, 5, "EIB $n $v";
				  
			      push(@list, $n);
			      $found = 1;
	    	    }
		    }}
	    }
   	}
   		
    	
  	return @list if $found>0;
    		
   	if($found==0)
   	{
	    my $dev_name = eib_hex2name($dev);
   		Log3 $dev, 3, "EIB Unknown device $dev ($dev_name), Value $val, please define it";
   		return "UNDEFINED EIB_$dev EIB $dev";
   	}
  }
}

sub
EIB_EncodeByDatapointType($$$$) #MH added  groupnr
{
	my ($hash, $name, $value, $gnr) = @_;
		my @model_array = split(" ",$attr{$name}{"model"}) if (defined($attr{$name}{"model"}));
		my $model = $model_array[0];

	if (!defined($model)) {
		Log3 $hash, 4,"EIB encode $value for $name";
		return $value;
	}

	if (defined($gnr)) {
		$model = $model_array[$gnr-1] if (defined($model_array[$gnr-1]));
	}

	Log3 $hash, 5,"EIB_EncodeByDatapointType: $name, Value= $value, model= $model";
	
	my $dpt = $eib_dpttypes{"$model"};

	if (!defined($dpt)) {
		Log3 $hash, 4,"EIB encode $value for $name model: $model";
		return $value;
	}

	my $code = $eib_dpttypes{"$model"}{"CODE"};
	my $unit = $eib_dpttypes{"$model"}{"UNIT"};
	my $transval = undef;
	my $adjustment = $eib_dpttypes{"$model"}{"ADJUSTMENT"};
	
	Log3 $hash, 4,"EIB encode $value for $name model: $model dpt: $code unit: $unit";
	
	if ($code eq "dpt1") 
	{
		$transval = $value;
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";
	}
	elsif ($code eq "dpt5") 
	{
		my $dpt5factor = $eib_dpttypes{"$model"}{"factor"};
		my $fullval = sprintf("00%.2x",($value/$dpt5factor));
		$transval = $fullval;
				
		Log3 $hash, 5,"EIB $code encode $value = $fullval factor = $dpt5factor translated: $transval";
		
	} elsif ($code eq "dpt7") 
	{
		my $fullval = sprintf("00%.2x",$value);
		$transval = $fullval;
		if($adjustment eq "255") {
			$transval = ($fullval / 2.55);
			$transval = sprintf("%.0f",$transval);
		} else {
			$transval = $fullval;
		}
				
		Log3 $hash, 5,"EIB $code encode $value = $fullval translated: $transval";
		
	} elsif($code eq "dpt9") 
	{
		$transval = encode_dpt9($value);		
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";
		
	} elsif ($code eq "dpt10") 
	{
		# set current Time
		my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		$year+=1900;
		$mon++;
		$value =  sprintf("%02d:%02d:%02d",$hours,$mins,$secs); # value for log
		
        # calculate offset for weekday
		if ($wday eq "0") {
			$wday = 7;
		}
		my $hoffset = 32*$wday;
 		
		my $fullval = $secs + ($mins<<8) + (($hoffset + $hours)<<16);

		$transval = sprintf("00%.6x",$fullval);
				
		Log3 $hash, 5,"EIB $code encode $value = $fullval hours: $hours mins: $mins secs: $secs translated: $transval";
		
	} elsif ($code eq "dpt10_ns") 
	{
		# set current Time
		my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		my $secZero = 0;
		$year+=1900;
		$mon++;

        # calculate offset for weekday
		if ($wday eq "0") {
			$wday = 7;
		}
		my $hoffset = 32*$wday;
 		
		#my $fullval = $secs + ($mins<<8) + ($hours<<16);		
		my $fullval = $secZero + ($mins<<8) + (($hoffset + $hours)<<16);

		$transval = sprintf("00%.6x",$fullval);
				
		Log3 $hash, 5,"EIB $code encode $value = $fullval hours: $hours mins: $mins secs: $secs translated: $transval";
		
	} elsif ($code eq "dpt11") 
	{
		# set current Date
		my ($secs,$mins,$hours,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);
		$year+=1900;
		$month++;
		
		my $fullval = ($year-2000) + ($month<<8) + ($day<<16);
		$transval = sprintf("00%.6x",$fullval);

		Log3 $hash, 5,"EIB $code encode $value = $fullval day: $day month: $month year: $year translated: $transval";
		
	} elsif ($code eq "dpt12") 
	{
		my $fullval = sprintf("00%.8x",$value);
		$transval = $fullval;
				
		Log3 $hash, 5,"EIB $code encode $value" . '=' . " $fullval translated: $transval";
		
	} elsif($code eq "dpt14") 
	{
		$transval = encode_dpt14($value);		
		Log3 $hash, 5,"EIB $code encode $value translated: $transval";	
		
	} elsif ($code eq "dptxx") {
		
	}
	
	# set state to translated value
	if(defined($transval))
	{
		Log3 $hash, 4,"EIB $name translated $value $unit to $transval";
		$value = "$transval";
	}
	else
	{
		Log3 $hash, 4,"EIB $name model $model value $value could not be translated/encoded. Just do a dec2hex translation";
		$value = sprintf("00%.2x",$value);		
	}
	
	return $value;
}

sub
EIB_ParseByDatapointType($$$$) #MH added groupnr
{
	my ($hash, $name, $value, $gnr) = @_; #MH
	my @model_array = split(" ",$attr{$name}{"model"}) if (defined($attr{$name}{"model"}));
	my $model = $model_array[0];
	
	# nothing to do if no model is given
	return $value if(!defined($model));
	
	if (defined($gnr)) {
		$model = $model_array[$gnr-1] if defined ($model_array[$gnr-1]);
	}
	
	print "EIB_ParseByDatapointType: $name, val= $value, Group= $gnr, Model= $model \n" if ($debug eq 1);
	
	my $dpt = $eib_dpttypes{"$model"};
	
	#nothing to do if no dpt is given
	if (!defined($dpt)) {
	    Log3 $hash, 4,"EIB parse $value for $name model: $model" if (defined($model));
		Log3 $hash, 4,"EIB parse $value for $name" if (!defined($model));
		return $value;
	}
	
	my $code = $eib_dpttypes{"$model"}{"CODE"};
	my $unit = $eib_dpttypes{"$model"}{"UNIT"};
	my $transval = undef;
	
	Log3 $hash, 5,"EIB parse $value for $name model: $model dpt: $code unit: $unit";
	print "EIB_ParseByDatapointType: $name, val= $value, Group= $gnr, Model= $model, code= $code, unit= $unit \n"  if ($debug eq 1);
	
	#ABU aus Übersichtlichkeitsgründen voran gestellt
	if ($code ne "dpt1")
	{
	    $value = 0 if ($value eq "off"); 
		$value = 1 if ($value eq "on"); 
	}
	
	#Je nach DPT ist was zu tun...
	if ($code eq "dpt1") 
	{
		$value = "off" if ($value eq 0); 
		$value = "on" if ($value eq 1); 

		$transval = $value;				
	}
	elsif ($code eq "dpt5") 
	{
		my $dpt5factor = $eib_dpttypes{"$model"}{"factor"};
		my $fullval = hex($value);
		$transval = $fullval;
		$transval = sprintf("%.0f",$transval * $dpt5factor) if($dpt5factor != 0);		
		
	} elsif ($code eq "dpt7") 
	{
		my $fullval = hex($value);
		$transval = $fullval;		
		
	} elsif($code eq "dpt9") 
	{
		my $fullval = hex($value);
		my $sign = 1;
		$sign = -1 if(($fullval & 0x8000)>0);
		my $exp = ($fullval & 0x7800)>>11;
		my $mant = ($fullval & 0x07FF);
		$mant = -(~($mant-1)&0x07FF) if($sign==-1);
		
		$transval = (1<<$exp)*0.01*$mant;
		
	} elsif ($code eq "dpt10") 
	{
		# Time
		my $fullval = hex($value);
		my $hours = ($fullval & 0x1F0000)>>16;
		my $mins  = ($fullval & 0x3F00)>>8;
		my $secs  = ($fullval & 0x3F);
		$transval = sprintf("%02d:%02d:%02d",$hours,$mins,$secs);
				
	} elsif ($code eq "dpt10_ns") 
	{
		# Time
		my $fullval = hex($value);
		my $hours = ($fullval & 0x1F0000)>>16;
		my $mins  = ($fullval & 0x3F00)>>8;
		my $secs  = ($fullval & 0x3F);
		$transval = sprintf("%02d:%02d",$hours,$mins);
				
	} elsif ($code eq "dpt11") 
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
				
	} elsif ($code eq "dpt12") 
	{
		my $fullval = hex($value);
		$transval = $fullval;		
				
	} elsif ($code eq "dpt14") # contributed by Olaf
    	{
        	# 4 byte single precision float
       	 	my $byte0 = hex(substr($value,0,2));
        	my $sign = ($byte0 & 0x80) ? -1 : 1;

        	my $bytee = hex(substr($value,0,4));
        	my $expo = (($bytee & 0x7F80) >> 7) - 127;

        	my $bytem = hex(substr($value,2,6));
        	my $mant = ($bytem & 0x7FFFFF | 0x800000);

        	$transval = $sign * (2 ** $expo) * ($mant / (1 <<23));
                
	} elsif ($code eq "dpt16") {

		$transval= decode_dpt16($value);

	} elsif ($code eq "dptxx") {
		
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
sub decode_dpt16($)
{ 
  # 14byte char
  my $val = shift;
  my $res = "";  

  for (my $i=0;$i<14;$i++) {
    my $c = hex(substr($val,$i*2,2));
    if ($c eq 0) {
      $i = 14;
    } else {
      $res .=  sprintf("%c", $c);
    }
  }
  return sprintf("%s","$res");
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

#############################
# 2byte signed float
sub encode_dpt9($) {
    my $state = shift;
    my $data;
	my $retVal;

    my $sign = ($state <0 ? 0x8000 : 0);
    my $exp  = 0;
    my $mant = 0;

    $mant = int($state * 100.0);
    while (abs($mant) > 2047) {
        $mant /= 2;
        $exp++;
    }
    $data = $sign | ($exp << 11) | ($mant & 0x07ff);
	
	$retVal = sprintf("00%.4x",$data);
	
    return $retVal;
}

#############################
# 4byte signed float
sub encode_dpt14 {

	my $real = shift; 
	my $packed_float = pack "f", $real; 
	my $data  = sprintf("%04X", unpack("L",  pack("f", $real))); 

    return $data
}

1;

=pod
=begin html

<a name="EIB"></a>
<h3>EIB / KNX</h3>
<div style="margin-left: 2em">
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
  <div style="margin-left: 2em">
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
  <div style="margin-left: 2em">
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt; g&lt;groupnr&gt;]</code>
    <p>where value one of:</p>
    <ul>
	  <li><b>on</b> switch on device</li>
	  <li><b>off</b> switch off device</li>
	  <li><b>on-for-timer</b> &lt;secs&gt; switch on the device for the given time. After the specified seconds a switch off command is sent.</li>
	  <li><b>on-till</b> &lt;time spec&gt; switches the device on. The device will be switched off at the given time.</li>
      <li><b>raw</b> &lt;hexvalue&gt; sends the given value as raw data to the device.</li>
      <li><b>value</b> &lt;decimal value&gt; transforms the value according to the chosen model and send the result to the device.</li>
    </ul>
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
      attr timedev model dpt10
      attr timedev eventMap /value now:now/
      attr timedev webCmd now
      
      define datedev EIB 0/0/8
      attr datedev model dpt11
      attr datedev eventMap /value now:now/
      attr datedev webCmd now
      
      # send every midnight the new date
      define dateset at *00:00:00 set datedev value now
      
      # send every hour the current time
      define timeset at +*01:00:00 set timedev value now
	</pre>	
  </div>
 
  <p><a name="EIBget"></a> <b>Get</b></p>
  <div style="margin-left: 2em">  
  <p>not implemented</p>
  </div>
    
  <p><a name="EIBattr"></a> <b>Attributes</b></p>
  <div style="margin-left: 2em">   
  <ul>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#alias">alias</a></li>
    <li><a href="#comment">comment</a></li>
    <li><a href="#devStateIcon">devStateIcon</a></li>
    <li><a href="#devStateStyle">devStateStyle</a></li>
<!--    <li><a href="#do_not_notify">do_not_notify</a></li> -->
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>    
<!--    <li><a href="#event-aggregator">event-aggregator</a></li>
    <li><a href="#event-min-interval">event-min-interval</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
-->
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#group">group</a></li>
    <li><a href="#icon">icon</a></li>
    <li><a href="#ignore">ignore</a></li>
<!--    <li><a href="#loglevel">loglevel</a></li> -->
    <li><a href="#room">room</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#sortby">sortby</a></li>
<!--    <li><a href="#stateFormat">stateFormat</a></li>
    <li><a href="#userReadings">userReadings</a></li>
-->
    <li><a href="#userattr">userattr</a></li>
    <li><a href="#verbose">verbose</a></li>
    <li><a href="#webCmd">webCmd</a></li>
    <li><a href="#widgetOverride">widgetOverride</a></li>
    <li><b>model</b> - 
      set the model according to the datapoint types defined by the (<a href="http://www.sti.uniurb.it/romanell/110504-Lez10a-KNX-Datapoint%20Types%20v1.5.00%20AS.pdf" target="_blank">EIB / KNX specifications</a>). The device state in FHEM is interpreted and shown according to the specification.
      <ul>
        <li>dpt1   will be interpreted as on/off</li>
      	<li>dpt5</li>
      	<li>dpt5.003</li>
      	<li>angle</li>
      	<li>percent</li>
      	<li>dpt5.004</li>
      	<li>percent255</li>
      	<li>dpt7</li>
      	<li>length-mm</li>
      	<li>current-mA</li>
      	<li>brightness</li>
      	<li>timeperiod-ms</li>
      	<li>timeperiod-min</li>
      	<li>timeperiod-h</li>
      	<li>dpt9</li>
      	<li>tempsensor</li>
      	<li>lightsensor</li>
      	<li>speedsensor</li>
      	<li>speedsensor-km/h</li>
      	<li>pressuresensor</li>
      	<li>rainsensor</li>
      	<li>time1sensor</li>
      	<li>time2sensor</li>
      	<li>humiditysensor</li>
      	<li>airqualitysensor</li>
      	<li>voltage-mV</li>
      	<li>current-mA2</li>
      	<li>current-mA2</li>
      	<li>power</li>
      	<li>powerdensity</li>
      	<li>dpt10</li>
		<li>dpt10_ns</li>
      	<li>time</li>
      	<li>dpt11</li>
      	<li>date</li>
      	<li>dpt12</li>
      	<li>dpt14</li>
      	<li>dpt16</li>
      </ul>
      <p>If the EIBreadingX is set, you can specify multiple blank separated models to cope with multiple groups in the define statement. The setting cannot be done thru the pulldown-menu, you have to specify them with <code>attr &lt;device&gt; model &lt;dpt1&gt; &lt;dpt2&gt; &lt;dpt3&gt;</code></p> 
    </li>

    <li><b>EIBreadingX</b> - 
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
      attr myDimmer model dpt1 dpt5.slider # GA 0/1/1 will be interpreted as on/off, GA 0/1/2 will be handled as dpt5 and show a slider on FHEMWEB
      attr myDimmer eventmap /on:An/off:Aus/value g2:dim/
      attr myDimmer webcmd on off dim
      attr myDimmer stateFormat getG2 % # copies actual dim-level (as sent/received to/from dimmer) into STATE 
      </pre>    
     </li>
  </ul>   
  </div>
</div>

=end html
=cut
