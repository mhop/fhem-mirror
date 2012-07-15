##############################################
package main;

use strict;
use warnings;

my @zwave_models = qw(
  Ever
);

sub
ZWave_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}     = "^........ ...*";
  $hash->{SetFn}     = "ZWave_Set";
  $hash->{DefFn}     = "ZWave_Define";
  $hash->{ParseFn}   = "ZWave_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ".
                       "ignore:1,0 dummy:1,0 showtime:1,0 ".
                       "loglevel:0,1,2,3,4,5,6 " .
                       "model:".join(",", sort @zwave_models);
}

my %zwave_classes = (
  'AV_CONTROL_POINT'  => {} ,
  'DISPLAY'           => {} ,
  'GARAGE_DOOR'       => {} ,
  'THERMOSTAT'        => {} ,
  'WINDOW_COVERING'   => {} ,
  'REPEATER_SLAVE'    => {} ,
  'SWITCH_BINARY'     => { 
        set => { "off" => "13%02x0320010005",
                 "on"  => "13%02x032001FF05", },
        parse => { "03250300" => "state:off",
                   "032503ff" => "state:on" }, } ,
  'SWITCH_MULTILEVEL' => {} ,
  'SWITCH_REMOTE'     => {} ,
  'SWITCH_TOGGLE'     => {} ,
  'SENSOR_BINARY'     => {} ,
  'SENSOR_MULTILEVEL' => {
      parse => { "0832022112(....)0000" => '"power:".hex($1)." W"' }, },
  'WATER_CONTROL'     => {} ,
  'METER_PULSE'       => {} ,
  'ENTRY_CONTROL'     => {} ,
);


#############################
sub
ZWave_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> ZWave homeId id class [class...]";
  return $u if(int(@a) < 4);

  my $name   = shift @a;
  my $type = shift(@a); # always ZWave
  my $homeId = lc(shift @a);
  my $id     = shift @a;

  return "define $name: wrong homeId ($homeId): need an 8 digit hex value"
              if( ($homeId !~ m/^[a-f0-9]{8}$/i) );
  return "define $name: wrong id ($id): need a number"
              if( ($id !~ m/^\d+$/i) );
  foreach my $cl (@a) {
    return "define $name: unknown class $cl" if(!$zwave_classes{uc($cl)});
  }

  $id = sprintf("%02x", $id);
  $hash->{HomeId} = $homeId;
  $hash->{Id}     = $id;
  $hash->{Classes} = uc(join(" ", @a));

  $modules{ZWave}{defptr}{"$homeId $id"} = $hash;
  AssignIoPort($hash);  # FIXME: should take homeId into account
}

###################################
sub
ZWave_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;

  return "no set value specified" if(int(@a) < 2);
  my $name = shift(@a);
  my $cmd  = shift(@a);

  # Collect the commands from the distinct classes
  my %cmdList;
  foreach my $cl (split(" ", $hash->{Classes})) {
    my $ptr = $zwave_classes{$cl}{set} if($zwave_classes{$cl}{set});
    next if(!$ptr);
    foreach my $k (keys %{$ptr}) {
      $cmdList{$k} = $ptr->{$k};
    }
  }
  return ("Unknown argument $cmd, choose one of ".join(" ",sort keys %cmdList))
    if(!$cmdList{$cmd});

  my $cmdOut = sprintf($cmdList{$cmd}, $hash->{Id}, @a);
  IOWrite($hash, "00", $cmdOut);

  $cmd .= " ".join(" ", @a) if(@a);
  my $tn = TimeNow();

  $hash->{CHANGED}[0] = $cmd;
  $hash->{STATE} = $cmd;
  $hash->{READINGS}{state}{TIME} = $tn;
  $hash->{READINGS}{state}{VAL} = $cmd;

  return undef;
}


sub
ZWave_Parse($$)
{
  my ($hash, $msg) = @_;

  my ($homeId, $pmsg) = split(" ", $msg, 2);
  return "" if($pmsg !~ m/^000400(..)(.*)$/); # Ignore unknown commands for now
  my ($id, $p) = ($1, $2);

  my $def = $modules{ZWave}{defptr}{"$homeId $id"};
  if($def) {
    Log 1, "Got $p";

    my @event;
    my @changed;
    my $tn = TimeNow();

    foreach my $cl (split(" ", $def->{Classes})) {
      my $ptr = $zwave_classes{$cl}{parse} if($zwave_classes{$cl}{parse});
      next if(!$ptr);
      foreach my $k (keys %{$ptr}) {
        if($p =~ m/$k/) {
          my $val = $ptr->{$k};
          $val = eval $val if(index($val, '$') >= 0);
          push @event, $val;
        }
      }
    }

    return "" if(!@event);

    for(my $i = 0; $i < int(@event); $i++) {
      next if($event[$i] eq "");
      my ($vn, $vv) = split(":", $event[$i], 2);
      if($vn eq "state") {
        $def->{STATE} = $vv;
        push @changed, $vv;

      } else {
        push @changed, "$vn: $vv";

      }
      $def->{READINGS}{$vn}{TIME} = $tn;
      $def->{READINGS}{$vn}{VAL} = $vv;
    }
    $def->{CHANGED} = \@changed;
    return $def->{NAME};


  } else {
    Log 3, "ZWave unknown device $homeId $id, please define it";

  }
  return "";

}

1;
