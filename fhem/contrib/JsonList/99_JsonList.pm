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
# examples:
# jsonslist        - returns all definitions and status infos
# jsonlist lamp1   - returns definitions and status infos for 'lamp1' 
# jsonlist FS20    - returns status infos for FS20 devices
# jsonlist ROOMS   - returns a list of rooms
################################################################

package main;
use strict;
use warnings;
use POSIX;

sub CommandJsonList($$);
sub JsonEscape($);
sub PrintHashJson($$);


#####################################
sub
JsonList_Initialize($$)
{
  my %lhash = ( Fn=>"CommandJsonList",
                Hlp=>"[<devspec>|<devtype>|rooms],list definitions and status info or rooms as JSON" );
  $cmds{jsonlist} = \%lhash;
}


#####################################
sub
JsonEscape($)
{
  my $a = shift;
  return "null" if(!$a);
  my %esc = (
    "\n" => '\n',
    "\r" => '\r',
    "\t" => '\t',
    "\f" => '\f',
    "\b" => '\b',
    "\"" => '\"',
    "\\" => '\\\\',
    "\'" => '\\\'',
  );
  $a =~ s/([\x22\x5c\n\r\t\f\b])/$esc{$1}/eg;
  return $a;
}

#####################################
sub
PrintHashJson($$)
{
  my ($h, $lev) = @_;

  my ($str,$sstr) = ("","");

  my $hc = keys %{$h};
  my $cc = 1;

  foreach my $c (sort keys %{$h}) {

    if(ref($h->{$c})) {
      if(ref($h->{$c}) eq "HASH" && $c ne "PortObj") {
        if($c eq "IODev" || $c eq "HASH") {
          $str .= sprintf("%*s\"%s\": \"%s\"", $lev," ",$c, JsonEscape($h->{$c}{NAME}));
        } else {
          $str .= sprintf("%*s\"%s\": {\n", $lev, " ", $c);
          if(keys(%{$h->{$c}}) != 0) {
          $str .= PrintHashJson($h->{$c}, $lev+2);
          } else {
            $str .= sprintf("%*s\"null\": \"null\"\n", $lev+4, " ");
          }
          $str .= sprintf("%*s}", $lev, " ");
        }
      } elsif(ref($h->{$c}) eq "ARRAY") {
        $str .= sprintf("%*s\"%s\": \"%s\"", $lev," ",$c, "ARRAY");
      } elsif($c eq "PortObj") {
        $str .= sprintf("%*s\"%s\": \"%s\"", $lev," ",$c, "PortObj");
      }
    } else {
      $str .= sprintf("%*s\"%s\": \"%s\"", $lev," ",$c, JsonEscape($h->{$c}));
    }
    $str .= ",\n" if($cc != $hc);
    $str .= "\n" if($cc == $hc);
    $cc++;
  }

  return $str;
}

