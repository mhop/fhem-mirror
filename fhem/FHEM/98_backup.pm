################################################################
# Developed with Kate
#
#  (c) 2012-2019 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  Rewrite and Maintained by Marko Oldenburg since 2019
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
#
# $Id$
#
################################################################

package main;
use strict;
use warnings;
use FHEM::Meta;

#####################################
sub backup_Initialize($$) {
    my %hash = (
        Fn  => 'FHEM::backup::CommandBackup',
        Hlp => ',create a backup of fhem configuration, state and modpath'
    );
    $cmds{backup} = \%hash;

    return FHEM::Meta::InitMod( __FILE__, \%hash );
}

######################################
## unserer packagename
package FHEM::backup;

use strict;
use warnings;
use FHEM::Meta;

use GPUtils qw(GP_Import)
  ;    # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(AttrVal
          InternalVal
          gettimeofday
          ResolveDateWildcards
          attr
          Log
          fhemForked
          defs
          configDBUsed
          TimeNow
          BC_searchTelnet
          BC_telnetDevice
          DoTrigger
          devspec2array
          configDB)
    );
}

my @pathname;

sub CommandBackup($$) {
    my ( $cl, $param ) = @_;

    my $byUpdate = ( $param && $param eq 'startedByUpdate' );
    my $modpath    = AttrVal( 'global', 'modpath', '.' );
    my $configfile = AttrVal( 'global', 'configfile', $modpath . '/fhem.cfg' );
    my $statefile  = AttrVal( 'global', 'statefile',  $modpath . '/log/fhem.save' );
    my $dir        = AttrVal( 'global', 'backupdir', $modpath . '/backup');
    my $now        = gettimeofday();
    my @t          = localtime($now);
    $statefile = ResolveDateWildcards( $statefile, @t );

    # prevent duplicate entries in backup list for default config, forum #54826
    $configfile = '' if ( $configfile eq 'fhem.cfg' || configDBUsed() );
    $statefile = '' if ( $statefile eq './log/fhem.save' );
    my $msg;
    my $ret;

    my ($err,$backupdir) = createBackupDir( $dir, $modpath );

    return Log( 1, 'ERROR: if create backup directory!' )
        if ( defined($err) and $err );
    
    Log( 1, 'NOTE: make sure you have a database backup!' )
      if ( configDBUsed() );
    $ret = addConfDBFiles( $configfile, $statefile );
    $ret = readModpath( $modpath, $backupdir );

    ## add all logfile path to pathname array
    $ret = addLogPathToPathnameArray();

    ### remove double entries from pathname array
    my %all=();
    @all{@pathname}=1;
    @pathname = keys %all;

    # create archiv
    $ret = createArchiv( $backupdir, $cl, $byUpdate );

    @pathname = [];
    undef @pathname;

    return $ret;
}

