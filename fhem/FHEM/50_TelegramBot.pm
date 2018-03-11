##############################################################################
#
#     50_TelegramBot.pm
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
#  TelegramBot (c) Johannes Viegener / https://github.com/viegener/Telegram-fhem
#
# This module handles receiving and sending messages to the messaging service telegram (see https://telegram.org/)
# TelegramBot is making use of the Telegrom Bot API (see https://core.telegram.org/bots and https://core.telegram.org/bots/api)
# For using it with fhem an telegram BOT API key is needed! --> see https://core.telegram.org/bots/api#authorizing-your-bot
#
# Discussed in FHEM Forum: https://forum.fhem.de/index.php/topic,38328.0.html
#
# $Id$
#
##############################################################################
# 0.0 2015-09-16 Started
# 1.0 2015-10-17 Initial SVN-Version 
# 2.0 2016-10-19 multibot support / markup on send text / msgEdit 

#   disable_web_page_preview - attribut webPagePreview - msg506924
#   log other messages in getupdate
#   add new get command "update" for single update poll
#   new cmd for forcing a msg reply - msgForceReply
#   add readings for reply msg id: msgReplyMsgId
#   documemt: msgForceReply, msgReplyMsgId 
#   diable attribute to stop polling
#   keyboards through [] in message command(s) -> no changed to () to avoid issues
#   send incomplete keyboards as message instead of error
#   Add | as separator for keys
#   documentation alignment - more consistent usage of peer (instead of user)
#   Keyboards in () istead of []
#   added callback being retrieved in updates
#   allow inline keyboards sent - new command inline keys titel:data
#   allow answer to callback (id must be given / text is optional)
#   document inline / answer
#   cleaned up recommendations for cmdKeyword etc
#   corrections to doc and code - msg540802
#   command names for answer / inline -changed to-> queryInline, queryAnswer - msg540802
#   attribute for automatic answer - eval set logic - queryAnswerText
#   FIX: trim $ret avoiding empty msg error from telegram in command response
#   FIX: trim $ret avoiding empty msg error from telegram also with control characters in 2 chars
#   rename callback... readings to query... for consistency
#   value 0 for queryAnswerText means no text sent but still answer
#   FIX: corrected documentation - unbalanced li
#   Run set magic on all comands before execution
#   add new reading sentMsgPeerId
#   add edit message for inline keyboards?
#   document queryEditInline
#   "0" message still sent on queryanswer
# 2.1 2016-12-25  msgForceReply, disable, keyboards in messages, inline keyboards and dialogs

#   allow response for commands being sent in chats - new attribute cmdRespondChat to configure
#   new reading msgChatId
#   exclamation mark in favorites to allow empty results also being sent
#   new get peerID for onverting a named peer into an id (same syntax as in msg)
#   document get commands
#   communication with TBot_List Module -> queryAnswer
#   document cmdRespondChat / msgChatId
#   "Bad Request:" or "Unauthorized" do not result in retry
#   cleaned up done list
#   ATTENTION: store api key in setkey value see patch from msg576714
#   put values in chat/chatId even if no group involved (peer will be set)
# 2.2 2017-02-26  msgChatId with peer / api key secured / communication with TBot_List

#   cmdSend to send the result of a command as message (used for sending SVGs)
#   add utf8Special attribute for encoding before send
#   reset msgReplyMsgId on reception to empty if no replyid
#   clarified scope of cmdRestrictedPeer in doc
#   changed utf8Special to downgrade
#   FIX: defpeer undefined in #msg605605
#   FIXDOC: url escaping for filenames
#   avoid empty favorites
#   allow multiple commands in favorites with double ;;
#   DOC: multiple commands in favorites
#  allow flagging favorites not shown in favlist (only with alias prefixing alias with a hyphen --> /-alias ) 
#   FIX: Allow utf8 again
#   alias execution is not honoring needsconfirm and sent result --> needs to be backward compatible
#   cleanup for favorite execution and parsing
#   reduce utf8 handling
#   add favorite hidden zusatz
#   favorite keyboard 2 column #msg609128
# 2.3 2017-03-27  utf8Special for unicode issues / favorite handling / hidden favorites

#   doc: favorites2Col for 2 columns favorites keyboard
#   fix: aliasExec can be undefined - avoid error
#   allow : in keyboards (either escaped or just use last : for data split) --> #msg611609
#   allow space before = in favorite
#   favoritesInline attribute for having favorites handled with inline keyboards
#   INT: addtl Parameter in SendIt for options (-msgid-)
#   Handle favorites as inline
#   document favoritesInline
#   remove old inline favorites dialog on execution of commands
#   allow execution of hidden favorites from inline menu
#   Debug/log cleanup
# 2.4 2017-05-25  favorites rework - inline / allow : in inline 

#   fix: options remove in sendit corrected: #msg641797
#   DOCFIX: Double semicolon for multiple commands in favorites
#   FIX: non-local $_ - see #msg647071
# 2.4.1 2017-06-16  minor fixes - #msg641797 / #msg647071

#   FIX: make fileread work for both old and new perl versions
# 2.4.2 2017-07-01  rewrite read file function due to $_ warning - #msg651947

#   FIX: make delayed retry work again
#   rename of bot also works with token encryption - #msg668108
# 2.4.3 2017-08-13  delayed retry & rename (#msg668108) 

#   remove debug / addtl testing
#   adapt prototypes for token
#   additional logs / removed debugs
#   special httputils debug lines added
#   add msgDelete function to delete messages sent before from the bot
#   added check for msgId not given as first parameter (e.g. msgDelete / msgEdit)
# 2.5 2017-09-10  new set cmd msgDelete

#   add - in description will not show favorite command in menu #msg686352
#   Issue: when direct favorite confirm is cancelled - do not jump to favorite menu
#   json_decode mit nonref   #msg687580
# 2.6 2017-09-24  hide command in favorites/change direct favorites confirm

#   Fix minusdesc undefined issue
#   Cleanup old code
#   add favoritesMenu to send favorites 
#   doc favoritesMenu
#   correct favoritesMenu to allow parameter
#   FIX: allow_nonref / eval also for makekeyboard #msg732757
#   new set cmd silentmsg for disable_notification - syntax as in msg
#   INT: change forceReply to options for sendit
# 2.7 2017-12-20  set command silentmsg 

#   new set cmd silentImage for disable_notification - syntax as in sendImage
#   FIX: allow queryAsnwer also with defaultpeer not set #msg757339
#   General. set commands not requiring a peer - internally set peers to 0 for sendit
#   FIX: Doc missing end code tag
#   Change log to not write _Set/_Get on ? parameter
#   attr to handle set / del types for polling/allowedCmds/favorites
#   silentInline added
#   cmdSendSilent added and documented
#   tests and fixes on handling of peers/chats for tbot_list and replies
#   FIX: peer names not numeric in send commands
#   FIX: disable also sending messages
#   FIX: have disable attribute with dropdown
#   Allow caption in sendImage also with \n\t
# 2.8 2018-03-11  more silent cmds, caption formatting, several fixes 

#   
##############################################################################
# TASKS 
#   
#   additional silent commands
#   
#   queryDialogStart / queryDialogEnd - keep msg id 
#   
#   remove keyboard after favorite confirm
#   
#   cleanup encodings
#   
#   replyKeyboardRemove - #msg592808
#   
#   \n in inline keyboards - not possible currently
#   
##############################################################################

package main;

use strict;
use warnings;

use HttpUtils;
use utf8;

use Encode;

# JSON:XS is used here normally
use JSON; 

use File::Basename;

use URI::Escape;

use Scalar::Util qw(reftype looks_like_number);

#########################
# Forward declaration
sub TelegramBot_Define($$);
sub TelegramBot_Undef($$);

sub TelegramBot_Set($@);
sub TelegramBot_Get($@);

sub TelegramBot_Callback($$$);
sub TelegramBot_SendIt($$$$$;$$$);
sub TelegramBot_checkAllowedPeer($$$);

sub TelegramBot_SplitFavoriteDef($$);

sub TelegramBot_AttrNum($$$);

sub TelegramBot_MakeKeyboard($$$@);
sub TelegramBot_ExecuteCommand($$$$;$$);

sub TelegramBot_readToken($;$);
sub TelegramBot_storeToken($$;$);

#########################
# Globals
my %sets = (
  "_msg" => "textField",
  "message" => "textField",
  "msg" => "textField",
  "send" => "textField",
  
  "silentmsg" => "textField",
  "silentImage" => "textField",
  "silentInline" => "textField",

  "msgDelete" => "textField",

  "msgEdit" => "textField",
  "msgForceReply" => "textField",

  "queryAnswer" => "textField",
  "queryInline" => "textField",
  "queryEditInline" => "textField",

  "sendImage" => "textField",
  "sendPhoto" => "textField",

  "sendDocument" => "textField",
  "sendMedia" => "textField",
  "sendVoice" => "textField",
  
  "sendLocation" => "textField",

  "favoritesMenu" => "textField",
  
  "cmdSend" => "textField",
  "cmdSendSilent" => "textField",

  "replaceContacts" => "textField",
  "reset" => undef,

  "reply" => "textField",

  "token" => "textField",

  "zDebug" => "textField"

);

my %deprecatedsets = (

  "image" => "textField",   
  "sendPhoto" => "textField",   
);

my %gets = (
  "urlForFile" => "textField",

  "update" => undef,
  
  "peerId" => "textField",
);

my $TelegramBot_header = "agent: TelegramBot/1.0\r\nUser-Agent: TelegramBot/1.0\r\nAccept: application/json\r\nAccept-Charset: utf-8";


my $TelegramBot_arg_retrycnt = 6;

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

sub TelegramBot_Initialize($) {
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{DefFn}      = "TelegramBot_Define";
  $hash->{UndefFn}    = "TelegramBot_Undef";
  $hash->{StateFn}    = "TelegramBot_State";
  $hash->{GetFn}      = "TelegramBot_Get";
  $hash->{RenameFn}   = "TelegramBot_Rename";
  $hash->{SetFn}      = "TelegramBot_Set";
  $hash->{AttrFn}     = "TelegramBot_Attr";
  $hash->{AttrList}   = "defaultPeer defaultPeerCopy:0,1 cmdKeyword cmdSentCommands favorites:textField-long favoritesInline:0,1 cmdFavorites cmdRestrictedPeer ". "cmdTriggerOnly:0,1 saveStateOnContactChange:1,0 maxFileSize maxReturnSize cmdReturnEmptyResult:1,0 pollingVerbose:1_Digest,2_Log,0_None ".
  "cmdTimeout pollingTimeout disable:1,0 queryAnswerText:textField cmdRespondChat:0,1 ".
  "allowUnknownContacts:1,0 textResponseConfirm:textField textResponseCommands:textField allowedCommands filenameUrlEscape:1,0 ". 
  "textResponseFavorites:textField textResponseResult:textField textResponseUnauthorized:textField ".
  "parseModeSend:0_None,1_Markdown,2_HTML,3_InMsg webPagePreview:1,0 utf8Special:1,0 favorites2Col:0,1 ".
  " maxRetries:0,1,2,3,4,5 ".$readingFnAttributes;           
}


######################################
#  Define function is called for actually defining a device of the corresponding module
#  For TelegramBot this is mainly API id for the bot
#  data will be stored in the hash of the device as internals
#  
sub TelegramBot_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $name = $hash->{NAME};

  Log3 $name, 3, "TelegramBot_Define $name: called ";

  my $errmsg = '';
  
  # Check parameter(s)
  
  # If api token is given check for syntax and remove from hash
  if ( ( int(@a) == 3 ) && ( $a[2] !~ /^([[:alnum:]]|[-:_])+[[:alnum:]]+([[:alnum:]]|[-:_])+$/ ) ) {
    $errmsg = "specify valid API token containing only alphanumeric characters and -: characters: define <name> TelegramBot  [ <APItoken> ]";
    Log3 $name, 1, "TelegramBot $name: " . $errmsg;
    return $errmsg;
  } elsif ( ( int(@a) == 2 ) && ( ! TelegramBot_readToken($hash) ) ){
    $errmsg = "no predefined token found specify token in define: define <name> TelegramBot <APItoken>";
    Log3 $name, 1, "TelegramBot $name: " . $errmsg;
    return $errmsg;
  } elsif( int(@a) > 3 || int(@a) < 2) {
    $errmsg = "syntax error: define <name> TelegramBot [ <APIid> ]"; 
    Log3 $name, 1, "TelegramBot $name: " . $errmsg;
    return $errmsg;
  }
  
  my $ret;
  
  $hash->{TYPE} = "TelegramBot";

  $hash->{STATE} = "Undefined";

  $hash->{WAIT} = 0;
  $hash->{FAILS} = 0;
  $hash->{UPDATER} = 0;
  $hash->{POLLING} = -1;
  
  my %hu_upd_params = (
                  url        => "",
                  timeout    => 5,
                  method     => "GET",
                  header     => $TelegramBot_header,
                  isPolling  => "update",
                  hideurl    => 1,
                  callback   => \&TelegramBot_Callback
  );

  my %hu_do_params = (
                  url        => "",
                  timeout    => 30,
                  method     => "GET",
                  header     => $TelegramBot_header,
                  hideurl    => 1,
                  callback   => \&TelegramBot_Callback
  );

  $hash->{HU_UPD_PARAMS} = \%hu_upd_params;
  $hash->{HU_DO_PARAMS} = \%hu_do_params;

  if (int(@a) == 3) {
      TelegramBot_storeToken($hash, $a[2]);
      $hash->{DEF} = undef; 
  }

  TelegramBot_Setup( $hash );

  return $ret; 
}

#####################################
#  Undef function is corresponding to the delete command the opposite to the define function 
#  Cleanup the device specifically for external ressources like connections, open files, 
#    external memory outside of hash, sub processes and timers
sub TelegramBot_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, "TelegramBot_Undef $name: called ";

  HttpUtils_Close($hash->{HU_UPD_PARAMS}); 
  
  HttpUtils_Close($hash->{HU_DO_PARAMS}); 

  RemoveInternalTimer($hash);

  RemoveInternalTimer($hash->{HU_DO_PARAMS});

  Log3 $name, 4, "TelegramBot_Undef $name: done ";
  return undef;
}


#############################################################################################
# called when the device gets renamed,
# in this case we then also need to rename the key in the token store and ensure it is recoded with new name
sub TelegramBot_Rename($$) {
    my ($new,$old) = @_;
    
    my $nhash = $defs{$new};
    
    my $token = TelegramBot_readToken( $nhash, $old );
    TelegramBot_storeToken( $nhash, $token );

    # remove old token with old name
    my $index_old = "TelegramBot_" . $old . "_token";
    setKeyValue($index_old, undef); 
}


##############################################################################
##############################################################################
##
## Instance operational methods
##
##############################################################################
##############################################################################


####################################
# State function to ensure contacts internal hash being reset on Contacts Readings Set
sub TelegramBot_State($$$$) {
  my ($hash, $time, $name, $value) = @_; 
  
#  Log3 $hash->{NAME}, 4, "TelegramBot_State called with :$name: value :$value:";

  if ($name eq 'Contacts')  {
    TelegramBot_CalcContactsHash( $hash, $value );
    Log3 $hash->{NAME}, 4, "TelegramBot_State Contacts hash has now :".scalar(keys %{$hash->{Contacts}}).":";
  }
  
  return undef;
}
 
