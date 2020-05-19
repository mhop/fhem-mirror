##############################################################################
##############################################################################
#
#     48_BlinkCamera.pm
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
#  
#  BlinkCamera (c) Johannes Viegener / https://github.com/viegener/Blink
#
# This module interacts with Blink Home Cameras : https://blinkforhome.com/
# Some information is based on the work here: https://github.com/MattTW/BlinkMonitorProtocol
# (although this was slightly outdated)
#
# Discussed in FHEM Forum: https://forum.fhem.de/index.php/topic,59719.0.html
#
# $Id$
#
##############################################################################
#
##### API change
#   Change to new login API - V4 (not containing networks)
#   getNetworks as new getter
#   set networks reading to INVALID on reading networks
#   ensure networks retrieved in docmd before other cmds
#   parse networks
# 2.0 2020-05-13 CheckIn to SVN for regular FHEM update
#
#   use DevIo according to commit hook
#   fix videodelete according to msg1053993
#   fix videodelete filename (change path to _)
#   new attribute homeScreenV3 set to 1 to use new v3 api
#   support blink cameras on homescreen - with new homeScreenV3
#   added documentation for homeScreenV3 and BLinkMini - readonly mode
#   added - for host name instaed of . after rest
#   new camtype dependant camEnable / camDisable 
#   ...Cam...active state corrected (was always disabled)
#   getThumbnail also for Blink Mini

#   FIX: camtype missing for old homescreen
# 
# 
# 
##############################################################################
##############################################################################
##############################################################################
##############################################################################
# TASKS 
#
#   unique id generator
#   change headers: user-agent (Blink/8280 CFNetwork/1125.2 Darwin/19.4.0)/ app-build (IOS_8280)
#   post on login with all information? --> https://rest-prod.immedia-semi.com/api/v4/account/login
#   
#
#
#   FIX: getThumbnail url failing sometimes
#   FIX: imgOriginalFile not fully working
#   might need to check for transaction id on command post
#   store poll failures / digest?
#   allow thumbnailreset
#   
##############################################################################
# Ideas
#   
#
##############################################################################
#
#{"authtoken":{"authtoken":"sjkashajhdjkashd","message":"auth"},"networks":{"<n>":{"name":"<name>","onboarded":true}},"region":{"prde":"Europe"}}
#{"message":"Unauthorized Access"}
#
# { "video_list": [ 1012458 ] }   - POST https://rest.prir.immedia-semi.com/api/v2/videos/delete
#
##############################################################################


package main;

use strict;
use warnings;

#use HttpUtils;
use utf8;

use Encode;

# JSON:XS is used here normally
use JSON; 

use Data::Dumper;

use URI::Escape;

use Scalar::Util qw(reftype looks_like_number);

use DevIo;

#########################
# Forward declaration
sub BlinkCamera_Define($$);
sub BlinkCamera_Undef($$);
sub BlinkCamera_Delete($$);

sub BlinkCamera_Set($@);
sub BlinkCamera_Get($@);

sub BlinkCamera_Callback($$$);
sub BlinkCamera_DoCmd($$;$$$);
sub BlinkCamera_PollInfo($);

sub BlinkCamera_GetCameraId( $;$ );
sub BlinkCamera_CameraDoCmd( $$$ );
sub BlinkCamera_CheckSetGet( $$$ );

sub BlinkCamera_ReplacePattern( $$;$ );
sub BlinkCamera_ParseStartAlerts($;$$$);
sub BlinkCamera_AnalyzeAlertPage( $$$ );
sub BlinkCamera_GetCamType( $$ );

#########################
# Globals
# OLD? my $BlinkCamera_host = "prod.immedia-semi.com";
#my $BlinkCamera_host = "rest.prir.immedia-semi.com";
#my $BlinkCamera_host = "rest.prde.immedia-semi.com";

my $BlinkCamera_hostpattern = "rest##sep####region##.immedia-semi.com";


my $BlinkCamera_header = "agent: TelegramBot/1.0\r\nUser-Agent: TelegramBot/1.0";
# my $BlinkCamera_header = "agent: TelegramBot/1.0\r\nUser-Agent: TelegramBot/1.0\r\nAccept-Charset: utf-8";

my $BlinkCamera_loginjson = "{ \"password\" : \"q_password_q\", \"client_specifier\" : \"FHEM blinkCameraModule 1 - q_name_q\", \"email\" : \"q_email_q\" }";

my $BlinkCamera_configCamAlertjson = "{ \"camera\" : \"q_id_q\", \"id\" : \"q_id_q\", \"network\" : \"q_network_q\", \"motion_alert\" : \"q_alert_q\" }";

my $BlinkCamera_configOwljson = "{ \"enabled\" : q_value_q }";

my $BlinkCamera_deleteVideojson = "{ \"video_list\" : [ q_id_q ] }";

my $BlinkCamera_cameraThumbnailjson = "{ \"id\" : \"q_id_q\", \"network\" : \"q_network_q\" }";


my $BlinkCamera_imgTemplate="<html><a href=\"#URL#\"><img src=\"#URL#\" height=36 widht=64>#URL#</a></html>";
my $BlinkCamera_vidTemplate="<html><a href=\"#URL#\">Video Id:#ID#:  #URL#</a></html>";

#     store list of videos in hash/intern - id -> deleted -> created_at, updated_at, camera_id, viewed, video
my $BlinkCamera_alertEntry='^([^\|]*)\|([^\|]*)\|([^\|]*)\|([^\|]*)\|(.*)$';

# always include name for name of the device to find the right device hash in proxy
my $BlinkCamera_camerathumbnail = "BlinkCamera/q_name_q/thumbnail/camera/q_id_q.jpg";
my $BlinkCamera_videofile = "BlinkCamera/q_name_q/video/q_id_q.mp4";

# special debug setting
my $BlinkCamera_specialLog = 4;


##############################################################################
##############################################################################
##
## Module operation
##
##############################################################################
##############################################################################

#####################################
# Initialize is called from fhem.pl after loading the module
#  define functions and attributed for the module and corresponding devices

sub BlinkCamera_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}      = "BlinkCamera_Define";
  $hash->{UndefFn}    = "BlinkCamera_Undef";
  $hash->{DeleteFn}    = "BlinkCamera_Delete";
  $hash->{GetFn}      = "BlinkCamera_Get";
  $hash->{SetFn}      = "BlinkCamera_Set";
  $hash->{AttrFn}     = "BlinkCamera_Attr";
  $hash->{AttrList}   = " maxRetries:0,1,2,3,4,5 ".
          "imgTemplate:textField ".
          "imgOriginalFile:0,1 ".
          "videoTemplate:textField ".
          "proxyDir:textField ".
          "webname:textField ".
          "network ".
          "pollingTimeout ".
          "homeScreenV3:0,1 ".
          $readingFnAttributes;           
}


######################################
#  Define function is called for actually defining a device of the corresponding module
#  For BlinkCamera this is email address and password
#  data will be stored in the hash of the device as internals / password as setkeyvalue
#  
sub BlinkCamera_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $name = $hash->{NAME};

  Log3 $name, 3, "BlinkCamera_Define $name: called ";

  my $errmsg = '';
  
  # Check parameter(s)
  if ( ( int(@a) != 4 ) && ( int(@a) != 3 ) ) {
    $errmsg = "syntax error: define <name> BlinkCamera <email> [ <password> ] ";
    Log3 $name, 1, "BlinkCamera $name: " . $errmsg;
    return $errmsg;
  }
  
  if ( $a[2] =~ /^.+@.+$/ ) {
    $hash->{Email} = $a[2];
  } else {
    $errmsg = "specify valid email address define <name> BlinkCamera <email> [ <password> ] ";
    Log3 $name, 1, "BlinkCamera $name: " . $errmsg;
    return $errmsg;
  }

  
  if ( int(@a) == 3 ) {
    my ($err, $password) = getKeyValue("BlinkCamera_".$hash->{Email});
    if ( defined($err) ){
      $errmsg = "no password token found (Error:".$err.") specify password with define <name> BlinkCamera <email> [ <password> ] ";
      Log3 $name, 1, "BlinkCamera $name: " . $errmsg;
      return $errmsg;
    } elsif ( ! defined($password) ) {
      $errmsg = "no password token found specify password with define <name> BlinkCamera <email> [ <password> ] ";
      Log3 $name, 1, "BlinkCamera $name: " . $errmsg;
      return $errmsg;
    }
  } else {
    setKeyValue(  "BlinkCamera_".$hash->{Email}, $a[3] ); 
    # remove password from def
    $hash->{DEF} = $hash->{Email};
  }
    
  my $ret;
  
  $hash->{TYPE} = "BlinkCamera";

  $hash->{STATE} = "Undefined";

  BlinkCamera_Setup( $hash );

  return $ret; 
}

#####################################
#  Undef function is corresponding to the delete command the opposite to the define function 
#  Cleanup the device specifically for external ressources like connections, open files, 
#    external memory outside of hash, sub processes and timers
sub BlinkCamera_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, "BlinkCamera_Undef $name: called ";

  HttpUtils_Close($hash->{HU_DO_PARAMS}); 

  RemoveInternalTimer($hash);

  RemoveInternalTimer($hash->{HU_DO_PARAMS});

  Log3 $name, 4, "BlinkCamera_Undef $name: done ";
  return undef;
}

#####################################
#  Undef function is corresponding to the delete command the opposite to the define function 
#  Cleanup the device specifically for external ressources like connections, open files, 
#    external memory outside of hash, sub processes and timers
sub BlinkCamera_Delete($$)
{
  my ($hash, $name) = @_;

  Log3 $name, 3, "BlinkCamera_Delete $name: called ";

  setKeyValue(  "BlinkCamera_".$hash->{Email}, undef ); 
  
  Log3 $name, 4, "BlinkCamera_Delete $name: done ";
  return undef;
}

##############################################################################
##############################################################################
##
## Instance operational methods
##
##############################################################################
##############################################################################


####################################
# set function for executing set operations on device
sub BlinkCamera_Set($@)
{
  my ( $hash, $name, @args ) = @_;
  
  ### Check Args
  my $numberOfArgs  = int(@args);
  return "BlinkCamera_Set: No cmd specified for set" if ( $numberOfArgs < 1 );

  my $cmd = shift @args;

  my $addArg = ($args[0] ? join(" ", @args ) : undef);

  Log3 $name, 5, "BlinkCamera_Set $name: Processing BlinkCamera_Set( $cmd ) - args :".(defined($addArg)?$addArg:"<undef>").":" if ( $cmd ne "?" );

  # check cmd / handle ?
  my $ret = BlinkCamera_CheckSetGet( $hash, $cmd, $hash->{setoptions} );

  if ( $ret ) {

    # do nothing if error/ret is defined
  } elsif ($cmd eq 'login') {
    $ret = BlinkCamera_DoCmd( $hash, $cmd );
  
  } elsif( ($cmd eq 'camEnable') || ($cmd eq 'camDisable') ) {
      $ret = BlinkCamera_CameraDoCmd( $hash, $cmd, $addArg )
      
  } elsif( ($cmd eq 'arm') || ($cmd eq 'disarm') ) {
    $ret = BlinkCamera_DoCmd( $hash, $cmd );

  } elsif($cmd eq 'reset') {
    Log3 $name, 3, "BlinkCamera_Set $name: reset requested ";
    BlinkCamera_Setup( $hash );

  } elsif($cmd eq 'videoDelete') {
    $ret = BlinkCamera_DoCmd( $hash, "videoDelete", $addArg );
    
  } elsif($cmd eq 'zDebug') {
    Log3 $name, 5, "BlinkCamera_Set $name: zDebug requested ";
#    $hash->{AuthToken} = "ABCDEF";
#    Debug "-------------------------";
#    Debug Dumper( $hash->{alertResults} );
#    Debug "-------------------------";
#    Debug Dumper( $hash->{videos} );
#    Debug "-------------------------";

  }

  Log3 $name, 5, "BlinkCamera_Set $name: $cmd ".((defined( $ret ))?"failed with :$ret: ":"done succesful ") 
    if ( $cmd ne "?" );
  return $ret
}

