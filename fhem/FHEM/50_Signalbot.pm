##############################################
#$Id$
my $Signalbot_VERSION="3.1";
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

my %sets = (
  "send" => "textField",
  "reinit" => "noArg",
  "signalAccount" => "none",		#V0.9.0+
  "contact" => "textField",
  "createGroup" => "textField",		#Call updategroups with empty group parameter, mandatory name and optional avatar picture
  "invite" => "textField",			#Call updategroups with mandatory group name and mandatory list of numbers to join
  "block" => "textField",			#Call setContactBlocked or setGroupBlocked (one one at a time)
  "unblock" => "textField",			#Call setContactBlocked or setGroupBlocked (one one at a time)
  "updateGroup" => "textField",		#Call updategroups to rename a group and/or set avatar picture
  "quitGroup" => "textField",		#V0.8.1+
  "joinGroup" => "textField",		#V0.8.1+
  "updateProfile" => "textField",	#V0.8.1+
  "link" => "noArg",				#V0.9.0+
  "register" => "textField",		#V0.9.0+
  "captcha" => "textField",			#V0.9.0+
  "verify" => "textField",			#V0.9.0+
 );
 
 my %gets = (
  "contacts"      => "all,nonblocked",			#V0.8.1+
  "groups"        => "all,active,nonblocked",	#V0.8.1+
  "accounts"      => "noArg",					#V0.9.0+
#  "introspective" => "noArg"
);


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
	"getGroupIds" 			=> "aay",
	"getGroupName" 			=> "ay",
	"getGroupMembers" 		=> "ay",
	"listNumbers" 			=> "",
	"getContactNumber" 		=> "s",
	"isContactBlocked" 		=> "s",
	"isGroupBlocked" 		=> "ay",
	"version" 				=> "",
	"isMember"				=> "ay",
	"getSelfNumber"			=> "", #V0.9.1
#	"isRegistered" 			=> "", Removing this will primarily use the register instance, so "true" means -U mode, "false" means multi
	"sendEndSessionMessage" => "as",		#unused
	"sendRemoteDeleteMessage" => "xas",		#unused
	"sendGroupRemoteDeletemessage" => "xay",#unused
	"sendMessageReaction" => "sbsxas",		#unused
	"sendGroupMessageReaction" => "sbsxay",	#unused
);

