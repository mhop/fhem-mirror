##############################################
# $Id:$
##########################################################
# GoogleTalk
# Nachricht mittles GoogleTalk auf ein Android-Smartphone

package main;

use strict;
use warnings;
use POSIX;

sub
Utils_GoogleTalk_Initialize($$)
{
  my ($hash) = @_;
}

sub GoogleTalk($) {

  my ($message) = @_;

  Log (3, "GoogleTalk \"" . $message . "\"");

  use Net::XMPP;
  my $conn = Net::XMPP::Client->new;

  # individuelles Google-Konto zum Versenden
  my $username = '<username>';
  my $domain = 'gmail.com';
  my $password = '<mypass>';

  # individuelles Google-Konto zum Empfangen
  my $recipient = '<empfaenger@gmail.com>';

  my $resource = 'FHEM';

  my $status = $conn->Connect(
    hostname => 'talk.google.com',
    port => 5222,
    componentname => $domain,
    connectiontype => 'tcpip',
    tls => 1,
  );

  die "Connection failed: $!" unless defined $status;
  my ($res,$msg) = $conn->AuthSend(
    username => $username,
    password => $password,
    resource => $resource,
  );

  die "Auth failed ", defined $msg ? $msg : '', " $!" unless defined $res and $res eq 'ok';
  $conn->MessageSend(
    to => $recipient,
    resource => $resource,
    subject => 'message via ' . $resource,
    type => 'chat',
    body => $message,
  );

}

1;
