##############################################
#
# 02_FHEMapi.pm
#
# forked from 02_HTTPSRV.pm written by Dr. Boris Neubert
#
##############################################
# $Id$

package main;
use strict;
use warnings;
use vars qw(%data);
use HttpUtils;

my $FHEMapi_matchlink = "^\/?(([^\/]*(\/[^\/]+)*)\/?)\$";

#########################
sub FHEMapi_addExtension($$$$) {
    my ($name,$func,$link,$friendlyname)= @_;

    # do some cleanup on link/url
    #   link should really show the link as expected to be called (might include trailing / but no leading /)
    #   url should only contain the directory piece with a leading / but no trailing /
    #   $1 is complete link without potentially leading /
    #   $2 is complete link without potentially leading / and trailing /
    $link =~ /$FHEMapi_matchlink/;

    my $url = "/".$2;
    my $modlink = $1;

    Log3 $name, 3, "Registering FHEMapi $name for URL $url   and assigned link $modlink ...";
    $data{FWEXT}{$url}{deviceName}= $name;
    $data{FWEXT}{$url}{FUNC} = $func;
    $data{FWEXT}{$url}{LINK} = $modlink;
    $data{FWEXT}{$url}{NAME} = $friendlyname;
}

sub FHEMapi_removeExtension($) {
    my ($link)= @_;

    # do some cleanup on link/url
    #   link should really show the link as expected to be called (might include trailing / but no leading /)
    #   url should only contain the directory piece with a leading / but no trailing /
    #   $1 is complete link without potentially leading /
    #   $2 is complete link without potentially leading / and trailing /
    $link =~ /$FHEMapi_matchlink/;

    my $url = "/".$2;

    my $name= $data{FWEXT}{$url}{deviceName};
    Log3 $name, 3, "Unregistering FHEMapi $name for URL $url...";
    delete $data{FWEXT}{$url};
}

##################
sub FHEMapi_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}     = "FHEMapi_Define";
    $hash->{DefFn}     = "FHEMapi_Define";
    $hash->{UndefFn}   = "FHEMapi_Undef";
    #$hash->{AttrFn}    = "FHEMapi_Attr";
    $hash->{AttrList}  = "directoryindex " .
                         "readings " . 
                         $readingFnAttributes;
    $hash->{AttrFn}    = "FHEMapi_Attr";
    #$hash->{SetFn}     = "FHEMapi_Set";

    return undef;
}

##################
sub FHEMapi_Define($$) {

  my ($hash, $def) = @_;

  my @a = split("[ \t]+", $def, 5);

  return "Usage: define <name> FHEMapi"  if(int(@a) != 2);
  my $name= $a[0];
  my $infix= 'api';
  my $directory= 'www/api';
  my $friendlyname= 'FHEMapi';

  $hash->{fhem}{infix}= $infix;
  $hash->{fhem}{directory}= $directory;
  $hash->{fhem}{friendlyname}= $friendlyname;

  Log3 $name, 3, "$name: new ext defined infix:$infix: dir:$directory:";

  FHEMapi_addExtension($name, "FHEMapi_CGI", $infix, $friendlyname);

  $hash->{STATE} = $name;
  return undef;
}

##################
sub FHEMapi_Undef($$) {

  my ($hash, $name) = @_;

  FHEMapi_removeExtension($hash->{fhem}{infix});

  return undef;
}

##################
sub FHEMapi_Attr(@)
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

sub FHEMapi_CGI() {

  my ($request) = @_;   # /$infix/filename

  Debug "request= $request";

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
    return("text/plain; charset=utf-8", "No FHEMapi device for $link") unless($name);

    return("text/plain; charset=utf-8", "42");


#     my $fullName = $filename;
#     foreach my $reading (split (/,/, AttrVal($name, "readings", "")))  {
#         my $value   = "";
#         if ($fullName =~ /^([^\?]+)\?(.*)($reading)=([^;&]*)([&;].*)?$/) {
#             $filename = $1;
#             $value    = $4;
#             Log3 $name, 5, "$name: set Reading $reading = $value";
#             readingsSingleUpdate($defs{$name}, $reading, $value, 1);
#         }
#     };
# 
#     # set directory index
#     $filename= AttrVal($name,"directoryindex","index.html") unless($filename);
#     $filename =~ s/\?.*//;
#     my $MIMEtype= filename2MIMEType($filename);
#     my $directory= $defs{$name}{fhem}{directory};
#     $filename= "$directory/$filename";
#     #Debug "read filename= $filename";
#     my @contents;
#     if(open(INPUTFILE, $filename)) {
#       binmode(INPUTFILE);
#       @contents= <INPUTFILE>;
#       close(INPUTFILE);
#       return("$MIMEtype; charset=utf-8", join("", @contents));
#     } else {
#       return("text/plain; charset=utf-8", "File not found: $filename");
#     }

  } else {
    return("text/plain; charset=utf-8", "Illegal request: $request");
  }


}




####

1;
