# $Id$
# vim: ts=2:et
################################################################
#
#  Copyright notice
#
#  (c) 2013 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This file is part of fhem.
#
#  Fhem is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  Fhem is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
################################################################

package main;
use strict;
use warnings;
use Time::Local;

sub CommandNotice($$);
sub notice_Confirmation($$$);
sub notice_Get($$$);
sub notice_List($$);
sub notice_Read($$$);

use vars qw(@locale);
@locale = qw(de en);

my $confirmationFile = ".notice-confirmation";

########################################
sub
notice_Initialize($$)
{
  my %hash = (
    Fn  => "CommandNotice",
    Hlp => "[confirm|list|reset|view] <id>,view and confirmation of system messages",
  );
  $cmds{notice} = \%hash;
}

########################################
sub
CommandNotice($$)
{
  my ($cl,$param) = @_;
  my $modPath   = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $modDir    = "$modPath/FHEM";
  my $noticeDir = "$modDir/FhemUtils";
  my $name      = "notice";
  my @commands  = qw(confirm condition get list position reset view);
  my $ret;

  # split arguments
  my @args = split(/ +/,$param);

  $args[0] = "list" if(!defined($args[0]));

  if(!@args || $args[0] ~~ @commands) {
    my $cmd = $args[0];

    if($cmd eq "list") {
      # view all a list of notes
      my $type = "all";
      if(defined($args[1])) {
        $type = $args[1];
      }
      $ret = notice_List($noticeDir,$type);

    } elsif($cmd eq "view") {
      # view a single note
      return "notice view needs an argument"
        if(!defined($args[1]));

      my $id = $args[1];
      my $notice_ref = {};
      $notice_ref = notice_Read($notice_ref,$noticeDir,$args[1]);
      return "Nothing to view. Maybe wrong ID?"
        if(!keys %$notice_ref);

      my $locale = "en";
      my $header = 1;
      if(@args == 3) {
        $locale = ($args[2] ~~ @locale) ? $args[2] : "en";
        $header = ($args[2] eq "noheader") ? 0 : 1;
      } elsif(@args == 4) {
        if($args[2] ~~ @locale) {
          $locale = ($args[2] ~~ @locale) ? $args[2] : "en";
          $header = ($args[3] eq "noheader") ? 0 : 1;
        } elsif($args[2] eq "noheader") {
          $header = ($args[2] eq "noheader") ? 0 : 1;
          $locale = ($args[3] ~~ @locale) ? $args[3] : "en";
        }
      }

      if($header) {
        $ret  = sprintf("%-10s: %s\n","ID",$id);
        $ret .= sprintf("%-10s: %s\n","From",$notice_ref->{$id}{from})
          if(exists $notice_ref->{$id}{from});
        $ret .= sprintf("%-10s: %s\n","Date",$notice_ref->{$id}{date})
          if(exists $notice_ref->{$id}{from});
        $ret .= sprintf("%-10s: %s\n","Expire",$notice_ref->{$id}{expire})
          if(exists $notice_ref->{$id}{expire});
        $ret .= sprintf("%-10s: %s\n","Title",$notice_ref->{$id}{locale}{$locale}{title})
          if(exists $notice_ref->{$id}{locale}{$locale}{title});
        $ret .= "### Start of Text\n";
      }

      foreach my $line (@{$notice_ref->{$id}{locale}{$locale}{text}}) {
        $ret .= $line."\n";
      }

      $ret .= "### End of Text\n" if($header);

    } elsif($cmd eq "confirm") {
      # confirm a note
      return "notice view needs an argument"
        if(!defined($args[1]));

      my $id = $args[1];
      my $notice_ref = {};
      $notice_ref = notice_Read($notice_ref,$noticeDir,$id);
      return "Nothing to view. Maybe wrong ID?"
        if(!keys %$notice_ref);

      if(!defined($notice_ref->{$id}{confirm}) ||
        (defined($notice_ref->{$id}{confirm}) && $notice_ref->{$id}{confirm} == 0) ) {
        return "$id needs no confirmation.";
      } else {
        my $confirmation = 1;
        if(@args > 2) {
          shift @args;
          shift @args;
          $confirmation = "@args";
        }
        $ret = notice_Confirmation($noticeDir,$id,$confirmation);
      }

    } elsif($cmd eq "get") {
      # get list of notes
      my $type  = (defined($args[1])) ? $args[1] : "all";
      my $value = (defined($args[2]) && $args[2] =~ /[0-8]/) ? $args[2] : 0;
      return notice_Get($noticeDir,$type,$value);

    } elsif($cmd eq "position") {
      # returns position of notice
      return "notice position needs an argument"
        if(!defined($args[1]));

      my $id = $args[1];
      my $notice_ref = {};
      $notice_ref = notice_Read($notice_ref,$noticeDir,$id);
      return (defined($notice_ref->{$id}{position})) ? $notice_ref->{$id}{position} : undef;
    } elsif($cmd eq "reset") {
      # reset all confirmations
      if(-e "$noticeDir/$confirmationFile") {
        if(defined($args[1] && lc($args[1]) eq "yes")) {
          my $cmdret = unlink "$noticeDir/$confirmationFile";
          if(!$cmdret) {
            $ret = "an error occured while deleting file '$noticeDir/$confirmationFile': $!";
          } else {
            $ret = "all confirmations deleted successfully.";
          }
        } else {
          $ret  = "This command delete all confirmations.\n";
          $ret .= "If you really want to do this, call 'notice reset yes'";
          return $ret;
        }
      } else {
        $ret = "nothing to do. no confirmation exists.";
      }
    } elsif($cmd eq "condition") {
      # supplies a value of an embedded test
      return "condition view needs an argument"
        if(!defined($args[1]));

      my $id = $args[1];
      my $notice_ref = {};
      $notice_ref = notice_Read($notice_ref,$noticeDir,$id);
      return "Nothing to view. Maybe wrong ID?"
        if(!keys %$notice_ref);

      my %conditions;
      foreach my $key (sort %{$notice_ref->{$id}}) {
        my $order;
        if(lc($key) =~ /^key_/) {
          (undef,$order) = split("_",$key);
          if(defined($notice_ref->{$id}{"val_$order"})) {
            $conditions{$notice_ref->{$id}{$key}}{value} = ($notice_ref->{$id}{"val_$order"}) ?
                                                    eval $notice_ref->{$id}{"val_$order"} : undef;
            $conditions{$notice_ref->{$id}{$key}}{condition} = (defined($notice_ref->{$id}{"con_$order"})) ?
                                                    $notice_ref->{$id}{"con_$order"} : "";
            Log 5, "notice id:$id condition key:".$notice_ref->{$id}{$key} . " " .
                   "value:" .$conditions{$notice_ref->{$id}{$key}}{value} . " " .
                   "condition:".$notice_ref->{$id}{"val_$order"};
          }
        }
      }

      if(keys %conditions) {
        foreach my $key (sort keys %conditions) {
          Log 5, "notice id:$id condition key:$key value:$conditions{$key}{value} condition:$conditions{$key}{condition}";
          $ret .= "$key:$conditions{$key}{value}:$conditions{$key}{condition}";
          $ret .= "|";
        }
        chop $ret;
        return $ret;
      } else {
        return undef;
      }
      
    }


  } else {
    return "Unknown argument $args[0]; choose one of " . join(" ", sort @commands);
  }

  return $ret;
}

