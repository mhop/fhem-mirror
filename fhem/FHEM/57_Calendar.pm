#
#
# 57_Calendar.pm
# written by Dr. Boris Neubert 2012-05-20
# e-mail: omega at online dot de
#
##############################################
# $Id$


use strict;
use warnings;
use Time::Local;


##############################################

package main;

sub debug($) {
  my ($msg)= @_;
  Log 1, "DEBUG: " . $msg;
}


#####################################
#
# ICal
# the ical format is governed by RFC2445 http://www.ietf.org/rfc/rfc2445.txt
#
#####################################

package ICal::Entry;

sub new {
  my $class= shift;
  my ($type)= @_;
  my $self= {};
  bless $self, $class;
  $self->{type}= $type;
  $self->{entries}= [];
  #main::debug "NEW: $type";
  return($self);
}

sub addproperty {
  my ($self,$line)= @_;
  #main::debug $line;
  my ($property,$parameter)= split(":", $line);
  my ($key,$parts)= split(";", $property,2);
  $parts= "" unless(defined($parts));
  $self->{properties}{$key}= {
      PARTS => "$parts",
      VALUE => "$parameter"
  };
  #main::debug "ADDPROPERTY: ". $self ." key= $key, parts= $parts, value= $parameter";
  #main::debug "WE ARE " .  $self->{properties}{$key}{VALUE};
}

sub value {
  my ($self,$key)= @_;
  return $self->{properties}{$key}{VALUE};
}

sub parts {
  my ($self,$key)= @_;
  return split(";", $self->{properties}{$key}{PARTS});
}

sub parse {
  my ($self,@ical)= @_;
  $self->parseSub(0, @ical);
}

sub parseSub {
  my ($self,$ln,@ical)= @_;
  #main::debug "ENTER @ $ln";
  while($ln<$#ical) {
    my $line= $ical[$ln];
    chomp $line;
    $line =~ s/[\x0D]//; # chomp will not remove the CR
    #main::debug "$ln: $line";
    $ln++;
    last if($line =~ m/^END:.*$/);
    if($line =~ m/^BEGIN:(.*)$/) {
      my $entry= ICal::Entry->new($1);
      push $self->{entries}, $entry;
      $ln= $entry->parseSub($ln,@ical);
    } else {
      $self->addproperty($line);
    }
  }
  #main::debug "BACK";
  return $ln;
}

sub asString() {
  my ($self,$level)= @_;
  $level= "" unless(defined($level));
  my $s= $level . $self->{type} . "\n";
  $level .= "  ";
  for my $key (keys %{$self->{properties}}) {
    $s.= $level . "$key: ". $self->value($key) . "\n";
  }
  my @entries=  @{$self->{entries}};
  for(my $i= 0; $i<=$#entries; $i++) {
    $s.= $entries[$i]->asString($level);
  }
  return $s;
}

#####################################
#
# Event
#
#####################################

package Calendar::Event;

sub new {
  my $class= shift;
  my $self= {};
  bless $self, $class;
  $self->{_state}= "";
  $self->setState("new");
  $self->{alarmTriggered}= 0;
  $self->{startTriggered}= 0;
  $self->{endTriggered}= 0;
  return($self);
}

sub uid {
  my ($self)= @_;
  return $self->{uid};
}

sub setState {
  my ($self,$state)= @_;
  #main::debug "Before setState $state: States(" . $self->uid() . ") " . $self->{_previousState} . " -> " . $self->{_state};
  $self->{_previousState}= $self->{_state};
  $self->{_state}= $state;
  #main::debug "After setState $state: States(" . $self->uid() . ") " . $self->{_previousState} . " -> " . $self->{_state};
  return $state;
}

sub touch {
  my ($self,$t)= @_;
  $self->{_lastSeen}= $t;
  return $t;
}

sub lastSeen {
  my ($self)= @_;
  return $self->{_lastSeen};
}

sub state {
  my ($self)= @_;
  return $self->{_state};
}

sub lastModified {
  my ($self)= @_;
  return $self->{lastModified};
}

sub isState {
  my ($self,$state)= @_;
  return $self->{_state} eq $state ? 1 : 0;
}

sub isNew {
  my ($self)= @_;
  return $self->isState("new");
}

sub isKnown {
  my ($self)= @_;
  return $self->isState("known");
}

sub isUpdated {
  my ($self)= @_;
  return $self->isState("updated");
}