#dbus interfaces that only exist in registration mode
my %regsig = (
	"listAccounts"			=> "",
	"isRegistered"			=> "",
	"link"					=> "s",
	"registerWithCaptcha"	=> "sbs",	#not implemented yet
	"verifyWithPin"			=> "sss",	#not implemented yet
	"register"				=> "sb",	#not implemented yet
	"verify"				=> "ss",	#not implemented yet
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
  $hash->{ReceiptReceived} = "Signalbot_ReceiptReceived";
  $hash->{version}		= "Signalbot_Version_cb";
  $hash->{updateGroup}  = "Signalbot_UpdateGroup_cb";
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
												"autoJoin:yes,no ".
												"registerMethod:SMS,Voice ".
												"$readingFnAttributes";
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
		}
		return "Signalbot_Set: Unknown argument $cmd, choose one of " . join(" ", @cList);
	} # error unknown cmd handling
	
	# Works always
	if ( $cmd eq "reinit") {
		my $ret = Signalbot_setup($hash);
		$hash->{STATE} = $ret if defined $ret;
		$hash->{helper}{qr}=undef;
		Signalbot_createRegfiles($hash);
		return undef;
	}

	#Pre-parse for " " embedded strings, except for "send" that does its own processing
	if ( $cmd ne "send") {
		@args=parse_line(' ',0,join(" ",@args));
	}
	if ( $cmd eq "signalAccount" ) {
		#When registered, first switch back to default account
		my $number = shift @args;
		return "Invalid number" if !defined Signalbot_checkNumber($number);;
		my $ret = Signalbot_setAccount($hash, $number);
		# undef is success
		if (!defined $ret) {
			Signalbot_refreshGroups($hash);
			$hash->{helper}{qr}=undef;
			$hash->{helper}{register}=undef;
			$hash->{helper}{verification}=undef;
			return undef;
		}
		#if some error occured, register the old account
		$ret = Signalbot_setAccount($hash,$account);
		return "Error changing account, using previous account $account";
	} elsif ($cmd eq "link") {
		my $qrcode=Signalbot_CallS($hash,"link","FHEM");
		
		if (defined $qrcode) {
			my $qr_url = "https://chart.googleapis.com/chart?cht=qr&chs=200x200"."&chl=";
			$qr_url .= uri_escape($qrcode);
			$hash->{helper}{qr}=$qr_url;
			$hash->{helper}{register}=undef;
			$hash->{helper}{verification}=undef;
			return undef;
		}
		return "Error creating device link";
	} elsif ( $cmd eq "register") {
		my $account= shift @args;
		return "Number needs to start with '+' followed by digits" if !defined Signalbot_checkNumber($account);
		my $ret=Signalbot_Registration($hash,$account);
		if (!defined $ret) {
			my $err=ReadingsVal($name,"lastError","");
			$err="Captcha";
			if ($err =~ /Captcha/) {
				$hash->{helper}{register}=$account;
				$hash->{helper}{verification}=undef;
				$hash->{helper}{qr}=undef;
				Signalbot_createRegfiles($hash);
				return;
			}
		}
		$hash->{helper}{verification}=$account;
		$hash->{helper}{register}=undef;
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
		return if !defined $ret;
		if ($ret == 0) {
			#On successfuly verification switch to that account
			$ret=Signalbot_setAccount($hash,$account);
			return $ret if defined $ret;
			$hash->{helper}{register}=undef;
			$hash->{helper}{verification}=undef;
			return undef;
		}
		return $ret;
	} elsif ( $cmd eq "contact") {
		if (@args<2 ) {
			return "Usage: set ".$hash->{NAME}." contact <number> <nickname>";
		} else {
			my $number = shift @args;
			my $nickname = join (" ",@args);
			my $ret=Signalbot_setContactName($hash,$number,$nickname);
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "createGroup") {
		if (@args<1 || @args>2 ) {
			return "Usage: set ".$hash->{NAME}." createGroup <group name> &[path to thumbnail]";
		} else {
			my $ret=Signalbot_updateGroup($hash,@args);
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "updateProfile") {
		if ($version<=800) {
			return "updateProfile requires signal-cli 0.8.1 or higher";
		}
		if (@args<1 || @args>2 ) {
			return "Usage: set ".$hash->{NAME}." updateProfile <new name> &[path to thumbnail]";
		} else {
			my $ret=Signalbot_updateProfile($hash,@args);
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "quitGroup") {
		if ($version<=800) {
			return $cmd." requires signal-cli 0.8.1 or higher";
		}
		if (@args!=1) {
			return "Usage: set ".$hash->{NAME}." ".$cmd." <group name>";
		}
		my $ret;
		my @group=Signalbot_getGroup($hash,$args[0]);
		return join(" ",@group) unless @group>1;
		Signalbot_Call($hash,"quitGroup",\@group);
		return undef;
	} elsif ( $cmd eq "joinGroup") {
		if (@args!=1) {
			return "Usage: set ".$hash->{NAME}." ".$cmd." <group link>";
		}
		return Signalbot_join($hash,$args[0]);
	} elsif ( $cmd eq "block" || $cmd eq "unblock") {
		if (@args!=1) {
			return "Usage: set ".$hash->{NAME}." ".$cmd." <group name>|<contact>";
		} else {
			my $name=shift @args;
			my $ret=Signalbot_setBlocked($hash,$name,($cmd eq "block"?1:0));
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "updateGroup") {
		if (@args<1 || @args>3 ) {
			return "Usage: set ".$hash->{NAME}." updateGroup <group name> #[new name] &[path to thumbnail]";
		} else {
			my $ret=Signalbot_updateGroup($hash,@args);
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "invite") {
		if (@args < 2 ) {
			return "Usage: set ".$hash->{NAME}." invite <group name> <contact1> [<contact2] ...]";
		} else {
			my $groupname = shift @args;
			my $ret=Signalbot_invite($hash,$groupname,@args);
			return $ret if defined $ret;
		}
		return undef;
	} elsif ( $cmd eq "send") {
		return "Usage: set ".$hash->{NAME}." send [@<Recipient1> ... @<RecipientN>] [#<GroupId1> ... #<GroupIdN>] [&<Attachment1> ... &<AttachmentN>] [<Text>]" if ( @args==0); 

		my @recipients = ();
		my @groups = ();
		my @attachments = ();
		my $message = "";
		#To allow spaces in strings, join string and split it with parse_line that will honor spaces embedded by double quotes
		my $fullstring=join(" ",@args);
		my $bExclude=AttrVal($hash->{NAME},"babbleExclude",undef);
		if ($bExclude && $fullstring =~ /$bExclude(.*)/s) {  #/s required so newlines are included in match
			#Extra utf Encoding marker)
			$fullstring=encode_utf8($1);
			Log3 $hash->{NAME}, 4 , $hash->{NAME}.": Extra UTF8 encoding of:$fullstring:\n";
		}
		eval { $fullstring=decode_utf8($fullstring); };
			Log3 $hash->{NAME}, 3 , $hash->{NAME}.": Error from decode" if $@;
			
		Log3 $hash->{NAME}, 3 , $hash->{NAME}.": Before parse:" . encode_utf8($fullstring) . ":";
		my $tmpmessage = $fullstring =~ s/\\n/\x0a/rg;
		my @args=parse_line(' ',0,$tmpmessage);
		
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
		return "Not enough arguments. Specify a Recipient, a GroupId or set the defaultPeer attribute" if( (@recipients==0) && (@groups==0) && (!defined $defaultPeer) );

		#Check for embedded fhem/perl commands
		my $err;
		($err, @recipients) = SignalBot_replaceCommands($hash,@recipients);
		if ($err) { return $err; }
		($err, @groups) = SignalBot_replaceCommands($hash,@groups);
		if ($err) { return $err; }
		($err, @attachments) = SignalBot_replaceCommands($hash,@attachments);
		if ($err) { return $err; }
		
		#Am Schluss eine Schleife über die Attachments und alle die mit /tmp/signalbot anfangen löschen (unlink)

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
					if ($file =~ /[tmp\/signalbot]/) {
						$file =~ /^.*?\.([^.]*)?$/;
						my $type = $1;
						my $tmpfilename="/tmp/signalbot".gettimeofday().".".$type;
						copy($file,$tmpfilename);
						push @newatt, $tmpfilename;
					} else {
						push @newatt, $file;
					}
				} else {
					return "File not found: $file";
				}
			}
			@attachments=@newatt;
		}

		#Send message to individuals (bulk)
		if (@recipients > 0) {
			Signalbot_sendMessage($hash,join(",",@recipients),join(",",@attachments),$message);
		}
		if (@groups > 0) {
		#Send message to groups (one at time)
			while(my $currgroup = shift @groups){
				Signalbot_sendGroupMessage($hash,$currgroup,join(",",@attachments),$message);
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
	} 
	return undef;
}
################################### 
sub Signalbot_Get($@) {
	my ($hash, $name, @args) = @_;
	
	my $numberOfArgs  = int(@args);
	return "Signalbot_Get: No cmd specified for get" if ( $numberOfArgs < 1 );

	my $cmd = shift @args;

	if (!exists($gets{$cmd}))  {
		my @cList;
		foreach my $k (keys %gets) {
			my $opts = undef;
			$opts = $gets{$k};

			if (defined($opts)) {
				push(@cList,$k . ':' . $opts);
			} else {
				push (@cList,$k);
			}
		}
		return "Signalbot_Get: Unknown argument $cmd, choose one of " . join(" ", @cList);
	} # error unknown cmd handling
	
	my $version = $hash->{helper}{version};
	my $arg = shift @args;
	
	if ($cmd eq "introspective") {
		my $reply=Signalbot_CallS($hash,"org.freedesktop.DBus.Introspectable.Introspect");
		return undef;
	} elsif ($cmd eq "accounts") {
		if ($version<900) {
			return "Signal-cli 0.9.0 required for this functionality";
		}
		my $num=Signalbot_CallS($hash,"listAccounts");
		return "Error in listAccounts" if !defined $num;
		my @numlist=@$num;
		my $ret="List of registered accounts:\n\n";
		foreach my $number (@numlist) {
			my $account = $number =~ s/\/org\/asamk\/Signal\/_/+/rg;
			$ret.=$account."\n";
		}
		return $ret;
	}
	
	if ($gets{$cmd} =~ /$arg/) {
		if ($cmd eq "contacts") {
			if ($version<=800) {
				return "Signal-cli 0.8.1+ required for this functionality";
			}
			my $num=Signalbot_CallS($hash,"listNumbers");
			return "Error in listNumbers" if !defined $num;
			my @numlist=@$num;
			my $ret="List of known contacts:\n\n";
			my $format="%-16s|%-30s|%-6s\n";
			$ret.=sprintf($format,"Number","Name","Blocked");
			$ret.="\n";
			foreach my $number (@numlist) {
				my $blocked=Signalbot_CallS($hash,"isContactBlocked",$number);
				my $name=$hash->{helper}{contacts}{$number};
				$name="UNKNOWN" unless defined $name;
				if (! ($number =~ /^\+/) ) { $number="Unknown"; }
				if ($arg eq "all" || $blocked==0) {
					$ret.=sprintf($format,$number,$name,$blocked==1?"yes":"no");
				}
			}
			return $ret;
		} elsif ($cmd eq "groups") {
			Signalbot_refreshGroups($hash);
			if ($version<=800) {
				return "Signal-cli 0.8.1+ required for this functionality";
			}
			
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
				return "Error reading group memebers" if !defined $mem;
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
		}
	} else {
		return "Signalbot_Set: Unknown argument for $cmd : $arg";
	}
	return undef;
}

sub Signalbot_command($@){
	my ($hash, $sender, $message) = @_;
	
	Log3 $hash->{NAME}, 5, $hash->{NAME}.": Check Command $sender $message";
	my $timeout=AttrVal($hash->{NAME},"authTimeout",0);
	return $message if $timeout==0;
	my $device=AttrVal($hash->{NAME},"authDev",undef);
	return $message unless defined $device;
	my $cmd=AttrVal($hash->{NAME},"cmdKeyword",undef);
	return $message unless defined $cmd;
	my @arr=();
	if ($message =~ /^$cmd(.*)/) {
		$cmd=$1;
		Log3 $hash->{NAME}, 5, $hash->{NAME}.": Command received:$cmd";
		my @cc=split(" ",$cmd);
		if ($cc[0] =~ /\d+$/) {
			#This could be a token
			my $token=shift @cc;
			my $restcmd=join(" ",@cc);
			my $ret = gAuth($device,$token);
			if ($ret == 1) {
				Log3 $hash->{NAME}, 5, $hash->{NAME}.": Token valid for sender $sender for $timeout seconds";
				$hash->{helper}{auth}{$sender}=1;
				#Remove potential old timer so countdown start from scratch
				RemoveInternalTimer("$hash->{NAME} $sender");
				InternalTimer(gettimeofday() + $timeout, 'SignalBot_authTimeout', "$hash->{NAME} $sender", 0);
				Signalbot_sendMessage($hash,$sender,"","You have control for ".$timeout."s");
				$cmd=$restcmd;
			} else {
				Log3 $hash->{NAME}, 3, $hash->{NAME}.": Invalid token for sender $sender";
				$hash->{helper}{auth}{$sender}=0;
				Signalbot_sendMessage($hash,$sender,"","Invalid token");
				return $cmd;
			}
		}
		return $cmd if $cmd eq "";
		if ($hash->{helper}{auth}{$sender}==1) {
			Log3 $hash->{NAME}, 4, $hash->{NAME}.": $sender executes command $cmd";
			my $error = AnalyzeCommand($hash, $cmd);
			if (defined $error) {
				Signalbot_sendMessage($hash,$sender,"",$error);
			} else {
				Signalbot_sendMessage($hash,$sender,"","Done");
			}
		} else {
			Signalbot_sendMessage($hash,$sender,"","You are not authorized to execute commands");
		}
		return $cmd;
	}
   return $message;
}

#Reset auth after timeout
sub SignalBot_authTimeout($@) {
	my ($val)=@_;
	my ($name,$sender)=split(" ",$val);
	my $hash = $defs{$name};
	$hash->{helper}{auth}{$sender}=0;
}

sub Signalbot_MessageReceived ($@) {
	my ($hash,$timestamp,$source,$groupID,$message,$attachments) = @_;

	Log3 $hash->{NAME}, 5, $hash->{NAME}.": Message Callback";

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
		Log3 $hash->{NAME}, 3, $hash->{NAME}.":Issue with resolving contact $source\n";
		$sender=$source;
	}
	
	my $join=AttrVal($hash->{NAME},"autoJoin","no");
	if ($join eq "yes") {
		if ($message =~ /^https:\/\/signal.group\//) {
			return Signalbot_join($hash,$message);
		}
	}
	
	my $senderRegex = quotemeta($sender);
	#Also check the untranslated sender names in case these were used in allowedPeer instead of the real names
	my $sourceRegex = quotemeta($source);
	my $groupIdRegex = quotemeta($group);
	my $allowedPeer = AttrVal($hash->{NAME},"allowedPeer",undef);
	
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

		$message=Signalbot_command($hash,$source,$message);
		$message=encode_utf8($message);
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
			Log3 $hash->{NAME}, 5, $hash->{NAME}.": Message matches BabbleExclude, skipping BabbleCall";
			return;
		}
		
		#Just pick one sender in den Priority: group, named contact, number, babblePeer
		my $replyPeer=undef;
		$replyPeer=$sourceRegex if (defined $sourceRegex and $sourceRegex ne "");
		$replyPeer=$senderRegex if (defined $senderRegex and $senderRegex ne "");
		$replyPeer="#".$groupIdRegex if (defined $groupIdRegex and $groupIdRegex ne "");
		
		#Activate Babble integration, only if sender or sender group is in babblePeer 
		if (defined $bDevice && defined $bPeer && defined $replyPeer) {
			if ($bPeer =~ /^.*$senderRegex.*$/ || $bPeer =~ /^.*$sourceRegex.*$/ || ($groupIdRegex ne "" && $bPeer =~ /^.*$groupIdRegex.*$/)) {
				Log3 $hash->{NAME}, 4, $hash->{NAME}.": Calling Babble for $message ($replyPeer)";
				if ($defs{$bDevice} && $defs{$bDevice}->{TYPE} eq "Babble") {
					my $rep=Babble_DoIt($bDevice,$message,$replyPeer);
				} else {
					Log3 $hash->{NAME}, 2, $hash->{NAME}.": Wrong Babble Device $bDevice";
				}
			}
		}
		Log3 $hash->{NAME}, 4, $hash->{NAME}.": Message from $sender : $message processed";
	} else {
		Log3 $hash->{NAME}, 4, $hash->{NAME}.": Message from $sender : $message ignored due to allowedPeer";
	}
}

