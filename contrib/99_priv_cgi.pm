##############################################
package main;

# call it whith http://localhost:8083/fhem/privcgi

use strict;
use warnings;

sub priv_cgi_Initialize($)
{
  $data{FWEXT}{"/privcgi"} = "priv_cgi_callback";
}

sub
priv_cgi_callback($$)
{
  my ($htmlarg) = @_;
  Log 1, "Got $htmlarg";
  return ("text/html; charset=ISO-8859-1", "Hello World");
}

1;
