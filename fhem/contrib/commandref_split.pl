#!/usr/bin/perl

use strict;
use warnings;

my @lang = ("EN", "DE");
my @modDir = ("FHEM");

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


my %doc;
my %fnd;
my $modFileName;
foreach my $lang (@lang) {
  my $suffix = ($lang eq "EN" ? "" : "_$lang");

  my $docIn  = "docs/commandref$suffix.html";
  my $docOut = "docs/commandref_frame$suffix.html";
  #my @modDir = ("FHEM", "contrib", "webfrontend/pgm5");

  open(IN, "$docIn")    || die "Cant open $docIn: $!\n";
  open(OUT, ">$docOut") || die "Cant open $docOut: $!\n";

  my $content = "";
  my $skipping;

  while(my $l = <IN>) {
    $l =~ s/[\r\n]//g;
    if($l =~ m,^<a name="(.*)"></a>$,) {
      if($modFileName) {
        $doc{$modFileName}{$lang} = $content;
        $content = "";
      }
      my $mod = lc($1);
      if($mods{$mod}) {
        print "Double-Fnd: $mod\n" if($fnd{$mod});
        $fnd{$mod} = 1;
        $modFileName = $mods{$mod};
      } else {
        print "Not a module: $mod\n" if($lang eq "EN");
        $modFileName = "";
      }
    }
    if($l =~ m,href="#global",) {
      print OUT "$l\n";
      $skipping = 1;
      next;
    }
    $skipping = 0 if($skipping && $l =~ m,</ul>,);
    next if($skipping);

    if($modFileName){
      $content .= "$l\n";
    } else {
      print OUT "$l\n";
    }
  }
}

foreach my $mod (sort {$mods{$a} cmp $mods{$b}} keys %mods) {
  print "Missing doc for $mods{$mod}\n" if(!$fnd{$mod});
  $modFileName = $mods{$mod};
  open(IN, "$modFileName") || die("$modFileName: $!\n");
  open(OUT, ">$modFileName.NEW") || die("$modFileName.NEW: $!\n");
  while(my $l = <IN>) {
    print OUT $l;
    if($l =~ m/^1;/) {
      if($doc{$modFileName}) {
        print OUT "\n=pod\n\n";
        foreach my $lang (@lang) {
          next if(!$doc{$modFileName}{$lang});
          my $suffix = ($lang eq "EN" ? "" : "_$lang");
          print OUT "=begin html$suffix\n\n";
          print OUT $doc{$modFileName}{$lang};
          print OUT "=end html$suffix\n\n";
        }
        print OUT "=cut\n";
      }
      last;
    }
  }
  close(IN);
  close(OUT);
  rename("$modFileName.NEW", $modFileName);
}
