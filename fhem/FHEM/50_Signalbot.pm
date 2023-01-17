##############################################
#$Id$
my $Signalbot_VERSION="3.12";
# Simple Interface to Signal CLI running as Dbus service
# Author: Adimarantis
# License: GPL
# Credits to FHEM Forum Users Quantum (SiSi Module) and Johannes Viegener (Telegrambot Module) for code fragments and ideas
# Requires signal_cli (https://github.com/AsamK/signal-cli) and Protocol::DBus to work
# Verbose levels
# 5 = Internal data and function calls
# 4 = User actions and results
# 3 = Error messages

package main;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use File::Temp qw( tempfile tempdir );
use Text::ParseWords;
use Encode;
#use Data::Dumper;
use Time::HiRes qw( usleep );
use URI::Escape;
use HttpUtils;

eval "use Protocol::DBus;1";
eval "use Protocol::DBus::Client;1" or my $DBus_missing = "yes";
sub LogUnicode($$$);

require FHEM::Text::Unicode;
use FHEM::Text::Unicode qw(:ALL);
use vars qw(%FW_webArgs); # all arguments specified in the GET
use vars qw($FW_detail);  # currently selected device for detail view
use vars qw($FW_RET);
use vars qw($FW_wname);

#maybe really get introspective here instead of handwritten list
 my %signatures = (
	"setContactBlocked" 	=> "sb",
	"setGroupBlocked" 		=> "ayb",
	"updateGroup" 			=> "aysass",
	"updateProfile" 		=> "ssssb",
	"quitGroup" 			=> "ay",
	"joinGroup"				=> "s",
	"sendGroupMessage"		=> "sasay",
	"sendNoteToSelfMessage" => "sas",
	"sendMessage" 			=> "sasas",
	"getContactName" 		=> "s",
	"setContactName" 		=> "ss",
	"getGroupIds" 			=> "",
	"getGroupName" 			=> "ay",
	"getGroupMembers" 		=> "ay",
	"listNumbers" 			=> "",
	"getContactNumber" 		=> "s",
	"isContactBlocked" 		=> "s",
	"isGroupBlocked" 		=> "ay",
	"isMember"				=> "ay",
	"createGroup"			=> "sass",
	"getSelfNumber"			=> "", #V0.9.1
	"deleteContact"			=> "s", #V0.10.0
	"deleteRecipient"		=> "s", #V0.10.0
	"setPin"				=> "s", #V0.10.0
	"removePin"				=> "", #V0.10.0
	"getGroup"				=> "ay", #V0.10.0
	"addDevice"				=> "s",
	"listDevices"			=> "",
	"unregister"			=> "",
	"sendEndSessionMessage" => "as",		#unused
	"sendRemoteDeleteMessage" => "xas",		#unused
	"sendGroupRemoteDeletemessage" => "xay",#unused
	"sendMessageReaction" => "sbsxas",		#unused
	"sendGroupMessageReaction" => "sbsxay",	#unused
);
	
 my %groupsignatures = (
	#methods in the "Groups" object from V0.10
	"deleteGroup"			=> "",
	"addMembers"			=> "as",
	"removeMembers"			=> "as",
	"quitGroup"				=> "",
	"addAdmins"				=> "as",
	"removeAdmins"			=> "as",
);

#dbus interfaces that only exist in registration mode
my %regsig = (
	"listAccounts"			=> "",
	"link"					=> "s",
	"registerWithCaptcha"	=> "sbs",
	"verifyWithPin"			=> "sss", #not used
	"register"				=> "sb",
	"verify"				=> "ss",
	"version" 				=> "",
);

sub Signalbot_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}     = 	"Signalbot_Define";
  $hash->{FW_detailFn}  = "Signalbot_Detail";
  $hash->{FW_deviceOverview} = 1;
  $hash->{AttrFn}    = 	"Signalbot_Attr";
  $hash->{SetFn}     = 	"Signalbot_Set";
  $hash->{ReadFn}    = 	"Signalbot_Read";
  $hash->{NotifyFn}  =  'Signalbot_Notify';
  $hash->{StateFn}   =  "Signalbot_State";
  $hash->{GetFn}     = 	"Signalbot_Get";
  $hash->{UndefFn}   = 	"Signalbot_Undef";
  $hash->{MessageReceived} = "Signalbot_MessageReceived";
  $hash->{MessageReceivedV2} = "Signalbot_MessageReceivedV2";
  $hash->{ReceiptReceived} = "Signalbot_ReceiptReceived";
  $hash->{version}		= "Signalbot_Version_cb";
  $hash->{updateGroup}  = "Signalbot_UpdateGroup_cb";
  $hash->{createGroup}  = "Signalbot_UpdateGroup_cb";
  $hash->{joinGroup}	= "Signalbot_UpdateGroup_cb";
  $hash->{listNumbers}	= "Signalbot_ListNumbers_cb";
  $hash->{AttrList}  = 	"IODev do_not_notify:1,0 ignore:1,0 showtime:1,0 ".
												"defaultPeer: ".
												"allowedPeer ".
												"babblePeer ".
												"babbleDev ".
												"babbleExclude ".
												"authTimeout ".
												"authDev ".
												"cmdKeyword ".
												"cmdFavorite ".
												"favorites:textField-long ".
												"autoJoin:yes,no ".
												"formatting:none,html,markdown,both ".
												"registerMethod:SMS,Voice ".
												"$readingFnAttributes";
	$data{FWEXT}{"/Signalbot_sendMsg"}{CONTENTFUNC} = "Signalbot_sendMsg";
}

sub Signalbot_sendMsg($@) {
	my ($arg) = @_;
	my ($cmd, $cmddev) = FW_digestCgi($arg);
	my $mod=$FW_webArgs{detail};
	my $snd=$FW_webArgs{send};
	my $hash = $defs{$mod};
	my @args=split(" ",$snd);
	@args=parse_line(' ',0,join(" ",@args));
	my $ret=Signalbot_prepareSend($hash,"send",@args);
	readingsSingleUpdate($hash, 'lastError', $ret,1) if defined $ret;
	#$FW_XHR=1;
	#This does not work als {CL} is not set here
	#my $name = $hash->{NAME};
	#my $web=$hash->{CL}{SNAME};
	#my $peer=$hash->{CL}{PEER};
	#DoTrigger($web,"JS#$peer:location.href=".'"'."?detail=$name".'"');
	return 0;
}

