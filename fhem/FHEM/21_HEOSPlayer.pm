###############################################################################
#
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Olaf Schnicke         Thanks for many many Code
#       - Dieter Hehlgans       Thanks for Commandref
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
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
#
# $Id$
#
###############################################################################

package main;

use strict;
use warnings;
use JSON qw(decode_json);
use Encode qw(encode_utf8);
use URI::Escape;
#use Data::Dumper;

my $version = "1.0.2";




# Declare functions
sub HEOSPlayer_Initialize($);
sub HEOSPlayer_Define($$);
sub HEOSPlayer_Undef($$);
sub HEOSPlayer_Attr(@);
sub HEOSPlayer_Parse($$);
sub HEOSPlayer_WriteReadings($$);
sub HEOSPlayer_Set($$@);
sub HEOSPlayer_PreProcessingReadings($$);
sub HEOSPlayer_GetPlayerInfo($);
sub HEOSPlayer_GetPlayState($);
sub HEOSPlayer_GetQueue($);
sub HEOSPlayer_GetNowPlayingMedia($);
sub HEOSPlayer_GetPlayMode($);
sub HEOSPlayer_GetVolume($);
sub HEOSPlayer_Get($$@);
sub HEOSPlayer_GetMute($);
sub HEOSPlayer_MakePlayLink($$$$$$$$);



sub HEOSPlayer_Initialize($) {
    
    my ($hash) = @_;

    $hash->{Match}          = '.*{"command":."player.*|.*{"command":."event/player.*|.*{"command":."event\/repeat_mode_changed.*|.*{"command":."event\/shuffle_mode_changed.*|.*{"command":."event\/favorites_changed.*';

    
    # Provider
    $hash->{SetFn}          = "HEOSPlayer_Set";
    $hash->{GetFn}          = "HEOSPlayer_Get";
    $hash->{DefFn}          = "HEOSPlayer_Define";
    $hash->{UndefFn}        = "HEOSPlayer_Undef";
    $hash->{AttrFn}         = "HEOSPlayer_Attr";
    $hash->{ParseFn}        = "HEOSPlayer_Parse";
    $hash->{AttrList}       = "IODev ".
                              "disable:1 ".
                              "mute2play:1 ".
                              "channelring:1 ".
                              $readingFnAttributes;

    foreach my $d(sort keys %{$modules{HEOSPlayer}{defptr}}) {
    
        my $hash = $modules{HEOSPlayer}{defptr}{$d};
        $hash->{VERSION}    = $version;
    }
}

sub HEOSPlayer_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t]+", $def );
    splice( @a, 1, 1 );
    my $iodev;
    my $i = 0;

    
    foreach my $param ( @a ) {
        if( $param =~ m/IODev=([^\s]*)/ ) {
        
            $iodev = $1;
            splice( @a, $i, 3 );
            last;
        }
        
        $i++;
    }
    
    return "too few parameters: define <name> HEOSPlayer <pid>" if( @a < 2 );
    
    my ($name,$pid)     = @a;

    $hash->{PID}        = $pid;
    $hash->{VERSION}    = $version;
    AssignIoPort($hash,$iodev) if( !$hash->{IODev} );
    
    if(defined($hash->{IODev}->{NAME})) {
    
        Log3 $name, 3, "HEOSPlayer ($name) - I/O device is " . $hash->{IODev}->{NAME};
    
    } else {
    
        Log3 $name, 1, "HEOSPlayer ($name) - no I/O device";
    }
    
    $iodev = $hash->{IODev}->{NAME};
    my $code = abs($pid);
    
    $code = $iodev."-".$code if( defined($iodev) );
    my $d = $modules{HEOSPlayer}{defptr}{$code};
    
    return "HEOSPlayer device $hash->{pid} on HEOSMaster $iodev already defined as $d->{NAME}."
    if( defined($d) && $d->{IODev} == $hash->{IODev} && $d->{NAME} ne $name );

    Log3 $name, 3, "HEOSPlayer ($name) - defined with Code: $code";
    $attr{$name}{room}          = "HEOS" if( !defined( $attr{$name}{room} ) );
    $attr{$name}{devStateIcon}  = "on:10px-kreis-gruen off:10px-kreis-rot" if( !defined( $attr{$name}{devStateIcon} ) );
    
    if( $init_done ) {
    
        InternalTimer( gettimeofday()+int(rand(2)), "HEOSPlayer_GetPlayerInfo", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(4)), "HEOSPlayer_GetPlayState", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(6)), "HEOSPlayer_GetNowPlayingMedia", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(8)), "HEOSPlayer_GetPlayMode", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(10)), "HEOSPlayer_GetVolume", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(12)), "HEOSPlayer_GetMute", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(14)), "HEOSPlayer_GetQueue", $hash, 0 );
        
   } else {
   
        InternalTimer( gettimeofday()+15+int(rand(2)), "HEOSPlayer_GetPlayerInfo", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(4)), "HEOSPlayer_GetPlayState", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(6)), "HEOSPlayer_GetNowPlayingMedia", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(8)), "HEOSPlayer_GetPlayMode", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(10)), "HEOSPlayer_GetVolume", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(12)), "HEOSPlayer_GetMute", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(14)), "HEOSPlayer_GetQueue", $hash, 0 );
    }
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'state','Initialized');
    readingsBulkUpdate($hash, 'volumeUp', 5);
    readingsBulkUpdate($hash, 'volumeDown', 5);
    readingsEndUpdate($hash, 1);
    
    $modules{HEOSPlayer}{defptr}{$code} = $hash;
    return undef;
}

sub HEOSPlayer_Undef($$) {

    my ( $hash, $arg ) = @_;
    my $pid = $hash->{PID};
    my $name = $hash->{NAME};

    
    RemoveInternalTimer($hash);
    my $code = abs($pid);
    $code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}->{NAME}) );
    delete($modules{HEOSPlayer}{defptr}{$code});
    
    Log3 $name, 3, "HEOSPlayer ($name) - device $name deleted with Code: $code";
    return undef;
}

