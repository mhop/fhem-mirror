#
#
# 02_HTTPSRV.pm
# written by Dr. Boris Neubert 2012-08-27
# e-mail: omega at online dot de
#
##############################################
# $Id$

package main;
use strict;
use warnings;
use vars qw(%data);
use HttpUtils;

my $HTTPSRV_matchlink = "^\/?(([^\/]*(\/[^\/]+)*)\/?)\$";

#########################
sub
HTTPSRV_addExtension($$$$) {
    my ($name,$func,$link,$friendlyname)= @_;

    # do some cleanup on link/url
    #   link should really show the link as expected to be called (might include trailing / but no leading /)
    #   url should only contain the directory piece with a leading / but no trailing /
    #   $1 is complete link without potentially leading /
    #   $2 is complete link without potentially leading / and trailing /
    $link =~ /$HTTPSRV_matchlink/;

    my $url = "/".$2;
    my $modlink = $1;

    Log3 $name, 3, "Registering HTTPSRV $name for URL $url   and assigned link $modlink ...";
    $data{FWEXT}{$url}{deviceName}= $name;
    $data{FWEXT}{$url}{FUNC} = $func;
    $data{FWEXT}{$url}{LINK} = $modlink;
    $data{FWEXT}{$url}{NAME} = $friendlyname;
}

sub
HTTPSRV_removeExtension($) {
    my ($link)= @_;

    # do some cleanup on link/url
    #   link should really show the link as expected to be called (might include trailing / but no leading /)
    #   url should only contain the directory piece with a leading / but no trailing /
    #   $1 is complete link without potentially leading /
    #   $2 is complete link without potentially leading / and trailing /
    $link =~ /$HTTPSRV_matchlink/;

    my $url = "/".$2;

    my $name= $data{FWEXT}{$url}{deviceName};
    Log3 $name, 3, "Unregistering HTTPSRV $name for URL $url...";
    delete $data{FWEXT}{$url};
}

##################
sub
HTTPSRV_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}     = "HTTPSRV_Define";
    $hash->{DefFn}     = "HTTPSRV_Define";
    $hash->{UndefFn}   = "HTTPSRV_Undef";
    #$hash->{AttrFn}    = "HTTPSRV_Attr";
    $hash->{AttrList}  = "directoryindex " .
                        "readings";
    $hash->{AttrFn}    = "HTTPSRV_Attr";
    #$hash->{SetFn}     = "HTTPSRV_Set";

    return undef;
 }

##################
sub
HTTPSRV_Define($$) {

  my ($hash, $def) = @_;

  my @a = split("[ \t]+", $def, 5);

  return "Usage: define <name> HTTPSRV <infix> <directory> <friendlyname>"  if(int(@a) != 5);
  my $name= $a[0];
  my $infix= $a[2];
  my $directory= $a[3];
  my $friendlyname= $a[4];

  $hash->{fhem}{infix}= $infix;
  $hash->{fhem}{directory}= $directory;
  $hash->{fhem}{friendlyname}= $friendlyname;

  Log3 $name, 3, "$name: new ext defined infix:$infix: dir:$directory:";

  HTTPSRV_addExtension($name, "HTTPSRV_CGI", $infix, $friendlyname);

  $hash->{STATE} = $name;
  return undef;
}

##################
sub
HTTPSRV_Undef($$) {

  my ($hash, $name) = @_;

  HTTPSRV_removeExtension($hash->{fhem}{infix});

  return undef;
}

##################
sub
HTTPSRV_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    if ($cmd eq "set") {
        if ($aName =~ "readings") {
            if ($aVal !~ /^[A-Z_a-z0-9\,]+$/) {
                Log3 $name, 3, "$name: Invalid reading list in attr $name $aName $aVal (only A-Z, a-z, 0-9, _ and , allowed)";
                return "Invalid reading name $aVal (only A-Z, a-z, 0-9, _ and , allowed)";
            }
        addToDevAttrList($name, $aName);
        }
    }
    return undef;
}



##################
#
# here we answer any request to http://host:port/fhem/$infix and below

