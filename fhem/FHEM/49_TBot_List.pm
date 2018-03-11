##############################################################################
##############################################################################
#
#     49_TBot_List.pm
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
#  TBot_List (c) Johannes Viegener / https://github.com/viegener/Telegram-fhem/tree/master/TBot_List
#
# This module interacts with TelegramBot and PostMe devices
#
# Discussed in FHEM Forum: https://forum.fhem.de/index.php/topic,67976.0.html
#
# $Id$
#
##############################################################################
# 0.0 2017-01-15 Started
#   add get normpeer getter to tbot
#   get data from tbot in set / get
#   setup needs to specfiy notifies
#   implement attr
#   handle reply msg
#   change key building to routine
#   change all handler calls to new parameters
#   use name in queryData
#   change key from lname to tbot
#   lname handling
#   TBot_List_handler invocations to be modified
#   check in get queryanswer if list is amtching current device
#   add handler from myutils
#   add notify function
#   change ensure cmd with name is handled correctly
#   modify tbot to call handler with querydcata -- get routine - returns undef=nothandled 0=emptyanswerbuthandled other=answer
# 0.1 2017-01-17 Initial Version - mostly tested

#   Documentation
#   changed log levels
#   corrected listNo calculation on dialog and define
# 0.2 2017-02-26 Initial SVN Checkin

#   Add note to documentation on events and event-on attributes
#   FIX: corrected allowedPeers definition
#   Also support chats in start without args
#   respond in chats / still only a single dialog per user allowed
#   add entry for messages sent accidentially - absed on dialog
#   removed debug statements
#   make unsolicited entries configurable
#   handle multiline entries --> remove line ends
#   handle multiline entries --> multiple entries to be created
# 0.3 2017-03-16 

#   Fix: undef errors in listhandler resolved
#   Menu für gesamte Liste
#   Sortierung A-Z und Z-A für Liste
#   allow double entries and correct handling
# 0.4 2017-05-13 Menu / Sort und fixes 

#   changed query data to prefix TBL_
#   fhem-call get peerId is quiet
# 0.5 2017-05-13 Menu / Sort und fixes 
#   
#   confirm delete configurable as attribute confirmDelete 
#   confirm add unsolicited configurable as attribute confirmUnsolicited 
# 0.6 2017-07-16   confirmDelete & confirmUnsolicited
#   
#   added list getter for simple text list with \n and empty string if no entries
#   switched from fhem( calls to AnalyzeCommandChain
#   added count getter for count of list entries
#   FIX: Some log entries / issues with inline commands
#   new attribute deleteOnly to have deleteonly lists / no changes or adds
#   document deleteOnly
# 0.7 2018-03-11   deleteonly lists / internal changes
  
#   
##############################################################################
# TASKS 
#   
#   
#   Make texts and addtl buttons configurable
#   
#   internal value if waiting for msg or reply -- otherwise notify not looping through events
#   
#   
#   TODOs
#
#   setters - start list / add new entry with question
##############################################################################
# Ideas
#   
#
##############################################################################


package main;

use strict;
use warnings;

use URI::Escape;

use Scalar::Util qw(reftype looks_like_number);

#########################
# Forward declaration
sub TBot_List_Define($$);
sub TBot_List_Undef($$);

sub TBot_List_Set($@);
sub TBot_List_Get($@);

sub TBot_List_handler( $$$$;$ );

#########################
# Globals


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

sub TBot_List_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}      = "TBot_List_Define";
  $hash->{UndefFn}    = "TBot_List_Undef";
  $hash->{GetFn}      = "TBot_List_Get";
  $hash->{SetFn}      = "TBot_List_Set";
  $hash->{AttrFn}     = "TBot_List_Attr";
  $hash->{NotifyFn}     = "TBot_List_Notify";
  $hash->{AttrList}   = 
          "telegramBots:textField ".
          "optionDouble:0,1 ".
          "handleUnsolicited:0,1 ".
          "confirmDelete:0,1 ".
          "confirmUnsolicited:0,1 ".
          "deleteOnly:0,1 ".
          "allowedPeers:textField ".
          $readingFnAttributes;           
}


######################################
#  Define function is called for actually defining a device of the corresponding module
#   this includes name of the PosteMe device and the listname
#  
sub TBot_List_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $name = $hash->{NAME};

  Log3 $name, 3, "TBot_List_Define $name: called ";

  my $errmsg = '';
  
  my $definemsg = "define <name> TBot_List <postmedevice> <listname>";
  
  # Check parameter(s)
  if( int(@a) != 4 ) {
    $errmsg = "syntax error: $definemsg";
    Log3 $name, 1, "TBot_List $name: " . $errmsg;
    return $errmsg;
  }

  my $postme = $a[2];
  if ( ( defined( $defs{$postme} ) ) && ( $defs{$postme}{TYPE} eq "PostMe" ) ) {
    $hash->{postme} = $postme;
  } else {
    $errmsg = "specify valid PostMe device in $definemsg ";
    Log3 $name, 1, "TBot_List $name: " . $errmsg;
    return $errmsg;
  }
  
  $hash->{listname} = $a[3];
  
  $hash->{TYPE} = "TBot_List";

  $hash->{STATE} = "Undefined";

  TBot_List_Setup( $hash );

  return; 
}

