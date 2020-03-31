# $Id$

package main;
use strict;
use warnings;

sub count_Initialize {
  $cmds{count} = {  Fn => "CommandCount",
                      Hlp=>"[filter],count devices"};
}

sub CommandCount
{
  my ($cl, $param) = @_;
  my $str = "";
  my $fill = $str;
  my $n    = 0;
  my $raw  = $n;
    
  if(!$param) { # List of all devices
    $n = keys %defs;
    $fill = "s" if $n != 1;
    $str = "\nCount: $n device$fill in total.\n";
  } else { # devspecArray
    $raw = $param =~ s/ raw$//i;
    $n       = 0;
    my @list = devspec2array($param,$cl);
    $n       = int(@list);
    if ($n == 1) {
       $n = (defined($defs{$list[0]})) ? 1 : "No";
       $fill = "s" if ($n eq "No"); 
    } else {
       $fill    = "s" 
    }
    $str     = "\nCount: $n device$fill for devspec $param\n";
  }

  return $str unless $raw;
  return $n;
}

1;

=pod
=item summary    count devices based on devspec
=item summary_DE z&auml;hlt Ger&auml;te, die einer devspec entsprechen
=item command
=begin html

<a name="count"></a>
<h3>count</h3>
<ul>
  <code>count [devspec] [raw]</code>
  <br><br>
  Count devices specified by devspec.<br/>
  If no devspec given, count will return number of totally defined devices.<br/>
  Count will return the plain number of devices if "raw" passed as last part of the command.<br/>
  This is useful for processing the number of devices itself.<br/>
</ul>

=end html

=cut
