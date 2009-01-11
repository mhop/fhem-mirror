##############################################
package main;

use strict;
use warnings;

#####################################
sub
weblink_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "weblink_Define";
  $hash->{AttrList}= "fixedrange plotmode plotsize label title";
}


#####################################
sub
weblink_Define($$)
{
  my ($hash, $def) = @_;
  my ($type, $name, $wltype, $link) = split("[ \t]+", $def, 4);
  my %thash = ( link=>1, fileplot=>1 );
  
  if(!$link || !$thash{$wltype}) {
    return "Usage: define <name> weblink [" . join("|",sort keys %thash) . "] <httplink>";
  }
  $hash->{WLTYPE} = $wltype;
  $hash->{LINK} = $link;
  $hash->{STATE} = "initial";
  return undef;
}

1;