#####################################
#  Undef function is corresponding to the delete command the opposite to the define function 
#  Cleanup the device specifically for external ressources like connections, open files, 
#    external memory outside of hash, sub processes and timers
sub TBot_List_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, "TBot_List_Undef $name: called ";

  Log3 $name, 4, "TBot_List_Undef $name: done ";
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
sub TBot_List_Set($@)
{
  my ( $hash, $name, @args ) = @_;
  
  Log3 $name, 5, "TBot_List_Set $name: called ";

  ### Check Args
  my $numberOfArgs  = int(@args);
  return "TBot_List_Set: No cmd specified for set" if ( $numberOfArgs < 1 );

  my $cmd = shift @args;

  my $addArg = ($args[0] ? join(" ", @args ) : undef);

  # check cmd / handle ?
  my $ret = TBot_List_CheckSetGet( $hash, $cmd, $hash->{setoptions} );
  return $ret if ( $ret );
  
  Log3 $name, 4, "TBot_List_Set $name: Processing TBot_List_Set( $cmd ) - args :".(defined($addArg)?$addArg:"<undef>").":";

  if ($cmd eq 'start')  {
    Log3 $name, 4, "TBot_List_Set $name: start of dialog requested ";
    $ret = "start requires a telegrambot and optionally a peer" if ( ( $numberOfArgs < 2 ) && ( $numberOfArgs > 3 ) );
    
    my $tbot;
    my $tpeer;
    my $tchat;
    if ( ! $ret ) {
      $tbot = $args[0];
      $ret = "No telegramBot specified :$tbot:" if ( ! TBot_List_isTBot( $hash, $tbot ) );
    }  

    if ( ! $ret ) {
      $ret = "TelegramBot specified :$tbot: is not monitored" if ( ! TBot_List_hasConfigTBot( $hash, $tbot ) );
    }
    
    if ( ! $ret ) {
      if ( $numberOfArgs == 2 ) {
        $tchat = ReadingsVal( $tbot, "msgChatId", undef );
        $tpeer = ReadingsVal( $tbot, "msgPeerId", "" );
      } else {
        $tpeer = AnalyzeCommandChain( $hash, "get $tbot peerId ".$args[1] );
      }
      $ret = "No peer found or specified :$tbot: ".(( $numberOfArgs == 2 )?"":$args[1]) if ( ! $tpeer );
    }  

    if ( ! $ret ) {
      # listno will be calculated at start of new dialog
      my $listNo = TBot_List_calcListNo($hash);

      if ( ! $listNo ) {
        $ret = "specify valid list for PostMe device ".$hash->{postme}." in $name :".$hash->{listname}.":";
        Log3 $name, 1, "TBot_List $name: " . $ret;
      }
    }
    
    Log3 $name, 1, "TBot_List_Set $name: Error :".$ret if ( $ret );
    
    # start uses a botname and an optional peer
    $tpeer .= " ".$tchat if ( defined( $tchat ) );
    
    $ret = TBot_List_handler( $hash, "list", $tbot, $tpeer ) if ( ! $ret );

  } elsif($cmd eq 'end') {
    Log3 $name, 4, "TBot_List_Set $name: end of dialog requested ";
    $ret = "end requires a telegrambot and optionally a peer" if ( $numberOfArgs != 3 );
    
    my $tbot;
    my $tpeer;
    if ( ! $ret ) {
      $tbot = $args[0];
      $ret = "No telegramBot specified :$tbot:" if ( ! TBot_List_isTBot( $hash, $tbot ) );
    }  
    
    if ( ! $ret ) {
      $tpeer = AnalyzeCommandChain( $hash, "get $tbot peerId ".$args[1], 1 );
      $ret = "No peer found or specified :$tbot: ".$args[1] if ( ! $tpeer );
    }  
  
    # start uses a botname and an optional peer
    $ret = TBot_List_handler( $hash, "end", $tbot, $tpeer ) if ( ! $ret );

  } elsif($cmd eq 'reset') {
    Log3 $name, 4, "TBot_List_Set $name: reset requested ";
    TBot_List_Setup( $hash );
  }


  Log3 $name, 4, "TBot_List_Set $name: $cmd ".((defined( $ret ))?"failed with :$ret: ":"done succesful ");
  return $ret
}

#####################################
# get function for gaining information from device
sub TBot_List_Get($@)
{
  my ( $hash, $name, @args ) = @_;
  
  Log3 $name, 5, "TBot_List_Get $name: called ";

  ### Check Args
  my $numberOfArgs  = int(@args);
  return "TBot_List_Get: No value specified for get" if ( $numberOfArgs < 1 );

  my $cmd = $args[0];
  my $arg = $args[1];

  # check cmd / handle ?
  my $ret = TBot_List_CheckSetGet( $hash, $cmd, $hash->{getoptions} );
  return $ret if ( $ret );

  Log3 $name, 5, "TBot_List_Get $name: Processing TBot_List_Get( $cmd )";

  if($cmd eq "textList") {
    $ret = TBot_List_getTextList($hash);
    
  } elsif($cmd eq "list") {
    my @list = TBot_List_getList( $hash );
    $ret = "";
    $ret = join("\n", @list ) if ( scalar( @list ) != 0 );
    
  } elsif($cmd eq "count") {
    my @list = TBot_List_getList( $hash );
    $ret = scalar( @list );
    
  } elsif($cmd eq 'queryAnswer') {
    # parameters cmd - queryAnswer <tbot> <peer> <querydata> 
    if ( $numberOfArgs != 4 ) {
      $ret = "queryAnswer requires a telegrambot peer and querydata to be specified";
    } else {
      Log3 $name, 4, "TBot_List_Get $name: queryAnswer requested tbot:".$args[1].":   peer:".$args[2].":   qdata:".$args[3].":";
    }
    
    my $tbot;
    my $tpeer;
    my $qdata = $args[3];
    
    if ( $qdata =~ s/^TBL_(.*)%(.*)$/$2/ ) {
      my $qname = $1;

      if ( $qname eq $name ) {
        # handle this only if name in query data is me

        if ( ! $ret ) {
          $tbot = $args[1];
          $ret = "No telegramBot specified :$tbot:" if ( ! TBot_List_isTBot( $hash, $tbot ) );
        }
        if ( ! $ret ) {
          $tpeer = AnalyzeCommandChain( $hash, "get $tbot peerId ".$args[2] );
          $ret = "No peer specified :$tbot: ".$args[2] if ( ! $tpeer );
        }
        
        # end uses a botname and a peer
        $ret = TBot_List_handler( $hash, $qdata, $tbot, $tpeer ) if ( ! $ret );
      }
      
    } else {
      # $ret = "query data does not contain a name and cmd separated with \% :$qdata: ".$args[1];
      # no return if qdata not in corresponding form
    }

  }
  
  Log3 $name, 4, "TBot_List_Get $name: $cmd ".(($ret)?"failed with :$ret: ":"done succesful ");

  return $ret
}