sub isDeleted {
  my ($self)= @_;
  return $self->isState("deleted");
}


sub stateChanged {
  my ($self)= @_;
  main::debug "States(" . $self->uid() . ") " . $self->{_previousState} . " -> " . $self->{_state};
  return $self->{_state} ne $self->{_previousState} ? 1 : 0;
}

# converts a date/time string to the number of non-leap seconds since the epoch
# 20120520T185202Z: date/time string in ISO8601 format, time zone GMT
# 20120520:         a date string has no time zone associated
sub tm {
  my ($t)= @_;
  #debug "convert $t";
  my ($year,$month,$day)= (substr($t,0,4), substr($t,4,2),substr($t,6,2));
  if(length($t)>8) {
      my ($hour,$minute,$second)= (substr($t,9,2), substr($t,11,2),substr($t,13,2));
      return Time::Local::timegm($second,$minute,$hour,$day,$month-1,$year-1900);
  } else {
      #debug "$day $month $year";
      return Time::Local::timelocal(0,0,0,$day,$month-1,$year-1900);
  }
}

#      DURATION RFC2445
#      dur-value  = (["+"] / "-") "P" (dur-date / dur-time / dur-week)
#
#      dur-date   = dur-day [dur-time]
#      dur-time   = "T" (dur-hour / dur-minute / dur-second)
#      dur-week   = 1*DIGIT "W"
#      dur-hour   = 1*DIGIT "H" [dur-minute]
#      dur-minute = 1*DIGIT "M" [dur-second]
#      dur-second = 1*DIGIT "S"
#      dur-day    = 1*DIGIT "D"
#
#      example: -P0DT0H30M0S
sub d {
  my ($d)= @_;

  my $sign= 1;
  my $t= 0;

  my @c= split("P", $d);
  $sign= -1 if($c[0] eq "-");
  shift @c if($c[0] =~ m/[\+\-]/);
  my ($dw,$dt)= split("T", $c[0]);
  if($dw =~ m/(\d+)D$/) {
    $t+= 86400*$1; # days
  } elsif($dw =~ m/(\d+)W$/) {
    $t+= 604800*$1; # weeks
  }
  if($dt =~ m/^(\d+)H(\d+)M(\d+)S$/) {
    $t+= $1*3600+$2*60+$3;
  }
  $t*= $sign;
  #main::debug "sign: $sign  dw: $dw  dt: $dt   t= $t";
  return $t;
}

sub ts {
  my ($tm)= @_;
  my ($second,$minute,$hour,$day,$month,$year,$wday,$yday,$isdst)= localtime($tm);
  return sprintf("%02d.%02d.%4d %02d:%02d:%02d", $day,$month+1,$year+1900,$hour,$minute,$second);
}

sub fromVEvent {
  my ($self,$vevent)= @_;

  $self->{uid}= $vevent->value("UID");
  $self->{start}= tm($vevent->value("DTSTART"));
  $self->{end}= tm($vevent->value("DTEND"));
  $self->{lastModified}= tm($vevent->value("LAST-MODIFIED"));
  $self->{summary}= $vevent->value("SUMMARY");
  #$self->{summary}=~ s/;/,/g;

  # alarms
  my @valarms= grep { $_->{type} eq "VALARM" } @{$vevent->{entries}};
  my @durations= sort map { d($_->value("TRIGGER")) } @valarms;
  if(@durations) {
    $self->{alarm}= $self->{start}+$durations[0];
  } else {
    $self->{alarm}= undef;
  }
}

# sub asString {
#   my ($self)= @_;
#   return sprintf("%s  %s(%s);%s;%s;%s;%s",
#     $self->state(),
#     $self->{uid},
#     ts($self->{lastModified}),
#     $self->{alarm} ? ts($self->{alarm}) : "",
#     ts($self->{start}),
#     ts($self->{end}),
#     $self->{summary}
#   );
# }

sub summary {
  my ($self)= @_;
  return $self->{summary};
}


sub asText {
  my ($self)= @_;
  #return sprintf("%s-%s %s",
  #  ts($self->{start}),
  #  ts($self->{end}),
  #  $self->{summary}
  #);
  return sprintf("%s %s",
    ts($self->{start}),
    $self->{summary}
  );
}

# returns 1 if time is between alarm time and start time, else 0
sub isAlarmed {
  my ($self,$t) = @_;
  return $self->{alarm} ?
    (($self->{alarm}<= $t && $t<= $self->{start}) ? 1 : 0) : 0;
}

