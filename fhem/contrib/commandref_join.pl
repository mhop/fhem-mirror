#!/usr/bin/perl

# MAXWI
# With pre: 1320, without 1020 (content only)
# pre { white-space: pre-wrap; } : 900

use strict;
use warnings;

# $Id$
use constant TAGS => qw{ul li code};
my %mods;
my @modDir = ("FHEM");
foreach my $modDir (@modDir) {
  opendir(DH, $modDir) || die "Cant open $modDir: $!\n";
  while(my $l = readdir DH) {
    next if($l !~ m/^\d\d_.*\.pm$/);
    my $of = $l;
    $l =~ s/.pm$//;
    $l =~ s/^[0-9][0-9]_//;
    $mods{$l} = "$modDir/$of";
  }
}
$mods{configDB} = "configDB.pm";


my @lang = ("EN", "DE");

foreach my $lang (@lang) {
  my $suffix = ($lang eq "EN" ? "" : "_$lang");
  my $docIn  = "docs/commandref_frame$suffix.html";
  my $docOut = "docs/commandref$suffix.html";

  open(IN, "$docIn")    || die "Cant open $docIn: $!\n";
  open(OUT, ">$docOut") || die "Cant open $docOut: $!\n";

  # First run: check what is a command and what is a helper module
  my $status;
  my %noindex;
  while(my $l = <IN>) {
    last if($l =~ m/<h3>Introduction/);
    $noindex{$1} = 1 if($l =~ m/href="#(.*)"/);
  }
  seek(IN,0,0);

  # Second run: create the file
  # Header
  while(my $l = <IN>) {
    print OUT $l;
    last if($l =~ m/#global/);
  }

  # index for devices.
  foreach my $mod (sort keys %mods) {
    next if($noindex{$mod});
    print OUT "      <a href='#$mod'>$mod</a> &nbsp;\n";
  }

  # Copy the middle part
  while(my $l = <IN>) {
    last if($l =~ m/name="perl"/);
    print OUT $l;
  }

  # Copy the doc part from the module
  foreach my $mod (sort keys %mods) {
    my $tag;
    my %tagcount= ();
    my %llwct = (); # Last line with closed tag
    open(MOD, $mods{$mod}) || die("Cant open $mods{$mod}:$!\n");
    my $skip = 1;
    my $line = 0;
    my $docCount = 0;
    my $hasLink = 0;
    my $dosMode = 0;
    while(my $l = <MOD>) {
      $line++;

      $dosMode = 1 if($l =~ m/^=begin html$suffix.*\r/);
      if($l =~ m/^=begin html$suffix$/) {
        $l = <MOD>;    # skip one line, to be able to repeat join+split
        print "$lang $mod: nonempty line after =begin html ignored\n"
          if($l =~ m/^...*$/);
        $skip = 0; $line++;

      } elsif($l =~ m/^=end html$suffix$/) {
        $skip = 1;

      } elsif(!$skip) {
        print OUT $l;
        $docCount++;
        $hasLink = ($l =~ m/<a name="$mod"/) if(!$hasLink);
        foreach $tag (TAGS) {
          my $ot = ($tagcount{$tag} ? $tagcount{$tag} : 0);
          $tagcount{$tag} +=()= ($l =~ /<$tag>/gi);
          $tagcount{$tag} -=()= ($l =~ /<\/$tag>/gi);
          $llwct{$tag} = $line if(!$llwct{$tag} || ($ot && !$tagcount{$tag}));
          #print "$mod $line $tag $tagcount{$tag}\n" if($tagcount{$tag} ne $ot);
        }
      }
    }
    close(MOD);
    print "*** $lang $mods{$mod}: ignoring text due to DOS encoding\n"
        if($dosMode);
    print "*** $lang $mods{$mod}: No document text found\n"
        if(!$suffix && !$docCount && !$dosMode);
    if($suffix && !$docCount && !$dosMode) {
      if($lang eq "DE") {
        print OUT << "EOF";
<a name="$mod"></a>
<h3>$mod</h3>
<ul>
  Leider keine deutsche Dokumentation vorhanden. Die englische Version gibt es
  hier: <a href='commandref.html#$mod'>$mod</a><br/>
</ul>
EOF
      }
    }
    print "$lang $mods{$mod}: No <a name=\"$mod\"> link\n"
        if(!$suffix && $docCount && !$hasLink);

    foreach $tag (TAGS) {
      print("$lang $mods{$mod}: Unbalanced $tag ".
                "($tagcount{$tag}, last line ok: $llwct{$tag})\n")
        if($tagcount{$tag});
    }
  }

  # Copy the tail
  print OUT '<a name="perl"></a>',"\n";
  while(my $l = <IN>) {
    print OUT $l;
  }
  close(OUT);
}