sub Signalbot_ReceiptReceived {
	my ($hash, $timestamp, $source) = @_;
	Log3 $hash->{NAME}, 5, $hash->{NAME}.": Signalbot_receive_callback $timestamp $source ";
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
		Log3 $hash->{NAME}, 3, $hash->{NAME}.":Issue with resolving contact $source\n";
		$sender=$source;
	}
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "sentMsgRecipient", $sender);
	readingsBulkUpdate($hash, 'sentMsgTimestamp', strftime("%d-%m-%Y %H:%M:%S", localtime($timestamp/1000)));
	readingsEndUpdate($hash, 0);
}

sub Signalbot_SyncMessageReceived {
	my ($hash,$timestamp, $source, $string1, $array1, $string2, $array2) = @_;
	Log3 $hash->{NAME}, 5, $hash->{NAME}."Signalbot: Signalbot_sync_callback $timestamp $source";
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
		return "Error setting up DBUS - is Protocol::Dbus installed?";
	}
	$hash->{helper}{dbus}=$dbus;
	$dbus->initialize();
	#Second instance for syncronous calls
	my $dbus2 = Protocol::DBus::Client::system();
	if (!defined $dbus2) {
		Log3 $name, 3, $hash->{NAME}.": Error while initializing Dbus";
		$hash->{helper}{dbuss}=undef;
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
		$hash->{helper}{version}=0; #prevent uninitalized value in case of service not present
		return "Error calling version";
	}
	
	my @ver=split('\.',$version);
	#to be on the safe side allow 2 digits for lowest version number, so 0.8.0 results to 800
	$hash->{helper}{version}=$ver[0]*1000+$ver[1]*100+$ver[2];
	$hash->{VERSION}="Signalbot:".$Signalbot_VERSION." signal-cli:".$version." Protocol::DBus:".$Protocol::DBus::VERSION;
	if($hash->{helper}{version}>800) {
		my $state=Signalbot_CallS($hash,"isRegistered");
		#Signal-cli 0.9.0 : isRegistered not existing and will return undef when in multi-mode (or false with my PR)
		if (!defined $state) {$state=0;}
		if ($state) {
			#if running daemon is running in -u mode set the signal path to default regardless of the registered number
			$hash->{helper}{signalpath}='/org/asamk/Signal';
			$account=Signalbot_CallS($hash,"getSelfNumber"); #Available from signal-cli 0.9.1
			#Workaround since signal-cli 0.9.0 did not include by getSelfNumber() method - delete the reading, so its not confusing
			if (!defined $account) { readingsDelete($hash,"account"); }
			#Remove all entries that are only available in registration or multi mode
			delete($gets{accounts});
			delete($sets{signalAccount});
			delete($sets{register});
			delete($sets{captcha});
			delete($sets{verify});
			delete($sets{link});
			$hash->{helper}{accounts}=0;
			$hash->{helper}{multi}=0;
		} else {
			#else get accounts and add all numbers to the pulldown
			my $num=Signalbot_CallS($hash,"listAccounts");
			return "Error in listAccounts" if !defined $num;
			my @numlist=@$num;
			my $ret="";
			foreach my $number (@numlist) {
				if ($ret ne "") {$ret.=",";}
				$ret .= $number =~ s/\/org\/asamk\/Signal\/_/+/rg;
			}
			$sets{signalAccount}=$ret eq ""?"none":$ret;
			#Only one number existing - choose automatically if not already set)
			if(@numlist == 1 && $account eq "none") {
				Signalbot_setAccount($hash,$ret);
				$account=$ret;
			}
			$hash->{helper}{accounts}=(@numlist);
			$hash->{helper}{multi}=1;
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

		#-u Mode or already registered
		if ($state || $account ne "none") {
			Signalbot_Call($hash,"listNumbers");
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
			readingsEndUpdate($hash, 1);
			return undef;
		}
	} else {
		#These require 0.8.1 or greater
		delete ($gets{contacts});
		delete ($gets{groups});
		delete ($sets{updateProfile});
		delete ($sets{quitGroup});
		delete ($sets{joinGroup});
	}
}

