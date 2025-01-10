#!/usr/bin/perl

# Usage:
#  if called with FHEM/XX.pm, than only this file will be checked

# MAXWI
# With pre: 1320, without 1020 (content only)
# pre { white-space: pre-wrap; } : 900

use strict;
use warnings;

# $Id$

my $noWarnings = grep $_ eq '-noWarnings', @ARGV;
my ($verify) = grep $_ =~ /\.pm$/ , @ARGV;

use constant TAGS => qw{b code div h3 h4 i li p table td tr u ul };

sub generateModuleCommandref($$;$$);

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
      my $modFh;
      open($modFh, "$modDir/$of") || die("Cant open $modDir/$l");
      while(my $cl = <$modFh>) {
        if($cl =~ m/^=item\s+(helper|command|device)/) {
          $modIdx{$l} = $1;
          last;
        }
      }
      close($modFh);
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
my $var;
sub
chkAndGenLangLinks($$$)
{
  my ($l, $lang, $fh) = @_;
  $var = $2 if($l =~ m/<a (name|id)="(.*?)".*><\/a>/);
  if($fh && $l =~ m/(.*?)<\/h3>/ && $var) {
    print $fh "<div class='langLinks'>[".join(" ", map { 
        $_ eq $lang ? $_ : 
        "<a href='commandref".($_ eq "EN" ? "":"_$_").".html#$var'>$_</a>"
      } @lang) . "]</div>\n";
    $var = undef;
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
      $modType = "device"  if($l =~ m/>Device modules</);
      $modType = "helper"  if($l =~ m/>Helper modules</);
      $modIdx{$1} = $modType
        if($modType && $l =~ m/href="#(.*?)">/ && $1 ne "global");
      last if($l =~ m/<!-- header end -->/);
    }
    seek(IN,0,0);
  }

  # Second run: create the file
  while(my $l = <IN>) { # Header
    last if($l =~ m/(name|id)="perl"/);
    print OUT $l;
    chkAndGenLangLinks($l, $lang, \*OUT);
    
    printList($1) if($l =~ m/<!-- header:(.*) -->/);
  }

  # Copy the doc part from the module
  foreach my $mod (sort keys %mods) {
    generateModuleCommandref($mod,$lang, \*OUT);
  }

  # Copy the tail
  print OUT '<a id="perl"></a>',"\n";
  $var = "perl"; 
  
  while(my $l = <IN>) {
    print OUT $l;
    chkAndGenLangLinks($l, $lang, \*OUT);
  }
  close(OUT);
}

#############################
# read a module file and check/print the commandref
sub 
generateModuleCommandref($$;$$)
{
    my ($mod, $lang, $fh, $jsFile) = @_; 
    my $fPath = $mods{$mod} ? $mods{$mod} : $mod;
    my $tag;
    my $suffix = ($lang eq "EN" ? "" : "_$lang");
    my %tagcount= ();
    map { $tagcount{$_} = 0 } TAGS;
    my %llwct = (); # Last line with closed tag
    my $modFh;
    open($modFh, $fPath) || die("Cant open $fPath:$!\n");
    my $skip = 1;
    my $line = 0;
    my $docCount = 0;
    my $hasLink = 0;
    my $dosMode = 0;
    my $nrEnd = 0;
    while(my $l = <$modFh>) {
      $line++;

      $dosMode = 1 if($l =~ m/^=begin html$suffix.*\r/);
      if($l =~ m/^=begin html$suffix$/) {
        $l = <$modFh>;    # skip one line, to be able to repeat join+split
        print "*** $lang $mod: nonempty line after =begin html ignored\n"
          if($l =~ m/^...*$/);
        $skip = 0; $line++;
        $nrEnd++;

      } elsif($l =~ m/^=end html$suffix$/) {
        $skip = 1;
        $nrEnd--;
        print $fh "<p>" if($fh);        

      } elsif(!$skip) {
        print $fh $l if($fh);
        if($l =~ m,INSERT_DOC_FROM: ([^ ]+)/([^ /]+) ,) {
          my ($dir, $re) = ($1, $2);
          if(opendir(DH, $dir)) {
            foreach my $file (grep { m/^$2$/ } readdir(DH)) {
              generateModuleCommandref("$dir/$file", $lang, $fh, 1);
            }
            closedir(DH);
          }
        }
        chkAndGenLangLinks($l, $lang, $fh);

        $docCount++;
        next if($noWarnings);
        $hasLink = ($l =~ m/<a (name|id)="$mod"/) if(!$hasLink);
        foreach $tag (TAGS) {
          if($l =~ m/<$tag ([^>]+)>/i) {
            print "*** $lang $mod line $line: $tag with attributes".
                " is not allowed\n" 
              if(!$noWarnings);
          }
          $tagcount{$tag} +=()= ($l =~ /<$tag( [^>]+)?>/gi);
          $tagcount{$tag} -=()= ($l =~ /<\/$tag>/gi);
          if($tagcount{$tag} < 0) {
            print "*** $lang $fPath: negative tagcount for $tag, line $line\n"
                if(!$noWarnings);
            $tagcount{$tag} = 0;
          }
          $llwct{$tag} = $line if(!$tagcount{$tag});
        }

      }
    }
    close($modFh);
    print "*** $lang $fPath: ignoring text due to DOS encoding\n"
        if($dosMode);
# TODO: add doc to each $jsfile
    print "*** $lang $fPath: No document text found\n"
       if(!$jsFile && !$suffix && !$docCount && !$dosMode &&
          $fPath !~ m,/99_, && !$noWarnings);
    if(!$jsFile && $suffix && !$docCount && !$dosMode) {
      if($lang eq "DE" && $fh) {
        print $fh <<EOF;
<a id="$mod"></a>
<h3>$mod</h3>
<ul>
  Leider keine deutsche Dokumentation vorhanden. Die englische Version gibt es
  hier: <a href='commandref.html#$mod'>$mod</a><br/>
</ul>
EOF
      }
    }
    print "*** $lang $fPath: No a-tag with id=\"$mod\" \n"
        if(!$jsFile && !$suffix && $docCount && !$hasLink && !$noWarnings);

    foreach $tag (TAGS) {
      print("*** $lang $fPath: Unbalanced $tag ".
                "($tagcount{$tag}, last line ok: $llwct{$tag})\n")
        if($tagcount{$tag} && !$noWarnings);
    }

    print "*** $lang $fPath: =end html$suffix: ".($nrEnd>0 ? "missing":"there are too many")."\n"
        if($nrEnd && !$noWarnings);
}
