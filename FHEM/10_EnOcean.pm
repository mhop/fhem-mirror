##############################################
# CUL HomeMatic handler
package main;

use strict;
use warnings;

sub EnOcean_Define($$);
sub EnOcean_Initialize($);
sub EnOcean_Pair(@);
sub EnOcean_Parse($$);
sub EnOcean_PushCmdStack($$);
sub EnOcean_SendCmd($$$$);
sub EnOcean_Set($@);
sub EnOcean_convTemp($);

sub
EnOcean_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^EnOcean:0B";
  $hash->{DefFn}     = "EnOcean_Define";
  $hash->{ParseFn}   = "EnOcean_Parse";
  $hash->{SetFn}     = "EnOcean_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 " .
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 model " .
                       "subType:remote,sensor,modem ";
}


#############################
sub
EnOcean_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  return "wrong syntax: define <name> EnOcean 8-digit-hex-code"
        if(int(@a)!=3 || $a[2] !~ m/^[A-F0-9]{8}$/i);

  $modules{EnOcean}{defptr}{uc($a[2])} = $hash;
  AssignIoPort($hash);
  # Help FHEMWEB split up davices
  $attr{$name}{subType} = $1 if($name =~ m/EnO_(.*)_$a[2]/);
  return undef;
}


my %sets = ( Btn0=>"10:30", Btn1=>"30:30", Btn2=>"20:30", Btn2=>"70:30",
             "Btn0,Btn2"=>"15:30", "Btn1,Btn2"=>"35:30",
             "Btn0,Btn3"=>"17:30", "Btn1,Btn3"=>"37:30",
             "released"=>"00:20" );

#############################
# Simulate a PTM
sub
EnOcean_Set($@)
{
  my ($hash, @a) = @_;
  return "no set value specified" if(@a != 2);

  my $cmd = $a[1];
  my $arg = $a[2];
  my $cmdhash = $sets{$cmd};
  return "Unknown argument $cmd, choose one of " . join(" ", sort keys %sets)
  	if(!defined($cmdhash));

  my $name = $hash->{NAME};
  my $ll2 = GetLogLevel($name, 2);
  Log $ll2, "EnOcean: set $name $cmd";

  my ($d1, $status) = split(":", $cmdhash, 2);
  IOWrite($hash, "", sprintf("6B05%s000000%s%s", $d1, $hash->{DEF}, $status));

  my $tn = TimeNow();
  $hash->{CHANGED}[0] = $cmd;
  $hash->{STATE} = $cmd;
  $hash->{READINGS}{state}{TIME} = $tn;
  $hash->{READINGS}{state}{VAL} = $cmd;
  return undef;
}

#############################
sub
EnOcean_Parse($$)
{
  my ($iohash, $msg) = @_;
  my %ot = ("05"=>"remote", "06"=>"sensor", "07"=>"sensor",
            "08"=>"remote", "0A"=>"modem",  "0B"=>"modem", );

  $msg =~ m/^EnOcean:0B(..)(........)(........)(..)/;
  my ($org,$data,$id,$status) = ($1,$2,$3,$4,$5);

  my $ot = $ot{$org};
  if(!$ot) {
    Log 2, "Unknown EnOcean ORG: $org received from $id";
    return "";
  }

  $id = ($id & 0xffff) if($org eq "0A");
  $id = (($id & 0xffff0000)>>16) if($org eq "0B");

  my $hash = $modules{EnOcean}{defptr}{$id}; 
  if(!$hash) {
    Log 3, "EnOcean Unknown device with ID $id, please define it";
    return "UNDEFINED EnO_${ot}_$id EnOcean $id";
  }

  my $name = $hash->{NAME};
  my $ll4 = GetLogLevel($name, 4);
  Log $ll4, "EnOcean: ORG:$org, DATA:$data, ID:$id, STATUS:$status";
  my @event;

  push @event, "0:rp_counter:".(hex($status)&0xf);

  my $d1 =  hex substr($data,0,2);

  #################################
  if($org eq "05") {    # PTM remote. Queer reporting methods.
    my $nu =  ((hex($status)&0x10)>>4);

    push @event, "0:T21:".((hex($status)&0x20)>>5);
    push @event, "0:NU:$nu";

    if($nu) {
      $msg  = sprintf    "Btn%d", ($d1&0xe0)>>5;
      $msg .= sprintf ",Btn%d", ($d1&0x0e)>>1 if($d1 & 1);

    } else {
      #confusing for normal use
      #my $nbu = (($d1&0xe0)>>5);
      #$msg  = sprintf "Buttons %d", $nbu ? ($nbu+1) : 0;
      $msg = "buttons";
      
    }
    $msg .= ($d1&0x10) ? " pressed" : " released";
    push @event, "1:state:$msg";

  #################################
  } elsif($org eq "06") {
    push @event, "1:state:$d1";
    push @event, "1:sensor1:$d1";

  #################################
  } elsif($org eq "07") {
    my $d2 = hex substr($data,2,2);
    my $d3 = hex substr($data,4,2);
    my $d4 = hex substr($data,6,2);
    push @event, "1:state:$d1";
    push @event, "1:sensor1:$d1";
    push @event, "1:sensor2:$d2";
    push @event, "1:sensor3:$d3";
    push @event, "1:D3:".($d4&0x8)?1:0;
    push @event, "1:D2:".($d4&0x4)?1:0;
    push @event, "1:D1:".($d4&0x2)?1:0;
    push @event, "1:D0:".($d4&0x1)?1:0;

  #################################
  } elsif($org eq "08") { # CTM remote.
    # Dont understand the SR bit
    $msg  = sprintf "Btn%d", ($d1&0xe0)>>5;
    $msg .= ($d1&0x10) ? " pressed" : " released";
    push @event, "1:state:$msg";

  #################################
  } elsif($org eq "0A") {
    push @event, "1:state:Modem:".substr($msg, 12, 6);

  #################################
  } elsif($org eq "0B") {
    push @event, "1:state:Modem:ACK";

  }

  my $tn = TimeNow();
  my @changed;
  for(my $i = 0; $i < int(@event); $i++) {
    my ($dochanged, $vn, $vv) = split(":", $event[$i], 3);

    if($dochanged) {
      if($vn eq "state") {
        $hash->{STATE} = $vv;
        push @changed, $vv;

      } else {
        push @changed, "$vn: $vv";

      }
    }

    $hash->{READINGS}{$vn}{TIME} = TimeNow();
    $hash->{READINGS}{$vn}{VAL} = $vv;
  }
  $hash->{CHANGED} = \@changed;
  
  return $name;
}

1;
