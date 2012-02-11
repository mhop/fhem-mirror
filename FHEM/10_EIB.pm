##############################################
# $Id$
package main;

use strict;
use warnings;

my %eib_c2b = (
	"off" => "00",
	"on" => "01",
	"on-for-timer" => "01",
	"on-till" => "01",
	"value" => ""
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

  # 1-Octet unsigned value (handled as dpt7)
  "dpt5" 		=> {"CODE"=>"dpt7", "UNIT"=>""},
  "percent" 	=> {"CODE"=>"dpt7", "UNIT"=>"%"},	

  # 2-Octet unsigned Value (current, length, brightness)
  "dpt7" 		=> {"CODE"=>"dpt7", "UNIT"=>""},
  "length-mm" 		=> {"CODE"=>"dpt7", "UNIT"=>"mm"},
  "current-mA" 		=> {"CODE"=>"dpt7", "UNIT"=>"mA"},
  "brightness"		=> {"CODE"=>"dpt7", "UNIT"=>"lux"},
  "timeperiod-ms"		=> {"CODE"=>"dpt7", "UNIT"=>"ms"},
  "timeperiod-min"		=> {"CODE"=>"dpt7", "UNIT"=>"min"},
  "timeperiod-h"		=> {"CODE"=>"dpt7", "UNIT"=>"h"},

  # 2-Octet unsigned Value (Temp / Light)
  "dpt9" 		=> {"CODE"=>"dpt9", "UNIT"=>""},
  "tempsensor"  => {"CODE"=>"dpt9", "UNIT"=>"Celsius"},
  "lightsensor" => {"CODE"=>"dpt9", "UNIT"=>"Lux"},
  
  # Time of Day
  "dpt10"		=> {"CODE"=>"dpt10", "UNIT"=>""},
  "time"		=> {"CODE"=>"dpt10", "UNIT"=>""},
  
  # Date
  "dpt11"		=> {"CODE"=>"dpt11", "UNIT"=>""},
  "date"		=> {"CODE"=>"dpt11", "UNIT"=>""},
  
  # 4-Octet unsigned value (handled as dpt7)
  "dpt12" 		=> {"CODE"=>"dpt7", "UNIT"=>""},
  
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
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:1,0 showtime:1,0 model:EIB loglevel:0,1,2,3,4,5,6";

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
  Log(5,"EIB setState tim: $tim vt: $vt val: $val");

  $val = $1 if($val =~ m/^(.*) \d+$/);
  return "Undefined value $val" if(!defined($eib_c2b{$val}));
  return undef;
}

###################################
sub
EIB_Get($@)
{
  my ($hash, @a) = @_;
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

  my $c = $eib_c2b{$a[1]};
  if(!defined($c)) {
    return "Unknown argument $a[1], choose one of " .
                                join(" ", sort keys %eib_c2b);
  }
  
  # the command can be send to any of the defined groups indexed starting by 1
  my $groupnr = 1;
  if($a[1] eq "value" && $na > 3){$groupnr=$a[3]}
  elsif ($na>2){$groupnr=$a[2]}
  return "groupnr argument $groupnr must be numeric." if( $groupnr !~ m/[0-9]*/i);
  return "groupnr $groupnr not known." if(!$hash->{CODE}{$groupnr}); 

  my $v = join(" ", @a);
  Log GetLogLevel($a[0],2), "EIB set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

  if($a[1] eq "value" && $na > 2) {                                
  	# complex value command.
  	# the additional argument is transfered alone.
    $c = $a[2];
  }

  my $groupcode = $hash->{CODE}{$groupnr};

  IOWrite($hash, "B", "w" . $groupcode . $c);

  ###########################################
  # Delete any timer for on-for_timer
  if($modules{EIB}{ldata}{$a[0]}) {
    CommandDelete(undef, $a[0] . "_timer");
    delete $modules{EIB}{ldata}{$a[0]};
  }
   
  ###########################################
  # Add a timer if any for-timer command has been chosen
  if($a[1] =~ m/for-timer/ && $na == 3) {
    my $dur = $a[2];
    my $to = sprintf("%02d:%02d:%02d", $dur/3600, ($dur%3600)/60, $dur%60);
    $modules{EIB}{ldata}{$a[0]} = $to;
    Log 4, "Follow: +$to set $a[0] off";
    CommandDefine(undef, $a[0] . "_timer at +$to set $a[0] off");
  }

  ###########################################
  # Delete any timer for on-till
  if($modules{EIB}{till}{$a[0]}) {
    CommandDelete(undef, $a[0] . "_till");
    delete $modules{EIB}{till}{$a[0]};
  }
  
  ###########################################
  # Add a timer if on-till command has been chosen
  if($a[1] =~ m/on-till/ && $na == 3) {
	  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
	  if($err) {
	  	Log(2,"Error trying to parse timespec for $a[0] $a[1] $a[2] : $err");
	  }
	  else {
		  my @lt = localtime;
		  my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
		  my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
		  if($hms_now ge $hms_till) {
		    Log 4, "on-till: won't switch as now ($hms_now) is later than $hms_till";
		  }
		  else {
		    $modules{EIB}{till}{$a[0]} = $hms_till;
		    Log 4, "Follow: $hms_till set $a[0] off";
		    CommandDefine(undef, $a[0] . "_till at $hms_till set $a[0] off");
		  }
	  }
  }
  

  ##########################
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{GROUP}";
  my $tn = TimeNow();
  foreach my $n (keys %{ $modules{EIB}{defptr}{$code} }) {

    my $lh = $modules{EIB}{defptr}{$code}{$n};
    $lh->{CHANGED}[0] = $v;
    $lh->{STATE} = $v;
    $lh->{READINGS}{state}{TIME} = $tn;
    $lh->{READINGS}{state}{VAL} = $v;
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
	
    my $def = $modules{EIB}{defptr}{"$dev"};
    if($def) {
	    foreach my $n (keys %{ $def }) {
	      my $lh = $def->{$n};
	      $n = $lh->{NAME};        # It may be renamed
	
	      return "" if(IsIgnored($n));   # Little strange.
	
	      # parse/translate by datapoint type
	      $v = EIB_ParseByDatapointType($lh,$n,$v);
	
	      $lh->{CHANGED}[0] = $v;
	      $lh->{STATE} = $v;
	      $lh->{RAWSTATE} = $rawv;
	      $lh->{LASTGROUP} = $dev;
	      $lh->{READINGS}{state}{TIME} = TimeNow();
	      $lh->{READINGS}{state}{VAL} = $v;

	      Log 2, "EIB $n $v";
	
	      push(@list, $n);
	      $found = 1;
	    }
        #return @list;
    } 
    
    # check also the further codes
    {
    	# check if the code is within the read groups
    	
    	foreach my $mod (keys %{$modules{EIB}{defptr}})
    	{
    		my $def = $modules{EIB}{defptr}{"$mod"};
		    if($def) {
		      	my @list;
			    foreach my $n (keys %{ $def }) {
			      my $lh = $def->{$n};
		          foreach my $c (keys %{ $lh->{CODE} } ) 
			      {
		    	    $c = $lh->{CODE}{$c};
		    	    if($c eq $dev)
		    	    {
				      $n = $lh->{NAME};        # It may be renamed
				
				      return "" if(IsIgnored($n));   # Little strange.
				
					  # parse/translate by datapoint type
				      $v = EIB_ParseByDatapointType($lh,$n,$v);
				
				      $lh->{CHANGED}[0] = $v;
				      $lh->{STATE} = $v;
				      $lh->{RAWSTATE} = $rawv;
				      $lh->{LASTGROUP} = $dev;
				      $lh->{READINGS}{state}{TIME} = TimeNow();
				      $lh->{READINGS}{state}{VAL} = $v;
	      			  Log 2, "EIB $n $v";
	      			  
				      push(@list, $n);
				      $found = 1;
		    	    }
			    }}
		    }
    	}
    }    		
    	
  	return @list if $found>0;
    		
   	if($found==0)
   	{
	    my $dev_name = eib_hex2name($dev);
   		Log(3, "EIB Unknown device $dev ($dev_name), Value $val, please define it");
   		return "UNDEFINED EIB_$dev EIB $dev";
   	}

  }

}

