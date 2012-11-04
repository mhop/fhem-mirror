##############################################
# $Id$
package main;

use strict;
use warnings;

#####################################
sub
weblink_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "weblink_Define";
  $hash->{AttrList}= "fixedrange plotmode plotsize label title htmlattr";
}


#####################################
sub
weblink_Define($$)
{
  my ($hash, $def) = @_;
  my ($type, $name, $wltype, $link) = split("[ \t]+", $def, 4);
  my %thash = ( link=>1, fileplot=>1, dbplot=>1, image=>1, iframe=>1, htmlCode=>1 );
  
  if(!$link || !$thash{$wltype}) {
    return "Usage: define <name> weblink [" .
                join("|",sort keys %thash) . "] <arg>";
  }
  $hash->{WLTYPE} = $wltype;
  $hash->{LINK} = $link;
  $hash->{STATE} = "initial";
  return undef;
}

1;

=pod
=begin html

<a name="weblink"></a>
<h3>weblink</h3>
<ul>
  <a name="weblinkdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; weblink [link|fileplot|image|iframe|htmlCode]
                &lt;argument&gt;</code>
    <br><br>
    This is a placeholder used with webpgm2 to be able to integrate links
    into it, and to be able to put more than one gnuplot/SVG picture on one
    page.  It has no set or get methods.

    Examples:
    <ul>
      <code>define homepage weblink link http://www.fhem.de</code><br>
      <code>define webcam_picture weblink image http://w.x.y.z/current.jpg</code><br>
      <code>define interactive_webcam weblink iframe http://w.x.y.z/webcam.cgi</code><br>
      <code>define hr weblink htmlCode &lt;hr&gt</code><br>
      <code>define w_Frlink weblink htmlCode { WeatherAsHtml("w_Frankfurt") }</code><br>
      <code>define MyPlot weblink fileplot &lt;logdevice&gt;:&lt;gnuplot-file&gt;:&lt;logfile&gt;</code><br>
    </ul>
    <br>

    Notes:
    <ul>
      <li>Normally you won't have to define fileplot weblinks manually, as
          FHEMWEB makes it easy for you, just plot a logfile (see
          <a href="#logtype">logtype</a>) and convert it to weblink.  Now you
          can group these weblinks by putting them into rooms.  If you convert
          the current logfile to a weblink, it will always refer to the current
          file, even if its name changes regularly (and not the one you
          originally specified).</li>
	</ul>
  </ul>

  <a name="weblinkset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="weblinkget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="weblinkattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="htmlattr"></a>
    <li>htmlattr<br>
      HTML attributes to be used for link, image and iframe type of links. E.g.:<br>
      <ul>
        <code>
        define yw weblink wl_im1 iframe http://weather.yahooapis.com/forecastrss?w=650272&u=c<br>
        attr yw weblink htmlattr width="480" height="560"<br>
        </code>
      </ul>
      </li>
      <br>
    <li><a href="#fixedrange">fixedrange</a></li>
    <li><a href="#plotsize">plotsize</a></li>
    <li><a href="#plotmode">plotmode</a></li>
    <a name="label"></a>
    <li>label<br>
      Double-Colon separated list of values. The values will be used to replace
      &lt;L#&gt; type of strings in the .gplot file, with # beginning at 1
      (&lt;L1&gt;, &lt;L2&gt;, etc.). Each value will be evaluated as a perl
      expression, so you have access e.g. to the Value functions.<br><br>

      If the plotmode is gnuplot-scroll or SVG, you can also use the min, max,
      avg, cnt, sum, currval (last value) and currdate (last date) values of the
      individual curves, by accessing the corresponding values from the data
      hash, see the example below:<br>

      <ul>
        <li>Fixed text for the right and left axis:<br>
          <ul>
            <li>Fhem config:<br>
                attr wl_1 label "Temperature"::"Humidity"</li>
            <li>.gplot file entry:<br>
                set ylabel &lt;L1&gt;<br>
                set y2label &lt;L2&gt;</li>
          </ul></li>
        <li>Title with maximum and current values of the 1st curve (FileLog)
          <ul>
            <li>Fhem config:<br>
                attr wl_1 label "Max $data{max1}, Current $data{currval1}"</li>
            <li>.gplot file entry:<br>
                set title &lt;L1&gt;<br>
          </ul></li>
      </ul>
      </li>

    <a name="title"></a>
    <li>title<br>
      A special form of label (see above), which replaces the string &lt;TL&gt;
      in the .gplot file. It defaults to the filename of the logfile.
      </li>

  </ul>
  <br>

</ul>

=end html
=cut
