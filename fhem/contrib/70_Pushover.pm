##############################################
#
# A module to send notifications to Pushover.
#
# written 2013 by Johannes B <johannes_b at icloud.com>
#
##############################################
#
# Definition:
# define <name> Pushover <token> <user>
#
# Example:
# define Pushover1 Pushover 12345 6789
#
#
# You can send messages via the following command:
# set <Pushover_device> msg <title> <msg> <device> <priority> <sound>
#
# Example:
# set Pushover1 msg 'Titel' 'This is a text.' '' 0 ''
#
# Explantation:
# If device is empty, the message will be sent to all devices.
# If sound is empty, the default setting in the app will be used.
#
#
# For further documentation of these parameters:
# https://pushover.net/api


package main;

use HTTP::Request;
use LWP::UserAgent;
use IO::Socket::SSL;
use utf8;

sub Pushover_Initialize($$)
{
  my ($hash) = @_;
  $hash->{DefFn}    = "Pushover_Define";
  $hash->{SetFn}    = "Pushover_Set";
}

sub Pushover_Define($$)
{
  my ($hash, $def) = @_;
  
  my @args = split("[ \t]+", $def);
  
  if (int(@args) < 2)
  {
    return "Invalid number of arguments: define <name> Pushover <token> <user>";
  }
  
  my ($name, $type, $token, $user) = @args;
  
  $hash->{STATE} = 'Initialized';
  
  if(defined($token) && defined($user))
  {    
    $hash->{Token} = $token;
    $hash->{User} = $user;
    return undef;
  }
  else
  {
    return "Token and/or user missing.";
  }
}

sub Pushover_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;

  if($cmd eq 'msg')
  {
    return Pushover_Set_Message($hash, @args);
  }
}

sub Pushover_Set_Message
{
  my $hash = shift;
  
  my $attr = join(" ", @_);
  $attr =~ /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(\d+)\s*(".*"|'.*')\s*$/s;
  
  my $title = $1;
  my $message = $2;
  my $device = $3;
  my $priority = $4;
  my $sound = $5;
  
  if($title =~ /^['"](.*)['"]$/s)
  {
    $title = $1;
  }
  
  if($message =~ /^['"](.*)['"]$/s)
  {
    $message = $1;
  }
  
  if($device =~ /^['"](.*)['"]$/s)
  {
    $device = $1;
  }
  
  if($priority =~ /^['"](.*)['"]$/)
  {
    $priority = $1;
  }
  
  if($sound =~ /^['"](.*)['"]$/s)
  {
    $sound = $1;
  }
  
  if(($title ne "") && ($message ne ""))
  {
    my $body = "token=" . $hash->{Token} . "&" .
    "user=" . $hash->{User} . "&" .
    "title=" . $title . "&" .
    "message=" . $message;
    
    if ($device ne "")
    {
      $body = $body . "&" . "device=" . $device;
    }
    
    if ($priority ne "")
    {
      $body = $body . "&" . "priority=" . $priority;
    }
    
    if ($sound ne "")
    {
      $body = $body . "&" . "sound=" . $sound;
    }
    
    return Pushover_HTTP_Call($hash, $body);
  }
  else
  {
    return "Syntax: set <Pushover_device> msg <title> <msg> <device> <priority> <sound>";
  }
}

sub Pushover_HTTP_Call($$) 
{
  my ($hash,$body) = @_;
  
  my $client = LWP::UserAgent->new();
  
  my $req = HTTP::Request->new(POST => "https://api.pushover.net/1/messages.json");
  $req->header('Content-Type' => 'application/x-www-form-urlencoded');
  $req->content($body);

  my $response = $client->request($req);
  
  if($response)
  {
    if ($response->is_error)
    {
        return "Error: " . $response->status_line;
    }
    else
    {
        return "OK";
    }
  }
  else
  {
    return "Status: " . $response->status_line;
  }
}

1;
