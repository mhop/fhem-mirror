#!/usr/bin/perl

# Server-Side script to check out the fhem SVN repository, and upload the
# changed files to the server

$ENV{CVS_RSH}="/usr/bin/ssh";

print "\n\n";
print localtime() . "\n";

chdir("/home/rudi/fhemupdate/culfw");
system("svn update .");
chdir("/home/rudi/fhemupdate/fhem");
system("mkdir -p UPLOAD");
system("svn update .");
die "SVN failed, exiting\n" if($?);

my $ndiff = `diff fhem.pl fhem.pl.txt | wc -l`;
if($ndiff != 4) {       # more than the standard stuff is different
  print "Modifying fhem.pl: >$ndiff<\n";
  system('perl -p -e "s/=DATE=/"`date +"%Y-%m-%d"`"/;'.
                     's/=VERS=/"`grep ^VERS= Makefile | '.
         'sed -e s/VERS=//`"+SVN/" fhem.pl > fhem.pl.txt');
}


my @filelist = (
 "./fhem.pl.txt",
 "FHEM/.*.pm",
 "webfrontend/pgm2/.*",
 "docs/commandref.html",
 "docs/faq.html",
 "docs/HOWTO.html",
 "docs/fhem.*.png",
 "docs/.*.jpg",
 "../culfw/Devices/CUL/.*.hex",
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
if(open FH, "UPLOAD/filetimes.txt") {
  while(my $l = <FH>) {
    chomp($l);
    my ($ts, $fs, $file) = split(" ", $l, 3);
    $oldtime{"$file.txt"} = $ts if($file eq "fhem.pl");
    $oldtime{$file} = $ts;
  }
  close(FH);
}

chdir("UPLOAD");
open FH, ">filetimes.txt" || die "Can't open filetimes.txt: $!\n";
open FTP, ">script.txt" || die "Can't open script.txt: $!\n";
print FTP "cd fhem/fhemupdate\n";
print FTP "put filetimes.txt\n";
print FTP "pas\n";      # Without passive only 28 files can be transferred
my $cnt;
foreach my $f (sort keys %filetime) {
  my $fn = $f;
  $fn =~ s/.txt$// if($fn =~ m/.pl.txt$/);
  print FH "$filetime{$f} $filesize{$f} $fn\n";

  my $newfname = $f;
  if(!$oldtime{$f} || $oldtime{$f} ne $filetime{$f}) {
    print FTP "put $f\n";
    system("cp ../$filedir{$f}/$f $f");
    $cnt++;
  }
}
close FH;
close FTP;

if($cnt) {
  print "FTP Upload needed for $cnt files\n";
  system("ftp -e fhem.de < script.txt");
}
