# $Id$
##############################################################################
#
#     82_LGTV_IP12.pm
#     An FHEM Perl module for controlling LG Smart TV's which were
#     release between 2012 - 2014.
#
#     based on 82_LGTV_IP12.pm from Julian Tatsch (http://www.tatsch-it.de/tag/lgtv/)
#
#     Copyright by Markus Bloch
#     e-mail: Notausstieg0309@googlemail.com
#
#     This file is part of fhem.
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
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use warnings;
use strict;
use HttpUtils;


sub LGTV_IP12_displayPairingCode($);
sub LGTV_IP12_Pair($$);
sub LGTV_IP12_getInfo($$);
sub LGTV_IP12_sendCommand($$);

# remote control codes
my %LGTV_IP12_rcCodes = (
	"power"=>1,
    "0"=>2,
	"1"=>3,
	"2"=>4,
	"3"=>5,
	"4"=>6,
	"5"=>7,
	"6"=>8,
	"7"=>9,
	"8"=>10,
	"9"=>11,
	"up"=>12,
	"down"=>13,
	"left"=>14,
	"right"=>15,
	"ok"=>20,
	"home"=>21,
	"menu"=>22,
	"back"=>23,
	"volumeUp"=>24,
	"volumeDown"=>25,
	"mute"=>26,
	"channelUp"=>27,
	"channelDown"=>28,
	"blue"=>29,
	"green"=>30,
	"red"=>31,
	"yellow"=>32,
	"play"=>33,
	"pause"=>34,
	"stop"=>35,
	"fastForward"=>36,
	"rewind"=>37,
	"skipForward"=>38,
	"skipBackward"=>39,
	"record"=>40,
	"recordingList"=>41,
	"repeat"=>42,
	"liveTv"=>43,
	"epg"=>44,
	"info"=>45,
	"ratio"=>46,
	"input"=>47,
	"PiP"=>48,
	"subtitle"=>49,
	"proglist"=>50,
	"teletext"=>51,
	"mark"=>52,
	"3Dvideo"=>400,
	"3D_L/R"=>401,
	"dash"=>402,
	"prevchannel"=>403,
	"favouriteChannel"=>404,
	"quickMenu"=>405,
	"textOption"=>406,
	"audioDescription"=>407,
	"netCast"=>408,
	"energySaving"=>409,
	"avMode"=>410,
	"simplink"=>411,
	"exit"=>412,
	"reservationProglist"=>413,
	"PiP_channelUp"=>414,
	"PiP_channelDown"=>415,
	"switchPriSecVideo"=>416,
	"myApps"=>417,
);

#################################
sub
LGTV_IP12_Initialize($)
{
    my ($hash) = @_;

    $hash->{DefFn}     = "LGTV_IP12_Define";
    $hash->{DeleteFn}  = "LGTV_IP12_Delete";
    $hash->{UndefFn}   = "LGTV_IP12_Undef";
    $hash->{SetFn}     = "LGTV_IP12_Set";
    $hash->{GetFn}     = "LGTV_IP12_Get";
    $hash->{AttrFn}    = "LGTV_IP12_Attr";
    $hash->{NotifyFn}  = "LGTV_IP12_Notify";
    $hash->{AttrList}  = "do_not_notify:0,1 pairingcode request-timeout:1,2,3,4,5 disable:0,1 disabledForIntervals ".$readingFnAttributes;
}

#################################
sub
LGTV_IP12_Define($$)
{
    my ($hash, $def) = @_;
    my @args = split("[ \t]+", $def);
    my $name = $hash->{NAME};
    if (int(@args) < 2)
    {
        return "LGTV_IP12: not enough arguments. Usage: " .
        "define <name> LGTV_IP12 <HOST>";
    }

    $hash->{HOST} = $args[2];
    $hash->{PORT} = "8080";

    # if an update interval was given which is greater than zero, use it.
    if(defined($args[3]) and $args[3] > 0)
    {
		$hash->{helper}{OFF_INTERVAL} = $args[3];
    }
    else
    {
		$hash->{helper}{OFF_INTERVAL} = 30;
    }

    if(defined($args[4]) and $args[4] > 0)
    {
        $hash->{ON_INTERVAL} = $args[4];
        $hash->{OFF_INTERVAL} = $hash->{helper}{OFF_INTERVAL};
		$hash->{helper}{ON_INTERVAL} = $args[4];
    }
    else
    {
        $hash->{INTERVAL} = $hash->{helper}{OFF_INTERVAL};
		$hash->{helper}{ON_INTERVAL} = $hash->{helper}{OFF_INTERVAL};
    }

    $hash->{STATE} = 'defined';
    $hash->{NOTIFYDEV} = "global";

    return undef;
}

