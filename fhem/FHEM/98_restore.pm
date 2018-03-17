################################################################
# $Id$

package main;
use strict;
use warnings;
use File::Copy qw(cp);

sub CommandUpdate($$);
sub restoreFile($$$);
sub restoreDir($$$);

########################################
sub
restore_Initialize($$)
{
  my %hash = (
    Fn  => "CommandRestore",
    Hlp => "[-a|list] [<filename|directory>],restore files saved by update",
  );
  $cmds{restore} = \%hash;
}

########################################
sub
CommandRestore($$)
{
  my ($cl,$param) = @_;
  my @args = split(/ +/,$param);

  my $list;
  $list = shift(@args) if(@args > 0 && $args[0] eq "list");

  my $all;
  $all = shift @args if(@args > 0 && $args[0] eq "-a");

  my $filename;
  $filename = shift @args if(@args > 0 && $args[0] !~ m/^-/);

  my $dest = $attr{global}{modpath};
  my $src = "$dest/restoreDir";

  $list = 1 if(!$list && (!$filename || $filename !~ m/20\d\d-\d\d-\d\d/));
  return "Usage: restore [-a|list] filename|directory"
    if(@args);

  $filename = "" if(!$filename);
  $filename =~ s/\.\.//g;

  return "restoreDir is not yet created" if(!-d $src);
  return "list argument must be a directory" if($list && !-d "$src/$filename");
  if($list) {
    my $dh;
    opendir($dh, "$src/$filename") || return "opendir $src/$filename: $!";
    my @files = readdir($dh);
    closedir($dh);
    return "Available for restore".($filename ? " in $filename":"").":\n  ".
           join("\n  ", sort grep { $_ ne "." && $_ ne ".." } @files);
  }

  return "$filename is not available for restore" if(!-e "$src/$filename");

  $src = "$src/$filename";
  $dest = "$dest/$1" if($filename =~ m,20\d\d-\d\d-\d\d/(.*)$,);

  return (-f $src ? restoreFile($src,$dest,$all) :
                    restoreDir( $src,$dest,$all) ).  "\n\nrestore finished";
}

sub
restoreFile($$$)
{
  my ($src, $dest, $all) = @_;
  if((index($dest,$attr{global}{configfile}) >= 0 || 
      index($dest,$attr{global}{statefile}) >= 0 ) && !$all) {
    return "skipping $dest";
  }
  cp($src, $dest) || return "cp $src $dest failed: $!";
  return "restore $dest";
}

sub
restoreDir($$$)
{
  my ($src, $dest, $all, $dh, @ret) = @_;
  opendir($dh, $src) || return "opendir $src: $!";
  my @files = sort grep { $_ ne "." && $_ ne ".." } readdir($dh);
  closedir($dh);
  foreach my $f (@files){
    if(-d "$src/$f") {
      push @ret, restoreDir("$src/$f", "$dest/$f", $all);
    } else {
      push @ret, restoreFile("$src/$f", "$dest/$f", $all);
    }
  }
  return join("\n", @ret);
}

1;

=pod
=item command
=item summary    restore program files modified by the update command
=item summary_DE durch das update Befehl ge&auml;nderte Programmdateien wiederherstellen
=begin html

<a name="restore"></a>
<h3>restore</h3>
<ul>
  <code>restore list [&lt;filename|directory&gt;]<br>
        restore [&lt;filename|directory&gt;]<br>
        restore -a [&lt;filename|directory&gt;]</code>
  <br><br>
  Restore the files saved previously by the update command. Check the available
  files with the list argument. See also the update command and its restoreDirs
  attribute. After a restore normally a "shutdown restart" is necessary.<br>
  If the -a option is specified, the configuration files are also restored.

</ul>

=end html
=begin html_DE

<a name="restore"></a>
<h3>restore</h3>
<ul>
  <code>restore list [&lt;filename|directory&gt;]<br>
        restore [&lt;filename|directory&gt;]<br>
        restore -a [&lt;filename|directory&gt;]</code>
  <br><br>
  Restauriert die beim update gesicherten Dateien. Mit dem Argument list kann
  man die Liste der verf&&uuml;gbaeren Sicherungen anzeigen, und mit der Angabe
  der direkten Datei/Verzeichnis kann man das zur&uuml;cksichern anstossen.
  Siehe auch das update Befehl, bzw. das restoreDirs Attribut.
  Nach restore ist meistens ein "shutdown restart" notwendig.<br>
  Falls die -a Option spezifiziert wurde, dann werden auch die
  Konfigurationsdateien wiederhergestellt.
</ul>


=end html_DE
=cut