####################################
# set function for executing set operations on device
sub TelegramBot_Set($@)
{
  my ( $hash, $name, @args ) = @_;
  
  Log3 $name, 5, "TelegramBot_Set $name: called "; 

  ### Check Args
  my $numberOfArgs  = int(@args);
  return "TelegramBot_Set: No cmd specified for set" if ( $numberOfArgs < 1 );

  my $cmd = shift @args;

  if (!exists($sets{$cmd}))  {
    my @cList;
    foreach my $k (keys %sets) {
      my $opts = undef;
      $opts = $sets{$k};

      if (defined($opts)) {
        push(@cList,$k . ':' . $opts);
      } else {
        push (@cList,$k);
      }
    } # end foreach

    return "TelegramBot_Set: Unknown argument $cmd, choose one of " . join(" ", @cList);
  } # error unknown cmd handling

  Log3 $name, 4, "TelegramBot_Set $name: Processing TelegramBot_Set( $cmd )";

  my $ret = undef;
  
  if( ($cmd eq 'message') || ($cmd eq 'queryInline') || ($cmd eq 'queryEditInline') || ($cmd eq 'queryAnswer') || 
      ($cmd eq 'msg') || ($cmd eq '_msg') || ($cmd eq 'reply') || ($cmd eq 'msgEdit') || ($cmd eq 'msgForceReply') || 
      ($cmd eq 'silentmsg') || ($cmd eq 'silentImage')  || ($cmd eq 'silentInline') || ($cmd =~ /^send.*/ ) ) {

    my $msgid;
    my $msg;
    my $addPar;
    my $sendType = 0;
    my $options = "";
    my $peers;
    my $inline = 0;
    my $needspeer = 1;
    
    if ( ($cmd eq 'reply') || ($cmd eq 'msgEdit' ) || ($cmd eq 'queryEditInline' ) ) {
      return "TelegramBot_Set: Command $cmd, no msgid and no text/file specified" if ( $numberOfArgs < 3 );
      $msgid = shift @args; 
      return "TelegramBot_Set: Command $cmd, msgId must be given as first parameter before peer" if ( $msgid =~ /^@/ );
      $numberOfArgs--;
      # all three messages need also a peer/chat_id
    } elsif ($cmd eq 'queryAnswer')  {
      $needspeer = 0;
    }
    
    # special options
    $inline = 1 if ( ($cmd eq 'queryInline') || ($cmd eq 'queryEditInline') || ($cmd eq 'silentInline') );
    $options .= " -force_reply- " if ($cmd eq 'msgForceReply');
    $options .= " -silent- " if ( ($cmd eq 'silentmsg') || ($cmd eq 'silentImage') || ($cmd eq 'silentInline') ) ;
    
    
    return "TelegramBot_Set: Command $cmd, no peers and no text/file specified" if ( $numberOfArgs < 2 );
    # numberOfArgs might not be correct beyond this point

    while ( $args[0] =~ /^@(..+)$/ ) {
      my $ppart = $1;
      return "TelegramBot_Set: Command $cmd, need exactly one peer" if ( ($cmd eq 'reply') && ( defined( $peers ) ) );
      $peers .= " " if ( defined( $peers ) );
      $peers = "" if ( ! defined( $peers ) );
      $peers .= $ppart;
      
      shift @args;
      last if ( int(@args) == 0 );
    }
      
    return "TelegramBot_Set: Command $cmd, no msg content specified" if ( int(@args) < 1 );


    if ( ($needspeer ) && ( ! defined( $peers ) ) ) {
      $peers = AttrVal($name,'defaultPeer',undef);
      return "TelegramBot_Set: Command $cmd, without explicit peer requires defaultPeer being set" if ( ! defined($peers) );
    } elsif ( ! defined( $peers ) ) {
      $peers = 0;
    }
    if ( ($cmd eq 'sendPhoto') || ($cmd eq 'sendImage') || ($cmd eq 'image') || ($cmd eq 'silentImage')  ) {
      $sendType = 1;
    } elsif ($cmd eq 'sendVoice')  {
      $sendType = 2;
    } elsif ( ($cmd eq 'sendDocument') || ($cmd eq 'sendMedia') ) {
      $sendType = 3;
    } elsif ( ($cmd eq 'msgEdit') || ($cmd eq 'queryEditInline') )  {
      $sendType = 10;
    } elsif ($cmd eq 'sendLocation')  {
      $sendType = 11;
    } elsif ($cmd eq 'queryAnswer')  {
      $sendType = 12;
    }

    if ( $sendType == 11 ) {
      # location
      
      return "TelegramBot_Set: Command $cmd, 2 parameters latitude / longitude need to be specified" if ( int(@args) != 2 );      

      # first latitude
      $msg = shift @args;

      # first longitude
      $addPar = shift @args;
      
    } elsif ( $sendType == 12 ) {
      # inline query
      
      return "TelegramBot_Set: Command $cmd, no inline query id given" if ( int(@args) < 1 );      

      # first inline query id
      $addPar = shift @args;
      
      # remaining msg
      $msg = "";
      $msg = join(" ", @args ) if ( int(@args) > 0 );

    } elsif ( ( $sendType > 0 ) && ( $sendType < 10 ) ) {
      # should return undef if succesful
      $msg = shift @args;
      $msg = $1 if ( $msg =~ /^\"(.*)\"$/ );

      if ( $sendType == 1 ) {
        # for Photos a caption can be given
        $addPar = join(" ", @args ) if ( int(@args) > 0 );
      } else {
        return "TelegramBot_Set: Command $cmd, extra parameter specified after filename" if ( int(@args) > 0 );
      }
    } else {
      if ( ! defined( $addPar ) ) {
        # check for Keyboard given (only if not forcing reply) and parse it to keys / jsonkb
        my @keys; 
        while ( $args[0] =~ /^\s*\(.*$/ ) {
          my $aKey = "";
          while ( $aKey !~ /^\s*\((.*)\)\s*$/ ) {
            $aKey .= " ".$args[0];
            
            shift @args;
            last if ( int(@args) == 0 );
          }  
          # trim key
          $aKey =~ s/^\s+|\s+$//g;

          if ( $aKey =~ /^\((.*)\)$/ ) {
            my @tmparr = split( /\|/, $1 );  
            push( @keys, \@tmparr );           
          } else {
            # incomplete key handle as message
            unshift( @args, $aKey ) if ( length( $aKey ) > 0 );
            last;
          }
        }
    
        $addPar = TelegramBot_MakeKeyboard( $hash, 1, $inline, @keys ) if ( scalar( @keys ) );
      }
    
      return "TelegramBot_Set: Command $cmd, no text for msg specified " if ( int(@args) == 0 );
      $msg = join(" ", @args );
    }
      
    Log3 $name, 5, "TelegramBot_Set $name: start send for cmd :$cmd: and sendType :$sendType:";
    $ret = TelegramBot_SendIt( $hash, $peers, $msg, $addPar, $sendType, $msgid, $options );


  } elsif($cmd eq 'favoritesMenu') {

    my $peers;
    if ( int(@args) > 0 ) {
      while ( $args[0] =~ /^@(..+)$/ ) {
        my $ppart = $1;
        return "TelegramBot_Set: Command $cmd, need exactly one peer" if ( ( defined( $peers ) ) );
        $peers = (defined($peers)?$peers." ":"").$ppart;
        shift @args;
        last if ( int(@args) == 0 );
      }   
      return "TelegramBot_Set: Command $cmd, addiitonal parameter specified" if ( int(@args) >= 1 );
    }
    
    if ( ! defined( $peers ) ) {
      $peers = AttrVal($name,'defaultPeer',undef);
      return "TelegramBot_Set: Command $cmd, without explicit peer requires defaultPeer being set" if ( ! defined($peers) );
    }
    
    return "TelegramBot_Set: Command $cmd, no favorites defined" if ( ! defined( AttrVal($name,'favorites',undef) ) );

    TelegramBot_SendFavorites($hash, $peers, undef, "", undef, undef, 0);
  
  } elsif($cmd =~ 'cmdSend(Silent)?') {

    return "TelegramBot_Set: Command $cmd, no peers and no text/file specified" if ( $numberOfArgs < 2 );
    # numberOfArgs might not be correct beyond this point
    
    my $options = "";
    $options .= " -silent- " if ( ($cmd eq 'cmdSendSilent') ) ;

    my $peers;
    while ( $args[0] =~ /^@(..+)$/ ) {
      my $ppart = $1;
      return "TelegramBot_Set: Command $cmd, need exactly one peer" if ( ( defined( $peers ) ) );
      $peers .= " " if ( defined( $peers ) );
      $peers = "" if ( ! defined( $peers ) );
      $peers .= $ppart;
      
      shift @args;
      last if ( int(@args) == 0 );
    }   
    return "TelegramBot_Set: Command $cmd, no msg content specified" if ( int(@args) < 1 );

    if ( ! defined( $peers ) ) {
      $peers = AttrVal($name,'defaultPeer',undef);
      return "TelegramBot_Set: Command $cmd, without explicit peer requires defaultPeer being set" if ( ! defined($peers) );
    }

    # Execute command
    my $isMediaStream = 0;
    
    my $msg;
    my $scmd = join(" ", @args );

    # run replace set magic on command - first
    my %dummy; 
    my ($err, @a) = ReplaceSetMagic(\%dummy, 0, ( $scmd ) );
      
    if ( $err ) {
      Log3 $name, 1, "TelegramBot_Set $name: parse cmd failed on ReplaceSetmagic with :$err: on  :$scmd:";
    } else {
      $msg = join(" ", @a);
      Log3 $name, 4, "TelegramBot_Set $name: parse cmd returned :$msg:";
    } 
  
    $msg = AnalyzeCommandChain( $hash, $msg );

    # Check for image/doc/audio stream in return (-1 image
    ( $isMediaStream ) = TelegramBot_IdentifyStream( $hash, $msg ) if ( defined( $msg ) );
      
    Log3 $name, 5, "TelegramBot_Set $name: start send for cmd :$cmd: and isMediaStream :$isMediaStream:";
    $ret = TelegramBot_SendIt( $hash, $peers, $msg, undef, $isMediaStream, undef, $options );
    
  } elsif($cmd eq 'msgDelete') {

    my $peers;
    my $sendType = 20;
    
    return "TelegramBot_Set: Command $cmd, no peer and no msgid specified" if ( $numberOfArgs < 2 );
    my $msgid = shift @args; 
    return "TelegramBot_Set: Command $cmd, msgId must be given as first parameter before peer" if ( $msgid =~ /^@/ );
    $numberOfArgs--;
      
    while ( $args[0] =~ /^@(..+)$/ ) {
      my $ppart = $1;
      return "TelegramBot_Set: Command $cmd, need exactly one peer" if ( defined( $peers ) );
      $peers .= " " if ( defined( $peers ) );
      $peers = "" if ( ! defined( $peers ) );
      $peers .= $ppart;
      
      shift @args;
      last if ( int(@args) == 0 );
    }

    if ( ! defined( $peers ) ) {
      $peers = AttrVal($name,'defaultPeer',undef);
      return "TelegramBot_Set: Command $cmd, without explicit peer requires defaultPeer being set" if ( ! defined($peers) );
    }
    
    Log3 $name, 5, "TelegramBot_Set $name: start send for cmd :$cmd: and sendType :$sendType:";
    $ret = TelegramBot_SendIt( $hash, $peers, "", undef, $sendType, $msgid );

  } elsif($cmd eq 'zDebug') {
    # for internal testing only
    Log3 $name, 5, "TelegramBot_Set $name: start debug option ";
#    delete $hash->{sentMsgPeer};
#    $ret = TelegramBot_SendIt( $hash, AttrVal($name,'defaultPeer',undef), "abc     def\n   def    ghi", undef, 0, undef );
  $hash->{HU_UPD_PARAMS}->{callback} = \&TelegramBot_Callback;
  $hash->{HU_DO_PARAMS}->{callback} = \&TelegramBot_Callback;

  } elsif($cmd eq 'token') {
    if ( $numberOfArgs == 2 ) {
      $ret = TelegramBot_storeToken ( $hash, $args[0] );
      TelegramBot_Setup( $hash );
    } else {
      return "TelegramBot_Set: Command $cmd no token specified or addtl parameters given";
    }
  } elsif($cmd eq 'reset') {
    Log3 $name, 5, "TelegramBot_Set $name: reset requested ";
    TelegramBot_Setup( $hash );

  } elsif($cmd eq 'replaceContacts') {
    if ( $numberOfArgs < 2 ) {
      return "TelegramBot_Set: Command $cmd, need to specify contacts string separate by space and contacts in the form of <id>:<full_name>:[@<username>|#<groupname>] ";
    }
    my $arg = join(" ", @args );
    Log3 $name, 3, "TelegramBot_Set $name: set new contacts to :$arg: ";
    # first set the hash accordingly
    TelegramBot_CalcContactsHash($hash, $arg);

    # then calculate correct string reading and put this into the reading
    my @dumarr;
    
    TelegramBot_ContactUpdate($hash, @dumarr);

    Log3 $name, 5, "TelegramBot_Set $name: contacts newly set ";

  }
  
  if ( ! defined( $ret ) ) {
    Log3 $name, 5, "TelegramBot_Set $name: $cmd done succesful: ";
  } else {
    Log3 $name, 5, "TelegramBot_Set $name: $cmd failed with :$ret: ";
  }
  return $ret
}

#####################################
# get function for gaining information from device
sub TelegramBot_Get($@)
{
  my ( $hash, $name, @args ) = @_;
  
  Log3 $name, 5, "TelegramBot_Get $name: called ";

  ### Check Args
  my $numberOfArgs  = int(@args);
  return "TelegramBot_Get: No value specified for get" if ( $numberOfArgs < 1 );

  my $cmd = $args[0];
  my $arg = ($args[1] ? $args[1] : "");

  if(!exists($gets{$cmd})) {
    my @cList;
    foreach my $k (sort keys %gets) {
      my $opts = undef;
      $opts = $sets{$k};

      if (defined($opts)) {
        push(@cList,$k . ':' . $opts);
      } else {
        push (@cList,$k);
      }
    } # end foreach

    return "TelegramBot_Get: Unknown argument $cmd, choose one of " . join(" ", @cList);
  } # error unknown cmd handling

  Log3 $name, 4, "TelegramBot_Get $name: Processing TelegramBot_Get( $cmd )";
  
  my $ret = undef;
  
  if($cmd eq 'urlForFile') {
    if ( $numberOfArgs != 2 ) {
      return "TelegramBot_Get: Command $cmd, no file id specified";
    }

    $hash->{fileUrl} = "";
    
    # return URL for file id
    my $url = TelegramBot_getBaseURL($hash)."getFile?file_id=".urlEncode($arg);
    my $guret = TelegramBot_DoUrlCommand( $hash, $url );
    my $token = TelegramBot_readToken( $hash );

    if ( ( defined($guret) ) && ( ref($guret) eq "HASH" ) ) {
      if ( defined($guret->{file_path} ) ) {
        # URL is https://api.telegram.org/file/bot<token>/<file_path>
        my $filePath = $guret->{file_path};
        $hash->{fileUrl} = "https://api.telegram.org/file/bot".$token."/".$filePath;
        $ret = $hash->{fileUrl};
      } else {
        $ret = "urlForFile failed: no file path found";
        $hash->{fileUrl} = $ret;
      }      

    } else {
      $ret = "urlForFile failed: ".(defined($guret)?$guret:"<undef>");
      $hash->{fileUrl} = $ret;
    }

  } elsif ( $cmd eq "update" ) {
    $ret = TelegramBot_UpdatePoll( $hash, "doOnce" );

  } elsif ( $cmd eq "peerId" ) {
    if ( $numberOfArgs != 2 ) {
      return "TelegramBot_Get: Command $cmd, peer specified";
    }
    $ret = TelegramBot_GetIdForPeer( $hash, $arg );
  }
  
  
  
  
  Log3 $name, 5, "TelegramBot_Get $name: done with ".( defined($ret)?$ret:"<undef>").": ";

  return $ret
}

##############################
# attr function for setting fhem attributes for the device
sub TelegramBot_Attr(@) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};

  Log3 $name, 5, "TelegramBot_Attr $name: called ";

  return "\"TelegramBot_Attr: \" $name does not exist" if (!defined($hash));

  if (defined($aVal)) {
    Log3 $name, 5, "TelegramBot_Attr $name: $cmd  on $aName to $aVal";
  } else {
    Log3 $name, 5, "TelegramBot_Attr $name: $cmd  on $aName to <undef>";
  }
  
  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value
  if ($aName eq 'favorites') {
    # Empty current alias list in hash
    if ( defined( $hash->{AliasCmds} ) ) {
      foreach my $key (keys %{$hash->{AliasCmds}} )
          {
              delete $hash->{AliasCmds}{$key};
          }
    } else {
      $hash->{AliasCmds} = {};
    }

    if ($cmd eq "set") {
      # keep double ; for inside commands
      $aVal =~ s/;;/SeMiCoLoN/g; 
      my @clist = split( /;/, $aVal);
      my $newVal = "";
      my $cnt = 0;

      foreach my $cs (  @clist ) {
        $cs =~ s/SeMiCoLoN/;;/g; # reestablish double ; for inside commands
        my ( $alias, $desc, $minusdesc, $parsecmd, $needsConfirm, $needsResult, $hidden ) = TelegramBot_SplitFavoriteDef( $hash, $cs );
        
        # Debug "parsecmd :".$parsecmd.":  ".length($parsecmd);
        next if ( length($parsecmd) == 0 ); # skip emtpy commands

        $cnt += 1;

        $newVal .= ";" if ( length($newVal)>0 );
        $newVal .= $cs;
        if ( $alias ) {
          my $alx = $alias;
          my $alcmd = $parsecmd;
          
          Log3 $name, 2, "TelegramBot_Attr $name: Alias $alcmd defined multiple times" if ( defined( $hash->{AliasCmds}{$alx} ) );
          $hash->{AliasCmds}{$alx} = $cnt;
        }
      }

      # set attribute value to newly combined commands
      $attr{$name}{'favorites'} = $newVal;
      $aVal = $newVal;
    }
  
  } elsif ($aName eq 'allowedCommands') {
    my $allowedName = "allowed_$name";
    my $exists = ($defs{$allowedName} ? 1 : 0); 
    my $alcmd = (($cmd eq "set")?$aVal:"<none>");
    AnalyzeCommand(undef, "defmod $allowedName allowed");
    AnalyzeCommand(undef, "attr $allowedName validFor $name");
    AnalyzeCommand(undef, "attr $allowedName $aName ".$alcmd);
    Log3 $name, 3, "TelegramBot_Attr $name: ".($exists ? "modified":"created")." $allowedName with commands :$alcmd:";
    # allowedCommands only set on the corresponding allowed_device
    return "\"TelegramBot_Attr: \" $aName ".($exists ? "modified":"created")." $allowedName with commands :$alcmd:"
      
  } elsif ($aName eq 'pollingTimeout') {
    return "\"TelegramBot_Attr: \" $aName needs to be given in digits only" if ( ($cmd eq "set") && ( $aVal !~ /^[[:digit:]]+$/ ) );
    # let all existing methods run into block
    RemoveInternalTimer($hash);
    $hash->{POLLING} = -1;
    
    # wait some time before next polling is starting
    TelegramBot_ResetPolling( $hash );

  } elsif ($aName eq 'disable') {
    return "\"TelegramBot_Attr: \" $aName needs to be 1 or 0" if ( ($cmd eq "set") && ( $aVal !~ /^(1|0)$/ ) );
    # let all existing methods run into block
    RemoveInternalTimer($hash);
    $hash->{POLLING} = -1;
    
    # wait some time before next polling is starting
    TelegramBot_ResetPolling( $hash );

    
  # attributes where only the set is relevant for syntax check  
  } elsif ($cmd eq "set") {

    if ($aName eq 'cmdRestrictedPeer') {
      $aVal =~ s/^\s+|\s+$//g;
      
    } elsif ( ($aName eq 'defaultPeerCopy') ||
              ($aName eq 'saveStateOnContactChange') ||
              ($aName eq 'cmdReturnEmptyResult') ||
              ($aName eq 'cmdTriggerOnly') ||
              ($aName eq 'allowUnknownContacts') ) {
      $aVal = ($aVal eq "1")? "1": "0";

    } elsif ( ($aName eq 'maxFileSize') ||
              ($aName eq 'maxReturnSize') ||
              ($aName eq 'maxRetries') ) {
      return "\"TelegramBot_Attr: \" $aName needs to be given in digits only" if ( $aVal !~ /^[[:digit:]]+$/ );


    } elsif ($aName eq 'pollingVerbose') {
      return "\"TelegramBot_Attr: \" Incorrect value given for pollingVerbose" if ( $aVal !~ /^((1_Digest)|(2_Log)|(0_None))$/ );
    }

    $_[3] = $aVal;
  
  }

  return undef;
}


##############################################################################
##############################################################################
##
## Command handling
##
##############################################################################
##############################################################################

#####################################
#####################################
# INTERNAL: Check against cmdkeyword given (no auth check !!!!)
sub TelegramBot_checkCmdKeyword($$$$$$) {
  my ($hash, $mpeernorm, $mchatnorm, $mtext, $cmdKey, $needsSep ) = @_;
  my $name = $hash->{NAME};

  my $cmd;
  my $doRet = 0;
  
#  Log3 $name, 3, "TelegramBot_checkCmdKeyword $name: check :".$mtext.":   against defined :".$ck.":   results in ".index($mtext,$ck);

  return ( undef, 0 ) if ( ! defined( $cmdKey ) );

  # Trim and then if requested add a space to the cmdKeyword
  $cmdKey =~ s/^\s+|\s+$//g;
  
  my $ck = $cmdKey;
  # Check special case end of messages considered separator
  if ( $mtext ne $ck ) { 
    $ck .= " " if ( $needsSep );
    return ( undef, 0 )  if ( index($mtext,$ck) != 0 );
  }

  $cmd = substr( $mtext, length($ck) );
  $cmd =~ s/^\s+|\s+$//g;

  # validate security criteria for commands and return cmd only if succesful
  return ( undef, 1 )  if ( ! TelegramBot_checkAllowedPeer( $hash, $mpeernorm, $mtext ) );

  return ( undef, 1 )  if ( ( $mchatnorm ) && ( ! TelegramBot_checkAllowedPeer( $hash, $mchatnorm, $mtext ) ) );


  return ( $cmd, 1 );
}
    

#####################################
#####################################
# INTERNAL: Split Favorite def in alias(optional), description (optional), parsecmd, needsConfirm
sub TelegramBot_SplitFavoriteDef($$) {
  my ($hash, $cmd ) = @_;
  my $name = $hash->{NAME};

  # Valid favoritedef
  #   list TYPE=SOMFY
  #   ?set TYPE=CUL_WM getconfig
  #   /rolladen=list TYPE=SOMFY
  #   /rolladen=?list TYPE=SOMFY
  #   /-rolladen=list TYPE=SOMFY
  
  #   /[Liste Rolladen]=list TYPE=SOMFY
  #   /[Liste Rolladen]=?list TYPE=SOMFY
  #   /rolladen[Liste Rolladen]=list TYPE=SOMFY
  #   /-rolladen[Liste Rolladen]=list TYPE=SOMFY
  #   /rolladen[Liste Rolladen]=list TYPE=SOMFY
  
  #   /[-Liste Rolladen]=list TYPE=SOMFY
  #   /[-Liste Rolladen]=?list TYPE=SOMFY
  #   /rolladen[-Liste Rolladen]=list TYPE=SOMFY
  #   /-rolladen[-Liste Rolladen]=list TYPE=SOMFY
  #   /rolladen[-Liste Rolladen]=list TYPE=SOMFY
  
  my ( $alias, $desc, $parsecmd, $confirm, $result, $hidden, $minusdesc  );
  $confirm = "";
  $result = "";
  $hidden = 0;
  $minusdesc = "";
  
  if ( $cmd =~ /^\s*((\/([^\[=]*)?)(\[(-)?([^\]]+)\])?\s*=)?(\??)(\!?)(.*?)$/ ) {
    $alias = $2;
    $minusdesc = $5 if ( $5 );
    $desc = $6;
    $confirm = $7 if ( $7 );
    $result = $8  if ( $8 );
    $parsecmd = $9;
    
    $alias = undef if ( $alias && ( $alias =~ /^\/-?$/ ) );
    if ( $alias && ( $alias =~ /\/-/ ) ) {
      $hidden = 1;
      $alias =~ s/^\/-/\//;   # remove - in alias
    }

    # replace double semicolon 
    $parsecmd =~ s/;;/;/g if ( $parsecmd ); # reestablish double ; for inside commands     
    
#    Debug "Parse 1  a:".$alias.":  d:".$desc.":  c:".$parsecmd.":";
  } else {
    Log3 $name, 1, "TelegramBot_SplitFavoriteDef invalid favorite definition :$cmd: ";
  }
  
  Log3 $name, 4, "TelegramBot_SplitFavoriteDef cmd :$cmd: \n      alias :".($alias?$alias:"<undef>").": desc :".($desc?$desc:"<undef>").
                  ":  parsecmd :".($parsecmd?$parsecmd:"<undef>").
                  ":   confirm: ".(($confirm eq "?")?1:0).":   result: ".(($result eq "!")?1:0).":   hidden: ".$hidden;
  
  return ( $alias, $desc, (($minusdesc eq "-")?1:0), $parsecmd, (($confirm eq "?")?1:0), (($result eq "!")?1:0), $hidden );
}
    