##############################
# attr function for setting fhem attributes for the device
sub TBot_List_Attr(@) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};

  Log3 $name, 5, "TBot_List_Attr $name: called ";

  return "\"TBot_List_Attr: \" $name does not exist" if (!defined($hash));

  if (defined($aVal)) {
    Log3 $name, 5, "TBot_List_Attr $name: $cmd  on $aName to $aVal";
  } else {
    Log3 $name, 5, "TBot_List_Attr $name: $cmd  on $aName to <undef>";
  }
  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value
  if ($cmd eq "set") {

    if ( ($aName eq 'optionDouble') ) {
      $aVal = ($aVal eq "1")? "1": "0";

    } elsif ( ($aName eq "confirmDelete" ) ||  ($aName eq "confirmUnsolicited" )  ||  ($aName eq "deleteOnly" )  ) {
      $aVal = ($aVal eq "1")? "1": "0";

    } elsif ($aName eq 'allowedPeers') {
      return "\"TBot_List_Attr: \" $aName needs to be given in digits - and space only" if ( $aVal !~ /^[[:digit:] -]*$/ );

    }

    $_[3] = $aVal;
  
  }

  return undef;
}
  
#####################################
#  notify function provide dev and 
# is corresponding to the delete command the opposite to the define function 
sub TBot_List_Notify($$)
{
  my ($hash,$dev) = @_;
  
  return undef if(!defined($hash) or !defined($dev));

  my $name = $hash->{NAME};
  my $events;

  my $devname = $dev->{NAME};
  
#  Debug "notify  name:".$name.":   - dev : ".$devname;
  if ( TBot_List_hasConfigTBot( $hash, $devname ) ) {
    # yes it is monitored 
    
    # grab events if not yet defined
    $events = deviceEvents($dev,0);
    
    TBot_List_handleEvents( $hash, $devname, $events );
  }

}


  
  
##############################################################################
##############################################################################
##
## Helper list handling
##
##############################################################################
##############################################################################

##############################################
# get the different config values
#
sub TBot_List_getConfigListname($)
{
  my ($hash) = @_;
  return $hash->{listname};
}
  
sub TBot_List_getConfigListno($)
{
  my ($hash) = @_;
  
  if ( ! defined($hash->{listno}) ) {
    TBot_List_calcListNo($hash);
  }
  
  return $hash->{listno};
}
  
sub TBot_List_getConfigPostMe($)
{
  my ($hash) = @_;
  return $hash->{postme};
}
sub TBot_List_isAllowed($$)
{
  my ($hash, $peer) = @_;
  my $name = $hash->{NAME};
  
  my $peers = AttrVal($name,'allowedPeers',undef);
  
  return 1 if ( ! $peers );

  $peers = " ".$peers." ";
  return ( $peers =~ / $peer / );
}

sub TBot_List_hasOptionDouble($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  return ( AttrVal($name,'optionDouble',0) ? 1:0 );
}

sub TBot_List_hasConfigTBot($$)
{
  my ($hash, $tbot) = @_;
  my $name = $hash->{NAME};
  
  my $bots = AttrVal($name,'telegramBots',undef);
  return 0 if ( ! $bots );

  $bots = " ".$bots." ";
#  Debug "Bots  :".$bots.":  tbot :".$tbot.":";
  
  return ( $bots =~ / $tbot / );
}



##############################################
# list or specific entry number
#
sub TBot_List_getList($;$)
{
  my ($hash, $entry) = @_;
  my $name = $hash->{NAME};

  my $rd = "postme".sprintf("%2.2d",TBot_List_getConfigListno($hash))."Name";
  if ( ReadingsVal(TBot_List_getConfigPostMe($hash),$rd,"") ne TBot_List_getConfigListname($hash) ) {
    Log3 $name, 1, "TBot_List_getList: list ".TBot_List_getConfigListname($hash)." not matching listno ".TBot_List_getConfigListno($hash);
    return undef;
  }
  
  $rd = "postme".sprintf("%2.2d",TBot_List_getConfigListno($hash))."Cont";
  my $listCont = ReadingsVal(TBot_List_getConfigPostMe($hash),$rd,"");
    
  $listCont =~ s/[\n\t\r\f]+/ /sg;
    
  my @entries = split( /,/, $listCont );
  
  if ( defined( $entry ) ) {
    return undef if ( ( $entry < 0 ) || ( $entry > scalar(@entries) ) );
    
    return $entries[$entry];
  }

  return @entries;
}




##############################################
# list or specific entry number
#
sub TBot_List_getTextList($)
{ 
  my ($hash) = @_;

  my @list = TBot_List_getList( $hash );
   
  return "<LEER>" if ( scalar( @list ) == 0 );
   
  return join("\r\n", @list );
}