########################################
sub
notice_List($$)
{
  my ($noticeDir,$type) = @_;
  $type = ($type eq "all") ? ".*" : $type;
  my @dir;
  my $ret;

  if(opendir(my $DH, "$noticeDir")) {
    @dir = grep { /^$type-.*\d+$/ && -f "$noticeDir/$_" } readdir($DH);
    closedir $DH;

    my $notice_ref = {};
    foreach my $file (@dir) {
      $notice_ref = notice_Read($notice_ref,$noticeDir,$file);
    }

    my @col1 = sort keys %{$notice_ref};
    my $col1 = (reverse sort { $a <=> $b } map { length($_) } @col1)[0];
    if(!keys %$notice_ref) {
      $ret = "==> nothing found";
    } else {

      my @confirmationFile;
      if(open(my $FH, "<$noticeDir/$confirmationFile")) {
        Log 5, "notice read file: $noticeDir/$confirmationFile";
        while(my $line = <$FH>) {
          chomp $line;
          push(@confirmationFile,$line);
        }
        close $FH;
      }

      foreach my $lang (sort @locale) {
        $ret .= "==> Language: $lang\n";
        $ret .= sprintf("  %-*s %-10s %-10s %-10s %s\n",$col1,"ID","Published","Expired","Confirmed","Description");
        foreach my $notice (sort keys %{$notice_ref}) {
          my ($dateTime,$oldConfirmation);
          next if(!exists $notice_ref->{$notice}{locale}{$lang});
          foreach my $line (@confirmationFile) {
            if($line =~ /^$notice\s*/) {
              ($dateTime,$oldConfirmation) = $line =~ /^.*\s*(\d{4}-\d{2}-\d{2})\s\d{2}:\d{2}:\d{2}\s*(.*)$/;
              $dateTime = substr($dateTime,8,2).".".substr($dateTime,5,2).".".substr($dateTime,0,4);
            }
          }
          $ret .= sprintf("  %-*s %-10s %-10s %-10s %s\n",
                          $col1,
                          $notice,
                          (defined($notice_ref->{$notice}{publish}) && $notice_ref->{$notice}{publish} ne "0") ?
                            $notice_ref->{$notice}{publish} : "actually",
                          (defined($notice_ref->{$notice}{expire}) && $notice_ref->{$notice}{expire} ne "0") ?
                            $notice_ref->{$notice}{expire} : "never",
                          ($dateTime) ? $dateTime :
                            (defined($notice_ref->{$notice}{confirm}) && $notice_ref->{$notice}{confirm} ne "0") ?
                              "no" : "not needed",
                          $notice_ref->{$notice}{locale}{$lang}{title});
        }
        $ret .= "\n";
      }
      chomp $ret;
    }

  } else {
    $ret = "update could not open directory '$noticeDir': $!";
    Log 1, $ret;
  }

  return $ret;
}

