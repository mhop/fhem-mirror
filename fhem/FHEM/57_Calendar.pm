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
use Storable qw(freeze thaw);
use POSIX qw(strftime);
use List::Util qw(any); # for contains


##############################################

package main;

#
# *** Potential issues:
#
# There might be issues when turning to daylight saving time and back that
# need further investigation. For counterpart please see
# http://forum.fhem.de/index.php?topic=18707
# http://forum.fhem.de/index.php?topic=15827
#
# *** Potential future extensions:
#
# sequence of events fired sorted by time
# http://forum.fhem.de/index.php?topic=29112
#
# document ownCloud ical use
# http://forum.fhem.de/index.php?topic=28667
#



=for comment

RFC
---

https://tools.ietf.org/html/rfc5545


Data structures
---------------

We call a set of calendar events (short: events) a series, even for sets
consisting only of a single event. A series may consist of only one single
event, a series of regularly reccuring events and reccuring events with
exceptions. A series is identified by a UID.


*** VEVENT record, class ICal::Entry

In the iCalendar, a series is represented by one or more VEVENT records.

The unique key for a VEVENT record is UID, RECURRENCE-ID (3.8.4.4, p. 112) and
SEQUENCE (3.8.7.4, p. 138).

The internal primary key for a VEVENT is ID.

FHEM keeps a set of VEVENT records (record set). When the calendar is updated,
a new record set is retrieved from the iCalendar and updates the old record set
to form the resultant record set.

A record in the resultant record set can be in exactly one of these states:
- deleted:
            a record from the old record set for which no record with the same
            (UID, RECURRENCE-ID) was in the new record set.
- new:
            a record from the new record set for which no record with same
            (UID, RECURRENCE-ID) was in the old record set.
- changed-old:
            a record from the old record set for which a record with the same
            (UID, RECURRENCE-ID) but different SEQUENCE was in the new record
            set.
- changed-new:
            a record from the new record set for which a record with the same
            (UID, RECURRENCE-ID) but different SEQUENCE was in the old record
            set.
- known:
            a record with this (UID, RECURRENCE-ID, SEQUENCE) was both in the
            old and in the new record set and both records have the same
            LAST-MODIFIED. The record from the old record set was
            kept and the record from the new record set was discarded.
- modified-new:
            a record with this (UID, RECURRENCE-ID, SEQUENCE) was both in the
            old and in the new record set and both records differ in
            LAST-MODIFIED. This is the record from the new record set.
- modified-old:
            a record with this (UID, RECURRENCE-ID, SEQUENCE) was both in the
            old and in the new record set and both records differ in
            LAST-MODIFIED. This is the record from the old record set.

Records in states modified-old and changed-old refer to the corresponding records
in states modified-new and change-new, and vice versa.

Records in state deleted, modified-old or changed-old are removed upon
the next update. They are said to be "obsolete".

A record is said to be "recurring" if it has a RRULE property.

A record is said to be an "exception" if it has a RECURRENCE-ID property.

Each records has a set of events attached.



*** calendar event, class Calendar::Event

Events are attached to single records (VEVENTs).

The uid of the event is the UID of the record with all non-alphanumerical
characters removed.

At a given point in time t, an event is in exactly one of these modes:
- upcoming:
            the start time of the event is in the future
- alarm:
            alarm time <= t < start time for any of the alarms for the event
- start:
            start time <= t <= end time of the event
- end:
            end time < t

An event is said to be "changed", when its mode has changed during the most
recent run of calendar event processing.

An event is said to be "hidden", when
- it was in mode end and end time of the event < t - horizonPast, or
- it was in mode upcoming and start time of the event > t + horizonFuture
at the most recent run of calendar event processing. horizonPast defaults to 0,
horizonFuture defaults to 366 days.



Processing of iCalendar
-----------------------

*** Initial situation:
We have an old record set of VEVENTs. It is empty on a restart of FHEM or upon
issueing the "set ... reload" command.

*** Step 1: Retrieval of new record set (Calendar_GetUpdate)
1) The iCalendar is downloaded from its location into FHEM memory.
2) It is parsed into a new record set of VEVENTs.

*** Step 2: Update of internal record set (Calendar_UpdateCalendar)
1) All records in the old record set that are in state deleted or obsolete are
removed.
2) All states of all records in the old record set are set to blank.
3) The old and new record sets are merged to create a resultant record set
according to the following procedure:

If the new record set contains a record with the same (UID, RECURRENCE-ID,
SEQUENCE) as a record in the old record set:
  - if the two records differ in LAST-MODIFIED, then both records
    are kept. The state of the record from the old record set is set to
    modified-old, the state of the record from the new record set is set to
    modified-new.
  - else the record from the old record set is kept, state set to known, and the
    record from the new record set is discarded.

If the new record set contains a record with the same (UID, RECURRENCE-ID) but
  different SEQUENCE as a record in the old record set, then both records are
  kept. The state of the record from the new record set is set to changed-new,
  and the state of record from the old record set is set to changed-old.

If the new record set contains a record that differs from any record in the old
record set by both UID and RECURRENCE-ID, the record from the new record set
id added to the resultant record set and its state is set to new.

4) The state of all records in the old record set that have not been touched
in 3) are set to deleted.

Notes:
- This procedure favors records from the new record set over records from the
  old record set, even if the SEQUENCE is lower or LAST-MODIFIED is earlier.
- DTSTAMP is the time stamp of the creation of the iCalendar entry. For Google
  Calendar it is the time stamp of the latest retrieval of the calendar.


*** Step 3: Update of calendar events (Calendar_UpdateCalendar)
We walk over all records and treat the corresponding events according to
the state of the record:

- deleted, changed-old, modified-old:
            all events are removed
- new, changed-new, modified-new:
            all events are removed and events are created anew
- known:
            all events are left alone

No events older than 400 days or more than 400 days in the future will be
created.

Creation of events in a series works as follows:

If we have several events in a series, the main series has the RRULE tag and
the exceptions have RECURRENCE-IDs. The RECURRENCE-ID match the start
dates in the series created from the RRULE that need to be exempted. We
therefore collect all events from records with same UID and RECURRENCE-ID set
as they form the list of records with the exceptions for the UID.

Before the regular creation is done, events for RDATEs are added as long as
an RDATE is not superseded by an EXDATE. An RDATE takes precedence over a
regularly created recurring event.

Starting with the start date of the series, one event is created after the
other. Creation stops when the series ends or when an event more than 400 days
in the future has been created. If the event is in the list of exceptions
(either defined by other events with same UID and a RECURRENCE-ID or by the
EXDATE property), it is not added.

What attributes are recognized and which of these are honored or ignored?

The following frequencies (FREQ) are recognized and honored:
SECONDLY
MINUTELY
HOURLY
DAILY
WEEKLY
    BYDAY: recognizes and honors one or several weekdays without prefix (e.g. -1SU, 2MO)
MONTHLY
    BYDAY: recognizes and honors one or several weekdays with and without prefix (e.g. -1SU, 2MO)
    BYMONTHDAY: recognized but ignored
    BYMONTH: recognized but ignored
YEARLY

For all of the above:
    INTERVAL: recognized and honored
    UNTIL: recognized and honored
    COUNT: recognized and honored
    WKST: recognized but ignored
    EXDATE: recognized and honored
    RDATE: recognized and honored

*** Step 4: The device readings related to updates are set

- calname
- lastUpdate
- nextUpdate
- nextWakeup
- state


Note: the state... readings from the previous version of this module (2015 and
earlier) are not available any more.


*** Note on cutoff of event creation

Events that are more than 400 days in the past or in the future from their 
time of creation are omitted. This time window can be further reduced by 
the cutoffOlderThan and cutoffLaterThan attributes. 

This would have the following consequence: as long as the calendar is not 
re-initialized (set ... reload or restart of FHEM) and the VEVENT record is 
not modified, events beyond the horizon may never get created.

Thus, a forced reload should be scheduled every now and then after initialization or 
reload. 


Processing of calendar events
-----------------------------
Calendar_CheckTimes

In case of a series of calendar events, several calendar events may exist for
the same uid which may be in different modes. Therefore only the most
interesting mode is chosen over any other mode of any calendar event with
the same uid. The most interesting mode is the first applicable from the
following list:
- start
- alarm
- upcoming
- end

Apart from these actual modes, virtual modes apply:
- changed: the actual mode has changed during this call of Calendar_CheckTimes
- alarmed: modes are alarm and changed
- started: modes are start and changed
- ended: modes are end and changed
- alarm or start: mode is alarm or start

If the mode has changed to <mode>, the following FHEM events are created:
changed uid <mode>
<mode> uid

Note: there is no colon in these FHEM events.


Program flow
------------

Calendar_Initialize sets the Calendar_Notify to watch for notifications.
Calendar_Notify acts on the INITIALIZED and REREADCFG events by starting the
    timer to call Calendar_Wakeup between 10 and 29 seconds after the
    notification.
Calendar_Wakeup starts a processing run.
    It sets the current time t as baseline for process.
    If the time for the next update has been reached,
        Calendar_GetUpdate is called
    else
        Calendar_CheckTimes
        Calendar_RearmTimer
    are called.
Calendar_GetUpdate retrieves the  iCal file. If the source is url, this is
    done asynchronously. Upon successfull retrieval of the iCal file, we
    continue with Calendar_ProcessUpdate.
Calendar_ProcessUpdate calls
        Calendar_UpdateCalendar
        Calendar_CheckTimes
        Calendar_RearmTimer
    in sequence.
Calendar_UpdateCalendar updates the VEVENT records in the
    $hash->{".fhem"}{vevents} hash and creates the associated calendar events.
Calendar_CheckTimes checks for a mode change of the calendar events and
    creates the readings and FHEM events.
Calendar_RearmTimer sets the timer to call Calendar_Wakeup to time of the
    next mode change or update, whatever comes earlier.


What's new?
-----------
This module version replaces the 2015 version that has been widely. Noteworthy
changes
- No more state... readings; "all" reading has been removed as well.
- The mode... readings (modeAlarm, modeAlarmOrStart, etc.) are deprecated
  and will be removed in a future version. Use the mode=<regex> filter instead.
- Handles recurring calendar events with out-of-order events and exceptions
  (EXDATE).
- Keeps ALL calendar events within plus/minus 400 days from the date of the
  in FHEM: this means that you can have more than one calendar event with the
  same UID.
- You can restrict visible calendar events with attributes hideLaterThan,
  hideOlderThan.
- Nonblocking retrieval of calendar from URL.
- New get commands:
    get <name> vevents
    get <name> vcalendar
    get <name> <format> <mode>
    get <name> <format> mode=<regex>
    get <name> <format> uid=<regex>
- The get commands
    get <name> <format> ...
  may not work as before since several calendar events may exist for a
  single UID, particularly the get command
    get <name> <format> all
  show all calendar events from a series (past, current, and future); you
  probably want to replace "all" by "next":
    get <name> <format> next
  to get only the first (not past but current or future) calendar event from
  each series.
- Migration hints:

  Replace
    get <name> <format> all
  by
    get <name> <format> next

  Replace
    get <name> <format> <uid>
  by
    get <name> <format> uid=<uid> 1

  Replace
    get <name> <format> modeAlarmOrStart
  by
    get <name> <format> mode=alarm|start

- The FHEM events created for mode changes of single calendar events have been
  amended:
    changed: UID <mode>
    <mode>: UID                 (this is new)
  <mode> is the current mode of the calendar event after the change. It is
  highly advisable to trigger actions based on these FHEM events instead of
  notifications for changes of the mode... readings.

=cut

#####################################
#
# human readable time format
# 
#####################################

sub beginOfMinute($) {
  my ($sec) = @_;
  return $sec == 0;
}

sub beginOfHour($$) {
  my ($sec,$min) = @_;
  return $sec == 0 && $min == 0;
}

sub beginOfDay($$$) {
  my ($sec,$min,$hour) = @_;
  return $sec == 0 && $min == 0 && $hour == 0;
}

sub humanDurationFormat($$) {
  my ($t1, $t2)= @_;
  my $d= $t2-$t1;
  my ($sec1, $min1, $hour1, $day1, $mon1, $year1) = localtime($t1);
  my ($sec2, $min2, $hour2, $day2, $mon2, $year2) = localtime($t2);
  # whole day events
  if(beginOfDay($sec1,$min1,$hour1) && beginOfDay($sec2,$min2,$hour2)) {
    if($year1 == $year2) {
      if($mon1 == $mon2) {
        if($day1 + 1 == $day2) {
          return strftime("%d.%m.%Y", $sec1, $min1, $hour1, $day1, $mon1, $year1);
        } else {
            return strftime("%d", $sec1, $min1, $hour1, $day1, $mon1, $year1) . "-" .
            strftime("%d.%m.%Y", $sec2, $min2, $hour2, $day2, $mon2, $year2); 
        }
      } else {
          return strftime("%d.%m", $sec1, $min1, $hour1, $day1, $mon1, $year1) . "-" .
          strftime("%d.%m.%Y", $sec2, $min2, $hour2, $day2, $mon2, $year2); 
        }
    } else {
          return strftime("%d.%m.%Y", $sec1, $min1, $hour1, $day1, $mon1, $year1) . "-" .
          strftime("%d.%m.%Y", $sec2, $min2, $hour2, $day2, $mon2, $year2); 
      }
  } else {
  # events that start intra-day
    if($year1 == $year2) {
      if(($day1 == $day2) && ($mon1 == $mon2)) {
        return strftime("%d.%m.%Y %k:%M", $sec1, $min1, $hour1, $day1, $mon1, $year1) . "-" .
        strftime("%k:%M", $sec2, $min2, $hour2, $day2, $mon2, $year2); 
      } else {
        return strftime("%d.%m. %k:%M", $sec1, $min1, $hour1, $day1, $mon1, $year1) . "-" .
        strftime("%d.%m.%Y %k:%M", $sec2, $min2, $hour2, $day2, $mon2, $year2); 
      }
    } else {
        return strftime("%d.%m.%Y %k:%M", $sec1, $min1, $hour1, $day1, $mon1, $year1) . "-" .
        strftime("%d.%m.%Y %k:%M", $sec2, $min2, $hour2, $day2, $mon2, $year2); 
    }
  }
  return("error in humanDurationFormat");
}

sub human($$$) {
  my($t1,$t2,$S) = @_;
  return humanDurationFormat($t1,$t2) . " " . $S;
}

#####################################
#
# Event
#
#####################################

package Calendar::Event;

