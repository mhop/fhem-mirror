########################################################################################################################
# $Id$
#########################################################################################################################
#       API.pm
#
#       (c) 2020 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module provides Synology API information.
# 
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#########################################################################################################################

package FHEM::SynoModules::API;                                          

use strict;           
use warnings;
use utf8;
use Carp qw(croak carp);

use version; our $VERSION = qv('1.0.0');

use Exporter ('import');
our @EXPORT_OK   = qw(apistatic);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

my %hspecs = (                                                           # Hash der verfügbaren API-Specs
  surveillance => {fn => "_staticSurveillance" },
  chat         => {fn => "_staticChat"         },
);

########################################################################
#      Liefert die statischen Informationen der angefoderten API
#      $pec = surveillance | chat
########################################################################
sub apistatic {
  my $spec = shift // carp "got no API specification !" && return;
  
  no strict "refs";                                                      ## no critic 'NoStrict'  
  if($hspecs{$spec} && defined &{$hspecs{$spec}{fn}}) {
      my $h = q{};
      $h    = &{$hspecs{$spec}{fn}};
      
      $h->{INFO}{PATH} = "query.cgi";
      $h->{INFO}{VER}  = 1;
      
      return $h;
  }
  use strict "refs";

  carp qq{API specification "$spec" not found !};

return;
}


########################################################################
#      Liefert die statischen Informationen der Surveillance API
########################################################################
sub _staticSurveillance {                        ## no critic "not used"
  my %hapi = (                                                                    
      INFO      => { NAME => "SYNO.API.Info"                              },      # Info-Seite für alle API's, einzige statische Seite !    
      AUTH      => { NAME => "SYNO.API.Auth"                              },      # API used to perform session login and logout
      SVSINFO   => { NAME => "SYNO.SurveillanceStation.Info"              },
      EVENT     => { NAME => "SYNO.SurveillanceStation.Event"             },
      EXTREC    => { NAME => "SYNO.SurveillanceStation.ExternalRecording" },
      EXTEVT    => { NAME => "SYNO.SurveillanceStation.ExternalEvent"     },
      CAM       => { NAME => "SYNO.SurveillanceStation.Camera"            },      # stark geändert ab API v2.8
      SNAPSHOT  => { NAME => "SYNO.SurveillanceStation.SnapShot"          },      # This API provides functions on snapshot, including taking, editing and deleting snapshots.
      PTZ       => { NAME => "SYNO.SurveillanceStation.PTZ"               },
      PRESET    => { NAME => "SYNO.SurveillanceStation.PTZ.Preset"        },
      CAMEVENT  => { NAME => "SYNO.SurveillanceStation.Camera.Event"      },
      VIDEOSTM  => { NAME => "SYNO.SurveillanceStation.VideoStreaming"    },      # verwendet in Response von "SYNO.SurveillanceStation.Camera: GetLiveViewPath" -> StreamKey-Methode
      STM       => { NAME => "SYNO.SurveillanceStation.Stream"            },      # Beschreibung ist falsch und entspricht "SYNO.SurveillanceStation.Streaming" auch noch ab v2.8
      HMODE     => { NAME => "SYNO.SurveillanceStation.HomeMode"          },
      LOG       => { NAME => "SYNO.SurveillanceStation.Log"               },
      AUDIOSTM  => { NAME => "SYNO.SurveillanceStation.AudioStream"       },      # Audiostream mit SID, removed in API v2.8 (noch undokumentiert verfügbar)
      VIDEOSTMS => { NAME => "SYNO.SurveillanceStation.VideoStream"       },      # Videostream mit SID, removed in API v2.8 (noch undokumentiert verfügbar)
      REC       => { NAME => "SYNO.SurveillanceStation.Recording"         },      # This API provides method to query recording information.
  );

return \%hapi;
}

########################################################################
#      Liefert die statischen Informationen der Chat API
########################################################################
sub _staticChat {                                ## no critic "not used"
  my %hapi = (                                                    
      INFO     => { NAME => "SYNO.API.Info"      }, 
      EXTERNAL => { NAME => "SYNO.Chat.External" },
  );

return \%hapi;
}

1;