# $Id$
##############################################################################
#
#     57_Calendar.pm
#     Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

use strict;
use warnings;
use HttpUtils;


##############################################

package main;


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
  #main::Debug "NEW: $type";
  return($self);
}

sub addproperty {
  my ($self,$line)= @_;
  # TRIGGER;VALUE=DATE-TIME:20120531T150000Z
  #main::Debug "line= $line";
  my ($property,$parameter)= split(":", $line,2); # TRIGGER;VALUE=DATE-TIME    20120531T150000Z
  #main::Debug "property= $property parameter= $parameter";
  my ($key,$parts)= split(";", $property,2);
  #main::Debug "key= $key parts= $parts";
  $parts= "" unless(defined($parts));
  $parameter= "" unless(defined($parameter));
  if($key eq "EXDATE") {
    push @{$self->{properties}{exdates}}, $parameter;
  }
  $self->{properties}{$key}= {
      PARTS => "$parts",
      VALUE => "$parameter"
  };
  #main::Debug "ADDPROPERTY: ". $self ." key= $key, parts= $parts, value= $parameter";
  #main::Debug "WE ARE " .  $self->{properties}{$key}{VALUE};
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
  #main::Debug "ENTER @ $ln";
  while($ln<$#ical) {
    my $line= $ical[$ln];
    chomp $line;
    $line =~ s/[\x0D]//; # chomp will not remove the CR
    #main::Debug "$ln: $line";
    $ln++;
    last if($line =~ m/^END:.*$/);
    if($line =~ m/^BEGIN:(.*)$/) {
      my $entry= ICal::Entry->new($1);
      push @{$self->{entries}}, $entry;
      $ln= $entry->parseSub($ln,@ical);
    } else {
      $self->addproperty($line);
    }
  }
  #main::Debug "BACK";
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
  $self->{_mode}= "undefined";
  $self->setState("new");
  $self->setMode("undefined");
  $self->{alarmTriggered}= 0;
  $self->{startTriggered}= 0;
  $self->{endTriggered}= 0;
  return($self);
}

sub uid {
  my ($self)= @_;
  return $self->{uid};
}

sub start {
  my ($self)= @_;
  return $self->{start};
}


sub setState {
  my ($self,$state)= @_;
  #main::Debug "Before setState $state: States(" . $self->uid() . ") " . $self->{_previousState} . " -> " . $self->{_state};
  $self->{_previousState}= $self->{_state};
  $self->{_state}= $state;
  #main::Debug "After setState $state: States(" . $self->uid() . ") " . $self->{_previousState} . " -> " . $self->{_state};
  return $state;
}