#####################################
# get function for gaining information from device
sub BlinkCamera_Get($@)
{
  my ( $hash, $name, @args ) = @_;
  
  ### Check Args
  my $numberOfArgs  = int(@args);
  return "BlinkCamera_Get: No value specified for get" if ( $numberOfArgs < 1 );
 
  my $cmd = $args[0];
  my $arg = $args[1];

  Log3 $name, 5, "BlinkCamera_Get $name: Processing BlinkCamera_Get( $cmd )" if ( $cmd ne "?" );

  # check cmd / handle ?
  my $ret = BlinkCamera_CheckSetGet( $hash, $cmd, $hash->{getoptions} );

  if ( $ret ) {
    # do nothing if error/ret is defined
  } elsif($cmd eq 'getInfo') {
    $ret = BlinkCamera_DoCmd( $hash, "homescreen" );
  
  } elsif($cmd eq 'getNetworks') {
    $ret = BlinkCamera_DoCmd( $hash, "networks" );
  
  } elsif ($cmd eq 'getInfoCamera') {
    return "BlinkCamera_Get: No value specified for get $cmd" if ( $numberOfArgs < 2 ) ;
    $ret = BlinkCamera_CameraDoCmd( $hash, "cameraConfig", $arg );

  } elsif ($cmd eq 'getThumbnail') {
    return "BlinkCamera_Get: No value specified for get $cmd" if ( $numberOfArgs < 2 ) ;
    $ret = BlinkCamera_CameraDoCmd( $hash, "cameraThumbnail", $arg );

  } elsif($cmd eq 'getVideoAlert') {
    $ret = BlinkCamera_DoCmd( $hash, "video", $arg );
    
  } elsif($cmd eq 'liveview') {
    return "BlinkCamera_Get: No value specified for get $cmd" if ( $numberOfArgs < 2 ) ;
    $ret = BlinkCamera_CameraDoCmd( $hash, "liveview", $arg );
    
  } elsif($cmd eq 'cameraList') {
    my $cList = BlinkCamera_GetCameraId( $hash );
    if ( ! defined( $cList ) ) {
      $ret = "ERROR: No cameras found - need to run getInfo?";
    } else {
      foreach my $cam ( @$cList ) {
        $ret = (defined($ret)?$ret."\n":"").$cam;
      }
    }
    $ret = "ERROR: cameralist is empty" if ( ! $ret );
    return $ret
  }
  
  Log3 $name, 5, "BlinkCamera_Get $name: $cmd ".((defined( $ret ))?"failed with :$ret: ":"done succesful ") if ( $cmd ne "?" );

  return $ret
}

##############################
# attr function for setting fhem attributes for the device
sub BlinkCamera_Attr(@) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};

  Log3 $name, 5, "BlinkCamera_Attr $name: called ";

  return "\"BlinkCamera_Attr: \" $name does not exist" if (!defined($hash));

  if (defined($aVal)) {
    Log3 $name, 5, "BlinkCamera_Attr $name: $cmd  on $aName to $aVal";
  } else {
    Log3 $name, 5, "BlinkCamera_Attr $name: $cmd  on $aName to <undef>";
  }
  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value
  if ($cmd eq "set") {
    if ( ($aName eq 'boolValue') ) {
      $aVal = ($aVal eq "1")? "1": "0";

    } elsif ($aName eq 'pollingTimeout') {
      return "\"BlinkCamera_Attr: \" $aName needs to be given in digits only" if ( $aVal !~ /^[[:digit:]]+$/ );
      # let all existing methods run into block
      RemoveInternalTimer($hash);
      $hash->{POLLING} = -1;
      
      # wait some time before next polling is starting
      BlinkCamera_ResetPollInfo( $hash );

    } elsif ($aName eq 'pollingVerbose') {
      return "\"BlinkCamera_Attr: \" Incorrect value given for pollingVerbose" if ( $aVal !~ /^((1_Digest)|(2_Log)|(0_None))$/ );

    }

    $_[3] = $aVal;
  
  }

  return undef;
}
  
   
  
##############################################################################
##############################################################################
##
## Communication - Do command
##
##############################################################################
##############################################################################


#####################################
# INTERNAL: Function to send a command to the blink server
# cmd is login / arm / homescreen 
# par1/par2 are placeholder for addtl params
sub BlinkCamera_DoCmd($$;$$$)
{
  my ( $hash, @args) = @_;

  my ( $cmd, $par1, $par2, $retryCount) = @args;
  my $name = $hash->{NAME};
  
  $retryCount = 0 if ( ! defined( $retryCount ) );

  # increase retrycount for next try
  $args[3] = $retryCount+1;
  
  my $cmdString = $cmd.(defined($par1)?"  par1:".$par1.":":"").(defined($par2)?"  par2:".$par2.":":"");
  
  Log3 $name, 4, "BlinkCamera_DoCmd $name: called  for cmd :$cmdString:";
  
  # ensure cmdQueue exists
  $hash->{cmdQueue} = [] if ( ! defined( $hash->{cmdQueue} ) );

  # Queue if not yet retried and currently waiting
  if ( ( defined( $hash->{doStatus} ) ) && ( $hash->{doStatus} =~ /^WAITING/ ) && (  $retryCount == 0 ) ){
    # add to queue
    Log3 $name, $BlinkCamera_specialLog, "BlinkCamera_DoCmd $name: add send to queue cmd ".$cmdString;
    # command / alert will always be added to the beginning of the queue
    if ( ( $cmd eq "command" ) || ( $cmd eq "alerts" ))  {
      unshift( @{ $hash->{cmdQueue} }, \@args );
    } else {
      push( @{ $hash->{cmdQueue} }, \@args );
    }
    return;
  }  

  #######################
  # check authentication otherwise queue the current cmd and do authenticate first
  if ( ($cmd ne "login") && ( ! defined( $hash->{AuthToken} ) ) ) {
    # add to queue
    Log3 $name, 4, "BlinkCamera_DoCmd $name: add send to queue cmd ".$cmdString;
    push( @{ $hash->{cmdQueue} }, \@args );
    $cmd = "login";
    $par1 = undef;
    $par2 = undef;
    # update cmdstring
    $cmdString = "cmd :$cmd: ".(defined($par1)?"  par1:".$par1.":":"").(defined($par2)?"  par2:".$par2.":":"");
  }
  
  #######################
  # Check for invalid auth token and just remove cmds
  if ( ($cmd ne "login") && ( $hash->{AuthToken} eq "INVALID" ) ) {
    # add to queue
    Log3 $name, 2, "BlinkCamera_DoCmd $name: failed due to invalid auth token ".$cmdString;
    return;
  } 
  
  
  #######################
  # check networks if not existing queue current cmd and get networks first
  my $net =  BlinkCamera_GetNetwork( $hash ); 
  if ( ($cmd ne "login") && ($cmd ne "networks") && ( ! defined( $net ) ) ) {
    # add to queue
    Log3 $name, 4, "BlinkCamera_DoCmd $name: add send to queue cmd ".$cmdString;
    push( @{ $hash->{cmdQueue} }, \@args );
    $cmd = "networks";
    $par1 = undef;
    $par2 = undef;
    # update cmdstring
    $cmdString = "cmd :$cmd: ".(defined($par1)?"  par1:".$par1.":":"").(defined($par2)?"  par2:".$par2.":":"");
  }
  
  #######################
  # Check for invalid auth token and just remove cmds
  if ( ($cmd ne "login") && ($cmd ne "networks") && ( $net eq "INVALID" ) ) {
    # add to queue
    Log3 $name, 2, "BlinkCamera_DoCmd $name: failed due to invalid networks list (set attribute network) ".$cmdString;
    return;
  } 

  my $ret;

  $hash->{doStatus} = "WAITING";
  $hash->{doStatus} .= " retry $retryCount" if ( $retryCount > 0 );
  
  $hash->{AuthToken} = "INVALID" if ($cmd eq "login");
  
  # reset networks reading for reading networks
  readingsSingleUpdate($hash, "networks", "INVALID", 0 ) if ( ($cmd eq "networks") );
 
  Log3 $name, 4, "BlinkCamera_DoCmd $name: try to send cmd ".$cmdString;

  if ( ( !defined( $par2 ) ) || ( ($par2 ne "POLLING" ) && ($par2 ne "HIDDEN" ) ) ) {
    $hash->{cmd} = $cmdString; 
    $hash->{cmdJson} = "";
  }
  
  # init param hash
  $hash->{HU_DO_PARAMS}->{hash} = $hash;
  delete( $hash->{HU_DO_PARAMS}->{args} );
  delete( $hash->{HU_DO_PARAMS}->{boundary} );
  delete( $hash->{HU_DO_PARAMS}->{compress} );
  delete( $hash->{HU_DO_PARAMS}->{filename} );

  $hash->{HU_DO_PARAMS}->{cmd} = $cmd;
  $hash->{HU_DO_PARAMS}->{par1} = $par1;
  $hash->{HU_DO_PARAMS}->{par2} = $par2;
  
  my $timeout =   AttrVal($name,'cmdTimeout',30);
  $hash->{HU_DO_PARAMS}->{timeout} = $timeout;

  # only for test / debug               
  $hash->{HU_DO_PARAMS}->{loglevel} = 4;
  
  $hash->{HU_DO_PARAMS}->{callback} = \&BlinkCamera_Callback;

#????????????
#SIZE_NOTIFICATION_KEY = 152
#SIZE_UID = 16
#         uid = util.gen_uid(const.SIZE_UID)
#        notification_key = util.gen_uid(const.SIZE_NOTIFICATION_KEY) 
#
#
#
#
#
# generate 32 hex values or 16 HEx BYTES
#my $rand_hex = join "", map { unpack "H*", chr(rand(256)) } 1..16;

my $notif_key = join "", map { unpack "H*", chr(rand(256)) } 1..76;
my $uid_key = join "", map { unpack "H*", chr(rand(256)) } 1..8;


  # handle data creation only if no error so far
  if ( ! defined( $ret ) ) {

    $hash->{HU_DO_PARAMS}->{method} = "POST";
    
    my $dynhost = $BlinkCamera_hostpattern;
    my $region = ReadingsVal( $name, "region", "prde" );
    
    if ($cmd eq "login") {
      $dynhost =~ s/##region##/prod/;
#      $dynhost =~ s/##sep##/-/;
    } else {
      $dynhost =~ s/##region##/$region/;
#      $dynhost =~ s/##sep##/./;
    }
    $dynhost =~ s/##sep##/-/;
    $hash->{URL} = "https://".$dynhost;
  
    $hash->{HU_DO_PARAMS}->{header} = $BlinkCamera_header.
      "\r\n"."Host: ".$dynhost;

    #######################
    if ($cmd eq "login") {
    
        $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."Content-Type: application/json";

###      $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/login";
      $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/api/v3/login";
#      $hash->{HU_DO_PARAMS}->{url} = "http://requestb.in";
      
      $hash->{HU_DO_PARAMS}->{data} = $BlinkCamera_loginjson;
#      $hash->{HU_DO_PARAMS}->{compress} = 1;
      
      my $email = $hash->{Email};
      my ($err, $password) = getKeyValue("BlinkCamera_".$email);

      if(defined($err)) {
        $ret =  "BlinkCamera_DoCmd $name: password retrieval failed with :$err:";
      } elsif(! defined($password)) {
        $ret =  "BlinkCamera_DoCmd $name: password is empty";
      } else {
        $hash->{HU_DO_PARAMS}->{data} =~ s/q_password_q/$password/g;
        $hash->{HU_DO_PARAMS}->{data} =~ s/q_email_q/$email/g;
        $hash->{HU_DO_PARAMS}->{data} =~ s/q_name_q/$name/g;

        Log3 $name, 4, "BlinkCamera_DoCmd $name:   data :".$hash->{HU_DO_PARAMS}->{data}.":";

      }
        
    #######################
    } elsif ( ($cmd eq "camEnable") || ($cmd eq "camDisable" ) ) {
    
      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken}."\r\n"."Content-Type: application/json";

      
      my $net =  BlinkCamera_GetNetwork( $hash );
      my $ctype = "invalid";
      
      if ( ! defined( $net ) ) {
        $ret = "BlinkCamera_DoCmd $name: no network identifier found for $cmd - set attribute";
      } else {
        $ctype =  BlinkCamera_GetCamType( $hash, $par1 );
      }

      if ( ! $ret ) {

        my $alert = ($cmd eq "camEnable")?"true":"false";
      
        if ( $ctype eq "camera" ) {
          $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/network/".$net."/camera/".$par1."/update";
        
          $hash->{HU_DO_PARAMS}->{data} = $BlinkCamera_configCamAlertjson;
          $hash->{HU_DO_PARAMS}->{data} =~ s/q_id_q/$par1/g;
          $hash->{HU_DO_PARAMS}->{data} =~ s/q_network_q/$net/g;
          $hash->{HU_DO_PARAMS}->{data} =~ s/q_alert_q/$alert/g;
          Log3 $name, 4, "BlinkCamera_DoCmd $name:   cam type: ".$ctype.":  - data :".$hash->{HU_DO_PARAMS}->{data}.":";
        } elsif ( $ctype eq "owl" ) {
        
          $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/api/v1/accounts/".$hash->{account}."/networks/".$net."/owls/".$par1."/config";
          
          $hash->{HU_DO_PARAMS}->{data} = $BlinkCamera_configOwljson;
          $hash->{HU_DO_PARAMS}->{data} =~ s/q_value_q/$alert/g;
          Log3 $name, 4, "BlinkCamera_DoCmd $name:   cam type: ".$ctype.":  - data :".$hash->{HU_DO_PARAMS}->{data}.":";
        } else {
          $ret = "BlinkCamera_DoCmd $name: camera type (".$ctype."( unknown !!";
        }

      }

    #######################
    } elsif ( ($cmd eq "arm") || ($cmd eq "disarm" ) ) {

      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken};
      
      my $net =  BlinkCamera_GetNetwork( $hash );
      if ( defined( $net ) ) {
        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/network/".$net."/".$cmd;
      } else {
        $ret = "BlinkCamera_DoCmd $name: no network identifier found for arm/disarm - set attribute";
      }

    #######################
    } elsif ($cmd eq "homescreen" ) {

      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken};
      
      $hash->{HU_DO_PARAMS}->{method} = "GET";
      
      my $newHomeScreen = AttrVal($name,'homeScreenV3',"0");
      
      if ( $newHomeScreen ) {
        my $acc = $hash->{account};

        if ( defined( $acc ) ) {
          $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/api/v3/accounts/".$net."/".$cmd;
        } else {
          $ret = "BlinkCamera_DoCmd $name: no account id found for homescreen";
        }
      } else {
        my $net =  BlinkCamera_GetNetwork( $hash );
        if ( defined( $net ) ) {
          $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/network/".$net."/".$cmd;
        } else {
          $ret = "BlinkCamera_DoCmd $name: no network identifier found for homescreen - set attribute";
        }
      }

    #######################
    } elsif ( ($cmd eq "networks" ) ) {

      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken};
      
      $hash->{HU_DO_PARAMS}->{method} = "GET" ;

      $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/networks";


    #######################
    } elsif ( ($cmd eq "command" )  ) {

      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken};
      
      $hash->{HU_DO_PARAMS}->{method} = "GET";

      my $net =  BlinkCamera_GetNetwork( $hash );
      if ( defined( $net ) ) {
        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/network/".$net."/command/".$par1;
      } else {
        $ret = "BlinkCamera_DoCmd $name: no network identifier found for command - set attribute";
      }

    #######################
    } elsif ( ($cmd eq "alerts" )  ) {

      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken};
      
      $hash->{HU_DO_PARAMS}->{method} = "GET";
      