########################################
# value: 0 = all
#        1 = not confirmed
#        2 = not expired
#        3 = not confirmed, not expired
#        4 = published
#        5 = not confirmed, published
#        6 = not expired, published
#        7 = not confirmed, not expired, published
#        8 = confirmed
sub
notice_Get($$$)
{
  my ($noticeDir,$type,$value) = @_;
  $value = ($value) ? $value : 0;
  my @now = localtime();
  
  my @dir;

  if(opendir(my $DH, "$noticeDir")) {
    my $search = ($type eq "all") ? ".*" : $type;
    @dir = grep { /^$search-.*\d+$/ && -f "$noticeDir/$_" } readdir($DH);
    closedir $DH;
  } else {
    Log 1, "notice could not open directory '$noticeDir': $!";
  }

  my @confirmed;
  if($value == 1 || $value == 3 || $value == 5 || $value == 7 || $value == 8) {
    if(open(my $FH, "<$noticeDir/$confirmationFile")) {
      Log 5, "notice read file: $noticeDir/$confirmationFile";
      while(my $line = <$FH>) {
        my ($id,undef) = split(" ",$line);
        if($type eq "all") {
          push(@confirmed,$id);
        } elsif($id =~ /^$type/) {
          push(@confirmed,$id);
        }
      }
      close $FH;
    }
  }

  if(@dir) {
    my $notice_ref = {};
    foreach my $file (sort @dir) {
      $notice_ref = notice_Read($notice_ref,$noticeDir,$file);
    }

    if(!keys %$notice_ref) {
      return undef;
    } else {

      my $ret;
      if($value == 0) {
        # all
        $ret = join(",",sort @dir);
      } elsif($value == 1) {
        # not confirmed
        $ret = _notConfirmed($notice_ref,@confirmed);
        Log 5, "notice notConfirmed:$ret";
      } elsif($value == 2) {
        # not expired
        $ret = _notExpired($notice_ref,@now);
        Log 5, "notice notExpired:$ret";
      } elsif($value == 3) {
        # not confirmed, not expired
        my $notConfirmed = _notConfirmed($notice_ref,@confirmed);
        my $notExpired   = _notExpired($notice_ref,@now);
        Log 5, "notice notConfirmed:$notConfirmed notExpired:$notExpired";
        my @merged;
        foreach my $id (@dir) {
          push (@merged, $id) if($notConfirmed =~ /$id/ && $notExpired =~ /$id/);
        }
        $ret = join(",",sort @merged);
      } elsif($value == 4) {
        # published
        $ret = _published($notice_ref,@now);
        Log 5, "notice published:$ret";
      } elsif($value == 5) {
        # not confirmed, published
        my $notConfirmed = _notConfirmed($notice_ref,@confirmed);
        my $published    = _published($notice_ref,@now);
        Log 5, "notice notConfirmed:$notConfirmed published:$published";
        my @merged;
        foreach my $id (sort @dir) {
          push (@merged, $id) if($notConfirmed =~ /$id/ && $published =~ /$id/);
        }
        $ret = join(",",sort @merged);
      } elsif($value == 6) {
        # not expired, published
        my $notExpired   = _notExpired($notice_ref,@now);
        my $published    = _published($notice_ref,@now);
        Log 5, "notice notExpired:$notExpired published:$published";
        my @merged;
        foreach my $id (sort @dir) {
          push (@merged, $id) if($notExpired =~ /$id/ && $published =~ /$id/);
        }
        $ret = join(",",sort @merged);
      } elsif($value == 7) {
        # not confirmed, not expired, published
        my $notConfirmed = _notConfirmed($notice_ref,@confirmed);
        my $notExpired   = _notExpired($notice_ref,@now);
        my $published    = _published($notice_ref,@now);
        Log 5, "notice notConfirmed:$notConfirmed notExpired:$notExpired published:$published";
        my @merged;
        foreach my $id (sort @dir) {
          push (@merged, $id) if($notConfirmed =~ /$id/ && $notExpired =~ /$id/ && $published =~ /$id/);
        }
        $ret = join(",",sort @merged);
      } elsif($value == 8) {
        # confirmed
        $ret = join(",",sort @confirmed);
      }

      return $ret;

    }

  } else {
    return undef;
  }

}

