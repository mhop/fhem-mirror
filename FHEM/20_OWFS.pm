################################################################
#
#  Copyright notice
#
#  (c) 2008 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use OW;

my %models = (
  "DS1420"     => "",
  "DS9097"     => "",
);
my %fc = (
  "1:DS9420"   => "01",
  "2:DS1420"   => "81",
  "3:DS1820"   => "10",
);

my %gets = (
  "address"     => "",
  "alias"       => "",
  "crc8"        => "",
  "family"      => "",
  "id"          => "",
  "locator"     => "",
  "present"     => "",
#  "r_address"   => "",
#  "r_id"        => "",
#  "r_locator"   => "",
  "type"        => "",
);

##############################################
sub
OWFS_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{WriteFn}    = "OWFS_Write";
  $hash->{Clients}    = ":OWTEMP:";

# Normal devices
  $hash->{DefFn}      = "OWFS_Define";
  $hash->{UndefFn}    = "OWFS_Undef";
  $hash->{GetFn}      = "OWFS_Get";
  #$hash->{SetFn}      = "OWFS_Set";
  $hash->{AttrList}   = "do_not_notify:1,0 dummy:1,0 temp-scale:C,F,K,R " .
                        "showtime:1,0 loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
OWFS_Get($$)
{
  my ($hash,@a) = @_;

  return "argument is missing @a" if (@a != 2);
  return "Passive Adapter defined. No Get function implemented."
    if(!defined($hash->{OW_ID}));
  return "Unknown argument $a[1], choose one of " . join(",", sort keys %gets)
    if(!defined($gets{$a[1]}));

  my $ret = OWFS_GetData($hash,$a[1]);

  return "$a[0] $a[1] => $ret"; 
}

#####################################
sub
OWFS_GetData($$)
{
  my ($hash,$query) = @_;
  my $name = $hash->{NAME};
  my $path = $hash->{OW_PATH};
  my $ret = undef;
  
  $ret = OW::get("/uncached/$path/$query");
  if ($ret) {
    # strip spaces
    $ret =~ s/^\s+//g;
    Log 4, "OWFS $name $query $ret";
    $hash->{READINGS}{$query}{VAL} = $ret;
    $hash->{READINGS}{$query}{TIME} = TimeNow();
    return $ret;
  } else {
    return undef;
  }
}

#####################################
sub
OWFS_DoInit($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $path;
  my $ret;

  if (defined($hash->{OWFS_ID})) {
    $path = $hash->{OW_FAMILY}.".".$hash->{OWFS_ID};
 
    foreach my $q (sort keys %gets) {
      $ret = OWFS_GetData($hash,$q);
    }
  }

  $hash->{STATE} = "Initialized" if (!$hash->{STATE});  
  return undef;
}

#####################################
sub
OWFS_Define($$)
{
  my ($hash, $def) = @_;

  # define <name> OWFS <owserver:port> <model> <id>
  # define foo OWFS 127.0.0.1:4304 DS1420 93302D000000

  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> OWFS <owserver:port> <model> [<id>]"
    if (@a < 2 && int(@a) > 5);

  my $name  = $a[0];
  my $dev   = $a[2];
#  return "wrong device format: use ip:port"
#    if ($device !~ m/^(.+):(0-9)+$/);

  my $model = $a[3];
  return "Define $name: wrong model: specify one of " . join ",", sort keys %models
    if (!grep { $_ eq $model } keys %models);

  if (@a > 4) {
    my $id     = $a[4];
    return "Define $name: wrong ID format: specify a 12 digit value"
      if (uc($id) !~ m/^[0-9|A-F]{12}$/); 

    $hash->{FamilyCode} = \%fc;
    my $fc = $hash->{FamilyCode};
    if (defined ($fc)) {
      foreach my $c (sort keys %{$fc}) {
        if ($c =~ m/$model/) {
          $hash->{OW_FAMILY} = $fc->{$c};
        }
      }
    }
    delete ($hash->{FamilyCode});
    $hash->{OW_ID} = $id;
    $hash->{OW_PATH} = $hash->{OW_FAMILY}.".".$hash->{OW_ID};
  }

  $hash->{STATE} = "Defined";

  # default temperature-scale: C
  # C: Celsius, F: Fahrenheit, K: Kelvin, R: Rankine
  $attr{$name}{"temp-scale"} = "C";

  if ($dev eq "none") {
    $attr{$name}{dummy} = 1;
    Log 1, "OWFS device is none, commands will be echoed only";
    return undef;
  }

  Log 3, "OWFS opening OWFS device $dev";

  my $po;
  $po = OW::init($dev);

  return "Can't connect to $dev: $!" if(!$po);

  Log 3, "OWFS opened $dev for $name";

  $hash->{DeviceName} = $dev;
  $hash->{STATE}="";
  my $ret  = OWFS_DoInit($hash);
  return undef;
}

#####################################
sub
OWFS_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if (defined($defs{$d}) && defined($defs{$d}{IODev}) && $defs{$d}{IODev} == $hash) {
      my $lev = ($reread_active ? 4 : 2);
      Log GetLogLevel($name,$lev), "deleting port for $d";
      delete $defs{$d}{IODev};
    }
  }
  return undef;
}

1;
