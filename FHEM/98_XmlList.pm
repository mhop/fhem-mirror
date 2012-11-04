##############################################
# $Id$
package main;
use strict;
use warnings;
use POSIX;

sub CommandXmlList($$);
sub XmlEscape($);


#####################################
sub
XmlList_Initialize($$)
{
  my %lhash = ( Fn=>"CommandXmlList",
                Hlp=>",list definitions and status info as xml" );
  $cmds{xmllist} = \%lhash;
}


#####################################
sub
XmlEscape($)
{
  my $a = shift;
  return "" if(!defined($a));
  $a =~ s/\\\n/<br>/g;  # Multi-line
  $a =~ s/&/&amp;/g;
  $a =~ s/"/&quot;/g;
  $a =~ s/</&lt;/g;
  $a =~ s/>/&gt;/g;
  # Not needed since we've gone UTF-8
  # $a =~ s/([^ -~])/sprintf("&#%02x;", ord($1))/ge;
  # Esacape characters 0-31, as they are not part of UTF-8
  $a =~ s/(\x00-\x19)//g;

  return $a;
}

#####################################
sub
CommandXmlList($$)
{
  my ($cl, $param) = @_;
  my $str = "<FHZINFO>\n";
  my $lt = "";
  my %filter;

  if($param) {
   my @arr = devspec2array($param);
   map { $filter{$_} = 1 } @arr;
  }
  delete($modules{""}) if(defined($modules{""})); # ???

  for my $d (sort { my $x = $modules{$defs{$a}{TYPE}}{ORDER}.$defs{$a}{TYPE} cmp
    		            $modules{$defs{$b}{TYPE}}{ORDER}.$defs{$b}{TYPE};
    		    $x = ($a cmp $b) if($x == 0); $x; } keys %defs) {

      next if(IsIgnored($d) || (%filter && !$filter{$d}));
      my $p = $defs{$d};
      my $t = $p->{TYPE};
      if($t ne $lt) {
        $str .= "\t</${lt}_LIST>\n" if($lt);
        $str .= "\t<${t}_LIST>\n";
      }
      $lt = $t;
 
      my $a1 = XmlEscape($p->{STATE});
      my $a2 = XmlEscape(getAllSets($d));
      my $a3 = XmlEscape(getAllAttr($d));
 
      $str .= "\t\t<$t name=\"$d\" state=\"$a1\" sets=\"$a2\" attrs=\"$a3\">\n";
 
      foreach my $c (sort keys %{$p}) {
        next if(ref($p->{$c}));
        $str .= sprintf("\t\t\t<INT key=\"%s\" value=\"%s\"/>\n",
                        XmlEscape($c), XmlEscape($p->{$c}));
      }
      $str .= sprintf("\t\t\t<INT key=\"IODev\" value=\"%s\"/>\n",
                                        $p->{IODev}{NAME}) if($p->{IODev});
 
      foreach my $c (sort keys %{$attr{$d}}) {
        $str .= sprintf("\t\t\t<ATTR key=\"%s\" value=\"%s\"/>\n",
                        XmlEscape($c), XmlEscape($attr{$d}{$c}));
      }
 
      my $r = $p->{READINGS};
      if($r) {
        foreach my $c (sort keys %{$r}) {
          my $h = $r->{$c};
          next if(!defined($h->{VAL}) || !defined($h->{TIME}));
          $str .=
            sprintf("\t\t\t<STATE key=\"%s\" value=\"%s\" measured=\"%s\"/>\n",
                XmlEscape($c), XmlEscape($h->{VAL}), $h->{TIME});
        }
      }
      $str .= "\t\t</$t>\n";
  }
  $str .= "\t</${lt}_LIST>\n" if($lt);
  $str .= "</FHZINFO>\n";
  return $str;
}


1;

=pod
=begin html

<a name="xmllist"></a>
<h3>xmllist</h3>
<ul>
  <code>xmllist [devspec]</code>
  <br><br>
  Returns an XML tree of device definitions. <a href="#devspec">devspec</a> is
  optional, and restricts the list of devices if specified. 
  <br><br>
  Example:
  <pre>  fhem> xmllist
  &lt;FHZINFO&gt;
          &lt;internal_LIST&gt;
                  &lt;internal name="global" state="internal" sets=""
                            attrs="room configfile logfile ..."&gt;
                          &lt;INT key="DEF" value="&lt;no definition&gt;"/&gt;
                          &lt;INT key="NR" value="0"/&gt;
                          &lt;INT key="STATE" value="internal"/&gt;
      [...]

  </pre>
</ul>

=end html
=cut
