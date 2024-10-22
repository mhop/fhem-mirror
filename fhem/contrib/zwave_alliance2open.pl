#!/usr/bin/perl


# convert ZWAVE-Alliance XML description file into openzwacve format, which can
# be digested by the FHEM ZWave module. Note: only the config parameters are converted.

if($#ARGV != -1) {
  print STDERR "Usage:  perl zwave_alliance2open.pl < zwavealliance.xml > openzwave.xml\n";
  exit(1);
}

my ($inTag, $name,$desc,$pnum,$size,$dflt,$min,$max);
print "<Product sourceFile=\"changeme\">\n";
print "  <CommandClass id=\"112\">\n";

while(my $l = <>) {
  $inTag = 1 if($l =~ /<ConfigurationParameterExport>/);
  $inTag = 0 if($l =~ /<ConfigurationParameterValues>/);
  if($inTag) {
    $name = $1 if($l =~ m/<Name>(.*)<\/Name>/);
    $desc = $1 if($l =~ m/<Description>(.*)<\/Description>/);
    $pnum = $1 if($l =~ m/<ParameterNumber>(.*)<\/ParameterNumber>/);
    $size = $1 if($l =~ m/<Size>(.*)<\/Size>/);
    $dflt = $1 if($l =~ m/<DefaultValue>(.*)<\/DefaultValue>/);
    $min  = $1 if($l =~ m/<minValue>(.*)<\/minValue>/);
    $max  = $1 if($l =~ m/<maxValue>(.*)<\/maxValue>/);
  }

  if($l =~ /<\/ConfigurationParameterExport>/) {
    print "    <Value genre=\"config\" index=\"$pnum\" label=\"$name\" size=\"$size\" type=\"byte\" value=\"$dflt\" min=\"$min\" max=\"$max\">\n";
    print "      <Help>$desc</Help>\n";
    print "    </Value>\n";
    $inTag = 0;
  }
}

print "  </CommandClass>\n";
print "</Product>\n";
