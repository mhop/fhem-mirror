##############################################
# $Id$
package main;

use strict;
use warnings;

sub
dummy_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "dummy_Set";
  $hash->{DefFn}     = "dummy_Define";
  $hash->{AttrList}  = "setList ". $readingFnAttributes;
}

###################################
sub
dummy_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "no set value specified" if(int(@a) < 1);
  my $setList = AttrVal($name, "setList", " ");
  return "Unknown argument ?, choose one of $setList" if($a[0] eq "?");

  my $v = join(" ", @a);
  Log3 $name, 4, "dummy set $name $v";

  readingsSingleUpdate($hash,"state",$v,1);
  return undef;
}

sub
dummy_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use define <name> dummy" if(int(@a) != 2);
  return undef;
}

1;

=pod
=begin html

<a name="dummy"></a>
<h3>dummy</h3>
<ul>

  Define a dummy. A dummy can take via <a href="#set">set</a> any values.
  Used for programming.
  <br><br>

  <a name="dummydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; dummy</code>
    <br><br>

    Example:
    <ul>
      <code>define myvar dummy</code><br>
      <code>set myvar 7</code><br>
    </ul>
  </ul>
  <br>

  <a name="dummyset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt</code><br>
    Set any value.
  </ul>
  <br>

  <a name="dummyget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="dummyattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="setList">setList</a><br>
        Space separated list of commands, which will be returned upon "set name ?",
        so the FHEMWEB frontend can construct a dropdown and offer on/off
        switches. Example: attr dummyName setList on off
        </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html
=cut
