##############################################
# $Id$
package main;

use strict;
use warnings;
use SetExtensions;

sub
dummy_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "dummy_Set";
  $hash->{DefFn}     = "dummy_Define";
  no warnings 'qw';
  my @attrList = qw(
    disable
    disabledForIntervals
    readingList
    setExtensionsEvent:1,0
    setList
    useSetExtensions
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." $readingFnAttributes";
}

###################################
sub
dummy_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "no set value specified" if(int(@a) < 1);
  my $setList = AttrVal($name, "setList", " ");
  $setList =~ s/\n/ /g;

  if(AttrVal($name,"useSetExtensions",undef)) {
    my $a0 = $a[0]; $a0 =~ s/([.?*])/\\$1/g;
    if($setList !~ m/\b$a0\b/) {
      unshift @a, $name;
      return SetExtensions($hash, $setList, @a) 
    }
    SetExtensionsCancel($hash);
  } else {
    return "Unknown argument ?, choose one of $setList" if($a[0] eq "?");
  }

  return undef
    if($attr{$name} &&  # Avoid checking it if only STATE is inactive
       ($attr{$name}{disable} || $attr{$name}{disabledForIntervals}) &&
       IsDisabled($name));

  my @rl = split(" ", AttrVal($name, "readingList", ""));
  my $doRet;
  eval {
    if(@rl && grep /^$a[0]$/, @rl) {
      my $v = shift @a;
      readingsSingleUpdate($hash, $v, join(" ",@a), 1);
      $doRet = 1;
    }
  };
  return if($doRet);

  my $v = join(" ", @a);
  Log3 $name, 4, "dummy set $name $v";

  $v = $hash->{SetExtensionsCommand}
        if($hash->{SetExtensionsCommand} &&
           AttrVal($name, "setExtensionsEvent", undef));
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
=item helper
=item summary    dummy device
=item summary_DE dummy Ger&auml;t
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
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a name="readingList">readingList</a><br>
      Space separated list of readings, which will be set, if the first
      argument of the set command matches one of them.</li>

    <li><a name="setList">setList</a><br>
      Space separated list of commands, which will be returned upon "set name
      ?", so the FHEMWEB frontend can construct a dropdown and offer on/off
      switches. Example: attr dummyName setList on off </li>

    <li><a name="useSetExtensions">useSetExtensions</a><br>
      If set, and setList contains on and off, then the
      <a href="#setExtensions">set extensions</a> are available.<br>
      Side-effect: if set, only the specified parameters are accepted, even if
      setList contains no on and off.</li>

    <li><a name="setExtensionsEvent">setExtensionsEvent</a><br>
      If set, the event will contain the command implemented by SetExtensions
      (e.g. on-for-timer 10), else the executed command (e.g. on).</li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html

=begin html_DE

<a name="dummy"></a>
<h3>dummy</h3>
<ul>

  Definiert eine Pseudovariable, der mit <a href="#set">set</a> jeder beliebige
  Wert zugewiesen werden kann.  Sinnvoll zum Programmieren.
  <br><br>

  <a name="dummydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; dummy</code>
    <br><br>

    Beispiel:
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
    Weist einen Wert zu.
  </ul>
  <br>

  <a name="dummyget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="dummyattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a name="readingList">readingList</a><br>
      Leerzeichen getrennte Liste mit Readings, die mit "set" gesetzt werden
      k&ouml;nnen.</li>

    <li><a name="setList">setList</a><br>
      Liste mit Werten durch Leerzeichen getrennt. Diese Liste wird mit "set
      name ?" ausgegeben.  Damit kann das FHEMWEB-Frontend Auswahl-Men&uuml;s
      oder Schalter erzeugen.<br> Beispiel: attr dummyName setList on off </li>

    <li><a name="useSetExtensions">useSetExtensions</a><br>
      Falls gesetzt, und setList enth&auml;lt on und off, dann sind die <a
      href="#setExtensions">set extensions</a> verf&uuml;gbar.<br>
      Seiteneffekt: falls gesetzt, werden nur die spezifizierten Parameter
      akzeptiert, auch dann, wenn setList kein on und off enth&auml;lt.</li>

    <li><a name="setExtensionsEvent">setExtensionsEvent</a><br>
      Falls gesetzt, enth&auml;lt das Event den im SetExtensions
      implementierten Befehl (z.Bsp. on-for-timer 10), sonst den
      Ausgef&uuml;rten (z.Bsp. on).</li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html_DE

=cut