#####################################
#####################################
# INTERNAL: handle favorites and alias execution
# alias exec is used by case an alias command is entered
#
# cmd is everything after the key word
# cases
#   empty --> list of favorites
#   [0-9]+ --> id no addition
#   [0-9]+ <addition> --> id no addition
#   [0-9]+ = <description or cmd> --> id automaticall no addition
#   
#   -[0-9]+- --> confirmed manually no addition
#   -[0-9]+- ; <addition> --> confirmed manually with addition
#   
#   -[0-9]+- = <description or cmd> --> confirmed automatically without addition
#   -[0-9]+- = <description or cmd> =; <addition> --> confirmed automatically with addition
#   
#
sub TelegramBot_SendFavorites($$$$$;$$) {
  my ($hash, $mpeernorm, $mchatnorm, $cmd, $mid, $aliasExec, $iscallback ) = @_;
  my $name = $hash->{NAME};
  
  $aliasExec = 0 if ( ! $aliasExec );
  $iscallback = 0 if ( ! $iscallback );

  my $ret;
  
  Log3 $name, 4, "TelegramBot_SendFavorites cmd correct peer ";

  my $isInline = ( AttrVal($name, "favoritesInline", 0 ) ? 1 : 0 );
  my $slc =  AttrVal($name,'favorites',"");
  
  # keep double ; for inside commands
  $slc =~ s/;;/SeMiCoLoN/g; 
  my @clist = split( /;/, $slc);
  my $isConfirm;
  my $cmdFavId;
  my $cmdAddition;
  
  my $resppeer = $mpeernorm;
  $resppeer .= "(".$mchatnorm.")" if ( $mchatnorm ); 
  
  my $storedMgsId = $mid if ( $isInline );   # nur queryeditinline wenn wirklich inline gesetzt
  
  Log3 $name, 4, "TelegramBot_SendFavorites cmd :$cmd:   peer :$mpeernorm:   aliasExec :".$aliasExec;
  
  if ( $cmd =~ /^\s*cancel\s*$/ ) {
    if ( $storedMgsId ) {
      # 10 for edit inline
      $ret = TelegramBot_SendIt( $hash, (($mchatnorm)?$mchatnorm:$mpeernorm), "Favoriten beendet", undef, 10, $storedMgsId );
    }
    return $ret;
  }

  if ( $cmd =~ /^\s*([0-9]+)( = .+)?\s*$/ ) {
  #   [0-9]+ --> id no addition
  #   [0-9]+ = <description or cmd> --> id automaticall no addition
    $cmdFavId = $1;
  
  } elsif ( $cmd =~ /^\s*([0-9]+)(.+)\s*$/ ) {
  #   [0-9]+<addition> --> id addition
    $cmdFavId = $1;
    $cmdAddition = $2;
    
  } elsif ( $cmd =~ /^\s*([0-9]+)( ; (.*))?\s*$/ ) {
  #   [0-9]+ --> id no addition
  #   [0-9]+ ; <addition> --> id but addition
    $cmdFavId = $1;
    $cmdAddition = $3;
    
  } elsif ( $cmd =~ /^\s*-([0-9]+)-( ; (.*))?\s*$/ ) {
  #   -[0-9]+- --> confirmed manually no addition
  #   -[0-9]+- ; <addition> --> confirmed manually with addition
    $cmdFavId = $1;
    $cmdAddition = $3;
    $isConfirm = 1;
    
  } elsif ( $cmd =~ /^\s*-([0-9]+)-( = ((=[^;])|([^=;])|([^=];))*)( =; (.*))?\s*$/ ) {
  #   -[0-9]+- = <description or cmd> --> confirmed automatically without addition
  #   -[0-9]+- = <description or cmd> =; <addition> --> confirmed automatically with addition
    $cmdFavId = $1;
    $cmdAddition = $8;
    $isConfirm = 1;

  } elsif ( $cmd =~ /^\s*(.*)\s*$/ ) {
  #   --> no id no addition
  #   <addition> --> no id but addition
    $cmdAddition = $1;
    
  } 
  
  # trim cmd addition if given
  $cmdAddition =~ s/^\s+|\s+$//g if ( $cmdAddition );
  
  Log3 $name, 5, "TelegramBot_SendFavorites parsed cmdFavId :".(defined($cmdFavId)?$cmdFavId:"<undef>")."   cmdaddition :".(defined($cmdAddition)?$cmdAddition:"<undef>").": ";

  # if given a number execute the numbered favorite as a command
  if ( $cmdFavId ) {
    my $cmdId = ($cmdFavId-1);
    Log3 $name, 4, "TelegramBot_SendFavorites exec cmd :$cmdId: ";
    if ( ( $cmdId >= 0 ) && ( $cmdId < scalar( @clist ) ) ) { 
      my $ecmd = $clist[$cmdId];
      $ecmd =~ s/SeMiCoLoN/;;/g; # reestablish double ; for inside commands 
            
      my ( $alias, $desc, $minusdesc, $parsecmd, $needsConfirm, $needsResult, $hidden ) = TelegramBot_SplitFavoriteDef( $hash, $ecmd );
      return "Alias could not be parsed :$ecmd:" if ( ! $parsecmd );

      $ecmd = $parsecmd;
      
      if ( ( $hidden ) && ( ! $aliasExec ) && ( ! $isConfirm ) && ( ! $storedMgsId )  ) {
        Log3 $name, 3, "TelegramBot_SendFavorites hidden favorite (id;".($cmdId+1).") execution from ".$mpeernorm;
      } elsif ( ( ! $isConfirm ) && ( $needsConfirm ) ) {
        # ask first for confirmation
        my $fcmd = AttrVal($name,'cmdFavorites',"");
        
        my @tmparr;
        my @keys = ();
        my $tmptxt;
        
        if ( $isInline ) {
          $tmptxt = (($desc)?$desc:$parsecmd);
          $tmptxt .= " (".($alias?$alias:$fcmd.$cmdFavId).")" if ( ! $minusdesc );
          $tmptxt .= ":TBOT_FAVORITE_-$cmdFavId";
        } else {
          $tmptxt = $fcmd."-".$cmdFavId."- = ".(($desc)?$desc:$parsecmd).($cmdAddition?" =; ".$cmdAddition:"");
        }
        my @tmparr1 = ( $tmptxt );
        push( @keys, \@tmparr1 );
        if ( $isInline ) {
          if ( $iscallback ) {
            $tmptxt =  "Zurueck:TBOT_FAVORITE_MENU";
          } else {
            $tmptxt =  "Abbruch:TBOT_FAVORITE_CANCEL";
          }
        } else {
          $tmptxt = "Abbruch";
        }
        my @tmparr2 = ( $tmptxt );
        push( @keys, \@tmparr2 );

        my $jsonkb = TelegramBot_MakeKeyboard( $hash, 1, $isInline, @keys );

        # LOCAL: External message
        $ret = encode_utf8( AttrVal( $name, 'textResponseConfirm', 'TelegramBot FHEM : $peer\n Soll der Befehl ausgeführt werden? \n') );
        
        $ret =~ s/\$peer/$resppeer/g;
        
        return TelegramBot_SendIt( $hash, (($mchatnorm)?$mchatnorm:$mpeernorm), $ret, $jsonkb, 
                (($storedMgsId)?10:0), $storedMgsId, ((!$storedMgsId)?"-msgid-":"") );
        
      } else {
#        $ecmd = $1 if ( $ecmd =~ /^\s*\?(.*)$/ );

        if ( $storedMgsId ) {
          # 10 for edit inline
          $ret = TelegramBot_SendIt( $hash, (($mchatnorm)?$mchatnorm:$mpeernorm), "-", undef, 10, $storedMgsId );
        }

        $ecmd .= " ".$cmdAddition if ( $cmdAddition );
        return TelegramBot_ExecuteCommand( $hash, $mpeernorm, $mchatnorm, $ecmd, $needsResult, $storedMgsId );
      }
    } else {
      Log3 $name, 3, "TelegramBot_SendFavorites cmd id not defined :($cmdId+1): ";
    }
  }
  
  # ret not defined means no favorite found that matches cmd or no fav given in cmd
  if ( ! defined( $ret ) ) {
      my $cnt = 0;
      my @keys = ();
      my $showalsohidden = 1 if ( $cmdAddition && ( $cmdAddition =~ /^hidden$/i ) ); 

      my $fcmd = AttrVal($name,'cmdFavorites',undef);
      my $lastarr;
      
      foreach my $cs (  @clist ) {
        $cs =~ s/SeMiCoLoN/;;/g; # reestablish double ; for inside commands 

        $cnt += 1;
        my ( $alias, $desc, $minusdesc, $parsecmd, $needsConfirm, $needsResult, $hidden ) = TelegramBot_SplitFavoriteDef( $hash, $cs );
        if ( ( defined($parsecmd) ) && ( ( ! $hidden ) || $showalsohidden ) ) { 
          my $key;
          if ( $isInline ) {
            $key = (($desc)?$desc:$parsecmd);
            $key .= " (".($alias?$alias:$fcmd.$cnt).")" if ( ! $minusdesc );
            $key .= ":TBOT_FAVORITE_$cnt";
          } else {
            $key = ( $fcmd.$cnt." = ".($alias?$alias." = ":"").(($desc)?$desc:$parsecmd) );
          }
          if ( ( $cnt % 2 ) || ( ! AttrVal($name,"favorites2Col",0) )  ){
            my @tmparr = ( $key );
            $lastarr = \@tmparr;
            push( @keys, \@tmparr );
          } else {
            $$lastarr[1] = $key;
          }
        }
      }
      if ( $isInline ) {
        my @tmparr = ( "Abbruch:TBOT_FAVORITE_CANCEL" );
        push( @keys, \@tmparr );
      }
      
      my $jsonkb = TelegramBot_MakeKeyboard( $hash, 1, $isInline, @keys );

      Log3 $name, 5, "TelegramBot_SendFavorites keyboard:".$jsonkb.": ";
      
      # LOCAL: External message
      $ret = AttrVal( $name, 'textResponseFavorites', 'TelegramBot FHEM : $peer\n Favoriten \n');
      $ret =~ s/\$peer/$resppeer/g;
      
      # always start new dialog if msgid is given
      $ret = TelegramBot_SendIt( $hash, (($mchatnorm)?$mchatnorm:$mpeernorm), $ret, $jsonkb, 
                (($storedMgsId)?10:0), $storedMgsId, ((!$storedMgsId)?"-msgid-":"") );
 
  }
  return $ret;
  
}

  
#####################################
#####################################
# INTERNAL: handle sentlast and favorites
sub TelegramBot_SentLastCommand($$$$) {
  my ($hash, $mpeernorm, $mchatnorm, $cmd ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  Log3 $name, 5, "TelegramBot_SentLastCommand cmd correct peer ";

  my $slc =  ReadingsVal($name ,"StoredCommands","");

  my @cmds = split( "\n", $slc );

  # create keyboard
  my @keys = ();

  foreach my $cs (  @cmds ) {
    my @tmparr = ( $cs );
    push( @keys, \@tmparr );
  }
#  my @tmparr = ( $fcmd."0 = Abbruch" );
#  push( @keys, \@tmparr );

  my $jsonkb = TelegramBot_MakeKeyboard( $hash, 1, 0, @keys );

  # LOCAL: External message
  $ret = AttrVal( $name, 'textResponseCommands', 'TelegramBot FHEM : $peer\n Letzte Befehle \n');
  
  my $resppeer = $mpeernorm;
  $resppeer .= "(".$mchatnorm.")" if ( $mchatnorm );
  
  $ret =~ s/\$peer/$resppeer/g;
  
  # overwrite ret with result from SendIt --> send response
  $ret = TelegramBot_SendIt( $hash, (($mchatnorm)?$mchatnorm:$mpeernorm), $ret, $jsonkb, 0 );

  return $ret;
}

  
#####################################
#####################################
# INTERNAL: execute command and sent return value 
sub TelegramBot_ReadHandleCommand($$$$$) {
  my ($hash, $mpeernorm, $mchatnorm, $cmd, $mtext ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  Log3 $name, 4, "TelegramBot_ReadHandleCommand $name: cmd found :".$cmd.": ";
  
  Log3 $name, 5, "TelegramBot_ReadHandleCommand cmd correct peer ";
  # Either no peer defined or cmdpeer matches peer for message -> good to execute
  my $cto = AttrVal($name,'cmdTriggerOnly',"0");
  if ( $cto eq '1' ) {
    $cmd = "trigger ".$cmd;
  }
  
  Log3 $name, 5, "TelegramBot_ReadHandleCommand final cmd for analyze :".$cmd.": ";

  # store last commands (original text)
  TelegramBot_AddStoredCommands( $hash, $mtext );

  $ret = TelegramBot_ExecuteCommand( $hash, $mpeernorm, $mchatnorm, $cmd );

  return $ret;
}

  
#####################################
#####################################
# INTERNAL: execute command and sent return value 
sub TelegramBot_ExecuteCommand($$$$;$$) {
  my ($hash, $mpeernorm, $mchatnorm, $cmd, $sentemptyresult, $qMsgId ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  $sentemptyresult = AttrVal($name,'cmdReturnEmptyResult',1) if ( ! $sentemptyresult );
  
  # get human readble name for peer
  my $pname = TelegramBot_GetFullnameForContact( $hash, $mpeernorm );

  Log3 $name, 5, "TelegramBot_ExecuteCommand final cmd for analyze :".$cmd.": ";

  # special case shutdown caught here to avoid endless loop
  $ret = "shutdown command can not be executed" if ( $cmd =~ /^shutdown/ );
  
  # Execute command
  my $isMediaStream = 0;
  
  if ( ! defined( $ret ) ) {
    # run replace set magic on command - first
    my %dummy; 
    my ($err, @a) = ReplaceSetMagic(\%dummy, 0, ( $cmd ) );
      
    if ( $err ) {
      Log3 $name, 1, "TelegramBot_ExecuteCommand $name: parse cmd failed on ReplaceSetmagic with :$err: on  :$cmd:";
    } else {
      $cmd = join(" ", @a);
      Log3 $name, 4, "TelegramBot_ExecuteCommand $name: parse cmd returned :$cmd:";
    } 

    $ret = AnalyzeCommandChain( $hash, $cmd );

    # Check for image/doc/audio stream in return (-1 image
    ( $isMediaStream ) = TelegramBot_IdentifyStream( $hash, $ret ) if ( defined( $ret ) );
    
    Log3 $name, 3, "TelegramBot_ExecuteCommand $name: cmd executed :".$cmd.": -->    :".TelegramBot_MsgForLog($ret, $isMediaStream ).":" if ( $ret );
  }

  Log3 $name, 4, "TelegramBot_ExecuteCommand result for analyze :".TelegramBot_MsgForLog($ret, $isMediaStream ).": ";

  my $defpeer = AttrVal($name,'defaultPeer',undef);
  $defpeer = TelegramBot_GetIdForPeer( $hash, $defpeer ) if ( defined( $defpeer ) );
  $defpeer = AttrVal($name,'defaultPeer',undef) if ( ! defined( $defpeer ) );
  $defpeer = undef if ( defined($defpeer) && ( $defpeer eq $mpeernorm ) );
  
  # LOCAL: External message
  my $retMsg = AttrVal( $name, 'textResponseResult', 'TelegramBot FHEM - $peer Befehl:$cmd: - Ergebnis:\n$result \n ');
  $retMsg =~ s/\$cmd/$cmd/g;
  
  if ( defined( $defpeer ) ) {
    $retMsg =~ s/\$peer/$pname/g;
  } else {
    $retMsg =~ s/\$peer//g;
  }
  

  if ( ( ! defined( $ret ) ) || ( length( $ret) == 0 ) ) {
    $retMsg =~ s/\$result/OK/g;
    $ret = $retMsg if ( $sentemptyresult );
  } elsif ( ! $isMediaStream ) {
    $retMsg =~ s/\$result/$ret/g;
    $ret = $retMsg;
  }

  # trim $ret avoiding empty msg error from telegram
#  Debug "Length before :".length($ret)."   :$ret:";
  $ret =~ s/^(\s|(\\[rfnt]))+|(\s|(\\[rfnt]))+$//g if ( defined($ret) );
#  Debug "Length after :".length($ret);
  
  Log3 $name, 5, "TelegramBot_ExecuteCommand $name: ".TelegramBot_MsgForLog($ret, $isMediaStream ).": ";
  
  if ( ( defined( $ret ) ) && ( length( $ret) != 0 ) ) {
    if ( ! $isMediaStream ) {
      # replace line ends with spaces
      $ret =~ s/\r//gm;
      
      # shorten to maxReturnSize if set
      my $limit = AttrVal($name,'maxReturnSize',4000);

      if ( ( length($ret) > $limit ) && ( $limit != 0 ) ) {
        $ret = substr( $ret, 0, $limit )."\n \n ...";
      }

      $ret =~ s/\n/\\n/gm;
    }

    my $peers = (($mchatnorm)?$mchatnorm:$mpeernorm);

    my $dpc = AttrVal($name,'defaultPeerCopy',1);
    $peers .= " ".$defpeer if ( ( $dpc ) && ( defined( $defpeer ) ) );

    if ( $isMediaStream ) {
      # changing message only if not mediastream
      $qMsgId = undef;
    } elsif ( $qMsgId ) {
      # set to 10 if query msg id is set
      $isMediaStream = 10   # queryEditInline
    }
    
    # Ignore result from sendIt here
    my $retsend = TelegramBot_SendIt( $hash, $peers, $ret, undef, $isMediaStream, $qMsgId ); 
    
    # ensure return is not a stream (due to log handling)
    $ret = TelegramBot_MsgForLog($ret, $isMediaStream )
  }
  
  return $ret;
}

######################################
#  add a command to the StoredCommands reading 
#  hash, cmd
sub TelegramBot_AddStoredCommands($$) {
  my ($hash, $cmd) = @_;
 
  my $stcmds = ReadingsVal($hash->{NAME},"StoredCommands","");
  $stcmds = $stcmds;

  if ( $stcmds !~ /^\Q$cmd\E$/m ) {
    # add new cmd
    $stcmds .= $cmd."\n";
    
    # check number lines 
    my $num = ( $stcmds =~ tr/\n// );
    if ( $num > 10 ) {
      $stcmds =~ /^[^\n]+\n(.*)$/s;
      $stcmds = $1;
    }

    # change reading  
    readingsSingleUpdate($hash, "StoredCommands", $stcmds , 1); 
    Log3 $hash->{NAME}, 4, "TelegramBot_AddStoredCommands :$stcmds: ";
  }
 
}
    
#####################################
# INTERNAL: Function to check for commands in messages 
# Always executes and returns on first match also in case of error 
# mid contains the message that might be needed to editinline for favorites
sub Telegram_HandleCommandInMessages($$$$$$)
{
  my ( $hash, $mpeernorm, $mchatnorm, $mtext, $mid, $iscallback ) = @_;
  my $name = $hash->{NAME};

  my $cmdRet;
  my $cmd;
  my $doRet;

  # trim whitespace from message text
  $mtext =~ s/^\s+|\s+$//g;

  #### Check authorization for cmd execution is done inside checkCmdKeyword
  
  # Check for cmdKeyword in msg
  ( $cmd, $doRet ) = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mchatnorm, $mtext, AttrVal($name,'cmdKeyword',undef), 1 );
  if ( defined( $cmd ) ) {
    $cmdRet = TelegramBot_ReadHandleCommand( $hash, $mpeernorm, $mchatnorm, $cmd, $mtext );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: ReadHandleCommand returned :$cmdRet:" if ( defined($cmdRet) );
    return;
  } elsif ( $doRet ) {
    return;
  }
  
  # Check for sentCommands Keyword in msg
  ( $cmd, $doRet ) = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mchatnorm, $mtext, AttrVal($name,'cmdSentCommands',undef), 1 );
  if ( defined( $cmd ) ) {
    $cmdRet = TelegramBot_SentLastCommand( $hash, $mpeernorm, $mchatnorm, $cmd );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: SentLastCommand returned :$cmdRet:" if ( defined($cmdRet) );
    return;
  } elsif ( $doRet ) {
    return;
  }
    
  # Check for favorites Keyword in msg
  ( $cmd, $doRet ) = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mchatnorm, $mtext, AttrVal($name,'cmdFavorites',undef), 0 );
  if ( defined( $cmd ) ) {
    $cmdRet = TelegramBot_SendFavorites( $hash, $mpeernorm, $mchatnorm, $cmd, $mid, 0, $iscallback );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: SendFavorites returned :$cmdRet:" if ( defined($cmdRet) );
    return;
  } elsif ( $doRet ) {
    return;
  }

  # Check for favorite aliase in msg - execute command then
  if ( defined( $hash->{AliasCmds} ) ) {
    foreach my $aliasKey (keys %{$hash->{AliasCmds}} ) {
      ( $cmd, $doRet ) = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mchatnorm, $mtext, $aliasKey, 1 );
      if ( defined( $cmd ) ) {
        $cmd = $hash->{AliasCmds}{$aliasKey}." ".$cmd;
        $cmdRet = TelegramBot_SendFavorites( $hash, $mpeernorm, $mchatnorm, $cmd, $mid, 1, $iscallback ); # call with aliasesxec set
        Log3 $name, 4, "TelegramBot_ParseMsg $name: SendFavorites (alias) returned :$cmdRet:" if ( defined($cmdRet) );
        return;
      } elsif ( $doRet ) {
        return;
      }
    }
  }

  #  ignore result of readhandlecommand since it leads to endless loop
}
  
   
#####################################
# INTERNAL: Function to send a command handle result
# Parameter
#   hash
#   url - url including parameters
#   > returns string in case of error or the content of the result object if ok
#   ignore set means no error is logged
sub TelegramBot_DoUrlCommand($$;$)
{
  my ( $hash, $url, $ignore ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  Log3 $name, 5, "TelegramBot_DoUrlCommand $name: called ";

  my $param = {
                  url        => $url,
                  timeout    => 1,
                  hash       => $hash,
                  method     => "GET",
                  header     => $TelegramBot_header
              };
  my ($err, $data) = HttpUtils_BlockingGet( $param );

  if ( $err ne "" ) {
    # http returned error
    $ret = "FAILED http access returned error :$err:";
    Log3 $name, ($ignore?5:2), "TelegramBot_DoUrlCommand $name: ".$ret;
  } else {
    my $jo;
    
    eval {
#      $jo = decode_json( $data );
     my $json = JSON->new->allow_nonref;
     $jo = $json->decode(Encode::encode_utf8($data));
    };

    if ( ! defined( $jo ) ) {
      $ret = "FAILED invalid JSON returned";
      Log3 $name, ($ignore?5:2), "TelegramBot_DoUrlCommand $name: ".$ret;
    } elsif ( $jo->{ok} ) {
      $ret = $jo->{result};
      Log3 $name, 4, "TelegramBot_DoUrlCommand OK with result";
    } else {
      my $ret = "FAILED Telegram returned error: ".$jo->{description};
      Log3 $name, ($ignore?5:2), "TelegramBot_DoUrlCommand $name: ".$ret;
    }    

  }

  return $ret;
}

  
##############################################################################
##############################################################################
##
## Communication - Send - receive - Parse
##
##############################################################################
##############################################################################

#####################################
# INTERNAL: Function to send a photo (and text message) to a peer and handle result
# addPar is caption for images / keyboard for text / longituted for location (isMedia 10)
# isMedia - 0 (text) 
#  $options is list of options in hyphens --> e.g. -msgid-  for get msgid
sub TelegramBot_SendIt($$$$$;$$$)
{
  my ( $hash, @args) = @_;

  my ( $peers, $msg, $addPar, $isMedia, $replyid, $options, $retryCount) = @args;
  my $name = $hash->{NAME};
  
  $retryCount = 0 if ( ! defined($retryCount) );
  
  $options = "" if ( ! defined($options) );
  
  # increase retrycount for next try
  $args[$TelegramBot_arg_retrycnt] = $retryCount+1;
  
  Log3 $name, 5, "TelegramBot_SendIt $name: called ";
  
  # ignore all sends if disabled
  return if ( AttrVal($name,'disable',0) );

  # ensure sentQueue exists
  $hash->{sentQueue} = [] if ( ! defined( $hash->{sentQueue} ) );

  if ( ( defined( $hash->{sentMsgResult} ) ) && ( $hash->{sentMsgResult} =~ /^WAITING/ ) && (  $retryCount == 0 ) ){
    # add to queue
    Log3 $name, 4, "TelegramBot_SendIt $name: add send to queue :$peers: -:".
        TelegramBot_MsgForLog($msg, ($isMedia<0) ).": - :".(defined($addPar)?$addPar:"<undef>").":";
    push( @{ $hash->{sentQueue} }, \@args );
    return;
  }  
    
  my $ret;
  $hash->{sentMsgResult} = "WAITING";
  
  $hash->{sentMsgResult} .= " retry $retryCount" if ( $retryCount > 0 );
  
  $hash->{sentMsgId} = "";

  my $peer;
  ( $peer, $peers ) = split( " ", $peers, 2 ); 
  
  # handle addtl peers specified (will be queued since WAITING is set already) 
  if ( defined( $peers ) ) {
    # ignore return, since it is only queued
    # remove msgid from options and also replyid reset
    my $sepoptions = $options;
    $sepoptions =~ s/-msgid-//;
    TelegramBot_SendIt( $hash, $peers, $msg, $addPar, $isMedia, undef, $sepoptions );
  }
  
  Log3 $name, 5, "TelegramBot_SendIt $name: try to send message to :$peer: -:".
      TelegramBot_MsgForLog($msg, ($isMedia<0) ).": - add :".(defined($addPar)?$addPar:"<undef>").
      ": - replyid :".(defined($replyid)?$replyid:"<undef>").
      ":".":    options :".$options.":";

    # trim and convert spaces in peer to underline 
  $peer = 0 if ( ! $peer ); # ensure peer is defined
  my $peer2 = (! $peer )?$peer:TelegramBot_GetIdForPeer( $hash, $peer );
  
#  Debug "peer :$peer:    peer2 :$peer2:";

  if ( ! defined( $peer2 ) ) {
    $ret = "FAILED peer not found :$peer:";
#    Log3 $name, 2, "TelegramBot_SendIt $name: failed with :".$ret.":";
    $peer2 = "";
  }
  
  $hash->{sentMsgPeer} = TelegramBot_GetFullnameForContact( $hash, $peer2 );
  $hash->{sentMsgPeerId} = $peer2;
  $hash->{sentMsgOptions} = $options;
  
  # init param hash
  $hash->{HU_DO_PARAMS}->{hash} = $hash;
  $hash->{HU_DO_PARAMS}->{header} = $TelegramBot_header;
  delete( $hash->{HU_DO_PARAMS}->{args} );
  delete( $hash->{HU_DO_PARAMS}->{boundary} );

  
  my $timeout =   AttrVal($name,'cmdTimeout',30);
  $hash->{HU_DO_PARAMS}->{timeout} = $timeout;

  $hash->{HU_DO_PARAMS}->{loglevel} = 4;
#  Debug option - switch this on for detailed logging of httputils
#  $hash->{HU_DO_PARAMS}->{loglevel} = 1;

# handle data creation only if no error so far
  if ( ! defined( $ret ) ) {

    # add chat / user id (no file) --> this will also do init
    $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "chat_id", undef, $peer2, 0 ) if ( $peer );

    if ( ( $isMedia == 0 ) || ( $isMedia == 10 ) || ( $isMedia == 20 ) ) {
      if ( $isMedia == 0 ) {
        $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendMessage";
      } elsif ( $isMedia == 20 ) {
        $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."deleteMessage";
        $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "message_id", undef, $replyid, 0 ) if ( ! defined( $ret ) );
        $replyid = undef;
      } else {
        $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."editMessageText";
        $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "message_id", undef, $replyid, 0 ) if ( ! defined( $ret ) );
        $replyid = undef;
      }
      
  # DEBUG OPTION
  #  $hash->{HU_DO_PARAMS}->{url} = "http://requestb.in/1ibjnj81" if ( $msg =~ /^ZZZ/ );

      my $parseMode = TelegramBot_AttrNum($name,"parseModeSend","0" );
      if ( $parseMode == 1 ) {
        $parseMode = "Markdown";
      } elsif ( $parseMode == 2 ) {
        $parseMode = "HTML";
      } elsif ( $parseMode == 3 ) {
        $parseMode = 0;
        if ( $msg =~ /^markdown(.*)$/i ) {
          $msg = $1;
          $parseMode = "Markdown";
        } elsif ( $msg =~ /^HTML(.*)$/i ) {
          $msg = $1;
          $parseMode = "HTML";
        }
      } else {
        $parseMode = 0;
      }
      Log3 $name, 4, "TelegramBot_SendIt parseMode $parseMode";
    
      if ( length($msg) > 1000 ) {
        $hash->{sentMsgText} = substr($msg,0, 1000)."...";
       } else {
        $hash->{sentMsgText} = $msg;
       }
      $msg =~ s/(?<![\\])\\n/\x0A/g;
      $msg =~ s/(?<![\\])\\t/\x09/g;

      # add msg (no file)
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "text", undef, $msg, 0 ) if ( ! defined( $ret ) );

      # add parseMode
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "parse_mode", undef, $parseMode, 0 ) if ( ( ! defined( $ret ) ) && ( $parseMode ) );

      # add disable_web_page_preview 	
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "disable_web_page_preview", undef, JSON::true, 0 ) 
            if ( ( ! defined( $ret ) ) && ( ! AttrVal($name,'webPagePreview',1) ) );

      
    } elsif ( $isMedia == 11 ) {
      # Location send    
      $hash->{sentMsgText} = "Location: ".TelegramBot_MsgForLog($msg, ($isMedia<0) ).
          (( defined( $addPar ) )?" - ".$addPar:"");

      $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendLocation";

      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "latitude", undef, $msg, 0 ) if ( ! defined( $ret ) );

      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "longitude", undef, $addPar, 0 ) if ( ! defined( $ret ) );
      $addPar = undef;
      
    } elsif ( $isMedia == 12 ) {
      # answer Inline query
      $hash->{sentMsgText} = "AnswerInline: ".TelegramBot_MsgForLog($msg, ($isMedia<0) ).
          (( defined( $addPar ) )?" - ".$addPar:"");

      $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."answerCallbackQuery";
      
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "callback_query_id", undef, $addPar, 0 ) if ( ! defined( $ret ) );
      $addPar = undef;

      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "text", undef, $msg, 0 ) if ( ( ! defined( $ret ) ) && ( $msg ) );
      
    } elsif ( abs($isMedia) == 1 ) {
      # Photo send    
      $hash->{sentMsgText} = "Image: ".TelegramBot_MsgForLog($msg, ($isMedia<0) ).
          (( defined( $addPar ) )?" - ".$addPar:"");

      $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendPhoto";

      # add caption
      if ( defined( $addPar ) ) {
        $addPar =~ s/(?<![\\])\\n/\x0A/g;
        $addPar =~ s/(?<![\\])\\t/\x09/g;

        $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "caption", undef, $addPar, 0 ) if ( ! defined( $ret ) );
        $addPar = undef;
      }
      
      # add msg or file or stream
        Log3 $name, 4, "TelegramBot_SendIt $name: Filename for image file :".
      TelegramBot_MsgForLog($msg, ($isMedia<0) ).":";
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "photo", undef, $msg, $isMedia ) if ( ! defined( $ret ) );
      
    }  elsif ( $isMedia == 2 ) {
      # Voicemsg send    == 2
      $hash->{sentMsgText} = "Voice: $msg";

      $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendVoice";

      # add msg or file or stream
      Log3 $name, 4, "TelegramBot_SendIt $name: Filename for document file :".
      TelegramBot_MsgForLog($msg, ($isMedia<0) ).":";
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "voice", undef, $msg, 1 ) if ( ! defined( $ret ) );
    } else {
      # Media send    == 3
      $hash->{sentMsgText} = "Document: ".TelegramBot_MsgForLog($msg, ($isMedia<0) );

      $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendDocument";

      # add msg (no file)
      Log3 $name, 4, "TelegramBot_SendIt $name: Filename for document file :$msg:";
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "document", undef, $msg, $isMedia ) if ( ! defined( $ret ) );
    }

    if ( defined( $replyid ) ) {
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "reply_to_message_id", undef, $replyid, 0 ) if ( ! defined( $ret ) );
    }

    if ( defined( $addPar ) ) {
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "reply_markup", undef, $addPar, 0 ) if ( ! defined( $ret ) );
    } elsif ( $options =~ /-force_reply-/ ) {
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "reply_markup", undef, "{\"force_reply\":true}", 0 ) if ( ! defined( $ret ) );
    }
    
    if ( $options =~ /-silent-/ ) {
      $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, "disable_notification", undef, "true", 0 ) if ( ! defined( $ret ) );
    }


    # finalize multipart 
    $ret = TelegramBot_AddMultipart($hash, $hash->{HU_DO_PARAMS}, undef, undef, undef, 0 ) if ( ! defined( $ret ) );

  }
  
  if ( defined( $ret ) ) {
    Log3 $name, 3, "TelegramBot_SendIt $name: Failed with :$ret:";
    TelegramBot_Callback( $hash->{HU_DO_PARAMS}, $ret, "");

  } else {
    $hash->{HU_DO_PARAMS}->{args} = \@args;
    
    # if utf8 is set on string this will lead to length wrongly calculated in HTTPUtils (char instead of bytes) for some installations
    if ( ( AttrVal($name,'utf8Special',0) ) && ( utf8::is_utf8($hash->{HU_DO_PARAMS}->{data}) ) ) {
      Log3 $name, 4, "TelegramBot_SendIt $name: utf8 encoding for data in message ";
      utf8::downgrade($hash->{HU_DO_PARAMS}->{data}); 
#      $hash->{HU_DO_PARAMS}->{data} = encode_utf8($hash->{HU_DO_PARAMS}->{data});
    }
    
    Log3 $name, 4, "TelegramBot_SendIt $name: timeout for sent :".$hash->{HU_DO_PARAMS}->{timeout}.": ";
    HttpUtils_NonblockingGet( $hash->{HU_DO_PARAMS} );

  }
  
  return $ret;
}