# OLD V2      $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/api/v2/videos/changed?page=".$par1."&since=".$hash->{alertUpdate};

# V1 seems still working here (v2 has been removed)
# GET https://rest-prde.immedia-semi.com/api/v1/accounts/<id>/media/changed?since=2019-05-26T15%3A22%3A36Z&page=1
      $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/api/v1/accounts/".$hash->{account}."/media/changed?page=".$par1."&since=".$hash->{alertUpdate};
#      my $net =  BlinkCamera_GetNetwork( $hash );
#      if ( defined( $net ) ) {
#        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/api/v2/videos?page=1";
#        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/events/network/".$net."/camera/2148?page=1";
#        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/events/network/".$net;
#        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/api/v2/videos/changed?page=2&since=2016-10-31T15:29:25Z";
#      }

    #######################
    } elsif ( ($cmd eq "cameraConfig" ) ) {

      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken};
      
      $hash->{HU_DO_PARAMS}->{method} = "GET";

      my $net =  BlinkCamera_GetNetwork( $hash );
      if ( defined( $net ) ) {
        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/network/".$net."/camera/".$par1."/config";
      } else {
        $ret = "BlinkCamera_DoCmd $name: no network identifier found for $cmd - set attribute";
      }

    #######################
    } elsif ( ($cmd eq "cameraThumbnail" ) ) {

      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken};
      
      $hash->{HU_DO_PARAMS}->{method} = "POST";
      $hash->{HU_DO_PARAMS}->{data} = "";

      my $net =  BlinkCamera_GetNetwork( $hash );
      if ( defined( $net ) ) {
      
        my $ctype =  BlinkCamera_GetCamType( $hash, $par1 );
        if ( $ctype eq "camera" ) {
          $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/network/".$net."/camera/".$par1."/thumbnail";

#          $hash->{HU_DO_PARAMS}->{data} = $BlinkCamera_cameraThumbnailjson;
#          $hash->{HU_DO_PARAMS}->{data} =~ s/q_network_q/$net/g;
#          $hash->{HU_DO_PARAMS}->{data} =~ s/q_id_q/$par1/g;
          Log3 $name, 4, "BlinkCamera_DoCmd $name:  $cmd cam type: ".$ctype.":  ";
        } elsif ( $ctype eq "owl" ) {
          # https://rest-prde.immedia-semi.com/api/v1/accounts/<accid>/networks/<netid>/owls/<camid>/thumbnail
          $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/api/v1/accounts/".$hash->{account}."/networks/".$net."/owls/".$par1."/thumbnail";
          Log3 $name, 4, "BlinkCamera_DoCmd $name:  $cmd cam type: ".$ctype.":  ";
        } else {
          $ret = "BlinkCamera_DoCmd $name: $cmd camera type (".$ctype."( unknown !!";
        }
      
      } else {
        $ret = "BlinkCamera_DoCmd $name: no network identifier found for $cmd - set attribute";
      }

    #######################
    } elsif ($cmd eq "thumbnail") {
      # camera id in par
      
      my $curl =  $hash->{"thumbnail".$par1."Req"};
      Log3 $name, 5, "BlinkCamera_DoCmd $name:   par1 :".$par1.":";
      Log3 $name, 5, "BlinkCamera_DoCmd $name:   curl :".(defined($curl)?$curl:"<undef>").":";
      
      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken};
      $hash->{HU_DO_PARAMS}->{method} = "GET";
      if ( defined( $curl ) ) {
        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}.$curl.".jpg";
        if ( AttrVal( $name, "imgOriginalFile", 0 ) ) {
          if ( $curl =~ /^.*\/([^\/]+)/ ) {
            my $orgthumbfile = $1;
            $hash->{HU_DO_PARAMS}->{filename} = BlinkCamera_ReplacePattern( $BlinkCamera_camerathumbnail, $par1."_".$orgthumbfile, $name );
          } else {
            $ret = "BlinkCamera_DoCmd $name: url did not contain filename " 
          }
        } else {
          $hash->{HU_DO_PARAMS}->{filename} = BlinkCamera_ReplacePattern( $BlinkCamera_camerathumbnail, $par1, $name );
        }
      } else {
        $ret = "BlinkCamera_DoCmd $name: no url found " 
      }
      
    #######################
    } elsif ($cmd eq "video") {
      # video id in par or take reading alertID
      my $vid = $par1;
      $vid = ReadingsVal( $name, "alertID", undef ) if ( !defined( $vid) );
      
      my $vidUrl = BlinkCamera_GetAlertVideoURL( $hash, $vid ) if ( defined( $vid) );
      
      # store back in par1 the actual video reques
      $par1 = $vid;
      $hash->{HU_DO_PARAMS}->{par1} = $par1;
      
      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken};
      $hash->{HU_DO_PARAMS}->{method} = "GET";

      if ( defined( $vidUrl ) ) {
        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}.$vidUrl;
        #     --> /tmp/BlinkCamera_<device>_thumbnail_<id>_<something 1 or 2>.<ext=jpg>
        $hash->{HU_DO_PARAMS}->{filename} = BlinkCamera_ReplacePattern( $BlinkCamera_videofile, $vid, $name );
        
      } else {
        $ret = "BlinkCamera_DoCmd $name: no video id or url found (".(defined($vid)?$vid:"<undef>").")"; 
      }
      
    #######################
    } elsif ($cmd eq "videoDelete") {
      # video id in par or take reading alertID
      my $vid = $par1;
      $vid = ReadingsVal( $name, "alertID", undef ) if ( !defined( $vid) );
      
      # first remove proxy file if existing
      my $vidUrl = BlinkCamera_GetAlertVideoURL( $hash, $vid ) if ( defined( $vid) );
      if ( defined( $vidUrl ) ) {
        my $filename = BlinkCamera_ReplacePattern( $BlinkCamera_videofile, $vid, $name );
        my $proxyDir = AttrVal($name,"proxyDir","/tmp/");

        # normalize URL separator / into _
        $filename =~ s/\//_/g;

        Log3 $name, 4, "BlinkCamera_DoCmd $name: deleting $filename in $proxyDir "; 

        eval { unlink $proxyDir."/".$filename; } if ( -e $proxyDir."/".$filename );
        Log3 $name, 2, "BlinkCamera_DoCmd $name: video file $filename could not be deleted :$@: " if $@; 
      }
        
      if ( defined( $vid ) ) {
        $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken}."\r\n"."Content-Type: application/json";

        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/api/v3/videos/delete";
        $hash->{HU_DO_PARAMS}->{data} = $BlinkCamera_deleteVideojson;
        $hash->{HU_DO_PARAMS}->{data} =~ s/q_id_q/$vid/g;

        Log3 $name, 4, "BlinkCamera_DoCmd $name:   data :".$hash->{HU_DO_PARAMS}->{data}.":";

      } else {
        $ret = "BlinkCamera_DoCmd $name: no video id for deletion found (".(defined($vid)?$vid:"<undef>").")"; 
      }
      
    #######################
    } elsif ( ($cmd eq "liveview" ) ) {

      $hash->{HU_DO_PARAMS}->{header} .= "\r\n"."TOKEN_AUTH: ".$hash->{AuthToken};
      
      $hash->{HU_DO_PARAMS}->{method} = "POST";

      my $net =  BlinkCamera_GetNetwork( $hash );
      if ( defined( $net ) ) {
        $hash->{HU_DO_PARAMS}->{url} = $hash->{URL}."/network/".$net."/camera/".$par1."/liveview";

      } else {
        $ret = "BlinkCamera_DoCmd $name: no network identifier found for $cmd - set attribute";
      }

    }

  }
  #######################
  
  ## JVI
#  Debug "send command  :".$hash->{HU_DO_PARAMS}->{data}.":";
  
  if ( defined( $ret ) ) {
    Log3 $name, 1, "BlinkCamera_DoCmd $name: Failed with :$ret:";
    BlinkCamera_Callback( $hash->{HU_DO_PARAMS}, $ret, "");

  } else {
    $hash->{HU_DO_PARAMS}->{args} = \@args;
    
    Log3 $name, 4, "BlinkCamera_DoCmd $name: call url :".$hash->{HU_DO_PARAMS}->{url}.": ";
    HttpUtils_NonblockingGet( $hash->{HU_DO_PARAMS} );

  }
  
  return $ret;
}


##############################################################################
##############################################################################
##
## callback
##
##############################################################################
##############################################################################

#####################################
#  INTERNAL: Called to retry a send operation after wait time
#   Gets the do params
sub BlinkCamera_RetryDo($)
{
  my ( $param ) = @_;
  my $hash= $param->{hash};
  my $name = $hash->{NAME};


  my $ref = $param->{args};
  Log3 $name, 4, "BlinkCamera_RetryDo $name: call retry @$ref[3]  cmd:@$ref[0]: par1:".(defined(@$ref[1])?@$ref[1]:"<undef>").": par2:".(defined(@$ref[2])?@$ref[2]:"<undef>").": ";
  BlinkCamera_DoCmd( $hash, @$ref[0], @$ref[1], @$ref[2], @$ref[3] );
  
}


#####################################
#  INTERNAL: Encode a deep structure
#   name <elements to be encoded>
sub BlinkCamera_Deepencode
{
    my @result;

    my $name = shift( @_ );

#    Debug "BlinkCamera_Deepencode with :".(@_).":";

    for (@_) {
        my $reftype= ref $_;
        if( $reftype eq "ARRAY" ) {
            Log3 $name, 5, "BlinkCamera_Deepencode $name: found an ARRAY";
            push @result, [ BlinkCamera_Deepencode($name, @$_) ];
        }
        elsif( $reftype eq "HASH" ) {
            my %h;
            @h{keys %$_}= BlinkCamera_Deepencode($name, values %$_);
            Log3 $name, 5, "BlinkCamera_Deepencode $name: found a HASH";
            push @result, \%h;
        }
        else {
            my $us = $_ ;
            if ( utf8::is_utf8($us) ) {
              $us = encode_utf8( $_ );
            }
            Log3 $name, 5, "BlinkCamera_Deepencode $name: encoded a String from :".(defined($_)?$_:"<undef>").": to :".(defined($us)?$us:"<undef>").":";
            push @result, $us;
        }
    }
    return @_ == 1 ? $result[0] : @result; 

}

