#!/usr/bin/perl

# Details in Forum #35416

if(@ARGV == 0 || ($ARGV[0] =~ m/^-/ && $ARGV[0] ne "-d")) {
  print "Usage:\n".
    "  cd open-zwave\n".
    "  perl .../contrib/zwave_configconvert.pl config |\n".
    "  gzip > .../FHEM/lib/openzwave_deviceconfig.xml.gz\n".
    "or\n".
    "  cd open-zwave\n".
    "  gzip -d < .../FHEM/lib/openzwave_deviceconfig.xml.gz |\n".
    "  perl .../contrib/zwave_configconvert.pl -d\n";
  exit 1;
}

if($ARGV[0] eq "-d") {
  while(my $l = <STDIN>) {
    next if($l !~ m/<Product sourceFile="([^"]*)"/);
    my $f = $1;
    next if(-f "config/$f");
    print("Creating: config/$f\n");
    open(FH, ">config/$f") || die("open config/$f: $!\n");
    print FH $l;
    while($l = <STDIN>) {
      print FH $l;
      last if($l =~ m,</Product>,);
    }
    close(FH);
  }
  exit(0);
}

print '<?xml version="1.0" encoding="utf-8"?>', "\n";
print "<ProductList>\n";
foreach my $file (`find $ARGV[0] -name \*.xml`) {
  chomp($file);
  my $name = $file;
  $name =~ s+.*config/++;
  next if($name !~ m+/+); # Only files from subdirs
  open(FH, $file) || die("$file:$!\n");
  my $buffer="";
  while(my $l = <FH>) {
    next if($l =~ m/^<\?xml/);
    chomp($l);
    $l =~ s/^<Product.*xmlns.*/<Product sourceFile="$name">/;
    $l =~ s/\r//g;
    $l =~ s/\t/  /g;
    #$l =~ s/^ *//g;
    $l =~ s/ *$//g;
    next if($l eq "");
    if($l !~ m/>$/ || $l =~ m/^\s*<Help>\s*$/) { $buffer .= " ".$l; next; }
    if($buffer && $l =~ m/>$/) { $l = "$buffer $l"; $buffer=""; }
    $l =~ s/<!--.*-->//g;
    $l =~ s/ *$//g;
    print $l,"\n" if($l);
  }
  close(FH);
  print $buffer if($buffer);
  print "\n"; # One empty line between products
}
print "</ProductList>\n";
