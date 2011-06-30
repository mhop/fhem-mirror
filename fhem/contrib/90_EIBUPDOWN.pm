##############################################
package main;

use strict;
use warnings;

my %eib_c2b1 = (
	"alloff" => "00",
	"off" => "01",
	"on" => "00",
	"up" => "01",
	"down" => "00",
	"up-for-timer" => "01",
	"down-for-timer" => "00",
);

my %eib_c2b2 = (
	"alloff" => "00",
	"off" => "00",
	"on" => "01",
	"up" => "00",
	"down" => "01",
	"up-for-timer" => "00",
	"down-for-timer" => "01",
);


my %readonly = (
  "dummy" => 1,
);

my $eib_simple ="alloff off on up down up-for-timer down-for-timer";
my %models = (
);

sub
EIBUPDOWN_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^B.*";
  $hash->{SetFn}     = "EIBUPDOWN_Set";
  $hash->{StateFn}   = "EIBUPDOWN_SetState";
  $hash->{DefFn}     = "EIBUPDOWN_Define";
  $hash->{UndefFn}   = "EIBUPDOWN_Undef";
  $hash->{ParseFn}   = "EIBUPDOWN_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:1,0 showtime:1,0 model:EIB loglevel:0,1,2,3,4,5,6";

}


#############################
sub
EIBUPDOWN_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> EIBUPDOWN <up group name> <down group name>";

  return $u if(int(@a) < 4);
  return "Define $a[0]: wrong up group name format: specify as 0-255/0-255/0-255"
  		if( ($a[2] !~ m/^[0-9]{1,3}\/[0-9]{1,3}\/[0-9]{1,3}$/i));

  return "Define $a[0]: wrong down group name format: specify as 0-255/0-255/0-255"
  		if( ($a[3] !~ m/^[0-9]{1,3}\/[0-9]{1,3}\/[0-9]{1,3}$/i));

  my $groupname_up = eibupdown_name2hex($a[2]);
  my $groupname_down = eibupdown_name2hex($a[3]);

  $hash->{GROUP_UP} = lc($groupname_up);
  $hash->{GROUP_DOWN} = lc($groupname_down);

  my $code = "$groupname_up$groupname_down";
  my $ncode = 1;
  my $name = $a[0];

  $hash->{CODE}{$ncode++} = $code;
  $modules{EIB}{defptr}{$code}{$name}   = $hash;

  AssignIoPort($hash);
}

#############################
sub
EIBUPDOWN_Undef($$)
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
EIBUPDOWN_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  $val = $1 if($val =~ m/^(.*) \d+$/);
  return "Undefined value $val" if(!defined($eib_c2b1{$val}));
  return undef;
}

###################################
sub
EIBUPDOWN_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);

  return "no set value specified" if($na < 2 || $na > 3);
  return "Readonly value $a[1]" if(defined($readonly{$a[1]}));

  my $c_off = $eib_c2b1{"alloff"};
  my $c_up = $eib_c2b1{$a[1]};
  my $c_down = $eib_c2b2{$a[1]};
  if(!defined($c_off) || !defined($c_up) || !defined($c_down)) {
    return "Unknown argument $a[1], choose one of " .
                                join(" ", sort keys %eib_c2b1);
  }

  my $v = join(" ", @a);
  Log GetLogLevel($a[0],2), "EIB set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

  # first of all switch off all channels
  # just for being sure
  IOWrite($hash, "B", "w" . $hash->{GROUP_UP} . $c_off);
  select(undef,undef,undef,0.5);
  IOWrite($hash, "B", "w" . $hash->{GROUP_DOWN} . $c_off);
  select(undef,undef,undef,0.5);

  # now switch on the right channel
  if($c_up ne $c_off) {
  	IOWrite($hash, "B", "w" . $hash->{GROUP_UP} . $c_up);
  }
  elsif($c_down ne $c_off) {
  	IOWrite($hash, "B", "w" . $hash->{GROUP_DOWN} . $c_down);
  }

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
    Log 4, "Follow: +$to set $a[0] alloff";
    CommandDefine(undef, $a[0] . "_timer at +$to set $a[0] alloff");
  }

  ##########################
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{GROUP_UP}$hash->{GROUP_DOWN}";
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
EIBUPDOWN_Parse($$)
{
  my ($hash, $msg) = @_;

  Log(5,"EIBUPDOWN_Parse is not defined. msg: $msg");

}

#############################
sub
eibupdown_name2hex($)
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