sub HEOSPlayer_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    my $token = $hash->{IODev}->{TOKEN};

    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
        
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "HEOSPlayer ($name) - disabled";
        
        } elsif( $cmd eq "del" ) {
        
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSPlayer ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
        
            Log3 $name, 3, "HEOSPlayer ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        
        } elsif( $cmd eq "del" ) {
        
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSPlayer ($name) - delete disabledForIntervals";
        }
    }
}

sub HEOSPlayer_Get($$@) {

    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;
    my $pid     = $hash->{PID};
    my $result  = "";
    my $me      = {};
    my $ret;
    
    $me->{cl}   = $hash->{CL} if( ref($hash->{CL}) eq 'HASH' );
    $me->{name} = $hash->{NAME};
    $me->{pid}  = $hash->{PID};

    #Leerzeichen müßen für die Rückgabe escaped werden sonst werden sie falsch angezeigt
    if( $cmd eq 'channelscount' ) {
    
        #gibt die Favoritenanzahl zurück
        return scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
        
    } elsif( $cmd eq 'ls' ) {

        my $param = shift( @args );
        $param = '' if( !$param );

        if ( $param eq '' ) {

            if( $me->{cl}->{TYPE} eq 'FHEMWEB' ) {

                $ret = '<div class="container">';
                $ret .= '<h3 style="text-align: center;">Musik</h3><hr>';
                $ret .= '<div class="list-group">';

            } else {

                $ret = "Musik\n";
                $ret .= sprintf( "%-15s %s\n", 'key', 'title' );

            }

            foreach my $item (@{ $hash->{IODev}{helper}{sources}}) {            
                $ret .= HEOSPlayer_MakePlayLink($me->{cl}->{TYPE}, $hash->{NAME}, $item->{sid}, $item->{type}, $item->{name}, $item->{image_url}, 128, 50);
            }

            $ret .= HEOSPlayer_MakePlayLink($me->{cl}->{TYPE}, $hash->{NAME}, "1025", "heos_service", "Playlist", "https://production.ws.skyegloup.com:443/media/images/service/logos/musicsource_logo_playlists.png", 128, 32);

            $ret .= HEOSPlayer_MakePlayLink($me->{cl}->{TYPE}, $hash->{NAME}, "1026", "heos_service", "Verlauf", "https://production.ws.skyegloup.com:443/media/images/service/logos/musicsource_logo_history.png", 128, 32);

            $ret .= HEOSPlayer_MakePlayLink($me->{cl}->{TYPE}, $hash->{NAME}, "1027", "heos_service", "Eingänge", "https://production.ws.skyegloup.com:443/media/images/service/logos/musicsource_logo_aux.png", 128, 32);

            $ret .= HEOSPlayer_MakePlayLink($me->{cl}->{TYPE}, $hash->{NAME}, "1028", "heos_service", "Favoriten", "https://production.ws.skyegloup.com:443/media/images/service/logos/musicsource_logo_favorites.png", 128, 32);

            $ret .= HEOSPlayer_MakePlayLink($me->{cl}->{TYPE}, $hash->{NAME}, "1029", "heos_service", "Warteschlange", "https://production.ws.skyegloup.com:443/media/images/service/logos/musicsource_logo_playlists.png", 128, 32);


            if( $me->{cl}->{TYPE} eq 'FHEMWEB' ) {

                $ret .= '</div></div>';
                $ret =~ s/&/&amp;/g;
                $ret =~ s/'/&apos;/g;
                $ret =~ s/\n/<br>/g;
                $ret = "<pre>$ret</pre>" if( $ret =~ m/  / );
                $ret = "<html>$ret</html>";
            }
            
            return $ret;

        } else {

            my ($sid,$cid) = split /,/,$param;

            if ( $sid eq "1025" ) {
            
                $me->{sourcename} = "Playlist";
                
            } elsif ( $sid eq "1026" ) {
            
                $me->{sourcename} = "Verlauf";
                
            } elsif ( $sid eq "1027" ) {
            
                $me->{sourcename} = "Eingänge";
                
            } elsif ( $sid eq "1028" ) {
            
                $me->{sourcename} = "Favoriten";
                
            } elsif ( $sid eq "1029" ) {
            
                $me->{sourcename} = "Warteschlange";
                
            } else {
            
                my @sids =  map { $_->{name} } grep { $_->{sid} =~ /$sid/i } (@{ $hash->{IODev}{helper}{sources} });
                $me->{sourcename} = $sids[0] if ( scalar @sids > 0);
            }

            my $heosCmd = "browseSource";
            my $action;

            if ( defined $sid && defined $cid && $cid ne "" ) {
                if ( $sid eq "1027" ) {
                
                    $action = "sid=$cid";

                } elsif ( $sid eq "1026" ) {
                
                    $me->{sourcename} .= "/$cid";
                    $action = "sid=$sid&cid=$cid";
                    
                } else {
                
                    my @cids =  map { $_->{name} } grep { $_->{cid} =~ /\Q$cid\E/i } (@{ $hash->{IODev}{helper}{media} });
                    $me->{sourcename} .= "/".$cids[0] if ( scalar @cids > 0);
                    $action = "sid=$sid&cid=$cid";
                    
                }
                
            } elsif ( defined $sid && $sid eq "1029" ) {

                if( $me->{cl}->{TYPE} eq 'FHEMWEB' ) {
            
                    $ret = '<div class="container">';
                    $ret .= '<h2 style="text-align: center;">'.$hash->{NAME}.'</h2>';
                    $ret .= '<h3 style="text-align: center;">Warteschlange</h3><hr>';

                    $ret .= '<div class="container" style="display: inline-block;width: 50%;"><a href="#" onClick="FW_cmd('."'$FW_ME$FW_subdir?XHR=1&cmd".uri_escape('=set '.$hash->{NAME}.' clearQueue')."')".'" style="cursor:pointer;"><img style="width: 32px; height: 32px;display: block;margin-left: auto;margin-right: auto;" src="'."$FW_ME$FW_subdir".'/images/fhemSVG/recycling.svg"></a></div>';

                    $ret .= '<div class="list-group">';

                } else {

                    $ret .= "Warteschlange von $hash->{NAME} \n";
                    $ret .= sprintf( "%-15s %s\n", 'key', 'title' );
                }

                my $x = 0;
                my $itemtext;
                my $itemkey;

                foreach my $item (@{ $hash->{helper}{queue}}) {

                    $itemtext = $item->{artist};
                    $itemtext .= ( defined $item->{artist} ) ? (", ".$item->{album}) : ($item->{album}) if ( defined $item->{album} );
                    $itemkey = '1029,'.++$x;

                    if( $me->{cl}->{TYPE} eq 'FHEMWEB' ) {
                        my $xcmd = 'cmd'.uri_escape('=set '.$hash->{NAME}.' input '.$itemkey);
                        $xcmd = "FW_cmd('$FW_ME$FW_subdir?XHR=1&$xcmd')";
                        $ret .= '<a href="#" onClick="'.$xcmd.'" class="list-group-item"><h4 class="list-group-item-heading">'.$item->{song}.'</h4><p class="list-group-item-text">'.$itemtext."</p></a>";
                        #$ret .= HEOSPlayer_MakePlayLink($hash->{NAME}, "1029,".++$x, "heos_queue", $item->{song}, $item->{image_url}, 64, 64);   
                    } else {
                        $ret .= sprintf( "%-15s %s\n", $itemkey, $item->{song}.", ".$itemtext )
                    }
                }

                if( $me->{cl}->{TYPE} eq 'FHEMWEB' ) {

                    $ret .= '</div></div>';
                    $ret =~ s/&/&amp;/g;
                    $ret =~ s/'/&apos;/g;
                    $ret =~ s/\n/<br>/g;
                    $ret = "<pre>$ret</pre>" if( $ret =~ m/  / );
                    $ret = "<html>$ret</html>";
                }
                
                asyncOutput( $me->{cl}, $ret );                
                                
            } else {
            
                $action = "sid=$sid";
            }

            IOWrite($hash,$heosCmd,$action,$me);
            Log3 $name, 4, "HEOSPlayer ($name) - IOWrite: $heosCmd $action IODevHash=$hash->{IODev}";
            
            return undef;
        }
    }

    my $list = 'channelscount:noArg ls';

    return "Unknown argument $cmd, choose one of $list";
}

