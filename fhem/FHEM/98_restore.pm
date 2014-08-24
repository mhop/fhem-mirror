################################################################
# $Id$

package main;
use strict;
use warnings;
use File::Copy qw(cp);

sub CommandUpdate($$);
sub restoreFile($$);
sub restoreDir($$);

########################################
sub
restore_Initialize($$)
{
  my %hash = (
    Fn  => "CommandRestore",
    Hlp => "[list] [<filename|directory>],restore files saved by update",
  );
  $cmds{restore} = \%hash;
}

########################################
sub
CommandRestore($$)
{
  my ($cl,$param) = @_;
  my @args = split(/ +/,$param);
  my $list = (@args > 0 && $args[0] eq "list");
  shift @args if($list);
  my $filename = shift @args;
  my $dest = $attr{global}{modpath};
  my $src = "$dest/restoreDir";

  $list = 1 if(!$list && !$filename);
  return "Usage: restore [list] filename|directory"
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

  $filename .= "/" if($filename !~ m,/,); # needed for the regexp below
  $filename =~ m,^([^/]*)/(.*)$,;
  $src = "$src/$filename";
  $dest = "$dest/$2" if($2);

  return (-f $src ? restoreFile($src, $dest) : restoreDir($src, $dest)).
        "\n\nrestore finished";
}

sub
restoreFile($$)
{
  my ($src, $dest) = @_;
  cp($src, $dest) || return "cp $src $dest failed: $!";
  return "restore $dest";
}

sub
restoreDir($$)
{
  my ($src, $dest, $dh, @ret) = @_;
  opendir($dh, $src) || return "opendir $src: $!";
  my @files = sort grep { $_ ne "." && $_ ne ".." } readdir($dh);
  closedir($dh);
  foreach my $f (@files){
    if(-d "$src/$f") {
      push @ret, restoreDir("$src/$f", "$dest/$f");
    } else {
      push @ret, restoreFile("$src/$f", "$dest/$f");
    }
  }
  return join("\n", @ret);
}

1;

=pod
=begin html

<a name="restore"></a>
<h3>restore</h3>
<ul>
  <code>restore list [<filename|directory>]<br>
        restore [<filename|directory>]</code>
  <br><br>
  Restore the files saved previously by the update command. Check the available
  files with the list argument. See also the update command and its restoreDirs
  attribute. After a restore normally a "shutdown restart" is necessary.
</ul>

=end html
=begin html_DE

<a name="restore"></a>
<h3>restore</h3>
<ul>
  <code>restore list [<filename|directory>]<br>
        restore <filename|directory></code>
  <br><br>
  Restauriert die beim update gesicherten Dateien. Mit dem Argument list kann
  man die Liste der verf&&uuml;gbaeren Sicherungen anzeigen, und mit der Angabe
  der direkten Datei/Verzeichnis kann man das zur&uuml;cksichern anstossen.
  Siehe auch das update Befehl, bzw. das restoreDirs Attribut.
  Nach restore ist meistens ein "shutdown restart" notwendig.
</ul>


=end html_DE
=cut
