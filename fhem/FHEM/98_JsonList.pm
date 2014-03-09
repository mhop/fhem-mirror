################################################################
# $Id$
#
#  Copyright notice
#
#  (c) 2008 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
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
  return if($h->{PrintHashJson});

  my $hc = keys %{$h};
  my @str;
  foreach my $c (sort keys %{$h}) {

    my $str = "";
    if(ref($h->{$c})) {
      if(ref($h->{$c}) eq "HASH" && $c ne "PortObj") {
        if($c eq "IODev" || $c eq "HASH") {
          $str .= sprintf("%*s\"%s\": \"%s\"", $lev," ",$c, JsonEscape($h->{$c}{NAME}));
        } else {
          $str .= sprintf("%*s\"%s\": {\n", $lev, " ", $c);
          if(keys(%{$h->{$c}}) != 0) {
            $h->{PrintHashJson} = 1;
            $str .= PrintHashJson($h->{$c}, $lev+2);
            delete($h->{PrintHashJson});
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
    push @str, $str if($str);
  }

  return join(",\n", @str) . "\n";
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

    # open JSON object 
    $str = "{\n";
    $str .= sprintf("%*s\"ResultSet\": \"%s\",\n", $lev, " ","full");
    # open JSON array
    $str .= sprintf("%*s\"Results\": [\n", $lev, " ");

    delete($modules{""}) if(defined($modules{""}));
    @dc = keys(%defs);
    $dc = @dc;
    #$tc = 0;
    for my $d (sort { my $x = $modules{$defs{$a}{TYPE}}{ORDER} cmp
                              $modules{$defs{$b}{TYPE}}{ORDER};
                         $x = ($a cmp $b) if($x == 0); $x; } keys %defs) {

      my $p = $defs{$d};
      my $t = $p->{TYPE};
      if(!$t) {
        Log3 undef, 3, "JsonList: device ($d) without TYPE";
        next;
      }
      $t = $q if($q ne "");

      #$str .= sprintf("} ") if($t eq $lt);
      #$str .= sprintf("},\n") if($t eq $lt);
      #$str .= sprintf("%*s},\n", $lev+6, " ") if($t eq $lt);

      my $a1 = JsonEscape($p->{STATE});
      # close device object
      $str .= sprintf("%*s},\n", $lev+6, " ") if($t eq $lt);

      if($t ne $lt) {
        # close device opject
        $str .= sprintf("%*s}\n", $lev+6, " ") if($lt && $t ne $lt);
        #$str .= sprintf("}\n") if($lt);

        # close devices array
        $str .= sprintf("%*s]\n", $lev+4, " ") if($lt);

        # close list object
        $str .= sprintf("%*s},\n", $lev+2, " ") if($lt);

       	#$str .= sprintf("%*s{\n", $lev+4, " ");
        # open  list object
        $str .= sprintf("%*s\{\n", $lev+2, " ");
        $str .= sprintf("%*s\"%s\": \"%s\",\n", $lev+4, " ", "list", $t);

        # open devices array
        $str .= sprintf("%*s\"%s\": [\n", $lev+4, " ", "devices");
      }

      $lt = $t;

      #$str .= sprintf("%*s{\n", $lev+8, " ");

      # open device object
      $str .= sprintf("%*s{\n", $lev+6, " ");

      #$str .= sprintf("%*s\"name\": \"%s\",\n", $lev+8, " ", $d);
      #$str .= sprintf("%*s\"state\": \"%s\",\n", $lev+8, " ", $a1);
      #$str .= sprintf("\"INT\": { ");
      @ac = keys(%{$p});
      $ac = 0;
      foreach my $k (sort @ac) {
        next if(ref($p->{$k}));
        $ac++;
      }
      $cc = 0;

      foreach my $c (sort keys %{$p}) {
        next if(ref($p->{$c}));
        $str .= sprintf("%*s\"%s\": \"%s\",\n", $lev+8, " ",
                        JsonEscape($c), JsonEscape($p->{$c}));
        $cc++;
        #$str .= ",\n" if($cc != $ac || ($cc == $ac && $p->{IODev}));
        #$str .= ",\n" if($cc != $ac || ($cc == $ac && $p->{IODev}));
        #$str .= "\n" if($cc == $ac && !$p->{IODev});
      }
      $str .= sprintf("%*s\"IODev\": \"%s\",\n", $lev+8, " ",
                      $p->{IODev}{NAME}) if($p->{IODev});
      #$str .= sprintf(" }, ");

      @ac = keys(%{$attr{$d}});
      $ac = @ac;
      $cc = 0;
      if($ac != 0) {
        $str .= sprintf("%*s\"ATTR\": {\n", $lev+8, " ");
        foreach my $c (sort keys %{$attr{$d}}) {
          $str .= sprintf("%*s\"%s\": \"%s\"", $lev+10, " ",
                          JsonEscape($c), JsonEscape($attr{$d}{$c}));
          $cc++;
          #$str .= ",\n" if($cc != $ac);
          $str .= ",\n" if($cc != $ac);
          #$str .= "\n" if($cc == $ac);
        }
        $str .= "\n";
        #$str .= sprintf("%*s]\n", $lev+8, " ") if(!$p->{READINGS});
        #$str .= sprintf("%*s],\n", $lev+8, " ") if($p->{READINGS});
        $str .= sprintf("%*s},\n", $lev+8, " ");
      } else {
        $str .= sprintf("%*s\"ATTR\": {},\n", $lev+8, " ");
      }
      #$str .= sprintf("%*s],\n", $lev+8, " ") if($p->{READINGS});
      #$str .= sprintf("%*s]\n", $lev+8, " ") if(!$p->{READINGS});

      my $r = $p->{READINGS};
      if($r) {
        $str .= sprintf("%*s\"READINGS\": [\n", $lev+8, " ");
        @ac = keys(%{$r});
        $ac = @ac;
        $cc = 0;
        foreach my $c (sort keys %{$r}) {
          $str .= sprintf("%*s{\n", $lev+10, " ");
	  $str .= sprintf("%*s\"%s\": \"%s\",\n", $lev+12, " ", JsonEscape($c), JsonEscape($r->{$c}{VAL}));
          $str .= sprintf("%*s\"measured\": \"%s\"\n", $lev+12, " ", $r->{$c}{TIME});
          $cc++;
          #$str .= ",\n" if($cc != $ac);
          $str .= sprintf("%*s},\n", $lev+10, " ") if($cc != $ac);
          $str .= sprintf("%*s}\n", $lev+10, " ") if($cc == $ac);
        }
        $str .= sprintf("%*s],\n", $lev+8, " ");
      } else {
        $str .= sprintf("%*s\"READINGS\": [],\n", $lev+8, " ");
      }


      # corresponding set parameters
      $str .= sprintf("%*s\"sets\": [\n", $lev+6, " ");
      my $sets = getAllSets($d);
      if($sets) {
        my @pSets;
        foreach my $set (split(" ", JsonEscape($sets))) {
          push @pSets, sprintf("%*s\"%s\"", $lev+8, " ", $set);
        } 
        $str .= join(",\n", @pSets);
      }
      $str .= sprintf("\n%*s],\n", $lev+6, " ");

      # corresponding attributes
      $str .= sprintf("%*s\"attrs\": [\n", $lev+6, " ");
      my $attrs = getAllAttr($d);
      if($attrs) {
        my @aSets;
        foreach my $attr (split(" ", JsonEscape($attrs))) {
          push @aSets, sprintf("%*s\"%s\"", $lev+8, " ", $attr);
        }
        $str .= join(",\n", @aSets);
      }
      $str .= sprintf("\n%*s]\n", $lev+6, " ");

      $tc++;
      $tr = $tc if($q eq "");
      $tr++ if($q ne "" && $p->{TYPE} eq $t);
      $str .= sprintf("%*s}\n", $lev+6, " ") if(($tc == $dc) || (!$lt));
    }
    $str .= sprintf("%*s]\n", $lev+4, " ") if($lt);
    $str .= sprintf("%*s}\n", $lev+2, " ") if($lt);

    # close JSON array
    $str .= sprintf("%*s],\n", $lev, " ");

    # return number of results
    $str .= sprintf("%*s\"totalResultsReturned\": %s\n", $lev, " ",$tr);

    # close JSON object
    $str .= "}\n";

  } else {
    if($param eq "ROOMS") {
      my %rooms;
      foreach my $d (keys %attr) {
        my $r = $attr{$d}{room};
        map { $rooms{$_} = 1 } split(",", $r) if($r && $r ne "hidden");
      }
      my @rooms = sort keys %rooms;

      # Result counter
      my $c = 0;

      # Open JSON object
      $str .= "{\n";
      $str .= sprintf("%*s\"%s\": \"%s\",\n", $lev, " ", "ResultSet", "rooms");
      # Open JSON array
      $str .= sprintf("%*s\"%s\": [", $lev, " ", "Results");

      for (my $i=0; $i<@rooms; $i++) {
        $str .= "," if($i <= $#rooms && $i > 0);
        $str .= sprintf("\n%*s\"%s\"", $lev+2, " ", $rooms[$i]);
        $c++;
      }

      $str .= "\n";
      # Close JSON array
      $str .= sprintf("%*s],\n", $lev, " ");
      # Result summary
      #$str .= sprintf("%*s\"%s\": %s,\n", $lev, " ", "totalResultsAvailable", $c);
      $str .= sprintf("%*s\"%s\": %s\n", $lev, " ", "totalResultsReturned", $c);
      # Close JSON object
      $str .= "}";

    } else {
      # Search for given device-type
      my @devs = grep { $param eq $defs{$_}{TYPE} } keys %defs;

      if(@devs) {
        my $lt = "";
        my $ld = "";
        # Result counter
        my $c = 0;

        # Open JSON object
        $str .= "{\n";
        $str .= sprintf("%*s\"%s\": \"%s\",\n", $lev, " ", "ResultSet", "devices#$param");
        # Open JSON array
        $str .= sprintf("%*s\"%s\": [", $lev, " ", "Results");

        # Sort first by type then by name
        for my $d (sort { my $x = $modules{$defs{$a}{TYPE}}{ORDER} cmp
                                  $modules{$defs{$b}{TYPE}}{ORDER};
                             $x = ($a cmp $b) if($x == 0); $x; } keys %defs) {
          if($defs{$d}{TYPE} eq $param) {
            my $t = $defs{$d}{TYPE};
            $str .= sprintf("\n%*s},",$lev+2, " ") if($d ne $ld && $lt ne "");
            $str .= sprintf("\n%*s{",$lev+2, " ");
            $str .= sprintf("\n%*s\"name\": \"%s\",",$lev+4, " ", $d);
            $str .= sprintf("\n%*s\"state\": \"%s\"",$lev+4, " ", $defs{$d}{STATE});
            $lt = $t;
            $ld = $d;
            $c++;
          }
        }

        $str .= sprintf("\n%*s}\n",$lev+2, " ");
        # Close JSON array
        $str .= sprintf("%*s],\n", $lev, " ");
        # Result summary
        $str .= sprintf("%*s\"%s\": %s\n", $lev, " ", "totalResultsReturned", $c);
        # Close JSON object
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

=pod
=begin html

<a name="JsonList"></a>
<h3>JsonList</h3>
<ul>
  <b>Note</b>: this command is deprecated, use <a
  href="#JsonList2">jsonlist2</a> instead.<br><br>

  <code>jsonlist [&lt;devspec&gt;|&lt;typespec&gt;|ROOMS]</code>
  <br><br>
  Returns an JSON tree of all definitions, all notify settings and all at
  entries if no parameter is given. Can also be called via HTTP by
    http://fhemhost:8083/fhem?cmd=jsonlist&XHR=1
  <br><br>
  Example:
  <pre><code>  fhem> jsonlist
  {
    "ResultSet": "full",
    "Results": [
      {
        "list": "Global",
        "devices": [
          {
            "DEF": "<no definition>",
            "NAME": "global",
            "NR": "1",
            "STATE": "<no definition>",
            "TYPE": "Global",
            "currentlogfile": "/var/log/fhem/fhem-2011-12.log",
            "logfile": "/var/log/fhem/fhem-%Y-%m.log",
            "ATTR": {
              "configfile": "/etc/fhem/fhem.conf",
              "logfile": "/var/log/fhem/fhem-%Y-%m.log",
              "modpath": "/usr/share/fhem",
              "pidfilename": "/var/run/fhem.pid",
              "port": "7072 global",
              "room": "Server",
              "statefile": "/var/cache/fhem/fhem.save",
              "verbose": "4",
              "version": "=VERS= from =DATE= ($Id$)"
            },
            "READINGS": []
          }
        ]
      },
      {
      "list": "CM11",
        "devices": [
          {
            "DEF": "/dev/cm11",
            "DeviceName": "/dev/cm11",
            "FD": "14",
            "NAME": "CM11",
            "NR": "19",
            "PARTIAL": "null",
            "STATE": "Initialized",
            "TYPE": "CM11",
            "ATTR": {
              "model": "CM11"
            },
            "READINGS": []
          }
        ]
      },
      {
              [...placeholder for more entrys...]
      },
    ],
    "totalResultsReturned": 235
  }
  </code></pre>
  If specifying <code>&lt;devspec&gt;</code>, then a detailed status for
  <code>&lt;devspec&gt;</code>  will be displayed, e.g.:
  <pre><code>  fhem> jsonlist lamp1
  {
    "ResultSet": {
      "Results": {
        "ATTRIBUTES": {
          "alias": "Lamp on Sideboard",
          "model": "fs20st",
          "room": "Livingroom"
        },
        "BTN": "01",
        "CHANGED": "ARRAY",
        "CHANGETIME": "ARRAY",
        "CODE": {
          "1": "0b0b 01",
          "2": "0b0b 0f",
          "3": "0b0b f0",
          "4": "0b0b ff"
        },
        "DEF": "12341234 1112 lm 1144 fg 4411 gm 4444",
        "IODev": "CUN868",
        "NAME": "lamp1",
        "NR": "155",
        "READINGS": {
          "state": {
            "TIME": "2011-12-01 16:23:01",
            "VAL": "on"
          }
        },
        "STATE": "on",
        "TYPE": "FS20",
        "XMIT": "0b0b"
      }
    }
  }
  </code></pre>
  If specifying <code>&lt;typespec&gt;</code>, then a list with the status for
  the defined <code>&lt;typespec&gt;</code> devices will be displayed, e.g.:
  <pre><code>  fhem> jsonlist HMS
  {
    "ResultSet": "devices#HMS",
    "Results": [
      {
        "name": "KG.ga.WD.01",
        "state": "Water Detect: off"
      },
      {
        "name": "KG.hz.GD.01",
        "state": "Gas Detect: off"
      },
      {
        "name": "KG.k1.TF.01",
        "state": "T: 16.6  H: 51.2  Bat: ok"
      },
      {
        "name": "NN.xx.RM.xx",
        "state": "smoke_detect: off"
      }
    ],
    "totalResultsReturned": 4
  }
  </code></pre>
  If specifying <code>ROOMS</code>, then a list with the defined rooms
  will be displayed, e.g.:
  <pre><code>  fhem> jsonlist ROOMS
  {
    "ResultSet": "rooms",
    "Results": [
      "Bathroom",
      "Bedroom",
      "Children",
      "Diningroom",
      "Garden",
      "House",
      "Livingroom",
      "Office",
      "hidden"
    ],
    "totalResultsReturned": 15
  }
  </code></pre>
</ul>

=end html
=cut
