# $Id$

package main;
use strict;
use warnings;

sub template_Initialize($$) {

  $cmds{template} = 
          { Fn=>"CommandTemplate",
            Hlp=>"[use] <filename> [<param1>=<value1> [<param2>=<value2> [...]]],use a template" };
}
            
sub EvaluateTemplate($$) {
  my ($filename, $args)= @_;

  # load template from file
  my ($err, @result)= FileRead($filename);
  return ($err, undef, undef, undef) if(defined($err));
  
  # remove trailing newlines and empty/whitespace lines
  @result= grep /\S/, map { s/\r?\n$//; $_ } @result;
  
  # we enumerate the parameters for the show command
  my %p;
  map { while(m/\%(\w+)%/g) { $p{$1}= 1 } } @result;
  my @params= keys %p;
  
  # do parameter substition
  Log 5, "Using template from file $filename.";
  my ($valuesref,$kvref)= parseParams($args);
  my @values= @{$valuesref}; my %kv= %{$kvref};
  return "parameters must be of form <param>=<value>" unless($#values<0);
  foreach my $key (keys %kv) {
    my $value= $kv{$key};
    my $count= 0;
    map { $count += s/\%$key\%/$value/g } @result;
    Log 5, "Using $value for parameter %$key% in template $filename $count time(s).";
  }

  # count and enumerate not substituted parameters
  my $count= 0; %p= ();
  map { while(m/\%(\w+)%/g) { $p{$1}= 1; $count++ } } @result;
  my $warn= "$count parameter(s) not substituted in template $filename: " . 
    join(" ", keys %p) if($count);
  
  # return the result
  return (undef, $warn, \@params, \@result);
}

sub CommandTemplate($$) {
  my ($cl, $param) = @_;
  my $usage= "Usage: template [use|show] <filename> [<param1>=<value1> [<param2>=<value2> [...]]]";
  
  # get the arguments and do first sanity checks
  my @args= split("[ \t]]*", $param);
  return $usage if($#args< 0);
  my $action= "use";
  $action= shift @args if($args[0] eq "use" || $args[0] eq "show"); 
  return $usage if($#args< 0);
  my $filename= shift @args;
  
  # evaluate the template
  my ($error, $warn, $paramsref, $resultref)= EvaluateTemplate($filename, join(" ", @args));
  return $error if(defined($error));
  # we inform the user about missing substitutions but
  # we do not make this an error because the actual occurence %...% might be intentional
  Log 5, $warn if(defined($warn));

  if($action eq "use") {
    my @ret;
    my $bigcmd = "";
    ${main::rcvdquit} = 0;
    foreach my $l (@{$resultref}) {
      if($l =~ m/^(.*)\\ *$/) {       # Multiline commands
        $bigcmd .= "$1\n";
      } else {
        my $tret = AnalyzeCommandChain($cl, $bigcmd . $l);
        push @ret, $tret if(defined($tret));
        $bigcmd = "";
      }
      last if(${main::rcvdquit});
    }
    return join("\n", @ret) if(@ret);
    return undef;
  } elsif($action eq "show") {
    return(
      "template: $filename" .
      "\nresult:\n" . join("\n", @{$resultref}) .
      "\nparameters: " . join(" ", @{$paramsref})
    );
  } else {
    return undef; # we never get here
  }
 
}


1;

=pod
=item command
=item summary    use a template for repetitive configurations and commands.
=item summary_DE verwendet ein Template f&uuml;r wiederkehrende Konfigurationen und Kommandos.
=begin html

<a name="template"></a>
<h3>template</h3>
<ul>
  <code>template [use|show] &lt;filename&gt; [&lt;param1&gt;=&lt;value1&gt; [&lt;param2&gt;=&lt;value2&gt; [...]]]</code>
  <br><br>
  Includes a file with parameter substitution, i.e. read the file and process every line as a FHEM command.
  For any given parameter/value pair <code>&lt;param&gt;=&lt;value&gt;</code> on the command line, 
  a literal <code>%&lt;param&gt;%</code> in the file is replaced by &lt;value&gt; before executing the command.<br><br>

  This can be used to to code recurring definitions of one or several devices only once and use it many times. 
  <code>template show ..</code> shows what would be done, including a parameter listing, while 
  <code>template use ...</code> actually does the job. The word <code>use</code> can be omitted.<br><br>
  
  <b>Example</b><br><br>
  
  File <i>H.templ</i>:<br><br>

  <code>
  define %name% FHT %fhtcode%<br>
  attr %name% IODev CUN<br>
  attr %name% alias %alias%<br>
  attr %name% group %group%<br>
  attr %name% icon icoTempHeizung.png<br>
  attr %name% room %room%,Anlagen/Heizungen<br>
  <br>
  define watchdog.%name% watchdog %name% 00:15:00 SAME set %name% report2 255<br>
  attr watchdog.%name% group %group%<br>
  attr watchdog.%name% room Control/Heizungen<br>
  <br>
  define %name%.log FileLog /opt/fhem/log/%name%-%Y%m.log %name%:.*<br>
  attr %name%.log group %group%<br>
  attr %name%.log icon icoLog.png<br>
  attr %name%.log logtype fht<br>
  attr %name%.log room Control/Heizungen<br>
  <br> 
  define %name%.weblink SVG %name%.log:%name%:CURRENT<br>
  attr %name%.weblink label sprintf("Temperatur: %.0f °C (%.0f °C .. %.0f °C)  Aktor: %.0f %% (%.0f %% .. %.0f %%)", $data{currval1}, $data{min1}, $data{max1}, $data{currval2}, $data{min2}, $data{max2} )<br>
  attr %name%.weblink room %room%<br>
  attr %name%.weblink alias %alias%<br>
  </code><br><br>
  
  Configuration:<br><br>
  
  <code>te H.templ name=3.dz.hzg fhtcode=3f4a alias=Dachzimmerheizung group=Heizung room=Dachzimmer</code><br><br>
  
  Please note that although %Y% in the FileLog definition looks like a parameter, it is not substituted since no parameter
  Y is given on the command line. You get detailed information at verbosity level 5 when you run the command.
 
</ul>

=end html

=begin html_DE

<a name="template"></a>
<h3>template</h3>
<ul>
  <code>template [use|show] &lt;filename&gt; [&lt;param1&gt;=&lt;value1&gt; [&lt;param2&gt;=&lt;value2&gt; [...]]]</code>
  <br><br>
  Includes a file with parameter substitution, i.e. read the file and process every line as a FHEM command.
  For any given parameter/value pair <code>&lt;param&gt;=&lt;value&gt;</code> on the command line, 
  a literal <code>%&lt;param&gt;%</code> in the file is replaced by &lt;value&gt; before executing the command.<br><br>

  This can be used to to code recurring definitions of one or several devices only once and use it many times. 
  <code>template show ..</code> shows what would be done, including a parameter listing, while 
  <code>template use ...</code> actually does the job. The word <code>use</code> can be omitted.<br><br>
  
  <b>Example</b><br><br>
  
  File <i>H.templ</i>:<br><br>

  <code>
  define %name% FHT %fhtcode%<br>
  attr %name% IODev CUN<br>
  attr %name% alias %alias%<br>
  attr %name% group %group%<br>
  attr %name% icon icoTempHeizung.png<br>
  attr %name% room %room%,Anlagen/Heizungen<br>
  <br>
  define watchdog.%name% watchdog %name% 00:15:00 SAME set %name% report2 255<br>
  attr watchdog.%name% group %group%<br>
  attr watchdog.%name% room Control/Heizungen<br>
  <br>
  define %name%.log FileLog /opt/fhem/log/%name%-%Y%m.log %name%:.*<br>
  attr %name%.log group %group%<br>
  attr %name%.log icon icoLog.png<br>
  attr %name%.log logtype fht<br>
  attr %name%.log room Control/Heizungen<br>
  <br> 
  define %name%.weblink SVG %name%.log:%name%:CURRENT<br>
  attr %name%.weblink label sprintf("Temperatur: %.0f °C (%.0f °C .. %.0f °C)  Aktor: %.0f %% (%.0f %% .. %.0f %%)", $data{currval1}, $data{min1}, $data{max1}, $data{currval2}, $data{min2}, $data{max2} )<br>
  attr %name%.weblink room %room%<br>
  attr %name%.weblink alias %alias%<br>
  </code><br><br>
  
  Configuration:<br><br>
  
  <code>te H.templ name=3.dz.hzg fhtcode=3f4a alias=Dachzimmerheizung group=Heizung room=Dachzimmer</code><br><br>
  
  Please note that although %Y% in the FileLog definition looks like a parameter, it is not substituted since no parameter
  Y is given on the command line. You get detailed information at verbosity level 5 when you run the command.
  
</ul>

=end html_DE

=cut
