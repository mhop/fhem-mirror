#########################################################################
# $Id$
# Utility functions for testing Modbus that can be uses by other Fhem modules
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
                    
package FHEM::Modbus::TestUtils;

use strict;
use warnings;
use GPUtils         qw(:all);
use Time::HiRes     qw(gettimeofday);
use Test::More;

use Exporter ('import');
our @EXPORT_OK = qw(
        CallStep
        NextStep
        LogStep
        SimRead
        findTimesInLog
        calcDelays
        SetTestOptions
        CheckAndReset
     );

our %EXPORT_TAGS = (all => [@EXPORT_OK]);

BEGIN {
    GP_Import( qw(
        fhem
        Log3
        RemoveInternalTimer
        InternalTimer
        gettimeofday

        FmtDateTime
        FmtTimeMs
        ReadingsVal
        ReadingsTimestamp
        AttrVal
        InternalVal
        featurelevel
        
        FhemTestUtils_gotEvent
        FhemTestUtils_gotLog
        FhemTestUtils_getLogTime
        FhemTestUtils_resetLogs
        FhemTestUtils_resetEvents
        
        defs
        modules
        attr
        done_testing
        logInform
    ));
};


our $testStep = 0;
our %testOptions;
our %results;


#####################################################################
#
#  NextStep
#       - GetNextStep
#       - set timer for CallStep or end Testing
#
#  InternalTimer -> CallStep 
#                       - step via eval
#                       - NextStep -> Timer for CallStep
#                                       - step via eval
#                                       - NextStep
#
#  LogInform -> ReactOnLogRegex -> 
#                   - InternalTimer for SimResponseRead
#
#  InternalTimer -> SimResponseRead
#                   - SimResponseRead
#                   - NextStep -> Timer for CallStep
#                                   - step via eval
#                                       - send -> LogInform -> SimResponseRead ...
#                                   - NextStep?? (don't set timer for next step in this case)
#


##################################################################
# find the next test step number 
# internal function, called from NextStep
sub GetNextStep {
    #Log3 undef, 1, "Test GetNextStep: look for next step";
    my $next = $testStep;
    FINDSTEP: 
    while (1) {
        $next++;
        return 0 if ($next > 99);
        #Log3 undef, 1, "Test GetNextStep: check step $next";
        next FINDSTEP if (!defined (&{"main::testStep$next"}));
        return $next;
    }
    return;     # never reached
}


######################################################################
# set internalTimer to call the next test step after an optional delay
# normally in tests to have the first step called and 
# also internally by CallStep and SimResponseRead
sub NextStep {
    my $delay = shift // 0;
    my $next  = shift // GetNextStep();
    if (!$next || ($delay && $delay eq 'end')) {        # done if no more steps
        Log3 undef, 1, "Test NextStep: no more steps found - exiting";
        done_testing;
        exit(0);
    }
    if (!$delay || $delay ne 'wait') {                  # set timer to next step unless waiting for reception of data
        #Log3 undef, 1, "Test NextStep: set timer to call step $next with delay $delay";
        InternalTimer(gettimeofday() + $delay, \&CallStep, "main::testStep$next");
        $testStep = $next;
    }
    #Log3 undef, 1, "Test NextStep: done.";
    return;
}


#############################################################################
# Call the Test step and then set the timer for the next one
# called by internalTimer
sub CallStep {
    my $func = shift;
    $func =~ /^(.*[A-Za-z]+)(\d+)$/;
    my $step = $2;
    Log3 undef, 1, "----------------------------------------------------";    
    Log3 undef, 1, "Test step $step ($func)";
    
    no strict "refs";                   ## no critic - function name needs to be string
    my $delay = eval { &{$func}() };    # call the next step and check for errors
    if ($@) {
        Log3 undef, 1, "Test step $step call created error: $@";
    } else {
        Log3 undef, 1, "Test step $step ($func) done" . (defined ($delay) ? ", delay before next step is $delay" : "");
    }
    # if step function returns 'wait' then do not set timer for next step but wait for ReactOnLogRegex or similar
    NextStep($delay);                   # check for next step and set timer or end testing
    return;
}


################################################################################
# check if a regex is found in logs (typically the sending of a request)
# and call SmResponseRead via timer to simulate the reception of a response
# called via logInform
sub ReactOnLogRegex {
    my $name = shift;
    my $line = shift;
    #die "line got: $line";
    if ($line =~ /$testOptions{RespondTo}/) {
        my $send = $1;
        my $id   = substr ($send, 0, 2);
        my $recv = $testOptions{ResponseHash}{$send};       # simulate broken error response by default
        if (!$recv) {
            $recv = ($id . '800041c0');
            Log3 undef, 1, "Test: request $send is not in Reply hash, respond with default error instead";
        }
        my $delay = $testOptions{ResponseDelay} // 0.05;
        Log3 undef, 1, "------------------------------------------------------------------------";    
        Log3 undef, 1, "Test saw sending $send, id $id, set timer to simulate receiving $recv in $delay";
        InternalTimer(gettimeofday() + $delay, \&SimResponseRead, $recv);       # set timer to simulate response and go to next step
    }
    return;
}