########################################
sub
_notConfirmed($@)
{
  my ($notice_ref,@confirmed) = @_;
  my @ret;
  foreach my $id (sort keys %{$notice_ref}) {
    push(@ret,$id)
      if(defined($notice_ref->{$id}{confirm}) &&
         $notice_ref->{$id}{confirm} != 0 && !grep (m/^$id$/,@confirmed));
  }
  return join(",",@ret);
}

########################################
sub
_notExpired($@)
{
  my ($notice_ref,@now) = @_;
  my @ret;
  foreach my $id (sort keys %{$notice_ref}) {
    my ($d,$m,$y);
    if(defined($notice_ref->{$id}{expire}) && $notice_ref->{$id}{expire} =~ /\d{2}.\d{2}.\d{4}/) {
      $d = substr($notice_ref->{$id}{expire},0,2);
      $m = substr($notice_ref->{$id}{expire},3,2)-1;
      $y = substr($notice_ref->{$id}{expire},6,4)-1900;
    }
    push(@ret,$id)
      if(!defined($notice_ref->{$id}{expire}) ||
        (defined($notice_ref->{$id}{expire}) && $notice_ref->{$id}{expire} !~ /\d{2}.\d{2}.\d{4}/) ||
        (defined($notice_ref->{$id}{expire}) && $notice_ref->{$id}{expire} =~ /\d{2}.\d{2}.\d{4}/ &&
        notice_epochDate($now[3],$now[4],$now[5]) <= notice_epochDate($d,$m,$y)));
  }
  return join(",",@ret);
}