sub HEOSPlayer_Set($$@) {

    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;
    my $pid     = $hash->{PID};
    my $action;
    my $heosCmd;
    my $rvalue;
    my $favoritcount = 1;
    my $qcount = 1;
    my $string = "pid=$pid";

    return undef unless ( ReadingsVal($name, "state", "off") eq "on" );

    if( $cmd eq 'getPlayerInfo' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'getPlayState' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'getPlayMode' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'getNowPlayingMedia' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'repeat' ) {
        my $param = "one|all|off";
        return "usage: $cmd $param" if( @args != 1 || ! grep { $_ =~ /$args[0]/ } split(/\|/, $param) );
        
        $heosCmd    = 'setPlayMode';
        $rvalue     = 'on_'.$args[0];
        $rvalue     = 'off' if($rvalue eq 'on_off'); 
        $action     = "repeat=$rvalue&shuffle=".ReadingsVal($name,'shuffle','off');
        
    } elsif( $cmd eq 'shuffle' ) {
        my $param = "on|off";
        return "usage: $cmd $param" if( @args != 1 || ! grep { $_ =~ /$args[0]/ } split(/\|/, $param) );
        
        $heosCmd    = 'setPlayMode';
        $rvalue     = 'on_'.ReadingsVal($name,'repeat','off');
        $rvalue     = 'off' if($rvalue eq 'on_off');         
        $action     = "repeat=$rvalue&shuffle=$args[0]";
        
    } elsif( $cmd eq 'play' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        
    } elsif( $cmd eq 'stop' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        
    } elsif( $cmd eq 'pause' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        
    } elsif( $cmd eq 'mute' ) {
        my $param = "on|off";
        return "usage: $cmd $param" if( @args != 1 || ! grep { $_ =~ /$args[0]/ } split(/\|/, $param) );
        
        $heosCmd    = 'setMute';
        $action     = "state=$args[0]";
        
    } elsif( $cmd eq 'volume' ) {
        return "usage: $cmd 0-100" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > 100 || $args[0] < 0);
        
        $heosCmd    = 'setVolume';
        $action     = "level=$args[0]";
        
    } elsif( $cmd eq 'volumeUp' ) {
        return "usage: $cmd 0-10" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > 10 || $args[0] < 1);
        
        $heosCmd    = $cmd;
        $action     = "step=$args[0]";
        
    } elsif( $cmd eq 'volumeDown' ) {
        return "usage: $cmd 0-10" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > 10 || $args[0] < 1);
        
        $heosCmd    = $cmd;
        $action     = "step=$args[0]";
        
    } elsif( $cmd eq 'groupWithMember' ) {
        return "usage: $cmd" if( @args != 1 );
        
        foreach ( split('\,', $args[0]) ) {
        
            $string    .= ",$defs{$_}->{PID}" if ( defined $defs{$_} );
            printf "String: $string\n";
        }
        
        $heosCmd    = 'createGroup';
        
    } elsif( $cmd eq 'groupClear' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'createGroup';
        
    } elsif( $cmd eq 'next' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'playNext';
        
    } elsif( $cmd eq 'prev' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'playPrev';
        
    } elsif ( $cmd =~ /channel/ ) {
    
        my $favorit = ReadingsVal($name,"channel", 1);
        
        $favoritcount = scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
        $heosCmd    = 'playPresetStation';
        
        if ( $cmd eq 'channel' ) {
            return "usage: channel 1-$favoritcount" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > $favoritcount || $args[0] < 1);
            
            $action  = "preset=$args[0]";
            
        } elsif( $cmd eq 'channelUp' ) {
            return "usage: $cmd" if( @args != 0 );
            
            ++$favorit;
            if ( $favorit > $favoritcount ) {
                if ( AttrVal($name, 'channelring', 0) == 1 ) {
                
                    $favorit = 1;
                    
                } else {
                
                    $favorit = $favoritcount;
                }
            }

            $action  = "preset=".$favorit;
            
        } elsif( $cmd eq 'channelDown' ) {
            return "usage: $cmd" if( @args != 0 );

            --$favorit;
            if ( $favorit <= 0 ) {
                if ( AttrVal($name, 'channelring', 0) == 1 ) {

                    $favorit = $favoritcount;

                } else {

                    $favorit = 1;
                }
            }

            $action  = "preset=".$favorit;
        }
        
    } elsif ( $cmd =~ /Queue/ ) {

        $heosCmd    = $cmd;
        if ( $cmd eq 'playQueueItem' ) {
                
            $qcount = scalar(@{$hash->{helper}{queue}}) if ( defined $hash->{helper}{queue} );
            return "usage: queue 1-$qcount" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > $qcount || $args[0] < 1);

            $action     = "qid=$args[0]";
          
        } elsif ( $cmd eq 'clearQueue' ) {
            #löscht die Warteschlange
            return "usage: $cmd" if( @args != 0 );
        
            delete $hash->{helper}{queue};
        
        } elsif ( $cmd eq 'saveQueue' ) {
        
            #speichert die aktuelle Warteschlange als Playlist ab
            return "usage: saveQueue" if( @args != 1 );
        
            $action     = "name=$args[0]";
        }

    } elsif ( $cmd =~ /Playlist/ ) {
    
        my $mid;
        my $cid = $args[0];
        my @path = split(",", $args[0]) if ( @args != 0 && $args[0] =~ /,/ );     
        $cid = $path[0] if ( scalar @path > 0); 
        $mid = $path[1] if ( scalar @path > 1); 

        if ( scalar @args != 0 ) {

            if ( $cid !~ /^-*[0-9]+$/ ) {
            
                my @cids =  map { $_->{cid} } grep { $_->{name} =~ /\Q$cid\E/i } (@{ $hash->{IODev}{helper}{playlists} });
                return "usage: $cmd name" if ( scalar @cids <= 0);
                
                $cid = $cids[0];
            }

            if ( $cmd eq 'playPlaylist' ) {

                $heosCmd    = $cmd;
                $action     = "sid=1025&cid=$cid&aid=4";
            
            } elsif ( $cmd eq 'playPlaylistItem' ) {
                return "usage: playPlaylistItem name,nr" if ( scalar @path < 2);

                $heosCmd    = 'playPlaylist';
                $action     = "sid=1025&cid=$cid&mid=$mid&aid=4";

            } elsif ( $cmd eq 'deletePlaylist' ) {
            
                $heosCmd    = $cmd;
                $action     = "cid=$cid";
                $string     = "sid=1025";
            }
            
        } else {
                    
            my @playlists = map { $_->{name} } (@{ $hash->{IODev}{helper}{playlists}});
            return "usage: $cmd name|id".join(",",@playlists);
        }
        
    } elsif( $cmd eq 'aux' ) {
        return "usage: $cmd" if( @args != 0 );

        my $auxname = @{ $hash->{helper}{aux} }[0]->{mid};
        $heosCmd = 'playInput';
        $action  = "input=$auxname";
    
        Log3 $name, 4, "HEOSPlayer ($name) - set aux to $auxname";
        readingsSingleUpdate($hash, "input", $args[0], 1);
        
    } elsif( $cmd eq 'input' ) {
        return "usage: $cmd sid[,cid][,mid]" if( @args != 1 );

        my $param = shift( @args );
        my ($sid,$cid,$mid) = split /,/,$param;
        return "usage: $cmd sid[,cid][,mid]" unless( defined $sid || $sid eq "" );

        if ( $sid eq "1024" ) {
            return "usage: $cmd sid,cid[,mid]" unless( defined($cid) && defined($mid) );
            
            #Server abspielen
            $heosCmd = 'playPlaylist';
            $action  = "sid=$sid&cid=$cid&aid=4";
            $action  = "sid=$sid&cid=$cid&mid=$mid&aid=4" if ( defined($mid) );

        } elsif ( $sid eq "1025" ) {
            return "usage: $cmd sid,cid[,mid]" unless( defined($cid) );

            #Playlist abspielen
            $heosCmd = 'playPlaylist';
            $action  = "sid=$sid&cid=$cid&aid=4";
            $action  = "sid=$sid&cid=$cid&mid=$mid&aid=4" if ( defined($mid) );

        } elsif ( $sid eq "1026" ) {
            return "usage: $cmd sid,cid,mid" unless( defined($cid) );

            #Verlauf abspielen
            if ( $cid eq "TRACKS" ) {

                $heosCmd = 'playPlaylist';
                $action  = "sid=$sid&cid=$cid&aid=4";
                $action  = "sid=$sid&cid=$cid&mid=$mid&aid=4" if ( defined($mid) );

            } elsif ( $cid eq "STATIONS" ) {

                $heosCmd = 'playStream';
                $action  = "sid=$sid&cid=$cid&mid=$mid";
            }

        } elsif ( $sid eq "1027" ) {
            return "usage: $cmd sid,spid,mid" unless( defined($cid) );

            #Eingang abspielen
            $heosCmd = 'playInput';
            $action  = "input=$mid";
            $action  = "spid=$cid&".$action if ( $pid ne $cid );

        } elsif ( $sid eq "1028" ) {
            return "usage: $cmd sid,nr" unless( defined($cid) );

            #Favoriten abspielen
            $heosCmd = 'playPresetStation';
            $action  = "preset=$cid";

        } elsif ( $sid eq "1029" ) {
            return "usage: $cmd sid,qid" unless( defined($cid) );

            #Warteschlange abspielen
            $heosCmd = 'playQueueItem';
            $action  = "qid=$cid";

        } elsif ( $sid eq "url" ) {
        
            #URL abspielen
            $heosCmd = 'playStream';
            #$action  = "url=".substr($param,4);
            $action  = "url=$cid";
            
            #getestet mit "set HEOSPlayer_Name input url,http://sender.eldoradio.de:8000/128.mp3"  ich wollte [cid] nicht nutzen da in einer url ja durchaus mehrere Kommata vorkommen können ob das mit dem substr() so toll ich kann ich leider nicht beurteilen. Auch würde ich bei der $sid ein lc($sid) drum machen aber da es nirgendwo ist :-)
            
        } else {
            if ( $sid > 0 && $sid < 1024 ) {
                return "usage: $cmd sid,cid,mid" unless( defined($cid) && defined($mid) );

                #Radio abspielen
                $heosCmd = 'playStream';
                $action = "sid=$sid&cid=$cid&mid=$mid";

            } else {
                return "usage: $cmd sid,cid[,mid]" unless( defined($cid) );
                
                #Server abspielen
                $heosCmd = 'playPlaylist';
                $action  = "sid=$sid&cid=$cid&aid=4";
                $action  = "sid=$sid&cid=$cid&mid=$mid&aid=4" if ( defined($mid) );

            }
        }
        
    } else {
        
        #### alte get Befehle sollen raus
        #### getPlayerInfo:noArg getPlayState:noArg getNowPlayingMedia:noArg getPlayMode:noArg
        my  $list = "play:noArg stop:noArg pause:noArg mute:on,off volume:slider,0,5,100 volumeUp:slider,0,1,10 volumeDown:slider,0,1,10 repeat:one,all,off shuffle:on,off next:noArg prev:noArg  input";

        my @players = devspec2array("TYPE=HEOSPlayer:FILTER=NAME!=$name");
        $list .= " groupWithMember:multiple-strict," . join( ",", @players ) if ( scalar @players > 0 );
        $list .= " groupClear:noArg" if ( defined($defs{"HEOSGroup".abs($pid)}) && $defs{"HEOSGroup".abs($pid)}->{STATE} eq "on" );

        #Parameterlisten für FHEMWeb zusammen bauen
        my $favoritcount = scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
        if ( defined $favoritcount && $favoritcount > 0) {

            $list .= " channel:slider,1,1,".scalar(@{$hash->{IODev}{helper}{favorites}});
            $list .= " channelUp:noArg channelDown:noArg" if ( $favoritcount > 1)
        }

        if ( defined($hash->{helper}{queue}) && ref($hash->{helper}{queue}) eq "ARRAY" && scalar(@{$hash->{helper}{queue}}) > 0 ) {
        
            $list .= " playQueueItem:slider,1,1,".scalar(@{$hash->{helper}{queue}}) if ( defined $hash->{helper}{queue} );
            $list .= " clearQueue:noArg saveQueue";            
        }

        if ( defined $hash->{IODev}{helper}{playlists} ) {
        
            my @playlists = map { my %n; $n{name} = $_->{name}; $n{name} =~ s/\s+/\&nbsp;/g; $n{name} } (@{ $hash->{IODev}{helper}{playlists}});
            
            $list .= " playPlaylist:".join(",",@playlists) if( scalar @playlists > 0 );
            $list .= " deletePlaylist:".join(",",@playlists) if( scalar @playlists > 0 );
        }

        $list .= " aux:noArg" if ( exists $hash->{helper}{aux} );
        return "Unknown argument $cmd, choose one of $list";
    }

    $string     .= "&$action" if( defined($action));
    IOWrite($hash,"$heosCmd","$string",undef);
    Log3 $name, 4, "HEOSPlayer ($name) - IOWrite: $heosCmd $string IODevHash=$hash->{IODev}";
    return undef;
}

