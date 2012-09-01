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

#########################
sub
HTTPSRV_addExtension($$$) {
    my ($func,$link,$friendlyname)= @_;
  
    my $url = "/" . $link;
    $data{FWEXT}{$url}{FUNC} = $func;
    $data{FWEXT}{$url}{LINK} = $link;
    $data{FWEXT}{$url}{NAME} = $friendlyname;
}

##################
sub
HTTPSRV_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}   = "HTTPSRV_Define";
    #$hash->{AttrFn}  = "HTTPSRV_Attr";
    $hash->{AttrList}= "loglevel:0,1,2,3,4,5";
    #$hash->{SetFn}   = "HTTPSRV_Set";

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

  HTTPSRV_addExtension("HTTPSRV_CGI", $infix, $friendlyname);
  
  $hash->{STATE} = $name;
  return undef;
}

##################
#
# here we answer any request to http://host:port/fhem/$infix and below
sub
HTTPSRV_CGI(){

  my ($request) = @_;   # /$infix/filename

  if($request !~ m,^/.+/.*,) {
    $request= "$request/index.html";
  }
  if($request =~ m,^/([^/]+)/(.*)$,) {
    my $name= $1;
    my $filename= $2;
    my $MIMEtype= filename2MIMEType($filename);
    #return("text/plain; charset=utf-8", "HTTPSRV device: $name, filename: $filename, MIME type: $MIMEtype");
    if(!defined($defs{$name})) {
      return("$MIMEtype; charset=utf-8", "Unknown HTTPSRV device: $name");
    }
      my $directory= $defs{$name}{fhem}{directory};
      $filename= "$directory/$filename";
      my @contents;
      if(open(INPUTFILE, $filename)) {
        binmode(INPUTFILE);
        @contents= <INPUTFILE>;
        close(INPUTFILE);
        return("", join("", @contents));
      } else {
        return("text/plain; charset=utf-8", "File not found: $filename");
    }
  } else {
    return("text/plain; charset=utf-8", "Illegal request: $request");
  }

}

####

1;