#####################################
#  INTERNAL: Parse the login results
sub BlinkCamera_ParseLogin($$$)
{
  my ( $hash, $result, $readUpdates ) = @_;
  my $name = $hash->{NAME};

  my $ret;

  if ( defined( $result->{authtoken} ) ) {
    my $at = $result->{authtoken};
    if ( defined( $at->{authtoken} ) ) {
      $hash->{AuthToken} = $at->{authtoken};
    }
    if ( defined( $result->{account} ) ) {
      my $acc = $result->{account};
      if ( defined( $acc->{id} ) ) {
        $hash->{account} = $acc->{id};
      }
    }
  }
  
  my $resreg = $result->{region};
  if ( defined( $resreg ) ) {
    my $regkey = ( keys %$resreg )[0];
    $readUpdates->{region} = $regkey;
    $readUpdates->{regionName} = $resreg->{$regkey};
  } else {
    $readUpdates->{region} = undef;    
    $readUpdates->{regionName} = undef;    
  }
  
  return $ret;
}


# OLD LOGIN #####################################
# #  INTERNAL: Parse the login results
# sub BlinkCamera_ParseLogin($$$)
# {
  # my ( $hash, $result, $readUpdates ) = @_;
  # my $name = $hash->{NAME};

  # my $ret;

  # if ( defined( $result->{authtoken} ) ) {
    # my $at = $result->{authtoken};
    # if ( defined( $at->{authtoken} ) ) {
      # $hash->{AuthToken} = $at->{authtoken};
    # }
    # if ( defined( $result->{account} ) ) {
      # my $acc = $result->{account};
      # if ( defined( $acc->{id} ) ) {
        # $hash->{account} = $acc->{id};
      # }
    # }
  # }
  
  # # grab network list
  # my $resnet = $result->{networks};
  # my $netlist = "";
  # if ( defined( $resnet ) ) {
    # Log3 $name, 4, "BlinkCamera_Callback $name: login number of networks ".scalar(keys %$resnet) ;
    # foreach my $netkey ( keys %$resnet ) {
      # Log3 $name, 4, "BlinkCamera_Callback $name: network  ".$netkey ;
      # my $net =  $resnet->{$netkey};
      # my $ob = 0;
      # $ob = 1 if ( ( defined( $net->{onboarded} ) ) && ( $net->{onboarded}) );
      # my $ns = $netkey.":".$net->{name};
# #      Log3 $name, 4, "BlinkCamera_Callback $name: onboarded  :".$net->{onboarded}.":" ;
      # if ( $ob ) {
      # Log3 $name, 4, "BlinkCamera_Callback $name: found onboarded network  ".$netkey ;
        # $ns .= "\n" if ( length( $netlist) > 0 );
        # $netlist = $ns.$netlist;
      # } else {
        # $netlist .= "\n" if ( length( $netlist) > 0 );
        # $netlist .= $ns;
      # }
    # }
  # }
  # $readUpdates->{networks} = $netlist;
  # my $resreg = $result->{region};
  # if ( defined( $resreg ) ) {
    # my $regkey = ( keys %$resreg )[0];
    # $readUpdates->{region} = $regkey;
    # $readUpdates->{regionName} = $resreg->{$regkey};
  # } else {
    # $readUpdates->{region} = undef;    
    # $readUpdates->{regionName} = undef;    
  # }
  
  # return $ret;
# }


#####################################
#  INTERNAL: Parse the networks results
sub BlinkCamera_ParseNetworks($$$)
{
  my ( $hash, $result, $readUpdates ) = @_;
  my $name = $hash->{NAME};

  my $ret;

  # grab network list from summary
  my $resnet = $result->{summary};
  my $netlist = "";
  if ( defined( $resnet ) ) {
    Log3 $name, 4, "BlinkCamera_Callback $name: login number of networks ".scalar(keys %$resnet) ;
    foreach my $netkey ( keys %$resnet ) {
      Log3 $name, 4, "BlinkCamera_Callback $name: network  ".$netkey ;
      my $net =  $resnet->{$netkey};
      my $ob = 0;
      $ob = 1 if ( ( defined( $net->{onboarded} ) ) && ( $net->{onboarded}) );
      my $ns = $netkey.":".$net->{name};
#      Log3 $name, 4, "BlinkCamera_Callback $name: onboarded  :".$net->{onboarded}.":" ;
      if ( $ob ) {
      Log3 $name, 4, "BlinkCamera_Callback $name: found onboarded network  ".$netkey ;
        $ns .= "\n" if ( length( $netlist) > 0 );
        $netlist = $ns.$netlist;
      } else {
        $netlist .= "\n" if ( length( $netlist) > 0 );
        $netlist .= $ns;
      }
    }
  }
  $readUpdates->{networks} = $netlist;

  return $ret;
}



#### OLD HOMESCREEN BEFORE V3 #####################################
#####################################
#  INTERNAL: Parse the homescreen results
sub BlinkCamera_ParseHomescreenOLD($$$)
{
  my ( $hash, $result, $readUpdates ) = @_;
  my $name = $hash->{NAME};

  my $ret;

  my $network = $result->{network};

  Log3 $name, 4, "BlinkCamera_ParseHomescreen $name:  ";
  
  # Homescreen succesful so start a request for alerst/videos/notifications
  $hash->{alertSkipped} = 0 if ( ! defined ($hash->{alertSkipped} ) );
  if ( defined ($hash->{alertUpdate} ) ) {
    $hash->{alertSkipped} += 1;
  } else {
    BlinkCamera_ParseStartAlerts($hash) 
  }

  # Get overall status
  $readUpdates->{networkName} = "";
  $readUpdates->{networkStatus} = "";
  $readUpdates->{networkArmed} = "";
  $readUpdates->{networkNotifications} = "";
  if ( defined( $network ) ) {
    $readUpdates->{networkName} = $network->{name} if ( defined( $network->{name} ) );
    $readUpdates->{networkStatus} = $network->{status} if ( defined( $network->{status} ) );
    $readUpdates->{networkArmed} = $network->{armed} if ( defined( $network->{armed} ) );
    $readUpdates->{networkNotifications} = $network->{notifications} if ( defined( $network->{notifications} ) );
    Log3 $name, 4, "BlinkCamera_ParseHomescreen $name:  foudn network info for network ";
  }

  # devices
  my $devList = $result->{devices};
  
  
  # loop through readings to reset all existing Cameras - but leave Img (otherwise too many events on thumbnails)
  if ( defined($hash->{READINGS}) ) {
    foreach my $cam ( keys  %{$hash->{READINGS}} ) {
      $readUpdates->{$cam} = undef if ( ( $cam =~ /^networkCamera/ ) && ( $cam !~ /^networkCamera.*Img/ ) );
    }
  }
  $readUpdates->{networkSyncModule} = "";
  
  # loop through devices and build a reading for cameras and a reading for the 
  if ( defined( $devList ) ) {
    my $cameraGets = "";
    my $cameras = "";
    foreach my $device ( @$devList ) {
      if ( $device->{device_type} eq "camera" ) {
#        Debug "Device loop: ".$device->{device_id};
        $readUpdates->{"networkCamera".$device->{device_id}} = $device->{name}.":".$device->{active};
        $readUpdates->{"networkCamera".$device->{device_id}."Name"} = $device->{name};
        $readUpdates->{"networkCamera".$device->{device_id}."Type"} = "camera";
        $readUpdates->{"networkCamera".$device->{device_id}."Active"} = $device->{active};
        $cameraGets .= $device->{name}.",".$device->{device_id}.",";
        $cameras .= $device->{device_id}.":".$device->{name}."\n";
        if ( defined( $device->{thumbnail} ) ) {
          # Load Thumbnail only if not already there
          if ( ( ! defined( $hash->{"thumbnail".$device->{device_id}."Url"} ) ||
               ( $hash->{"thumbnail".$device->{device_id}."Url"} ne $device->{thumbnail} ) ) ) {
            if ( ! defined( $hash->{"thumbnail".$device->{device_id}."Req"} ) ) {
#              Debug "retreive thumbnail from homescreen for ".$device->{device_id};
              # Do thumbnail request only of not already there (e.g. by polling)
              $hash->{"thumbnail".$device->{device_id}."Req"} = $device->{thumbnail};
              BlinkCamera_DoCmd( $hash, "thumbnail", $device->{device_id}, "HIDDEN" );
            } else {
              Log3 $name, 4, "BlinkCamera_ParseHomescreen $name:  thumbnail Req already defined for ".$device->{device_id};
            }
          } else {
            # already there just update readings
            $readUpdates->{"networkCamera".$device->{device_id}."Url"} = BlinkCamera_getwebname( $hash ).
                BlinkCamera_ReplacePattern( $BlinkCamera_camerathumbnail, $device->{device_id}, $name ); 
          }
        }
        $readUpdates->{"networkCamera".$device->{device_id}."Thumbnail"} = $device->{thumbnail}; 
        $readUpdates->{"networkCamera".$device->{device_id}."Batt"} = $device->{battery}; 
        $readUpdates->{"networkCamera".$device->{device_id}."Temp"} = $device->{temp}; 
      } elsif ( $device->{device_type} eq "sync_module" ) {
        if ( length( $readUpdates->{networkSyncModule} ) > 0 ) {
          Log3 $name, 2, "BlinkCamera_ParseHomescreen $name: found multiple syncModules ";
        } else {
          $readUpdates->{networkSyncModule} .= $device->{device_id}.":".$device->{status};
        }
      } else {
        Log3 $name, 2, "BlinkCamera_ParseHomescreen $name: unknown device type found ".$device->{device_type};
      }
    }
    $cameraGets .= "all";
    $hash->{getoptions}->{liveview} = $cameraGets;
    $hash->{getoptions}->{getThumbnail} = $cameraGets;
    $hash->{getoptions}->{getInfoCamera} = $cameraGets;
    $hash->{setoptions}->{camEnable} = $cameraGets;
    $hash->{setoptions}->{camDisable} = $cameraGets;
    $readUpdates->{networkCameras} = $cameras;
  }

  return $ret;
}


