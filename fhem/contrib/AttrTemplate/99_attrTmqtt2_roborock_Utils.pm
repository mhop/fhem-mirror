##############################################
# $Id: attrTmqtt2_roborock_Utils.pm 2020-01-19 Beta-User $
#

package main;

use strict;
use warnings;

sub
attrTmqtt2_roborock_Utils_Initialize
{
  my $hash = shift;
  return;
}

# Enter you functions below _this_ line.

sub
attrTmqtt2_roborock_valetudo2svg
{
  my ($reading, $d, $filename) = @_;
  my %ret;

  if($d !~ m/height":(\d+),"width":(\d+).*?floor":\[(.*\])\]/) {
    $ret{$reading} = "ERROR: Unknown format";
    return \%ret;
  }
  my ($w,$h,$nums) = ($1, $2, $3);

  my $svg=<<"EOD";
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 20010904//EN" "http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd">
<svg version="1.0" xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" viewBox="0 0 $w $h">
<g fill="#000000" stroke="none">
  <rect x="0" y="0" width="$w" height="$h" stroke="black" stroke-width="1" fill="none"/>
EOD

  $nums =~ s/\[(\d+),(\d+)\]/
    $svg .= "<rect x=\"$1\" y=\"$2\" width=\"1\" height=\"1\"\/>\n";
    ""
  /xge;
  $svg .= "</g></svg>";

  if(!open FD,">$filename") {
    $ret{$reading} = "ERROR: $filename: $!";
    return \%ret;
  }
  print FD $svg;
  close(FD);
  $ret{$reading} = "Wrote $filename";
  return \%ret;
}



1;

=pod
=begin html

<a name="attrTmqtt2_roborock_Utils"></a>
<h3>attrTmqtt2_roborock_Utils</h3>
<ul>
  <b>Functions to support attrTemplates for roborock/valetudo</b><br> 
</ul>
<ul>
  <b>attrTmqtt2_roborock_valetudo2svg</b><br>
  <code>attrTmqtt2_roborock_valetudo2svg($$$)</code><br>
  Parameters are 
  <ul>
    <li>map_data</li> 
    <li>$EVENT</li> 
    <li>SVG-filename and path</li> 
  </ul>
  See Rudolf Koenig's original post <a href https://forum.fhem.de/index.php/topic,104687.msg986304.html#msg986304>here</a>.
</ul><br>
=end html
=cut