#################################
sub
LGTV_IP12_Get($@)
{
    my ($hash, @a) = @_;
    my $what;
    my $return;

    return "argument is missing" if(int(@a) != 2);

    $what = $a[1];

    return ReadingsVal($hash->{NAME}, $what, "") if(defined(ReadingsVal($hash->{NAME}, $what, undef)));

    $return = "unknown argument $what, choose one of";

    foreach my $reading (keys %{$hash->{READINGS}})
    {
        $return .= " $reading:noArg";
    }

    return $return;

}

#################################
sub
LGTV_IP12_Notify($$)
{
    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};

    return unless(exists($dev->{NAME}) and $dev->{NAME} eq "global");

    if(grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}))
    {
        if(defined(AttrVal($name, "pairingcode", undef)) and AttrVal($name, "pairingcode", undef) =~/^\d{6}$/)
        {
            Log3 $name, 3, "LGTV_IP12 ($name) - try pairing with pairingcode ".AttrVal($name, "pairingcode", undef);
            LGTV_IP12_Pair($hash, AttrVal($name, "pairingcode", undef));
        }

        LGTV_IP12_ResetTimer($hash, 0);
    }
    elsif(grep(m/^(?:ATTR $name disable.*|DELETEATTR $name disable.*)$/, @{$dev->{CHANGED}}))
    {
        LGTV_IP12_ResetTimer($hash, 0);
    }
}

#################################
sub
LGTV_IP12_Set($@)
{
    my ($hash, @args) = @_;
    my $name = $hash->{NAME};

    my $what = $args[1];
    my $arg = $args[2];

    my $usage = "Unknown argument $what, choose one of ". "statusRequest:noArg ".
                                                          "showPairCode:noArg ".
                                                          "removePairing:noArg ".
                                                          "remoteControl:".join(",", sort keys %LGTV_IP12_rcCodes)." ".
                                                          (exists($hash->{helper}{CHANNEL_LIST}) ? "channelDown:noArg channelUp:noArg channel:".join(",",sort {$a <=> $b} keys %{$hash->{helper}{CHANNEL_LIST}}) : "")." ".
                                                          (exists($hash->{helper}{APP_LIST}) ? "startApp:".join(",",sort {$a cmp $b} keys %{$hash->{helper}{APP_LIST}})." stopApp:".join(",",sort {$a cmp $b} keys %{$hash->{helper}{APP_LIST}}) : "")
                                                          ;

    if($what eq "showPairCode")
    {
        LGTV_IP12_HttpGet($hash, "/udap/api/pairing", $what, undef, "<api type=\"pairing\"><name>showKey</name></api>");
    }
    elsif($what eq "removePairing")
    {
        LGTV_IP12_HttpGet($hash, "/udap/api/pairing", $what, undef, "<api type=\"pairing\"><name>byebye</name><port>8080</port></api>");
    }
    elsif($what =~ /^(channel|channelUp|channelDown)$/)
    {
        unless(exists($hash->{helper}{CHANNEL_LIST}))
        {
            LGTV_IP12_ResetTimer($hash, 0);
        }

        my $new_channel;

        if($what eq "channelUp" or $what eq "channelDown")
        {
            my $current_channel = ReadingsVal($name, "channel", undef);

            if(defined($current_channel) and $current_channel =~ /^\d+$/ and $current_channel > 0)
            {
                my $found = 0;

                $new_channel = (grep { $found++ < 1; } grep {  ($what eq "channelUp"  ? $_ > $current_channel : $_ < $current_channel ) } sort { ($what eq "channelUp" ? $a <=> $b : $b <=> $a) } grep { defined($_) and /^\d+$/ } keys %{$hash->{helper}{CHANNEL_LIST}})[0];

            }
        }
        elsif($what eq "channel" and exists($hash->{helper}{CHANNEL_LIST}) and exists($hash->{helper}{CHANNEL_LIST}{$arg}))
        {
           $new_channel = $arg;
        }
        else
        {
            return $usage;
        }

        if(defined($new_channel))
        {
            Log3 $hash->{NAME}, 5 , "LGTV_IP12 (".$hash->{NAME}.") - set new channel: $new_channel";

            my $xml = "<api type=\"command\"><name>HandleChannelChange</name>";
            $xml .= "<major>".$hash->{helper}{CHANNEL_LIST}{$new_channel}{major}."</major>";
            $xml .= "<minor>".$hash->{helper}{CHANNEL_LIST}{$new_channel}{minor}."</minor>";
            $xml .= "<sourceIndex>".$hash->{helper}{CHANNEL_LIST}{$new_channel}{sourceIndex}."</sourceIndex>";
            $xml .= "<physicalNum>".$hash->{helper}{CHANNEL_LIST}{$new_channel}{physicalNum}."</physicalNum>";
            $xml .= "</api>";

            LGTV_IP12_HttpGet($hash, "/udap/api/command", "channel", $new_channel, $xml);
        }
    }
    elsif($what eq "startApp" and exists($hash->{helper}{APP_LIST}) and exists($hash->{helper}{APP_LIST}{$arg}))
    {
        LGTV_IP12_HttpGet($hash, "/udap/api/command", $what, $arg, "<api type=\"command\"><name>AppExecute</name><auid>".$hash->{helper}{APP_LIST}{$arg}{auid}."</auid><appname>".$hash->{helper}{APP_LIST}{$arg}{name}."</appname><contentId>".$hash->{helper}{APP_LIST}{$arg}{cpid}."</contentId></api>");
    }
    elsif($what eq "stopApp" and exists($hash->{helper}{APP_LIST}) and exists($hash->{helper}{APP_LIST}{$arg}))
    {
        LGTV_IP12_HttpGet($hash, "/udap/api/command", $what, $arg, "<api type=\"command\"><name>AppTerminate</name><auid>".$hash->{helper}{APP_LIST}{$arg}{auid}."</auid><appname>".$hash->{helper}{APP_LIST}{$arg}{name}."</appname><contentId>".$hash->{helper}{APP_LIST}{$arg}{cpid}."</contentId></api>");
    }
    elsif($what eq "statusRequest")
    {
        LGTV_IP12_GetStatus($hash)
    }
    elsif($what eq "remoteControl" and exists($LGTV_IP12_rcCodes{$arg}))
    {
        LGTV_IP12_HttpGet($hash, "/udap/api/command", $what, $arg, "<api type=\"command\"><name>HandleKeyInput</name><value>".$LGTV_IP12_rcCodes{$arg}."</value></api>");
    }
    else
    {
        return $usage;
    }
}

