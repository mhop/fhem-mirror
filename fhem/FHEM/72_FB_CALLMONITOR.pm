# $Id$
##############################################################################
#
#     72_FB_CALLMONITOR.pm
#     Connects to a FritzBox Fon via network.
#     When a call is received or takes place it creates an event with further call informations.
#     This module has no sets or gets as it is only used for event triggering.
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

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Digest::MD5;
use HttpUtils;
use DevIo;
use FritzBoxUtils;
use utf8;

my %connection_type = (
    0 => "0",
    1 => "FON1",
    2 => "FON2",
    3 => "FON3",
    4 => "ISDN",
    5 => "FAX",
    6 => "not_defined",
    7 => "not_defined",
    8 => "not_defined",
    9 => "not_defined",
    10 => "DECT_1",
    11 => "DECT_2",
    12 => "DECT_3",
    13 => "DECT_4",
    14 => "DECT_5",
    15 => "DECT_6",
    16 => "FRITZMini_1",
    17 => "FRITZMini_2",
    18 => "FRITZMini_3",
    19 => "FRITZMini_4",
    20 => "VoIP_1",
    21 => "VoIP_2",
    22 => "VoIP_3",
    23 => "VoIP_4",
    24 => "VoIP_5",
    25 => "VoIP_6",
    26 => "VoIP_7",
    27 => "VoIP_8",
    28 => "VoIP_9",
    29 => "VoIP_10",
    40 => "Answering_Machine_1",
    41 => "Answering_Machine_2",
    42 => "Answering_Machine_3",
    43 => "Answering_Machine_4",
    44 => "Answering_Machine_5"
);


#####################################
sub
FB_CALLMONITOR_Initialize($)
{
    my ($hash) = @_;

    # Provider
    $hash->{ReadFn}    = "FB_CALLMONITOR_Read";  
    $hash->{ReadyFn}   = "FB_CALLMONITOR_Ready";
    $hash->{GetFn}     = "FB_CALLMONITOR_Get";
    $hash->{SetFn}     = "FB_CALLMONITOR_Set";
    $hash->{DefFn}     = "FB_CALLMONITOR_Define";
    $hash->{UndefFn}   = "FB_CALLMONITOR_Undef";
    $hash->{AttrFn}    = "FB_CALLMONITOR_Attr";
    $hash->{NotifyFn}  = "FB_CALLMONITOR_Notify";
    $hash->{NOTIFYDEV} = "global";
    $hash->{AttrList}  = "do_not_notify:0,1 ".
                         "disable:0,1 ".
                         "unique-call-ids:0,1 ".
                         "local-area-code ".
                         "country-code ".
                         "remove-leading-zero:0,1 ".
                         "reverse-search-cache-file ".
                         "reverse-search:multiple-strict,phonebook,klicktel.de,dasoertliche.de,search.ch,dasschnelle.at ".
                         "reverse-search-cache:0,1 ".
                         "reverse-search-phonebook-file ".
                         "fritzbox-remote-phonebook:0,1 ".
                         "fritzbox-remote-phonebook-via:web,telnet ".
                         "fritzbox-remote-phonebook-exclude ".
                         "fritzbox-remote-timeout ".
                         "fritzbox-user ".
                         $readingFnAttributes;
}

#####################################
sub
FB_CALLMONITOR_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);

    if(@a != 3) 
    {
        my $msg = "wrong syntax: define <name> FB_CALLMONITOR ip[:port]";
        Log 2, $msg;
        return $msg;
    }
    
    DevIo_CloseDev($hash);

    my $dev = $a[2];

    $dev .= ":1012" if($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);

    $hash->{DeviceName} = $dev;

    return DevIo_OpenDev($hash, 0, undef);
}


#####################################
# closing the connection on undefinition (shutdown/delete)
sub
FB_CALLMONITOR_Undef($$)
{
    my ($hash, $arg) = @_;

    DevIo_CloseDev($hash); 
    
    return undef;
}



#####################################
# Get function for returning a reverse search name
sub
FB_CALLMONITOR_Get($@)
{
    my ($hash, @arguments) = @_;

    return "argument missing" if(int(@arguments) < 2);

    if($arguments[1] eq "search")
    {
        return FB_CALLMONITOR_reverseSearch($hash, $arguments[2]);
    }
    elsif($arguments[1] eq "showPhonebookIds" and exists($hash->{helper}{PHONEBOOK_NAMES}))
    {
        my $table = "";
        my $head = "Id    Name";
        my $width = 10;
        foreach my $phonebookId (sort keys %{$hash->{helper}{PHONEBOOK_NAMES}})
        {
            my $string = sprintf("%-3s", $phonebookId)." - ".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}; 
            $width = length($string) if(length($string) > $width);
            $table .= $string."\n";
        }
        
        return $head."\n".("-" x $width)."\n".$table;
    }
    elsif($arguments[1] eq "showPhonebookEntries" and exists($hash->{helper}{PHONEBOOK}))
    {
        my $table = "";
       
        my $number_width = 0;
        my $name_width = 0;
        
        foreach my $number (keys %{$hash->{helper}{PHONEBOOK}})
        {
            $number_width = length($number) if($number_width < length($number));
            $name_width = length($hash->{helper}{PHONEBOOK}{$number}) if($name_width < length($hash->{helper}{PHONEBOOK}{$number}));
        }
        my $head = sprintf("%-".$number_width."s   %s" ,"Number", "Name"); 
        foreach my $number (sort { lc($hash->{helper}{PHONEBOOK}{$a}) cmp lc($hash->{helper}{PHONEBOOK}{$b}) } keys %{$hash->{helper}{PHONEBOOK}})
        {
            
            my $string = sprintf("%-".$number_width."s - %s" , $number,$hash->{helper}{PHONEBOOK}{$number}); 
            $table .= $string."\n";
        }
        
        return $head."\n".("-" x ($number_width + $name_width + 3))."\n".$table;
    }
    elsif($arguments[1] eq "showCacheEntries" and exists($hash->{helper}{CACHE}))
    {
        my $table = "";
       
        my $number_width = 0;
        my $name_width = 0;
        
        foreach my $number (keys %{$hash->{helper}{CACHE}})
        {
            $number_width = length($number) if($number_width < length($number));
            $name_width = length($hash->{helper}{CACHE}{$number}) if($name_width < length($hash->{helper}{CACHE}{$number}));
        }
        my $head = sprintf("%-".$number_width."s   %s" ,"Number", "Name"); 
        foreach my $number (sort { lc($hash->{helper}{CACHE}{$a}) cmp lc($hash->{helper}{CACHE}{$b}) } keys %{$hash->{helper}{CACHE}})
        {
            
            my $string = sprintf("%-".$number_width."s - %s" , $number,$hash->{helper}{CACHE}{$number}); 
            $table .= $string."\n";
        }
        
        return $head."\n".("-" x ($number_width + $name_width + 3))."\n".$table;
    }
    else
    {
        return "unknown argument ".$arguments[1].", choose one of search".(exists($hash->{helper}{PHONEBOOK_NAMES}) ? " showPhonebookIds" : "").(exists($hash->{helper}{PHONEBOOK}) ? " showPhonebookEntries" : "").(exists($hash->{helper}{CACHE}) ? " showCacheEntries" : ""); 
    }

}

#####################################
# Set function for executing a reread of the internal phonebook
sub
FB_CALLMONITOR_Set($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $usage;
    my @sets = ();
    
    push @sets, "rereadPhonebook" if(defined($hash->{helper}{PHONEBOOK}) or AttrVal($name, "reverse-search" , "") =~ /(all|phonebook|internal)/);
    push @sets, "password" if($hash->{helper}{PWD_NEEDED});
    
    $usage = "Unknown argument ".$a[1].", choose one of ".join(" ", @sets) if(scalar @sets > 0);
    
    if($a[1] eq "rereadPhonebook")
    {
        FB_CALLMONITOR_readPhonebook($hash);
        return undef;
    }
    elsif($a[1] eq "password")
    {
        return FB_CALLMONITOR_storePassword($hash, $a[2]) if($hash->{helper}{PWD_NEEDED});
        Log3 $name, 2, "FB_CALLMONITOR ($name) - SOMEONE UNWANTED TRIED TO SET A NEW FRITZBOX PASSWORD!!!";
        return "I didn't ask for a password, so go away!!!"
    }
    else
    {
        return $usage;
    }
}


