########################################################################################################################
# $Id$
#########################################################################################################################
#       ErrCodes.pm
#
#       (c) 2020 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module provides Synology API Error Codes.
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

package FHEM::SynoModules::ErrCodes;                                          

use strict;           
use warnings;
use utf8;
use Carp qw(croak carp);

use version; our $VERSION = version->declare('1.0.0');

use Exporter ('import');
our @EXPORT_OK   = qw(expErrorsAuth expErrors);                 
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

my %hterr = (                                                           # Hash der TYPE Error Code Spezifikationen
  SSCam => {fnerrauth => "_errauthsscam", fnerr => "_errsscam" },    
  SSCal => {fnerrauth => "_errauthsscal", fnerr => "_errsscal" },
);

# Standard Rückgabewert wenn keine Message zum Error Code gefunden wurde
my $nofound = qq{Message not found for error code:};

##############################################################################
#                             Error Code Hashes 
##############################################################################
## SSCam ##
my %errauthsscam = (                                                    # Authentification Error Codes der Surveillance Station API
  100 => "Unknown error",
  101 => "The account parameter is not specified",
  102 => "API does not exist",
  400 => "Invalid user or password",
  401 => "Guest or disabled account",
  402 => "Permission denied - DSM-Session: make sure user is member of Admin-group, SVS-Session: make sure SVS package is started, make sure FHEM-Server IP won't be blocked in DSM automated blocking list",
  403 => "One time password not specified",
  404 => "One time password authenticate failed",
  405 => "method not allowd - maybe the password is too long",
  406 => "OTP code enforced",
  407 => "Max Tries (if auto blocking is set to true) - make sure FHEM-Server IP won't be blocked in DSM automated blocking list",
  408 => "Password Expired Can not Change",
  409 => "Password Expired",
  410 => "Password must change (when first time use or after reset password by admin)",
  411 => "Account Locked (when account max try exceed)",
);

my %errsscam = (                                                       # Standard Error Codes der Surveillance Station API                 
  100 => "Unknown error",
  101 => "Invalid parameters",
  102 => "API does not exist",
  103 => "Method does not exist",
  104 => "This API version is not supported",
  105 => "Insufficient user privilege",
  106 => "Connection time out",
  107 => "Multiple login detected",
  117 => "need manager rights in SurveillanceStation for operation",
  400 => "Execution failed",
  401 => "Parameter invalid",
  402 => "Camera disabled",
  403 => "Insufficient license",
  404 => "Codec activation failed",
  405 => "CMS server connection failed",
  407 => "CMS closed",
  410 => "Service is not enabled",
  412 => "Need to add license",
  413 => "Reach the maximum of platform",
  414 => "Some events not exist",
  415 => "message connect failed",
  417 => "Test Connection Error",
  418 => "Object is not exist",
  419 => "Visualstation name repetition",
  439 => "Too many items selected",
  502 => "Camera disconnected",
  600 => "Presetname and PresetID not found in Hash",
);

## SSCal ##
my %errauthsscal = (                                                   # Authentification Error Codes der Calendar API
  400 => "No such account or the password is incorrect",
  401 => "Account disabled",
  402 => "Permission denied",
  403 => "2-step verification code required",
  404 => "Failed to authenticate 2-step verification code",
);