##########################
sub
LGTV_IP12_Attr(@)
{
    my @a = @_;
    my $hash = $defs{$a[1]};

    if($a[0] eq "set" && $a[2] eq "pairingcode")
    {
        # if a pairing code was set as attribute, try immediatly a pairing
        LGTV_IP12_Pair($hash, $a[3]);
    }
    elsif($a[0] eq "del" && $a[2] eq "pairingcode")
    {
        # if a pairing code is removed, start unpairing
        LGTV_IP12_HttpGet($hash, "/udap/api/pairing", "removePairing", undef, "<api type=\"pairing\"><name>byebye</name><port>8080</port></api>") if(exists($hash->{helper}{PAIRED}) and $hash->{helper}{PAIRED} == 1);
    }

    if($a[0] eq "set" && $a[2] eq "disable")
    {
        if($a[3] eq "1")
        {
            readingsSingleUpdate($hash, "state", "disabled",1);
        }
        LGTV_IP12_ResetTimer($hash, 0);
    }
    elsif($a[0] eq "del" && $a[2] eq "disable")
    {
        LGTV_IP12_ResetTimer($hash, 0);
    }

    return undef;
}

#################################
sub
LGTV_IP12_Delete($$)
{
    my ($hash, $name) = @_;
    # unpairing
    LGTV_IP12_HttpGet($hash, "/udap/api/pairing", "removePairing", undef, "<api type=\"pairing\"><name>byebye</name><port>8080</port></api>") if(exists($hash->{helper}{PAIRED}) and $hash->{helper}{PAIRED} == 1);
}

#################################
sub
LGTV_IP12_Undef($$)
{
    my ($hash, $name) = @_;

    RemoveInternalTimer($hash);
}


############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################


#################################
# start a status request by starting the neccessary requests
sub
LGTV_IP12_GetStatus($)
{
    my ($hash) = @_;

    unless(exists($hash->{helper}{CHANNEL_LIST}) and ReadingsVal($hash->{NAME}, "state", "off") eq "on")
    {
        LGTV_IP12_HttpGet($hash, "/udap/api/data?target=channel_list", "statusRequest", "channelList", undef);
    }

    unless(exists($hash->{helper}{APP_LIST}) and ReadingsVal($hash->{NAME}, "state", "off") eq "on")
    {
        LGTV_IP12_HttpGet($hash, "/udap/api/data?target=applist_get&type=1&index=0&number=0", "statusRequest", "appList", undef);
    }

    LGTV_IP12_HttpGet($hash, "/udap/api/data?target=cur_channel", "statusRequest", "currentChannel");

    LGTV_IP12_HttpGet($hash, "/udap/api/data?target=volume_info", "statusRequest", "volumeInfo");

    LGTV_IP12_HttpGet($hash, "/udap/api/data?target=is_3d", "statusRequest", "is3d");

    LGTV_IP12_ResetTimer($hash);
}

