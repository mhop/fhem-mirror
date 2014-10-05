#!/usr/bin/perl

# Usage: contrib/zwave_configconvert.pl priv/zwave/open-zwave-read-only/config |
#        gzip > FHEM/lib/openzwave_deviceconfig.xml.gz
#

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
    $l =~ s/^<Product .*/<Product sourceFile="$name">/;
    $l =~ s/\r//g;
    $l =~ s/^[ \t]*//g;
    $l =~ s/[ \t]*$//g;
    next if($l eq "");
    if($l !~ m/>$/ || $l =~ m/^<Help>$/) { $buffer .= " ".$l; next; }
    if($buffer && $l =~ m/>$/) { $l = "$buffer $l"; $buffer=""; }
    $l =~ s/<!--.*-->//g;
    $l =~ s/^[ \t]*//g;
    $l =~ s/[ \t]*$//g;
    print "$l\n" if($l);
  }
  close(FH);
  print $buffer if($buffer);
  print "\n"; # Some files are not NL terminated!
}
print "</ProductList>\n";
