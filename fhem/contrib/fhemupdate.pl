#!/usr/bin/perl

###############################
# This is quite a big mess here.

use IO::File;
use strict;
use warnings;

# Server-Side script to check out the fhem SVN repository, and upload the
# changed files to the server

print "\n\n";
print "fhemupdate.pl START: ".localtime()."\n";

my $homedir="/home/rko/fhemupdate";
my $destdir="/var/www/html/fhem.de";

chdir("$homedir/culfw");
system("svn update .");

chdir("$homedir/fhem");
system("svn update .");
die "SVN failed, exiting\n" if($?);

`../copyfiles.sh`;

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
  "FHEM/lib/Device/MySensors/.*.pm",
  "FHEM/lib/MP3/.*.pm",
  "FHEM/lib/MP3/Tag/.*",
  "FHEM/lib/UPnP/.*",
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


my $cfh = new IO::File ">$fname" || die "Can't open $fname: $!\n";
`svn info ..` =~ m/Revision: (\d+)/m;
print $cfh "REV $1\n";
if(open(ADD, "../../fhemupdate.control.fhem")) {
  print $cfh join("",<ADD>);
  close ADD;
}

my $cnt;
foreach my $f (sort keys %filetime2) {
  my $fn = $f;
  $fn =~ s/.txt$// if($fn =~ m/.pl.txt$/);
  print $cfh "UPD $filetime2{$f} $filesize2{$f} $fn\n";
  my $newfname = $f;
  if(!$oldtime{$f} || $oldtime{$f} ne $filetime2{$f}) {
    $f =~ m,^(.*)/([^/]*)$,;
    my ($tdir, $file) = ($1, $2);
    system("mkdir -p $tdir") unless(-d $tdir);
    system("cp ../$filedir2{$f}/$file $tdir/$file");
    $cnt++;
  }
}
close $cfh;

chdir("$homedir/fhem");
my $diff=`diff -I '^REV' fhemupdate/$fname $fname`;
if($diff) {
  system("cp fhemupdate/$fname $fname");
  system("svn commit -m '$fname: fhemupdate checkin'");
}

system("cp -p ../culfw/Devices/CUL/*.hex fhemupdate/FHEM");
system("cp -p ../culfw/Devices/CUL/*.hex fhemupdate/FHEM/firmware");
system("cp -p FHEM/firmware/*.hex        fhemupdate/FHEM/firmware");


my $rsyncopts="-a --delete --verbose";
print "rsync $rsyncopts fhemupdate/. $destdir/fhemupdate/.\n";
system("rsync $rsyncopts fhemupdate/. $destdir/fhemupdate/.");
if(-f "commandref_changed") {
  system("cp docs/commandref.html docs/commandref_DE.html $destdir");
}

system("cp CHANGED MAINTAINER.txt $destdir");
system("cp $destdir/stats/data/fhem_statistics_db.sqlite ..");

chdir("$homedir");
system("grep -v '^REV' fhem/fhemupdate/controls_fhem.txt > controls_fhem_5.5.txt");
system("cp controls_fhem_5.5.txt $destdir/fhemupdate4/svn/controls_fhem.txt");

#system("sh stats/dostats.sh"); disabled due to new reworked statistics2.cgi
print "generating SVNLOG\n";
system("sh mksvnlog.sh > SVNLOG");
system("cp SVNLOG $destdir");
print "fhemupdate.pl END: ".localtime()."\n";
