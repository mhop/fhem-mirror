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


##############################################

package main;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

#
# *** Potential isses:
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
# high load when parsing
# http://forum.fhem.de/index.php/topic,40783.0.html


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

sub ts($$) {
  my ($self,$tm)= @_;
  return "" unless($tm);
  my ($second,$minute,$hour,$day,$month,$year,$wday,$yday,$isdst)= localtime($tm);
  return sprintf("%02d.%02d.%4d %02d:%02d:%02d", $day,$month+1,$year+1900,$hour,$minute,$second);
}

sub ts0($$) {
  my ($self,$tm)= @_;
  return "" unless($tm);
  my ($second,$minute,$hour,$day,$month,$year,$wday,$yday,$isdst)= localtime($tm);
  return sprintf("%02d.%02d.%2d %02d:%02d", $day,$month+1,$year-100,$hour,$minute);
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
  return 0 unless(defined($self->{end}));
  return $self->{end}<= $t ? 1 : 0;
}

sub nextTime {
  my ($self,$t) = @_;
  my @times= ( );
  push @times, $self->{start} if(defined($self->{start}));
  push @times, $self->{end} if(defined($self->{end}));
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
  #main::Debug "new ICal::Entry $type";
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
  return $self->state() ~~ @statesObsolete ? 1 : 0;
}

