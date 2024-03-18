##############################################
# $Id$
package FHEM::FHEMAPP;

use strict;
use warnings;
use HttpUtils;

use MIME::Base64;

use Data::Dumper;

use GPUtils qw(:all);

use File::Temp qw(tempfile tempdir cleanup);
use File::Path qw(rmtree);

#$dir = File::Temp->newdir();

#https://www.perl-howto.de/2008/07/temporare-dateien-sicher-erzeugen.html
#https://metacpan.org/release/TJENNESS/File-Temp-0.22/view/Temp.pm#OBJECT-ORIENTED_INTERFACE

#########################################################################
# Importing/Exporting Functions and variables from/to main
#########################################################################
BEGIN {
	GP_Import(qw(
		defs
		data
		AttrVal
		ReadingsVal
		InternalVal
		Log3
		fhem
		readingFnAttributes
		readingsSingleUpdate
		readingsBeginUpdate
		readingsBulkUpdateIfChanged
		readingsBulkUpdate
		readingsEndUpdate
		readingsDelete
		init_done
		FW_CSRF
		FW_confdir
		FW_dir
		FW_ME
		CommandAttr
		CommandDeleteAttr
		devspec2array
		getAllSets
		getAllAttr
		IsIgnored
		unicodeEncoding
		WriteStatefile
		HttpUtils_NonblockingGet
		getAllAttr
		FileWrite
		FileRead
		FileDelete
		gettimeofday
		InternalTimer
		RemoveInternalTimer
		IsDisabled
		deviceEvents
	));
	
	#Exporting Initialize for Main
	GP_Export(qw(
		Initialize
	))
}

#########################################################################
# Trying to import functions from an applicaple JSON-Library
#########################################################################
	my $JSON="none";
	#JSON-Library-Usage was cpopied from Weather-APIs
	# try to use JSON::MaybeXS wrapper
	# for chance of better performance + open code
	eval {
		require JSON::MaybeXS;
		import JSON::MaybeXS qw( decode_json encode_json );
		$JSON='JSON::MaybeXS';
		1;
	} or do {

		# try to use JSON wrapper
		#   for chance of better performance
		eval {
			# JSON preference order
			local $ENV{PERL_JSON_BACKEND} =
				'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
				unless ( defined( $ENV{PERL_JSON_BACKEND} ) );

			require JSON;
			import JSON qw( decode_json encode_json );
			$JSON='JSON';
			1;
		} or do {

			# In rare cases, Cpanel::JSON::XS may
			#   be installed but JSON|JSON::MaybeXS not ...
			eval {
					require Cpanel::JSON::XS;
					import Cpanel::JSON::XS qw(decode_json encode_json);
				$JSON='Cpanel::JSON::XS';
					1;
			} or do {

					# In rare cases, JSON::XS may
					#   be installed but JSON not ...
					eval {
						require JSON::XS;
						import JSON::XS qw(decode_json encode_json);
					$JSON='JSON::XS';
						1;
					} or do {

						# Fallback to built-in JSON which SHOULD
						#   be available since 5.014 ...
						eval {
							require JSON::PP;
							import JSON::PP qw(decode_json encode_json);
						$JSON='JSON::PP';
							1;
						} or do {

							# Fallback to JSON::backportPP in really rare cases
							require JSON::backportPP;
							import JSON::backportPP qw(decode_json encode_json);
						$JSON='JSON::backportPP';
							1;
						};
					};
			};
		};
	};

#########################################################################
# Constants and defaults
#########################################################################
	use constant {
		FA_VERSION 					=> '1.1.0',			#Version of this Modul
		FA_VERSION_FILENAME 		=> 'CHANGELOG.md',	#Default Version Filename
		FA_INIT_INTERVAL			=> 60,				#Default Startup Interval
		FA_DEFAULT_INTERVAL		=> 3600,			#Default Interval
		FA_GITHUB_URL 				=> 'https://github.com/jemu75/fhemApp',
		FA_GITHUB_API_BASEURL	=> 'https://api.github.com/repos/jemu75/fhemApp',
		FA_GITHUB_API_OWNER     => 'jemu75',
		FA_GITHUB_API_REPO	   => 'fhemApp',
		FA_GITHUB_API_RELEASES  => 'releases',
		FA_TAR_SUB_FOLDER			=> 'www/fhemapp4',
		FA_VERSION_LOWEST    	=> '4.0.0',
		FA_MOD_TYPE 				=> (split('::',__PACKAGE__))[-1],
		INT_SOURCE_URL				=> 'SOURCE_URL',	#INTERNAL NAME
		INT_CONFIG_FILE			=> 'CONFIG_FILE',	#INTERNAL NAME
		INT_INTERVAL				=> 'INTERVAL',		#INTERNAL NAME
		INT_VERSION					=> 'VERSION',		#INTERNAL NAME
		INT_JSON_LIB				=> '.JSON_LIB',	#INTERNAL NAME
		INT_LOCAL_INST				=> 'LOCAL',			#INTERNAL NAME
		INT_PATH						=> 'PATH',			#INTERNAL NAME
		INT_LINK						=> 'FHEMAPP_UI',  #INTERNAL NAME
		INT_FANAME					=> 'FHEMAPP_NAME' #INTERNAL NAME
	};
	no warnings 'qw';

	my @attrList = qw(
		disable:1,toggle
		interval
		sourceUrl
		updatePath:beta
		exposeConfigFile:1
		linkPath
	);

	# autoUpdate:1 

	use warnings 'qw';