#Async Callback after updating Groups (change/invite/join)
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

# Dbus syncronous (request->reply) Call
sub Signalbot_CallS($@) {
	my ($hash,$function,@args) = @_;
	my $dbus=$hash->{helper}{dbuss};
	if (!defined $dbus) {
		readingsSingleUpdate($hash, 'lastError', "Error: Dbus not initialized",1);
		return undef;
	}
	Log3 $hash->{NAME}, 5, $hash->{NAME}.": Sync Dbus Call: $function Args:".((@args==0)?"empty":join(",",@args));
	my $sig="";
	my $body="";
	my $path=$hash->{helper}{signalpath};
	my $got_response = 0;
	if (@args>0) {
		$sig=$signatures{$function};
		$body=\@args;
	}
	#Call base service (registration mode)
	if (exists $regsig{$function}) {
		$sig=$regsig{$function};
		$path='/org/asamk/Signal';
	}
	#print $path."\nf:".$function."\nb:".Dumper($body)."\ns:".$sig."\n";
	$dbus->send_call(
		path => $path,
		interface => 'org.asamk.Signal',
		signature => $sig,
		body => $body,
		destination => 'org.asamk.Signal',
		member => $function,
	) ->then( sub {
		$got_response = 1;
		} 
	) -> catch ( sub () {
		Log3 $hash->{NAME}, 4, $hash->{NAME}.": Sync Error for: $function";
		my $msg = shift;
		if (!defined $msg) {
			readingsSingleUpdate($hash, 'lastError', "Fatal Error in $function: empty message",1);
			return;
		}
		my $sig = $msg->get_header('SIGNATURE');
		if (!defined $sig) {
			readingsSingleUpdate($hash, 'lastError', "Error in $function: message without signature",1);
			return;
		}
		$got_response = -1;
		}
	);

	my $counter=5;
	while ($counter>0) {
		my $msg=$dbus->get_message();
		my $sig = $msg->get_header('SIGNATURE');
		if (!defined $sig) {
			#Empty signature is probably a reply from a function without return data, return 0 to differ to error case
			return 0;
		}
		my $b=$msg->get_body()->[0];
		if ($got_response==-1) {
			#Error Case
			readingsSingleUpdate($hash, 'lastError', "Error in $function:".$b,1);
			return undef;
		}
		if ($got_response==1) {
			return $b
		}
		$counter--;
	}
}

