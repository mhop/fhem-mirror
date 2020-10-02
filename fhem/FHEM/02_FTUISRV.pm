################################################################
#
#
# 02_FTUISRV.pm
#
#   written by Johannes Viegener
#   based on 02_HTTPSRV written by Dr. Boris Neubert 2012-08-27
#
#     This file is part of Fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with Fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
################################################################
#  
#  FTUISRV https://github.com/viegener/Telegram-fhem/ftuisrv
#
# This module provides a mini HTTP server plugin for FHEMWEB for the specific use with FTUI or new FHEM tablet UI
#
# It serves files from a given directory and parses them according to specific rules.
# The goal is to be able to create reusable elements of multiple widgets and 
# surrounding tags on multiple pages and even with different devices or other 
# modifications. Therefore changes to the design have to be done only at one place 
# and not at every occurence of the template (called parts in this doc).
#
# Discussed in FHEM Forum: https://forum.fhem.de/index.php/topic,43110.0.html
#
# $Id$
#
##############################################################################
# 0.0 Initial version FTUIHTTPSRV
#   enable include und key value replacement
#   also recursive operation
#   show missing key definitions
# 0.1 - First working version FTUISRV
#
#   check and warn for remaining keys
#   added header for includes also for defining default values
#   changed key replacement to run through all content instead of list of keys
#   removed all callback elements
#   allow device content readings (and perl commands) in header 
#   add validateFiles / validateResult as attributes for HTML validation
#   validate for HTML and part files
#   validate a specific file only once (if unchanged)
#   validate* 1 means only errors/warnings / 2 means also opening and closing being logged 
#   documentation for validate* added
# 0.2 - Extended by validation of html, device data and default values (header)
#
#   add documentation for device readings (set logic)
#   allow reading values also in inc tag
# 0.3 - 2016-04-25 - Version for publication in SVN
#   
#   Allow replacements setp by step in headerline --> ?> must be escaped to ?\>
#   added if else endif for segments ftui-if=( <expr> ) 
#   simplified keyvalue parsing
#   simplified include in separate sub
#   add loopinc for looping include multiple times loopinc="<path>" <key>=( <expr> )  <keyvalues> 
#   summary for commandref
#   added if and loopinc to commandref
#   add new attribute for defining special template urls templateFiles
#   allow spaces around = and after <? for more tolerance
#   do not require space at end of tag before ?> for more tolerance
#   more tolerance on spaces around =
#   doc change on ftui-if

#   FIX: changed replaceSetmagic to hand over real device hash
#   FIX: $result might be undefined in some cases for loop/if
#   
################################################################
#TODO:
#
#
# deepcopy only if new keys found
#
##############################################
#
# ATTENTION: filenames need to have .ftui. before extension to be parsed
#
#
################################################################

package main;
use strict;
use warnings;
use vars qw(%data);

use File::Basename;

#use HttpUtils;

my $FTUISRV_matchlink = "^\/?(([^\/]*(\/[^\/]+)*)\/?)\$";

my $FTUISRV_matchtemplatefile = "^.*\.ftui\.[^\.]+\$";

my $FTUISRV_ftuimatch_header = '<\?\s*ftui-header\s*=\s*"([^"\?]*)"\s+(.*?)\?>';

my $FTUISRV_ftuimatch_keysegment = '^\s*([^=\s]+)(\s*=\s*"([^"]*)")?\s*';

my $FTUISRV_ftuimatch_keygeneric = '<\?\s*ftui-key\s*=\s*([^\s\?]+)\s*\?>';

my $FTUISRV_ftuimatch_if_het = '^(.*?)<\?\s*ftui-if\s*=\s*\((.*?)\)\s*\?>(.*)$';

my $FTUISRV_ftuimatch_else_ht = '^(.*?)<\?\s*ftui-else\s*\?>(.*)$';
my $FTUISRV_ftuimatch_endif_ht = '^(.*?)<\?\s*ftui-endif\s*\?>(.*)$';


my $FTUISRV_ftuimatch_inc_hfvt = '^(.*?)<\?\s*ftui-inc\s*=\s*"([^"\?]+)"\s+([^\?]*)\?>(.*?)$';

my $FTUISRV_ftuimatch_loopinc_hfkevt = '^(.*?)<\?\s*ftui-loopinc\s*=\s*"([^"\?]+)"\s+([^=\s]+)\s*=\s*\((.+?)\)\s+([^\?]*)\?>(.*?)$';


#########################
# FORWARD DECLARATIONS

sub FTUISRV_handletemplatefile( $$$$ );
sub FTUISRV_validateHtml( $$$$ );
sub FTUISRV_handleIf( $$$ );


#########################
sub
FTUISRV_addExtension($$$$) {
    my ($name,$func,$link,$friendlyname)= @_;

    # do some cleanup on link/url
    #   link should really show the link as expected to be called (might include trailing / but no leading /)
    #   url should only contain the directory piece with a leading / but no trailing /
    #   $1 is complete link without potentially leading /
    #   $2 is complete link without potentially leading / and trailing /
    $link =~ /$FTUISRV_matchlink/;

    my $url = "/".$2;
    my $modlink = $1;

    Log3 $name, 3, "Registering FTUISRV $name for URL $url   and assigned link $modlink ...";
    $data{FWEXT}{$url}{deviceName}= $name;
    $data{FWEXT}{$url}{FUNC} = $func;
    $data{FWEXT}{$url}{LINK} = $modlink;
    $data{FWEXT}{$url}{NAME} = $friendlyname;
}

