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
# set <Pushover_device> msg <title> <msg> <device> <priority> <sound> [<retry> <expire>]
#
# Examples:
# set Pushover1 msg 'Titel' 'This is a text.' '' 0 ''
# set Pushover1 msg 'Emergency' 'Security issue in living room.' '' 2 'siren' 30 3600
#
# Explantation:
# If device is empty, the message will be sent to all devices.
# If sound is empty, the default setting in the app will be used.
# If priority is higher or equal 2, retry and expire must be defined.
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
  
  my $shortExpressionMatched = 0;
  my $longExpressionMatched = 0;
  
  if($attr =~ /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(\d+)\s*(".*"|'.*')\s*(\d+)\s*(\d+)\s*$/s)
  {
    $longExpressionMatched = 1;
  }
  elsif($attr =~ /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(\d+)\s*(".*"|'.*')\s*$/s)
  {
    $shortExpressionMatched = 1;
  }
  
  my $title = "";
  my $message = "";
  my $device = "";
  my $priority = "";
  my $sound = "";
  my $retry = "";
  my $expire = "";
  
  if(($shortExpressionMatched == 1) || ($longExpressionMatched == 1))
  {
    $title = $1;
    $message = $2;
    $device = $3;
    $priority = $4;
    $sound = $5;
    
    if($longExpressionMatched == 1)
    {
      $retry = $6;
      $expire = $7;
    }
    
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
    
    if($retry =~ /^['"](.*)['"]$/s)
    {
      $retry = $1;
    }
    
    if($expire =~ /^['"](.*)['"]$/s)
    {
      $expire = $1;
    }
  }
  
  if((($title ne "") && ($message ne "")) && ((($retry ne "") && ($expire ne "")) || ($priority < 2)))
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
    
    if ($retry ne "")
    {
      $body = $body . "&" . "retry=" . $retry;
    }
    
    if ($expire ne "")
    {
      $body = $body . "&" . "expire=" . $expire;
    }
    
    return Pushover_HTTP_Call($hash, $body);
  }
  else
  {
    return "Syntax: set <Pushover_device> msg <title> <msg> <device> <priority> <sound> [<retry> <expire>]";
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
