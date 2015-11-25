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
# $Id$
#
##############################################################################
# 0.0 2015-09-16 Started
# 1.0 2015-10-17 Initial SVN-Version 
#   
#   INTERNAL: sendIt allows providing a keyboard json
#   Favorites sent as keyboard
#   allow sending to contacts not in the contacts list (by giving id of user)
#   added comment on save (statefile) for correct operation in documentation
#   contacts changed on new contacts found
#   saveStateOnContactChange attribute to disaloow statefile save on contact change
#   writeStatefile on contact change
#   make contact restore simpler --> whenever new contact found write all contacts into log with loglevel 1
#   Do not allow shutdown as command for execution
#   ret from command handlings logged
#   maxReturnSize for command results
#   limit sentMsgTxt internal to 1000 chars (even if longer texts are sent)
#   contact reading now written in contactsupdate before statefile written
#   documentation corrected - forum#msg350873
#   cleanup on comments 
#   removed old version changes to history.txt
#   add digest readings for error
#   attribute to reduce logging on updatepoll errors - pollingVerbose:0_None,1_Digest,2_Log - (no log, default digest log daily, log every issue)
#   documentation for pollingverbose
#   reset / log polling status also in case of no error
#   removed remark on timeout of 20sec
#   LastCommands returns keyboard with commands 
#   added send / image command for compatibility with yowsup
#   image not in cmd list to avoid this being first option
#   FIX: Keyboard removed after fac execution
#   Do not use contacts from msg since this might be NON-Telegram contact
#   cmdReturnEmptyResult - to suppress empty results from command execution
#   prev... Readings do not trigger events (to reduce log content)
#   Contacts reading only changed if string is not equal
#   Need to replace \n again with Chr10 - linefeed due to a telegram change - FORUM #msg363825
# 1.1 2015-11-24 keyboards added, log changes and multiple smaller enhancements
#   
#   
#   
##############################################################################
# TASKS 
#
#   allow multiple accounts to be specified
#   
#   allow keyboards in the device api
#   
#   dialog function
#   
#   allowed commands
#   
#   comment on a single telegram bot api
#   
#
##############################################################################
# Ideas / Future
#   add replyTo
#
##############################################################################

package main;

use strict;
use warnings;

use HttpUtils;
use Encode;
use JSON; 

use File::Basename;

use Scalar::Util qw(reftype looks_like_number);

#########################
# Forward declaration
sub TelegramBot_Define($$);
sub TelegramBot_Undef($$);

sub TelegramBot_Set($@);
sub TelegramBot_Get($@);

sub TelegramBot_Callback($$$);


#########################
# Globals
my %sets = (
	"message" => "textField",
	"msg" => "textField",
	"send" => "textField",

	"sendImage" => "textField",
#	"image" => "textField",

	"replaceContacts" => "textField",
	"reset" => undef,

	"zDebug" => "textField"

);

my %deprecatedsets = (

	"messageTo" => "textField",   
	"sendImageTo" => "textField", 
	"sendPhoto" => "textField",   
	"sendPhotoTo" => "textField"
);

my %gets = (
#	"msgById" => "textField"
);

my $TelegramBot_header = "agent: TelegramBot/1.0\r\nUser-Agent: TelegramBot/1.0\r\nAccept: application/json\r\nAccept-Charset: utf-8";


my %TelegramBot_hu_upd_params = (
                  url        => "",
                  timeout    => 5,
                  method     => "GET",
                  header     => $TelegramBot_header,
                  isPolling  => "update",
                  hideurl    => 1,
                  callback   => \&TelegramBot_Callback
);

my %TelegramBot_hu_do_params = (
                  url        => "",
                  timeout    => 30,
                  method     => "GET",
                  header     => $TelegramBot_header,
                  hideurl    => 1,
                  callback   => \&TelegramBot_Callback
);


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
	$hash->{SetFn}      = "TelegramBot_Set";
	$hash->{AttrFn}     = "TelegramBot_Attr";
	$hash->{AttrList}   = "defaultPeer defaultPeerCopy:0,1 pollingTimeout cmdKeyword cmdSentCommands favorites:textField-long cmdFavorites cmdRestrictedPeer cmdTriggerOnly:0,1 saveStateOnContactChange:1,0 maxFileSize maxReturnSize cmdReturnEmptyResult:1,0 pollingVerbose:1_Digest,2_Log,0_None ".
						$readingFnAttributes;           
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
  if( int(@a) != 3 ) {
    $errmsg = "syntax error: define <name> TelegramBot <APIid> ";
    Log3 $name, 1, "TelegramBot $name: " . $errmsg;
    return $errmsg;
  }
  
  if ( $a[2] =~ /^([[:alnum:]]|[-:_])+[[:alnum:]]+([[:alnum:]]|[-:_])+$/ ) {
    $hash->{Token} = $a[2];
  } else {
    $errmsg = "specify valid API token containing only alphanumeric characters and -: characters: define <name> TelegramBot  <APItoken> ";
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

  $hash->{HU_UPD_PARAMS} = \%TelegramBot_hu_upd_params;
  $hash->{HU_DO_PARAMS} = \%TelegramBot_hu_do_params;

  TelegramBot_Setup( $hash );

  return $ret; 
}

#####################################
#  Undef function is corresponding to the delete command the opposite to the define function 
#  Cleanup the device specifically for external ressources like connections, open files, 
#		external memory outside of hash, sub processes and timers
sub TelegramBot_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, "TelegramBot_Undef $name: called ";

  HttpUtils_Close(\%TelegramBot_hu_upd_params); 
  
  HttpUtils_Close(\%TelegramBot_hu_do_params); 

  RemoveInternalTimer($hash);

  Log3 $name, 4, "TelegramBot_Undef $name: done ";
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
# State function to ensure contacts internal hash being reset on Contacts Readings Set
sub TelegramBot_State($$$$) {
	my ($hash, $time, $name, $value) = @_; 
	
#  Log3 $hash->{NAME}, 4, "TelegramBot_State called with :$name: value :$value:";

  if ($name eq 'Contacts')  {
    TelegramBot_CalcContactsHash( $hash, $value );
    Log3 $hash->{NAME}, 4, "TelegramBot_State Contacts hash has now :".scalar(keys $hash->{Contacts}).":";
	}
	
	return undef;
}
 