# return 1 if time is between start time and end time, else 0
sub isRunning {
  my ($self,$t) = @_;
  return $self->{start}<= $t && $t<= $self->{end} ? 1 : 0;
}

sub nextTime {
  my ($self,$t) = @_;
  my @times= ( $self->{start}, $self->{end} );
  unshift @times, $self->{alarm} if($self->{alarm});
  @times= sort grep { $_ >= $t } @times;
  if(@times) {
    return $times[0];
  } else {
    return undef;
  }
}

#####################################
#
# Events
#
#####################################

package Calendar::Events;

sub new {
  my $class= shift;
  my $self= {};
  bless $self, $class;
  $self->{events}= {};
  return($self);
}

sub uids {
  my ($self)= @_;
  return keys $self->{events};
}

sub events {
  my ($self)= @_;
  return values $self->{events};
}

sub event {
  my ($self,$uid)= @_;
  return $self->{events}{$uid};
}

sub setEvent {
  my ($self,$event)= @_;
  $self->{events}{$event->uid()}= $event;
}
sub deleteEvent {
  my ($self,$uid)= @_;
  delete $self->{events}{$uid};
}

# sub ts {
#   my ($tm)= @_;
#   my ($second,$minute,$hour,$day,$month,$year,$wday,$yday,$isdst)= localtime($tm);
#   return sprintf("%02d.%02d.%4d %02d:%02d:%02d", $day,$month+1,$year+1900,$hour,$minute,$second);
# }

sub updateFromCalendar {
  my ($self,$calendar)= @_;
  my $t= time();
  my $uid;
  my $event;

  # we first remove all elements which were previously marked for deletion
  foreach $event ($self->events()) {
    if($event->isDeleted()) {
      $self->deleteEvent($event->uid());
    }
  }

  # we iterate over the VEVENTs in the calendar
  my @vevents= grep { $_->{type} eq "VEVENT" } @{$calendar->{entries}};
  foreach my $vevent (@vevents) {
    # convert event to entry
    my $event= Calendar::Event->new();
    $event->fromVEvent($vevent);

    $uid= $event->uid();
    #main::debug "Processing event $uid.";
    if(defined($self->event($uid))) {
      # the event already exists
      #main::debug "Event $uid already exists.";
      $event->setState($self->event($uid)->state()); # copy the state from the existing event
      #main::debug "Our lastModified: " . ts($self->event($uid)->lastModified());
      #main::debug "New lastModified: " . ts($event->lastModified());
      if($self->event($uid)->lastModified() != $event->lastModified()) {
         $event->setState("updated")
      } else {
         $event->setState("known")
      }   
    };
    $event->touch($t);
    $self->setEvent($event);
  }

  # untouched elements get marked as deleted
  foreach $event ($self->events()) {
    if($event->lastSeen() != $t) {
      $event->setState("deleted");
    }
  }
}

#####################################

package main;


#####################################
sub Calendar_Initialize($) {

  my ($hash) = @_;
  $hash->{DefFn}   = "Calendar_Define";
  $hash->{UndefFn} = "Calendar_Undef";
  $hash->{GetFn}   = "Calendar_Get";
  $hash->{SetFn}   = "Calendar_Set";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5 event-on-update-reading event-on-change-reading";

}

###################################
sub Calendar_CheckTimes($) {

my ($hash) = @_;

  my $eventsObj= $hash->{fhem}{events};
  my $t= time();

  # we now run over all events and update the readings for those with changed states
  my @allevents= $eventsObj->events();
  my @running= sort map { $_->uid() } grep { $_->isRunning($t) } @allevents;
  my @alarmed= sort map { $_->uid() } grep { $_->isAlarmed($t) } @allevents;

  readingsBeginUpdate($hash);
  readingsUpdate($hash, "running", join(";", @running));
  readingsUpdate($hash, "alarmed", join(";", @alarmed));
  readingsEndUpdate($hash, 1); # DoTrigger, because sub is called by a timer instead of dispatch
  
}  


