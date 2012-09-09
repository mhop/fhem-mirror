#####################################################################
#                                                                   #
# SecvestIP.pm written by Peter J. Flathmann                        #
# Version 0.1, 2012-09-07                                           #
# SecvestIP firmware version 2.3.4                                  #
#                                                                   #
#                                                                   #
# Usage: define <name> SecvestIP <hostname> <user> <password>       #
#                                                                   #
#                                                                   #
# Example:                                                          #
#                                                                   #
# define EMA SecvestIP secvestip admin geheimesKennwort             #
#                                                                   #
# define Alarmanlage dummy                                          #
# attr Alarmanlage alias SecvestIP                                  #
# attr Alarmanlage eventMap on:on off:off                           #
#                                                                   #
# define AlarmanlageScharf    notify Alarmanlage:on set EMA Set     #
# define AlarmanlageUnscharf  notify Alarmanlage:off set EMA Unset  #
#                                                                   #
#####################################################################

package main;
use strict;
use warnings;
use POSIX;
use LWP::UserAgent;
use HTTP::Cookies;

sub
SecvestIP_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "SecvestIP_Define";
  $hash->{SetFn}     = "SecvestIP_Set";
  $hash->{GetFn}     = "SecvestIP_Get";
}

sub SecvestIP_Get($@) {

  my ($hash,@a) = @_;

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

  $response = $agent->get ($url.'getMode.cgi?ts='.time().'&Action=AudioAlarm&Source=Webpage');

  my @pairs = split(/\s+/,$response->content);
  my @state = split('=',$pairs[0]);

  $hash->{STATE} = $state[1];
  
  return undef;
}

sub SecvestIP_Set($$$) {

  my ($hash, $name ,$cmd) = @_;

  Log 1, "SecvestIP: Set $name $cmd";
  return "Unknown argument $cmd, choose one of Set Unset PartSet" if ("?" eq $cmd); 

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

  $response = $agent->get ($url.'setMode.cgi?Mode='.$cmd.'&Source=Webpage&ts='.time() );
  $hash->{STATE} = $cmd;

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