#####################################
# Receives an event and creates several readings for event triggering
sub
FB_CALLMONITOR_Read($)
{
    my ($hash) = @_;

    my $buf = DevIo_SimpleRead($hash);
    
    return "" if(!defined($buf));
    
    my $name = $hash->{NAME};
    my @array;
    my $reverse_search = undef;
    my $data = $buf;
    my $area_code = AttrVal($name, "local-area-code", "");
    my $external_number = undef;
  
    foreach $data (split(/^/m, $buf))
    {
        chomp $data;
        
        Log3 $name, 5, "FB_CALLMONITOR ($name) - received data: $data"; 
        
        @array = split(";", $data);
      
        $external_number = $array[3] if(not $array[3] eq "0" and $array[1] eq "RING" and $array[3] ne "");
        $external_number = $array[5] if($array[1] eq "CALL" and $array[3] ne "");
        $external_number =~ s/^0// if(AttrVal($name, "remove-leading-zero", "0") eq "1" and defined($external_number));
      
        if(defined($external_number) and not $external_number =~ /^0/ and $area_code ne "")
        {
            if($area_code =~ /^0[1-9]\d+$/)
            {
                $external_number = $area_code.$external_number;
            }
            else
            {
                Log3 $name, 2, "FB_CALLMONITOR ($name) - given local area code '$area_code' is not an area code. therefore will be ignored";
            }
        }

        # Remove trailing hash sign and everything afterwards
        $external_number =~ s/#.*$// if(defined($external_number));
      
        $reverse_search = FB_CALLMONITOR_reverseSearch($hash, $external_number) if(defined($external_number) and AttrVal($name, "reverse-search", "none") ne "none");
       
        Log3 $name, 4, "FB_CALLMONITOR ($name) - reverse search returned: $reverse_search" if(defined($reverse_search));
        
        if($array[1] eq "CALL" or $array[1] eq "RING")
        {
            delete($hash->{helper}{TEMP}{$array[2]}) if(exists($hash->{helper}{TEMP}{$array[2]}));
            
            if(AttrVal($name, "unique-call-ids", "0") eq "1")
            {
                $hash->{helper}{TEMP}{$array[2]}{call_id} = Digest::MD5::md5_hex($data);
            }
        }

        if($array[1] eq "CALL")
        {
            $hash->{helper}{TEMP}{$array[2]}{external_number} = (defined($external_number) ? $external_number : "unknown");
            $hash->{helper}{TEMP}{$array[2]}{external_name} = (defined($reverse_search) ? $reverse_search : "unknown");
            $hash->{helper}{TEMP}{$array[2]}{internal_number} = $array[4];
            $hash->{helper}{TEMP}{$array[2]}{external_connection} = $array[6];
            $hash->{helper}{TEMP}{$array[2]}{internal_connection} =  $connection_type{$array[3]} if(defined($connection_type{$array[3]}));
            $hash->{helper}{TEMP}{$array[2]}{direction} = "outgoing";
        }
       
        if($array[1] eq "RING")
        {
            $hash->{helper}{TEMP}{$array[2]}{external_number} = (defined($external_number) ? $external_number : "unknown");
            $hash->{helper}{TEMP}{$array[2]}{external_name} = (defined($reverse_search) ? $reverse_search : "unknown");
            $hash->{helper}{TEMP}{$array[2]}{internal_number} = $array[4];
            $hash->{helper}{TEMP}{$array[2]}{external_connection} = $array[5];
            $hash->{helper}{TEMP}{$array[2]}{direction} = "incoming";
        }
       
        if($array[1] eq "CONNECT" and not exists($hash->{helper}{TEMP}{$array[2]}{internal_connection}))
        {
            $hash->{helper}{TEMP}{$array[2]}{internal_connection} =  $connection_type{$array[3]} if(defined($connection_type{$array[3]}));
        }    
        
        if($array[1] eq "DISCONNECT")
        {
            $hash->{helper}{TEMP}{$array[2]}{call_duration} = $array[3];
        
            if(exists($hash->{helper}{TEMP}{$array[2]}{direction}) and exists($hash->{helper}{TEMP}{$array[2]}{external_number}) and $hash->{helper}{TEMP}{$array[2]}{direction} eq "incoming" and $array[3] eq "0")
            {
                $hash->{helper}{TEMP}{$array[2]}{missed_call} = $hash->{helper}{TEMP}{$array[2]}{external_number}.(exists($hash->{helper}{TEMP}{$array[2]}{external_name}) and $hash->{helper}{TEMP}{$array[2]}{external_name} ne "unknown" ? " (".$hash->{helper}{TEMP}{$array[2]}{external_name}.")" : "");
                $hash->{helper}{TEMP}{$array[2]}{missed_call_line} = $hash->{helper}{TEMP}{$array[2]}{internal_number};
            }
        }    
        
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "event", lc($array[1]));
        
        foreach my $key (keys %{$hash->{helper}{TEMP}{$array[2]}})
        {
            readingsBulkUpdate($hash, $key, $hash->{helper}{TEMP}{$array[2]}{$key}) unless($key eq "call_id");
        }   
        
        if(AttrVal($name, "unique-call-ids", "0") eq "1" and exists($hash->{helper}{TEMP}{$array[2]}{call_id}))
        {
            readingsBulkUpdate($hash, "call_id", $hash->{helper}{TEMP}{$array[2]}{call_id});
        }
        else
        {
            readingsBulkUpdate($hash, "call_id", $array[2]);
        }
        
        if($array[1] eq "DISCONNECT")
        {
            delete($hash->{helper}{TEMP}{$array[2]}) if(exists($hash->{helper}{TEMP}{$array[2]}));
        } 
        
        readingsEndUpdate($hash, 1);
        
    }
}

#####################################
# Reconnects to FritzBox in case of disconnects
sub
FB_CALLMONITOR_Ready($)
{
    my ($hash) = @_;
   
    return DevIo_OpenDev($hash, 1, undef);
}

#####################################
# Handles Attribute Changes
sub
FB_CALLMONITOR_Attr($@)
{
    
    my ($cmd, $name, $attrib, $value) = @_;
    my $hash = $defs{$name};
    
    if($cmd eq "set")
    {    
    
        if((($attrib eq "reverse-search" and $value =~ /(all|internal|phonebook)/) or $attrib eq "reverse-search-phonebook-file" or $attrib eq "fritzbox-remote-phonebook") and $init_done == 1)
        {
            $attr{$name}{$attrib} = $value;   
            return FB_CALLMONITOR_readPhonebook($hash);
        }
        
        
        if($attrib eq "reverse-search-cache-file")
        {
            return FB_CALLMONITOR_loadCacheFile($hash, $value);
        }
        
        if($attrib eq "disable")
        {
            if($value eq "0")
            {
                DevIo_OpenDev($hash, 0, undef);
            }
            elsif($value eq "1")
            {
                DevIo_CloseDev($hash); 
                $hash->{STATE} = "disabled";
            }
        }
    }
    elsif($cmd eq "del")
    {
        if($attrib eq "reverse-search" or $attrib eq "reverse-search-phonebook-file")
        {
            delete($hash->{helper}{PHONEBOOK}) if(defined($hash->{helper}{PHONEBOOK}));
        } 
        
        if($attrib eq "reverse-search-cache")
        {
            delete($hash->{helper}{CACHE}) if(defined($hash->{helper}{CACHE}));
        } 
        
        if($attrib eq "disable")
        {
            DevIo_OpenDev($hash, 0, undef);
        }
    }
    
    return undef;
}


sub
FB_CALLMONITOR_Notify($$)
{
    my ($hash,$dev) = @_;

    return if($dev->{NAME} ne "global");
    return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));
  
    FB_CALLMONITOR_readPhonebook($hash);
}
############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################