sub 
FTUISRV_removeExtension($) {
    my ($link)= @_;

    # do some cleanup on link/url
    #   link should really show the link as expected to be called (might include trailing / but no leading /)
    #   url should only contain the directory piece with a leading / but no trailing /
    #   $1 is complete link without potentially leading /
    #   $2 is complete link without potentially leading / and trailing /
    $link =~ /$FTUISRV_matchlink/;

    my $url = "/".$2;

    my $name= $data{FWEXT}{$url}{deviceName};
    Log3 $name, 3, "Unregistering FTUISRV $name for URL $url...";
    delete $data{FWEXT}{$url};
}

##################
sub
FTUISRV_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}     = "FTUISRV_Define";
    $hash->{UndefFn}   = "FTUISRV_Undef";
    $hash->{AttrList}  = "directoryindex templateFiles ".
                        "readings validateFiles:0,1,2 validateResult:0,1,2 ";
    $hash->{AttrFn}    = "FTUISRV_Attr";                    
    #$hash->{SetFn}     = "FTUISRV_Set";

    return undef;
 }

##################
sub
FTUISRV_Define($$) {

  my ($hash, $def) = @_;

  my @a = split("[ \t]+", $def, 6);

  return "Usage: define <name> FTUISRV <infix> <directory> <friendlyname>"  if(( int(@a) < 5) );
  my $name= $a[0];
  my $infix= $a[2];
  my $directory= $a[3];
  my $friendlyname;

  $friendlyname = $a[4].(( int(@a) == 6 )?" ".$a[5]:"");
  
  $hash->{fhem}{infix}= $infix;
  $hash->{fhem}{directory}= $directory;
  $hash->{fhem}{friendlyname}= $friendlyname;

  Log3 $name, 3, "$name: new ext defined infix:$infix: dir:$directory:";

  FTUISRV_addExtension($name, "FTUISRV_CGI", $infix, $friendlyname);
  
  $hash->{STATE} = $name;
  return undef;
}

##################
sub
FTUISRV_Undef($$) {

  my ($hash, $name) = @_;

  FTUISRV_removeExtension($hash->{fhem}{infix});

  return undef;
}

##################
sub
FTUISRV_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    if ($cmd eq "set") {        
        if ($aName =~ "readings") {
          if ($aVal !~ /^[A-Z_a-z0-9\,]+$/) {
              Log3 $name, 2, "$name: Invalid reading list in attr $name $aName $aVal (only A-Z, a-z, 0-9, _ and , allowed)";
              return "Invalid reading name $aVal (only A-Z, a-z, 0-9, _ and , allowed)";
          }
          addToDevAttrList($name, $aName);
        } elsif ($aName =~ "validateFiles") {
          $attr{$name}{'validateFiles'} = (($aVal eq "2")? "2": (($aVal eq "1")? "1": "0"));
        } elsif ($aName =~ "validateResult") {
          $attr{$name}{'validateResult'} = (($aVal eq "2")? "2": (($aVal eq "1")? "1": "0"));
        }
    }
    return undef;
}



##################
#
# here we answer any request to http://host:port/fhem/$infix and below

