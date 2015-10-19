# $Id$
##############################################################################
#
#     messageSchema.pm
#     Schema database for FHEM modules and their messaging options.
#     These commands are being used as default setting for FHEM command 'msg'
#     unless there is an explicit msgCmd* attribute.
#
#     FHEM module authors may request to extend this file
#
#     Copyright by Julian Pawlowski
#     e-mail: julian.pawlowski at gmail.com
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

package messageSchema;

use strict;
use warnings;

# FHEM module schema definitions for messaging commands
my $db = {
  'audio' => {

    'AMAD' => {
      'Normal'    => 'set %DEVICE% ttsMsg %MSG%',
      'ShortPrio' => 'set %DEVICE% ttsMsg %MSGSH%',
      'Short'     => 'set %DEVICE% notifySndFile %AMAD_FILENAME%',
      'defaultValues' => {
        'ShortPrio' => {
          'MSGSH' => 'Achtung!',
        },
      },
    },

    'SONOSPLAYER' => {
      'Normal'    => 'set %DEVICE% Speak %VOLUME% %LANG% |%TITLE%| %MSG%',
      'ShortPrio' => 'set %DEVICE% Speak %VOLUME% %LANG% |%TITLE%| %MSGSH%',
      'Short'     => 'set %DEVICE% Speak %VOLUME% %LANG% |%TITLE%| %MSGSH%',
      'defaultValues' => {
        'Normal' => {
          'VOLUME' => 38,
          'LANG' => 'de',
        },
        'ShortPrio' => {
          'VOLUME' => 33,
          'LANG' => 'de',
          'MSGSH' => 'Achtung!',
        },
        'Short' => {
          'VOLUME' => 28,
          'LANG' => 'de',
          'MSGSH' => '',
        },
      },
    },

  },

  'light' => {

    'HUEDevice' => {
      'Normal'  => '{my $state=ReadingsVal("%DEVICE%","state","off"); fhem "set %DEVICE% blink 2 1"; fhem "sleep 4.25;set %DEVICE%:FILTER=state!=$state $state"}',
      'High'    => '{my $state=ReadingsVal("%DEVICE%","state","off"); fhem "set %DEVICE% blink 10 1"; fhem "sleep 20.25;set %DEVICE%:FILTER=state!=$state $state"}',
      'Low'     => 'set %DEVICE% alert select',
    },
    
  },

  'mail' => {

    'fhemMsgMail' => {
      'Normal'  => '{system("echo \'%MSG%\' | /usr/bin/mail -s \'%TITLE%\' -t \'%DEVICE%\' -a \'MIME-Version: 1.0\' -a \'Content-Type: text/html; charset=UTF-8\'")}',
      'High'    => '{system("echo \'%MSG%\' | /usr/bin/mail -s \'%TITLE%\' -t \'%DEVICE%\' -a \'MIME-Version: 1.0\' -a \'Content-Type: text/html; charset=UTF-8\' -a \'X-Priority: 1 (Highest)\' -a \'X-MSMail-Priority: High\' -a \'Importance: high\'")}',
      'Low'     => '{system("echo \'%MSG%\' | /usr/bin/mail -s \'%TITLE%\' -t \'%DEVICE%\' -a \'MIME-Version: 1.0\' -a \'Content-Type: text/html; charset=UTF-8\' -a \'X-Priority: 5 (Lowest)\' -a \'X-MSMail-Priority: Low\' -a \'Importance: low\'")}',
    },

  },

  'push' => {

    'Fhemapppush' => {
      'Normal'  => 'set %DEVICE% message \'%TITLE%: %MSG%\' %ACTION%',
      'High'    => 'set %DEVICE% message \'%TITLE%: %MSG%\' %ACTION%',
      'Low'     => 'set %DEVICE% message \'%TITLE%: %MSG%\' %ACTION%',
      'defaultValues' => {
        'Normal' => {
          'ACTION'    => '',
        },
        'High' => {
          'ACTION'    => '',
        },
        'Low' => {
          'ACTION'    => '',
        },
      },
    },

    'Pushbullet' => {
      'Normal'  => 'set %DEVICE% message %MSG% | %TITLE% %RECIPIENT%',
      'High'    => 'set %DEVICE% message %MSG% | %TITLE% %RECIPIENT%',
      'Low'     => 'set %DEVICE% message %MSG% | %TITLE% %RECIPIENT%',
    },

    'PushNotifier' => {
      'Normal'  => 'set %DEVICE% message %TITLE%: %MSG%',
      'High'    => 'set %DEVICE% message %TITLE%: %MSG%',
      'Low'     => 'set %DEVICE% message %TITLE%: %MSG%',
    },

    'Pushover' => {
      'Normal'  => 'set %DEVICE% msg \'%TITLE%\' \'%MSG%\' \'%RECIPIENT%\' %PRIORITY% \'\' %RETRY% %EXPIRE% %URLTITLE% %ACTION%',
      'High'    => 'set %DEVICE% msg \'%TITLE%\' \'%MSG%\' \'%RECIPIENT%\' %PRIORITY% \'\' %RETRY% %EXPIRE% %URLTITLE% %ACTION%',
      'Low'     => 'set %DEVICE% msg \'%TITLE%\' \'%MSG%\' \'%RECIPIENT%\' %PRIORITY% \'\' %RETRY% %EXPIRE% %URLTITLE% %ACTION%',
      'defaultValues' => {
        'Normal' => {
          'RECIPIENT' => '',
          'RETRY'     => '',
          'EXPIRE'    => '',
          'URLTITLE'  => '',
          'ACTION'    => '',
        },
        'High' => {
          'RECIPIENT' => '',
          'RETRY'     => '120',
          'EXPIRE'    => '600',
          'URLTITLE'  => '',
          'ACTION'    => '',
        },
        'Low' => {
          'RECIPIENT' => '',
          'RETRY'     => '',
          'EXPIRE'    => '',
          'URLTITLE'  => '',
          'ACTION'    => '',
        },
      },
    },

    'TelegramBot' => {
      'Normal'  => 'set %DEVICE% message %RECIPIENT% %TITLE%: %MSG%',
      'High'    => 'set %DEVICE% message %RECIPIENT% %TITLE%: %MSG%',
      'Low'     => 'set %DEVICE% message %RECIPIENT% %TITLE%: %MSG%',
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
      'Normal'  => 'set %DEVICE% send %RECIPIENT% %TITLE%: %MSG%',
      'High'    => 'set %DEVICE% send %RECIPIENT% %TITLE%: %MSG%',
      'Low'     => 'set %DEVICE% send %RECIPIENT% %TITLE%: %MSG%',
    },

  },

  'screen' => {

    'AMAD' => {
      'Normal'  => 'set %DEVICE% screenMsg %TITLE%: %MSG%',
      'High'    => 'set %DEVICE% screenMsg %TITLE%: %MSG%',
      'Low'     => 'set %DEVICE% screenMsg %TITLE%: %MSG%',
    },

    'ENIGMA2' => {
      'Normal'  => 'set %DEVICE% msg %ENIGMA2_TYPE% %TIMEOUT% %MSG%',
      'High'    => 'set %DEVICE% msg %ENIGMA2_TYPE% %TIMEOUT% %MSG%',
      'Low'     => 'set %DEVICE% msg %ENIGMA2_TYPE% %TIMEOUT% %MSG%',
      'defaultValues' => {
        'Normal' => {
          'ENIGMA2_TYPE' => 'info',
          'TIMEOUT'     => 8,
        },
        'High' => {
          'ENIGMA2_TYPE'     => 'attention',
          'TIMEOUT'     => 12,
        },
        'Low' => {
          'ENIGMA2_TYPE'     => 'message',
          'TIMEOUT'     => 8,
        },
      },
    },

  },
};

sub get {
  return $db;
}

1;
