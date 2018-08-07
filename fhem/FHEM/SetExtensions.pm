##############################################
# $Id$

package main;
use strict;
use warnings;

sub SetExtensions($$@);
sub SetExtensionsFn($);

sub
SetExtensionsCancel($)
{
  my ($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );
  return undef if( $hash->{InSetExtensions} );
  my $name = $hash->{NAME};

  if($hash->{TIMED_OnOff}) {      # on-for-timer, blink
    my $cmd = $hash->{TIMED_OnOff}{CMD};
    RemoveInternalTimer("SE $name $cmd");
    delete $hash->{TIMED_OnOff};
  }

  for my $sfx ("_till", "_intervalFrom", "_intervalNext") {
    CommandDelete(undef, $name.$sfx) if($defs{$name.$sfx});
  }
  return undef;
}

sub
SE_DoSet(@)
{
  my $hash = $defs{$_[0]};
  $hash->{InSetExtensions} = 1;
  AnalyzeCommand($hash->{CL}, "set ".join(" ", @_)); # cmdalias (Forum #63896)
  delete $hash->{InSetExtensions};
}

sub
SetExtensions($$@)
{
  my ($hash, $list, $name, $cmd, @a) = @_;

  return "Unknown argument $cmd, choose one of " if(!$list);

  my %se_list = (
    "on-for-timer"      => 1,
    "off-for-timer"     => 1,
    "on-till"           => 1,
    "off-till"          => 1,
    "on-till-overnight" => 1,
    "off-till-overnight"=> 1,
    "blink"             => 0,
    "intervals"         => 0,
    "toggle"            => 0
  );

  my $hasOn  = ($list =~ m/(^| )on\b/);
  my $hasOff = ($list =~ m/(^| )off\b/);
  my $eventMap = AttrVal($name, "eventMap", undef);

  if((!$hasOn || !$hasOff) && $eventMap) {
    if(!$hasOn) {
      my (undef,$value) = ReplaceEventMap($name, [$name, "on"], 0);
      $hasOn = ($value ne "on");
    }
    if(!$hasOff) {
      my (undef,$value) = ReplaceEventMap($name, [$name, "off"], 0);
      $hasOff = ($value ne "off");
    }
  }

  if(!$hasOn || !$hasOff) { # No extension
    return "Unknown argument $cmd, choose one of $list";
  }

  if(!defined($se_list{$cmd})) {
    # Add only "new" commands
    my @mylist = grep { $list !~ m/\b$_\b/ } keys %se_list;
    return "Unknown argument $cmd, choose one of $list " .
        join(" ", @mylist);
  }
  if($se_list{$cmd} && $se_list{$cmd} != int(@a)) {
    return "$cmd requires $se_list{$cmd} parameter";
  }

  SetExtensionsCancel($hash);
  my $cmd1 = ($cmd =~ m/^on.*/ ? "on" : "off");
  my $cmd2 = ($cmd =~ m/^on.*/ ? "off" : "on");
  my $param = $a[0];


  if($cmd eq "on-for-timer" || $cmd eq "off-for-timer") {
    return "$cmd requires a number as argument" if($param !~ m/^\d*\.?\d*$/);

    if($param) {
      $hash->{TIMED_OnOff} = {
        START=>time(), START_FMT=>TimeNow(), DURATION=>$param,
        CMD=>$cmd, NEXTCMD=>$cmd2
      };
      SE_DoSet($name, $cmd1);
      InternalTimer(gettimeofday()+$param,"SetExtensionsFn","SE $name $cmd",0);
    }

  } elsif($cmd =~ m/^(on|off)-till/) {
    my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($param);
    return "$cmd: $err" if($err);

    my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
    if($cmd =~ m/-till$/) {
      my @lt = localtime;
      my $hms_now  = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
      if($hms_now ge $hms_till) {
        Log3 $hash, 4,
          "$name $cmd: won't switch as now ($hms_now) is later than $hms_till";
        return "";
      }
      if($hms_till ge "24") { # sunrise, #89985
        Log3 $hash, 4, "$name $cmd: won't switch as $hms_till is tomorrow";
        return "";
      }
    }
    SE_DoSet($name, $cmd1);
    CommandDefine(undef, "${name}_till at $hms_till set $name $cmd2");

  } elsif($cmd eq "blink") {
    my $p2 = $a[1];
    return "$cmd requires 2 numbers as argument"
        if($param !~ m/^\d+$/ || $p2 !~ m/^\d*\.?\d*$/);

    if($param) {
      SE_DoSet($name, $a[2] ? "off" : "on");
      $param-- if($a[2]);
      if($param) {
        $hash->{TIMED_OnOff} = {
          START=>time(), START_FMT=>TimeNow(), DURATION=>$param,
          CMD=>$cmd, NEXTCMD=>"$cmd $param $p2 ".($a[2] ? "0" : "1")
        };
        InternalTimer(gettimeofday()+$p2, "SetExtensionsFn","SE $name $cmd",0);
      }
    }

  } elsif($cmd eq "intervals") {

    my $intSpec = shift(@a);
    if($intSpec) {
      my ($from, $till) = split("-", $intSpec);

      my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($from);
      return "$cmd: $err" if($err);
      my @lt = localtime;
      my $hms_from = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
      my $hms_now  = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);

      if($hms_from le $hms_now) { # By slight delays at will schedule tomorrow.
        SetExtensions($hash, $list, $name, "on-till", $till);

      } else {
        CommandDefine(undef,
                "${name}_intervalFrom at $from set $name on-till $till");

      }

      if(@a) {
        my $rest = join(" ", @a);
        my ($from, $till) = split("-", shift @a);
        CommandDefine(undef,
                "${name}_intervalNext at $from set $name intervals $rest");
      }
    }
    
  } elsif($cmd eq "toggle") {
    my $value = Value($name);
    (undef,$value) = ReplaceEventMap($name, [$name, $value], 0) if($eventMap);

    $value = ($1==0 ? "off" : "on") if($value =~ m/dim (\d+)/); # Forum #49391
    SE_DoSet($name, $value =~ m/^on/ ? "off" : "on");

  }

  return undef;
}

sub
SetExtensionsFn($)
{
  my (undef, $name, $cmd) = split(" ", shift, 3);
  my $hash = $defs{$name};
  return if(!$hash || !$hash->{TIMED_OnOff});

  my $nextcmd = $hash->{TIMED_OnOff}{NEXTCMD};
  delete $hash->{TIMED_OnOff};
  SE_DoSet($name, split(" ",$nextcmd));
}

1;