#####################################
sub
CommandJsonList($$)
{
  my ($cl, $param) = @_;
  my $lt = "";
  my $str = "";

  # Text indentation
  my $lev = 2;

  if(!$param) {
    # Array counter
    my @ac;
    my $ac = 0;
    my $cc = 0;
    my @dc;
    my $dc = 0;
    my $tc = 0; # total available
    my $tr = 0; # results returned

    my $q = "";

    # Open JSON object 
    $str = "{\n";
    $str .= sprintf("%*s\"ResultSet\": {\n", $lev, " ");
    # Open JSON array
    $str .= sprintf("%*s\"Results\": [\n", $lev+2, " ");

    delete($modules{""}) if(defined($modules{""}));
    @dc = keys(%defs);
    $dc = @dc;
    #$tc = 0;
    for my $d (sort { my $x = $modules{$defs{$a}{TYPE}}{ORDER} cmp
                              $modules{$defs{$b}{TYPE}}{ORDER};
                         $x = ($a cmp $b) if($x == 0); $x; } keys %defs) {

      my $p = $defs{$d};
      my $t = $p->{TYPE};
      $t = $q if($q ne "");

      $str .= sprintf("} ") if($t eq $lt);
      $str .= sprintf("},\n") if($t eq $lt);

      if($t ne $lt) {
        $str .= sprintf("} ") if($lt);
        $str .= sprintf("}\n") if($lt);
        $str .= sprintf("%*s]\n", $lev+6, " ") if($lt);
        $str .= sprintf("%*s},\n", $lev+4, " ") if($lt);
        #$str .= sprintf("%*s{\n", $lev+4, " ");
        $str .= sprintf("%*s\{ \"%s_LIST\": [\n", $lev+4, " ", $t);
      }
      $lt = $t;

      my $a1 = JsonEscape($p->{STATE});
      my $a2 = JsonEscape(getAllSets($d));
      my @sets;
      foreach my $k2 (split(" ", $a2)) {
        push @sets, $k2;
      }
      my $a3 = JsonEscape(getAllAttr($d));
      my @attrs;
      foreach my $k3 (split(" ", $a3)) {
        push @attrs, $k3;
      }

      #$str .= sprintf("%*s{\n", $lev+8, " ");
      $str .= sprintf("%*s{ \"%s\": { ", $lev+8, " ", $t);
      $str .= sprintf("\"name\": \"%s\", ", $d);
      $str .= sprintf("\"state\": \"%s\", ", $a1);
      $str .= sprintf("\"sets\": [ ");

      $ac = @sets;
      $cc = 0;
      foreach my $set (@sets) {
        $str .= sprintf("{ \"VAL\": \"%s\" }", $set);
        $cc++;
        #$str .= ",\n" if($cc != $ac);
        $str .= ", " if($cc != $ac);
        #$str .= "\n" if($cc == $ac);
      } 
      $str .= sprintf(" ], ");
      $str .= sprintf("\"attrs\": [ ");
      $ac = @attrs;
      $cc = 0;
      foreach my $attr (@attrs) {
        $str .= sprintf("{ \"VAL\": \"%s\" }", $attr);
        $cc++;
        #$str .= ",\n" if($cc != $ac);
        $str .= "," if($cc != $ac);
        #$str .= "\n" if($cc == $ac);
      } 
      $str .= sprintf(" ], ");

      $str .= sprintf("\"INT\": { ");
      @ac = keys(%{$p});
      $ac = 0;
      foreach my $k (sort @ac) {
        next if(ref($p->{$k}));
        $ac++;
      }
      $cc = 0;

      foreach my $c (sort keys %{$p}) {
        next if(ref($p->{$c}));
        $str .= sprintf("\"%s\": \"%s\"",
                        JsonEscape($c), JsonEscape($p->{$c}));
        $cc++;
        #$str .= ",\n" if($cc != $ac || ($cc == $ac && $p->{IODev}));
        $str .= ", " if($cc != $ac || ($cc == $ac && $p->{IODev}));
        #$str .= "\n" if($cc == $ac && !$p->{IODev});
      }
      $str .= sprintf("\"IODev\": \"%s\" ",
                      $p->{IODev}{NAME}) if($p->{IODev});
      $str .= sprintf(" }, ");

      $str .= sprintf("\"ATTR\": { ");
      @ac = keys(%{$attr{$d}});
      $ac = @ac;
      $cc = 0;
      foreach my $c (sort keys %{$attr{$d}}) {
        $str .= sprintf("\"%s\": \"%s\"",
                        JsonEscape($c), JsonEscape($attr{$d}{$c}));
        $cc++;
        #$str .= ",\n" if($cc != $ac);
        $str .= ", " if($cc != $ac);
        #$str .= "\n" if($cc == $ac);
      }
      $str .= sprintf(" }, ") if($p->{READINGS});
      $str .= sprintf(" } ") if(!$p->{READINGS});

      my $r = $p->{READINGS};
      if($r) {
        $str .= sprintf("\"STATE\": { ");
        @ac = keys(%{$r});
        $ac = @ac;
        $cc = 0;
        foreach my $c (sort keys %{$r}) {
	  $str .=
            sprintf("\"%s\": \"%s\", \"measured\": \"%s\"",
                   JsonEscape($c), JsonEscape($r->{$c}{VAL}), $r->{$c}{TIME});
            $cc++;
            #$str .= ",\n" if($cc != $ac);
            $str .= ", " if($cc != $ac);
            #$str .= "\n" if($cc == $ac);
        }
        $str .= sprintf(" } ");
      }
      $tc++;
      $tr = $tc if($q eq "");
      $tr++ if($q ne "" && $p->{TYPE} eq $t);
      $str .= sprintf("} ") if(($tc == $dc) || (!$lt));
      $str .= sprintf("}\n") if(($tc == $dc) || (!$lt));
      $str .= sprintf("%*s]\n", $lev+6, " ") if(($tc == $dc) || (!$lt));
    }
    $str .= sprintf("%*s}\n", $lev+4, " ") if($lt);
    $str .= sprintf("%*s],\n", $lev+2, " ");
    $str .= sprintf("%*s\"totalResultsAvailable\": %s,\n", $lev+2, " ",$tc);
    $str .= sprintf("%*s\"totalResultsReturned\": %s\n", $lev+2, " ",$tr);
    $str .= sprintf("%*s}\n", $lev, " ");
    $str .= "}";
  } else {
    if($param eq "ROOMS") {
      my @rooms;
      foreach my $d (sort keys %defs) {
        if($attr{$d}{"room"}) {
          push(@rooms, $attr{$d}{"room"}) unless(grep($_ eq $attr{$d}{"room"}, @rooms));
          next;
        }
      }
      @rooms = sort(@rooms);

      # Result counter
      my $c = 0;

      # Open JSON object
      $str .= "{\n";
      $str .= sprintf("%*s\"%s\": {\n", $lev, " ", "ResultSet");
      # Open JSON array
      $str .= sprintf("%*s\"%s\": [", $lev+2, " ", "Results");

      for (my $i=0; $i<@rooms; $i++) {
        $str .= " }," if($i <= $#rooms && $i > 0);
        $str .= sprintf("\n%*s{ \"NAME\": \"%s\"", $lev+4, " ", $rooms[$i]);
        $c++;
      }

      $str .= " }\n";
      # Close JSON array
      $str .= sprintf("%*s],\n", $lev+2, " ");
      # Result summary
      $str .= sprintf("%*s\"%s\": %s,\n", $lev+2, " ", "totalResultsAvailable", $c);
      $str .= sprintf("%*s\"%s\": %s\n", $lev+2, " ", "totalResultsReturned", $c);
      # Close JSON object
      $str .= sprintf("%*s}\n", $lev, " ");
      $str .= "}";

    } else {
      # Search for given device-type
      my $listDev = "";
      foreach my $d (sort { my $x = $defs{$a}{TYPE} cmp
                                    $defs{$b}{TYPE};
                               $x = ($a cmp $b) if($x == 0); $x; } keys %defs) {
        if($param eq $defs{$d}{TYPE}) {
          $listDev = $defs{$d}{TYPE};
          next;
        }
      }

      # List devices by type
      if($listDev ne "") {
        my $lt = "";
        my $ld = "";
        # Result counter
        my $c = 0;

        # Open JSON object
        $str .= "{\n";
        $str .= sprintf("%*s\"%s\": {\n", $lev, " ", "ResultSet");
        # Open JSON array
        $str .= sprintf("%*s\"%s\": [", $lev+2, " ", "Results");

        # Sort first by type then by name
        for my $d (sort { my $x = $modules{$defs{$a}{TYPE}}{ORDER} cmp
                                  $modules{$defs{$b}{TYPE}}{ORDER};
                             $x = ($a cmp $b) if($x == 0); $x; } keys %defs) {
          if($defs{$d}{TYPE} eq $param) {
            my $t = $defs{$d}{TYPE};
            $str .= " }," if($d ne $ld && $lt ne "");
            $str .= sprintf("\n%*s{ \"NAME\": \"%s\", \"STATE\": \"%s\"",
                             $lev+4, " ", $d, $defs{$d}{STATE});
            $lt = $t;
            $ld = $d;
            $c++;
          }
        }

        $str .= " }\n";
        # Close JSON array
        $str .= sprintf("%*s],\n", $lev+2, " ");
        # Result summary
        $str .= sprintf("%*s\"%s\": %s,\n", $lev+2, " ", "totalResultsAvailable", $c);
        $str .= sprintf("%*s\"%s\": %s\n", $lev+2, " ", "totalResultsReturned", $c);
        # Close JSON object
        $str .= sprintf("%*s}\n", $lev, " ");
        $str .= "}";

      } else {
        # List device
        foreach my $sdev (devspec2array($param)) {
          if(!defined($defs{$sdev})) {
            $str .= "No device named or type $param found, try <list> for all devices";
            next;
          }
          $defs{$sdev}{"ATTRIBUTES"} = $attr{$sdev};
          # Open JSON object
          $str = "{\n";
          $str .= sprintf("%*s\"%s\": {\n", $lev, " ", "ResultSet");
          # Open JSON array
          $str .= sprintf("%*s\"%s\": {\n", $lev+2, " ", "Results");
          $str .= PrintHashJson($defs{$sdev}, $lev+4);
          # Close JSON array
          $str .= sprintf("%*s}\n", $lev+2, " ");
          # Close JSON object
          $str .= sprintf("%*s}\n", $lev, " ");
          $str .= "}";
        }
      }
    }
  }
  return $str;
}

1;
