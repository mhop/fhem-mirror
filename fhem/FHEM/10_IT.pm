######################################################
# InterTechno Switch Manager as FHM-Module
#
# (c) Olaf Droegehorn / DHS-Computertechnik GmbH
# 
# Published under GNU GPL License
######################################################package main;

use strict;
use warnings;


my %codes = (
  "XMIToff" 		=> "off",
  "XMITon" 			=> "on",		
  "XMITdimup" 	=> "dimup",
  "XMITdimdown" => "dimdown",
  "99" => "on-till",
 
);

my %it_c2b;

my $it_defrepetition = 6;   ## Default number of InterTechno Repetitions

my $it_simple ="off on";
my %models = (
    itremote    => 'sender',
    itswitch    => 'simple',
    itdimmer    => 'dimmer',
);

sub
IT_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %codes) {
    $it_c2b{$codes{$k}} = $k;
  }

#  $hash->{Match}     = "";
  $hash->{SetFn}     = "IT_Set";
  $hash->{StateFn}   = "IT_SetState";
  $hash->{DefFn}     = "IT_Define";
  $hash->{UndefFn}   = "IT_Undef";
#  $hash->{ParseFn}   = "IT_Parse";
  $hash->{AttrList}  = "IODev ITfrequency ITrepetition switch_rfmode:1,0 do_not_notify:1,0 ignore:0,1 dummy:1,0 model:itremote,itswitch,itdimmer loglevel:0,1,2,3,4,5,6";

}

#####################################
sub
IT_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  $val = $1 if($val =~ m/^(.*) \d+$/);
  return "Undefined value $val" if(!defined($it_c2b{$val}));
  return undef;
}

#############################
sub
IT_Do_On_Till($@)
{
  my ($hash, @a) = @_;
  return "Timespec (HH:MM[:SS]) needed for the on-till command" if(@a != 3);

  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
  return $err if($err);

  my @lt = localtime;
  my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
  my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
  if($hms_now ge $hms_till) {
    Log 4, "on-till: won't switch as now ($hms_now) is later than $hms_till";
    return "";
  }

  my @b = ($a[0], "on");
  IT_Set($hash, @b);
  my $tname = $hash->{NAME} . "_till";
  CommandDelete(undef, $tname) if($defs{$tname});
  CommandDefine(undef, "$tname at $hms_till set $a[0] off");

}

###################################
sub
IT_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);
  my $message;

  return "no set value specified" if($na < 2 || $na > 3);

  my $c = $it_c2b{$a[1]};
  if(!defined($c)) {

    # Model specific set arguments
    if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"model"})) {
      my $mt = $models{$attr{$a[0]}{"model"}};
      return "Unknown argument $a[1], choose one of "
                                               if($mt && $mt eq "sender");
      return "Unknown argument $a[1], choose one of $it_simple"
                                               if($mt && $mt eq "simple");
    }
    return "Unknown argument $a[1], choose one of " .
                                join(" ", sort keys %it_c2b);
  }

  return IT_Do_On_Till($hash, @a) if($a[1] eq "on-till");
  return "Bad time spec" if($na == 3 && $a[2] !~ m/^\d*\.?\d+$/);

  my $io = $hash->{IODev};

	## Do we need to change RFMode to SlowRF??
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"switch_rfmode"})) {
  	if ($attr{$a[0]}{"switch_rfmode"} eq "1") {			# do we need to change RFMode of IODev
  		  my $ret = CallFn($io->{NAME}, "AttrFn", "set", ($io->{NAME}, "rfmode", "SlowRF"));
 	 	}	
	}

  ## Do we need to change ITrepetition ??	
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"ITrepetition"})) {
  	$message = "isr".$attr{$a[0]}{"ITrepetition"};
		CUL_SimpleWrite($io, $message);
		Log GetLogLevel($a[0],4), "IT set ITrepetition: $message for $io->{NAME}";
	}

  ## Do we need to change ITfrequency ??	
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"ITfrequency"})) {
    my $f = $attr{$a[0]}{"ITfrequency"}/26*65536;
    my $f2 = sprintf("%02x", $f / 65536);
    my $f1 = sprintf("%02x", int($f % 65536) / 256);
    my $f0 = sprintf("%02x", $f % 256);
    
    my $arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
    Log GetLogLevel($a[0],4), "Setting ITfrequency (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz";
    CUL_SimpleWrite($hash, "if$f2$f1$f0");
	}
	
  my $v = join(" ", @a);
  $message = "is".uc($hash->{XMIT}.$hash->{$c});
	
	## Log that we are going to switch InterTechno
  Log GetLogLevel($a[0],2), "IT set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

	## Send Message to IODev and wait for correct answer
  my $msg = CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", $message));
  if ($msg =~ m/raw => $message/) {
        Log 4, "Answer from $io->{NAME}: $msg";
  } else {
        Log 2, "IT IODev device didn't answer is command correctly: $msg";
  }

  ## Do we need to change ITrepetition back??	
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"ITrepetition"})) {
  	$message = "isr".$it_defrepetition;
		CUL_SimpleWrite($io, $message);
		Log GetLogLevel($a[0],4), "IT set ITrepetition back: $message for $io->{NAME}";
	}

  ## Do we need to change ITfrequency back??	
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"ITfrequency"})) {
    Log GetLogLevel($a[0],4), "Setting ITfrequency back to 433.92 MHz";
    CUL_SimpleWrite($hash, "if0");
	}

	## Do we need to change RFMode back to HomeMatic??
  if(defined($attr{$a[0]}) && defined($attr{$a[0]}{"switch_rfmode"})) {
  	if ($attr{$a[0]}{"switch_rfmode"} eq "1") {			# do we need to change RFMode of IODev
  		  my $ret = CallFn($io->{NAME}, "AttrFn", "set", ($io->{NAME}, "rfmode", "HomeMatic"));
 	 	}	
	}


  ##########################
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{XMIT}";
  my $tn = TimeNow();
  foreach my $n (keys %{ $modules{IT}{defptr}{$code} }) {

    my $lh = $modules{IT}{defptr}{$code}{$n};
    $lh->{CHANGED}[0] = $v;
    $lh->{STATE} = $v;
    $lh->{READINGS}{state}{TIME} = $tn;
    $lh->{READINGS}{state}{VAL} = $v;
  }
  return $ret;
}

