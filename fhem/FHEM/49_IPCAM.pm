################################################################
# $Id: $
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

sub IPCAM_getSnapshot($);
sub IPCAM_guessFileFormat($);

my %gets = (
  "image"     => "",
  "last"      => "",
  "snapshots" => "",
);

#####################################
sub
IPCAM_Initialize($$)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "IPCAM_Define";
  $hash->{UndefFn}  = "IPCAM_Undef";
  $hash->{GetFn}    = "IPCAM_Get";
  $hash->{AttrList} = "delay credentials path query snapshots storage ".
                      "do_not_notify:1,0 showtime:1,0 ".
                      "loglevel:0,1,2,3,4,5,6 disable:0,1";
}

#####################################
sub
IPCAM_Define($$) {
  my ($hash, $def) = @_;

  # define <name> IPCAM <camip:port>
  # define webcam IPCAM 192.168.1.58:81

  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use 'define <name> IPCAM <camip:port>'"
    if(@a != 3);

  my $name  = $a[0];
  my $auth  = $a[2];

  $hash->{AUTHORITY} = $auth;
  $hash->{STATE}     = "Defined";
  $hash->{SEQ}       = 0;

  return undef;
}

#####################################
sub
IPCAM_Undef($$) {
  my ($hash, $name) = @_;

  delete($modules{IPCAM}{defptr}{$hash->{NAME}});
  RemoveInternalTimer($hash);

  return undef;
}

#####################################
sub
IPCAM_Get($@) {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $seqImages;
  my $seqDelay;
  my $seqWait;
  my $storage = (defined($attr{$name}{storage}) ? $attr{$name}{storage} : "");

  # check syntax
  return "argument is missing @a"
    if(int(@a) != 2);
  # check argument
  return "Unknown argument $a[1], choose on of ".join(" ", sort keys %gets)
    if(!defined($gets{$a[1]}));
  # check attributes
  return "Attribute 'path' is missing. Please add this attribute first!"
    if(!defined($attr{$name}) || (defined($attr{$name}) && !defined($attr{$name}{path})));
  return "Attribute 'path' is defined but empty."
    if(defined($attr{$name}{path}) && $attr{$name}{path} eq "");
  return "Attribute 'query' is defined but empty."
    if(defined($attr{$name}{query}) && $attr{$name}{query} eq "");

  my $arg = $a[1];

  if($arg eq "image") {

    return "Attribute 'storage' is missing. Please add this attribute first!"
      if(!$storage);
      
    $seqImages = int(defined($attr{$name}{snapshots}) ? $attr{$name}{snapshots} : 1);
    $seqDelay  = int(defined($attr{$name}{delay}) ? $attr{$name}{delay} : 0);
    $seqWait   = 0;

    # housekeeping after number of sequence has changed
    my $readings = $hash->{READINGS};
    foreach my $r (sort keys %{$readings}) {
      if($r =~ /snapshot\d+/) {
        my $n = $r;
        $n =~ s/snapshot//;
        delete $readings->{$r} if( $r =~ m/snapshot/ && int($n) > $seqImages);
        Log 5, "IPCAM $name remove old reading: $r";
        
      }
    }
    $hash->{READINGS}{snapshots}{VAL} = 0;
    for (my $i=0;$i<$seqImages;$i++) {
      InternalTimer(gettimeofday()+$seqWait, "IPCAM_getSnapshot", $hash, 0);
      $seqWait = $seqWait + $seqDelay;
    }
    return undef;

  } elsif(defined($hash->{READINGS}{$arg})) {

    if(defined($hash->{READINGS}{$arg}{VAL})) {
      return "$name $arg => $hash->{READINGS}{$arg}{VAL}";
    } else {
      return "$name $arg => undef";
    }

  }

}