sub HEOSPlayer_Parse($$) {

    my ($io_hash,$json) = @_;
    my $name            = $io_hash->{NAME};
    my $pid;
    my $decode_json;
    my $code;

    
    $decode_json    = decode_json(encode_utf8($json));
    Log3 $name, 4, "HEOSPlayer - ParseFn wurde aufgerufen";
    if( defined($decode_json->{pid}) ) {
    
        $pid            = $decode_json->{pid};
        $code           = abs($pid);
        $code           = $io_hash->{NAME} ."-". $code if( defined($io_hash->{NAME}) );
    
        if( my $hash    = $modules{HEOSPlayer}{defptr}{$code} ) {
        
            IOWrite($hash,'getPlayerInfo',"pid=$hash->{PID}",undef);
            readingsSingleUpdate( $hash, "state", "on", 1 );
            Log3 $hash->{NAME}, 4, "HEOSPlayer ($hash->{NAME}) - find logical device: $hash->{NAME}";
            Log3 $hash->{NAME}, 4, "HEOSPlayer ($hash->{NAME}) - find PID in root from decode_json";
            return $hash->{NAME};
            
        } else {
        
            my $devname = "HEOSPlayer".abs($pid);
            return "UNDEFINED $devname HEOSPlayer $pid IODev=$name";
        }
        
    } else {
    
        my %message  = map { my ( $key, $value ) = split "="; $key => $value } split('&', $decode_json->{heos}{message});

        $pid = $message{pid} if( defined($message{pid}) );
        $pid = $decode_json->{payload}{pid} if( ref($decode_json->{payload}) ne "ARRAY" && defined($decode_json->{payload}{pid}) );
         
        Log3 $name, 4, "HEOSPlayer ($name) PID: $pid";
        
        $code           = abs($pid);
        $code           = $io_hash->{NAME} ."-". $code if( defined($io_hash->{NAME}) );
        
        if( my $hash    = $modules{HEOSPlayer}{defptr}{$code} ) {        
            my $name    = $hash->{NAME};
                        
            HEOSPlayer_WriteReadings($hash,$decode_json);
            Log3 $name, 4, "HEOSPlayer ($name) - find logical device: $hash->{NAME}";
                        
            return $hash->{NAME};
            
        } else {
        
            my $devname = "HEOSPlayer".abs($pid);
            return "UNDEFINED $devname HEOSPlayer $pid IODev=$name";
        }
    }
}

