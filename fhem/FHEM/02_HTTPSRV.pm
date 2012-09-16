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
HTTPSRV_addExtension($$$$) {
    my ($name,$func,$link,$friendlyname)= @_;
  
    my $url = "/$link";
    Log 3, "Registering HTTPSRV $name for URL $url...";
    $data{FWEXT}{$url}{deviceName}= $name;
    $data{FWEXT}{$url}{FUNC} = $func;
    $data{FWEXT}{$url}{LINK} = $link;
    $data{FWEXT}{$url}{NAME} = $friendlyname;
}

sub 
HTTPSRV_removeExtension($) {
    my ($link)= @_;

    my $url = "/$link";
    my $name= $data{FWEXT}{$url}{deviceName};
    Log 3, "Unregistering HTTPSRV $name for URL $url...";
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
    $hash->{AttrList}  = "loglevel:0,1,2,3,4,5 directoryindex";
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
#
# here we answer any request to http://host:port/fhem/$infix and below

sub HTTPSRV_CGI() {

  my ($request) = @_;   # /$infix/filename

  if($request =~ m,^(/[^/]+)(/(.*)?)?$,) {
    my $link= $1;
    my $filename= $3;
    my $name;

    # get device name
    $name= $data{FWEXT}{$link}{deviceName} if($data{FWEXT}{$link});

    Debug "link= $link";
    Debug "filename= $filename";
    Debug "name= $name";

    # return error if no such device
    return("text/plain; charset=utf-8", "No HTTPSRV device for $link") unless($name);

    # set directory index
    $filename= AttrVal($name,"directoryindex","index.html") unless($filename);
    my $MIMEtype= filename2MIMEType($filename);

    my $directory= $defs{$name}{fhem}{directory};
    $filename= "$directory/$filename";
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



