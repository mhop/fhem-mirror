##############################################
# $Id$

=for comment
##############################################
#
# 55_bshGezeiten.pm written by betateilchen
#
##############################################
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
##############################################
=cut

package main;

use strict;
use warnings;
use feature qw/switch/;

use HTML::TreeBuilder::XPath;

sub bshGezeiten_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}     = "bshG_Define";
  $hash->{UndefFn}   = "bshG_Undefine";
  $hash->{AttrFn}    = "bshG_Attr";
  $hash->{AttrList}  = "bsh_language:en,de ".
                       "bsh_numEntries ".
                       "bsh_skipOutdated:1,0 " .
                       "bsh_timeZone:legal,UTC,MEZ ".
                       "disabled:0,1 ".
                       $readingFnAttributes;
}

#http://www.bsh.de/cgi-bin/gezeiten/was_tab_e.pl?ort=DE__743P&zone=Legal+time+%B9&niveau=KN

sub bshG_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use define <name> bshGezeiten <location>" if(int(@a) != 3);

  $hash->{'.url'}       = "http://mobile.bsh.de/cgi-bin/gezeiten/was_mobil.pl?ort=__LOC__&zone=Gesetzliche+Zeit&niveau=KN";
  $hash->{'.url'} =~ s/__LOC__/$a[2]/;
  _bsh_pegel($hash);
  readingsSingleUpdate($hash, 'state', 'initialized', 1);
  return undef;
}

sub bshG_Undefine($) {
   my ($hash) = @_;
   RemoveInternalTimer($hash);
   return;
}   

sub bshG_Attr(@) {
	my @a = @_;
	my $hash = $defs{$a[1]};
	my ($cmd, $name, $attrName, $attrValue) = @a;
	$attrValue //= '';

	given($attrName){
		when("bsh_timeZone"){
			if ($cmd eq 'del'){
				delete $attr{$name}{$attrName};
				$attrValue = "Gesetzliche+Zeit";
			} else {
				$attrValue = "Gesetzliche+Zeit" if ($attrValue eq 'legal');
			}
			$hash->{'.url'} =~ s/&zone=.*&/&zone=$attrValue&/;
			RemoveInternalTimer($hash,'_bsh_pegel');
			_bsh_pegel($hash);
			return;
		}

		when("bsh_numEntries"){
			CommandDeleteReading(undef,"$name tidalInfo.*");
		}

		when("bsh_skipOutdated"){
			CommandDeleteReading(undef,"$name tidalInfo.*");
		}

		default {$attr{$name}{$attrName} = $attrValue;}
	}

	RemoveInternalTimer($hash,'_bsh_decode');
	RemoveInternalTimer($hash,'_bsh_pegel');
	if(IsDisabled($name)) {
		readingsSingleUpdate($hash, 'state', 'disabled', 0);
	} else {
		readingsSingleUpdate($hash, 'state', 'active', 0);
#		InternalTimer(gettimeofday()+1, "_bsh_pegel", $hash, 0);
		_bsh_pegel($hash);
	}
	return;
}

# --------------------------------------------------

sub _bsh_pegel($) {
   my ($hash) = @_;
   my $name = $hash->{NAME};
   Log3($hash,4,"$name: starting data retrieval");
   InternalTimer(gettimeofday()+3600, "_bsh_pegel", $hash, 0);
   HttpUtils_NonblockingGet({ 
      hash       => $hash,
      timeout    => 5,
      url        => $hash->{'.url'},
      callback   => \&_bsh_pegel_cb,
  })
}

sub _bsh_pegel_cb($){
  my ($param, $err, $content) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
     $hash->{'.content'} = $content;
  _bsh_decode($hash);   
}

