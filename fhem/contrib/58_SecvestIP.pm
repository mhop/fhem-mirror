#####################################################################
#                                                                   #
# SecvestIP.pm written by Peter J. Flathmann                        #
# Version 0.3, 2012-09-15                                           #
# SecvestIP firmware version 2.3.4                                  #
#                                                                   #
# ----------------------------------------------------------------- #
#                                                                   #
# Usage:                                                            #
#                                                                   #
# define <name> SecvestIP <hostname> <user> <password>              #
# set <name> <Set|PartSet|Unset>                                    #
#                                                                   #
# Example:                                                          #
#                                                                   #
# define EMA SecvestIP secvestip admin geheimesKennwort             #
# attr EMA webCmd state                                             #
# set EMA Set                                                       #
#                                                                   #
# ----------------------------------------------------------------- #
#                                                                   #
# Possible states:                                                  #
#                                                                   #
# Set:     activated                                                #
# PartSet: internally activated                                     #
# Unset:   deactivated                                              #
#                                                                   #
#####################################################################

package main;
use strict;
use warnings;
use POSIX;
use LWP::UserAgent;
use HTTP::Cookies;

sub SecvestIP_Initialize($) {

  my ($hash) = @_;

  $hash->{DefFn}     = "SecvestIP_Define";
  $hash->{SetFn}     = "SecvestIP_Set";
  $hash->{GetFn}     = "SecvestIP_Get";

  return undef;
}

sub SecvestIP_Get($) {

  my ($hash) = @_;

  my $url = 'http://'.$hash->{HOST}.'/';

  my $agent = LWP::UserAgent->new(
    cookie_jar            => HTTP::Cookies->new,
    requests_redirectable => [ 'GET', 'HEAD', 'POST' ] 
  );

  # Login
  my $response = $agent->post( $url."login.cgi", {
    Language => 'deutsch',
    UserName => $hash->{USER},
    Password => $hash->{PASSWORD}} 
  );

  # Get SecvestIP state
  $response = $agent->get ($url.'getMode.cgi?ts='.time().'&Action=AudioAlarm&Source=Webpage');

  my @pairs = split(/\s+/,$response->content);
  my @state = split('=',$pairs[0]);
  $hash->{STATE} = $state[1];
  
  return undef;
}

sub SecvestIP_Set($$$) {

  my ($hash, $name ,$cmd) = @_;
  
  # Get current SecvestIP state
  SecvestIP_Get($hash);
 
  return "Unknown argument $cmd, choose one of state:Set,Unset,PartSet" if ($cmd eq "?");

  Log 1, "SecvestIP: Set $name $cmd";

  my $url = 'http://'.$hash->{HOST}.'/';

  my $agent = LWP::UserAgent->new(
    cookie_jar            => HTTP::Cookies->new,
    requests_redirectable => [ 'GET', 'HEAD', 'POST' ]
  );

  # Login
  my $response = $agent->post( $url."login.cgi", {
    Language => 'deutsch',
    UserName => $hash->{USER},
    Password => $hash->{PASSWORD}}
  );
  
  # switching between internal and full activation or vice versa requires Unset first
  if ($cmd eq "Set" and $hash->{STATE} eq "PartSet" or $cmd eq "PartSet" and $hash->{STATE} eq "Set")  {
    Log 1, "SecvestIP: switching from $hash->{STATE} to $cmd";
    $response = $agent->get ($url.'setMode.cgi?Mode=Unset&Source=Webpage&ts='.time() );
    sleep(2); # wait a moment to avoid confusing SecvestIP's web interface
  }
  
  $response = $agent->get ($url.'setMode.cgi?Mode='.$cmd.'&Source=Webpage&ts='.time() );
  SecvestIP_Get($hash);

  return undef;
}

sub SecvestIP_Define($$) {

  my ($hash, $def) = @_;
  
  Log 1, "SecvestIP: define $def";
 
  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> SecvestIP <hostname> <user> <password>" if (int(@a) != 5);

  $hash->{STATE} = "Initialized";

  $hash->{NAME} = $a[0];
  $hash->{HOST} = $a[2];
  $hash->{USER} = $a[3];
  $hash->{PASSWORD} = $a[4];

  SecvestIP_Get($hash);

  return undef;
}

1;