sub HEOSPlayer_WriteReadings($$) {
    
    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};

    
    Log3 $name, 4, "HEOSPlayer ($name) - processing data to write readings";
    ############################
    #### Aufbereiten der Daten soweit nötig (bei Events zum Beispiel)
    my $readingsHash    = HEOSPlayer_PreProcessingReadings($hash,$decode_json)
    if( $decode_json->{heos}{message} =~ /^pid=/ and $decode_json->{heos}{command} ne "player\/get_now_playing_media");

    ############################
    #### schreiben der Readings
    readingsBeginUpdate($hash);
    ### Event Readings
    if( ref($readingsHash) eq "HASH" ) {
    
        Log3 $name, 4, "HEOSPlayer ($name) - response json Hash back from HEOSPlayer_PreProcessingReadings";
        my $t;
        my $v;
    
        while( ( $t, $v ) = each (%{$readingsHash}) ) {
            readingsBulkUpdate( $hash, $t, $v ) if( defined( $v ) );
        }
    }

    ### PlayerInfos
    readingsBulkUpdate( $hash, 'name', $decode_json->{payload}{name} );
    readingsBulkUpdate( $hash, 'gid', $decode_json->{payload}{gid} );
    readingsBulkUpdate( $hash, 'model', $decode_json->{payload}{model} );
    readingsBulkUpdate( $hash, 'version', $decode_json->{payload}{version} );
    readingsBulkUpdate( $hash, 'network', $decode_json->{payload}{network} );
    readingsBulkUpdate( $hash, 'lineout', $decode_json->{payload}{lineout} );
    readingsBulkUpdate( $hash, 'control', $decode_json->{payload}{control} );
    readingsBulkUpdate( $hash, 'ip-address', $decode_json->{payload}{ip} );

    ### playing Infos
    readingsBulkUpdate( $hash, 'currentMedia', $decode_json->{payload}{type} );
    readingsBulkUpdate( $hash, 'currentTitle', $decode_json->{payload}{song} );
    readingsBulkUpdate( $hash, 'currentAlbum', $decode_json->{payload}{album} );
    readingsBulkUpdate( $hash, 'currentArtist', $decode_json->{payload}{artist} );
    readingsBulkUpdate( $hash, 'currentImageUrl', $decode_json->{payload}{image_url} );
    readingsBulkUpdate( $hash, 'currentMid', $decode_json->{payload}{mid} );
    readingsBulkUpdate( $hash, 'currentQid', $decode_json->{payload}{qid} );
    readingsBulkUpdate( $hash, 'currentSid', $decode_json->{payload}{sid} );
    readingsBulkUpdate( $hash, 'currentStation', $decode_json->{payload}{station} );

    #sucht in den Favoriten nach der aktuell gespielten Radiostation und aktualisiert den channel wenn diese enthalten ist
    my @presets = map { $_->{name} } (@{ $hash->{IODev}{helper}{favorites} });
    my $search = ReadingsVal($name,"currentStation" ,undef);
    my( @index )= grep { $presets[$_] eq $search } 0..$#presets if ( defined $search );
    
    readingsBulkUpdate( $hash, 'channel', $index[0]+1 ) if ( scalar @index > 0 );
    readingsEndUpdate( $hash, 1 );
    Log3 $name, 5, "HEOSPlayer ($name) - readings set for $name";
    return undef;
}