sub _bsh_decode($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3($hash,4,"$name: starting data decoder");
  RemoveInternalTimer($hash,'_bsh_decode');
  InternalTimer(gettimeofday()+60, "_bsh_decode", $hash, 0);

  my $tree= HTML::TreeBuilder::XPath->new;
  $tree->parse($hash->{'.content'});
  my @ort = $tree->findvalues(q{//strong});
  my $ort = (split(/ /,$ort[1],3))[2];
  $ort = latin1ToUtf8($ort);
  my @values = $tree->findvalues(q{//table//tr});
  my $counter = 0;
  my $year = (split(/ /,localtime(time)))[4];
  readingsBeginUpdate($hash);
  foreach my $v (@values){
    next if(length($v) < 2);
    #Sa16.12.HW03:09 4.0�m
    my $d = substr($v,2,6);
    my $w = substr($v,8,2);
       $w =~ s/NW/LW/ if (lc(AttrVal($name,'bsh_language',"en")) eq 'en');
    my $t = substr($v,10,5);
    my $h = substr($v,15,4);
    if (AttrVal($name,'bsh_skipOutdated',1)) {
      my ($day1,$month1) = split(/\./,$d);
      my ($hour1,$min1)  = split(/:/,$t);
      my $x = time_str2num "$year-$month1-$day1 $hour1:$min1:00";
      next if time > $x;
    }
    $counter++;
    readingsBulkUpdate($hash, sprintf('tidalInfo.%02s',$counter), "$w $d $t $h");
    last if ($counter == AttrVal($name,'bsh_numEntries',8));
  }
  readingsBulkUpdateIfChanged($hash,'stationName',$ort);
  readingsBulkUpdate($hash,'state','active');
  readingsEndUpdate($hash,1);
}


1;

# commandref documentation
=pod
=item device
=item summary    show times of high and low water
=item summary_DE Gezeitenvorhersage des BSH
=begin html

<a name="bshGezeiten"></a>
<h3>bshGezeiten</h3>
<ul>

	<b>Prerequesits</b>
	<ul>
	
		<br/>
		Module uses following additional Perl modules:<br/><br/>
		<code>HTML::TreeBuilder::XPath</code><br/><br/>
		If not already installed in your environment, 
		please install them using appropriate commands from your environment.

	</ul>
	<br/><br/>
	
	<a name="bshGezeitendefine"></a>
	<b>Define</b>
	<ul>
		<br>
		<code>define &lt;name&gt; bshGezeiten &lt;locationId&gt;</code><br/>
		<br/>
		You can have the times of high and low water displayed for seven days at selected tide gauge locations.<br/>
		<br/>
		LocationId can be found on <a href="http://www.bsh.de/en/Marine_data/Forecasts/Tides/index.jsp">BSH webpage</a><br/>
		<br/>
		After selecting a station from list you fill find the Id in the resulting url, e.g. for Brake = DE__743P<br/>
	</ul>
	<br/>
	<br/>

	<a name="bshGezeitenset"></a>
	<b>Set-Commands</b><br/>
	<ul><br/>n/a</ul>
	<br/>
	<br/>

	<a name="bshGezeitenget"></a>
	<b>Get-Commands</b><br/>
	<ul><br/>n/a	</ul>
	<br/>
	<br/>

	<a name="bshGezeitenattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
		<br/>
		<li><b>bsh_language</b> - to be completed</li>
		<li><b>bsh_numEntries</b> - to be completed</li>
		<li><b>bsh_skipOutdated</b> - to be completed</li>
		<li><b>bsh_timeZone</b> - to be completed</li>
	</ul>
	<br/>
	<br/>

	<b>Generated Readings:</b>
	<br/>
	<br/>
	<ul>
		<li><b>stationName</b> - guess what...</li>
		<li><b>tidalInfo.xx</b> - numbered list of next high water (HW) and low water (LW)<br/>
		<code>
		Example: HW 21.12. 18:31 3.9<br/>
		HW    = High Water<br/>
		21.12 = date<br/>
		18:31 = time<br/>
		3.9.  = height<br/>
		</code>
		</li>
	</ul>
	<br/>
	<br/>

	<b>Author's notes</b><br/><br/>
	<ul>
	<li>Have fun!</li><br/>
	</ul>

</ul>

=end html
=begin html_DE

<a name="bshGezeiten"></a>
<h3>bshGezeiten</h3>
<ul>
Sorry, keine deutsche Dokumentation vorhanden.<br/><br/>
Die englische Doku gibt es hier: <a href='http://fhem.de/commandref.html#bshGezeiten'>bshGezeiten</a><br/>
</ul>
=end html_DE
=cut