# Generic Dbus Call method
#e.g.:
# $hash, "sendMessage", ("Message",\@att,\@rec)
sub Signalbot_Call($@) {
	my ($hash,$function,@args) = @_;
	my $dbus=$hash->{helper}{dbus};
	if (!defined $dbus) {
		readingsSingleUpdate($hash, 'lastError', "Error: Dbus not initialized",1);
		return undef;
	}
	Log3 $hash->{NAME}, 5, $hash->{NAME}.": ASync Dbus Call: $function Args:".((@args==0)?"empty":join(",",@args));
	my $sig="";
	my $body="";
	my $path=$hash->{helper}{signalpath};
	if (@args>0) {
		$sig=$signatures{$function};
		$body=\@args;
	}
	#Call base service (registration mode)
	if (exists $regsig{$function}) {
		$sig=$regsig{$function};
		$path='/org/asamk/Signal';
	}
	$dbus->send_call(
		path => $path,
		interface => 'org.asamk.Signal',
		signature => $sig,
		body => $body,
		destination => 'org.asamk.Signal',
		member => $function,
	) ->then ( sub () {
		my $msg = shift;
		my $sig = $msg->get_header('SIGNATURE');
		if (!defined $sig) {
			#Empty signature is probably a reply from a function without return data, nothing to do
			return undef;
		}
		my $b=$msg->get_body();
		my 	@body=@$b;
		Log3 $hash->{NAME}, 5, $hash->{NAME}.": ASync Calling: $function Args:".join(",",@body);
		CallFn($hash->{NAME},$function,$hash,@body);
		}
	) -> catch ( sub () {
		Log3 $hash->{NAME}, 4, $hash->{NAME}.": ASync Error for: $function";
		my $msg = shift;
		if (!defined $msg) {
			readingsSingleUpdate($hash, 'lastError', "Fatal Error in $function: empty message",1);
			return;
		}
		my $sig = $msg->get_header('SIGNATURE');
		if (!defined $sig) {
			readingsSingleUpdate($hash, 'lastError', "Error in $function: message without signature",1);
			return;
		}
		#Handle Error here and mark Serial for mainloop to ignore
		my $b=$msg->get_body()->[0];
		readingsSingleUpdate($hash, 'lastError', "Error in $function:".$b,1);
		return;
		}
	);
	return undef;
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
				if ($callback eq "MessageReceived" || $callback eq "ReceiptReceived" || $callback eq "SyncMessageReceived") {
					my $func="Signalbot_$callback";
					Log3 $hash->{NAME}, 5, $hash->{NAME}.": Sync Callback: $callback Args:".join(",",@body);
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
	while (my $next = shift @args) {
		if ($next =~ /^#(.*)/) {
			$rename=$1;
		}
		if ($next =~ /^\&(.*)/) {
			$avatar=$1;
		}
	}
	if (defined $avatar) {
		return "Can't find file $avatar" unless ( -e $avatar);
		Log3 $hash->{NAME}, 4, $hash->{NAME}.": updateGroup Avatar $avatar";
		my $size = -s $avatar;
		return "Please reduce the size of your group picture to <2MB" if ($size>2000000);
	}
	my @groupID=Signalbot_getGroup($hash,$groupname);
	#Rename case: Group has to exist
	if (defined $rename) {
		if (@groupID==1) {
			return "Group $groupname does not exist";
		} else {
			Log3 $hash->{NAME}, 4, $hash->{NAME}.": renameGroup $groupname to $rename";
			$groupname=$rename;
		}
	}
	#Create case (no rename and no avatar): Group cannot exist
	if (!defined $rename && !defined $avatar) {
		return "Group $groupname already exists" if @groupID>1;
		Log3 $hash->{NAME}, 4, $hash->{NAME}.": createGroup $groupname";
	}
	if (@groupID==1) { @groupID=();	}
	if (!defined $avatar) { $avatar=""; }
	my @members=(); #only set for invite
	Signalbot_Call($hash,"updateGroup",\@groupID,$groupname,\@members,$avatar);
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
		Log3 $hash->{NAME}, 4, $hash->{NAME}.": updateProfile Avatar $avatar";
		my $size = -s $avatar;
		return "Please reduce the size of your group picture to <2MB" if ($size>2000000);
	} else { $avatar=""; }
	#new name, about, emoji, avatar, removeAvatar
	Signalbot_Call($hash,"updateProfile",$newname,"","",$avatar,0);
}

