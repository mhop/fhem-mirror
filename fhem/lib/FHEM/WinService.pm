################################################################
#
#  Copyright notice
#
#  (c) 2013 Thomas Eckardt (Thomas.Eckardt@thockar.com)
#
#  This script is free software; you can redistribute it and/or modify
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
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

# $Id$

package FHEM::WinService;

use strict;

sub __installService($$$);
sub __initService($$);
sub new($$$);

use vars qw($VERSION);

$VERSION = $1 if('$Id$' =~ /,v ([\d.]+) /);


###################################################
# Windows Service Handler
#
# install/remove or possibly start fhem as a Windows Service

sub
new ($$$) {
    my ($class, $argv) = @_;

    my $fhem = $0;
    $fhem =~ s/\\/\//go;
    my $fhembase = $fhem;
    $fhembase =~ s/\/?[^\/]+$//o;
    if (! $fhembase && eval('use Cwd();1;')) {
        $fhembase = Cwd::cwd();
        $fhembase =~ s/\\/\//go;
    }
    my $larg = $argv->[@$argv-1];

    if ($larg eq '-i') {
        if (! $fhembase) {
            print "error: unable to detect fhem folder - cancel\n";
            exit 0;
        }
        $fhem = $fhembase.'/'.$fhem if $fhem !~ /\//o;
        my $cfg = $argv->[0];
        $cfg =~ s/\\/\//go;
        $cfg = $fhembase.'/'.$cfg if $cfg !~ /\//o;
        print "try to install fhem windows service as: $^X $fhem $cfg\n";
        __installService('-i' , $fhem, $cfg);
        exit 0;
    } elsif ($larg eq '-u') {
        print "try to remove fhem windows service\n";
        __installService('-u',undef,undef);
        exit 0;
    } else {
        $class = ref $class || $class;
        bless my $self = {}, $class;
        $self->{ServiceLog} = [];
        @{$self->{ServiceLog}} = __initService($self, $argv->[0]);
        return $self;
    }
}
###################################################


###################################################
# from here are internal subs only !
###################################################


###################################################
# install or remove fhem as a Windows Service
#

sub
__installService($$$)
{
 eval(<<'EOT') or print "error: $@\n)";
    use Win32::Daemon;
    my $p;
    my $p2;

    if(lc $_[0] eq '-u') {
        system('cmd.exe /C net stop fhem');
        sleep(1);
        Win32::Daemon::DeleteService('','fhem') ||
          print "Failed to remove fhem service: " .
          Win32::FormatMessage( Win32::Daemon::GetLastError() ) . "\n" & return;
        print "Successfully removed service fhem\n";
    } elsif( lc $_[0] eq '-i') {
        unless($p=$_[1]) {
            $p=$0;
            $p=~s/\w+\.pl/fhem.pl/o;
        }
        if($p2=$_[2]) {
            $p2=~s/[\\\/]$//o;
        } else {
            $p2=$p; $p2=~s/\.pl/.cfg/io;
        }
        my %Hash = (
            name    =>  'fhem',
            display =>  'fhem server',
            path    =>  "\"$^X\"",
            user    =>  '',
            pwd     =>  '',
            parameters => "\"$p\" \"$p2\"",
          );
        if( Win32::Daemon::CreateService( \%Hash ) ) {
            print "fhem service successfully added.\n";
        } else {
            print "Failed to add fhem service: " .
                  Win32::FormatMessage( Win32::Daemon::GetLastError() ) . "\n";
            print "Note: if you're getting an error: Service is marked for ".
                  "deletion, then close the service control manager window".
                  " and try again.\n";
        }
    }
    1;
EOT
}


###################################################
# check if called from SCM and start the service if so
#

sub
__initService ($$) {
    my ($self, $arg) = @_;
    my @ServiceLog;

    # check how we are called from the OS - Console or SCM
    
    # Win32 Daemon and Console module installed ?
    if( eval("use Win32::Daemon; use Win32::Console; 1;") ) {
      eval(<<'EOT');
        my $cmdlin = Win32::Console::_GetConsoleTitle () ? 1 : 0;

        eval{&main::doGlobalDef($arg);}; # we need some config here

        if ($cmdlin) {
            $self->{AsAService} = 0;
        } else {
            $self->{AsAService} = 1;
            $self->{ServiceStopping} = 0;
            $main::attr{global}{nofork}=1; # this has to be set here
            push @ServiceLog, 'registering fhem as Windows Service';
            Win32::Daemon::StartService();

            # Wait until the service manager is ready for us to continue...
            my $i = 0;
            while( SERVICE_START_PENDING != Win32::Daemon::State() && $i < 60) {
                # looping indefinitely and waiting to start
                sleep( 1 );
                $i++;
            }
            if ($i > 59) {
                push @ServiceLog,'unable to register fhem in SCM - cancel';
                die "unable to register fhem in SCM - cancel\n";
            }
            Win32::Daemon::State( SERVICE_RUNNING );
            push @ServiceLog,'starting fhem as a service';

            # this sub is called in the main loop to check the service state
            $self->{serviceCheck} = sub {
               return unless $self->{AsAService};
               my $state = Win32::Daemon::State();
               my %idlestate = (
                   Win32::Daemon::SERVICE_PAUSE_PENDING => 1,
                   Win32::Daemon::SERVICE_CONTINUE_PENDING => -1
               );
               if( $state == SERVICE_STOP_PENDING ) {
                   if ($self->{ServiceStopping} == 0) {
                       $self->{ServiceStopping} = 1;
                       &main::Log(1,'service stopping');
                       #ask SCM for a grace time (30 seconds) to shutdown
                       Win32::Daemon::State( SERVICE_STOP_PENDING, 30000 );
                       &main::Log(1, 'service stopped');
                       &main::CommandShutdown(undef, undef);
                       $self->{ServiceStopping} = 2;
                       Win32::Daemon::State( SERVICE_STOPPED );
                       Win32::Daemon::StopService();
                       # be nice, tell we stopped
                       exit 0;
                   } elsif ($self->{ServiceStopping} == 1) {
                       # keep telling SCM we're stopping and didn't hang
                       Win32::Daemon::State( SERVICE_STOP_PENDING, 30000 );
                   }
               } elsif ( $state == SERVICE_PAUSE_PENDING ) {
                   Win32::Daemon::State( SERVICE_PAUSED );
                   $self->{allIdle} = $idlestate{$state};
                   &main::Log(1,'pausing service');
               } elsif ( $state == SERVICE_CONTINUE_PENDING ) {
                   Win32::Daemon::State( SERVICE_RUNNING );
                   $self->{allIdle} = $idlestate{$state};
                   &main::Log(1, 'continue service');
               } else {
                   my $PrevState = SERVICE_RUNNING;
                   $PrevState = SERVICE_STOPPED if $self->{ServiceStopping};
                   $PrevState = SERVICE_PAUSED if $self->{allIdle} > 0;
                   Win32::Daemon::State( $PrevState );
                   undef $self->{allIdle}
                       if ($PrevState == SERVICE_RUNNING);
               }
            };
        } # end if ($cmdlin)
EOT
        if ($@) {   # we got some Perl errors in eval
            push @ServiceLog, "error: $@";
            $self->{serviceCheck} = sub {}; # set it - could be destroyed
            $self->{AsAService} = 0;
        }
        push @ServiceLog,'starting in console mode'
            unless $self->{AsAService};
    } else {
        $self->{AsAService} = 0;
        push @ServiceLog,'starting in console mode';
    }
    return @ServiceLog;
}
###################################################

1;