##############################################
# set text message to wait for or undef
# undef, store, reply, textmsg, ...
sub TBot_List_setMsgId($$$;$$) {
  my ($hash, $tbot, $peer, $msgId, $postfix) = @_;

  my $key = $tbot."_".$peer.(defined($postfix)?"_".$postfix:"");
  if ( defined( $msgId ) ) {
    $msgId =~ s/\s//g;
    $hash->{inlinechats}{$key} = $msgId;
  } else {
    delete( $hash->{inlinechats}{$key} );
  }
}


##############################################
# set text message to wait for or undef
#
sub TBot_List_getMsgId($$$;$) {
  my ($hash, $tbot, $peer, $postfix) = @_;

  my $key = $tbot."_".$peer.(defined($postfix)?"_".$postfix:"");
  return $hash->{inlinechats}{$key};
}

##############################################
# translate multiple lines into comma separated list
#
sub TBot_List_changeMultiLine($) {
  my ($text) = @_;

  $text =~ s/[\n\t\r\f]+/,/sg;

  return $text;
}



##############################################################################
##############################################################################
##
## Handling of List in central routine from myUtils
##
##############################################################################
##############################################################################

##############################################
##############################################
# hash, tbot, events
#
sub TBot_List_handleEvents($$$)
{
  my ($hash, $tbot, $events ) = @_;
  my $name = $hash->{NAME};

  my $unsolic = AttrVal($name,"handleUnsolicited",0);
  
  # events - look for sentMsgId / msgReplyMsgId
  foreach my $event ( @{$events} ) {
    next if(!defined($event));
    
    # msgPeer is chat here in chats
    if ( $event =~ /sentMsgId\:/ ) {
      Log3 $name, 4, "TBot_List_handleEvents $name: found sentMsgId ". $event;
      my $msgChat = InternalVal( $tbot, "sentMsgPeerId", "" );  
      my $msgWait = TBot_List_getMsgId( $hash, $tbot, $msgChat, "textmsg" );
      my $msgSent = InternalVal( $tbot, "sentMsgText", "" );
      $msgSent =~ s/\s//g;
#      Debug "wait :".$msgWait.":   sent :".$msgSent.":    msgPeer/chat :$msgChat:"; 
      if ( defined( $msgWait ) && (  $msgSent eq $msgWait ) ) {
        my $arg = ReadingsVal($tbot,"sentMsgId","");
        
        # store key set means a reply is expected
        if ( defined( TBot_List_getMsgId( $hash, $tbot, $msgChat, "store") ) ) {
          # reply received
          TBot_List_setMsgId( $hash, $tbot, $msgChat, $arg, "reply");

          TBot_List_setMsgId( $hash, $tbot, $msgChat, undef, "store");

        } else {
        
          TBot_List_setMsgId( $hash, $tbot, $msgChat, $arg );

          # remove old entry ids from chg entries
          TBot_List_setMsgId( $hash, $tbot, $msgChat, undef, "entry");
        }
        
        # reset internal msg
        TBot_List_setMsgId( $hash, $tbot, $msgChat, undef, "textmsg" );
        
      }
      
    } elsif ( $event =~ /msgId\:/ ) {
      Log3 $name, 4, "TBot_List_handleEvents $name: found msgId ". $event;
      my $msgReplyId = ReadingsVal($tbot,"msgReplyMsgId","");
      my $msgChat = ReadingsVal( $tbot, "msgChatId", "" );  
      my $replyMsg = TBot_List_getMsgId( $hash, $tbot, $msgChat, "reply");
      my $hasChat = TBot_List_getMsgId( $hash, $tbot, $msgChat );

      # distinguish between reply (check for waiting reply)
      if ( length($msgReplyId) != 0 ) {
        # reply found
#        Debug "reply :".$replyMsg.":   rece reply :".$msgReplyId.":    msgPeer/chat :$msgChat:"; 
        if ( defined( $replyMsg ) && ( $replyMsg eq $msgReplyId ) ) {
          TBot_List_setMsgId( $hash, $tbot, $msgChat, undef, "reply");
          
          my $msgText = ReadingsVal( $tbot, "msgText", "" );

          # now check if an id of an entry was stored then this is edit
          my $entryno = TBot_List_getMsgId( $hash, $tbot, $msgChat, "entry");
          if ( defined( $entryno ) ) {
            TBot_List_setMsgId( $hash, $tbot, $msgChat, undef, "entry");

            TBot_List_handler( $hash, "list_chg-$entryno", $tbot, $msgChat, $msgText );
          } else {
            TBot_List_handler( $hash,  "list_add", $tbot, $msgChat, $msgText );
          }
        }
        
      } elsif( ( defined( $hasChat ) ) && ( ! defined( $replyMsg ) ) && ( $unsolic ) ) {
        # not waiting for reply but received message -> ask if entry should be added
        my $msgText = ReadingsVal( $tbot, "msgText", "" );  
        TBot_List_handler( $hash,  "list_expadd", $tbot, $msgChat, $msgText );
      }
      
    }
  }
}

##############################################
##############################################
# create an inline key for the keyboard
#  TBot_List_inlinekey( $hash, $entry, )
sub TBot_List_inlinekey($$$)
{
  my ($hash, $entry, $keycmd ) = @_;
  my $name = $hash->{NAME};
  
  return $entry.":TBL_".$name."\%".$keycmd;
}