#####################################
# Performs a reverse search of a phone number
sub
FB_CALLMONITOR_reverseSearch($$)
{
    my ($hash, $number) = @_;
    my $name = $hash->{NAME};
    my $result;
    my $invert_match = undef;
    my @attr_list = split("(,|\\|)", AttrVal($name, "reverse-search", "none"));
    
    chomp $number;

    # Using internal phonebook if available and enabled
    if((grep { /^(all|phonebook|internal)$/ } @attr_list) and defined($hash->{helper}{PHONEBOOK}))
    {
        if(defined($hash->{helper}{PHONEBOOK}{$number}))
        {
            Log3 $name, 4, "FB_CALLMONITOR ($name) - using internal phonebook for reverse search of $number";
            return $hash->{helper}{PHONEBOOK}{$number};
        }
    }

    # Using Cache if enabled
    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
    {
        if(defined($hash->{helper}{CACHE}{$number}))
        {
            Log3 $name, 4, "FB_CALLMONITOR ($name) - using cache for reverse search of $number";
            if($hash->{helper}{CACHE}{$number} ne "timeout")
            {
                return $hash->{helper}{CACHE}{$number};
            }
        }
    }

    # Ask klicktel.de
    if((grep { /^(all|klicktel\.de)$/ } @attr_list))
    { 
        Log3 $name, 4, "FB_CALLMONITOR ($name) - using klicktel.de for reverse search of $number";

        $result = GetFileFromURL("http://www.klicktel.de/rueckwaertssuche/".$number, 5, undef, 1);
        if(not defined($result))
        {
            if(AttrVal($name, "reverse-search-cache", "0") eq "1")
            {
                $hash->{helper}{CACHE}{$number} = "timeout";
                undef($result);
                return "timeout";
            }
        }
        else
        {
            if($result =~ /<a href="http\:\/\/www\.klicktel\.de\/.*html" target="_self">(.+?)<\/a>/)
            {
                $invert_match = $1;
                $invert_match = FB_CALLMONITOR_html2txt($invert_match);
                FB_CALLMONITOR_writeToCache($hash, $number, $invert_match) if(AttrVal($name, "reverse-search-cache", "0") eq "1");
                undef($result);
                return $invert_match;
            }
            elsif(not $result =~ /Leider wurde zu dieser Suche kein Eintrag gefunden/)
            {
                Log3 $name, 3, "FB_CALLMONITOR ($name) - the reverse search result for $number could not be extracted from klicktel.de. Please contact the FHEM community.";
            }
        }
    }

    # Ask dasoertliche.de
    if(grep { /^(all|dasoertliche\.de)$/ } @attr_list)
    {
        Log3 $name, 4, "FB_CALLMONITOR ($name) - using dasoertliche.de for reverse search of $number";

        $result = GetFileFromURL("http://www1.dasoertliche.de/?form_name=search_inv&ph=".$number, 5, undef, 1);
        if(not defined($result))
        {
            if(AttrVal($name, "reverse-search-cache", "0") eq "1")
            {
                $hash->{helper}{CACHE}{$number} = "timeout";
                undef($result);
                return "timeout";
            }
        }
        else
        {
            #Log 2, $result;
            if($result =~ /<a href="http\:\/\/.+?\.dasoertliche\.de.+?".+?class="name ".+?><span class="">(.+?)<\/span>/)
            {
                $invert_match = $1;
                $invert_match = FB_CALLMONITOR_html2txt($invert_match);
                FB_CALLMONITOR_writeToCache($hash, $number, $invert_match) if(AttrVal($name, "reverse-search-cache", "0") eq "1");
                undef($result);
                return $invert_match;
            }
            elsif(not $result =~ /wir konnten keine Treffer finden/)
            {
                Log3 $name, 3, "FB_CALLMONITOR ($name) - the reverse search result for $number could not be extracted from dasoertliche.de. Please contact the FHEM community.";
            }
        }
    }

    # SWITZERLAND ONLY!!! Ask search.ch
    if(grep { /^search\.ch$/ } @attr_list)
    {
        Log3 $name, 4, "FB_CALLMONITOR ($name) - using search.ch for reverse search of $number";

        $result = GetFileFromURL("http://tel.search.ch/?was=".$number, 5, undef, 1);
        if(not defined($result))
        {
            if(AttrVal($name, "reverse-search-cache", "0") eq "1")
            {
                $hash->{helper}{CACHE}{$number} = "timeout";
                undef($result);
                return "timeout";
            }
        }
        else
        {
            #Log 2, $result;
            if($result =~ /<section[^>]*>.*?<h1>(.+?)<\/h1>.*?<\/section>/s)
            {
                $invert_match = $1;
                $invert_match = FB_CALLMONITOR_html2txt($invert_match);
                FB_CALLMONITOR_writeToCache($hash, $number, $invert_match) if(AttrVal($name, "reverse-search-cache", "0") eq "1");
                undef($result);
                return $invert_match;
            }
            elsif(not $result =~ /Keine Eintr.ge gefunden/)
            {
                Log3 $name, 3, "FB_CALLMONITOR ($name) - the reverse search result for $number could not be extracted from search.ch. Please contact the FHEM community.";
            }
        }
    }

    # Austria ONLY!!! Ask dasschnelle.at
    if(grep { /^dasschnelle\.at$/ } @attr_list)
    {
        Log3 $name, 4, "FB_CALLMONITOR ($name) - using dasschnelle.at for reverse search of $number";

        $result = GetFileFromURL("http://www.dasschnelle.at/result/index/results?PerPage=5&pageNum=1&what=".$number."&where=&rubrik=0&bezirk=0&orderBy=Standard&mapsearch=false", 5, undef, 1);
        if(not defined($result))
        {
            if(AttrVal($name, "reverse-search-cache", "0") eq "1")
            {
                $hash->{helper}{CACHE}{$number} = "timeout";
                undef($result);
                return "timeout";
            }
        }
        else
        {
            #Log 2, $result;
            if($result =~ /name\s+:\s+"(.+?)",/)
            {
                $invert_match = "";

                while($result =~ /name\s+:\s+"(.+?)",/g)
                {
                $invert_match = $1 if(length($1) > length($invert_match));
                }

                $invert_match = FB_CALLMONITOR_html2txt($invert_match);
                FB_CALLMONITOR_writeToCache($hash, $number, $invert_match) if(AttrVal($name, "reverse-search-cache", "0") eq "1");
                undef($result);
                return $invert_match;
            }
            elsif(not $result =~ /Es wurden keine passenden Eintr.ge gefunden/)
            {
                Log3 $name, 3, "FB_CALLMONITOR ($name) - the reverse search result for $number could not be extracted from dasschnelle.at. Please contact the FHEM community.";
            }
        }
    }

    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
    { 
        # If no result is available set cache result and return undefined 
        $hash->{helper}{CACHE}{$number} = "unknown";
    }

    return undef;

} 