###################################
sub Calendar_GetUpdate($$)
{
  my ($hash,$starttimer) = @_;


  if($starttimer) {
    #main::debug "Start timer: $starttimer, " . $hash->{fhem}{interval} . "s";
    InternalTimer(gettimeofday()+$hash->{fhem}{interval}, "Calendar_GetUpdate", $hash, 0) ;
  }
   
  my $url= $hash->{fhem}{url};
  
  # split into hostname and filename, TODO: enable https
  if($url =~ m,^http://(.+?)(/.+)$,) {
    # well-formed, host now in $1, filename now in $2
    #main::debug "Get $url";
  } else {
    Log 1, "Calendar " . $hash->{NAME} . ": $url is not a valid URL.";
    return 0;
  }
  my $ics= GetHttpFile("$1:80",$2);
  return 0 if($ics eq "");

  # we parse the calendar into a recursive ICal::Entry structure
  my $ical= ICal::Entry->new("root");
  $ical->parse(split("\n",$ics));
  #main::debug "*** Result:\n";
  #main::debug $ical->asString();

  # we now create the events from it
  #main::debug "Creating events...";
  my $eventsObj= $hash->{fhem}{events};
  $eventsObj->updateFromCalendar(@{$ical->{entries}}[0]);
  $hash->{fhem}{events}= $eventsObj;

  # we now update the readings
  my @allevents= $eventsObj->events();

  my @all= sort map { $_->uid() } @allevents;
  my @new= sort map { $_->uid() } grep { $_->isNew() } @allevents;
  my @updated= sort map { $_->uid() } grep { $_->isUpdated() } @allevents;
  my @deleted = sort map { $_->uid() } grep { $_->isDeleted() } @allevents;
  my @changed= sort (@new, @updated, @deleted);

  #$hash->{STATE}= $val;
  readingsBeginUpdate($hash);
  readingsUpdate($hash, "all", join(";", @all));
  readingsUpdate($hash, "new", join(";", @new));
  readingsUpdate($hash, "updated", join(";", @updated));
  readingsUpdate($hash, "deleted", join(";", @deleted));
  readingsUpdate($hash, "changed", join(";", @changed));
  readingsEndUpdate($hash, 1); # DoTrigger, because sub is called by a timer instead of dispatch

  Calendar_CheckTimes($hash);
  return 1;
}

###################################
sub Calendar_Set($@) {
  my ($hash, @a) = @_;

  my $cmd= $a[1];

  # usage check
  if((@a == 2) && ($a[1] eq "update")) {
     Calendar_GetUpdate($hash,0);
     return undef;
  } else {
    return "Unknown argument $cmd, choose one of update";
  }
}

###################################
sub Calendar_Get($@) {

  my ($hash, @a) = @_;

  return "argument is missing" if($#a != 2);

  my $eventsObj= $hash->{fhem}{events};
  my @uids;

  my $cmd= $a[1];
  if($cmd eq "text") {

    
    my $reading= $a[2];
    
    # $reading is alarmed, all, changed, deleted, new, running, updated
    # if $reading does not match any of these it is assumed to be a uid
    if(defined($hash->{READINGS}{$reading})) {
      @uids= split(";", $hash->{READINGS}{$reading}{VAL});
    } else {
      @uids= sort map { $_->uid() } grep { $_->uid() eq $reading } $eventsObj->events();
    }

    my @texts;
    if(@uids) {
      foreach my $uid (@uids) {
        my $event= $eventsObj->event($uid);
        push @texts, $event->asText();
      }
    }  
    return join("\n", @texts);
    
  } elsif($cmd eq "find") {

    my $regexp= $a[2];
    foreach my $event ($eventsObj->events()) {
      push @uids, $event->uid() if($event->summary() =~ m/$regexp/);
    }
    return join(";", @uids);
  
  } else {
    return "Unknown argument $cmd, choose one of text find";
  }

}


#####################################
sub Calendar_Define($$) {

  my ($hash, $def) = @_;

  # define <name> Calendar ical URL [interval]

  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> Calendar ical url <URL> [interval]"
    if(($#a < 4 && $#a > 5) || ($a[2] ne 'ical') || ($a[3] ne 'url'));

  $hash->{STATE} = "Initialized";

  my $name      = $a[0];
  my $url       = $a[4];
  my $interval  = 3600;
  
  $interval= $a[5] if($#a==5);
   
  $hash->{fhem}{url}= $url;
  $hash->{fhem}{interval}= $interval;
  $hash->{fhem}{events}= Calendar::Events->new();

  #main::debug "Interval: ${interval}s";
  Calendar_GetUpdate($hash,1);

  return undef;
}

#####################################
sub Calendar_Undef($$) {

  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}

#####################################


#####################################


1;
