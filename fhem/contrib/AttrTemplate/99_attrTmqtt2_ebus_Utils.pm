##############################################
# $Id: attrTmqtt2_ebus_Utils.pm 2020-01-18 Beta-User $
#

package main;

use strict;
use warnings;

sub
attrTmqtt2_ebus_Utils_Initialize
{
  my $hash = shift;
  return;
}

# Enter you functions below _this_ line.

sub
attrTmqtt2_ebus_createBarView {
  my ($val,$maxValue,$color) = @_;
  $maxValue = $maxValue//100;
  $color = $color//"red";
  my $percent = $val / $maxValue * 100;
  # Definition des valueStyles
  my $stylestring = 'style="'.
    'width: 200px; '.
    'text-align:center; '.
    'border: 1px solid #ccc ;'. 
    "background-image: -webkit-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '.
    "background-image:    -moz-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '. 
    "background-image:     -ms-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '. 
    "background-image:      -o-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '. 
    "background-image:         linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%);"';
    # Rückgabe des definierten Strings
  return $stylestring;
}

1;

=pod
=begin html

<a name="attrTmqtt2_ebus_Utils"></a>
<h3>attrTmqtt2_ebus_Utils</h3>
<ul>
  <b>Functions to support attrTemplates for ebusd</b><br> 
</ul>
<ul>
  <b>attrTmqtt2_ebus_createBarView</b><br>
  <code>attrTmqtt2_ebus_createBarView($,$$)</code><br>
  Parameters are 
  <ul>
    <li>$value (required)</li> 
    <li>$maxvalue (optional), defaults to 100</li> 
    <li>$color, (optional), defaults to red</li> 
  </ul>
</ul><br>
=end html
=cut