#################################
# parses the HTTP response from the TV
sub
LGTV_IP12_ParseHttpResponse($$$)
{

    my ( $param, $err, $data ) = @_;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $cmd = $param->{cmd};
    my $arg = $param->{arg};

    $err = "" unless(defined($err));
    $data = "" unless(defined($data));

    # we successfully received a HTTP status code in the response
    if($data eq "" and exists($param->{code}))
    {
        # when a HTTP 401 was received => UNAUTHORIZED => No Pairing
        if($param->{code} eq 401)
        {
            Log3 $name, 3, "LGTV_IP12 ($name) - failed to execute \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": Device is not paired";

            if(exists($hash->{helper}{PAIRED}))
            {
                if($hash->{helper}{PAIRED} == 1)
                {
                    $hash->{helper}{PAIRED} = 0;
                }
            }

            # If a pairing code is set as attribute, try one repair (when $hash->{helper}{PAIRED} == -1)
            if(defined(AttrVal($name, "pairingcode", undef)) and AttrVal($name, "pairingcode", undef) =~/^\d{6}$/)
            {
                Log3 $name, 3, "LGTV_IP12 ($name) - try repairing with pairingcode ".AttrVal($name, "pairingcode", undef);
                LGTV_IP12_Pair($hash, AttrVal($name, "pairingcode", undef));
                return;
            }
        }

        if($cmd eq "channel" and $param->{code} == 200)
        {
            readingsSingleUpdate($hash, $cmd, $arg, 1);
            LGTV_IP12_ResetTimer($hash, 2);
            return;
        }
    }

    readingsBeginUpdate($hash);

    # if an error was occured, raise a log entry
    if($err ne "")
    {
        Log3 $name, 5, "LGTV_IP12 ($name) - could not execute command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\" - $err";

        readingsBulkUpdate($hash, "state", "off");
        readingsBulkUpdate($hash, "power", "off");
    }

    # if the response contains data, examine it.
    if($data ne "")
    {
        Log3 $name, 5, "LGTV_IP12 ($name) - got response for \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $data";

        readingsBulkUpdate($hash, "state", "on");
        readingsBulkUpdate($hash, "power", "on");

        if($cmd eq "statusRequest")
        {
            if($arg eq "volumeInfo")
            {
                if($data =~ /<level>(.+?)<\/level>/)
                {
                    readingsBulkUpdate($hash, "volume", $1);
                }

                if($data =~ /<mute>(.+?)<\/mute>/)
                {
                    readingsBulkUpdate($hash, "mute", ($1 eq "true" ? "on" : "off"));
                }
            }

            if($arg eq "currentChannel")
            {
                if($data =~ /<inputSourceName>(.+?)<\/inputSourceName>/)
                {
                    readingsBulkUpdate($hash, "input", LGTV_IP12_html2txt($1));
                }

                if($data =~ /<labelName>(.+?)<\/labelName>/)
                {
                    readingsBulkUpdate($hash, "inputLabel", LGTV_IP12_html2txt($1));
                }

                if($data =~ /<chname>(.+?)<\/chname>/)
                {
                    readingsBulkUpdate($hash, "channelName", LGTV_IP12_html2txt($1));
                }

                 if($data =~ /<major>(.+?)<\/major>/)
                {
                    readingsBulkUpdate($hash, "channel", $1);
                }

                if($data =~ /<progName>(.+?)<\/progName>/)
                {
                    readingsBulkUpdate($hash, "currentProgram", LGTV_IP12_html2txt($1));
                }
            }

            if($arg eq "is3d")
            {
                if($data =~ /<is3D>(.+?)<\/is3D>/)
                {
                    readingsBulkUpdate($hash, "3D", $1);
                }
            }

            if($arg eq "appList")
            {
                while($data =~ /<data><auid>([0-9a-f]+)<\/auid><name>\s*([^<]+?)\s*<\/name><type>(\d+)<\/type><cpid>([\w\d_-]*)<\/cpid>.*?<\/data>/gci)
                {
                    my @fields = ($1,$2,$3,$4);
                    my $index = $2;
                    $index =~ s/[^a-z0-9\.-_ ]//gi;
                    $index =~ s/[\s,]+/_/g;
                    $hash->{helper}{APP_LIST}{$index}{auid} = $fields[0];
                    $hash->{helper}{APP_LIST}{$index}{name} = $fields[1];
                    $hash->{helper}{APP_LIST}{$index}{type} = $fields[2];
                    $hash->{helper}{APP_LIST}{$index}{cpid} = $fields[3];
                }
            }

            if($arg eq "channelList")
            {
                delete($hash->{helper}{CHANNEL_LIST}) if(exists($hash->{helper}{CHANNEL_LIST}));

                while($data =~ /<data>(.+?)<\/data>/gc)
                {
                    my $channel = $1;
                    if($channel =~ /<major>(\d+?)<\/major>/)
                    {
                        my $channel_major = $1;
                        $hash->{helper}{CHANNEL_LIST}{$channel_major}{major} = $channel_major;

                        if($channel =~ /<minor>(\d+?)<\/minor>/)
                        {
                            $hash->{helper}{CHANNEL_LIST}{$channel_major}{minor} = $1;
                        }

                        if($channel =~ /<sourceIndex>(\d+?)<\/sourceIndex>/)
                        {
                            $hash->{helper}{CHANNEL_LIST}{$channel_major}{sourceIndex} = $1;
                        }

                        if($channel =~ /<physicalNum>(\d+?)<\/physicalNum>/)
                        {
                            $hash->{helper}{CHANNEL_LIST}{$channel_major}{physicalNum} = $1;
                        }

                        if($channel =~ /<chname>(.+?)<\/chname>/)
                        {
                            Log3 $name, 5 , "LGTV_IP12 ($name) - adding channel ".LGTV_IP12_html2txt($1);
                            $hash->{helper}{CHANNEL_LIST}{$channel_major}{chname} = LGTV_IP12_html2txt($1);
                        }
                    }
                }
            }
        }
    }

    readingsEndUpdate($hash, 1);
}

