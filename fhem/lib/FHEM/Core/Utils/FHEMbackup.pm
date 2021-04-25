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

package FHEM::Core::Utils::FHEMbackup;

use strict;
use warnings;


my @pathname;

sub CommandBackup {
    my $cl          = shift;
    my $param       = shift;

    my $byUpdate    = ( $param && $param eq 'startedByUpdate' );
    my $modpath     = ::AttrVal( 'global', 'modpath', '.' );
    my $configfile  = ::AttrVal( 'global', 'configfile', $modpath . '/fhem.cfg' );
    my $statefile   = ::AttrVal( 'global', 'statefile',  $modpath . '/log/fhem.save' );
    my $dir         = ::AttrVal( 'global', 'backupdir', $modpath . '/backup');
    my $now         = ::gettimeofday();
    my @t           = localtime($now);
    my $dateTime    = dateTime();

    $statefile      = ::ResolveDateWildcards( $statefile, @t );

    # prevent duplicate entries in backup list for default config, forum #54826
    $configfile = '' if ( $configfile eq 'fhem.cfg' || ::configDBUsed() );
    $statefile  = '' if ( $statefile eq './log/fhem.save' );
    my $msg;
    my $ret;

    my ($err,$backupdir) = createBackupDir( $dir, $modpath );

    return ::Log(1, q(ERROR: if create backup directory!))
        if ( defined($err) && $err );
    
    ::Log(1, q(NOTE: make sure you have a database backup!))
      if ( ::configDBUsed() );
    $ret = addConfDBFiles( $configfile, $statefile );
    return ::Log(1, qq(Backup ERROR - addConfDBFiles: $ret))
      if ( defined($ret)
        && $ret =~ m{\ACan\'t\sopen.*:\s.*}xms);

    $ret = readModpath( $modpath, $backupdir );
    return ::Log(1, qq(Backup ERROR - readModpath: $ret))
      if ( defined($ret)
        && $ret =~ m{\ACan\'t\sopen\s\$modpath:\s.*}xms);

    ## add all logfile path to pathname array
    $ret = addLogPathToPathnameArray();

    ### remove double entries from pathname array
    my %all=();
    @all{@pathname}=1;
    @pathname = keys %all;

    ### create archiv
    $ret = createArchiv( $backupdir, $cl, $byUpdate, $dateTime );
    
    ### support for backupToStorage Modul
    ::readingsSingleUpdate($::defs{join(' ',
        ::devspec2array('TYPE=backupToStorage'))}
        , 'fhemBackupFile'
        , "$backupdir/FHEM-$dateTime.tar.gz"
        , 0
    )
        if ( ::devspec2array('TYPE=backupToStorage') > 0 );

    @pathname = [];
    undef @pathname;

    return $ret;
}

sub addConfDBFiles {
    my $configfile  = shift;
    my $statefile   = shift;

    my $ret;
    
    if ( ::configDBUsed() ) {
        # add ::configDB configuration file
        push( @pathname, 'configDB.conf' );
        ::Log(2, q(backup include: 'configDB.conf'));
        
        ## check if sqlite db file outside of modpath
        if ( $::configDB{type} eq 'SQLITE'
          && defined($::configDB{filename})
          && $::configDB{filename} !~ m{\A[a-zA-Z].*|^\.\/[a-zA-Z].*}xms )
        {
            ## backup sqlite db file
            ::Log(2, qq(backup include SQLite DB File: $::configDB{filename}));
            push( @pathname, $::configDB{filename} );
        }
    }
    else {
        # get pathnames to archiv
        push( @pathname, $configfile ) if ($configfile);
        ::Log(2, qq(backup include: $configfile))
          if ($configfile);

        $ret = parseConfig($configfile);
        push( @pathname, $statefile ) if ($statefile);
        ::Log(2, qq(backup include: $statefile))
          if ($statefile);
    }
    
    return $ret;
}

sub createBackupDir {
    my $dir     = shift;
    my $modpath = shift;
    
    my $msg;
    my $ret;
    my $backupdir = $dir =~ m{\A\.(\/.*)\z}xms ? $modpath.$1 : $dir =~ m{\A\.\.\/}xms ? $modpath.'/'.$dir : $dir;

    # create backupdir if not exists
    if ( !-d $backupdir ) {
        ::Log(4, qq(backup create backupdir: $backupdir));
        $ret = `(mkdir -p $backupdir) 2>&1`;
        if ($ret) {
            chomp($ret);
            $msg = 'backup: ' . $ret;
            return ($msg,undef);
        }
    }
    
    return (undef,$backupdir);
}

sub parseConfig {
    my $configfile = shift;

    # we need default value to read included files
    $configfile = $configfile ? $configfile : 'fhem.cfg';
    my $fh;
    my $msg;
    my $ret;

    if ( !open( $fh, $configfile ) ) {
        $msg = 'Can\'t open ' . $configfile . ': ' . $!;
        ::Log(1, qq(backup $msg));
        return $msg;
    }

    while ( my $l = <$fh> ) {
        $l =~ s/[\r\n]//g;
        if ( $l =~ m{\A\s*include\s+(\S+)\s*.*\z}xms ) {
            if ( -e $1 ) {
                push @pathname, $1;
                ::Log(4, qq(backup include: $1));
                $ret = parseConfig($1);
            }
            else {
                ::Log(1, qq(backup configfile: $1 does not exists! File not included.));
            }
        }
    }

    close $fh;
    return $ret;
}

sub readModpath {
    my $modpath     = shift;
    my $backupdir   = shift;

    my $msg;
    my $ret;

    if ( !opendir( DH, $modpath ) ) {
        $msg = qq(Can't open \$modpath: $!);
        ::Log(1, qq(backup $msg));
        return $msg;
    }

    my @files = <$modpath/*>;
    foreach my $file (@files) {
        if ( $file eq $backupdir && ( -d $file || -l $file ) ) {
            ::Log(4, qq(backup exclude: $file));
        }
        else {
            ::Log(4, qq(backup include: $file));
            push @pathname, $file;
        }
    }

    return $ret;
}

sub dateTime {
    my $dateTime = ::TimeNow();
    $dateTime =~ s/ /_/g;
    $dateTime =~ s/(:|-)//g;
    
    return $dateTime;
}

sub createArchiv {
    my ($backupdir, $cl, $byUpdate, $dateTime) = @_;

    my $backupcmd   = ::AttrVal('global','backupcmd',undef);
    my $symlink     = ::AttrVal('global','backupsymlink','no');
    my $tarOpts;
    my $msg;
    my $ret;

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
        $cmd = "tar $tarOpts $backupdir/FHEM-$dateTime.tar.gz \"$pathlist\"";
    }
    else {
        $cmd = $backupcmd . ' \"' . $pathlist . '\"';
    }

    ::Log(2, qq(Backup with command: $cmd));
    if ( !$::fhemForked && !$byUpdate ) {
        require Blocking;
        ::BC_searchTelnet('backup');
        my $tp = $::defs{$::BC_telnetDevice}{PORT};

        system( "($cmd; echo Backup done;"
              . "$^X $0 localhost:$tp 'trigger global backup done')2>&1 &" );

        return
          "Started the backup in the background, watch the log for details";
    }

    $ret = `($cmd) 2>&1`;

    if ($ret) {
        chomp $ret;
        ::Log(1, qq(backup $ret));
    }

    if ( !defined($backupcmd) && -e "$backupdir/FHEM-$dateTime.tar.gz" ) {
        my $size = -s "$backupdir/FHEM-$dateTime.tar.gz";
        $msg = "backup done: FHEM-$dateTime.tar.gz ($size Bytes)";
        ::DoTrigger( 'global', $msg );
        ::Log(1, $msg);
        $ret .= "\n" . $msg;
    }

    return $ret;
}

sub addLogPathToPathnameArray {
    my $ret;    
    my @logpathname;
    my $extlogpath;

    ::Log(4, q(addLogPathToPathnameArray));
    
    foreach my $logFile (::devspec2array('TYPE=FileLog')) {
        ::Log(5, qq(found logFiles: $logFile));
        my $logpath = ::InternalVal($logFile,'currentlogfile','');
        ::Log(4, qq(found logpath: $logpath));
        if ( $logpath =~ m{\A(.+?)\/[\_|\-|\w]+\.log\z}xms ) {
            $extlogpath = $1;
            ::Log(4, qq(found extlogpath: $extlogpath));

            if ( $1 =~ m{\A\/[A-Za-z]}xms ) {
                push( @logpathname, $extlogpath ) ;
                ::Log(4, qq(external logpath include: $extlogpath));
            }
        }
    }

    push( @pathname, @logpathname);

    return $ret;
}

1;
