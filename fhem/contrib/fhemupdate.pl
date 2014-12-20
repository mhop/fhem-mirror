#!/usr/bin/perl

###############################
# This is quite a big mess here.

use IO::File;
use strict;
use warnings;

# Server-Side script to check out the fhem SVN repository, and upload the
# changed files to the server

$ENV{CVS_RSH}="/usr/bin/ssh";

print "\n\n";
print localtime() . "\n";

my $homedir="/home/rudi/fhemupdate";

chdir("$homedir/culfw");
system("svn update .");

chdir("$homedir/fhem");
system("svn update .");
die "SVN failed, exiting\n" if($?);

`../copyfiles.sh`;

#################################
# new Style
chdir("$homedir/fhem");
my $uploaddir2 = "fhemupdate4";
system("mkdir -p $uploaddir2");

my @filelist2 = (
  "./fhem.pl.txt",
  "./CHANGED",
  "./configDB.pm",
  "FHEM/.*.pm",
  "FHEM/FhemUtils/.*.pm",
  "FHEM/FhemUtils/update-.*",
  "FHEM/lib/.*.pm",
  "FHEM/lib/.*.xml",
  "FHEM/firmware/.*",
  "FHEM/lib/SWAP/.*.xml",
  "FHEM/lib/SWAP/panStamp/.*",
  "FHEM/lib/SWAP/justme/.*",
  "FHEM/lib/Device/.*.pm",
  "FHEM/lib/Device/Firmata/.*.pm",
  "FHEM/lib/Device/MySensors/.*.pm",
  "FHEM/lib/MP3/.*.pm",
  "FHEM/lib/MP3/Tag/.*",
  "FHEM/lib/UPnP/.*",
  "www/pgm2/.*",
  "www/jscolor/.*",
  "www/codemirror/.*",
  "www/gplot/.*.gplot",
  "www/images/fhemSVG/.*.svg",
  "www/images/openautomation/.*.svg",
  "www/images/openautomation/.*.txt",
  "www/images/default/.*",
  "www/images/default/remotecontrol/.*",
  "docs/commandref(_..)?.html",
  "docs/faq(_..)?.html",
  "docs/HOWTO(_..)?.html",
  "docs/fhem.*.png",
  "docs/.*.jpg",
  "docs/fhemdoc.js",
);


# Can't make negative regexp to work, so do it with extra logic
my %skiplist2 = (
# "www/pgm2"  => ".pm\$",
);

# Read in the file timestamps
my %filetime2;
my %filesize2;
my %filedir2;
foreach my $fspec (@filelist2) {
  $fspec =~ m,^(.+)/([^/]+)$,;
  my ($dir,$pattern) = ($1, $2);
  my $tdir = $dir;
  opendir DH, $dir || die("Can't open $dir: $!\n");
  foreach my $file (grep { /$pattern/ && -f "$dir/$_" } readdir(DH)) {
    next if($skiplist2{$tdir} && $file =~ m/$skiplist2{$tdir}/);
    my @st = stat("$dir/$file");
    my @mt = localtime($st[9]);
    $filetime2{"$tdir/$file"} = sprintf "%04d-%02d-%02d_%02d:%02d:%02d",
                $mt[5]+1900, $mt[4]+1, $mt[3], $mt[2], $mt[1], $mt[0];
    $filesize2{"$tdir/$file"} = $st[7];
    $filedir2{"$tdir/$file"} = $dir;
  }
  closedir(DH);
}

chdir("$homedir/fhem/$uploaddir2");
my %oldtime;
if(open FH, "filetimes.txt") {
  while(my $l = <FH>) {
    chomp($l);
    my ($ts, $fs, $file) = split(" ", $l, 3);
    $oldtime{"$file.txt"} = $ts if($file =~ m/fhem.pl/);
    $oldtime{$file} = $ts;
  }
  close(FH);
}

open FH, ">filetimes.txt" || die "Can't open filetimes.txt: $!\n";

my %controls = (fhem=>0);
foreach my $k (keys %controls) {
  my $fname = "controls_$k.txt";
  $controls{$k} = new IO::File ">$fname" || die "Can't open $fname: $!\n";
  if(open(ADD, "../../fhemupdate.control.$k")) {
    while(my $l = <ADD>) {
      my $fh = $controls{$k};
      print $fh $l;
    }
    close ADD;
  }
}

my $cnt;
foreach my $f (sort keys %filetime2) {
  my $fn = $f;
  $fn =~ s/.txt$// if($fn =~ m/.pl.txt$/);
  print FH "$filetime2{$f} $filesize2{$f} $fn\n";
  foreach my $k (keys %controls) {
    my $fh = $controls{$k};
    print $fh "UPD $filetime2{$f} $filesize2{$f} $fn\n"
  }
  my $newfname = $f;
  if(!$oldtime{$f} || $oldtime{$f} ne $filetime2{$f}) {
    $f =~ m,^(.*)/([^/]*)$,;
    my ($tdir, $file) = ($1, $2);
    system("mkdir -p $tdir") unless(-d $tdir);
    system("cp ../$filedir2{$f}/$file $tdir/$file");
    $cnt++;
  }
}
close FH;

foreach my $k (keys %controls) {
  close $controls{$k};
}

$ENV{RSYNC_RSH}="ssh";
chdir("$homedir/fhem");

if(0) {
  my $fname="controls_fhem.txt";
  my @st = stat("fhemupdate4/$fname");
  my @mt = localtime($st[9]);
  my $ftime = sprintf "%04d-%02d-%02d_%02d:%02d:%02d",
                    $mt[5]+1900, $mt[4]+1, $mt[3], $mt[2], $mt[1], $mt[0];
  my $fsize = $st[7];
}

system("cp -p ../culfw/Devices/CUL/*.hex fhemupdate4/FHEM");
system("cp -p ../culfw/Devices/CUL/*.hex fhemupdate4/FHEM/firmware");
system("cp -p FHEM/firmware/*.hex        fhemupdate4/FHEM/firmware");

my $rsyncopts="-a --delete --compress --verbose";
system("rsync $rsyncopts fhemupdate4/. fhem.de:fhem/fhemupdate4/svn");
if(-f "commandref_changed") {
  system("scp docs/commandref.html docs/commandref_DE.html fhem.de:fhem");
}

system("scp CHANGED MAINTAINER.txt fhem.de:fhem");
system("scp fhem.de:fhem/stats/data/fhem_statistics_db.sqlite ..");
chdir("$homedir");

system("sh stats/dostats.sh");
system("sh mksvnlog.sh > SVNLOG");
system("scp SVNLOG fhem.de:fhem");

system("sourceforge/dorsync");
