########################################################
# $Id$
########################################################
#
# History:
#
# 2015-05-11: Improve error logging to assist problem solving
# 2015-05-09: Assimilate mail related code from 75_MSG
# 2015-05-06: Tidy up code for restructuring
# 2015-05-05: Remove dependency on Switch
# 2012      : Created by rbente
#
package main;

use strict;
use warnings;
use MIME::Lite;
use Net::SMTP;    # libnet-3.06 has SSL included, so we need to check the version

my %sets = (
    "add"   => "MSGMail",
    "clear" => "MSGMail",
    "list"  => "MSGMail",
    "send"  => "MSGMail"
);

my $MSGMail_SSL  = 0;
my $MSGMail_SMTP = 0;

##############################################
# Initialize Function
#  Attributes are:
#     authfile    the name of the file which contains userid and password
#     smtphost    the smtp server hostname
#     smtpport    the port of the smtp host
#     subject     subject of the email
#     from        from mailaddress (sender)
#     to          to mailaddress (receipent)
#     cc          carbon copy address(es)  (delimiter is comma)
#     CR          0 = no CR added to the end of the line
#                 1 = CR added to the end of the line
##############################################
sub MSGMail_Initialize($)
{
    my ($hash) = @_;

    $hash->{SetFn}    = "MSGMail_Set";
    $hash->{DefFn}    = "MSGMail_Define";
    $hash->{UndefFn}  = "MSGMail_Undef";
    $hash->{AttrList} = "loglevel:0,1,2,3,4,5,6 authfile smtphost smtpport subject from to cc CR:0,1";

    my $name = "MSGMail";

    # check version of libnet - if < 3.00, try to load Net::SMTP::SSL
    $MSGMail_SMTP = $Net::SMTP::VERSION;
    if ($Net::SMTP::VERSION >= 3)
    {
        $MSGMail_SSL = 1;
    }
    else
    {
        eval "use Net::SMTP::SSL";
        if ($@)
        {
            Log 0, $@ if ($@);
            $MSGMail_SSL = 0;
        }
        else
        {
            $MSGMail_SSL = 1;
        }
    }
    Log 0,
      "$name: SSL is "
      . (
          ($MSGMail_SSL)
        ? ("available, provided by Net::SMTP" . (($MSGMail_SMTP < 3.00) ? "::SSL" : ""))
        : "not available"
      );
}

##############################################
# Define Function
# set the counter to 0
##############################################
sub MSGMail_Define($$)
{
    my ($hash, $def) = @_;
    my @a      = split("[ \t][ \t]*", $def);
    my $errmsg = "wrong syntax: define <name> MSGMail from to smtphost authfile";
    my $name   = $hash->{NAME};

    return $errmsg if (@a != 6);

    # set all  the Attributes
    $attr{$name}{from}     = $a[2];
    $attr{$name}{to}       = $a[3];
    $attr{$name}{smtphost} = $a[4];
    $attr{$name}{authfile} = $a[5];
    $attr{$name}{subject}  = "FHEM ";
    $attr{$name}{CR}       = "1";

    $hash->{STATE}                    = "ready";
    $hash->{TYPE}                     = "MSGMail";
    $hash->{READINGS}{msgcount}{TIME} = TimeNow();
    $hash->{READINGS}{msgcount}{VAL}  = 0;
    return undef;
}

##############################################
# Undefine Function
# flush all lines of data
##############################################
sub MSGMail_Undef($$)
{
    my ($hash, $name) = @_;
    my $i;

    #  flush the data
    for ($i = 0 ; $i < ReadingsVal($name, "msgcount", 0) ; $i++)
    {
        $data{$name}{$i} = "";
    }

    delete($modules{MSGMail}{defptr}{ $hash->{CODE} }) if ($hash && $hash->{CODE});
    return undef;
}