#########################################################################
# FHEM - Module management Functions (xxxFn)
#########################################################################
	#========================================================================
	sub Initialize
	#========================================================================
	{
		my $hash=shift // return;
		
		$hash->{DefFn}     = \&Define;
		$hash->{GetFn}     = \&Get;
		$hash->{SetFn}     = \&Set;
		$hash->{DeleteFn}  = \&Delete;
		$hash->{CopyFn}    = \&DeviceCopied;
		$hash->{RenameFn}  = \&DeviceRenamed;
		$hash->{NotifyFn}  = \&Notify;
		$hash->{AttrFn}    = \&Attr;
		
		$hash->{AttrList} = join(" ", @attrList)." $readingFnAttributes";
	}
	#========================================================================
	sub Attr	# AttrFn
	#========================================================================
	{
		my $cmd= shift // return undef;
		my $name=shift // return undef;
		my $att= shift // return undef;
		my $val= shift;

		my $hash   = $defs{$name};
		
		#set fa interval 59
		Log($name,"AttrFn: $cmd $name $att $val",4);
		if($att eq 'disable') {
			if($val && $val==1) {
				StopLoop($hash);
				readingsSingleUpdate($hash,'state','disabled',1);
				
			}
			elsif ( $cmd eq "del" or !$val ) {
				readingsSingleUpdate($hash,'state','defined',1);
				StartLoop($hash,FA_INIT_INTERVAL,0,1);
			}
		}
		elsif($att eq 'interval') {
			if($cmd eq 'set') {
				$val+=0;
				if($val < FA_INIT_INTERVAL) {
					$val=0;
					#will be disabled if < 60 seconds => set to 0
					return "$att should not be set lower than ".FA_INIT_INTERVAL;
				} 
				elsif($val > 86400) {
					return "$att should not be longer than 1 day (86400 sec)";
				}
				elsif($val==FA_DEFAULT_INTERVAL) {
					return "Default for $att is already $val";
				}
				$hash->{&INT_INTERVAL}=$val;
				StartLoop($hash,FA_INIT_INTERVAL,1);
			}
			else
			{
				$hash->{&INT_INTERVAL}=FA_DEFAULT_INTERVAL;
				StartLoop($hash,FA_INIT_INTERVAL,1);
			}
		}
		elsif($att eq 'sourceUrl') {
			if($cmd eq 'set') {
				if($val eq FA_GITHUB_URL) {
					return "$val is already default for $att";
				}
				$hash->{&INT_SOURCE_URL}=$val;
			}
			else
			{
				$hash->{&INT_SOURCE_URL}=FA_GITHUB_URL;
			}
		}
		elsif($att eq 'exposeConfigFile') {
			my $filespec=get_config_file($name,undef,1);
			if($cmd eq 'set') {
				if($val) {
					if(int($val) != 1) {
						return "$val is not valid for $att";
					}
					Log($name,"$att changed to $val!",4);
					$data{confFiles}{$filespec} = '0';
				} 
			} else {
				Log($name,"$att was deleted!",4);
				delete($data{confFiles}{$filespec});
			}
			
		} elsif($att eq 'linkPath') {
			if($cmd eq "set") {
				set_fhemapp_link($hash,$val);
			} else {
				set_fhemapp_link($hash,'%%DELETE%%');
			}
		}
		return undef;
	}

	
	#========================================================================
	sub Notify	# NofifyFn
	#========================================================================
	{
		my $hash = shift // return;
		my $src_hash=shift // return;


		my $name = $hash->{NAME};
		return if(IsDisabled($name));

		my $src  = $src_hash->{NAME};

		my $events = deviceEvents($src_hash,1);
		return if( !$events );

		#HANDLING GLOBAL EVENTS
		if($src eq 'global') {
			foreach my $event (@{$events}) {
				Log($name,"EVENT: $src:$event",5);
				$event = "" if(!defined($event));
				if($event eq 'INITIALIZED') {
					Log($name,"Event recieved from '$src'",5);
					StartLoop($hash,FA_INIT_INTERVAL);
				}
			} 
		} 
		return;
	}

	#========================================================================
	sub Define	# DefFn
	#========================================================================
	{
		my $hash=shift // return;	

		my $def=shift;
		my @a = split("[ \t][ \t]*", $def);

		my $name=shift @a;
		my $type=shift @a;
		my $fa_name= shift @a;
		
		Log(undef,"DefFn called for $name $init_done",4);
		
		
		#Setting INTERNAL values
		$hash->{&INT_VERSION}=FA_VERSION;
		$hash->{&INT_SOURCE_URL}=AttrVal($name,'sourceUrl',FA_GITHUB_URL);
		$hash->{&INT_JSON_LIB}=$JSON;
		$hash->{&INT_CONFIG_FILE}=get_config_file($name);
		$hash->{&INT_INTERVAL}=AttrVal($name,'interval',FA_DEFAULT_INTERVAL);  
		$hash->{&INT_FANAME}=$fa_name;

		$hash->{NOTIFYDEV}="global";
		
		#Internal PATH is only available if local path is specified in DEF
		if($fa_name eq 'none') {
			delete($hash->{&INT_PATH});
			$hash->{&INT_LOCAL_INST}=0;
		} else {
			$hash->{&INT_PATH}="$FW_dir/$fa_name";
			$hash->{&INT_LOCAL_INST}=1;
		}
		
		set_fhemapp_link($hash);
			
		#Setting defined state
		if(!$init_done) {
			#Reading conifg on Define, e.g. when copied from other device
			#[todo]: this is not necessary on simple define .... Move to CopyFn?
			ReadConfig($hash);
		}
		else 
		{
			#Start Version loop 
			#[todo]: maybe move to global:Initialize handling in NotifyFn
			StartLoop($hash,FA_INIT_INTERVAL);
		}
		
		#Set startup disabled/defined state
		if(IsDisabled($name)) {
			readingsSingleUpdate($hash,'state','disabled',0);   
		}
		else
		{
			readingsSingleUpdate($hash,'state','defined',0); 
		}

		#AddExtension( $name, \&ExtensionGetConfigData, FA_MOD_TYPE . "/$name/cfg" );
	
		
		return "Wrong syntax: use define <name> fhemapp <localFhemappPath|none>" if(!$fa_name);
	}

	#========================================================================
	sub Get		# GetFn
	#========================================================================
	{
		my $hash=shift // return;
		my $name=shift;
		my $opt=shift;
		
		return "\"get $name\" needs at least one argument" unless(defined($opt));

		my $localInst=InternalVal($name,INT_LOCAL_INST,0);			

		if($opt eq 'config') {
			return encode_base64(get_config($hash));
		}
		elsif($opt eq 'rawconfig') {
			return get_config($hash);
		}	
		elsif($opt eq 'options') {
			return AttrOptions_json($name);
		}	
		elsif($opt eq 'version') {
			if($localInst) {
				check_local_version($hash);
				return ReadingsVal($name,'local_version','unknown');
				#return get_local_version($hash);
			} 
			return "not available!";
		}	
		elsif($opt eq 'localfolder') {
			if($localInst) {
				return get_local_path($hash);
			}
			return "not available!"
		}	
		else
		{
			#my $loc_gets='version:noArg';
			my $loc_gets='version:noArg';
			if($localInst) {
				return "Unknown argument $opt, choose one of rawconfig:noArg $loc_gets";
			} else {
				return "Unknown argument $opt, choose one of rawconfig:noArg";		
			}
		}
	}

	#========================================================================
	sub Set		# SetFn
	#========================================================================
	{
		my $hash=shift // return;
		my $name=shift;
		my $opt=shift;
		
		my @args=@_;

		my $localInst=InternalVal($name,INT_LOCAL_INST,0);			
		
		return "\"set $name\" needs at least one argument" unless(defined($opt));

		if($opt eq 'config') {
			set_config($hash,decode_base64(join(" ",@args)),1);
		}
		elsif($opt eq 'rawconfig') {
			set_config($hash,join(" ",@args),1);
		}
		elsif($opt eq 'update') {
			if($localInst) {
				update($hash);
			} else {
				return "$opt not available for " . FA_MOD_TYPE . " without local fhemapp path!";
			}
		}
		elsif($opt eq 'getConfig') {
			return get_config($hash);
		}	
		#elsif($opt eq 'forceVersion') {
			#return forceVersion($hash,@args);
		#}
		elsif($opt eq "checkVersions") {
			if($localInst) {
				check_local_version($hash);
				Request_Releases($hash)
			} else {
				return "$opt not available for " . FA_MOD_TYPE . " without local fhemapp path!";
			}
		}
		elsif($opt eq "createfolder") {
			create_fhemapp_folder($hash);
		}
		elsif($opt eq "refreshLink") {
				set_fhemapp_link($hash);
		}
		elsif($opt eq "rereadCfg") {
			ReadConfig($hash,1);
		}
		else {
			if($localInst) {
				return "Unknown argument $opt, choose one of getConfig:noArg checkVersions:noArg update:noArg rereadCfg:noArg";
			} else {
				return "Unknown argument $opt, choose one of getConfig:noArg rereadCfg:noArg";
			}
		}
		return undef;
	}

	#========================================================================
	sub Delete	# DeleteFn
	#========================================================================
	#Cleanup when device is deleted
	{
		my $hash=shift // return;
		
		#Cancel and delete runnint internal timer
		StopLoop($hash);
		#Delete config file 
		DeleteConfig($hash);	
	}


	#========================================================================
	sub DeviceCopied	#CopyFn
	#========================================================================
	{
		my $old_name=shift // return;
		my $new_name=shift // return;
			
		Log ($new_name,"Copying config '$old_name' -> '$new_name'",4);
		$defs{$new_name}{helper}{config} = $defs{$old_name}{helper}{config};
		#Log($new_name,$new_hash->{helper}{config},5);
		
		WriteConfig($defs{$new_name});
		
		return;
	}

	#========================================================================
	sub DeviceRenamed	#RenameFn
	#========================================================================
	{
		my $new_name=shift // return;
		my $old_name=shift // return;
		
		Log($new_name,"Device renamed '$old_name' -> '$new_name'",4);
		my $new_hash=$defs{$new_name};
		WriteConfig($new_hash);

		my $oldFile=get_config_file($old_name);
		Log($new_name,"Deleting config '$oldFile' ...",4);
		FileDelete($oldFile);
		
		return;

	}