sub setMode {
  my ($self,$mode)= @_;
  $self->{_previousMode}= $self->{_mode};
  $self->{_mode}= $mode;
  #main::Debug "After setMode $mode: Modes(" . $self->uid() . ") " . $self->{_previousMode} . " -> " . $self->{_mode};
  return $mode;
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

sub mode {
  my ($self)= @_;
  return $self->{_mode};
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
  #main::Debug "States(" . $self->uid() . ") " . $self->{_previousState} . " -> " . $self->{_state};
  return $self->{_state} ne $self->{_previousState} ? 1 : 0;
}

sub modeChanged {
  my ($self)= @_;
  return $self->{_mode} ne $self->{_previousMode} ? 1 : 0;
}

# converts a date/time string to the number of non-leap seconds since the epoch
# 20120520T185202Z: date/time string in ISO8601 format, time zone GMT
# 20121129T222200: date/time string in ISO8601 format, time zone local
# 20120520:         a date string has no time zone associated
sub tm {
  my ($t)= @_;
  return undef if(!$t);
  #main::Debug "convert >$t<";
  my ($year,$month,$day)= (substr($t,0,4), substr($t,4,2),substr($t,6,2));
  if(length($t)>8) {
      my ($hour,$minute,$second)= (substr($t,9,2), substr($t,11,2),substr($t,13,2));
      my $z;
      $z= substr($t,15,1) if(length($t) == 16);
      #main::Debug "$day.$month.$year $hour:$minute:$second $z";
      if($z) {
        return main::fhemTimeGm($second,$minute,$hour,$day,$month-1,$year-1900);
      } else {
        return main::fhemTimeLocal($second,$minute,$hour,$day,$month-1,$year-1900);
      }
  } else {
      #main::Debug "$day.$month.$year";
      return main::fhemTimeLocal(0,0,0,$day,$month-1,$year-1900);
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

  #main::Debug "Duration $d";
  
  my $sign= 1;
  my $t= 0;

  my @c= split("P", $d);
  $sign= -1 if($c[0] eq "-");
  my ($dw,$dt)= split("T", $c[1]);
  $dt="" unless defined($dt);
  if($dw =~ m/(\d+)D$/) {
    $t+= 86400*$1; # days
  } elsif($dw =~ m/(\d+)W$/) {
    $t+= 604800*$1; # weeks
  }
  if($dt =~ m/^(\d+)H(\d+)M(\d+)S$/) {
    $t+= $1*3600+$2*60+$3;
  }
  $t*= $sign;
  #main::Debug "sign: $sign  dw: $dw  dt: $dt   t= $t";
  return $t;
}

sub dt {
  my ($t0,$value,$parts)= @_;
  #main::Debug "t0= $t0  parts= $parts  value= $value";
  if(defined($parts) && $parts =~ m/VALUE=DATE/) {
    return tm($value);
  } else {
    return $t0+d($value);
  }
}

sub ts {
  my ($tm)= @_;
  return "" unless($tm);
  my ($second,$minute,$hour,$day,$month,$year,$wday,$yday,$isdst)= localtime($tm);
  return sprintf("%02d.%02d.%4d %02d:%02d:%02d", $day,$month+1,$year+1900,$hour,$minute,$second);
}

sub ts0 {
  my ($tm)= @_;
  return "" unless($tm);
  my ($second,$minute,$hour,$day,$month,$year,$wday,$yday,$isdst)= localtime($tm);
  return sprintf("%02d.%02d.%2d %02d:%02d", $day,$month+1,$year-100,$hour,$minute);
}

sub plusNMonths($$) {
  my ($tm, $n)= @_;
  my ($second,$minute,$hour,$day,$month,$year,$wday,$yday,$isdst)= localtime($tm);
  #main::Debug "Adding $n months to $day.$month.$year $hour:$minute:$second= " . ts($tm);
  $month+= $n;
  $year+= int($month / 12);
  $month %= 12;
  #main::Debug " gives $day.$month.$year $hour:$minute:$second= " . ts(main::fhemTimeLocal($second,$minute,$hour,$day,$month,$year));
  return main::fhemTimeLocal($second,$minute,$hour,$day,$month,$year);
}

sub fromVEvent {
  my ($self,$vevent)= @_;

  $self->{uid}= $vevent->value("UID");
  $self->{uid}=~ s/\W//g; # remove all non-alphanumeric characters, this makes life easier for perl specials
  $self->{start}= tm($vevent->value("DTSTART"));
  $self->{end}= tm($vevent->value("DTEND"));
  $self->{lastModified}= tm($vevent->value("LAST-MODIFIED"));
  $self->{summary}= $vevent->value("SUMMARY");
  $self->{location}= $vevent->value("LOCATION");

  #Dates to exclude in reoccuring rule
  my @exdate;
  if(exists($vevent->{properties}{exdates})) {
    foreach my $entry (@{$vevent->{properties}{exdates}}) {
      my @ed = split(",", $entry);
      @ed = map { tm($_) } @ed;
      push @exdate, @ed;
    }
  }  

  #@exdate= split(",", $vevent->value("EXDATE")) if($vevent->value("EXDATE"));
  #@exdate = map { tm($_) } @exdate;
  $self->{exdate} = \@exdate;

  #$self->{summary}=~ s/;/,/g;

  #
  # recurring events
  #
  # this part is under construction
  # we have to think a lot about how to deal with the migration of states for recurring events
  my $rrule= $vevent->value("RRULE");
  if($rrule) {
    my @rrparts= split(";", $rrule);
    my %r= map { split("=", $_); } @rrparts;

    my @keywords= qw(FREQ INTERVAL UNTIL COUNT BYMONTHDAY BYDAY BYMONTH);
    foreach my $k (keys %r) {
      if(not($k ~~ @keywords)) {
        main::Log3 undef, 2, "Calendar: RRULE $rrule is not supported";
      }
    }

    $self->{freq} =  $r{"FREQ"};
    #According to RFC, interval defaults to 1
    $self->{interval} = exists($r{"INTERVAL"}) ? $r{"INTERVAL"} : 1;
    $self->{until} = tm($r{"UNTIL"}) if(exists($r{"UNTIL"}));
    $self->{count} = $r{"COUNT"} if(exists($r{"COUNT"}));
    $self->{bymonthday} = $r{"BYMONTHDAY"} if(exists($r{"BYMONTHDAY"})); # stored but ignored
    $self->{byday} = $r{"BYDAY"} if(exists($r{"BYDAY"})); # stored but ignored
    $self->{bymonth} = $r{"BYMONTH"} if(exists($r{"BYMONTH"})); # stored but ignored

    # advanceToNextOccurance until we are in the future
    my $t = time();
    while($self->{end} < $t and $self->advanceToNextOccurance()) { ; }
  }
  

  # alarms
  my @valarms= grep { $_->{type} eq "VALARM" } @{$vevent->{entries}};
  my @alarmtimes= sort map { dt($self->{start}, $_->value("TRIGGER"), $_->parts("TRIGGER")) } @valarms;
  if(@alarmtimes) {
    $self->{alarm}= $alarmtimes[0];
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

sub location {
  my ($self)= @_;
  return $self->{location};
}


sub asText {
  my ($self)= @_;
  return sprintf("%s %s",
    ts0($self->{start}),
    $self->{summary}
  );
}

sub asFull {
  my ($self)= @_;
  return sprintf("%s %7s %8s %s %s-%s %s %s",
    $self->uid(),
    $self->state(),
    $self->mode(),
    $self->{alarm} ? ts($self->{alarm}) : "                   ",
    ts($self->{start}),
    ts($self->{end}),
    $self->{summary},
    $self->{location}
  );
}

sub alarmTime {
  my ($self)= @_;
  return ts($self->{alarm});
}

sub startTime {
  my ($self)= @_;
  return ts($self->{start});
}

sub endTime {
  my ($self)= @_;
  return ts($self->{end});
}

sub advanceToNextOccurance {
  my ($self) = @_;
  # See RFC 2445 page 39 and following

  return if(!exists($self->{freq})); #This event is not reoccuring
  $self->{count}-- if(exists($self->{count})); # since we look for the next occurance we have to decrement count first
  return if(exists($self->{count}) and $self->{count} <= 0); #We are already at the last occurance

  my @weekdays = qw(SU MO TU WE TH FR SA);
  #There are no leap seconds in epoch time
  #Valid values for freq: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, YEARLY
  my  $nextstart = $self->{start};
  do
  {
    if($self->{freq} eq "SECONDLY") {
      $nextstart += $self->{interval};
    } elsif($self->{freq} eq "MINUTELY") {
      $nextstart += 60*$self->{interval};
    } elsif($self->{freq} eq "HOURLY") {
      $nextstart += 60*60*$self->{interval};
    } elsif($self->{freq} eq "DAILY") {
      $nextstart += 60*60*24*$self->{interval};
    } elsif($self->{freq} eq "WEEKLY") {
      # special handling for WEEKLY and BYDAY
      if(exists($self->{byday})) {
        my ($msec, $mmin, $mhour, $mday, $mmon, $myear, $mwday, $yday, $isdat);
        my $preventloop = 0;        
        do {
          $nextstart += 60*60*24*$self->{interval};
          ($msec, $mmin, $mhour, $mday, $mmon, $myear, $mwday, $yday, $isdat) = gmtime($nextstart);
          $preventloop ++;        
        } while(index($self->{byday}, $weekdays[$mwday]) == -1 and $preventloop < 10);
      }
      else {
        # default WEEKLY handling
        $nextstart += 7*60*60*24*$self->{interval};
      }
    } elsif($self->{freq} eq "MONTHLY") {
      # here we ignore BYMONTHDAY as we consider the day of month of $self->{start}
      # to be equal to BYMONTHDAY.
      $nextstart= plusNMonths($nextstart, $self->{interval});
    } elsif($self->{freq} eq "YEARLY") {
      $nextstart= plusNMonths($nextstart, 12*$self->{interval});
    } else {
      main::Log3 undef, 1, "Calendar: event frequency '" . $self->{freq} . "' not implemented";
      return;
    }

  # Loop if nextstart is in the "dates to exclude"
  } while(exists($self->{exdate}) and ($nextstart ~~ $self->{exdate}));

  #the UNTIL clause is inclusive, so $newt == $self->{until} is okey
  return if(exists($self->{until}) and $nextstart > $self->{until});

  my $duration = $self->{end} - $self->{start};
  $self->{start} = $nextstart;
  $self->{end} = $self->{start} + $duration;
  main::Log3 undef, 5, "Next time of $self->{summary} is: start " . ts($self->{"start"}) . ", end " . ts($self->{"end"});
  return 1;
}


# returns 1 if time is before alarm time and before start time, else 0
sub isUpcoming {
  my ($self,$t) = @_;
  return 0 if($self->isDeleted());
  if($self->{alarm}) {
    return $t< $self->{alarm} ? 1 : 0;
  } else {
    return $t< $self->{start} ? 1 : 0;
  }
}

# returns 1 if time is between alarm time and start time, else 0
sub isAlarmed {
  my ($self,$t) = @_;
  return 0 if($self->isDeleted());
  return $self->{alarm} ?
    (($self->{alarm}<= $t && $t<= $self->{start}) ? 1 : 0) : 0;
}

# return 1 if time is between start time and end time, else 0
sub isStarted {
  my ($self,$t) = @_;
  return 0 if($self->isDeleted());
  return $self->{start}<= $t && $t< $self->{end} ? 1 : 0;
}

sub isEnded {
  my ($self,$t) = @_;
  return 0 if($self->isDeleted());
  return $self->{end}<= $t ? 1 : 0;
}

sub nextTime {
  my ($self,$t) = @_;
  my @times= ( $self->{start}, $self->{end} );
  unshift @times, $self->{alarm} if($self->{alarm});
  @times= sort grep { $_ > $t } @times;

#   main::Debug "Calendar: " . $self->asFull();
#   main::Debug "Calendar: Start " . main::FmtDateTime($self->{start});
#   main::Debug "Calendar: End   " . main::FmtDateTime($self->{end});
#   main::Debug "Calendar: Alarm " . main::FmtDateTime($self->{alarm}) if($self->{alarm});
#   main::Debug "Calendar: times[0] " . main::FmtDateTime($times[0]);
#   main::Debug "Calendar: times[1] " . main::FmtDateTime($times[1]);
#   main::Debug "Calendar: times[2] " . main::FmtDateTime($times[2]);
  
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
  return keys %{$self->{events}};
}

sub events {
  my ($self)= @_;
  return values %{$self->{events}};
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
    #main::Debug "Processing event $uid.";
    #foreach my $ee ($self->events()) {
    #  main::Debug $ee->asFull();
    #}
    if(defined($self->event($uid))) {
      # the event already exists
      #main::Debug "Event $uid already exists.";
      $event->setState($self->event($uid)->state()); # copy the state from the existing event
      $event->setMode($self->event($uid)->mode()); # copy the mode from the existing event
      #main::Debug "Our lastModified: " . ts($self->event($uid)->lastModified());
      #main::Debug "New lastModified: " . ts($event->lastModified());
      if($self->event($uid)->lastModified() != $event->lastModified()) {
         $event->setState("updated");
         #main::Debug "We set it to updated.";
      } else {
         $event->setState("known")
      }   
    };
    # new events that have ended are omitted 
    if($event->state() ne "new" || !$event->isEnded($t)) {
      $event->touch($t);
      $self->setEvent($event);
    }
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
  $hash->{AttrList}=  $readingFnAttributes;
}

###################################
sub Calendar_Wakeup($) {

  my ($hash) = @_;

  my $t= time();
  Log3 $hash, 4, "Calendar " . $hash->{NAME} . ": Wakeup";

  Calendar_GetUpdate($hash) if($t>= $hash->{fhem}{nxtUpdtTs});

  $hash->{fhem}{lastChkTs}= $t;
  $hash->{fhem}{lastCheck}= FmtDateTime($t);
  Calendar_CheckTimes($hash);

  # find next event
  my $nt= $hash->{fhem}{nxtUpdtTs};
  foreach my $event ($hash->{fhem}{events}->events()) {
    next if $event->isDeleted();
    my $et= $event->nextTime($t);
    # we only consider times in the future to avoid multiple
    # invocations for calendar events with the event time
    $nt= $et if(defined($et) && ($et< $nt) && ($et > $t));
  }
  $hash->{fhem}{nextChkTs}= $nt;
  $hash->{fhem}{nextCheck}= FmtDateTime($nt);

  InternalTimer($nt, "Calendar_Wakeup", $hash, 0) ;

}

###################################
sub Calendar_CheckTimes($) {

  my ($hash) = @_;

  my $eventsObj= $hash->{fhem}{events};
  my $t= time();
  Log3 $hash, 4, "Calendar " . $hash->{NAME} . ": Checking times...";

  # we now run over all events and update the readings 
  my @allevents= $eventsObj->events();
  my @endedevents= grep { $_->isEnded($t) } @allevents;
  foreach (@endedevents) { $_->advanceToNextOccurance(); }

  my @upcomingevents= grep { $_->isUpcoming($t) } @allevents;
  my @alarmedevents= grep { $_->isAlarmed($t) } @allevents;
  my @startedevents= grep { $_->isStarted($t) } @allevents;

  my $event;
  #main::Debug "Updating modes...";
  foreach $event (@upcomingevents) { $event->setMode("upcoming"); }
  foreach $event (@alarmedevents) { $event->setMode("alarm"); }
  foreach $event (@startedevents) { $event->setMode("start"); }
  foreach $event (@endedevents) { $event->setMode("end"); }

  my @changedevents= grep { $_->modeChanged() } @allevents;

  
  my @upcoming= sort map { $_->uid() } @upcomingevents;
  my @alarm= sort map { $_->uid() } @alarmedevents;
  my @alarmed= sort map { $_->uid() } grep { $_->modeChanged() } @alarmedevents;
  my @start= sort map { $_->uid() } @startedevents;
  my @started= sort map { $_->uid() } grep { $_->modeChanged() } @startedevents;
  my @end= sort map { $_->uid() } @endedevents;
  my @ended= sort map { $_->uid() } grep { $_->modeChanged() } @endedevents;
  my @changed= sort map { $_->uid() } @changedevents;
  
  readingsBeginUpdate($hash); # clears all events in CHANGED, thus must be called first
  # we create one fhem event for one changed calendar event
  map { addEvent($hash, "changed: " . $_->uid() . " " . $_->mode() ); } @changedevents;
  readingsBulkUpdate($hash, "lastCheck", $hash->{fhem}{lastCheck});
  readingsBulkUpdate($hash, "modeUpcoming", join(";", @upcoming));
  readingsBulkUpdate($hash, "modeAlarm", join(";", @alarm));
  readingsBulkUpdate($hash, "modeAlarmed", join(";", @alarmed));
  readingsBulkUpdate($hash, "modeAlarmOrStart", join(";", @alarm,@start));
  readingsBulkUpdate($hash, "modeChanged", join(";", @changed));
  readingsBulkUpdate($hash, "modeStart", join(";", @start));
  readingsBulkUpdate($hash, "modeStarted", join(";", @started));
  readingsBulkUpdate($hash, "modeEnd", join(";", @end));
  readingsBulkUpdate($hash, "modeEnded", join(";", @ended));
  readingsEndUpdate($hash, 1); # DoTrigger, because sub is called by a timer instead of dispatch
  
}  


###################################
sub Calendar_GetUpdate($) {

  my ($hash) = @_;

  my $t= time();
  $hash->{fhem}{lstUpdtTs}= $t;
  $hash->{fhem}{lastUpdate}= FmtDateTime($t);
  
  Log3 $hash, 4, "Calendar " . $hash->{NAME} . ": Updating...";
  my $type = $hash->{fhem}{type};
  my $url= $hash->{fhem}{url};
  
  my $ics;
  
  if($type eq "url"){ 
    $ics= GetFileFromURLQuiet($url) if($type eq "url");
  } elsif($type eq "file") {
    if(open(ICSFILE, $url)) {
      while(<ICSFILE>) { 
        $ics .= $_; 
      }
      close(ICSFILE);
    } else {
      Log3 $hash, 1, "Calendar " . $hash->{NAME} . ": Could not open file $url"; 
      return 0;
    }
  } else {
    # this case never happens by virtue of _Define, so just
    die "Software Error";
  }
    
  
  if(!defined($ics)) {
    Log3 $hash, 1, "Calendar " . $hash->{NAME} . ": Could not retrieve file at URL";
    return 0;
  }
  
  # we parse the calendar into a recursive ICal::Entry structure
  my $ical= ICal::Entry->new("root");
  $ical->parse(split("\n",$ics));
  #main::Debug "*** Result:\n";
  #main::Debug $ical->asString();

  my @entries= @{$ical->{entries}};
  if($#entries<0) {
    Log3 $hash, 1, "Calendar " . $hash->{NAME} . ": Not an ical file at URL";
    $hash->{STATE}= "Not an ical file at URL";
    return 0;
  };
  
  my $root= @{$ical->{entries}}[0];
  my $calname= "?";
  if($root->{type} ne "VCALENDAR") {
    Log3 $hash, 1, "Calendar " . $hash->{NAME} . ": Root element is not a VCALENDAR";
    $hash->{STATE}= "Root element is not a VCALENDAR";
    return 0;
  } else {
    $calname= $root->value("X-WR-CALNAME");
  }
  
    
  $hash->{STATE}= "Active";
  
  # we now create the events from it
  #main::Debug "Creating events...";
  my $eventsObj= $hash->{fhem}{events};
  $eventsObj->updateFromCalendar($root);
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
  readingsBulkUpdate($hash, "calname", $calname);
  readingsBulkUpdate($hash, "lastUpdate", $hash->{fhem}{lastUpdate});
  readingsBulkUpdate($hash, "all", join(";", @all));
  readingsBulkUpdate($hash, "stateNew", join(";", @new));
  readingsBulkUpdate($hash, "stateUpdated", join(";", @updated));
  readingsBulkUpdate($hash, "stateDeleted", join(";", @deleted));
  readingsBulkUpdate($hash, "stateChanged", join(";", @changed));
  readingsEndUpdate($hash, 1); # DoTrigger, because sub is called by a timer instead of dispatch

  $t+= $hash->{fhem}{interval};
  $hash->{fhem}{nxtUpdtTs}= $t;
  $hash->{fhem}{nextUpdate}= FmtDateTime($t);

  return 1;
}

###################################
sub Calendar_Set($@) {
  my ($hash, @a) = @_;

  my $cmd= $a[1];

  # usage check
  if((@a == 2) && ($a[1] eq "update")) {
     $hash->{fhem}{nxtUpdtTs}= 0; # force update
     Calendar_Wakeup($hash);
     return undef;
  } else {
    return "Unknown argument $cmd, choose one of update:noArg";
  }
}

###################################
sub Calendar_Get($@) {

  my ($hash, @a) = @_;


  my $eventsObj= $hash->{fhem}{events};
  my @events;

  my $cmd= $a[1];
  if(grep(/^$cmd$/, ("text","full","summary","location","alarm","start","end"))) {

    return "argument is missing" if($#a < 2);
    my $reading= $a[2];
    
    # $reading is alarmed, all, changed, deleted, new, started, updated
    # if $reading does not match any of these it is assumed to be a uid
    if(defined($hash->{READINGS}{$reading})) {
      @events= grep { my $uid= $_->uid(); $hash->{READINGS}{$reading}{VAL} =~ m/$uid/ } $eventsObj->events();
    } else {
      @events= grep { $_->uid() eq $reading } $eventsObj->events();
    }

    my @texts;

    
    if(@events) {
      foreach my $event (sort { $a->start() <=> $b->start() } @events) {
        push @texts, $event->asText() if $cmd eq "text";
        push @texts, $event->asFull() if $cmd eq "full";
        push @texts, $event->summary() if $cmd eq "summary";
        push @texts, $event->location() if $cmd eq "location";
        push @texts, $event->alarmTime() if $cmd eq "alarm";
        push @texts, $event->startTime() if $cmd eq "start";
        push @texts, $event->endTime() if $cmd eq "end";
      }
    }
    if(defined($a[3])) {
      my $keep= $a[3];
      return "Argument $keep is not a number." unless($keep =~ /\d+/);
      splice @texts, $keep if($#texts>= 0);  
    }
    return join("\n", @texts);
    
  } elsif($cmd eq "find") {

    return "argument is missing" if($#a != 2);
    my $regexp= $a[2];
    my @uids;
    foreach my $event ($eventsObj->events()) {
      push @uids, $event->uid() if($event->summary() =~ m/$regexp/);
    }
    return join(";", @uids);
  
  } else {
    return "Unknown argument $cmd, choose one of text summary full find";
  }

}

#####################################
sub Calendar_Define($$) {

  my ($hash, $def) = @_;

  # define <name> Calendar ical URL [interval]

  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> Calendar ical url <URL> [interval]\n".\
         "        define <name> Calendar ical file <FILENAME> [interval]"
    if(($#a < 4 && $#a > 5) || ($a[2] ne 'ical') || (($a[3] ne 'url') && ($a[3] ne 'file')));

  $hash->{STATE} = "Initialized";

  my $name      = $a[0];
  my $type      = $a[3];
  my $url       = $a[4];
  my $interval  = 3600;
  
  $interval= $a[5] if($#a==5);
   
  $hash->{fhem}{type}= $type;
  $hash->{fhem}{url}= $url;
  $hash->{fhem}{interval}= $interval;
  $hash->{fhem}{events}= Calendar::Events->new();

  #main::Debug "Interval: ${interval}s";
  $hash->{fhem}{nxtUpdtTs}= 0;
  Calendar_Wakeup($hash);

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

=pod
=begin html

<a name="Calendar"></a>
<h3>Calendar</h3>
<ul>
  <br>

  <a name="Calendardefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Calendar ical url &lt;URL&gt; [&lt;interval&gt;]</code><br>
    <code>define &lt;name&gt; Calendar ical file &lt;FILENAME&gt; [&lt;interval&gt;]</code><br>
    <br>
    Defines a calendar device.<br><br>

    A calendar device periodically gathers calendar events from the source calendar at the given URL or from a file. 
    The file must be in ICal format.<br><br>

    If the URL
    starts with <code>https://</code>, the perl module IO::Socket::SSL must be installed
    (use <code>cpan -i IO::Socket::SSL</code>).<br><br>

    Note for users of Google Calendar: You can literally use the private ICal URL from your Google Calendar.
    <!--Google App accounts do not work since requests to the URL
    get redirected first and the fhem mechanism for retrieving data via http/https cannot handle this. -->
    If your Google Calendar
    URL starts with <code>https://</code> and the perl module IO::Socket::SSL is not installed on your system, you can
    replace it by <code>http://</code> if and only if there is no redirection to the <code>https://</code> URL. 
    Check with your browser first if unsure.<br><br>

    The optional parameter <code>interval</code> is the time between subsequent updates
    in seconds. It defaults to 3600 (1 hour).<br><br>

    Examples:
    <pre>
      define MyCalendar Calendar ical url https://www.google.com&shy;/calendar/ical/john.doe%40example.com&shy;/private-foo4711/basic.ics
      define YourCalendar Calendar ical url http://www.google.com&shy;/calendar/ical/jane.doe%40example.com&shy;/private-bar0815/basic.ics 86400
      define SomeCalendar Calendar ical file /home/johndoe/calendar.ics
      </pre>
  </ul>
  <br>

  <a name="Calendarset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; update</code><br><br>

    Forces the retrieval of the calendar from the URL. The next automatic retrieval is scheduled to occur
    <code>interval</code> seconds later.<br><br>
  </ul>
  <br>


  <a name="Calendarget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; full|text|summary|location|alarm|start|end &lt;reading&gt|&lt;uid&gt; [max]</code><br><br>

    Returns, line by line, the full state or a textual representation or the summary (subject, title) or the
    location or the alarm time or the start time or the end time
    of the calendar event(s) listed in the
    reading &lt;reading&gt or identified by the UID &lt;uid&gt. The optional parameter <code>max</code> limits
    the number of returned lines.<br><br>

    <code>get &lt;name&gt; find &lt;regexp&gt;</code><br><br>

    Returns, line by line, the UIDs of all calendar events whose summary matches the regular expression
    &lt;regexp&gt;.<br><br>

  </ul>

  <br>

  <a name="Calendarattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <b>Description</b>
  <ul>

  A calendar is a set of calendar events. A calendar event has a summary (usually the title shown in a visual
  representation of the source calendar), a start time, an end time, and zero, one or more alarm times. The calendar events are
  fetched from the source calendar at the given URL. In case of multiple alarm times for a calendar event, only the
  earliest alarm time is kept. Recurring calendar events are currently not supported.<p>

  A calendar event is identified by its UID. The UID is taken from the source calendar. All non-alphanumerical characters
  are stripped off the UID to make your life easier.<p>

  A calendar event can be in one of the following states:
  <table border="1">
  <tr><td>new</td><td>The calendar event was first seen at the most recent update. Either this was your first retrieval of
  the calendar or you newly added the calendar event to the source calendar.</td></tr>
  <tr><td>known</td><td>The calendar event was already there before the most recent update.</td></tr>
  <tr><td>updated</td><td>The calendar event was already there before the most recent update but it has changed since it
  was last retrieved.</td></tr>
  <tr><td>deleted</td><td>The calendar event was there before the most recent update but is no longer. You removed it from the source calendar. The calendar event will be removed from all lists at the next update.</td></tr>
  </table><br>
  Calendar events that lie completely in the past (current time on wall clock is later than the calendar event's end time)
  are not retrieved and are thus not accessible through the calendar.
  <p>

  A calendar event can be in one of the following modes:
  <table border="1">
  <tr><td>upcoming</td><td>Neither the alarm time nor the start time of the calendar event is reached.</td></tr>
  <tr><td>alarm</td><td>The alarm time has passed but the start time of the calendar event is not yet reached.</td></tr>
  <tr><td>start</td><td>The start time has passed but the end time of the calendar event is not yet reached.</td></tr>
  <tr><td>end</td><td>The end time of the calendar event has passed.</td></tr>
  </table><br>
  A calendar event transitions from one mode to another immediately when the time for the change has come. This is done by waiting
  for the earliest future time among all alarm, start or end times of all calendar events.
  <p>

  A calendar device has several readings. Except for <code>calname</code>, each reading is a semicolon-separated list of UIDs of
  calendar events that satisfy certain conditions:
  <table border="1">
  <tr><td>calname</td><td>name of the calendar</td></tr>
  <tr><td>all</td><td>all events</td></tr>
  <tr><td>modeAlarm</td><td>events in alarm mode</td></tr>
  <tr><td>modeAlarmOrStart</td><td>events in alarm or start mode</td></tr>
  <tr><td>modeAlarmed</td><td>events that have just transitioned from upcoming to alarm mode</td></tr>
  <tr><td>modeChanged</td><td>events that have just changed their mode somehow</td></tr>
  <tr><td>modeEnd</td><td>events in end mode</td></tr>
  <tr><td>modeEnded</td><td>events that have just transitioned from start to end mode</td></tr>
  <tr><td>modeStart</td><td>events in start mode</td></tr>
  <tr><td>modeStarted</td><td>events that have just transitioned to start mode</td></tr>
  <tr><td>modeUpcoming</td><td>events in upcoming mode</td></tr>
  <tr><td>stateChanged</td><td>events that have just changed their state somehow</td></tr>
  <tr><td>stateDeleted</td><td>events in state deleted</td></tr>
  <tr><td>stateNew</td><td>events in state new</td></tr>
  <tr><td>stateUpdated</td><td>events in state updated</td></tr>
  </table>
  </ul>
  <p>
  
  When a calendar event has changed, an event is created in the form
  <code>changed: UID mode</code> with mode being the current mode the calendar event is in after the change.
  
  <p>

  <b>Usage scenarios</b>
  <ul>
    <i>Show all calendar events with details</i><br><br>
    <ul>
    <code>
    get MyCalendar full all<br>
    2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom   known    alarm 31.05.2012 17:00:00 07.06.2012 16:30:00-07.06.2012 18:00:00 Erna for coffee<br>
    992hydf4y44awer5466lhfdsr&shy;gl7tin6b6mckf8glmhui4&shy;googlecom   known upcoming                     08.06.2012 00:00:00-09.06.2012 00:00:00 Vacation
    </code><br><br>
    </ul>

    <i>Show calendar events in your photo frame</i><br><br>
    <ul>
    Put a line in the <a href="#RSSlayout">layout description</a> to show calendar events in alarm or start mode:<br><br>
    <code>text 20 60 { fhem("get MyCalendar text modeAlarmOrStart") }</code><br><br>
    This may look like:<br><br>
    <code>
    07.06.12 16:30 Erna for coffee<br>
    08.06.12 00:00 Vacation
    </code><br><br>
    </ul>

    <i>Switch the light on when Erna comes</i><br><br>
    <ul>
    First find the UID of the calendar event:<br><br>
    <code>
    get MyCalendar find .*Erna.*<br>
    2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom
    </code><br><br>
    Then define a notify:<br><br>
    <code>
    define ErnaComes notify MyCalendar:modeStarted.*2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom.* set MyLight on
    </code><br><br>
    You can also do some logging:<br><br>
    <code>
    define LogErna notify MyCalendar:modeAlarmed.*2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom.* { Log3 %NAME, 1, "ALARM name=%NAME event=%EVENT part1=%EVTPART0 part2=%EVTPART1" }
    </code><br><br>
    </ul>

    <i>Switch actors on and off</i><br><br>
    <ul>
    Think about a calendar with calendar events whose summaries (subjects, titles) are the names of devices in your fhem installation.
    You want the respective devices to switch on when the calendar event starts and to switch off when the calendar event ends.<br><br>
   <code>
    define SwitchActorOn  notify MyCalendar:modeStarted.* { 
                my $reading="%EVTPART0";; 
                my $uid= "%EVTPART1";; 
                my $actor= fhem("get MyCalendar summary $uid");; 
                if(defined $actor) { 
                   fhem("set $actor on") 
                } 
    }<br><br>
    define SwitchActorOff  notify MyCalendar:modeEnded.* { 
                my $reading="%EVTPART0";; 
                my $uid= "%EVTPART1";; 
                my $actor= fhem("get MyCalendar summary $uid");; 
                if(defined $actor) { 
                   fhem("set $actor off") 
                } 
    }
    </code><br><br>
    You can also do some logging:<br><br>
    <code>
    define LogActors notify MyCalendar:mode(Started|Ended).* { my $reading= "%EVTPART0";; my $uid= "%EVTPART1";; my $actor= fhem("get MyCalendar summary $uid");; Log 3 %NAME, 1, "Actor: $actor, Reading $reading" }
    </code><br><br>
    </ul>


  </ul>


</ul>


=end html
=cut