#####################################
# INTERNAL: Build a multipart form data in a given hash
# Parameter
#   hash (device hash)
#   params (hash for building up the data)
#   paramname --> if not sepecifed / undef - multipart will be finished
#   header for multipart
#   content 
#   isFile to specify if content is providing a file to be read as content
#     
#   > returns string in case of error or undef
sub TelegramBot_AddMultipart($$$$$$)
{
  my ( $hash, $params, $parname, $parheader, $parcontent, $isMedia ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  # Check if boundary is defined
  if ( ! defined( $params->{boundary} ) ) {
    $params->{boundary} = "TelegramBot_boundary-x0123";
    $params->{header} .= "\r\nContent-Type: multipart/form-data; boundary=".$params->{boundary};
    $params->{method} = "POST";
    $params->{data} = "";
  }
  
  # ensure parheader is defined and add final header new lines
  $parheader = "" if ( ! defined( $parheader ) );
  $parheader .= "\r\n" if ( ( length($parheader) > 0 ) && ( $parheader !~ /\r\n$/ ) );

  # add content 
  my $finalcontent;
  if ( defined( $parname ) ) {
    $params->{data} .= "--".$params->{boundary}."\r\n";
    if ( $isMedia > 0) {
      # url decode filename
      $parcontent = uri_unescape($parcontent) if ( AttrVal($name,'filenameUrlEscape',0) );

      my $baseFilename =  basename($parcontent);
      $parheader = "Content-Disposition: form-data; name=\"".$parname."\"; filename=\"".$baseFilename."\"\r\n".$parheader."\r\n";

      return( "FAILED file :$parcontent: not found or empty" ) if ( ! -e $parcontent ) ;
      
      my $size = -s $parcontent;
      my $limit = AttrVal($name,'maxFileSize',10485760);
      return( "FAILED file :$parcontent: is too large for transfer (current limit: ".$limit."B)" ) if ( $size >  $limit ) ;
      
      $finalcontent = TelegramBot_BinaryFileRead( $hash, $parcontent );
      if ( $finalcontent eq "" ) {
        return( "FAILED file :$parcontent: not found or empty" );
      }
    } elsif ( $isMedia < 0) {
      my ( $im, $ext ) = TelegramBot_IdentifyStream( $hash, $parcontent );

      my $baseFilename =  "fhem.".$ext;

      $parheader = "Content-Disposition: form-data; name=\"".$parname."\"; filename=\"".$baseFilename."\"\r\n".$parheader."\r\n";
      $finalcontent = $parcontent;
    } else {
      $parheader = "Content-Disposition: form-data; name=\"".$parname."\"\r\n".$parheader."\r\n";
      $finalcontent = $parcontent;
    }
    $params->{data} .= $parheader.$finalcontent."\r\n";
    
  } else {
    return( "No content defined for multipart" ) if ( length( $params->{data} ) == 0 );
    $params->{data} .= "--".$params->{boundary}."--";     
  }

  return undef;
}


#####################################
# INTERNAL: Build a keyboard string for sendMessage
# Parameter
#   hash (device hash)
#   onetime/hide --> true means onetime / false means hide / undef means nothing
#   inline --> true/false
#   keys array of arrays for keyboard
#   > returns string in case of error or undef
sub TelegramBot_MakeKeyboard($$$@)
{
  my ( $hash, $onetime_hide, $inlinekb, @keys ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  my %par;
  
  if ( ( defined( $inlinekb ) ) && ( $inlinekb ) ) {
    # inline kb
    my @parKeys = ( );
    my $keytext;
    my $keydata;
    
    foreach my $aKeyRow (  @keys ) {
      my @parRow = ();
      foreach my $aKey (  @$aKeyRow ) {
        $keytext = $aKey;
        if ( $keytext =~ /^\s*(.*):([^:]+)\s*$/ ) {
          $keytext = $1;
          $keydata = $2;
        } else {
          $keydata = $keytext;
        }
        my %oneKey = ( "text" => $keytext, "callback_data" => $keydata );
        push( @parRow, \%oneKey );
      }
      push( @parKeys, \@parRow );
    }
    %par = ( "inline_keyboard" => \@parKeys  );
    
  } elsif ( ( defined( $onetime_hide ) ) && ( ! $onetime_hide ) ) {
    %par = ( "hide_keyboard" => JSON::true );
  } else {
    return $ret if ( ! @keys );
    %par = ( "one_time_keyboard" => (( ( defined( $onetime_hide ) ) && ( $onetime_hide ) )?JSON::true:JSON::true ) );
    $par{keyboard} = \@keys;
  }
  
  my $refkb = \%par;

  # encode keyboard with JSON
  my $json        = JSON->new->utf8->allow_nonref;
  eval {
    $ret = $json->utf8(0)->encode( $refkb );
  };
  Log3 $name, 2, "JSON encode() did fail with: ".(( $@ )?$@:"<unknown error>") if ( ! $ret );

  if ( $ret ) {
    Log3 $name, 4, "TelegramBot_MakeKeyboard $name: json :$ret: is utf8? ".(utf8::is_utf8($ret)?"yes":"no");

    if ( utf8::is_utf8($ret) ) {
      utf8::downgrade($ret); 
      Log3 $name, 4, "TelegramBot_MakeKeyboard $name: json downgraded :$ret: is utf8? ".(utf8::is_utf8($ret)?"yes":"no");
    }
  }
  
  return $ret;
}
  

#####################################
#  INTERNAL: _PollUpdate is called to set out a nonblocking http call for updates
#  if still polling return
#  if more than one fails happened --> wait instead of poll
#
#  2nd parameter set means do it once only not by regular update
sub TelegramBot_UpdatePoll($;$) 
{
  my ($hash, $doOnce) = @_;
  my $name = $hash->{NAME};
    
  Log3 $name, 5, "TelegramBot_UpdatePoll $name: called ";

  if ( $hash->{POLLING} ) {
    Log3 $name, 4, "TelegramBot_UpdatePoll $name: polling still running ";
    return ( ( $doOnce ) ? "Update polling still running" : undef );
  }

  # Get timeout from attribute 
  my $timeout =   AttrVal($name,'pollingTimeout',0);
  $timeout = 0 if ( AttrVal($name,'disable',0) );
  
  if ( $doOnce ) {
    $timeout = 0;
    
  } else {
  
    if ( $timeout == 0 ) {
      $hash->{STATE} = "Static";
      Log3 $name, 4, "TelegramBot_UpdatePoll $name: Polling timeout 0 - no polling ";
      return;
    }
    
    if ( $hash->{FAILS} > 1 ) {
      # more than one fail in a row wait until next poll
      $hash->{OLDFAILS} = $hash->{FAILS};
      $hash->{FAILS} = 0;
      my $wait = $hash->{OLDFAILS}+2;
      Log3 $name, 5, "TelegramBot_UpdatePoll $name: got fails :".$hash->{OLDFAILS}.": wait ".$wait." seconds";
      InternalTimer(gettimeofday()+$wait, "TelegramBot_UpdatePoll", $hash,0); 
      return;
    } elsif ( defined($hash->{OLDFAILS}) ) {
      # oldfails defined means 
      $hash->{FAILS} = $hash->{OLDFAILS};
      delete $hash->{OLDFAILS};
    }
  }
    
  Log3 $name, 5, "TelegramBot_UpdatePoll $name: - Initiate non blocking polling - ".(defined($hash->{HU_UPD_PARAMS}->{callback})?"With callback set":"no callback");

  # get next offset id
  my $offset = $hash->{offset_id};
  $offset = 0 if ( ! defined($offset) );
  
  # build url 
  my $url =  TelegramBot_getBaseURL($hash)."getUpdates?offset=".$offset. ( ($timeout!=0)? "&limit=5&timeout=".$timeout : "" );

  $hash->{HU_UPD_PARAMS}->{url} = $url;
  $hash->{HU_UPD_PARAMS}->{timeout} = $timeout+$timeout+5;
  $hash->{HU_UPD_PARAMS}->{hash} = $hash;
  $hash->{HU_UPD_PARAMS}->{offset} = $offset;

  $hash->{STATE} = "Polling";

  $hash->{HU_UPD_PARAMS}->{loglevel} = 4;
#  Debug option - switch this on for detailed logging of httputils
#  $hash->{HU_UPD_PARAMS}->{loglevel} = 1;
  
  $hash->{POLLING} = ( ( defined( $hash->{OLD_POLLING} ) )?$hash->{OLD_POLLING}:1 );
  Log3 $name, 4, "TelegramBot_UpdatePoll $name: initiate polling with nonblockingGet with ".$timeout."s";
  HttpUtils_NonblockingGet( $hash->{HU_UPD_PARAMS} ); 

  Log3 $name, 5, "TelegramBot_UpdatePoll $name: - Ende > next polling started";
}


#####################################
#  INTERNAL: Called to retry a send operation after wait time
#   Gets the do params
sub TelegramBot_RetrySend($)
{
  my ( $param ) = @_;
  my $hash= $param->{hash};
  my $name = $hash->{NAME};


  my $ref = $param->{args};
  Log3 $name, 4, "TelegramBot_Retrysend $name: reply ".(defined( @$ref[4] )?@$ref[4]:"<undef>")." retry ".@$ref[$TelegramBot_arg_retrycnt]." :@$ref[0]: -:@$ref[1]: ";
  TelegramBot_SendIt( $hash, @$ref[0], @$ref[1], @$ref[2], @$ref[3], @$ref[4], @$ref[5], @$ref[6] );
  
}



sub TelegramBot_Deepencode
{
    my @result;

    my $name = shift( @_ );

#    Debug "TelegramBot_Deepencode with :".(@_).":";

    for (@_) {
        my $reftype= ref $_;
        if( $reftype eq "ARRAY" ) {
            Log3 $name, 5, "TelegramBot_Deepencode $name: found an ARRAY";
            push @result, [ TelegramBot_Deepencode($name, @$_) ];
        }
        elsif( $reftype eq "HASH" ) {
            my %h;
            @h{keys %$_}= TelegramBot_Deepencode($name, values %$_);
            Log3 $name, 5, "TelegramBot_Deepencode $name: found a HASH";
            push @result, \%h;
        }
        else {
            my $us = $_ ;
            if ( utf8::is_utf8($us) ) {
              $us = encode_utf8( $_ );
            }
            Log3 $name, 5, "TelegramBot_Deepencode $name: encoded a String from :".$_.": to :".$us.":";
            push @result, $us;
        }
    }
    return @_ == 1 ? $result[0] : @result; 

}
      
  
#####################################
#  INTERNAL: Callback is the callback for any nonblocking call to the bot api (e.g. the long poll on update call)
#   3 params are defined for callbacks
#     param-hash
#     err
#     data (returned from url call)
# empty string used instead of undef for no return/err value
sub TelegramBot_Callback($$$)
{
  my ( $param, $err, $data ) = @_;
  my $hash= $param->{hash};
  my $name = $hash->{NAME};

  my $ret;
  my $doRetry = 1;   # will be set to zero if error is found that should lead to no retry
  my $result;
  my $msgId;
  my $ll = 5;

  if ( defined( $param->{isPolling} ) ) {
    $hash->{OLD_POLLING} = ( ( defined( $hash->{POLLING} ) )?$hash->{POLLING}:0 ) + 1;
    $hash->{OLD_POLLING} = 1 if ( $hash->{OLD_POLLING} > 255 );
    
    $hash->{POLLING} = 0 if ( $hash->{POLLING} != -1 ) ;
  }
  
  Log3 $name, 5, "TelegramBot_Callback $name: called from ".(( defined( $param->{isPolling} ) )?"Polling":"SendIt");

  # Check for timeout   "read from $hash->{addr} timed out"
  if ( $err =~ /^read from.*timed out$/ ) {
    $ret = "NonBlockingGet timed out on read from ".($param->{hideurl}?"<hidden>":$param->{url})." after ".$param->{timeout}."s";
  } elsif ( $err ne "" ) {
    $ret = "NonBlockingGet: returned $err";
  } elsif ( $data ne "" ) {
    # assuming empty data without err means timeout
    Log3 $name, 5, "TelegramBot_Callback $name: data returned :$data:";
    my $jo;
 

    eval {
#       $data = encode( 'latin1', $data );
       $data = encode_utf8( $data );
#       $data = decode_utf8( $data );
# Debug "-----AFTER------\n".$data."\n-------UC=".${^UNICODE} ."-----\n";
#       $jo = decode_json( $data );
       my $json = JSON->new->allow_nonref;
       $jo = $json->decode(Encode::encode_utf8($data));
       $jo = TelegramBot_Deepencode( $name, $jo );
    };
 
    Log3 $name, 5, "TelegramBot_Callback $name: after encoding";

###################### 
 
    if ( $@ ) {
      $ret = "Callback returned no valid JSON: $@ ";
    } elsif ( ! defined( $jo ) ) {
      $ret = "Callback returned no valid JSON !";
    } elsif ( ! $jo->{ok} ) {
      if ( defined( $jo->{description} ) ) {
        $ret = "Callback returned error :".$jo->{description}.":";
        $doRetry = 0 if ($jo->{description} =~ /^Bad Request\:/);
#        Debug "description :".$jo->{description}.":";
        $doRetry = 0 if ($jo->{description} =~ /^Unauthorized/);
      } else {
        $ret = "Callback returned error without description";
      }
    } else {
      if ( defined( $jo->{result} ) ) {
        $result = $jo->{result};
      } else {
        $ret = "Callback returned no result";
      }
    }
  }

  
  if ( defined( $param->{isPolling} ) ) {
    Log3 $name, 5, "TelegramBot_Callback $name: polling returned result? ".((defined($result))?scalar(@$result):"<undef>");
  
    # Polling means result must be analyzed
    if ( defined($result) ) {
       # handle result
      $hash->{FAILS} = 0;    # succesful UpdatePoll reset fails
      Log3 $name, 5, "UpdatePoll $name: number of results ".scalar(@$result) ;
      foreach my $update ( @$result ) {
        Log3 $name, 5, "UpdatePoll $name: parse result ";
        if ( defined( $update->{message} ) ) {
          
          $ret = TelegramBot_ParseMsg( $hash, $update->{update_id}, $update->{message} );
        } elsif ( defined( $update->{callback_query} ) ) {
          
          $ret = TelegramBot_ParseCallbackQuery( $hash, $update->{update_id}, $update->{callback_query} );
        } else {
          Log3 $name, 3, "UpdatePoll $name: inline_query  id:".$update->{inline_query}->{id}.
                ":  query:".$update->{inline_query}->{query}.":" if ( defined( $update->{inline_query} ) );
          Log3 $name, 3, "UpdatePoll $name: chosen_inline_result  id:".$update->{chosen_inline_result}->{result_id}.":".
                "   inline id:".$update->{chosen_inline_result}->{inline_message_id}.":". 
                "   query:".$update->{chosen_inline_result}->{query}.":" 
              if ( defined( $update->{chosen_inline_result} ) );
          Log3 $name, 3, "UpdatePoll $name: callback_query  id:".$update->{callback_query}->{id}.":".
                "   inline id:".$update->{callback_query}->{inline_message_id}.":". 
                "   data:".$update->{callback_query}->{data}.":" 
              if ( defined( $update->{callback_query} ) );
        }
        if ( defined( $ret ) ) {
          last;
        } else {
          $hash->{offset_id} = $update->{update_id}+1;
        }
      }
    }
    
    # get timestamps and verbose
    my $now = FmtDateTime( gettimeofday() ); 
    my $tst = ReadingsTimestamp( $name, "PollingErrCount", "1970-01-01 01:00:00" );
    my $pv = AttrVal( $name, "pollingVerbose", "1_Digest" );

    # get current error cnt
    my $cnt = ReadingsVal( $name, "PollingErrCount", "0" );

    # flag if log needs to be written
    my $doLog = 0;
    
    # Error to be converted to Reading for Poll
    if ( defined( $ret ) ) {
      # something went wrong increase fails
      $hash->{FAILS} += 1;

      # Put last error into reading
      readingsSingleUpdate($hash, "PollingLastError", $ret , 1); 
      
      if ( substr($now,0,10) eq substr($tst,0,10) ) {
        # Still same date just increment
        $cnt += 1;
        readingsSingleUpdate($hash, "PollingErrCount", $cnt, 1); 
      } else {
        # Write digest in log on next date
        $doLog = ( $pv ne "3_None" );
        readingsSingleUpdate($hash, "PollingErrCount", 1, 1); 
      }
      
    } elsif ( substr($now,0,10) ne substr($tst,0,10) ) {
      readingsSingleUpdate($hash, "PollingErrCount", 0, 1);
      $doLog = ( $pv ne "3_None" );
    }

    # log level is 2 on error if not digest is selected
    $ll =( ( $pv eq "2_Log" )?2:4 );

    # log digest if flag set
    Log3 $name, 3, "TelegramBot_Callback $name: Digest: Number of poll failures on ".substr($tst,0,10)." is :$cnt:" if ( $doLog );


    # start next poll or wait
    TelegramBot_UpdatePoll($hash); 


  } else {
    # Non Polling means: get msgid, reset the params and set loglevel
    $hash->{HU_DO_PARAMS}->{data} = "";
    $ll = 3 if ( defined( $ret ) );
    $msgId = $result->{message_id} if ( ( defined($result) ) && ( ref($result) eq "HASH" ) );
       
  }

  $ret = "SUCCESS" if ( ! defined( $ret ) );
  Log3 $name, $ll, "TelegramBot_Callback $name: resulted in $ret from ".(( defined( $param->{isPolling} ) )?"Polling":"SendIt");

  if ( ! defined( $param->{isPolling} ) ) {
    $hash->{sentLastResult} = $ret;

    # handle retry
    # ret defined / args defined in params 
    if ( ( $ret ne  "SUCCESS" ) && ( $doRetry ) && ( defined( $param->{args} ) ) ) {
      my $wait = $param->{args}[$TelegramBot_arg_retrycnt];
      my $maxRetries =  AttrVal($name,'maxRetries',0);
      
      Log3 $name, 4, "TelegramBot_Callback $name: retry count so far $wait (max: $maxRetries) for msg ".
            $param->{args}[0]." : ".$param->{args}[1];
      
      if ( $wait <= $maxRetries ) {
        # calculate wait time 10s / 100s / 1000s ~ 17min / 10000s ~ 3h / 100000s ~ 30h
        $wait = 10**$wait;
        
        Log3 $name, 4, "TelegramBot_Callback $name: do retry ".$param->{args}[$TelegramBot_arg_retrycnt]." timer: $wait (ret: $ret) for msg ".
              $param->{args}[0]." : ".$param->{args}[1];

        # set timer
        InternalTimer(gettimeofday()+$wait, "TelegramBot_RetrySend", $param,0); 
        
        # finish
        return;
      }

      Log3 $name, 3, "TelegramBot_Callback $name: Reached max retries (ret: $ret) for msg ".$param->{args}[0]." : ".$param->{args}[1];
      
    } elsif ( ( $ret ne  "SUCCESS" ) && ( ! $doRetry ) ) {
      Log3 $name, 3, "TelegramBot_Callback $name: No retry for (ret: $ret) for msg ".$param->{args}[0]." : ".$param->{args}[1];
    }
    
    $hash->{sentMsgResult} = $ret;
    $hash->{sentMsgId} = ((defined($msgId))?$msgId:"");
    
    # Also set sentMsg Id and result in Readings
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "sentMsgResult", $ret);        
    readingsBulkUpdate($hash, "sentMsgId", ((defined($msgId))?$msgId:"") );        
    readingsBulkUpdate($hash, "sentMsgPeerId", ((defined($hash->{sentMsgPeerId}))?$hash->{sentMsgPeerId}:"") );        
    readingsEndUpdate($hash, 1);
    
    if ( scalar( @{ $hash->{sentQueue} } ) ) {
      my $ref = shift @{ $hash->{sentQueue} };
      Log3 $name, 5, "TelegramBot_Callback $name: handle queued send with :@$ref[0]: -:@$ref[1]: ";
      TelegramBot_SendIt( $hash, @$ref[0], @$ref[1], @$ref[2], @$ref[3], @$ref[4], @$ref[5], @$ref[6] );
    }
  }
  
  Log3 $name, 5, "TelegramBot_Callback $name: - Ende > Control back to FHEM";
}

#####################################
#  INTERNAL: _ParseMsg handle a message from the update call 
#   params are the hash, the updateid and the actual message
sub TelegramBot_ParseMsg($$$)
{
  my ( $hash, $uid, $message ) = @_;
  my $name = $hash->{NAME};

  my @contacts;
  
  my $ret;
  
  my $mid = $message->{message_id};
  
  my $from = $message->{from};
  my $mpeer = $from->{id};

  # ignore if unknown contacts shall be accepter
  if ( ( AttrVal($name,'allowUnknownContacts',1) == 0 ) && ( ! TelegramBot_IsKnownContact( $hash, $mpeer ) ) ) {
    my $mName = $from->{first_name};
    $mName .= " ".$from->{last_name} if ( defined($from->{last_name}) );
    Log3 $name, 3, "TelegramBot $name: Message from unknown Contact (id:$mpeer: name:$mName:) blocked";
    
    return $ret;
  }

  # check peers beside from only contact (shared contact) and new_chat_participant are checked
  push( @contacts, $from );

  my $chatId = "";
  my $chat = $message->{chat};
  if ( ( defined( $chat ) ) && ( $chat->{type} ne "private" ) ) {
    push( @contacts, $chat );
    $chatId = $chat->{id};
  }

  my $user = $message->{new_chat_participant};
  if ( defined( $user ) ) {
    push( @contacts, $user );
  }

  # get reply message id
  my $replyId;
  my $replyPart = $message->{reply_to_message};
  if ( defined( $replyPart ) ) {
    $replyId = $replyPart->{message_id};
  }
  
  # mtext contains the text of the message (if empty no further handling)
  my ( $mtext, $mfileid );

  if ( defined( $message->{text} ) ) {
    # handle text message
    $mtext = $message->{text};
    Log3 $name, 4, "TelegramBot_ParseMsg $name: Textmessage";

  } elsif ( defined( $message->{audio} ) ) {
    # handle audio message
    my $subtype = $message->{audio};
    $mtext = "received audio ";

    $mfileid = $subtype->{file_id};

    $mtext .= " # Performer: ".$subtype->{performer} if ( defined( $subtype->{performer} ) );
    $mtext .= " # Title: ".$subtype->{title} if ( defined( $subtype->{title} ) );
    $mtext .= " # Mime: ".$subtype->{mime_type} if ( defined( $subtype->{mime_type} ) );
    $mtext .= " # Size: ".$subtype->{file_size} if ( defined( $subtype->{file_size} ) );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: audio fileid: $mfileid";

  } elsif ( defined( $message->{document} ) ) {
    # handle document message
    my $subtype = $message->{document};
    $mtext = "received document ";

    $mfileid = $subtype->{file_id};

    $mtext .= " # Caption: ".$message->{caption} if ( defined( $message->{caption} ) );
    $mtext .= " # Name: ".$subtype->{file_name} if ( defined( $subtype->{file_name} ) );
    $mtext .= " # Mime: ".$subtype->{mime_type} if ( defined( $subtype->{mime_type} ) );
    $mtext .= " # Size: ".$subtype->{file_size} if ( defined( $subtype->{file_size} ) );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: document fileid: $mfileid ";

  } elsif ( defined( $message->{voice} ) ) {
    # handle voice message
    my $subtype = $message->{voice};
    $mtext = "received voice ";

    $mfileid = $subtype->{file_id};

    $mtext .= " # Mime: ".$subtype->{mime_type} if ( defined( $subtype->{mime_type} ) );
    $mtext .= " # Size: ".$subtype->{file_size} if ( defined( $subtype->{file_size} ) );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: voice fileid: $mfileid";

  } elsif ( defined( $message->{video} ) ) {
    # handle video message
    my $subtype = $message->{video};
    $mtext = "received video ";

    $mfileid = $subtype->{file_id};

    $mtext .= " # Caption: ".$message->{caption} if ( defined( $message->{caption} ) );
    $mtext .= " # Mime: ".$subtype->{mime_type} if ( defined( $subtype->{mime_type} ) );
    $mtext .= " # Size: ".$subtype->{file_size} if ( defined( $subtype->{file_size} ) );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: video fileid: $mfileid";

  } elsif ( defined( $message->{photo} ) ) {
    # handle photo message
    # photos are always an array with (hopefully) the biggest size last in the array
    my $photolist = $message->{photo};
    
    if ( scalar(@$photolist) > 0 ) {
      my $subtype = $$photolist[scalar(@$photolist)-1] ;
      $mtext = "received photo ";

      $mfileid = $subtype->{file_id};

      $mtext .= " # Caption: ".$message->{caption} if ( defined( $message->{caption} ) );
      $mtext .= " # Mime: ".$subtype->{mime_type} if ( defined( $subtype->{mime_type} ) );
      $mtext .= " # Size: ".$subtype->{file_size} if ( defined( $subtype->{file_size} ) );
      Log3 $name, 4, "TelegramBot_ParseMsg $name: photo fileid: $mfileid";
    }
  } elsif ( defined( $message->{venue} ) ) {
    # handle location type message
    my $ven = $message->{venue};
    my $loc = $ven->{location};
    
    $mtext = "received venue ";

    $mtext .= " # latitude: ".$loc->{latitude}." # longitude: ".$loc->{longitude};
    $mtext .= " # title: ".$ven->{title}." # address: ".$ven->{address};
    
# urls will be discarded in fhemweb    $mtext .= "\n# url: <a href=\"http://maps.google.com/?q=loc:".$loc->{latitude}.",".$loc->{longitude}."\">maplink</a>";
    
    Log3 $name, 4, "TelegramBot_ParseMsg $name: location received: latitude: ".$loc->{latitude}." longitude: ".$loc->{longitude};;
  } elsif ( defined( $message->{location} ) ) {
    # handle location type message
    my $loc = $message->{location};
    
    $mtext = "received location ";

    $mtext .= " # latitude: ".$loc->{latitude}." # longitude: ".$loc->{longitude};
    
# urls will be discarded in fhemweb    $mtext .= "\n# url: <a href=\"http://maps.google.com/?q=loc:".$loc->{latitude}.",".$loc->{longitude}."\">maplink</a>";
    
    Log3 $name, 4, "TelegramBot_ParseMsg $name: location received: latitude: ".$loc->{latitude}." longitude: ".$loc->{longitude};;
  }


  if ( defined( $mtext ) ) {
    Log3 $name, 4, "TelegramBot_ParseMsg $name: text   :$mtext:";

    my $mpeernorm = $mpeer;
    $mpeernorm =~ s/^\s+|\s+$//g;
    $mpeernorm =~ s/ /_/g;

    my $mchatnorm = "";
    $mchatnorm = $chatId if ( AttrVal($name,'cmdRespondChat',1) == 1 ); 

    #    Log3 $name, 5, "TelegramBot_ParseMsg $name: Found message $mid from $mpeer :$mtext:";

    # contacts handled separately since readings are updated in here
    TelegramBot_ContactUpdate($hash, @contacts) if ( scalar(@contacts) > 0 );
    
    readingsBeginUpdate($hash);

    readingsBulkUpdate($hash, "prevMsgId", $hash->{READINGS}{msgId}{VAL});        
    readingsBulkUpdate($hash, "prevMsgPeer", $hash->{READINGS}{msgPeer}{VAL});        
    readingsBulkUpdate($hash, "prevMsgPeerId", $hash->{READINGS}{msgPeerId}{VAL});        
    readingsBulkUpdate($hash, "prevMsgChat", $hash->{READINGS}{msgChat}{VAL});        
    readingsBulkUpdate($hash, "prevMsgText", $hash->{READINGS}{msgText}{VAL});        
    readingsBulkUpdate($hash, "prevMsgFileId", $hash->{READINGS}{msgFileId}{VAL});        
    readingsBulkUpdate($hash, "prevMsgReplyMsgId", $hash->{READINGS}{msgReplyMsgId}{VAL});        

    readingsEndUpdate($hash, 0);
    
    readingsBeginUpdate($hash);

    readingsBulkUpdate($hash, "msgId", $mid);        
    readingsBulkUpdate($hash, "msgPeer", TelegramBot_GetFullnameForContact( $hash, $mpeernorm ));        
    readingsBulkUpdate($hash, "msgPeerId", $mpeernorm);        
    readingsBulkUpdate($hash, "msgChat", TelegramBot_GetFullnameForContact( $hash, ((!$chatId)?$mpeernorm:$chatId) ) );        
    readingsBulkUpdate($hash, "msgChatId", ((!$chatId)?$mpeernorm:$chatId) );        
    readingsBulkUpdate($hash, "msgText", $mtext);
    readingsBulkUpdate($hash, "msgReplyMsgId", (defined($replyId)?$replyId:""));        

    readingsBulkUpdate($hash, "msgFileId", ( ( defined( $mfileid ) ) ? $mfileid : "" ) );        

    readingsEndUpdate($hash, 1);
    
    # COMMAND Handling (only if no fileid found
    Telegram_HandleCommandInMessages( $hash, $mpeernorm, $mchatnorm, $mtext, undef, 0 ) if ( ! defined( $mfileid ) );
   
  } elsif ( scalar(@contacts) > 0 )  {
    # will also update reading
    TelegramBot_ContactUpdate( $hash, @contacts );

    Log3 $name, 5, "TelegramBot_ParseMsg $name: Found message $mid from $mpeer without text/media but with contacts";

  } else {
    Log3 $name, 5, "TelegramBot_ParseMsg $name: Found message $mid from $mpeer without text/media";
  }
  
  return $ret;
}


#####################################
#  INTERNAL: _ParseCallbackQuery handle the callback of a query provide as 
#   params are the hash, the updateid and the actual message
sub TelegramBot_ParseCallbackQuery($$$)
{
  my ( $hash, $uid, $callback ) = @_;
  my $name = $hash->{NAME};

  my @contacts;
  
  my $ret;
  
  my $qid = $callback->{id};
  
  my $from = $callback->{from};
  my $mpeer = $from->{id};
  
  # get reply message id
  my $replyId;
  my $chatId;
  my $replyPart = $callback->{message};
  if ( defined( $replyPart ) ) {
    $replyId = $replyPart->{message_id};
    my $chat = $replyPart->{chat};
    if ( ( defined( $chat ) ) && ( $chat->{type} ne "private" ) ) {
      $chatId = $chat->{id};
    }
  }
  
  my $imid = $callback->{inline_message_id};
  my $chat= $callback->{chat_instance};
#  Debug "Chat :".$chat.":";
  
  my $data = $callback->{data};

  my $mtext = "Callback for inline query id: $qid  from : $mpeer :  data : ".(defined($data)?$data:"<undef>");

  # ignore if unknown contacts shall be accepter
  if ( ( AttrVal($name,'allowUnknownContacts',1) == 0 ) && ( ! TelegramBot_IsKnownContact( $hash, $mpeer ) ) ) {
    my $mName = $from->{first_name};
    $mName .= " ".$from->{last_name} if ( defined($from->{last_name}) );
    Log3 $name, 3, "TelegramBot $name: Message from unknown Contact (id:$mpeer: name:$mName:) blocked";
    
    return $ret;
  }

  my $mpeernorm = $mpeer;
  $mpeernorm =~ s/^\s+|\s+$//g;
  $mpeernorm =~ s/ /_/g;
  
  # check peers beside from only contact (shared contact) and new_chat_participant are checked
  push( @contacts, $from );

  my $answerData = "";

  if ( TelegramBot_checkAllowedPeer( $hash, $mpeernorm, $mtext ) ) {

    Log3 $name, 4, "TelegramBot_ParseCallback $name: ".$mtext;

    # contacts handled separately since readings are updated in here
    TelegramBot_ContactUpdate($hash, @contacts) if ( scalar(@contacts) > 0 );
    
    readingsBeginUpdate($hash);

    readingsBulkUpdate($hash, "queryID", $qid);        
    readingsBulkUpdate($hash, "queryPeer", TelegramBot_GetFullnameForContact( $hash, $mpeernorm ));        
    readingsBulkUpdate($hash, "queryPeerId", $mpeernorm);        

    readingsBulkUpdate($hash, "queryData", ( ( defined( $data ) ) ? $data : "" ) );        

    readingsBulkUpdate($hash, "queryReplyMsgId", ( ( defined( $replyId ) ) ? $replyId : "" ) );        

    readingsEndUpdate($hash, 1);
    
    $answerData = AttrVal($name,'queryAnswerText',undef); 
    
    # special handling for TBot_List
    if ( defined( $data ) ) {
      if ( $data =~ /^TBL_.+/ ) {
        # TBot_List has always prefix "TBL_"
        my @ltbots = devspec2array( "TYPE=TBot_List" );
        my $ltbotresult;
        foreach my $ltbot ( @ltbots ) {
          $ltbotresult = fhem( "get $ltbot queryAnswer $name $mpeernorm $data", 1 );
          if ( defined( $ltbotresult ) ) {
            $answerData = $ltbotresult;
            last;
          }
        }
      } elsif ( $data =~ /^TBOT_FAVORITE_(.+)$/ ) {
        # Telegrambot has always prefix "TBOT_"
        # ??? favorites inline
        my $favpart = $1;
        
        my $fcmd = AttrVal($name,'cmdFavorites',undef);
        if ( $fcmd ) {
          if ( $favpart =~ /^-[0-9]+$/ ) {
            $fcmd .= " $favpart-";
          } elsif ( $favpart =~ /^[0-9]+$/ ) {
            $fcmd .= " $favpart";
          } elsif ( $favpart =~ /^MENU$/ ) {
          } else {
            # assume cancel in all other cases
            $fcmd .= " cancel";
          }
          # where to get chat id from ?
          Log3 $name, 4, "TelegramBot_ParseCallback $name: REPLYMID: $replyId";
          Telegram_HandleCommandInMessages( $hash, $mpeernorm, $chatId, $fcmd, $replyId, 1 );
        }
      }    
    }
  } 
  
  # sent answer if not undef 
  if ( defined( $answerData ) ) {
    $answerData = "" if ( ! $answerData  );
    if ( length( $answerData ) > 0 ) {
      my %dummy; 
      my ($err, @a) = ReplaceSetMagic(\%dummy, 0, ( $answerData ) );
      
      if ( $err ) {
        Log3 $name, 1, "TelegramBot_ParseCallback $name: parse answerData failed on ReplaceSetmagic with :$err: on  :$answerData:";
        $answerData = "";
      } else {
        $answerData = join(" ", @a);
        Log3 $name, 4, "TelegramBot_ParseCallback $name: parse answerData returned :$answerData:";
      } 
    }

    my $tmpRet = TelegramBot_SendIt( $hash, $mpeernorm, $answerData, $qid, 12, undef );
    Log3 $name, 1, "TelegramBot_ParseCallback $name: send answer failed with :$tmpRet: " if ( $tmpRet );
  }

  return $ret;
}


##############################################################################
##############################################################################
##
## Polling / Setup
##
##############################################################################
##############################################################################


######################################
#  make sure a reinitialization is triggered on next update
#  
sub TelegramBot_ResetPolling($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "TelegramBot_ResetPolling $name: called ";

  RemoveInternalTimer($hash);

  HttpUtils_Close( $hash->{HU_UPD_PARAMS} ); 
  HttpUtils_Close( $hash->{HU_DO_PARAMS} ); 
  
  $hash->{WAIT} = 0;
  $hash->{FAILS} = 0;

  # let all existing methods first run into block
  $hash->{POLLING} = -1;
  
  # wait some time before next polling is starting
  InternalTimer(gettimeofday()+30, "TelegramBot_RestartPolling", $hash,0); 

  Log3 $name, 4, "TelegramBot_ResetPolling $name: finished ";

}

  
######################################
#  make sure a reinitialization is triggered on next update
#  
sub TelegramBot_RestartPolling($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "TelegramBot_RestartPolling $name: called ";

  # Now polling can start
  $hash->{POLLING} = 0;

  # wait some time before next polling is starting
  TelegramBot_UpdatePoll($hash);

  Log3 $name, 4, "TelegramBot_RestartPolling $name: finished ";

}

  
######################################
#  make sure a reinitialization is triggered on next update
#  
sub TelegramBot_Setup($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "TelegramBot_Setup $name: called ";

  $hash->{me} = "<unknown>";
  $hash->{STATE} = "Undefined";

  $hash->{POLLING} = -1;
  $hash->{HU_UPD_PARAMS}->{callback} = \&TelegramBot_Callback;
  $hash->{HU_DO_PARAMS}->{callback} = \&TelegramBot_Callback;
 
  # Temp?? SNAME is required for allowed (normally set in TCPServerUtils)
  $hash->{SNAME} = $name;

  # Ensure queueing is not happening
  delete( $hash->{sentQueue} );
  delete( $hash->{sentMsgResult} );

  # remove timer for retry
  RemoveInternalTimer($hash->{HU_DO_PARAMS});
  
  $hash->{STATE} = "Defined";
  
  if ( ! TelegramBot_readToken($hash) ) {
    Log3 $name, 1, "TelegramBot_Setup $name: no valid API token found, please call \"set $name token <token>\" (once)";
    $hash->{STATE} = "NoValidToken";

  } else {
    # getMe as connectivity check and set internals accordingly
    my $url = TelegramBot_getBaseURL($hash)."getMe";
    my $meret = TelegramBot_DoUrlCommand( $hash, $url, 1 );   # ignore first error
    if ( ( ! defined($meret) ) || ( ref($meret) ne "HASH" ) ) {
      # retry on first failure
      $meret = TelegramBot_DoUrlCommand( $hash, $url );
    }

    if ( ( defined($meret) ) && ( ref($meret) eq "HASH" ) ) {
      $hash->{me} = TelegramBot_userObjectToString( $meret );
      $hash->{STATE} = "Setup";

    } else {
      $hash->{me} = "Failed - see log file for details";
      $hash->{STATE} = "Failed";
      $hash->{FAILS} = 1;
    }
  }
  
  my %hh = ();
  $hash->{inlinechats} = \%hh;
  
  TelegramBot_InternalContactsFromReading( $hash);

  TelegramBot_ResetPolling($hash);

  Log3 $name, 4, "TelegramBot_Setup $name: ended ";

}

##############################################################################
##############################################################################
##
## CONTACT handling
##
##############################################################################
##############################################################################



#####################################
# INTERNAL: get id for a peer
#   if only digits --> assume id
#   if start with @ --> assume username
#   if start with # --> assume groupname
#   else --> assume full name
sub TelegramBot_GetIdForPeer($$)
{
  my ($hash,$mpeer) = @_;

  TelegramBot_InternalContactsFromReading( $hash ) if ( ! defined( $hash->{Contacts} ) );

  my $id;
  
  if ( $mpeer =~ /^\-?[[:digit:]]+$/ ) {
    # check if id is in hash 
#    $id = $mpeer if ( defined( $hash->{Contacts}{$mpeer} ) );
    # Allow also sending to ids which are not in the contacts list
    $id = $mpeer;
  } elsif ( $mpeer =~ /^[@#].*$/ ) {
    foreach  my $mkey ( keys %{$hash->{Contacts}} ) {
      my @clist = split( /:/, $hash->{Contacts}{$mkey} );
      if ( (defined($clist[2])) && ( $clist[2] eq $mpeer ) ) {
        $id = $clist[0];
        last;
      }
    }
  } else {
    $mpeer =~ s/^\s+|\s+$//g;
    $mpeer =~ s/ /_/g;
    foreach  my $mkey ( keys %{$hash->{Contacts}} ) {
      my @clist = split( /:/, $hash->{Contacts}{$mkey} );
      if ( (defined($clist[1])) && ( $clist[1] eq $mpeer ) ) {
        $id = $clist[0];
        last;
      }
    }
  }  
  
  return $id
}
  


#####################################
# INTERNAL: get full name for contact id
sub TelegramBot_GetContactInfoForContact($$)
{
  my ($hash,$mcid) = @_;

  TelegramBot_InternalContactsFromReading( $hash ) if ( ! defined( $hash->{Contacts} ) );

  return ( $hash->{Contacts}{$mcid});
}
  
  
#####################################
# INTERNAL: get full name for contact id
sub TelegramBot_GetFullnameForContact($$)
{
  my ($hash,$mcid) = @_;

  my $contact = TelegramBot_GetContactInfoForContact( $hash,$mcid );
  my $ret = "";
  

  if ( defined( $contact ) ) {
      Log3 $hash->{NAME}, 4, "TelegramBot_GetFullnameForContact # Contacts is $contact:";
      my @clist = split( /:/, $contact );
      $ret = $clist[1];
      $ret = $clist[2] if ( ! $ret);
      $ret = $clist[0] if ( ! $ret);
      Log3 $hash->{NAME}, 4, "TelegramBot_GetFullnameForContact # name is $ret";
  } else {
    Log3 $hash->{NAME}, 4, "TelegramBot_GetFullnameForContact # Contacts is <undef>";
  }
  
  return $ret;
}
  
  
#####################################
# INTERNAL: get full name for a chat
sub TelegramBot_GetFullnameForChat($$)
{
  my ($hash,$mcid) = @_;
  my $ret = "";

  return $ret if ( ! $mcid );

  my $contact = TelegramBot_GetContactInfoForContact( $hash,$mcid );
  

  if ( defined( $contact ) ) {
      my @clist = split( /:/, $contact );
      $ret = $clist[0];
      $ret .= " (".$clist[2].")" if ( $clist[2] );
      Log3 $hash->{NAME}, 4, "TelegramBot_GetFullnameForChat # $mcid is $ret";
  }
  
  return $ret;
}
  
  
#####################################
# INTERNAL: check if a contact is already known in the internals->Contacts-hash
sub TelegramBot_IsKnownContact($$)
{
  my ($hash,$mpeer) = @_;

  TelegramBot_InternalContactsFromReading( $hash ) if ( ! defined( $hash->{Contacts} ) );

#  foreach my $key (keys $hash->{Contacts} )
#      {
#        Log3 $hash->{NAME}, 4, "Contact :$key: is  :".$hash->{Contacts}{$key}.":";
#      }

#  Debug "Is known ? ".( defined( $hash->{Contacts}{$mpeer} ) );
  return ( defined( $hash->{Contacts}{$mpeer} ) );
}

#####################################
# INTERNAL: calculate internals->contacts-hash from Readings->Contacts string
sub TelegramBot_CalcContactsHash($$)
{
  my ($hash, $cstr) = @_;

  # create a new hash
  if ( defined( $hash->{Contacts} ) ) {
    foreach my $key (keys %{$hash->{Contacts}} )
        {
            delete $hash->{Contacts}{$key};
        }
  } else {
    $hash->{Contacts} = {};
  }
  
  # split reading at separator 
  my @contactList = split(/\s+/, $cstr );
  
  # for each element - get id as hashtag and full contact as value
  foreach  my $contact ( @contactList ) {
    my ( $id, $cname, $cuser ) = split( ":", $contact, 3 );
    # add contact only if all three parts are there and either 2nd or 3rd part not empty and 3rd part either empty or start with @ or # and at least 3 chars
    # and id must be only digits
    $cuser = "" if ( ! defined( $cuser ) );
    $cname = "" if ( ! defined( $cname ) );
    
    Log3 $hash->{NAME}, 5, "Contact add :$contact:   :$id:  :$cname: :$cuser:";
  
    if ( ( length( $cname ) == 0 ) && ( length( $cuser ) == 0 ) ) {
      Log3 $hash->{NAME}, 5, "Contact add :$contact: has empty cname and cuser:";
      next;
    } elsif ( ( length( $cuser ) > 0 ) && ( length( $cuser ) < 3 ) ) {
      Log3 $hash->{NAME}, 5, "Contact add :$contact: cuser not long enough (3):";
      next;
    } elsif ( ( length( $cuser ) > 0 ) && ( $cuser !~ /^[\@#]/ ) ) {
      Log3 $hash->{NAME}, 5, "Contact add :$contact: cuser not matching start chars:";
      next;
    } elsif ( $id !~ /^\-?[[:digit:]]+$/ ) {
      Log3 $hash->{NAME}, 5, "Contact add :$contact: cid is not number or -number:";
      next;
    } else {
      $cname = TelegramBot_encodeContactString( $cname );

      $cuser = TelegramBot_encodeContactString( $cuser );
      
      $hash->{Contacts}{$id} = $id.":".$cname.":".$cuser;
    }
  }

}


#####################################
# INTERNAL: calculate internals->contacts-hash from Readings->Contacts string
sub TelegramBot_InternalContactsFromReading($)
{
  my ($hash) = @_;
  TelegramBot_CalcContactsHash( $hash, ReadingsVal($hash->{NAME},"Contacts","") );
}


#####################################
# INTERNAL: update contacts hash and change readings string (no return)
sub TelegramBot_ContactUpdate($@) {

  my ($hash, @contacts) = @_;

  my $newfound = ( int(@contacts) == 0 );

  my $oldContactString = ReadingsVal($hash->{NAME},"Contacts","");

  TelegramBot_InternalContactsFromReading( $hash ) if ( ! defined( $hash->{Contacts} ) );
  
  Log3 $hash->{NAME}, 4, "TelegramBot_ContactUpdate # Contacts in hash before :".scalar(keys %{$hash->{Contacts}}).":";

  foreach my $user ( @contacts ) {
    my $contactString = TelegramBot_userObjectToString( $user );

    # keep the username part of the new contatc for deleting old users with same username
    my $unamepart;
    my @clist = split( /:/, $contactString );
    if (defined($clist[2])) {
      $unamepart = $clist[2]; 
    }
    
    if ( ! defined( $hash->{Contacts}{$user->{id}} ) ) {
      Log3 $hash->{NAME}, 3, "TelegramBot_ContactUpdate new contact :".$contactString.":";
      next if ( AttrVal($hash->{NAME},'allowUnknownContacts',1) == 0 );
      $newfound = 1;
    } elsif ( $contactString ne $hash->{Contacts}{$user->{id}} ) {
      Log3 $hash->{NAME}, 3, "TelegramBot_ContactUpdate updated contact :".$contactString.":";
    }

    # remove all contacts with same username
    if ( defined( $unamepart ) ) {
      my $dupid = TelegramBot_GetIdForPeer( $hash, $unamepart );
      while ( $dupid ) {
         Log3 $hash->{NAME}, 3, "TelegramBot_ContactUpdate removed stale/duplicate contact ($dupid:$unamepart):".$hash->{Contacts}{$dupid}.":" if ( $dupid ne $user->{id} );
         delete( $hash->{Contacts}{$dupid} );
         $dupid = TelegramBot_GetIdForPeer( $hash, $unamepart );
      }
    }
    
    # set new contact data
    $hash->{Contacts}{$user->{id}} = $contactString;
  }

  Log3 $hash->{NAME}, 4, "TelegramBot_ContactUpdate # Contacts in hash after :".scalar(keys %{$hash->{Contacts}}).":";

  my $rc = "";
  foreach  my $key ( keys %{$hash->{Contacts}} )
    {
      if ( length($rc) > 0 ) {
        $rc .= " ".$hash->{Contacts}{$key};
      } else {
        $rc = $hash->{Contacts}{$key};
      }
    }

  # Do a readings change directly for contacts
  readingsSingleUpdate($hash, "Contacts", $rc , 1) if ( $rc ne $oldContactString );
    
  # save state file on new contact 
  if ( $newfound ) {
    WriteStatefile() if ( AttrVal($hash->{NAME}, 'saveStateOnContactChange', 1) ) ;
    Log3 $hash->{NAME}, 2, "TelegramBot_ContactUpdate Updated Contact list :".$rc.":";
  }
  
  return;    
}
  
#####################################
# INTERNAL: Convert TelegramBot user and chat object to string
sub TelegramBot_userObjectToString($) {

  my ( $user ) = @_;
  
  my $ret = $user->{id}.":";
  
  # user objects do not contain a type field / chat objects need to contain a type but only if type=group or type=supergroup it is really a group
  if ( ( defined( $user->{type} ) ) && ( ( $user->{type} eq "group" ) || ( $user->{type} eq "supergroup" ) ) ) {
    
    $ret .= ":";

    $ret .= "#".TelegramBot_encodeContactString($user->{title}) if ( defined( $user->{title} ) );

  } else {

    my $part = "";

    $part .= $user->{first_name} if ( defined( $user->{first_name} ) );
    $part .= " ".$user->{last_name} if ( defined( $user->{last_name} ) );

    $ret .= TelegramBot_encodeContactString($part).":";

    $ret .= "@".TelegramBot_encodeContactString($user->{username}) if ( defined( $user->{username} ) );
  }

  return $ret;
}

#####################################
# INTERNAL: Convert TelegramBot user and chat object to string
sub TelegramBot_encodeContactString($) {
  my ($str) = @_;

    $str =~ s/:/_/g;
    $str =~ s/^\s+|\s+$//g;
    $str =~ s/ /_/g;

  return $str;
}

#####################################
# INTERNAL: Check if peer is allowed - true if allowed
sub TelegramBot_checkAllowedPeer($$$) {
  my ($hash,$mpeer,$msg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "TelegramBot_checkAllowedPeer $name: called with $mpeer";

  my $cp = AttrVal($name,'cmdRestrictedPeer','');

  return 1 if ( $cp eq '' );
  
  my @peers = split( " ", $cp);  
  foreach my $cp (@peers) {
    return 1 if ( $cp eq $mpeer );
    my $cdefpeer = TelegramBot_GetIdForPeer( $hash, $cp );
    if ( defined( $cdefpeer ) ) {
      return 1 if ( $cdefpeer eq $mpeer );
    }
  }
  # get human readble name for peer
  my $pname = TelegramBot_GetFullnameForContact( $hash, $mpeer );

  # unauthorized fhem cmd
  Log3 $name, 1, "TelegramBot unauthorized cmd from user :$pname: ($mpeer) \n  Msg: $msg";
  # LOCAL: External message
  my $ret = AttrVal( $name, 'textResponseUnauthorized', 'UNAUTHORIZED: TelegramBot FHEM request from user :$peer \n  Msg: $msg');
  $ret =~ s/\$peer/$pname ($mpeer)/g;
  $ret =~ s/\$msg/$msg/g;
  # my $ret =  "UNAUTHORIZED: TelegramBot FHEM request from user :$pname: ($mpeer) \n  Msg: $msg";
  
  # send unauthorized to defaultpeer
  my $defpeer = AttrVal($name,'defaultPeer',undef);
  if ( defined( $defpeer ) ) {
    AnalyzeCommand( undef, "set $name message $ret" );
  }
 
  return 0;
}  



##############################################################################
##############################################################################
##
## HELPER
##
##############################################################################
##############################################################################



#####################################
# stores Telegram API Token 
sub TelegramBot_getBaseURL($)
{
  my ($hash) = @_;

  my $token = TelegramBot_readToken( $hash );
  
#  Debug "Token  ".$hash->{NAME}."  ".$token;
  
  return "https://api.telegram.org/bot".$token."/";
}




#####################################
# stores Telegram API Token 
sub TelegramBot_storeToken($$;$)
{
    my ($hash, $token, $name) = @_;
     
    if ( $token !~ /^([[:alnum:]]|[-:_])+[[:alnum:]]+([[:alnum:]]|[-:_])+$/ ) {
      return "specify valid API token containing only alphanumeric characters and -: characters";
    }

    $name = $hash->{NAME} if ( ! defined($name) );
    
    my $index = "TelegramBot_".$name."_token";
    my $key = getUniqueId().$index;
    
    my $enc_pwd = "";
    
    if(eval "use Digest::MD5;1")
    {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }
    
    for my $char (split //, $token)
    {
        my $encode=chop($key);
        $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }
    my $err = setKeyValue($index, $enc_pwd);

    return "error while saving the API token - $err" if(defined($err));
    return "API token successfully saved";
} # end storeToken

#####################################
# reads the Telegram API Token
sub TelegramBot_readToken($;$)
{
   my ($hash, $name) = @_;
   
   $name = $hash->{NAME} if ( ! defined($name) );

   my $index = "TelegramBot_" . $name . "_token";
   my $key = getUniqueId().$index;

   my ($token, $err);

   Log3 $hash, 5, "TelegramBot_readToken: Read Telegram API token from file";
   ($err, $token) = getKeyValue($index);

   if ( defined($err) ) {
      Log3 $hash, 1, "TelegramBot_readToken: Error: unable to read API token from file: $err";
      return "";
   }  
    
   if ( defined($token) ) {
      if ( eval "use Digest::MD5;1" ) {
         $key = Digest::MD5::md5_hex(unpack "H*", $key);
         $key .= Digest::MD5::md5_hex($key);
      }

      my $dec_pwd = '';
     
      for my $char (map { pack('C', hex($_)) } ($token =~ /(..)/g)) {
         my $decode=chop($key);
         $dec_pwd.=chr(ord($char)^ord($decode));
         $key=$decode.$key;
      }
     
      return $dec_pwd;
   }
   else {
      Log3 $hash, 1, "TelegramBot_readToken: Error: No API token in file";
      return "";
   }
} # end readToken


#####################################
#  INTERNAL: get only numeric part of a value (simple)
sub TelegramBot_AttrNum($$$)
{
  my ($d,$n,$default) = @_;
  my $val = AttrVal($d,$n,$default);
  $val =~ s/[^-\.\d]//g;
  return $val;
} 


######################################
#  Get a string and identify possible media streams
#  PNG is tested
#  returns 
#   -1 for image
#   -2 for Audio
#   -3 for other media
# and extension without dot as 2nd list element

sub TelegramBot_IdentifyStream($$) {
  my ($hash, $msg) = @_;

  # signatures for media files are documented here --> https://en.wikipedia.org/wiki/List_of_file_signatures
  # seems sometimes more correct: https://wangrui.wordpress.com/2007/06/19/file-signatures-table/
  return (-1,"png") if ( $msg =~ /^\x89PNG\r\n\x1a\n/ );    # PNG
  return (-1,"jpg") if ( $msg =~ /^\xFF\xD8\xFF/ );    # JPG not necessarily complete, but should be fine here
  
  return (-2 ,"mp3") if ( $msg =~ /^\xFF\xF3/ );    # MP3    MPEG-1 Layer 3 file without an ID3 tag or with an ID3v1 tag
  return (-2 ,"mp3") if ( $msg =~ /^\xFF\xFB/ );    # MP3    MPEG-1 Layer 3 file without an ID3 tag or with an ID3v1 tag
  
  # MP3    MPEG-1 Layer 3 file with an ID3v2 tag 
  #   starts with ID3 then version (most popular 03, new 04 seldom used, old 01 and 02) ==> Only 2,3 and 4 are tested currently
  return (-2 ,"mp3") if ( $msg =~ /^ID3\x03/ );    
  return (-2 ,"mp3") if ( $msg =~ /^ID3\x04/ );    
  return (-2 ,"mp3") if ( $msg =~ /^ID3\x02/ );    

  return (-3,"pdf") if ( $msg =~ /^%PDF/ );    # PDF document
  return (-3,"docx") if ( $msg =~ /^PK\x03\x04/ );    # Office new
  return (-3,"docx") if ( $msg =~ /^PK\x05\x06/ );    # Office new
  return (-3,"docx") if ( $msg =~ /^PK\x07\x08/ );    # Office new
  return (-3,"doc") if ( $msg =~ /^\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1/ );    # Office old - D0 CF 11 E0 A1 B1 1A E1

  return (0,undef);
}

#####################################
#####################################
# INTERNAL: prepare msg/ret for log file 
sub TelegramBot_MsgForLog($;$) {
  my ($msg, $stream) = @_;

  if ( ! defined( $msg ) ) {
    return "<undef>";
  } elsif ( $stream ) {
    return "<stream:".length($msg).">";
  } 
  return $msg;
}

######################################
#  read binary file for Phototransfer - returns undef or empty string on error
#  
sub TelegramBot_BinaryFileRead($$) {
  my ($hash, $fileName) = @_;

  return '' if ( ! (-e $fileName) );
  
  my $fileData = '';
    
  open TGB_BINFILE, '<'.$fileName;
  binmode TGB_BINFILE;
  while (my $line = <TGB_BINFILE>){
    $fileData .= $line;
  }
  close TGB_BINFILE;
  
  return $fileData;
}



######################################
#  write binary file for (hest hash, filename and the data
#  
sub TelegramBot_BinaryFileWrite($$$) {
  my ($hash, $fileName, $data) = @_;

  open TGB_BINFILE, '>'.$fileName;
  binmode TGB_BINFILE;
  print TGB_BINFILE $data;
  close TGB_BINFILE;
  
  return undef;
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
=item summary   send and receive of messages through telegram instant messaging
=item summary_DE senden und empfangen von Nachrichten durch telegram IM
=begin html

<a name="TelegramBot"></a>
<h3>TelegramBot</h3>
<ul>
  The TelegramBot module allows the usage of the instant messaging service <a href="https://telegram.org/">Telegram</a> from FHEM in both directions (sending and receiving). 
  So FHEM can use telegram for notifications of states or alerts, general informations and actions can be triggered.
  <br>
  <br>
  TelegramBot makes use of the <a href=https://core.telegram.org/bots/api>telegram bot api</a> and does NOT rely on any addition local client installed. 
  <br>
  Telegram Bots are different from normal telegram accounts, without being connected to a phone number. Instead bots need to be registered through the 
  <a href=https://core.telegram.org/bots#botfather>BotFather</a> to gain the needed token for authorizing as bot with telegram.org. This is done by connecting (in a telegram client) to the BotFather and sending the command <code>/newbot</code> and follow the steps specified by the BotFather. This results in a token, this token (e.g. something like <code>110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw</code> is required for defining a working telegram bot in fhem.
  <br><br>
  Bots also differ in other aspects from normal telegram accounts. Here some examples:
  <ul>
    <li>Bots can not initiate connections to arbitrary users, instead users need to first initiate the communication with the bot.</li> 
    <li>Bots have a different privacy setting then normal users (see <a href=https://core.telegram.org/bots#privacy-mode>Privacy mode</a>) </li> 
    <li>Bots support commands and specialized keyboards for the interaction </li> 
  </ul>
  
  <br><br>
  Note:
  <ul>
    <li>This module requires the perl JSON module.<br>
        Please install the module (e.g. with <code>sudo apt-get install libjson-perl</code>) or the correct method for the underlying platform/system.</li>
    <li>The attribute pollingTimeout needs to be set to a value greater than zero, to define the interval of receiving messages (if not set or set to 0, no messages will be received!)</li>
    <li>Multiple infomations are stored in readings (esp contacts) and internals that are needed for the bot operation, so having an recent statefile will help in correct operation of the bot. Generally it is recommended to regularly store the statefile (see save command)</li>
  </ul>   
  <br><br>

  The TelegramBot module allows receiving of messages from any peer (telegram user) and can send messages to known users.
  The contacts/peers, that are known to the bot are stored in a reading (named <code>Contacts</code>) and also internally in the module in a hashed list to allow the usage 
  of contact ids and also full names and usernames. Contact ids are made up from only digits, user names are prefixed with a @, group names are prefixed with a #. 
  All other names will be considered as full names of contacts. Here any spaces in the name need to be replaced by underscores (_).
  Each contact is considered a triple of contact id, full name (spaces replaced by underscores) and username or groupname prefixed by @ respectively #. 
  The three parts are separated by a colon (:).
  <br>
  Contacts are collected automatically during communication by new users contacting the bot or users mentioned in messages.
  <br><br>
  Updates and messages are received via long poll of the GetUpdates message. This message currently supports a maximum of 20 sec long poll. 
  In case of failures delays are taken between new calls of GetUpdates. In this case there might be increasing delays between sending and receiving messages! 
  <br>
  Beside pure text messages also media messages can be sent and received. This includes audio, video, images, documents, locations and venues.
  <br><br>
  <a name="TelegramBotdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TelegramBot  &lt;token&gt; </code>
    <br><br>
    Defines a TelegramBot device using the specified token perceived from botfather
    <br>

    Example:
    <ul>
      <code>define teleBot TelegramBot 110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw</code><br>
    </ul>
    <br>
  </ul>
  <br><br>

  <a name="TelegramBotset"></a>
  <b>Set</b>
  <ul>
    <li><code>message|msg|_msg|send [ @&lt;peer1&gt; ... @&lt;peerN&gt; ] [ (&lt;keyrow1&gt;) ... (&lt;keyrowN&gt;) ] &lt;text&gt;</code><br>Sends the given message to the given peer or if peer(s) is ommitted currently defined default peer user. Each peer given needs to be always prefixed with a '@'. Peers can be specified as contact ids, full names (with underscore instead of space), usernames (prefixed with another @) or chat names (also known as groups in telegram groups must be prefixed with #). Multiple peers are to be separated by space<br>
    A reply keyboard can be specified by adding a list of strings enclosed in parentheses "()". Each separate string will make one keyboard row in a reply keyboard. The different keys in the row need to be separated by |. The key strings can contain spaces.<br>
    Messages do not need to be quoted if containing spaces. If you want to use parentheses at the start of the message than add one extra character before the parentheses (i.e. an underline) to avoid the message being parsed as a keyboard <br>
    Examples:<br>
      <dl>
        <dt><code>set aTelegramBotDevice message @@someusername a message to be sent</code></dt>
          <dd> to send to a peer having someusername as username (not first and last name) in telegram <br> </dd>
        <dt><code>set aTelegramBotDevice message (yes) (may be) are you there?</code></dt>
          <dd> to send the message "are you there?" and provide a reply keyboard with two buttons ("yes" and "may be") on separate rows to the default peer <br> </dd>
        <dt><code>set aTelegramBotDevice message @@someusername (yes) (may be) are you there?</code></dt>
          <dd> to send the message from above with reply keyboard to a peer having someusername as username <br> </dd>
        <dt><code>set aTelegramBotDevice message (yes|no) (may be) are you there?</code></dt>
          <dd> to send the message from above with reply keyboard having 3 keys, 2 in the first row ("yes" / "no") and a second row with just one key to the default peer <br> </dd>
        <dt><code>set aTelegramBotDevice message @@someusername @1234567 a message to be sent to multiple receipients</code></dt>
          <dd> to send to a peer having someusername as username (not first and last name) in telegram <br> </dd>
        <dt><code>set aTelegramBotDevice message @Ralf_Mustermann another message</code></dt>
          <dd> to send to a peer with Ralf as firstname and Mustermann as last name in telegram   <br></dd>
        <dt><code>set aTelegramBotDevice message @#justchatting Hello</code></dt>
          <dd> to send the message "Hello" to a chat with the name "justchatting"   <br></dd>
        <dt><code>set aTelegramBotDevice message @1234567 Bye</code></dt>
          <dd> to send the message "Bye" to a contact or chat with the id "1234567". Chat ids might be negative and need to be specified with a leading hyphen (-). <br></dd>
      <dl>
    </li>
    
    <li><code>silentmsg, silentImage, silentInline ...</code><br>Sends the given message silently (with disabled_notifications) to the recipients. Syntax and parameters are the same as in the corresponding send/message command.
    </li>
    
    <li><code>msgForceReply [ @&lt;peer1&gt; ... @&lt;peerN&gt; ] &lt;text&gt;</code><br>Sends the given message to the recipient(s) and requests (forces) a reply. Handling of peers is equal to the message command. Adding reply keyboards is currently not supported by telegram.
    </li>
    <li><code>reply &lt;msgid&gt; [ @&lt;peer1&gt; ] &lt;text&gt;</code><br>Sends the given message as a reply to the msgid (number) given to the given peer or if peer is ommitted to the defined default peer user. Only a single peer can be specified. Beside the handling of the message as a reply to a message received earlier, the peer and message handling is otherwise identical to the msg command. 
    </li>

    <li><code>msgEdit &lt;msgid&gt; [ @&lt;peer1&gt; ] &lt;text&gt;</code><br>Changes the given message on the recipients clients. The msgid of the message to be changed must match a valid msgId and the peers need to match the original recipient, so only a single peer can be given or if peer is ommitted the defined default peer user is used. Beside the handling of a change of an existing message, the peer and message handling is otherwise identical to the msg command. 
    </li>

    <li><code>msgDelete &lt;msgid&gt; [ @&lt;peer1&gt; ] </code><br>Deletes the given message on the recipients clients. The msgid of the message to be changed must match a valid msgId and the peers need to match the original recipient, so only a single peer can be given or if peer is ommitted the defined default peer user is used. Restrictions apply for deleting messages in the Bot API as currently specified here (<a href=https://core.telegram.org/bots/api#deletemessage>deleteMessage</a>)
    </li>

    <li><code>favoritesMenu [ @&lt;peer&gt; ] </code><br>send the favorites menu to the corresponding peer if defined</code>
    </li>

    <li><code>cmdSend|cmdSendSilent [ @&lt;peer1&gt; ... @&lt;peerN&gt; ] &lt;fhem command&gt;</code><br>Executes the given fhem command and then sends the result to the given peers or the default peer (cmdSendSilent does the same as silent message).<br>
    Example: The following command would sent the resulting SVG picture to the default peer: <br>
      <code>set tbot cmdSend { plotAsPng('SVG_FileLog_Aussen') }</code>
    </li>

    <li><code>queryInline [ @&lt;peer1&gt; ... @&lt;peerN&gt; ] (&lt;keyrow1&gt;) ... (&lt;keyrowN&gt;) &lt;text&gt;</code><br>Sends the given message to the recipient(s) with an inline keyboard allowing direct response <br>
    IMPORTANT: The response coming from the keyboard will be provided in readings and a corresponding answer command with the query id is required, sicne the client is frozen otherwise waiting for the response from the bot!
    REMARK: inline queries are only accepted from contacts/peers that are authorized (i.e. as for executing commands, see cmdKeyword and cmdRestrictedPeer !)
    </li>
    <li><code>queryEditInline &lt;msgid&gt; [ @&lt;peer&gt; ] (&lt;keyrow1&gt;) ... (&lt;keyrowN&gt;) &lt;text&gt;</code><br>Updates the original message specified with msgId with the given message to the recipient(s) with an inline keyboard allowing direct response <br>
    With this method interactive inline dialogs are possible, since the edit of message or inline keyboard can be done multiple times.
    </li>
    

    <li><code>queryAnswer &lt;queryid&gt; [ &lt;text&gt; ] </code><br>Sends the response to the inline query button press. The message is optional, the query id can be collected from the reading "callbackID". This call is mandatory on reception of an inline query from the inline command above
    </li>

    <li><code>sendImage|image [ @&lt;peer1&gt; ... @&lt;peerN&gt;] &lt;file&gt; [&lt;caption&gt;]</code><br>Sends a photo to the given peer(s) or if ommitted to the default peer. 
    File is specifying a filename and path to the image file to be send. 
    Local paths should be given local to the root directory of fhem (the directory of fhem.pl e.g. /opt/fhem).
    Filenames with special characters (especially spaces) need to be given with url escaping (i.e. spaces need to be replaced by %20). 
    Rules for specifying peers are the same as for messages. Multiple peers are to be separated by space. Captions can also contain multiple words and do not need to be quoted.
    </li>
    <li><code>sendMedia|sendDocument [ @&lt;peer1&gt; ... @&lt;peerN&gt;] &lt;file&gt;</code><br>Sends a media file (video, audio, image or other file type) to the given peer(s) or if ommitted to the default peer. Handling for files and peers is as specified above.
    </li>
    <li><code>sendVoice [ @&lt;peer1&gt; ... @&lt;peerN&gt;] &lt;file&gt;</code><br>Sends a voice message for playing directly in the browser to the given peer(s) or if ommitted to the default peer. Handling for files and peers is as specified above.
    </li>
    
    <li><code>silentImage ...</code><br>Sends the given image silently (with disabled_notifications) to the recipients. Syntax and parameters are the same as in the sendImage command.
    </li>
    

  <br>
    <li><code>sendLocation [ @&lt;peer1&gt; ... @&lt;peerN&gt;] &lt;latitude&gt; &lt;longitude&gt;</code><br>Sends a location as pair of coordinates latitude and longitude as floating point numbers 
    <br>Example: <code>set aTelegramBotDevice sendLocation @@someusername 51.163375 10.447683</code> will send the coordinates of the geographical center of Germany as location.
    </li>

  <br>
    <li><code>replaceContacts &lt;text&gt;</code><br>Set the contacts newly from a string. Multiple contacts can be separated by a space. 
    Each contact needs to be specified as a triple of contact id, full name and user name as explained above. </li>
    <li><code>reset</code><br>Reset the internal state of the telegram bot. This is normally not needed, but can be used to reset the used URL, 
    internal contact handling, queue of send items and polling <br>
    ATTENTION: Messages that might be queued on the telegram server side (especially commands) might be then worked off afterwards immedately. 
    If in doubt it is recommened to temporarily deactivate (delete) the cmdKeyword attribute before resetting.</li>

  <br>
    <li><code>token &lt;apitoken&gt;</code><br>Specify a new APItoken to be stored for this bot
    </li>

  </ul>

  <br><br>

  <a name="TelegramBotget"></a>
  <b>Get</b>
  <ul>
    <li><code>urlForFile &lt;fileid&gt;</code><br>Get a URL for a file id that was returned in a message
    </li>
    <li><code>update </code><br>Execute a single update (instead of automatic polling) - manual polling
    </li>
    <li><code>peerId &lt;peer&gt;</code><br>Ask for a peerId for a given peer, the peer can be specified in the same form as in a message without the initial '@'
    </li>
  </ul>

  <br><br>

    <a name="TelegramBotattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>defaultPeer &lt;name&gt;</code><br>Specify contact id, user name or full name of the default peer to be used for sending messages. </li> 
    <li><code>defaultPeerCopy &lt;1 (default) or 0&gt;</code><br>Copy all command results also to the defined defaultPeer. If set results are sent both to the requestor and the defaultPeer if they are different. 
    </li> 

    <li><code>parseModeSend &lt;0_None or 1_Markdown or 2_HTML or 3_Inmsg &gt;</code><br>Specify the parse_mode (allowing formatting of text messages) for sent text messages. 0_None is the default where no formatting is used and plain text is sent. The different formatting options for markdown or HTML are described here <a href="https://core.telegram.org/bots/api/#formatting-options">https://core.telegram.org/bots/api/#formatting-options</a>. The option 3_Inmsg allows to specify the correct parse_mode at the beginning of the message (e.g. "Markdown*bold text*..." as message).
    </li> 
    
    <li><code>webPagePreview &lt;1 or 0&gt;</code><br>Disable / Enable (Default = 1) web page preview on links in messages. See parameter https://core.telegram.org/bots/api/#sendmessage as described here: https://core.telegram.org/bots/api/#sendmessage
    </li> 
    
    
    
  <br>
    <li><code>cmdKeyword &lt;keyword&gt;</code><br>Specify a specific text that needs to be sent to make the rest of the message being executed as a command. 
      So if for example cmdKeyword is set to <code>ok fhem</code> then a message starting with this string will be executed as fhem command 
        (see also cmdTriggerOnly).<br>
        NOTE: It is advised to set cmdRestrictedPeer for restricting access to this feature!<br>
        Example: If this attribute is set to a value of <code>ok fhem</code> a message of <code>ok fhem attr telegram room IM</code> 
        send to the bot would execute the command  <code>attr telegram room IM</code> and set a device called telegram into room IM.
        The result of the cmd is sent to the requestor and in addition (if different) sent also as message to the defaultPeer (This can be controlled with the attribute <code>defaultPeerCopy</code>). 
    <br>
        Note: <code>shutdown</code> is not supported as a command (also in favorites) and will be rejected. This is needed to avoid reexecution of the shutdown command directly after restart (endless loop !).
    </li> 
    <li><code>cmdSentCommands &lt;keyword&gt;</code><br>Specify a specific text that will trigger sending the last commands back to the sender<br>
        Example: If this attribute is set to a value of <code>last cmd</code> a message of <code>last cmd</code> 
        woud lead to a reply with the list of the last sent fhem commands will be sent back.<br>
        Please also consider cmdRestrictedPeer for restricting access to this feature!<br>
    </li> 

  <br>
    <li><code>cmdFavorites &lt;keyword&gt;</code><br>Specify a specific text that will trigger sending the list of defined favorites or executes a given favorite by number (the favorites are defined in attribute <code>favorites</code>).
    <br>
    NOTE: It is advised to set cmdRestrictedPeer for restricting access to this feature!<br>
        Example: If this attribute is set to a value of <code>favorite</code> a message of <code>favorite</code> to the bot will return a list of defined favorite commands and their index number. In the same case the message <code>favorite &lt;n&gt;</code> (with n being a number) would execute the command that is the n-th command in the favorites list. The result of the command will be returned as in other command executions. 
    </li> 
    <li><code>favorites &lt;list of commands&gt;</code><br>Specify a list of favorite commands for Fhem (without cmdKeyword). Multiple favorites  are separated by a single semicolon (;). A double semicolon can be used to specify multiple commands for a single favorite <br>
    <br>
    Favorite commands are fhem commands with an optional alias for the command given. The alias can be sent as message (instead of the favoriteCmd) to execute the command. Before the favorite command also an alias (other shortcut for the favorite) or/and a descriptive text (description enclosed in []) can be specifed. If alias or description is specified this needs to be prefixed with a '/' and the alias if given needs to be specified first.
    <br>
    Favorites can also only be callable with the alias command and not via the corresponding favorite number and it will not be listed in the keyboard. For this the alias needs to be prefixed with a hyphen (-) after the leading slash
    <br>
    <br>
        Example: Assuming cmdFavorites is set to a value of <code>favorite</code> and this attribute is set to a value of
        <br><code>get lights status; /light=set lights on; /dark[Make it dark]=set lights off; /-heating=set heater; /[status]=get heater status;</code> <br>
        <ul>
          <li>Then a message "favorite1" to the bot would execute the command <code>get lights status</code></li>
          <li>A message "favorite 2" or "/light" to the bot would execute the command <code>set lights on</code>. And the favorite would show as "make it dark" in the list of favorites.</li>
          <li>A message "/heating on" to the bot would execute the command <code>set heater on</code><br> (Attention the remainder after the alias will be added to the command in fhem!). SInce this favorite is hidden only the alias can be used to call the favorite</li>
          <li>A message "favorite 3" (since the one before is hidden) to the bot would execute the command <code>get heater status</code> and this favorite would show as "status" as a description in the favorite list</li>
        </ul>
    <br>
    Favorite commands can also be prefixed with a question mark ('?') to enable a confirmation being requested before executing the command.
    <br>
        Examples: <code>get lights status; /light=?set lights on; /dark=set lights off; ?set heater;</code> <br>
    <br>
    <br>
    Favorite commands can also be prefixed with a exclamation mark ('!') to ensure an ok-result message is sent even when the attribute cmdReturnEmptyResult is set to 0. 
    <br>
        Examples: <code>get lights status; /light=!set lights on; /dark=set lights off; !set heater;</code> <br>
    <br>
    The question mark needs to be before the exclamation mark if both are given.
    <br>
    <br>
    The description for an alias can also be prefixed with a '-'. In this case the favorite command/alias will not be shown in the favorite menu. This case only works for inline keyboard favorite menus.
    <br>
    <br>
    Favorite commands can also include multiple fhem commands being execute using ;; as a separator 
    <br>
        Example: <code>get lights status; /blink=set lights on;; sleep 3;; set lights off; set heater;</code> <br>
    <br>
    Meaning the full format for a single favorite is <code>/alias[description]=commands</code> where the alias can be empty if the description is given or <code>/alias=command</code> or <code>/-alias=command</code> for a hidden favorite or just the <code>commands</code>. In any case the commands can be also prefixed with a '?' or a '!' (or both). The description also can be given as <code>[-description]</code> to remvoe the command or alias from the favorite menus in inline keyboard menus. Spaces are only allowed in the description and the commands, usage of spaces in other areas might lead to wrong interpretation of the definition. Spaces and also many other characters are not supported in the alias commands by telegram, so if you want to have your favorite/alias directly recognized in the telegram app, restriction to letters, digits and underscore is required. Double semicolon will be used for specifying mutliple fhem commands in a single favorites, while single semicolon is used to separate between different favorite definitions
    </li> 
    <li><code>favorites2Col &lt;1 or 0&gt;</code><br>Show favorites in 2 columns keyboard (instead of 1 column  - default)
    </li> 
    <li><code>favoritesInline &lt;1 or 0&gt;</code><br>When set to 1 it shows favorite dialog as inline keyboard and results will be also displayed inline (instead of as reply keyboards - default)
    </li> 

  <br>
    <li><code>cmdRestrictedPeer &lt;peer(s)&gt;</code><br>Restrict the execution of commands only to messages sent from the given peername or multiple peernames
    (specified in the form of contact id, username or full name, multiple peers to be separated by a space). This applies to the internal machanisms for commands in the TelegramBot-Module (favorites, cmdKeyword etc) not for external methods to react on changes of readings.
    A message with the cmd and sender is sent to the default peer in case of another peer trying to sent messages<br>
    NOTE: It is recommended to use only peer ids for this restriction to reduce spoofing risk!

    </li> 
    <li><code>cmdRespondChat &lt;1 or 0&gt;</code><br>Results / Responses from Commands will be sent to a group chat (1 = default) if originating from this chat. Otherwise responses will be sent only to the person initiating the command (personal chat) if set to value 0. <br>
    Note: Group chats also need to be allowed as restricted Peer in cmdRestrictedPeer if this is set. 
    </li> 
    <li><code>allowUnknownContacts &lt;1 or 0&gt;</code><br>Allow new contacts to be added automatically (1 - Default) or restrict message reception only to known contacts and unknwown contacts will be ignored (0).
    </li> 
    <li><code>saveStateOnContactChange &lt;1 or 0&gt;</code><br>Allow statefile being written on every new contact found, ensures new contacts not being lost on any loss of statefile. Default is on (1).
    </li> 
    <li><code>cmdReturnEmptyResult &lt;1 or 0&gt;</code><br>Return empty (success) message for commands (default). Otherwise return messages are only sent if a result text or error message is the result of the command execution.
    </li> 

    <li><code>allowedCommands &lt;list of command&gt;</code><br>Restrict the commands that can be executed through favorites and cmdKeyword to the listed commands (separated by space). Similar to the corresponding restriction in FHEMWEB. The allowedCommands will be set on the corresponding instance of an allowed device with the name "allowed_&lt;TelegrambotDeviceName&gt; and not on the telegramBotDevice! This allowed device is created and modified automatically.<br>
    <b>ATTENTION: This is not a hardened secure blocking of command execution, there might be ways to break the restriction!</b>
    </li> 

    <li><code>cmdTriggerOnly &lt;0 or 1&gt;</code><br>Restrict the execution of commands only to trigger command. If this attr is set (value 1), then only the name of the trigger even has to be given (i.e. without the preceding statement trigger). 
          So if for example cmdKeyword is set to <code>ok fhem</code> and cmdTriggerOnly is set, then a message of <code>ok fhem someMacro</code> would execute the fhem command  <code>trigger someMacro</code>.<br>
    Note: This is deprecated and will be removed in one of the next releases
    </li> 

    <li><code>queryAnswerText &lt;text&gt;</code><br>Specify the automatic answering to buttons send through queryInline command. If this attribute is set an automatic answer is provided to the press of the inline button. The text in the attribute is evaluated through set-logic, so that readings and also perl code can be stored here. The result of the translation with set-logic will be sent as a text with the answer (this text is currently limited by telegram to 200 characters). <br>
    Note: A value of "0" in the attribute or as result of the evaluation will result in no text being sent with the answer.
    <br>
    Note: If the peer sending the button is not authorized an answer is always sent without any text.
    </li> 



  <br>
    <li><code>pollingTimeout &lt;number&gt;</code><br>Used to specify the timeout for long polling of updates. A value of 0 is switching off any long poll. 
      In this case no updates are automatically received and therefore also no messages can be received. It is recommended to set the pollingtimeout to a reasonable time between 15 (not too short) and 60 (to avoid broken connections). See also attribute <code>disable</code>. 
    </li> 
    <li><code>pollingVerbose &lt;0_None 1_Digest 2_Log&gt;</code><br>Used to limit the amount of logging for errors of the polling connection. These errors are happening regularly and usually are not consider critical, since the polling restarts automatically and pauses in case of excess errors. With the default setting "1_Digest" once a day the number of errors on the last day is logged (log level 3). With "2_Log" every error is logged with log level 2. With the setting "0_None" no errors are logged. In any case the count of errors during the last day and the last error is stored in the readings <code>PollingErrCount</code> and <code>PollingLastError</code> </li> 
    <li><code>disable &lt;0 or 1&gt;</code><br>Used to disable the polling if set to 1 (default is 0). 
    </li> 
    
  <br>
    <li><code>cmdTimeout &lt;number&gt;</code><br>Used to specify the timeout for sending commands. The default is a value of 30 seconds, which should be normally fine for most environments. In the case of slow or on-demand connections to the internet this parameter can be used to specify a longer time until a connection failure is considered.
    </li> 

  <br>
    <li><code>maxFileSize &lt;number of bytes&gt;</code><br>Maximum file size in bytes for transfer of files (images). If not set the internal limit is specified as 10MB (10485760B).
    </li> 
    <li><code>filenameUrlEscape &lt;0 or 1&gt;</code><br>Specify if filenames can be specified using url escaping, so that special chanarcters as in URLs. This specifically allows to specify spaces in filenames as <code>%20</code>. Default is off (0).
    </li> 

    <li><code>maxReturnSize &lt;number of chars&gt;</code><br>Maximum size of command result returned as a text message including header (Default is unlimited). The internal shown on the device is limited to 1000 chars.
    </li> 
    <li><code>maxRetries &lt;0,1,2,3,4,5&gt;</code><br>Specify the number of retries for sending a message in case of a failure. The first retry is sent after 10sec, the second after 100, then after 1000s (~16min), then after 10000s (~2.5h), then after approximately a day. Setting the value to 0 (default) will result in no retries.
    </li> 

  <br>
    <li><code>textResponseConfirm &lt;TelegramBot FHEM : $peer\n Bestätigung \n&gt;</code><br>Text to be sent when a confirmation for a command is requested. Default is shown here and $peer will be replaced with the actual contact full name if added.
    </li> 
    <li><code>textResponseFavorites &lt;TelegramBot FHEM : $peer\n Favoriten \n&gt;</code><br>Text to be sent as starter for the list of favorites. Default is shown here and $peer will be replaced with the actual contact full name if added.
    </li> 
    <li><code>textResponseCommands &lt;TelegramBot FHEM : $peer\n Letzte Befehle \n&gt;</code><br>Text to be sent as starter for the list of last commands. Default is shown here and $peer will be replaced with the actual contact full name if added.
    </li> 
    <li><code>textResponseResult &lt;TelegramBot FHEM : $peer\n Befehl:$cmd:\n Ergebnis:\n$result\n&gt;</code><br>Text to be sent as result for a cmd execution. Default is shown here and $peer will be replaced with the actual contact full name if added. Similarly $cmd and $result will be replaced with the cmd and the execution result. If the result is a response with just spaces, or other separator characters the result will be not sent at all (i.e. a values of "\n") will result in no message at all.
    </li> 
    <li><code>textResponseUnauthorized &lt;UNAUTHORIZED: TelegramBot FHEM request from user :$peer\n  Msg: $msg&gt;</code><br>Text to be sent as warning for unauthorized command requests. Default is shown here and $peer will be replaced with the actual contact full name and id if added. $msg will be replaced with the sent message.
    </li> 

    <li><code>utf8Special &lt;0 or 1&gt;</code><br>Specify if utf8 encodings will be resolved before sending to avoid issues with timeout on HTTP send (experimental ! / default is off).
    </li> 
    
  </ul>
  <br><br>
  
  <a name="TelegramBotreadings"></a>
  <b>Readings</b>
  <br><br>
  <ul>
    <li>Contacts &lt;text&gt;<br>The current list of contacts known to the telegram bot. 
    Each contact is specified as a triple in the same form as described above. Multiple contacts separated by a space. </li> 
  <br>
    <li>msgId &lt;text&gt;<br>The id of the last received message is stored in this reading. 
    For secret chats a value of -1 will be given, since the msgIds of secret messages are not part of the consecutive numbering</li> 
    <li>msgPeer &lt;text&gt;<br>The sender name of the last received message (either full name or if not available @username)</li> 
    <li>msgPeerId &lt;text&gt;<br>The sender id of the last received message</li> 
    <li>msgChat &lt;text&gt;<br>The name of the Chat in which the last message was received (might be the peer if no group involved)</li> 
    <li>msgChatId &lt;ID&gt;<br>The id of the chat of the last message, if not identical to the private peer chat then this value will be the peer id</li> 
    <li>msgText &lt;text&gt;<br>The last received message text is stored in this reading. Information about special messages like documents, audio, video, locations or venues will be also stored in this reading</li> 
    <li>msgFileId &lt;fileid&gt;<br>The last received message file_id (Audio, Photo, Video, Voice or other Document) is stored in this reading.</li> 
    <li>msgReplyMsgId &lt;text&gt;<br>Contains the message id of the original message, that this message was a reply to</li> 
    
  <br>
    <li>prevMsgId &lt;text&gt;<br>The id of the SECOND last received message is stored in this reading</li> 
    <li>prevMsgPeer &lt;text&gt;<br>The sender name of the SECOND last received message (either full name or if not available @username)</li> 
    <li>prevMsgPeerId &lt;text&gt;<br>The sender id of the SECOND last received message</li> 
    <li>prevMsgText &lt;text&gt;<br>The SECOND last received message text is stored in this reading</li> 
    <li>prevMsgFileId &lt;fileid&gt;<br>The SECOND last received file id is stored in this reading</li> 
  <br><b>Note: All prev... Readings are not triggering events</b><br>
  <br>

    <li>sentMsgId &lt;text&gt;<br>The id of the last sent message is stored in this reading, if not succesful the id is empty</li> 
    <li>sentMsgResult &lt;text&gt;<br>The result of the send process for the last message is contained in this reading - SUCCESS if succesful</li> 

  <br>
    <li>StoredCommands &lt;text&gt;<br>A list of the last commands executed through TelegramBot. Maximum 10 commands are stored.</li> 

  <br>
    <li>PollingErrCount &lt;number&gt;<br>Show the number of polling errors during the last day. The number is reset at the beginning of the next day.</li> 
    <li>PollingLastError &lt;number&gt;<br>Last error message that occured during a polling update call</li> 
    
  <br>
    <li>callbackID &lt;id&gt; / callbackPeerId &lt;peer id&gt; / callbackPeer &lt;peer&gt;<br>Contains the query ID (respective the peer id and peer name) of the last received inline query from an inline query button (see set ... inline)</li> 

  </ul>
  <br><br>
  
  <a name="TelegramBotexamples"></a>
  <b>Examples</b>
  <br><br>
  <ul>

     <li>Send a telegram message if fhem has been newly started
      <p>
      <code>define notify_fhem_reload notify global:INITIALIZED set &lt;telegrambot&gt; message fhem started - just now </code>
      </p> 
    </li> 
  <br>

  <li>A command, that will retrieve an SVG plot and send this as a message back (can be also defined as a favorite).
      <p>
      Send the following message as a command to the bot <code>ok fhem { plotAsPng('SVG_FileLog_Aussen') }</code> 
      <br>assuming <code>ok fhem</code> is the command keyword)
      </p> (
      
      The png picture created by plotAsPng will then be send back in image format to the telegram client. This also works with other pictures returned and should also work with other media files (e.g. MP3 and doc files). The command can also be defined in a favorite.<br>
      Remark: Example requires librsvg installed
    </li> 
  <br>

    <li>Allow telegram bot commands to be used<br>
        If the keywords for commands are starting with a slash (/), the corresponding commands can be also defined with the 
        <a href=http://botsfortelegram.com/project/the-bot-father/>Bot Father</a>. So if a slash is typed a list of the commands will be automatically shown. Assuming that <code>cmdSentCommands</code> is set to <code>/History</code>. Then you can initiate the communication with the botfather, select the right bot and then with the command <code>/setcommands</code> define one or more commands like
        <p>
          <code>History-Show a history of the last 10 executed commands</code>
        </p> 
        When typing a slash, then the text above will immediately show up in the client.
    </li> 

    </ul>
</ul>

=end html
=cut
