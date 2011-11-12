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

sub
EIB_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^B.*";
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

  my $u = "wrong syntax: define <name> EIB <group name>";

  return $u if(int(@a) < 3);
  return "Define $a[0]: wrong group name format: specify as 0-15/0-15/0-255 or as hex"
  		if( ($a[2] !~ m/^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{1,3}$/i)  && (lc($a[2]) !~ m/^[0-9a-f]{4}$/i));

  my $groupname = eib_name2hex(lc($a[2]));

  $hash->{GROUP} = lc($groupname);

  my $code = "$groupname";
  my $ncode = 1;
  my $name = $a[0];

  $hash->{CODE}{$ncode++} = $code;
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

  $val = $1 if($val =~ m/^(.*) \d+$/);
  return "Undefined value $val" if(!defined($eib_c2b{$val}));
  return undef;
}

###################################
sub
EIB_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);

  return "no set value specified" if($na < 2 || $na > 3);
  return "Readonly value $a[1]" if(defined($readonly{$a[1]}));

  my $c = $eib_c2b{$a[1]};
  if(!defined($c)) {
    return "Unknown argument $a[1], choose one of " .
                                join(" ", sort keys %eib_c2b);
  }

  my $v = join(" ", @a);
  Log GetLogLevel($a[0],2), "EIB set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

  if($a[1] eq "value" && $na == 3) {                                
  	# complex value command.
  	# the additional argument is transfered alone.
    $c = $a[2];
  }

  IOWrite($hash, "B", "w" . $hash->{GROUP} . $c);

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

    my $def = $modules{EIB}{defptr}{"$dev"};
    if($def) {
      	my @list;
	    foreach my $n (keys %{ $def }) {
	      my $lh = $def->{$n};
	      $n = $lh->{NAME};        # It may be renamed
	
	      return "" if(IsIgnored($n));   # Little strange.
	
	      $lh->{CHANGED}[0] = $v;
	      $lh->{STATE} = $v;
	      $lh->{READINGS}{state}{TIME} = TimeNow();
	      $lh->{READINGS}{state}{VAL} = $v;
	      Log GetLogLevel($n,2), "EIB $n $v";
	
	      push(@list, $n);
	    }
        return @list;
    } else {
    my $dev_name = eib_hex2name($dev);
    Log(3, "EIB Unknown device $dev ($dev_name), Value $val, please define it");
    return "UNDEFINED EIB_$dev EIB $dev";
    }
  }

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
  	$r = sprintf("%01x%021%02x",$1,$2,$3);
  }  
    
  return $r;
}


1;