#####################################
#  INTERNAL: Parse the homescreen results --> valid for V3 
sub BlinkCamera_ParseHomescreen($$$)
{
  my ( $hash, $result, $readUpdates ) = @_;
  my $name = $hash->{NAME};

  # Run old homescreen parsing if attribute not set
  my $newHomeScreen = AttrVal($name,'homeScreenV3',"0");
  if ( ! $newHomeScreen ) {
    Log3 $name, 4, "BlinkCamera_ParseHomescreen $name: Use old home screen parsing ";
    return BlinkCamera_ParseHomescreenOLD( $hash, $result, $readUpdates );
  }

  ################ NEW ##############

  my $ret;

  Log3 $name, 4, "BlinkCamera_ParseHomescreen $name:  ";
  
  # Homescreen succesful so start a request for alerst/videos/notifications
  $hash->{alertSkipped} = 0 if ( ! defined ($hash->{alertSkipped} ) );
  if ( defined ($hash->{alertUpdate} ) ) {
    $hash->{alertSkipped} += 1;
  } else {
    BlinkCamera_ParseStartAlerts($hash) 
  }

  my $network = BlinkCamera_GetNetwork( $hash );
  if ( ! defined( $network ) ) {
    Log3 $name, 2, "BlinkCamera_ParseHomescreen $name: Network ID not found - please set attribute ";
    $network = "invalid";
  }

  # networks
  my $netList = $result->{networks};
  
  # loop through networks and get the requested network information 
  $readUpdates->{networkName} = "";
  $readUpdates->{networkArmed} = "";
  if ( defined( $netList ) ) {
    foreach my $network ( @$netList ) {
      if ( $network->{id} eq $network ) {
        $readUpdates->{networkName} = $network->{name} if ( defined( $network->{name} ) );
        $readUpdates->{networkArmed} = $network->{armed} if ( defined( $network->{armed} ) );
        Log3 $name, 4, "BlinkCamera_ParseHomescreen $name:  found network info for network ";
        last;
      }
    }
  }

  # sync module information
  my $syncList = $result->{sync_modules};
  
  
  # loop through msync modules and get the requested module information 
  $readUpdates->{networkSyncModule} = "";
  $readUpdates->{networkSyncId} = "";
  $readUpdates->{networkSyncName} = "";
  $readUpdates->{networkSyncSerial} = "";
  $readUpdates->{networkSyncFirmware} = "";
  $readUpdates->{networkSyncWifi} = "";
  if ( defined( $syncList ) ) {
    foreach my $module ( @$syncList ) {
      if ( $module->{network_id} eq $network ) {
        $readUpdates->{networkSyncModule} = $module->{status} if ( defined( $module->{status} ) );
        $readUpdates->{networkSyncId} = $module->{id} if ( defined( $module->{id} ) );
        $readUpdates->{networkSyncName} = $module->{name} if ( defined( $module->{name} ) );
        $readUpdates->{networkSyncSerial} = $module->{serial} if ( defined( $module->{serial} ) );
        $readUpdates->{networkSyncFirmware} = $module->{fw_version} if ( defined( $module->{fw_version} ) );
        $readUpdates->{networkSyncWifi} = $module->{wifi_strength} if ( defined( $module->{wifi_strength} ) );
        Log3 $name, 4, "BlinkCamera_ParseHomescreen $name:  found sync module info for network ";
        last;
      }
    }
  }


  # Cameras and Owls (blink mini)
  my $camList = $result->{cameras};
  my $owlList = $result->{owls};
  
  return $ret if ( ( ! defined( $camList ) ) &&  ( ! defined( $owlList ) ) ); 
  
  my $cameraGets = "";
  my $cameras = "";

  # loop through cameras and get the requested camera information 
  if ( defined( $camList ) ) {
  
    foreach my $device ( @$camList ) {
      if ( $device->{network_id} eq $network ) {
        my $active = "disabled";
#        $active = "armed" if ( $device->{enabled} eq "true" );
        $active = "armed" if ( $device->{enabled} );
        
        $readUpdates->{"networkCamera".$device->{id}} = $device->{name}.":".$active;
        $readUpdates->{"networkCamera".$device->{id}."Name"} = $device->{name};
        $readUpdates->{"networkCamera".$device->{id}."Type"} = "camera";
        $readUpdates->{"networkCamera".$device->{id}."Active"} = $active;
        $cameraGets .= $device->{name}.",".$device->{id}.",";
        $cameras .= $device->{id}.":".$device->{name}."\n";
        
        if ( defined( $device->{thumbnail} ) ) {
          # Load Thumbnail only if not already there
          if ( ( ! defined( $hash->{"thumbnail".$device->{id}."Url"} ) ||
               ( $hash->{"thumbnail".$device->{id}."Url"} ne $device->{thumbnail} ) ) ) {
            if ( ! defined( $hash->{"thumbnail".$device->{id}."Req"} ) ) {
  #              Debug "retreive thumbnail from homescreen for ".$device->{id};
              # Do thumbnail request only of not already there (e.g. by polling)
              $hash->{"thumbnail".$device->{id}."Req"} = $device->{thumbnail};
              BlinkCamera_DoCmd( $hash, "thumbnail", $device->{id}, "HIDDEN" );
            } else {
              Log3 $name, 4, "BlinkCamera_ParseHomescreen $name:  thumbnail Req already defined for ".$device->{id};
            }
          } else {
            # already there just update readings
            $readUpdates->{"networkCamera".$device->{id}."Url"} = BlinkCamera_getwebname( $hash ).
                BlinkCamera_ReplacePattern( $BlinkCamera_camerathumbnail, $device->{id}, $name ); 
          }
          $readUpdates->{"networkCamera".$device->{id}."Thumbnail"} = $device->{thumbnail} ; 
        }
        $readUpdates->{"networkCamera".$device->{id}."Batt"} = $device->{battery} if ( defined( $device->{battery} ) );
        $readUpdates->{"networkCamera".$device->{id}."Firmware"} = $device->{fw_version} if ( defined( $device->{fw_version} ) );
        $readUpdates->{"networkCamera".$device->{id}."Status"} = $device->{status} if ( defined( $device->{status} ) );
        if ( defined( $device->{signals} ) ) {
          my $signal = $device->{signals};
          $readUpdates->{"networkCamera".$device->{id}."Temp"} = $signal->{temp}; 
        }
      }
    }

  }

  # loop through owls and get the requested camera information 
  if ( defined( $owlList ) ) {
  
    foreach my $device ( @$owlList ) {
      if ( $device->{network_id} eq $network ) {
        my $active = "disabled";
#        $active = "armed" if ( $device->{enabled} eq "true" );
        $active = "armed" if ( $device->{enabled}  );
        
        $readUpdates->{"networkCamera".$device->{id}} = $device->{name}.":".$active;
        $readUpdates->{"networkCamera".$device->{id}."Name"} = $device->{name};
        $readUpdates->{"networkCamera".$device->{id}."Type"} = "owl";
        $readUpdates->{"networkCamera".$device->{id}."Active"} = $active;
        $cameraGets .= $device->{name}.",".$device->{id}.",";
        $cameras .= $device->{id}.":".$device->{name}."\n";
        
        if ( defined( $device->{thumbnail} ) ) {
          # Load Thumbnail only if not already there
          if ( ( ! defined( $hash->{"thumbnail".$device->{id}."Url"} ) ||
               ( $hash->{"thumbnail".$device->{id}."Url"} ne $device->{thumbnail} ) ) ) {
            if ( ! defined( $hash->{"thumbnail".$device->{id}."Req"} ) ) {
  #              Debug "retreive thumbnail from homescreen for ".$device->{id};
              # Do thumbnail request only of not already there (e.g. by polling)
              $hash->{"thumbnail".$device->{id}."Req"} = $device->{thumbnail};
              BlinkCamera_DoCmd( $hash, "thumbnail", $device->{id}, "HIDDEN" );
            } else {
              Log3 $name, 4, "BlinkCamera_ParseHomescreen $name:  thumbnail Req already defined for ".$device->{id};
            }
          } else {
            # already there just update readings
            $readUpdates->{"networkCamera".$device->{id}."Url"} = BlinkCamera_getwebname( $hash ).
                BlinkCamera_ReplacePattern( $BlinkCamera_camerathumbnail, $device->{id}, $name ); 
          }
          $readUpdates->{"networkCamera".$device->{id}."Thumbnail"} = $device->{thumbnail} ; 
        }
        $readUpdates->{"networkCamera".$device->{id}."Firmware"} = $device->{fw_version} if ( defined( $device->{fw_version} ) );
        $readUpdates->{"networkCamera".$device->{id}."Status"} = $device->{status} if ( defined( $device->{status} ) );
        if ( defined( $device->{signals} ) ) {
          my $signal = $device->{signals};
          $readUpdates->{"networkCamera".$device->{id}."Temp"} = $signal->{temp}; 
        }
      }
    }

  }

  $cameraGets .= "all";
  $hash->{getoptions}->{liveview} = $cameraGets;
  $hash->{getoptions}->{getThumbnail} = $cameraGets;
  $hash->{getoptions}->{getInfoCamera} = $cameraGets;
  $hash->{setoptions}->{camEnable} = $cameraGets;
  $hash->{setoptions}->{camDisable} = $cameraGets;
  $readUpdates->{networkCameras} = $cameras;

  return $ret;
}



#####################################
#  INTERNAL: Parse the cameraConfig results
sub BlinkCamera_ParseCameraConfig($$$$)
{
  my ( $hash, $result, $cam, $readUpdates ) = @_;
  my $name = $hash->{NAME};

  my $ret;

  my $camera = $result->{camera};

  Log3 $name, 4, "BlinkCamera_ParseCameraConfig $name: for Camera $cam ";

  $readUpdates->{"cameraConfig".$cam} = Dumper($camera)."\n";

  return $ret;
}


