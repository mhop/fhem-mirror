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

use Exporter ('import');
our @EXPORT_OK = qw(
        CallStep
        NextStep
        LogStep
        SimRead
        findTimesInLog
        calcDelays
        SetTestOptions
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
        
        FhemTestUtils_getLogTime
        
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
our $nextStepMode = 'auto';

sub SimRead {
    my $name   = shift;
    my $readFn = shift;
    my $text   = shift;
    my $option = shift;
    my $hash   = $defs{$name};
    my $data;
    Log3 undef, 1, "Test simulate reception of $text";
    if ($option && $option eq 'ASCII') {
        $data = $text;                      # ascii 
    } else {
        $data   = pack ('H*', $text);       # hex coded binary
    }
    $hash->{TestInput} = $data;
    eval { &{$readFn}($hash) };
    if ($@) {
        Log3 undef, 1, "Test step $testStep call to readFn created error: $@";
    } else {
        Log3 undef, 1, "Test step $testStep readFn done.";
    }
    return;
}

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


sub NextStep {
    my $delay = shift // 0;
    my $next  = GetNextStep();
    
    InternalTimer(gettimeofday() + $delay, \&CallStep, "main::testStep$next");
    #Log3 undef, 1, "Test NextStep: done.";
    $testStep = $next;
    return;
}


sub CallStep {
    my $func = shift;
    Log3 undef, 1, "----------------------------------------------------";    
    Log3 undef, 1, "Test step $testStep";
    
    no strict "refs";               ## no critic - function name needs to be string
    my $delay = eval { &{$func}() };
    if ($@) {
        Log3 undef, 1, "Test step $testStep call created error: $@";
    } else {
        Log3 undef, 1, "Test step $testStep done.";
    }
    
    my $next  = GetNextStep();      
    if (!$next) {                       # done if no more steps
        Log3 undef, 1, "Test NextStep: no more steps found - exiting";
        done_testing;
        exit(0);
    }
    if ($nextStepMode eq 'auto') {
        NextStep($delay);               # set timer to go to next step with delay returned by last
    }
    return;
}


sub LogStep {
    my $msg = shift // '';
    Log3 undef, 1, "Test step $testStep: $msg";
    return;
}


sub ReactOnSendingLog {
    my $name = shift;
    my $line = shift;
    #die "line got: $line";
    if ($line =~ /$testOptions{RespondTo}/) {
        my $send = $1;
        my $id   = substr ($send, 0, 2);
        my $recv = $testOptions{ReplyHash}{$send} // (($id . '800041c0'));       # simulate broken error response by default
        my $delay = $testOptions{ResponseDelay} // 0.05;
        Log3 undef, 1, "------------------------------------------------------------------------";    
        Log3 undef, 1, "Test saw sending $send, id $id, set timer to simulate receiving $recv in $delay";
        InternalTimer(gettimeofday() + $delay, \&SimResponseRead, $recv);
    }
    return;
}


sub SimResponseRead {
    my $data = shift;
    Log3 undef, 1, "Test now simulate reception of response and then call next step";
    SimRead($testOptions{IODevice}, $testOptions{ReadFn}, $data);
    NextStep();
}


sub SetTestOptions {
    my $opt = shift;
    foreach my $k (keys %{$opt}) {
        $testOptions{$k} = $opt->{$k};
    }
    if ($testOptions{RespondTo}) {
        $nextStepMode  = 'reception';
        $logInform{$testOptions{IODevice}} = \&ReactOnSendingLog;
    }
}


sub findTimesInLog {
    $results{$testOptions{Time1Name}.$testStep} = FhemTestUtils_getLogTime($testOptions{Time1Regex});      
    $results{$testOptions{Time2Name}.$testStep} = FhemTestUtils_getLogTime($testOptions{Time2Regex});
    Log3 undef, 1, "Test step $testStep: LogTime for last $testOptions{Time1Name} is " . 
        ($results{$testOptions{Time1Name}.$testStep} ? FmtTimeMs($results{$testOptions{Time1Name}.$testStep}) : 'unknown');
    Log3 undef, 1, "Test step $testStep: LogTime for last $testOptions{Time2Name} is " . 
    ($results{$testOptions{Time2Name}.$testStep} ? FmtTimeMs($results{$testOptions{Time2Name}.$testStep}) : 'unknown');
    return;
}


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


1;