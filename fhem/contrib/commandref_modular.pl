#!/usr/bin/perl

# $Id$

use strict;
use warnings;

my @lang = ("EN", "DE");
my $modDir = "FHEM";
my $now = time();

for my $lang (@lang) {
  my $sfx = ($lang eq "EN" ? "" : "_$lang");
  my %modData;
  my $cmdref = "docs/commandref_frame$sfx.html";

  open(FH, $cmdref) || die("Cant open $cmdref: $!\n");
  my $type = "";
  while(my $l = <FH>) {
    if($l =~ m/<!-- header:(.*) -->/) {
      $type = $1; next;
    }
    if($type && $l =~ m/<a href="#([^"]+).*<!--(.*)-->/) {
      $modData{$1}{type} = $type;
      $modData{$1}{"summary$sfx"} = $2;
      $modData{$1}{ts} = $now;
    } else {
      $type = "";
    }
  }
  close(FH);

  $cmdref = "docs/commandref${sfx}.html";
  if(open(FH, $cmdref)) {
    my $cmptime = (stat($cmdref))[9];
    my $type = "device";
    while(my $l = <FH>) {
      $type = $1 if($l =~ m,<!-- header:(.*) -->,);
      if($l =~ m,<td class='modname'><a href='#'>(.*)</a></td><td>(.*)</td>, &&
         !$modData{$1}) {     # commandref_frame has prio
        $modData{$1}{type} = $type;
        $modData{$1}{"summary$sfx"} = $2;
        $modData{$1}{ts} = $cmptime;
      }
    }
    close(FH);
  }

  opendir(DH, $modDir) || die "Cant open $modDir: $!\n";
  while(my $fName = readdir DH) {
    next if($fName !~ m/^\d\d_(.*)\.pm$/);
    my $mName = $1;
    my $ts = (stat("$modDir/$fName"))[9];
    if(!$modData{$mName} || !$modData{$mName}{ts} || $modData{$mName}{ts}<$ts) {
      print "Checking $fName for $lang short description\n";

      $modData{$mName}{type}="device" if(!$modData{$mName}{type});
      open(FH, "$modDir/$fName") || die("Cant open $modDir/$fName: $!\n");
      while(my $l = <FH>) {
        $modData{$mName}{type}=$1 if($l =~ m/^=item\s+(helper|command|device)/);
        $modData{$mName}{$1}  =$2 if($l =~ m/^=item\s+(summary[^ ]*)\s(.*)$/);
      }
      close(FH);
    }
  }
  closedir(DH);

  $cmdref = "docs/commandref_frame${sfx}.html";
  open(IN, $cmdref) || die("Cant open $cmdref: $!\n");

  $cmdref = ">docs/commandref${sfx}.html";
  open(OUT, $cmdref) || die("Cant open $cmdref: $!\n");
  
  while(my $l = <IN>) {

    print OUT $l;
    if($l =~ m,\s*<title>,) {
      print OUT << 'EOF'
  <script type="text/javascript" src="../pgm2/jquery.min.js"></script>
  <script type="text/javascript" src="../pgm2/fhemdoc_modular.js"></script>
EOF
    }

    if($l =~ m,<!-- header:(.*) -->,) {
      my $type = $1;
      while(my $l = <IN>) {
        last if($l !~ m/<a href="/);
      }
      print OUT "<table class='block summary class_$type'>\n";
      my $rc = "odd";
      for my $m (sort {uc($a) cmp uc($b)} keys %modData) {
        next if(!$modData{$m}{type} || $modData{$m}{type} ne $type);
        my $d = $modData{$m}{"summary$sfx"};
        if(!$d) {
          my $osfx = ($lang eq "DE" ? "" : "_DE");
          $d = $modData{$m}{"summary$sfx"};
          if(!$d) {
            $d = "keine Kurzbeschreibung vorhanden" if($lang eq "DE");
            $d = "no short description available"   if($lang eq "EN");
          }
        }
        print OUT "<tr class='$rc'><td class='modname'><a href='#'>$m</a></td>".
                                  "<td>$d</td><tr>\n";
        $rc = ($rc eq "odd" ? "even" : "odd");
      }
      print OUT "</table>\n";
    }

  }
}
