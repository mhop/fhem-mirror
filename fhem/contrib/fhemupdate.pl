#!/usr/bin/perl

###############################
# This is quite a big mess here.

use IO::File;

# Server-Side script to check out the fhem SVN repository, and upload the
# changed files to the server

$ENV{CVS_RSH}="/usr/bin/ssh";

print "\n\n";
print localtime() . "\n";

#my $homedir="/Users/rudi/Projects/fhem/fhemupdate";
my $homedir="/home/rudi/fhemupdate";
#goto NEWSTYLE;

chdir("$homedir/culfw");
system("svn update .");

chdir("$homedir/fhem");
system("mkdir -p fhemupdate");
system("svn update .");
die "SVN failed, exiting\n" if($?);

`cp fhem.pl fhem.pl.txt`;


#################################
# Old style
my @filelist = (
 "./fhem.pl.txt",
 "FHEM/.*.pm",
 "FHEM/FhemUtils/.*.pm",
 "www/gplot/.*.gplot",
 "www/images/dark/.*.png",
 "www/images/default/.*.png",
 "www/images/smallscreen/.*.png",
 "www/pgm2/.*\.(js|css|svg)",
 "docs/commandref.html",
 "docs/faq.html",
 "docs/HOWTO.html",
 "docs/fhem.*.png",
 "docs/.*.jpg",
 "../culfw/Devices/CUL/.*.hex",
 "./CHANGED",
);

# Read in the file timestamps
my %filetime;
my %filesize;
my %filedir;
foreach my $fspec (@filelist) {
  $fspec =~ m,^(.+)/([^/]+)$,;
  my ($dir,$pattern) = ($1, $2);

  opendir DH, $dir || die("Can't open $dir: $!\n");
  foreach my $file (grep { /$pattern/ && -f "$dir/$_" } readdir(DH)) {
    my @st = stat("$dir/$file");
    my @mt = localtime($st[9]);
    $filetime{$file} = sprintf "%04d-%02d-%02d_%02d:%02d:%02d",
                $mt[5]+1900, $mt[4]+1, $mt[3], $mt[2], $mt[1], $mt[0];
    $filesize{$file} = $st[7];
    $filedir{$file} = $dir;
  }
  closedir(DH);
}

my %oldtime;
if(open FH, "fhemupdate/filetimes.txt") {
  while(my $l = <FH>) {
    chomp($l);
    my ($ts, $fs, $file) = split(" ", $l, 3);
    $oldtime{"$file.txt"} = $ts if($file eq "fhem.pl");
    $oldtime{$file} = $ts;
  }
  close(FH);
}

chdir("$homedir/fhem/fhemupdate");
open FH, ">filetimes.txt" || die "Can't open filetimes.txt: $!\n";
my $cnt;
foreach my $f (sort keys %filetime) {
  my $fn = $f;
  $fn =~ s/.txt$// if($fn =~ m/.pl.txt$/);
  print FH "$filetime{$f} $filesize{$f} $fn\n";

  my $newfname = $f;
  if(!$oldtime{$f} || $oldtime{$f} ne $filetime{$f}) {
    system("cp ../$filedir{$f}/$f $f");
    $cnt++;
  }
}
close FH;

NEWSTYLE:

for(my $loop = 0; $loop < 2; $loop++) {
  #################################
  # new Style
  chdir("$homedir/fhem");
  my $uploaddir2= ($loop ? "fhemupdate4" : "fhemupdate2");
  system("mkdir -p $uploaddir2");

  my %filelist2 = (
   "./fhem.pl.txt"               => { type=>",fhem,", dir=>"." },
   "./CHANGED"                   => { type=>",fhem,", dir=>"." },
   "FHEM/.*.pm"                  => { type=>",fhem,", dir=>"FHEM" },
   "FHEM/FhemUtils/.*.pm"        => { type=>",fhem,", dir=>"FHEM/FhemUtils"},
   "../culfw/Devices/CUL/.*.hex" => { type=>",fhem,", dir=>"FHEM",
                                                      dir3=>"FHEM", },
   "www/pgm2/.*"                 => { type=>"fhem,",  dir=>"www/pgm2"},
   "www/gplot/.*.gplot"          => { type=>"fhem,",  dir=>"www/pgm2"},
   "www/images/dark/.*.png"      => { type=>"fhem,",  dir=>"www/pgm2"},
   "www/images/default/.*"       => { type=>"fhem,",  dir=>"www/pgm2"},
   "www/images/smallscreen/.*"   => { type=>"fhem,",  dir=>"www/pgm2"},
   "docs/commandref.html"        => { type=>"fhem,",  dir=>"www/pgm2"},
   "docs/faq.html"               => { type=>"fhem,",  dir=>"www/pgm2"},
   "docs/HOWTO.html"             => { type=>"fhem,",  dir=>"www/pgm2"},
   "docs/fhem.*.png"             => { type=>"fhem,",  dir=>"www/pgm2"},
   "docs/.*.jpg"                 => { type=>"fhem,",  dir=>"www/pgm2"},
  );


  # Can't make negative regexp to work, so do it with extra logic
  my %skiplist2 = (
  # "www/pgm2"  => ".pm\$",
  );

  # Read in the file timestamps
  my %filetime2;
  my %filesize2;
  my %filedir2;
  my %filetype2;
  foreach my $fspec (keys %filelist2) {
    $fspec =~ m,^(.+)/([^/]+)$,;
    my ($dir,$pattern) = ($1, $2);
    my $tdir = $filelist2{$fspec}{$loop ? "dir3" : "dir"};
    $tdir = $dir if(!$tdir);
    opendir DH, $dir || die("Can't open $dir: $!\n");
    foreach my $file (grep { /$pattern/ && -f "$dir/$_" } readdir(DH)) {
      next if($skiplist2{$tdir} && $file =~ m/$skiplist2{$tdir}/);
      my @st = stat("$dir/$file");
      my @mt = localtime($st[9]);
      $filetime2{"$tdir/$file"} = sprintf "%04d-%02d-%02d_%02d:%02d:%02d",
                  $mt[5]+1900, $mt[4]+1, $mt[3], $mt[2], $mt[1], $mt[0];
      $filesize2{"$tdir/$file"} = $st[7];
      $filedir2{"$tdir/$file"} = $dir;
      $filetype2{"$tdir/$file"} = $filelist2{$fspec}{type};
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
}

$ENV{RSYNC_RSH}="ssh";
chdir("$homedir/fhem");

if(0) {
  my $fname="controls_fhem.txt";
  `cp fhemupdate4/$fname fhemupdate`;
  `cp fhemupdate4/$fname fhemupdate2/FHEM`;
  `rm fhemupdate2/$fname`;
  my @st = stat("fhemupdate4/$fname");
  my @mt = localtime($st[9]);
  my $ftime = sprintf "%04d-%02d-%02d_%02d:%02d:%02d",
                    $mt[5]+1900, $mt[4]+1, $mt[3], $mt[2], $mt[1], $mt[0];
  my $fsize = $st[7];
  system("echo $ftime $fsize $fname >> fhemupdate/filetimes.txt");
  system("echo $ftime $fsize FHEM/$fname >> fhemupdate2/filetimes.txt");
}

my $rsyncopts="-a --delete --compress --verbose";
system("rsync $rsyncopts fhemupdate fhem.de:fhem");
system("rsync $rsyncopts fhemupdate2 fhem.de:fhem");
system("rsync $rsyncopts fhemupdate4/. fhem.de:fhem/fhemupdate4/svn");