#####################################
#  INTERNAL: Parse the results of alerts to manage videos
sub BlinkCamera_ParseStartAlerts($;$$$)
{
  my ( $hash, $result, $page, $readUpdates ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  my $isLast = 0;

  Log3 $name, 4, "BlinkCamera_ParseStartAlerts $name: for page :".(defined($page)?$page:"--").": ";
  
  if ( ! defined( $page ) ) {
    # prepare for getting alerts
    $page = 0;

    my $lastUpdate = $hash->{updateTimestamp};
    $lastUpdate = "2016-01-01T14:33:02" if( ! defined( $lastUpdate ) );

    # normalize timestamps for queries and update/create timestamps (2016-11-02T21:43:49+00:00)
    $lastUpdate =~ s/\+.+$/Z/;
    
    # store old eventTimestamp and lastUpdate
    $hash->{eventTimestamp} = ReadingsVal($name,"eventTimestamp","");
    $hash->{alertUpdate} = $lastUpdate;
    
    my @a = ();
    $hash->{alertResults} = \@a;
  } else {
    # Store results
    my $v = $result->{media}; 
    push( @{$hash->{alertResults}}, @$v );
    
    $isLast = ( BlinkCamera_IsLastAlertPage( $hash, $result ) ); 
  }

  if ( $isLast ) {
    Log3 $name, 4, "BlinkCamera_ParseStartAlerts $name: Analyze the results now ";
    $ret = BlinkCamera_AnalyzeAlertResults( $hash, $hash->{alertResults}, $readUpdates );

    # remove internal values / specifically results
    delete( $hash->{alertUpdate} );
    delete( $hash->{alertResults} );
    delete( $hash->{eventTimestamp} );
  } else {
    $ret = BlinkCamera_DoCmd( $hash, "alerts", $page+1, "HIDDEN" ) if ( ! $isLast );
  }
  
  return $ret;
}




#####################################
#  INTERNAL: Callback is the callback for any nonblocking call to the bot api (e.g. the long poll on update call)
#   3 params are defined for callbacks
#     param-hash
#     err
#     data (returned from url call)
# empty string used instead of undef for no return/err value
sub BlinkCamera_Callback($$$)
{
  my ( $param, $err, $data ) = @_;
  my $hash= $param->{hash};
  my $name = $hash->{NAME};

  my $ret;
  my $cmdId;
  my $result;
  my $ll = 5;
  my $maxRetries;
  my %readUpdates = ();
  
  my $filename = $param->{filename};
  my $cmd = $param->{cmd};
  my $par1 = $param->{par1};  
  my $par2 = $param->{par2};

  my $polling = ( defined($par2) ) && ($par2 eq "POLLING" );
  my $hidden = ( ( defined($par2) ) && ($par2 eq "HIDDEN" ) ) || $polling;
  
  my $fullurl;
  my $repfilename;

  Log3 $name, 4, "BlinkCamera_Callback $name: called from ".($polling?"Polling":($hidden?"Hidden":"DoCmd"));
  
  Log3 $name, 4, "BlinkCamera_Callback $name: ".
    (defined( $err )?"status err :".$err:"").
    (defined( $filename )?
        ":  data length ".(( defined( $data ) )?length($data):"<undefined>")."   filename :".$filename.":" :
        ":  data ".(( defined( $data ) )?$data:"<undefined>"));

  # Check for timeout   "read from $hash->{addr} timed out"
  if ( $err =~ /^read from.*timed out$/ ) {
    $ret = "NonBlockingGet timed out on read from ".($param->{hideurl}?"<hidden>":$param->{url})." after ".$param->{timeout}."s";
  } elsif ( $err ne "" ) {
    $ret = "NonBlockingGet: returned $err";
  } elsif ( $data ne "" ) {
    # assuming empty data without err means timeout
    my $jo;

    if ( defined( $filename ) ) {
      # write file with media
      
      # check for message json return
      if ( $data =~ /^\s*{\s*\"message\":\"(.*)\"\s*}\s*$/ ) {
        Log3 $name, 4, "BlinkCamera_Callback $name: data on file returned :$data:";
        $ret = "Callback returned error:".$1.":";
      }
      
      if ( ! $ret ) {
        # allow changing proxy dir -> from devname
        my $proxyDir = AttrVal($name,"proxyDir","/tmp/");

        # filename - "BlinkCamera/".$name."/thumbnail/camera/".$par1."_1.jpg"
        $repfilename = $filename;
        $repfilename =~ s/\//_/g;

        Log3 $name, 4, "BlinkCamera_Callback $name: binary write  file :".$repfilename;
        $ret = BlinkCamera_BinaryFileWrite( $hash, $proxyDir.$repfilename, $data );
        
        $fullurl = BlinkCamera_getwebname( $hash ).$filename;
      }
      
    } else {
      Log3 $name, 5, "BlinkCamera_Callback $name: data returned :$data:";
      eval {
         my $json = JSON->new->allow_nonref;
#         $jo = $json->decode(Encode::encode_utf8($data));
         $jo = $json->decode($data);
#         $jo = BlinkCamera_Deepencode( $name, $jo );
      };
      
      if ( $@ ) {
        $ret = "Callback returned no valid JSON: $@ ";
      } elsif ( ! defined( $jo ) ) {
        $ret = "Callback returned no valid JSON !";
      } elsif ( ref( $jo ) ne "HASH" ) {
        $ret = "Callback returned no valid JSON (no hash: ".ref( $jo ).")!";
      } elsif ( $jo->{message} ) {
        $ret = "Callback returned error:".$jo->{message}.":";
        
        $ret = "SUCCESS" if ( $jo->{message} =~ /^Successfully / );
        # reset authtoken if {"message":"Unauthorized Access"} --> will be re checked on next call
        delete( $hash->{AuthToken} ) if ( $jo->{message} eq "Unauthorized Access" );
      } else {
        $result = $jo;
      }
      Log3 $name, 4, "BlinkCamera_Callback $name: after decoding status ret:".(defined($ret)?$ret:" <success> ").":";
    }
  }

  $ll = 2 if ( $hidden );
  $hash->{POLLING} = 0 if ( $polling );
 
  ##################################################
  $hash->{HU_DO_PARAMS}->{data} = "";

  $readUpdates{cmd} = $cmd if ( ! $hidden );
  
  if ( ! defined( $ret ) ) {
    # SUCCESS - parse results
    $ll = $BlinkCamera_specialLog;

    # clean up param hash
    delete( $param->{buf} );

    Log3 $name, 4, "BlinkCamera_Callback $name: analyze result for cmd:$cmd:";
    
    # handle different commands
    if ( $cmd eq "login" ) {
      $ret = BlinkCamera_ParseLogin( $hash, $result, \%readUpdates );
      
    } elsif ( ($cmd eq "networks")  ) {
      $ret = BlinkCamera_ParseNetworks( $hash, $result, \%readUpdates );

    } elsif ( ($cmd eq "arm") || ($cmd eq "disarm" ) || ($cmd eq "camEnable" ) || ($cmd eq "camDisable" ) ) {
      # Debug "result :".Dumper( $result );
      $cmdId = $result->{id} if ( defined( $result->{id} ) );
      Log3 $name, 4, "BlinkCamera_Callback $name: cmd :$cmd: sent resulting in id : ".(defined($cmdId)?$cmdId:"<undef>");

    } elsif ( ($cmd eq "cameraConfig")  ) {
      $ret = BlinkCamera_ParseCameraConfig( $hash, $result, $par1, \%readUpdates );

    } elsif ($cmd eq "homescreen" ) {
      $ret = BlinkCamera_ParseHomescreen( $hash, $result, \%readUpdates );
    
    } elsif ( ($cmd eq "cameraThumbnail")  ) {
      # store cmd id also for thumbnail to wait for result
      $cmdId = $result->{id} if ( defined( $result->{id} ) );
#      if ( ! defined($cmdId) ) {
#        # no commandid means done already --> so get the full update
#        BlinkCamera_DoCmd( $hash, "homescreen", undef, "POLLING" );
#      }

    } elsif ($cmd eq "command" ) {
      if ( defined( $result->{complete} ) ) {
        if ( $result->{complete} ) {
          BlinkCamera_DoCmd( $hash, "homescreen", undef, "POLLING" );
        } else {
          $cmdId = $result->{id} if ( defined( $result->{id} ) );
          $ret = "waiting for command to be finished";
          $maxRetries = 3;
        }
      }

    } elsif ( ($cmd eq "video" ) || ($cmd eq "thumbnail"  ) ) {
      my $readTemplate;
      my $readName;
      if ($cmd eq "video") {
        $readTemplate = AttrVal($name,"videoTemplate",$BlinkCamera_vidTemplate);
        $readName = "video";
        $readUpdates{videoFilename} = $repfilename;
        $readUpdates{videoID} = $par1;

      } else {
        $readTemplate = AttrVal($name,"imgTemplate",$BlinkCamera_imgTemplate);
        $readName = "networkCamera".$param->{par1}."Img";
        
        # Store which thumbnail file is loaded already
        $hash->{"thumbnail".$par1."Url"} = $hash->{"thumbnail".$par1."Req"};
        delete( $hash->{"thumbnail".$par1."Req"} );
        
#        $readUpdates{"networkCamera".$par1."Url"} = BlinkCamera_getwebname( $hash ).
#            BlinkCamera_ReplacePattern( $BlinkCamera_camerathumbnail, $par1, $name ); 
        $readUpdates{"networkCamera".$par1."Url"} = BlinkCamera_getwebname( $hash ).$filename;

        my $proxyDir = AttrVal($name,"proxyDir","/tmp/");
        $readUpdates{"networkCamera".$par1."File"} = $proxyDir.$repfilename;
      }
      $readTemplate =~ s/#URL#/$fullurl/g;
      $readTemplate =~ s/#ID#/$par1/g;
      $readUpdates{$readName} = $readTemplate;

    } elsif ($cmd eq "alerts" ) {
      $ret = BlinkCamera_ParseStartAlerts( $hash, $result, $par1, \%readUpdates );
    
    } elsif ($cmd eq "liveview" ) {
      $readUpdates{liveVideo} = $result->{server};

    } else {
      
    }
    
  }
  
  $ret = "SUCCESS" if ( ! defined( $ret ) );
  Log3 $name, $ll, "BlinkCamera_Callback $name: for cmd :$cmd:  retry :".(defined($param->{args}[3])?$param->{args}[3]:"----")."  resulted in :$ret:  cmdId :".(defined($cmdId)?$cmdId:"--")." from ".($polling?"Polling":($hidden?"Hidden":"DoCmd"));

  if ( ! $polling ) {

    # cmd result intern also set if retried / cmdjson only if verbose > 3
    $hash->{cmdResult} = $ret;
    if ( AttrVal($name,"verbose",AttrVal("global","verbose",3)) > 3 ) {
      if ( defined( $filename ) ) {
        $hash->{cmdJson} = (defined($data)?"length :".length($data):"<undef>");
      } else {
#        Debug "Result :".$data.":";
        
        $hash->{cmdJson} = (defined($data)?$data:"<undef>");
      }
    }

    # handle retry
    # ret defined / args defined in params 
    if ( ( $ret ne  "SUCCESS" ) && ( defined( $param->{args} ) ) ) {
      my $wait = $param->{args}[3];
      
      $maxRetries =  AttrVal($name,'maxRetries',0) if ( ! defined( $maxRetries ) );
      if ( ( defined($wait) ) && ( $wait <= $maxRetries ) ) {
        # calculate wait time 10s / 100s / 1000s ~ 17min / 10000s ~ 3h / 100000s ~ 30h
        $wait = 3**$wait;
        
        Log3 $name, 4, "BlinkCamera_Callback $name: do retry ".$param->{args}[3]." timer: $wait (ret: $ret) for cmd ".
              $param->{args}[0];

        # set timer
        InternalTimer(gettimeofday()+$wait, "BlinkCamera_RetryDo", $param,0); 
        
        # finish
        return;
      }

    Log3 $name, 3, "BlinkCamera_Callback $name: Reached max retries (ret: $ret) for cmd ".$cmd;
      
    }
    
  } else {
    $hash->{pollResult} = $cmd." : ".$ret;
  }

  $hash->{doStatus} = "";

  #########################
  # Also set and result in Readings
  readingsBeginUpdate($hash);
  if ( ! $polling ) {
    readingsBulkUpdate($hash, "cmdResult", $ret );   
  }
  if ( ( $ret eq  "SUCCESS" ) )  {
    foreach my $readName ( keys %readUpdates ) {
      if ( defined( $readUpdates{$readName} ) ) {
        readingsBulkUpdate($hash, $readName, $readUpdates{$readName} );        
      } else {
        CommandDeleteReading(undef,$readName)
      }
    }
  }
  readingsEndUpdate($hash, 1);

  #########################
  # Wait for command completion if cmd Id found
  if ( ( $ret eq  "SUCCESS" ) )  {
    # cmd sent / waiting for completion (so add command check) / completion reached add homescreen
    if (  ( defined( $cmdId ) ) )  {
      Log3 $name, 4, "BlinkCamera_Callback $name: start polling for cmd result";
      BlinkCamera_DoCmd( $hash, "command", $cmdId, "HIDDEN" );
      return ;
    }
  
  }

  #########################
  # start next command in queue if available
  if ( ( defined( $hash->{cmdQueue} ) ) && ( scalar( @{ $hash->{cmdQueue} } ) ) ) {
    my $ref = shift @{ $hash->{cmdQueue} };
    Log3 $name, 4, "BlinkCamera_Callback $name: handle queued cmd with :@$ref[0]: ";
    BlinkCamera_DoCmd( $hash, @$ref[0], @$ref[1], @$ref[2], @$ref[3] );
  }
  
}


##############################################################################
##############################################################################
##
## Web proxy handling
##
##############################################################################
##############################################################################

########################################################################################
#
# CGI handling for medai and thumbnails of camera
# camera thumbnail URL   
#     /BlinkCamera/<device>/camera/thumbnail_<id>_<something 1 or 2>.<ext> 
#     --> /tmp/BlinkCamera_<device>_thumbnail_<id>_<something 1 or 2>.<ext=jpg>
#
sub BlinkCamera_WebCallback($) {
	my ($URL) = @_;
	
	Log3 undef, 4, "BlinkCamera_WebCallback: ".$URL;
	
	# Remove prefix
  
  $URL =~ s/^\/BlinkCamera//i;

  # handle camera thumbnail
	if ( ($URL =~ m/^\/([^\/]+)\/(thumbnail|video)\//i) ) {
    # filename - "BlinkCamera/".$name."/thumbnail/camera/".$par1."_1.jpg" or "BlinkCamera/<name>/video/<id>.mp4"

    my $devname = $1;
    my $urlfile = "BlinkCamera".uri_unescape($URL);
  
    Log3 undef, 4, "BlinkCamera_WebCallback:   devname :$devname:   urlfile :$urlfile:  ";

    # allow changing proxy dir -> from devname
    my $proxyDir = AttrVal($devname,"proxyDir","/tmp/");

    # normalize URL separator / into _
    $urlfile =~ s/\//_/g;
    
    
    # let fhemweb handle the rest
    my $fullfile = $proxyDir.$urlfile;
    if ( -e $fullfile ) {
				Log3 undef, 5, "Found file in proxydir ".$urlfile.' from ('.$URL.')';
				
        $urlfile =~ m/^(.*)\.(.*)$/;

				FW_serveSpecial($1, $2, $proxyDir, 0);
				
				return(undef, undef);
    } else {
      Log3 undef, 2, "File not found in proxydir ".$urlfile.' from ('.$URL.')';
    }
    
  }
  
  # Wenn wir hier ankommen, dann konnte nichts verarbeitet werden...
	return ("text/html; charset=UTF8", "BlinkCamera_WebCallback could not handle: ".$URL);
}
 
########################################################################################
#
# Defines an extension (CGI call) to get pictures / media
sub BlinkCamera_DefineWebExt() {
	# CGI definition
	my $name = "BlinkCamera";
	my $baseurl = "/".$name ;
	$data{FWEXT}{$baseurl}{FUNC} = "BlinkCamera_WebCallback";
	$data{FWEXT}{$baseurl}{LINK} = $name;
	$data{FWEXT}{$baseurl}{NAME} = undef; 
}



##############################################################################
##############################################################################
##
## Polling / Setup
##
##############################################################################
##############################################################################


#####################################
#  INTERNAL: PollInfo is called to queue the next getInfo and/or set the next timer
sub BlinkCamera_PollInfo($) 
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
    
  Log3 $name, 5, "BlinkCamera_PollInfo $name: called ";

  # Get timeout from attribute 
  my $timeout =   AttrVal($name,'pollingTimeout',0);
  if ( $timeout == 0 ) {
    $hash->{STATE} = "Static";
    Log3 $name, 4, "BlinkCamera_PollInfo $name: Polling timeout 0 - no polling ";
    return;
  }

  $hash->{STATE} = "Polling";

  if ( $hash->{POLLING} ) {
    Log3 $name, 4, "BlinkCamera_PollInfo $name: polling still running ";
  } else {
    $hash->{POLLING} = 1;
    my $ret = BlinkCamera_DoCmd( $hash, "homescreen", undef, "POLLING" );
    Log3 $name, 1, "BlinkCamera_PollInfo $name: Poll call resulted in ".$ret." " if ( defined($ret) );
  }

  Log3 $name, 4, "BlinkCamera_PollInfo $name: initiate next polling homescreen ".$timeout."s";
  InternalTimer(gettimeofday()+$timeout, "BlinkCamera_PollInfo", $hash,0); 

}
  
######################################
#  make sure a reinitialization is triggered on next update
#  
sub BlinkCamera_ResetPollInfo($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "BlinkCamera_ResetPollInfo $name: called ";

  RemoveInternalTimer($hash);

  HttpUtils_Close($hash->{HU_DO_PARAMS}); 
  
  $hash->{FAILS} = 0;

  # let all existing methods first run into block
  $hash->{POLLING} = 0;
  
  # wait some time before next polling is starting
  
    if( $init_done ) {
      InternalTimer(gettimeofday()+5, "BlinkCamera_PollInfo", $hash, 0); 
    } else {
      InternalTimer(gettimeofday()+60, "BlinkCamera_PollInfo", $hash, 0); 
    }

  Log3 $name, 4, "BlinkCamera_ResetPollInfo $name: finished ";

}




######################################
#  make sure a reinitialization is triggered on next update
#  
sub BlinkCamera_Setup($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "BlinkCamera_Setup $name: called ";

  $hash->{STATE} = "Undefined";

  # remove all readings ebside eventTimestamp to avoid addtl notifications
  my $eventTime =  ReadingsVal($name,"eventTimestamp",undef);
  CommandDeleteReading(undef, "$name .*");
  readingsSingleUpdate($hash, "eventTimestamp", $eventTime, 0 ) if ( defined( $eventTime ) );

  foreach my $aKey ( keys  %{$hash} ) {
    # "thumbnail".$device->{device_id}."Req"
    delete( $hash->{$aKey} ) if ( $aKey =~ /^thumbnail/ );
  }
  
  my %sets = (
    "login" => undef,

    "arm" => undef,
    "disarm" => undef,
    
    "camEnable" => undef,
    "camDisable" => undef,
    
    "reset" => undef,
    
    "videoDelete" => undef,
    
    "zDebug" => undef

  );

  my %gets = (
    "getNetworks" => undef,

    "getInfo" => undef,
    "getInfoCamera" => undef,

    "getThumbnail" => undef,
    
    "getVideoAlert" => undef,

    "cameraList" => undef,

    "liveview" => undef,

  );

  $hash->{getoptions} = \%gets;
  $hash->{setoptions} = \%sets;

  my %hu_do_params = (
                  url        => "",
                  timeout    => 30,
                  method     => "GET",
                  header     => $BlinkCamera_header,
                  hideurl    => 1,
                  callback   => \&BlinkCamera_Callback
  );

  $hash->{HU_DO_PARAMS} = \%hu_do_params;

  $hash->{POLLING} = -1;
  
  # Temp?? SNAME is required for allowed (normally set in TCPServerUtils)
  $hash->{SNAME} = $name;

  # Ensure queueing is not happening
  delete( $hash->{cmdQueue} );

  delete( $hash->{doStatus} );

  delete( $hash->{cmd} );
  delete( $hash->{cmdResult} );
  delete( $hash->{cmdJson} );

  delete( $hash->{pollResult} );

  delete( $hash->{AuthToken} );

  delete( $hash->{videos} );
  delete( $hash->{updateTimestamp} );

  delete( $hash->{video} );
  delete( $hash->{videoFilename} );
  delete( $hash->{videoID} );

  delete( $hash->{alertSkipped} );
  delete( $hash->{alertUpdate} );
  delete( $hash->{alertResults} );
  
  delete( $hash->{URL} );
  
  # remove timer for retry
  RemoveInternalTimer($hash->{HU_DO_PARAMS});
  
  # cleanup proxy dir only blink files for current name
  my $proxyDir = AttrVal($name,"proxyDir","/tmp/");
  if(opendir(DH, $proxyDir)) {
    my $pattern = "^BlinkCamera_".$name."_";
    while(my $f = readdir(DH)) {
      Log3 $name, 4, "BlinkCamera_Setup $name: found file :$f: ";
      next if($f !~ /$pattern/ );
      eval { unlink $proxyDir."/".$f; };
      Log3 $name, 1, "BlinkCamera_Setup $name: file $f could not be deleted :$@: " if $@; 
    }
    closedir(DH); 
  }

  $hash->{URL} = "";

  $hash->{STATE} = "Defined";

  BlinkCamera_ResetPollInfo($hash);
  
  BlinkCamera_DefineWebExt();

  Log3 $name, 4, "BlinkCamera_Setup $name: ended ";

}




##############################################################################
##############################################################################
##
## HELPER
##
##############################################################################
##############################################################################


#####################################
#  INTERNAL: get pattern replaced
sub BlinkCamera_getwebname( $ ) {
  my ( $hash ) = @_;

  my $wn = AttrVal($hash->{NAME},'webname',"fhem");

  # might add parsing for removing trailing / leadings slashes
  
  $wn =~ s/^\/+//;
  $wn =~ s/\/+$//;
  
  return "/".$wn."/";
}

#####################################
#  INTERNAL: get pattern replaced
sub BlinkCamera_ReplacePattern( $$;$ ) {
  my ( $pattern, $id, $name ) = @_;

 $pattern =~ s/q_id_q/$id/g if ( defined($id) );
 $pattern =~ s/q_name_q/$name/g if ( defined($name) );

 return $pattern;
}

#####################################
#  INTERNAL: Get Id for a camera or list of all cameras if no name or id was given or undef if not found
sub BlinkCamera_CheckSetGet( $$$ ) {
  my ( $hash, $cmd, $options ) = @_;

  if (!exists($options->{$cmd}))  {
    my @cList;
    foreach my $k (keys %$options) {
      my $opts = undef;
      $opts = $options->{$k};

      if (defined($opts)) {
        push(@cList,$k . ':' . $opts);
      } else {
        push (@cList,$k);
      }
    } # end foreach

    return "BlinkCamera_CheckSetGet: Unknown argument $cmd, choose one of " . join(" ", @cList);
  } # error unknown cmd handling
  return undef;
}

#####################################
#  INTERNAL: Get Id for a camera or list of all cameras if no name or id was given or undef if not found
sub BlinkCamera_CameraDoCmd( $$$ ) {
  my ( $hash, $cmd, $arg ) = @_;

  my $ret;
  
  if ( $arg eq "all" ) {
    my $cList = BlinkCamera_GetCameraId( $hash );
    if ( ! defined( $cList ) ) {
      $ret = "No cameras found - try GetInfo first";
    } else {
      foreach my $cam ( @$cList ) {
        my $sret = BlinkCamera_DoCmd( $hash, $cmd, $cam );
        if ( defined( $sret ) ) {
          $sret = "CameraConfig for $cam returned ".$sret;
          $ret = (defined($ret)?$ret:"").$sret;
        }
      }
    }
  } else {
    my $cam = BlinkCamera_GetCameraId( $hash, $arg );
    if ( ! defined( $cam ) ) {
      $ret = "Camera :$arg: not found - try GetInfo first";
    } else {
      $ret = BlinkCamera_DoCmd( $hash, $cmd, $cam );
    }
  }

  return $ret;
}


#####################################
#  INTERNAL: Get Id for a camera or list of all cameras if no name or id was given or undef if not found
sub BlinkCamera_GetCameraId( $;$ ) {
  my ( $hash, $name ) = @_;
  
  my $cameras = ReadingsVal($hash->{NAME},'networkCameras',"");
  
  my $ret;
  
  my @cameradefs = split( "\n", $cameras);
  if ( defined( $name ) ) {
    foreach my $cameradef ( @cameradefs ) {
    $cameradef =~ /^([^:]+):(.*)$/;
      $ret = $1 if ( ( $2 eq $name ) || ( $1 eq $name ) );
    }
  } else {
    my @retList;
    foreach my $cameradef ( @cameradefs ) {
      $cameradef =~ /^([^:]+):(.*)$/;
      push( @retList, $1 ) if ( defined( $1 ) );
    }
    $ret = \@retList;
  }
  
  return $ret;
}
  
#####################################
#  INTERNAL: Get name for a camera or undef if not found
sub BlinkCamera_GetCameraName( $$ ) {
  my ( $hash, $id ) = @_;
  
  my $cameras = ReadingsVal($hash->{NAME},'networkCameras',"");
  
  my $ret;
  
  my @cameradefs = split( "\n", $cameras);
  foreach my $cameradef ( @cameradefs ) {
    $cameradef =~ /^([^:]+):(.*)$/;
    $ret = $2 if ( ( $2 eq $id ) || ( $1 eq $id ) );
  }
 
  return $ret;
}
  
#####################################
#  INTERNAL: Either read attribute, if not set use Reading networks first line
sub BlinkCamera_GetNetwork( $ ) {
  my ( $hash ) = @_;
  
  my $net = AttrVal($hash->{NAME},'network',undef);
  
  if ( ! defined( $net ) ) {
    # grab reading
    my $nets = ReadingsVal($hash->{NAME},'networks',"INVALID");
    
    if ( ( defined( $nets ) ) && ( $nets ne "INVALID" ) && ( $nets =~ /^([^:]+):/ ) ) {
      $net = $1;
    }
  }
  
  return $net;
}

#####################################
#  INTERNAL: Either read attribute, if not set use Reading networks first line
sub BlinkCamera_GetCamType( $$ ) {
  my ( $hash, $camid ) = @_;
  
  return ReadingsVal($hash->{NAME},"networkCamera".$camid."Type","INVALID");
}



  
######################################
#  write binary file for (hest hash, filename and the data
#  
sub BlinkCamera_BinaryFileWrite($$$) {
  my ($hash, $fileName, $data) = @_;

  return "BlinkCamera_BinaryFileWrite - could not write ".$fileName.": ".$! if ( ! open BINFILE, '>'.$fileName );

  binmode BINFILE;
  print BINFILE $data;
  close BINFILE;

  return undef;
}

##############################################################################
##############################################################################
##
## Alert / event handling
#        "/api/v2/videos/changed?page=2&since=2016-01-24T14:33:02Z";
#     store list of videos in hash/intern - id -> deleted -> created_at, updated_at, camera_id, viewed, video
##
##############################################################################
##############################################################################

#####################################
#  INTERNAL: Get a single json video entry -> returns $id, $deleted, $updated, $entryString
sub BlinkCamera_GetAlertEntry( $$ ) {
  my ( $hash, $jentry ) = @_;
  
  my $id;
  my $deleted;
  my $updated = "";
  my $entrystring = "";
  
#     store list of videos in hash/intern - id -> deleted -> created_at, updated_at, camera_id, viewed, video
  
  if ( defined($jentry->{id}) ) {
    $id = $jentry->{id};

    $entrystring .= $jentry->{created_at} if ( defined( $jentry->{created_at} ) );
    $entrystring .= "|";
    
    
    $updated = $jentry->{updated_at} if ( defined( $jentry->{updated_at} ) );
    $entrystring .= $updated;
    $entrystring .= "|";
    
    $entrystring .= $jentry->{device_id} if ( defined( $jentry->{device_id} ) );
    $entrystring .= "|";
    
    $entrystring .= (( $jentry->{watched} eq "true" )?"1":"") if ( defined( $jentry->{watched} ) );
    $entrystring .= "|";
    
    $entrystring .= $jentry->{media} if ( defined( $jentry->{media} ) );

    $deleted = 0;
    $deleted = (( $jentry->{deleted} eq "true" )?1:0) if ( defined( $jentry->{deleted} ) );
  }
  
  return ($id, $deleted, $updated, $entrystring);
}



#####################################
#  INTERNAL: get url for a video from internal alert list for given id
sub BlinkCamera_GetAlertVideoURL( $$ ) {
  my ( $hash, $vid) = @_;
  my $name = $hash->{NAME};

  my $vidUrl;
  
  if ( defined( $hash->{videos} ) ) {
    my $entry = $hash->{videos}->{$vid};
    
    if ( ( defined( $entry ) ) && (  $entry =~ /$BlinkCamera_alertEntry/ ) ) {
      $vidUrl = $5;
    }
  }

  return $vidUrl;
}


#####################################
#  INTERNAL: analyze an alert page to check if a followup page might be needed
sub BlinkCamera_IsLastAlertPage( $$ ) {
  my ( $hash, $jpage ) = @_;
  my $name = $hash->{NAME};

  my ( $limit, $entries );
  
  return 1 if ( ( ! defined( $jpage->{limit} ) ) || ( ! defined( $jpage->{media} ) ) );
  
  $limit = $jpage->{limit}; 
  
  $entries = 0;
  my $v = $jpage->{media};
  $entries = scalar( @$v ) if ( ( defined( $jpage->{media} ) ) && ( ref( $v ) eq "ARRAY" ) );

  Log3 $name, 4, "BlinkCamera_IsLastAlertPage $name: limit :$limit: / entries :$entries: ";
  
  return ( $limit > $entries );
}


#####################################
#  INTERNAL: analyze an alert page
sub BlinkCamera_HandleAlertEntry( $$$$ ) {

  my ( $hash, $id, $deleted, $entry ) = @_;
  my $name = $hash->{NAME};

  $hash->{videos} = () if ( ! defined( $hash->{videos} ) );
  
  my $videos = $hash->{videos};
  
  if ( $deleted ) {
    delete( $videos->{$id} );
  } elsif ( defined( $videos->{$id} ) ) {
    # existing means just update the entry  
    $videos->{$id} = $entry;
  } else {  
    # non existing means new entry events also needed
    $videos->{$id} = $entry;

#     store list of videos in hash/intern - id -> deleted -> created_at, updated_at, camera_id, viewed, video
#       alertTime - 
#       alertCamera - 
#       alertVideo - 
#       alertID -
    
    if ( $entry =~ /$BlinkCamera_alertEntry/ ) {
      my $alertTime = $1;
      my $alertCamera = $3;
      my $alertViewed = $4;
      my $alertVideo = $5;

      my $lastUpdate = $hash->{eventTimestamp};

      Log3 $name, 5, "BlinkCamera_HandleAlertEntry $name: id  :$id: alert time  :$alertTime: ";
      Log3 $name, 5, "BlinkCamera_HandleAlertEntry lastUpdate was  :$lastUpdate:  and viewed :$alertViewed:";
      
      if ( ( $alertTime gt $lastUpdate ) && ( length($alertViewed) == 0 ) ) {
        Log3 $name, 5, "BlinkCamera_HandleAlertEntry $name: id  :$id: is new alert ";
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "alertVideo", $alertVideo );        
        readingsBulkUpdate($hash, "alertCamera", $alertCamera );        
        
        my $cname = BlinkCamera_GetCameraName( $hash, $alertCamera );
        readingsBulkUpdate($hash, "alertCameraName", $cname ) if ( defined( $cname ) );        

        readingsBulkUpdate($hash, "alertTime", $alertTime );        
        readingsBulkUpdate($hash, "alertID", $id );        

        readingsEndUpdate($hash, 1);
      }

      # eval eventTimestamp to check for latest and update event timestamp
      my $newestTS =  ReadingsVal($name,"eventTimestamp","");
      readingsSingleUpdate($hash, "eventTimestamp", $alertTime, 1 ) if ( $alertTime gt $newestTS );


    } else {
      Log3 $name, 1, "BlinkCamera_HandleAlertEntry $name: parsing of alertEntry failed :$entry: ";
    }
    
  }
  
}


#####################################
#  INTERNAL: analyze an alert page
sub BlinkCamera_AnalyzeAlertResults( $$$ ) {
  my ( $hash, $jvarray, $readUpdates ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  Log3 $name, 5, "BlinkCamera_AnalyzeAlertResults $name: parsing of alertEntry entries:".scalar(@$jvarray).":   ref:".ref($jvarray).": ";

  return "BlinkCamera_AnalyzeAlertPage: No videos found" if ( ( ! defined( $jvarray ) ) || ( ref( $jvarray ) ne "ARRAY" ) );

  # ensure the internal video hash is existing
  if ( ! defined( $hash->{videos} ) ) {
    my %h = ();
    
    $hash->{videos} = \%h;
  }   
  
  my $lastUpdate = $hash->{updateTimestamp};
  $lastUpdate = "" if ( ! defined( $lastUpdate ) );

  foreach my $video ( reverse( @$jvarray ) ) {
    my ( $id, $deleted, $updated, $entry ) = BlinkCamera_GetAlertEntry( $hash, $video );
    
    # set reading if time is later meaning > 
    Log3 $name, 5, "BlinkCamera_AnalyzeAlertResults $name: id  :$id: update :$updated:  last :$lastUpdate:  compare ".(( $updated gt $lastUpdate )?"newer":"-");
    if ( $updated gt $lastUpdate ) {
      $hash->{updateTimestamp} = $updated;
      $lastUpdate = $updated;
    }

    # handle newly received entry
    BlinkCamera_HandleAlertEntry( $hash, $id, $deleted, $entry ) if ( defined( $id ) ); 
  }
  
  return $ret;

}





  

##############################################################################
##############################################################################
##
## Documentation
##
##############################################################################
##############################################################################

1;

=pod
=item summary    interact with Blink Home (Security) cameras
=item summary_DE steuere  Blink Heim- / Sicherheits-kameras
=begin html

<a name="BlinkCamera"></a>
<h3>BlinkCamera</h3>
<ul>

  This module connects remotely to a system of Blink Home Cameras 
  
  <a href="https://blinkforhome.com">Blink Home Cameras</a> are relatively inexpensive wire-free video home security & monitoring system

  The blink device contains the possibility to regular poll for updates (i.e. specifically for notificatio0ns/alerts) 
  MOst commands that change configurations are not synchronous, but the result will be returned after polling for status information. This is automatically handled in the device and the result of the cmd is marked in the reading <code>cmdResult</code> with the value "SUCCESS".
  <br>
  The blink device also contains a proxy for retrieving videos and thumbnails throug an FHEMweb extension in the form of http://&lt;fhem&gt;:&lt;fhemwebport&gt;/fhem/BlinkCamera/&lt;name of the blink device&gt;/...
  
  <br><br>
  <a name="BlinkCameradefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; BlinkCamera &lt;email&gt; [ &lt;password&gt; ] </code>
    <br><br>
    Defines a BlinkCamera device, which connects to the cloud servers with the given user name and password (as provided during registration / setup)
    <br><br>
    The password will be removed from the define and stored separately (so needs to be given on the initial define)
    <br><br>
    Example: <code>define blink BlinkCamera ichbins@nicht.de abc123</code><br>
    <br>
  </ul>
  <br><br>   
  
  <a name="BlinkCameraset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br><br>
    where &lt;what&gt; / &lt;value&gt; is one of

  <br><br>
    <li><code>login</code><br>Initiate a login to the blink servers. This is usually done automatically when needed or when the login is expired
    </li>
    <li><code>arm</code> or <code>disarm</code><br>All enabled cameras in the system will be armed (i.e. they will be set to a mode where alarms/videos are automatically created based on the current settings) / disarmed (set to inactive mode where no video is recorded.
    </li>
    <li><code>camEnable &lt;camera name or number or "all"&gt;</code> or <code>camDisable &lt;camera name or number&gt;</code><br>The specified camera will be enabled (i.e. so that it is included in the arm / disarm commands) / disabled (excluded from arm/disarm).
    </li>
    
    <li><code>reset</code><br>Reset the FHEM device (only used in case of something gets into an unknown or strange state)
    </li>
    
    <li><code>videoDelete &lt;video id&gt;</code><br>The video with the given id will be removed (both from the local filesystem and from the blink servers)
    </li>
    
  </ul>

  <br><br>

  <a name="BlinkCameraget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br><br>
    where &lt;what&gt; / &lt;value&gt; is one of

  <br><br>
    <li><code>getNetworks</code><br>Retrieve the networks defined in the blink account. This is needed for further operations and information request to blink. For specifying a specific network (id), the attribute network can be also set</li>
    <li><code>getInfo</code><br>Get information about the system from the blink servers (including cameras and state) . This is usually done automatically based on the reular interval specified in attribute <code>pollingTimeout</code>
    </li>
    <li><code>getInfoCamera &lt;camera name or number or "all"&gt;</code><br>Get the information about the specified camera from the blink system. Currently the information about the camera is just stored in raw json format in a single reading <code>cameraConfig&lt;camera id&gt;</code>
    </li>
    <li><code>getThumbnail &lt;camera name or number or "all"&gt;</code><br>Request a new thumbnail being taken from the specified camera in the blink system. The thumbnail is not automatically retrieved, this can be done using <code>getInfoCamera</code>
    </li>
    
    
    <li><code>getVideoAlert [ &lt;video id&gt; ]</code><br>Retrieve the video for the corresponding id (or if ommitted as specified in the reading <code>alertID</code>) and store the video in a local file in the directory given in the attribute <code>proxyDir</code>
    </li>
    
    <li><code>liveview &lt;camera name or number or "all"&gt;</code><br>Request a link to the live video stream. The live video stream access (URL) will be stored in the reading liveVideo. The link to the video is an rtsp - which can be shown in video players like VLC.
    <br>
    Note: Live video streaming might have a substantially negative effect on battery life<br>
    </li>
    
    
  </ul>

  <br><br>

  <a name="BlinkCameraattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>network &lt;network id&gt;</code><br>This attribute is needed if your blink system contains more than one network. If not specified the first netowrk defined in the account is used
    </li> 

    <li><code>proxyDir &lt;directory path&gt;</code><br>Specify the path where temporary files (videos, thumbnails) are stored to be access via the proxy server built into the device as an fhemweb extension
    </li> 

    <li><code>pollingTimeout &lt;interval&gt;</code><br>Interval in which the system is checking for status updates from the blink servers (given in seconds - value 0 means no polling). This is the frequency in which new alerts can be received
    </li> 

    <li><code>imgTemplate &lt;HTML template for reading&gt;</code><br>Give an HTML template for the image reading that shows the thumbnail of a camera. Default is a template which shows the image a link to the image and also the url as text. In the template the string #URL# will be replaced with the actual URL
    </li> 


    <li><code>homeScreenV3 &lt;1 or 0&gt;</code><br>If set to 1 the new version 3 of the blink API will be used. Unfortunately this includes different readings and settings <br>
    NOTE: This is necessary to show at least the status of Blink Mini cameras - changes are not yet possible 
    </li> 


    <li><code>imgOriginalFile &lt;1 or 0&gt;</code><br>If set to 1 it will keep the original filename of the thumbnail when storing ti. With setting this new thumbnails will not overwrite existing ones. <br>
    NOTE: No cleanup of thumbnails is done, so over time more and more thumbnails will be stored in the proxydir. 
    </li> 

    <li><code>vidTemplate &lt;HTML template for reading&gt;</code><br>Give an HTML template for the video reading that shows the video of a notification from the camera. Default is a template which shows the video a link to the video and also the url and id as text. In the template the string #URL# will be replaced with the actual URL of the video and #ID# will be replaced by the video ID.
    </li> 

    <li><code>webname &lt;path to fhem web&gt;</code><br>can be set if fhem is not accessible through the standard url of FHEMWeb <code>/fhem/... </code> (Default value is fhem). 
    </li> 

  </ul>

  <br><br>


    <a name="BlinkCamerareadings"></a>
  <b>Readings</b>
  
  <ul>
    <li><code>cmd &lt;internal name of the last executed command&gt;</code><br>Used to identify the cmd that was last executed and where the result is given in cmdResult </li> 
    <li><code>cmdResult &lt;error message or SUCCESS&gt;</code><br>Used to identify success or failure of a command </li> 
    
    <br>
    
    <li><code>networks &lt;list of networks&gt;</code><br>Lists the defined networks for the account at blink in the form networkid:networkname </li> 
    <li><code>networkName &lt;name&gt;</code><br>Name of the network that is currently used to fill the readings </li> 
    <li><code>networkArmed &lt;status&gt;</code><br>Network arm status (true or false)</li> 
    <li><code>networkStatus &lt;ok or failure&gt;</code><br>Basic status of the current network</li> 
    <li><code>networkCameras &lt;number&gt;</code><br>Lists the defined cameras in the current network in the form cameraid:cameraname </li> 
    <li><code>networkSyncModule &lt;id and status&gt;</code><br>Information about the syncmodule in the current network in the form syncid:syncmodulestatus </li> 
    
    <br>
    
    <li><code>networkCamera... </code><br>Set of readings specific for each camera (identified by the cameraID in the reading name). Providing status and name of the camera / most recent thumbnail / url for the thumbnail to the proxy </li> 
    
    
  </ul> 

  <br><br>   
</ul>



=end html
=cut