##############################################
##############################################
# hash, cmd, bot, peer, opt: arg
#
sub TBot_List_handler($$$$;$)
{
  my ($hash, $cmd, $tbot, $peer, $arg ) = @_;
  my $name = $hash->{NAME};

  my $ret;

  Log3 $name, 4, "TBot_List_handler: $name - $tbot  peer :$peer:   cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");

  my $lname = TBot_List_getConfigListname($hash);
  my $msgId;
  my $chatId;
  my @list;
  
  my $donly = AttrVal($name,'deleteOnly',0);
  
  # in start case from group chat both ids will be given and need to be allowed
  ($peer, $chatId) = split( / /, $peer );
  
  $ret = "TBot_List_handler: $name - $tbot  ERROR - $peer peer not allowed" if ( ( ! $ret ) && ( ! TBot_List_isAllowed( $hash, $peer ) ) );
  $ret = "TBot_List_handler: $name - $tbot  ERROR - $chatId chat not allowed" if ( ( ! $ret ) && ( defined($chatId) ) && ( ! TBot_List_isAllowed( $hash, $peer ) ) );
  
  # get Msgid and list as prefetch
  if ( ! $ret ) {
    $chatId = TBot_List_getMsgId( $hash, $tbot, $peer, "chat" ) if ( ! defined($chatId) );
    $chatId = $peer if ( ! defined($chatId) );
    
    $msgId = TBot_List_getMsgId( $hash, $tbot, $peer );
    $msgId = TBot_List_getMsgId( $hash, $tbot, $chatId ) if ( ! defined( $msgId ) );

    @list = TBot_List_getList( $hash );
  }
  Log3 $name, 4, "TBot_List_handler: $name - after prefetch peer :$peer:  chatId :$chatId:   msgId :".($msgId?$msgId:"<undef>").": ";
  
  #####################  
  if ( $ret ) {
    # do nothing if error found already
#    Log 1,$ret;

  #####################  
  } elsif ( ( $cmd eq "list_ok" ) || ( $cmd eq "list_done" ) ) {
    # done means clean buttons and show only list
    my $textmsg = (defined($arg)?$arg:"DONE");   # default for done
    my $inline = " ";
    
    if ( $cmd eq "list_ok" ) {
      # get the list of entries in the list
      my $liste = "";
      foreach my $entry ( @list )  {
        $liste .= "\n    ".$entry; 
      }
    
      $textmsg = "Liste ".$lname;
      $textmsg .= " ist leer " if ( scalar(@list) == 0 );
      $textmsg .= " : $arg " if ( defined($arg) );
      $textmsg .= $liste;
    }

    if ( defined($msgId ) ) {
      # show final list 
      AnalyzeCommandChain( $hash, "set ".$tbot." queryEditInline $msgId ".'@'.$chatId." $inline $textmsg" );
      TBot_List_setMsgId( $hash, $tbot, $chatId );
      TBot_List_setMsgId( $hash, $tbot, $peer, undef, "chat" );
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }
    
  #####################  
  } elsif ( ( $cmd eq "list" ) || ( $cmd eq "list_edit" ) ) {
    # list means create button table with list entries
    
    # start the inline
    my $inline = "";
    
    # get the list of entries in the list
    my $nre = 0;
    
    my $double = (TBot_List_hasOptionDouble( $hash )?1:0);
    foreach my $entry (  @list ) {
      $entry =~ s/[\(\):]/_/g;

      if ( $double == 1 ) {
        $inline .= "(".TBot_List_inlinekey( $hash, $entry, "list_idx-".$nre ); 
        $double = 2;
      } elsif ( $double == 2 ) {
        $inline .= "|".TBot_List_inlinekey( $hash, $entry, "list_idx-".$nre ) .") "; 
        $double = 1;
      } else {
        $inline .= "(".TBot_List_inlinekey( $hash, $entry, "list_idx-".$nre ) .") "; 
      }
      $nre++;
    }
    
    $inline .= ") " if ( $double == 2 );
    
    $inline .= "(".TBot_List_inlinekey( $hash, "ok", "list_ok" );
    
    if ( $donly ) {
      $inline .=  "|".TBot_List_inlinekey( $hash, "Leeren", "list_askclr" ).")";
    } else {
      $inline .=  "|".TBot_List_inlinekey( $hash, "ändern", "list_menu" )."|".
                  TBot_List_inlinekey( $hash, "hinzu", "list_askadd" ).")";
    }
    
    my $textmsg = "Liste ".$lname;
    $textmsg .= " ist leer " if ( scalar(@list) == 0 );
    $textmsg .= " : $arg " if ( defined($arg) );
    
    if ( $cmd eq "list" ) {
    
      # remove msgId if existing
      if ( defined($msgId ) ) {
        # done old list now and start a new list message
        TBot_List_handler( $hash,  "list_done", $tbot, $peer, "wurde beendet" );
      } else {
        # there might be still a dialog in another chat
        my $oldchatId = TBot_List_getMsgId( $hash, $tbot, $peer, "chat" );
        TBot_List_handler( $hash,  "list_done", $tbot, $peer, "wurde beendet" ) if ( $oldchatId && ( defined( TBot_List_getMsgId( $hash, $tbot, $oldchatId ) ) ) );
      }
      
      # store text msg to recognize msg id in dummy
      TBot_List_setMsgId( $hash, $tbot, $chatId, $textmsg, "textmsg" );
      
      # store chat
      TBot_List_setMsgId( $hash, $tbot, $peer, $chatId, "chat" );
      
      # send msg and keys
      AnalyzeCommandChain( $hash, "set ".$tbot." queryInline ".'@'.$chatId." $inline $textmsg" );
      
    } else {
      if ( defined($msgId ) ) {
        # show new list 
        AnalyzeCommandChain( $hash, "set ".$tbot." queryEditInline $msgId ".'@'.$chatId." $inline $textmsg" );
      } else {
        $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
      }
    }
    
  #####################  
  } elsif ( $cmd =~ /^list_idx-(\d+)$/ ) {
    # means change the entry or delete - ask for which option
    my $no = $1;
    
    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {
    
      # post new msg to ask for change
      if ( defined($msgId ) ) {
        # show ask for removal
        my $textmsg = "Liste ".$lname."\nEintrag ".($no+1)." (".$list[$no].") ?";
        # show ask msgs (depending on attr)
        my $indata = ( AttrVal($name,'confirmDelete',1) ? "list_rem-$no" : "list_remyes-$no" );
        my $inline = "(".TBot_List_inlinekey( $hash, "Entfernen", $indata );
        
        if ( ! $donly ) {
          $inline .= "|".TBot_List_inlinekey( $hash, "Aendern", "list_askchg-$no" )."|".
                        TBot_List_inlinekey( $hash, "Nach Oben", "list_totop-$no" );
        }
        $inline .= "|".TBot_List_inlinekey( $hash, "Zurueck", "list_edit" ).")";
        
        AnalyzeCommandChain( $hash, "set ".$tbot." queryEditInline $msgId ".'@'.$chatId." $inline $textmsg" );
      } else {
        $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
      }
    
    }
    
  #####################  
  } elsif ( $cmd =~ /^list_totop-(\d+)$/ ) {
    # totop means make it first entry in the 
    
    my $no = $1;
    
    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {
    
      my $topentry = $list[$no];
      # remove from array the entry with the index 
      splice(@list, $no, 1);    
      
      # add it at the beginning
      unshift @list, $topentry;

      my $text = join(",", @list );
      
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." clear $lname " );
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." add $lname $text" );
    
      # show updated list -> call recursively
      TBot_List_handler( $hash,  "list_edit", $tbot, $peer, " Nach oben gesetzt" );
    }
 
  #####################  
  } elsif ( $cmd =~ /^list_rem-(\d+)$/ ) {
    # means remove a numbered entry from list - first ask
    my $no = $1;
    
    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {
    
      # post new msg to ask for removal
      if ( defined($msgId ) ) {
        # show ask for removal
        my $textmsg = "Liste ".$lname."\nSoll der Eintrag ".($no+1)." (".$list[$no].") entfernt werden?";
        # show ask msg 
        my $inline = "(".TBot_List_inlinekey( $hash, "Ja", "list_remyes-$no" )."|".TBot_List_inlinekey( $hash, "Nein", "list_edit" ).")";
        AnalyzeCommandChain( $hash, "set ".$tbot." queryEditInline $msgId ".'@'.$chatId." $inline $textmsg" );
      } else {
        $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
      }
    }
     
  #####################  
  } elsif ( $cmd =~ /^list_remyes-(\d+)$/ ) {
    # means remove a numbered entry from list - now it is confirmed
    my $no = $1;
    
    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {
    
      # remove from array the entry with the index 
      splice(@list, $no, 1);    

      my $text = join(",", @list );
      
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." clear $lname " );
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." add $lname $text" );
      
      # show updated list -> call recursively
      TBot_List_handler( $hash,  "list_edit", $tbot, $peer, " Eintrag geloescht" );
    
    }
    
  #####################  
  } elsif ( $cmd eq "list_menu" ) {
    # post new msg to ask what to do on list
    if ( defined($msgId ) ) {
      # show menu
      my $textmsg = "Liste ".$lname." ?";
      # show menu msg 
      my $inline = "(".TBot_List_inlinekey( $hash, "Sortieren", "list_asksrt" )."|".TBot_List_inlinekey( $hash, "Leeren", "list_askclr" )."|".
                TBot_List_inlinekey( $hash, "Zurück", "list_edit" ).")";
      AnalyzeCommandChain( $hash, "set ".$tbot." queryEditInline $msgId ".'@'.$chatId." $inline $textmsg" );
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }

  #####################  
  } elsif ( $cmd eq "list_asksrt" ) {
    # post new msg to ask for srt
    if ( defined($msgId ) ) {
      # show ask for sort
      my $textmsg = "Liste ".$lname." sortieren ?";
      # show ask msg 
      my $inline = "(".TBot_List_inlinekey( $hash, "Ja - von A-Z", "list_srtyes1" )."|".TBot_List_inlinekey( $hash, "Ja - von Z-A", "list_srtyes2" )."|".
                TBot_List_inlinekey( $hash, "Nein", "list_edit" ).")";
      AnalyzeCommandChain( $hash, "set ".$tbot." queryEditInline $msgId ".'@'.$chatId." $inline $textmsg" );
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }

  #####################  
  } elsif ( $cmd =~ /list_srtyes(\d)/ ) {
    my $stype = $1;
    # means sort all entries - now it is confirmed
    
    # sort depending on stype
    if ( scalar(@list) > 0 )  {
      if ( $stype == 1 ) {
        @list = sort {$a cmp $b} @list;
      } else {
        @list = sort {$b cmp $a} @list;
      }
      my $text = join( ",", @list );
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." clear $lname " );
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." add $lname $text" );     
    }
    
    # show updated list -> call recursively
    TBot_List_handler( $hash,  "list_edit", $tbot, $peer, " Liste sortiert" );
    
          
  #####################  
  } elsif ( $cmd eq "list_askclr" ) {
    # post new msg to ask for clr
    if ( defined($msgId ) ) {
      # show ask for removal
      my $textmsg = "Liste ".$lname."\nSoll die gesamte Liste ".scalar(@list)." Einträge gelöscht werden?";
      # show ask msg 
      my $inline = "(".TBot_List_inlinekey( $hash, "Ja - Liste löschen", "list_clryes" )."|".TBot_List_inlinekey( $hash, "Nein", "list_edit" ).")";
      AnalyzeCommandChain( $hash, "set ".$tbot." queryEditInline $msgId ".'@'.$chatId." $inline $textmsg" );
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }

  #####################  
  } elsif ( $cmd eq "list_clryes" ) {
    # means remove all entries - now it is confirmed
    AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." clear $lname " );

    # show updated list -> call recursively
    TBot_List_handler( $hash,  "list_edit", $tbot, $peer, " Liste geloescht" );
    
          
  #####################  
  } elsif ( $cmd eq "list_askadd" ) {
    TBot_List_setMsgId( $hash, $tbot, $chatId, $msgId, "store" );

    my $textmsg = "Liste ".$lname." Neuen Eintrag eingeben:";
    
    # store text msg to recognize msg id in dummy
    TBot_List_setMsgId( $hash, $tbot, $chatId, $textmsg, "textmsg" );
    
    # means ask for an entry to be added to the list
    AnalyzeCommandChain( $hash, "set ".$tbot." msgForceReply ".'@'.$chatId." $textmsg" );

  #####################  
  } elsif ( $cmd eq "list_add" ) {
    # means add entry to list

    $arg = TBot_List_changeMultiLine( $arg );
    
    # ! means put on top
    if ( $arg =~ /^\!(.+)$/ ) {
      my $text = $1;
      foreach my $entry (  @list ) {
        $text .= ",".$entry ;
      }
       
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." clear $lname " );
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." add $lname $text" );
    
    } else {
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." add $lname ".$arg );
    }
    
    if ( defined($msgId ) ) {
      # show new list -> call recursively
      $ret = "Eintrag hinzugefuegt";
      TBot_List_handler( $hash,  "list", $tbot, $peer, $ret );
      $ret = undef;
      
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }
    
  #####################  
  } elsif ( $cmd =~ /^list_askchg-(\d+)$/ ) {
    my $no = $1;

    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {

      TBot_List_setMsgId( $hash, $tbot, $chatId, $msgId, "store" );
      
      # remove old entry ids from chg entries
      TBot_List_setMsgId( $hash, $tbot, $chatId, $no, "entry" );

      my $textmsg = "Liste ".$lname." Eintrag ".($no+1)." ändern : ".$list[$no];
      
      # store text msg to recognize msg id in dummy
      TBot_List_setMsgId( $hash, $tbot, $chatId, $textmsg, "textmsg" );

      # means ask for an entry to be added to the list
      AnalyzeCommandChain( $hash, "set ".$tbot." msgForceReply ".'@'.$chatId." $textmsg" );
      
    }

  #####################  
  } elsif ( $cmd =~ /^list_chg-(\d+)$/ ) {
    # means add entry to list
    my $no = $1;
    
    $arg = TBot_List_changeMultiLine( $arg );
    
    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {
      my $nre = 0;
      my $text = "";
      foreach my $entry (  @list ) {
        if ( $nre == $no ) {
          $text .= ",".$arg ;
        } else {
          $text .= ",".$entry ;
        }
        $nre++;
      }
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." clear $lname " );
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." add $lname $text" );
    }
    
    if ( defined($msgId ) ) {
      # show new list -> call recursively
      $ret = "Eintrag gändert";
      TBot_List_handler( $hash,  "list", $tbot, $peer, $ret );
      $ret = undef;
      
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }
    
    
  #####################  
  } elsif ( $cmd =~ /^list_expadd$/ ) {
    # means unsolicited message ask for adding - first ask
    
    $arg = TBot_List_changeMultiLine( $arg );
    
    my $textmsg = "Liste ".$lname."\nSoll der Eintrag ".$arg." hinzugefuegt werden?";
    if ( defined($msgId ) ) {
      # store text for adding 
      TBot_List_setMsgId( $hash, $tbot, $chatId, $arg, "expadd" );
      
      if ( AttrVal($name,'confirmUnsolicited',1) ) {
        my $inline = "(".TBot_List_inlinekey( $hash, "Ja", "list_expaddyes" )."|".TBot_List_inlinekey( $hash, "Nein", "list_edit" ).")";
        AnalyzeCommandChain( $hash, "set ".$tbot." queryEditInline $msgId ".'@'.$chatId." $inline $textmsg" );
      } else {
        # directly add entry  --> call recursively
        TBot_List_handler( $hash,  "list_expaddyes", $tbot, $peer );  
      }
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }

  #####################  
  } elsif ( $cmd eq "list_expaddyes" ) {
    # means add entry to list
    
    my $addentry =  TBot_List_getMsgId( $hash, $tbot, $chatId, "expadd" );

    if ( defined($addentry ) ) {
      AnalyzeCommandChain( $hash, "set ".TBot_List_getConfigPostMe($hash)." add $lname ".$addentry );
      # show list again -> call recursively
      if ( defined($msgId ) ) {
        TBot_List_handler( $hash,  "list_edit", $tbot, $peer, " Eintrag hinzugefuegt" );
      } else {
        $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer: chat :$chatId:  cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
      }
    }
    
  }

  Log3 $name, 1, $ret if ( $ret );

  return $ret;
  
}

  

   
  


