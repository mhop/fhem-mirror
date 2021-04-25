################################################################
# Developed with Kate
#
#  (c) 2012-2021 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  Rewrite and Maintained by Marko Oldenburg since 2019
#  All rights reserved
#
#       Contributors:
#         - Marko Oldenburg (CoolTux - fhemdevelopment at cooltux dot net)
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
#
# $Id$
#
################################################################

package main;
use strict;
use warnings;
use FHEM::Meta;

require FHEM::Core::Utils::FHEMbackup;

#####################################
sub backup_Initialize {

    my %hash = (
        Fn  => \&FHEM::Core::Utils::FHEMbackup::CommandBackup,
        Hlp => ',create a backup of fhem configuration, state and modpath'
    );

    $cmds{backup} = \%hash;

    return FHEM::Meta::InitMod( __FILE__, \%hash );
}


1;

=pod
=item command
=item summary    create a backup of the FHEM installation
=item summary_DE erzeugt eine Sicherungsdatei der FHEM Installation
=begin html

<a name="backup"></a>
<h3>backup</h3>
<ul>
  <code>backup</code><br>
  <br>
  The complete FHEM directory (containing the modules), the WebInterface
  pgm2 (if installed) and the config-file will be saved into a .tar.gz
  file by default. The file is stored with a timestamp in the
  <a href="#modpath">modpath</a>/backup directory or to a directory
  specified by the global Attribute <a href="#backupdir">backupdir</a>.<br>
  Note: tar and gzip must be installed to use this feature.
  <br>
  <br>
  If you need to call tar with support for symlinks, you could set the
  global Attribute <a href="#backupsymlink">backupsymlink</a> to everything
  else as "no".
  <br>
  <br>
  You could pass the backup to your own command / script by using the
  global ::attribute <a href="#backupcmd">backupcmd</a>.
  <br>
  <br>
</ul>

=end html

=for :application/json;q=META.json 98_backup.pm
{
  "abstract": "Modul to retrieves apt information about Debian update state",
  "x_lang": {
    "de": {
      "abstract": "Modul um apt Updateinformationen von Debian Systemen zu bekommen"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "backup",
    "tar"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v2.0.1",
  "author": [
    "Marko Oldenburg <fhemdevelopment@cooltux.net>"
  ],
  "x_fhem_maintainer": [
    "CoolTux"
  ],
  "x_fhem_maintainer_github": [
    "LeonGaultier"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut
