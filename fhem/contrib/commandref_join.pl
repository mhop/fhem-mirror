#!/usr/bin/perl

# MAXWI
# With pre: 1320, without 1020 (content only)
# pre { white-space: pre-wrap; } : 900

use strict;
use warnings;

# $Id$

my $noWarnings = grep $_ eq '-noWarnings', @ARGV;
my ($verify) = grep $_ =~ /\.pm$/ , @ARGV;

use constant TAGS => qw{ul li code b i u table tr td div};

sub generateModuleCommandref($$;$);

my %mods;
my %modIdx;
my @modDir = ("FHEM");
my @lang = ("EN", "DE");

if(!$verify) {
  foreach my $modDir (@modDir) {
    opendir(DH, $modDir) || die "Cant open $modDir: $!\n";
    while(my $l = readdir DH) {
      next if($l !~ m/^\d\d_.*\.pm$/);
      my $of = $l;
      $l =~ s/.pm$//;
      $l =~ s/^[0-9][0-9]_//;
      $mods{$l} = "$modDir/$of";
      $modIdx{$l} = "device";
      open(MOD, "$modDir/$of") || die("Cant open $modDir/$l");
      while(my $cl = <MOD>) {
        if($cl =~ m/^=item\s+(helper|command|device)/) {
          $modIdx{$l} = $1;
          last;
        }
      }
      close(MOD);
    }
  }
 
  if(-f "configDB.pm") {
    $mods{configDB}   = "configDB.pm";
    $modIdx{configDB} = "helper";
  }
   
} else { # check for syntax only
  my $modname = $verify;
  $modname =~ s/^.*[\/\\](?:\d\d_)?(.+).pm$/$1/;
  $mods{$modname} = $verify;
  foreach my $lang (@lang) {
    generateModuleCommandref($modname, $lang);
  }
  exit;
}

sub
printList($)
{
  for my $i (sort { "\L$a" cmp "\L$b" } keys %modIdx) {
    print OUT "      <a href=\"#$i\">$i</a> &nbsp;\n"
        if($modIdx{$i} eq $_[0]);
  }
  while(my $l = <IN>) {
    next if($l =~ m/href=/);
    print OUT $l;
    last;
  }
}

foreach my $lang (@lang) {
  my $suffix = ($lang eq "EN" ? "" : "_$lang");
  my $docIn  = "docs/commandref_frame$suffix.html";
  my $docOut = "docs/commandref$suffix.html";

  open(IN, "$docIn")    || die "Cant open $docIn: $!\n";
  open(OUT, ">$docOut") || die "Cant open $docOut: $!\n";

  if(!$suffix) { # First run: remember commands/helper module
    my $modType;
    while(my $l = <IN>) {
      $modType = "command" if($l =~ m/>FHEM commands</);
      $modType = "device"  if($l =~ m/>Devices</);
      $modType = "helper"  if($l =~ m/>Helper modules</);
      $modIdx{$1} = $modType
        if($modType && $l =~ m/href="#(.*?)">/ && $1 ne "global");
      last if($l =~ m/<!-- header end -->/);
    }
    seek(IN,0,0);
  }

  # Second run: create the file
  while(my $l = <IN>) { # Header
    last if($l =~ m/name="perl"/);
    print OUT $l;
    printList($1) if($l =~ m/<!-- header:(.*) -->/);
  }

  # Copy the doc part from the module
  foreach my $mod (sort keys %mods) {
    generateModuleCommandref($mod,$lang, \*OUT);
  }

  # Copy the tail
  print OUT '<a name="perl"></a>',"\n";
  while(my $l = <IN>) {
    print OUT $l;
  }
  close(OUT);
}

#############################
# read a module file and check/print the commandref
sub generateModuleCommandref($$;$)
{
    my ($mod, $lang, $fh) = @_; 
    my $tag;
    my $suffix = ($lang eq "EN" ? "" : "_$lang");
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
        print "*** $lang $mod: nonempty line after =begin html ignored\n"
          if($l =~ m/^...*$/);
        $skip = 0; $line++;

      } elsif($l =~ m/^=end html$suffix$/) {
        $skip = 1;

      } elsif(!$skip) {
        print $fh $l if($fh);
        $docCount++;
        $hasLink = ($l =~ m/<a name="$mod"/) if(!$hasLink);
        foreach $tag (TAGS) {
          $tagcount{$tag} +=()= ($l =~ /<$tag>/gi);
          $tagcount{$tag} -=()= ($l =~ /<\/$tag>/gi);
          $llwct{$tag} = $line if(!$tagcount{$tag});
        }
      }
    }
    close(MOD);
    print "*** $lang $mods{$mod}: ignoring text due to DOS encoding\n"
        if($dosMode);
    print "*** $lang $mods{$mod}: No document text found\n"
        if(!$suffix && !$docCount && !$dosMode && $mods{$mod} !~ m,/99_,);
    if($suffix && !$docCount && !$dosMode) {
      if($lang eq "DE" && $fh) {
        print $fh <<EOF;
<a name="$mod"></a>
<h3>$mod</h3>
<ul>
  Leider keine deutsche Dokumentation vorhanden. Die englische Version gibt es
  hier: <a href='commandref.html#$mod'>$mod</a><br/>
</ul>
EOF
      }
    }
    print "*** $lang $mods{$mod}: No a-tag with name=\"$mod\" \n"
        if(!$suffix && $docCount && !$hasLink && !$noWarnings);

    foreach $tag (TAGS) {
      print("*** $lang $mods{$mod}: Unbalanced $tag ".
                "($tagcount{$tag}, last line ok: $llwct{$tag})\n")
        if($tagcount{$tag} && !$noWarnings);
    }
}
