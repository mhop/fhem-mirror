###############################################################################
# $Id$
package main;
sub msgSchema_Initialize() { }

package msgSchema;
use strict;
use warnings;

# FHEM module schema definitions for messaging commands
my $db = {
    'audio' => {

        'AMADDevice' => {
            'Normal'        => 'set %DEVICE% ttsMsg &%LANG%; %MSGSHRT%',
            'ShortPrio'     => 'set %DEVICE% ttsMsg &%LANG%; %SHOUTOUT%',
            'Short'         => 'set %DEVICE% ttsMsg &%LANG%; %SHOUTOUT%',
            'defaultValues' => {
                'Normal' => {
                    'LANG' => 'de',
                },
                'ShortPrio' => {
                    'LANG'     => 'de',
                    'SHOUTOUT' => 'Achtung!',
                },
                'Short' => {
                    'LANG'     => 'de',
                    'SHOUTOUT' => 'Hinweis!',
                },
            },
        },

        'SB_PLAYER' => {
            'Normal'        => 'set %DEVICE% talk |%TITLE%| %MSGSHRT%',
            'ShortPrio'     => 'set %DEVICE% talk |%TITLE%| %SHOUTOUT%',
            'Short'         => 'set %DEVICE% talk |%TITLE%| %SHOUTOUT%',
            'defaultValues' => {
                'Normal' => {
                    'TITLE' => 'Announcement',
                },
                'ShortPrio' => {
                    'SHOUTOUT' => 'Achtung!',
                    'TITLE'    => 'Announcement',
                },
                'Short' => {
                    'SHOUTOUT' => '',
                    'TITLE'    => 'Announcement',
                },
            },
        },

        'SONOSPLAYER' => {
            'Normal' =>
              'set %DEVICE% Speak %VOLUME% %LANG% |%TITLE%| %MSGSHRT%',
            'ShortPrio' =>
              'set %DEVICE% Speak %VOLUME% %LANG% |%TITLE%| %SHOUTOUT%',
            'Short' =>
              'set %DEVICE% Speak %VOLUME% %LANG% |%TITLE%| %SHOUTOUT%',
            'defaultValues' => {
                'Normal' => {
                    'VOLUME' => 38,
                    'LANG'   => 'de',
                    'TITLE'  => 'Announcement',
                },
                'ShortPrio' => {
                    'VOLUME'   => 33,
                    'LANG'     => 'de',
                    'TITLE'    => 'Announcement',
                    'SHOUTOUT' => 'Achtung!',
                },
                'Short' => {
                    'VOLUME'   => 28,
                    'LANG'     => 'de',
                    'TITLE'    => 'Announcement',
                    'SHOUTOUT' => '',
                },
            },
        },

        'Text2Speech' => {
            'Normal'        => 'set %DEVICE% tts %MSGSHRT%',
            'ShortPrio'     => 'set %DEVICE% tts %SHOUTOUT%',
            'Short'         => 'set %DEVICE% tts %SHOUTOUT%',
            'defaultValues' => {
                'ShortPrio' => {
                    'SHOUTOUT' => 'Achtung!',
                },
                'Short' => {
                    'SHOUTOUT' => 'Hinweis!',
                },
            },
        },

    },

    'light' => {

        'HUEDevice' => {
            'Normal' =>
'{ my $d=\'%DEVICE%\'; my $state=ReadingsVal($d,"state","off"); fhem "set $d blink 2 1"; fhem "sleep 4.25; set $d:FILTER=state!=$state $state"; }',
            'High' =>
'{ my $d=\'%DEVICE%\'; my $state=ReadingsVal($d,"state","off"); fhem "set $d blink 10 1"; fhem "sleep 20.25; set $d:FILTER=state!=$state $state"; }',
            'Low' => 'set %DEVICE% alert select',
        },

    },

    'mail' => {

        'fhemMsgMail' => {
            'Normal' =>
'{ my $d=\'%DEVICE%\'; my $title=\'%TITLE%\'; my $msg=\'%MSG%\'; system("echo \'$msg\' | /usr/bin/mail -s \'$title\' \'$d\'"); }',
            'High' =>
'{ my $d=\'%DEVICE%\'; my $title=\'%TITLE%\'; my $msg=\'%MSG%\'; system("echo \'$msg\' | /usr/bin/mail -s \'$title\' \'$d\'"); }',
            'Low' =>
'{ my $d=\'%DEVICE%\'; my $title=\'%TITLE%\'; my $msg=\'%MSG%\'; system("echo \'$msg\' | /usr/bin/mail -s \'$title\' \'$d\'"); }',
            'defaultValues' => {
                'Normal' => {
                    'TITLE' => 'System Message',
                },
                'High' => {
                    'TITLE' => 'System Message',
                },
                'Low' => {
                    'TITLE' => 'System Message',
                },
            },

        },
    },

    'push' => {

        'Fhemapppush' => {
            'Normal'        => 'set %DEVICE% message \'%MSG%\' %ACTION%',
            'High'          => 'set %DEVICE% message \'%MSG%\' %ACTION%',
            'Low'           => 'set %DEVICE% message \'%MSG%\' %ACTION%',
            'defaultValues' => {
                'Normal' => {
                    'ACTION' => '',
                },
                'High' => {
                    'ACTION' => '',
                },
                'Low' => {
                    'ACTION' => '',
                },
            },
        },

        'Jabber' => {
            'Normal' => 'set %DEVICE% msg%Jabber_MTYPE% %RECIPIENT% %MSG%',
            'High'   => 'set %DEVICE% msg%Jabber_MTYPE% %RECIPIENT% %MSG%',
            'Low'    => 'set %DEVICE% msg%Jabber_MTYPE% %RECIPIENT% %MSG%',
            'defaultValues' => {
                'Normal' => {
                    'Jabber_MTYPE' => '',
                },
                'High' => {
                    'Jabber_MTYPE' => '',
                },
                'Low' => {
                    'Jabber_MTYPE' => '',
                },
            },
        },

        'Pushbullet' => {
            'Normal' => 'set %DEVICE% message %MSG% | %TITLE% %RECIPIENT%',
            'High'   => 'set %DEVICE% message %MSG% | %TITLE% %RECIPIENT%',
            'Low'    => 'set %DEVICE% message %MSG% | %TITLE% %RECIPIENT%',
            'defaultValues' => {
                'Normal' => {
                    'RECIPIENT' => '',
                },
                'High' => {
                    'RECIPIENT' => '',
                },
                'Low' => {
                    'RECIPIENT' => '',
                },
            },
        },

        'PushNotifier' => {
            'Normal' => 'set %DEVICE% message %MSG%',
            'High'   => 'set %DEVICE% message %MSG%',
            'Low'    => 'set %DEVICE% message %MSG%',
        },

        'Pushover' => {
            'Normal' =>
'set %DEVICE% %Pushover_MTYPE% title=\'%TITLE%\' device=\'%RECIPIENT%:%TERMINAL%\' priority=%PRIORITY% url_title="%URLTITLE%" message=\'%MSG%\'',
            'High' =>
'set %DEVICE% %Pushover_MTYPE% title=\'%TITLE%\' device=\'%RECIPIENT%:%TERMINAL%\' priority=%PRIORITY% url_title="%URLTITLE%" retry=%RETRY% expire=%EXPIRE% message=\'%MSG%\'',
            'Low' =>
'set %DEVICE% %Pushover_MTYPE% title=\'%TITLE%\' device=\'%RECIPIENT%:%TERMINAL%\' priority=%PRIORITY% url_title="%URLTITLE%" message=\'%MSG%\'',
            'defaultValues' => {
                'Normal' => {
                    'RECIPIENT'      => '',
                    'TERMINAL'       => '',
                    'URLTITLE'       => '',
                    'Pushover_MTYPE' => 'msg',
                },
                'High' => {
                    'RECIPIENT'      => '',
                    'TERMINAL'       => '',
                    'RETRY'          => '120',
                    'EXPIRE'         => '600',
                    'URLTITLE'       => '',
                    'Pushover_MTYPE' => 'msg',
                },
                'Low' => {
                    'RECIPIENT'      => '',
                    'TERMINAL'       => '',
                    'URLTITLE'       => '',
                    'Pushover_MTYPE' => 'msg',
                },
            },
        },

        'Pushsafer' => {
            'Normal' =>
'set %DEVICE% message "%MSG%" title="%TITLE%" key="%RECIPIENT%" device="%TERMINAL%" vibration="%Pushsafer_VIBRATION%" url="%ACTION%" urlText="%URLTITLE%" ttl="%EXPIRE%"',
            'High' =>
'set %DEVICE% message "%MSG%" title="%TITLE%" key="%RECIPIENT%" device="%TERMINAL%" vibration="%Pushsafer_VIBRATION%" url="%ACTION%" urlText="%URLTITLE%" ttl="%EXPIRE%"',
            'Low' =>
'set %DEVICE% message "%MSG%" title="%TITLE%" key="%RECIPIENT%" device="%TERMINAL%" url="%ACTION%" urlText="%URLTITLE%" ttl="%EXPIRE%"',
            'defaultValues' => {
                'Normal' => {
                    'RECIPIENT'           => '',
                    'TERMINAL'            => '',
                    'EXPIRE'              => '',
                    'URLTITLE'            => '',
                    'ACTION'              => '',
                    'Pushsafer_VIBRATION' => '1',
                },
                'High' => {
                    'RECIPIENT'           => '',
                    'TERMINAL'            => '',
                    'EXPIRE'              => '',
                    'URLTITLE'            => '',
                    'ACTION'              => '',
                    'Pushsafer_VIBRATION' => '2',
                },
                'Low' => {
                    'RECIPIENT' => '',
                    'TERMINAL'  => '',
                    'EXPIRE'    => '',
                    'URLTITLE'  => '',
                    'ACTION'    => '',
                },
            },
        },

        'TelegramBot' => {
            'Normal'        => 'set %DEVICE% message %RECIPIENT% %MSG%',
            'High'          => 'set %DEVICE% message %RECIPIENT% %MSG%',
            'Low'           => 'set %DEVICE% message %RECIPIENT% %MSG%',
            'defaultValues' => {
                'Normal' => {
                    'RECIPIENT' => '',
                },
                'High' => {
                    'RECIPIENT' => '',
                },
                'Low' => {
                    'RECIPIENT' => '',
                },
            },
        },

        'yowsup' => {
            'Normal' => 'set %DEVICE% send %RECIPIENT% %MSG%',
            'High'   => 'set %DEVICE% send %RECIPIENT% %MSG%',
            'Low'    => 'set %DEVICE% send %RECIPIENT% %MSG%',
        },

    },

    'screen' => {

        'AMADDevice' => {
            'Normal' => 'set %DEVICE% screenMsg %MSG%',
            'High'   => 'set %DEVICE% screenMsg %MSG%',
            'Low'    => 'set %DEVICE% screenMsg %MSG%',
        },

        'ENIGMA2' => {
            'Normal' => 'set %DEVICE% msg %ENIGMA2_MTYPE% %TIMEOUT% %MSG%',
            'High'   => 'set %DEVICE% msg %ENIGMA2_MTYPE% %TIMEOUT% %MSG%',
            'Low'    => 'set %DEVICE% msg %ENIGMA2_MTYPE% %TIMEOUT% %MSG%',
            'defaultValues' => {
                'Normal' => {
                    'ENIGMA2_MTYPE' => 'info',
                    'TIMEOUT'       => 8,
                },
                'High' => {
                    'ENIGMA2_MTYPE' => 'attention',
                    'TIMEOUT'       => 12,
                },
                'Low' => {
                    'ENIGMA2_MTYPE' => 'message',
                    'TIMEOUT'       => 8,
                },
            },
        },

        'KODI' => {
            'Normal' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %KODI_ICON%"; }',
            'High' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %KODI_ICON%"; }',
            'Low' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %KODI_ICON%"; }',
            'defaultValues' => {
                'Normal' => {
                    'TIMEOUT'   => 8,
                    'TITLE'     => 'Info',
                    'KODI_ICON' => 'info',
                },
                'High' => {
                    'TIMEOUT'   => 12,
                    'TITLE'     => 'Warning',
                    'KODI_ICON' => 'warning',
                },
                'Low' => {
                    'TIMEOUT'   => 8,
                    'TITLE'     => 'Notice',
                    'KODI_ICON' => '',
                },
            },
        },

        'PostMe' => {
            'Normal' =>
'set %DEVICE% create %TITLESHRT2%_%MSGID%; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSGDATETIME%; set %DEVICE% add %TITLESHRT2%_%MSGID% %TITLE%; set %DEVICE% add %TITLESHRT2%_%MSGID% %PostMe_TO%%SRCALIAS% (%SOURCE%); set %DEVICE% add %TITLESHRT2%_%MSGID% _________________________; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSG%',
            'High' =>
'set %DEVICE% create %TITLESHRT2%_%MSGID%; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSGDATETIME%; set %DEVICE% add %TITLESHRT2%_%MSGID% %TITLE%; set %DEVICE% add %TITLESHRT2%_%MSGID% %PostMe_PRIO%%PRIOCAT%/%PRIORITY%; set %DEVICE% add %TITLESHRT2%_%MSGID% %PostMe_TO%%SRCALIAS% (%SOURCE%); set %DEVICE% add %TITLESHRT2%_%MSGID% _________________________; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSG%',
            'Low' =>
'set %DEVICE% create %TITLESHRT2%_%MSGID%; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSGDATETIME%; set %DEVICE% add %TITLESHRT2%_%MSGID% %TITLE%; set %DEVICE% add %TITLESHRT2%_%MSGID% %PostMe_PRIO%%PRIOCAT%/%PRIORITY%; set %DEVICE% add %TITLESHRT2%_%MSGID% %PostMe_TO%%SRCALIAS% (%SOURCE%); set %DEVICE% add %TITLESHRT2%_%MSGID% _________________________; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSG%',
            'defaultValues' => {
                'Normal' => {
                    'TITLE'       => 'Info',
                    'PostMe_TO'   => 'To: ',
                    'PostMe_SUB'  => 'Subject: ',
                    'PostMe_PRIO' => 'Priority: ',
                },
                'High' => {
                    'TITLE'       => 'Warning',
                    'PostMe_TO'   => 'To',
                    'PostMe_SUB'  => 'Subject',
                    'PostMe_PRIO' => 'Priority',
                },
                'Low' => {
                    'TITLE'       => 'Notice',
                    'PostMe_TO'   => 'To: ',
                    'PostMe_SUB'  => 'Subject: ',
                    'PostMe_PRIO' => 'Priority: ',
                },
            },
        },

        'XBMC' => {
            'Normal' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %XBMC_ICON%"; }',
            'High' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %XBMC_ICON%"; }',
            'Low' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %XBMC_ICON%"; }',
            'defaultValues' => {
                'Normal' => {
                    'TIMEOUT'   => 8,
                    'TITLE'     => 'Info',
                    'XBMC_ICON' => 'info',
                },
                'High' => {
                    'TIMEOUT'   => 12,
                    'TITLE'     => 'Warning',
                    'XBMC_ICON' => 'warning',
                },
                'Low' => {
                    'TIMEOUT'   => 8,
                    'TITLE'     => 'Notice',
                    'XBMC_ICON' => '',
                },
            },
        },

    },
};

sub get {
    return $db;
}

1;