#############################
sub
IT_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  # calculate transmit code from IT A-P rotary switches
  if($a[2] =~ /^([A-O])(([0]{0,1}[1-9])|(1[0-6]))$/i) {
      my %it_1st = (
          "A","0000","B","F000","C","0F00","D","FF00","E","00F0","F","F0F0",
          "G","0FF0","H","FFF0","I","000F","J","F00F","K","0F0F","L","FF0F",
          "M","00FF","N","F0FF","O","0FFF","P","FFFF"
          );
      my %it_2nd = (
          1 ,"0000",2 ,"F000",3 ,"0F00",4 ,"FF00",5 ,"00F0",6 ,"F0F0",
          7 ,"0FF0",8 ,"FFF0",9 ,"000F",10,"F00F",11,"0F0F",12,"FF0F",
          13,"00FF",14,"F0FF",15,"0FFF",16,"FFFF"
          );
      
      $a[2] = $it_1st{$1}.$it_2nd{int($2)}."0F";
      defined $a[3] or $a[3] = "FF";
      defined $a[4] or $a[4] = "F0";
      defined $a[5] or $a[5] = "0F";
      defined $a[6] or $a[6] = "00";
  }
  # calculate transmit code from FLS 100 I,II,III,IV rotary switches
  if($a[2] =~ /^(I|II|III|IV)([1-4])$/i) {
      my %fls_1st = ("I","0FFF","II","F0FF","III","FF0F","IV","FFF0" );
      my %fls_2nd = (1 ,"0FFF",2 ,"F0FF",3 ,"FF0F",4 ,"FFF0");
      
      $a[2] = $fls_1st{$1}.$fls_2nd{int($2)}."0F";
      defined $a[3] or $a[3] = "FF";
      defined $a[4] or $a[4] = "F0";
      defined $a[5] or $a[5] = "0F";
      defined $a[6] or $a[6] = "00";
  }

  my $u = "wrong syntax: define <name> IT 10-bit-housecode " .
                        "off-code on-code [dimup-code] [dimdown-code]";

  return $u if(int(@a) < 5);
  return "Define $a[0]: wrong IT-Code format: specify a 10 digits 0/1/f "
  		if( ($a[2] !~ m/^[f0-1]{10}$/i) );

  return "Define $a[0]: wrong ON format: specify a 2 digits 0/1/f "
    	if( ($a[3] !~ m/^[f0-1]{2}$/i) );

  return "Define $a[0]: wrong OFF format: specify a 2 digits 0/1/f "
    	if( ($a[4] !~ m/^[f0-1]{2}$/i) );

  my $housecode = $a[2];
  my $oncode = $a[3];
  my $offcode = $a[4];

  $hash->{XMIT} = lc($housecode);
  $hash->{$it_c2b{"on"}}  = lc($oncode);
  $hash->{$it_c2b{"off"}}  = lc($offcode);
  
  if (int(@a) > 5) {
  	return "Define $a[0]: wrong dimup-code format: specify a 2 digits 0/1/f "
    	if( ($a[5] !~ m/^[f0-1]{2}$/i) );
		$hash->{$it_c2b{"dimup"}}  = lc($a[5]);
   
	  if (int(@a) == 7) {
  		return "Define $a[0]: wrong dimdown-code format: specify a 2 digits 0/1/f "
	    	if( ($a[6] !~ m/^[f0-1]{2}$/i) );
    	$hash->{$it_c2b{"dimdown"}}  = lc($a[6]);
  	}
  } else {
		$hash->{$it_c2b{"dimup"}}  = "00";
   	$hash->{$it_c2b{"dimdown"}}  = "00";
  }
  
  my $code = lc($housecode);
  my $ncode = 1;
  my $name = $a[0];

  $hash->{CODE}{$ncode++} = $code;
  $modules{IT}{defptr}{$code}{$name}   = $hash;

  AssignIoPort($hash);
}

#############################
sub
IT_Undef($$)
{
  my ($hash, $name) = @_;

  foreach my $c (keys %{ $hash->{CODE} } ) {
    $c = $hash->{CODE}{$c};

    # As after a rename the $name my be different from the $defptr{$c}{$n}
    # we look for the hash.
    foreach my $dname (keys %{ $modules{IT}{defptr}{$c} }) {
      delete($modules{IT}{defptr}{$c}{$dname})
        if($modules{IT}{defptr}{$c}{$dname} == $hash);
    }
  }
  return undef;
}

sub
IT_Parse($$)
{

}

1;
