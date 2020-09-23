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

use version; our $VERSION = version->declare('1.2.0');

use Exporter ('import');
our @EXPORT_OK   = qw(apistatic);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

my %hspecs = (                                                           # Hash der verfügbaren API-Specs
  surveillance => {fn => \&_staticSurveillance },
  chat         => {fn => \&_staticChat         },
  calendar     => {fn => \&_staticCalendar     },
  file         => {fn => \&_staticFile         },
);

########################################################################
#      Liefert die statischen Informationen der angefoderten API
#      $pec = surveillance | chat
########################################################################
sub apistatic {
  my $spec = shift // carp "got no API specification !" && return;
   
  if($hspecs{$spec} && defined &{$hspecs{$spec}{fn}}) {
      my $h = q{};
      $h    = &{$hspecs{$spec}{fn}};
      
      $h->{INFO}{PATH} = "query.cgi";
      $h->{INFO}{VER}  = 1;
      
      return $h;
  }

  carp qq{API specification "$spec" not found !};

return;
}


########################################################################
#      Liefert die statischen Informationen der Surveillance API
########################################################################
sub _staticSurveillance {
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
sub _staticChat {
  my %hapi = (                                                    
      INFO     => { NAME => "SYNO.API.Info"      }, 
      EXTERNAL => { NAME => "SYNO.Chat.External" },
  );

return \%hapi;
}

########################################################################
#      Liefert die statischen Informationen der Calendar API
########################################################################
sub _staticCalendar {
  my %hapi = (                                                    
      INFO   => { NAME => "SYNO.API.Info"    },                                          
      AUTH   => { NAME => "SYNO.API.Auth"    },     # API used to perform session login and logout  
      CAL    => { NAME => "SYNO.Cal.Cal"     },     # API to manipulate calendar
      EVENT  => { NAME => "SYNO.Cal.Event"   },     # Provide methods to manipulate events in the specific calendar
      SHARE  => { NAME => "SYNO.Cal.Sharing" },     # Get/set sharing setting of calendar
      TODO   => { NAME => "SYNO.Cal.Todo"    },     # Provide methods to manipulate events in the specific calendar
  );

return \%hapi;
}

########################################################################
#      Liefert die statischen Informationen der File Station API
########################################################################
sub _staticFile {
  my %hapi = (                                                    
      INFO      => { NAME => "SYNO.API.Info"                    },                                          
      AUTH      => { NAME => "SYNO.API.Auth"                    },     # Perform login and logout
      FSINFO    => { NAME => "SYNO.FileStation.Info"            },     # Provide File Station info
      LIST      => { NAME => "SYNO.FileStation.List"            },     # List all shared folders, enumerate files in a shared folder, and get detailed file information
      SEARCH    => { NAME => "SYNO.FileStation.Search"          },     # Search files on given criteria
      LVFOLDER  => { NAME => "SYNO.FileStation.VirtualFolder"   },     # List all mount point folders of virtual file system, ex: CIFS or ISO
      FAVORITE  => { NAME => "SYNO.FileStation.Favorite"        },     # Add a folder to user’s favorites or do operations on user’s favorites
      THUMB     => { NAME => "SYNO.FileStation.Thumb"           },     # Get a thumbnail of a file
      DIRSIZE   => { NAME => "SYNO.FileStation.DirSize"         },     # Get the total size of files/folders within folder(s)
      MD5       => { NAME => "SYNO.FileStation.MD5"             },     # Get MD5 of a file
      CHECKPERM => { NAME => "SYNO.FileStation.CheckPermission" },     # Check if the file/folder has a permission of a file/folder or not
      UPLOAD    => { NAME => "SYNO.FileStation.Upload"          },     # Upload a file
      DOWNLOAD  => { NAME => "SYNO.FileStation.Download"        },     # Download files/folders
      SHARING   => { NAME => "SYNO.FileStation.Sharing"         },     # Generate a sharing link to share files/folders with other people and perform operations on sharing links
      CFOLDER   => { NAME => "SYNO.FileStation.CreateFolder"    },     # Create folder(s)
      RENAME    => { NAME => "SYNO.FileStation.Rename"          },     # Rename a file/folder
      COPYMOVE  => { NAME => "SYNO.FileStation.CopyMove"        },     # Copy/Move files/folders
      DELETE    => { NAME => "SYNO.FileStation.Delete"          },     # Delete files/folders
      EXTRACT   => { NAME => "SYNO.FileStation.Extract"         },     # Extract an archive and do operations on an archive
      COMPRESS  => { NAME => "SYNO.FileStation.Compress"        },     # Compress files/folders
      BGTASK    => { NAME => "SYNO.FileStation.BackgroundTask"  },     # Get information regarding tasks of file operations which are run as the background process including copy, move, delete, compress and extract tasks or perform operations on these background tasks
  );

return \%hapi;
}

1;