#####################################
# replaces all HTML entities to their utf-8 counter parts.
sub FB_CALLMONITOR_html2txt($)
{

    my ($string) = @_;

    $string =~ s/&nbsp;/ /g;
    $string =~ s/&amp;/&/g;
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

#####################################
# writes reverse search result to the cache and if enabled to the cache file 
sub FB_CALLMONITOR_writeToCache($$$)
{
    my ($hash, $number, $txt) = @_;
    my $name = $hash->{NAME};
    my $file = AttrVal($name, "reverse-search-cache-file", "");
    my $err;
    my @cachefile;
    my $phonebook_file;
    
    $file =~ s/(^\s+|\s+$)//g;
  
    $hash->{helper}{CACHE}{$number} = $txt;
  
    if($file ne "")
    {
        Log3 $name, 4, "FB_CALLMONITOR ($name) - opening cache file $file for writing $number ($txt)";
        
        foreach my $key (keys %{$hash->{helper}{CACHE}})
        {
            push @cachefile, "$key|".$hash->{helper}{CACHE}{$key};
        }
        
        $err = FileWrite($file,@cachefile);
        
        if(defined($err) && $err)
        {
            Log3 $name, 2, "FB_CALLMONITOR ($name) - could not write cache file: $err";
        }
    }
}

#####################################
# reads a FritzBox phonebook
sub FB_CALLMONITOR_readPhonebook($;$)
{
    my ($hash, $testPassword) = @_;
   
    my $name = $hash->{NAME};
    my ($err, $count_contacts, @lines, $phonebook);
    
	if(AttrVal($name, "fritzbox-remote-phonebook", "0") eq "1")
    {
        if(AttrVal($name, "fritzbox-remote-phonebook-via", "web") eq "telnet")
        {
            ($err, $phonebook) = FB_CALLMONITOR_readRemotePhonebookViaTelnet($hash, $testPassword);
            
            if(defined($err))
            {
                Log3 $name, 2, "FB_CALLMONITOR ($name) - could not read remote FritzBox phonebook file - $err";
                return "Could not read remote FritzBox phonebook file - $err";	
            }
            
            Log3 $name, 2, "FB_CALLMONITOR ($name) - found remote FritzBox phonebook via telnet";
            
            ($err, $count_contacts) = FB_CALLMONITOR_parsePhonebook($hash, $phonebook);
            
            if(defined($err))
            {
                Log3 $name, 2, "FB_CALLMONITOR ($name) - could not parse remote phonebook - $err";
                return "Could not parse remote phonebook - $err";
            }
            else
            {
                Log3 $name, 2, "FB_CALLMONITOR ($name) - read $count_contacts contact".($count_contacts == 1 ? "" : "s")." from remote phonebook via telnet";
            }
        }
        elsif(AttrVal($name, "fritzbox-remote-phonebook-via", "web") eq "web")
        {
            $err = FB_CALLMONITOR_identifyPhoneBooksViaWeb($hash, $testPassword);
            
            if(defined($err))
            {
                Log3 $name, 2, "FB_CALLMONITOR ($name) - could not identify remote phonebooks - $err";
                return "could not identify remote phonebooks - $err";
            }
            
            unless(exists($hash->{helper}{PHONEBOOK_NAMES}))
            {
                Log3 $name, 2, "FB_CALLMONITOR ($name) - no phonebooks could be found";
                return "no phonebooks could be found";
            }
            
            my %excludedIds = map { trim($_) => 1 } split(",",AttrVal($name, "fritzbox-remote-phonebook-exclude", ""));
            
            foreach my $phonebookId (sort keys %{$hash->{helper}{PHONEBOOK_NAMES}})
            {
                if(exists($excludedIds{$phonebookId}))
                {
                    Log3 $name, 4, "FB_CALLMONITOR ($name) - skipping excluded phonebook id $phonebookId (".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}.")";
                    next;
                }
            
                Log3 $name, 4, "FB_CALLMONITOR ($name) - requesting phonebook id $phonebookId (".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}.")";
                
                ($err, $phonebook) = FB_CALLMONITOR_readRemotePhonebookViaWeb($hash, $phonebookId, $testPassword);
                
                if(defined($err))
                {
                        Log3 $name, 2, "FB_CALLMONITOR ($name) - unable to retrieve phonebook \"".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}."\" from FritzBox - $err";
                        return "unable to retrieve phonebook \"".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}."\" from FritzBox - $err";
                }
                else
                {
                    ($err, $count_contacts) = FB_CALLMONITOR_parsePhonebook($hash, $phonebook);
 
                    if(defined($err))
                    {
                        Log3 $name, 2, "FB_CALLMONITOR ($name) - could not parse remote phonebook ".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}." - $err";
                        return "could not parse remote phonebook ".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}." - $err";
                    }
                    else
                    {
                        Log3 $name, 2, "FB_CALLMONITOR ($name) - read $count_contacts contact".($count_contacts == 1 ? "" : "s")." from remote phonebook \"".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}."\"";
                    }
                }
            }
        }
	}
    else
    {
        Log3 $name, 4, "FB_CALLMONITOR ($name) - skipping remote phonebook";
    }
    
    if(-e "/usr/bin/ctlmgr_ctl" or ((not -e "/usr/bin/ctlmgr_ctl") and defined(AttrVal($name, "reverse-search-phonebook-file", undef))))
    {
		my $phonebook_file = AttrVal($name, "reverse-search-phonebook-file", "/var/flash/phonebook");
		
        ($err, @lines) = FileRead($phonebook_file); 
        
        if(defined($err) && $err)
        {
            Log3 $name, 2, "FB_CALLMONITOR ($name) - could not read FritzBox phonebook file - $err";
            return "Could not read FritzBox phonebook file - $err";
        }
       
        $phonebook = join("", @lines);	
        
        Log3 $name, 2, "FB_CALLMONITOR ($name) - found FritzBox phonebook $phonebook_file";
        
        ($err, $count_contacts) = FB_CALLMONITOR_parsePhonebook($hash, $phonebook);
        
        if(defined($err))
        {
            Log3 $name, 2, "FB_CALLMONITOR ($name) - could not parse $phonebook_file  - $err";
            return "Could not parse $phonebook_file - $err";
        }
        else
        {
            Log3 $name, 2, "FB_CALLMONITOR ($name) - read $count_contacts contact".($count_contacts == 1 ? "" : "s")." from $phonebook_file";
        }
	} 
    else
    {
        Log3 $name, 4, "FB_CALLMONITOR ($name) - skipping local phonebook file";
    }
}


#####################################
# reads the FritzBox phonebook file and parses the entries
sub FB_CALLMONITOR_parsePhonebook($$)
{

    my ($hash, $phonebook) = @_;
    my $name = $hash->{NAME};
    my $contact;
    my $contact_name;
    my $number;
    my $count_contacts = 0;

    my $area_code = AttrVal($name, "local-area-code", "");
    my $country_code = AttrVal($name, "country-code", "0049");
    if($phonebook =~ /<contact/ and $phonebook =~ /<realName>/ and $phonebook =~ /<number/ and $phonebook =~ /<phonebook/ and $phonebook =~ /<\/phonebook>/) 
    {
    
        while($phonebook =~ m/<contact[^>]*>(.+?)<\/contact>/gs) 
        {
            $contact = $1;
             
            if($contact =~ m/<realName>(.+?)<\/realName>/) 
            {
                $contact_name = $1; 
                
                while($contact =~ m/<number[^>]*?type="([^<>"]+?)"[^<>]*?>([^<>"]+?)<\/number>/gs) 
                {
                    if($1 ne "intern" and $1 ne "memo") 
                    {
                        $number = $2;
                        $number =~ s/\s//g;			                # Remove spaces
                        $number =~ s/^\+/00/g;			            # Convert leading + to 00 country extension
                        $number =~ s/^$country_code/0/g;            # Replace own country code with leading 0
                        $number =~ s/^(\#[0-9]{1,10}\#)//g;	        # Remove phone control codes
                        $number =~ s/\D//g if(not $number =~ /@/);	# Remove anything else isn't a number if it is no VoIP number

                        if(not $number =~ /^0/ and not $number =~ /@/ and $area_code =~ /^0[1-9]\d+$/) 
                        {
                                $number = $area_code.$number;
                        }     
                        
                        $count_contacts++;
                        Log3 $name, 4, "FB_CALLMONITOR ($name) - found $contact_name with number $number";
                        $hash->{helper}{PHONEBOOK}{$number} = FB_CALLMONITOR_html2txt($contact_name) if(not defined($hash->{helper}{PHONEBOOK}{$number}));
                        undef $number;
                    }
                }
                undef $contact_name;
            }
        }
        
        undef $phonebook;
 
        return (undef, $count_contacts);
    }
    else
    {
        return "this is not a FritzBox phonebook";
    }
}

#####################################
# loads the reverse search cache from file
sub FB_CALLMONITOR_loadCacheFile($;$)
{
    my ($hash, $file) = @_;

    my @cachefile;
    my @tmpline;
    my $count_contacts;
    my $name = $hash->{NAME};
    my $err;
    $file = AttrVal($hash->{NAME}, "reverse-search-cache-file", "") unless(defined($file));
    $file =~ s/(^\s+|\s+$)//g;

    if($file ne "" and -r $file)
    { 
        delete($hash->{helper}{CACHE}) if(defined($hash->{helper}{CACHE}));
  
        Log3 $hash->{NAME}, 3, "FB_CALLMONITOR ($name) - loading cache file $file";
        
        ($err, @cachefile) = FileRead($file);
        
        unless(defined($err) and $err)
        {      
            foreach my $line (@cachefile)
            {
                if(not $line =~ /^\s*$/)
                {
                    $line =~ s/\n//g;
                    @tmpline = split("\\|", $line);
                    
                    if(@tmpline == 2)
                    {
                        $hash->{helper}{CACHE}{$tmpline[0]} = $tmpline[1];
                    }
                }
            }

            $count_contacts = scalar keys %{$hash->{helper}{CACHE}};
            Log3 $name, 2, "FB_CALLMONITOR ($name) - read ".($count_contacts > 0 ? $count_contacts : "no")." contact".($count_contacts == 1 ? "" : "s")." from Cache"; 
        }
        else
        {
            Log3 $name, 3, "FB_CALLMONITOR ($name) - could not open cache file: $err";
        }
    }
}

