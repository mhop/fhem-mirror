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
  return "" if(!$a);
  $a =~ s/\\\n/<br>/g;  # Multi-line
  $a =~ s/&/&amp;/g;
  $a =~ s/"/&quot;/g;
  $a =~ s/</&lt;/g;
  $a =~ s/>/&gt;/g;
  $a =~ s/([^ -~])/sprintf("#%02x;", ord($1))/ge;
  return $a;
}

#####################################
sub
CommandXmlList($$)
{
  my ($cl, $param) = @_;
  my $str = "<FHZINFO>\n";
  my $lt = "";

  delete($modules{""}) if(defined($modules{""}));
  for my $d (sort { my $x = $modules{$defs{$a}{TYPE}}{ORDER} cmp
    		            $modules{$defs{$b}{TYPE}}{ORDER};
    		    $x = ($a cmp $b) if($x == 0); $x; } keys %defs) {

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
          next if(!$h->{VAL} || !$h->{TIME});
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