sub Signalbot_join($@) {
	my ( $hash,$grouplink) = @_;
	my $version = $hash->{helper}{version};
	if ($version<=800) {
		return "Joining groups requires signal-cli 0.8.1 or higher";
	}
	Signalbot_Call($hash,"joinGroup",$grouplink);
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
	
	Log3 $hash->{NAME}, 4, $hash->{NAME}.": Invited ".join(",",@members)." to $groupname";
	Signalbot_Call($hash,"updateGroup",\@group,"",\@members,"");
	return;
}

sub Signalbot_setBlocked($@) {
	my ( $hash,$name,$blocked) = @_;
	if ($name =~ /^#(.*)/) {
		my @group=Signalbot_getGroup($hash,$1);
		return join(" ",@group) unless @group>1;
		Log3 $hash->{NAME}, 4, $hash->{NAME}.": ".($blocked==0?"Un":"")."blocked $name";
		Signalbot_Call($hash,"setGroupBlocked",\@group,$blocked);
	} else {
		my $number=Signalbot_translateContact($hash,$name);
		return "Unknown Contact" unless defined $number;
		Log3 $hash->{NAME}, 4, $hash->{NAME}.": ".($blocked==0?"Un":"")."blocked $name ($number)";
		my $ret=Signalbot_Call($hash,"setContactBlocked",$number,$blocked);
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

	Signalbot_Call($hash,"setContactName",$number,$name);
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
		my $groupid = join(" ",@group);
		$hash->{helper}{groups}{$groupid}{name}=$groupname;	
		Log3 $hash->{NAME}, 5, "found group ".$groupname; 
		if($hash->{helper}{version}>800) {
			my $active = Signalbot_CallS($hash,"isMember",\@group);
			$hash->{helper}{groups}{$groupid}{active}=$active;
			my $blocked = Signalbot_CallS($hash,"isGroupBlocked",\@group);
			$hash->{helper}{groups}{$groupid}{blocked}=$blocked;
			if ($blocked==1) {
				$groupname="(".$groupname.")";
			}
			if ($active==1) {
				push @grouplist,$groupname;
			}
		}
	}
	readingsSingleUpdate($hash, 'joinedGroups', join(",",@grouplist),1);
	return undef;
}

sub Signalbot_sendMessage($@) {
	my ( $hash,$rec,$att,$mes ) = @_;
	Log3 $hash->{NAME}, 4, $hash->{NAME}.": sendMessage called for $rec:$att:".encode_utf8($mes); 

	my @recorg= split(/,/,$rec);
	my @attach=split(/,/,$att);
	my @recipient=();
	foreach (@recorg) {
		my $trans=Signalbot_translateContact($hash,$_);
		return "Unknown recipient ".$_ unless defined $trans;
		push @recipient, $trans;
	}
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "sentMsg", encode_utf8($mes));
	readingsBulkUpdate($hash, 'sentMsgTimestamp', "pending");
	readingsEndUpdate($hash, 0);
	Signalbot_Call($hash,"sendMessage",$mes,\@attach,\@recipient); 
}

#get the identifies (list of hex codes) for a group based on the name
#Check error with int(@)=1
sub Signalbot_getGroup($@) {
	my ($hash,$rec) = @_;
	Log3 $hash->{NAME}, 5, $hash->{NAME}.": getGroup $rec";
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
	Log3 $hash->{NAME}, 4, $hash->{NAME}.": sendGroupMessage called for $rec:$att:$mes"; 

	$rec=~s/#//g;
	my @recipient= split(/,/,$rec);
	if (@recipient>1) { return "Can only send to one group at once";}
	my @attach=split(/,/,$att);
	my @arr=Signalbot_getGroup($hash,$rec);
	return join(" ",@arr) unless @arr>1;

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "sentMsg", encode_utf8($mes));
	readingsBulkUpdate($hash, 'sentMsgTimestamp', "pending");
	readingsEndUpdate($hash, 0);

	Signalbot_Call($hash,"sendGroupMessage",$mes,\@attach,\@arr); 
}

