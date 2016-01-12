# $Id$

package main;
use strict;
use warnings;

sub version_Initialize($$) {

  $cmds{version} = {  Fn => "CommandVersion",
                      Hlp=>"[filter],print SVN version of loaded modules"};
}

#####################################
sub
CommandVersion($$)
{
  my ($cl, $param) = @_;

  my @ret;
  my $max = 0; 
  my $modpath = (exists($attr{global}{modpath}) ? $attr{global}{modpath} : "");
  my @files = map {$INC{$_}} keys %INC;
  push @files, $0; # path to fhem.pl
  push @ret, cfgDB_svnId() if(configDBUsed());
  foreach my $fn (@files) {
    next unless($fn =~ /^$modpath.?FHEM/ or $fn =~ /(?:^FHEM|fhem.pl$)/); # configDB 
    my $mod_name = ($fn=~ /[\/\\]([^\/\\]+)$/ ? $1 : $fn);
    next if($param && $mod_name !~ /$param/);
    next if(grep(/$mod_name/, @ret));
    Log 4, "Looking for SVN Id in module $mod_name";

    $max = length($mod_name) if($max < length($mod_name))

    my $line;
    
    if(!open(FH, $fn)) {
      $line = "$fn: $!";
      if(configDBUsed()){
        Log 4, "Looking for module $mod_name in configDB to find SVN Id";
        $line = cfgDB_Fileversion($fn,$line);
      }
    } else {
      while(<FH>) {
         if(/#.*\$Id\:[^\$\n\r].+\$/) {
           $line = $_;
           last;
         }
      }
      close(FH);
    }
    $line = "No Id found for $mod_name" unless($line);
    push @ret, $line;
  }
  
  @ret = map {/\$Id\: (\S+) (\S+) (.+?) \$/ ? sprintf("%-".$max."s %5d %s",$1,$2,$3) : $_} @ret; 
  @ret = sort {version_sortModules($a, $b)} grep {(defined($param) ? $_ =~ /$param/ : 1)} @ret;
  return "no loaded modules found that match: $param" if($param && !@ret);
  return sprintf("%-".$max."s %s","File","Rev   Last Change\n\n").
         trim(join("\n",  grep (($_ =~ /^fhem.pl|\d\d_/), @ret))."\n\n".
              join("\n",  grep (($_ !~ /^fhem.pl|\d\d_/), @ret))
             );
}

#####################################
sub version_sortModules($$)
{
    my ($a, $b) = @_;

    $a =~ s/^No Id found for //;
    $b =~ s/^No Id found for //;
    
    my @a_vals  = split(' ', $a);
    my @b_vals  = split(' ', $b);

    # fhem.pl always at top
    return -1 if($a_vals[0] eq "fhem.pl"); 
    return  1 if($b_vals[0] eq "fhem.pl");
    
    $a_vals[0] =~ s/^\d\d_//;
    $b_vals[0] =~ s/^\d\d_//;

    return uc($a_vals[0]) cmp uc($b_vals[0]);
}

1;

=pod
=begin html

<a name="version"></a>
<h3>version</h3>
<ul>
  <code>version [filter]</code>
  <br><br>
  List the version of fhem.pl and all loaded modules. The optional parameter
  can be used to filter the ouput.

  <br><br>
  Example output of "<code>version</code>":
  <ul>
    <code><br>
        File&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Rev&nbsp;&nbsp;&nbsp;Last&nbsp;Change<br><br>
        fhem.pl&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10397&nbsp;2016-01-07&nbsp;08:36:49Z&nbsp;rudolfkoenig<br>
        90_at.pm&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10048&nbsp;2015-11-29&nbsp;14:51:40Z&nbsp;rudolfkoenig<br>
        98_autocreate.pm&nbsp;10165&nbsp;2015-12-13&nbsp;11:14:15Z&nbsp;rudolfkoenig<br>
        00_CUL.pm&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10146&nbsp;2015-12-10&nbsp;10:17:42Z&nbsp;rudolfkoenig<br>
        10_CUL_HM.pm&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10411&nbsp;2016-01-08&nbsp;15:18:17Z&nbsp;martinp876<br>
    </code>
  </ul>
  <br>
  Example output of "<code>version fhem</code>":
  <ul>
    <code><br>    
        File&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Rev&nbsp;&nbsp;&nbsp;Last&nbsp;Change<br><br>
        fhem.pl&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10397&nbsp;2016-01-07&nbsp;08:36:49Z&nbsp;rudolfkoenig<br>     
    </code>
  </ul>
</ul>

=end html

=begin html_DE

<a name="version"></a>
<h3>version</h3>
<ul>
  <code>version [filter]</code>
  <br><br>
  Gibt die Versionsinformation von fhem.pl und aller geladenen Module aus. Mit
  der optionalen Parameter kann man die Ausgabe filtern.

  <br><br>
  Beispiel der Ausgabe von "<code>version</code>":
  <ul>
    <code><br>    
        File&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Rev&nbsp;&nbsp;&nbsp;Last&nbsp;Change<br><br>
        fhem.pl&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10397&nbsp;2016-01-07&nbsp;08:36:49Z&nbsp;rudolfkoenig<br>
        90_at.pm&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10048&nbsp;2015-11-29&nbsp;14:51:40Z&nbsp;rudolfkoenig<br>
        98_autocreate.pm&nbsp;10165&nbsp;2015-12-13&nbsp;11:14:15Z&nbsp;rudolfkoenig<br>
        00_CUL.pm&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10146&nbsp;2015-12-10&nbsp;10:17:42Z&nbsp;rudolfkoenig<br>
        10_CUL_HM.pm&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10411&nbsp;2016-01-08&nbsp;15:18:17Z&nbsp;martinp876<br>
    </code>
  </ul>
  <br>
   Beispiel der Ausgabe von "<code>version fhem</code>":
  <ul>
    <code><br>    
        File&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Rev&nbsp;&nbsp;&nbsp;Last&nbsp;Change<br><br>
        fhem.pl&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10397&nbsp;2016-01-07&nbsp;08:36:49Z&nbsp;rudolfkoenig<br>     
    </code>
  </ul>
</ul>
=end html_DE

=cut