####################################
# set function for executing set operations on device
sub TelegramBot_Set($@)
{
	my ( $hash, $name, @args ) = @_;
	
  Log3 $name, 4, "TelegramBot_Set $name: called ";

	### Check Args
	my $numberOfArgs  = int(@args);
	return "TelegramBot_Set: No value specified for set" if ( $numberOfArgs < 1 );

	my $cmd = shift @args;

  Log3 $name, 4, "TelegramBot_Set $name: Processing TelegramBot_Set( $cmd )";

	if( (!exists($sets{$cmd})) && (!exists($deprecatedsets{$cmd})) ) {
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

  my $ret = undef;
  
	if( ($cmd eq 'message') || ($cmd eq 'msg') || ($cmd eq 'send') ) {
    if ( $numberOfArgs < 2 ) {
      return "TelegramBot_Set: Command $cmd, no text (and no optional peer) specified";
    }
    my $peer;
    if ( $args[0] =~ /^@(..+)$/ ) {
      $peer = $1;
      shift @args;
      return "TelegramBot_Set: Command $cmd, no text specified" if ( $numberOfArgs < 3 );
    } else {
      $peer = AttrVal($name,'defaultPeer',undef);
      return "TelegramBot_Set: Command $cmd, without explicit peer requires defaultPeer being set" if ( ! defined($peer) );
    }

    # should return undef if succesful
    Log3 $name, 4, "TelegramBot_Set $name: start message send ";
    my $arg = join(" ", @args );
    $ret = TelegramBot_SendIt( $hash, $peer, $arg, undef, 1 );

  } elsif ( ($cmd eq 'sendPhoto') || ($cmd eq 'sendImage') || ($cmd eq 'image') ) {
    if ( $numberOfArgs < 2 ) {
      return "TelegramBot_Set: Command $cmd, need to specify filename ";
    }

    my $peer;
    if ( $args[0] =~ /^@(..+)$/ ) {
      $peer = $1;
      shift @args;
      return "TelegramBot_Set: Command $cmd, need to specify filename" if ( $numberOfArgs < 3 );
    } else {
      $peer = AttrVal($name,'defaultPeer',undef);
      return "TelegramBot_Set: Command $cmd, without explicit peer requires defaultPeer being set" if ( ! defined($peer) );
    }

    # should return undef if succesful
    my $file = shift @args;
    $file = $1 if ( $file =~ /^\"(.*)\"$/ );
    
    my $caption;
    $caption = join(" ", @args ) if ( int(@args) > 0 );

    Log3 $name, 5, "TelegramBot_Set $name: start photo send ";
#    $ret = "TelegramBot_Set: Command $cmd, not yet supported ";
    $ret = TelegramBot_SendIt( $hash, $peer, $file, $caption, 0 );

  # DEPRECATED
	} elsif($cmd eq 'messageTo') {
    if ( $numberOfArgs < 3 ) {
      return "TelegramBot_Set: Command $cmd, need to specify peer and text ";
    }

    # should return undef if succesful
    my $peer = shift @args;
    my $arg = join(" ", @args );

    Log3 $name, 4, "TelegramBot_Set $name: start message send ";
    $ret = TelegramBot_SendIt( $hash, $peer, $arg, undef, 1 );
 
  # DEPRECATED
  } elsif ( ($cmd eq 'sendPhotoTo') || ($cmd eq 'sendImageTo') ) {
    if ( $numberOfArgs < 3 ) {
      return "TelegramBot_Set: Command $cmd, need to specify peer and text ";
    }

    # should return undef if succesful
    my $peer = shift @args;

    my $file = shift @args;
    $file = $1 if ( $file =~ /^\"(.*)\"$/ );
    
    my $caption;
    $caption = join(" ", @args ) if ( $numberOfArgs > 3 );

    Log3 $name, 5, "TelegramBot_Set $name: start photo send to $peer";
    $ret = TelegramBot_SendIt( $hash, $peer, $file, $caption, 0 );

  } elsif($cmd eq 'zDebug') {
    # for internal testing only
    Log3 $name, 5, "TelegramBot_Set $name: start debug option ";
#    delete $hash->{sentMsgPeer};

    
  # BOTONLY
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

  Log3 $name, 5, "TelegramBot_Get $name: Processing TelegramBot_Get( $cmd )";

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

  
  my $ret = undef;
  
	if($cmd eq 'msgById') {
    if ( $numberOfArgs != 2 ) {
      return "TelegramBot_Set: Command $cmd, no msg id specified";
    }
    Log3 $name, 5, "TelegramBot_Get $name: $cmd not supported yet";

    # should return undef if succesful
   $ret = TelegramBot_GetMessage( $hash, $arg );
  }
  
  Log3 $name, 5, "TelegramBot_Get $name: done with $ret: ";

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
	if ($cmd eq "set") {
    if ($aName eq 'defaultPeer') {
			$attr{$name}{'defaultPeer'} = $aVal;

		} elsif ($aName eq 'cmdKeyword') {
			$attr{$name}{'cmdKeyword'} = $aVal;

		} elsif ($aName eq 'cmdSentCommands') {
			$attr{$name}{'cmdSentCommands'} = $aVal;

		} elsif ($aName eq 'cmdFavorites') {
			$attr{$name}{'cmdFavorites'} = $aVal;

		} elsif ($aName eq 'favorites') {
			$attr{$name}{'favorites'} = $aVal;

		} elsif ($aName eq 'cmdRestrictedPeer') {
      $aVal =~ s/^\s+|\s+$//g;
      $attr{$name}{'cmdRestrictedPeer'} = $aVal;
      
		} elsif ($aName eq 'defaultPeerCopy') {
			$attr{$name}{'defaultPeerCopy'} = ($aVal eq "1")? "1": "0";

		} elsif ($aName eq 'saveStateOnContactChange') {
			$attr{$name}{'saveStateOnContactChange'} = ($aVal eq "1")? "1": "0";

		} elsif ($aName eq 'cmdReturnEmptyResult') {
			$attr{$name}{'cmdReturnEmptyResult'} = ($aVal eq "1")? "1": "0";

		} elsif ($aName eq 'cmdTriggerOnly') {
			$attr{$name}{'cmdTriggerOnly'} = ($aVal eq "1")? "1": "0";

      } elsif ($aName eq 'maxFileSize') {
      if ( $aVal =~ /^[[:digit:]]+$/ ) {
        $attr{$name}{'maxFileSize'} = $aVal;
      }

		} elsif ($aName eq 'maxReturnSize') {
      if ( $aVal =~ /^[[:digit:]]+$/ ) {
        $attr{$name}{'maxReturnSize'} = $aVal;
      }

    } elsif ($aName eq 'pollingTimeout') {
      if ( $aVal =~ /^[[:digit:]]+$/ ) {
        $attr{$name}{'pollingTimeout'} = $aVal;
      }
      # let all existing methods run into block
      RemoveInternalTimer($hash);
      $hash->{POLLING} = -1;
      
      # wait some time before next polling is starting
      TelegramBot_ResetPolling( $hash );

    }
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
# INTERNAL: Check for cmdkeyword given 
sub TelegramBot_checkCmdKeyword($$$$) {
  my ($hash, $mpeernorm, $mtext, $attrName ) = @_;
  my $name = $hash->{NAME};

  my $cmd;
  
  # command key word aus Attribut holen
  my $ck = AttrVal($name,$attrName,undef);
  
#  Log3 $name, 3, "TelegramBot_checkCmdKeyword $name: check :".$mtext.":   against defined :".$ck.":   results in ".index($mtext,$ck);

  return $cmd if ( ! defined( $ck ) );

  return $cmd if ( index($mtext,$ck) != 0 );

  $cmd = substr( $mtext, length($ck) );
  $cmd =~ s/^\s+|\s+$//g;

  # get human readble name for peer
  my $pname = TelegramBot_GetFullnameForContact( $hash, $mpeernorm );

  # validate security criteria for commands and return cmd if succesful
  return $cmd if ( TelegramBot_checkAllowedPeer( $hash, $mpeernorm ) );

   # unauthorized fhem cmd
  Log3 $name, 1, "TelegramBot_checkCmdKeyword($attrName) unauthorized cmd from user :$pname: ($mpeernorm) \n  Cmd: $cmd";
  my $ret =  "UNAUTHORIZED: TelegramBot fhem request for $attrName from user :$pname: ($mpeernorm) \n  Cmd: $cmd";
  
  # send unauthorized to defaultpeer
  my $defpeer = AttrVal($name,'defaultPeer',undef);
  $defpeer = TelegramBot_GetIdForPeer( $hash, $defpeer ) if ( defined( $defpeer ) );
  if ( defined( $defpeer ) ) {
    AnalyzeCommand( undef, "set $name message $ret", "" );
  }
  
  return undef;
}
    

#####################################
#####################################
# INTERNAL: handle sentlast and favorites
sub TelegramBot_SentFavorites($$$$) {
  my ($hash, $mpeernorm, $mtext, $mid ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  my $cmd = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mtext, 'cmdFavorites' );
  return $ret if ( ! defined( $cmd ) );
    
  Log3 $name, 4, "TelegramBot_SentFavorites cmd correct peer ";

  my $slc =  AttrVal($name,'favorites',"");
  Log3 $name, 4, "TelegramBot_SentFavorites Favorites :$slc: ";
  my @clist = split( /;/, $slc);
  
  $cmd = $1 if ( $cmd =~ /^\s*([0-9]+)[^0-9=]*=.*$/ );
  
  # if given a number execute the numbered favorite as a command
  if ( looks_like_number( $cmd ) ) {
    return $ret if ( $cmd == 0 );
    my $cmdId = ($cmd-1);
#    Log3 $name, 3, "TelegramBot_SentFavorites exec cmd :$cmdId: ";
    if ( ( $cmdId >= 0 ) && ( $cmdId < scalar( @clist ) ) ) { 
      $cmd = $clist[$cmdId];
      return TelegramBot_ExecuteCommand( $hash, $mpeernorm, $cmd );
    } else {
      Log3 $name, 3, "TelegramBot_SentFavorites cmd id not defined :($cmdId+1): ";
    }
    
  }
  
  # ret not defined means no favorite found that matches cmd or no fav given in cmd
  if ( ! defined( $ret ) ) {
      my $cnt = 0;
      my @keys = ();

      my $fcmd = AttrVal($name,'cmdFavorites',undef);
      
      foreach my $cs (  @clist ) {
        $cnt += 1;
        my @tmparr = ( $fcmd.$cnt." = ".$cs );
        push( @keys, \@tmparr );
      }
      my @tmparr = ( $fcmd."0 = Abbruch" );
      push( @keys, \@tmparr );

      my $jsonkb = TelegramBot_MakeKeyboard( $hash, 1, @keys );

      Log3 $name, 5, "TelegramBot_SentFavorites keyboard:".$jsonkb.": ";
      
      $ret = "TelegramBot fhem  : ($mpeernorm)\n Favorites \n";
      
      $ret = TelegramBot_SendIt( $hash, $mpeernorm, $ret, $jsonkb, 1 );
  
  
############ OLD Favorites sent as message   
#  Log3 $name, 3, "TelegramBot_SentFavorites Favorites :".scalar(@clist).": ";
      # my $cnt = 0;
      # $slc = "";
      # my $ck = AttrVal($name,'cmdKeyword',"");

      # foreach my $cs (  @clist ) {
        # $cnt += 1;
        # $slc .= $cnt."\n  $ck ".$cs."\n";
      # }  

      # my $defpeer = AttrVal($name,'defaultPeer',undef);
      # $defpeer = TelegramBot_GetIdForPeer( $hash, $defpeer ) if ( defined( $defpeer ) );
      # $ret = "TelegramBot fhem  : ($mpeernorm)\n Favorites \n\n".$slc;
      # $ret = TelegramBot_SendIt( $hash, $defpeer, $ret, $mid, 1 );
  }
  return $ret;
  
}

  
#####################################
#####################################
# INTERNAL: handle sentlast and favorites
sub TelegramBot_SentLastCommand($$$) {
  my ($hash, $mpeernorm, $mtext ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  my $cmd = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mtext, 'cmdSentCommands' );
  return $ret if ( ! defined( $cmd ) );
    
  Log3 $name, 5, "TelegramBot_SentLastCommand cmd correct peer ";

  my $slc =  ReadingsVal($name ,"StoredCommands","");

  my $defpeer = AttrVal($name,'defaultPeer',undef);
  $defpeer = TelegramBot_GetIdForPeer( $hash, $defpeer ) if ( defined( $defpeer ) );
 
  my @cmds = split( "\n", $slc );

  # create keyboard
  my @keys = ();

  foreach my $cs (  @cmds ) {
    my @tmparr = ( $cs );
    push( @keys, \@tmparr );
  }
#  my @tmparr = ( $fcmd."0 = Abbruch" );
#  push( @keys, \@tmparr );

  my $jsonkb = TelegramBot_MakeKeyboard( $hash, 1, @keys );

  $ret = "TelegramBot fhem  : $mpeernorm \n Last Commands \n";
  
  # overwrite ret with result from SendIt --> send response
  $ret = TelegramBot_SendIt( $hash, $mpeernorm, $ret, $jsonkb, 1 );

############ OLD SentLastCommands sent as message   
#  $ret = "TelegramBot fhem  : $mpeernorm \nLast Commands \n\n".$slc;
  
#  # overwrite ret with result from Analyzecommand --> send response
#  $ret = AnalyzeCommand( undef, "set $name message \@$mpeernorm $ret", "" );

  return $ret;
}

  
#####################################
#####################################
# INTERNAL: execute command and sent return value 
sub TelegramBot_ReadHandleCommand($$$) {
  my ($hash, $mpeernorm, $mtext ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  my $cmd = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mtext, 'cmdKeyword' );
  return $ret if ( ! defined( $cmd ) );

  Log3 $name, 3, "TelegramBot_ReadHandleCommand $name: cmd found :".$cmd.": ";
  
  # get human readble name for peer
  my $pname = TelegramBot_GetFullnameForContact( $hash, $mpeernorm );

  Log3 $name, 5, "TelegramBot_ReadHandleCommand cmd correct peer ";
  # Either no peer defined or cmdpeer matches peer for message -> good to execute
  my $cto = AttrVal($name,'cmdTriggerOnly',"0");
  if ( $cto eq '1' ) {
    $cmd = "trigger ".$cmd;
  }
  
  Log3 $name, 5, "TelegramBot_ReadHandleCommand final cmd for analyze :".$cmd.": ";

  # store last commands (original text)
  TelegramBot_AddStoredCommands( $hash, $mtext );

  $ret = TelegramBot_ExecuteCommand( $hash, $mpeernorm, $cmd );

  return $ret;
}

  
#####################################
#####################################
# INTERNAL: execute command and sent return value 
sub TelegramBot_ExecuteCommand($$$) {
  my ($hash, $mpeernorm, $cmd ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  # get human readble name for peer
  my $pname = TelegramBot_GetFullnameForContact( $hash, $mpeernorm );

  Log3 $name, 5, "TelegramBot_ExecuteCommand final cmd for analyze :".$cmd.": ";

  # special case shutdown caught here to avoid endless loop
  $ret = "shutdown command can not be executed" if ( $cmd =~ /^shutdown(\s+.*)?$/ );
  
  # Execute command
  $ret = AnalyzeCommand( undef, $cmd, "" ) if ( ! defined( $ret ) );

  Log3 $name, 5, "TelegramBot_ExecuteCommand result for analyze :".(defined($ret)?$ret:"<undef>").": ";

  my $defpeer = AttrVal($name,'defaultPeer',undef);
  $defpeer = TelegramBot_GetIdForPeer( $hash, $defpeer ) if ( defined( $defpeer ) );
  
  my $retstart = "TelegramBot fhem";
  $retstart .= " from $pname ($mpeernorm)" if ( $defpeer ne $mpeernorm );
  
  my $retempty = AttrVal($name,'cmdReturnEmptyResult',1);

  # undef is considered ok
  if ( ( ! defined( $ret ) ) || ( length( $ret) == 0 ) ) {
    $ret = "$retstart cmd :$cmd: result OK" if ( $retempty );
  } else {
    $ret = "$retstart cmd :$cmd: result :$ret:";
  }
  Log3 $name, 5, "TelegramBot_ExecuteCommand $name: ".(defined($ret)?$ret:"<undef>").": ";
  
  if ( ( defined( $ret ) ) && ( length( $ret) != 0 ) ) {
    # replace line ends with spaces
    $ret =~ s/\r//gm;
    
    # shorten to maxReturnSize if set
    my $limit = AttrVal($name,'maxReturnSize',0);

    if ( ( length($ret) > $limit ) && ( $limit != 0 ) ) {
      $ret = substr( $ret, 0, $limit )."\n\n...";
    }

    AnalyzeCommand( undef, "set $name message \@$mpeernorm $ret", "" );

    my $dpc = AttrVal($name,'defaultPeerCopy',1);
    if ( ( $dpc ) && ( defined( $defpeer ) ) ) {
      if ( $defpeer ne $mpeernorm ) {
        AnalyzeCommand( undef, "set $name message $ret", "" );
      }
    }
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
    
  
##############################################################################
##############################################################################
##
## Communication - Send - receive - Parse
##
##############################################################################
##############################################################################

#####################################
# INTERNAL: Function to send a photo (and text message) to a peer and handle result
# addPar is caption for images / keyboard for text
sub TelegramBot_SendIt($$$$$)
{
	my ( $hash, @args) = @_;

	my ( $peer, $msg, $addPar, $isText) = @args;
  my $name = $hash->{NAME};
	
  Log3 $name, 5, "TelegramBot_SendIt $name: called ";

  if ( ( defined( $hash->{sentMsgResult} ) ) && ( $hash->{sentMsgResult} eq "WAITING" ) ){
    # add to queue
    if ( ! defined( $hash->{sentQueue} ) ) {
      $hash->{sentQueue} = [];
    }
    Log3 $name, 3, "TelegramBot_SendIt $name: add send to queue :$peer: -:$msg: - :".(defined($addPar)?$addPar:"<undef>").":";
    push( @{ $hash->{sentQueue} }, \@args );
    return;
  }  
    
  my $ret;
  $hash->{sentMsgResult} = "WAITING";

  Log3 $name, 5, "TelegramBot_SendIt $name: try to send message to :$peer: -:$msg: - :".(defined($addPar)?$addPar:"<undef>").":";

    # trim and convert spaces in peer to underline 
  my $peer2 = TelegramBot_GetIdForPeer( $hash, $peer );

  if ( ! defined( $peer2 ) ) {
    $ret = "FAILED peer not found :$peer:";
#    Log3 $name, 2, "TelegramBot_SendIt $name: failed with :".$ret.":";
    $peer2 = "";
  }
  
  $hash->{sentMsgPeer} = TelegramBot_GetFullnameForContact( $hash, $peer2 );
  $hash->{sentMsgPeerId} = $peer2;
  
  # init param hash
  $TelegramBot_hu_do_params{hash} = $hash;
  $TelegramBot_hu_do_params{header} = $TelegramBot_header;
  delete( $TelegramBot_hu_do_params{boundary} );

  # handle data creation only if no error so far
  if ( ! defined( $ret ) ) {

    # add chat / user id (no file) --> this will also do init
    $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "chat_id", undef, $peer2, 0 );

    if ( $isText ) {
      $TelegramBot_hu_do_params{url} = $hash->{URL}."sendMessage";
#      $TelegramBot_hu_do_params{url} = "http://requestb.in/1dvvb8u1";

      if ( length($msg) > 1000 ) {
        $hash->{sentMsgText} = substr($msg,0, 1000)."...";
       } else {
        $hash->{sentMsgText} = $msg;
       }
      my $c = chr(10);
      $msg =~ s/([^\\])\\n/$1$c/g;

      # add msg (no file)
      $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "text", undef, $msg, 0 ) if ( ! defined( $ret ) );

      
      if ( defined( $addPar ) ) {
        $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "reply_markup", undef, $addPar, 0 ) if ( ! defined( $ret ) );
      }

    } else {
      # Photo send    
      $hash->{sentMsgText} = "Image: $msg".(( defined( $addPar ) )?" - ".$addPar:"");

      $TelegramBot_hu_do_params{url} = $hash->{URL}."sendPhoto";
      #    $TelegramBot_hu_do_params{url} = "http://requestb.in/q6o06yq6";

      # add caption
      if ( defined( $addPar ) ) {
        $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "caption", undef, $addPar, 0 ) if ( ! defined( $ret ) );
      }
      
      # add msg (no file)
      Log3 $name, 4, "TelegramBot_SendIt $name: Filename for image file :$msg:";
      $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "photo", undef, $msg, 1 ) if ( ! defined( $ret ) );
      
      # only for test / debug               
      $TelegramBot_hu_do_params{loglevel} = 3;
    }

    # finalize multipart 
    $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, undef, undef, undef, 0 ) if ( ! defined( $ret ) );

  }

  
  if ( defined( $ret ) ) {
    Log3 $name, 3, "TelegramBot_SendIt $name: Failed with :$ret:";
    TelegramBot_Callback( \%TelegramBot_hu_do_params, $ret, "");

  } else {
    HttpUtils_NonblockingGet( \%TelegramBot_hu_do_params);

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
#   > returns string in case of error or undef
sub TelegramBot_AddMultipart($$$$$$)
{
	my ( $hash, $params, $parname, $parheader, $parcontent, $isFile ) = @_;
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
    if ( $isFile ) {
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
#   keys array of arrays for keyboard
#   > returns string in case of error or undef
sub TelegramBot_MakeKeyboard($$@)
{
	my ( $hash, $onetime_hide, @keys ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  my %par;
  
  if ( ( defined( $onetime_hide ) ) && ( ! $onetime_hide ) ) {
    %par = ( "hide_keyboard" => JSON::true );
  } else {
    return $ret if ( ! @keys );
    %par = ( "one_time_keyboard" => (( ( defined( $onetime_hide ) ) && ( $onetime_hide ) )?JSON::true:JSON::true ) );
    $par{keyboard} = \@keys;
  }
  
  my $refkb = \%par;
  
  $ret = encode_json( $refkb );

  return $ret;
}

  
  

#####################################
#  INTERNAL: _PollUpdate is called to set out a nonblocking http call for updates
#  if still polling return
#  if more than one fails happened --> wait instead of poll
#
sub TelegramBot_UpdatePoll($) 
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
		
  Log3 $name, 5, "TelegramBot_UpdatePoll $name: called ";

  if ( $hash->{POLLING} ) {
    Log3 $name, 4, "TelegramBot_UpdatePoll $name: polling still running ";
    return;
  }

  # Get timeout from attribute 
  my $timeout =   AttrVal($name,'pollingTimeout',0);
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

  # get next offset id
  my $offset = $hash->{offset_id};
  $offset = 0 if ( ! defined($offset) );
  
  # build url 
  my $url =  $hash->{URL}."getUpdates?offset=".$offset."&limit=5&timeout=".$timeout;

  $TelegramBot_hu_upd_params{url} = $url;
  $TelegramBot_hu_upd_params{timeout} = $timeout+$timeout+5;
  $TelegramBot_hu_upd_params{hash} = $hash;
  $TelegramBot_hu_upd_params{offset} = $offset;

  $hash->{STATE} = "Polling";

  $hash->{POLLING} = ( ( defined( $hash->{OLD_POLLING} ) )?$hash->{OLD_POLLING}:1 );
  Log3 $name, 4, "TelegramBot_UpdatePoll $name: initiate polling with nonblockingGet with ".$timeout."s";
  HttpUtils_NonblockingGet( \%TelegramBot_hu_upd_params); 
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
  my $result;
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
    Log3 $name, 5, "TelegramBot_ParseUpdate $name: data returned :$data:";
    my $jo;
 

### mark as latin1 to ensure no conversion is happening (this works surprisingly)
     eval {
       $data = encode( 'latin1', $data );
# Debug "-----AFTER------\n".$data."\n-------UC=".${^UNICODE} ."-----\n";
       $jo = decode_json( $data );
    };
 

###################### 
 
    if ( $@ ) {
      $ret = "Callback returned no valid JSON: $@ ";
    } elsif ( ! defined( $jo ) ) {
      $ret = "Callback returned no valid JSON !";
    } elsif ( ! $jo->{ok} ) {
      if ( defined( $jo->{description} ) ) {
        $ret = "Callback returned error:".TelegramBot_GetUTF8Back( $jo->{description} ).":";
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
    # Polling means result must be analyzed
    if ( defined($result) ) {
       # handle result
      $hash->{FAILS} = 0;    # succesful UpdatePoll reset fails
      Log3 $name, 5, "UpdatePoll $name: number of results ".scalar(@$result) ;
      foreach my $update ( @$result ) {
        Log3 $name, 5, "UpdatePoll $name: parse result ";
        if ( defined( $update->{message} ) ) {
          
          $ret = TelegramBot_ParseMsg( $hash, $update->{update_id}, $update->{message} );
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
    # Non Polling means reset only the 
    $TelegramBot_hu_do_params{data} = "";
    $ll = 3 if ( defined( $ret ) );
  }
  
  
  $ret = "SUCCESS" if ( ! defined( $ret ) );
  Log3 $name, $ll, "TelegramBot_Callback $name: resulted in :$ret: from ".(( defined( $param->{isPolling} ) )?"Polling":"SendIt");

  if ( ! defined( $param->{isPolling} ) ) {
    $hash->{sentMsgResult} = $ret;
    if ( ( defined( $hash->{sentQueue} ) ) && (  scalar( @{ $hash->{sentQueue} } ) ) ) {
      my $ref = shift @{ $hash->{sentQueue} };
      Log3 $name, 5, "TelegramBot_Callback $name: handle queued send with :@$ref[0]: -:@$ref[1]: ";
      TelegramBot_SendIt( $hash, @$ref[0], @$ref[1], @$ref[2], @$ref[3] );
    }
  }
  
}


#####################################
#  INTERNAL: Convert (Mark) a scalar as UTF8
sub TelegramBot_GetUTF8Back( $ ) {
  my ( $data ) = @_;
  
  return encode('utf8', $data);
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

  # check peers beside from only contact (shared contact) and new_chat_participant are checked
  push( @contacts, $from );

  my $chatId = "";
  my $chat = $message->{chat};
  if ( ( defined( $chat ) ) && ( $chat->{type} ne "private" ) ) {
    push( @contacts, $chat );
    $chatId = $chat->{id};
  }

#  my $user = $message->{contact};
#  if ( defined( $user ) ) {
#    push( @contacts, $user );
#  }

  my $user = $message->{new_chat_participant};
  if ( defined( $user ) ) {
    push( @contacts, $user );
  }

  # handle text message
  if ( defined( $message->{text} ) ) {
    my $mtext = TelegramBot_GetUTF8Back( $message->{text} );

    Log3 $name, 4, "TelegramBot_ParseMsg $name: text   :$mtext:";

#    Log3 $name, 4, "TelegramBot_ParseMsg $name: text utf8  :".encode( 'utf8', $mtext).":";
    
    my $mpeernorm = $mpeer;
    $mpeernorm =~ s/^\s+|\s+$//g;
    $mpeernorm =~ s/ /_/g;

#    Log3 $name, 5, "TelegramBot_ParseMsg $name: Found message $mid from $mpeer :$mtext:";

    # contacts handled separately since readings are updated in here
    TelegramBot_ContactUpdate($hash, @contacts) if ( scalar(@contacts) > 0 );
    
    readingsBeginUpdate($hash);

    readingsBulkUpdate($hash, "prevMsgId", $hash->{READINGS}{msgId}{VAL});				
    readingsBulkUpdate($hash, "prevMsgPeer", $hash->{READINGS}{msgPeer}{VAL});				
    readingsBulkUpdate($hash, "prevMsgPeerId", $hash->{READINGS}{msgPeerId}{VAL});				
    readingsBulkUpdate($hash, "prevMsgChat", $hash->{READINGS}{msgChat}{VAL});				
    readingsBulkUpdate($hash, "prevMsgText", $hash->{READINGS}{msgText}{VAL});				

    readingsEndUpdate($hash, 0);
    
    readingsBeginUpdate($hash);

    readingsBulkUpdate($hash, "msgId", $mid);				
    readingsBulkUpdate($hash, "msgPeer", TelegramBot_GetFullnameForContact( $hash, $mpeernorm ));				
    readingsBulkUpdate($hash, "msgChat", TelegramBot_GetFullnameForChat( $hash, $chatId ) );				
    readingsBulkUpdate($hash, "msgPeerId", $mpeernorm);				
    readingsBulkUpdate($hash, "msgText", $mtext);				
#    readingsBulkUpdate($hash, "msgText", encode( 'utf8', $mtext));				


    readingsEndUpdate($hash, 1);
    
    # trim whitespace from message text
    $mtext =~ s/^\s+|\s+$//g;

    my $cmdRet;
    
    $cmdRet = TelegramBot_ReadHandleCommand( $hash, $mpeernorm, $mtext );
    Log3 $name, 3, "TelegramBot_ParseMsg $name: ReadHandleCommand returned :$cmdRet:" if ( defined($cmdRet) );
    
    #  ignore result of readhandlecommand since it leads to endless loop

    $cmdRet = TelegramBot_SentLastCommand( $hash, $mpeernorm, $mtext );
    Log3 $name, 3, "TelegramBot_ParseMsg $name: SentLastCommand returned :$cmdRet:" if ( defined($cmdRet) );
    
    $cmdRet = TelegramBot_SentFavorites( $hash, $mpeernorm, $mtext, $mid );
    Log3 $name, 3, "TelegramBot_ParseMsg $name: SentFavorites returned :$cmdRet:" if ( defined($cmdRet) );
    
    
  } elsif ( scalar(@contacts) > 0 )  {
    # will also update reading
    TelegramBot_ContactUpdate( $hash, @contacts );

    Log3 $name, 5, "TelegramBot_ParseMsg $name: Found message $mid from $mpeer without text but with contacts";

  } else {
    Log3 $name, 5, "TelegramBot_ParseMsg $name: Found message $mid from $mpeer without text";
  }
  
  return $ret;
}

#####################################
# INTERNAL: Function to send a command handle result
# Parameter
#   hash
#   url - url including parameters
#   > returns string in case of error or the content of the result object if ok
sub TelegramBot_DoUrlCommand($$)
{
	my ( $hash, $url ) = @_;
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
    Log3 $name, 2, "TelegramBot_DoUrlCommand $name: ".$ret;
  } else {
    my $jo;
    
    eval {
      $jo = decode_json( $data );
    };

    if ( ! defined( $jo ) ) {
      $ret = "FAILED invalid JSON returned";
      Log3 $name, 2, "TelegramBot_DoUrlCommand $name: ".$ret;
    } elsif ( $jo->{ok} ) {
      $ret = $jo->{result};
      Log3 $name, 4, "TelegramBot_DoUrlCommand OK with result";
    } else {
      my $ret = "FAILED Telegram returned error: ".$jo->{description};
      Log3 $name, 2, "TelegramBot_DoUrlCommand $name: ".$ret;
    }    

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

  HttpUtils_Close(\%TelegramBot_hu_upd_params); 
  HttpUtils_Close(\%TelegramBot_hu_do_params); 
  
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

  # Ensure queueing is not happening
  delete( $hash->{sentQueue} );
  delete( $hash->{sentMsgResult} );
  
  $hash->{URL} = "https://api.telegram.org/bot".$hash->{Token}."/";

  $hash->{STATE} = "Defined";

  # getMe as connectivity check and set internals accordingly
  my $url = $hash->{URL}."getMe";
  my $meret = TelegramBot_DoUrlCommand( $hash, $url );
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
    foreach  my $mkey ( keys $hash->{Contacts} ) {
      my @clist = split( /:/, $hash->{Contacts}{$mkey} );
      if ( (defined($clist[2])) && ( $clist[2] eq $mpeer ) ) {
        $id = $clist[0];
        last;
      }
    }
  } else {
    $mpeer =~ s/^\s+|\s+$//g;
    $mpeer =~ s/ /_/g;
    foreach  my $mkey ( keys $hash->{Contacts} ) {
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


  return ( defined( $hash->{$mpeer} ) );
}

#####################################
# INTERNAL: calculate internals->contacts-hash from Readings->Contacts string
sub TelegramBot_CalcContactsHash($$)
{
  my ($hash, $cstr) = @_;

  # create a new hash
  if ( defined( $hash->{Contacts} ) ) {
    foreach my $key (keys $hash->{Contacts} )
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
      $cname =~ TelegramBot_encodeContactString( $cname );

      $cuser =~ TelegramBot_encodeContactString( $cuser );
      
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
  
  Log3 $hash->{NAME}, 4, "TelegramBot_ContactUpdate # Contacts in hash before :".scalar(keys $hash->{Contacts}).":";

  foreach my $user ( @contacts ) {
    my $contactString = TelegramBot_userObjectToString( $user );
    if ( ! defined( $hash->{Contacts}{$user->{id}} ) ) {
      Log3 $hash->{NAME}, 3, "TelegramBot_ContactUpdate new contact :".$contactString.":";
      $newfound = 1;
    } elsif ( $contactString ne $hash->{Contacts}{$user->{id}} ) {
      Log3 $hash->{NAME}, 3, "TelegramBot_ContactUpdate updated contact :".$contactString.":";
    }
    $hash->{Contacts}{$user->{id}} = $contactString;
  }

  Log3 $hash->{NAME}, 4, "TelegramBot_ContactUpdate # Contacts in hash after :".scalar(keys $hash->{Contacts}).":";

  my $rc = "";
  foreach my $key (keys $hash->{Contacts} )
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
  
  # user objects do not contain a type field / chat objects need to contain a type but only if type=group it is really a group
  if ( ( defined( $user->{type} ) ) && ( $user->{type} eq "group" ) ) {
    
    $ret .= ":";

    $ret .= "#".TelegramBot_encodeContactString($user->{title}) if ( defined( $user->{title} ) );

  } else {

    my $part = $user->{first_name};
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

  return TelegramBot_GetUTF8Back( $str );
}

#####################################
# INTERNAL: Check if peer is allowed - true if allowed
sub TelegramBot_checkAllowedPeer($$) {
  my ($hash,$mpeer) = @_;
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
  
  return 0;
}  



##############################################################################
##############################################################################
##
## HELPER
##
##############################################################################
##############################################################################


######################################
#  read binary file for Phototransfer - returns undef or empty string on error
#  
sub TelegramBot_BinaryFileRead($$) {
	my ($hash, $fileName) = @_;

  return '' if ( ! (-e $fileName) );
  
  my $fileData = '';
		
  open TGB_BINFILE, '<'.$fileName;
  binmode TGB_BINFILE;
  while (<TGB_BINFILE>){
    $fileData .= $_;
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
  <a href=https://core.telegram.org/bots#botfather>botfather</a> to gain the needed token for authorizing as bot with telegram.org. 
  The token (e.g. something like <code>110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw</code> is required for defining a working telegram bot in fhem.
  <br><br>
  Bots also differ in other aspects from normal telegram accounts. Here some examples:
  <ul>
    <li>Bots can not initiate connections to arbitrary users, instead users need to first initiate the communication with the bot.</li> 
    <li>Bots have a different privacy setting then normal users (see <a href=https://core.telegram.org/bots#privacy-mode>Privacy mode</a>) </li> 
    <li>Bots support commands and specialized keyboards for the interaction (not yet supported in the fhem telegramBot)</li> 
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

  The TelegramBot module allows receiving of (text) messages from any peer (telegram user) and can send text messages to known users.
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
  <br><br>
  <a name="TelegramBotdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TelegramBot  &lt;token&gt; </code>
    <br><br>
    Defines a TelegramBot device using the specified token perceived from botfather
    <br><br>

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
    <code>set &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br><br>
    where &lt;what&gt; is one of

  <br><br>
    <li><code>message|msg|send [@&lt;peer&gt;] &lt;text&gt;</code><br>Sends the given message to the given peer or if peer is ommitted currently defined default peer user. If a peer is given it needs to be always prefixed with a '@'. Peers can be specified as contact ids, full names (with underscore instead of space), usernames (prefixed with another @) or chat names (also known as groups in telegram groups must be prefixed with #).<br>
    Messages do not need to be quoted if containing spaces.<br>
    Examples:<br>
      <dl>
        <dt><code>set aTelegramBotDevice message @@someusername a message to be sent</code></dt>
          <dd> to send to a user having someusername as username (not first and last name) in telegram <br> </dd>
        <dt><code>set aTelegramBotDevice message @Ralf_Mustermann another message</code></dt>
          <dd> to send to a user Ralf as firstname and Mustermann as last name in telegram   <br></dd>
        <dt><code>set aTelegramBotDevice message @#justchatting Hello</code></dt>
          <dd> to send the message "Hello" to a chat with the name "justchatting"   <br></dd>
        <dt><code>set aTelegramBotDevice message @1234567 Bye</code></dt>
          <dd> to send the message "Bye" to a contact or chat with the id "1234567". Chat ids might be negative and need to be specified with a leading hyphen (-). <br></dd>
      <dl>
    </li>
    <li><code>sendImage|image [@&lt;peer&gt;] &lt;file&gt; [&lt;caption&gt;]</code><br>Sends a photo to the given or if ommitted to the default peer. 
    File is specifying a filename and path to the image file to be send. 
    Local paths should be given local to the root directory of fhem (the directory of fhem.pl e.g. /opt/fhem).
    filenames containing spaces need to be given in parentheses.<br>
    Rule for specifying peers are the same as for messages. Captions can also contain multiple words and do not need to be quoted.
    </li>
  <br><br>
    <li><code>replaceContacts &lt;text&gt;</code><br>Set the contacts newly from a string. Multiple contacts can be separated by a space. 
    Each contact needs to be specified as a triple of contact id, full name and user name as explained above. </li>
    <li><code>reset</code><br>Reset the internal state of the telegram bot. This is normally not needed, but can be used to reset the used URL, 
    internal contact handling, queue of send items and polling <br>
    ATTENTION: Messages that might be queued on the telegram server side (especially commands) might be then worked off afterwards immedately. 
    If in doubt it is recommened to temporarily deactivate (delete) the cmdKeyword attribute before resetting.</li>

  <br><br>
    <li>DEPRECATED: <code>sendImageTo &lt;peer&gt; &lt;file&gt; [&lt;caption&gt;]</code><br>Sends a photo to the given peer, 
    other arguments are handled as with <code>sendPhoto</code></li>
    <li>DEPRECATED: <code>messageTo &lt;peer&gt; &lt;text&gt;</code><br>Sends the given message to the given peer. 
    Peer needs to be given without space or other separator, i.e. spaces should be replaced by underscore (e.g. first_last)</li>

  </ul>
  <br><br>

  <a name="TelegramBotattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>defaultPeer &lt;name&gt;</code><br>Specify contact id, user name or full name of the default peer to be used for sending messages. </li> 
    <li><code>defaultPeerCopy &lt;1 (default) or 0&gt;</code><br>Copy all command results also to the defined defaultPeer. If set results are sent both to the requestor and the defaultPeer if they are different. 
    </li> 


  <br><br>
    <li><code>cmdKeyword &lt;keyword&gt;</code><br>Specify a specific text that needs to be sent to make the rest of the message being executed as a command. 
      So if for example cmdKeyword is set to <code>ok fhem</code> then a message starting with this string will be executed as fhem command 
        (see also cmdTriggerOnly).<br>
        Please also consider cmdRestrictedPeer for restricting access to this feature!<br>
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

  <br><br>
    <li><code>cmdFavorites &lt;keyword&gt;</code><br>Specify a specific text that will trigger sending the list of defined favorites or executes a given favorite by number (the favorites are defined in attribute <code>favorites</code>).
    <br>
        Example: If this attribute is set to a value of <code>favorite</code> a message of <code>favorite</code> to the bot will return a list of defined favorite commands and their index number. In the same case the message <code>favorite &lt;n&gt;</code> (with n being a number) would execute the command that is the n-th command in the favorites list. The result of the command will be returned as in other command executions. 
        Please also consider cmdRestrictedPeer for restricting access to this feature!<br>
    </li> 
    <li><code>favorites &lt;list of commands&gt;</code><br>Specify a list of favorite commands for Fhem (without cmdKeyword). Multiple commands are separated by semicolon (;). This also means that only simple commands (without embedded semicolon) can be defined. <br>
    </li> 


  <br><br>
    <li><code>cmdRestrictedPeer &lt;peername(s)&gt;</code><br>Restrict the execution of commands only to messages sent from the given peername or multiple peernames
    (specified in the form of contact id, username or full name, multiple peers to be separated by a space). 
    A message with the cmd and sender is sent to the default peer in case of another user trying to sent messages<br>
    </li> 
    <li><code>cmdTriggerOnly &lt;0 or 1&gt;</code><br>Restrict the execution of commands only to trigger command. If this attr is set (value 1), then only the name of the trigger even has to be given (i.e. without the preceding statement trigger). 
          So if for example cmdKeyword is set to <code>ok fhem</code> and cmdTriggerOnly is set, then a message of <code>ok fhem someMacro</code> would execute the fhem command  <code>trigger someMacro</code>.
    </li> 
    <li><code>cmdReturnEmptyResult &lt;1 or 0&gt;</code><br>Return empty (success) message for commands (default). Otherwise return messages are only sent if a result text or error message is the result of the command execution.
    </li> 


  <br><br>
    <li><code>pollingTimeout &lt;number&gt;</code><br>Used to specify the timeout for long polling of updates. A value of 0 is switching off any long poll. 
      In this case no updates are automatically received and therefore also no messages can be received. It is recommended to set the pollingtimeout to a reasonable time between 15 (not too short) and 60 (to avoid broken connections). 
    </li> 
    <li><code>pollingVerbose &lt;0_None 1_Digest 2_Log&gt;</code><br>Used to limit the amount of logging for errors of the polling connection. These errors are happening regularly and usually are not consider critical, since the polling restarts automatically and pauses in case of excess errors. With the default setting "1_Digest" once a day the number of errors on the last day is logged (log level 3). With "2_Log" every error is logged with log level 2. With the setting "0_None" no errors are logged. In any case the count of errors during the last day and the last error is stored in the readings <code>PollingErrCount</code> and <code>PollingLastError</code> </li> 

    
pollingVerbose:1_Digest,2_Log,0_None
    
  <br><br>
    <li><code>maxFileSize &lt;number of bytes&gt;</code><br>Maximum file size in bytes for transfer of files (images). If not set the internal limit is specified as 10MB (10485760B).
    </li> 
    <li><code>maxReturnSize &lt;number of chars&gt;</code><br>Maximum size of command result returned as a text message including header (Default is unlimited). The internal shown on the device is limited to 1000 chars.
    </li> 

    <br><br>
    <li><code>saveStateOnContactChange &lt;1 or 0&gt;</code><br>Allow statefile being written on every new contact found, ensures new contacts not being lost on any loss of statefile. Default is on (1).
    </li> 



    <li><a href="#verbose">verbose</a></li>
  </ul>
  <br><br>
  
  <a name="TelegramBotreadings"></a>
  <b>Readings</b>
  <br><br>
  <ul>
    <li>Contacts &lt;text&gt;<br>The current list of contacts known to the telegram bot. 
    Each contact is specified as a triple in the same form as described above. Multiple contacts separated by a space. </li> 

  <br><br>
    <li>msgId &lt;text&gt;<br>The id of the last received message is stored in this reading. 
    For secret chats a value of -1 will be given, since the msgIds of secret messages are not part of the consecutive numbering</li> 
    <li>msgPeer &lt;text&gt;<br>The sender name of the last received message (either full name or if not available @username)</li> 
    <li>msgPeerId &lt;text&gt;<br>The sender id of the last received message</li> 
    <li>msgText &lt;text&gt;<br>The last received message text is stored in this reading.</li> 

  <br><br>

    <li>prevMsgId &lt;text&gt;<br>The id of the SECOND last received message is stored in this reading</li> 
    <li>prevMsgPeer &lt;text&gt;<br>The sender name of the SECOND last received message (either full name or if not available @username)</li> 
    <li>prevMsgPeerId &lt;text&gt;<br>The sender id of the SECOND last received message</li> 
    <li>prevMsgText &lt;text&gt;<br>The SECOND last received message text is stored in this reading</li> 

  <br>All prev... Readings are not triggering events<br>

  <br><br>
    <li>StoredCommands &lt;text&gt;<br>A list of the last commands executed through TelegramBot. Maximum 10 commands are stored.</li> 

  <br><br>
    <li>PollingErrCount &lt;number&gt;<br>Show the number of polling errors during the last day. The number is reset at the beginning of the next day.</li> 
    <li>PollingLastError &lt;number&gt;<br>Last error message that occured during a polling update call</li> 
    
  </ul>
  <br><br>
  
  <a name="TelegramBotexamples"></a>
  <b>Examples</b>
  <br><br>
  <ul>

    <li>Send a telegram message if fhem has been newly started
      <p>
      <code>define notify_fhem_reload notify global:INITIALIZED set &lt;telegrambot&gt; message fhem newly started - just now !  </code>
      </p> 
    </li> 
  <br><br>

    <li>Allow telegram bot commands to be used<br>
        If the keywords for commands are starting with a slash (/), the corresponding commands can be also defined with the <a href=http://botsfortelegram.com/project/the-bot-father/>Bot Father</a>. So if a slash is typed a list of the commands will be automatically shown.<br>
        
        Assuming that <code>cmdSentCommands</code> is set to <code>/History</code>. Then you can initiate the communication with the botfather, select the right bot and then with the command <code>/setcommands</code> define one or more commands like
        <p>
          <code>History-Show a history of the last 10 executed commands</code>
        </p> 
        When typing a slash, then the text above will immediately show up in the client.
    </li> 
  </ul>
  
  <br><br>
</ul>

=end html
=cut