my %errsscal = (                                                       # Standard Error Codes der Calendar API 
  100 => "Unknown error",
  101 => "No parameter of API, method or version",
  102 => "The requested API does not exist - may be the Synology Calendar package is stopped",
  103 => "The requested method does not exist",
  104 => "The requested version does not support the functionality",
  105 => "The logged in session does not have permission",
  106 => "Session timeout",
  107 => "Session interrupted by duplicate login",
  114 => "Missing required parameters",
  117 => "Unknown internal error",
  119 => "session id not valid",
  120 => "Invalid parameter",
  160 => "Insufficient application privilege",
  400 => "Invalid parameter of file operation",
  401 => "Unknown error of file operation",
  402 => "System is too busy",
  403 => "The user does not have permission to execute this operation",
  404 => "The group does not have permission to execute this operation",
  405 => "The user/group does not have permission to execute this operation",
  406 => "Cannot obtain user/group information from the account server",
  407 => "Operation not permitted",
  408 => "No such file or directory",
  409 => "File system not supported",
  410 => "Failed to connect internet-based file system (ex: CIFS)",
  411 => "Read-only file system",
  412 => "Filename too long in the non-encrypted file system",
  413 => "Filename too long in the encrypted file system",
  414 => "File already exists",
  415 => "Disk quota exceeded",
  416 => "No space left on device",
  417 => "Input/output error",
  418 => "Illegal name or path",
  419 => "Illegal file name",
  420 => "Illegal file name on FAT file system",
  421 => "Device or resource busy",
  599 => "No such task of the file operation",
  800 => "malformed or unsupported URL",
  805 => "empty API data received - may be the Synology cal Server package is stopped",
  806 => "couldn't get Synology cal API information",
  810 => "The credentials couldn't be retrieved",
  900 => "malformed JSON string received from Synology Calendar Server",
  910 => "Wrong timestamp definition. Check attributes \"cutOlderDays\", \"cutLaterDays\". ",
);

##############################################################################
#              Auflösung Errorcodes bei Login / Logout
##############################################################################
sub expErrorsAuth {
  my $hash      = shift // carp "got no hash value !"           && return;
  my $errorcode = shift // carp "got no error code to analyse"  && return;
  my $type      = $hash->{TYPE};
  
  no strict "refs";                                                      ## no critic 'NoStrict'  
  if($hterr{$type} && defined &{$hterr{$type}{fnerrauth}}) {
      my $error = &{$hterr{$type}{fnerrauth}} ($errorcode);
      return $error;
  }
  use strict "refs";
  
  carp qq{No resolution function of authentication errors for module type "$type" defined};

return q{};
}

##############################################################################
#               Auflösung Standard Errorcodes 
##############################################################################
sub expErrors {
  my $hash      = shift // carp "got no hash value !"           && return;
  my $errorcode = shift // carp "got no error code to analyse"  && return;
  my $type      = $hash->{TYPE};
  
  no strict "refs";                                                      ## no critic 'NoStrict'  
  if($hterr{$type} && defined &{$hterr{$type}{fnerr}}) {
      my $error = &{$hterr{$type}{fnerr}} ($errorcode);
      return $error;
  }
  use strict "refs";
  
  carp qq{No resolution function of authentication errors for module type "$type" defined};

return q{};
}

##############################################################################
# Liefert Fehlertext für einen 
# Authentification Error Code der Surveillance Station API
##############################################################################
sub _errauthsscam {                                    ## no critic "not used"
  my $errorcode = shift;
  
  my $error = $errauthsscam{"$errorcode"} // $nofound." ".$errorcode;

return $error;
}

##############################################################################
# Liefert Fehlertext für einen 
# Standard Error Code der Surveillance Station API
##############################################################################
sub _errsscam {                                        ## no critic "not used"
  my $errorcode = shift;
  
  my $error = $errsscam{"$errorcode"} // $nofound." ".$errorcode;

return $error;
}

##############################################################################
# Liefert Fehlertext für einen 
# Authentification Error Code der Calendar API
##############################################################################
sub _errauthsscal {                                    ## no critic "not used"
  my $errorcode = shift;
  
  my $error = $errauthsscal{"$errorcode"} // $nofound." ".$errorcode;

return $error;
}

##############################################################################
# Liefert Fehlertext für einen 
# Standard Error Code der Calendar API
##############################################################################
sub _errsscal {                                        ## no critic "not used"
  my $errorcode = shift;
  
  my $error = $errsscal{"$errorcode"} // $nofound." ".$errorcode;

return $error;
}

1;