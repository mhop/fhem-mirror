# $Id$

package main;
use strict;
use warnings;

sub mark_Initialize($$) {
  $cmds{mark} = {  Fn  => "CommandMark",
                   Hlp =>"<TEMPORARY|VOLATILE>,mark devices"};
}

sub CommandMark($$)
{
  my ($cl, $param) = @_;
  my ($devspec,@marks) = split (" ",$param);
  my @devices = devspec2array($devspec,undef);
  my $ret = "";
  
  foreach my $m (@marks) {
    $m = uc($m);
    next if( $m ne "TEMPORARY" && $m ne "VOLATILE" );
    foreach my $d (@devices){
      $defs{$d}{$m} = 1; 
      $ret .= "$d marked as $m\n";
    }
  }  
  return $ret;
}

1;

=pod
=item helper
=item summary    mark devices for TEMPORARY or VOLATILE
=item summary_DE markiert Ger&auml;te als TEMPORARY oder VOLATILE
=item command
=begin html

<a name="mark"></a>
<h3>mark</h3>
<ul>
  <code>mark &lt;devspec&gt; &lt;TEMPORARY|VOLATILE&gt;</code>
  <br><br>
</ul>

=end html

=cut
