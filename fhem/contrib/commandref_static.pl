#!/usr/bin/perl

# $Id$

use strict;
use warnings;

sub _cref_search;
sub _cref_read;
sub _cref_write;

my $rebuild = (defined($ARGV[0]) && lc($ARGV[0]) eq "rebuild") ? 1 : 0;

my $protVersion=1;
my @lang = ("EN", "DE");
my $modDir = "FHEM";
my $now = time();

for my $lang (@lang) {
  my $sfx = ($lang eq "EN" ? "" : "_$lang");
  my %modData;
  my $cmdref = "docs/commandref_frame$sfx.html";
  
  my $outpath = "docs/cref$sfx";
  unlink glob "$outpath/*" if $rebuild;
  mkdir $outpath unless (-e $outpath);

  open(FH, $cmdref) || die("Cant open $cmdref: $!\n");
  my $type = "";
  my $fileVersion = 0;
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
      $fileVersion = $1 if($type && $l =~ m/<table.*protVersion='(.*)'>/);

      if($l =~ m,<td class='modname'><a href='#'>(.*)</a></td><td>(.*)</td>, &&
         !$modData{$1}{type}) {     # commandref_frame has prio
        $modData{$1}{type} = $type;
        $modData{$1}{"summary$sfx"} = $2;
        $modData{$1}{ts} = $cmptime;
      }

      if($l =~ m,<div id='modLinks'[^>]*> ([^<]+)</div>,) {
        for my $ml (split(" ", $1)) {
          my @kv=split(/[:,]/,$ml);
          my $n = shift(@kv);
          for my $v (@kv) {
            $modData{$n}{modLinks}{$v} = 1;
          }
        }
      }

      if($l =~ m,<div id='modLangs'[^>]*> ([^<]+)</div>,) {
        for my $ml (split(" ", $1)) {
          my ($n,$v) = split(/[:,]/,$ml,2);
          $modData{$n}{modLangs} = $v;
        }
      }
    }
    close(FH);
  }

  opendir(DH, $modDir) || die "Cant open $modDir: $!\n";
  while(my $fName = readdir DH) {
    next if($fName !~ m/^\d\d_(.*)\.pm$/);
    my $mName = $1;
    my $ts = (stat("$modDir/$fName"))[9];
    if($protVersion != $fileVersion || $rebuild ||
       !$modData{$mName} || !$modData{$mName}{ts} || $modData{$mName}{ts}<$ts ||
       !$modData{$mName}{modLangs}) {

      #print "Checking $fName for $lang short description\n";

      $modData{$mName}{type}="device" if(!$modData{$mName}{type});
      delete($modData{$mName}{modLinks});
      open(FH, "$modDir/$fName") || die("Cant open $modDir/$fName: $!\n");
      my @lang;
      while(my $l = <FH>) {
        push @lang,($1 eq "" ? "EN":substr($1,1)) if($l =~ m/^=begin html(.*)/);
        $modData{$mName}{type}=$1 if($l =~ m/^=item\s+(helper|command|device)/);
        $modData{$mName}{$1}  =$2 if($l =~ m/^=item\s+(summary[^ ]*)\s(.*)$/);
        $modData{$mName}{modLinks}{$2} = 1
                 if($l =~ m/<a\s+(name|id)=['"]([^ '"]+)['"]>/);
      }
      $modData{$mName}{modLangs} = join(",", @lang);
      close(FH);
      my $output = _cref_search("$modDir/$fName",$sfx);
      my $outFile = "docs/cref$sfx/$mName.cref";
      _cref_write($outFile,$output) if $output;

    }
  }
  closedir(DH);

  $cmdref = "docs/commandref_frame${sfx}.html";
  open(IN, $cmdref) || die("Cant open $cmdref: $!\n");

  $cmdref = ">docs/commandref_modular${sfx}.html";
  open(OUT, $cmdref) || die("Cant open $cmdref: $!\n");
  
  my $linkDumped = 0;
  while(my $l = <IN>) {

    $l =~ s,class="commandref,class="commandref modular,;
    print OUT $l;
    if($l =~ m,\s*<title>,) {
      print OUT << 'EOF'
  <script type="text/javascript" src="../pgm2/jquery.min.js"></script>
  <script type="text/javascript" src="../pgm2/fhemdoc_modular.js"></script>
EOF
    }

    if($l =~ m,<!-- header:(.*) -->,) {
      my @mList = sort {uc($a) cmp uc($b)} keys %modData;
      if(!$linkDumped) {
        my ($mlink,$mlang) = ("","");
        for my $m (@mList) {
          $mlink .= " $m:".join(",", keys(%{$modData{$m}{modLinks}}))
            if($modData{$m}{modLinks});
          $mlang .= " $m:$modData{$m}{modLangs}"
            if($modData{$m}{modLangs});
        }
        print OUT "<div id='modLinks' style='display:none'>$mlink</div>\n";
        print OUT "<div id='modLangs' style='display:none'>$mlang</div>\n";
        $linkDumped = 1;
      }
      my $type = $1;
      while(my $l = <IN>) {
        last if($l !~ m/<a href="/);
      }
      print OUT "<table class='block summary class_$type' ".
                "protVersion='$protVersion'>\n";
      my $rc = "odd";
      for my $m (@mList) {
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
  close(OUT);
  close(IN);
}


sub _cref_search {
   my ($fileName,$sfx) = @_;
   my $output = "";
   my $skip = 1;
   my ($err,@text) = _cref_read($fileName);
   return $err if $err;
   foreach my $l (@text) {
     if($l =~ m/^=begin html$sfx$/) {
        $skip = 0;
     } elsif($l =~ m/^=end html$sfx$/) {
        $skip = 1;
     } elsif(!$skip) {
        $output .= "$l\n";
        if($l =~ m,INSERT_DOC_FROM: ([^ ]+)/([^ /]+) ,) {
          my ($dir, $re) = ($1, $2);
          if(opendir(DD, $dir)) {
            foreach my $file (grep { m/^$2$/ } readdir(DD)) {
              my $o2 = _cref_search("$dir/$file", $sfx);
              $output .= $o2 if $o2;
            }
            closedir(DD);
          }
        }
     }
   }
   return $output;
}

sub _cref_read {
   my ($fileName) = @_;
   my ($err, @ret);
   if(open(FF, $fileName)) {
      @ret = <FF>;
      close(FF);
      chomp(@ret);
   } else {
      $err = "Can't open $fileName: $!";
   }
   return ($err, @ret);
}

sub _cref_write {
   my ($fileName,$content) = @_;

   if(open(FH, ">$fileName")) {
      binmode (FH);
      print FH $content;
      close(FH);
      return undef;
   } else {
      return "Can't open $fileName: $!";
   }
}