###############
### my little Helpers

sub HEOSPlayer_PreProcessingReadings($$) {
    
    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};
    my $reading;
    my %buffer;
    my %message  = map { my ( $key, $value ) = split "="; $key => $value } split('&', $decode_json->{heos}{message});
    
    
    Log3 $name, 4, "HEOSPlayer ($name) - preprocessing readings";
    
    if ( $decode_json->{heos}{command} =~ /play_state/ or $decode_json->{heos}{command} =~ /player_state_changed/ ) {
    
        $buffer{'playStatus'}   = $message{state};
    
    } elsif ( $decode_json->{heos}{command} =~ /volume_changed/ or $decode_json->{heos}{command} =~ /set_volume/ or $decode_json->{heos}{command} =~ /get_volume/ ) {

        my @value           = split('&', $decode_json->{heos}{message});
        $buffer{'volume'}   = $message{level};
        $buffer{'mute'}     = $message{mute} if( $decode_json->{heos}{command} =~ /volume_changed/ );
        if (defined($buffer{'mute'}) && AttrVal($name, 'mute2play', 0) == 1) {
            IOWrite($hash,'setPlayState',"pid=$hash->{PID}&state=play",undef) if $buffer{'mute'} eq "off";
            IOWrite($hash,'setPlayState',"pid=$hash->{PID}&state=stop",undef) if $buffer{'mute'} eq "on";
        }
        
    } elsif ( $decode_json->{heos}{command} =~ /play_mode/ or $decode_json->{heos}{command} =~ /repeat_mode_changed/ or $decode_json->{heos}{command} =~ /shuffle_mode_changed/ ) {
    
        $buffer{'shuffle'}  = $message{shuffle};
        $buffer{'repeat'}   = $message{repeat};
        $buffer{'repeat'}   =~ s/.*\_(.*)/$1/g;
        
    } elsif ( $decode_json->{heos}{command} =~ /get_mute/ ) {
    
        $buffer{'mute'}     = $message{state};
        
    } elsif ( $decode_json->{heos}{command} =~ /volume_up/ or $decode_json->{heos}{command} =~ /volume_down/ ) {
    
        $buffer{'volumeUp'}     = $message{step} if( $decode_json->{heos}{command} =~ /volume_up/ );
        $buffer{'volumeDown'}   = $message{step} if( $decode_json->{heos}{command} =~ /volume_down/ );
        
    } elsif ( $decode_json->{heos}{command} =~ /player_now_playing_changed/ or $decode_json->{heos}{command} =~ /favorites_changed/ ) {
        IOWrite($hash,'getNowPlayingMedia',"pid=$hash->{PID}",undef);
        
    } elsif ( $decode_json->{heos}{command} =~ /play_preset/ ) {
    
        $buffer{'channel'}      = $message{preset}
        
    } elsif ( $decode_json->{heos}{command} =~ /play_input/ ) {
    
        $buffer{'input'}        = $message{input};

    } elsif ( $decode_json->{heos}{command} =~ /playback_error/ ) {
    
        $buffer{'error'}        = $message{error};
        
    } else {
    
        Log3 $name, 4, "HEOSPlayer ($name) - no match found";
        return undef;
    }
    
    Log3 $name, 4, "HEOSPlayer ($name) - Match found for decode_json";
    return \%buffer;
}