sub addConfDBFiles($$) {
    my ($configfile,$statefile) = @_;
    my $ret;
    
    if ( configDBUsed() ) {
        # add configDB configuration file
        push( @pathname, 'configDB.conf' );
        Log( 2, 'backup include: \'configDB.conf\'' );
        
        ## check if sqlite db file outside of modpath
        if (  $configDB{type} eq 'SQLITE'
          and defined($configDB{filename})
          and $configDB{filename} !~ m#^[a-zA-Z].*|^\.\/[a-zA-Z].*# )
        {
            ## backup sqlite db file
            Log( 2, 'backup include SQLite DB File: ' . $configDB{filename} );
            push( @pathname, $configDB{filename} );
        }
    }
    else {
        # get pathnames to archiv
        push( @pathname, $configfile ) if ($configfile);
        Log( 2, 'backup include: ' . $configfile );
        $ret = parseConfig($configfile);
        push( @pathname, $statefile ) if ($statefile);
        Log( 2, 'backup include: ' . $statefile );
    }
    
    return $ret;
}

sub createBackupDir($$) {
    my ($dir,$modpath)  = @_;
    
    my $msg;
    my $ret;
    my $backupdir = $dir =~ m#^\.(\/.*)$# ? $modpath.$1 : $dir =~ m#^\.\.\/# ? $modpath.'/'.$dir : $dir;

    # create backupdir if not exists
    if ( !-d $backupdir ) {
        Log( 4, 'backup create backupdir: ' . $backupdir );
        $ret = `(mkdir -p $backupdir) 2>&1`;
        if ($ret) {
            chomp($ret);
            $msg = 'backup: ' . $ret;
            return ($msg,undef);
        }
    }
    
    return (undef,$backupdir);
}

sub parseConfig($);

sub parseConfig($) {
    my $configfile = shift;

    # we need default value to read included files
    $configfile = $configfile ? $configfile : 'fhem.cfg';
    my $fh;
    my $msg;
    my $ret;

    if ( !open( $fh, $configfile ) ) {
        $msg = 'Can\'t open ' . $configfile . ': ' . $!;
        Log( 1, 'backup ' . $msg );
        return $msg;
    }

    while ( my $l = <$fh> ) {
        $l =~ s/[\r\n]//g;
        if ( $l =~ m/^\s*include\s+(\S+)\s*.*$/ ) {
            if ( -e $1 ) {
                push @pathname, $1;
                Log( 4, 'backup include: ' . $1 );
                $ret = parseConfig($1);
            }
            else {
                Log( 1,
                        'backup configfile: '
                      . $1
                      . ' does not exists! File not included.' );
            }
        }
    }

    close $fh;
    return $ret;
}

sub readModpath($$) {
    my ( $modpath, $backupdir ) = @_;
    my $msg;
    my $ret;

    if ( !opendir( DH, $modpath ) ) {
        $msg = 'Can\'t open $modpath: ' . $!;
        Log( 1, 'backup ' . $msg );
        return $msg;
    }

    my @files = <$modpath/*>;
    foreach my $file (@files) {
        if ( $file eq $backupdir && ( -d $file || -l $file ) ) {
            Log( 4, 'backup exclude: ' . $file );
        }
        else {
            Log( 4, 'backup include: ' . $file );
            push @pathname, $file;
        }
    }

    return $ret;
}

sub createArchiv($$$) {
    my ( $backupdir, $cl, $byUpdate ) = @_;
    my $backupcmd = AttrVal('global','backupcmd',undef);
    my $symlink = AttrVal('global','backupsymlink','no');
    my $tarOpts;
    my $msg;
    my $ret;

    my $dateTime = TimeNow();
    $dateTime =~ s/ /_/g;
    $dateTime =~ s/(:|-)//g;

    my $pathlist = join( '" "', @pathname );

    my $cmd = '';
    if ( !defined($backupcmd) ) {
        if ( lc($symlink) eq 'no' ) {
            $tarOpts = 'czf';
        }
        else {
            $tarOpts = 'chzf';
        }

# prevents tar's output of "Removing leading /" and return total bytes of
# archive
#     $cmd = "tar -$tarOpts - \"$pathlist\" |gzip > $backupdir/FHEM-$dateTime.tar.gz";
        $cmd = "tar $tarOpts $backupdir/FHEM-$dateTime.tar.gz \"$pathlist\"";
    }
    else {
        $cmd = $backupcmd . ' \"' . $pathlist . '\"';
    }

    Log( 2, 'Backup with command: ' . $cmd );
    if ( !$fhemForked && !$byUpdate ) {
        use Blocking;
        our $BC_telnetDevice;
        BC_searchTelnet('backup');
        my $tp = $defs{$BC_telnetDevice}{PORT};

        system( "($cmd; echo Backup done;"
              . "$^X $0 localhost:$tp 'trigger global backup done')2>&1 &" );
        return
          "Started the backup in the background, watch the log for details";
    }

    $ret = `($cmd) 2>&1`;

    if ($ret) {
        chomp $ret;
        Log( 1, 'backup ' . $ret );
    }

    if ( !defined($backupcmd) && -e "$backupdir/FHEM-$dateTime.tar.gz" ) {
        my $size = -s "$backupdir/FHEM-$dateTime.tar.gz";
        $msg = "backup done: FHEM-$dateTime.tar.gz ($size Bytes)";
        DoTrigger( 'global', $msg );
        Log( 1, $msg );
        $ret .= "\n" . $msg;
    }

    return $ret;
}

sub addLogPathToPathnameArray() {
#     my $modpath = shift;

    my $ret;    
    my @logpathname;
    my $extlogpath;

    Log( 4, 'addLogPathToPathnameArray' );
    
    foreach my $logFile (devspec2array('TYPE=FileLog')) {
        Log( 5, 'found logFiles: ' . $logFile );
        my $logpath = InternalVal($logFile,'currentlogfile','');
        Log( 4, 'found logpath: ' . $logpath );
        if ( $logpath =~ m#^(.+?)\/[\_|\-|\w]+\.log$# ) {
            $extlogpath = $1;
            Log( 4, 'found extlogpath: ' . $extlogpath );
            if ( $1 =~ /^\/[A-Za-z]/ ) {
                push( @logpathname, $extlogpath ) ;
                Log( 4, 'external logpath include: ' . $extlogpath );
            }
        }
    }

    push( @pathname, @logpathname);

    return $ret;
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
  specified by the global attribute <a href="#backupdir">backupdir</a>.<br>
  Note: tar and gzip must be installed to use this feature.
  <br>
  <br>
  If you need to call tar with support for symlinks, you could set the
  global attribute <a href="#backupsymlink">backupsymlink</a> to everything
  else as "no".
  <br>
  <br>
  You could pass the backup to your own command / script by using the
  global attribute <a href="#backupcmd">backupcmd</a>.
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
  "author": [
    "Marko Oldenburg <leongaultier@gmail.com>"
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
