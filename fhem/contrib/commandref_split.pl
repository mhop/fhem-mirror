#!/usr/bin/perl

use strict;
use warnings;

my $docIn  = "docs/commandref.html";
my $docOut = "docs/commandref_frame.html";
my @modDir = ("FHEM", "contrib", "webfrontend/pgm5");

open(IN, "$docIn")    || die "Cant open $docIn: $!\n";
open(OUT, ">$docOut") || die "Cant open $docOut: $!\n";

my %mods;
foreach my $modDir (@modDir) {
  opendir(DH, $modDir) || die "Cant open $modDir: $!\n";
  while(my $l = readdir DH) {
    next if($l !~ m/^\d\d_.*\.pm$/);
    my $of = $l;
    $l =~ s/.pm$//;
    $l =~ s/^[0-9][0-9]_//;
    $mods{lc($l)} = "$modDir/$of" if(!$mods{lc($l)});
  }
}

my %fnd;
my $modFileName;
while(my $l = <IN>) {
  $l =~ s/[\r\n]//g;
  if($l =~ m,^<a name="(.*)"></a>$,) {
    if($modFileName) {
      print MODOUT "=end html\n=cut\n";
      close(MODOUT);
      rename "$modFileName.NEW", $modFileName;
    }
    my $mod = lc($1);
    if($mods{$mod}) {
      print "Double-Fnd: $mod\n" if($fnd{$mod});
      $fnd{$mod} = 1;
      $modFileName = $mods{$mod};
      open(MODIN, "$modFileName") || die("Cant open $modFileName: $!\n");
      open(MODOUT, ">$modFileName.NEW") || die("Cant open $modFileName.NEW: $!\n");
      my $seen1;
      while(my $l = <MODIN>) {
        $seen1 = 1 if($l =~ m/^1;[\r\n]*/);
        last if($l =~ m/=pod/ && $seen1);
        print MODOUT $l;
      }
      print MODOUT "\n\=pod\n=begin html\n\n";
    } else {
      print "Not a module: $mod\n";
      $modFileName = "";
    }
  }
  if($modFileName){
    print MODOUT "$l\n";
  } else {
    print OUT "$l\n";
  }
}

foreach my $mod (sort {$mods{$a} cmp $mods{$b}} keys %mods) {
  print "Missing doc for $mods{$mod}\n" if(!$fnd{$mod});
}