################################### 
sub Signalbot_Set($@) {					#

	my ( $hash, $name, @args ) = @_;

	### Check Args
	my $numberOfArgs  = int(@args);
	return "Signalbot_Set: No cmd specified for set" if ( $numberOfArgs < 1 );

	my $cmd = shift @args;
	my $account = ReadingsVal($name,"account","none");
	my $version = $hash->{helper}{version};
	return "$name not initialized" if (!defined $version);
	my $multi = $hash->{helper}{multi};
	my @accounts;
	@accounts =@{$hash->{helper}{accountlist}} if defined $hash->{helper}{accountlist};
	my $sets=	"send:textField ".
				"updateProfile:textField ".
				"reply:textField ".
				"addDevice:textField ".
				"removeDevice:textField ";
	$sets.=	"addContact:textField ".
				"createGroup:textField ".
				"invite:textField ".
				"block:textField ".
				"unblock:textField ".
				"updateGroup:textField ".
				"quitGroup:textField ".
				"joinGroup:textField " if $version <1000;
	$sets.=	"group:widgetList,13,select,addMembers,removeMembers,addAdmins,removeAdmins,invite,".
	"create,delete,block,unblock,update,".
	"quit,join,1,textField contact:widgetList,5,select,add,delete,block,unblock,1,textField " if $version >=1000;
	my $sets_reg=	"link:textField ".
					"register:textField ";
	$sets_reg	.=	"captcha:textField " if defined ($hash->{helper}{register});
	$sets_reg	.=	"verify:textField " if defined ($hash->{helper}{verification});
	
	$sets.=$sets_reg if defined $multi && $multi==1;
	$sets=$sets_reg if $account eq "none";
	$sets.="signalAccount:".join(",",@accounts)." " if @accounts>0; 
	$sets.="reinit:noArg ";
	
	if ( $cmd eq "?" ) {
		return "Signalbot_Set: Unknown argument $cmd, choose one of " . $sets;
	} # error unknown cmd handling
	
	# Works always
	if ( $cmd eq "reinit") {
		$hash->{helper}{qr}=undef;
		$hash->{helper}{register}=undef;
		$hash->{helper}{verification}=undef;
		$hash->{helper}{captcha}=undef;
		my $ret = Signalbot_setup($hash);
		$hash->{STATE} = $ret if defined $ret;
		Signalbot_createRegfiles($hash);
		return undef;
	}

	#Pre-parse for " " embedded strings, except for "send" that does its own processing
	if ( $cmd ne "send" && $cmd ne "msg") {
		@args=parse_line(' ',0,join(" ",@args));
	}

	#restructure multi widget command (that have a comma after the first argument)
	if ( $cmd eq "group" or $cmd eq "contact") {
		my @cm=split(",",$args[0]);
		$cmd=$cmd.$cm[0];
		$args[0]=$cm[1];
		print "$cmd ".join(":",@args)."\n";
	}
	
	if ( $cmd eq "signalAccount" ) {
		#When registered, first switch back to default account
		my $number = shift @args;
		return "Invalid number" if !defined Signalbot_checkNumber($number);;
		my $ret = Signalbot_setAccount($hash, $number);
		# undef is success
		if (!defined $ret) {
			$hash->{helper}{qr}=undef;
			$hash->{helper}{register}=undef;
			$hash->{helper}{verification}=undef;
			$ret=Signalbot_setup($hash);
			$hash->{STATE} = $ret if defined $ret;
			return undef;
		}
		#if some error occured, register the old account
		$ret = Signalbot_setAccount($hash,$account);
		return "Error changing account, using previous account $account";
	} elsif ($cmd eq "link") {
		my $acname=shift @args;
		$acname="FHEM" if (!defined $acname);
		my $qrcode=Signalbot_CallS($hash,"link",$acname);
		if (defined $qrcode) {
			my $qr_url = "https://chart.googleapis.com/chart?cht=qr&chs=200x200"."&chl=";
			$qr_url .= uri_escape($qrcode);
			$hash->{helper}{qr}=$qr_url;
			$hash->{helper}{uri}=$qrcode;
			$hash->{helper}{register}=undef;
			$hash->{helper}{verification}=undef;
			return undef;
		}
		return "Error creating device link:".$hash->{helper}{lasterr};
	} elsif ($cmd eq "addDevice") {
		my $url = shift @args;
		my $ret = Signalbot_CallS($hash,"addDevice",$url);
		LogUnicode $hash->{NAME}, 3 , $hash->{NAME}.": AddDevice for ".$url." returned:" .$ret;
		return $ret;
	} elsif ($cmd eq "removeDevice") {
		my $devID = shift @args;
		return Signalbot_removeDevice($hash,$devID);
	} elsif ( $cmd eq "unregister") {
		my $number=ReadingsVal($name,"account","");
		my $vernum= shift @args;
		if ($number eq $vernum) {
			my $ret=Signalbot_CallS($hash,"unregister");
			#delete account and do a reinit
			Signalbot_disconnect($hash);
			readingsSingleUpdate($hash, 'account', "none", 0);
			$hash->{helper}{qr}=undef;
			$hash->{helper}{register}=undef;
			$hash->{helper}{verification}=undef;
			$hash->{helper}{captcha}=undef;
			$ret = Signalbot_setup($hash);
			$hash->{STATE} = $ret if defined $ret;
			Signalbot_createRegfiles($hash);
			return undef;
		}
		return "To unregister provide current account for safety reasons";
	} elsif ( $cmd eq "register") {
		my $account= shift @args;
		return "Number needs to start with '+' followed by digits" if !defined Signalbot_checkNumber($account);
		delete $hash->{helper}{captcha};
		my $ret=Signalbot_Registration($hash,$account);
		if (!defined $ret) {
			my $err=ReadingsVal($name,"lastError","");
			$hash->{helper}{verification}=undef;
			$hash->{helper}{qr}=undef;
			$err="Captcha";
			if ($err =~ /Captcha/) {
				$hash->{helper}{register}=$account;
				Signalbot_createRegfiles($hash);
				return;
			} else {
				$hash->{helper}{register}=undef;
			}
		} 			
		$hash->{helper}{verification}=$account;
		$hash->{helper}{register}=undef;
		if (defined $ret && $ret==-1) {
			#Special case: registration succeeded without captcha as it just was reactivated - no verification
			$hash->{helper}{verification}=undef;
			$ret=Signalbot_setAccount($hash,$account);
		}
		return;
		
	} elsif ( $cmd eq "captcha" ) {
		my $captcha=shift @args;
		if ($captcha =~ /signalcaptcha:\/\//) {
			$hash->{helper}{captcha}=$captcha =~ s/signalcaptcha:\/\///rg;;
			my $account=$hash->{helper}{register};
			if (defined $account) {
				#register already done before - try again right away
				my $ret=Signalbot_Registration($hash,$account);
				if (defined $ret) {
					$hash->{helper}{verification}=$account;
					$hash->{helper}{register}=undef;
					#Switch back to device overview - experimental hint from rudolphkoenig https://forum.fhem.de/index.php/topic,122771.msg1173835.html#new
					my $web=$hash->{CL}{SNAME};
					my $peer=$hash->{CL}{PEER};
					DoTrigger($web,"JS#$peer:location.href=".'"'."?detail=$name".'"');
					return undef;
				} else {
					my $err=ReadingsVal($name,"lastError","");
					return "Error with captcha:$err";
				}
			}
		}
		return "Incorrect captcha - e.g. needs to start with signalcaptcha://";
	} elsif ( $cmd eq "verify" ) {
		my $code=shift @args;
		my $account=$hash->{helper}{verification};
		if (!defined $account) {
			return "You first need to complete registration before you can enter the verification code";
		}
		my $ret=Signalbot_CallS($hash,"verify",$account,$code);
		return $hash->{helper}{lasterr} if !defined $ret;
		if ($ret == 0) {
			#On successfuly verification switch to that account
			$ret=Signalbot_setAccount($hash,$account);
			return $ret if defined $ret;
			$hash->{helper}{register}=undef;
			$hash->{helper}{verification}=undef;
			return undef;
		}
		return $ret;
	} elsif ( $cmd eq "addContact" || $cmd eq "contactadd") {
		if (@args<2 ) {
			return "Usage: set ".$hash->{NAME}." contact <number> <nickname>";
		} else {
			my $number = shift @args;
			my $nickname = join (" ",@args);
			my $ret=Signalbot_setContactName($hash,$number,$nickname);
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "deleteContact" || $cmd eq "contactdelete") {
		return "Usage: set ".$hash->{NAME}." deleteContact <number|name>" if (@args<1);
		return "signal-cli 0.10.0+ required" if $version<1000;
		my $nickname = join (" ",@args);
		my $number=Signalbot_translateContact($hash,$nickname);
		return "Unknown contact" if !defined $number;
		delete $hash->{helper}{contacts}{$number} if defined $hash->{helper}{contacts}{$number};
		Signalbot_CallA($hash,"deleteRecipient",$number);
		return;
	} elsif ( $cmd eq "deleteGroup" || $cmd eq "groupdelete") {
		return "Usage: set ".$hash->{NAME}." deleteGroup <groupname>" if (@args<1);
		return "signal-cli 0.10.0+ required" if $version<1000;
		my $ret=Signalbot_CallSG($hash,"deleteGroup",shift @args);
		return $hash->{helper}{lasterr} if !defined $ret;
		delete $hash->{helper}{groups}; #Delete the whole hash to clean up removed groups
		print "deleted" if !defined $hash->{helper}{groups};
		Signalbot_refreshGroups($hash); #and read the back
		return;		
	} elsif ( $cmd eq "addGroupMembers" || $cmd eq "groupaddMembers") {
		return Signalbot_memberShip($hash,"addMembers",@args);
	} elsif ( $cmd eq "removeGroupMembers" || $cmd eq "groupremoveMembers") {
		return Signalbot_memberShip($hash,"removeMembers",@args);
	} elsif ( $cmd eq "addGroupAdmins" || $cmd eq "groupaddAdmins") {
		return Signalbot_memberShip($hash,"addAdmins",@args);
	} elsif ( $cmd eq "removeGroupAdmins" || $cmd eq "groupremoveAdmins") {
		return Signalbot_memberShip($hash,"removeAdmins",@args);
	} elsif ( $cmd eq "createGroup" || $cmd eq "groupcreate") {
		if (@args<1) {
			return "Usage: set ".$hash->{NAME}." createGroup <group name> &[path to thumbnail] [member1,member2...]";
		} else {
			my $ret=Signalbot_updateGroup($hash,@args);
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "updateProfile") {
		if (@args<1 || @args>2 ) {
			return "Usage: set ".$hash->{NAME}." updateProfile <new name> &[path to thumbnail]";
		} else {
			my $ret=Signalbot_updateProfile($hash,@args);
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "quitGroup" || $cmd eq "groupquit") {
		if (@args!=1) {
			return "Usage: set ".$hash->{NAME}." ".$cmd." <group name>";
		}
		my @group=Signalbot_getGroup($hash,$args[0]);
		return join(" ",@group) unless @group>1;
		Signalbot_CallA($hash,"quitGroup",\@group);
		return;
	} elsif ( $cmd eq "joinGroup" || $cmd eq "groupjoin") {
		if (@args!=1) {
			return "Usage: set ".$hash->{NAME}." ".$cmd." <group link>";
		}
		Signalbot_CallA($hash,"joinGroup",$args[0]);
		return;
	} elsif ( $cmd eq "block" || $cmd eq "unblock" || $cmd eq "contactblock" || $cmd eq "contactunblock" || $cmd eq "groupblock" || $cmd eq "groupunblock") {
		if (@args!=1) {
			return "Usage: set ".$hash->{NAME}." ".$cmd." <group name>|<contact>";
		} else {
			my $name=shift @args;
			my $ret=Signalbot_setBlocked($hash,$name,(($cmd=~ /unblock/)?0:1));
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "updateGroup" || $cmd eq "groupupdate") {
		if (@args<1 || @args>3 ) {
			return "Usage: set ".$hash->{NAME}." updateGroup <group name> #[new name] &[path to thumbnail]";
		} else {
			my $ret=Signalbot_updateGroup($hash,@args);
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "invite" || $cmd eq "groupinvite") {
		if (@args < 2 ) {
			return "Usage: set ".$hash->{NAME}." invite <group name> <contact1> [<contact2] ...]";
		} else {
			my $groupname = shift @args;
			my $ret=Signalbot_invite($hash,$groupname,@args);
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "send" || $cmd eq "reply" || $cmd eq "msg") {
		return "Usage: set ".$hash->{NAME}." send [@<Recipient1> ... @<RecipientN>] [#<GroupId1> ... #<GroupIdN>] [&<Attachment1> ... &<AttachmentN>] [<Text>]" if ( @args==0); 
		
		return Signalbot_prepareSend($hash,$cmd,@args);
	} 
	return "Unknown command $cmd";
}

sub Signalbot_memberShip($@) {
	my ($hash,$func,@args) = @_;
	return "Usage: set ".$hash->{NAME}." $func <groupname> <contact1> [contact2] ..." if (@args<2);
	my $version = $hash->{helper}{version};
	return "signal-cli 0.10.0+ required" if $version<1000;
	my $group=shift @args;
	my @contacts;
	foreach my $contact (@args) {
		my $c=Signalbot_translateContact($hash,$contact);
		return "Unknown contact $contact" if !defined $c;
		push @contacts,$c;
	}
	Signalbot_CallAG($hash,$func,$group,\@contacts);
	return;
}
		
sub Signalbot_prepareSend($@) {
	my ($hash,$cmd,@args)= @_;

	my @recipients = ();
	my @groups = ();
	my @attachments = ();
	my $message = "";
	#To allow spaces in strings, join string and split it with parse_line that will honor spaces embedded by double quotes
	my $fullstring=join(" ",@args);
	my $bExclude=AttrVal($hash->{NAME},"babbleExclude",undef);
	if ($bExclude && $fullstring =~ /$bExclude(.*)/s) {  #/s required so newlines are included in match
		#Extra utf Encoding marker)
		#$fullstring=encode_utf8($1);
		#Log3 $hash->{NAME}, 4 , $hash->{NAME}.": Extra UTF8 encoding of:$fullstring:\n";
	}
	#$fullstring=encode_utf8($fullstring) if($unicodeEncoding); 
	eval { $fullstring=decode_utf8($fullstring) if !($unicodeEncoding)};
	#	Log3 $hash->{NAME}, 3 , $hash->{NAME}.": Error from decode" if $@;
		
	LogUnicode $hash->{NAME}, 3 , $hash->{NAME}.": Before parse:" .$fullstring. ":";
	my $tmpmessage = $fullstring =~ s/\\n/\x0a/rg;
	@args=parse_line(' ',0,$tmpmessage);
	
	while(my $curr_arg = shift @args){
		if($curr_arg =~ /^\@([^#].*)$/){	#Compatbility with SiSi - also allow @# as groupname
			push(@recipients,$1);
		}elsif($curr_arg =~ /^\@#(.*)$/){ 	#Compatbility with SiSi - also allow @# as groupname
			push(@groups,$1);
		}elsif($curr_arg =~ /^#(.*)$/){
			push(@groups,$1);
		}elsif($curr_arg =~ /^\&(.*)$/){
			push(@attachments,$1);
		}else{
			unshift(@args,$curr_arg);
			last;
		}

	}
	my $defaultPeer=AttrVal($hash->{NAME},"defaultPeer",undef);
	if ($cmd eq "reply") {
		my $lastSender=ReadingsVal($hash->{NAME},"msgGroupName","");
		if ($lastSender ne "") {
			$lastSender="#".$lastSender;
		} else {
			$lastSender=ReadingsVal($hash->{NAME},"msgSender","");
		}
		$defaultPeer=$lastSender if $lastSender ne "";
		Log3 $hash->{NAME}, 4 , $hash->{NAME}.": Reply mode to $defaultPeer";
	}
	return "Not enough arguments. Specify a Recipient, a GroupId or set the defaultPeer attribute" if( (@recipients==0) && (@groups==0) && (!defined $defaultPeer) );

	#Check for embedded fhem/perl commands
	my $err;
	($err, @recipients) = Signalbot_replaceCommands($hash,@recipients);
	if ($err) { return $err; }
	($err, @groups) = Signalbot_replaceCommands($hash,@groups);
	if ($err) { return $err; }
	($err, @attachments) = Signalbot_replaceCommands($hash,@attachments);
	if ($err) { return $err; }
	
	if ((defined $defaultPeer) && (@recipients==0) && (@groups==0)) {

		my @peers = split(/,/,$defaultPeer);
		while(my $curr_arg = shift @peers){
			if($curr_arg =~ /^#/){
				push(@groups,$curr_arg);
			} else {
				push(@recipients,$curr_arg);
			}
		}
	}
	return "Specify either a message text or an attachment" if((@attachments==0) && (@args==0));

	$message = join(" ", @args);
	if (@attachments>0) {
		#create copy in /tmp to mitigate incomplete files and relative paths in fhem
		my @newatt;
		foreach my $file (@attachments) {
			if ( -e $file ) {
				if ($file=~/^\/tmp\/signalbot.*/ ne 1) {
					$file =~ /^.*?\.([^.]*)?$/;
					my $type = $1;
					my $tmpfilename="/tmp/signalbot".gettimeofday().".".$type;
					copy($file,$tmpfilename);
					push @newatt, $tmpfilename;
				} else {
					push @newatt, $file;
				}
			} else {
				my $png=Signalbot_getPNG($hash,$file);
				return "File not found: $file" if !defined $png;
				return $png if ($png =~ /^Error:.*/);
				push @newatt, $png;
			}
		}
		@attachments=@newatt;
	}
	#Convert html or markdown to unicode
	my $format=AttrVal($hash->{NAME},"formatting","none");
	my $convmsg=formatTextUnicode($format,$message);
	$message=$convmsg if defined $convmsg;
	my $ret;
	#Send message to individuals (bulk)
	if (@recipients > 0) {
		$ret=Signalbot_sendMessage($hash,join(",",@recipients),join(",",@attachments),$message);
	}
	if (@groups > 0) {
	#Send message to groups (one at time)
		while(my $currgroup = shift @groups){
			$ret=Signalbot_sendGroupMessage($hash,$currgroup,join(",",@attachments),$message);
		}
	}
	#Remember temp files
	my @atts = ();
	my $attstore = $hash->{helper}{attachments};
	if (defined $attstore) {
		@atts = @$attstore;
	}
	push @atts,@attachments;
	$hash->{helper}{attachments}=[@atts];
	return $ret;
}
################################### 
sub Signalbot_Get($@) {
	my ($hash, $name, @args) = @_;
	my $version = $hash->{helper}{version};	
	return "$name not initialized" if (!defined $version);

	my $numberOfArgs  = int(@args);
	return "Signalbot_Get: No cmd specified for get" if ( $numberOfArgs < 1 );

	my $cmd = shift @args;
	my $account = ReadingsVal($name,"account","none");

	if ($cmd eq "?") {
		my $gets="favorites:noArg accounts:noArg helpUnicode:noArg ";
		$gets.="contacts:all,nonblocked ".
			"groups:all,active,nonblocked devices:noArg " if $account ne "none";
		$gets .="groupProperties:textField " if $version >= 1000;
		return "Signalbot_Get: Unknown argument $cmd, choose one of ".$gets;
	}
	
	my $arg = shift @args;
	
	if ($cmd eq "introspective") {
		my $reply=Signalbot_CallS($hash,"org.freedesktop.DBus.Introspectable.Introspect");
		return undef;
	} elsif ($cmd eq "helpUnicode") {
		return demoUnicodeHTML();
	} elsif ($cmd eq "accounts") {
		my $num=Signalbot_getAccounts($hash);
		return "Error in listAccounts" if $num<0;
		my $ret="List of registered accounts:\n\n";
		my @numlist=@{$hash->{helper}{accountlist}};
		$ret=$ret.join("\n",@numlist);
		return $ret;
	} elsif ($cmd eq "devices") {
		my $ret=Signalbot_CallS($hash,"listDevices");
		my $str="Linked devices:\n\n";
		foreach my $dev (@$ret) {
			my ($devpath,$devid,$devname)=@$dev;
			if ($devid eq 1 && $devname eq "") {
				$devname="main device";
			}
			$str.=sprintf("%2i %s\n",$devid,$devname);
		}
	return $str;
	} elsif ($cmd eq "favorites") {
		my $favs = AttrVal($name,"favorites","");
		$favs =~ s/[\n\r]//g;
		$favs =~ s/;;/##/g;
		my @fav=split(";",$favs);
		return "No favorites defined" if @fav==0;
		my $ret="Defined favorites:\n\n";
		my $format="%2i (%s) %-15s %-50s\n";
		$ret.="ID (A) Alias           Command\n";
		my $cnt=1;
		foreach (@fav) {
			my $ff=$_;
			$ff =~ /(^\[(.*?)\])?([\-]?)(.*)/;
			my $aa="y";
			if ($3 eq "-") {
				$aa="n";
			}
			my $alias=$2;
			$alias="" if !defined $2;
			my $favs=$4;
			$favs =~ s/##/;;/g;
			$ret.=sprintf($format,$cnt,$aa,$alias,$favs);
			$cnt++;
		}
		$ret.="\n(A)=GoogleAuth required to execute command";
		return $ret;
	} elsif ($cmd eq "contacts" && defined $arg) {
		my $num=Signalbot_CallS($hash,"listNumbers");
		return $hash->{helper}{lasterr} if !defined $num;
		my @numlist=@$num;
		my $ret="List of known contacts:\n\n";
		my $format="%-16s|%-30s|%-6s\n";
		$ret.=sprintf($format,"Number","Name","Blocked");
		$ret.="\n";
		foreach my $number (@numlist) {
			my $blocked=Signalbot_CallS($hash,"isContactBlocked",$number);
			return $hash->{helper}{lasterr} if !defined $blocked;
			my $name=$hash->{helper}{contacts}{$number};
			if (!defined $name) {
				$name=Signalbot_getContactName($hash,$number);
			}
			$name="UNKNOWN" if ($name =~/^\+/);
			if (! ($number =~ /^\+/) ) { $number="Unknown"; }
			if ($arg eq "all" || $blocked==0) {
				$ret.=sprintf($format,$number,$name,$blocked==1?"yes":"no");
			}
		}
		return $ret;
	} elsif ($cmd eq "groups" && defined $arg) {
		Signalbot_refreshGroups($hash);
		
		my $ret="List of known groups:\n\n";
		my $memsize=40;
		my $format="%-20.20s|%-6.6s|%-7.7s|%-".$memsize.".".$memsize."s\n";
		$ret.=sprintf($format,"Group","Active","Blocked","Members");
		$ret.="\n";
		foreach my $groupid (keys %{$hash->{helper}{groups}}) {
			my $blocked=$hash->{helper}{groups}{$groupid}{blocked};
			my $active=$hash->{helper}{groups}{$groupid}{active};
			my $group=$hash->{helper}{groups}{$groupid}{name};
			my @groupID=split(" ",$groupid);
			my $mem=Signalbot_CallS($hash,"getGroupMembers",\@groupID);
			return $hash->{helper}{lasterr} if !defined $mem;
			my @members=();;
			foreach (@$mem) {
				push @members,Signalbot_getContactName($hash,$_);
			}
			if ($arg eq "all" || ($active==1 && $arg eq "active") || ($active==1 && $blocked==0 && $arg eq "nonblocked") ) {
				my $mem=join(",",@members);
				$ret.=sprintf($format,$group,$active==1?"yes":"no",$blocked==1?"yes":"no",substr($mem,0,$memsize));
				my $cnt=1;
				while (length($mem)>$cnt*$memsize) {
					$ret.=sprintf($format,"","","",substr($mem,$cnt*$memsize,$cnt*$memsize+$memsize));
					$cnt++;
				}
			}
		}
		return $ret;
	} elsif ($cmd eq "groupProperties") {
		return if $version<1000;
		my $ret=Signalbot_getGroupProperties($hash,$arg);
		return "Error:".$hash->{helper}{lasterr} if !defined $ret;
		my %props=%$ret;
		
		$ret="Group $arg\n==============================\n";
		$ret.="Description:".$props{Description}."\n";
		$ret.="IsMember:".(($props{IsMember}==1)?"yes":"no")."\n";
		$ret.="SendMessage:".$props{PermissionSendMessage}."\n";
		$ret.="EditDetails:".$props{PermissionEditDetails}."\n";
		$ret.="IsBlocked:".(($props{IsBlocked}==1)?"yes":"no")."\n";
		$ret.="IsAdmin:".(($props{IsAdmin}==1)?"yes":"no")."\n";
		
		my $members=$props{Members};
		$ret .="\nMembers:".join(",",Signalbot_contactsToList($hash,@$members));
		$members=$props{RequestingMembers};
		$ret .="\nRequesting members:".join(",",Signalbot_contactsToList($hash,@$members));
		$members=$props{Admins};
		$ret .="\nAdmins:".join(",",Signalbot_contactsToList($hash,@$members));
		$members=$props{PendingMembers};
		$ret .="\nPending members:".join(",",Signalbot_contactsToList($hash,@$members));
		return $ret;
	}
	return undef;
}

sub Signalbot_contactsToList($@) {
	my ($hash,@con) = @_;
	my @list;
	foreach (@con) {
		push @list,Signalbot_getContactName($hash,$_);
	}
	return @list;
}

sub Signalbot_command($@){
	my ($hash, $sender, $message) = @_;
	
	LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Check Command $sender $message";
	my $timeout=AttrVal($hash->{NAME},"authTimeout",300);
	return $message if $timeout==0;
	my $cmd=AttrVal($hash->{NAME},"cmdKeyword",undef);
	return $message unless defined $cmd;
	my @arr=();
	if ($message =~ /^$cmd(.*)/) {
		$cmd=$1;
		LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Command received:$cmd";
		my $device=AttrVal($hash->{NAME},"authDev",undef);
		if (!defined $device) {
			readingsSingleUpdate($hash, 'lastError', "Missing GoogleAuth device in authDev to execute remote command",1);
			return $message;
		}
		my @cc=split(" ",$cmd);
		if ($cc[0] =~ /^\d+$/) {
			#This could be a token
			my $token=shift @cc;
			my $restcmd=join(" ",@cc);
			my $ret = gAuth($device,$token);
			if ($ret == 1) {
				LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Token valid for sender $sender for $timeout seconds";
				$hash->{helper}{auth}{$sender}=1;
				#Remove potential old timer so countdown start from scratch
				RemoveInternalTimer("$hash->{NAME} $sender");
				InternalTimer(gettimeofday() + $timeout, 'Signalbot_authTimeout', "$hash->{NAME} $sender", 0);
				Signalbot_sendMessage($hash,$sender,"","You have control for ".$timeout."s");
				$cmd=$restcmd;
			} else {
				LogUnicode $hash->{NAME}, 3, $hash->{NAME}.": Invalid token sent by $sender";
				$hash->{helper}{auth}{$sender}=0;
				Signalbot_sendMessage($hash,$sender,"","Invalid token");
				LogUnicode $hash->{NAME}, 2, $hash->{NAME}.": Invalid token sent by $sender:$message";
				return $cmd;
			}
		}
		my $auth=0;
		if (defined $hash->{helper}{auth}{$sender} && $hash->{helper}{auth}{$sender}==1) {
			$auth=1;
		}
		my $fav=AttrVal($hash->{NAME},"cmdFavorite",undef);
		$fav =~ /^(-?)(.*)/;
		my $authList=$1;
		$fav = $2;
		my $error="";
		if (defined $fav && defined $cc[0] && $cc[0] eq $fav) {
			shift @cc;
			my $fav=AttrVal($hash->{NAME},"favorites","");
			eval { $fav=decode_utf8($fav) if !($unicodeEncoding)};
			$fav =~ s/[\n\r]//g;
			$fav =~ s/;;/##/g;
			my @favorites=split(";",$fav);
			if (@cc>0) {
				LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": $sender executes favorite command $cc[0]";
				if ($cc[0] =~/\d+$/) {
					#Favorite by index
					my $fid=$cc[0]-1;
					if ($fid<@favorites) {
						$cmd=$favorites[$fid];
						$cmd =~ /(^\[.*?\])?([\-]?)(.*)/;
						$cmd=$3 if defined $3;
						#"-" defined favorite commands that do not require authentification
						$auth=1 if (defined $2 && $2 eq "-");
						LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": $sender requests favorite command:$cmd";
					} else {
						$cmd="";
						$error="favorite #$cc[0] not defined";
					}
				} else {
					my $alias=join(" ",@cc);
					$cmd="";
					foreach my $ff (@favorites) {
						$ff =~ /(^\[(.*?)\])?([\-]?)(.*)/;
						if (defined $2 && $2 eq $alias) {
							$cmd=$4 if defined $4;
					#"-" defined favorite commands that do not require authentification
							$auth=1 if (defined $3 && $3 eq "-");
						}
					}
					if ($cmd eq "") {
						$error="favorite '$alias' not defined";
					}
				}
			} else {
				my $ret="Defined favorites:\n\n";
				$ret.="ID [Alias] Command\n";
				my $cnt=1;
				foreach (@favorites) {
					my $ff=$_;
					$ff =~ s/##/;;/g;
					$ff =~ /(^\[(.*?)\])?([\-]?)(.*)/;
					my $fav=$4;
					$fav =$1." ".$fav if defined $1;
					$fav =sprintf("%2i %s",$cnt,$fav);
					$fav =substr($fav,0,25)."..." if length($fav)>27;
					$ret.=$fav."\n";
					$cnt++;
				}
				$ret="No favorites defined" if @favorites==0;
				if ($auth || $authList eq "-") {
					Signalbot_sendMessage($hash,$sender,"",$ret);
					return $cmd;
				}
				$cmd="";
			}
		}
		# Always return the same message if not authorized
		if (!$auth) {
			readingsSingleUpdate($hash, 'lastError', "Unauthorized command request by $sender:$message",1);
			LogUnicode $hash->{NAME}, 2, $hash->{NAME}.": Unauthorized command request by $sender:$message";
			Signalbot_sendMessage($hash,$sender,"","You are not authorized to execute commands");
			return $cmd;
		}
		# If authorized return errors via Signal and Logfile
		if ($error ne "") {
			Signalbot_sendMessage($hash,$sender,"",$error);
			#Log3 $hash->{NAME}, 4, $hash->{NAME}.": $error";
		}
		return $cmd if $cmd eq "";

		LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": $sender executes command $cmd";
		$cmd =~ s/##/;/g;
		my %dummy; 
		my ($err, @a) = ReplaceSetMagic(\%dummy, 0, ( $cmd ) );
		if ( $err ) {
			LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": parse cmd failed on ReplaceSetmagic with :$err: on  :$cmd:";
		} else {
		$cmd = join(" ", @a);
			LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": parse cmd returned :$cmd:";
		}
		if ($cmd =~ /^print (.*)/) {
			$error=$1; #ReplaceSetMagic has already modified the string, treat it as error to send
			$cmd="";
		}
		elsif ($cmd =~ /{(.*)}/) {
			$error = AnalyzePerlCommand($hash, $1);
		} else {
			$error = AnalyzeCommandChain($hash, $cmd);
		}
		if (defined $error) {
			Signalbot_sendMessage($hash,$sender,"",$error);
		} else {
			Signalbot_sendMessage($hash,$sender,"","Done");
		}
		return $cmd; #so msgText gets logged without the cmdKeyword and actual command after favorite replacement
	}
   return $message;
}

#Reset auth after timeout
sub Signalbot_authTimeout($@) {
	my ($val)=@_;
	my ($name,$sender)=split(" ",$val);
	my $hash = $defs{$name};
	$hash->{helper}{auth}{$sender}=0;
}

#Wrapper around the new MessageReceived callback - currently ignored since V0.10.0 sends both callbacks
sub Signalbot_MessageReceivedV2 ($@) {
	my ($hash,$timestamp,$source,$groupID,$message,$extras) = @_;
	LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Message CallbackV2 - ignored";	
	return;
	my @attachments;
	if (defined $extras->{attachments}) {
		my @att =@{$extras->{attachments}};
		foreach (@att) {
			push @attachments, $_->{file};
		}
	}
	Signalbot_MessageReceived($hash,$timestamp,$source,$groupID,$message,\@attachments);
}	

sub Signalbot_MessageReceived ($@) {
	my ($hash,$timestamp,$source,$groupID,$message,$attachments) = @_;

	LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Message Callback";

	my $atr="";
	my @att=@$attachments;
	foreach (@att) {
		$atr.= $_." " if defined $_;
	}	

	my @groups=@$groupID;

	if ($message eq "" && @att==0) {
		#Empty message are sent with a group if group memberships or properties are changed (invite/leave/change name) - update membership
		if (@groups>0) {
			Signalbot_refreshGroups($hash);
		}
		return;
	}

	my $grp="";
	foreach (@groups) {
		$grp.=$_." " if defined $_;
	} 	

	my $group=Signalbot_translateGroup($hash,trim($grp));
	my $sender=Signalbot_getContactName($hash,$source);
	
	if (!defined $sender) {
		LogUnicode $hash->{NAME}, 3, $hash->{NAME}.":Issue with resolving contact $source\n";
		$sender=$source;
	}
	
	my $join=AttrVal($hash->{NAME},"autoJoin","no");
	if ($join eq "yes") {
		if ($message =~ /^https:\/\/signal.group\//) {
			Signalbot_CallA($hash,"joinGroup",$message);
			return;
		}
	}
	
	my $senderRegex = quotemeta($sender);
	#Also check the untranslated sender names in case these were used in allowedPeer instead of the real names
	my $sourceRegex = quotemeta($source);
	my $groupIdRegex = quotemeta($group);
	my $allowedPeer = AttrVal($hash->{NAME},"allowedPeer",undef);
	my $babble=1;
	if(!defined $allowedPeer || $allowedPeer =~ /^.*$senderRegex.*$/ || $allowedPeer =~ /^.*$sourceRegex.*$/ || ($groupIdRegex ne "" && $allowedPeer =~ /^.*$groupIdRegex.*$/)) {
		#Copy previous redings to keep history of on message
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "prevMsgTimestamp", ReadingsVal($hash->{NAME}, "msgTimestamp", undef)) if defined ReadingsVal($hash->{NAME}, "msgTimestamp", undef);
		readingsBulkUpdate($hash, "prevMsgText", ReadingsVal($hash->{NAME}, "msgText", undef)) if defined ReadingsVal($hash->{NAME}, "msgText", undef);
		readingsBulkUpdate($hash, "prevMsgSender", ReadingsVal($hash->{NAME}, "msgSender", undef)) if defined ReadingsVal($hash->{NAME}, "msgSender", undef);
		readingsBulkUpdate($hash, "prevMsgGroupName", ReadingsVal($hash->{NAME}, "msgGroupName", undef)) if defined ReadingsVal($hash->{NAME}, "msgGroupName", undef);
		readingsBulkUpdate($hash, "prevMsgGroupId", ReadingsVal($hash->{NAME}, "msgGroupId", undef)) if defined ReadingsVal($hash->{NAME}, "msgGroupId", undef);
		readingsBulkUpdate($hash, "prevMsgAttachment", ReadingsVal($hash->{NAME}, "msgAttachment", undef)) if defined ReadingsVal($hash->{NAME}, "msgAttachment", undef);
		readingsEndUpdate($hash, 0);

		my $cmd=AttrVal($hash->{NAME},"cmdKeyword",undef);
		if (defined $cmd && $message =~ /^$cmd(.*)/) { 
			$babble=0; #Skip Babble execution in command mode
			$message=Signalbot_command($hash,$source,$message);
		}
		#$message=encode_utf8($message);
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "msgAttachment", trim($atr));
		readingsBulkUpdate($hash, "msgTimestamp", strftime("%d-%m-%Y %H:%M:%S", localtime($timestamp/1000)));
		readingsBulkUpdate($hash, "msgText", $message);
		readingsBulkUpdate($hash, "msgSender", $sender);
		readingsBulkUpdate($hash, "msgGroupName", $group);
		#Check if for command execution
		my $auth=0;
		if (defined $hash->{helper}{auth}{$source}) { $auth=$hash->{helper}{auth}{$source}; }
		readingsBulkUpdate($hash, "msgAuth", $auth);
		readingsEndUpdate($hash, 1);

		my $bDevice=AttrVal($hash->{NAME},"babbleDev",undef);
		my $bPeer=AttrVal($hash->{NAME},"babblePeer",undef);
		my $bExclude=AttrVal($hash->{NAME},"babbleExclude",undef);
		
		if ($bExclude && $message =~ /$bExclude/) {
			LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Message matches BabbleExclude, skipping BabbleCall";
			return;
		}
		
		#Just pick one sender in den Priority: group, named contact, number, babblePeer
		my $replyPeer=undef;
		$replyPeer=$sourceRegex if (defined $sourceRegex and $sourceRegex ne "");
		$replyPeer=$senderRegex if (defined $senderRegex and $senderRegex ne "");
		$replyPeer="#".$groupIdRegex if (defined $groupIdRegex and $groupIdRegex ne "");
		
		#Activate Babble integration, only if sender or sender group is in babblePeer 
		if (defined $bDevice && defined $bPeer && defined $replyPeer && $babble==1) {
			if ($bPeer =~ /^.*$senderRegex.*$/ || $bPeer =~ /^.*$sourceRegex.*$/ || ($groupIdRegex ne "" && $bPeer =~ /^.*$groupIdRegex.*$/)) {
				LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": Calling Babble for $message ($replyPeer)";
				if ($defs{$bDevice} && $defs{$bDevice}->{TYPE} eq "Babble") {
					my $rep=Babble_DoIt($bDevice,$message,$replyPeer);
				} else {
					LogUnicode $hash->{NAME}, 2, $hash->{NAME}.": Wrong Babble Device $bDevice";
				}
			}
		}
		LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": Message from $sender : ".$message." processed";
	} else {
		LogUnicode $hash->{NAME}, 2, $hash->{NAME}.": Ignored message due to allowedPeer by $source:$message";
		readingsSingleUpdate($hash, 'lastError', "Ignored message due to allowedPeer by $source:$message",1);
	}
}

sub Signalbot_ReceiptReceived {
	my ($hash, $timestamp, $source) = @_;
	LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Signalbot_receive_callback $timestamp $source ";
	my $sender=Signalbot_getContactName($hash,$source);
	#Delete temporary files from last message(s)
	my $attstore = $hash->{helper}{attachments};
	if (defined $attstore) {
		my @atts = @$attstore;
		foreach my $file (@atts) {
			if ($file =~ /tmp\/signalbot/) {
				unlink $file;
			}
		}
		delete $hash->{helper}{attachments};
	}

	if (!defined $sender) {
		LogUnicode $hash->{NAME}, 3, $hash->{NAME}.":Issue with resolving contact $source\n";
		$sender=$source;
	}
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "sentMsgRecipient", $sender);
	readingsBulkUpdate($hash, 'sentMsgTimestamp', strftime("%d-%m-%Y %H:%M:%S", localtime($timestamp/1000)));
	readingsEndUpdate($hash, 0);
}

sub Signalbot_SyncMessageReceived {
	my ($hash,$timestamp, $source, $string1, $array1, $string2, $array2) = @_;
	LogUnicode $hash->{NAME}, 5, $hash->{NAME}."Signalbot: Signalbot_sync_callback $timestamp $source";
	my $tmp="";
	my @arr1=@$array1;
	foreach (@arr1) {
		$tmp.=$_." " if defined $_;
	} 

	my @arr2=@$array2;
	foreach (@arr2) {
		$tmp.= $_." " if defined $_;
	} 	
}

sub Signalbot_disconnect($@) {
	my ($hash) = @_;
	my $name=$hash->{NAME};
	eval { 
		delete $hash->{helper}{dbus} if defined $hash->{helper}{dbus};
		delete $hash->{helper}{dbuss} if defined $hash->{helper}{dbuss};
		delete $hash->{FD};
		$selectlist{"$name.dbus"} = undef;
		$hash->{STATE}="Disconnected";
		readingsSingleUpdate($hash, 'state', "disconnected",1);
	}; 
	if ($@) {
		Log3 $name, 4, "Error in disconnect:".$@;
	}
	Log3 $name, 5, "Disconnected and cleaned up";
}

# Initialize Connect and use FHEM select loop to wait for finish
sub Signalbot_setup($@){
	my ($hash) = @_;
	my $name=$hash->{NAME};
	if (defined $hash->{helper}{dbus}) {
		#Reinitialize everything to avoid double callbacks and other issues
		Signalbot_disconnect($hash);
	}
	#Clear error on init to avoid confusion with old erros
	readingsSingleUpdate($hash, 'lastError', "ok",0);
	delete $hash->{helper}{contacts};
	my $dbus = Protocol::DBus::Client::system();
	if (!defined $dbus) {
		Log3 $name, 3, $hash->{NAME}.": Error while initializing Dbus";
		$hash->{helper}{dbus}=undef;
		readingsSingleUpdate($hash, 'state', "unavailable",1);
		return "Error setting up DBUS - is Protocol::Dbus installed?";
	}
	$hash->{helper}{dbus}=$dbus;
	$dbus->initialize();
	#Second instance for syncronous calls
	my $dbus2 = Protocol::DBus::Client::system();
	if (!defined $dbus2) {
		Log3 $name, 3, $hash->{NAME}.": Error while initializing Dbus";
		$hash->{helper}{dbuss}=undef;
		readingsSingleUpdate($hash, 'state', "unavailable",1);
		return "Error setting up DBUS - is Protocol::Dbus installed?";
	}
	$hash->{helper}{dbuss}=$dbus2;
	$dbus2->initialize();
	delete $hash->{helper}{init};
	$dbus->blocking(0);
	#Get filehandle
	$hash->{FD}=$dbus->fileno();
	$selectlist{"$name.dbus"} = $hash;
	$hash->{STATE}="Connecting";
	Signalbot_fetchFile($hash,"svn.fhem.de","/fhem/trunk/fhem/contrib/signal/signal_install.sh","www/signal/signal_install.sh");
	chmod 0755, "www/signal/signal_install.sh";
	return undef;
}

my $Signalbot_Retry=0;
# After Dbus init successfully came back
sub Signalbot_setup2($@) {
	my ($hash) = @_;
	my $name=$hash->{NAME};
	my $dbus=$hash->{helper}{dbus};
	if (!defined $dbus) {
		return "Error: Dbus not initialized";
	}
	if (!$dbus->initialize()) { $dbus->init_pending_send(); return; }
	$hash->{helper}{init}=1;
	
	#Restore contactlist into internal hash
	my $clist=ReadingsVal($hash->{NAME}, "contactList",undef);
	if (defined $clist) {
		my @contacts=split(",",$clist);
		foreach my $val (@contacts) {
			my ($k,$v) = split ("=",$val);
			$hash->{helper}{contacts}{$k}=$v;
		}
	}
	my $version=Signalbot_CallS($hash,"version");
	my $account=ReadingsVal($name,"account","none");
	if (!defined $version) {
		if ($Signalbot_Retry<3) {
			$Signalbot_Retry++;
			InternalTimer(gettimeofday() + 10, 'Signalbot_setup', $hash, 0);
			Log3 $name, 3, $hash->{NAME}.": Could not init signal-cli - retry $Signalbot_Retry in 10 seconds";
		}
		return "Error calling version";
	}
	
	my @ver=split('\.',$version);
	#to be on the safe side allow 2 digits for version number, so 0.8.0 results to 800, 1.10.11 would result in 11011
	$hash->{VERSION}="Signalbot:".$Signalbot_VERSION." signal-cli:".$version." Protocol::DBus:".$Protocol::DBus::VERSION;
	$version=$ver[0]*10000+$ver[1]*100+$ver[2];
	$hash->{helper}{version}=$version;
	$hash->{model}=Signalbot_OSRel();
	#listAccounts only available in registration instance
	my $num=Signalbot_getAccounts($hash);
	#listAccounts failed - probably running in -u mode
	if ($num<0) {
		$hash->{helper}{signalpath}='/org/asamk/Signal';
		$account=Signalbot_CallS($hash,"getSelfNumber") if ($version>901); #Available from signal-cli 0.9.1
		#Workaround since signal-cli 0.9.0 did not include by getSelfNumber() method - delete the reading, so its not confusing
		if (!defined $account) { readingsDelete($hash,"account"); $account="none"; }
		$hash->{helper}{accounts}=0;
		$hash->{helper}{multi}=0;
	} else {
		my @numlist=@{$hash->{helper}{accountlist}};
		if (@numlist == 0 && $account ne "none") {
			#Reset account if there are no accounts but FHEM has one set
			Signalbot_setPath($hash,undef);
			return;
		}
		#Only one number existing - choose automatically if not already set)
		if(@numlist == 1 && $account eq "none") {
			Signalbot_setAccount($hash,$numlist[0]);
			$account=$numlist[0];
		}
		$hash->{helper}{multi}=1;
	}
	if ($account ne "none") {
		my $name=Signalbot_CallS($hash,"getContactName",$account);
		readingsSingleUpdate($hash, 'accountName', $name, 0) if defined $name;
	}
	
	#Initialize Signal listener only at the very end to make sure correct $signalpath is used
	my $signalpath=$hash->{helper}{signalpath};
	$dbus->send_call(
			path        => '/org/freedesktop/DBus',
			interface   => 'org.freedesktop.DBus',
			member      => 'AddMatch',
			destination => 'org.freedesktop.DBus',
			signature   => 's',
			body        => [ "type='signal',path='$signalpath'" 
		],
		);	
	$hash->{STATE}="Connected to $signalpath";
	readingsSingleUpdate($hash, 'state', $hash->{STATE},1);

	#-u Mode or already registered
	if ($num<0 || $account ne "none") {
		Signalbot_CallA($hash,"listNumbers");
		#Might make sense to call refreshGroups here, however, that is a sync call and might potentially take longer, so maybe no good idea in startup
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'account', $account) if defined $account;
		readingsBulkUpdate($hash, 'lastError', "ok");
		readingsEndUpdate($hash, 1);
		return undef;
	} else {
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'account', "none");
		readingsBulkUpdate($hash, 'joinedGroups', "");
		readingsBulkUpdate($hash, 'lastError', "No account registered - use set account to connect to an existing registration, link or register to get a new account");
		$hash->{STATE}="Disconnected";
		readingsBulkUpdate($hash, 'state', "disconnected");
		readingsEndUpdate($hash, 1);
		return undef;
	}
}

#Async Callback after updating Groups (change/invite/join/create)
sub Signalbot_UpdateGroup_cb($@) {
	my ($hash) = @_;
	Signalbot_refreshGroups($hash);
}

#Async Callback after getting list of Numbers, results will also be filled asynchronous
sub Signalbot_ListNumbers_cb($@) {
	my ($hash,$rec) = @_;
	my @numbers=@$rec;
	foreach (@numbers) {
		my $contact=Signalbot_getContactName($hash,$_);
	}
}

#async
sub	Signalbot_CallA($@) { 
	my ($hash,$function,@args) = @_;
	my $prototype=$signatures{$function};
	my $path=$hash->{helper}{signalpath};
	Signalbot_CallDbus($hash,0,$path,$function,$prototype,'org.asamk.Signal',@args);
}
#sync
sub	Signalbot_CallS($@) { 
	my ($hash,$function,@args) = @_;
	my $prototype=$signatures{$function};
	my $path=$hash->{helper}{signalpath};
	return Signalbot_CallDbus($hash,1,$path,$function,$prototype,'org.asamk.Signal',@args);
}
#async, group
sub	Signalbot_CallAG($@) { 
	my ($hash,$function,$group,@args) = @_;
	my $prototype=$groupsignatures{$function};
	my $path=Signalbot_getGroupPath($hash,$group);
	return if !defined $path;
	Signalbot_CallDbus($hash,0,$path,$function,$prototype,'org.asamk.Signal',@args);
}
#sync, group
sub	Signalbot_CallSG($@) { 
	my ($hash,$function,$group,@args) = @_;
	my $prototype=$groupsignatures{$function};
	my $path=Signalbot_getGroupPath($hash,$group);
	return if !defined $path;
	return Signalbot_CallDbus($hash,1,$path,$function,$prototype,'org.asamk.Signal',@args);
}

#all group properties
sub	Signalbot_getGroupProperties($@) { 
	my ($hash,$group) = @_;
	my $prototype="s";
	my $path=Signalbot_getGroupPath($hash,$group);
	return if !defined $path;
	return Signalbot_CallDbus($hash,1,$path,'GetAll',$prototype,'org.freedesktop.DBus.Properties','org.asamk.Signal.Group');
}

sub Signalbot_removeDevice($@) {
	my ($hash,$devid) = @_;
	return "DeviceID needs to be numeric" if (!looks_like_number($devid));
	return "You should not remove the main device" if $devid eq 1;
	my $path=$hash->{helper}{signalpath}."/Devices/".$devid;
	my @emptylist;
	return Signalbot_CallDbus($hash,1,$path,'removeDevice','','org.asamk.Signal',@emptylist);
}

sub Signalbot_CallDbus($@) {
	my ($hash,$sync,$path,$function,$prototype,$interface,@args) = @_;
	my $got_response=0;
	my $dbus=$hash->{helper}{dbus};
	if (!defined $dbus) {
		$hash->{helper}{lasterr}="Error: Dbus not initialized";
		readingsSingleUpdate($hash, 'lastError', $hash->{helper}{lasterr},1);
		return undef;
	}

	my $body="";
	if (@args>0) {
		$body=\@args;
	}
	#Call base service (registration mode)
	if (!defined $prototype) {
		$prototype=$regsig{$function};
		$path='/org/asamk/Signal';
	}
	LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Dbus Call sync:$sync $function($prototype) $path Args:".((@args==0)?"empty":join(",",@args));
	$dbus->send_call(
		path => $path,
		interface => $interface,
		signature => $prototype,
		body => $body,
		destination => 'org.asamk.Signal',
		member => $function,
	) ->then ( sub () {
			$got_response = 1;
			return if $sync; # Synchronous mode, handling of return data in main loop

			#Only for asynchronous case:
			my $msg = shift;
			my $sig = $msg->get_header('SIGNATURE');
			if (!defined $sig) {
				#Empty signature is probably a reply from a function without return data, nothing to do
				return undef;
			}
			my $b=$msg->get_body();
			my 	@body=@$b;
			LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": DBus callback: $function Args:".join(",",@body);
			CallFn($hash->{NAME},$function,$hash,@body);
		}
	) -> catch ( sub () {
			$got_response = -1;
			if ($function ne "listAccounts") { #listacccounts produces an error in some versions of signal-cli
				Log3 $hash->{NAME}, 4, $hash->{NAME}.": Dbus Error for: $function (details in reading lasterr)";
			}
			my $msg = shift;
			if (!defined $msg) {
				$hash->{helper}{lasterr}="Fatal Error in $function: empty message";
				readingsSingleUpdate($hash, 'lastError', $hash->{helper}{lasterr},1);
				return;
			}
			my $sig = $msg->get_header('SIGNATURE');
			if (!defined $sig) {
				$hash->{helper}{lasterr}="Error in $function: message without signature";
				readingsSingleUpdate($hash, 'lastError', $hash->{helper}{lasterr},1);
				return;
			}
			#Handle Error here and mark Serial for mainloop to ignore
			my $b=$msg->get_body()->[0];
			$hash->{helper}{lasterr}="Error in $function:".$b;
			readingsSingleUpdate($hash, 'lastError', $hash->{helper}{lasterr},1);
			return;
		}
	);
	return undef if !$sync; #Async mode returns immediately and uses callback functions

	#Evaluate reply in sync mode
	my $counter=5;
	while ($counter>0) {
		$dbus->blocking(1);
		my $msg=$dbus->get_message();
		#print Dumper($msg);
		if (defined $msg) {
			my $sig = $msg->get_header('SIGNATURE');
			if (!defined $sig) {
				#Empty signature is probably a reply from a function without return data, return 0 to differ to error case
				return 0;
			}
			my $b=$msg->get_body()->[0];
			if ($got_response==-1) {
				#Error Case
				$hash->{helper}{lasterr}="Error in $function:".$b;
				readingsSingleUpdate($hash, 'lastError', $hash->{helper}{lasterr},1);
				return undef;
			}
			if ($got_response==1) {
				return $b
			}
		}
		$counter--; #usleep(10000); 
	}
	Log3 $hash->{NAME}, 3, $hash->{NAME}.": Dbus Timeout for $function";
	return undef;
}

sub Signalbot_getGroupPath($@) {
	my ($hash,$group) = @_;
	my @arr=Signalbot_getGroup($hash,$group);
	if (@arr<2) {
		$hash->{helper}{lasterr}=join(" ",@arr);
		return undef;
	}
	return join(" ",@arr) unless @arr>1; #Error message
	#Get the DBus PATH to the group
	my $path=Signalbot_CallS($hash,"getGroup",\@arr);
	return "Cannot access group $group" if !defined $path;
	LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Group Dbus Path=".$path;
	if (! ($path =~ /^\//)) {
		$hash->{helper}{lasterr}=$path;
		return undef;
	}
	return $path
}

sub Signalbot_Read($@){
	my ($hash) = @_;
	if (!defined $hash->{helper}{init}) { Signalbot_setup2($hash); return;};

	my $dbus=$hash->{helper}{dbus};
	if (!defined $dbus) {
		return "Error: Dbus not initialized";
	}
	my $msg="";
	my $counter=5;
	while (defined $msg || $counter>0) {
		$dbus->blocking(0);
		$msg = $dbus->get_message();
		if ($msg) {
			#Signal handling
			my $callback = $msg->get_header('MEMBER');
			if (defined $callback) {
				my $b=$msg->get_body();
				my @body=@$b;
				if ($callback eq "MessageReceived" || $callback eq "ReceiptReceived" || $callback eq "SyncMessageReceived" || $callback eq "MessageReceivedV2") {
					my $func="Signalbot_$callback";
					LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Sync Callback: $callback Args:".join(",",@body);
					CallFn($hash->{NAME},$callback,$hash,@body);
				} elsif ($callback eq "NameAcquired") {
					Log3 $hash->{NAME}, 5, $hash->{NAME}.": My Dbus Name is $body[0]";
					$hash->{helper}{init}=$body[0];
				} else {
					Log3 $hash->{NAME}, 4, $hash->{NAME}.": Unknown callback $callback";
				}
			}
		}
		$counter--; usleep(10000); 
	}
}

sub Signalbot_getContactName($@) {
	my ( $hash,$number) = @_;

	#check internal inventory
	my $contact=$hash->{helper}{contacts}{$number};

	#if not found, ask Signal
	if (!defined $contact || $contact eq "") {
		#In this case it needs to stay synchronous, but should rarely be called due to caching
		$contact = Signalbot_CallS($hash,"getContactName",$number);
		#Add to internal inventory
		if (!defined $contact) {return "";}
		$hash->{helper}{contacts}{$number}=$contact;
	}
	if ($contact eq "") {return $number;}
	return $contact;
}

#Allow create only for new groups
sub Signalbot_updateGroup($@) {
	my ( $hash,@args) = @_;
	my $groupname = shift @args;
	if ($groupname =~ /^#(.*)/) {
		$groupname=$1;
	}
	my $rename;
	my $avatar;
	my @members;
	while (my $next = shift @args) {
		if ($next =~ /^#(.*)/) {
			$rename=$1;
		} elsif ($next =~ /^\&(.*)/) {
			$avatar=$1;
		} else {
			my $contact=Signalbot_translateContact($hash,$next);
			return "Unknown contact $next" if !defined $contact;
			push @members,$contact;
		}
	}
	if (defined $avatar) {
		return "Can't find file $avatar" unless ( -e $avatar);
		LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": updateGroup Avatar $avatar";
		my $size = -s $avatar;
		return "Please reduce the size of your group picture to <2MB" if ($size>2000000);
	}
	my @groupID=Signalbot_getGroup($hash,$groupname);
	#Rename case: Group has to exist
	if (defined $rename) {
		if (@groupID==1) {
			return "Group $groupname does not exist";
		} else {
			LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": renameGroup $groupname to $rename";
			Signalbot_CallA($hash,"updateGroup",\@groupID,$rename,\@members,$avatar);
			return;
		}
	} else {
		$avatar="" if (!defined $avatar);
		return "Group $groupname already exists" if @groupID>1;
		LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": createGroup $groupname:".join(" ",@members);
		Signalbot_CallA($hash,"createGroup",$groupname,\@members,$avatar);
		return;
	}
}

sub Signalbot_updateProfile($@) {
	my ($hash,@args) = @_;
	my $avatar;
	my $newname;
	while (my $next = shift @args) {
		if ($next =~ /^\&(.*)/) {
			$avatar=$1;
		} else {
			$newname=$next;
		}
	}
	if (defined $avatar) {
		return "Can't find file $avatar" unless ( -e $avatar);
		LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": updateProfile Avatar $avatar";
		my $size = -s $avatar;
		return "Please reduce the size of your group picture to <2MB" if ($size>2000000);
	} else { $avatar=""; }
	#new name, about, emoji, avatar, removeAvatar
	Signalbot_CallA($hash,"updateProfile",$newname,"","",$avatar,0);
}

sub Signalbot_invite($@) {
	my ( $hash,$groupname,@contacts) = @_;

	my @members=();
	while (@contacts) {
		my $contact=shift @contacts;
		my $number=Signalbot_translateContact($hash,$contact);
		return "Unknown Contact $contact" unless defined $number;
		push @members,$number;
	}
	
	my @group=Signalbot_getGroup($hash,$groupname);
	return join(" ",@group) unless @group>1;
	
	LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": Invited ".join(",",@members)." to $groupname";
	Signalbot_CallA($hash,"updateGroup",\@group,"",\@members,"");
	return;
}

sub Signalbot_setBlocked($@) {
	my ( $hash,$name,$blocked) = @_;
	if ($name =~ /^#(.*)/) {
		my @group=Signalbot_getGroup($hash,$1);
		return join(" ",@group) unless @group>1;
		LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": ".($blocked==0?"Un":"")."blocked $name";
		Signalbot_CallA($hash,"setGroupBlocked",\@group,$blocked);
	} else {
		my $number=Signalbot_translateContact($hash,$name);
		return "Unknown Contact" unless defined $number;
		LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": ".($blocked==0?"Un":"")."blocked $name ($number)";
		Signalbot_CallA($hash,"setContactBlocked",$number,$blocked);
	}
	return undef;
}

sub Signalbot_setContactName($@) {
	my ( $hash,$number,$name) = @_;

	if (!defined $number || !defined $name || $number eq "" || $name eq "") {
		return "setContactName: Number and Name required";
	}
	if ($number =~ /^[^\+].*/) {
		return "setContactName: Invalid number";
	}
	$hash->{helper}{contacts}{$number}=$name;

	Signalbot_CallA($hash,"setContactName",$number,$name);
	return undef;
}

sub Signalbot_translateContact($@) {
	my ($hash,$contact) = @_;
	#if contact looks like a number +..... just return it so this can even be called transparently for numbers and contact names
	return $contact if ( $contact =~ /^\+/ );
	my $con=$hash->{helper}{contacts};

	foreach my $key (keys %{$con}) {
		my $val=$con->{$key};
		return $key if $val eq $contact;
	}
	return undef;
}

sub Signalbot_translateGroup($@) {
	my ($hash, $groupID) = @_;
	my $groups=$hash->{helper}{groups};
	
	#Don't try to translate empty groupname
	if ($groupID eq "") { return ""; }
	
	my $group=$hash->{helper}{groups}{$groupID}{name};
	return $group if defined $group;

	#Group not found, so check if we simply don't know it yet
	Signalbot_refreshGroups($hash) if ($init_done);
	#And try again
	$group=$hash->{helper}{groups}{$groupID}{name};
	return $group if defined $group;
	return "Unknown group";
}

sub Signalbot_getNumber($@) {
	my ( $hash,$rec) = @_;
	my @recipient= split(/,/,$rec);
	
	#Das klappt nicht - kann man die Contacts nicht abfragen????
	#Interne liste in den readings pflegen, die bei setContactName geupdated wird und gespeichert bleibt?
	
	foreach(@recipient) {
		my $number=$hash->{helper}{contacts}{$_};
		if (!defined($number)){
		    my $bus = Net::DBus->system;
			my $service = $bus->get_service("org.asamk.Signal");
			my $object = $service->get_object("/org/asamk/Signal");

			my $number = 1;
		}
	}
}

sub Signalbot_refreshGroups($@) {
	my ( $hash ) = @_;
	my $ret= Signalbot_CallS($hash,"getGroupIds");
	return undef if !defined $ret;
	my @groups = @$ret;
	my @grouplist;
	foreach (@groups) {
		my @group=@$_;
		my $groupname = Signalbot_CallS($hash,"getGroupName",\@group);
		return $hash->{helper}{lasterr} if !defined $groupname;
		my $groupid = join(" ",@group);
		$hash->{helper}{groups}{$groupid}{name}=$groupname;	
		LogUnicode $hash->{NAME}, 5, "found group ".$groupname; 
		my $active = Signalbot_CallS($hash,"isMember",\@group);
		$active="?" if !defined $active;
		$hash->{helper}{groups}{$groupid}{active}=$active;
		my $blocked = Signalbot_CallS($hash,"isGroupBlocked",\@group);
		$blocked="?" if !defined $blocked;
		$hash->{helper}{groups}{$groupid}{blocked}=$blocked;
		if ($blocked==1) {
			$groupname="(".$groupname.")";
		}
		if ($active==1) {
			push @grouplist,$groupname;
		}
	}
	readingsSingleUpdate($hash, 'joinedGroups', join(",",@grouplist),1);
	return undef;
}

sub Signalbot_sendMessage($@) {
	my ( $hash,$rec,$att,$mes ) = @_;
	LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": sendMessage called for $rec:$att:".$mes; 

	my @recorg= split(/,/,$rec);
	my @attach=split(/,/,$att);
	my @recipient=();
	foreach (@recorg) {
		my $trans=Signalbot_translateContact($hash,$_);
		return "Unknown recipient ".$_ unless defined $trans;
		push @recipient, $trans;
	}
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "sentMsg", $mes);
	readingsBulkUpdate($hash, 'sentMsgTimestamp', "pending");
	readingsEndUpdate($hash, 0);
	Signalbot_CallA($hash,"sendMessage",$mes,\@attach,\@recipient); 
}

#get the identifies (list of hex codes) for a group based on the name
#Check error with int(@)=1
sub Signalbot_getGroup($@) {
	my ($hash,$rec) = @_;
	LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": getGroup $rec";
	if ( $rec =~ /^#(.*)/) {
		$rec=$1;
	}
	my $group;
	foreach my $groupid (keys %{$hash->{helper}{groups}}) {
		$group=$hash->{helper}{groups}{$groupid}{name};
		return split(" ",$groupid) if (defined $group && $group eq $rec);
	}
	Signalbot_refreshGroups($hash);
	foreach my $groupid (keys %{$hash->{helper}{groups}}) {
		$group=$hash->{helper}{groups}{$groupid}{name};
		return split(" ",$groupid) if (defined $group && $group eq $rec);
	}
	return "Unknown group ".$rec." please check or refresh group list";
}

sub Signalbot_sendGroupMessage($@) {
	my ( $hash,$rec,$att,$mes ) = @_;
	LogUnicode $hash->{NAME}, 4, $hash->{NAME}.": sendGroupMessage called for $rec:$att:$mes"; 

	$rec=~s/#//g;
	my @recipient= split(/,/,$rec);
	if (@recipient>1) { return "Can only send to one group at once";}
	my @attach=split(/,/,$att);
	my @arr=Signalbot_getGroup($hash,$rec);
	return join(" ",@arr) unless @arr>1;

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "sentMsg", $mes);
	readingsBulkUpdate($hash, 'sentMsgTimestamp', "pending");
	readingsEndUpdate($hash, 0);

	Signalbot_CallA($hash,"sendGroupMessage",$mes,\@attach,\@arr); 
}

################################### 
sub Signalbot_Attr(@) {					#
	my ($command, $name, $attr, $val) = @_;
	my $hash = $defs{$name};
	my $msg = undef;
	return if !defined $val; #nothing to do when deleting an attribute
	LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Attr $attr=$val"; 
	if($attr eq "allowedPeer") {
	#Take over as is
	return undef;
	}	elsif($attr eq "babbleExclude") {
	#Take over as is
	return undef;
	} elsif($attr eq "babblePeer") {
	#Take over as is
	my $bDevice=AttrVal($hash->{NAME},"babbleDev",undef);
	if (!defined $bDevice && $init_done) {
		foreach my $dev ( sort keys %main::defs ) {
			if ($defs{$dev}->{TYPE} eq "Babble") {
				CommandAttr(undef,"$name babbleDev $dev");
				last;
			}
		}
	}
	return undef;
	} elsif($attr eq "authTimeout" || $attr eq "cmdKeyword") {
	#Take over as is
	my $aDevice=AttrVal($hash->{NAME},"authDev",undef);
	if (!defined $aDevice && $init_done) {
		foreach my $dev ( sort keys %main::defs ) {
			if ($defs{$dev}->{TYPE} eq "GoogleAuth") {
				CommandAttr(undef,"$name authDev $dev");
				last;
			}
		}
	}
	return undef;
	} elsif($attr eq "authDev") {
	return undef unless (defined $val && $val ne "" && $init_done);
	my $bhash = $defs{$val};
	return "Unknown device $val" if !defined $bhash;
	return "Not a GoogleAuth device $val" unless $bhash->{TYPE} eq "GoogleAuth";
	return undef;
	} elsif($attr eq "cmdFavorite") {
		return undef;
	} elsif($attr eq "babbleDev") {
		return undef unless (defined $val && $val ne "" && $init_done);
		my $bhash = $defs{$val};
		return "Not a Babble device $val" unless $bhash->{TYPE} eq "Babble";
		return undef;
	}
	#check for correct values while setting so we need no error handling later
	foreach ('xx', 'yy') {
		if ($attr eq $_) {
			if ( defined($val) ) {
				if ( !looks_like_number($val) || $val <= 0) {
					$msg = "$hash->{NAME}: ".$attr." must be a number > 0";
				}
			}
		}
	}
	return $msg;	
}

sub Signalbot_setPath($$) {
	my ($hash,$val) = @_;
	my $account=$val;
	if (defined $val) {
		readingsSingleUpdate($hash, 'account', ($account=~s/^\_/\+/r),0);
		$hash->{helper}{signalpath}='/org/asamk/Signal/'.($val=~s/^\+/\_/r);
		LogUnicode $hash->{NAME}, 5, $hash->{NAME}." Using number $val";
	} else {
		$hash->{helper}{signalpath}='/org/asamk/Signal';
		LogUnicode $hash->{NAME}, 5, $hash->{NAME}." Setting number to default";
		readingsSingleUpdate($hash, 'account', "none" ,0 );
	}
	my $ret = Signalbot_setup($hash);
	$hash->{STATE} = $ret if defined $ret;
	return $ret;
}

sub Signalbot_checkNumber($) {
	my ($number) = @_;
	return undef if !defined $number;
	#Phone numbers need to start with + followed by a number (except 0) and an arbitrary list of digits (at least 5)
	if ($number =~ /^\+[1-9][0-9]{5,}$/) {
		#return with + replace to _ (which can be used or simply means "true")
		return $number =~ s/^\+/\_/r;
	}
	#return undef if the number is incorrect
	return undef;
}

sub Signalbot_getAccounts($) {
	my ($hash) = @_;
	my $num=Signalbot_CallS($hash,"listAccounts");
	return -1 if !defined $num;
	my @numlist=@$num;
	my @accounts;
	foreach my $number (@numlist) {
		my $account = $number =~ s/\/org\/asamk\/Signal\/_/+/rg;
		push @accounts,$account;
	}
	$hash->{helper}{accountlist}=\@accounts;
	$hash->{helper}{accounts}=@accounts;
	Log3 $hash->{NAME}, 5, $hash->{NAME}." Found @accounts";
	return @accounts;
}

sub Signalbot_setAccount($$) {
	my ($hash,$number) = @_;
	my $account = Signalbot_checkNumber($number);
	return "Account needs to start with '+' followed by digits" if !defined $account;
	my $num=Signalbot_CallS($hash,"listAccounts");
	return "Error in listAccounts" if !defined $num;
	my @numlist=@$num;
	foreach my $number (@numlist) {
		if ($number =~ /$account/) {
			Signalbot_setPath($hash,$account);
			return undef;
		}
	}
	return "Unknown account $account, please register or use listAccounts to view existing accounts";
}


sub Signalbot_Registration($$) {
	my ($hash,$account) = @_;
	my $name=$hash->{NAME};
	my $method=AttrVal($name,"registerMethod","SMS");
	$method=$method eq "SMS"?0:1;
	my $captcha=$hash->{helper}{captcha};
	my $ret;
	if (!defined $captcha) {
		#try without captcha (but never works nowadays)
		$ret=Signalbot_CallS($hash,"register",$account,$method);
		return -1 if (defined $ret)
	} else {
		$ret=Signalbot_CallS($hash,"registerWithCaptcha",$account,$method,$captcha);
	}
	return $ret;
}

sub Signalbot_createRegfiles($) {
	my ($hash) = @_;
	#Generate .reg file for easy Captcha retrieval
	my $ip=qx(hostname -I);
	my @ipp=split(" ",$ip);
	$ip=$ipp[0];
	
	if (! -d "www/signal") {
		mkdir("www/signal");
	}
	my $http="http";
	$http="https" if (AttrVal($FW_wname,"HTTPS",0) eq 1);
	my $fh;
	#1. For Windows
	my $tmpfilename="www/signal/signalcaptcha.reg";
	my $msg="Windows Registry Editor Version 5.00\n";
	$msg .= '[HKEY_CLASSES_ROOT\signalcaptcha]'."\n";
	$msg .= '@="URL:signalcaptcha"'."\n";
	$msg .= '"URL Protocol"=""'."\n";
	$msg .= '[HKEY_CLASSES_ROOT\signalcaptcha\shell]'."\n";
	$msg .= '[HKEY_CLASSES_ROOT\signalcaptcha\shell\open]'."\n";
	$msg .= '[HKEY_CLASSES_ROOT\signalcaptcha\shell\open\command]'."\n";
	$msg .= '@="powershell.exe Start-Process -FilePath ( $(\'';
	$msg .= $http."://".$ip;
	$msg .= ':8083/fhem?cmd=set%%20'.$hash->{NAME}.'%%20captcha%%20\'+($(\'%1\')';
	#Captcha has an extra "\" at the end which makes replacing with CSRF a bit more complicated
	if ($FW_CSRF ne "") {
		$msg.= '+$(\''.$FW_CSRF.'\')';
		$msg .= ' -replace \'^(.*)/&\',\'$1&\') ) )"'."\n";
	} else {
		$msg .= ' -replace \'^(.*)/$\',\'$1\') ) )"'."\n";
	}
	if(!open($fh, ">", $tmpfilename,)) {
		LogUnicode $hash->{NAME}, 3, $hash->{NAME}.": Can't write $tmpfilename";
	} else {
		print $fh $msg;
		close($fh);
	}
	#2. For Linux/X11
	$tmpfilename="www/signal/signalcaptcha.desktop";
	$msg  = "[Desktop Entry]\n";
	$msg .= "Name=Signalcaptcha\n";
	$msg .= 'Exec=xdg-open '.$http.'://'.$ip.':8083/fhem?cmd=set%%20'.$hash->{NAME}.'%%20captcha%%20%u'.$FW_CSRF."\n";
	$msg .= "Type=Application\n";
	$msg .= "Terminal=false\n";
	$msg .= "StartupNotify=false\n";
	$msg .= "MimeType=x-scheme-handler/signalcaptcha\n";
	if(!open($fh, ">", $tmpfilename,)) {
		LogUnicode $hash->{NAME}, 3, $hash->{NAME}.": Can't write $tmpfilename";
	} else {
		print $fh $msg;
		close($fh);
	}
}

sub Signalbot_Notify($$) {
	my ($own_hash, $dev_hash) = @_;
	my $ownName = $own_hash->{NAME}; # own name / hash

	return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled

	my $devName = $dev_hash->{NAME}; # Device that created the events
	my $events = deviceEvents($dev_hash,1);
	if ($devName eq "global" and grep(m/^INITIALIZED|REREADCFG$/, @{$events})) {
		my $def=$own_hash->{DEF};
		$def="" if (!defined $def); 
		Signalbot_Init($own_hash,$ownName." ".$own_hash->{TYPE}." ".$def);
	}
}

################################### 
sub Signalbot_Define($$) {			#
	my ($hash, $def) = @_;
	Log3 $hash->{NAME}, 2, $hash->{NAME}." Define: $def";
	
	$hash->{NOTIFYDEV} = "global";
		if ($init_done) {
			Log3 $hash->{NAME}, 2, "Define init_done: $def";
			my $ret=Signalbot_Init( $hash, $def );
			return $ret if $ret;
	}
	return undef;
}
################################### 
sub Signalbot_Init($$) {				#
	my ( $hash, $args ) = @_;
	$hash->{helper}{version}=0;
	Log3 $hash->{NAME}, 5, $hash->{NAME}.": Init: $args";
	if (defined $DBus_missing) {
		$hash->{STATE} ="Please make sure that Protocol::DBus is installed, e.g. by 'sudo cpan install Protocol::DBus'";
		Log3 $hash->{NAME}, 2, $hash->{NAME}.": Init: $hash->{STATE}";
		readingsSingleUpdate($hash, 'state', "unavailable",1);
		return $hash->{STATE};
	}
	Log3 $hash->{NAME}, 4, $hash->{NAME}.": Protocol::DBus version found ".$Protocol::DBus::VERSION;
	
	my @a = ();
	@a = split("[ \t]+", $args) if defined $args;
	shift @a;shift @a;
	my $name = $hash->{NAME};
	if (defined $args && @a>1)	{
		return "Define: Wrong syntax. Usage:\n" .
		       "define <name> Signalbot [phonenumber]";
	}

	Signalbot_Set($hash, $name, "setfromreading");
	my $account=ReadingsVal($name,"account","none");
	if ($account eq "none") {$account=$a[0]};
	return Signalbot_setPath($hash,$account);
}

sub Signalbot_fetchFile($$$$) {
	my ($hash, $host, $path, $name) = @_;
	my $msg=GetHttpFile($host,$path);
	if ($msg) {
		if (! -d "www/signal") {
			mkdir("www/signal");
		}
		my $fh;
		if(!open($fh, ">", $name,)) {
			Log3 $hash->{NAME}, 3, $hash->{NAME}.": Can't write $name";
		} else {
			print $fh $msg;
			close($fh);
		}
	}
}

sub Signalbot_Detail {
	my ($FW_wname, $name, $room, $pageHash) = @_;
	my $hash=$defs{$name};
	my $ret = "";
	if ($^O ne "linux") {
		return "SignalBot will only work on Linux - you run ".$^O."<br>This is because it requires some 3rd party tools only available on Linux.<br>Sorry.<br>";
	}

	if (defined $DBus_missing) {
		return "Perl module Protocol:DBus not found, please install with<br><b>sudo cpan install Protocol::DBus</b><br> and restart FHEM<br><br>";
	}
	my $multi=$hash->{helper}{multi};
	my $version=$hash->{helper}{version};
	$multi=0 if !defined $multi;
	if($version<1100) {
		$ret .= "<b>signal-cli v0.11.2+ required.</b><br>Please use installer to install or update<br>";
		$ret .= "<b>Note:</b> The installer only supports Debian based Linux distributions like Ubuntu and Raspberry OS<br>";
		$ret .= "      and X86 or armv7l CPUs<br>";
	}
	if ($multi==0 && $version>0) {
		$ret .= "Signal-cli is running in single-mode, please consider starting it without -u parameter (e.g. by re-running the installer)<br>";
	}
	if($version<1100 || $multi==0) {
		$ret .= '<br>You can download the installer <a href="www/signal/signal_install.sh" download>here</a> or your www/signal directory and run it with<br><b>sudo ./signal_install.sh</b><br><br>';
	}
	return $ret if ($hash->{helper}{version}<1100);
	
	my $current=ReadingsVal($name,"account","none");
	my $account=$hash->{helper}{register};
	my $verification=$hash->{helper}{verification};
	my $accounts=$hash->{helper}{accounts};

	#Not registered and no registration in progress
	if ($current eq "none" && !defined $account && !defined $verification && $multi==1) {
		$ret .= "To get started you need to <b>register a phone number</b> to FHEM ";
		$ret .= "or use <b>set account</b> to use one of your existing ".$accounts." accounts" if $accounts>0;
		$ret .= ".<br><br>";
		$ret .= "It is recommended that you use an landline number using <b>set register</b> (remember to set the attribute <b>registerMethod</b> to 'Voice' if you need to receive a voice call instead of SMS)<br><br>";
		$ret .= "Using a landline number typically will not interfere with using it for normal phone calls in parallel.<br>";
		$ret .= "<b>Warning:</b> Registering will remove any prior registration (e.g. unregister your Smartphone using Signal Messsenger)!<br><br>";
		$ret .= "You can however also <b>link</b> your Smartphone to FHEM (like a Desktop client) by using <b>set link</b> and scanning the QR Code.<br><br>";
		$ret .=" Be aware that using FHEM in linked mode might cause unexpected behaviour since FHEM will receive all your messages!<br>";
	}

	if(defined $account) {
		$ret .= "<b>Your registration for $account requires a Captcha to succeed.</b><br><br>";
		if ($FW_userAgent =~ /Mobile/) {
			$ret .= "You seem to access FHEM from a mobile device. If the Signal Messenger is installed on this device, the Captcha will be catched by Signal and you will not be able to properly register FHEM. Recommendation is to do this from Windows where this can mostly be automated<br><br>";
		}
		if ($FW_userAgent =~ /\(Windows/) {
			$ret .= "You seem to access FHEM from Windows. Please consider to download <a href=fhem/signal/signalcaptcha.reg download>this registry hack<\/a> and execute it. This helps to mostly automate the registration process<br><br>";
		}
		if ($FW_userAgent =~ /\((X11|Wayland)/) {
			$ret .= "You seem to access FHEM from a Linux Desktop. Please consider to download <a href=fhem/signal/signalcaptcha.desktop download>this mine scheme<\/a> and install under ~/.local/share/applications/signalcaptcha.desktop<br>";
			$ret .= "To activate it execute <b>xdg-mime default signalcaptcha.desktop x-scheme-handler/signalcaptcha</b> from your shell. This helps to mostly automate the registration process, however seems only to work with Firefox (not with Chromium)<br><br>";
		}
		$ret .= "Visit <a href=https://signalcaptchas.org/registration/generate.html>Signal Messenger Captcha Page<\/a> or <a href=https://signalcaptchas.org/challenge/generate.html>Alternative Captcha Page<\/a> and complete the captcha.<br><br>";
		if ($FW_userAgent =~ /\(Windows/) {
		$ret .= "If you applied the Windows registry hack, confirm opening Windows PowerShell and the rest will run automatically.<br><br>"
		}
		$ret .="If you're not using an automation option, you will then have to copy&paste the Captcha string that looks something like:<br><br>";
		$ret .="<i>signalcaptcha://signal-recaptcha-v2.6LfBXs0bAAAAAAjkDyyI1Lk5gBAUWfhI_bIyox5W.challenge.03AEkXO..........</i><br><br>";
		$ret .="After solving the captcha you will see a link below the captcha like 'open Signal'. Copy that link adress and<br><br>";
		$ret .="return here to use <b>set captcha</b> to paste it and continue registration.<br><br>";
	}

	if (defined $verification) {
		$ret .= "<b>Your registration for $verification requires a verification code to complete.</b><br><br>";
		$ret .= "You should have received a SMS or Voice call providing you the verification code.<br>";
		$ret .= "use <b>set verify</b> with that code to complete the process.<br>";
	}

	my $qr_url = $hash->{helper}{qr};
	if (defined $qr_url) {
		$ret .= "<table>";
		$ret .= "<tr><td rowspan=2>";
		$ret .= "<a href=\"$qr_url\"><img src=\"$qr_url\"><\/a>";
		$ret .= "</td>";
		$ret .= "<td><br>&nbsp;Scan this QR code to link FHEM to your existing Signal device<\/td>";
		$ret .= "</tr>";
		$ret .= "URI:".$hash->{helper}{uri}."<br>";
		$ret .= "</table><br>After successfully scanning and accepting the QR code on your phone, wait ~1min to let signal-cli sync and then execute <b>set reinit</b><br>";
		$ret .= "If you already have other accounts active, you might additionally have to do a <b>set signalAccount<br></b>"
	}

#  $ret .= "<div class='makeTable wide'>";
  $ret.="<form id='Signalbot' method='$FW_formmethod' autocomplete='off' ".
              "action='$FW_ME/Signalbot_sendMsg'>";
  $ret .= "<table class=\"block wide\">";
  $ret .= "<td>";
  $ret .= FW_submit("submit", "send message ")."<input type=\"text\" name=\"send\" size=\"80\">";
  $ret .= "<input type=\"hidden\" name=\"detail\" value=\"$hash->{NAME}\">";
  $ret .= "</table></form>";
	
	return if ($ret eq ""); #Avoid strange empty line if nothing is printed
	return $ret;
}

################################### 
sub Signalbot_Catch($) {
	my $exception = shift;
	if ($exception) {
		$exception =~ /^(.*)( at.*FHEM.*)$/;
		return $1;
	}
	return undef;
}
################################### 
sub Signalbot_State($$$$) {			#reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;

	return undef;
}
################################### 
sub Signalbot_Undef($$) {				#
	my ($hash, $name) = @_;
	Signalbot_disconnect($hash);
	return undef;
}

#Any part of the message can contain FHEM or {perl} commands that get executed here
#This is marked by being in (brackets) - returned is the result (without brackets)
#If its a media stream, a file is being created and the temporary filename (delete later!) is returned
#Question: more complex commands could contain spaces but that will require more complex parsing

sub Signalbot_replaceCommands(@) {
	my ($hash, @data) = @_;
	
	my @processed=();
	
	foreach my $string (@data) {
		#Commands need to be enclosed in brackets
		if ($string =~ /^\((.*)\)$/) {
			$string=$1; #without brackets
			my %dummy; 
			my ($err, @newargs) = ReplaceSetMagic(\%dummy, 0, ( $string ) );
			my $msg="";
			if ( $err ) {
				LogUnicode $hash->{NAME}, 3, $hash->{NAME}.": parse cmd failed on ReplaceSetmagic with :$err: on  :$string:";
			} else {
				$msg = join(" ", @newargs);
				LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": parse cmd returned :$msg:";
			}
			$msg = AnalyzeCommandChain( $hash, $msg );
			#If a normal FHEM command (no return value) is executed, $msg is undef - just the to empty string then
			if (!defined $msg) { 
				$msg=""; 
				LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": commands executed without return value";
			}
			#Only way to distinguish a real error with the return stream
			if ($msg =~ /^Unknown command/) { 
				LogUnicode $hash->{NAME}, 3, $hash->{NAME}.": Error message: ".$msg;
				return ($msg, @processed); 
			}
			
			my ( $isMediaStream, $type ) = Signalbot_IdentifyStream( $hash, $msg );
			if ($isMediaStream<0) {
				LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": Media stream found $isMediaStream $type";
				my $ret=Signalbot_copyToFile($msg,$type);
				return ("Can't write to temporary file",@processed) if !defined $ret;
				#If we created a file return the filename instead
				push @processed, $ret;
			} else {
				LogUnicode $hash->{NAME}, 5, $hash->{NAME}.": normal text found:$msg";
				#No mediastream - return what it was
				push @processed, $msg;
			}
		} else {
			#Not even in brackets, return as is
			push @processed, $string;
		}
		
	}
	
	return (undef,@processed);
}

sub Signalbot_copyToFile(@) {
	my ($msg,$type) = @_;
	my $tmpfilename="/tmp/signalbot".gettimeofday().".".$type;
	my $fh;
	if(!open($fh, ">", $tmpfilename,)) {
		#return undef since this is a fatal error
		return undef;
	}
	print $fh $msg;
	close($fh);
	return $tmpfilename;
}	

sub Signalbot_getPNG(@) {
	my ($hash, $file) = @_;

	my @special=split(",",$file);
	#does the first part equal to a FHEM device?
	my $sname = shift @special;
	my $shash = $defs{$sname};
	if (defined $shash) {
		Log3 $hash->{NAME}, 4 , $hash->{NAME}.": Attachment matches device $sname of type $shash->{TYPE}";
		my $svg;
		if ($shash->{TYPE} eq "SVG") {
			my $FW_RET_save=$FW_RET;
			$svg=plotAsPng($sname,@special);
			$FW_RET=$FW_RET_save;
		}
		if ($shash->{TYPE} eq "DOIF") {
			$svg=Signalbot_DOIFAsPng($shash,@special);
		}
		return undef if !defined $svg;
		return $svg if ($svg =~ /^Error:.*/);
		return Signalbot_copyToFile($svg,"png");
	}
	return;
}

#Special version with one Argument for returning the SVG as String
sub 
getSVGuiTable($) 
{
	my ($arg)=@_;
	return readSVGuiTable($arg,"");
}	
#Special public routine to retrieve the uiTable from a DOIF an store the SVG into the reading of a device
#Usage: getSVGuiTable("Device:Reading","DOIF_Device,device=source_device,val=reading");
sub
readSVGuiTable($$) 
{
	my ($doif,$device) = @_;
	my @special=split(",",$doif);
	my $sname = shift @special;
	my $shash = $defs{$sname};
	if ($shash->{TYPE} ne "DOIF") {
		return "getSVGuiTable() needs to specify a valid DOIF device as first argument (found $sname)";
	}
	push @special, "svg=1";
	my $svgdata=Signalbot_DOIFAsPng($shash,@special);
	$svgdata='<?xml version="1.0" encoding="UTF-8"?><svg>'.$svgdata.'</svg>';
	$svgdata=~/viewBox=\"(\d+) (\d+) (\d+) (\d+)\"/;
	my $x=$1;
	my $y=$2;
	my $width=$3/2;
	my $height=$4/2;
	my $w=$3*2;
	my $h=$4*2;
	#$svgdata=~s/viewBox=\"(\d+) (\d+) (\d+) (\d+)\"/viewbox=\"$x $y $width $height\" width=\"$w\" height=\"$h\"/g;
	
	return $svgdata if ($device eq "");
	my @reading=split(":",$device);
	return "Please specifiy device:reading to store your svg" if (@reading != 2);
	my $hash = $defs{$reading[0]};
	#$svgdata=~s/\n//ge;
	$svgdata=encode_utf8($svgdata);
	readingsSingleUpdate($hash,$reading[1],$svgdata,1);
}

#Special public routine to retrieve the uiTable from a DOIF an store the SVG into a file
#Usage: saveSVGuiTable("filename","DOIF_Device,device=source_device,val=reading");
sub
saveSVGuiTable($$) {
	my ($doif,$file)= @_;
	my @special=split(",",$doif);
	return "Filename required" if (!defined $file || $file eq "");
	my $sname = shift @special;
	my $shash = $defs{$sname};
	if ($shash->{TYPE} ne "DOIF") {
		return "getSVGuiTable() needs to specify a valid DOIF device as first argument";
	}
	push @special, "svg=1";
	my $svgdata=Signalbot_DOIFAsPng($shash,@special);
	$svgdata='<?xml version="1.0" encoding="UTF-8"?>'.$svgdata;
	my $fh;
	if(!open($fh, ">", $file,)) {
		#return undef since this is a fatal error
		return undef;
	}
	#Suppress "wide character" warning that is generated if special characters are used
	{no warnings; print $fh $svgdata; }
	close($fh);
	return $file;
}

sub
Signalbot_DOIFAsPng($@)
{
	my ($hash,@params) = @_;
	my (@webs, $mimetype, $svgdata, $rsvg, $pngImg);

	my $matchid=-1;
	my $sizex=-1;
	my $sizey=-1;
	my $zoom=1.0;
	my $matchdev="";
	my $matchread="";
	my $target="uiTable";
	my $svgonly=0;
	
	#If no further information given, take the first entry of uitables
	if (@params == 0) {
		$matchid=1;
	} else {
		foreach my $p (@params) {
			my @par=split("=",$p);
			my $cm=shift @par;
			my $val=shift @par;
			$matchid=$p if looks_like_number($p);
			next if (!defined $cm || !defined $val);
			if ($cm eq "id") {
				$matchid=$val if looks_like_number($val);
			} elsif ($cm eq "zoom") {
				$zoom=$val if looks_like_number($val);
			} elsif ($cm eq "dev") {
				$matchdev=$val;
			} elsif ($cm eq "svg") {
				$svgonly=$val;
			} elsif ($cm eq "val") {
				$matchread=$val;
			} elsif ($cm eq "sizex") {
				$sizex=$val if looks_like_number($val);
			} elsif ($cm eq "sizey") {
				$sizey=$val if looks_like_number($val);
			} elsif ($cm eq "state") {
				$target="uiState";
			}
		}
	}
	$target="uiState" if (!defined $hash->{$target}{table});
	my $table=$hash->{$target}{table};

	# "Error: uiTable/uiState not defined" 
	return "Error: $target not defined in $hash->{NAME}" if (!defined $table);
	
	my $id=0;
	my $cmd;
	OUTER:
	for (my $i=0;$i < scalar keys %{$table};$i++){
		for (my $k=0;$k < scalar keys %{$table->{$i}};$k++){
			for (my $l=0;$l < scalar keys %{$table->{$i}{$k}};$l++){
				for (my $m=0;$m < scalar keys %{$table->{$i}{$k}{$l}};$m++) {
					$id++;
					my $tab=$table->{$i}{$k}{$l}{$m};
					$tab =~ /.*DOIF_Widget\(.*?,.*?,.*?,(.*),.*\)/;
					$cmd=$1;
					next if !defined $cmd;
					if ($matchid==$id) {
						last OUTER;
					} elsif ($matchid==-1) {
						$cmd =~ /.*ReadingValDoIf\(\$hash,\'(.*?)\',\'(.*?)\'.*\)/;
						next if ($matchdev ne "" && $matchdev ne $1);
						next if ($matchread ne "" && $matchread ne $2);
						last OUTER;
					}
				}
			}
		}
		#Nothing found, since if something found we skip out with "last"
		$cmd="";
	}

	if (defined $cmd && $cmd ne "") {
		$cmd="package ui_Table;"."$cmd".";";
		$svgdata=eval($cmd);
		return if $@;
	} else {
		return "Error: uiTable format error";
	}

	$svgdata=decode_utf8($svgdata) if !($unicodeEncoding);
	$svgdata=~s/&#x(....)/chr(hex($1))/ge; #replace all html unicode with real characters since libsvg does not like'em

	return "Error: getting converting uiTable to SVG for $cmd" if (! defined $svgdata);
	if ($svgonly) {
		#Remove the fixed size so ftui or any other receiver can scale it themselves
		$svgdata =~ s/ width=\"(\d+)\" height=\"(\d+)\" style=\"width:(\d+)px; height:(\d+)px;\"//g;
		#Add XML header with right encoding
		return $svgdata;
	}

	$svgdata='<?xml version="1.0" encoding="UTF-8"?><svg>'.$svgdata.'</svg>';
	
	my $ret;
	eval {
		require Image::LibRSVG;
		$rsvg = new Image::LibRSVG();
		if ($sizex != -1 && $sizey !=-1) {
		$ret=$rsvg->loadFromStringAtZoomWithMax($svgdata, $zoom, $zoom, $sizex, $sizey  );
		} else {
		$ret=$rsvg->loadFromStringAtZoom($svgdata, $zoom, $zoom);
		}
		$pngImg = $rsvg->getImageBitmap() if $ret;
	};
	if (defined $pngImg && $pngImg ne "") {
		return $pngImg if $pngImg;
	}
	print $@;
	return "Error: Converting SVG to PNG for $cmd";
}

#Get OSRelease Version
sub Signalbot_OSRel() {
	my $fh;

	if (!open($fh, "<", "/etc/os-release")) {
		return "Unknown";
	}
	while (my $line = <$fh>) {
		chomp($line);
		if ($line =~ /PRETTY_NAME="(.*)"/) {
			close ($fh);
			return $1;
		}
	}
	close ($fh);
	return "Unknown";
}

sub LogUnicode($$$) {
	my ($name,$level,$text) = @_;
	$text=encode_utf8($text) if !($unicodeEncoding);
	Log3 $name, $level, $text;
}

######################################
#  Get a string and identify possible media streams
#  Copied from Telegrambot
#  PNG is tested
#  returns 
#   -1 for image
#   -2 for Audio
#   -3 for other media
# and extension without dot as 2nd list element
sub Signalbot_IdentifyStream($$) {
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

	return (-4,"mp4") if ( $msg =~ /^....\x66\x74\x79\x70\x69\x73\x6F\x6D/ );    # MP4 according to Wikipedia
	return (-4,"mpg") if ( $msg =~ /^\x00\x00\x01[\xB3\xBA]/ );    # MPG according to Wikipedia

	return (0,"txt");
}

1;

#Todo Write update documentation

=pod
=item device
=item summary Integration of Signal Messenger via signal_cli running as dbus daemon 
=item summary_DE Integration des Signal Messenger ueber signal_cli im dbus daemon modus

=begin html

<h3>Signalbot</h3>
<a id="Signalbot"></a>
For German documentation see <a href="https://wiki.fhem.de/wiki/Signalbot">Wiki</a>
<ul>
		provides an interface to the Signal Messenger, via signal_cli running as dbus daemon<br>
		The signal_cli package needs to be installed. See github for installation details on <a href="https://github.com/AsamK/signal-cli">signal-cli</a><br>
		An install script is available in the <a href="https://forum.fhem.de/index.php/topic,118370.0.html">FHEM forum</a><br>
		<br><br>
		Supported functionality:<br>
		<ul>
		<li>Send messages to individuals and/or groups with or without attachments</li>
		<li>Work with contacts and groups using real names instead of internal codes and numbers</li>
		<li>Group and contact names can contain space - surround them with quotes to use them in set commands</li>
		<li>Creaet, join and leave and administrate groups</li>
		<li>Register and link multiple devices and switch between them</li>
		<br>
		</ul>
</ul>
	<a id="Signalbot-define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; Signalbot [phonenumber]</code><br>
		The optional argument <b>phonenumber</b> will try to use an existing registration for this number if already present.<br>
		Note: To use multiple accounts (numbers) the signal-cli daemon needs to be started without the -u argument.<br>
		<br>
	</ul>

	<a id="Signalbot-set"></a>
	<b>Set</b>
	<ul>
		<li><b>set send [@&lt;Recipient1&gt; ... @&lt;RecipientN&gt;] [#&lt;GroupId1&gt; ... #&lt;GroupIdN&gt;] [&&lt;Attachment1&gt; ... &&lt;AttachmentN&gt;] [&lt;Text&gt;]</b><br>
			<a id="Signalbot-set-send"></a>
			Send a message to a Signal recipient using @Name or @+49xxx as well as groups with #Group or #@Group along with an attachment with &<path to file> and a message.
		</li>
			<ul>
			<a id="Signalbot-set-ignore"></a>
			<li>Use round brackets to let FHEM execute the content (e.g <code>&({plotAsPng('SVG_Temperatures')}</code></li>
			<li>If a recipient, group or attachment contains white spaces, the whole expression (including @ # or &) needs to be put in double quotes. Escape quotes within with \"</li>
			<li>If the round brackets contain curly brackets to execute Perl commands, two semi-colons (;;) need to be used to seperate multiple commands and at the end. The return value will be used e.g. as recipient</li>
			<li>For compatibility reasons @# can also be used to mark group names</li>
			<li>Messages to multiple recipients will be sent as one message</li>
			<li>Messages to multiple groups or mixed with individual recipients will be sent in multiple messages</li>
			<li>Attachments need to be file names readable for the fhem user with absolute path or relative to fhem user home</li>
			<li>Recipients can be either contact names or phone numbers (starting with +). Since signal-cli only understand phone numbers, 
			Signalbot tries to translate known contact names from its cache and might fail to send the message if unable to decode the contact</li><br>
			<li>To send multi line messages, use "\\n" in the message text</li>
			<br>
			Example:<br>
			<code>set Signalbot send "@({my $var=\"Joerg\";; return $var;;})" #FHEM "&( {plotAsPng('SVG_Temperatures')} )" Here come the current temperature plot</code><br>
			<br>
			</ul>
		<li><b>set reply ....</b><br>
			<a id="Signalbot-set-reply"></a>
			Send message to previous sender. For detailed syntax, see "set send"<br>
			If no recipient is given, sends the message back to the sender of the last received message. If the message came from a group (reading "msgGroupName" is set), the reply will go to the group, else the individual sender (reading "msgSender") is used.<br>
			<b>Note:</b> You should only use this from a NOTIFY or DOIF that was triggered by an incoming message otherwise you risk using the wrong recipient.<br>
		</li>
		<li><b>set setContact &ltnumber&gt &ltname&gt</b><br>
		<a id="Signalbot-set-setContact"></a>
		Define a nickname for a phone number to be used with the send command and in readings<br>
		</li>
		<li><b>set block #&ltgroupname&gt|&ltcontact&gt</b><br>
		<a id="Signalbot-set-block"></a>
		Put a group or contact on the blocked list (at the server) so you won't receive messages anymore. While the attribute "allowedPeer" is handled on FHEM level and messages are still received (but ignored), FHEM will not receive messages anymore for blocked communication partners<br>
		</li>
		<li><b>set unblock #&ltgroupname&gt|&ltcontact&gt</b><br>
		<a id="Signalbot-set-unblock"></a>
		Reverses the effect of "block", re-enabling the communication.<br>
		</li>
		<li><b>set createGroup &ltgroupname&gt [&&ltgroup picture&gt]</b><br>
		<a id="Signalbot-set-createGroup"></a>
		Define a new Signal group with the specified name.<br>
		Note: Pictures >2MB are known to cause issues and are blocked.<br>
		</li>
		<li><b>set updateGroup &ltgroupname&gt #[&ltnew groupname&gt] [&&ltgroup picture&gt]</b><br>
		<a id="Signalbot-set-updateGroup"></a>
		Update the name and/or group picture for an existing group.<br>
		Note: Pictures >2MB are known to cause issues and are blocked.<br>
		</li>
		<li><b>set invite &ltgroupname&gt &ltcontact&gt</b><br>
		<a id="Signalbot-set-invite"></a>
		Invite new members to an existing group. You can add multiple contacts separated by space.<br>
		</li>		
		<a id="Signalbot-set-joinGroup"></a>
		<li><b>set joinGroup &ltgroup link&gt</b><br>
		Join a group via an invitation group like (starting with https://signal.group/....). This link can be sent from the group properties with the "group link" function.<br>
		Easiest way is to share via Signal and set the "autoJoin" attribute which be recognized by Signalbot to automatically join.<br>
		</li>
		<li><b>set quitGroup &ltgroupname&gt</b><br>
		<a id="Signalbot-set-quitGroup"></a>
		Quit from a joined group. This only sets the membership to inactive, but does not delete the group (see "get groups")"<br>
		</li>
		<li><b>set updateProfile &ltnew name&gt [&&ltavatar picture&gt]</b><br>
		<a id="Signalbot-set-updateProfile"></a>
		Set the name of the FHEM Signal user as well as an optional avatar picture.<br>
		</li>
		<li><b>set signalAccount &ltnumber&gt</b><br>
		<a id="Signalbot-set-signalAccount"></a>
		Switch to a different already existing and registered account. When signal-cli runs in multi mode, the available numbers will be pre-filled as dropdown or can be updated by doing a "reinit".<br>
		</li>
		<li><b>set register &ltnumber&gt</b><br>
		<a id="Signalbot-set-register"></a>
		Start the registration wizard which will guide you through the registration of a new account including Captcha and Verification Code - just follow the instructions on the screen.<br>
		Remember to set the attribute registerMethod to "Voice" if you want to receive a voice call with the verification code instead of a SMS.<br>
		</li>
		<li><b>set captcha signalcaptcha://&ltcaptcha string&gt</b><br>
		<a id="Signalbot-set-captcha"></a>
		Typically registration requires you to solve a captcha to protect spam to phone numbers. The registration wizard will typically guide you through the process.<br>
		If the captcha is accepted use "set verify" to enter the verification code and finish registration.<br>
		</li>
		<li><b>set verify &ltverification code&gt</b><br>
		<a id="Signalbot-set-verify"></a>
		Last step in the registration process. Use this command to provide the verifcation code you got via SMS or voice call.<br>
		If this step is finished successfully, Signalbot is ready to be used.<br>
		</li>
		<li><b>set link &ltmy name&gt</b><br>
		<a id="Signalbot-set-link"></a>
		Alternative to registration: Link your Signal Messenger used with your smartphone to FHEM. A qr-code will be displayed that you can scan with your phone under settings->linked devices.<br>
		Use the optional name to identify your instance - if empty "FHEM" is used.<br>
		Note: This is not the preferred method, since FHEM will receive all the messages you get on your phone which can cause unexpected results.<br>
		</li>
		<li><b>set reinit</b><br>
		<a id="Signalbot-set-reinit"></a>
		Re-Initialize the module. For testing purposes when module stops receiving, has other issues or has been updated. Should not be necessary.<br>
		</li>
		<li><b>set addDevice &ltdevice URI&gt</b><br>
		<a id="Signalbot-set-addDevice"></a>
		Add another Signal instance as linked device. Typically the URI is presented as QR-Code though other Signalbot instances will display them as text when using the "set link" function. It starts with "sgnl://linkdevice..." <br>
		</li>
		<li><b>set removeDevice &ltdeviceID&gt</b><br>
		<a id="Signalbot-set-removeDevice"></a>
		Remove a linked device that was added to this instance with "addDevice". The deviceID can be retrieved with "get devices". If only one device is linked the id would typically be "2" as "1" is the main device.<br>
		You can only remove a device from the main device, otherwise you will get an authorization failed error.<br>
		</li>
		<li><b>set group &ltgroup command&gt &ltgroupname&gt &ltargument&gt</b><br>
		<a id="Signalbot-set-group"></a>
		Combined command for group related functions:
		<ul>
			<li>addMembers,removeMembers,addAdmins,removeAdmins &ltgroupname&gt &ltcontact(s)&gt : Modify the member or admin list for the group</li>
			<li>invite &ltgroupname&gt &ltcontact(s)&gt : Same as addMembers</li>
			<li>create &ltgroupname&gt [&ltcontact(s)&gt]: create a new group and optionally define members</li>
			<li>block/unblock &ltgroupname&gt : block/unblock receiving messages from a specific group</li>
			<li>quit &ltgroupname&gt : Leave a group</li>
			<li>join &ltgroup link&gt : Join a group with a group link.</li>
			<li>delete &ltgroupname&gt : Delete a group from local repository (you should first leave it)</li>
			<li>update &ltgroupname&gt &ltnew groupname&gt [&&ltavatar picture&gt] : Set a new name and/or picture for the group</li>
		</ul>
		</li>
		<li><b>set contact &ltcontact command&gt &ltcontact&gt &ltargument&gt</b><br>
		<a id="Signalbot-set-contact"></a>
		Combined command for contact related functions:
		<ul>
			<li>add &ltcontact&gt &ltnickname&gt : Define a local name for a contact</li>
			<li>delete &ltcontact&gt : Remove contact from local repository</li>
			<li>block/unblock &ltcontact&gt : block/unblock receiving messages from contact</li>
		</ul>
		</li>
		<br>
	</ul>
	
	<a id="Signalbot-get"></a>
	<b>Get</b>
	<ul>
		<li><b>get contacts all|nonblocked</b><br>
			<a id="Signalbot-get-contacts"></a>
			Shows an overview of all known numbers and contacts along with their blocked status. If "nonblocked" is chosen the list will not containt blocked contacts.<br>
		</li>
		<li><b>get groups all|active|nonblocked</b><br>
			<a id="Signalbot-get-groups"></a>
			Shows an overview of all known groups along with their active and blocked status as well as the list of group members.<br>
			Using the "active" option, all non-active groups (those you quit) are hidden, with "nonblocked" additionally the blocked ones get hidden.<br>
		</li>
		<li><b>get accounts</b><br>
			<a id="Signalbot-get-accounts"></a>
			Lists all accounts (phone numbers) registered on this computer.<br>
			Use register or link to create new accounts.<br>
		</li>
		<li><b>get favorites</b><br>
			<a id="Signalbot-get-favorites"></a>
			Lists the defined favorites in the attribute "favorites" in a readable format<br>
		</li>
		<li><b>get devices</b><br>
			<a id="Signalbot-get-devices"></a>
			Lists the defined devices linked to this devices. The ID "1" typically is this device and if no devices are linked this will be the only entry shown.<br>
		</li>
		<li><b>get helpUnicode</b><br>
			<a id="Signalbot-get-helpUnicode"></a>
			Opens a cheat sheet for all supported replacements to format text or add emoticons using html-like tags or markdown.<br>
			<b>Note:</b> This functionality needs to be enabled using the "formatting" attribute.<br>
		</li>
		<li><b>get groupPropertiese &ltgroup&gt</b><br>
			<a id="Signalbot-get-groupPropertiese"></a>
			Shows all known properties of the given group, like members, admins and permissions.
		</li>
		<br>
	</ul>

	<a id="Signalbot-attr"></a>
	<b>Attributes</b>
	<ul>
		<br>
		<li><b>registerMethod</b><br>
		<a id="Signalbot-attr-registerMethod></a>
			Choose if you want to receive your verification code by SMS or Voice call during the registration process.<br>
			Default: SMS, valid values: SMS, Voice<br>
		</li>
		<li><b>authTimeout</b><br>
		<a id="Signalbot-attr-authTimeout"></a>
			The number of seconds after which a user authentificated for command access stays authentifcated.<br>
			Default: 300, valid values: decimal number<br>
		</li>
		<li><b>authDev</b><br>
		<a id="Signalbot-attr-authDev"></a>
			Name of GoogleAuth device. Will normally be automatically filled when setting an authTimeout or cmdKeyword if a GoogleAuth device is already existing.<br>
		</li>
		<li><b>autoJoin no|yes</b><br>
		<a id="Signalbot-attr-autoJoin"></a>
			If set to yes, Signalbot will automatically inspect incoming messages for group invite links and join that group.<br>
			Default: no, valid values: no|yes<br>
		</li>
		<li><b>allowedPeer</b><br>
		<a id="Signalbot-attr-allowedPeer"></a>
			Comma separated list of recipient(s) and/or groupId(s), allowed to
			update the msg.* readings and trigger new events when receiving a new message.<br>
			<b>If the attribute is not defined, everyone is able to trigger new events!!</b>
		</li>
		<li><b>babblePeer</b><br>
		<a id="Signalbot-attr-babblePeer"></a>
			Comma separated list of recipient(s) and/or groupId(s) that will trigger that messages are forwarded to a Babble module defined by "babbleDev". This can be used to interpret real language interpretation of messages as a chatbot or to trigger FHEM events.<br>
			<b>If the attribute is not defined, nothing is sent to Babble</b>
		</li>
		<li><b>babbleDev</b><br>
		<a id="Signalbot-attr-babbleDev"></a>
			Name of Babble Device to be used. This will typically be automatically filled when bubblePeer is set.<br>
			<b>If the attribute is not defined, nothing is sent to Babble</b>
		</li>
		<li><b>babbleExclude</b><br>
		<a id="Signalbot-attr-babbleExclude"></a>
			RegExp pattern that, when matched, will exclude messages to be processed by the Babble connection<br>
		</li>
		<li><b>cmdKeyword</b><br>
		<a id="Signalbot-attr-cmdKeyword"></a>
			One or more characters that mark a message as GoogleAuth protected command which is directly forwarded to FHEM for processing. Example: for "="<br>
			=123456 set lamp off<br>
			where "123456" is a GoogleAuth token. The command after the token is optional. After the authentification the user stay for "authTimeout" seconds authentificated and can execute command without token (e.g. "=set lamp on").<br>
			<b>If the attribute is not defined, no commands can be issued</b>
		</li>
		<li><b>cmdFavorite</b><br>
		<a id="Signalbot-attr-cmdFavorite"></a>
			One or more characters that mark a message as favorite in GoogleAuth mode.<br>
			The favorite is either followed by a number or an alias as defined in the "favorite" attribute.<br>
			Assuming cmdKeyword "=" and cmdFavorite "fav", "=fav 1" will execute the first favorite.<br>
			Just sending "=fav" will list the available favorites.<br>
			<b>Note</b>: The cmdFavorite will be checked before an actual command is interpreted. So "set" will be a bad idea since you won't be able to use any "set" command anymore.
		</li>
		<li><b>favorites</b><br>
		<a id="Signalbot-attr-favorites"></a>
			Semicolon separated list of favorite definitions (see "cmdFavorite"). Favorites are identified either by their ID (defined by their order) or an optional alias in square brackets, preceding the command definition.<br>
		</li><li>
			<a id="Signalbot-attr-favignore"></a>
			Example: set lamp on;set lamp off;[lamp]set lamp on<br>
			This defines 3 favorites numbered 1 to 3 where the third one can also be accessed with the alias "lamp".<br>
			Using favorites you can define specific commands that can be executed without GoogleAuth by preceeding the command with a minus "-" sign.<br>
			Example: -set lamp off;[lamp]-set lamp on;set door open<br>
			Both favorites 1 and 2 (or "lamp") can be executed without authentification while facorite 3 requires to be authentificated.<br>
			You should use "get favorites" to validate your list and identify the correct IDs since no syntax checking is done when setting the attribute.<br>
			Multiple commands in one favorite need to be separeted by two semicolons ";;". For better readability you can add new lines anywhere - they are ignored (but spaces are not).<br>
			Special commands:<br>
			You can also embed Perl code with curly brackets: <i>{my $var=ReadingsVal("sensor","temperature",0);; return $var;;}</i><br>
			To just return a text and evaluate readings, you can use: <i>print Temperature is [sensor:temperature]</i><br>
		</li>
		<li><b>defaultPeer</b><br>
		<a id="Signalbot-attr-defaultPeer"></a>
			If <b>send</b> is used without a recipient, the message will send to this account or group(with #)<br>
		</li>
		<li><b>formatting</b><br>
		<a id="Signalbot-attr-formatting"></a>
			The "formatting" attribute has the following four options that allow highlighting in Unicode:
		<ul>
		<li>none - no replacements </li>
		<li>html - replacements are enabled here with HTML-type tags (e.g. for bold &lt;b&gt; is bold &lt;/b&gt;)</li>
		<li>markdown - replacements are enabled by markdown-like tags (e.g. __for italic__) as well as emotics</li>
		<li>both - both methods are possible here</li>
		</ul>
		To learn about the syntax how to use tags and markdown, use the get helpUnicode method. You can still also simply copy&paste Unicode text from other sources.
		</li>
		<br>
	</ul>
	<br>
	<a id="Signalbot-readings"></a>
	<b>Readings</b>
	<ul>
		<br>
		<li><b>account</b></li>
		The currently active account (phone number) - "none" if current not registered to a number.<br>
		<li><b>(prev)msgAttachment</b></li>
		Attachment(s) of the last received (or for history reasons the previous before). The path points to the storage in signal-cli and can be used to retrieve the attachment.<br>
		<li><b>(prev)msgGroupName</b></li>
		Group of the last message (or for history reasons the previous before). Empty if last message was a private message<br>
		<li><b>(prev)msgSender</b></li>
		Sender that sent the last message (or previous before) <br>
		<li><b>(prev)msgText</b></li>
		Content of the last message <br>
		<li><b>(prev)msgTimestamp</b></li>
		Time the last message was sent (a bit redundant, since all readings have a timestamp anyway<br>
		<li><b>msgAuth</b></li>
		Set to 1 if the user was authentificated via GoogleAuth by the time the message arrived, 0 otherwise.<br>
		<li><b>sentMsg</b></li>
		Content of the last message that was sent from this module<br>
		<li><b>sentRecipient</b></li>
		Recipient of the last message that was sent<br>
		This is taken from the actual reply and will contain the last recipient that confirmed getting the message in case multiple recipients or group members got it<br>
		<li><b>sentMsgTimestamp</b></li>
		Timestamp the message was received by the recipient. Will show pending of not confirmed (likely only if even the Signal server did not get it)<br>
		<li><b>joinedGroups</b></li>
		Comma separated list of groups the registered number has joined. Inactive groups will be skipped, blocked groups appear in brackets.<br>
	<br>
</ul>

=end html

=cut