sub hasChanged($) {
  my($self)= @_;
  # VEVENT records in these states have changed
  my @statesChanged= qw/new changed-new modified-new/;
  return $self->state() ~~ @statesChanged ? 1 : 0;
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
  #main::Debug "line=\'$line\'";
  # for DTSTART, DTEND there are several variants:
  #    DTSTART;TZID=Europe/Berlin:20140205T183600
  #  * DTSTART;TZID="(UTC+01:00) Amsterdam, Berlin, Bern, Rome, Stockholm, Vienna":20140904T180000
  #    DTSTART:20140211T212000Z
  #    DTSTART;VALUE=DATE:20130619
  my ($key,$parts,$parameter);
  if($line =~ /^([\w\d\-]+)(;(.*))?:(.*)$/) {
    $key= $1;
    $parts= $3 // "";
    $parameter= $4 // "";
  } else {
    return;
  }
  return unless($key);
  #main::Debug "addproperty for key $key";

  # ignore some properties
  # commented out: it is faster to add the property than to do the check
  # return if(($key eq "ATTENDEE") or ($key eq "TRANSP") or ($key eq "STATUS"));
  return if(substr($key,0,2) eq "^X-");

  if(($key eq "RDATE") or ($key eq "EXDATE")) {
        #main::Debug "addproperty for dates";
        # handle multiple properties
        my @values;
        @values= @{$self->values($key)} if($self->hasKey($key));
        push @values, $parameter;
        #main::Debug "addproperty pushed parameter $parameter to key $key";
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
  my @ical= split /(?>\r\n|[\r\n])/, $ics;
  return $self->parseSub(0, \@ical);
}

sub parseSub($$$) {
  my ($self,$ln,$icalref)= @_;
  my $len= scalar @$icalref;
  #main::Debug "lines= $len";
  #main::Debug "ENTER @ $ln";
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
    #main::Debug "$ln: $line";
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
  #main::Debug "BACK";
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
sub tm($$) {
  my ($self, $t)= @_;
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
  #main::Debug "Adding $n months to $day.$month.$year $hour:$minute:$second= " . ts($tm);
  $month+= $n;
  $year+= int($month / 12);
  $month %= 12;
  #main::Debug " gives $day.$month.$year $hour:$minute:$second= " . ts(main::fhemTimeLocal($second,$minute,$hour,$day,$month,$year));
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
	#main::Debug "lByDay = $lByDay, lByDayLength = $lByDayLength, lDay = $lDay, lDayInterval = $lDayInterval, lDayOfWeek = $lDayOfWeek, lFirstOfNextMonth = $lFirstOfNextMonth, lNextYear = $lNextYear, lNextMonth = $lNextMonth";
	#main::Debug main::FmtDateTime($lNewTime);

	return $lNewTime;
}

use constant eventsLimitMinus => -34560000; # -400d
use constant eventsLimitPlus  =>  34560000; # +400d

sub addEventLimited($$$) {
    my ($self, $t, $event)= @_;

    return -1 if($event->start()< $t+eventsLimitMinus);
    return  1 if($event->start()> $t+eventsLimitPlus);
    #main::Debug "  addEvent: " . $event->asFull();
    $self->addEvent($event);
    return  0;

}

sub createSingleEvent($$$) {

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

sub createEvents($$$%) {
  my ($self, $t, $onCreateEvent, %vevents)= @_;

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
            if(not($k ~~ @keywords)) {
                main::Log3 undef, 2, "Calendar: keyword $k in RRULE $rrule is not supported";
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
                my $event= $self->createSingleEvent($self->tm($rdate), $onCreateEvent);
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
                    # and return if we exceed storage limit
                    $event->setNote("RDATE: $rdate");
                    $self->addEventLimited($t, $event);
                }
            }
        }

        #
        # now we build the series
        #

        # first event in the series
        my $event= $self->createSingleEvent(undef, $onCreateEvent);
        my $n= 0;


        while(1) {
            my $skip= 0;

            # check if superseded by out-of-series event
            if($self->hasReferences()) {
                foreach my $id (@{$self->references()}) {
                    my $vevent= $vevents{$id};
                    my $recurrenceid= $vevent->value("RECURRENCE-ID");
                    my $originalstart= $vevent->tm($recurrenceid);
                    if($originalstart == $event->start()) {
                        $event->setNote("RECURRENCE-ID: $recurrenceid");
                        $self->addSkippedEvent($event);
                        $skip++;
                        last;
                    }
                }
            }

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
            if($self->hasKey('EXDATE')) {
                foreach my $exdate (@{$self->values("EXDATE")}) {
                    if($self->tm($exdate) == $event->start()) {
                        $event->setNote("EXDATE: $exdate");
                        $self->addSkippedEvent($event);
                        $skip++;
                        last;
                    }
                }
            }

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

            return if($event->{start} > $until); # return if we are after end of series
            if(!$skip) {
                # add event
                # and return if we exceed storage limit
                return if($self->addEventLimited($t, $event) > 0);
            }
            $n++;
            return if($n>= $count); # return if we exceeded occurances

            # advance to next occurence
            my  $nextstart = $event->{start};
            if($freq eq "SECONDLY") {
                $nextstart = plusNSeconds($nextstart, 1, $interval);
            } elsif($freq eq "MINUTELY") {
                $nextstart = plusNSeconds($nextstart, 60, $interval);
            } elsif($freq eq "HOURLY") {
                $nextstart = plusNSeconds($nextstart, 60*60, $interval);
            } elsif($freq  eq "DAILY") {
                $nextstart = plusNSeconds($nextstart, 24*60*60, $interval);
            } elsif($freq  eq "WEEKLY") {
                # special handling for WEEKLY and BYDAY
                #main::Debug "weekly event, BYDAY= $byday";
                if($byday ne "") {
                    # BYDAY with prefix (e.g. -1SU or 2MO) is not recognized
                    my @bydays= split(',', $byday);
                    # we skip interval-1 weeks
                    $nextstart = plusNSeconds($nextstart, 7*24*60*60, $interval-1);
                    my ($msec, $mmin, $mhour, $mday, $mmon, $myear, $mwday, $yday, $isdat);
                    my $preventloop = 0;
                    do {
                        $nextstart = plusNSeconds($nextstart, 24*60*60, 1); # forward day by day
                        ($msec, $mmin, $mhour, $mday, $mmon, $myear, $mwday, $yday, $isdat) =
                            localtime($nextstart);
                        #main::Debug "Skip to: start " . $event->ts($nextstart) . " = " . $weekdays[$mwday];
                        $preventloop++;
                        if($preventloop > 7) {
                            main::Log3 undef, 2,
                                "Calendar: something is wrong for RRULE $rrule in " .
                                $self->asString();
                            last;
                        }
                        #main::Debug "weekday= " . $weekdays[$mwday] . "($mwday), smartmatch " . join(" ",@bydays) ."= " . ($weekdays[$mwday] ~~ @bydays ? "yes" : "no");
                    } until($weekdays[$mwday] ~~ @bydays);
                }
                else {
                    # default WEEKLY handling
                    $nextstart = plusNSeconds($nextstart, 7*24*60*60, $interval);
                }
            } elsif($freq eq "MONTHLY") {
				if ( $byday ne "" ) {
					$nextstart = getNextMonthlyDateByDay( $nextstart, $byday, $interval );
				}
				else {
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
            $event= $self->createSingleEvent($nextstart, $onCreateEvent);

        }


  } else {
        #
        # single event
        #
        my $event= $self->createSingleEvent(undef, $onCreateEvent);
        $self->addEventLimited($t, $event);
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
  $hash->{AttrList}=  "update:sync,async,none removevcalendar:0,1 cutoffOlderThan hideOlderThan hideLaterThan onCreateEvent SSLVerify:0,1 $readingFnAttributes";
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

  $interval= $a[5] if($#a==5);

  $hash->{".fhem"}{type}= $type;
  $hash->{".fhem"}{url}= $url;
  $hash->{".fhem"}{interval}= $interval;
  $hash->{".fhem"}{lastid}= 0;
  $hash->{".fhem"}{vevents}= {};
  $hash->{".fhem"}{nxtUpdtTs}= 0;

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
    my @args= qw/none sync async/;
    return "Argument for update must be one of " . join(" ", @args) .
      " instead of $arg." unless($arg ~~ @args);
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
  my $delay= 10+int(rand(20));

  # delay removed until further notice
  $delay= 2;

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
sub Calendar_Get($@) {

  my ($hash, @a) = @_;

  my $t= time();

  my $eventsObj= $hash->{".fhem"}{events};
  my @events;

  my $cmd= $a[1];
  $cmd= "?" unless($cmd);


  if($cmd eq "update") {
    # this is the same as set update for convenience
    Calendar_DisarmTimer($hash);
    Calendar_GetUpdate($hash, $t, 0);
    return undef;
  }

  if($cmd eq "reload") {
    # this is the same as set reload for convenience
     Calendar_DisarmTimer($hash);
     Calendar_GetUpdate($hash, $t, 1); # remove all events before update
     return undef;
  }

  if($cmd eq "events") {

    # see https://forum.fhem.de/index.php/topic,46608.msg397309.html#msg397309 for ideas
    # get myCalendar events filter:mode=alarm|start|upcoming format=custom:{ sprintf("...") } select:series=next,max=8,from=-3d,to=10d
    # attr myCalendar defaultFormat <format>

    my @texts;
    my @events= Calendar_GetEvents($hash, $t, undef, undef);
    foreach my $event (@events) {
        push @texts, $event->asFull();
    }
    return "" if($#texts<0);
    return join("\n", @texts);

  }

  my @cmds2= qw/text full summary location description categories alarm start end uid debug/;
  if($cmd ~~ @cmds2) {

    return "argument is missing" if($#a < 2);
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
        $filterref= undef;
    } elsif($filter eq "next") {
        $filterref= \&filter_notend;
        $param= { }; # reference to anonymous (unnamed) empty hash, thus $ in $param
    } else { # everything else is interpreted as uid
        $filterref= \&filter_uid;
        $param= $a[2];
    }

    @events= Calendar_GetEvents($hash, $t, $filterref, $param);

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
    return "Unknown argument $cmd, choose one of update:noArg reload:noArg find text full summary location description categories alarm start end vcalendar:noArg vevents:noArg";
  }

}

###################################
sub Calendar_Wakeup($$) {

  my ($hash, $removeall) = @_;

  Log3 $hash, 4, "Calendar " . $hash->{NAME} . ": Wakeup";

  my $t= time(); # baseline
  # we could arrive here 1 second before nextWakeTs for unknown reasons
  use constant delta => 5; # avoid waking up again in a few seconds
  if($t>= $hash->{".fhem"}{nxtUpdtTs} - delta) {
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
        $nt= $et if(defined($et) && ($et< $nt) && ($et > $t));
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
sub Calendar_GetSecondsFromTimeSpec($) {

  my ($tspec) = @_;

  # days
  if($tspec =~ m/^([0-9]+)d$/) {
    return ("", $1*86400);
  }

  # seconds
  if($tspec =~ m/^[0-9]+s?$/) {
    return ("", $tspec);
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

sub filter_end($) {
    my ($event)= @_;
    return $event->getMode() eq "end" ? 1 : 0;
}

sub filter_notend($) {
    my ($event)= @_;
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
    #foreach my $u (@uids) { main::Debug "UID $u"; }
    my $uid= $event->uid();
    #main::Debug "SUCHE $uid";
    #main::Debug "GREP: " . grep(/^$uid$/, @uids);
    return grep(/^$uid$/, @uids);
}




###################################
sub Calendar_GetEvents($$$$) {

    my ($hash, $t, $filterref, $param)= @_;
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
            if(defined($filterref)) {
                next unless(&$filterref($event, $param));
            }
            if(defined($t1)) { next if(defined($event->end()) && $event->end() < $t1); }
            if(defined($t2)) { next if(defined($event->start()) && $event->start() > $t2); }
            push @result, $event;
        }
    }
    return sort { $a->start() <=> $b->start() } @result;

}

###################################
sub Calendar_GetUpdate($$$) {

  my ($hash, $t, $removeall) = @_;
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
  if(AttrVal($hash->{NAME},"update","") eq "none") {
    Calendar_CheckTimes($hash, $t);
    Calendar_RearmTimer($hash, $t);
    return;
  }

  Log3 $hash, 4, "Calendar $name: Updating...";
  my $type = $hash->{".fhem"}{type};
  my $url= $hash->{".fhem"}{url};

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

    HttpUtils_NonblockingGet({
      url => $url,
      hideurl => 1,
      noshutdown => 1,
      hash => $hash,
      timeout => 30,
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

  if(exists($hash->{".fhem"}{subprocess})) {
      Log3 $hash, 2, "Calendar $name: update in progress, process aborted.";
      return 0;
  }

  # not for the developer:
  # we must be sure that code that starts here ends with Calendar_CheckAndRearm()
  # no matter what branch is taken in the following

  delete($hash->{".fhem"}{iCalendar});

  if($errmsg) {
    Log3 $name, 1, "Calendar $name: retrieval failed with error message $errmsg";
    readingsSingleUpdate($hash, "state", "error ($errmsg)", 1);
  } else {
    readingsSingleUpdate($hash, "state", "retrieved", 1);
  }

  if($errmsg or !defined($ics) or ("$ics" eq "") ) {
    Log3 $hash, 1, "Calendar $name: retrieved no or empty data";
    readingsSingleUpdate($hash, "state", "error (no or empty data)", 1);
    Calendar_CheckAndRearm($hash, $t);
  } else {
    $hash->{".fhem"}{iCalendar}= $ics; # the plain text iCalendar
    $hash->{".fhem"}{t}= $t;
    $hash->{".fhem"}{removeall}= $removeall;
    if(AttrVal($name, "update", "sync") eq "async") {
      Calendar_AsynchronousUpdateCalendar($hash);
    } else {
      Calendar_SynchronousUpdateCalendar($hash);
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

  #main::Debug "Calendar $name: parsing data";
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

  # *******************************
  # *** Step 1 Digest Parser Result
  # *******************************

  my $name= $hash->{NAME};
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
    my $cutoffOlderThan = AttrVal($name, "cutoffOlderThan", undef);
    my $cutoffT= 0;
    my $cutoff;
    if(defined($cutoffOlderThan)) {
        ($error, $cutoffT)= Calendar_GetSecondsFromTimeSpec($cutoffOlderThan);
        if($error) {
            Log3 $hash, 2, "$name: attribute cutoffOlderThan: $error";
        };
        $cutoff= $t- $cutoffT;
    }

  foreach my $v (grep { $_->{type} eq "VEVENT" } @{$root->{entries}}) {

        # totally skip outdated calendar entries
	next if(
          defined($cutoffOlderThan) &&
          $v->hasKey("DTEND") &&
          $v->tm($v->value("DTEND")) < $cutoff &&
          !$v->hasKey("RRULE")
        );

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
                if($v0->sameValue($v, "LAST-MODIFIED")) {
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

  foreach my $id (keys %vevents) {
        my $v= $vevents{$id};
        if($v->isObsolete()) {
            $v->clearEvents();
            next;
        }

        my $onCreateEvent= AttrVal($name, "onCreateEvent", undef);
        if($v->hasChanged() or !$v->numEvents()) {
            #main::Debug "createEvents";
            $v->createEvents($t, $onCreateEvent, %vevents);
        }

  }

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

    Log3 $hash, 4, "Calendar " . $hash->{NAME} . ": Checking times...";

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
    #    main::Debug $event->asFull();
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
    rbu($hash, "modeUpcoming", es(@upcoming));
    rbu($hash, "modeAlarm", es(@alarm));
    rbu($hash, "modeAlarmed", es(@alarmed));
    rbu($hash, "modeAlarmOrStart", es(@alarm,@start));
    rbu($hash, "modeChanged", es(@changed));
    rbu($hash, "modeStart", es(@start));
    rbu($hash, "modeStarted", es(@started));
    rbu($hash, "modeEnd", es(@end));
    rbu($hash, "modeEnded", es(@ended));
    readingsBulkUpdate($hash, "state", "triggered");
    # DoTrigger, because sub is called by a timer instead of dispatch
    readingsEndUpdate($hash, 1);

}


#####################################

# filter:next count:3
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
    (use <code>cpan -i IO::Socket::SSL</code>).<br><br>

    Note for users of Google Calendar: You can literally use the private ICal URL from your Google Calendar.
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
  <b>Set </b><br><br>
  <ul>
    <code>set &lt;name&gt; update</code><br>
    Forces the retrieval of the calendar from the URL. The next automatic retrieval is scheduled to occur <code>interval</code> seconds later.<br><br>

    <code>set &lt;name&gt; reload</code><br>
    Same as <code>update</code> but all calendar events are removed first.<br><br>

  </ul>
  <br>


  <a name="Calendarget"></a>
  <b>Get</b><br><br>
  <ul>
    <code>get &lt;name&gt; update</code><br>
    Same as  <code>set &lt;name&gt; update</code><br><br>

    <code>get &lt;name&gt; reload</code><br>
    Same as  <code>set &lt;name&gt; update</code><br><br>

    <code>get &lt;name&gt; &lt;format&gt; &lt;filter&gt; [&lt;max&gt;]</code><br>
    Returns, line by line, information on the calendar events in the calendar &lt;name&gt;. The content depends on the
    &lt;format&gt specifier:<br><br>

    <table>
    <tr><th>&lt;format&gt;</th><th>content</th></tr>
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

    The &lt;filter&gt; specifier determines the selected subset of calendar events:<br><br>

    <table>
    <tr><th>&lt;filter&gt;</th><th>selection</th></tr>
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

    <code>get &lt;name&gt; find &lt;regexp&gt;</code><br>
    Returns, line by line, the UIDs of all calendar events whose summary matches the regular expression
    &lt;regexp&gt;.<br><br>

    <code>get &lt;name&gt; vcalendar</code><br>
    Returns the calendar in ICal format as retrieved from the source.<br><br>

    <code>get &lt;name&gt; vevents</code><br>
    Returns a list of all VEVENT entries in the calendar with additional information for
    debugging. Only properties that have been kept during processing of the source
    are shown. The list of calendar events created from each VEVENT entry is shown as well
    as the list of calendar events that have been omitted.

  </ul>

  <br>

  <a name="Calendarattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>update sync|async|none</code><br>
        If this attribute is not set or if it is set to <code>sync</code>, the processing of
        the calendar is done in the foreground. Large calendars will block FHEM on slow
        systems. If this attribute is set to <code>async</code>, the processing is done in the
        background and FHEM will not block during updates. If this attribute is set to
        <code>none</code>, the calendar will not be updated at all.
        </li><p>

    <li><code>removevcalendar 0|1</code><br>
        If this attribute is set to 1, the vCalendar will be discarded after the processing to reduce the memory consumption of the module.
        A retrieval via <code>get &lt;name&gt; vcalendar</code> is then no longer possible.
        </li><p>

    <li><code>hideOlderThan &lt;timespec&gt;</code><br>
        <code>hideLaterThan &lt;timespec&gt;</code><br><p>

        These attributes limit the list of events shown by
        <code>get &lt;name&gt; full|debug|text|summary|location|alarm|start|end ...</code>.<p>

        The time is specified relative to the current time t. If hideOlderThan is set,
        calendar events that ended before t-hideOlderThan are not shown. If hideLaterThan is
        set, calendar events that will start after t+hideLaterThan are not shown.<p>

        Please note that an action triggered by a change to mode "end" cannot access the calendar event
        if you set hideOlderThan to 0 because the calendar event will already be hidden at that time. Better set
        hideOlderThan to 10.<p>

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
        <p>

    <li><code>cutoffOlderThan &lt;timespec&gt;</code><br>
        This attribute cuts off all non-recurring calendar events that ended a timespan cutoffOlderThan
        before the last update of the calendar. The purpose of setting this attribute is to save memory.
        Such calendar events cannot be accessed at all from FHEM. Calendar events are not cut off if
        they are recurring or if they have no end time (DTEND).
    </li><p>

    <li><code>onCreateEvent &lt;perl-code&gt;</code><br>

        This attribute allows to run the Perl code &lt;perl-code&gt; for every
        calendar event that is created. See section <a href="#CalendarPlugIns">Plug-ins</a> below.
    </li><p>

    <li><code>SSLVerify</code><br>

        This attribute sets the verification mode for the peer certificate for connections secured by
        SSL. Set attribute either to 0 for SSL_VERIFY_NONE (no certificate verification) or
        to 1 for SSL_VERIFY_PEER (certificate verification). Disabling verification is useful
        for local calendar installations (e.g. OwnCloud, NextCloud) without valid SSL certificate.
    </li><p>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <b>Description</b>
  <ul>
  <br>
  A calendar is a set of calendar events. The calendar events are
  fetched from the source calendar at the given URL on a regular basis.<p>

  A calendar event has a summary (usually the title shown in a visual
  representation of the source calendar), a start time, an end time, and zero, one or more alarm times. In case of multiple alarm times for a calendar event, only the
  earliest alarm time is kept.<p>

  Recurring calendar events (series) are currently supported to an extent:
  FREQ INTERVAL UNTIL COUNT are interpreted, BYMONTHDAY BYMONTH WKST
  are recognized but not interpreted. BYDAY is correctly interpreted for weekly and monthly events.
  The module will get it most likely wrong
  if you have recurring calendar events with unrecognized or uninterpreted keywords.
  Out-of-order events and events excluded from a series (EXDATE) are handled.
  <p>

  Calendar events are created when FHEM is started or when the respective entry in the source
  calendar has changed and the calendar is updated or when the calendar is reloaded with
  <code>get &lt;name&gt; reload</code>.
  Only calendar events within &pm;400 days around the event creation time are created. Consider
  reloading the calendar from time to time to avoid running out of upcoming events. You can use something like <code>define reloadCalendar at +*240:00:00 set MyCalendar reload</code> for that purpose.<p>

  Some dumb calendars do not use LAST-MODIFIED. This may result in modifications in the source calendar
  go unnoticed. Reload the calendar if you experience this issue.<p>

  A calendar event is identified by its UID. The UID is taken from the source calendar.
  All events in a series including out-of-order events habe the same UID.
  All non-alphanumerical characters
  are stripped off the original UID to make your life easier.<p>

  A calendar event can be in one of the following modes:
  <table>
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
  </ul>
  <p>

  For recurring events, usually several calendar events exists with the same UID. In such a case,
  the UID is only shown in the mode reading for the most interesting mode. The most
  interesting mode is the first applicable of start, alarm, upcoming, end.<p>

  In particular, you will never see the UID of a series in modeEnd or modeEnded as long as the series
  has not yet ended - the UID will be in one of the other mode... readings. This means that you better
  do not trigger FHEM events for series based on mode... readings. See below for a recommendation.<p>

  <b>Events</b>
  <ul><br>
  When the calendar was reloaded or updated or when an alarm, start or end time was reached, one
  FHEM event is created:<p>

  <code>triggered</code><br><br>

  When you receive this event, you can rely on the calendar's readings being in a consistent and
  most recent state.<p>


  When a calendar event has changed, two FHEM events are created:<p>

  <code>changed: UID &lt;mode&gt;</code><br>
  <code>&lt;mode&gt;: UID</code><br><br>

  &lt;mode&gt; is the current mode of the calendar event after the change. Note: there is a
  colon followed by a single space in the FHEM event specification.<p>

  The recommended way of reacting on mode changes of calendar events is to get notified
  on the aforementioned FHEM events and do not check for the FHEM events triggered
  by a change of a mode reading.
  <p>
  </ul>

  <a name="CalendarPlugIns"></a>
  <b>Plug-ins</b>
  <ul>
  <br>
  This is experimental. Use with caution.<p>

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
  </ul>
  <br><br>

  <b>Usage scenarios</b>
  <ul><br><br>
    <i>Show all calendar events with details</i><br><br>
    <ul>
    <code>
    get MyCalendar full all<br>
    2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom     alarm 31.05.2012 17:00:00 07.06.2012 16:30:00-07.06.2012 18:00:00 Erna for coffee<br>
    992hydf4y44awer5466lhfdsr&shy;gl7tin6b6mckf8glmhui4&shy;googlecom  upcoming                     08.06.2012 00:00:00-09.06.2012 00:00:00 Vacation
    </code><br><br>
    </ul>

    <i>Show calendar events in your photo frame</i><br><br>
    <ul>
    Put a line in the <a href="#RSSlayout">layout description</a> to show calendar events in alarm or start mode:<br><br>
    <code>text 20 60 { fhem("get MyCalendar text next 2") }</code><br><br>
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
    define SwitchActorOn  notify MyCalendar:start:.* {
                my $reading="$EVTPART0";;
                my $uid= "$EVTPART1";;
                my $actor= fhem("get MyCalendar summary $uid");;
                if(defined $actor) {
                   fhem("set $actor on")
                }
    }<br><br>
    define SwitchActorOff  notify MyCalendar:end:.* {
                my $reading="$EVTPART0";;
                my $uid= "$EVTPART1";;
                my $actor= fhem("get MyCalendar summary $uid");;
                if(defined $actor) {
                   fhem("set $actor off")
                }
    }
    </code><br><br>
    You can also do some logging:<br><br>
    <code>
    define LogActors notify MyCalendar:(start|end):.* { my $reading= "$EVTPART0";; my $uid= "$EVTPART1";; my $actor= fhem("get MyCalendar summary $uid");; Log 3 $NAME, 1, "Actor: $actor, Reading $reading" }
    </code><br><br>
    </ul>


  </ul>


  <b>Embedded HTML</b>
  <ul><br>
  The module provides an additional function <code>CalendarAsHtml(&lt;name&gt;,&lt;options&gt;)</code>. It
  returns the HTML code for a list of calendar events. <code>&lt;name&gt;</code> is the name of the
  Calendar device and <code>&lt;options&gt;</code> is what you would write after <code>get &lt;name&gt; text ...</code>.
  <br><br>
  Example: <code>define MyCalendarWeblink weblink htmlCode { CalendarAsHtml("MyCalendar","next 3") }</code>
  <br><br>
  This is a rudimentary function which might be extended in a future version.
  <p>
  </ul>


</ul>


=end html
=begin html_DE

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
    Definiert ein Kalender-Device.<br><br>

    Ein Kalender-Device ermittelt (Serien-) Termine aus einem Quell-Kalender. Dieser kann eine URL oder eine Datei sein.
	Die Datei muss im iCal-Format vorliegen.<br><br>

    Beginnt die URL mit <code>https://</code>, muss das Perl-Modul IO::Socket::SSL installiert sein
    (use <code>cpan -i IO::Socket::SSL</code>).<br><br>

    Hinweis f&uuml;r Nutzer des Google-Kalenders: Du kann direkt die private iCal-URL des Google Kalender nutzen.

    Sollte Deine Google-Kalender-URL mit <code>https://</code> beginnen und das Perl-Modul IO::Socket::SSL ist nicht auf Deinem Systeme installiert,
	kannst Du in der URL  <code>https://</code> durch <code>http://</code> ersetzen, falls keine automatische Umleitung auf die <code>https://</code> URL erfolgt.
    Solltest Du unsicher sein, ob dies der Fall ist, &uuml;berpr&uuml;fe es bitte zuerst mit Deinem Browser.<br><br>

    Der optionale Parameter <code>interval</code> bestimmt die Zeit in Sekunden zwischen den Updates. Default-Wert ist 3600 (1 Stunde).<br><br>

    Beispiele:
    <pre>
      define MeinKalender Calendar ical url https://www.google.com&shy;/calendar/ical/john.doe%40example.com&shy;/private-foo4711/basic.ics
      define DeinKalender Calendar ical url http://www.google.com&shy;/calendar/ical/jane.doe%40example.com&shy;/private-bar0815/basic.ics 86400
      define IrgendeinKalender Calendar ical file /home/johndoe/calendar.ics
      </pre>
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

    <code>get &lt;name&gt; &lt;format&gt; &lt;filter&gt; [&lt;max&gt;]</code><br>
    Die Termine f&uuml;r den Kalender &lt;name&gt; werden Zeile f&uuml;r Zeile ausgegeben.<br><br>

	Folgende Selektoren/Filter stehen zur Verf&uuml;gung:<br><br>

	Der Selektor &lt;format&gt legt den zur&uuml;ckgegeben Inhalt fest:<br><br>

    <table>
    <tr><th>&lt;format&gt;</th><th>Inhalt</th></tr>
    <tr><td>uid</td><td>UID des Termins</td></tr>
    <tr><td>text</td><td>Benutzer-/Monitorfreundliche Textausgabe.</td></tr>
    <tr><td>summary</td><td>&Uuml;bersicht (Betreff, Titel)</td></tr>
    <tr><td>location</td><td>Ort</td></tr>
    <tr><td>categories</td><td>Kategorien</td></tr>
    <tr><td>alarm</td><td>Alarmzeit</td></tr>
    <tr><td>start</td><td>Startzeit</td></tr>
    <tr><td>end</td><td>Endezeit</td></tr>
    <tr><td>full</td><td>Vollst&auml;ndiger Status</td></tr>
    <tr><td>debug</td><td>wie &lt;full&gt; mit zus&auml;tzlichen Informationen zur Fehlersuche</td></tr>
    </table><br>

    Der Filter &lt;filter&gt; grenzt die Termine ein:<br><br>

    <table>
    <tr><th>&lt;filter&gt;</th><th>Inhalt</th></tr>
    <tr><td>mode=&lt;regex&gt;</td><td>alle Termine, deren Modus durch den regul&auml;ren Ausdruck &lt;regex&gt beschrieben werden.</td></tr>
    <tr><td>&lt;mode&gt;</td><td>alle Termine mit Modus &lt;mode&gt.</td></tr>
    <tr><td>uid=&lt;regex&gt;</td><td>Alle Termine, deren UIDs durch den regul&auml;ren Ausdruck &lt;regex&gt beschrieben werden.</td></tr>
    <tr><td>&lt;uid&gt;</td><td>Alle Termine mit der UID &lt;uid&gt;</td></tr>
    <tr><td>&lt;reading&gt;</td><td>Alle Termine die im Reading &lt;reading&gt; aufgelistet werden (modeAlarm, modeAlarmed, modeStart, etc.)
	- dieser Filter ist abgek&uuml;ndigt und steht in einer zuk&uuml;nftigen Version nicht mehr zur Verf&uuml;gung, bitte mode=&lt;regex&gt; benutzen.</td></tr>
    <tr><td>all</td><td>Alle Termine (vergangene, aktuelle und zuk&uuml;nftige)</td></tr>
    <tr><td>next</td><td>Alle Termine, die noch nicht beendet sind. Bei Serienterminen der erste Termin. Benutzer-/Monitorfreundliche Textausgabe</td></tr>
    </table><br>

    Die Filter <code>mode=&lt;regex&gt;</code> und <code>uid=&lt;regex&gt;</code> sollten den Filtern
    <code>&lt;mode&gt;</code> und <code>&lt;uid&gt;</code> vorgezogen werden.<br><br>

    Der optionale Parameter <code>&lt;max&gt;</code> schr&auml;nkt die Anzahl der zur&uuml;ckgegebenen Zeilen ein.<br><br>

    Bitte beachte die Attribute <code>hideOlderThan</code> und
    <code>hideLaterThan</code> f&uuml;r die Seletion von Terminen in einem bestimmten Zeitfenster.
    Bitte ber&uuml;cksichtige, dass das globale &pm;400 Tageslimit gilt .<br><br>

    Beispiele:<br>
    <code>get MyCalendar text next</code><br>
    <code>get MyCalendar summary uid:435kjhk435googlecom 1</code><br>
    <code>get MyCalendar summary 435kjhk435googlecom 1</code><br>
    <code>get MyCalendar full all</code><br>
    <code>get MyCalendar text mode=alarm|start</code><br>
    <code>get MyCalendar text uid=.*6286.*</code><br>
    <br>

    <code>get &lt;name&gt; find &lt;regexp&gt;</code><br>
	Gibt Zeile f&uuml;r Zeile die UIDs aller Termine deren Zusammenfassungen durch den regul&auml;ren Ausdruck &lt;regex&gt beschrieben werden.
    &lt;regexp&gt;.<br><br>

    <code>get &lt;name&gt; vcalendar</code><br>
    Gibt den Kalender ICal-Format, so wie er von der Quelle gelesen wurde, zur&uuml;ck.<br><br>

    <code>get &lt;name&gt; vevents</code><br>
    Gibt eine Liste aller VEVENT-Eintr&auml;ge des Kalenders &lt;name&gt;, angereichert um Ausgaben f&uuml;r die Fehlersuche, zur&uuml;ck.
    Es werden nur Eigenschaften angezeigt, die w&auml;hrend der Programmausf&uuml;hrung beibehalten wurden. Es wird sowohl die Liste
	der Termine, die von jedem VEVENT-Eintrag erzeugt wurden, als auch die Liste der ausgelassenen Termine angezeigt.

  </ul>

  <br>

  <a name="Calendarattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>update sync|async|none</code><br>
        Wenn dieses Attribut nicht gesetzt ist oder wenn es auf <code>sync</code> gesetzt ist,
        findet die Verarbeitung des Kalenders im Vordergrund statt. Gro&szlig;e Kalender werden FHEM
        auf langsamen Systemen blockieren. Wenn das Attribut auf <code>async</code> gesetzt ist,
        findet die Verarbeitung im Hintergrund statt, und FHEM wird w&auml;hrend der Verarbeitung
        nicht blockieren. Wenn dieses Attribut auf <code>none</code> gesetzt ist, wird der
        Kalender &uuml;berhaupt nicht aktualisiert.
        </li><p>

    <li><code>removevcalendar 0|1</code><br>
		Wenn dieses Attribut auf 1 gesetzt ist, wird der vCalendar nach der Verarbeitung verworfen,
		gleichzeitig reduziert sich der Speicherverbrauch des Moduls.
		Ein Abruf &uuml;ber <code>get &lt;name&gt; vcalendar</code> ist dann nicht mehr m&ouml;glich.
        </li><p>

    <li><code>hideOlderThan &lt;timespec&gt;</code><br>
        <code>hideLaterThan &lt;timespec&gt;</code><br><p>

		Dieses Attribut grenzt die Liste der durch <code>get &lt;name&gt; full|debug|text|summary|location|alarm|start|end ...</code> gezeigten Termine ein.

        Die Zeit wird relativ zur aktuellen Zeit t angegeben.<br>
		Wenn &lt;hideOlderThan&gt; gesetzt ist, werden Termine, die vor &lt;t-hideOlderThan&gt; enden, ingnoriert.<br>
        Wenn &lt;hideLaterThan&gt; gesetzt ist, werden Termine, die nach &lt;t+hideLaterThan&gt; anfangen, ignoriert.<p>

        Bitte beachten, dass eine Aktion, die durch einen Wechsel in den Modus "end" ausgel&ouml;st wird, nicht auf den Termin
        zugreifen kann, wenn hideOlderThan 0 ist, weil der Termin dann schon versteckt ist. Besser hideOlderThan auf 10 setzen.<p>


        <code>&lt;timespec&gt;</code> muss einem der folgenden Formate entsprechen:<br>
        <table>
        <tr><th>Format</th><th>Beschreibung</th><th>Beispiel</th></tr>
        <tr><td>SSS</td><td>Sekunden</td><td>3600</td></tr>
        <tr><td>SSSs</td><td>Sekunden</td><td>3600s</td></tr>
        <tr><td>HH:MM</td><td>Stunden:Minuten</td><td>02:30</td></tr>
        <tr><td>HH:MM:SS</td><td>Stunden:Minuten:Sekunden</td><td>00:01:30</td></tr>
        <tr><td>D:HH:MM:SS</td><td>Tage:Stunden:Minuten:Sekunden</td><td>122:10:00:00</td></tr>
        <tr><td>DDDd</td><td>Tage</td><td>100d</td></tr>
        </table></li>
        <p>

    <li><code>cutoffOlderThan &lt;timespec&gt;</code><br>
        Dieses Attribut schneidet alle nicht wiederkehrenden Termine weg, die eine Zeitspanne cutoffOlderThan
        vor der letzten Aktualisierung des Kalenders endeten. Der Zweck dieses Attributs ist es Speicher zu
        sparen. Auf solche Termine kann gar nicht mehr aus FHEM heraus zugegriffen werden. Serientermine und
        Termine ohne Endezeitpunkt (DTEND) werden nicht weggeschnitten.
    </li><p>

    <li><code>onCreateEvent &lt;perl-code&gt;</code><br>

		Dieses Attribut f&uuml;hrt ein Perlprogramm &lt;perl-code&gt; f&uuml;r jeden erzeugten Termin aus.
        Weitere Informationen unter <a href="#CalendarPlugIns">Plug-ins</a> im Text.
    </li><p>

        <li><code>SSLVerify</code><br>

        Dieses Attribut setzt die Art der &Uuml;berpr&uuml;fung des Zertifikats des Partners
        bei mit SSL gesicherten Verbindungen. Entweder auf 0 setzen f&uuml;r
        SSL_VERIFY_NONE (keine &Uuml;berpr&uuml;fung des Zertifikats) oder auf 1 f&uuml;r
        SSL_VERIFY_PEER (&Uuml;berpr&uuml;fung des Zertifikats). Die &Uuml;berpr&uuml;fung auszuschalten
        ist n&uuml;tzlich f&uuml;r lokale Kalenderinstallationen(e.g. OwnCloud, NextCloud)
        ohne g&uuml;tiges SSL-Zertifikat.
    </li><p>

<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <b>Beschreibung</b>
  <ul><br>

  Ein Kalender ist eine Menge von Terminen. Ein Termin hat eine Zusammenfassung (normalerweise der Titel, welcher im Quell-Kalender angezeigt wird), eine Startzeit, eine Endzeit und keine, eine oder mehrere Alarmzeiten. Die Termine werden
  aus dem Quellkalender ermittelt, welcher &uuml;ber die URL angegeben wird. Sollten mehrere Alarmzeiten f&uuml;r einen Termin existieren, wird nur der fr&uuml;heste Alarmzeitpunkt beibehalten. Wiederkehrende Kalendereintr&auml;ge werden in einem gewissen Umfang unterst&uuml;tzt:
  FREQ INTERVAL UNTIL COUNT werden ausgewertet, BYMONTHDAY BYMONTH WKST
  werden erkannt aber nicht ausgewertet. BYDAY wird f&uuml;r w&ouml;chentliche und monatliche Termine
  korrekt behandelt. Das Modul wird es sehr wahrscheinlich falsch machen, wenn Du wiederkehrende Termine mit unerkannten oder nicht ausgewerteten Schl&uuml;sselw&ouml;rtern hast.<p>

  Termine werden erzeugt, wenn FHEM gestartet wird oder der betreffende Eintrag im Quell-Kalender ver&auml;ndert
  wurde oder der Kalender mit <code>get &lt;name&gt; reload</code> neu geladen wird. Es werden nur Termine
  innerhalb &pm;400 Tage um die Erzeugungs des Termins herum erzeugt. Ziehe in Betracht, den Kalender von Zeit zu Zeit
  neu zu laden, um zu vermeiden, dass die k&uuml;nftigen Termine ausgehen. Du kann so etwas wie <code>define reloadCalendar at +*240:00:00 set MyCalendar reload</code> daf&uuml;r verwenden.<p>

  Manche dummen Kalender benutzen LAST-MODIFIED nicht. Das kann dazu f&uuml;hren, dass Ver&auml;nderungen im
  Quell-Kalender unbemerkt bleiben. Lade den Kalender neu, wenn Du dieses Problem hast.<p>

  Ein Termin wird durch seine UID identifiziert. Die UID wird vom Quellkalender bezogen. Um das Leben leichter zu machen, werden alle nicht-alphanumerischen Zeichen automatisch aus der UID entfernt.<p>

  Ein Termin kann sich in einem der folgenden Modi befinden:
  <table>
  <tr><td>upcoming</td><td>Weder die Alarmzeit noch die Startzeit des Kalendereintrags ist erreicht.</td></tr>
  <tr><td>alarm</td><td>Die Alarmzeit ist &uuml;berschritten, aber die Startzeit des Kalender-Ereignisses ist noch nicht erreicht.</td></tr>
  <tr><td>start</td><td>Die Startzeit ist &uuml;berschritten, aber die Ende-Zeit des Kalender-Ereignisses ist noch nicht erreicht.</td></tr>
  <tr><td>end</td><td>Die Ende-Zeit des Kalender-Ereignisses wurde &uuml;berschritten.</td></tr>
  </table><br>
  Ein Kalender-Ereignis wechselt umgehend von einem Modus zum Anderen, wenn die Zeit f&uuml;r eine &Auml;nderung erreicht wurde. Dies wird dadurch erreicht, dass auf die fr&uuml;heste zuk&uuml;nftige Zeit aller Alarme, Start- oder Endezeiten aller Kalender-Ereignisse gewartet wird.
  <p>

  Ein Kalender-Device hat verschiedene Readings. Mit Ausnahme von <code>calname</code> stellt jedes Reading eine Semikolon-getrennte Liste von UIDs von Kalender-Ereignisse dar, welche bestimmte Zust&auml;nde haben:
  <table>
  <tr><td>calname</td><td>Name des Kalenders</td></tr>
  <tr><td>modeAlarm</td><td>Ereignisse im Alarm-Modus</td></tr>
  <tr><td>modeAlarmOrStart</td><td>Ereignisse im Alarm- oder Startmodus</td></tr>
  <tr><td>modeAlarmed</td><td>Ereignisse, welche gerade in den Alarmmodus gewechselt haben</td></tr>
  <tr><td>modeChanged</td><td>Ereignisse, welche gerade in irgendeiner Form ihren Modus gewechselt haben</td></tr>
  <tr><td>modeEnd</td><td>Ereignisse im Endemodus</td></tr>
  <tr><td>modeEnded</td><td>Ereignisse, welche gerade vom Start- in den Endemodus gewechselt haben</td></tr>
  <tr><td>modeStart</td><td>Ereignisse im Startmodus</td></tr>
  <tr><td>modeStarted</td><td>Ereignisse, welche gerade in den Startmodus gewechselt haben</td></tr>
  <tr><td>modeUpcoming</td><td>Ereignisse im zuk&uuml;nftigen Modus</td></tr>
  </table>
  <p>

  F&uuml;r Serientermine werden mehrere Termine mit der selben UID erzeugt. In diesem Fall
  wird die UID nur im interessantesten gelesenen Modus-Reading angezeigt.
  Der interessanteste Modus ist der erste zutreffende Modus aus der Liste der Modi start, alarm, upcoming, end.<p>

  Die UID eines Serientermins wird nicht angezeigt, solange sich der Termin im Modus: modeEnd oder modeEnded befindet
  und die Serie nicht beendet ist. Die UID befindet sich in einem der anderen mode... Readings.
  Hieraus ergibts sich, das FHEM-Events nicht auf einem mode... Reading basieren sollten.
  Weiter unten im Text gibt es hierzu eine Empfehlung.<p>
  </ul>

  <b>Events</b>
  <ul><br>
  Wenn der Kalendar neu geladen oder aktualisiert oder eine Alarm-, Start- oder Endezeit
  erreicht wurde, wird ein FHEM-Event erzeugt:<p>

  <code>triggered</code><br><br>

  Man kann sich darauf verlassen, dass alle Readings des Kalenders in einem konsistenten und aktuellen
  Zustand befinden, wenn dieses Event empfangen wird.<p>

  Wenn ein Termin ge&auml;ndert wurde, werden zwei FHEM-Events erzeugt:<p>

  <code>changed: UID &lt;mode&gt;</code><br>
  <code>&lt;mode&gt;: UID</code><br><br>

  &lt;mode&gt; ist der aktuelle Modus des Termins nach der &auml;nderung. Bitte beachten: Im FHEM-Event befindet sich ein Doppelpunkt gefolgt von einem Leerzeichen.<p>

  FHEM-Events sollten nur auf den vorgenannten Events basieren und nicht auf FHEM-Events, die durch &auml;ndern eines mode... Readings ausgel&ouml;st werden.
  <p>
  </ul>

  <a name="CalendarPlugIns"></a>
  <b>Plug-ins</b>
  <ul>
  <br>
  Experimentell, bitte mit Vorsicht nutzen.<p>

  Ein Plug-In ist ein kleines Perl-Programm, dass Termine nebenher ver&auml;ndern kann.
  Das Perl-Programm arbeitet mit der Hash-Referenz <code>$e</code>.<br>
  Die wichtigsten Elemente sind:

  <table>
  <tr><th>code</th><th>description</th></tr>
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
  </ul>
  <br><br>

  <b>Anwendungsbeispiele</b>
  <ul><br>
    <i>Alle Termine inkl. Details anzeigen</i><br><br>
    <ul>
    <code>
    get MyCalendar full all<br>
    2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom   known    alarm 31.05.2012 17:00:00 07.06.2012 16:30:00-07.06.2012 18:00:00 Erna for coffee<br>
    992hydf4y44awer5466lhfdsr&shy;gl7tin6b6mckf8glmhui4&shy;googlecom   known upcoming                     08.06.2012 00:00:00-09.06.2012 00:00:00 Vacation
    </code><br><br>
    </ul>

    <i>Zeige Termine in Deinem Bilderrahmen</i><br><br>
    <ul>
    F&uuml;ge eine Zeile in die <a href="#RSSlayout">layout description</a> ein, um Termine im Alarm- oder Startmodus anzuzeigen:<br><br>
    <code>text 20 60 { fhem("get MyCalendar text next 2") }</code><br><br>
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
    Definiere dann ein notify: (Der Punkt nach dem zweiten Doppelpunkt steht f&uuml;r ein Leerzeichen)<br><br>
    <code>
    define ErnaComes notify MyCalendar:start:.2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom.* set MyLight on
    </code><br><br>
    Du kannst auch ein Logging aufsetzen:<br><br>
    <code>
    define LogErna notify MyCalendar:alarm:.2767324dsfretfvds7dsfn3e4&shy;dsa234r234sdfds6bh874&shy;googlecom.* { Log3 $NAME, 1, "ALARM name=$NAME event=$EVENT part1=$EVTPART0 part2=$EVTPART1" }
    </code><br><br>
    </ul>

    <i>Schalte die Aktoren an und aus</i><br><br>
    <ul>
    Stell Dir einen Kalender vor, dessen Zusammenfassungen (Betreff, Titel) die Namen von Devices in Deiner fhem-Installation sind.
    Du willst nun die entsprechenden Devices an- und ausschalten, wenn das Kalender-Ereignis beginnt bzw. endet.<br><br>
    <code>
    define SwitchActorOn notify MyCalendar:start:.* {}<br>
    </code>
	Dann auf DEF klicken und im DEF-Editor folgendes zwischen die beiden geschweiften Klammern {} eingeben:
    <code>
                my $reading="$EVTPART0";
                my $uid= "$EVTPART1";
                my $actor= fhem("get MyCalendar summary $uid");
                if(defined $actor) {
                   fhem("set $actor on")
                }
    <br><br>
    define SwitchActorOff notify MyCalendar:end:.* {}<br>
    </code>
	Dann auf DEF klicken und im DEF-Editor folgendes zwischen die beiden geschweiften Klammern {} eingeben:
    <code>
                my $reading="$EVTPART0";
                my $uid= "$EVTPART1";
                my $actor= fhem("get MyCalendar summary $uid");
                if(defined $actor) {
                   fhem("set $actor off")
                }
    </code><br><br>
    Auch hier kann ein Logging aufgesetzt werden:<br><br>
    <code>
    define LogActors notify MyCalendar:(start|end).* {}<br>
    </code>
	Dann auf DEF klicken und im DEF-Editor folgendes zwischen die beiden geschweiften Klammern {} eingeben:
    <code>
                my $reading= "$EVTPART0";
                my $uid= "$EVTPART1";
                my $actor= fhem("get MyCalendar summary $uid");
                Log 3 $NAME, 1, "Actor: $actor, Reading $reading";
    </code><br><br>
    </ul>

  </ul>

  <b>Eingebettetes HTML</b>
  <ul><br>
  Das Modul stellt eine zus&auml;tzliche Funktion <code>CalendarAsHtml(&lt;name&gt;,&lt;options&gt;)</code> bereit.
  Diese gibt den HTML-Kode f&uuml;r eine Liste von Terminen zur&uuml;ck. <code>&lt;name&gt;</code> ist der Name des
  Kalendar-Device und <code>&lt;options&gt;</code> ist das, was Du hinter <code>get &lt;name&gt; text ...</code>
  schreiben w&uuml;rdest.
  <br><br>
  Beispiel: <code>define MyCalendarWeblink weblink htmlCode { CalendarAsHtml("MyCalendar","next 3") }</code>
  <br><br>
  Dies ist eine rudiment&auml;re Funktion, die vielleicht in k&uuml;nftigen Versionen erweitert wird.
  <p>
  </ul>


</ul>

=end html_DE
=cut