##############################################
# Set Function
# all the data are stored in the global array  @data
# as counter we use a READING named msgcount
##############################################
sub MSGMail_Set($@)
{
    my ($hash, @a) = @_;
    return "Unknown argument $a[1], choose one of ->  " . join(" ", sort keys %sets)
      if (!defined($sets{ $a[1] }));
    my $name = shift @a;

    return "no set value specified" if (int(@a) < 1);

    #	return "Unknown argument ?" if($a[0] eq "?");
    my $v = join(" ", @a);

    # we like to add another line of data
    if ($a[0] eq "add")
    {
        # split the line in command and data
        my $mx = shift @a;
        my $my = join(" ", @a);

        # check if we like to have and CR at the end of the line
        if (AttrVal($name, "CR", "0") eq "1")
        {
            $my = $my . "\n";
        }

        # get the highest number of lines, stored the line in  @data and increase
        # the counter, at the end set the status
        my $count = $hash->{READINGS}{msgcount}{VAL};
        $data{$name}{$count}              = $my;
        $hash->{READINGS}{msgcount}{TIME} = TimeNow();
        $hash->{READINGS}{msgcount}{VAL}  = $count + 1;
        $hash->{STATE}                    = "addmsg";
    }

    # we like to clear our buffer, first clear all lines of @data
    # and then set the counter to 0 and the status to clear

    elsif ($a[0] eq "clear")
    {
        my $i;
        for ($i = 0 ; $i < ReadingsVal($name, "msgcount", 0) ; $i++)
        {
            $data{$name}{$i} = "";
        }
        $hash->{READINGS}{msgcount}{TIME} = TimeNow();
        $hash->{READINGS}{msgcount}{VAL}  = 0;
        $hash->{STATE}                    = "clear";
    }

    # we like to see the buffer

    elsif ($a[0] eq "list")
    {
        my $i;
        my $mess = "---- Lines of data for $name ----\n";
        for ($i = 0 ; $i < ReadingsVal($name, "msgcount", 0) ; $i++)
        {
            $mess .= $data{$name}{$i};
        }
        return "$mess---- End of data for $name ----";
    }

    elsif ($a[0] eq "send")
    {
        # check all required data
        my $from     = AttrVal($name, "from",     "");
        my $to       = AttrVal($name, "to",       "");
        my $subject  = AttrVal($name, "subject",  "");
        my $authfile = AttrVal($name, "authfile", "");
        my $smtphost = AttrVal($name, "smtphost", "");
        my $smtpport = AttrVal($name, "smtpport", "465");    # 465 is the default port
        my $cc       = AttrVal($name, "cc",       "");       # Carbon Copy

        return "No <from> address specified, use  attr $name from <mail-address>"
          if (!$from);
        return "No <to> address specified, use  attr $name to <mail-address>"
          if (!$to);
        return "No <subject> specified, use  attr $name subject <text>"
          if (!$subject);
        return "No <authfile> specified, use  attr $name authfile <filename>"
          if (!$authfile);
        return "No <smtphost> name specified, use  attr $name sntphost <hostname>"
          if (!$smtphost);

        open(FHEMAUTHFILE, "<" . $authfile)
          || return "Can not open authfile $authfile: $!";
        my @auth = <FHEMAUTHFILE>;
        close(FHEMAUTHFILE);
        chomp(@auth);

        # Log 1, "MSG User = <" . @auth[0] . ">  Passwort = <" . @auth[1] . ">";

        # compose message
        my $i;
        my $mess = "";
        for ($i = 0 ; $i < ReadingsVal($name, "msgcount", 0) ; $i++)
        {
            $mess .= $data{$name}{$i};
        }

        my $mailmsg = MIME::Lite->new(
            From    => $from,
            To      => $to,
            Subject => $subject,
            Type    => 'text/plain; charset=UTF-8',    #'multipart/mixed', # was 'text/plain'
            Data    => $mess
        );

        # login to the SMTP Host using SSL and send the message
        my $smtp;
        my $smtperrmsg = "SMTP Error: ";

        #$smtp = Net::SMTP::SSL->new($smtphost, Port => $smtpport)
        $smtp = MSGMail_conn($defs{$name})
          or return MSGMail_error($name, "Can't connect to host $smtphost",
            $smtperrmsg . " Can't connect to host $smtphost");
        $smtp->auth($auth[0], $auth[1])
          or
          return MSGMail_error($name, "Can't authenticate", $smtperrmsg . " Can't authenticate: " . $smtp->message());
        $smtp->mail($from)
          or return MSGMail_error($name, "Error setting sender '$from'", $smtperrmsg . $smtp->message());
        $smtp->to($to) or return MSGMail_error($name, "Error setting receiver '$to'", $smtperrmsg . $smtp->message());
        if ($cc ne '')
        {
            Log3 $name, 1, "$name: CC = $cc";
            $smtp->cc($cc)
              or return MSGMail_error($name, "Error setting carbon-copy $cc", $smtperrmsg . $smtp->message());
        }
        $smtp->data() or return MSGMail_error($name, "Error setting data", $smtperrmsg . $smtp->message());
        $smtp->datasend($mailmsg->as_string)
          or return MSGMail_error($name, "Error sending email", $smtperrmsg . $smtp->message());
        $smtp->dataend() or return MSGMail_error($name, "Error ending transaction", $smtperrmsg . $smtp->message());
        $smtp->quit()    or return MSGMail_error($name, "Error saying good-bye",    $smtperrmsg . $smtp->message());

        Log3 $name, 1, "$name: successfully sent email w/ subject '$subject'";

    }    ###>  END MSGMail

    Log GetLogLevel($name, 2), "messenger set $name $v";

    #   set stats
    # $hash->{CHANGED}[0] = $v;
    $hash->{READINGS}{state}{TIME} = TimeNow();
    $hash->{READINGS}{state}{VAL}  = $v;
    return undef;
}