##############################################################################
##############################################################################
##
## HELPER
##
##############################################################################
##############################################################################


#####################################
#  notify function provide dev and 
# is corresponding to the delete command the opposite to the define function 
sub TBot_List_isTBot($$)
{
  my ($hash,$tbot) = @_;
  
  my @tbots = devspec2array( "TYPE=TelegramBot" );
  foreach my $abot ( @tbots ) {
    return 1 if ( $abot eq $tbot ) ;
  }
  
  return 0;
}

#####################################
#  calculate listno where needed
sub TBot_List_calcListNo($)
{
  my ($hash) = @_;

  # listno will be calculated at start of new dialog
  my $pcnt = ReadingsNum($hash->{postme},"postmeCnt",0);
  my $curr = 0;
  my $listNo;

  while ( $curr < $pcnt ) {
    $curr++;
    my $rd = "postme".sprintf("%2.2d",$curr)."Name";
#        Debug "rd : ".$rd;
    if ( ReadingsVal($hash->{postme},$rd,"") eq $hash->{listname} ) {
      $listNo = $curr;
      last;
    }
  }

  $hash->{listno} = $listNo;
  
  return $listNo;
}


#####################################
#  INTERNAL: Get Id for a camera or list of all cameras if no name or id was given or undef if not found
sub TBot_List_CheckSetGet( $$$ ) {
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

    return "TBot_List_Set: Unknown argument $cmd, choose one of " . join(" ", @cList);
  } # error unknown cmd handling
  return undef;
}

