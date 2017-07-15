# $Id: 98_unmark.pm 13246 2017-01-26 19:24:51Z betateilchen $

package main;
use strict;
use warnings;

sub unmark_Initialize($$) {
  $cmds{unmark} = {  Fn  => "CommandUnmark",
                   Hlp =>"<TEMPORARY|VOLATILE>,unmark devices"};
}

sub CommandUnmark($$)
{
  my ($cl, $param) = @_;
  my ($devspec,@marks) = split (" ",$param);
  my @devices = devspec2array($devspec,undef);
  my $ret = "";
  
  foreach my $m (@marks) {
    $m = uc($m);
    next if( $m ne "TEMPORARY" && $m ne "VOLATILE" );
    foreach my $d (@devices){
      delete $defs{$d}{$m}; 
      $ret .= "$d unmarked as $m\n";
    }
  }  
  return $ret;
}

1;

=pod
=item command
=item summary    mark devices for TEMPORARY or VOLATILE
=item summary_DE markiert Ger&auml;te als TEMPORARY oder VOLATILE
=item command
=begin html

<a name="unmark"></a>
<h3>unmark</h3>
<ul>
  <code>unmark &lt;devspec&gt; &lt;TEMPORARY|VOLATILE&gt;</code>
  <br><br>
</ul>

=end html

=cut