#========================================================================
sub ExtensionGetConfigData
#========================================================================
{
	my ($request) = @_;
	my $TP=FA_MOD_TYPE;
	#Log($TP,"$TP got WebRequest: $request",2);
	if ( $request =~ /^\/$TP\/(\w+)\/cfg/x ) {
		my $name   = $1;
		my $dta=$defs{$name}{helper}{config};
		return ( "application/json", $dta );
		#return ( "text/plain; charset=utf-8",
		#"you've successfully reached a $TP device ($name) for webhook $request in " . __PACKAGE__ );

	}

	return ( "text/plain; charset=utf-8",
		"No $TP device for webhook $request" );


}

#========================================================================
sub AddExtension 
#========================================================================
{
	my ( $name, $func, $link ) = @_;

	my $url = "/$link";
	Log( $name, "Registering " . FA_MOD_TYPE . " $name for URL $url",3 );
	$::data{FWEXT}{$url}{deviceName} = $name;
	$::data{FWEXT}{$url}{FUNC}       = $func;
	$::data{FWEXT}{$url}{LINK}       = $link;

	return;
}
	
#========================================================================
sub RemoveExtension 
#========================================================================
{
	my ($link) = @_;

	my $url  = "/$link";
	my $name = $::data{FWEXT}{$url}{deviceName};
	Log( $name, "Unregistering " . FA_MOD_TYPE . " $name for URL $url",3 );
	delete $::data{FWEXT}{$url};

	return;
}
	

#========================================================================
sub create_fhemapp_folder
#========================================================================
{
	my $hash=shift // return;
	my $name=$hash->{NAME};

	my $localInst=InternalVal($name,INT_LOCAL_INST,0);
	if(!$localInst) {
		Log($name,"create_fhemapp_folder: no local fhemapp-instance!",2);
		return 0;
	}
	my $fld=InternalVal($name,INT_PATH,undef);
	if(!$fld) {
		Log($name,"no path specification found check DEF of $name",2);
		return 0;
	}
	if(-d $fld) {
		Log($name,"create_fhemapp_folder: folder already exists: '$fld'",2);
		return 0;
	}

	mkdir($fld);
	if(-d $fld) {
		Log($name,"create_fhemapp_folder: folder successfully created: '$fld'",4);
		return 1;
	} else {
		Log($name,"create_chemapp_folder: unable to create folder '$fld'",2);
		return 0;
	}

	#my $name=shift // return;	
	#my $destFolder=InternalVal($name,INT_PATH,'none');	
}

#========================================================================
sub forceVersion
#========================================================================
{
	my $hash=shift // return 'no hash';
	my @args=shift // return 'no args';

	my $first=shift @args // return 'empty args';

	my $name=$hash->{NAME};
	my $localPath=get_local_path($hash);

	return "$first - $localPath";

}

#========================================================================
sub update {
#========================================================================

	my $hash=shift // return;

   my $name = $hash->{NAME};

	my $continueUpdate = shift;
	$continueUpdate //=0;
	
	#TODO: Get Releases ... this is a non-blocking (async) process ...
   #      ... need to wait until finished ... non-blocking :(
	if(!$continueUpdate) {
		Log($name,"Update ... first checking versions ...",4);
		check_local_version($hash);
		Request_Releases($hash,1);
		return;
	} else {
		Log($name,"Update ... got releases ... continuing...",4);
	}

	#Find required tarball-URL
	my $url=undef;
	my $updatePath=AttrVal($name,'updatePath','stable');
	if( $updatePath eq 'beta') {
		$url=ReadingsVal($name,'.pre_tarball_url',undef);
	} else {
		$url=ReadingsVal($name,'.stable_tarball_url',undef);
	}
	
	#Build non-blocking request to download tarball from github
	#Donwload is handled in callback sub 'update_response'
	if($url) {
		Log($name,"Requesting: $url",4);
		my $param = {
						url        => $url,
						timeout    => 5,
						hash       => $hash,                                                                                 
						method     => "GET",                                                                                 
						header     => "User-Agent: TeleHeater/2.2.3\r\nAccept: application/json",                            
						callback   => \&update_response                                                                  
					};
		HttpUtils_NonblockingGet($param); 
	} else {
		Log($name, "Update: No url for current update-path '$updatePath' available!",4);
	}
	return;

}