sub HTTPSRV_CGI() {

  my ($request) = @_;   # /$infix/filename

#  Debug "request= $request";

  # Match request first without trailing / in the link part
  if($request =~ m,^(/[^/]+)(/(.*)?)?$,) {
    my $link= $1;
    my $filename= $3;
    my $name;

    # If FWEXT not found for this make a second try with a trailing slash in the link part
    if(! $data{FWEXT}{$link}) {
      $link = $link."/";
      return("text/plain; charset=utf-8", "Illegal request: $request") if(! $data{FWEXT}{$link});
    }

    # get device name
    $name= $data{FWEXT}{$link}{deviceName};

#    Debug "link= $link";
#    Debug "filename= $filename";
#    Debug "name= $name";

    # return error if no such device
    return("text/plain; charset=utf-8", "No HTTPSRV device for $link") unless($name);

    my $fullName = $filename;
    foreach my $reading (split (/,/, AttrVal($name, "readings", "")))  {
        my $value   = "";
        if ($fullName =~ /^([^\?]+)\?(.*)($reading)=([^;&]*)([&;].*)?$/) {
            $filename = $1;
            $value    = $4;
            Log3 $name, 5, "$name: set Reading $reading = $value";
            readingsSingleUpdate($defs{$name}, $reading, $value, 1);
        }
    };

    # set directory index
    $filename= AttrVal($name,"directoryindex","index.html") unless($filename);
    $filename =~ s/\?.*//;
    my $MIMEtype= filename2MIMEType($filename);
    my $directory= $defs{$name}{fhem}{directory};
    $filename= "$directory/$filename";
    #Debug "read filename= $filename";
    my @contents;
    if(open(INPUTFILE, $filename)) {
      binmode(INPUTFILE);
      @contents= <INPUTFILE>;
      close(INPUTFILE);
      return("$MIMEtype; charset=utf-8", join("", @contents));
    } else {
      return("text/plain; charset=utf-8", "File not found: $filename");
    }

  } else {
    return("text/plain; charset=utf-8", "Illegal request: $request");
  }


}




####

1;




=pod
=item device
=item summary rudimentary HTTP server that accepts parameters as readings
=item summary_DE rudiment&auml;rer HTTP-Server, der auch Parameter als Readings akzeptiert
=begin html

<a name="HTTPSRV"></a>
<h3>HTTPSRV</h3>
<ul>
  Provides a mini HTTP server plugin for FHEMWEB. It serves files from a given directory.
  It optionally accepts a query string to set readings of this device if an attribute allows the given reading<p>

  HTTPSRV is an extension to <a href="HTTPSRV">FHEMWEB</a>. You must install FHEMWEB to use HTTPSRV.</p>

  <a name="HTTPSRVdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HTTPSRV &lt;infix&gt; &lt;directory&gt; &lt;friendlyname&gt;</code><br><br>

    Defines the HTTP server. <code>&lt;infix&gt;</code> is the portion behind the FHEMWEB base URL (usually
    <code>http://hostname:8083/fhem</code>), <code>&lt;directory&gt;</code> is the absolute path the
    files are served from, and <code>&lt;friendlyname&gt;</code> is the name displayed in the side menu of FHEMWEB.<p><p>

    Example:
    <ul>
      <code>define myJSFrontend HTTPSRV jsf /usr/share/jsfrontend My little frontend</code><br>
      or <br>
      <code>
        define kindleweb HTTPSRV kindle /opt/fhem/kindle Kindle Web<br>
        attr kindleweb readings KindleBatt
      </code><br>
    </ul>
    <br>
  </ul>

  <a name="HTTPSRVset"></a>
  <b>Set</b>
  <ul>
    n/a
  </ul>
  <br><br>

  <a name="HTTPSRVattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>directoryindex: if the request is sent with no filename, i.e. the infix (with or without trailing slash) only, the file given in this attribute is loaded. Defaults to <code>index.html</code>.</li>
    <li>readings: a comma separated list of reading names. If the request ends with a querystring like <code>?Batt=43</code> and an attribute is set like <code>attr kindleweb readings Batt</code>, then a reading with the Name of this Attribute (here Batt) is created with the value from the request.</li>
  </ul>
  <br><br>

  <b>Usage information</b>
  <br><br>
  <ul>

  The above example on <code>http://hostname:8083/fhem</code> will return the file
  <code>/usr/share/jsfrontend/foo.html</code> for <code>http://hostname:8083/fhem/jsf/foo.html</code>.
  If no filename is given, the filename prescribed by the <code>directoryindex</code> attribute is returned.<p>

  Notice: All links are relative to <code>http://hostname:8083/fhem</code>.
  </ul>
  <br><br>
</ul>

=end html
=cut
