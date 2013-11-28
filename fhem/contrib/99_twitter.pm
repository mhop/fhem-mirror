##############################################
#
# Twitter for FHEM
#
##############################################
#
#  Copyright notice
#
#  (c) 2010
#  Copyright: Axel Rieger (fhem BEI anax PUNKT info)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
##############################################
# Sends Twitter-MSG
#
# Usage:
# twitter <MESSAGE>
# Beispiel
# twitter "MEINE TWITTER NACHRICHT"
# per AT-Job alle 15min
# define TW001 at +00:15:00 {my $msg = TimeNow() . " " . $defs{<DEVICE-NAME>}{'STATE'} ;; fhem "twitter $msg"}
#
# twitter STATUS
# Shows status of twitter-command:
#--------------------------------------------------------------------------------
#TWITTER 
#--------------------------------------------------------------------------------
#	 Status: Enabeld
#	 Message-Count: 17
#	 Message-Count-Max: 1000
#	 Error-Count: 0
#	 Error-Count-Max: 5
#	 Last Message: <TIMESTAMP>
#	 Last Message: <MESSAGE>
#--------------------------------------------------------------------------------
#
# twitter ENABLE/DISABLE
# Enables/disbales twitter-command
#
# Twitter Limits
# http://help.twitter.com/forums/10711/entries/15364
# Updates: 1,000 per day. The daily update limit is further broken down into
# smaller limits for semi-hourly intervals. Retweets are counted as updates.
#
# My Limits ;-)
# LPW-Timeout 5sec
# Max-Errors = 10
##############################################
package main;
use strict;
use warnings;
use POSIX;
use Data::Dumper;
use LWP::UserAgent;
use vars qw(%data);
use vars qw(%cmds);
sub Commandtwitter($);
#####################################
sub
twitter_Initialize($)
{
  # Config-Data
  # Account-Data
  $data{twitter}{login}{user} = "********";
  $data{twitter}{login}{pwd} = "********";
  # disabled ?? -> enable
  if(defined($data{twitter}{conf}{disabeld})){
    delete $data{twitter}{conf}{disabeld};
    }
  # $data{twitter}{conf}{disabeld} = 1;
  # Max 1000 MSGs per Day
  $data{twitter}{conf}{msg_count} = 0;
  $data{twitter}{conf}{day} = (localtime(time()))[3];
  # Error-Counter
  $data{twitter}{error} = 0;
  $data{twitter}{error_max} = 5;
  $data{twitter}{last_msg} = "";
  $data{twitter}{last_msg_time} = "";
  #FHEM-Command
  $cmds{twitter}{Fn} = "Commandtwitter";
  $cmds{twitter}{Hlp} = "Sends Twitter Messages (max. 140 Chars): twitter MSG";
}
#####################################
sub Commandtwitter($)
{
  my ($cl, $msg) = @_;
  if(!$msg) {
    Log 0, "TWITTER[ERROR] Keine Nachricht";
    return undef;
  }
  #Show Status
  my $status;
  $status .= "--------------------------------------------------------------------------------\n";
  $status .= "TWITTER \n";
  $status .= "--------------------------------------------------------------------------------\n";
  if($msg eq "STATUS"){
    if(defined($data{twitter}{conf}{disabeld})){$status .= "\t Status: Disbaled\n";}
    else{$status .= "\t Status: Enabeld\n";}
    $status .= "\t Message-Count: " . $data{twitter}{conf}{msg_count} . "\n";
    $status .= "\t Message-Count-Max: 1000\n";
    $status .= "\t Error-Count: " . $data{twitter}{error} . "\n"; 
    $status .= "\t Error-Count-Max: " . $data{twitter}{error_max} . "\n";
    $status .= "\t Last Message: " . $data{twitter}{last_msg_time} . "\n";
    $status .= "\t Last Message: " . $data{twitter}{last_msg} . "\n";
    $status .= "--------------------------------------------------------------------------------\n";
    return $status;
  }
  #Enable
  if($msg eq "ENABLE"){
    if(defined($data{twitter}{conf}{disabeld})){
        $status = "Twitter enabled";
        return $status;
        }
    return "Twitter already Enabeld";
  }
  # Disable
  if($msg eq "DISABLE"){
    $data{twitter}{conf}{disabeld} = 1;
    return "Twitter disabeld";
  }
  #ERROR-Counter
  my ($err_cnt,$err_max);
  if(defined($data{twitter}{error})){
  	$err_cnt = $data{twitter}{error};
  	$err_max = $data{twitter}{error_max};
  	if($err_cnt > $err_max){
  		# ERROR disable twitter
  		Log 0, "TWITTER[INFO] ErrCounter exceeded $err_max  DISABLED";
        $data{twitter}{last_msg_time} = TimeNow();
        $data{twitter}{last_msg} = "TWITTER[INFO] ErrCounter exceeded $err_max  DISABLED";
    	$data{twitter}{conf}{disabeld} = 1;
  		}
  	}
  # Disbaled ??
  if(defined($data{twitter}{conf}{disabeld})){
    Log 0, "TWITTER[STATUS] DISABLED";
    return undef;
  }
  #Changed Day
  my $d = (localtime(time()))[3];
  my $d_old = $data{twitter}{conf}{day};
  if($d_old ne $d){
    $data{twitter}{conf}{day} = $d;
    Log 0,"TWITTER[INFO] DAY-CHANGE: DAY: $d_old MSG-COUNT: " . $data{twitter}{conf}{msg_count};
    $data{twitter}{conf}{msg_count} = 0;
    #Reset ERROR-Counter
    $data{twitter}{error} = 0;
  }
  #Count MSG
  my $msg_cnt = $data{twitter}{conf}{msg_count};
  if($msg_cnt > 1000) {
    Log 0, "TWITTER[INFO] MessageCount exceede 1000 Messages per Day";
    $data{twitter}{last_msg_time} = TimeNow() ;
    $data{twitter}{last_msg} = "TWITTER[INFO] Message-Count exceeded 1000 Messages per Day";
    return undef;
  }
  my $t_user = $data{twitter}{login}{user};
  my $t_pdw = $data{twitter}{login}{pwd};
  my $t_log;
  #Add MSG-Count
  $msg = "[" . $msg_cnt ."] " . $msg;
  # Max ;SG-Length 140
  my $ml = length ($msg);
  if($ml > 140){
    Log 0, "TWITTER[INFO] Die Nachricht ist mit $ml Zeichen zu lang (max. 140)";
    $msg = substr($msg, 0, 140);
    }
  my $browser = LWP::UserAgent->new;
  # Proxy-Server
  # $browser->proxy(['http'], "http://PROXYSERVER:PORT");
  $browser->timeout(5);
  my $url = 'http://twitter.com/statuses/update.json';
  
  $browser->credentials('twitter.com:80', 'Twitter API', $t_user , $t_pdw);
  my $response = $browser->get("http://twitter.com/account/verify_credentials.json");
  if($response->code eq 200){
  	$t_log = "LOGIN=SUCCESS";
  	}
  else {
    $t_log = "TWITTER[ERROR] LOGIN: " . $response->code .":".$response->message . " DISABLED";
    $data{twitter}{error}++;
    $data{twitter}{last_msg_time} = TimeNow() ;
    $data{twitter}{last_msg} = $t_log;
    return undef;
    }
  
  $response = $browser->post($url, {status => $msg});
  if($response->code eq 200){
  	$t_log .= " UPDATE=SUCCESS";
  	}
  else {
    $t_log = "TWITTER[ERROR] UPDATE: " . $response->code .":".$response->message . " DISABLED";
    $data{twitter}{error}++;
    $data{twitter}{last_msg_time} = TimeNow() ;
    $data{twitter}{last_msg} = $t_log;
    return undef;
    }
  Log 0, "TWITTER[INFO] " . $t_log . " MSG-$msg_cnt-: $msg";
  $data{twitter}{last_msg_time} = TimeNow() ;
  $data{twitter}{last_msg} = $msg;
  $data{twitter}{conf}{msg_count}++;
  # Reset ERROR-COUNTER
  $data{twitter}{error} = 0;
  $msg_cnt++;
  return undef;
}
1;