##############################################################################
##############################################################################
##
## Setup
##
##############################################################################
##############################################################################

  


######################################
#  make sure a reinitialization is triggered on next update
#  
sub TBot_List_Setup($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "TBot_List_Setup $name: called ";

  $hash->{STATE} = "Undefined";
  
  my %sets = (
    "start" => undef,
    "end" => undef,
    "reset" => undef,

  );

  my %gets = (
    "queryAnswer" => undef,
    "textList" => undef,
    "list" => undef,
    "count" => undef,

  );

  $hash->{getoptions} = \%gets;
  $hash->{setoptions} = \%sets;
  
  my %hh = ();
  $hash->{inlinechats} = \%hh;
  
  # get global notifications and from all telegramBots
  $hash->{NOTIFYDEV} = "global,TYPE=TelegramBot";

  $hash->{STATE} = "Defined";

  Log3 $name, 4, "TBot_List_Setup $name: ended ";

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
=item summary    Dialogs for PostMe lists in TelegramBot 
=item summary_DE Dialoge über TelegramBot für PostMe-Listen
=begin html

<a name="TBot_List"></a>
<h3>TBot_List</h3>
<ul>

  This module connects for allowing inline keyboard interactions between a telegramBot and PostMe lists.
  
  <br><br>
  <a name="TBot_Listdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TBot_List &lt;PostMe device&gt; &lt;listname&gt; </code>
    <br><br>
    Defines a TBot_List device, which will allow interaction between the telegrambot and the postme device
    <br><br>
    Example: <code>define testtbotlist TBot_List testposteme testlist</code><br>
    <br><br>
    Note: The module relies on events send from the corresponding TelegramBot devices. Specifically changes to the readings <code>sentMsgId</code> and <code>msgReplyMsgId</code> are required to enable to find the corresponding message ids to be able to modify messages. This needs to be taken into account when using the attributes event-on-*-reading on the TelegramBot device.<br>
    <br>
  </ul>
  <br><br>   
  
  <a name="TBot_Listset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br>
    where &lt;what&gt; / &lt;value&gt; is one of

  <br><br>
    <li><code>start &lt;telegrambot name&gt; [ &lt;peerid&gt; ]</code><br>Initiate a new dialog for the given peer (or the last peer sending a message on the given telegrambot)
    </li>
    <li><code>end &lt;telegrambot name&gt; &lt;peerid&gt;</code><br>Finalize a new dialog for the given peer  on the given telegrambot
    </li>
    
  </ul>

  <br><br>

  <a name="TBot_Listget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br>
    where &lt;what&gt; / &lt;value&gt; is one of

  <br><br>
    <li><code>queryAnswer &lt;telegrambot name&gt; &lt;peerid&gt; &lt;queryData&gt; </code><br>Get the queryAnswer for the given query data in the dialog (will be called internally by the telegramBot on receiving querydata) 
    </li>
    
    <li><code>textList</code><br>Returns a multiline string containing the list elements or <Leer>  
    </li>
    
    <li><code>list</code><br>Returns a multiline string containing the list elements or an empty String  
    </li>
    
  </ul>

  <br><br>

  <a name="TBot_Listattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>telegramBots &lt;list of telegramBot names separated by space&gt;</code><br>This attribute takes the names of telegram bots, that are monitored by this Tbot_List device
    </li> 

    <li><code>optionDouble &lt;1 or 0&gt;</code><br>Specify if the list shall be done in two columns (double=1) or in a single column (double=0 or not set).
    </li> 
    
    <li><code>allowedPeers &lt;list of peer ids&gt;</code><br>If specifed further restricts the users for the given list to these peers. It can be specifed in the same form as in the telegramBot msg command but without the leading @ (so ids will be just numbers).
    </li> 

    <li><code>handleUnsolicited &lt;1 or 0&gt;</code><br>If set to 1 and new messages are sent in a chat where a dialog of this list is active the bot will ask if an entry should be added. This helps for accidential messages without out first pressing the "add" button.
    </li> 
    
    <li><code>confirmDelete &lt;1 or 0&gt;</code><br>If set to 1 the bot will ask for a confirmation if an entry should be deleted. This is the default. With a value of 0 the additional confirmation will not be requested.
    </li> 
    
    <li><code>deleteOnly &lt;1 or 0&gt;</code><br>If set to 1 the bot will only allow deletion of entries or the complete list (no new entries or entry text can be changed - neither sorting or similar will be possible). Default is 0 (all changes allowed).
    </li> 
    
  </ul>

  <br><br>


    <a name="TBot_Listreadings"></a>
  <b>Readings</b>
  
  <ul>
    <li>currently none</li> 
    
    <br>
    
  </ul> 

  <br><br>   
</ul>



=end html
=cut
