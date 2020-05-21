#!/usr/bin/perl

###############################
# Server-Side script to check out the fhem SVN repository, and upload the
# changed files to the server

# $Id$

use strict;
use warnings;

my $debug = 0;
print "\n\n";
print "fhemupdate.pl START: ".localtime()."\n";

my $homedir="/home/rko/fhemupdate";
my $destdir="/var/www/html/fhem.de";

chdir("$homedir/culfw");
system("svn update .") if(!$debug);

chdir("$homedir/fhem");
system("svn update .") if(!$debug);
die "SVN failed, exiting\n" if($?);

`../copyfiles.sh` if(!$debug);

#################################
# new Style
chdir("$homedir/fhem");
system("mkdir -p fhemupdate");

my @filelist2 = (
  "./fhem.pl.txt",
  "./CHANGED",
  "./MAINTAINER.txt",
  "./configDB.pm",
  "FHEM/.*.pm",
  "FHEM/.*.layout",
  "FHEM/FhemUtils/.*.pm",
  "FHEM/FhemUtils/update-.*",
  "FHEM/lib/.*.pm",
  "FHEM/lib/.*.xml",
  "FHEM/lib/.*.csv",
  "FHEM/firmware/.*",
  "FHEM/lib/SWAP/.*.xml",
  "FHEM/lib/SWAP/panStamp/.*",
  "FHEM/lib/SWAP/justme/.*",
  "FHEM/lib/Device/.*.pm",
  "FHEM/lib/Device/Firmata/.*.pm",
  "FHEM/lib/MP3/.*.pm",
  "FHEM/lib/MP3/Tag/.*",
  "FHEM/lib/UPnP/.*",
  "FHEM/lib/AttrTemplate/.*.template",
  "FHEM/holiday/.*.holiday",
  "contrib/commandref_join.pl.txt",
  "contrib/commandref_modular.pl.txt",
  "www/pgm2/.*",
  "www/pgm2/images/.*.png",
  "www/jscolor/.*",
  "www/codemirror/.*",
  "www/gplot/.*.gplot",
  "www/images/fhemSVG/.*.svg",
  "www/images/openautomation/.*.svg",
  "www/images/openautomation/.*.txt",
  "www/images/default/.*",
  "www/images/default/remotecontrol/.*",
  "www/images/sscam/.*.png",
  "docs/commandref.*.html",
  "docs/faq(_..)?.html",
  "docs/HOWTO(_..)?.html",
  "docs/fhem.*.png",
  "docs/.*.jpg",
  "docs/fhemdoc.js",
  "demolog/.*",
  "./fhem.cfg.demo",
);


# Collect file timestamp and size
my %filetime2;
my %filesize2;
sub
statDir
{
  my ($fspec, $recursive) = @_;
  $fspec =~ m,^(.+)/([^/]+)$,;
  my ($dir,$pattern) = ($1, $2);

  opendir DH, $dir || die("Can't open $dir: $!\n");
  my @files = readdir(DH);
  closedir(DH);

  foreach my $file (@files) {
    my $fPath = "$dir/$file";
    if(-d $fPath) {
      statDir("$fPath/$pattern", 1) if($recursive && $file !~ m/^\./);
    } else {
      next if($file !~ m/$pattern/);
      my @st = stat($fPath);
      my @mt = localtime($st[9]);
      $filetime2{$fPath} = sprintf "%04d-%02d-%02d_%02d:%02d:%02d",
                  $mt[5]+1900, $mt[4]+1, $mt[3], $mt[2], $mt[1], $mt[0];
      $filesize2{$fPath} = $st[7];
    }
  }
}

foreach my $fspec (@filelist2) {
  statDir($fspec);
}
statDir("lib/.*.pm",1) if(-d "lib");

#######################
# read in the old times
chdir("$homedir/fhem/fhemupdate");
my %oldtime;
my $fname = "controls_fhem.txt";
if(open FH, $fname) {
  while(my $l = <FH>) {
    chomp($l);
    next if($l !~ m/^UPD ([^ ]*) ([^ ]*) (.*)$/);
    my ($ts, $fs, $file) = ($1, $2, $3);
    $oldtime{"$file.txt"} = $ts if($file =~ m/\.pl$/);
    $oldtime{$file} = $ts;
  }
  close(FH);
}


# Create the new controls_fhem.txt and copy the changed files
open(FH, ">$fname") || die "Can't open $fname: $!\n";
`svn info ..` =~ m/Revision: (\d+)/m;
print FH "REV $1\n";
if(open(ADD, "../../fhemupdate.control.fhem")) {
  print FH join("",<ADD>);
  close ADD;
}
my $cnt;
foreach my $f (sort keys %filetime2) {
  my $fn = $f;
  $fn =~ s/.txt$// if($fn =~ m/.pl.txt$/);
  print FH "UPD $filetime2{$f} $filesize2{$f} $fn\n";
  my $newfname = $f;
  if(!$oldtime{$f} || $oldtime{$f} ne $filetime2{$f}) {
    $f =~ m,^(.*)/([^/]*)$,;
    my ($dir, $file) = ($1, $2);
    system("mkdir -p $dir") unless(-d $dir);
    system("cp ../$dir/$file $dir/$file");
    $cnt++;
  }
}
close(FH);

exit(0) if($debug);

# copy and check in the controls file if it was changed.
chdir("$homedir/fhem");
my $diff=`diff -I '^REV' fhemupdate/$fname $fname`;
if($diff) {
  system("cp fhemupdate/$fname $fname");
  system("svn commit -m '$fname: fhemupdate checkin'");
}

system("cp -p ../culfw/Devices/CUL/*.hex fhemupdate/FHEM");
system("cp -p ../culfw/Devices/CUL/*.hex fhemupdate/FHEM/firmware");
system("cp -p FHEM/firmware/*.hex        fhemupdate/FHEM/firmware");


# copy the stuff to the external dir
my $rsyncopts="-a --delete --verbose";
print "rsync $rsyncopts fhemupdate/. $destdir/fhemupdate/.\n";
system("rsync $rsyncopts fhemupdate/. $destdir/fhemupdate/.");
if(-f "commandref_changed") {
  system("cp docs/commandref.html docs/commandref_DE.html $destdir");
  system("cp docs/commandref_modular*.html $destdir");
}

system("cp CHANGED MAINTAINER.txt $destdir");
system("cp $destdir/stats/data/fhem_statistics_db.sqlite ..");

chdir("$homedir");

print "generating SVNLOG\n";
system("sh mksvnlog.sh > SVNLOG");
system("cp SVNLOG $destdir");
print "fhemupdate.pl END: ".localtime()."\n";