sub MSGMail_error($$$)
{
    my ($name, $msg, $error) = @_;
    Log3 $name, 0, "$name: $msg: $error";
    return $error;
}

##############################################
# Helper Function to connect to mail server
# Returns a smtp connection (see Net:SMTP)
##############################################
sub MSGMail_conn($)
{
    my ($hash) = @_;
    my ($name) = $hash->{NAME};

    my $smtphost = AttrVal($name, "smtphost", "");
    my $smtpport = AttrVal($name, "smtpport", "465");    # 465 is the default port

    if ($MSGMail_SSL)
    {
        if ($MSGMail_SMTP < 3.00)
        {
            Log3 $name, 3, "$name: try to connect with Net::SMTP::SSL";
            return Net::SMTP::SSL->new($smtphost, Port => $smtpport);
        }
        else
        {
            Log3 $name, 3, "$name: try to connect with Net::SMTP";
            return Net::SMTP->new(Host => $smtphost, Port => $smtpport, SSL => 1);
        }
    }
    Log3 $name, 0, "$name: SSL not available. Connection will fail";
    return undef;
}

1;

=pod
=begin html

<a name="MSGMail"></a>
<h3>MSGMail</h3>
<ul>
  The MSGMail device is used to send mail messages to a recipient by connecting 
  to a SMTP server. Currently MSGMail supports only servers, that allow SSL secured connections
  like Googlemail, GMX, Yahoo or 1und1. 
  MSGMail requires the perl pacakge <b>MAIL::Lite</b>. 
  For SSL support, Net::SMTP version 3.06 is required. On systems with an older version of Net::SMTP, 
  MSGMail requires the package <b>Net::SMTP::SSL</b>.
  <br><br>

  <a name="MSGMailDefine"></a>
  <b>Define</b>
  <ul><br>
          <code>define &lt;name&gt; MSGMail &lt;from&gt; &lt;to&gt; &lt;smtphost&gt; &lt;authfile&gt;</code><br><br>
          Specifies the MSGMail device. At definition the message counter is set to 0.
          From, To, SMTPHost and the authfile (see attributes below) need to be defined
          at definition time.
  </ul>
                  <br>
          Examples:
          <ul>
                  <code>define myMail MSGMail from@address.com to@address.com smtp.provider.host /etc/msgauthfile</code>
          </ul><br>

  <a name="MSGMailSet"></a>
  <b>Set</b><br>
  <ul><code>set &lt;name&gt; add|clear|list|send [text]</code><br>
	Set is used to manipulate the message buffer of the device. The message
	buffer is an array of lines of data, stored serial based on the incoming
	time into the buffer. Lines of data inside the buffer could not be deleted
	anymore, except of flashing the whole buffer.<br>
	<ul><b>add</b><br> to add lines of data to the message buffer. All data behind
	"add" will be interpreted as text message. To add a carriage return to the data,
	please use the CR attribute.
	</ul>
	<ul><b>clear</b><br> to flush the message buffer and set the line counter to 0.
		All the lines of data are deleted and the buffer is flushed.</ul>
	<ul><b>list</b><br> to list the message buffer.<br></ul><br>
        <ul><b>send</b><br> to send the message buffer.<br></ul><br>
		<br>
		Examples:
		<ul>
			<code>set myMail add Dies ist Textzeile 1</code><br>
			<code>set myMail add Dies ist Textzeile 2</code><br>
			<code>set myMail clear</code><br><br>
			Full working example to send two lines of data to a recipent:<br>
			<code>define myMail MSGMail donald.duck@entenhausen.com dagobert.duck@duck-banking.com smtp.entenhausen.net /etc/fhem/msgmailauth</code><br>
			<code>attr myMail smtpport 9999</code><br>
			<code>attr myMail subject i need more money</code><br>
			<code>attr myMail CR 0</code><br>
			<code>set myMail add Please send me </code><br>
			<code>set myMail add 1.000.000 Taler</code><br>
			<code>set myMail send</code><br>
			<code>set myMail clear</code><br>
		</ul><br>
  </ul>

  <a name="MSGMailattr"></a>
  <b>Attributes</b>
  <ul>
    Almost all of these attributes are not optional, most of them could set at definition.<br>
    <li><a href="MSGMailFrom">from</a><br>
		sets the mail address of the sender</li>
    <li><a href="MSGMailTo">to</a><br>
		sets the mail address of the recipent</li>
    <li><a href="MSGMailsmtphost">smtphost</a><br>
		sets the name of the smtphost, for example for GMX
		you could use mail.gmx.net or for Googlemail the smtphost is
		smtp.googlemail.com</li>
    <li><a href="MSGMailsmtphost">smtpport</a> (optional)<br>
		sets the port of the smtphost, for example for GMX
		or for Googlemail the smtport is 465, which is also
		the default and do not need to be set</li>
    <li><a href="MSGMailsubject">subject</a> (optional)<br>
		sets the subject of this email. Per default the subject is set to "FHEM"<br>
		</li>
    <li><a href="MSGMailauthfile">authfile</a><br>
		sets the authfile for the SSL connection to the SMTP host<br>
		the authfile is a simple textfile with the userid in line 1 and
		the password in line 2.<br>
		Example:<br>
		<code>123user45</code><br>
		<code>strenggeheim</code><br>
		It is a good behaviour to protect this data and put the file, for
		example into the /etc directory and set the rights to 440
		(chmod 440 /etc/msgmailauthfile), so that not everyone could see the contents
		of the file. FHEM must have access to this file to read the userid and password.
		<br>
		</li>
    <li><a href="MSGFilenameCR">CR</a><br>
		set the option to write a carriage return at the end of the line.
		CR could be set to 0 or 1, 1 enables this feature.
		Per default this attribute is enabled</li>
    <li><a href="#loglevel">loglevel</a></li>
  </ul>
</ul>


=end html
=cut