#========================================================================
sub update_response{
#========================================================================
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

	 my $localPath=get_local_path($hash);

	 my $fname="fhemapp_update.tar.gz";
	 Log($name,"request-header: ".$param->{httpheader},5);

	#Extracting the package filename from httpheader
	if($param->{httpheader} =~/filename=(.+.tar.gz)/gm) {
		$fname=$1;
	}
	Log($name,"filename for update package is $fname");
	 #{my $v1="ertuy";;if($v1 =~ /er(tu)y/gm) {$1}}
	 
	 my @hdr=split('\n',$param->{httpheader});
	 Log($name,"http-header:".Dumper(@hdr),5);

   if($err ne "")                                                                                                      
   {
		#An Error occured during request
      Log($name,"error while requesting ".$param->{url}." - $err",4);                                               
      readingsSingleUpdate($hash, ".fullResponse", "ERROR: $err", 0);  		
   }
   elsif($data ne "")                                                                                                  
   {
		#Incoming data ... saving file
      Log($name,"update data recieved ".$param->{url},4);                                               
		my $dir = tempdir(CLEANUP=>1);
		$dir=~ s!/*$!/!;
		my $filename="${dir}$fname";
		my @content;
		push @content,$data;
				
		#FileWrite($filename,@content); #-> Added one, unwanted character (probably a \n)
		#So doing "native" file-write here:
      Log($name,"writing $filename ",4);                                               
		open(FH, '>', $filename);
		print FH $data;
		close(FH);

		#my $topfolder=`tar -tzf $filename' | head -1 | cut -f1 -d"/"`;
		#chomp $topfolder;
		my $tarlist=`tar -tzf $filename`;
		my $topfolder=(split /\n/, $tarlist )[0];
		chop $topfolder if($topfolder =~ /.*\/$/);
		Log($name,"top folder in '$filename' is $topfolder");

		if(!$topfolder) {
			Log($name, "Unable to get top folder from '$filename'",4);
			temp_cleanup($hash);
			return;
		}

		my $fullTarFolder="$topfolder/".FA_TAR_SUB_FOLDER;
		my $depth=scalar(split("/",$fullTarFolder));

		my $lpath=get_local_path($hash);

		my $bpath=undef;
		if($lpath) {
			Log($name,"Local path already exists: '$lpath'",4);
			$bpath="$lpath.bak";

			#TODO: Do not remove --> should introduce a force variant
			if($bpath && -d $bpath) {
			   Log($name,"Trying to remove previously left backup folder '$bpath'",3);
				my $res=rmtree($bpath,0,1);
			}

			Log($name,"-> renaming to '$bpath'",4);
			if(!rename($lpath,$bpath)) {
				Log($name,"Error renaming folder '$lpath' to '$bpath'",2);
				temp_cleanup($hash);
				return;
			}
		}

		if(!$lpath || ! -d $lpath) {
			if(create_fhemapp_folder($hash)) {
				$lpath=get_local_path($hash);
				my $cmd="tar xf $filename -C $lpath $topfolder/". FA_TAR_SUB_FOLDER . " --strip-components $depth";
				Log($name,"extract cmd '$cmd' ",4);                                               

				my $res=system($cmd);
				Log($name,"extract result: $res",4);

			} 
		} else {
			Log($name, "Local path still exists (shouldn't): '$lpath'",2);
			temp_cleanup($hash);
			return;
		}

		#Trying to cleanup temp-folder ...
		temp_cleanup($hash);
		#Updating local version (Readings)

		if($bpath && -d $bpath) {
			Log($name,"Removing backup folder '$bpath' after sucessfull installlation",4);
			my $res=rmtree($bpath,0,1);
		}
		check_local_version($hash);
		check_update_available($hash);

   }
	return;
}	

 #========================================================================
sub temp_cleanup{
#========================================================================
	my $hash=shift // return;
	my $name=$hash->{NAME};

	if(cleanup()==0) {
		Log($name,"Successfully cleaned temp folder",4);
	} else {
		Log($name,"Cleanup of temp folder failed!",2)
	}

}

#========================================================================
sub Request_Releases
#========================================================================
{
    my $hash=shift // return;
    my $name = $hash->{NAME};

	 my $continueUpdate=shift;
	 $continueUpdate //= 0;
	
	
	my $url=AttrVal($name,'sourceUrl',FA_GITHUB_API_BASEURL); 
	$url=~ s!/*$!/!;
	$url.=FA_GITHUB_API_RELEASES;
	
	Log($name,"Requesting: $url",4);
    my $param = {
                    url        => $url,
                    timeout    => 5,
                    hash       => $hash,                                                                                 
                    method     => "GET",                                                                                 
                    header     => "User-Agent: TeleHeater/2.2.3\r\nAccept: application/json",                            
                    callback   => \&Request_Releases_Response,
						  continueUpdate => $continueUpdate                                                                  
                };

    HttpUtils_NonblockingGet($param);                                                                                    
	return;
}

#========================================================================
sub Request_Releases_Response($)
#========================================================================
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
	 
    if($err ne "")                                                                                                      
    {
        Log($name,"error while requesting ".$param->{url}." - $err",5);                                               
        #readingsSingleUpdate($hash, ".fullResponse", "ERROR: $err", 0);  
    }
    elsif($data ne "")                                                                                                  
    {
        Log($name,"url ".$param->{url}." returned: $data",5);                                                         
		#Log3 $name, 3, Dumper $data;
		
		my $rels =  decode_json($data);

		my $latestPre=undef;
		my $latestFull=undef;

		foreach my $rel (@{$rels}){
			Log($name,"Release: " . $rel->{tag_name},5);
			my $isVer=version_compare($rel->{tag_name},FA_VERSION_LOWEST);
			Log($name,"Lowest: " . FA_VERSION_LOWEST . " is: $isVer",5);
			if($isVer < 0) {
				next;
			}
			if( !$latestPre && $rel->{prerelease})  {
				$latestPre=$rel;
			}
			if(!$latestFull && !$rel->{prerelease}) {
				$latestFull=$rel;
			}
		}

		my $updateAvailable=0;
		my $updatePath=AttrVal($name,'updatePath','stable');


		#Updating device readings
		readingsBeginUpdate($hash);
			readingsBulkUpdateIfChanged($hash,'.latest_url',$param->{url},0);

			if($latestPre) {
				Log($name,"Latest-Pre: " . $latestPre->{tag_name},4);
				readingsBulkUpdateIfChanged($hash,'pre_tag_name',$latestPre->{tag_name},1);
				readingsBulkUpdateIfChanged($hash,'pre_html_url',$latestPre->{html_url},1);
				readingsBulkUpdateIfChanged($hash,'.pre_tarball_url',$latestPre->{tarball_url},0);
				readingsBulkUpdateIfChanged($hash,'pre_info',$latestPre->{body},1);
				readingsBulkUpdateIfChanged($hash,'pre_published_at',$latestPre->{published_at},1);
			} else {
				readingsBulkUpdateIfChanged($hash,'pre_tag_name','unknown',1);
			}
			if($latestFull) {
				Log($name,"Latest-Stable: " . $latestFull->{tag_name},4);
				readingsBulkUpdateIfChanged($hash,'stable_tag_name',$latestFull->{tag_name},1);
				readingsBulkUpdateIfChanged($hash,'stable_html_url',$latestFull->{html_url},1);
				readingsBulkUpdateIfChanged($hash,'.stable_tarball_url',$latestFull->{tarball_url},0);
				readingsBulkUpdateIfChanged($hash,'stable_info',$latestFull->{body},1);
				readingsBulkUpdateIfChanged($hash,'stable_published_at',$latestFull->{published_at},1);
			} else {
				readingsBulkUpdateIfChanged($hash,'stable_tag_name','unknown',1);
			}

			#In case of error ....
			#readingsBulkUpdate($hash, ".fullResponse", $data,0); 
			if($err) {
				readingsBulkUpdateIfChanged($hash,'request_result','error',1);
				readingsBulkUpdate($hash,'request_error',$err,1);
			} else {
				readingsBulkUpdateIfChanged($hash,'request_result','success',1);
			}
		readingsEndUpdate($hash,1);

		#Delete un-fillable version information readings 
		if(!$latestPre) {
			readingsDelete($hash,'pre_html_url');
			readingsDelete($hash,'.pre_tarball_url');
			readingsDelete($hash,'pre_info');
			readingsDelete($hash,'pre_published_at');
		}
		if(!$latestFull) {
			readingsDelete($hash,'stable_html_url');
			readingsDelete($hash,'.stable_tarball_url');
			readingsDelete($hash,'stable_info');
			readingsDelete($hash,'stable_published_at');
		}
		if(!$err) {
			readingsDelete($hash,'request_error');
		}
    }

	if($param->{continueUpdate}) {
		#if called during update process ... continue with update
		update($hash,1);
	} else {
		check_update_available($hash);
	}

    
}

#========================================================================
sub check_update_available
#========================================================================
{
	my $hash=shift // return;
	my $name=$hash->{NAME};

	my $path=AttrVal($name,'updatePath','stable');
	my $ver=ReadingsVal($name,'stable_tag_name','unknown');
	$ver=ReadingsVal($name,'pre_tag_name','unknown') if($path eq "beta");

	return if($ver eq 'unknown');

	my $local_ver=ReadingsVal($name,'local_version','unknown');

	if ($local_ver eq 'unknown' || version_compare($ver,$local_ver) ) {
		readingsSingleUpdate($hash,'update_available',1,1);
	} else {
		if(ReadingsVal($name,'update_available',undef) ne '0') {
			readingsSingleUpdate($hash,'update_available','0',1);
		}
	}
}


#========================================================================
sub set_fhemapp_link {
#========================================================================
	my $hash=shift // return;
	my $forceValue=shift;

	my $name=$hash->{NAME};
	#my $fa_name=$hash->{&INT_FANAME};

	my $fw_me=$FW_ME;
	$fw_me //= '/fhem';

	my $fa_name=AttrVal($name,'linkPath',undef);
	$fa_name=$hash->{&INT_FANAME} if($hash->{&INT_LOCAL_INST});

	if($forceValue) {
		if($forceValue ne '%%DELETE%%') {
			$fa_name=$forceValue;
		} else {
			$fa_name=undef;
		}
	}

	if($fa_name) {
		my $link="$fw_me/$fa_name/index.html#/$name";
		$hash->{&INT_LINK}="<html><a href=\"$link\">$link</a></html>";
	} else {
		delete($hash->{&INT_LINK});
	}

	

#	if($hash->{&INT_LOCAL_INST}) {
#		my $link="$fw_me/$fa_name/index.html#/$name";
#		$hash->{&INT_LINK}="<html><a href=\"$link\">$link</a></html>";
#	} else {
#		$fa_name=AttrVal($name,'linkPath',undef);
#		if($fa_name) {
#			$link="$fw_me/$fa_name/index.html#/$name";
#			$hash->{&INT_LINK}="<html><a href=\"$link\">$link</a></html>";
#		} else {
#			delete($hash->{&INT_LINK});
#		}
#	}
}


#========================================================================
sub AttrNames{
#========================================================================
	my $name=shift;
	
	my @atts;
	if (!$name) {
		@atts=@attrList;
	} else {
		@atts=split(' ',getAllAttr($name));
	}
	
	my @rList;
	#foreach (@attrList) {
	foreach (@atts) {
		push @rList,(split(':', $_))[0];
	}
	return @rList;
}

#========================================================================
sub AttrOptions_json
#========================================================================
{
	my $name=shift // return undef;

	my @rOpts;
	foreach my $att (AttrNames($name)) {
		my $val=AttrVal($name,$att,undef);
		push @rOpts, "\"$att\":\"$val\"" if(defined($val));
	}	
	my $jOpts=join(',',@rOpts);
	
	return $jOpts if($jOpts);
	
	return undef;
}

#========================================================================
sub get_config
#========================================================================
{
	my $hash=shift // return;
	
	my $name=$hash->{NAME};
	
	#FHEMApp does not need any Attributes from FHEMAPP-Device,
	#so deactivate appending Attributes
	#(https://forum.fhem.de/index.php?topic=137239.msg1305847#msg1305847)
	
	#my $jOpts=AttrOptions_json($name);	
	my $jOpts=undef;

	my $config=$hash->{helper}{config};
	
	if(!$config) {
		$config=$config=ReadingsVal($name,".config",undef);
		if($config) {
			set_config($hash,$config,1);
			readingsDelete($hash,'.config');
		}
	}
	
	if($config) {
		my $ret;
		if($jOpts) {
		  $jOpts="{$jOpts}";
		  ($ret = $config) =~ s{(.*)\}}{$1,"attributes":$jOpts\}}xms;
		} else {
		  $ret=$config;
		}

		return $ret if($ret);
	
	}
	
	return jsonError("No config found!");
}

#========================================================================
sub set_config
#========================================================================
{
	my $hash=shift // return;
	my $newVal=shift // return;
	my $writeConfig =shift;
	
	$writeConfig //= 0;
	
	my $name=$hash->{NAME};
	
	$hash->{helper}{config}=$newVal;
	
	WriteConfig($hash) if($writeConfig);
	
}

#========================================================================
sub get_config_file
#========================================================================
{
	my $name=shift // return;
	my $getOld=shift;
	my $noPath=shift;

	my $ret="${name}_config.".FA_MOD_TYPE;
	$ret="$ret.json" if(!$getOld);

	$ret="$FW_confdir/$ret" if(!$noPath);

	return lc($ret);

	#if($getOld) {
	#	return lc("$FW_confdir/${name}_config.".FA_MOD_TYPE);
	#} 
	#return lc("$FW_confdir/${name}_config.".FA_MOD_TYPE.".json");	
}

 
#========================================================================
sub WriteConfig
#========================================================================
{
	my $hash=shift // return;
	my $name=$hash->{NAME};
	
	if(InternalVal('global','configfile','x') ne 'configDB') {
		if(! -d $FW_confdir) {
			if(!mkdir($FW_confdir)) {
				Log($name,"Unable to create missing config folder '$FW_confdir'",2);
				Log($name,"Cannot write config!",2);
				return;
			}
		}	
	}
	
	my $config=$hash->{helper}{config};
	
	if($config) {
		my @content;
		push @content,$hash->{helper}{config};

		my $filename=get_config_file($name);
		Log($name,"Writing config '$filename'...",4);
		FileWrite($filename,@content);
		readingsSingleUpdate($hash,'configLastWrite',localtime(),0);
		$hash->{&INT_CONFIG_FILE}=$filename if($hash->{&INT_CONFIG_FILE} ne $filename);
	} else {
		Log($name,"No config to write!",3);
	}
	return;
}
 
#========================================================================
sub ReadConfig
#========================================================================
{
	my $hash=shift // return;
	my $event=shift;
	$event //=0;
	$event=1 if($event ne 0);

	my $name=$hash->{NAME};


	#during first part of beta testing, the config files where stored with a
	#.fhemapp suffix 
	#In fact the files are .json files so they will be saved as .fhemapp.json
	#This conversion is done out of user sight when reading the config file.

	#First try to read a "new" file with .json extension
	my $filename=get_config_file($name);
	my $saveAsNew=undef;
	
	Log($name,"Reading config '$filename' ...",4);
	my ($err,@content)=FileRead($filename);	

	if($err) {
		#Reading failed, then check if a file with .fhemapp extension exists
		Log($name,"Could not read $filename",4);
		Log($name,"Check if an old .fhemapp file exists...",4);
		$err=undef;
		$filename=get_config_file($name,1); 
		Log($name,"Trying to read $filename",5);
		($err,@content)=FileRead($filename);
		if(!$err) {
			#old .fhemapp file successfully read ... need to save later
			Log($name, "Successfully read old formatted '$filename'",4);
			$saveAsNew=1;
		}
	}
	if(!$err) {
		$hash->{helper}{config}=join('',@content);
		readingsSingleUpdate($hash,'configLastRead',localtime(),$event);
		if($saveAsNew) {
			#Old .fhemapp file was loaded, need to save it under new name
			#with .json extension
			Log($name, "Storing under new name with .json extension...",2);
			WriteConfig($hash);
			Log($name, "Deleting old config file '$filename' ...",2);
			#And fianally delete the old config file!
			FileDelete($filename);
		}
	} else {
		#Neither an "old", nor a "new" formatted config file could be read
		#... so most likely it was never written by FHEMAapp
		readingsSingleUpdate($hash,'configLastRead',$err,$event);
		Log($name,"WARNING: No Config found when trying to read config-file!",3);
		Log($name,$err,5);
	}
	
	return;
}
 
#========================================================================
sub DeleteConfig
#========================================================================
{
	my $hash = shift // return;
	my $name =shift;
	$name //= $hash->{NAME};

	my $filename=get_config_file($name);
	Log($name,"Deleting config '$filename' ...",4);
	FileDelete($filename);
	
	return;
}
 

#========================================================================
sub get_local_path
#========================================================================
{
	my $hash=shift // return undef;
	my $append=shift;
	
	my $name=$hash->{NAME};
	my $path=InternalVal($name,INT_PATH,undef);
	
	
	
	if($path) {
		if(-d $path) {
			if($append) {
				$path =~ s!/*$!/!;
				$path .= $append;
			}
			return $path;
		}
	}	
	return undef;
}

#========================================================================
sub get_local_version
#========================================================================
{
	my $hash=shift // return;
	
	
	my $name=$hash->{NAME};
	my $filename=get_local_path($hash,FA_VERSION_FILENAME);
	
	
	
	if($filename) {
		my ($err,@content)=FileRead({FileName => $filename,ForceType => 'file'});
	
		my $config='';
		
		if(FA_VERSION_FILENAME=~/\.json/) {
			#handling vesion.json
			if(!$err) {
				$config=join('',@content);	
			}
			my $data=decode_json($config);
			return $data->{version};		
		} else {
			#handling CHANGELOG.md
			my $vLine=shift @content;
			return (split(' ',$vLine))[-2];
		}
	}
	return undef;
}

#========================================================================
sub check_local_version
#========================================================================
{
	my $hash=shift // return;

	if($hash->{&INT_LOCAL_INST}) {
		readingsBeginUpdate($hash);

		#my $ver=get_local_version($hash);


		#---
		my $filename=get_local_path($hash,FA_VERSION_FILENAME);
		
		my $ver='unknown';
		if($filename) {
			my ($err,@content)=FileRead({FileName => $filename,ForceType => 'file'});
		
			my $config='';
			
			readingsBulkUpdateIfChanged($hash,'.local_version_src',FA_VERSION_FILENAME,1);
			
			if(FA_VERSION_FILENAME=~/\.json/) {
				#handling vesion.json
				if(!$err) {
					$config=join('',@content);	
				}
				my $data=decode_json($config);
				$ver=$data->{version};		
			} else {
				#handling CHANGELOG.md
				my $vLine=shift @content;
				$ver=(split(' ',$vLine))[-2];
			}
		}

			readingsBulkUpdateIfChanged($hash,'local_version',$ver,1);
		
		readingsEndUpdate($hash,1);

	} 
	else 
	{
		readingsDelete($hash,'local_version');		
		readingsDelete($hash,'.local_version_src');		
	}
	return;
}

#========================================================================
sub StartLoop
#========================================================================
{
	my $hash=shift // return;	
	my $time=shift;
	my $stop=shift;
	my $force=shift;
	
	my $name=$hash->{NAME};
	my $localInst=InternalVal($name,INT_LOCAL_INST,0);			
	
	my $currentInterval=AttrVal($name,'interval',FA_DEFAULT_INTERVAL);
	if($currentInterval < FA_DEFAULT_INTERVAL) {
		StopLoop($hash);
		Log($name,"Interval is lower than " . FA_DEFAULT_INTERVAL . " seconds. Stopping all loop activities",5);
		return;
	}

	if(!$localInst) {
		#As the only reason for the loop is to check for new versions, it should be only available for 
		#FHEMAPP-Instances with local installations
		Log($name,"No local Installation - no need to check for new versions periodically",5);
		StopLoop($hash);
		return;
	}

	if(!IsDisabled($name) or $force) {
		$stop //= 1;
		$time //= 0;
		$time = AttrVal($name,'interval',FA_DEFAULT_INTERVAL) if(!(0+$time));
		StopLoop($hash) if($stop);
		Log($name,"Starting internal timer loop ($time sec.)",5);
		my $nextTimer=gettimeofday()+$time;
		InternalTimer($nextTimer,\&Loop,$hash);
		readingsSingleUpdate($hash,'next_cycle',localtime($nextTimer),0);
	}
	
	return;
}

#========================================================================
 sub Loop
#========================================================================
{
	my $hash = shift // return;

	my $name = $hash->{NAME};
	Log($name,"Internal timer loop elapsed",5);
	
	check_local_version($hash);
	Request_Releases($hash);
	
	StartLoop($hash);
	
	return;
}

#========================================================================
sub StopLoop
#========================================================================
{
	my $hash=shift // return;	
	my $name=$hash->{NAME};
	
	Log($name,"Stopping internal timer loop",5);
	RemoveInternalTimer($hash);		
	readingsSingleUpdate($hash,'next_cycle','disabled',0);

	return;
}

############################################################################
# HELPER - Functions
############################################################################

	#========================================================================
	sub Log
	#========================================================================
	#own log routine adding package and device name to log entries
	{
		my $name=shift;
		my $msg=shift;
		my $verb=shift;
		
		$msg //= 'noMsg';
		my $verbRef = $name; #(undef=global!)
		$name //= __PACKAGE__;
		$verb //= 3;
		

		Log3 $verbRef,$verb,'['.$name.']: '.$msg;
		return undef
	}

	#========================================================================
	sub version_compare
	#========================================================================
	{
		#returns 1  if v1 > v2
		#returns -1 if v1 < v1
		#returns 0  if v1 = v2
		#if number of version parts are different, only minimum number of
		#version parts are compared. So '1.4' = '1.4.2' and '1.4' = '1.4.8' ...
		my $v1=shift // return;
		my $v2=shift // return;

		$v1=$v1 =~ s/[^0-9.]//rg;
		$v1=$v1 =~ s/^\.//gr; 

		$v2=$v2 =~ s/[^0-9.]//rg;
		$v2=$v2 =~ s/^\.//gr; 

		my @sv1= split /\./, $v1;
		my @sv2= split /\./, $v2;
		
		return if($#sv1 < 0 || $#sv2 < 0);
		
		my $min=$#sv1;
		if($#sv2 < $min) {
			$min=$#sv2
		}

		my $result=0;

		for(my $i=0;$i<=$min;$i++) {
			if($sv1[$i]+0 > $sv2[$i]+0) {
					$result=1;
					last;
			} elsif($sv1[$i]+0 < $sv2[$i]+0) {
					$result=-1;
					last;
			}
		}
		
		return $result;
		
	}

	#========================================================================
	sub jsonError {
	#========================================================================
		my $err=shift;
		return "{\"error\":\"$err\"}";
	}




#########################################################################
# HELP - Documentation for FHEM help command in EN and DE
#------------------------------------------------------------------------
# must be validated with ./contrib/commandref_join.pl -> No Errors!
#########################################################################
1;

=pod
=item helper
=item summary Settings and special functions for FHEMapp-UI
=item summary_DE Einstellungen und Spezialfunktionalitaet fuer das FHEMapp-UI

=begin html

<a id="FHEMAPP"></a>
<h3>fhemApp</h3>
<ul>

  Defines a helper device for FHEMapp UI.<br>
  Provides configuration storage, special functionalities for a FHEMapp UI.<br><br>
  
  This requires at least one installation of FHEMApp to be delivered by a Web-Server. If the installation should
  run on the same computer as FHEM and FHEM should deliver the FHEMApp-UI (recommended) then The 
  installation can be performed by a FHEMAPP device itself locally.<br><br>

  For more information and detailed instructions, see FHEMApp on github: <a href="https://github.com/jemu75/fhemApp">https://github.com/jemu75/fhemApp</a>
  <br><br>

  <a id="FHEMAPP-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHEMAPP [pathToLocalFolder|none]</code>
    <br><br>

	pathToLocalFolder = A local folder that could be accessed by FHEM and
	from which FHEMapp UI is provided via FHEMWEB.
	Usually this is a folder below ./www (this will automatcally resolved)
	<br><br>
	If no local installations should be managed by this device you could
	specify none instead of a folder path.
	<br><br>

    Examples:
    <ul>
      <code>define fa FHEMAPP fhemapp</code><br>
    </ul>
    <ul>
      <code>define fa2 FHEMAPP none</code><br>
    </ul>

	 <br><br>
	 <b>Important:</b> If the device is deleted with delete command, it
	    also deletes the config file!<br>
		 The fhemapp application files (in ./www) are currently <b>not</b> deleted
		 if the device is deleted.
  </ul>
  <br>

  <a id="FHEMAPP-set"></a>
  <b>Set</b>
  <ul>
    <li>checkVersions<br>
	Executes the version check, which is usually performed cyclic, immediately.
	This has no effect on the actual version check cycle itself.<br>
	This command is only available for FHEMAPP instances that are managing a 
	local FHEMApp installation
	</li>
    <li>update<br>
	Updates the locally managed fhemapp installation to the latest release or
	pre-release, depending on the updatePath (see attribute).<br>
	This command is only available for FHEMAPP instances that are managing a 
	local FHEMApp installation
	</li>
    <li>rereadCfg<br>
	Reloads the config from the fhemapp config file. Could be used in case of
	changes to the file were made manually.
	</li>
    <li>getConfig<br>
	Returns the current configuration JSON in the active window withoud surrounding
	dialog.
	</li>
  </ul>
  <br>

  <a id="FHEMAPP-get"></a>
  <b>Get</b> 
  <ul>
    <li>rawconfig<br>
	returns the currently saved config for FHEMapp in json format.
	This is usually only used by FHEMapp itself, but can be useful
	for debugging purposes.
	</li>
	<li>version<br>
	Returns the current version number of a local FHEMapp installation.
	If no local installation is specified (s. define), there will be
	no result (undef).
	</li>
  </ul>
  <br>

  <a id="FHEMAPP-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a><br>
	this will only disable the cyclic version checking!</li>

    <li><a id="FHEMAPP-attr-interval">interval</a><br>
      Overrides the default interval (3600 seconds) for cyclic version 
	  checking. Max value is 1 day (86400 seconds) and minimum value
	  is 1 minute (60) seconds.<br>
	  See also INTERNAL INTERVAL
	  </li>

    <li><a id="FHEMAPP-attr-sourceUrl">sourceUrl</a><br>
      Overrides the default URL for the source repository, used for 
	  version checking, update and installation. This is usally a
	  github repository<br>
	  See also INTERNAL SOURCE_URL
	</li>

    <li><a id="FHEMAPP-attr-updatePath">updatePath</a><br>
      Defines the update path for fhemapp updates and installations.
		Can be set to "beta" to retreive pre-releases. Default is 
		stable (attribute is unset).
	</li>
    <li><a id="FHEMAPP-attr-exposeConfigFile">exposeConfigFile</a><br>
	   By setting this attribute, the config file is made availabel in the 
		"Edit Files" list in FHEM.
		This is could be usefull for backup purposes.<br>
		!!! Direct editing the config file is explicitly NOT RECOMMENDED!!!
	 </li>
    <li><a id="FHEMAPP-attr-linkPath">linkPath</a><br>
	   FHEMAPP instances, that are managing local FHEMApp installations usually have
		a INTERNAL containing a link to the UI.
		For instances that are defined with "none", the required path information is
		missing and could therefore be set here the same way as in DEF for "full" instances.<br>
		This is only relevant for instances without local FHEMApp-Installation.
	 </li>

  </ul>
  <br>

</ul>

=end html

=begin html_DE

<a id="FHEMAPP"></a>
<h3>FHEMAPP</h3>
<ul>

  Definiert ein Hilfs-Device für FHEMApp (UI)
  Es &uuml;bernimm dafür die Konfigurationsverwaltung stellt weitere Hilfsfunktionen für FHEMApp bereit.
  <br><br>
  
  Es wird mindestens eine erreichbare Installation von FHEMApp UI ben&ouml;tigt, die von einem Web-Server ausgeliefert wird.
  Soll die Installation auf demselben Computer, auf dem auch FHEM installiert ist erfolgen und soll FHEM als Web-Server
  für die Auslieferung der FHEMApp UI - Anwendung sein (das ist die bevorzuge Methode), so kann ein FHEMAPP-Device diese
  lokale Installation selbst vornehemen.<br><br>

  Für weitere Informationen und die FHEMApp-Dokumentation siehe FHEMApp auf github: <a href="https://github.com/jemu75/fhemApp">https://github.com/jemu75/fhemApp</a>
  <br><br>

  <a id="FHEMAPP-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHEMAPP &lt;pathToLocalFolder|none&gt;</code>
    <br><br>
	
	pathToLocalFolder = Ein lokaler Ordner, der von FHEM aus erreicht werden
	kann und unter dem das FHEMapp UI von FHEMWEB bereitgestellt wird.
	Normalerweise ist das ein Ordner unterhalb von ./www (wird autom. erg&auml;nzt)
	<br><br>
	Sollen keine lokalen FHEMapp UI Installationen durch das Modul verwaltet
	werden, kann hier statt des Pfade none angegeben werden.
	<br><br>
    Beispiele:
    <ul>
      <code>define fa FHEMAPP fhemapp</code><br>
    </ul>
    <ul>
      <code>define fa2 FHEMAPP none</code><br>
    </ul>

	 <br><br>
	 <b>WICHTIG:</b> Wenn das Device mittels delete Befehl aus FHEM gel&ouml;scht wird, 
		 dann wird ebenfalls die Config-Datei gel&ouml;scht!<br>
		 Die fhemapp Anwendungsinstallation (in ./www) wird derzeit <b>nicht</b> mit-gel&ouml;scht.
  </ul>
  <br>

  <a id="FHEMAPP-set"></a>
  <b>Set</b>
  <ul>
    <li>checkVersions<br>
	F&uuml;hrt den Check, der nmormalerweise zyklisch ausgef&uuml;hrt wird, 
	sofort aus. Der normale Abfragezyklus wird davon nicht beeinflu&szlig;t.<br>
	Dieser befehl ist nur bei einer FHEMAPP-Instanz vorhanden, die auch eine
	lokales FHEMApp-Installation verwaltet
	</li>
    <li>update<br>
	F&uuml;hrt ein update der lokal verwalteten fhemapp-Installation auf die
	aktuellste Version im gewählten Update-Pfad durch.<br>
	Dieser befehl ist nur bei einer FHEMAPP-Instanz vorhanden, die auch eine
	lokales FHEMApp-Installation verwaltet
	</li>
    <li>rereadCfg<br>
	Erzwingt ein erneutes Einlesen der fhemapp Config-Datei. Dies kann notwendig
	sein, wenn manuell &Auml;nderungen an der Datei vorgenommen wurden.
	</li>
    <li>getConfig<br>
	Ruft die aktuell im Speicher vorhandene Config als JSON ab. Die Ausgabe
	efolgt dabei direkt im Fenster, ohne umschließenden Diealog, wie bei get.
	</li>
  </ul>
  <br>

  <a id="FHEMAPP-get"></a>
  <b>Get</b> 
  <ul>
    <li>rawconfig<br>
	Gibt die aktuell gespeicherte Konfiguration von FHEMapp aus.
	Diese Funktion wird normalerweise ausschlie&szlig;lich durch FHEMapp direkt
	verwendet, kann aber f&uuml;r Debugging-Zwecke n&uuml;tzlich sein.
	</li>
  </ul>
  <br>

  <a id="FHEMAPP-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a><br>
	Es wird lediglich die zyklische Versionspr&uuml;fung deaktiviert!</li>

    <li><a id="FHEMAPP-attr-interval">interval</a><br>
      &uuml;berschreibt das Default-Intervall (alle 3600 Sekunden) für die zyklische
	  Abfrage der Versionsinformationen. Minimum-Wert ist 60 Sekunden, Maximum
	  ist 1 Tag (86400 Sekunden).<br>
	  Dieses Attribut ist nur bei Instanzen relevant, die auch ein lokale FHEMApp-Installation
	  verwalten.<br>
	  Siehe auch INTERNAL INTERVAL</li>

    <li><a id="FHEMAPP-attr-sourceUrl">sourceUrl</a><br>
      Mit diesem Attribut kann die Default-Url des Quell-Repositories, das für 
	  Versions-Abfragen, Installation und Aktualisierungen verwendet werden soll
	  &uuml;berschrieben werden. Das ist i.d.R. ein github-Repository.<br>
	  Siehe auch INTERNAL SOURCE_URL</li>
    <li><a id="FHEMAPP-attr-updatePath">updatePath</a><br>
      Mit diesem Attribut kann der Update-Pfad festgelegt werden, sprich welche
		Updates &uuml;berhaupt installiert werden sollen. Das Attribut kann auf "beta" 
		gesetzt werden, um pre-releases zu erhalten. Default ist "stable" (Wenn
		das Attribut nicht gesetzt ist)</li>
    <li><a id="FHEMAPP-attr-exposeConfigFile">exposeConfigFile</a><br>
      Mit diesem Attribut kann festgelegt werden, dass das Config-File in der Liste
		unter "Edit Files" zur Bearbeitung zur Verf&uuml;gung steht.
		Diese Funktion kann zu Backup-Zwecken verwendet werden!<br>
		!!! Die direkte Bearbeitung der Config wird ausdrücklich NICHT empfohlen!!!</li>
    <li><a id="FHEMAPP-attr-linkPath">linkPath</a><br>
      Bei FHEMAPP-Instanzen, die eine lokale FHEMApp-Installation verwalten wird 
		automatisch ein Link generiert, &uuml;ber den FHEMApp mit der Config dieser 
		Instanz aufgerufen werden kann. Bei Instanzen, wo im DEF "none" angegeben wurde,
		fehlt die notwendige Information f&uuml;r den aufruf. Die kann hier analog zum DEF
		nachgeholt werden.<br>
		Bei Instanzen mit lokaler FHEMApp-Verwaltung hat dieses Attribut keine Relevanz</li>

  </ul>
  <br>

</ul>

=end html_DE

=cut