sub FTUISRV_CGI() {

  my ($request) = @_;   # /$infix/filename

#  Debug "request= $request";
  Log3 undef, 4, "FTUISRV: Request to FTUISRV :$request:";
 
  # Match request first without trailing / in the link part 
  if($request =~ m,^(/[^/]+)(/([^\?]*)?)?(\?([^#]*))?$,) {
    my $link= $1;
    my $filename= $3;
    my $qparams= $5;
    my $name;
  
    # If FWEXT not found for this make a second try with a trailing slash in the link part
    if(! $data{FWEXT}{$link}) {
      $link = $link."/";
      return("text/plain; charset=utf-8", "Illegal request: $request") if(! $data{FWEXT}{$link});
    }
    
    # get device name
    $name= $data{FWEXT}{$link}{deviceName}; 
    
    # get corresponding hash
    my $hash = $defs{$name};

    # check system / device loglevel
    my $logLevel = $attr{global}{verbose};
    $logLevel = $attr{$name}{verbose} if ( defined( $attr{$name}{verbose} ) );
    
#     Log3 undef, 3, "FTUISRV: Request to FTUISRV :$request:";
    if ( 4 <= $logLevel ) {
      if ( ( $request =~ /index.html/ ) || ( $request =~ /\/$/ ) ) {
        Log3 $name, 4, "FTUISRV: request to FTUISRV :$request:  Header :".join("\n",@FW_httpheader).":";
      }
    }
  
#    Debug "link= ".((defined($link))?$link:"<undef>");
#    Debug "filename= ".((defined($filename))?$filename:"<undef>");
#    Debug "qparams= ".((defined($qparams))?$qparams:"<undef>");
#    Debug "name= $name";

    if ( ! $name ) {
      Log3 undef, 1, "FTUISRV: Request to FTUISRV but no link found !! :$request:";
    }

    # return error if no such device
    return("text/plain; charset=utf-8", "No FTUISRV device for $link") unless($name);

    my $fullName = $filename;
    foreach my $reading (split (/,/, AttrVal($name, "readings", "")))  {
        my $value   = "";
        if ($fullName =~ /^([^\?]+)\?(.*)($reading)=([^;&]*)([&;].*)?$/) {
            $filename = $1;
            $value    = $4;
            Log3 $name, 5, "$name: set Reading $reading = $value";
            readingsSingleUpdate($hash, $reading, $value, 1);
        }
    };
    
    Log3 $name, 5, "$name: Request to :$request:";
    
    $filename= AttrVal($name,"directoryindex","index.html") unless($filename);
    my $MIMEtype= filename2MIMEType($filename);

    my $directory= $defs{$name}{fhem}{directory};
    $filename= "$directory/$filename";
    #Debug "read filename= $filename";
    return("text/plain; charset=utf-8", "File not found: $filename") if(! -e $filename );
    
    my $parhash = {};
    my $validatehash = {};
    
    my ($err, $validated, $content) = FTUISRV_handletemplatefile( $hash, $filename, $parhash, $validatehash );

    # Validate HTML Result after parsing
    my $validate = AttrVal($name,'validateResult',0);
    if ( ( $validate ) && ( ( $filename =~ /\.html?$/i ) || ( $filename =~ /\.part?$/i )  ) && ( ! $validated ) ) {
      FTUISRV_validateHtml( $hash, $content, $validate, $filename );
    }
    
    return("text/plain; charset=utf-8", "Error in filehandling: $err") if ( defined($err) );
      
    return("$MIMEtype; charset=utf-8", $content);
    
  } else {
    return("text/plain; charset=utf-8", "Illegal request: $request");
  }

    
}   
    
##############################################
##############################################
##
## validate HTML
##
##############################################
##############################################


##################
#
# validate HTML according to basic criteria
# should be best build with HTML::Parser (cpan) --> allows also to parse processing instructions
#   example: 23_KOSTALPIKO.pm
#   comments correctly closed
#   build tag dictionary / array
#   optional: check FTUI 
sub FTUISRV_validateHtml( $$$$ ) {

  my ($hash, $content, $validateLevel, $filename ) = @_;   
  my $name = $hash->{NAME}; 

  # state: 0: normal  / 1: in tag  / 2: in comment   / 3: in quotes  / 4: in dquotes  / 5: in ptag
  #
  # tags contains
  #   <li   if tag has been found, but is not yet finished
  #   li    if li tag is found and completed
  #   "     in quotes
  #   '     in double quotes
  #   #     in comment
  #   <?    in processing tag (unfinished)
  
  # handle /> as end of tag
  # handle no close tags ==> meta, img
  # handle doctype with <! ==> as in processing tag no end
  # pushtag / poptag add prefix FTUISRV_
  
  Log3 $name, (( $validateLevel > 1 )?1:4), "$name: validate parsed HTML for request :$filename:";

  $content .= "   ";
  
  my $state = 0;
  my $line = 1;
  my $pos = 0;
  my $slen = length( $content );
  my @tags = ();
  my @tagline= ();
  my $ctag = "";
  
  while ( $pos < $slen ) {
    my $ch = substr( $content, $pos, 1 );
    $pos++;
    
    # Processing tag
    if ( $state == 5 ) {
      if ( $ch eq "\\" ) {
        $pos++;
      } elsif ( $ch eq "\"" ) {
        pushTag( \@tags, \@tagline, "<?", $line );
        $state = 4;
      } elsif ( $ch eq "\'" ) {
        $state = 3;
        pushTag( \@tags, \@tagline, "<?", $line );
      } elsif ( ( $ch eq "?" ) && ( substr( $content, $pos, 1 ) eq ">" ) ) {
        Log3(  $name, 1, "<< Leave Processing Tag: #$line" ) if ( $validateLevel > 1 );

        $pos++;
        ( $state, $ctag ) = popTag( \@tags, \@tagline );
      }
      
    # quote tags
    } elsif ( $state >= 3 ) {
      if ( $ch eq "\\" ) {
        $pos++;
      } elsif ( ( $ch eq "\"" ) && ( $state == 4 ) ){
        ( $state, $ctag ) = popTag( \@tags, \@tagline );
#        Debug "New state $state #$line";
      } elsif ( $ch eq "\"" ) {
        pushTag( \@tags, \@tagline, "\'", $line );
        $state = 4;
      } elsif ( ( $ch eq "\'" ) && ( $state == 3 ) ){
        ( $state, $ctag ) = popTag( \@tags, \@tagline );
      } elsif ( $ch eq "\'" ) {
        $state = 3;
        pushTag( \@tags, \@tagline, "\"", $line );
      }
    
    # comment tag
    } elsif ( $state == 2 ) {
      if ( ( $ch eq "-" ) && ( substr( $content, $pos, 2 ) eq "->" ) ) {
        $pos+=2;
        Log3(  $name, 1, "<< Leave Comment: #$line" ) if ( $validateLevel > 1 );
        ( $state, $ctag ) = popTag( \@tags, \@tagline );
      }
      
    # in tag
    } elsif ( $state == 1 ) {
      if ( $ch eq "\"" ) {
        pushTag( \@tags, \@tagline, $ctag, $line );
#        Debug "Go to state 4 #$line";
        $state = 4;
      } elsif ( $ch eq "\'" ) {
        pushTag( \@tags, \@tagline, $ctag, $line );
        $state = 3;
      } elsif ( ( $ch eq "<" ) && ( substr( $content, $pos, 1 ) eq "?" ) ) {
        pushTag( \@tags, \@tagline, $ctag, $line );
        $pos++;
        $state = 5;
      } elsif ( ( $ch eq "<" ) && ( substr( $content, $pos, 3 ) eq "!--" ) ) {
        pushTag( \@tags, \@tagline, $ctag, $line );
        $pos+=2;
        $state = 2;
      } elsif ( $ch eq "<" ) {
        Log3(  $name, 1, "FTUISRV_validate: Warning Spurious < in $filename (line $line)" );
      } elsif ( ( $ch eq "/" ) && ( substr( $content, $pos, 1 ) eq ">" ) ) {
        my $dl = $tagline[$#tagline];
        ( $state, $ctag ) = popTag( \@tags, \@tagline );
        Log3(  $name, 1, "<< end tag directly :$ctag: #$line" ) if ( $validateLevel > 1 );
        # correct state (outside tag)
        $state = 0;
      } elsif ( $ch eq ">" ) {
        my $dl = $tagline[$#tagline];
        ( $state, $ctag ) = popTag( \@tags, \@tagline );
        Log3(  $name, 1, "-- start tag complete :$ctag: #$line" ) if ( $validateLevel > 1 );
        # restore old tag start line
        pushTag( \@tags, \@tagline, substr($ctag,1), $dl );
        # correct state (outside tag)
        $state = 0;
      }
      
    # out of everything
    } else {
      if ( ( $ch eq "<" ) && ( substr( $content, $pos, 1 ) eq "?" ) ) {
        pushTag( \@tags, \@tagline, "", $line );
        $pos++;
        $state = 5;
        Log3(  $name, 1, ">> Enter Processing Tag #$line" ) if ( $validateLevel > 1 );
      } elsif ( ( $ch eq "<" ) && ( substr( $content, $pos, 3 ) eq "!--" ) ) {
        pushTag( \@tags, \@tagline, "", $line );
        $pos+=2;
        $state = 2;
        Log3(  $name, 1, ">> Enter Comment #$line" )  if ( $validateLevel > 1 );
      } elsif ( ( $ch eq "<" ) && ( substr( $content, $pos, 1 ) eq "/" ) ) {
        $pos++;
        my $tag = "";
        
        while ( $pos < $slen ) {
          my $ch2 = substr( $content, $pos, 1 );
          $pos++;
          
          if ( $ch2 eq ">" ) {
            last;
          } elsif (( $ch2 eq "\n" ) || ( $ch2 eq " " ) || ( $ch2 eq "\t" ) ) {
            $pos = $slen;
          } else {
            $tag .= $ch2;
          }

        }
        if ( $pos >= $slen ) {
          Log3(  $name, 1, "FTUISRV_validate: Error incomplete tag :".(defined($tag)?$tag:"<undef>").": not finished with > in $filename (line $line)" );
          @tags = 0;
        } else {
          Log3(  $name, 1, "<< end tag $tag: #$line" ) if ( $validateLevel > 1 );
          while ( scalar(@tags) > 0 ) {
            my $ptag = pop( @tags );
            my $pline = pop( @tagline );
            
            if ( $ptag eq $tag ) {
              Log3( $name, 1, "FTUISRV_validate: Warning void tag :".(defined($tag)?$tag:"<undef>").": unnecessarily closed $filename (opened in line $pline)" ) if ( FTUISRV_isVoidTag( $tag ) );
              last;
            } elsif ( scalar(@tags) == 0 ) {
              Log3(  $name, 1, "FTUISRV_validate: Error tag :".(defined($tag)?$tag:"<undef>").": closed but not open $filename (line $line)" );
              $pos = $slen;
            } else {
              Log3(  $name, 1, "FTUISRV_validate: Warning tag :".(defined($ptag)?$ptag:"<undef>").": not closed $filename (opened in line $pline)" ) 
                  if ( ! FTUISRV_isVoidTag( $ptag ) );
            }
          }
        }
        
      } elsif ( $ch eq "<" ) {
        # identify tag
        my $tag = "<";
        
        while ( $pos < $slen ) {
          my $ch2 = substr( $content, $pos, 1 );
          $pos++;
          
          if ( $ch2 eq ">" ) {
            $pos--;
            last;
          } elsif (( $ch2 eq "\n" ) || ( $ch2 eq " " ) || ( $ch2 eq "\t" ) ) {
            $pos--;
            last;
          } else {
            $tag .= $ch2;
          }

        }
        if ( $pos >= $slen ) {
          Log3(  $name, 1, "FTUISRV_validate: Warning start tag :".(defined($tag)?$tag:"<undef>").": not finished in $filename (line $line)" );
        } else {
          Log3(  $name, 1, "<< start tag $tag: #$line" ) if ( $validateLevel > 1 );
          $ctag = $tag;
          $state = 1;
          pushTag( \@tags, \@tagline, $ctag, $line );
        }
      }
      
    }
    
    $line++ if ( $ch eq "\n" );
    
    # ???
    # $pos = $slen if ( $line > 50 );
    
  }

  # remaining tags report
  while ( scalar(@tags) > 0 ) {
    my $ptag = pop( @tags );
    my $pline = pop( @tagline );
    
    Log3(  $name, 1, "FTUISRV_validate: Warning tag :".(defined($ptag)?$ptag:"<undef>").": not closed $filename (opened in line $pline)" )
        if ( ! FTUISRV_isVoidTag( $ptag ) );

  }
  
  
}


##################
#  Check if tag does not require an explicit end  
sub FTUISRV_isVoidTag( $ ) {

  my ($tag) = @_;   

  return ( index( " area base br col command embed hr img input link meta param source !DOCTYPE ", " ".$tag." " ) != -1 );  
}

##############################################
sub pushTag( $$$$ ) {

  my ( $ptags, $ptagline, $ch, $line ) = @_ ;

  push( @{ $ptags }, $ch );
  push( @{ $ptagline }, $line );
  
}
  

##############################################
sub popTag( $$ ) {

  my ( $ptags, $ptagline ) = @_; 
  
  return (0, "") if ( scalar($ptags) == 0 ); 

  my $ch = pop( @{ $ptags } );
  my $line = pop( @{ $ptagline } );
  my $state = 0;
  
  # state: 0: normal  / 1: in tag  / 2: in comment   / 3: in quotes  / 4: in dquotes  / 5: in ptag
  if ( $ch eq "" ) {
    $state = 0;
  } elsif ( $ch eq "<!--" ) {
    $state = 2;
  } elsif ( $ch eq "<?" ) {
    $state = 5;
  } elsif ( $ch eq "\'" ) {
    $state = 3;
  } elsif ( $ch eq "\"" ) {
    $state = 4;
  } elsif ( substr($ch,0,1) eq "<" ) {
    $state = 1;
  } else {
    # nothing else must be tag
    $state = 0;
  }
  return ( $state, $ch );
  
}
  

##############################################
##############################################
##
## Template handling
##
##############################################
##############################################


##################
#
# handle a ftui template string
#   name of the current ftui device
#   filename full fledged filename to be handled
#   string with content to be replaced
#   parhash reference to a hash with the current key-values
# returns
#   contents
sub FTUISRV_replaceKeys( $$$$ ) {

  my ($hash, $filename, $content, $parhash) = @_;
  my $name = $hash->{NAME}; 

  # make replacements of keys from hash
  while ( $content =~ /<\?ftui-key=([^\s]+)\s*\?>/g ) {
    my $key = $1;
    
    my $value = $parhash->{$key};
    if ( ! defined( $value ) ) {
      Log3 $name, 4, "$name: unmatched key in file :$filename:    key :$key:";
      $value = "";
    }
    Log3 $name, 4, "$name: replace key in file :$filename:    key :$key:  with :$value:";
    $content =~ s/<\?ftui-key=$key\s*\?>/$value/sg;
  }

#    while ( $content =~ /$FTUISRV_ftuimatch_keygeneric/s ) {
  while ( $content =~ /<\?ftui-key=([^\s]+)\s*\?>/g ) {
    Log3 $name, 4, "$name: unmatched key in file :$filename:    key :$1:";
  }
  
  return $content;
}



##################
#
# handle a ftui template for ifs
#   name of the current ftui device
#   filename full fledged filename to be handled
#   string with content to be replaced
# returns
#   contents
sub FTUISRV_handleIf( $$$ ) {

  my ($hash, $filename, $content) = @_;
  my $name = $hash->{NAME}; 

  # Look for if expression
  my $done = "";

  return $content if ( $content !~ /$FTUISRV_ftuimatch_if_het/s );

  $done .= $1;
  my $expr = $2;
  my $rest = $3;

  # handle rest to check recursively for further ifs
  $rest = FTUISRV_handleIf( $hash, $filename, $rest );
  
  # identify then and else parts
  my $then;
  my $else = "";
  if ( $rest =~ /$FTUISRV_ftuimatch_else_ht/s ) {
    $then = $1;
    $rest = $2;
  }

  if ( $rest =~ /$FTUISRV_ftuimatch_endif_ht/s ) {
    $else = $1;
    $rest = $2;
    if ( ! defined($then) ) {
      $then = $else;
      $else = "";
    }
  }
  
  # check expression
  my %dummy;
  my ($err, @a) = ReplaceSetMagic($hash, 0, ( $expr ) );
  if ( $err ) {
    Log3 $name, 1, "$name: FTUISRV_handleIf failed on ReplaceSetmagic with :$err: on header :$expr:";
  } else {
    Log3 $name, 4, "$name: FTUISRV_handleIf expr before setmagic :".$expr.":";
    $expr = join(" ", @a);
    # need to trim result of replacesetmagic -> multiple elements some space
    $expr =~ s/^\s+|\s+$//g; 
    Log3 $name, 4, "$name: FTUISRV_handleIf expr elements :".scalar(@a).":";
    Log3 $name, 4, "$name: FTUISRV_handleIf expr after setmagic :".$expr.":";
  }
  #Debug "Expr : ".( ( $expr ) ? $then : $else ).":";

  # put then/else depending on expr
  $done .= ( ( $expr ) ? $then : $else );
  $done .= $rest;

  return $done;
}


##################
#
# handle a ftui template for incs and then this as the template
#   name of the current ftui device
#   filename full fledged filename to be handled
#   curdir current directory for filename
#   string with content to be replaced
#   parhash reference to a hash with the current key-values
#   validated is ref to hash with filenames
# returns
#   err (might be undef) 
#   contents
sub FTUISRV_handleInc( $$$$$$ ) {

  my ($hash, $filename, $curdir, $content, $parhash, $validatehash) = @_;
  my $name = $hash->{NAME}; 
  
  # Look for if expression
  my $done = "";
  my $rest = $content;
  
  while ( $rest =~ /$FTUISRV_ftuimatch_inc_hfvt/s ) {
    $done .= $1;
    my $incfile = $2;
    my $values = $3;
    $rest = $4;
  
    Log3 $name, 4, "$name: include found :$filename:    inc :$incfile:   vals :$values:";
    return ("$name: Empty file name in include :$filename:", $content) if ( length($incfile) == 0 );
      
    # replace [device:reading] or even perl expressions with replaceSetMagic 
    my %dummy;
    Log3 $name, 4, "$name: FTUISRV_handleInc ReplaceSetmagic INC before :$values:";
    my ($err, @a) = ReplaceSetMagic($hash, 0, ( $values ) );
      
    if ( $err ) {
      Log3 $name, 1, "$name: FTUISRV_handleInc ($filename) failed on ReplaceSetmagic with :$err: on INC :$values:";
    } else {
      $values = join(" ", @a);
      Log3 $name, 4, "$name: FTUISRV_handleInc ($filename) ReplaceSetmagic INC after :".$values.":";
    }

    # deepcopy parhash here 
    my $incparhash = deepcopy( $parhash );

    # parse $values + add keys to inchash
    while ( $values =~ s/$FTUISRV_ftuimatch_keysegment//s ) {
      my $skey = $1;
      my $sval = $3;
      $sval="" if ( ! defined($sval) );
    
      Log3 $name, 4, "$name: a key :$skey: = :$sval: ";

      $incparhash->{$skey} = $sval;
    }
     
    # build new filename (if not absolute already)
    $incfile = $curdir.$incfile if ( substr($incfile,0,1) ne "/" );
        
    Log3 $name, 4, "$name: start handling include (rec) :$incfile:";
    my $inccontent;
    my $dummy;
    ($err, $dummy, $inccontent) = FTUISRV_handletemplatefile( $hash, $incfile, $incparhash, $validatehash );
      
    Log3 $name, 4, "$name: done handling include (rec) :$incfile: ".(defined($err)?"Err: ".$err:"ok");

    # error will always result in stopping recursion
    return ($err." (included)", $content) if ( defined($err) );
                    
    $done .= $inccontent;
#      Log3 $name, 3, "$name: done handling include new content:----------------\n$content\n--------------------";

    last if ( length($rest) == 0 );
  }
  
  $done .= $rest;
  
  return ( undef, $done );
}


##################
#
# handle a ftui template for loopInc and then the file as a template for all expression results
#   name of the current ftui device
#   filename full fledged filename to be handled
#   curdir current directory for filename
#   string with content to be replaced
#   parhash reference to a hash with the current key-values
#   validated is ref to hash with filenames
# returns
#   err (might be undef) 
#   contents
sub FTUISRV_handleLoopInc( $$$$$$ ) {

  my ($hash, $filename, $curdir, $content, $parhash, $validatehash) = @_;
  my $name = $hash->{NAME}; 

  # Look for if expression
  my $done = "";
  my $rest = $content;
  
  while ( $rest =~ /$FTUISRV_ftuimatch_loopinc_hfkevt/s ) {
    $done .= $1;
    my $incfile = $2;
    my $key = $3;
    my $expr = $4;
    my $values = $5;
    $rest = $6;
  
    Log3 $name, 4, "$name: include loop found :$filename:   key :$key: expr:$expr:\n   inc :$incfile:   vals :$values:";
    return ("$name: Empty file name in loopinc :$filename:", $content) if ( length($incfile) == 0 );

    # Evaluate expression as command to get list of entries for loop ???
    my $result = AnalyzeCommand(undef, $expr);     

    $result = "" if ( ! $result );
    
    # Identify split char ???
    
    # split at splitchar (default \n) into array ???
    my @aResults = split( /\n/, $result );
    
    # replace [device:reading] or even perl expressions with replaceSetMagic 
    my %dummy;
    Log3 $name, 4, "$name: FTUISRV_handleLoopInc ReplaceSetmagic INC before :$values:";
    my ($err, @a) = ReplaceSetMagic($hash, 0, ( $values ) );
      
    if ( $err ) {
      Log3 $name, 1, "$name: FTUISRV_handleLoopInc ($filename) failed on ReplaceSetmagic with :$err: on INC :$values:";
    } else {
      $values = join(" ", @a);
      Log3 $name, 4, "$name: FTUISRV_handleLoopInc ($filename) ReplaceSetmagic INC after :".$values.":";
    }

    # deepcopy parhash here 
    my $incparhash = deepcopy( $parhash );

    # parse $values + add keys to inchash
    while ( $values =~ s/$FTUISRV_ftuimatch_keysegment//s ) {
      my $skey = $1;
      my $sval = $3;
      $sval="" if ( ! defined($sval) );
    
      Log3 $name, 4, "$name: a key :$skey: = :$sval: ";

      $incparhash->{$skey} = $sval;
    }
     
    # build new filename (if not absolute already)
    $incfile = $curdir.$incfile if ( substr($incfile,0,1) ne "/" );
        
    # Loop over list of values
    foreach my $loopvariable ( @aResults ) {

      # deepcopy parhash here 
      my $loopincparhash = deepcopy( $incparhash );

      # add loopvariable with current value
      $loopincparhash->{$key} = $loopvariable;
      
      Log3 $name, 4, "$name: start handling include (rec) :$incfile: with value $key = :$loopvariable:";
      my $inccontent;
      my $dummy;
      ($err, $dummy, $inccontent) = FTUISRV_handletemplatefile( $hash, $incfile, $loopincparhash, $validatehash );
        
      Log3 $name, 4, "$name: done handling include (rec) :$incfile: ".(defined($err)?"Err: ".$err:"ok");

      # error will always result in stopping recursion
      return ($err." (included)", $content) if ( defined($err) );
                      
      $done .= $inccontent;
#      Log3 $name, 3, "$name: done handling include new content:----------------\n$content\n--------------------";

    }

    last if ( length($rest) == 0 );
  }
  
  $done .= $rest;
  
  return ( undef, $done );
}


##################
#
# handle a ftui template file
#   name of the current ftui device
#   filename full fledged filename to be handled
#   parhash reference to a hash with the current key-values
#   validated is ref to hash with filenames
# returns
#   err
#   validated if the file handed over has been validated in unmodified form (only if not parsed, then this will be reseit)
#   contents
sub FTUISRV_handletemplatefile( $$$$ ) {

  my ($hash, $filename, $parhash, $validatehash) = @_;
  my $name = $hash->{NAME}; 

  my $content;
  my $err;
  my $validated = 0;
  
  Log3 $name, 5, "$name: handletemplatefile :$filename:";

  $content = FTUISRV_BinaryFileRead( $filename );
  return ("$name: File not existing or empty :$filename:", $validated, $content) if ( length($content) == 0 );

  # Validate HTML Result after parsing
  my $validate = AttrVal($name,'validateFiles',0);
  if ( ( $validate ) && ( ! defined($validatehash->{$filename} ) ) && ( ( $filename =~ /\.html?$/i ) || ( $filename =~ /\.part?$/i )  ) ) {
    $validated = 1;
    $validatehash->{$filename} = 1 if ( ! defined($validatehash->{$filename} ) );
    FTUISRV_validateHtml( $hash, $content, $validate, $filename );
  }
    
  
  if ( ( $filename =~ /$FTUISRV_matchtemplatefile/ ) || ( index( ":".AttrVal($name,"templateFiles","").":", ":".$filename.":" ) != -1 ) ) {
    Log3 $name, 4, "$name: is real template :$filename:";
    $validated = 0;

    my ($dum, $curdir) = fileparse( $filename );

    # Get file header with keys / default values (optional)
    if ( $content =~ /$FTUISRV_ftuimatch_header/s ) {
      my $hvalues = $2;
      Log3 $name, 4, "$name: found header with hvalues :$hvalues: ";

      # replace [device:reading] or even perl expressions with replaceSetMagic 
      my %dummy;
      Log3 $name, 4, "$name: FTUISRV_handletemplatefile ReplaceSetmagic HEADER before :$hvalues:";

      # grab keys for default values from header
      while ( $hvalues =~ /$FTUISRV_ftuimatch_keysegment/s ) {
        my $skey = $1;
        my $sval = $3;
      
        if ( defined($sval) ) {
          Log3 $name, 4, "$name: default value for key :$skey: = :$sval: ";

          # replace escaped > (i.e. \>) by > for key replacement
          $sval =~ s/\?\\>/\?>/g;
          
          $sval = FTUISRV_replaceKeys( $hash, $filename." header", $sval, $parhash );
          Log3 $name, 4, "$name: FTUISRV_handletemplatefile default value for key :$skey: after replace :".$sval.":";

          my ($err, @a) = ReplaceSetMagic($hash, 0, ( $sval ) );
          if ( $err ) {
            Log3 $name, 1, "$name: FTUISRV_handletemplatefile failed on ReplaceSetmagic with :$err: on header :$sval:";
          } else {
            $sval = join(" ", @a);
            Log3 $name, 4, "$name: FTUISRV_handletemplatefile default value for key :$skey: after setmagic :".$sval.":";
          }

          $parhash->{$skey} = $sval if ( ! defined($parhash->{$skey} ) )
        }
        $hvalues =~ s/$FTUISRV_ftuimatch_keysegment//s;
      }


      # remove header from output 
      $content =~ s/$FTUISRV_ftuimatch_header//s
    }

    # replace the keys first before loop/if
    $content = FTUISRV_replaceKeys( $hash, $filename, $content, $parhash );

    # eval if else endif expressions
    $content = FTUISRV_handleIf( $hash, $filename, $content );

    # Handle includes
    Log3 $name, 4, "$name: look for includes :$filename:";

    ( $err, $content ) = FTUISRV_handleInc( $hash, $filename, $curdir, $content, $parhash, $validatehash );
    # error will always result in stopping recursion
    return ($err, $validated, $content) if ( defined($err) );

    ( $err, $content ) = FTUISRV_handleLoopInc( $hash, $filename, $curdir, $content, $parhash, $validatehash );
    # error will always result in stopping recursion
    return ($err, $validated, $content) if ( defined($err) );

  }
    
  return ($err,$validated,$content);
}

##################
# from http://www.volkerschatz.com/perl/snippets/dup.html
# Duplicate a nested data structure of hash and array references.
# -> List of scalars, possibly array or hash references
# <- List of deep copies of arguments.  References that are not hash or array
#    refs are copied as-is.
sub deepcopy
{
    my @result;

    for (@_) {
        my $reftype= ref $_;
        if( $reftype eq "ARRAY" ) {
            push @result, [ deepcopy(@$_) ];
        }
        elsif( $reftype eq "HASH" ) {
            my %h;
            @h{keys %$_}= deepcopy(values %$_);
            push @result, \%h;
        }
        else {
            push @result, $_;
        }
    }
    return @_ == 1 ? $result[0] : @result;
}
   
   
##################
#
# Callback for FTUI handling
sub FTUISRV_returnFileContent($$) {
  my ($name, $request) = @_;   # name of extension and request (url)

  # split request

  $request =~ m,^(/[^/]+)(/([^\?]*)?)?(\?([^#]*))?$,;
  my $link= $1;
  my $filename= $3;
  my $qparams= $5;
  
  Debug "link= ".((defined($link))?$link:"<undef>");
  Debug "filename= ".((defined($filename))?$filename:"<undef>");
  Debug "qparams= ".((defined($qparams))?$qparams:"<undef>");

  $filename= AttrVal($name,"directoryindex","index.html") unless($filename);
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
}

######################################
#  read binary file for Phototransfer - returns undef or empty string on error
#  
sub FTUISRV_BinaryFileRead($) {
	my ($fileName) = @_;

  return '' if ( ! (-e $fileName) );
  
  my $fileData = '';
		
  open FHS_BINFILE, '<'.$fileName;
  binmode FHS_BINFILE;
  while (<FHS_BINFILE>){
    $fileData .= $_;
  }
  close FHS_BINFILE;
  
  return $fileData;
}

##############################################
##############################################
##############################################
##############################################
##############################################
####

1;




=pod
=item summary    HTTP Server for tablet UI with server side includes, loops, ifs
=item summary_DE HTTP-Server für das tablet UI mit server-seitigen includes, loop, if
=begin html

<a name="FTUISRV"></a>
<h3>FTUISRV</h3>
<ul>
  Provides a mini HTTP server plugin for FHEMWEB for the specific use with FTUI. 
  It serves files from a given directory and parses them according to specific rules.
  The goal is to be able to create reusable elements of multiple widgets and surrounding tags on multiple pages and even with different devices or other modifications. Therefore changes to the design have to be done only at one place and not at every occurence of the template (called parts in this doc).
  
  FTUISRV is an extension to <a href="FTUISRV">FHEMWEB</a> and code is based on HTTPSRV. You must install FHEMWEB to use FTUISRV.</p>
  
  FTUISRV is able to handled includes and replacements in files before sending the result back to the client (Browser).
  Special handling of files is ONLY done if the filenames include the specific pattern ".ftui." in the filename. 
  For example a file named "test.ftui.html" would be handled specifically in FTUISRV.
  
  <br><br>
  FTUI files can contain the following elements  
  <ul><br>
    <li><code>&lt;?ftui-inc="name" varname1="content1" ... varnameN="contentN" ?&gt;</code> <br>
      INCLUDE statement: Including other files that will be embedded in the result at the place of the include statement. 
      Additionally in the embedded files the variables listed as varnamex will be replaced by the content 
      enclosed in double quotes (").
      <br>
      The quotation marks and the spaces between the variable replacements and before the final ? are significant and can not be ommitted.
      <br>Example: <code>&lt;?ftui-inc="temphum-inline.ftui.part" thdev="sensorWZ" thformat="top-space-2x" thtemp="measured-temp" ?&gt;</code>
    </li><br>

    <li><code>&lt;?ftui-if=( expression ) ?&gt; ... [ &lt;?ftui-else ?&gt; ... ] &lt;?ftui-endif ?&gt; </code> <br>
      IF statement: Allow the inclusion of a block depending on an expression that might again include also variables and expressions in fhem. The else block is optional and can contain a block that is included if the expression is empty or 0 .
      <br>
      Example: <code>&lt;?ftui-if=( [tempdevice:batteryok] ) ?&gt; ... &lt;?ftui-else ?&gt; ... &lt;?ftui-endif ?&gt; </code>
      <br>
      Note: The expression is not automatically evaluated in perl, if this is needed there should be the set-logic for perl expressions being used 
      Example: <code>&lt;?ftui-if=( {( ReadingsVal("tempdevice","batteryok","") eq "ok" )} ) ?&gt; ... &lt;?ftui-else ?&gt; ... &lt;?ftui-endif ?&gt; </code>
    </li><br>

    <li><code>&lt;?ftui-loopinc="name" loopvariable=( loop-expression ) varname1="content1" ... varnameN="contentN" ?&gt;</code> <br>
      LOOP-INCLUDE statement: Including other files that will be embedded in the result at the place of the include statement. The include will be executed once for every entry (line) that is returned when evaluating the loop-expression as an fhem command. So the loop expression could be a list command returning multiple devices
      <br>
      The quotation marks and the spaces between the variable replacements and before the final ? are significant and can not be ommitted.
      <br>Example: <code>&lt;?ftui-loopinc="temphum-inline.ftui.part" thdev=( list TYPE=CUL_TX ) thformat="top-space-2x" thtemp="measured-temp" ?&gt;</code>
    </li><br>
    
    <li><code>&lt;?ftui-key=varname ?&gt;</code> <br>
      VARIABLE specification: Replacement of variables with given parameters in the include statement (or the include header).
      The text specified for the corresponding variable will be inserted at the place of the FTUI-Statement in parentheses.
      There will be no space or other padding added before or after the replacement, 
      the replacement will be done exactly as specified in the definition in the include
      <br>Example: <code>&lt;?ftui-key=measured-temp ?&gt;</code>
    </li><br>

    <li><code>&lt;?ftui-header="include name" varname1[="defaultcontent1"] .. varnameN[="defaultcontentN"] ?&gt;</code> <br>
      HEADER definition: Optional header for included files that can be used also to specify which variables are used in the include
      file and optionally specify default content for the variables that will be used if no content is specified in the include statement.
      the header is removed from the output given by FTUISRV.
      Headers are only required if default values should be specified and are helpful in showing the necessary variable names easy for users.
      (The name for the include does not need to be matching the file name)
      <br>Example: <code>&lt;?ftui-header="TempHum inline" thdev thformat thtemp="temperature" ?&gt;</code>
      Headers can also use device readings in for setting default values in the form of <code>[device:reading]</code>(according to the syntax and logic used in the set command)
      <br>Example: <code>&lt;?ftui-header="TempHum inline" thdev thformat thbattery=[temphm:batteryok] thtemp="temperature" ?&gt;</code>
      <br>
      In the special case, where also variable content shall be used in the header part a special escaping for the closing tags for the ftui-key needs to be used. That means for the example above:
      Example: <code>&lt;?ftui-header="TempHum inline" thdev thformat thbattery=[<ftui-key=thdev ?\>:batteryok] thtemp="temperature" ?&gt;</code>
    </li><br>
  </ul>
 
  <br><br>

  <a name="FTUISRVdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; &lt;infix&gt; &lt;directory&gt; &lt;friendlyname&gt;</code><br><br>

    Defines the HTTP server. <code>&lt;infix&gt;</code> is the portion behind the FHEMWEB base URL (usually
    <code>http://hostname:8083/fhem</code>), <code>&lt;directory&gt;</code> is the absolute path the
    files are served from, and <code>&lt;friendlyname&gt;</code> is the name displayed in the side menu of FHEMWEB.<p><p>
    <br>
  </ul>

  <a name="FTUISRVset"></a>
  <b>Set</b>
  <ul>
    n/a
  </ul>
  <br><br>

  <a name="FTUISRVattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>validateFiles &lt;0,1,2&gt;</code><br>
      Allows basic validation of HTML/Part files on correct opening/closing tags etc. 
      Here the original files   from disk are validated (setting to 1 means validation is done / 2 means also the full parsing is logged (Attention very verbose !) 
    </li>   
    <li><code>validateResult &lt;0,1,2&gt;</code><br>
      Allows basic validation of HTML content on correct opening/closing tags etc. Here the resulting content provided to the browser 
      (after parsing) are validated (setting to 1 means validation is done / 2 means also the full parsing is logged (Attention very verbose !) 
    </li> 
    <li><code>templateFiles &lt;relative paths separated by :&gt;</code><br>
      specify specific files / urls to be handled as templates even if not containing the ftui in the filename. Multiple files can be separated by colon.
    </li> 



    </ul>
  <br><br>

</ul>

=end html
=cut