########################################
sub
_published($@)
{
  my ($notice_ref,@now) = @_;
  my @ret;
  foreach my $id (sort keys %{$notice_ref}) {
    my ($d,$m,$y);
    if(defined($notice_ref->{$id}{publish}) && $notice_ref->{$id}{publish} =~ /\d{2}.\d{2}.\d{4}/) {
      $d = substr($notice_ref->{$id}{publish},0,2);
      $m = substr($notice_ref->{$id}{publish},3,2)-1;
      $y = substr($notice_ref->{$id}{publish},6,4)-1900;
    }
    push(@ret,$id)
      if(!defined($notice_ref->{$id}{publish}) ||
        (defined($notice_ref->{$id}{publish}) && $notice_ref->{$id}{publish} !~ /\d{2}.\d{2}.\d{4}/) ||
        (defined($notice_ref->{$id}{publish}) && $notice_ref->{$id}{publish} =~ /\d{2}.\d{2}.\d{4}/ &&
        notice_epochDate($now[3],$now[4],$now[5]) >= notice_epochDate($d,$m,$y)));
  }
  return join(",",@ret);
}

########################################
sub
notice_epochDate($$$)
{
  my ($day,$month,$year) = @_;
  return timelocal("0","0","0",$day,$month,$year);
}

########################################
sub
notice_Confirmation($$$)
{
  my ($noticeDir,$id,$confirmation) = @_;
  my @file;
  my $confirmed = 0;
  my $oldConfirmation = "";
  my $dateTime;
  my $now = TimeNow();
  my $ret;

  if(open(my $FH, "<$noticeDir/$confirmationFile")) {
    Log 5, "notice read file: $noticeDir/$confirmationFile";
    while(my $line = <$FH>) {
      chomp $line;
      if($line =~ /^$id\s*/) {
        ($dateTime,$oldConfirmation) = $line =~ /^.*\s*(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})\s*(.*)$/;
        $confirmed = 1;
      }
      push(@file,$line);
    }
    close $FH;
  }

  if($confirmed == 0) {
    push(@file,"$id $now $confirmation\n");
  }

  if($oldConfirmation eq $confirmation) {
    $ret = "$id already confirmed on $dateTime: $oldConfirmation";
  } else {
    if(open(my $FH, ">$noticeDir/$confirmationFile")) {
      Log 5, "notice write file: $noticeDir/$confirmationFile";
      foreach my $line (sort @file) {
        if($line =~ /^$id\s*/) {
          print $FH "$id $now $confirmation\n";
          if(!$oldConfirmation) {
            $ret = "$id confirmed on $now: $confirmation";
          } else {
            $ret = "$id changed on $now: $confirmation";
          }
          Log 1, "notice $ret";
        } else {
          print $FH "$line\n";
        }
      }
    } else {
      $ret = "error while writing file: $noticeDir/$confirmationFile: $!";
      Log 1, "notice $ret";
    }
  }

  return $ret;
}