################################### 
sub Signalbot_Attr(@) {					#
	my ($command, $name, $attr, $val) = @_;
	my $hash = $defs{$name};
	my $msg = undef;
	return if !defined $val; #nothing to do when deleting an attribute
	Log3 $hash->{NAME}, 5, $hash->{NAME}.": Attr $attr=$val"; 
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
	} elsif($attr eq "authTimeout") {
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
	return "Not a GoogleAuth device $val" unless $bhash->{TYPE} eq "GoogleAuth";
	return undef;
	} elsif($attr eq "cmdKeyword") {
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
		Log3 $hash->{NAME}, 5, $hash->{NAME}." Using number $val";
	} else {
		$hash->{helper}{signalpath}='/org/asamk/Signal';
		Log3 $hash->{NAME}, 5, $hash->{NAME}." Setting number to default";
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

sub Signalbot_setAccount($$) {
	my ($hash,$account) = @_;
	$account = Signalbot_checkNumber($account);
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
	$msg .= '@="powershell.exe Start-Process -FilePath ( $(\'http://';
	$msg .= $ip;
	$msg .= ':8083/fhem?cmd=set%%20'.$hash->{NAME}.'%%20captcha%%20\'+($(\'%1\')';
	#Captcha has an extra "\" at the end which makes replacing with CSRF a bit more complicated
	if ($FW_CSRF ne "") {
		$msg.= '+$(\''.$FW_CSRF.'\')';
		$msg .= ' -replace \'^(.*)/&\',\'$1&\') ) )"'."\n";
	} else {
		$msg .= ' -replace \'^(.*)/$\',\'$1\') ) )"'."\n";
	}
	if(!open($fh, ">", $tmpfilename,)) {
		Log3 $hash->{NAME}, 3, $hash->{NAME}.": Can't write $tmpfilename";
	} else {
		print $fh $msg;
		close($fh);
	}
	#2. For Linux/X11
	$tmpfilename="www/signal/signalcaptcha.desktop";
	$msg  = "[Desktop Entry]\n";
	$msg .= "Name=Signalcaptcha\n";
	$msg .= 'Exec=xdg-open http://'.$ip.':8083/fhem?cmd=set%%20'.$hash->{NAME}.'%%20captcha%%20%u'.$FW_CSRF."\n";
	$msg .= "Type=Application\n";
	$msg .= "Terminal=false\n";
	$msg .= "StartupNotify=false\n";
	$msg .= "MimeType=x-scheme-handler/signalcaptcha\n";
	if(!open($fh, ">", $tmpfilename,)) {
		Log3 $hash->{NAME}, 3, $hash->{NAME}.": Can't write $tmpfilename";
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
	Log3 $hash->{NAME}, 1, $hash->{NAME}." Define: $def";
	
	$hash->{NOTIFYDEV} = "global";
		if ($init_done) {
			Log3 $hash->{NAME}, 1, "Define init_done: $def";
			my $ret=Signalbot_Init( $hash, $def );
			return $ret if $ret;
	}
	return undef;
}
################################### 
sub Signalbot_Init($$) {				#
	my ( $hash, $args ) = @_;
	Log3 $hash->{NAME}, 5, $hash->{NAME}.": Init: $args";
	if (defined $DBus_missing) {
		$hash->{STATE} ="Please make sure that Protocol::DBus is installed, e.g. by 'sudo cpan install Protocol::DBus'";
		Log3 $hash->{NAME}, 1, $hash->{NAME}.": Init: $hash->{STATE}";
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
	my $ret = Signalbot_setPath($hash,$account);
	$hash->{STATE} = $ret if defined $ret;
	return $ret if defined $ret;
	return;
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
	$multi=0 if !defined $multi;
	if($hash->{helper}{version}<900) {
		$ret .= "<b>signal-cli v0.9.0+ required.</b><br>Please use installer to install or update<br>";
		$ret .= "Note: The installer only supports Debian based Linux distributions like Ubuntu and Raspberry OS<br>";
		$ret .= "      and X86 or armv7l CPUs<br>";
	}
	if($hash->{helper}{version}==901) {
		$ret .= "<b>Warning: signal-cli v0.9.1 has issues affecting Signalbot.</b><br>Please use installer to downgrade to 0.9.0<br>";
	}
	if ($multi==0) {
		$ret .= "Signal-cli is running in single-mode, please consider starting it without -u parameter (e.g. by re-running the installer)<br>";
	}
	if($hash->{helper}{version}<900 || $multi==0) {
		$ret .= 'You can download the installer <a href="www/signal/signal_install.sh" download>here</a> or your www/signal directory and run it with<br><b>sudo ./signal_install.sh</b><br><br>';
		$ret .= "Alternatively go to <a href=https://svn.fhem.de/fhem/trunk/fhem/thirdparty/signal-cli-packages>FHEM SVN thirdparty</a> and download the matching Debian package<br>";
		$ret .= "Install with e.g. <b>sudo apt install ./signal-cli-dbus_0.9.0-1_buster_armhf.deb</b> (./ is important to tell apt this is a file)<br><br>";
	}
	return $ret if ($hash->{helper}{version}<900);
	
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
		$ret .= "Visit <a href=https://signalcaptchas.org/registration/generate.html>Signal Messenger Captcha Page<\/a> and complete the potential Captcha (often you will see an empty page which means you already passed just by visiting the page).<br><br>";
		if ($FW_userAgent =~ /\(Windows/) {
		$ret .= "If you applied the Windows registry hack, confirm opening Windows PowerShell and the rest will run automatically.<br><br>"
		}
		$ret .="If you're not using an automation option, you will then have to copy&paste the Captcha string that looks something like:<br><br>";
		$ret .="<i>signalcaptcha://03AGdBq24NskB_KwAsS9kSY0PzRp4vKx01PZ8nGsfaTV2x548zaUy3aMqedsj..........</i><br><br>";
		$ret .="To do this you typically need to open the Developer Tools (F12) and reload the Captcha.<br><br>";
		if ($FW_userAgent =~ /Chrome/ ) {
		$ret .="You seem to use a Chrome compatible browser. Now find the 'Network' tab, then the line with the Status=(canceled)<br>";
		$ret .="If you move over the Name column you will see that it actually starts with signalcaptcha://<br>";
		$ret .="Right click and chose Copy->Link Adress<br>";
		$ret .="Return here and use <b>set captcha</b> to paste it and continue registration.<br><br>";
		$ret .='<img src="https://svn.fhem.de/fhem/trunk/fhem/contrib/signal/chrome-x11-snapshot.png"><br>';
		}
		if ($FW_userAgent =~ /Firefox/ ) {
		$ret .="You seem to use Firefox. Here find the 'Console' tab. You should see a 'prevented navigation' entry.<br>";
		$ret .="Copy&Paste the signalcaptcha:// string (between quotes).<br>";
		$ret .="Return here and use <b>set captcha</b> to paste it and continue registration.<br><br>";
		$ret .='<img src="https://svn.fhem.de/fhem/trunk/fhem/contrib/signal/firefox-x11-snapshot.png"><br>';
		}
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
		$ret .= "</table>";
	}
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
	$hash->{STATE}="Disconnected";
	return undef;
}

#Any part of the message can contain FHEM or {perl} commands that get executed here
#This is marked by being in (brackets) - returned is the result (without brackets)
#If its a media stream, a file is being created and the temporary filename (delete later!) is returned
#Question: more complex commands could contain spaces but that will require more complex parsing

sub SignalBot_replaceCommands(@) {
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
				Log3 $hash->{NAME}, 3, $hash->{NAME}.": parse cmd failed on ReplaceSetmagic with :$err: on  :$string:";
			} else {
				$msg = join(" ", @newargs);
				Log3 $hash->{NAME}, 5, $hash->{NAME}.": parse cmd returned :$msg:";
			}
			$msg = AnalyzeCommandChain( $hash, $msg );
			#If a normal FHEM command (no return value) is executed, $msg is undef - just the to empty string then
			if (!defined $msg) { 
				$msg=""; 
				Log3 $hash->{NAME}, 5, $hash->{NAME}.": commands executed without return value";
			}
			#Only way to distinguish a real error with the return stream
			if ($msg =~ /^Unknown command/) { 
				Log3 $hash->{NAME}, 3, $hash->{NAME}.": Error message: ".$msg;
				return ($msg, @processed); 
			}
			
			my ( $isMediaStream, $type ) = SignalBot_IdentifyStream( $hash, $msg ) if ( defined( $msg ) );
			if ($isMediaStream<0) {
				Log3 $hash->{NAME}, 5, $hash->{NAME}.": Media stream found $isMediaStream $type";
				my $tmpfilename="/tmp/signalbot".gettimeofday().".".$type;
				my $fh;
				#tempfile() would be the better way, but is not readable by signal-cli (how to set world-readable?)
				#could be changed with "chmod 0666, $tmpfilename;" which should even work on Windows, but what's the point - dbus/signal-cli works on Linux only anyways
				#my ($fh, $tmpfilename) = tempfile();
				if(!open($fh, ">", $tmpfilename,)) {
				#if (!defined $fh) {
					Log3 $hash->{NAME}, 3, $hash->{NAME}.": Can't write $tmpfilename";
					#return undef since this is a fatal error 
					return ("Can't write $tmpfilename",@processed);
				}
				print $fh $msg;
				close($fh);
				#If we created a file return the filename instead
				push @processed, $tmpfilename;
			} else {
				Log3 $hash->{NAME}, 5, $hash->{NAME}.": normal text found:$msg";
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


######################################
#  Get a string and identify possible media streams
#  Copied from Telegrambot
#  PNG is tested
#  returns 
#   -1 for image
#   -2 for Audio
#   -3 for other media
# and extension without dot as 2nd list element

sub SignalBot_IdentifyStream($$) {
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
		<br>
		<a id="Signalbot-setignore"></a>
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
			</ul>
			<br>
		<li><b>set contact &ltnumber&gt &ltname&gt</b><br>
		<a id="Signalbot-set-contact"></a>
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
		<li><b>set quitGroup &ltgroup link&gt</b><br>
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
		<li><b>set verify &ltverifcation code&gt</b><br>
		<a id="Signalbot-set-verify"></a>
		Last step in the registration process. Use this command to provide the verifcation code you got via SMS or voice call.<br>
		If this step is finished successfully, Signalbot is ready to be used.<br>
		</li>
		<li><b>set link</b><br>
		<a id="Signalbot-set-link"></a>
		Alternative to registration: Link your Signal Messenger used with your smartphone to FHEM. A qr-code will be displayed that you can scan with your phone under settings->linked devices.<br>
		Note: This is not the preferred method, since FHEM will receive all the messages you get on your phone which can cause unexpected results.<br>
		</li>
		<li><b>set reinit</b><br>
		<a id="Signalbot-set-reinit"></a>
		Re-Initialize the module. For testing purposes when module stops receiving, has other issues or has been updated. Should not be necessary.<br>
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
			Lists all accounts (phone numbers) registered on this computer. Only available when not attached to an account (account=none).
			Use register or link to create new accounts.<br>
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
			Default: -, valid values: decimal number<br>
		</li>
		<li><b>authDev</b><br>
		<a id="Signalbot-attr-authDev"></a>
			Name of GoogleAuth device. Will normally be automatically filled when setting an authTimeout if a GoogleAuth device is already existing.<br>
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
			Comma separated list of recipient(s) and/or groupId(s) that will trigger that messages are forwarded to a Babble module defined by "BabbleDev". This can be used to interpret real language interpretation of messages as a chatbot or to trigger FHEM events.<br>
			<b>If the attribute is not defined, nothing is sent to Babble</b>
		</li>
		<li><b>babbleDev</b><br>
		<a id="Signalbot-attr-babbleDev"></a>
			Name of Babble Device to be used. This will typically be automatically filled when bubblePeer is set.<br>
			<b>If the attribute is not defined, nothing is sent to Babble</b>
		</li>
		<li><b>commandKeyword</b><br>
		<a id="Signalbot-attr-commandKeyword"></a>
			One or more characters that mark a message as GoogleAuth protected command which is directly forwarded to FHEM for processing. Example: for "="<br>
			=123456 set lamp off<br>
			where "123456" is a GoogleAuth token. The command after the token is optional. After the authentification the user stay for "authTimeout" seconds authentificated and can execute command without token (e.g. "=set lamp on").<br>
			<b>If the attribute is not defined, no commands can be issued</b>
		</li>
		<li><b>defaultPeer</b><br>
		<a id="Signalbot-attr-defaultPeer"></a>
			If <b>send</b> is used without a recipient, the message will send to this account or group(with #)<br>
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