#################################
# executes a http request with or without data and starts the HTTP request non-blocking to avoid timing problems for other modules (e.g. HomeMatic)
sub
LGTV_IP12_HttpGet($$$$;$)
{
    my ($hash, $path, $cmd, $arg, $data) = @_;

    if(defined($data))
    {
        Log3 $hash->{NAME}, 5 , "LGTV_IP12 (".$hash->{NAME}.") - sending POST request for command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\" to url $path: $data";
        # start a HTTP POST on the given url with content data
        HttpUtils_NonblockingGet({
                                url        => "http://".$hash->{HOST}.":8080".$path,
                                timeout    => AttrVal($hash->{NAME}, "request-timeout", 4),
                                noshutdown => 1,
                                header     => "User-Agent: Linux/2.6.18 UDAP/2.0 CentOS/5.8\r\nContent-Type: text/xml; charset=utf-8\r\nConnection: Close",
                                data       => "<?xml version=\"1.0\" encoding=\"utf-8\"?><envelope>".$data."</envelope>",
                                loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                                hash       => $hash,
                                cmd        => $cmd,
                                arg        => $arg,
                                httpversion => "1.1",
                                callback   => \&LGTV_IP12_ParseHttpResponse
                            });
    }
    else
    {
        Log3 $hash->{NAME}, 5 , "LGTV_IP12 (".$hash->{NAME}.") - sending GET request for command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\" to url $path";

        # start a HTTP GET on the given url
        HttpUtils_NonblockingGet({
                                url        => "http://".$hash->{HOST}.":8080".$path,
                                timeout    => AttrVal($hash->{NAME}, "request-timeout", 4),
                                noshutdown => 1,
                                header     => "User-Agent: Linux/2.6.18 UDAP/2.0 CentOS/5.8",
                                loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                                hash       => $hash,
                                cmd        => $cmd,
                                arg        => $arg,
                                httpversion => "1.1",
                                callback   => \&LGTV_IP12_ParseHttpResponse
                            });
    }
}

#################################
# sends the pairing request.
sub
LGTV_IP12_Pair($$)
{
    my ($hash, $code) = @_;

    LGTV_IP12_HttpGet($hash, "/udap/api/pairing", "pairing", $code, "<api type=\"pairing\"><name>hello</name><value>$code</value><port>8080</port></api>");
}


#################################
# resets the status update timer according to the current state
sub LGTV_IP12_ResetTimer($;$)
{
    my ($hash, $interval) = @_;

    RemoveInternalTimer($hash);

    unless(IsDisabled($hash->{NAME}))
    {
        if(defined($interval))
        {
            InternalTimer(gettimeofday()+$interval, "LGTV_IP12_GetStatus", $hash, 0);
        }
        elsif(ReadingsVal($hash->{NAME}, "state", "off") eq "on")
        {
            InternalTimer(gettimeofday()+$hash->{helper}{ON_INTERVAL}, "LGTV_IP12_GetStatus", $hash, 0);
        }
        else
        {
            InternalTimer(gettimeofday()+$hash->{helper}{OFF_INTERVAL}, "LGTV_IP12_GetStatus", $hash, 0);
        }
    }

    return undef;
}
#############################
# convert all HTML entities into UTF-8 aquivalents
sub LGTV_IP12_html2txt($)
{
    my ($string) = @_;

    $string =~ s/&amp;/&/g;
    $string =~ s/&amp;/&/g;
    $string =~ s/&nbsp;/ /g;
    $string =~ s/&apos;/'/g;
    $string =~ s/(\xe4|&auml;)/ä/g;
    $string =~ s/(\xc4|&Auml;)/Ä/g;
    $string =~ s/(\xf6|&ouml;)/ö/g;
    $string =~ s/(\xd6|&Ouml;)/Ö/g;
    $string =~ s/(\xfc|&uuml;)/ü/g;
    $string =~ s/(\xdc|&Uuml;)/Ü/g;
    $string =~ s/(\xdf|&szlig;)/ß/g;

    $string =~ s/<.+?>//g;
    $string =~ s/(^\s+|\s+$)//g;

    return $string;
}