########################################
sub
notice_Read($$$)
{
  my ($notice_ref,$noticeDir,$noticeFile) = @_;
  my %notice = %$notice_ref if($notice_ref && ref($notice_ref) eq "HASH");

  if(open(my $FH, "<$noticeDir/$noticeFile")) {
    Log 5, "notice read file: $noticeDir/$noticeFile";
    my $key;
    my $value;
    my $locale;
    while(my $line = <$FH>) {
      chomp $line;
      if(uc($line) =~ /^#\s.*:.*$/ && uc($line) !~ /^#\s*NOTICE_\S{2}$/ && uc($line) !~ /^#\s*TITLE_\S{2}\s*:.*$/) {
        ($key,$value) = $line =~ /^#\s*(.*)\s*:\s*(.*)$/;
        $notice{$noticeFile}{lc($key)} = $value;
      } elsif (uc($line) =~ /^#\s*TITLE_\S{2}\s*:.*$/) {
        ($locale,$value) = $line =~ /^#\s*TITLE_(\S{2})\s*:\s*(.*)$/;
        $notice{$noticeFile}{locale}{lc($locale)}{title} = $value;
      } elsif (uc($line) =~ /^#\s*NOTICE_\S{2}$/) {
        ($locale) = $line =~ /^#\s*NOTICE_(\S{2})$/;
      } else {
        $locale = "EN" if(!$locale);
        push @{ $notice{$noticeFile}{locale}{lc($locale)}{text} }, $line;
      }
    }
    close $FH;
  } else {
    Log 1, "update could not open notice '$noticeDir/$noticeFile': $!";
    return undef;
  }
  return \%notice;
}

=pod
=begin html