sub
EIB_ParseByDatapointType($$$)
{
	my ($hash, $name, $value) = @_;
	my $model = $attr{$name}{"model"};
	
	# nothing to do if no model is given
	return $value if(!defined($model));
	
	my $dpt = $eib_dpttypes{"$model"};
	
	Log(4,"EIB parse $value for $name model: $model dpt: $dpt");
	return $value if(!defined($dpt));
	
	my $code = $eib_dpttypes{"$model"}{"CODE"};
	my $unit = $eib_dpttypes{"$model"}{"UNIT"};
	my $transval = undef;
	
	Log(4,"EIB parse $value for $name model: $model dpt: $code unit: $unit");
	
	if ($code eq "dpt7") 
	{
		my $fullval = hex($value);
		$transval = $fullval;		
				
		Log(5,"EIB $code parse $value = $fullval translated: $transval");
		
	} elsif($code eq "dpt9") 
	{
		my $fullval = hex($value);
		my $sign = 1;
		$sign = -1 if(($fullval & 0x8000)>0);
		my $exp = ($fullval & 0x7800)>>11;
		my $mant = ($fullval & 0x07FF);
		
		$transval = ($sign * $mant * (2**$exp))/100;
		
		Log(5,"EIB $code parse $value = $fullval sign: $sign mant: $mant exp: $exp translated: $transval");	
		
		
	} elsif ($code eq "dpt10") 
	{
		# Time
		my $fullval = hex($value);
		my $hours = ($fullval & 0x1F0000)>>16;
		my $mins  = ($fullval & 0x3F00)>>8;
		my $secs  = ($fullval & 0x3F);
		$transval = sprintf("%02d:%02d:%02d",$hours,$mins,$secs);
				
		Log(5,"EIB $code parse $value = $fullval hours: $hours mins: $mins secs: $secs translated: $transval");
		
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
				
		Log(5,"EIB $code parse $value = $fullval day: $day month: $month year: $year translated: $transval");
		
	} elsif ($code eq "dptxx") {
		
	}
	
	# set state to translated value
	if(defined($transval))
	{
		Log(4,"EIB $name translated to $transval $unit");
		$value = "$transval $unit";
	}
	else
	{
		Log(4,"EIB $name model $model value $value could not be translated.");
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
  Log(5, "name2hex: $v");
  if($v =~ /^([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{1,3})$/) {
  	$r = sprintf("%01x%01x%02x",$1,$2,$3);
  }
  elsif($v =~ /^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,3})$/) {
  	$r = sprintf("%01x%01x%02x",$1,$2,$3);
  }  
    
  return $r;
}


1;