#####################################
# loads phonebook from extern FritzBox
sub FB_CALLMONITOR_readRemotePhonebookViaTelnet($;$)
{
    my ($hash, $testPassword) = @_;

    my $name = $hash->{NAME};

    my $rc = eval {
        require Net::Telnet;
        Net::Telnet->import();
        1;
    };

    unless($rc)
    {
        return "Error loading Net::Telnet. May be this module is not installed.";
    }
    
    my $phonebook_file = "/var/flash/phonebook";
    
    my ($fb_ip,undef) = split(/:/, ($hash->{DeviceName}), 2);
    
    $hash->{helper}{READ_PWD} = 1;
    
    my $fb_user = AttrVal($name, "fritzbox-user", undef);
    my $fb_pw = FB_CALLMONITOR_readPassword($hash, $testPassword);
    
    delete($hash->{helper}{READ_PWD}) if(exists($hash->{helper}{READ_PWD}));
    return "no password available to access FritzBox" unless(defined($fb_pw));
    
    my $telnet = new Net::Telnet ( Timeout=>10, Errmode=>'return');
    
    unless($telnet->open($fb_ip))
    {
        return "Error Connecting to FritzBox: ".$telnet->errmsg;
    }
    
    Log3 $name, 4, "FB_CALLMONITOR ($name) - connected to FritzBox via telnet";
    
    my ($prematch, $match) = $telnet->waitfor('/(?:login|user|password):\s*$/i');
    
    unless(defined($prematch) and defined($match)) 
    {
        $telnet->close;
        return "Couldn't recognize login prompt: ".$telnet->errmsg;
    }
    
    if($match =~ /(login|user):/i and defined($fb_user))
    {
        Log3 $name, 4, "FB_CALLMONITOR ($name) - setting user to FritzBox: $fb_user";
        $telnet->print($fb_user);
        unless($telnet->waitfor('/password:\s*$/i'))
        {
            $telnet->close;
            return "Error giving password to FritzBox: ".$telnet->errmsg;
        } 
        
        Log3 $name, 4, "FB_CALLMONITOR ($name) - giving password to FritzBox";
        $telnet->print($fb_pw);  
    }
    elsif($match =~ /(login|user):/i and not defined($fb_user))
    {
        $telnet->close;
        return "FritzBox needs a username to login via telnet. Please provide a valid username/password combination";
    }
    elsif($match =~ /password:/i)
    {
        Log3 $name, 4, "FB_CALLMONITOR ($name) - giving password to FritzBox";
        $telnet->print($fb_pw);
    }
    
    unless($telnet->waitfor('/#\s*$/')) 
    {
        $telnet->close;
        my $err = $telnet->errmsg;
        $hash->{helper}{PWD_NEEDED} = 1;
        return "wrong password, please provide the right password" if($err =~ /\s*eof/i);
        return "Could'nt recognize shell prompt: $err";
    }
    
    Log3 $name, 4, "FB_CALLMONITOR ($name) - requesting $phonebook_file via telnet";
    
    my $command = "cat ".$phonebook_file;
  
    my @FBPhoneBook = $telnet->cmd($command);

    unless(@FBPhoneBook)
    {
        $telnet->close;
    	return "Error getting phonebook FritzBox: ".$telnet->errmsg;
    } 
    else 
    {
    	Log3 $name, 3, "FB_CALLMONITOR ($name) - Getting phonebook from FritzBox: $phonebook_file";
    }

    $telnet->print('exit');
    $telnet->close;
    
    delete($hash->{helper}{PWD_NEEDED}) if(exists($hash->{helper}{PWD_NEEDED}));
    
    return (undef, join('', @FBPhoneBook));
}

#####################################
# identifys the phonebooks defined on the FritzBox via web interface (http)
sub FB_CALLMONITOR_identifyPhoneBooksViaWeb($;$)
{
    my ($hash, $testPassword) = @_;
    my $name = $hash->{NAME};

    my ($fb_ip,undef) = split(/:/, ($hash->{DeviceName}), 2);
    my $fb_user = AttrVal($name, "fritzbox-user", undef);
    my $fb_pw;
    my $fb_sid;

    $hash->{helper}{READ_PWD} = 1;
    $fb_pw = FB_CALLMONITOR_readPassword($hash, $testPassword);
    delete($hash->{helper}{READ_PWD}) if(exists($hash->{helper}{READ_PWD}));

    return "no password available to access FritzBox" unless(defined($fb_pw));

    $fb_sid = FB_doCheckPW($fb_ip, $fb_user, $fb_pw);
    
    unless(defined($fb_sid))
    {
        $hash->{helper}{PWD_NEEDED} = 1;
        return "unable to login via webinterface, maybe wrong user/password?" 
    }
    
    Log3 $name, 4, "FB_CALLMONITOR ($name) - identifying available phonebooks";

    my $param;
    $param->{url}        = "http://$fb_ip/fon_num/fonbook_select.lua?sid=$fb_sid";
    $param->{noshutdown} = 1;
    $param->{timeout}    = AttrVal($name, "fritzbox-remote-timeout", 5);
    $param->{loglevel}   = 4;

    my ($err, $data)    = HttpUtils_BlockingGet($param);

    if ($err ne "")
    {
        Log3 $name, 3, "FB_CALLMONITOR ($name) - error while requesting phonebooks: $err";
        return "error while requesting phonebooks: $err";
    }

    if($data eq "" and exists($param->{code}))
    {
        Log3 $name, 3, "FB_CALLMONITOR ($name) - received http code ".$param->{code}." without any data after requesting available phonebooks";
        return  "received no data after requesting available phonebooks";
    }

    Log3 $name, 4, "FB_CALLMONITOR ($name) - phonebooks successfully identified";
    
    if($data =~ m/<form[^>]*name="mainform"[^>]*>(.+?)<\/form>/s)
    {
        $data = $1;
    }

    delete($hash->{helper}{PHONEBOOK_NAMES}) if(exists($hash->{helper}{PHONEBOOK_NAMES}));
    
    while($data =~ /<label[^>]*for="uiBookid:(\d+)"[^>]*>\s*(.+?)\s*<\/label>/gcs)
    {
        $hash->{helper}{PHONEBOOK_NAMES}{$1} = $2;
        Log3 $name, 4, "FB_CALLMONITOR ($name) - found phonebook: $2";
    }
    
    Log3 $name, 3, "FB_CALLMONITOR ($name) - phonebooks found: ".join(", ", map { $hash->{helper}{PHONEBOOK_NAMES}{$_}." (id: $_)" } sort keys %{$hash->{helper}{PHONEBOOK_NAMES}}) if(exists($hash->{helper}{PHONEBOOK_NAMES}));

    delete($hash->{helper}{PWD_NEEDED}) if(exists($hash->{helper}{PWD_NEEDED}));

    return undef;
}
#####################################
# loads internal and online phonebooks from extern FritzBox via web interface (http)
sub FB_CALLMONITOR_readRemotePhonebookViaWeb($$;$)
{
    my ($hash, $phonebookId, $testPassword) = @_;
    my $name = $hash->{NAME};

    my ($fb_ip,undef) = split(/:/, ($hash->{DeviceName}), 2);
    my $fb_user = AttrVal($name, "fritzbox-user", '');
    my $fb_pw;
    my $fb_sid;
    
    return "unknown phonebook id: $phonebookId" unless(exists($hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}));
    
    $hash->{helper}{READ_PWD} = 1;

    $fb_pw = FB_CALLMONITOR_readPassword($hash, $testPassword);
    delete($hash->{helper}{READ_PWD}) if(exists($hash->{helper}{READ_PWD}));
    
    return "no password available to access FritzBox" unless(defined($fb_pw));
   
    $fb_sid = FB_doCheckPW($fb_ip, $fb_user, $fb_pw);
    
    unless(defined($fb_sid))
    {
        $hash->{helper}{PWD_NEEDED} = 1;
        return "no session id available to access FritzBox. Maybe wrong user/password?" 
    }
    
    my $param;
    $param->{url}        = "http://$fb_ip/cgi-bin/firmwarecfg";
    $param->{noshutdown} = 1;
    $param->{timeout}    = AttrVal($name, "fritzbox-remote-timeout", 5);
    $param->{loglevel}   = 4;
    $param->{method}     = "POST";
    $param->{header}     = "Content-Type: multipart/form-data; boundary=boundary";
    
    $param->{data} = "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"sid\"\r\n".
                     "\r\n".
                     "$fb_sid\r\n".
                     "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"PhonebookId\"\r\n".
                     "\r\n".
                     "$phonebookId\r\n".
                     "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"PhonebookExportName\"\r\n".
                     "\r\n".
                     $hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}."\r\n".
                     "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"PhonebookExport\"\r\n".
                     "\r\n".
                     "\r\n".
                     "--boundary--";
                     
    Log3 $name, 4, "FB_CALLMONITOR ($name) - get export for phonebook: $phonebookId";             
    
    my ($err, $phonebook) = HttpUtils_BlockingGet($param);
    
    Log3 $name, 5, "FB_CALLMONITOR ($name) - received http response code ".$param->{code} if(exists($param->{code}));
    
    if ($err ne "") 
    {
        Log3 $name, 3, "FB_CALLMONITOR ($name) - got error while requesting phonebook: $err";
        return "got error while requesting phonebook: $err";
    }

    if($phonebook eq "" and exists($param->{code}))
    {
        Log3 $name, 3, "FB_CALLMONITOR ($name) - received http code ".$param->{code}." without any data";
        return  "received http code ".$param->{code}." without any data";
    }

    delete($hash->{helper}{PWD_NEEDED}) if(exists($hash->{helper}{PWD_NEEDED}));

    return (undef, $phonebook); 
    
}
#####################################
# checks and store FritzBox password used for telnet connection
sub FB_CALLMONITOR_storePassword($$)
{
    my ($hash, $password) = @_;
     
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;
    
    my $enc_pwd = "";
    
    if(eval "use Digest::MD5;1")
    {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }
    
    for my $char (split //, $password)
    {
        my $encode=chop($key);
        $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }
    
    my $err = FB_CALLMONITOR_readPhonebook($hash, $enc_pwd);
    
    return "unable to check password - $err" if(defined($err));
        
    $err = setKeyValue($index, $enc_pwd);
    
    return "error while saving the password - $err" if(defined($err));
    
    return "password successfully saved";
}
    
#####################################
# reads the FritzBox password
sub FB_CALLMONITOR_readPassword($;$)
{
    my ($hash, $testPassword) = @_;
    my $name = $hash->{NAME};
    
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;
    
    my ($password, $err);
    
    if(defined($testPassword))
    {
        $password = $testPassword;
    }
    else
    { 
        ($err, $password) = getKeyValue($index);
        
        if(defined($err))
        {
           $hash->{helper}{PWD_NEEDED} = 1;
           Log3 $name, 4, "FB_CALLMONITOR ($name) - unable to read FritzBox password from file: $err";
           return undef;
        }  
    } 
    
    if(defined($password))
    {
        if(eval "use Digest::MD5;1")
        {
            $key = Digest::MD5::md5_hex(unpack "H*", $key);
            $key .= Digest::MD5::md5_hex($key);
        }

        my $dec_pwd = '';
        
        for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g))
        {
            my $decode=chop($key);
            $dec_pwd.=chr(ord($char)^ord($decode));
            $key=$decode.$key;
        }
        
        return $dec_pwd if($hash->{helper}{READ_PWD});
    }
    else
    {
        $hash->{helper}{PWD_NEEDED} = 1;
        
        return undef;
    }
}