sub new {
  my $class= shift;
  my $self= {}; # I am a hash
  bless $self, $class;
  $self->{_previousMode}= "undefined";
  $self->{_mode}= "undefined";
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

sub end {
  my ($self)= @_;
  return $self->{end};
}

sub setNote($$) {
  my ($self,$note)= @_;
  $self->{_note}= $note;
  return $note;
}

sub getNote($) {
  my ($self)= @_;
  return $self->{_note};
}

sub hasNote($) {
  my ($self)= @_;
  return defined($self->{_note}) ? 1 : 0;
}


sub setMode {
  my ($self,$mode)= @_;
  $self->{_previousMode}= $self->{_mode};
  $self->{_mode}= $mode;
  #main::Debug "After setMode $mode: Modes(" . $self->uid() . ") " . $self->{_previousMode} . " -> " . $self->{_mode};
  return $mode;
}

sub setModeUnchanged {
  my ($self)= @_;
  $self->{_previousMode}= $self->{_mode};
}

sub getMode {
  my ($self)= @_;
  return $self->{_mode};
}

sub lastModified {
  my ($self)= @_;
  return $self->{lastModified};
}

sub modeChanged {
  my ($self)= @_;
  return (($self->{_mode} ne $self->{_previousMode}) and
         ($self->{_previousMode} ne "undefined")) ? 1 : 0;
}


sub summary {
  my ($self)= @_;
  return $self->{summary};
}

sub location {
  my ($self)= @_;
  return $self->{location};
}

sub description {
  my ($self)= @_;
  return $self->{description};
}

sub categories {
  my ($self)= @_;
  return $self->{categories};
}

sub classfication {
  my ($self)= @_;
  return $self->{classification};
}

sub ts {
  my ($self,$tm,$tf)= @_;
  return "" unless($tm);
  $tf= $tf // "%d.%m.%Y %H:%M";
  return POSIX::strftime($tf, localtime($tm));
}

sub ts0 {
  my ($self,$tm)= @_;
  return $self->ts($tm, "%d.%m.%y %H:%M");
}

# duration as friendly string
sub td {
  # 20d
  # 47h
  # 5d 12h
  # 8d 4:22'04
  #
  my ($self, $d)= @_;
  return "" unless defined($d);
  my $s= $d % 60; $d-= $s; $d/= 60;
  my $m= $d % 60; $d-= $m; $d/= 60;
  my $h= $d % 24; $d-= $h; $d/= 24;
  if(24*$d+$h<= 72) { $h+= 24*$d; $d= 0; }
  my @r= ();
  push @r, sprintf("%dd", $d) if $d> 0;
  if($m>0 || $s>0) {
    my $t= sprintf("%d:%02d", $h, $m);
    $t.= sprintf("\'%02d", $s) if $s> 0;
    push @r, $t;
  } else {
    push @r, sprintf("%dh", $h) if $h> 0;
  }
  return join(" ", @r);
}

sub asText {
  my ($self)= @_;
  return sprintf("%s %s",
    $self->ts0($self->{start}),
    $self->{summary}
  );
}

sub asFull {
  my ($self)= @_;
  return sprintf("%s %9s %s %s-%s %s %s %s",
    $self->uid(),
    $self->getMode(),
    $self->{alarm} ? $self->ts($self->{alarm}) : "                   ",
    $self->ts($self->{start}),
    $self->ts($self->{end}),
    $self->{summary},
    $self->{categories},
    $self->{location}
  );
}

sub asDebug {
  my ($self)= @_;
  return sprintf("%s %s %9s %s %s-%s %s %s %s %s",
    $self->uid(),
    $self->modeChanged() ? "*" : " ",
    $self->getMode(),
    $self->{alarm} ? $self->ts($self->{alarm}) : "                   ",
    $self->ts($self->{start}),
    $self->ts($self->{end}),
    $self->{summary},
    $self->{categories},
    $self->{location},
    $self->hasNote() ? $self->getNote() : ""
  );
}

sub formatted {
  my ($self, $format, $timeformat)= @_;

  my $t1= $self->{start};
  my $T1= defined($t1) ? $self->ts($t1, $timeformat) : "";
  my $t2= $self->{end};
  my $T2= defined($t2) ? $self->ts($t2, $timeformat) : "";
  my $a= $self->{alarm};
  my $A= defined($a) ? $self->ts($a, $timeformat) : "";
  my $S= $self->{summary}; $S=~s/\\,/,/g;
  my $L= $self->{location}; $L=~s/\\,/,/g;
  my $CA= $self->{categories};
  my $CL= $self->{classification};
  my $DS= $self->{description}; $DS=~s/\\,/,/g;
  my $d= defined($t1) && defined($t2) ? $t2-$t1 : undef;
  my $D= defined($d) ? $self->td($d) : "";
  my $U= $self->uid();
  my $M= sprintf("%9s", $self->getMode());

  my $r= eval $format;
  $r= $@ if $@;
  return $r;
}


sub alarmTime {
  my ($self)= @_;
  return $self->ts($self->{alarm});
}

sub startTime {
  my ($self)= @_;
  return $self->ts($self->{start});
}

sub endTime {
  my ($self)= @_;
  return $self->ts($self->{end});
}


# returns 1 if time is before alarm time and before start time, else 0
sub isUpcoming {
  my ($self,$t) = @_;
  return 0 unless defined($t);
  if($self->{alarm}) {
    return $t< $self->{alarm} ? 1 : 0;
  } else {
    return $t< $self->{start} ? 1 : 0;
  }
}

# returns 1 if time is between alarm time and start time, else 0
sub isAlarmed {
  my ($self,$t) = @_;
  return $self->{alarm} ?
    (($self->{alarm}<= $t && $t< $self->{start}) ? 1 : 0) : 0;
}

# return 1 if time is between start time and end time, else 0
sub isStarted {
  my ($self,$t) = @_;
  return 0 unless(defined($self->{start}));
  return 0 if($t < $self->{start});
  if(defined($self->{end})) {
    return 0 if($t>= $self->{end});
  }
  return 1;
}

sub isSeries {
  my ($self)= @_;
  #main::Debug "      freq=  " . $self->{freq};
  return exists($self->{freq}) ? 1 : 0;
}

sub isAfterSeriesEnded {
  my ($self,$t) = @_;
  #main::Debug "    isSeries? " . $self->isSeries();
  return 0 unless($self->isSeries());
  #main::Debug "    until= " . $self->{until};
  return 0 unless(exists($self->{until}));
  #main::Debug "    has until!";
  return $self->{until}< $t ? 1 : 0;
}

sub isEnded {
  my ($self,$t) = @_;
  #main::Debug "isEnded for " . $self->asFull();
  #main::Debug "  isAfterSeriesEnded? " . $self->isAfterSeriesEnded($t);
  #return 1 if($self->isAfterSeriesEnded($t));
  #main::Debug "   has end? " . (defined($self->{end}) ? 1 : 0);
  return 0 unless(defined($self->{end}) && defined($t));
  return $self->{end}<= $t ? 1 : 0;
}

sub nextTime {
  my ($self,$t) = @_;
  my @times= ( );
  push @times, $self->{start} if(defined($self->{start}));
  push @times, $self->{end} if(defined($self->{end}));
  unshift @times, $self->{alarm} if($self->{alarm});
  if(defined($t)) {
      @times= sort grep { $_ > $t } @times;
  } else {
      @times= sort @times;
  }

#   #main::Debug "Calendar: " . $self->asFull();
#   #main::Debug "Calendar: Start " . main::FmtDateTime($self->{start});
#   #main::Debug "Calendar: End   " . main::FmtDateTime($self->{end});
#   #main::Debug "Calendar: Alarm " . main::FmtDateTime($self->{alarm}) if($self->{alarm});
#   #main::Debug "Calendar: times[0] " . main::FmtDateTime($times[0]);
#   #main::Debug "Calendar: times[1] " . main::FmtDateTime($times[1]);
#   #main::Debug "Calendar: times[2] " . main::FmtDateTime($times[2]);

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
  my $self= []; # I am an array
  bless $self, $class;
  return($self);
}

sub addEvent($$) {
  my ($self,$event)= @_;
  return push @{$self}, $event;
}

sub clear($) {
  my ($self)= @_;
  return @{$self}= ();
}

#####################################
#
# ICal
# the ical format is governed by RFC2445 http://www.ietf.org/rfc/rfc2445.txt
#
#####################################

package ICal::Entry;

sub getNextMonthlyDateByDay($$$);

sub new($$) {
  my $class= shift;
  my ($type)= @_;
  ##main::Debug "new ICal::Entry $type";
  my $self= {};
  bless $self, $class;
  $self->{type}= $type;
  #$self->clearState();  set here:
  $self->{state}= "<none>";
  #$self->clearCounterpart(); unnecessary
  #$self->clearReferences();  set here:
  $self->{references}= [];
  #$self->clearTags(); unnecessary
  $self->{entries}= [];  # array of subordinated ICal::Entry
  $self->{events}= Calendar::Events->new();
  $self->{skippedEvents}= Calendar::Events->new();
  return($self);
}

#
# keys, properties, values
#

# is key a repeated property?
sub isMultiple($$) {
  my ($self,$key)= @_;
  return $self->{properties}{$key}{multiple};
}

# has a property named key?
sub hasKey($$) {
  my ($self,$key)= @_;
  return exists($self->{properties}{$key}) ? 1 : 0;
}

# value for single property key
sub value($$) {
  my ($self,$key)= @_;
  return undef if($self->isMultiple($key));
  return $self->{properties}{$key}{VALUE};
}

# value for property key or default, if non-existant
sub valueOrDefault($$$) {
  my ($self,$key,$default)= @_;
  return $self->hasKey($key) ? $self->value($key) : $default;
}

# value for multiple property key (array counterpart)
sub values($$) {
  my ($self,$key)= @_;
  return undef unless($self->isMultiple($key));
  return $self->{properties}{$key}{VALUES};
}

# true, if the property exists at both entries and have the same value
# or neither entry has this property
sub sameValue($$$) {
  my ($self,$other,$key)= @_;
  my $value1= $self->hasKey($key) ? $self->value($key) : "";
  my $value2= $other->hasKey($key) ? $other->value($key) : "";
  return $value1 eq $value2;
}

sub parts($$) {
  my ($self,$key)= @_;
  return split(";", $self->{properties}{$key}{PARTS});
}

#
# state
#
sub setState {
  my ($self,$state)= @_;
  $self->{state}= $state;
  return $state;
}

sub clearState {
  my ($self)= @_;
  $self->{state}= "<none>";
}

sub state($) {
  my($self)= @_;
  return $self->{state};
}

sub inState($$) {
  my($self, $state)= @_;
  return ($self->{state} eq $state ? 1 : 0);
}

sub isObsolete($) {
  my($self)= @_;
  # VEVENT records in these states are obsolete
  my @statesObsolete= qw/deleted changed-old modified-old/;
  return main::contains_string $self->state(), @statesObsolete;
}

sub hasChanged($) {
  my($self)= @_;
  # VEVENT records in these states have changed
  my @statesChanged= qw/new changed-new modified-new/;
  return main::contains_string $self->state(), @statesChanged;
}

#
# type
#
sub type($) {
  my($self)= @_;
  return $self->{type};
}

#
# counterpart, for changed or modified records
#
sub counterpart($) {
  my($self)= @_;
  return $self->{counterpart};
}

sub setCounterpart($$) {
  my ($self, $id)= @_;
  $self->{counterpart}= $id;
  return $id;
}

sub hasCounterpart($) {
  my($self)= @_;
  return (defined($self->{counterpart}) ? 1 : 0);
}

sub clearCounterpart($) {
  my($self)= @_;
  delete $self->{counterpart} if(defined($self->{counterpart}));
}

#
# series
#
sub isRecurring($) {
  my($self)= @_;
  return $self->hasKey("RRULE");
}

sub isException($) {
  my($self)= @_;
  return $self->hasKey("RECURRENCE-ID");
}

sub isCancelled($) {
  my($self)= @_;
  return (($self->valueOrDefault("STATUS","CONFIRMED") eq "CANCELLED") ? 1 : 0);
}

sub hasReferences($) {
  my($self)= @_;
  return scalar(@{$self->references()});
}

sub references($) {
  my($self)= @_;
  return $self->{references};
}

sub clearReferences($) {
  my($self)= @_;
  $self->{references}= [];
}

#
# tags
#

# sub tags($) {
#   my($self)= @_;
#   return $self->{tags};
# }
#
# sub clearTags($) {
#   my($self)= @_;
#   $self->{tags}= [];
# }
#
# sub tagAs($$) {
#   my ($self, $tag)= @_;
#   push @{$self->{tags}}, $tag unless($self->isTaggedAs($tag));
# }
#
# sub isTaggedAs($$) {
#   my ($self, $tag)= @_;
#   return grep { $_ eq $tag } @{$self->{tags}} ? 1 : 0;
# }
#
# sub numTags($) {
#   my ($self)= @_;
#   return scalar @{$self->{tags}};
# }


#
# parsing
#

sub addproperty($$) {
  my ($self,$line)= @_;
  # contentline        = name *(";" param ) ":" value CRLF [Page 13]
  # example:
  # TRIGGER;VALUE=DATE-TIME:20120531T150000Z
  ##main::Debug "line=\'$line\'";
  # for DTSTART, DTEND there are several variants:
  #    DTSTART;TZID=Europe/Berlin:20140205T183600
  #  * DTSTART;TZID="(UTC+01:00) Amsterdam, Berlin, Bern, Rome, Stockholm, Vienna":20140904T180000
  #    DTSTART:20140211T212000Z
  #    DTSTART;VALUE=DATE:20130619
  my ($key,$parts,$parameter);
  if($line =~ /^([\w\d\-]+)(;((?:[^\:]+|\"[^\"]*\")*))?:(.*)$/) { # forum 140729
    $key= $1;
    $parts= $3 // "";
    $parameter= $4 // "";
  } else {
    return;
  }
  return unless($key);
  ##main::Debug "addproperty for key $key";

  # ignore some properties
  # commented out: it is faster to add the property than to do the check
  # return if(($key eq "ATTENDEE") or ($key eq "TRANSP") or ($key eq "STATUS"));
  return if(substr($key,0,2) eq "^X-");

  if(($key eq "RDATE") or ($key eq "EXDATE")) {
        ##main::Debug "addproperty for dates";
        # handle multiple properties
        my @values;
        @values= @{$self->values($key)} if($self->hasKey($key));
        push @values, split(',',$parameter);
        ##main::Debug "addproperty pushed parameter $parameter to key $key";
        $self->{properties}{$key}= {
            multiple => 1,
            VALUES => \@values,
        }
  } else {
        # handle single properties
        $self->{properties}{$key}= {
            multiple => 0,
            PARTS => "$parts",
            VALUE => "$parameter",
        }
    };
}

sub parse($$) {
  my ($self,$ics)= @_;

  # This is the proper way to do it, with \R corresponding to (?>\r\n|\n|\x0b|\f|\r|\x85|\x2028|\x2029)
  #      my @ical= split /\R/, $ics;
  # Tt does not treat some unicode emojis correctly, though.
  # We thus go for the the DOS/Windows/Unix/Mac classic variants.
  # Suggested reading:
  # http://stackoverflow.com/questions/3219014/what-is-a-cross-platform-regex-for-removal-of-line-breaks
  my @ical= defined($ics) ? split /(?>\r\n|[\r\n])/, $ics : [];
  return $self->parseSub(0, \@ical);
}

sub parseSub($$$) {
  my ($self,$ln,$icalref)= @_;
  my $len= scalar @$icalref;
  ##main::Debug "lines= $len";
  ##main::Debug "ENTER @ $ln";
  while($ln< $len) {
    my $line= $$icalref[$ln];
    $ln++;
    # check for and handle continuation lines (4.1 on page 12)
    while($ln< $len) {
      my $line1= $$icalref[$ln];
      last if(substr($line1,0,1) ne " ");
      $line.= substr($line1,1);
      $ln++;
    };
    ##main::Debug "$ln: $line";
    next if($line eq ""); # ignore empty line
    last if(substr($line,0,4) eq "END:");
    if(substr($line,0,6) eq "BEGIN:") {
      my $entry= ICal::Entry->new(substr($line,6));
      $entry->{ln}= $ln;
      push @{$self->{entries}}, $entry;
      $ln= $entry->parseSub($ln,$icalref);
    } else {
      $self->addproperty($line);
    }
  }
  ##main::Debug "BACK";
  return $ln;
}

#
# events
#
sub events($) {
  my ($self)= @_;
  return $self->{events};
}

sub clearEvents($) {
  my ($self)= @_;
  $self->{events}->clear();
}

sub numEvents($) {
  my ($self)= @_;
  return scalar(@{$self->{events}});
}

sub addEvent($$) {
  my ($self, $event)= @_;
  $self->{events}->addEvent($event);
}

sub skippedEvents($) {
  my ($self)= @_;
  return $self->{skippedEvents};
}

sub clearSkippedEvents($) {
  my ($self)= @_;
  $self->{skippedEvents}->clear();
}

sub numSkippedEvents($) {
  my ($self)= @_;
  return scalar(@{$self->{skippedEvents}});
}

sub addSkippedEvent($$) {
  my ($self, $event)= @_;
  $self->{skippedEvents}->addEvent($event);
}



sub createEvent($) {
  my ($self)= @_;

  my $event= Calendar::Event->new();

  $event->{uid}= $self->value("UID");
  $event->{uid}=~ s/\W//g; # remove all non-alphanumeric characters, this makes life easier for perl specials

  return $event;
}


# converts a date/time string to the number of non-leap seconds since the epoch
# 20120520T185202Z: date/time string in ISO8601 format, time zone GMT
# 20121129T222200: date/time string in ISO8601 format, time zone local
# 20120520:         a date string has no time zone associated
sub tm($$;$) {
  my ($self, $t, $eod)= @_;
  return undef if(!$t);
  $eod= 0 unless defined($eod);
  ##main::Debug "convert >$t<";
  my ($year,$month,$day)= (substr($t,0,4), substr($t,4,2),substr($t,6,2));
  if(length($t)>8) {
      my ($hour,$minute,$second)= (substr($t,9,2), substr($t,11,2),substr($t,13,2));
      my $z;
      $z= substr($t,15,1) if(length($t) == 16);
      ##main::Debug "$day.$month.$year $hour:$minute:$second $z";
      if($z) {
        return main::fhemTimeGm($second,$minute,$hour,$day,$month-1,$year-1900);
      } else {
        return main::fhemTimeLocal($second,$minute,$hour,$day,$month-1,$year-1900);
      }
  } else {
      ##main::Debug "$day.$month.$year";
      if($eod) {
        # treat a date without time component as end of day, i.e. start of next day, for comparisons
        return main::fhemTimeLocal(0,0,0,$day+1,$month-1,$year-1900); # fhemTimeLocal can handle days after end of month
      } else {
        return main::fhemTimeLocal(0,0,0,$day,$month-1,$year-1900);
      }
  }
}

# compare a date/time string in ISO8601 format with a point in time
# date/time string < point in time
sub before($$) {
  my ($self, $t, $pit) = @_;
  # include the whole day if the time component is missing in the date/time string
  return $self->tm($t,1) < $pit;
}

# date/time string > point in time
sub after($$) {
  my ($self, $t, $pit) = @_;
  return $self->tm($t,0) > $pit;
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
sub d($$) {
  my ($self, $d)= @_;

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
  if($dt =~ m/(\d+)H/) {
    $t+= $1*3600;
  }
  if($dt =~ m/(\d+)M/) {
    $t+= $1*60;
  }
  if($dt =~ m/(\d+)S/) {
    $t+= $1;
  }
  $t*= $sign;
  #main::Debug "sign: $sign  dw: $dw  dt: $dt   t= $t";
  return $t;
}

sub dt($$$$) {
  my ($self,$t0,$value,$parts)= @_;
  #main::Debug "t0= $t0  parts= $parts  value= $value";
  if(defined($parts) && $parts =~ m/VALUE=DATE/) {
    return $self->tm($value);
  } else {
    return $t0+$self->d($value);
  }
}


sub makeEventDetails($$) {
  my ($self, $event)= @_;

  $event->{summary}= $self->valueOrDefault("SUMMARY", "");
  $event->{location}= $self->valueOrDefault("LOCATION", "");
  $event->{description}= $self->valueOrDefault("DESCRIPTION", "");
  $event->{categories}= $self->valueOrDefault("CATEGORIES", "");
  $event->{classification}= $self->valueOrDefault("CLASS", "PUBLIC");

  return $event;
}

sub makeEventAlarms($$) {
  my ($self, $event)= @_;

  # alarms
  my @valarms= grep { $_->{type} eq "VALARM" } @{$self->{entries}};
  my @alarmtimes= sort map { $self->dt($event->{start}, $_->value("TRIGGER"), $_->parts("TRIGGER")) } @valarms;
  if(@alarmtimes) {
    $event->{alarm}= $alarmtimes[0];
  } else {
    $event->{alarm}= undef;
  }

  return $event;
}


sub DSTOffset($$) {
  my ($t1,$t2)= @_;

  my @lt1 = localtime($t1);
  my @lt2 = localtime($t2);

  return 3600 *($lt1[8] - $lt2[8]);
}

# This function adds $n times $seconds to $t1 (seconds from the epoch).
# A correction of 3600 seconds (one hour) is applied if and only if
# one of $t1 and $t1+$n*$seconds falls into wintertime and the other
# into summertime. Thus, e.g., adding a multiple of 24*60*60 seconds
# to 5 o'clock always gives 5 o'clock and not 4 o'clock or 6 o'clock
# upon a change of summertime to wintertime or vice versa.

sub plusNSeconds($$$) {
  my ($t1, $seconds, $n)= @_;
  $n= 1 unless defined($n);
  my $t2= $t1+$n*$seconds;
  return $t2+DSTOffset($t1,$t2);
}

sub plusNMonths($$) {
  my ($tm, $n)= @_;
  my ($second,$minute,$hour,$day,$month,$year,$wday,$yday,$isdst)= localtime($tm);
  $month+= $n;
  $year+= int($month / 12);
  $month %= 12;
  return main::fhemTimeLocal($second,$minute,$hour,$day,$month,$year);
}

# This function gets the next date according to interval and byDate
# Alex, 2016-11-24
# 1. parameter: startTime
# 2. parameter: interval (months)
# 3. parameter: byDay	(string with byDay-value(s), e.g. "FR" or "4SA" or "-1SU" or "4SA,4SU" (not sure if this is possible, i just take the first byDay))
sub getNextMonthlyDateByDay($$$) {
	my ( $ipTimeLocal, $ipByDays, $ipInterval )= @_;

	my ($lSecond, $lMinute, $lHour, $lDay, $lMonth, $lYear, $lWday, $lYday, $lIsdst )= localtime( $ipTimeLocal );

	#main::Debug "getNextMonthlyDateByDay($ipTimeLocal, $ipByDays, $ipInterval)";

	my @lByDays = split(",", $ipByDays);
	my $lByDay = $lByDays[0];	#only get first day element within string
	my $lByDayLength = length( $lByDay );

	my $lDayStr;		# which day to set the date
	my $lDayInterval;	# e.g. 2 = 2nd $lDayStr of month or -1 = last $lDayStr of month
	if ( $lByDayLength > 2 ) {
		$lDayStr= substr( $lByDay, -2 );
		$lDayInterval= int( substr( $lByDay, 0, $lByDayLength - 2 ) );
	} else {
		$lDayStr= $lByDay;
		$lDayInterval= 1;
	}

        my @weekdays = qw(SU MO TU WE TH FR SA);
        my ($lDayOfWeek)= grep { $weekdays[$_] eq $lDayStr } 0..$#weekdays;

	# get next day from beginning of the month, e.g. "4FR" = 4th friday of the month
	my $lNextMonth;
	my $lNextYear;
	my $lDayOfWeekNew;
	my $lDaysToAddOrSub;
	my $lNewTime;
	if ( $lDayInterval > 0 ) {
		#get next month and year according to $ipInterval
		$lNextMonth= $lMonth + $ipInterval;
		$lNextYear= $lYear;
		$lNextYear  += int( $lNextMonth / 12);
		$lNextMonth %= 12;

		my $lFirstOfNextMonth = main::fhemTimeLocal( $lSecond, $lMinute, $lHour, 1, $lNextMonth, $lNextYear );
		($lSecond, $lMinute, $lHour, $lDay, $lMonth, $lYear, $lDayOfWeekNew, $lYday, $lIsdst )= localtime( $lFirstOfNextMonth );

		if ( $lDayOfWeekNew <= $lDayOfWeek ) {
			$lDaysToAddOrSub = $lDayOfWeek - $lDayOfWeekNew;
		} else {
			$lDaysToAddOrSub = 7 - $lDayOfWeekNew + $lDayOfWeek;
		}
		$lDaysToAddOrSub += ( 7 * ( $lDayInterval - 1 ) ); #add day interval, e.g. 4th friday...

		$lNewTime = plusNSeconds( $lFirstOfNextMonth, 24*60*60*$lDaysToAddOrSub, 1);
		($lSecond, $lMinute, $lHour, $lDay, $lMonth, $lYear, $lWday, $lYday, $lIsdst )= localtime( $lNewTime );
		if ( $lMonth ne $lNextMonth ) {    #skip this date and move on to the next interval...
			$lNewTime = getNextMonthlyDateByDay( $lFirstOfNextMonth, $ipByDays, $ipInterval );
		}
	} else { #calculate date from end of month
		#get next month and year according to ipInterval
		$lNextMonth	= $lMonth + $ipInterval + 1; 	#first get the month after the desired month
		$lNextYear  = $lYear;
		$lNextYear  += int( $lNextMonth / 12);
		$lNextMonth %= 12;

		my $lLastOfNextMonth = main::fhemTimeLocal( $lSecond, $lMinute, $lHour, 1, $lNextMonth, $lNextYear ); # get time
		$lLastOfNextMonth = plusNSeconds( $lLastOfNextMonth, -24*60*60, 1 );	#subtract one day

		($lSecond, $lMinute, $lHour, $lDay, $lMonth, $lYear, $lDayOfWeekNew, $lYday, $lIsdst )= localtime( $lLastOfNextMonth );

		if ( $lDayOfWeekNew >= $lDayOfWeek )
		{
			$lDaysToAddOrSub = $lDayOfWeekNew - $lDayOfWeek;
		}
		else
		{
			$lDaysToAddOrSub =  7 - $lDayOfWeek + $lDayOfWeekNew;
		}
		$lDaysToAddOrSub += ( 7 * ( abs( $lDayInterval ) - 1 ) );

		$lNewTime = plusNSeconds( $lLastOfNextMonth, -24*60*60*$lDaysToAddOrSub, 1);
	}

	return $lNewTime;
}

use constant eventsLimitMinus => -34560000; # -400d
use constant eventsLimitPlus  =>  34560000; # +400d

sub addEventLimited($$$) {
    my ($self, $t, $event)= @_;

    return -1 if($event->start()< $t+eventsLimitMinus);
    return  1 if($event->start()> $t+eventsLimitPlus);
    $self->addEvent($event);
    #main::Debug "  addEventLimited: " . $event->asDebug();
    return  0;

}

# 0= SU ... 6= SA
sub weekdayOf($$) {
  my ($self, $t)= @_;
  my (undef, undef, undef, undef,  undef, undef, $weekday, undef, undef) = localtime($t);
  return $weekday;
}

sub createSingleEvent($$$$) {

    my ($self, $nextstart, $onCreateEvent)= @_;

    my $event= $self->createEvent();
    my $start= $self->tm($self->value("DTSTART"));
    $nextstart= $start unless(defined($nextstart));
    $event->{start}= $nextstart;
    if($self->hasKey("DTEND")) {
        my $end= $self->tm($self->value("DTEND"));
        $event->{end}= $nextstart+($end-$start);
    } elsif($self->hasKey("DURATION")) {
        my $duration= $self->d($self->value("DURATION"));
        $event->{end}= $nextstart + $duration;
    } else {

      # Page 53ge 53
      # For cases where a "VEVENT" calendar component
      # specifies a "DTSTART" property with a DATE value type but no
      # "DTEND" nor "DURATION" property, the event's duration is taken to
      # be one day.  For cases where a "VEVENT" calendar component
      # specifies a "DTSTART" property with a DATE-TIME value type but no
      # "DTEND" property, the event ends on the same calendar date and
      # time of day specified by the "DTSTART" property.
      #
      # https://forum.fhem.de/index.php?topic=75308
        $event->{end}= $nextstart + 86400;
    }
    $self->makeEventDetails($event);
    $self->makeEventAlarms($event);

    #main::Debug "createSingleEvent DTSTART=" . $self->value("DTSTART") . " DTEND=" . $self->value("DTEND");
    #main::Debug "createSingleEvent Start " . main::FmtDateTime($event->{start});
    #main::Debug "createSingleEvent End   " . main::FmtDateTime($event->{end});

    # plug-in
    if(defined($onCreateEvent)) {
        my $e= $event;
        #main::Debug "Executing $onCreateEvent for " . $e->asDebug();
        eval $onCreateEvent;
        if($@) {
            main::Log3 undef, 2, "Erroneous onCreateEvent $onCreateEvent: $@";
        } else {
            $event= $e;
        }
    }

    return $event;
}

sub excludeByExdate($$) {
  my ($self, $event)= @_;
  my $skip= 0;
  if($self->hasKey('EXDATE')) {
      foreach my $exdate (@{$self->values("EXDATE")}) {
          if($self->tm($exdate) == $event->start()) {
              $skip++;
              $event->setNote("EXDATE: $exdate");
              $self->addSkippedEvent($event);
              last;
          }
      } # end of foreach exdate
  } # end of EXDATE checking
  return $skip;
}

sub excludeByReference($$$) {
  my ($self, $event, $veventsref)= @_;
  my $skip= 0;
  # check if superseded by out-of-series event
  if($self->hasReferences()) {
      foreach my $id (@{$self->references()}) {
          my $vevent= $veventsref->{$id};
          # saving the originalstart speeds up processing on repeated checks
          my $originalstart= $vevent->{originalstart};
          if(!defined($originalstart)) {
            my $recurrenceid= $vevent->value("RECURRENCE-ID");
            $originalstart= $vevent->tm($recurrenceid);
            $vevent->{originalstart}= $originalstart;
          }
          if($originalstart == $event->start()) {
              #$event->setNote("RECURRENCE-ID: $recurrenceid");
              $self->addSkippedEvent($event);
              $skip++;
              last;
          }
      }
  }
  return $skip;
}

sub excludeByRdate($$) {
  my ($self, $event)= @_;
  my $skip= 0;
  # check if excluded by a duplicate RDATE
  # this is only to avoid duplicates from previously added RDATEs
  if($self->hasKey('RDATE')) {
      foreach my $rdate (@{$self->values("RDATE")}) {
          if($self->tm($rdate) == $event->start()) {
              $event->setNote("RDATE: $rdate");
              $self->addSkippedEvent($event);
              $skip++;
              last;
          }
      }
  }
  return $skip;
}

# we return 0 if the storage limit is exceeded or the number of occurances is reached
# we return 1 else no matter if this evevent was added or skipped
sub addOrSkipSeriesEvent($$$$$$) {
  my ($self, $event, $t0, $until, $count, $veventsref)= @_;

  #main::Debug " addOrSkipSeriesEvent: " . $event->asDebug();
  return if($event->{start} > $until); # return if we are after end of series

  my $skip= 0;

  # check if superseded by out-of-series event
  $skip+= $self->excludeByReference($event, $veventsref);

  # RFC 5545 p. 120
  # The final recurrence set is generated by gathering all of the
  # start DATE-TIME values generated by any of the specified "RRULE"
  # and "RDATE" properties, and then excluding any start DATE-TIME
  # values specified by "EXDATE" properties.  This implies that start
  # DATE-TIME values specified by "EXDATE" properties take precedence
  # over those specified by inclusion properties (i.e., "RDATE" and
  # "RRULE").  Where duplicate instances are generated by the "RRULE"
  # and "RDATE" properties, only one recurrence is considered.
  # Duplicate instances are ignored.

  # check if excluded by EXDATE
  $skip+= $self->excludeByExdate($event);

  # check if excluded by a duplicate RDATE
  # this is only to avoid duplicates from previously added RDATEs
  $skip+= $self->excludeByRdate($event);

  if(!$skip) {
      # add event
      # and return if we exceed storage limit
      my $x= $self->addEventLimited($t0, $event);
      #main::Debug "addEventLimited returned $x";
      return 0 if($x> 0);
      #return 0 if($self->addEventLimited($t0, $event) > 0);
  }

  my $occurances= scalar(@{$self->{events}})+scalar(@{$self->{skippedEvents}});
  #main::Debug("$occurances occurances so far");
  return($occurances< $count);

}

sub createEvents($$$$$$%) {
  my ($self, $name, $t0, $onCreateEvent,
    $cutoffLowerBound, $cutoffUpperBound, %vevents)= @_; # t0 is today (for limits)

  $self->clearEvents();
  $self->clearSkippedEvents();

  if($self->isRecurring()) {
        #
        # recurring event creates a series
        #
        my $rrule= $self->value("RRULE");
        my @rrparts= split(";", $rrule);
        my %r= map { split("=", $_); } @rrparts;

        my @keywords= qw(FREQ INTERVAL UNTIL COUNT BYMONTHDAY BYDAY BYMONTH WKST);
        foreach my $k (keys %r) {
            if(not(main::contains_string $k, @keywords)) {
                main::Log3 $name, 3, "Calendar $name: keyword $k in RRULE $rrule is not supported";
            } else {
                #main::Debug "keyword $k in RRULE $rrule has value $r{$k}";
            }
        }

        # Valid values for freq: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, YEARLY
        my $freq =  $r{"FREQ"};
        #main::Debug "FREQ= $freq";
        # According to RFC, interval defaults to 1
        my $interval = exists($r{"INTERVAL"}) ? $r{"INTERVAL"} : 1;
        my $until = exists($r{"UNTIL"}) ? $self->tm($r{"UNTIL"}) : 99999999999999999;
        $until= $cutoffUpperBound if($cutoffUpperBound && ($until> $cutoffUpperBound));
        my $count = exists($r{"COUNT"}) ? $r{"COUNT"} : 999999;
        my $bymonthday = $r{"BYMONTHDAY"} if(exists($r{"BYMONTHDAY"})); # stored but ignored
        my $byday = exists($r{"BYDAY"}) ? $r{"BYDAY"} : "";
        #main::Debug "byday is $byday";
        my $bymonth = $r{"BYMONTH"} if(exists($r{"BYMONTH"})); # stored but ignored
        my $wkst = $r{"WKST"} if(exists($r{"WKST"})); # stored but ignored

        my @weekdays = qw(SU MO TU WE TH FR SA);


        #main::Debug "createEvents: " . $self->asString();

        #
        # we first add all RDATEs
        #
        if($self->hasKey('RDATE')) {
            foreach my $rdate (@{$self->values("RDATE")}) {
                my $tr= $self->tm($rdate);
                my $event= $self->createSingleEvent($tr, $onCreateEvent);
                my $skip= 0;
                if($self->hasKey('EXDATE')) {
                    foreach my $exdate (@{$self->values("EXDATE")}) {
                        if($self->tm($exdate) == $event->start()) {
                            $event->setNote("EXDATE: $exdate for RDATE: $rdate");
                            $self->addSkippedEvent($event);
                            $skip++;
                            last;
                        }
                    }
                }
                if(!$skip) {
                    # add event
                    $event->setNote("RDATE: $rdate");
                    $self->addEventLimited($t0, $event);
                }
            }
        }

        #
        # now we build the series
        #
        #main::Debug "building series...";

        # first event in the series
        my $event= $self->createSingleEvent(undef, $onCreateEvent);
        return if(!$self->addOrSkipSeriesEvent($event, $t0, $until, $count, \%vevents));
        my $nextstart = $event->{start};
        #main::Debug "start: " . $event->ts($nextstart);

        if(($freq eq "WEEKLY") && ($byday ne "")) {
            # special handling for WEEKLY and BYDAY

            # BYDAY with prefix (e.g. -1SU or 2MO) is not recognized
            #main::Debug "weekly event, BYDAY= $byday";
            my @bydays= split(',', $byday);

            # we assume a week from MO to SU
            # we need to cover situations similar to:
            #  BYDAY= TU,WE,TH and start is WE or end is WE

            # loop over days, skip over weeks
            # e.g. TH, FR, SA, SU / ... / MO, TU, WE
            while(1) {
              # next day
              $nextstart= plusNSeconds($nextstart, 24*60*60, 1);
              my $weekday= $self->weekdayOf($nextstart);
              # if we reach MO, then skip ($interval-1) weeks
              $nextstart= plusNSeconds($nextstart, 7*24*60*60, $interval-1) if($weekday==1);
              #main::Debug "Skip to: start " . $event->ts($nextstart) . " = " . $weekdays[$weekday];
              if(main::contains_string $weekdays[$weekday], @bydays) {
                my $event= $self->createSingleEvent($nextstart, $onCreateEvent);
                return if(!$self->addOrSkipSeriesEvent($event, $t0, $until, $count, \%vevents));
              }
            }
        } else {
            # handling for events with equal time spacing
            while(1) {
                # advance to next occurance
                if($freq eq "SECONDLY") {
                    $nextstart = plusNSeconds($nextstart, 1, $interval);
                } elsif($freq eq "MINUTELY") {
                    $nextstart = plusNSeconds($nextstart, 60, $interval);
                } elsif($freq eq "HOURLY") {
                    $nextstart = plusNSeconds($nextstart, 60*60, $interval);
                } elsif($freq  eq "DAILY") {
                    $nextstart = plusNSeconds($nextstart, 24*60*60, $interval);
                } elsif($freq  eq "WEEKLY") {
                    # default WEEKLY handling
                    $nextstart = plusNSeconds($nextstart, 7*24*60*60, $interval);
                } elsif($freq eq "MONTHLY") {
          				if ( $byday ne "" ) {
          					$nextstart = getNextMonthlyDateByDay( $nextstart, $byday, $interval );
            			} else {
                      # here we ignore BYMONTHDAY as we consider the day of month of $self->{start}
                      # to be equal to BYMONTHDAY.
                      $nextstart= plusNMonths($nextstart, $interval);
            				}
                } elsif($freq eq "YEARLY") {
                    $nextstart= plusNMonths($nextstart, 12*$interval);
                } else {
                    main::Log3 undef, 2, "Calendar: event frequency '$freq' not implemented";
                    return;
                }
                # the next event
                #main::Debug "Skip to: start " . $event->ts($nextstart);
                $event= $self->createSingleEvent($nextstart, $onCreateEvent);
                return if(!$self->addOrSkipSeriesEvent($event, $t0, $until, $count, \%vevents));
            }
        }

  } else {
        #
        # single event
        #
        my $event= $self->createSingleEvent(undef, $onCreateEvent);
        $self->addEventLimited($t0, $event);
  }

}


#
# friendly string
#
sub asString($$) {
  my ($self,$level)= @_;
  $level= "" unless(defined($level));
  my $s= $level . $self->{type};
  $s.= " @" . $self->{ln} if(defined($self->{ln}));
  $s.= " [";
  $s.= "obsolete, " if($self->isObsolete());
  $s.= $self->state();
  $s.= ", refers to " . $self->counterpart() if($self->hasCounterpart());
  $s.= ", in a series with " . join(",", sort @{$self->references()}) if($self->hasReferences());
  $s.= "]";
  #$s.= " (tags: " . join(",", @{$self->tags()}) . ")" if($self->numTags());
  $s.= "\n";
  $level .= "    ";
  for my $key (sort keys %{$self->{properties}}) {
    $s.= $level . "$key: ";
    if($self->{properties}{$key}{multiple}) {
        $s.= "(" . join(" ", @{$self->values($key)}) . ")";
    } else {
        $s.= $self->value($key);
    }
    $s.= "\n";
  }
  if($self->{type} eq "VEVENT") {
    if($self->isRecurring()) {
        $s.= $level . ">>> is a series\n";
    }
    if($self->isException()) {
        $s.= $level . ">>> is an exception\n";
    }
    $s.= $level . ">>> Events:\n";
    foreach my $event (@{$self->{events}}) {
        $s.= "$level  " . $event->asDebug() . "\n";
    }
    $s.= $level . ">>> Skipped events:\n";
    foreach my $event (@{$self->{skippedEvents}}) {
        $s.= "$level  " . $event->asDebug() . "\n";
    }
  }
  my @entries=  @{$self->{entries}};
  for(my $i= 0; $i<=$#entries; $i++) {
    $s.= $entries[$i]->asString($level);
  }

  return $s;
}

##########################################################################
#
# main
#
##########################################################################

package main;

#####################################
sub Calendar_Initialize($) {

  my ($hash) = @_;
  $hash->{DefFn}   = "Calendar_Define";
  $hash->{UndefFn} = "Calendar_Undef";
  $hash->{GetFn}   = "Calendar_Get";
  $hash->{SetFn}   = "Calendar_Set";
  $hash->{AttrFn}   = "Calendar_Attr";
  $hash->{NotifyFn}= "Calendar_Notify";
  $hash->{AttrList}=  "update:none,onUrlChanged ".
                      "synchronousUpdate:0,1 ".
                      "delay " .
                      "timeout " .
                      "removevcalendar:0,1 " .
                      "ignoreCancelled:0,1 ".
                      "SSLVerify:0,1 ".
                      "cutoffOlderThan cutoffLaterThan hideOlderThan hideLaterThan ".
                      "onCreateEvent quirks ".
                      "defaultFormat defaultTimeFormat ".
                      "hasModeReadings:0,1 " .
                      $readingFnAttributes;
}


#####################################
sub Calendar_Define($$) {

  my ($hash, $def) = @_;

  # define <name> Calendar ical URL [interval]

  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> Calendar ical url <URL> [interval]\n".\
         "        define <name> Calendar ical file <FILENAME> [interval]"
    if(($#a < 4 && $#a > 5) || ($a[2] ne 'ical') || (($a[3] ne 'url') && ($a[3] ne 'file')));

  $hash->{NOTIFYDEV} = "global";
  readingsSingleUpdate($hash, "state", "initialized", 1);

  my $name      = $a[0];
  my $type      = $a[3];
  my $url       = $a[4];
  my $interval  = 3600;
  if($#a==5) {
    $interval= $a[5] if ($a[5] > 0);
    Log3 $hash,2,"Calendar $name: interval $a[5] not allowed. Using 3600 as default." if ($a[5] <= 0);
  }

  $hash->{".fhem"}{type}= $type;
  $hash->{".fhem"}{url}= $url;
  $hash->{".fhem"}{lasturl}= $url;
  $hash->{".fhem"}{interval}= $interval;
  $hash->{".fhem"}{lastid}= 0;
  $hash->{".fhem"}{vevents}= {};
  $hash->{".fhem"}{nxtUpdtTs}= 0;
  $hash->{".fhem"}{noWildcards} = ($url =~ /google/) ? 1 : 0;

  #$attr{$name}{"hideOlderThan"}= 0;

  #main::Debug "Interval: ${interval}s";
  # if initialization is not yet done, we do not wake up at this point already to
  # avoid the following race condition:
  # events are loaded from fhem.save and data are updated asynchronousy from
  # non-blocking Http get
  Calendar_Wakeup($hash, 0) if($init_done);


  return undef;
}

#####################################
sub Calendar_deleteModeReadings($) {

  my ($hash) = @_;
  my $deletedCount= 0;
  my $name= $hash->{NAME};

  foreach my $reading (grep { /mode.*/ } keys %{$hash->{READINGS}} ) {
      readingsDelete($hash, $reading);
      $deletedCount++;
  }
  Log3 $hash, 3, "Calendar $name: $deletedCount obsolete mode readings deleted." if($deletedCount);
}

#####################################
sub Calendar_Undef($$) {

  my ($hash, $arg) = @_;

  Calendar_DisarmTimer($hash);

  if(exists($hash->{".fhem"}{subprocess})) {
    my $subprocess= $hash->{".fhem"}{subprocess};
    $subprocess->terminate();
    $subprocess->wait();
  }

  return undef;
}


#####################################
sub Calendar_Attr(@) {

  my ($cmd, $name, @a) = @_;

  return undef unless($cmd eq "set");

  my $hash= $defs{$name};

  return "attr $name needs at least one argument." if(!@a);

  my $arg= $a[1];
  if($a[0] eq "onCreateEvent") {
    if($arg !~ m/^{.*}$/s) {
        return "$arg must be a perl command in curly brackets but you supplied $arg.";
    }
  } elsif($a[0] eq "update") {
    my @args= qw/sync async/;
    if (main::contains_string $arg, @args) { # inform about new attribute synchronousUpdate
       Log3 $hash,2,"Calendar $name: Value '$arg' for attribute 'update' is deprecated.";
       Log3 $hash,2,"Calendar $name: Please use new attribute 'synchronousUpdate' if really needed.";
       Log3 $hash,2,"Calendar $name: Attribute 'update' deleted. Please use 'save config' to update your configuration.";
       CommandDefine(undef,"delattr_$name at +00:00:01 deleteattr $name update");
       return undef;
    }
    @args= qw/none onUrlChanged/;
    return "Calendar $name: Argument for update must be one of " . join(" ", @args) .
           " instead of $arg." unless(main::contains_string $arg, @args);
  }

  return undef;

}

###################################
sub Calendar_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  return if($attr{$name} && $attr{$name}{disable});

  # update calendar after initialization or change of configuration
  # wait 10 to 29 seconds to avoid congestion due to concurrent activities
  Calendar_DisarmTimer($hash);
  my $delay= AttrVal($name, "delay", 10+int(rand(20)));

  Log3 $hash, 5, "Calendar $name: FHEM initialization or rereadcfg triggered update, delay $delay seconds.";
  InternalTimer(time()+$delay, "Calendar_Wakeup", $hash, 0) ;

  return undef;
}

###################################
sub Calendar_Set($@) {
  my ($hash, @a) = @_;

  my $cmd= $a[1];
  $cmd= "?" unless($cmd);


  my $t= time();
  # usage check
  if((@a == 2) && ($a[1] eq "update")) {
     Calendar_DisarmTimer($hash);
     Calendar_GetUpdate($hash, $t, 0);
     return undef;
  } elsif((@a == 2) && ($a[1] eq "reload")) {
     Calendar_DisarmTimer($hash);
     Calendar_GetUpdate($hash, $t, 1); # remove all events before update
     return undef;
  } else {
    return "Unknown argument $cmd, choose one of update:noArg reload:noArg";
  }
}

###################################
# everything within matching single or double quotes is literally copied
# everything within braces is literally copied, nesting braces is allowed
# use \ to mask quotes and braces
# parts are separated by one or more spaces
sub Calendar_simpleParseWords($;$) {
  my ($p,$separator)= @_;
  $separator= " " unless defined($separator);

  my $quote= undef;
  my $braces= 0;
  my @parts= (); # resultant array of space-separated parts
  my @chars= split(//, $p); # split into characters
  my $escape= 0; # escape mode off
  my @part= (); # the current part
  for my $c (@chars) {
    #Debug "checking $c, quote is " . (defined($quote) ? $quote : "empty") . ", braces is $braces";
    push @part, $c; # append the character to the current part
    if($escape) { $escape= 0; next; } # continue and turn escape mode off if escape mode is on
    if(($c eq $separator)  && !$braces && !defined($quote)) { # we have encountered a space outside quotes and braces
      #Debug " break";
      pop @part; # remove the space
      push @parts, join("", @part) if(@part);  # add the completed part if non-empty
      @part= ();
      next;
    }
    $escape= ($c eq "\\"); next if($escape); # escape mode on
    #Debug " not escaped";
    if(($c eq "\"") || ($c eq "\'")) {
      #Debug " quote";
      if(defined($quote)) {
        if($c eq $quote) { $quote= undef; }
      } else {
        $quote= $c;
      }
      next;
    }
    next if defined($quote);
    if($c eq "{") { $braces++; next; } # opening brace
    if($c eq "}") { # closing brace
      return("closing brace without matching opening brace", undef) unless($braces);
      $braces--;
    }
  }
  return("opening quote $quote without matching closing quote", undef) if(defined($quote));
  return("$braces opening brace(s) without matching closing brace(s)", undef) if($braces);
  push @parts, join("", @part) if(@part);  # add the completed part
  return(undef, \@parts);
}

sub Calendar_Get($@) {

  my ($hash, @a) = @_;
  my $name= $hash->{NAME};

  my $t= time();

  my $eventsObj= $hash->{".fhem"}{events};
  my @events;

  #Debug "Command line: " . join(" ", @a);
  my $cmd= $a[1];
  $cmd= "?" unless($cmd);


  # --------------------------------------------------------------------------
  if($cmd eq "update") {
    # this is the same as set update for convenience
    Calendar_DisarmTimer($hash);
    Calendar_GetUpdate($hash, $t, 0, 1);
    return undef;
  }

  # --------------------------------------------------------------------------
  if($cmd eq "reload") {
    # this is the same as set reload for convenience
     Calendar_DisarmTimer($hash);
     Calendar_GetUpdate($hash, $t, 1, 1); # remove all events before update
     return undef;
  }

  # --------------------------------------------------------------------------
  if($cmd eq "events") {

    # see https://forum.fhem.de/index.php/topic,46608.msg397309.html#msg397309 for ideas
    # get myCalendar events
    #   filter:mode=alarm|start|upcoming
    #   format:custom={ sprintf("...") }
    #   series:next=3
    # attr myCalendar defaultFormat <format>

    my $format= AttrVal($name, "defaultFormat", '"$T1 $D $S"');
    my $timeFormat= AttrVal($name, "defaultTimeFormat",'%d.%m.%Y %H:%M');
    my @filters= ();
    my $next= undef;
    my $count= undef;
    my $returnFormat= '$text';
    my @includes= ();

    my ($paramerror, $arrayref)= Calendar_simpleParseWords(join(" ", @a));
    return "$name: Parameter parse error: $paramerror" if(defined($paramerror));
    my @a= @{$arrayref};
    shift @a; shift @a; # remove name and "events"
    for my $p (@a) {
      ### format
      if($p =~ /^format:(.+)$/) {
        my $v= $1;
        if($v eq "default") {
          # as if it were not there at all
        } elsif($v eq "full") {
          $format= '"$U $M $A $T1-$T2 $S $CA $L"';
        } elsif($v eq "text") {
          $format= '"$T1 $S"';
        } elsif($v =~ /^custom=['"](.+)['"]$/) {
          $format= '"'.$1.'"';
        } elsif($v =~ /^custom=(\{.+\})$/) {
          $format= $1;
          #Debug "Format=$format";
        } elsif($v eq "human") {
          $format='{ main::human($t1,$t2,$S) }';
        } else {
          return "$name: Illegal format specification: $v";
        }
      ### timeFormat
    } elsif($p =~ /^timeFormat:['"](.+)['"]$/) {
        $timeFormat= $1;
      ### filter
    } elsif($p =~ /^filter:(.+)$/) {
        my ($filtererror, $filterarrayref)= Calendar_simpleParseWords($1, ",");
        return "$name: Filter parse error: $filtererror" if(defined($filtererror));
        my @filterspecs= @{$filterarrayref};
        for my $filterspec (@filterspecs) {
          #Debug "Filter specification: $filterspec";
          if($filterspec =~ /^mode==['"](.+)['"]$/) {
              push @filters, { ref => \&filter_mode, param => $1 }
          } elsif($filterspec =~ /^mode=~['"](.+)['"]$/) {
              push @filters, { ref => \&filter_modes, param => $1 }
          } elsif($filterspec =~ /^uid==['"](.+)['"]$/) {
              push @filters, { ref => \&filter_uid, param => $1 }
          } elsif($filterspec =~ /^uid=~['"](.+)['"]$/) {
              push @filters, { ref => \&filter_uids, param => $1 }
          } elsif($filterspec =~ /^field\((uid|mode|summary|description|location|categories|classification)\)==['"](.+)['"]$/) {
                push @filters, { ref => \&filter_field, field => $1, param => $2 }
          } elsif($filterspec =~ /^field\((uid|mode|summary|description|location|categories|classification)\)=~['"](.+)['"]$/) {
                push @filters, { ref => \&filter_fields, field => $1, param => $2 }
          } else {
            return "$name: Illegal filter specification: $filterspec";
          }
        }
      ### series
    } elsif($p =~ /^series:(.+)$/) {
        my ($serieserror,$seriesarrayref)= Calendar_simpleParseWords($1, ",");
        return "$name: Series parse error: $serieserror" if(defined($serieserror));
        my @seriesspecs= @{$seriesarrayref};
        for my $seriesspec (@seriesspecs) {
          if($seriesspec eq "next") {
            $next= 1;
            push(@filters, { ref => \&filter_notend });
          } elsif($seriesspec =~ /next=([1-9]+\d*)/) {
            $next= $1;
            push(@filters, { ref => \&filter_notend });
          } else {
            return "$name: Illegal series specification: $seriesspec";
          }
        }
      ### limit
    } elsif($p =~ /^limit:(.+)$/) {
        my ($limiterror, $limitarrayref)= Calendar_simpleParseWords($1, ",");
        return "$name: Limit parse error: $limiterror" if(defined($limiterror));
        my @limits= @{$limitarrayref};
        for my $limit (@limits) {
          if($limit =~ /count=([1-9]+\d*)/) {
            $count= $1;
          } elsif($limit =~ /^when=(today|tomorrow|(-?\d+)(..(-?\d+))?)$/i) {
            my ($from,$to,$d1,$d2);
            if (lc($1) eq 'today') {
              $d1= 0;
              $d2= 0;
            } elsif(lc($1) eq 'tomorrow') {
              $d1= 1;
              $d2= 1;
            } else {
              $d1= $2;
              $d2= $d1;
              if(defined($4) and ($4 ne '')) {
                $d2= $4;
              }
              ($d1,$d2)= ($d2,$d1) if($d1> $d2);
            }
            $from  = $d1*DAYSECONDS - Calendar_GetSecondsFromMidnight();
            $to    = $from + ($d2-$d1+1)*DAYSECONDS - 1;
            push @filters, { ref => \&filter_endafter, param => $t+$from };
            push @filters, { ref => \&filter_startbefore, param => $t+$to };
          } elsif($limit =~ /from=([+-]?)(.+)/ ) {
            my $sign= $1 eq "-" ? -1 : 1;
            my ($error, $from)= Calendar_GetSecondsFromTimeSpec($2);
            return "$name: $error" if($error);
            push @filters, { ref => \&filter_endafter, param => $t+$sign*$from };
          } elsif($limit =~ /to=([+-]?)(.+)/ ) {
            my $sign= $1 eq "-" ? -1 : 1;
            my ($error, $to)= Calendar_GetSecondsFromTimeSpec($2);
            return "$name: $error" if($error);
            push @filters, { ref => \&filter_startbefore, param => $t+$sign*$to };
          } else {
            return "$name: Illegal limit specification: $limit";
          }

      }
    } elsif($p =~ /^returnType:(.+)$/) {
        $returnFormat= $1;
        if( ($returnFormat eq '$text') ||
            ($returnFormat eq '@events') ||
            ($returnFormat eq '@texts')) {
              # fine
        } else {
          return "$name: Illegal return format: $returnFormat";
        }
    } elsif($p =~ /^include:(.+)$/) {
        @includes= split(",", $1);
        # remove duplicates
        @includes= keys %{{ map{ $_ => 1 } @includes }};
        #my %seen = ();
        #@includes = grep { ! $seen{ $_ }++ } @includes;
    } else {
        return "$name: Illegal parameter: $p";
      }
    }

    my @events= Calendar_GetEvents($hash, $t, @filters);

    if($#includes>= 0) {
      foreach my $calname (@includes) {
        next if($calname eq $name); # silently ignore inclusion of this calendar
        my $dev= $defs{$calname};
        if(defined($dev) && $dev->{TYPE} eq "Calendar") {
          push @events, Calendar_GetEvents($dev, $t, @filters);
        } else {
          Log3 $hash, 2, "$name: device $calname does not exist or is not a Calendar";
        }
      }
      @events= sort { $a->start() <=> $b->start() } @events;
    }

    # special treatment for next
    if(defined($next)) {
        my %uids;  # remember the UIDs
        # the @events are ordered by start time ascending
        # they do contain all events that have not ended
        @events = grep {
            my $seen= $uids{$_->uid()} // 0;
            $uids{$_->uid()}= ++$seen;
            #Debug $_->uid() . " => " . $seen . ", next= $next";
            $seen <= $next;
        } @events;
    }

    return @events if($returnFormat eq '@events');

    my $n= 0;
    my @texts;
    foreach my $event (@events) {
        push @texts, $event->formatted($format, $timeFormat);
        last if(defined($count) && (++$n>= $count));
    }
    return @texts  if($returnFormat eq '@texts');

    return "" if($#texts<0);
    return join("\n", @texts);

  }

  # --------------------------------------------------------------------------
  my @cmds2= qw/text full summary location description categories alarm start end uid debug/;
  if(main::contains_string $cmd, @cmds2) {

    return "argument is missing" if($#a < 2);
    Log3 $hash, 2, "get $name $cmd is deprecated and will be removed soon. Use get $name events instead.";
    my $filter= $a[2];


    # $reading is alarm, all, changed, start, end, upcoming
    my $filterref;
    my $param= undef;
    my $keeppos= 3;
    if($filter eq "changed") {
        $filterref= \&filter_changed;
    } elsif($filter eq "alarm") {
        $filterref= \&filter_alarm;
    } elsif($filter eq "start") {
        $filterref= \&filter_start;
    } elsif($filter eq "end") {
        $filterref= \&filter_end;
    } elsif($filter eq "upcoming") {
        $filterref= \&filter_upcoming;
    } elsif($filter =~ /^uid=(.+)$/) {
        $filterref= \&filter_uids;
        $param= $1;
    } elsif($filter =~ /^mode=(.+)$/) {
        $filterref= \&filter_modes;
        $param= $1;
    } elsif(($filter =~ /^mode\w+$/) and (defined($hash->{READINGS}{$filter}))) {
        #main::Debug "apply filter_reading";
        $filterref= \&filter_reading;
        my @uids= split(";", $hash->{READINGS}{$filter}{VAL});
        $param= \@uids;
    } elsif($filter eq "all") {
        $filterref= \&filter_true;
    } elsif($filter eq "next") {
        $filterref= \&filter_notend;
        $param= { }; # reference to anonymous (unnamed) empty hash, thus $ in $param
    } else { # everything else is interpreted as uid
        $filterref= \&filter_uid;
        $param= $a[2];
    }
    my @filters= ( { ref => $filterref, param => $param } );
    @events= Calendar_GetEvents($hash, $t, @filters);

    # special treatment for next
    if($filter eq "next") {
        my %uids;  # remember the UIDs

        # the @events are ordered by start time ascending
        # they do contain all events that have not ended
        @events= grep {
            my $seen= defined($uids{$_->uid()});
            $uids{$_->uid()}= 1;
            not $seen;
        } @events;

    }

    my @texts;

    if(@events) {
      foreach my $event (sort { $a->start() <=> $b->start() } @events) {
        push @texts, $event->uid() if $cmd eq "uid";
        push @texts, $event->asText() if $cmd eq "text";
        push @texts, $event->asFull() if $cmd eq "full";
        push @texts, $event->asDebug() if $cmd eq "debug";
        push @texts, $event->summary() if $cmd eq "summary";
        push @texts, $event->location() if $cmd eq "location";
        push @texts, $event->description() if $cmd eq "description";
        push @texts, $event->categories() if $cmd eq "categories";
        push @texts, $event->alarmTime() if $cmd eq "alarm";
        push @texts, $event->startTime() if $cmd eq "start";
        push @texts, $event->endTime() if $cmd eq "end";
      }
    }
    if(defined($a[$keeppos])) {
      my $keep= $a[$keeppos];
      return "Argument $keep is not a number." unless($keep =~ /\d+/);
      $keep= $#texts+1 if($keep> $#texts);
      splice @texts, $keep if($keep>= 0);
    }
    return "" if($#texts<0);
    return join("\n", @texts);

  } elsif($cmd eq "vevents") {

        my %vevents= %{$hash->{".fhem"}{vevents}};
        my $s= "";
        foreach my $key (sort {$a<=>$b} keys %vevents) {
            $s .= "$key: ";
            $s .= $vevents{$key}->asString();
            $s .= "\n";
        }
        return $s;

  } elsif($cmd eq "vcalendar") {

        return undef unless(defined($hash->{".fhem"}{iCalendar}));
        return $hash->{".fhem"}{iCalendar}

  } elsif($cmd eq "find") {

    return "argument is missing" if($#a != 2);
    my $regexp= $a[2];

    my %vevents= %{$hash->{".fhem"}{vevents}};
    my %uids;
    foreach my $id (keys %vevents) {
        my $v= $vevents{$id};
        my @events= @{$v->{events}};
        if(@events) {
            eval {
                if($events[0]->summary() =~ m/$regexp/) {
                    $uids{$events[0]->uid()}= 1;    #
                }
            }
        }
        Log3($hash, 2, "Calendar " . $hash->{NAME} .
            ": The regular expression $regexp caused a problem: $@") if($@);
    }
    return join(";", keys %uids);

  } else {
    return "Unknown argument $cmd, choose one of update:noArg reload:noArg events find text full summary location description categories alarm start end vcalendar:noArg vevents:noArg";
  }

}

###################################
sub Calendar_Wakeup($$) {

  my ($hash, $removeall) = @_;

  Log3 $hash, 4, "Calendar " . $hash->{NAME} . ": Wakeup";

  my $t= time(); # baseline
  # we could arrive here 1 second before nextWakeTs for unknown reasons
  use constant delta => 5; # avoid waking up again in a few seconds
  if(defined($t) && ($t>= $hash->{".fhem"}{nxtUpdtTs} - delta)) {
    # GetUpdate does CheckTimes and RearmTimer asynchronously
    Calendar_GetUpdate($hash, $t, $removeall);
  } else {
    Calendar_CheckTimes($hash, $t);
    Calendar_RearmTimer($hash, $t);
  }
}

###################################
sub Calendar_RearmTimer($$) {

  my ($hash, $t) = @_;

  #main::Debug "RearmTimer now " . FmtDateTime($t);
  my $nt= $hash->{".fhem"}{nxtUpdtTs};
  #main::Debug "RearmTimer next update " . FmtDateTime($nt);
  # find next event
  my %vevents= %{$hash->{".fhem"}{vevents}};
  foreach my $uid (keys %vevents) {
      my $v= $vevents{$uid};
      foreach my $e (@{$v->{events}}) {
        my $et= $e->nextTime($t);
        # we only consider times in the future to avoid multiple
        # invocations for calendar events with the event time
        $nt= $et if(defined($et) && defined($t) && ($et< $nt) && ($et > $t));
      }
  }

  $hash->{".fhem"}{nextWakeTs}= $nt;
  $hash->{".fhem"}{nextWake}= FmtDateTime($nt);
  #main::Debug "RearmTimer for " . $hash->{".fhem"}{nextWake};
  readingsSingleUpdate($hash, "nextWakeup", $hash->{".fhem"}{nextWake}, 1);

  if($nt< $t) { $nt= $t+1 }; # sanity check / do not wake-up at or before the same second
  InternalTimer($nt, "Calendar_Wakeup", $hash, 0) ;

}

sub Calendar_DisarmTimer($) {

    my ($hash)= @_;
    RemoveInternalTimer($hash);
}
#

###################################
sub Calendar_GetSecondsFromMidnight(){
  my @time = localtime();
  return (($time[2] * HOURSECONDS) + ($time[1] * MINUTESECONDS) + $time[0]);
}

###################################
sub Calendar_GetSecondsFromTimeSpec($) {

  my ($tspec) = @_;

  # days
  if($tspec =~ m/^([0-9]+)d$/) {
    return ("", $1*86400);
  }

   # seconds
  if($tspec =~ m/^([0-9]+)s?$/) {
    return ("", $1);
  }

  # D:HH:MM:SS
  if($tspec =~ m/^([0-9]+):([0-1][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])$/) {
    return ("", $4+60*($3+60*($2+24*$1)));
  }

  # HH:MM:SS
  if($tspec =~ m/^([0-9]+):([0-5][0-9]):([0-5][0-9])$/) { # HH:MM:SS
    return ("", $3+60*($2+(60*$1)));
  }

  # HH:MM
  if($tspec =~ m/^([0-9]+):([0-5][0-9])$/) {
    return ("", 60*($2+60*$1));
  }

  return ("Wrong time specification $tspec", undef);

}

###################################
# Filters

sub filter_true($$) {
  return 1;
}

sub filter_mode($$) {
    my ($event,$value)= @_;
    my $hit;
    eval { $hit= ($event->getMode() eq $value); };
    return 0 if($@);
    return $hit ? 1 : 0;
}

sub filter_modes($$) {
    my ($event,$regex)= @_;
    my $hit;
    eval { $hit= ($event->getMode() =~ $regex); };
    return 0 if($@);
    return $hit ? 1 : 0;
}

sub filter_uids($$) {
    my ($event,$regex)= @_;
    my $hit;
    eval { $hit= ($event->uid() =~ $regex); };
    return 0 if($@);
    #Debug "filter_uids: " . $event->uid() . "  $regex: $hit";
    return $hit ? 1 : 0;
}

sub filter_field($$$) {
    my ($event,$value,$field)= @_;
    my $hit;
    eval { $hit= ($event->{$field} eq $value); };
    return 0 if($@);
    return $hit ? 1 : 0;
}

sub filter_fields($$$) {
    my ($event,$regex,$field)= @_;
    my $hit;
    eval { $hit= ($event->{$field} =~ $regex); };
    return 0 if($@);
    return $hit ? 1 : 0;
}

sub filter_changed($) {
    my ($event)= @_;
    return $event->modeChanged();
}

sub filter_alarm($) {
    my ($event)= @_;
    return $event->getMode() eq "alarm" ? 1 : 0;
}

sub filter_start($) {
    my ($event)= @_;
    return $event->getMode() eq "start" ? 1 : 0;
}

sub filter_startbefore($$) {
    my ($event, $param)= @_;
    return $event->start() < $param ? 1 : 0;
}

sub filter_end($) {
    my ($event)= @_;
    return $event->getMode() eq "end" ? 1 : 0;
}

sub filter_endafter($$) {
    my ($event, $param)= @_;
    return $event->end() > $param ? 1 : 0;
}

sub filter_notend($) {
    my ($event)= @_;
    #Debug "filter_notend: event " . $event->{summary} . ", mode= " . $event->getMode();
    return $event->getMode() eq "end" ? 0 : 1;
}

sub filter_upcoming($) {
    my ($event)= @_;
    return $event->getMode() eq "upcoming" ? 1 : 0;
}

sub filter_uid($$) {
    my ($event, $param)= @_;
    return $event->uid() eq "$param" ? 1 : 0;
}

sub filter_reading($$) {
    my ($event, $param)= @_;
    my @uids= @{$param};
    #foreach my $u (@uids) { #main::Debug "UID $u"; }
    my $uid= $event->uid();
    #main::Debug "SUCHE $uid";
    #main::Debug "GREP: " . grep(/^$uid$/, @uids);
    return grep(/^$uid$/, @uids);
}




###################################
sub Calendar_GetEvents($$@) {

    my ($hash, $t, @filters)= @_;
    my $name= $hash->{NAME};
    my @result= ();

    # time window
    my ($error, $t1, $t2)= (undef, undef, undef);
    my $hideOlderThan= AttrVal($name, "hideOlderThan", undef);
    my $hideLaterThan= AttrVal($name, "hideLaterThan", undef);

    # start of time window
    if(defined($hideOlderThan)) {
        ($error, $t1)= Calendar_GetSecondsFromTimeSpec($hideOlderThan);
        if($error) {
            Log3 $hash, 2, "$name: attribute hideOlderThan: $error";
        } else {
            $t1= $t- $t1;
        }
    }

    # end of time window
    if(defined($hideLaterThan)) {
        ($error, $t2)= Calendar_GetSecondsFromTimeSpec($hideLaterThan);
        if($error) {
            Log3 $hash, 2, "$name: attribute hideLaterThan: $error";
        } else {
            $t2= $t+ $t2;
        }
    }

    # get and filter events
    my %vevents= %{$hash->{".fhem"}{vevents}};
    foreach my $id (keys %vevents) {
        my $v= $vevents{$id};
        my @events= @{$v->{events}};
        foreach my $event (@events) {
            if(@filters) {
              my $match= 0;
              for my $h (@filters) {
                my $filter= \%$h;
                my $filterref= $filter->{ref};
                my $param = $filter->{param};
                my $field = $filter->{field};
                last unless(&$filterref($event, $param, $field));
                $match++;
              }
              #Debug "Filter $filterref, Parameter $param, Match $match";
              next unless $match==@filters;
            }
            if(defined($t1)) { next if(defined($event->end()) && $event->end() < $t1); }
            if(defined($t2)) { next if(defined($event->start()) && $event->start() > $t2); }
            push @result, $event;
        }
    }
    return sort { $a->start() <=> $b->start() } @result;

}

###################################
sub Calendar_GetUpdate($$$;$) {

  my ($hash, $t, $removeall, $force) = @_;
  my $name= $hash->{NAME};

  $hash->{".fhem"}{lstUpdtTs}= $t;
  $hash->{".fhem"}{lastUpdate}= FmtDateTime($t);

  my $nut= $t+ $hash->{".fhem"}{interval};
  $hash->{".fhem"}{nxtUpdtTs}= $nut;
  $hash->{".fhem"}{nextUpdate}= FmtDateTime($nut);

  #main::Debug "Getting update now: " . $hash->{".fhem"}{lastUpdate};
  #main::Debug "Next Update is at : " . $hash->{".fhem"}{nextUpdate};

  # If update is disable, shortcut to time checking and rearming timer.
  # Why is this here and not in Calendar_Wakeup? Because the next update time needs to be set
  if(!$force && (AttrVal($hash->{NAME},"update","") eq "none")) {
    Calendar_CheckTimes($hash, $t);
    Calendar_RearmTimer($hash, $t);
    return;
  }

  my $url = $hash->{".fhem"}{url};
  unless ($hash->{".fhem"}{noWildcards} == 1 || AttrVal($name,'quirks','') =~ /noWildcards/) {
    my @ti = localtime;
    $url   = ResolveDateWildcards($hash->{".fhem"}{url}, @ti);
  }

  if($url ne $hash->{".fhem"}{lasturl}) {
    $hash->{".fhem"}{lasturl} = $url;
  } elsif (!$force && (AttrVal($hash->{NAME},"update","") eq "onUrlChanged")) {
    Log3 $hash,4,"Calendar $name: unchanged url and update set to unUrlChanged = nothing to do.";
    Calendar_CheckTimes($hash, $t);
    Calendar_RearmTimer($hash, $t);
    return;
  }

  Log3 $hash, 4, "Calendar $name: Updating...";
  my $type = $hash->{".fhem"}{type};

  my $errmsg= "";
  my $ics;

  if($type eq "url") {

    my $SSLVerify= AttrVal($name, "SSLVerify", undef);
    my $SSLArgs= { };
    if(defined($SSLVerify)) {
      eval "use IO::Socket::SSL";
      if($@) {
        Log3 $hash, 2, $@;
      } else {
        my $SSLVerifyMode= eval("$SSLVerify ? SSL_VERIFY_PEER : SSL_VERIFY_NONE");
        Log3 $hash, 5, "SSL verify mode set to $SSLVerifyMode";
        $SSLArgs= { SSL_verify_mode => $SSLVerifyMode };
      }
    }

    my $timeout= AttrVal($name, "timeout", 30);
    HttpUtils_NonblockingGet({
      url => $url,
      hideurl => 1,
      noshutdown => 1,
      hash => $hash,
      timeout => $timeout,
      type => 'caldata',
      removeall => $removeall,
      sslargs => $SSLArgs,
      t => $t,
      callback => \&Calendar_ProcessUpdate,
    });
    Log3 $hash, 4, "Calendar $name: Getting data from URL <hidden>"; # $url

  } elsif($type eq "file") {

    Log3 $hash, 4, "Calendar $name: Getting data from file $url";
    if(open(ICSFILE, $url)) {
      while(<ICSFILE>) {
        $ics .= $_;
      }
      close(ICSFILE);

      my $paramhash;
      $paramhash->{hash} = $hash;
      $paramhash->{removeall} = $removeall;
      $paramhash->{t} = $t;
      $paramhash->{type} = 'caldata';
      Calendar_ProcessUpdate($paramhash, '', $ics);
      return undef;

    } else {
      Log3 $hash, 1, "Calendar $name: Could not open file $url";
      readingsSingleUpdate($hash, "state", "error (could not open file)", 1);
      return 0;
    }
  } else {
    # this case never happens by virtue of _Define, so just
    die "Software Error";
  }

}


###################################
sub Calendar_ProcessUpdate($$$) {

  my ($param, $errmsg, $ics) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $removeall = $param->{removeall};
  my $t= $param->{t};
  my $type= $hash->{".fhem"}{type};

  if(exists($hash->{".fhem"}{subprocess})) {
      Log3 $hash, 2, "Calendar $name: update in progress, process aborted.";
      return 0;
  }

  # not for the developer:
  # we must be sure that code that starts here ends with Calendar_CheckAndRearm()
  # no matter what branch is taken in the following

  delete($hash->{".fhem"}{iCalendar});

  my $httpresponsecode= $param->{code};

  if($errmsg) {
    Log3 $name, 1, "Calendar $name: retrieval failed with error message $errmsg";
    readingsSingleUpdate($hash, "state", "error ($errmsg)", 1);
  } else {
    if($type eq "url") {
      if($httpresponsecode != 200) {
        $errmsg= "retrieval failed with HTTP response code $httpresponsecode";
        Log3 $name, 1, "Calendar $name: $errmsg";
        readingsSingleUpdate($hash, "state", "error ($errmsg)", 1);
        Log3 $name, 5, "Calendar $name: HTTP response header:\n" .
          $param->{httpheader};
      } else {
        Log3 $name, 5, "Calendar $name: HTTP response code $httpresponsecode";
        readingsSingleUpdate($hash, "state", "retrieved", 1);
      }
    } elsif($type eq "file") {
      Log3 $name, 5, "Calendar $name: file retrieval successful";
      readingsSingleUpdate($hash, "state", "retrieved", 1);
    } else {
      # this case never happens by virtue of _Define, so just
      die "Software Error";
    }
  }

  $hash->{".fhem"}{t}= $t;
  if($errmsg or !defined($ics) or ("$ics" eq "") ) {
    Log3 $hash, 1, "Calendar $name: retrieved no or empty data";
    readingsSingleUpdate($hash, "state", "error (no or empty data)", 1);
    $hash->{".fhem"}{t}= $t;
    Calendar_CheckAndRearm($hash);
  } else {
    $hash->{".fhem"}{iCalendar}= $ics; # the plain text iCalendar
    $hash->{".fhem"}{removeall}= $removeall;
    if( $^O =~ m/Win/ || AttrVal($name, "synchronousUpdate", 0) == 1 ) {
      Calendar_SynchronousUpdateCalendar($hash);
    } else {
      Calendar_AsynchronousUpdateCalendar($hash);
    }
  }

}

sub Calendar_Cleanup($) {
  my ($hash)= @_;
  delete($hash->{".fhem"}{t});
  delete($hash->{".fhem"}{removeall});
  delete($hash->{".fhem"}{serialized});
  delete($hash->{".fhem"}{subprocess});

  my $name= $hash->{NAME};
  delete($hash->{".fhem"}{iCalendar}) if(AttrVal($name,"removevcalendar",0));
  Log3 $hash, 4, "Calendar $name: process ended.";
}


sub Calendar_CheckAndRearm($) {

  my ($hash)= @_;
  my $t= $hash->{".fhem"}{t};
  Calendar_CheckTimes($hash, $t);
  Calendar_RearmTimer($hash, $t);
}

sub Calendar_SynchronousUpdateCalendar($) {

  my ($hash) = @_;
  my $name= $hash->{NAME};
  Log3 $hash, 4, "Calendar $name: parsing data synchronously";
  my $ical= Calendar_ParseICS($hash->{".fhem"}{iCalendar});
  Calendar_UpdateCalendar($hash, $ical);
  Calendar_CheckAndRearm($hash);
  Calendar_Cleanup($hash);
}

use constant POLLINTERVAL => 1;

sub Calendar_AsynchronousUpdateCalendar($) {

  require "SubProcess.pm";

  my ($hash) = @_;
  my $name= $hash->{NAME};

  my $subprocess= SubProcess->new({ onRun => \&Calendar_OnRun });
  $subprocess->{ics}= $hash->{".fhem"}{iCalendar};
  my $pid= $subprocess->run();

  if(!defined($pid)) {
    Log3 $hash, 1, "Calendar $name: Cannot parse asynchronously";
    Calendar_CheckAndRearm($hash);
    Calendar_Cleanup($hash);
    return undef;
  }

  Log3 $hash, 4, "Calendar $name: parsing data asynchronously (PID= $pid)";
  $hash->{".fhem"}{subprocess}= $subprocess;
  $hash->{".fhem"}{serialized}= "";
  InternalTimer(gettimeofday()+POLLINTERVAL, "Calendar_PollChild", $hash, 0);

  # go and do your thing while the timer polls and waits for the child to terminate
  Log3 $hash, 5, "Calendar $name: control passed back to main loop.";

}

sub Calendar_OnRun() {

  # This routine runs in a process separate from the main process.
  my $subprocess= shift;
  my $ical= Calendar_ParseICS($subprocess->{ics});
  my $serialized= freeze $ical;
  $subprocess->writeToParent($serialized);
}



sub Calendar_PollChild($) {

  my ($hash)= @_;
  my $name= $hash->{NAME};
  my $subprocess= $hash->{".fhem"}{subprocess};
  my $data= $subprocess->readFromChild();
  if(!defined($data)) {
    Log3 $name, 4, "Calendar $name: still waiting (". $subprocess->{lasterror} .").";
    InternalTimer(gettimeofday()+POLLINTERVAL, "Calendar_PollChild", $hash, 0);
    return;
  } else {
    Log3 $name, 4, "Calendar $name: got result from asynchronous parsing.";
    $subprocess->wait();
    Log3 $name, 4, "Calendar $name: asynchronous parsing finished.";
    my $ical= thaw($data);
    Calendar_UpdateCalendar($hash, $ical);
    Calendar_CheckAndRearm($hash);
    Calendar_Cleanup($hash);
  }
}


sub Calendar_ParseICS($) {

  #main::Debug "Calendar: parsing data";
  my ($ics)= @_;
  my ($error, $state)= (undef, "");

  # we parse the calendar into a recursive ICal::Entry structure
  my $ical= ICal::Entry->new("root");
  $ical->parse($ics);

  #main::Debug "*** Result:";
  #main::Debug $ical->asString();

  my $numentries= scalar @{$ical->{entries}};
  if($numentries<= 0) {
    eval { require Compress::Zlib; };
    if($@) {
      $error= "data not in ICal format; maybe gzip data, but cannot load Compress::Zlib";
    }
    else {
      $ics = Compress::Zlib::memGunzip($ics);
      $ical->parse($ics);
      $numentries= scalar @{$ical->{entries}};
      if($numentries<= 0) {
        $error= "data not in ICal format; even not gzip data";
      } else {
        $state= "parsed (gzip data)";
      }
    }
  } else {
    $state= "parsed";
  };

  $ical->{error}= $error;
  $ical->{state}= $state;
  return $ical;
}

###################################
sub Calendar_UpdateCalendar($$) {

  my ($hash, $ical)= @_;

  my $name= $hash->{NAME};

  my @quirks= split(",", AttrVal($name, "quirks", ""));
  my $nodtstamp= main::contains_string "ignoreDtStamp", @quirks;

  # *******************************
  # *** Step 1 Digest Parser Result
  # *******************************

  my $error= $ical->{error};
  my $state= $ical->{state};

  if(defined($error)) {
    Log3 $hash, 2, "Calendar $name: error ($error)";
    readingsSingleUpdate($hash, "state", "error ($error)", 1);
    return 0;
  } else {
    readingsSingleUpdate($hash, "state", $state, 1);
  }
  my $t= $hash->{".fhem"}{t};
  my $removeall= $hash->{".fhem"}{removeall};

  if(!defined($ical->{entries})) {
    Log3 $hash, 1, "Calendar $name: no ical entries";
    readingsSingleUpdate($hash, "state", "error (no ical entries)", 1);
    return 0;
  }
  my @entries= @{$ical->{entries}};
  my $root= @{$ical->{entries}}[0];
  my $calname= "?";
  if($root->{type} ne "VCALENDAR") {
    Log3 $hash, 1, "Calendar $name: root element is not VCALENDAR";
    readingsSingleUpdate($hash, "state", "error (root element is not VCALENDAR)", 1);
    return 0;
  } else {
    $calname= $root->value("X-WR-CALNAME");
  }

  # *********************
  # *** Step 2 Merging
  # *********************

  Log3 $hash, 4, "Calendar $name: merging data";
  #main::Debug "Calendar $name: merging data";

  # this the hash of VEVENTs that have been created on the previous update
  my %vevents;
  %vevents= %{$hash->{".fhem"}{vevents}} if(!$removeall);

  # the keys to the hash are numbers taken from a sequence
  my $lastid= $hash->{".fhem"}{lastid};

  #
  # 1, 2, 4
  #

  # we first discard all VEVENTs that have been tagged as deleted in the previous run
  # and untag the rest
  foreach my $key (keys %vevents) {
    #main::Debug "Preparing id $key...";
    if($vevents{$key}->isObsolete() ) {
        delete($vevents{$key});
    } else {
        $vevents{$key}->setState("deleted"); # will be changed if record is touched in the next step
        $vevents{$key}->clearCounterpart();
        $vevents{$key}->clearReferences();
    }
  }

  #
  # 3
  #

  # we now run through the list of freshly retrieved VEVENTs and merge them into
  # the hash
  my ($n, $nknown, $nmodified, $nnew, $nchanged)= (0,0,0,0,0,0);

  # this code is O(n^2) and stalls FHEM for large numbers of VEVENTs
  # to speed up the code we first build a reverse hash (UID,RECURRENCE-ID) -> id
  sub kf($) { my ($v)= @_; return $v->value("UID").$v->valueOrDefault("RECURRENCE-ID","") }

  my %lookup;
  foreach my $id (keys %vevents) {
        my $k= kf($vevents{$id});
        Log3 $hash, 2, "Calendar $name: Duplicate VEVENT" if(defined($lookup{$k}));
        $lookup{$k}= $id;
        #main::Debug "Adding event $id with key $k to lookup hash.";
  }

    # start of time window for cutoff
    my $cutoffLowerBound= 0;
    my $cutoffOlderThan = AttrVal($name, "cutoffOlderThan", undef);
    if(defined($cutoffOlderThan)) {
        my $cutoffT= 0;
        ($error, $cutoffT)= Calendar_GetSecondsFromTimeSpec($cutoffOlderThan);
        if($error) {
          Log3 $hash, 2, "$name: attribute cutoffOlderThan: $error";
        } else {
          $cutoffLowerBound= $t- $cutoffT;
        }
    }
    # end of time window for cutoff
    my $cutoffUpperBound= 0;
    my $cutoffLaterThan = AttrVal($name, "cutoffLaterThan", undef);
    if(defined($cutoffLaterThan)) {
        my $cutoffT= 0;
        ($error, $cutoffT)= Calendar_GetSecondsFromTimeSpec($cutoffLaterThan);
        if($error) {
          Log3 $hash, 2, "$name: attribute cutoffLaterThan: $error";
        } else {
          $cutoffUpperBound= $t+ $cutoffT;
        }
    }

  foreach my $v (grep { $_->{type} eq "VEVENT" } @{$root->{entries}}) {

        # totally skip old calendar entries
        if($cutoffLowerBound) {
          if(!$v->isRecurring()) {
            # non recurring event
            next if(
              $v->hasKey("DTEND") &&
              $v->before($v->value("DTEND"), $cutoffLowerBound)
              );
          } else {
            # recurring event, inspect
            my $rrule= $v->value("RRULE");
            my @rrparts= split(";", $rrule);
            my %r= map { split("=", $_); } @rrparts;
            if(exists($r{"UNTIL"})) {
              next if($v->before($r{"UNTIL"},$cutoffLowerBound))
            }
          }
        }
        # totally skip distant future calendar entries
        if($cutoffUpperBound) {
          next if(
            $v->hasKey("DTSTART") &&
            $v->after($v->value("DTSTART"), $cutoffUpperBound)
            );
        }

	      #main::Debug "Merging " . $v->asString();
        my $found= 0;
        my $added= 0; # flag to prevent multiple additions
        $n++;
        # some braindead calendars provide no UID - add one:
        $v->addproperty(sprintf("UID:synthetic-%06d", $v->{ln}))
            unless($v->hasKey("UID") or !defined($v->{ln}));
        # look for related records in the old record set
        my $k= kf($v);
        #main::Debug "Looking for event with key $k";
        my $id= $lookup{$k};
        if(defined($id)) {
            my $v0= $vevents{$id};
            #main::Debug "Found $id";

            #
            # same UID and RECURRENCE-ID
            #
            $found++;
            if($v0->sameValue($v, "SEQUENCE")) {
                #
                # and same SEQUENCE
                #
                if($v0->sameValue($v, "LAST-MODIFIED") &&
                   ($nodtstamp || $v0->sameValue($v, "DTSTAMP"))) {
                    #
                    # is not modified
                    #
                    # we only keep the record from the old record set
                    $v0->setState("known");
                    $nknown++;
                } else {
                    #
                    # is modified
                    #
                    # we keep both records
                    next if($added);
                    $added++;
                    $vevents{++$lastid}= $v;
                    $v->setState("modified-new");
                    $v->setCounterpart($id);
                    $v0->setState("modified-old");
                    $v0->setCounterpart($lastid);
                    $nmodified++;
                }
            } else {
                #
                # and different SEQUENCE
                #
                # we keep both records
                next if($added);
                $added++;
                $vevents{++$lastid}= $v;
                $v->setState("changed-new");
                $v->setCounterpart($id);
                $v0->setState("changed-old");
                $v0->setCounterpart($lastid);
                $nchanged++;
            }
        }

        if(!$found) {
            $v->setState("new");
            $vevents{++$lastid}= $v;
            $added++;
            $nnew++;
        }
  }

  #
  # Cross-referencing series
  #
  # this code is O(n^2) and stalls FHEM for large numbers of VEVENTs
  # to speed up the code we build a hash of a hash UID => {id => VEVENT}
  %lookup= ();
  foreach my $id (keys %vevents) {
    my $v= $vevents{$id};
    $lookup{$v->value("UID")}{$id}= $v unless($v->isObsolete);
  }
  for my $idref (values %lookup)  {
    my %vs= %{$idref};
    foreach my $v (values %vs) {
        foreach my $id (keys %vs) {
            push @{$v->references()}, $id unless($vs{$id} eq $v);
        }
    }
  }

#   foreach my $id (keys %vevents) {
#         my $v= $vevents{$id};
#         next if($v->isObsolete());
#         foreach my $id0 (keys %vevents) {
#             next if($id==$id0);
#             my $v0= $vevents{$id0};
#             next if($v0->isObsolete());
#             push @{$v0->references()}, $id if($v->sameValue($v0, "UID"));
#         }
#   }


  Log3 $hash, 4, "Calendar $name: $n records processed, $nnew new, ".
    "$nknown known, $nmodified modified, $nchanged changed.";

  # save the VEVENTs hash and lastid
  $hash->{".fhem"}{vevents}= \%vevents;
  $hash->{".fhem"}{lastid}= $lastid;

  # *********************
  # *** Step 3 Events
  # *********************


  #
  # Recreating the events
  #
  Log3 $hash, 4, "Calendar $name: creating calendar events";
  #main::Debug "Calendar $name: creating calendar events";

  my $ignoreCancelled= AttrVal($name, "ignoreCancelled", 0);
  my $clearedCount= 0;
  my $createdCount= 0;
  foreach my $id (keys %vevents) {
        my $v= $vevents{$id};
        if($v->isObsolete() or ($ignoreCancelled and $v->isCancelled())) {
            $clearedCount++;
            $v->clearEvents();
            next;
        }
        my $onCreateEvent= AttrVal($name, "onCreateEvent", undef);
        if($v->hasChanged() or !$v->numEvents()) {
            $createdCount++;
            #main::Debug "createEvents";
            $v->createEvents($name, $t, $onCreateEvent,
              $cutoffLowerBound, $cutoffUpperBound, %vevents);
        }
  }
  Log3 $hash, 4, "Calendar $name: events for $clearedCount records cleared, events for $createdCount records created.";


  #main::Debug "*** Result:";
  #main::Debug $ical->asString();


  # *********************
  # *** Step 4 Readings
  # *********************

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "calname", $calname);
  readingsBulkUpdate($hash, "lastUpdate", $hash->{".fhem"}{lastUpdate});
  readingsBulkUpdate($hash, "nextUpdate", $hash->{".fhem"}{nextUpdate});
  readingsEndUpdate($hash, 1); # DoTrigger, because sub is called by a timer instead of dispatch




  return 1;
}


###################################
sub Calendar_CheckTimes($$) {

    my ($hash, $t) = @_;
    my $name= $hash->{NAME};

    Log3 $hash, 4, "Calendar $name: Checking times...";

    # delete obsolete readings
    Calendar_deleteModeReadings($hash) unless AttrVal($name, "hasModeReadings", 0);

    #
    # determine the uids of all events and their most interesting mode
    #
    my %priority= (
        "none" => 0,
        "end" => 1,
        "upcoming" => 2,
        "alarm" => 3,
        "start" => 4,
    );
    my %mim;     # most interesting mode per id
    my %changed;  # changed per id
    my %vevents= %{$hash->{".fhem"}{vevents}};
    foreach my $uid (keys %vevents) {
        my $v= $vevents{$uid};
        foreach my $e (@{$v->{events}}) {
            my $uid= $e->uid();
            my $mode= defined($mim{$uid}) ? $mim{$uid} : "none";
            if($e->isEnded($t)) {
                $e->setMode("end");
            } elsif($e->isUpcoming($t)) {
                $e->setMode("upcoming");
            } elsif($e->isStarted($t)) {
                $e->setMode("start");
            } elsif($e->isAlarmed($t)) {
                $e->setMode("alarm");
            }
            if($priority{$e->getMode()} > $priority{$mode}) {
                $mim{$uid}= $e->getMode();
            }
            $changed{$uid}= 0 unless(defined($changed{$uid}));
            # create the FHEM event
            if($e->modeChanged()) {
                $changed{$uid}= 1;
                addEvent($hash, "changed: $uid " . $e->getMode());
                addEvent($hash, $e->getMode() . ": $uid ");
            }
        }
    }

    #
    # determine the uids of events in certain modes
    #
    my @changed;
    my @upcoming;
    my @start;
    my @started;
    my @alarm;
    my @alarmed;
    my @end;
    my @ended;
    foreach my $uid (keys %mim) {
        push @changed, $uid if($changed{$uid});
        push @upcoming, $uid if($mim{$uid} eq "upcoming");
        if($mim{$uid} eq "alarm") {
            push @alarm, $uid;
            push @alarmed, $uid if($changed{$uid});
        }
        if($mim{$uid} eq "start") {
            push @start, $uid;
            push @started, $uid if($changed{$uid});
        }
        if($mim{$uid} eq "end") {
            push @end, $uid;
            push @ended, $uid if($changed{$uid});
        }
    }


    #sub uniq { my %uids; return grep {!$uids{$_->uid()}++} @_; }


    #@allevents= sort { $a->start() <=> $b->start() } uniq(@allevents);


    #foreach my $event (@allevents) {
    #    #main::Debug $event->asFull();
    #}


    sub es(@) {
        my (@events)= @_;
        return join(";", @events);
    }

    sub rbu($$$) {
        my ($hash, $reading, $value)= @_;
        if(!defined($hash->{READINGS}{$reading}) or
           ($hash->{READINGS}{$reading}{VAL} ne $value)) {
            readingsBulkUpdate($hash, $reading, $value);
        }
    }

 
    # clears all events in CHANGED, thus must be called first
    readingsBeginUpdate($hash);
    # we update the readings
    if(AttrVal($name, "hasModeReadings", 0)) {
        Log3 $hash, 5, "Calendar $name: Updating obsolete mode readings...";
        rbu($hash, "modeUpcoming", es(@upcoming));
        rbu($hash, "modeAlarm", es(@alarm));
        rbu($hash, "modeAlarmed", es(@alarmed));
        rbu($hash, "modeAlarmOrStart", es(@alarm,@start));
        rbu($hash, "modeChanged", es(@changed));
        rbu($hash, "modeStart", es(@start));
        rbu($hash, "modeStarted", es(@started));
        rbu($hash, "modeEnd", es(@end));
        rbu($hash, "modeEnded", es(@ended));
    } 
    readingsBulkUpdate($hash, "state", "triggered");
    # DoTrigger, because sub is called by a timer instead of dispatch
    readingsEndUpdate($hash, 1);

}


#####################################

sub CalendarAsHtml($;$) {

  my ($d,$o) = @_;
  $d = "<none>" if(!$d);
  return "$d is not a Calendar instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "Calendar");

  my $l= Calendar_Get($defs{$d}, split("[ \t]+", "- text $o"));
  my @lines= split("\n", $l);

  my $ret = '<table class="calendar">';

  foreach my $line (@lines) {
    my @fields= split(" ", $line, 3);
    $ret.= sprintf("<tr><td>%s</td><td>%s</td><td>%s</td></tr>", @fields);
  }
  $ret .= '</table>';

  return $ret;
}

sub CalendarEventsAsHtml($;$) {

  my ($d,$parameters) = @_;
  $d = "<none>" if(!$d);
  return "$d is not a Calendar instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "Calendar");

  my $l= Calendar_Get($defs{$d}, split("[ \t]+", "- events $parameters"));
  my @lines= split("\n", $l);

  my $ret = '<table class="calendar">';

  foreach my $line (@lines) {
    my @fields= split(" ", $line, 3);
    $ret.= sprintf("<tr><td>%s</td><td>%s</td><td>%s</td></tr>", @fields);
  }
  $ret .= '</table>';

  return $ret;
}

#####################################


1;

=pod
=item device
=item summary handles calendar events from iCal file or URL
=item summary_DE handhabt Kalendertermine aus iCal-Dateien und URLs
=begin html

<a name="Calendar"></a>
<h3>Calendar</h3>
<ul>
  <br>

  <a name="Calendardefine"></a>
  <b>Define</b><br><br>
  <ul>
    <code>define &lt;name&gt; Calendar ical url &lt;URL&gt; [&lt;interval&gt;]</code><br>
    <code>define &lt;name&gt; Calendar ical file &lt;FILENAME&gt; [&lt;interval&gt;]</code><br>
    <br>
    Defines a calendar device.<br><br>

    A calendar device periodically gathers calendar events from the source calendar at the given URL or from a file.
    The file must be in ICal format.<br><br>

    If the URL
    starts with <code>https://</code>, the perl module IO::Socket::SSL must be installed
    (use <code>cpan -i IO::Socket::SSL</code>).<br>
    <br/>
    <code>&lt;URL&gt;</code> may contain %-wildcards of the
    POSIX strftime function of the underlying OS (see your strftime manual).
    Common used wildcards are:
    <ul>
    <li><code>%d</code> day of month (01..31)</li>
    <li><code>%m</code> month (01..12)</li>
    <li><code>%Y</code> year (1970...)</li>
    <li><code>%w</code> day of week (0..6);  0 represents Sunday</li>
    <li><code>%j</code> day of year (001..366)</li>
    <li><code>%U</code> week number of year with Sunday as first day of week (00..53)</li>
    <li><code>%W</code> week number of year with Monday as first day of week (00..53)</li>
    </ul>
    <br/>
    - Wildcards in url will be evaluated on every calendar update.<br/>
    - The evaluation of wildcards maybe disabled by adding literal 'noWildcards' to attribute 'quirks'.
    This may be useful in url containing % without marking a wildcard.<br/>
    <br/>
    Note for users of Google Calendar:
    <ul>
    <li>Wildcards must not be used in Google Calendar url!</li>
    <li>You can literally use the private ICal URL from your Google Calendar.</li>
    <li>If your Google Calendar URL starts with <code>https://</code> and the perl module IO::Socket::SSL is
    not installed on your system, you can replace it by <code>http://</code> if and only if there is
    no redirection to the <code>https://</code> URL. Check with your browser first if unsure.</li>
    </ul>
    <br/>
    Note for users of Netxtcloud Calendar: you can use an URL of the form
    <code>https://admin:admin@demo.nextcloud.com/wid0ohgh/remote.php/dav/calendars/admin/personal/?export</code>.
    <br><br>

    The optional parameter <code>interval</code> is the time between subsequent updates
    in seconds. It defaults to 3600 (1 hour).<br>
    An interval = 0 will not be allowed and replaced by 3600 automatically. A corresponding log entry will be created.<br/><br>

    Examples:
    <pre>
      define MyCalendar Calendar ical url https://www.google.com&shy;/calendar/ical/john.doe%40example.com&shy;/private-foo4711/basic.ics
      define YourCalendar Calendar ical url http://www.google.com&shy;/calendar/ical/jane.doe%40example.com&shy;/private-bar0815/basic.ics 86400
      define SomeCalendar Calendar ical file /home/johndoe/calendar.ics
    </pre>

    Note on cutoff of event creation:<ul><li>
    
      Events that are more than 400 days in the past or in the future from their 
      time of creation are omitted. This time window can be further reduced by 
      the <code>cutoffOlderThan</code> and <code>cutoffLaterThan</code> attributes.

      This would have the following consequence: as long as the calendar is not 
      re-initialized (<code>set ... reload</code> or restart of FHEM) and the VEVENT record is 
      not modified, events beyond the horizon never get created.

      Thus, a forced reload should be scheduled every now and then.</li></ul>
      
  </ul>
  <br>

  <a name="Calendarset"></a>
  <b>Set </b><br><br>
  <ul>
    <li><code>set &lt;name&gt; update</code><br>
    Forces the retrieval of the calendar from the URL. The next automatic retrieval is scheduled to occur <code>interval</code> seconds later.<br><br></li>

    <li><code>set &lt;name&gt; reload</code><br>
    Same as <code>update</code> but all calendar events are removed first.<br><br></li>

  </ul>
  <br>


  <a name="Calendarget"></a>
  <b>Get</b><br><br>
  <ul>

    <li><code>get &lt;name&gt; update</code><br>
    Same as  <code>set &lt;name&gt; update</code><br><br></li>

    <li><code>get &lt;name&gt; reload</code><br>
    Same as  <code>set &lt;name&gt; update</code><br><br></li>


    <li><code>get &lt;name&gt; events [format:&lt;formatSpec&gt;] [timeFormat:&lt;timeFormatSpec&gt;] [filter:&lt;filterSpecs&gt;]
    [series:next[=&lt;max&gt;]] [limit:&lt;limitSpecs&gt;]
    [include:&lt;names&gt;]
    [returnType:&lt;returnTypeSpec&gt;]
    </code><br><br>
    The swiss army knife for displaying calendar events.
    Returns, line by line, information on the calendar events in the calendar &lt;name&gt;
    according to formatting and filtering rules.
    You can give none, one or several of the <code>format</code>,
    <code>timeFormat</code>, <code>filter</code>, <code>series</code> and <code>limit</code>
    parameters and it makes even sense to give the <code>filter</code>
    parameter several times.
    <br><br>


    The <u><code>format</code></u> parameter determines the overall formatting of the calendar event.
    The following format specifications are available:<br><br>

    <table>
    <tr><th align="left">&lt;formatSpec&gt;</th><th align="left">content</th></tr>
    <tr><td><code>default</code></td><td>the default format (see below)</td></tr>
    <tr><td><code>full</code></td><td>same as <code>custom="$U $M $A $T1-$T2 $S $CA $L"</code></td></tr>
    <tr><td><code>text</code></td><td>same as <code>custom="$T1 $S"</code></td></tr>
    <tr><td><code>human</code></td><td>same as <code>custom={ human($t1,$t2,$S) }</code> -  <code>human()</code> is a built-in function that presents the event in a terse human-readable format</td></tr>
    <tr><td><code>custom="&lt;formatString&gt;"</code></td><td> a custom format (see below)</td></tr>
    <tr><td><code>custom="{ &lt;perl-code&gt; }"</code></td><td>a custom format (see below)</td></tr>
    </table><br>
    Single quotes (<code>'</code>) can be used instead of double quotes (<code>"</code>) in the
    custom format.<br><br>
    You can use the following variables in the <code>&lt;formatString&gt;</code> and in
    the <code>&lt;perl-code&gt;</code>:<br><br>

    <table>
    <tr><th align="left">variable</th><th align="left">meaning</th></tr>
    <tr><td><code>$t1</code></td><td>the start time in seconds since the epoch</td></tr>
    <tr><td><code>$T1</code></td><td>the start time according to the time format</td></tr>
    <tr><td><code>$t2</code></td><td>the end time in seconds since the epoch</td></tr>
    <tr><td><code>$T2</code></td><td>the end time according to the time format</td></tr>
    <tr><td><code>$a</code></td><td>the alarm time in seconds since the epoch</td></tr>
    <tr><td><code>$A</code></td><td>the alarm time according to the time format</td></tr>
    <tr><td><code>$d</code></td><td>the duration in seconds</td></tr>
    <tr><td><code>$D</code></td><td>the duration in human-readable form</td></tr>
    <tr><td><code>$S</code></td><td>the summary</td></tr>
    <tr><td><code>$L</code></td><td>the location</td></tr>
    <tr><td><code>$CA</code></td><td>the categories</td></tr>
    <tr><td><code>$CL</code></td><td>the classification</td></tr>
    <tr><td><code>$DS</code></td><td>the description</td></tr>
    <tr><td><code>$U</code></td><td>the UID</td></tr>
    <tr><td><code>$M</code></td><td>the mode</td></tr>
    </table><br>
    \, (masked comma) in summary, location and description is replaced by a comma but \n
    (indicates newline) is untouched.<br><br>

    If the <code>format</code> parameter is omitted, the custom format string
    from the <code>defaultFormat</code> attribute is used. If this attribute
    is not set, <code>"$T1 $D $S"</code> is used as default custom format string.
    The last occurance wins if the <code>format</code>
    parameter is given several times.<br><br>

    Examples:<br>
    <code>get MyCalendar events format:full</code><br>
    <code>get MyCalendar events format:custom="$T1-$T2 $S \@ $L"</code><br>
    <code>get MyCalendar events format:custom={ sprintf("%20s %8s", $S, $D) }</code><br><br>

    The <u><code>timeFormat</code></u> parameter determines the formatting of
    start, end and alarm times.<br><br>

    You use the POSIX conversion specifications in the <code>&lt;timeFormatSpec&gt;</code>.
    The web page <a href="http://strftime.net">strftime.net</a> has a nice builder
    for <code>&lt;timeFormatSpec&gt;</code>.<br><br>

    If the <code>timeFormat</code> parameter is omitted, the time format specification
    from the <code>defaultTimeFormat</code> attribute is used. If this attribute
    is not set, <code>"%d.%m.%Y %H:%M"</code> is used as default time format
    specification.
    Single quotes (<code>'</code>) or double quotes (<code>"</code>) can be
    used to enclose the format specification.<br><br>

    The last occurance wins if the parameter is given several times.<br><br>

    Example:<br>
    <code>get MyCalendar events timeFormat:"%e-%b-%Y" format:full</code><br><br>

    The <u><code>filter</code></u> parameter restricts the calendar
    events displayed to a subset. <code>&lt;filterSpecs&gt;</code> is a comma-separated
    list of <code>&lt;filterSpec&gt;</code> specifications. All filters must apply for a
    calendar event to be displayed. The parameter is cumulative: all separate
    occurances of the parameter add to the list of filters.<br><br>

    <table>
    <tr><th align="left"><code>&lt;filterSpec&gt;</code></th><th align="left">description</th></tr>
    <tr><td><code>uid=="&lt;uid&gt;"</code></td><td>UID is <code>&lt;uid&gt;</code><br>
      same as <code>field(uid)=="&lt;uid&gt;"</code></td></tr>
    <tr><td><code>uid=~"&lt;regex&gt;"</code></td><td>UID matches regular expression <code>&lt;regex&gt;</code><br>
      same as <code>field(uid)=~"&lt;regex&gt;"</code></td></tr>
    <tr><td><code>mode=="&lt;mode&gt;"</code></td><td>mode is <code>&lt;mode&gt;</code><br>
      same as <code>field(mode)=="&lt;mode&gt;"</code></td></tr>
    <tr><td><code>mode=~"&lt;regex&gt;"</code></td><td>mode matches regular expression <code>&lt;regex&gt;</code><br>
      same as <code>field(mode)=~"&lt;regex&gt;"</code></td></tr>
    <tr><td><code>field(&lt;field&gt;)=="&lt;value&gt;"</code></td><td>content of the field <code>&lt;field&gt;</code> is <code>&lt;value&gt;</code><br>
      &lt;field&gt; is one of <code>uid</code>, <code>mode</code>, <code>summary</code>, <code>location</code>,
      <code>description</code>, <code>categories</code>, <code>classification</code>
      </td></tr>
    <tr><td><code>field(&lt;field&gt;)=~"&lt;regex&gt;"</code></td><td>content of the field &lt;field&gt; matches &lt;regex&gt;<br>
      &lt;field&gt; is one of <code>uid</code>, <code>mode</code>, <code>summary</code>, <code>location</code>,
      <code>description</code>, <code>categories</code>, <code>classification</code><br>
      </td></tr>
    </table><br>
    The double quotes (<code>"</code>) on the right hand side of a <code>&lt;filterSpec&gt;</code>
    are not part of the value or regular expression. Single quotes (<code>'</code>) can be
    used instead.<br><br>

    Examples:<br>
    <code>get MyCalendar events filter:uid=="432dsafweq64yehdbwqhkd"</code><br>
    <code>get MyCalendar events filter:uid=~"^7"</code><br>
    <code>get MyCalendar events filter:mode=="alarm"</code><br>
    <code>get MyCalendar events filter:mode=~"alarm|upcoming"</code><br>
    <code>get MyCalendar events filter:field(summary)=~"Mama"</code><br>
    <code>get MyCalendar events filter:field(classification)=="PUBLIC"</code><br>
    <code>get MyCalendar events filter:field(summary)=~"Gelber Sack",mode=~"upcoming|start"</code><br>
    <code>get MyCalendar events filter:field(summary)=~"Gelber Sack" filter:mode=~"upcoming|start"</code>
    <br><br>

    The <u><code>series</code></u> parameter determines the display of
    recurring events. <code>series:next</code> limits the display to the
    next calendar event out of all calendar events in the series that have
    not yet ended. <code>series:next=&lt;max&gt;</code> shows at most the
    <code>&lt;max&gt;</code> next calendar events in the series. This applies
    per series. To limit the total amount of events displayed see the <code>limit</code>
    parameter below.<br><br>

    The <u><code>limit</code></u> parameter limits the number of events displayed.
    <code>&lt;limitSpecs&gt;</code> is a comma-separated list of <code>&lt;limitSpec&gt;</code>
    specifications.<br><br>

    <table>
    <tr><th align="left"><code>&lt;limitSpec&gt;</code></th><th align="left">description</th></tr>
    <tr><td><code>count=&lt;n&gt;</code></td><td>shows at most <code>&lt;n&gt;</code> events, <code>&lt;n&gt;</code> is a positive integer</td></tr>
    <tr><td><code>from=[+|-]&lt;timespec&gt;</code></td><td>shows only events that end after
      a timespan &lt;timespec&gt; from now; use a minus sign for events in the
      past; &lt;timespec&gt; is described below in the Attributes section</td></tr>
    <tr><td><code>to=[+|-]&lt;timespec&gt;</code></td><td>shows only events that start before
      a timespan &lt;timespec&gt; from now; use a minus sign for events in the
      past; &lt;timespec&gt; is described below in the Attributes section</td></tr>
    <tr><td><code>when=today|tomorrow</code></td><td>shows events for today or tomorrow</td></tr>
    <tr><td><code>when=&lt;D1&gt;</code></td><td>shows events for day &lt;D1&gt; from now, &lt;D1&gt;= 0 stands for today, negative values allowed </td></tr>
    <tr><td><code>when=&lt;D1&gt;..&lt;D2&gt;</code></td><td>shows events for the day range from day &lt;D1&gt; to day &lt;D2&gt; from now</td></tr>
    </table><br>

    Examples:<br>
    <code>get MyCalendar events limit:count=10</code><br>
    <code>get MyCalendar events limit:from=-2d</code><br>
    <code>get MyCalendar events limit:when=today</code><br>
    <code>get MyCalendar events limit:count=10,from=0,to=+10d</code><br>
    <br><br>

    The <u><code>include</code></u> parameter includes events from other calendars. This is useful for
    displaying events from several calendars in one combined output. <code>&lt;names&gt;</code> is
    a comma-separated list of names of calendar devices. The name of the device itself as well as
    any duplicates are silently ignored. Names of non-existant devices or of devices that are not
    Calendar devices are ignored and an error is written to the log.<br><br>
    Example:<br>
    <code>get MyCalendar events include:HolidayCalendar,GarbageCollection</code><br>
    <br><br>


    The <u><code>returnType</code></u> parameter is used to return the events in a particular type.
    This is useful for Perl scripts.<br><br>

    <table>
    <tr><th align="left"><code>&lt;returnTypeSpec&gt;</code></th><th align="left">description</th></tr>
    <tr><td><code>$text</code></td><td>a multiline string in human-readable format (default)</td></tr>
    <tr><td><code>@texts</code></td><td>an array of strings in human-readable format</td></tr>
    <tr><td><code>@events</code></td><td>an array of Calendar::Event hashes</td></tr>

    </table>
    <br><br>

    </li>


    <!-- DEPRECATED

    <li><code>get &lt;name&gt; &lt;format&gt; &lt;filter&gt; [&lt;max&gt;]</code><br>
    This command is deprecated. Use <code>get &lt;name&gt;  events ...</code>
    instead. Please inform the author of the module if you think that there
    is anything this command can do what <code>get &lt;name&gt;  events ...</code>
    cannot.<br><br>

    Returns, line by line, information on the calendar events in the calendar &lt;name&gt;. The content depends on the
    &lt;format&gt specifier:<br><br>

    <table>
    <tr><th align="left">&lt;format&gt;</th><th align="left">content</th></tr>
    <tr><td>uid</td><td>the UID of the event</td></tr>
    <tr><td>text</td><td>a user-friendly textual representation, best suited for display</td></tr>
    <tr><td>summary</td><td>the content of the summary field (subject, title)</td></tr>
    <tr><td>location</td><td>the content of the location field</td></tr>
    <tr><td>categories</td><td>the content of the categories field</td></tr>
    <tr><td>alarm</td><td>alarm time in human-readable format</td></tr>
    <tr><td>start</td><td>start time in human-readable format</td></tr>
    <tr><td>end</td><td>end time in human-readable format</td></tr>
    <tr><td>categories</td><td>the content of the categories field</td></tr>
    <tr><td>full</td><td>the full state</td></tr>
    <tr><td>debug</td><td>like full with additional information for debugging purposes</td></tr>
    </table><br>

    The &lt;filter&gt; specifier determines the seriesed subset of calendar events:<br><br>

    <table>
    <tr><th align="left">&lt;filter&gt;</th align="left"><th>seriesion</th></tr>
    <tr><td>mode=&lt;regex&gt;</td><td>all calendar events with mode matching the regular expression &lt;regex&gt</td></tr>
    <tr><td>&lt;mode&gt;</td><td>all calendar events in the mode &lt;mode&gt</td></tr>
    <tr><td>uid=&lt;regex&gt;</td><td>all calendar events identified by UIDs that match the regular expression &lt;regex&gt;.</td></tr>
    <tr><td>&lt;uid&gt;</td><td>all calendar events identified by the UID &lt;uid&gt;</td></tr>
    <tr><td>&lt;reading&gt;</td><td>all calendar events listed in the reading &lt;reading&gt; (modeAlarm, modeAlarmed, modeStart, etc.) - this is deprecated and will be removed in a future version, use mode=&lt;regex&gt; instead.</td></tr>
    <tr><td>all</td><td>all calendar events (past, current and future)</td></tr>
    <tr><td>next</td><td>only calendar events that have not yet ended and among these only the first in a series, best suited for display</td></tr>
    </table><br>

    The <code>mode=&lt;regex&gt;</code> and <code>uid=&lt;regex&gt;</code> filters should be preferred over the
    <code>&lt;mode&gt;</code> and <code>&lt;uid&gt;</code> filters.<br><br>

    The optional parameter <code>&lt;max&gt;</code> limits
    the number of returned lines.<br><br>

    See attributes <code>hideOlderThan</code> and
    <code>hideLaterThan</code> for how to return events within a certain time window.
    Please remember that the global &pm;400 days limits apply.<br><br>

    Examples:<br>
    <code>get MyCalendar text next</code><br>
    <code>get MyCalendar summary uid:435kjhk435googlecom 1</code><br>
    <code>get MyCalendar summary 435kjhk435googlecom 1</code><br>
    <code>get MyCalendar full all</code><br>
    <code>get MyCalendar text mode=alarm|start</code><br>
    <code>get MyCalendar text uid=.*6286.*</code><br>
    <br>
    </li>

    -->

    <li><code>get &lt;name&gt; find &lt;regexp&gt;</code><br>
    Returns, line by line, the UIDs of all calendar events whose summary matches the regular expression
    &lt;regexp&gt;.<br><br></li>

    <li><code>get &lt;name&gt; vcalendar</code><br>
    Returns the calendar in ICal format as retrieved from the source.<br><br></li>

    <li><code>get &lt;name&gt; vevents</code><br>
    Returns a list of all VEVENT entries in the calendar with additional information for
    debugging. Only properties that have been kept during processing of the source
    are shown. The list of calendar events created from each VEVENT entry is shown as well
    as the list of calendar events that have been omitted.</li>

  </ul>

  <br><br>

  <a name="Calendarattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>defaultFormat &lt;formatSpec&gt;</code><br>
        Sets the default format for the <code>get &lt;name&gt; events</code>
        command. The specification is explained there. You must enclose
        the &lt;formatSpec&gt; in double quotes (") like input
        in <code>attr myCalendar defaultFormat "$T1 $D $S"</code>.</li><br><br>

    <li><code>defaultTimeFormat &lt;timeFormatSpec&gt;</code><br>
      Sets the default time format for the <code>get &lt;name&gt;events</code>
      command. The specification is explained there. Do not enclose
      the &lt;timeFormatSpec&gt; in quotes.</li><br><br>

    <li><code>synchronousUpdate 0|1</code><br>
        If this attribute is not set or if it is set to 0, the processing is done
        in the background and FHEM will not block during updates. <br/>
        If this attribute is set to 1, the processing of the calendar is done
        in the foreground. Large calendars will block FHEM on slow systems. <br/>
        <br/>
        Attribute value will be ignored if FHEM is running on a Windows platform.<br/>
        On Windows platforms the processing will always be done synchronously<br/>
        </li><br><br>

    <li><code>update onUrlChanged|none</code><br>
        If this attribute is set to <code>onUrlChanged</code>, the processing is done only
        if url to calendar has changed since last calendar update.<br/>
        If this attribute is set to <code>none</code>, the calendar will not be updated at all.
        </li><br><br>

    <li><code>delay &lt;time&gt;</code><br>
        The waiting time in seconds after the initialization of FHEM or a configuration change before 
        actually retrieving the calendar from its source. If not set, a random time between 10 and 29 
        seconds is chosen. When several calendar devices are defined, staggered delays reduce
        load error rates.
        </li><br><br>

    <li><code>timeout &lt;time&gt;</code><br>
        The timeout in seconds for retrieving the calendar from its source. The default is 30. 
        Increase for very large calendars that take time to be assembled and retrieved from 
        their sources.
        </li><br><br>

    <li><code>removevcalendar 0|1</code><br>
        If this attribute is set to 1, the vCalendar will be discarded after the processing to reduce the memory consumption of the module.
        A retrieval via <code>get &lt;name&gt; vcalendar</code> is then no longer possible.
        </li><br><br>

    <li><code>hideOlderThan &lt;timespec&gt;</code><br>
        <code>hideLaterThan &lt;timespec&gt;</code><br><br><br>

        These attributes limit the list of events shown by
        <code>get &lt;name&gt; full|debug|text|summary|location|alarm|start|end ...</code>.<br><br>

        The time is specified relative to the current time t. If hideOlderThan is set,
        calendar events that ended before t-hideOlderThan are not shown. If hideLaterThan is
        set, calendar events that will start after t+hideLaterThan are not shown.<br><br>

        Please note that an action triggered by a change to mode "end" cannot access the calendar event
        if you set hideOlderThan to 0 because the calendar event will already be hidden at that time. Better set
        hideOlderThan to 10.<br><br>

        <code>&lt;timespec&gt;</code> must have one of the following formats:<br>
        <table>
        <tr><th>format</th><th>description</th><th>example</th></tr>
        <tr><td>SSS</td><td>seconds</td><td>3600</td></tr>
        <tr><td>SSSs</td><td>seconds</td><td>3600s</td></tr>
        <tr><td>HH:MM</td><td>hours:minutes</td><td>02:30</td></tr>
        <tr><td>HH:MM:SS</td><td>hours:minutes:seconds</td><td>00:01:30</td></tr>
        <tr><td>D:HH:MM:SS</td><td>days:hours:minutes:seconds</td><td>122:10:00:00</td></tr>
        <tr><td>DDDd</td><td>days</td><td>100d</td></tr>
        </table></li>
        <br><br>

    <li><code>cutoffOlderThan &lt;timespec&gt;</code><br>
        <code>cutoffLaterThan &lt;timespec&gt;</code><br>
        These attributes cut off all calendar events that end a timespan cutoffOlderThan
        before or a timespan cutoffLaterThan after the last update of the calendar.
        The purpose of setting this attribute is to save memory and processing time.
        Such calendar events cannot be accessed at all from FHEM.
    </li><br><br>

    <li><code>onCreateEvent &lt;perl-code&gt;</code><br>

        This attribute allows to run the Perl code &lt;perl-code&gt; for every
        calendar event that is created. See section <a href="#CalendarPlugIns">Plug-ins</a> below.
    </li><br><br>

    <li><code>SSLVerify</code><br>

        This attribute sets the verification mode for the peer certificate for connections secured by
        SSL. Set attribute either to 0 for SSL_VERIFY_NONE (no certificate verification) or
        to 1 for SSL_VERIFY_PEER (certificate verification). Disabling verification is useful
        for local calendar installations (e.g. OwnCloud, NextCloud) without valid SSL certificate.
    </li><br><br>

    <li><code>ignoreCancelled</code><br>
        Set to 1 to ignore events with status "CANCELLED".
        Set this attribute to 1 if calanedar events of a series are returned
        although they are cancelled.
    </li><br><br>

    <li><code>hasModeReadings</code><br>
        Set to 1 to use the obsolete mode readings.
    </li><br><br>

    <li><code>quirks &lt;values&gt;</code><br>
        Parameters to handle special situations. <code>&lt;values&gt;</code> is
        a comma-separated list of the following keywords:
        <ul>
          <li><code>ignoreDtStamp</code>: if present, a modified DTSTAMP attribute of a calendar event
          does not signify that the calendar event was modified.</li>
          <li><code>noWildcards</code>: if present, wildcards in the calendar's
          URL will not be expanded.</li>
        </ul>
    </li><br><br>


    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>

  <b>Description</b>
  <ul>
  <br>
  A calendar is a set of calendar events. The calendar events are
  fetched from the source calendar at the given URL on a regular basis.<br><br>

  A calendar event has a summary (usually the title shown in a visual
  representation of the source calendar), a start time, an end time, and zero, one or more alarm times. In case of multiple alarm times for a calendar event, only the
  earliest alarm time is kept.<br><br>

  Recurring calendar events (series) are currently supported to an extent:
  FREQ INTERVAL UNTIL COUNT are interpreted, BYMONTHDAY BYMONTH WKST
  are recognized but not interpreted. BYDAY is correctly interpreted for weekly and monthly events.
  The module will get it most likely wrong
  if you have recurring calendar events with unrecognized or uninterpreted keywords.
  Out-of-order events and events excluded from a series (EXDATE) are handled.
  Calendar events are only created within &pm;400 days around the time of the
  last update.
  <br><br>

  Calendar events are created when FHEM is started or when the respective entry in the source
  calendar has changed and the calendar is updated or when the calendar is reloaded with
  <code>get &lt;name&gt; reload</code>.
  Only calendar events within &pm;400 days around the event creation time are created. Consider
  reloading the calendar from time to time to avoid running out of upcoming events. You can use something like <code>define reloadCalendar at +*240:00:00 set MyCalendar reload</code> for that purpose.<br><br>

  Some dumb calendars do not use LAST-MODIFIED. This may result in modifications in the source calendar
  go unnoticed. Reload the calendar if you experience this issue.<br><br>

  A calendar event is identified by its UID. The UID is taken from the source calendar.
  All events in a series including out-of-order events habe the same UID.
  All non-alphanumerical characters
  are stripped off the original UID to make your life easier.<br><br>

  A calendar event can be in one of the following modes:
  <table>
  <tr><td>upcoming</td><td>Neither the alarm time nor the start time of the calendar event is reached.</td></tr>
  <tr><td>alarm</td><td>The alarm time has passed but the start time of the calendar event is not yet reached.</td></tr>
  <tr><td>start</td><td>The start time has passed but the end time of the calendar event is not yet reached.</td></tr>
  <tr><td>end</td><td>The end time of the calendar event has passed.</td></tr>
  </table><br>

  A calendar event transitions from one mode to another immediately when the time for the change has come. This is done by waiting
  for the earliest future time among all alarm, start or end times of all calendar events.
  <br><br>

  For backward compatibility, mode readings are filled when the <code>hasModeReadings</code> attribute is set. The remainder of
  this description applies to the obsolete mode readings.<br><br>

  Each mode reading is a semicolon-separated list of UIDs of
  calendar events that satisfy certain conditions:
  <table>
  <tr><td>calname</td><td>name of the calendar</td></tr>
  <tr><td>modeAlarm</td><td>events in alarm mode</td></tr>
  <tr><td>modeAlarmOrStart</td><td>events in alarm or start mode</td></tr>
  <tr><td>modeAlarmed</td><td>events that have just transitioned from upcoming to alarm mode</td></tr>
  <tr><td>modeChanged</td><td>events that have just changed their mode somehow</td></tr>
  <tr><td>modeEnd</td><td>events in end mode</td></tr>
  <tr><td>modeEnded</td><td>events that have just transitioned from start to end mode</td></tr>
  <tr><td>modeStart</td><td>events in start mode</td></tr>
  <tr><td>modeStarted</td><td>events that have just transitioned to start mode</td></tr>
  <tr><td>modeUpcoming</td><td>events in upcoming mode</td></tr>
  </table>
  <br><br>

  For recurring events, usually several calendar events exists with the same UID. In such a case,
  the UID is only shown in the mode reading for the most interesting mode. The most
  interesting mode is the first applicable of start, alarm, upcoming, end.<br><br>

  In particular, you will never see the UID of a series in modeEnd or modeEnded as long as the series
  has not yet ended - the UID will be in one of the other mode... readings. This means that you better
  do not trigger FHEM events for series based on mode... readings. See below for a recommendation.<br><br>
  </ul>
  <br>

  <b>Events</b>
  <br><br>
  <ul>
  When the calendar was reloaded or updated or when an alarm, start or end time was reached, one
  FHEM event is created:<br><br>

  <code>triggered</code><br><br>

  When you receive this event, you can rely on the calendar's readings being in a consistent and
  most recent state.<br><br>

  When a calendar event has changed, two FHEM events are created:<br><br>

  <code>changed: UID &lt;mode&gt;</code><br>
  <code>&lt;mode&gt;: UID</code><br><br>

  &lt;mode&gt; is the current mode of the calendar event after the change. Note: there is a
  colon followed by a single space in the FHEM event specification.<br><br>

  The recommended way of reacting on mode changes of calendar events is to get notified
  on the aforementioned FHEM events and do not check for the FHEM events triggered
  by a change of a mode reading.
  <br><br>
  </ul>

  <a name="CalendarPlugIns"></a>
  <b>Plug-ins</b>
  <ul>
  <br>
  A plug-in is a piece of Perl code that modifies a calendar event on the fly. The Perl code operates on the
  hash reference <code>$e</code>. The most important elements are as follows:

  <table>
  <tr><th>code</th><th>description</th></tr>
  <tr><td>$e->{start}</td><td>the start time of the calendar event, in seconds since the epoch</td></tr>
  <tr><td>$e->{end}</td><td>the end time of the calendar event, in seconds since the epoch</td></tr>
  <tr><td>$e->{alarm}</td><td>the alarm time of the calendar event, in seconds since the epoch</td></tr>
  <tr><td>$e->{summary}</td><td>the summary (caption, title) of the calendar event</td></tr>
  <tr><td>$e->{location}</td><td>the location of the calendar event</td></tr>
  </table><br>

  To add or change the alarm time of a calendar event for all events with the string "Tonne" in the
  summary, the following plug-in can be used:<br><br>
  <code>attr MyCalendar onCreateEvent { $e->{alarm}= $e->{start}-86400 if($e->{summary} =~ /Tonne/);; }</code><br>
  <br>The double semicolon masks the semicolon. <a href="#perl">Perl specials</a> cannot be used.<br>
  <br>
  To add a missing end time, the following plug-in can be used:<br><br>
  <code>attr MyCalendar onCreateEvent { $e->{end}= $e->{start}+86400 unless(defined($e->{end})) }</code><br>
  </ul>
  <br><br>

  <b>Usage scenarios</b>
  <ul><br>
    <i>Show all calendar events with details</i><br><br>
    <ul>
    <code>
    get MyCalendar events format:full<br>
    2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom     alarm 31.05.2012 17:00:00 07.06.2012 16:30:00-07.06.2012 18:00:00 Erna for coffee<br>
    992hydf4y44awer5466lhfdsr&shy;gl7tin6b6mckf8glmhui4&shy;googlecom  upcoming                     08.06.2012 00:00:00-09.06.2012 00:00:00 Vacation
    </code><br><br>
    </ul>

    <i>Show calendar events in your photo frame</i><br><br>
    <ul>
    Put a line in the <a href="#RSSlayout">layout description</a> to show calendar events in alarm or start mode:<br><br>
    <code>text 20 60 { fhem("get MyCalendar events timeFormat:'%d.%m.%Y %H:%M' format:custom='$T1 $S' filter:mode=~'alarm|start') }</code><br><br>
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
    Then define a notify (the dot after the second colon matches the space):<br><br>
    <code>
    define ErnaComes notify MyCalendar:start:.2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom set MyLight on
    </code><br><br>
    You can also do some logging:<br><br>
    <code>
    define LogErna notify MyCalendar:alarm:.2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom { Log3 $NAME, 1, "ALARM name=$NAME event=$EVENT part1=$EVTPART0 part2=$EVTPART1" }
    </code><br><br>
    </ul>

    <i>Switch actors on and off</i><br><br>
    <ul>
    Think about a calendar with calendar events whose summaries (subjects, titles) are the names of devices in your fhem installation.
    You want the respective devices to switch on when the calendar event starts and to switch off when the calendar event ends.<br><br>
    <code>
    define SwitchActorOn  notify MyCalendar:start:.* { \<br>
                my $reading="$EVTPART0";; \<br>
                my $uid= "$EVTPART1";; \<br>
                my $actor= fhem('get MyCalendar events filter:uid=="'.$uid.'" format:custom="$S"');; \<br>
                if(defined $actor) {
                   fhem("set $actor on")
                } \<br>
    }<br><br>
    define SwitchActorOff  notify MyCalendar:end:.* { \<br>
                my $reading="$EVTPART0";; \<br>
                my $uid= "$EVTPART1";; \<br>
                my $actor= fhem('get MyCalendar events filter:uid=="'.$uid.'" format:custom="$S"');; \<br>
                if(defined $actor) {
                   fhem("set $actor off")
                } \<br>
    }
    </code><br><br>
    You can also do some logging:<br><br>
    <code>
    define LogActors notify MyCalendar:(start|end):.*
    { my $reading= "$EVTPART0";; my $uid= "$EVTPART1";; \<br>
      my $actor= fhem('get MyCalendar events filter:uid=="'.$uid.'" format:custom="$S"');; \<br>
     Log3 $NAME, 1, "Actor: $actor, Reading $reading" }
    </code><br><br>
    </ul>


    <i>Inform about garbage collection</i><br><br>
    <ul>
    We assume the <code>GarbageCalendar</code> has all the dates of the
    garbage collection with the type of garbage collected in the summary. The
    following notify can be used to inform about the garbage collection:
    <br><br><code>
    define GarbageCollectionNotifier notify GarbageCalendar:alarm:.* { \<br>
      my $uid= "$EVTPART1";; \<br>
      my $summary= fhem('get MyCalendar events filter:uid=="'.$uid.'" format:custom="$S"');; \<br>
      # e.g. mail $summary to someone \<br>
    }</code><br><br>

    If the garbage calendar has no reminders, you can set these to one day
    before the date of the collection:<br><br><code>
    attr GarbageCalendar onCreateEvent { $e->{alarm}= $e->{start}-86400 }
    </code><br><br>
    The following code realizes a HTML display of the upcoming collection
    dates (see below):<br><br>
    <code>{ CalendarEventsAsHtml('GarbageCalendar','format:text filter:mode=~"alarm|start"') }</code>
    <br>
    </ul>


  </ul>
  <br>

  <b>Embedded HTML</b>
  <ul><br>
  The module provides two functions which return HTML code.<br><br>
  <code>CalendarAsHtml(&lt;name&gt;,&lt;options&gt;)</code>
  returns the HTML code for a list of calendar events. <code>&lt;name&gt;</code> is the name of the
  Calendar device and <code>&lt;options&gt;</code> is what you would write
  after <code>get &lt;name&gt; text ...</code>. This function is deprecated.
  <br><br>
  Example: <code>define MyCalendarWeblink weblink htmlCode { CalendarAsHtml("MyCalendar","next 3") }</code>
  <br><br>
  <code>CalendarEventsAsHtml(&lt;name&gt;,&lt;parameters&gt;)</code>
  returns the HTML code for a list of calendar events. <code>&lt;name&gt;</code> is the name of the
  Calendar device and <code>&lt;parameters&gt;</code> is what you would write
  in <code>get &lt;name&gt; events &lt;parameters&gt;</code>.
  <br><br>
  Example: <code>define MyCalendarWeblink weblink htmlCode
  { CalendarEventsAsHtml('F','format:custom="$T1 $D $S" timeFormat:"%d.%m" series:next=3') }</code>
  <br><br>
  Tip: use single quotes as outer quotes.

  <br><br>
  </ul>


</ul>


=end html
=begin html_DE

<a name="Calendar"></a>
<h3>Calendar</h3>
<ul>
  <a name="Calendardefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Calendar ical url &lt;URL&gt; [&lt;interval&gt;]</code><br>
    <code>define &lt;name&gt; Calendar ical file &lt;FILENAME&gt; [&lt;interval&gt;]</code><br>
    <br>
    Definiert ein Kalender-Device.<br><br>

    Ein Kalender-Device ermittelt (Serien-)Termine aus einem Quell-Kalender. Dieser kann eine URL oder eine Datei sein.
	Die Datei muss im iCal-Format vorliegen.<br><br>

    Beginnt die <abbr>URL</abbr> mit <code>https://</code>, muss das Perl-Modul <code>IO::Socket::SSL</code> installiert sein
    (use <code>cpan -i IO::Socket::SSL</code>).<br><br>

    Die <code>&lt;URL&gt;</code> kann %-wildcards der POSIX
    strftime-Funktion des darunterliegenden OS enthalten (siehe auch strftime
    Beschreibung).
    Allgemein gebr&auml;uchliche Wildcards sind:
    <ul>
    <li><code>%d</code> Tag des Monats (01..31)</li>
    <li><code>%m</code> Monat (01..12)</li>
    <li><code>%Y</code> Jahr (1970...)</li>
    <li><code>%w</code> Wochentag (0..6);  beginnend mit Sonntag (0)</li>
    <li><code>%j</code> Tag des Jahres (001..366)</li>
    <li><code>%U</code> Wochennummer des Jahres, wobei Wochenbeginn = Sonntag (00..53)</li>
    <li><code>%W</code> Wochennummer des Jahres, wobei Wochenbeginn = Montag (00..53)</li>
    </ul>
    <br/>
    -Die wildcards werden bei jedem Kalenderupdate ausgewertet.<br/>
    -Die Auswertung von wildcards kann bei Bedarf f&uuml; einen Kalender deaktiviert werden, indem das Schl&uuml;sselwort 'noWildcards'
     dem Attribut 'quirks' hinzugef&uuml;gt wird. Das ist n&uuml;tzlich bei url die bereits ein % enthalten, ohne damit ein wildcard
     zu kennzeichnen.<br/>
    <br/>
    Hinweise f&uuml;r Nutzer des Google-Kalenders:
    <ul>
    <li>Wildcards d&uuml;rfen in Google Kalender URL nicht verwendet werden!</li>
    <li>Du kannst direkt die private iCal-URL des Google-Kalenders nutzen.</li>
    <li>Sollte deine Google-Kalender-URL mit <code>https://</code> beginnen und das Perl-Modul <code>IO::Socket::SSL</code> ist nicht auf deinem System  installiert,
	kannst Du in der URL <code>https://</code> durch <code>http://</code> ersetzen, falls keine automatische Umleitung auf die <code>https://</code> URL erfolgt.
    Solltest Du unsicher sein, ob dies der Fall ist, &uuml;berpr&uuml;fe es bitte zuerst mit deinem Browser.</li>
    </ul>
    Hinweis f&uuml;r Nutzer des Nextcloud-Kalenders: Du kannst eine URL der folgenden Form benutzen:
    <code>https://admin:admin@demo.nextcloud.com/wid0ohgh/remote.php/dav/calendars/admin/personal/?export</code>.<br><br>

    Der optionale Parameter <code>interval</code> bestimmt die Zeit in Sekunden zwischen den Updates. Default-Wert ist 3600 (1 Stunde).<br>
    Eine Intervallangabe von 0 ist nicht erlaubt. Diese wird automatisch durch den Standardwert 3600 ersetzt und im Log protokolliert.<br><br/>

    Beispiele:
    <pre>
      define MeinKalender Calendar ical url https://www.google.com&shy;/calendar/ical/john.doe%40example.com&shy;/private-foo4711/basic.ics
      define DeinKalender Calendar ical url http://www.google.com&shy;/calendar/ical/jane.doe%40example.com&shy;/private-bar0815/basic.ics 86400
      define IrgendeinKalender Calendar ical file /home/johndoe/calendar.ics
      </pre>
      <br>

      Hinweis zur Erzeugung von Terminen:<ul><li>
    
      Termine, die zum Zeitpunkt ihrer Erstellung mehr als 400 Tage in der Vergangenheit oder in der Zukunft liegen,
      werden ausgelassen. Dieses Zeitfenster kann durch die
      Attribute <code>cutoffOlderThan</code> und <code>cutoffLaterThan</code> noch verkleinert werden.

      Dies kann zur Folge haben, dass Termine jenseits dieses Horizonts niemals erstellt werden, 
      solange der Kalender nicht neu initialisiert wird (<code>set ... reload</code> oder Neustart von FHEM) 
      oder der VEVENT-Datensatz nicht ver&auml;ndert wird.

      Daher sollte ab und zu ein erzwungenes Neuladen eingeplant werden.
      </li></ul>
      
  </ul>
  <br>



  <a name="Calendarset"></a>
  <b>Set </b><br><br>
  <ul>
    <code>set &lt;name&gt; update</code><br>

    Erzwingt das Einlesen des Kalenders von der definierten URL. Das n&auml;chste automatische Einlesen erfolgt in
    <code>interval</code> Sekunden sp&auml;ter.<br><br>

    <code>set &lt;name&gt; reload</code><br>
    Dasselbe wie <code>update</code>, jedoch werden zuerst alle Termine entfernt.<br><br>

  </ul>
  <br>


  <a name="Calendarget"></a>
  <b>Get</b><br><br>
  <ul>
    <code>get &lt;name&gt; update</code><br>
    Entspricht <code>set &lt;name&gt; update</code><br><br>

    <code>get &lt;name&gt; reload</code><br>
    Entspricht  <code>set &lt;name&gt; reload</code><br><br>


    <li><code>get &lt;name&gt; events [format:&lt;formatSpec&gt;] [timeFormat:&lt;timeFormatSpec&gt;] [filter:&lt;filterSpecs&gt;]
    [series:next[=&lt;max&gt;]] [limit:&lt;limitSpecs&gt;]
    [include:&lt;names&gt;]
    [returnType:&lt;returnTypeSpec&gt;]
    </code><br><br>
    Das Schweizer Taschenmesser f&uuml;r die Anzeige von Terminen.
    Die Termine des Kalenders &lt;name&gt; werden Zeile f&uuml;r Zeile entsprechend der Format- und Filterangaben ausgegeben.
    Keiner, einer oder mehrere der Parameter <code>format</code>,
    <code>timeFormat</code>, <code>filter</code>, <code>series</code> und <code>limit</code>
    k&ouml;nnen angegeben werden, weiterhin ist es sinnvoll, den Parameter <code>filter</code> mehrere Male anzugeben.
    <br><br>

    Der Parameter <u><code>format</code></u> legt den zur&uuml;ckgegeben Inhalt fest.<br><br>
    Folgende Formatspezifikationen stehen zur Verf&uuml;gung:<br><br>

    <table>
    <tr><th align="left">&lt;formatSpec&gt;</th><th align="left">Beschreibung</th></tr>
    <tr><td><code>default</code></td><td>Standardformat (siehe unten)</td></tr>
    <tr><td><code>full</code></td><td>entspricht <code>custom="$U $M $A $T1-$T2 $S $CA $L"</code></td></tr>
    <tr><td><code>text</code></td><td>entspricht <code>custom="$T1 $S"</code></td></tr>
    <tr><td><code>human</code></td><td>same as <code>custom={ human($t1,$t2,$S) }</code> -  <code>human()</code> ist eine eingebaute Funktion, die das Ereignis in einem verdichteten menschenlesbaren Format ausgibt</td></tr>
    <tr><td><code>custom="&lt;formatString&gt;"</code></td><td>ein spezifisches Format (siehe unten)</td></tr>
    <tr><td><code>custom="{ &lt;perl-code&gt; }"</code></td><td>ein spezifisches Format (siehe unten)</td></tr>
    </table><br>
    Einzelne Anf&uuml;hrungszeichen (<code>'</code>) k&ouml;nnen anstelle von doppelten Anf&uuml;hrungszeichen (<code>"</code>) innerhalb
    eines spezifischen Formats benutzt werden.

    Folgende Variablen k&ouml;nnen in <code>&lt;formatString&gt;</code> und in
    <code>&lt;perl-code&gt;</code> verwendet werden:
    <br><br>

    <table>
    <tr><th align="left">variable</th><th align="left">Bedeutung</th></tr>
    <tr><td><code>$t1</code></td><td>Startzeit in Sekunden</td></tr>
    <tr><td><code>$T1</code></td><td>Startzeit entsprechend Zeitformat</td></tr>
    <tr><td><code>$t2</code></td><td>Endzeit in Sekunden</td></tr>
    <tr><td><code>$T2</code></td><td>Endzeit entsprechend Zeitformat</td></tr>
    <tr><td><code>$a</code></td><td>Alarmzeit in Sekunden</td></tr>
    <tr><td><code>$A</code></td><td>Alarmzeit entsprechend Zeitformat</td></tr>
    <tr><td><code>$d</code></td><td>Dauer in Sekunden</td></tr>
    <tr><td><code>$D</code></td><td>Dauer in menschenlesbarer Form</td></tr>
    <tr><td><code>$S</code></td><td>Zusammenfassung</td></tr>
    <tr><td><code>$L</code></td><td>Ortsangabe</td></tr>
    <tr><td><code>$CA</code></td><td>Kategorien</td></tr>
    <tr><td><code>$CL</code></td><td>Klassifizierung</td></tr>
    <tr><td><code>$DS</code></td><td>Beschreibung</td></tr>
    <tr><td><code>$U</code></td><td>UID</td></tr>
    <tr><td><code>$M</code></td><td>Modus</td></tr>
    </table><br>
    \, (maskiertes Komma) in Zusammenfassung, Ortsangabe und Beschreibung werden durch ein Komma ersetzt,
    aber \n (kennzeichnet Absatz) bleibt unber&uuml;hrt.<br><br>

    Wird der Parameter <code>format</code> ausgelassen, dann wird die Formatierung
    aus <code>defaultFormat</code> benutzt. Ist dieses Attribut nicht gesetzt,  wird <code>"$T1 $D $S"</code>
    als Formatierung benutzt.

    Das letzte Auftreten von <code>format</code> gewinnt bei mehrfacher Angabe.
    <br><br>

    Examples:<br>
    <code>get MyCalendar events format:full</code><br>
    <code>get MyCalendar events format:custom="$T1-$T2 $S \@ $L"</code><br>
    <code>get MyCalendar events format:custom={ sprintf("%20s %8s", $S, $D) }</code><br><br>

    Der Parameter <u><code>timeFormat</code></u> legt das Format f&uuml;r die Start-,
    End- und Alarmzeiten fest.<br><br>

    In <code>&lt;timeFormatSpec&gt;</code> kann die POSIX-Spezifikation verwendet werden.
    Auf <a href="http://strftime.net">strftime.net</a> gibt es ein Tool zum Erstellen von
    <code>&lt;timeFormatSpec&gt;</code>.<br><br>

    Wenn der Parameter <code>timeFormat</code> ausgelassen, dann wird die Formatierung
    aus <code>defaultTimeFormat</code> benutzt. Ist dieses Attribut nicht gesetzt, dann
    wird <code>"%d.%m.%Y %H:%M"</code> als Formatierung benutzt.
    Zum Umschlie&szlig;en der Formatangabe k&ouml;nnen einfache (<code>'</code>) oder
    doppelte (<code>"</code>) Anf&uuml;hrungszeichen verwendet werden.<br><br>

    Das letzte Auftreten von <code>timeFormat</code> gewinnt bei mehrfacher Angabe.
    <br><br>

    Example:<br>
    <code>get MyCalendar events timeFormat:"%e-%b-%Y" format:full</code><br><br>


    Der Parameter <u><code>filter</code></u> schr&auml;nkt die Anzeige der Termine ein.
    <code>&lt;filterSpecs&gt;</code> ist eine kommaseparierte Liste von
    <code>&lt;filterSpec&gt;</code>-Angaben.
    Alle Filterangaben m&uuml;ssen zutreffen, damit ein Termin angezeigt wird.
    Die Angabe ist kumulativ: jeder angegebene Filter wird zur Filterliste hinzugef&uum;gt
    und ber&uum;cksichtigt.<br><br>

    <table>
    <tr><th align="left"><code>&lt;filterSpec&gt;</code></th><th align="left">Beschreibung</th></tr>
    <tr><td><code>uid=="&lt;uid&gt;"</code></td><td>UID ist <code>&lt;uid&gt;</code><br>
      entspricht <code>field(uid)=="&lt;uid&gt;"</code></td></tr>
    <tr><td><code>uid=~"&lt;regex&gt;"</code></td><td>Der regul&auml;re Ausdruck <code>&lt;regex&gt;</code> entspricht der UID<br>
      entspricht <code>field(uid)=~"&lt;regex&gt;"</code></td></tr>
    <tr><td><code>mode=="&lt;mode&gt;"</code></td><td>Modus ist <code>&lt;mode&gt;</code><br>
      entspricht <code>field(mode)=="&lt;mode&gt;"</code></td></tr>
    <tr><td><code>mode=~"&lt;regex&gt;"</code></td><td>Der regul&auml;re Ausdruck <code>&lt;regex&gt;</code> entspricht <code>mode</code><br>
      entspricht <code>field(mode)=~"&lt;regex&gt;"</code></td></tr>
    <tr><td><code>field(&lt;field&gt;)=="&lt;value&gt;"</code></td><td>Inhalt von <code>&lt;field&gt;</code> ist <code>&lt;value&gt;</code><br>
      &lt;field&gt; ist eines von <code>uid</code>, <code>mode</code>, <code>summary</code>, <code>location</code>,
      <code>description</code>, <code>categories</code>, <code>classification</code>
      </td></tr>
    <tr><td><code>field(&lt;field&gt;)=~"&lt;regex&gt;"</code></td><td>Inhalt von &lt;field&gt; entspricht dem regul&auml;ren Ausdruck <code>&lt;regex&gt;</code><br>
      &lt;field&gt; ist eines von <code>uid</code>, <code>mode</code>, <code>summary</code>, <code>location</code>,
      <code>description</code>, <code>categories</code>, <code>classification</code><br>
      </td></tr>
    </table><br>
    Die doppelten Anf&uuml;hrungszeichen auf der rechten Seite von <code>&lt;filterSpec&gt;</code> sind nicht
    Teil des regul&auml;ren Ausdrucks. Es k&ouml;nnen stattdessen einfache Anf&uuml;hrungszeichen verwendet werden.
    <br><br>

    Examples:<br>
    <code>get MyCalendar events filter:uid=="432dsafweq64yehdbwqhkd"</code><br>
    <code>get MyCalendar events filter:uid=~"^7"</code><br>
    <code>get MyCalendar events filter:mode=="alarm"</code><br>
    <code>get MyCalendar events filter:mode=~"alarm|upcoming"</code><br>
    <code>get MyCalendar events filter:field(summary)=~"Mama"</code><br>
    <code>get MyCalendar events filter:field(classification)=="PUBLIC"</code><br>
    <code>get MyCalendar events filter:field(summary)=~"Gelber Sack",mode=~"upcoming|start"</code><br>
    <code>get MyCalendar events filter:field(summary)=~"Gelber Sack" filter:mode=~"upcoming|start"</code>
    <br><br>

    Der Parameter <u><code>series</code></u> bestimmt die Anzeige von wiederkehrenden
    Terminen. <code>series:next</code> begrenzt die Anzeige auf den n&auml;chsten Termin
    der noch nicht beendeten Termine innerhalb der Serie. <code>series:next=&lt;max&gt;</code>
    zeigt die n&auml;chsten <code>&lt;max&gt;</code> Termine der Serie. Dies gilt pro Serie.
    Zur Begrenzung der Anzeige siehe den <code>limit</code>-Parameter.<br><br>

    Der Parameter <u><code>limit</code></u> begrenzt die Anzeige der Termine.
    <code>&lt;limitSpecs&gt;</code> ist eine kommaseparierte Liste von <code>&lt;limitSpec&gt;</code> Angaben.
    <br><br>

    <table>
    <tr><th align="left"><code>&lt;limitSpec&gt;</code></th><th align="left">Beschreibung</th></tr>
    <tr><td><code>count=&lt;n&gt;</code></td><td>zeigt <code>&lt;n&gt;</code> Termine, wobei <code>&lt;n&gt;</code> eine positive Ganzzahl (integer) ist</td></tr>
    <tr><td><code>from=[+|-]&lt;timespec&gt;</code></td><td>zeigt nur Termine die nach einer Zeitspanne &lt;timespec&gt; ab jetzt enden;
    Minuszeichen f&uuml;r Termine in der Vergangenheit benutzen; &lt;timespec&gt; wird weiter unten im Attribut-Abschnitt beschrieben.</td></tr>
    <tr><td><code>to=[+|-]&lt;timespec&gt;</code></td><td>
    zeigt nur Termine die vor einer Zeitspanne &lt;timespec&gt; ab jetzt starten;
    Minuszeichen f&uuml;r Termine in der Vergangenheit benutzen; &lt;timespec&gt; wird weiter unten im Attribut-Abschnitt beschrieben.</td></tr>
    <tr><td><code>when=today|tomorrow</code></td><td>zeigt anstehende Termin f&uuml;r heute oder morgen an</td></tr>
    <tr><td><code>when=&lt;D1&gt;</code></td><td>zeigt Termine f&uuml;r Tag &lt;D1&gt; von heute an, &lt;D1&gt;= 0 steht f&uuml;r heute, negative Werte sind erlaubt</td></tr>
    <tr><td><code>when=&lt;D1&gt;..&lt;D2&gt;</code></td><td>zeigt Termine f&uuml;r den Tagesbereich von Tag
     &lt;D1&gt; bis Tag &lt;D2&gt; von heute an</td></tr>
    </table><br>

    Examples:<br>
    <code>get MyCalendar events limit:count=10</code><br>
    <code>get MyCalendar events limit:from=-2d</code><br>
    <code>get MyCalendar events limit:when=today</code><br>
    <code>get MyCalendar events limit:count=10,from=0,to=+10d</code><br>
    <br><br>

    Der <u><code>include</code></u> Parameter schlie&szlig;t Termine aus anderen Kalendern ein. Das ist n&uuml;tzlich,
    um Termine aus anderen Kalendern in einer kombimierten Ausgabe anzuzeigen.
    <code>&lt;names&gt;</code> ist eine mit Kommas getrennte Liste der Namen von Calendar-Ger&auml;ten.
    Der Name des Kalenders selbst sowie Duplikate werden stillschweigend ignoriert. Namen von Ger&auml;ten, die
    es nicht gibt oder keine Calendar-Ger&auml;te sind, werden ignoriert und es wird eine Fehlermeldung ins Log
    geschrieben.<br><br>
    Example:<br>
    <code>get MyCalendar events include:Feiertage,M&uuml;llabfuhr</code><br>
    <br><br>


    Der Parameter <u><code>returnType</code></u> wird verwendet, um die Termine als ein bestimmter Typ
    zur&uuml;ckzugeben. Das ist n&uuml;tzlich f&uuml;r Perl-Skripte.<br><br>

    <table>
    <tr><th align="left"><code>&lt;returnTypeSpec&gt;</code></th><th align="left">Beschreibung</th></tr>
    <tr><td><code>$text</code></td><td>ein mehrzeiliger String in menschenlesbarer Darstellung (Vorgabe)</td></tr>
    <tr><td><code>@texts</code></td><td>ein Array von Strings in menschenlesbarer Darstellung</td></tr>
    <tr><td><code>@events</code></td><td>ein Array von Calendar::Event-Hashs</td></tr>

    </table>
    <br><br>

    </li>


    <li><code>get &lt;name&gt; find &lt;regexp&gt;</code><br>
    Gibt zeilenweise die UID von allen Terminen aus, deren Zusammenfassung dem regul&auml;ren Ausdruck &lt;regexp&gt; entspricht.<br><br></li>

    <li><code>get &lt;name&gt; vcalendar</code><br>
    Gibt den Kalender im ICal-Format aus, so wie er von der Quelle abgerufen wurde.<br><br></li>

    <li><code>get &lt;name&gt; vevents</code><br>
    Gibt eine Liste aller VEVENT-Eintr&auml;ge mit weiteren Informationen f&uuml;r Debugzwecke zur&uuml;ck.
    Nur Eigenschaften, die bei der Verarbeitung des Kalenders behalten wurden, werden gezeigt.
    Die Liste, der aus jedem VEVENT-Eintrag erstellten Termine, wird, ebenso wie die ausgelassenen Termine, gezeigt.
    </li>

  </ul>

  <br>

  <a name="Calendarattr"></a>
  <b>Attribute</b>
  <br><br>
  <ul>
    <li><code>defaultFormat &lt;formatSpec&gt;</code><br>
        Setzt das Standardformat f&uuml;r <code>get &lt;name&gt; events</code>.
        Der Aufbau wird dort erkl&auml;t. &lt;formatSpec&gt; muss in doppelte
        Anf&uuml;hrungszeichen (") gesetzt werden, wie z.B. <code>attr myCalendar defaultFormat "$T1 $D $S"</code>.</li><br><br>

    <li><code>defaultTimeFormat &lt;timeFormatSpec&gt;</code><br>
        Setzt das Standardzeitformat f&uuml;r <code>get &lt;name&gt; events</code>.
        Der Aufbau wird dort erkl&auml;t. &lt;timeFormatSpec&gt; <b>nicht</b> in Anf&uuml;hrungszeichen setzten. </li><br><br>

    <li><code>synchronousUpdate 0|1</code><br>
        Wenn dieses Attribut nicht oder auf 0 gesetzt ist, findet die Verarbeitung im Hintergrund statt
        und FHEM wird w&auml;hrend der Verarbeitung nicht blockieren.<br/>
        Wird dieses Attribut auf 1 gesetzt, findet die Verarbeitung des Kalenders im Vordergrund statt.
        Umfangreiche Kalender werden FHEM auf langsamen Systemen blockieren.<br/>
        <br/>
        Das Attribut wird ignoriert, falls FHEM unter Windows betrieben wird.
        In diesem Fall erfolgt die Verarbeitung immer synchron.<br/>
       </li><br><br>

    <li><code>update none|onUrlChanged</code><br>
        Wird dieses Attribut auf <code>none</code> gesetzt ist, wird der Kalender &uuml;berhaupt nicht aktualisiert.<br/>
        Wird dieses Attribut auf <code>onUrlChanged</code> gesetzt ist, wird der Kalender nur dann aktualisiert, wenn sich die
        URL seit dem letzten Aufruf ver&auml;ndert hat, insbesondere nach der Auswertung von wildcards im define.<br/>
        </li><br><br>

     <li><code>delay &lt;time&gt;</code><br>
        Wartezeit in Sekunden nach der Initialisierung von FHEM oder einer Konfigurations&auml;nderung bevor
        der Kalender tats&auml;chlich von der Quelle geladen wird. Wenn nicht gesetzt wird eine
        Zufallszeit zwischen 10 und 29 Sekunden gew&auml;hlt. Wenn mehrere Kalender definiert sind, f&uuml;hren
        gestaffelte Wartezeiten zu einer Verminderung der Ladefehleranf&auml;lligkeit.
        </li><br><br>

      <li><code>timeout &lt;time&gt;</code><br>
        Der Timeout in Sekunden um einen Kalender von seiner Quelle zu holen. Standard ist 30.
        Erh&ouml;hen f&uuml;r sehr gro&szlig;e Kalender, bei denen es eine Weile dauert,
        sie an der Quelle zusammenzustellen und herunterzuladen.
        </li><br><br>

    <li><code>removevcalendar 0|1</code><br>
		Wenn dieses Attribut auf 1 gesetzt ist, wird der vCalendar nach der Verarbeitung verworfen,
		gleichzeitig reduziert sich der Speicherverbrauch des Moduls.
		Ein Abruf &uuml;ber <code>get &lt;name&gt; vcalendar</code> ist dann nicht mehr m&ouml;glich.
        </li><br><br>

    <li><code>hideOlderThan &lt;timespec&gt;</code><br>
        <code>hideLaterThan &lt;timespec&gt;</code><br><br><br>

		Dieses Attribut grenzt die Liste der durch <code>get &lt;name&gt; full|debug|text|summary|location|alarm|start|end ...</code> gezeigten Termine ein.

        Die Zeit wird relativ zur aktuellen Zeit <var>t</var> angegeben.<br>
		Wenn &lt;hideOlderThan&gt; gesetzt ist, werden Termine, die vor &lt;t-hideOlderThan&gt; enden, ingnoriert.<br>
        Wenn &lt;hideLaterThan&gt; gesetzt ist, werden Termine, die nach &lt;t+hideLaterThan&gt; anfangen, ignoriert.<br><br>

        Bitte beachte, dass eine Aktion, die durch einen Wechsel in den Modus "end" ausgel&ouml;st wird, nicht auf den Termin
        zugreifen kann, wenn <code>hideOlderThan</code> 0 ist, denn der Termin ist dann schon versteckt. Setze <code>hideOlderThan</code> besser auf 10.<br><br>


        <code>&lt;timespec&gt;</code> muss; einem der folgenden Formate entsprechen:<br>
        <table>
        <tr><th>Format</th><th>Beschreibung</th><th>Beispiel</th></tr>
        <tr><td>SSS</td><td>Sekunden</td><td>3600</td></tr>
        <tr><td>SSSs</td><td>Sekunden</td><td>3600s</td></tr>
        <tr><td>HH:MM</td><td>Stunden:Minuten</td><td>02:30</td></tr>
        <tr><td>HH:MM:SS</td><td>Stunden:Minuten:Sekunden</td><td>00:01:30</td></tr>
        <tr><td>D:HH:MM:SS</td><td>Tage:Stunden:Minuten:Sekunden</td><td>122:10:00:00</td></tr>
        <tr><td>DDDd</td><td>Tage</td><td>100d</td></tr>
        </table></li>
        <br><br>

    <li><code>cutoffOlderThan &lt;timespec&gt;</code><br>
        <code>cutoffLaterThan &lt;timespec&gt;</code><br>
        Diese Attribut schneidem alle Termine weg, die eine Zeitspanne <code>cutoffOlderThan</code>
        vor bzw. <code>cutoffLaterThan</code> nach der letzten Aktualisierung des Kalenders enden.
        Der Zweck dieses Attributs ist
        es Speicher und Verarbeitungszeit zu
        sparen. Auf solche Termine kann gar nicht mehr aus FHEM heraus zugegriffen
        werden.
    </li><br><br>

    <li><code>onCreateEvent &lt;perl-code&gt;</code><br>

		Dieses Attribut f&uuml;hrt ein Perlprogramm &lt;perl-code&gt; f&uuml;r jeden erzeugten Termin aus.
        Weitere Informationen unter <a href="#CalendarPlugIns">Plug-ins</a> im Text.
    </li><br><br>

        <li><code>SSLVerify</code><br>

        Dieses Attribut setzt die Art der &Uuml;berpr&uuml;fung des Zertifikats des Partners
        bei mit SSL gesicherten Verbindungen. Entweder auf 0 setzen f&uuml;r
        SSL_VERIFY_NONE (keine &Uuml;berpr&uuml;fung des Zertifikats) oder auf 1 f&uuml;r
        SSL_VERIFY_PEER (&Uuml;berpr&uuml;fung des Zertifikats). Die &Uuml;berpr&uuml;fung auszuschalten
        ist n&uuml;tzlich f&uuml;r lokale Kalenderinstallationen(e.g. OwnCloud, NextCloud)
        ohne g&uuml;tiges SSL-Zertifikat.
    </li><br><br>

    <li><code>ignoreCancelled</code><br>
        Wenn dieses Attribut auf 1 gesetzt ist, werden Termine im Status "CANCELLED" ignoriert.
        Dieses Attribut auf 1 setzen, falls Termine in einer
        Serie zur&uuml;ckgegeben werden, die gel&ouml;scht sind.
    </li><br><br>

    <li><code>hasModeReadings</code><br>
        Auf 1 setzen, um die veralteten mode-Readings zu benutzen.
    </li><br><br>


    <li><code>quirks &lt;values&gt;</code><br>
        Parameter f&uuml;r spezielle Situationen. <code>&lt;values&gt;</code> ist
        eine kommaseparierte Liste der folgenden Schl&uuml;sselw&ouml;rter:
        <ul>
          <li><code>ignoreDtStamp</code>: wenn gesetzt, dann zeigt
          ein ver&auml;ndertes DTSTAMP Attribut eines Termins nicht an, dass;
          der Termin ver&auml;ndert wurde.</li>
          <li><code>noWildcards</code>: wenn gesetzt, werden Wildcards in der
            URL des Kalenders nicht ersetzt.</li>
        </ul>
    </li><br><br>


<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <b>Beschreibung</b>
  <ul><br>

  Ein Kalender ist eine Menge von Terminen. Ein Termin hat eine Zusammenfassg;ung (normalerweise der Titel, welcher im Quell-Kalender angezeigt wird), eine Startzeit, eine Endzeit und keine, eine oder mehrere Alarmzeiten. Die Termine werden
  aus dem Quellkalender ermittelt, welcher &uuml;ber die URL angegeben wird. Sollten mehrere Alarmzeiten f&uuml;r einen Termin existieren, wird nur der fr&uuml;heste Alarmzeitpunkt beibehalten. Wiederkehrende Kalendereintr&auml;ge werden in einem gewiss;en Umfang unterst&uuml;tzt:
  FREQ INTERVAL UNTIL COUNT werden ausgewertet, BYMONTHDAY BYMONTH WKST
  werden erkannt aber nicht ausgewertet. BYDAY wird f&uuml;r w&ouml;chentliche und monatliche Termine
  korrekt behandelt. Das Modul wird es sehr wahrscheinlich falsch machen, wenn Du wiederkehrende Termine mit unerkannten oder nicht ausgewerteten Schl&uuml;sselw&ouml;rtern hast.<br><br>

  Termine werden erzeugt, wenn FHEM gestartet wird oder der betreffende Eintrag im Quell-Kalender ver&auml;ndert
  wurde oder der Kalender mit <code>get &lt;name&gt; reload</code> neu geladen wird. Es werden nur Termine
  innerhalb &pm;400 Tage um die Erzeugungs des Termins herum erzeugt. Ziehe in Betracht, den Kalender von Zeit zu Zeit
  neu zu laden, um zu vermeiden, dass; FHEM die k&uuml;nftigen Termine ausgehen. Du kann so etwas wie <code>define reloadCalendar at +*240:00:00 set MyCalendar reload</code> daf&uuml;r verwenden.<br><br>

  Manche dumme Kalender benutzen LAST-MODIFIED nicht. Das kann dazu f&uuml;hren, dass Ver&auml;nderungen im
  Quell-Kalender unbemerkt bleiben. Lade den Kalender neu, wenn Du dieses Problem hast.<br><br>

  Ein Termin wird durch seine UID identifiziert. Die UID wird vom Quellkalender bezogen. Um das Leben leichter zu machen, werden alle nicht-alphanumerischen Zeichen automatisch aus der UID entfernt.<br><br>

  Ein Termin kann sich in einem der folgenden Modi befinden:
  <table>
  <tr><td>upcoming</td><td>Weder die Alarmzeit noch die Startzeit des Kalendereintrags ist erreicht.</td></tr>
  <tr><td>alarm</td><td>Die Alarmzeit ist &uuml;berschritten, aber die Startzeit des Kalender-Ereignisses ist noch nicht erreicht.</td></tr>
  <tr><td>start</td><td>Die Startzeit ist &uuml;berschritten, aber die Ende-Zeit des Kalender-Ereignisses ist noch nicht erreicht.</td></tr>
  <tr><td>end</td><td>Die Endzeit des Kalender-Ereignisses wurde &uuml;berschritten.</td></tr>
  </table><br>
  Ein Kalender-Ereignis wechselt umgehend von einem Modus zum anderen, wenn die Zeit f&uuml;r eine &Auml;nderung erreicht wurde. Dies wird dadurch erreicht, dass auf die fr&uuml;heste zuk&uuml;nftige Zeit aller Alarme, Start- oder Endzeiten aller Kalender-Ereignisse gewartet wird.
  <br><br>

  Aus Gr&uuml;nden der Abw&auml;rtskompatibilit&auml;t werden mode-Readings gef&uuml;llt, wenn das Attribut <code>hasModeReadings</code> gesetzt ist.
  Der Rest dieser Beschreibung bezieht sich auf diese veralteten mode-Readings.<br><br>
  
  Ein Kalender-Device hat verschiedene mode-Readings. Jedes mode-Reading stellt eine semikolonseparierte Liste aus UID von Kalender-Ereignisse dar, welche bestimmte Zust&auml;nde haben:
  <table>
  <tr><td>calname</td><td>Name des Kalenders</td></tr>
  <tr><td>modeAlarm</td><td>Ereignisse im Alarm-Modus</td></tr>
  <tr><td>modeAlarmOrStart</td><td>Ereignisse im Alarm- oder Startmodus</td></tr>
  <tr><td>modeAlarmed</td><td>Ereignisse, welche gerade in den Alarmmodus gewechselt haben</td></tr>
  <tr><td>modeChanged</td><td>Ereignisse, welche gerade in irgendeiner Form ihren Modus gewechselt haben</td></tr>
  <tr><td>modeEnd</td><td>Ereignisse im Endmodus</td></tr>
  <tr><td>modeEnded</td><td>Ereignisse, welche gerade vom Start- in den Endmodus gewechselt haben</td></tr>
  <tr><td>modeStart</td><td>Ereignisse im Startmodus</td></tr>
  <tr><td>modeStarted</td><td>Ereignisse, welche gerade in den Startmodus gewechselt haben</td></tr>
  <tr><td>modeUpcoming</td><td>Ereignisse im zuk&uuml;nftigen Modus</td></tr>
  </table>
  <br><br>

  F&uuml;r Serientermine werden mehrere Termine mit identischer UID erzeugt. In diesem Fall
  wird die UID nur im interessantesten gelesenen Modus-Reading angezeigt.
  Der interessanteste Modus ist der erste zutreffende Modus aus der Liste der Modi start, alarm, upcoming, end.<br><br>

  Die UID eines Serientermins wird nicht angezeigt, solange sich der Termin im Modus: modeEnd oder modeEnded befindet
  und die Serie nicht beendet ist. Die UID befindet sich in einem der anderen mode... Readings.
  Hieraus ergibts sich, das FHEM-Events nicht auf einem mode... Reading basieren sollten.
  Weiter unten im Text gibt es hierzu eine Empfehlung.<br><br>
  </ul>

  <b>Events</b>
  <ul><br>
  Wenn der Kalendar neu geladen oder aktualisiert oder eine Alarm-, Start- oder Endzeit
  erreicht wurde, wird ein FHEM-Event erzeugt:<br><br>

  <code>triggered</code><br><br>

  Man kann sich darauf verlassen, dass alle Readings des Kalenders in einem konsistenten und aktuellen
  Zustand befinden, wenn dieses Event empfangen wird.<br><br>

  Wenn ein Termin ge&auml;ndert wurde, werden zwei FHEM-Events erzeugt:<br><br>

  <code>changed: UID &lt;mode&gt;</code><br>
  <code>&lt;mode&gt;: UID</code><br><br>

  &lt;mode&gt; ist der aktuelle Modus des Termins nach der &auml;nderung. Bitte beachten: Im FHEM-Event befindet sich ein Doppelpunkt gefolgt von einem Leerzeichen.<br><br>

  FHEM-Events sollten nur auf den vorgenannten Events basieren und nicht auf FHEM-Events, die durch &auml;ndern eines mode... Readings ausgel&ouml;st werden.
  <br><br>
  </ul>

  <a name="CalendarPlugIns"></a>
  <b>Plug-ins</b>
  <ul>
  <br>
  Experimentell, bitte mit Vorsicht nutzen.<br><br>

  Ein Plug-In ist ein kleines Perl-Programm, das Termine nebenher ver&auml;ndern kann.
  Das Perl-Programm arbeitet mit der Hash-Referenz <code>$e</code>.<br>
  Die wichtigsten Elemente sind:

  <table>
  <tr><th>code</th><th>Beschreibung</th></tr>
  <tr><td>$e->{start}</td><td>Startzeit des Termins, in Sekunden seit 1.1.1970</td></tr>
  <tr><td>$e->{end}</td><td>Endezeit des Termins, in Sekunden seit 1.1.1970</td></tr>
  <tr><td>$e->{alarm}</td><td>Alarmzeit des Termins, in Sekunden seit 1.1.1970</td></tr>
  <tr><td>$e->{summary}</td><td>die Zusammenfassung (Betreff, Titel) des Termins</td></tr>
  <tr><td>$e->{location}</td><td>Der Ort des Termins</td></tr>
  </table><br>

  Um f&uuml;r alle Termine mit dem Text "Tonne" in der Zusammenfassung die Alarmzeit zu erg&auml;nzen / zu &auml;ndern,
  kann folgendes Plug-In benutzt werden:<br><br>
  <code>attr MyCalendar onCreateEvent { $e->{alarm}= $e->{start}-86400 if($e->{summary} =~ /Tonne/);; }</code><br>
  <br>Das doppelte Semikolon maskiert das Semikolon. <a href="#perl">Perl specials</a> k&ouml;nnen nicht genutzt werden.<br>
  <br>
  Zum Erg&auml;nzen einer fehlenden Endezeit, kann folgendes Plug-In benutzt werden: <br><br>
  <code>attr MyCalendar onCreateEvent { $e->{end}= $e->{start}+86400 unless(defined($e->{end})) }</code><br>
  </ul>
  <br><br>

  <b>Anwendungsbeispiele</b>
  <ul><br>
    <i>Alle Termine inkl. Details anzeigen</i><br><br>
    <ul>
    <code>
    get MyCalendar events format:full<br>
    2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom     alarm 31.05.2012 17:00:00 07.06.2012 16:30:00-07.06.2012 18:00:00 Erna for coffee<br>
    992hydf4y44awer5466lhfdsr&shy;gl7tin6b6mckf8glmhui4&shy;googlecom  upcoming                     08.06.2012 00:00:00-09.06.2012 00:00:00 Vacation
    </code><br><br>
    </ul>

    <i>Zeige Termine in Deinem Bilderrahmen</i><br><br>
    <ul>
    F&uuml;ge eine Zeile in die <a href="#RSSlayout">layout description</a> ein, um Termine im Alarm- oder Startmodus anzuzeigen:<br><br>
    <code>text 20 60 { fhem("get MyCalendar events timeFormat:'%d.%m.%Y %H:%M' format:custom='$T1 $S' filter:mode=~'alarm|start') }</code><br><br>
    Dies kann dann z.B. so aussehen:<br><br>
    <code>
    07.06.12 16:30 Erna zum Kaffee<br>
    08.06.12 00:00 Urlaub
    </code><br><br>
    </ul>

    <i>Schalte das Licht ein, wenn Erna kommt</i><br><br>
    <ul>
    Finde zuerst die UID des Termins:<br><br>
    <code>
    get MyCalendar find .*Erna.*<br>
    2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom
    </code><br><br>
    Definiere dann ein notif (der Punkt nach dem zweiten Doppelpunkt steht f&uuml;r ein Leerzeichen)<br><br>
    <code>
    define ErnaComes notify MyCalendar:start:.2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom.* set MyLight on
    </code><br><br>
    Du kannst auch ein Logging aufsetzen:<br><br>
    <code>
    define LogErna notify MyCalendar:alarm:.2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom.* { Log3 $NAME, 1, "ALARM name=$NAME event=$EVENT part1=$EVTPART0 part2=$EVTPART1" }
    </code><br><br>
    </ul>

    <i>Schalte Aktoren an und aus</i><br><br>
    <ul>
    Stell Dir einen Kalender vor, dessen Zusammenfassungen (Betreff, Titel) die Namen von Devices in Deiner FHEM-Installation sind.
    Du willst nun die entsprechenden Devices an- und ausschalten, wenn das Kalender-Ereignis beginnt bzw. endet.<br><br>
    <code>
    define SwitchActorOn  notify MyCalendar:start:.* { \<br>
                my $reading="$EVTPART0";; \<br>
                my $uid= "$EVTPART1";; \<br>
                my $actor= fhem('get MyCalendar events filter:uid=="'.$uid.'" format:custom="$S"');; \<br>
                if(defined $actor) {
                   fhem("set $actor on")
                } \<br>
    }<br><br>
    define SwitchActorOff  notify MyCalendar:end:.* { \<br>
                my $reading="$EVTPART0";; \<br>
                my $uid= "$EVTPART1";; \<br>
                my $actor= fhem('get MyCalendar events filter:uid=="'.$uid.'" format:custom="$S"');; \<br>
                if(defined $actor) {
                   fhem("set $actor off")
                } \<br>
    }
    </code><br><br>
    Auch hier kannst du Aktionen mitloggen:<br><br>
    <code>
    define LogActors notify MyCalendar:(start|end):.*
    { my $reading= "$EVTPART0";; my $uid= "$EVTPART1";; \<br>
      my $actor= fhem('get MyCalendar events filter:uid=="'.$uid.'" format:custom="$S"');; \<br>
     Log3 $NAME, 1, "Actor: $actor, Reading $reading" }
    </code><br><br>
    </ul>

    <i>Benachrichtigen &uuml;ber M&uuml;llabholung</i><br><br>
    <ul>
    Nehmen wir an der <code>GarbageCalendar</code> beinhaltet alle Termine der
    M&uuml;llabholung mit der Art des M&uuml;lls innerhalb der Zusammenfassung (summary).
    Das folgende notify kann zur Benachrichtigung &uuml;ber die M&uuml;llabholung
    benutzt werden:<br><br><code>
    define GarbageCollectionNotifier notify GarbageCalendar:alarm:.* { \<br>
      my $uid= "$EVTPART1";; \<br>
      my $summary= fhem('get GarbageCalendar events filter:uid=="'.$uid.'" format:custom="$S"');; \<br>
      # e.g. mail $summary to someone \<br>
    }</code><br><br>

    Wenn der M&uuml;llkalender keine Erinnerungen hat, dann kannst du sie auf
    auf einen Tag vor das Datum der Abholung setzen:<br><br><code>
    attr GarbageCalendar onCreateEvent { $e->{alarm}= $e->{start}-86400 }
    </code><br><br>
    Das folgende realisiert eine HTML Anzeige f&uuml;r die n&aauml;chsten Abholungstermine:<br><br>
    <code>{ CalendarEventsAsHtml('GarbageCalendar','format:text filter:mode=~"alarm|start"') }</code>
    <br>
    </ul>



  </ul>

  <b>Eingebettetes HTML</b>
  <ul><br>
    Das Modul definiert zwei Funktionen an, die HTML-Code zur&uuml;ckliefern.<br><br>
    <code>CalendarAsHtml(&lt;name&gt;,&lt;parameter&gt;)</code> liefert eine Liste von Kalendereintr&auml;gen als
    HTML zur&uuml;ck. <code>&lt;name&gt;</code> ist der Name des Kalender-Devices; <code>&lt;parameter&gt;</code>
    w&uuml;rdest Du nach <code>get &lt;name&gt; text ...</code> schreiben. <b>Diese Funktion ist veraltert
    und sollte nicht mehr genutzt werden!</b>.
    <br><br>
    <b>Beispiel</b>
    <code>define MyCalendarWeblink weblink htmlCode { CalendarAsHtml("MyCalendar","next 3") }</code>
    <br><br>
    <code>CalendarEventsAsHtml(&lt;name&gt;,&lt;parameter&gt;)</code> liefert eine Liste von Kalender-Events
    zur&uuml;ck; zu <code>name</code> und <code>parameters</code> siehe oben.
     <br><br>
     <b>Beispiel</b>
    <br><br>
    <code>define MyCalendarWeblink weblink htmlCode
    { CalendarEventsAsHtml('F','format:custom="$T1 $D $S" timeFormat:"%d.%m" series:next=3') }</code>
    <br><br>
    Empfehlung: Benutze einfache Anf&uuml;hrungszeichen als &auml;u&szlig;ere Anf&uuml;hrungszeichen.
  <br><br>
  </ul>
</ul>

=end html_DE
=cut