sub HEOSPlayer_GetPlayerInfo($) {

    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetPlayerInfo');
    IOWrite($hash,'getPlayerInfo',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetPlayState($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetPlayState');
    IOWrite($hash,'getPlayState',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetPlayMode($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetPlayMode');
    IOWrite($hash,'getPlayMode',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetNowPlayingMedia($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetNowPlayingMedia');
    IOWrite($hash,'getNowPlayingMedia',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetVolume($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetVolume');
    IOWrite($hash,'getVolume',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetMute($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetMute');
    IOWrite($hash,'getMute',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetQueue($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetQueue');
    IOWrite($hash,'getQueue',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_MakePlayLink($$$$$$$$) {

    my ($type, $name, $sid, $itemtype, $itemname, $itemurl, $xsize, $ysize) = @_;
    
    if( $type eq 'FHEMWEB' ) {

        my $xcmd = 'cmd'.uri_escape('=get '.$name.' ls '.$sid);
        my $xtext = $sid;
    
        $xcmd = 'cmd'.uri_escape('=set '.$name.' input '.$sid) if ( $itemtype eq "heos_queue" );
        $ysize = '10.75em' if (!defined($ysize));
        $xcmd = "FW_cmd('$FW_ME$FW_subdir?XHR=1&$xcmd')";
        
        return '<a onClick="'.$xcmd.'" class="list-group-item active" style="display: flex;align-items: center;cursor:pointer;"><img style="width: '.$xsize.'px; height: '.$ysize.'px;" src="'.$itemurl.'"><h5 class="list-group-item-heading" style="padding: 10px;">'.$itemname."</h5></a>";

    } else {

        return sprintf( "%-15s %s\n", $sid, $itemname );

    }

}

sub HEOSPlayer_makeImage($$) {
    my ($url, $xsize, $ysize) = @_;

    my $ret .= "<img src=\"$url\" width=\"$xsize\" height=\"$ysize\" style=\"float:left;\">\n";

    return $ret;
}





1;





=pod
=item device
=item summary       Modul to controls the Denon multiroom soundsystem
=item summary_DE    Modul zum steuern des Denon Multiroom-Soundsystem

=begin html

<a name="HEOSPlayer"></a>
<h3>HEOSPlayer</h3>
<ul>
  <u><b>HEOSPlayer</b></u>
  <br><br>
  In combination with HEOSMaster and HEOSGroup this FHEM Module controls the Denon multiroom soundsystem using a telnet socket connection and the HEOS Command Line Interface (CLI).
  <br><br>
  Once the master device is created, the players and groups of Your system are automatically recognized and created in FHEM. From now on the players and groups can be controlled and changes in the HEOS app or at the Receiver are synchronized with the state and media readings of the players and groups.
  <a name="HEOSPlayerreadings"></a>
 <br><br>
  <b>Readings</b>
  <ul>
    <li>channel - nr of now playing favorite</li>
    <li>currentAlbum - name of now playing album</li>
    <li>currentArtist - name of now playing artist</li>
    <li>currentImageUrl - URL of cover art, station logo, etc.</li>
    <li>currentMedia - type of now playing media (song|station|genre|artist|album|container)</li>
    <li>currentMid - media ID</li>
    <li>currentQid - queue ID</li>
    <li>currentSid - source ID</li>
    <li>currentStation - name of now playing station</li>
    <li>currentTitle - name of now playing title</li>
    <li>error - last error</li>
    <li>gid - ID of group, in which player is member</li>
    <li>ip-address - ip address of the player</li>
    <li>lineout - lineout level type (variable|Fixed)</li>
    <li>model - model of HEOS speaker (e.g. HEOS 1)</li>
    <li>mute - player mute state (on|off)</li>
    <li>name - name of player (received from app)</li>
    <li>network - network connection type (wired|wifi)</li>
    <li>playStatus - state of player (play|pause|stop)</li>
    <li>repeat - player repeat state (on_all|on_one|off)</li>
    <li>shuffle - player shuffle state (on|off)</li>
    <li>state - state of player connection (on|off)</li>
    <li>version - software version of HEOS speaker</li>
    <li>volume - player volume level (0-100)</li>
    <li>volumeDown - player volume step level (1-10, default 5)</li>
    <li>volumeUp - player volume step level (1-10, default 5)</li>
  </ul>
  <br><br>
  <a name="HEOSPlayerset"></a>
  <b>set</b>
  <ul>
    <li>aux - uses source at aux-input of player</li>
    <li>channel &ltnr&gt - plays favorite &ltnr&gt created with app</li>
    <li>channelUp - switches to next favorite</li>
    <li>channelDown- switches to previous favorite</li>
    <li>clear queue - clears the queue</li>
    <li>deletePlaylist &ltmyList&gt - clears playlist &ltmyList&gt</li>
    <li>set &lthp1&gt groupWithMember &lthp2&gt - creates group with hp1 as leader and hp2 as member</li>
    <li>input sid[,cid][,mid] - set input source-id[,container-id][,media-id]  </li>
    <ul>
        <code>Example: set kitchen input 1027,1772574848,inputs/tvaudio<br>
        starts "tv audio" on player "kitchen"</code>
    </ul>
    <li>mute on|off - set mute state on|off</li>
    <li>next - play next title in queue</li>
    <li>pause - set state of player to "pause"</li>
    <li>play - set state of player to "play"</li>
    <li>playPlaylist &ltmyList&gt - play playlist &ltmyList&gt</li>
    <li>playQueueItem &ltnr&gt - play title &ltnr&gt in queue</li>
    <li>prev - play previous title in queue</li>
    <li>repeat - set player repeat state (on_all|on_one|off)</li>
    <li>saveQueue &ltmyList&gt - save queue as &ltmyList&gt</li>
    <li>shuffle - set player shuffle state on|off</li>
    <li>stop - set state of player to "stop"</li>
    <li>volume - set volume 0..100</li>
    <li>volumeDown - reduce volume by &ltvolumeDown&gt</li>
    <li>volumeUp - increase volume by &ltvolumeUp&gt</li>
  </ul>
  <br><br>
  <a name="HEOSPlayerget"></a>
  <b>get</b>
  <ul>
    <li>ls - list music sources (input, playlists, favorites, music services, ...) </li>
    <li>channelscount - number of favorites</li>
    </ul>
  <br><br>
  <a name="HEOSPlayerstate"></a>
  <b>state</b>
  <ul>
    <li>state of player connection (on|off)</li>
  </ul>
 <br><br>
  <a name="HEOSPlayerattributes"></a>
  <b>attributes</b>
  <ul>
    <li>channelring - when reaching the last favorite ChannelUp/Down switches in circle, i.e. to the first/last favorite again</li>
    <li>mute2play - if mute switch on speaker is pressed, the stream stops</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="HEOSPlayer"></a>
<h3>HEOSPlayer</h3>
<ul>
  <u><b>HEOSPlayer</b></u>
  <br><br>
  In Kombination mit HEOSMaster and HEOSGroup steuert dieses FHEM Modul das Denon Multiroom-Soundsystem mit Hilfe einer telnet Socket-Verbindung und dem HEOS Command Line Interface (CLI). 
  <br><br>
  Nachdem der Master einmal angelegt ist werden die Player und Gruppierungen des Systems automatisch erkannt und in FHEM angelegt. Von da an k&oumlnnen die Player und Gruppierungen gesteuert werden und Ver&aumlnderungen in der HEOS App oder am Reveiver werden mit dem Status und den Media Readings der Player und Gruppierungen synchronisiert.
  <a name="HEOSPlayerreadings"></a>
 <br><br>
  <b>Readings</b>
  <ul>
    <li>channel - Nr des gerade abgespielten Favoriten</li>
    <li>currentAlbum - Name des gerade abgespielten Albums</li>
    <li>currentArtist - Name des gerade abgespielten K&uumlnstlers</li>
    <li>currentImageUrl - URL des Albumcovers, Senderlogos, etc.</li>
    <li>currentMedia - Medientyp des gerade abgespielten Streams (song|station|genre|artist|album|container)</li>
    <li>currentMid - media ID</li>
    <li>currentQid - queue ID</li>
    <li>currentSid - source ID</li>
    <li>currentStation - Name des gerade abgespielten Senders</li>
    <li>currentTitle - Name des gerade abgespielten Titels</li>
    <li>error - letzte Fehlermeldung</li>
    <li>gid - ID der Gruppe, in der der Player Mitglied ist</li>
    <li>ip-address - IP-Adresse des Players</li>
    <li>lineout - lineout level type (variable|Fixed)</li>
    <li>model - Modell des HEOS Lautsprechers (z.B. HEOS 1)</li>
    <li>mute - Player mute Status (on|off)</li>
    <li>name - Name des Players (aus der App &uumlbernommen)</li>
    <li>network - Netzwerkverbindung (wired|wifi)</li>
    <li>playStatus - Status des Players (play|pause|stop)</li>
    <li>repeat - Player Repeat Status (on_all|on_one|off) </li>
    <li>shuffle - Player Shuffle Status (on|off)</li>
    <li>state - Status der Player-Verbindung (on|off)</li>
    <li>version - Softwareversion des HEOS Lautsprechers</li>
    <li>volume - aktuelle Lautst&aumlrke (0-100)</li>
    <li>volumeDown - Schrittweite Lautst&aumlrke (1-10, default 5)</li>
    <li>volumeUp - Schrittweite Lautst&aumlrke (1-10, default 5)</li>
  </ul>
  <br><br>
  <a name="HEOSPlayerset"></a>
  <b>set</b>
  <ul>
    <li>aux - aktiviert die Quelle am AUX-Eingang des Players</li>
    <li>channel &ltnr&gt - spielt den vorher mit der App erstellten Favoriten &ltnr&gt ab</li>
    <li>channelUp - schaltet auf den n&aumlchsten Favoriten in der Favoritenliste um</li>
    <li>channelDown- schaltet auf vorherigen Favoriten in der Favoritenliste um</li>
    <li>clear queue - l&oumlscht die Warteschlange</li>
    <li>deletePlaylist &ltmyList&gt - l&oumlscht die Playlist &ltmyList&gt </li>
    <li>set &lthp1&gt groupWithMember &lthp2&gt - erzeugt eine Gruppierung mit hp1 als Leader und hp2 als Mitglied</li>
    <li>input sid[,cid][,mid] - setze input source-id[,container-id][,media-id]  </li>
        <ul>
        <code>Beispiel: set K&uumlche input 1027,1772574848,inputs/tvaudio<br>
        startet "TV-Audio" auf dem Player "K&uumlche"</code>
    </ul>
    <li>mute on|off - setzt den mute Status on|off</li>
    <li>next - spielt n&aumlchsten Titel in Warteschlange</li>
    <li>pause - setzt den Status des Players auf "pause"</li>
    <li>play - setzt den Status des Players auf "play"</li>
    <li>playPlaylist &ltmyList&gt - spielt die Playlist &ltmyList&gt ab</li>
    <li>playQueueItem &ltnr&gt - spielt Titel &ltnr&gt in Warteschlange</li>
    <li>prev - spielt vorherigen Titel in Warteschlange</li>
    <li>repeat - setzt den Player Repeat Status (on_all|on_one|off) </li>
    <li>saveQueue &ltmyList&gt - speichert die Warteschlange als Playlist &ltmyList&gt</li>
    <li>shuffle - setzt den Player Shuffle Status auf on|off</li>
    <li>stop - setzt den Status des Players auf "stop"</li>
    <li>volume - setzt die Lautst&aumlrke auf 0..100</li>
    <li>volumeDown - verringert die Lautst&aumlrke um &ltvolumeDown&gt</li>
    <li>volumeUp - erh&oumlht die Lautst&aumlrke um &ltvolumeUp&gt</li>
  </ul>
  <br><br>
  <a name="HEOSPlayerget"></a>
  <b>get</b>
  <ul>
    <li>ls - listet Musikquellen (Eing&aumlnge, Playlists, Favoriten, Musik-Dienste, ...)</li>
    <li>channelscount - Anzahl der Favoriten</li>
    </ul>
  <br><br>
  <a name="HEOSPlayerstate"></a>
  <b>state</b>
  <ul>
    <li>Status der Player-Verbindung (on|off)</li>
  </ul>
 <br><br>
  <a name="HEOSPlayerattributes"></a>
  <b>attributes</b>
  <ul>
    <li>channelring - Beim Erreichen des letzten Favoriten schaltet ChannelUp/Down im Kreis, also wieder auf den ersten/letzten Favoriten</li>
    <li>mute2play - Beim Bet&aumltigen der Mute-Taste am Lautsprecher wird auch der Stream angehalten</li>
  </ul>
</ul>
  
=end html_DE

=cut