1;

=pod
=begin html

<a name="FB_CALLMONITOR"></a>
<h3>FB_CALLMONITOR</h3>
<ul>
  <tr><td>
  The FB_CALLMONITOR module connects to a AVM FritzBox Fon and listens for telephone
  <a href="#FB_CALLMONITORevents">events</a> (Receiving incoming call, Making a call)
  <br><br>
  In order to use this module with fhem you <b>must</b> enable the Callmonitor feature via 
  telephone shortcode.<br><br>
  <ul>
      <code>#96*5* - for activating<br>#96*4* - for deactivating</code>
  </ul>
  
  <br>
  Just dial the shortcode for activating on one of your phones, after 3 seconds just hang up. The feature is now activated.
  <br><br>
  After activating the Callmonitor-Support in your FritzBox, this module is able to 
  generate an event for each external call. Internal calls were not be detected by the Callmonitor.
  <br><br>
  This module work with any FritzBox Fon model.
  <br><br>
  
  <a name="FB_CALLMONITORdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FB_CALLMONITOR &lt;ip-address&gt;[:port]</code><br>
    <br>
    port is 1012 by default.
    <br>
  </ul>
  <br>
  <a name="FB_CALLMONITORset"></a>
  <b>Set</b>
  <ul>
  <li><b>rereadPhonebook</b> - Reloads the FritzBox phonebook (from given file, via telnet or directly if available)</li>
  <li><b>password</b> - set the FritzBox password (only available when password is really needed for network access to FritzBox phonebook, see attribute <a href="#fritzbox-remote-phonebook">fritzbox-remote-phonebook</a>)</li>
  </ul>
  <br>

  <a name="FB_CALLMONITORget"></a>
  <b>Get</b>
  <ul>
  <li><b>search &lt;phone-number&gt;</b> - returns the name of the given number via reverse-search (internal phonebook, cache or internet lookup)</li>
  <li><b>showPhonebookIds</b> - returns a list of all available phonebooks on the FritzBox (not available when using telnet to retrieve remote phonebook)</li>
  <li><b>showPhonebookEntries</b> - returns a list of all currently known phonebook entries (only available when using phonebook funktionality)</li>
  <li><b>showCacheEntries</b> - returns a list of all currently known cache entries (only available when using reverse search caching funktionality)</li>
  </ul>
  <br>

  <a name="FB_CALLMONITORattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="disable">disable</a></li>
	Optional attribute to disable the Callmonitor. When disabled, no phone events can be detected.
	<br><br>
	Possible values: 0 => Callmonitor is activated, 1 => Callmonitor is deactivated.<br>
    Default Value is 0 (activated)<br><br>
    <li><a name="reverse-search">reverse-search</a> (phonebook,klicktel.de,dasoertliche.de,search.ch,dasschnelle.at)</li>
    Enables the reverse searching of the external number (at dial and call receiving).
    This attribute contains a comma separated list of providers which should be used to reverse search a name to a specific phone number. The phonebook (and cache) will always use first, afterwards all web providers.
    It is possible to select a specific web service, which should be used for reverse searching.
    <br><br>per default, reverse search is disabled.<br><br>
    <li><a name="reverse-search-cache">reverse-search-cache</a></li>
    If this attribute is activated each reverse-search result is saved in an internal cache
    and will be used instead of reverse searching every time the same number.<br><br>
    Possible values: 0 => off , 1 => on<br>
    Default Value is 0 (off)<br><br>
    <li><a name="reverse-search-cache-file">reverse-search-cache-file</a> &lt;file&gt;</li>
    Write the internal reverse-search-cache to the given file and use it next time FHEM starts.
    So all reverse search results are persistent written to disk and will be used instantly after FHEM starts.<br><br>
    <li><a name="reverse-search-phonebook-file">reverse-search-phonebook-file</a> &lt;file&gt;</li>
    This attribute can be used to specify the (full) path to a phonebook file in FritzBox format (XML structure). Using this option it is possible to use the phonebook of a FritzBox even without FHEM running on a Fritzbox.
    The phonebook file can be obtained by an export via FritzBox web UI<br><br>
    Default value is /var/flash/phonebook (phonebook filepath on FritzBox)<br><br>
    <li><a name="remove-leading-zero">remove-leading-zero</a></li>
    If this attribute is activated, a leading zero will be removed from the external number (e.g. in telefon systems).<br><br>
    Possible values: 0 => off , 1 => on<br>
    Default Value is 0 (off)<br><br>
    <li><a name="unique-call-ids">unique-call-ids</a></li>
    If this attribute is activated, each call will use a biunique call id. So each call can be separated from previous calls in the past.<br><br>
    Possible values: 0 => off , 1 => on<br>
    Default Value is 0 (off)<br><br>
    <li><a name="local-area-code">local-area-code</a></li>
    Use the given local area code for reverse search in case of a local call (e.g. 0228 for Bonn, Germany)<br><br>
    <li><a name="country-code">country-code</a></li>
    Your local country code. This is needed to identify phonenumbers in your phonebook with your local country code as a national phone number instead of an international one (e.g. 0049 for Germany, 0043 for Austria or 001 for USA)<br><br>
    Default Value is 0049 (Germany)<br><br>
    <li><a name="fritzbox-remote-phonebook">fritzbox-remote-phonebook</a></li>
    If this attribute is activated, the phonebook should be obtained direct from the FritzBox via remote network connection (in case FHEM is not running on a FritzBox). This is only possible if a password (and depending on configuration a username as well) is configured.<br><br>
    Possible values: 0 => off , 1 => on (use remote telnet connection to obtain FritzBox phonebook)<br>
    Default Value is 0 (off)<br><br>
    <li><a name="fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-via</a></li>
    Set the method how the phonebook should be requested via network. When set to "web", the phonebook is obtained from the web interface via HTTP. When set to "telnet", it uses a telnet connection to login and retrieve the phonebook (telnet must be activated via dial shortcode #96*7*)<br><br>
    Possible values: web,telnet<br>
    Default Value is web (retrieve phonebooks via web interface)<br><br>
    <li><a name="fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-exclude</a></li>
    A comma separated list of phonebook id's which should be excluded when retrieving all possible phonebooks via web method (see attribute <i>fritzbox-remote-phonebook-via</i>). All list possible values is provided by <a href="#FB_CALLMONITORget">get command</a> <i>showPhonebookIds</i>. This attribute is not applicable when using telnet method to obtain remote phonebook.<br><br>
    Default Value: <i>empty</i> (all phonebooks should be used, no exclusions)<br><br>
    <li><a name="fritzbox-user">fritzbox-user</a></li>
    Use the given user for remote connect to obtain the phonebook. This attribute is only needed, if you use multiple users on your FritzBox.<br><br>
    </ul>
  <br>
 
  <a name="FB_CALLMONITORevents"></a>
  <b>Generated Events:</b><br><br>
  <ul>
  <li><b>event</b> (call|ring|connect|disconnect) - which event in detail was triggerd</li>
  <li><b>direction</b> (incoming|outgoing) - the call direction in general (incoming or outgoing call)</li>
  <li><b>external_number</b> - The participants number which is calling (event: ring) or beeing called (event: call)</li>
  <li><b>external_name</b> - The result of the reverse lookup of the external_number via internet. Is only available if reverse-search is activated. Special values are "unknown" (no search results found) and "timeout" (got timeout while search request). In case of an timeout and activated caching, the number will be searched again next time a call occurs with the same number</li>
  <li><b>internal_number</b> - The internal number (fixed line, VoIP number, ...) on which the participant is calling (event: ring) or is used for calling (event: call)</li>
  <li><b>internal_connection</b> - The internal connection (FON1, FON2, ISDN, DECT, ...) which is used to take or perform the call</li>
  <li><b>external_connection</b> - The external connection (fixed line, VoIP account) which is used to take or perform the call</li>
  <li><b>call_duration</b> - The call duration in seconds. Is only generated at a disconnect event. The value 0 means, the call was not taken by anybody.</li>
  <li><b>call_id</b> - The call identification number to separate events of two or more different calls at the same time. This id number is equal for all events relating to one specific call.</li>
  <li><b>missed_call</b> - This event will be raised in case of a missing incoming call. If available, also the name of the calling number will be displayed.</li>
  <li><b>missed_call_line</b> - Will be raised together with "missed_call". It shows the number of the internal line which received the missed call.</li> 
  </ul>
</ul>


=end html
=begin html_DE

<a name="FB_CALLMONITOR"></a>
<h3>FB_CALLMONITOR</h3>
<ul>
  <tr><td>
  Das Modul FB_CALLMONITOR verbindet sich zu einer AVM FritzBox Fon und verarbeitet
  Telefonie-<a href="#FB_CALLMONITORevents">Ereignisse</a>.(eingehende & ausgehende Telefonate)
  <br><br>
  Um dieses Modul nutzen zu k&ouml;nnen, muss der Callmonitor via Kurzwahl mit einem Telefon aktiviert werden.
 .<br><br>
  <ul>
      <code>#96*5* - Callmonitor aktivieren<br>#96*4* - Callmonitor deaktivieren</code>
  </ul>
  <br>
  Einfach die entsprechende Kurzwahl auf irgend einem Telefon eingeben, welches an die Fritz!Box angeschlossen ist. 
  Nach ca. 3 Sekunden kann man einfach wieder auflegen. Nun ist der Callmonitor aktiviert.
  <br><br>
  Sobald der Callmonitor auf der Fritz!Box aktiviert wurde erzeugt das Modul entsprechende Events (s.u.) f&uuml;r alle externen Anrufe. Interne Anrufe werden nicht durch den Callmonitor erfasst.
  <br><br>
  Dieses Modul funktioniert mit allen Fritz!Box Modellen, welche Telefonie unterst&uuml;tzen (Namenszusatz: Fon).
  <br><br>
  
  <a name="FB_CALLMONITORdefine"></a>
  <b>Definition</b>
  <ul>
    <code>define &lt;name&gt; FB_CALLMONITOR &lt;IP-Addresse&gt;[:Port]</code><br>
    <br>
    Port 1012 ist der Standardport und muss daher nicht explizit angegeben werden.
    <br>
  </ul>
  <br>
  <a name="FB_CALLMONITORset"></a>
  <b>Set-Kommandos</b>
  <ul>
  <li><b>rereadPhonebook</b> - Liest das Telefonbuch der FritzBox neu ein (per Datei, Telnet oder direkt lokal)</li>
  <li><b>password</b> - speichert das FritzBox Passwort, welches f&uuml;r das Einlesen aller Telefonb&uuml;cher direkt von der FritzBox ben&ouml;tigt wird. Dieses Kommando ist nur verf&uuml;gbar, wenn ein Passwort ben&ouml;tigt wird um das Telefonbuch via Netzwerk einzulesen, siehe dazu Attribut <a href="#fritzbox-remote-phonebook">fritzbox-remote-phonebook</a>.</li>
  </ul>
  <br>

  <a name="FB_CALLMONITORget"></a>
  <b>Get-Kommandos</b>
  <ul>
  <li><b>search &lt;Rufnummer&gt;</b> - gibt den Namen der Telefonnummer zur&uuml;ck (aus Cache, Telefonbuch oder R&uuml;ckw&auml;rtssuche)</li>
  <li><b>showPhonebookIds</b> - gibt eine Liste aller verf&uuml;gbaren Telefonb&uuml;cher auf der FritzBox zur&uuml;ck (nicht verf&uuml;gbar wenn das Telefonbuch via Telnet-Verbindung eingelesen wird)</li>
  <li><b>showPhonebookEntries</b> - gibt eine Liste aller bekannten Telefonbucheintr&auml;ge zur&uuml;ck (nur verf&uuml;gbar, wenn eine R&uuml;ckw&auml;rtssuche via Telefonbuch aktiviert ist)</li>
  <li><b>showCacheEntries</b> - gibt eine Liste aller bekannten Cacheeintr&auml;ge zur&uuml;ck (nur verf&uuml;gbar, wenn die Cache-Funktionalit&auml;t der R&uuml;ckw&auml;rtssuche aktiviert ist))</li>
  </ul>
  <br>

  <a name="FB_CALLMONITORattr"></a>
  <b>Attribute</b><br><br>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="disable">disable</a></li>
	Optionales Attribut zur Deaktivierung des Callmonitors. Es k&ouml;nnen dann keine Anruf-Events mehr erkannt und erzeugt werden.
	<br><br>
	M&ouml;gliche Werte: 0 => Callmonitor ist aktiv, 1 => Callmonitor ist deaktiviert.<br>
    Standardwert ist 0 (aktiv)<br><br>
    <li><a name="reverse-search">reverse-search</a> (phonebook,klicktel.de,dasoertliche.de,search.ch,dasschnelle.at)</li>
    Aktiviert die R&uuml;ckw&auml;rtssuche der externen Rufnummer (bei eingehenden/ausgehenden Anrufen).
    Dieses Attribut enth&auml;lt eine komma-separierte Liste mit allen Anbietern die f&uuml;r eine R&uuml;ckw&auml;rtssuche benutzt werden sollen. Das interne Telefonbuch (phonebook) und der Cache (sofern aktiviert) wird dabei immer zuerst benutzt. Falls die Rufnummer dort nicht verzeichnet ist, werden externe Suchanbieter verwendet.
    Es ist m&ouml;glich einen bestimmten Suchanbieter zu verwenden, welcher f&uuml;r die R&uuml;ckw&auml;rtssuche verwendet werden soll.
    Der Wert "phonebook" verwendet ausschlie&szlig;lich das interne Telefonbuch der FritzBox (siehe Attribut reverse-search-phonebook-file)<br><br>
    Standardm&auml;&szlig;ig ist diese Funktion deaktiviert (nicht gesetzt)<br><br>
    <li><a name="reverse-search-cache">reverse-search-cache</a></li>
    Wenn dieses Attribut gesetzt ist, werden alle Ergebisse der R&uuml;ckw&auml;rtssuche in einem modul-internen Cache gespeichert
    und alle existierenden Ergebnisse aus dem Cache genutzt anstatt eine erneute R&uuml;ckw&auml;rtssuche durchzuf&uuml;hren.<br><br>
    M&ouml;gliche Werte: 0 => deaktiviert , 1 => aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>
    <li><a name="reverse-search-cache-file">reverse-search-cache-file</a> &lt;Dateipfad&gt;</li>
    Da der Cache nur im Arbeitsspeicher existiert, ist er nicht persistent und geht beim stoppen von FHEM verloren.
    Mit diesem Parameter werden alle Cache-Ergebnisse in eine Textdatei geschrieben (z.B. /usr/share/fhem/telefonbuch.txt) 
    und beim n&auml;chsten Start von FHEM wieder in den Cache geladen und genutzt.
    <br><br>
    <li><a name="reverse-search-phonebook-file">reverse-search-phonebook-file</a> &lt;Dateipfad&gt</li>
    Mit diesem Attribut kann man optional den Pfad zu einer Datei angeben, welche ein Telefonbuch im FritzBox-Format (XML-Struktur) enth&auml;lt.
    Dadurch ist es m&ouml;glich ein FritzBox-Telefonbuch zu verwenden, ohne das FHEM auf einer FritzBox laufen muss.
    Sofern FHEM auf einer FritzBox l&auml;uft (und nichts abweichendes angegeben wurde), wird das interne File /var/flash/phonebook verwendet. Alternativ kann man das Telefonbuch in der FritzBox-Weboberfl&auml;che exportieren und dieses verwenden<br><br>
    Standardwert ist /var/flash/phonebook (entspricht dem Pfad auf einer FritzBox)<br><br>
    <li><a name="remove-leading-zero">remove-leading-zero</a></li>
    Wenn dieses Attribut aktiviert ist, wird die f&uuml;hrende Null aus der externen Rufnummer (bei eingehenden & abgehenden Anrufen) entfernt. Dies ist z.B. notwendig bei Telefonanlagen.<br><br>
    M&ouml;gliche Werte: 0 => deaktiviert , 1 => aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>
    <li><a name="unique-call-ids">unique-call-ids</a></li>
    Wenn dieses Attribut aktiviert ist, wird f&uuml;r jedes Gespr&auml;ch eine eineindeutige Identifizierungsnummer verwendet. Dadurch lassen sich auch bereits beendete Gespr&auml;che voneinander unterscheiden. Dies ist z.B. notwendig bei der Verarbeitung der Events durch eine Datenbank.<br><br>
    M&ouml;gliche Werte: 0 => deaktiviert , 1 => aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>
    <li><a name="local-area-code">local-area-code</a></li>
    Verwendet die gesetze Vorwahlnummer bei R&uuml;ckw&auml;rtssuchen von Ortsgespr&auml;chen (z.B. 0228 f&uuml;r Bonn)<br><br>
    <li><a name="country-code">country-code</a></li>
    Die Landesvorwahl wird ben&ouml;tigt um Telefonbucheintr&auml;ge mit lokaler Landesvorwahl als Inlands-Rufnummern zu erkennen (z.B. 0049 f&uuml;r Deutschland, 0043 f&uuml;r &Ouml;sterreich oder 001 f&uuml;r USA).<br><br>
    Standardwert ist 0049 (Deutschland)<br><br>
    <li><a name="fritzbox-remote-phonebook">fritzbox-remote-phonebook</a></li>
    Wenn dieses Attribut aktiviert ist, wird das FritzBox Telefonbuch direkt von der FritzBox gelesen. Dazu ist das FritzBox Passwort und je nach FritzBox Konfiguration auch ein Username notwendig, der in den entsprechenden Attributen konfiguriert sein muss.<br><br>
    M&ouml;gliche Werte: 0 => deaktiviert , 1 => aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>  
    <li><a name="fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-via</a></li>
    Setzt die Methode mit der das Telefonbuch von der FritzBox abgefragt werden soll. Bei der Methode "web", werden alle verf&uuml;gbaren Telefonb&uuml;cher (lokales sowie alle konfigurierten Online-Telefonb&uuml;cher) &uuml;ber die Web-Oberfl&auml;che eingelesen. Bei der Methode "telnet" wird eine Telnet-Verbindung zur FritzBox aufgebaut um das lokale Telefonbuch abzufragen (keine Online-Telefonb&uuml;cher). Dazu muss die Telnet-Funktion aktiviert sein (Telefon Kurzwahl: #96*7*)<br><br>
    M&ouml;gliche Werte: web,telnet<br>
    Standardwert ist "web" (Abfrage aller verf&uuml;gbaren Telefonb&uuml;cher &uuml;ber die Web-Oberfl&auml;che)<br><br>
    <li><a name="fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-exclude</a></li>
    Eine komma-separierte Liste von Telefonbuch-ID's welche beim einlesen &uuml;bersprungen werden sollen. Dieses Attribut greift nur beim einlesen der Telefonb&uuml;cher via "web"-Methode (siehe Attribut <i>fritzbox-remote-phonebook-via</i>). Eine Liste aller m&ouml;glichen Werte kann &uuml;ber das <a href="#FB_CALLMONITORget">Get-Kommando</a> <i>showPhonebookIds</i> angezeigt werden.<br><br>
    Standardm&auml;&szlig;ig ist diese Funktion deaktiviert (alle Telefonb&uuml;cher werden eingelesen)<br><br>
    <li><a name="fritzbox-user">fritzbox-user</a></li>
    Der Username f&uuml;r das Telnet-Interface, sofern das Telefonbuch direkt von der FritzBox geladen werden soll (Attribut: fritzbox-remote-phonebook). Dieses Attribut ist nur notwendig, wenn mehrere Benutzer auf der FritzBox konfiguriert sind.<br><br>
    </ul>
  <br>
 
  <a name="FB_CALLMONITORevents"></a>
  <b>Generierte Events:</b><br><br>
  <ul>
  <li><b>event</b> (call|ring|connect|disconnect) - Welches Event wurde genau ausgel&ouml;st. ("call" =&gt; ausgehender Rufversuch, "ring" =&gt; eingehender Rufversuch, "connect" =&gt; Gespr&auml;ch ist zustande gekommen, "disconnect" =&gt; es wurde aufgelegt)</li>
  <li><b>direction</b> (incoming|outgoing) - Die Anruf-Richtung ("incoming" =&gt; eingehender Anruf, "outgoing" =&gt; ausgehender Anruf)</li>
  <li><b>external_number</b> - Die Rufnummer des Gegen&uuml;bers, welcher anruft (event: ring) oder angerufen wird (event: call)</li>
  <li><b>external_name</b> - Das Ergebniss der R&uuml;ckw&auml;rtssuche (sofern aktiviert). Im Fehlerfall kann diese Reading auch den Inhalt "unknown" (keinen Eintrag gefunden) oder "timeout" (Zeit&uuml;berschreitung bei der Abfrage) enthalten. Im Falle einer Zeit&uuml;berschreitung und aktiviertem Caching, wird die Rufnummer beim n&auml;chsten Mal erneut gesucht.</li>
  <li><b>internal_number</b> - Die interne Rufnummer (Festnetz, VoIP-Nummer, ...) auf welcher man angerufen wird (event: ring) oder die man gerade nutzt um jemanden anzurufen (event: call)</li>
  <li><b>internal_connection</b> - Der interne Anschluss an der Fritz!Box welcher genutzt wird um das Gespr&auml;ch durchzuf&uuml;hren (FON1, FON2, ISDN, DECT, ...)</li>
  <li><b>external_connection</b> - Der externe Anschluss welcher genutzt wird um das Gespr&auml;ch durchzuf&uuml;hren  (Festnetz, VoIP Nummer, ...)</li>
  <li><b>call_duration</b> - Die Gespr&auml;chsdauer in Sekunden. Dieser Wert wird nur bei einem disconnect-Event erzeugt. Ist der Wert 0, so wurde das Gespr&auml;ch von niemandem angenommen.</li>
  <li><b>call_id</b> - Die Identifizierungsnummer eines einzelnen Gespr&auml;chs. Dient der Zuordnung bei zwei oder mehr parallelen Gespr&auml;chen, damit alle Events eindeutig einem Gespr&auml;ch zugeordnet werden k&ouml;nnen</li>
  <li><b>missed_call</b> - Dieses Event wird nur generiert, wenn ein eingehender Anruf nicht beantwortet wird. Sofern der Name dazu bekannt ist, wird dieser ebenfalls mit angezeigt.</li>
  <li><b>missed_call_line</b> - Analog zu "missed_call" wird dieses Event nur generiert, wenn ein eingehender Anruf nicht beantwortet wird. Es zeigt die Rufnummer an &uuml;ber, den dieser unbeantwortete Anruf eingegangen ist.</li>
  </ul>
</ul>


=end html_DE
=cut
