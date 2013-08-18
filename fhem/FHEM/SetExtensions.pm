##############################################
# $Id$

package main;
use strict;
use warnings;

sub SetExtensions($$@);
sub SetExtensionsFn($);

sub
SetExtensions($$@)
{
  my ($hash, $list, $name, $cmd, @a) = @_;

  my %se_list = (
    "on-for-timer"  => 1,
    "off-for-timer" => 1,
    "on-till"       => 1,
    "off-till"      => 1,
    "blink"         => 2,
    "intervals"     => 0,
  );

  my $hasOn  = ($list =~ m/\bon\b/);
  my $hasOff = ($list =~ m/\boff\b/);
  if(!$hasOn || !$hasOff) {
    my $em = AttrVal($name, "eventMap", undef);
    if($em) {
      $hasOn  = ($em =~ m/:on\b/)  if(!$hasOn);
      $hasOff = ($em =~ m/:off\b/) if(!$hasOff);
    }
    $cmd = ReplaceEventMap($name, $cmd, 1) if($cmd ne "?"); # Fix B0-for-timer
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

  my $cmd1 = ($cmd =~ m/on.*/ ? "on" : "off");
  my $cmd2 = ($cmd =~ m/on.*/ ? "off" : "on");
  my $param = $a[0];

  if($cmd eq "on-for-timer" || $cmd eq "off-for-timer") {
    RemoveInternalTimer("SE $name $cmd");
    return "$cmd requires a number as argument" if($param !~ m/^\d*\.?\d*$/);

    if($param) {
      DoSet($name, $cmd1);
      InternalTimer(gettimeofday()+$param,"SetExtensionsFn","SE $name $cmd",0);
    }

  } elsif($cmd eq "on-till" || $cmd eq "off-till") {
    my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($param);
    return "$cmd: $err" if($err);

    my $at = $name . "_till";
    CommandDelete(undef, $at) if($defs{$at});

    my @lt = localtime;
    my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
    my $hms_now  = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
    if($hms_now ge $hms_till) {
      Log $hash, 4,
        "$cmd: won't switch as now ($hms_now) is later than $hms_till";
      return "";
    }
    DoSet($name, $cmd1);
    CommandDefine(undef, "$at at $hms_till set $name $cmd2");

  } elsif($cmd eq "blink") {
    my $p2 = $a[1];
    delete($hash->{SE_BLINKPARAM});
    return "$cmd requires 2 numbers as argument"
        if($param !~ m/^\d+$/ || $p2 !~ m/^\d*\d?\d*$/);

    if($param) {
      DoSet($name, "on-for-timer", $p2);
      $param--;
      if($param) {
        $hash->{SE_BLINKPARAM} = "$param $p2";
        InternalTimer(gettimeofday()+2*$p2,"SetExtensionsFn","SE $name $cmd",0);
      }
    }

  } elsif($cmd eq "intervals") {
    my $at0 = "${name}_till";
    my $at1 = "${name}_intervalFrom",
    my $at2 = "${name}_intervalNext";
    CommandDelete(undef, $at0) if($defs{$at0});
    CommandDelete(undef, $at1) if($defs{$at1});
    CommandDelete(undef, $at2) if($defs{$at2});

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
        CommandDefine(undef, "$at1 at $from set $name on-till $till");

      }

      if(@a) {
        my $rest = join(" ", @a);
        my ($from, $till) = split("-", shift @a);
        CommandDefine(undef, "$at2 at $from set $name intervals $rest");
      }
    }
    
  }

  return undef;
}

sub
SetExtensionsFn($)
{
  my (undef, $name, $cmd) = split(" ", shift, 3);
  return if(!defined($defs{$name}));


  if($cmd eq "on-for-timer") {
    DoSet($name, "off");

  } elsif($cmd eq "off-for-timer") {
    DoSet($name, "on");

  } elsif($cmd eq "blink") {
    DoSet($name, "blink", split(" ", $defs{$name}{SE_BLINKPARAM}, 2));

  }

}

1;
