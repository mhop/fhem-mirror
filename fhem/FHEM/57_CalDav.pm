##############################################
# $Id$
package main;

use strict;
use warnings;
use HttpUtils;
use XML::LibXML;
use Data::Dumper;
use English qw(-no_match_vars); 

sub CalDav_Initialize($$)
{
  $cmds{caldav} = {  Fn => "CommandCaldav",
                      Hlp=>"url"};
}

sub CommandCaldav($$) {
  my ($cl, $params) = @_;

  my ($url,$options) = split (" ",$params,2);
  $options //= "";
  $url .= "/" unless $url =~ /\/$/;

  my $hash = ();
  $hash->{URL}          = $url;
  $hash->{NAME}         = "caldav_";
  $hash->{OPTIONS}      = $options;

  my %hu_hash = ();
  $hu_hash{hash}        = $hash;
  $hu_hash{url}         = $url;
  $hu_hash{hideurl}     = 1;
  $hu_hash{timeout}     = 30;
  $hu_hash{noshutdown}  = 1;
  $hu_hash{header}      = "Depth: 1\r\nContent-Type: application/xml; charset=utf-8";
  $hu_hash{method}      = "PROPFIND";
  $hu_hash{callback}    = \&CalDav_Process;
  HttpUtils_NonblockingGet(\%hu_hash);
}

sub CalDav_Process($$$) {

  my ($param, $errmsg, $data) = @_;
  my $hash    = $param->{hash};
  my $name    = $hash->{NAME};
  my $url     = $hash->{URL};
  my $options = $hash->{OPTIONS};
    
  my $d = XML::LibXML->load_xml(string => $data);

  foreach my $r ($d->findnodes('/d:multistatus/d:response/d:href')) {
    my $u = $r->to_literal();
    next if ($url =~ /$u/);
    next if ($u =~ /(inbox|outbox)\/$/);
    my @a = split(/\//,$u);
    my $t = "define $name$a[-1] Calendar ical url $url$a[-1]$options";
    fhem  $t;  
    $t =~ /https?:\/\/([^^\/]*)/;
    substr($t, $LAST_MATCH_START[1], $LAST_MATCH_END[1] - $LAST_MATCH_START[1], "..."); 
    Log3 ("caldav",3,"Creating Calendar: $t");
  }
}

1;

=pod
=item summary    create single Calendar devices from webdav server
=item summary_DE erzeugt einzelne Calendar devices aus einem webdav Server
=item command
=begin html

<a name="CalDav"></a>
<h3>caldav</h3>
<ul>
  <code>caldav &lt;url&gt; [&lt;options&gt;]</code>
  <br/><br/>
  create single Calendar devices from webdav resources.<br/>
  <br/>
  Example for ownCloud / Nextcloud:<br/>
  <br/>
  <code>caldav https://&lt;user&gt;:&lt;password&gt;@my.cloudServer.de/remote.php/dav/calendars/&lt;user&gt;/ /?export</code><br/>
  <br/>
  This command module requires the perl library XML::LibXML<br/>
</ul>

=end html

=cut
