# $Id$

package main;
use strict;
use warnings;

sub Deletefile_Initialize($$) {

  $cmds{deletefile} = {  Fn => "CommandDeletefile",
                      Hlp=>"[filename],delete file"};
}

sub CommandDeletefile($$)
{
  my ($cl, $param) = @_;
  return "It is not allowed to delete the configuration file fhem.cfg." if ($param =~ m/fhem.cfg/);

  my $file = FW_fileNameToPath($param);
  return "File $param not found." unless -f $file;

  eval { unlink $file; };
  return "Error: $@" if $@;

  return "File $file deleted.";
}

1;

=pod
=item command
=begin html

<a name="deletefile"></a>
<h3>deletefile</h3>
<ul>
  <code>deletefile &lt;filename&gt;</code><br/>
  <br/>Delete a file in filesystem.<br/>
  <br/>
  <li>File must be listed in "Edit files"</li>
  <li>File fhem.cfg must not be deleted.</li>
  <li>Wildcards are not evaluated.</li>
</ul>

=end html

=cut
