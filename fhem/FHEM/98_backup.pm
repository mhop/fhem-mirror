################################################################
# $Id$
# vim: ts=2:et
#
#  (c) 2012 Copyright: Martin Fischer (m_fischer at gmx dot de)
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
################################################################

package main;
use strict;
use warnings;

sub CommandBackup($$);
sub parseConfig($);
sub readModpath($$);
sub createArchiv($);

my @pathname;

#####################################
sub
backup_Initialize($$)
{
  my %hash = (  Fn => "CommandBackup",
               Hlp => ",create a backup of fhem configuration, state and modpath" );
  $cmds{backup} = \%hash;
}

#####################################
sub
CommandBackup($$)
{
  my ($cl, $param) = @_;

  my $modpath = $attr{global}{modpath};
  my $configfile = (!defined($attr{global}{configfile}) ? undef : $attr{global}{configfile});
  my $statefile  = (!defined($attr{global}{statefile}) ? undef : $attr{global}{statefile});
  my $msg;
  my $ret;

  return "Backup is not supported for configDB" if($configfile eq 'configDB');

  # set backupdir
  my $backupdir;
  if (!defined($attr{global}{backupdir})) {
    $backupdir = "$modpath/backup";
  } else {
    if ($attr{global}{backupdir} =~ m/^\/.*/) {
      $backupdir = $attr{global}{backupdir};
    } elsif ($attr{global}{backupdir} =~ m/^\.+\/.*/) {
      $backupdir = "$modpath/$attr{global}{backupdir}";
    } else {
      $backupdir = "$modpath/$attr{global}{backupdir}";
    }
  }

  # create backupdir if not exists
  if (!-d $backupdir) {
    Log 4, "backup create backupdir: '$backupdir'";
    $ret = `(mkdir -p $backupdir) 2>&1`;
    if ($ret) {
      chomp $ret;
      $msg = "backup: $ret";
      return $msg;
    }
  }

  # get pathnames to archiv
  push @pathname, $configfile;
  Log 4, "backup include: '$configfile'";
  $ret = parseConfig($configfile);
  push @pathname, $statefile;
  Log 4, "backup include: '$statefile'";
  $ret = readModpath($modpath,$backupdir);

  # create archiv
  $ret = createArchiv($backupdir);

  @pathname = [];
  undef @pathname;

  return $ret;
}

sub
parseConfig($)
{
  my $configfile = shift;
  my $fh;
  my $msg;
  my $ret;

  if (!open($fh,$configfile)) {
    $msg = "Can't open $configfile: $!";
    Log 1, "backup $msg";
    return $msg;
  }

  while (my $l = <$fh>) {
    $l =~ s/[\r\n]//g;
    if ($l =~ m/^\s*include\s+(\S+)\s*.*$/) {
      if (-e $1) {
        push @pathname, $1;
        Log 4, "backup include: '$1'";
        $ret = parseConfig($1);
      } else {
        Log 1, "backup configfile: '$1' does not exists! File not included."
      }
    }
  }
  close $fh;
  return $ret;
}

sub
readModpath($$)
{
  my ($modpath,$backupdir) = @_;
  my $msg;
  my $ret;

  if (!opendir(DH, $modpath)) {
    $msg = "Can't open $modpath: $!";
    Log 1, "backup $msg";
    return $msg;
  }
  my @files = <$modpath/*>;
  foreach my $file (@files) {
    if ($file eq $backupdir && (-d $file || -l $file)) {
      Log 4, "backup exclude: '$file'";
    } else {
      Log 4, "backup include: '$file'";
      push @pathname, $file;
    }
  }
  return $ret;
}

sub
createArchiv($)
{
  my $backupdir = shift;
  my $backupcmd = (!defined($attr{global}{backupcmd}) ? undef : $attr{global}{backupcmd});
  my $symlink = (!defined($attr{global}{backupsymlink}) ? "no" : $attr{global}{backupsymlink});
  my $tarOpts;
  my $msg;
  my $ret;

  my $dateTime = TimeNow();
  $dateTime =~ s/ /_/g;
  $dateTime =~ s/(:|-)//g;

  my $cmd="";
  if (!defined($backupcmd)) {
    if (lc($symlink) eq "no") {
      $tarOpts = "cf";
    } else {
      $tarOpts = "chf";
    }

    # prevents tar's output of "Removing leading /" and return total bytes of archive
    $cmd = "tar -$tarOpts - @pathname |gzip > $backupdir/FHEM-$dateTime.tar.gz";

  } else {
    $cmd = "$backupcmd \"@pathname\"";

  }
  Log 2, "Backup with command: $cmd";
  $ret = `($cmd) 2>&1`;

  if($ret) {
    chomp $ret;
    Log 1, "backup $ret";
  }
  if (!defined($backupcmd) && -e "$backupdir/FHEM-$dateTime.tar.gz") {
    my $size = -s "$backupdir/FHEM-$dateTime.tar.gz";
    $msg = "backup done: FHEM-$dateTime.tar.gz ($size Bytes)";
    Log 1, $msg;
    $ret .= "\n".$msg;
  }
  return $ret;
}

1;

=pod
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
=cut
