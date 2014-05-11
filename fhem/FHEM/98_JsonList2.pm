################################################################
# $Id$
################################################################

package main;
use strict;
use warnings;
use POSIX;

sub CommandJsonList2($$);

#####################################
sub
JsonList2_Initialize($$)
{
  my %lhash = ( Fn=>"CommandJsonList2",
                Hlp=>"[<devspec>],list definitions as JSON" );
  $cmds{jsonlist2} = \%lhash;
}


#####################################
sub
JsonList2_Escape($)
{
  my $a = shift;
  return "null" if(!defined($a));
  my %esc = (
    "\n" => '\n',
    "\r" => '\r',
    "\t" => '\t',
    "\f" => '\f',
    "\b" => '\b',
    "\"" => '\"',
    "\\" => '\\\\',
    "\'" => '\\\'',
  );
  $a =~ s/([\x22\x5c\n\r\t\f\b])/$esc{$1}/eg;
  return $a;
}

sub
JsonList2_dumpHash($$$$$)
{
  my ($name, $h, $isReading, $si, $next) = @_;
  my $ret = "";
  
  $ret .= "    \"$name\": {\n";
  my @arr = grep { $si || $_ !~ m/^\./ } sort keys %{$h};
  @arr = grep { !ref($h->{$_}) } @arr if(!$isReading);

  for(my $i2=0; $i2 < @arr; $i2++) {
    my $k = $arr[$i2];
    $ret .= "      \"".JsonList2_Escape($k)."\": ";
    if($isReading) {
      $ret .= "{ \"Value\":\"".JsonList2_Escape($h->{$k}{VAL})."\",";
      $ret .=   " \"Time\":\"".JsonList2_Escape($h->{$k}{TIME})."\" }";
    } else {
      $ret .= "\"".JsonList2_Escape($h->{$k})."\"";
    }
    $ret .= "," if($i2 < int(@arr)-1);
    $ret .= "\n";
  }
  $ret .= "    }".($next ? ",":"")."\n";
  return $ret;
}

#####################################
sub
CommandJsonList2($$)
{
  my ($cl, $param) = @_;
  my @d;
  my $ret;
  my $cnt=0;
  my $si = AttrVal("global", "showInternalValues", 0);

  if($param) {
    @d = devspec2array($param);

  } else {
    @d = keys %defs;
    $param="";

  }

  $ret  = "{\n";
  $ret .= "  \"Arg\":\"".JsonList2_Escape($param)."\",\n",
  $ret .= "  \"Results\": [\n";

  for(my $i1 = 0; $i1 < int(@d); $i1++) {
    my $d = $d[$i1];
    next if(IsIgnored($d));
    $cnt++;

    my $h = $defs{$d};
    my $n = $h->{NAME};
    next if(!$h || !$n);

    $ret .= "  {\n";
    $ret .= "    \"Name\":\"".JsonList2_Escape($n)."\",\n";
    $ret .= "    \"PossibleSets\":\"".JsonList2_Escape(getAllSets($n))."\",\n";
    $ret .= "    \"PossibleAttrs\":\"".JsonList2_Escape(getAllAttr($n))."\",\n";

    $ret .= JsonList2_dumpHash("Internals", $h,             0, $si, 1);
    $ret .= JsonList2_dumpHash("Readings",  $h->{READINGS}, 1, $si, 1);
    $ret .= JsonList2_dumpHash("Attributes",$attr{$d},      0, $si, 0);

    $ret .= "  }";
    $ret .= "," if($i1 < int(@d)-1);
    $ret .= "\n";
  }

  $ret .= "  ],\n";
  $ret .= "  \"totalResultsReturned\":$cnt\n";
  $ret .= "}\n";
  return $ret;
}

1;

=pod

=begin html

<a name="JsonList2"></a>
<h3>JsonList2</h3>
<ul>
  <code>jsonlist [&lt;devspec&gt;]</code>
  <br><br>
  This is a command, to be issued on the command line (FHEMWEB or telnet
  interface). Can also be called via HTTP by
  <ul>
  http://fhemhost:8083/fhem?cmd=jsonlist2&XHR=1
  </ul>
  Returns an JSON tree of the internal values, readings and attributes of the
  requested definitions.<br>
  <b>Note</b>: the old command jsonlist (without the 2 as suffix) is deprecated
  and will be removed in the future<br>
</ul>

=end html

=begin html_DE

<a name="JsonList2"></a>
<h3>JsonList2</h3>
<ul>
  <code>jsonlist [&lt;devspec&gt;]</code>
  <br><br>
  Dieses Befehl sollte in der FHEMWEB oder telnet Eingabezeile ausgef&uuml;hrt
  werden, kann aber auch direkt &uuml;ber HTTP abgerufen werden &uuml;ber 
  <ul>
  http://fhemhost:8083/fhem?cmd=jsonlist2&XHR=1
  </ul>
  Es liefert die JSON Darstellung der internen Variablen, Readings und
  Attribute zur&uuml;ck.
  <b>Achtung</b>: die alte Version dieses Befehls (jsonlist, ohne 2 am Ende) is
  &uuml;berholt, und wird in der Zukunft entfernt.<br>
</ul>

=end html_DE
=cut