#######################################################################################
# simulate the reception of a response by calling SimRead 
# and then setting the timer for the next step.
# todo: delay should be definable
sub SimResponseRead {
    my $data = shift;
    Log3 undef, 1, "Test now simulates reception of response and then checks for next step";
    SimRead($testOptions{IODevice}, $data);
    NextStep($testOptions{delayAfterResponse} // 0);
    return;
}


##########################################################################
# interface to set options hash
# used options:
# - delayAfterResponse : time in seconds to wait after a simualted response before the next step function is called
# - IODevice : name of the device for sending and receiving
# - RespondTo : Regex to be used when monitoring the Fhem log and reacting on a "sending" log with a simulated reception
# - ResponseHash : Hash that maps from data sent (as found in log) to a valid response for the simulation 
# - ResponseDelay : delay before the reception of a response is sumulated
# - Time1Regex and Time1Name : name and regex to be searched in log to find the time when it was logged, used by calcDelays
# - Time2Regex and Time2Name : name and regex to be searched in log to find the time when it was logged, used by calcDelays
sub SetTestOptions {
    my $opt = shift;
    foreach my $k (keys %{$opt}) {
        $testOptions{$k} = $opt->{$k};
    }
    if ($testOptions{RespondTo}) {
        $logInform{$testOptions{IODevice}} = \&ReactOnLogRegex;
    }
    return;
}


##############################################################
# simulate reading from a device. 
# the device should be defined with 'none' as interface 
# and the readFn should take data from $hash->{TestInput}
# in this case
sub SimRead {
    my $name   = shift;             # Name of the io device that should read data
    my $input  = shift;             # binary input string (coded as hex-string) to be read
    my $option = shift;             # further otions (so far only 'ASCII' to treat the input string as text instead of hex)
    my $hash   = $defs{$name};
    my $data;
    Log3 undef, 1, "Test simulate reception of $input";
    if ($option && $option eq 'ASCII') {
        $data = $input;                      # ascii 
    } else {
        $data   = pack ('H*', $input);       # hex coded binary
    }
    $hash->{TestInput} = $data;
    my $type    = $defs{$name}{TYPE};
    my $modHash = $modules{$type};
    my $readFn  = $modHash->{ReadFn};
    eval { &{$readFn}($hash) };
    if ($@) {
        Log3 undef, 1, "Test step $testStep call to readFn created error: $@";
    } else {
        Log3 undef, 1, "Test step $testStep readFn done.";
    }
    return;
}


#############################################################
# wrapper for Log3 to be used in tests
sub LogStep {
    my $msg = shift // '';
    Log3 undef, 1, "Test step $testStep: $msg";
    return;
}


###########################################################################
# find the time of two regexes in the log 
sub findTimesInLog {
    $results{$testOptions{Time1Name}.$testStep} = FhemTestUtils_getLogTime($testOptions{Time1Regex});      
    $results{$testOptions{Time2Name}.$testStep} = FhemTestUtils_getLogTime($testOptions{Time2Regex});
    Log3 undef, 1, "Test step $testStep: LogTime for last $testOptions{Time1Name} is " . 
        ($results{$testOptions{Time1Name}.$testStep} ? FmtTimeMs($results{$testOptions{Time1Name}.$testStep}) : 'unknown');
    Log3 undef, 1, "Test step $testStep: LogTime for last $testOptions{Time2Name} is " . 
    ($results{$testOptions{Time2Name}.$testStep} ? FmtTimeMs($results{$testOptions{Time2Name}.$testStep}) : 'unknown');
    return;
}


################################################################################
# calculate and log the time differences found by calling findTimesInLog
sub calcDelays {
    my ($lastDelay, $commDelay, $sendDelay);
    if (defined ($results{$testOptions{Time1Name} . $testStep}) && 
        defined ($results{$testOptions{Time2Name} . $testStep})) {
        $lastDelay = sprintf '%.3f', ($results{$testOptions{Time2Name} . $testStep} // 0) - ($results{$testOptions{Time1Name} . ($testStep)} // 0);
        Log3 undef, 1, "Test step $testStep: delay between $testOptions{Time1Name} in step " . ($testStep) . " and $testOptions{Time2Name} in step $testStep is $lastDelay";
    }
    if (defined ($results{$testOptions{Time1Name} . ($testStep - 1)}) && 
    defined ($results{$testOptions{Time2Name} . ($testStep - 1)})) {
        $commDelay = sprintf '%.3f', ($results{$testOptions{Time1Name} . $testStep} // 0) - ($results{$testOptions{Time2Name} . ($testStep - 1)} // 0);
        $sendDelay = sprintf '%.3f', ($results{$testOptions{Time1Name} . $testStep} // 0) - ($results{$testOptions{Time1Name} . ($testStep - 1)} // 0);

        Log3 undef, 1, "Test step $testStep: delay between $testOptions{Time2Name} in step " . ($testStep - 1) . " and $testOptions{Time1Name} in step $testStep is $commDelay, between each $testOptions{Time1Name} $sendDelay";
    }
    return ($commDelay, $sendDelay, $lastDelay);
}


################################################################################
# Reset Logs and Events and check for Warnings
sub CheckAndReset {
    is(FhemTestUtils_gotLog('PERL WARNING'), 0, "no Perl Warnings so far");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    return;
}


1;