<a name="notice"></a>
<h3>notice</h3>
<ul>
  <code>notice [confirm [value]|list [&lt;keyword&gt;]|reset [yes]|view &lt;id&gt; [noheader|[de|en]]]</code><br>
  <br>
    View and confirmation of system messages.
    <br>
    <br>
    During an update or a system start from FHEM sometimes it is necessary to
    inform the user about important changes or additions. It may be necessary
    to confirm a system message by the user.
    <br>
    <br>
    By entering the command '<code>notice</code>' a list of all messages is displayed.
    Are messages available in different languages, they are ordered by language.
    <br>
    Example:
    <blockquote><code><pre>
    fhem&gt; notice
    ==&gt; Language: de
      ID                  Published  Expired    Confirmed  Description
      advice-20130128-002 actually   never      not needed kurze beschreibung
      update-20130128-002 31.01.2013 01.02.2013 no         kurze beschreibung

    ==&gt; Language: en
      ID                  Published  Expired    Confirmed  Description
      advice-20130128-001 actually   never      no         short description
      advice-20130128-002 actually   never      not needed short description
      update-20130128-001 actually   never      no         short description
      update-20130128-002 31.01.2013 01.02.2013 no         short description
    </pre></code></blockquote>
    By entering '<code>notice list &lt;keyword&gt;</code>' the output of the list contains only
    available messages that starts with '<code>&lt;keyword&gt;</code>'.
    <br>
    Example:
    <blockquote><code><pre>
    fhem&gt; notice list update
    ==&gt; Language: de
      ID                  Published  Expired    Confirmed  Description
      update-20130128-002 31.01.2013 01.02.2013 no         kurze beschreibung

    ==&gt; Language: en
      ID                  Published  Expired    Confirmed  Description
      update-20130128-001 actually   never      no         short description
      update-20130128-002 31.01.2013 01.02.2013 no         short description
    </pre></code></blockquote>
    To display a single message, enter the command '<code>notice view &lt;id&gt;</code>' where <code>id</code>
    is the Identifier of the message. You can use the optional parameter <code>noheader</code>
    or the language codes <code>de</code> or <code>en</code> to display the message
    without the header informations or in your prefered language if available.
    <br>
    Example:
    <blockquote><code><pre>
    fhem&gt; notice view advice-20130128-002 de
    ID        : advice-20130128-002
    From      : M. Fischer
    Date      : 28.01.2013
    Expire    : 0
    Title     : kurze beschreibung
    ### Start of Text
    test-advice

    dies ist ein test

    001
    ### End of Text
    </pre></code></blockquote>
    If it is necessary to confirm a message, this is be done by entering '<code>notice confirm &lt;id&gt; [value]</code>'.
    The optional argument <code>value</code> will also be stored with the confirmation.
    <br>
    Example:
    <blockquote><code><pre>
    fhem&gt; notice confirm update-20130128-001 foo:bar
    update-20130128-001 confirmed on 2013-01-29 20:58:57: foo:bar
    </pre></code></blockquote>
    Sometimes it is necessary to reset all confirmations. This is be done by entering
    '<code>notice reset</code>'.
    <br>
    Example:
    <blockquote><code><pre>
    fhem&gt; notice reset
    This command delete all confirmations.
    If you really want to do this, call 'notice reset yes'
    </pre></code></blockquote>
    <br>
    <strong>For developers only:</strong>
    <br>
    <br>
    <code>notice [condition &lt;id&gt;|get &lt;keyword&gt; &lt;value&gt;|position &lt;id&gt;]</code><br>
    <br>
    <br>
    These arguments are normally not needed by any user.
    <br>
    <br>
    A message may optionally contains one or more code snippets. The argument <code>condition</code> supplies the determined
    value(s) of the embedded test(s) as a key:value pair. If more than one pair returned, they they are seperated by <code>|</code>.
    It is possible to define your own rules for a condition, like <code>!empty</code> or <code>&gt;>5</code> and so on. An example
    of a condition is shown in the below example message file.
    Example:
    <blockquote><code><pre>
    fhem&gt; notice condition update-20130127-001
    configfile:./fhem.cfg|sendStatistics:never:!empty
    </pre></code></blockquote>
    The argument <code>get</code>, followed by a <code>keyword</code> and a number from 0 to 8, returns a
    comma seperated list of message ids.
    The possible outputs are:
    <ul>
      <li><code>0 returns a list of all messages.</code></li>
      <li><code>1 returns a list of unconfirmed messages.</code></li>
      <li><code>2 returns a list of messages that are not expired.</code></li>
      <li><code>3 returns a list of messages that are not expired and unconfirmed.</code></li>
      <li><code>4 returns a list of published messages.</code></li>
      <li><code>5 returns a list of unconfirmed and published messages.</code></li>
      <li><code>6 returns a list of published messages that are not expired.</code></li>
      <li><code>7 returns a list of published, unconfirmed and not expired messages.</code></li>
      <li><code>8 returns a list of confirmed messages.</code></li>
    </ul>
    Example:
    <blockquote><code><pre>
    fhem&gt; notice get all 2
    advice-20130128-001,advice-20130128-002,update-20130128-001,update-20130128-002
    </pre></code></blockquote>
    The argument <code>position</code> followed by an <code>&lt;id&gt;</code> returns the view position of a message if defined.
    <br>
    Example:
    <blockquote><code><pre>
    fhem&gt; notice position update-20130128-001
    before
    </pre></code></blockquote>
    Example of a message file:
    <blockquote><code><pre>
    # FROM: M. Fischer
    # DATE: 28.01.2013
    # CONFIRM: 1
    # PUBLISH: 31.01.2013
    # EXPIRE: 01.02.2013
    # KEY_1: sendStatistics
    # VAL_1: AttrVal("global","sendStatistics",undef);
    # CON_1: !empty
    # KEY_2: configfile
    # VAL_2: AttrVal("global","configfile",undef);
    # POSITION: top
    # TITLE_DE: kurze beschreibung
    # NOTICE_DE
    Hinweis:

    dies ist ein test
    # TITLE_EN: short description
    # NOTICE_EN
    Advice:

    this is a test
    </pre></code></blockquote>
    The keywords '<code>FROM, DATE, CONFIRM, PUBLISH, EXPIRE, TITLE_DE, TITLE_EN, NOTICE_DE, NOTICE_EN</code>' are fixed.
    It is possible to add any key:value string to these files. Also it is possible to set only one or both keywords of
    '<code>TITLE_DE, TITLE_EN</code>' and '<code>NOTICE_DE, NOTICE_EN</code>'.
</ul>

=end html
1;