1;

=pod
=item device
=item summary    controls LG SmartTV's build between 2012-2014 via LAN connection
=item summary_DE steuert LG SmartTV's via LAN, welche zwischen 2012-2014 hergestellt wurden
=begin html

<a name="LGTV_IP12"></a>
<h3>LGTV_IP12</h3>
<ul>
  This module controls LG SmartTV's which were released between 2012 - 2014 via network connection. You are able
  to switch query it's power state, control the TV channels, open and close apps and send all remote control commands.
  <br><br>
  For a list of supported models see the compatibility list for <a href="https://itunes.apple.com/de/app/lg-tv-remote/id509979485?mt=8" target="_new">LG TV Remote</a> smartphone app.
  <br><br>
  <a name="LGTV_IP12_define"></a>
  <b>Define</b>
  <ul>
    <code>
    define &lt;name&gt; LGTV_IP12 &lt;ip-address&gt; [&lt;status_interval&gt;]
    <br><br>
    define &lt;name&gt; LGTV_IP12 &lt;ip-address&gt; [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
    </code>
    <br><br>

    Defining a LGTV_IP12 device will schedule an internal task (interval can be set
    with optional parameter &lt;status_interval&gt; in seconds, if not set, the value is 30
    seconds), which periodically reads the status of the TV (power state, current channel, input, ...)
    and triggers notify/FileLog commands.
    <br><br>
    Different status update intervals depending on the power state can be given also.
    If two intervals are given to the define statement, the first interval statement represents the status update
    interval in seconds in case the device is off. The second
    interval statement is used when the device is on.

    Example:<br><br>
    <ul><code>
       define TV LGTV_IP12 192.168.0.10
       <br><br>
       # With custom status interval of 60 seconds<br>
       define TV LGTV_IP12 192.168.0.10 60
       <br><br>
       # With custom "off"-interval of 60 seconds and "on"-interval of 10 seconds<br>
       define TV LGTV_IP12 192.168.0.10 60 10
    </code></ul>

  </ul>
  <br><br>

  <a name="LGTV_IP12_set"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    Currently, the following commands are defined.
    <br><br>
    <ul>
      <li><b>channel</b> &nbsp;&nbsp;-&nbsp;&nbsp; set the current channel</li>
      <li><b>channelUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches to next channel</li>
      <li><b>channelDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches to previous channel</li>
      <li><b>removePairing</b> &nbsp;&nbsp;-&nbsp;&nbsp; deletes the pairing with the device</li>
      <li><b>showPairCode</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the TV to display the pair code on the TV screen. This pair code must be set in the attribute <a href="#LGTV_IP12_pairingcode">pairingcode</a></li>
      <li><b>startApp</b> &nbsp;&nbsp;-&nbsp;&nbsp; start a installed app on the TV</li>
      <li><b>stopApp</b> &nbsp;&nbsp;-&nbsp;&nbsp; stops a running app on the TV</li>
      <li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
      <li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands</li>
    </ul>
  </ul>
  <br><br>
  <a name="LGTV_IP12get"></a>
  <b>Get</b>
 <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code>
    <br><br>
    Currently, the get command only returns the reading values. For a specific list of possible values, see section "Generated Readings/Events".
    <br><br>
  </ul>
  <br><br>
  <a name="LGTV_IP12_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="LGTV_IP12_disable">disable</a></li>
    Optional attribute to disable the internal cyclic status update of the TV. Manual status updates via statusRequest command is still possible.
    <br><br>
    Possible values: 0 => perform cyclic status update, 1 => don't perform cyclic status updates.<br><br>
    <li><a name="LGTV_IP12_disabledForIntervals">disabledForIntervals</a> HH:MM-HH:MM HH:MM-HH-MM...</li>
    Optional attribute to disable the internal cyclic status update of the TV during a specific time interval. The attribute contains a space separated list of HH:MM tupels.
    If the current time is between any of these time specifications, the cyclic update will be disabled.
    Instead of HH:MM you can also specify HH or HH:MM:SS.
    <br><br>To specify an interval spawning midnight, you have to specify two intervals, e.g.:
    <pre>23:00-24:00 00:00-01:00</pre>
    Default Value is <i>empty</i> (no intervals defined, cyclic update is always active)<br><br>
    <li><a name="LGTV_IP12_request-timeout">request-timeout</a></li>
    Optional attribute change the response timeout in seconds for all queries to the TV.
    <br><br>
    Possible values: 1-5 seconds. Default value is 4 seconds.<br><br>
    <li><a name="LGTV_IP12_pairingcode">pairingcode</a></li>
    This attribute contains the pairing code to authenticate FHEM as trusted controller. The pairing code can be displayed via  <a href="#LGTV_IP12_set">set command</a> <code>showPairCode</code>
  </ul>
  <br><br>
  <b>Generated Readings/Events:</b><br>
  <ul>
  <li><b>3D</b> - The status of 3D playback (can be "true" or "false")</li>
  <li><b>channel</b> - The number of the current channel</li>
  <li><b>channelName</b> - The name of the current channel</li>
  <li><b>currentProgram</b> - The name of the running program of the current channel</li>
  <li><b>input</b> - The current input source (e.g. Antenna, Sattelite, HDMI1, ...)</li>
  <li><b>inputLabel</b> - The user defined name of the current input source</li>
  <li><b>mute</b> - Reports the current mute state (can be "on" or "off")</li>
  <li><b>power</b> - The power status (can be "on" or "off")</li>
  <li><b>volume</b> - Reports the volume state.</li>
  </ul>
</ul>


=end html
=begin html_DE

<a name="LGTV_IP12"></a>
<h3>LGTV_IP12</h3>
<ul>
  Dieses Modul steuert SmartTV's des Herstellers LG welche zwischen 2012 und 2014 produziert wurden &uuml;ber die Netzwerkschnittstelle.
  Es bietet die M&ouml;glichkeit den aktuellen TV Kanal zu steuern, sowie Apps zu starten, Fernbedienungsbefehle zu senden, sowie den aktuellen Status abzufragen.
  <br><br>
  Es werden alle TV Modelle unterst&uuml;tzt, welche mit der <a href="https://itunes.apple.com/de/app/lg-tv-remote/id509979485?mt=8" target="_new">LG TV Remote</a> Smartphone App steuerbar sind.
  <br><br>
  <a name="LGTV_IP12_define"></a>
  <b>Definition</b>
  <ul>
    <code>define &lt;name&gt; LGTV_IP12 &lt;IP-Addresse&gt; [&lt;Status_Interval&gt;]
    <br><br>
    define &lt;name&gt; LGTV_IP12 &lt;IP-Addresse&gt; [&lt;Off_Interval&gt;] [&lt;On_Interval&gt;]
    </code>
    <br><br>
    Bei der Definition eines LGTV_IP12-Moduls wird eine interne Routine in Gang gesetzt, welche regelm&auml;&szlig;ig
    (einstellbar durch den optionalen Parameter <code>&lt;Status_Interval&gt;</code>; falls nicht gesetzt ist der Standardwert 30 Sekunden)
    den Status des TV abfragt und entsprechende Notify-/FileLog-Definitionen triggert.
    <br><br>
    Sofern 2 Interval-Argumente &uuml;bergeben werden, wird der erste Parameter <code>&lt;Off_Interval&gt;</code> genutzt
    sofern der TV ausgeschaltet ist. Der zweiter Parameter <code>&lt;On_Interval&gt;</code>
    wird verwendet, sofern der TV eingeschaltet ist.
    <br><br>
    Beispiel:<br><br>
    <ul><code>
       define TV LGTV_IP12 192.168.0.10
       <br><br>
       # Mit modifiziertem Status Interval (60 Sekunden)<br>
       define TV LGTV_IP12 192.168.0.10 60
       <br><br>
       # Mit gesetztem "Off"-Interval (60 Sekunden) und "On"-Interval (10 Sekunden)<br>
       define TV LGTV_IP12 192.168.0.10 60 10
    </code></ul>
  </ul>
  <br><br>
  <a name="LGTV_IP12_set"></a>
  <b>Set-Kommandos </b>
  <ul>
    <code>set &lt;Name&gt; &lt;Kommando&gt; [&lt;Parameter&gt;]</code>
    <br><br>
    Aktuell werden folgende Kommandos unterst&uuml;tzt.
    <br><br>
    <ul>
    <li><b>channel</b> &lt;Nummer&gt;&nbsp;&nbsp;-&nbsp;&nbsp; w&auml;hlt den aktuellen TV-Kanal aus</li>
    <li><b>channelUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; schaltet auf den n&auml;chsten Kanal um </li>
    <li><b>channelDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; schaltet auf den vorherigen Kanal um </li>
    <li><b>removePairing</b>  &nbsp;&nbsp;-&nbsp;&nbsp; l&ouml;scht das Pairing zwischen FHEM und dem TV</li>
    <li><b>showPairCode</b>  &nbsp;&nbsp;-&nbsp;&nbsp; zeigt den Pair-Code auf dem TV-Bildschirm an. Dieser Code muss im Attribut <a href="#LGTV_IP12_pairingcode">pairingcode</a> gesetzt werden, damit FHEM mit dem TV kommunizieren kann.</li>
    <li><b>startApp</b> &lt;Name&gt;&nbsp;&nbsp;-&nbsp;&nbsp; startet eine installierte App</li>
    <li><b>stopApp</b> &lt;Name&gt;&nbsp;&nbsp;-&nbsp;&nbsp; stoppt eine laufende App</li>
    <li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; fragt den aktuellen Status ab</li>
    <li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; sendet Fernbedienungsbefehle</li>
    </ul>
  </ul>
  <br><br>
  <a name="LGTV_IP12_get"></a>
  <b>Get-Kommandos</b>
  <ul>
    <code>get &lt;Name&gt; &lt;Readingname&gt;</code>
    <br><br>
    Aktuell stehen via GET lediglich die Werte der Readings zur Verf&uuml;gung. Eine genaue Auflistung aller m&ouml;glichen Readings folgen unter "Generierte Readings/Events".
  </ul>
  <br><br>
  <a name="LGTV_IP12_attr"></a>
  <b>Attribute</b>
  <ul>

    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="LGTV_IP12_disable">disable</a></li>
    Optionales Attribut zur Deaktivierung des zyklischen Status-Updates. Ein manuelles Update via statusRequest-Befehl ist dennoch m&ouml;glich.
    <br><br>
    M&ouml;gliche Werte: 0 => zyklische Status-Updates, 1 => keine zyklischen Status-Updates.<br><br>
    <li><a name="LGTV_IP12_disabledForIntervals">disabledForIntervals</a> HH:MM-HH:MM HH:MM-HH-MM...</li>
    Optionales Attribut zur Deaktivierung der zyklischen Status-Updates innerhalb von bestimmten Zeitintervallen.
    Das Argument ist eine Leerzeichen-getrennte Liste von Minuszeichen-getrennten HH:MM Paaren (Stunde : Minute).
    Falls die aktuelle Uhrzeit zwischen diese Werte f&auml;llt, dann werden zyklische Status-Updates, wie bei <a href="#LGTV_IP12_disable">disable</a>, ausgesetzt.
    Statt HH:MM kann man auch HH oder HH:MM:SS angeben.<br><br>
    Um einen Intervall um Mitternacht zu spezifizieren, muss man zwei einzelne Intervalle angeben, z.Bsp.:
    <pre>23:00-24:00 00:00-01:00</pre>
    Standardwert ist <i>nicht gesetzt</i> (dauerhaft aktiv)<br><br>
    <li><a name="LGTV_IP12_request-timeout">request-timeout</a></li>
    Optionales Attribut. Maximale Dauer einer Anfrage in Sekunden zum TV.
    <br><br>
    M&ouml;gliche Werte: 1-5 Sekunden. Standartwert ist 4 Sekunden<br><br>
    <li><a name="LGTV_IP12_pairingcode">pairingcode</a></li>
    Dieses Attribut speichert den Pairing Code um sich gegen&uuml;ber dem TV als vertrauensw&uuml;rdigen Controller zu authentifizieren. Der Pairing-Code kann via Set-Kommando <a href="#LGTV_IP12_set">showPairCode</a> angezeigt werden.
  </ul>
  <br><br>
  <b>Generierte Readings/Events:</b><br>
  <ul>
  <li><b>3D</b> - Status des 3D-Wiedergabemodus ("true" =&gt; 3D Wiedergabemodus aktiv, "false" =&gt; 3D Wiedergabemodus nicht aktiv)</li>
  <li><b>channel</b> - Die Nummer des aktuellen TV-Kanals</li>
  <li><b>channelName</b> - Der Name des aktuellen TV-Kanals</li>
  <li><b>currentProgram</b> - Der Name der laufenden Sendung</li>
  <li><b>input</b> - Die aktuelle Eingangsquelle (z.B. Antenna, Sattelite, HDMI1, ...)</li>
  <li><b>inputLabel</b> - Die benutzerdefinierte Bezeichnung der aktuellen Eingangsquelle</li>
  <li><b>mute</b> on,off - Der aktuelle Stumm-Status ("on" =&gt; Stumm, "off" =&gt; Laut)</li>
  <li><b>power</b> on,off - Der aktuelle Power-Status ("on" =&gt; eingeschaltet, "off" =&gt; ausgeschaltet)</li>
  <li><b>volume</b> - Der aktuelle Lautstärkepegel.</li>
  </ul>
</ul>
=end html_DE

=cut