#####################################
sub
IPCAM_getSnapshot($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $camAuth = $hash->{AUTHORITY};
  my $camURI;
  my $camPath;
  my $camQuery;
  my $camCredentials;
  my $imageFile;
  my $imageFormat;
  my $lastSnapshot;
  my $snapshot;
  my $dateTime;
  my $seqImages = int(defined($attr{$name}{snapshots}) ? $attr{$name}{snapshots} : 1);
  my $seq = int(defined($hash->{SEQ}) ? $hash->{SEQ} : 0);
  my $storage = (defined($attr{$name}{storage}) ? $attr{$name}{storage} : "");

  if(!$storage) {
    RemoveInternalTimer($hash);
    return "Attribute 'storage' is missing. Please add this attribute first!";
  }

  $camPath  = $attr{$name}{path};
  $camQuery = $attr{$name}{query}
    if(defined($attr{$name}{query}) && $attr{$name}{query} ne "");

  $camURI  = "http://$camAuth/$camPath";
  $camURI .= "?$camQuery" if($camQuery);

  if($camURI =~ m/{USERNAME}/ || $camURI  =~ m/{PASSWORD}/) {

    if(defined($attr{$name}{credentials})) {
      if(!open(CFG, $attr{$name}{credentials})) {
        Log 1, "IPCAM $name Cannot open credentials file: $attr{$name}{credentials}";
        RemoveInternalTimer($hash);
        return undef; 
      }
      my @cfg = <CFG>;
      close(CFG);
      my %credentials;
      eval join("", @cfg);
      $camURI =~ s/{USERNAME}/$credentials{$name}{username}/;
      $camURI =~ s/{PASSWORD}/$credentials{$name}{password}/;
    }
  }

  $dateTime = TimeNow();

  $snapshot = GetFileFromURLQuiet($camURI);

  $imageFormat = IPCAM_guessFileFormat(\$snapshot);

  my @imageTypes = qw(JPEG PNG GIF TIFF BMP ICO PPM XPM XBM SVG);

  if( ! grep { $_ eq "$imageFormat"} @imageTypes) {
    Log 1, "IPCAM $name Wrong or not supported image format: $imageFormat";
    RemoveInternalTimer($hash);
    return undef;
  }

  Log GetLogLevel($name,5), "IPCAM $name Image Format: $imageFormat";

  readingsBeginUpdate($hash);
  if($seq < $seqImages) {
    $seq++;
    $imageFormat = "JPG" if($imageFormat eq "JPEG");
    $lastSnapshot = $name."_snapshot.".lc($imageFormat);
    $imageFile = $name."_snapshot".$seq.".".lc($imageFormat);
    if(!open(FH, ">$storage/$lastSnapshot")) {
      Log 1, "IPCAM $name Can't write $storage/$lastSnapshot: $!";
      RemoveInternalTimer($hash);
      readingsEndUpdate($hash, defined($hash->{LOCAL} ? 0 : 1));
      return undef;
    }
    print FH $snapshot;
    close(FH);
    Log 5, "IPCAM $name snapshot $storage/$lastSnapshot written.";
    if(!open(FH, ">$storage/$imageFile")) {
      Log 1, "IPCAM $name Can't write $storage/$imageFile: $!";
      RemoveInternalTimer($hash);
      readingsEndUpdate($hash, defined($hash->{LOCAL} ? 0 : 1));
      return undef;
    }
    print FH $snapshot;
    close(FH);
    Log 5, "IPCAM $name snapshot $storage/$imageFile written.";
    readingsUpdate($hash,"last",$lastSnapshot);
    $hash->{STATE} = "last: $dateTime";
    $hash->{READINGS}{"snapshot$seq"}{TIME} = $dateTime;
    $hash->{READINGS}{"snapshot$seq"}{VAL}  = $imageFile;
  }

  Log GetLogLevel($name,4), "IPCAM $name image: $imageFile";

  if($seq == $seqImages) {
    readingsUpdate($hash,"snapshots",$seq);
    $seq = 0;
  }
  readingsEndUpdate($hash, defined($hash->{LOCAL} ? 0 : 1));
  $hash->{SEQ}  = $seq;

  return undef;
}

#####################################
sub
IPCAM_guessFileFormat($) {
  my ($src) = shift;
  my $header;
  my $srcHeader;

  open(my $s, "<", $src) || return "can't open source image: $!";
  $src = $s;

  my $reading = read($src, $srcHeader, 64);
  return "error while reading source image: $!" if(!$reading);

  local($_) = $srcHeader;
  return "JPEG" if /^\xFF\xD8/;
  return "PNG"  if /^\x89PNG\x0d\x0a\x1a\x0a/;
  return "GIF"  if /^GIF8[79]a/;
  return "TIFF" if /^MM\x00\x2a/;
  return "TIFF" if /^II\x2a\x00/;
  return "BMP"  if /^BM/;
  return "ICO"  if /^\000\000\001\000/;
  return "PPM"  if /^P[1-6]/;
  return "XPM"  if /(^\/\* XPM \*\/)|(static\s+char\s+\*\w+\[\]\s*=\s*{\s*"\d+)/;
  return "XBM"  if /^(?:\/\*.*\*\/\n)?#define\s/;
  return "SVG"  if /^(<\?xml|[\012\015\t ]*<svg\b)/;
  return "unknown";
}

# vim: ts=2:et

1;
