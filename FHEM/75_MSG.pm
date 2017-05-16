##############################################
# $Id: 75_MSG.pm 2012-06-20 18:29:00 rbente
##############################################
package main;

use strict;
use warnings;
use Switch;
use MIME::Lite;
use Net::SMTP::SSL;
my %sets = (
  "send" => "MSG",
  "write" => "MSG",
);
###########################################################
## Initialize Function
##
############################################################
sub
MSG_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "MSG_Set";
  $hash->{DefFn}     = "MSG_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

###########################################################
## Set Function
##
############################################################
sub
MSG_Set($@)
{
	my ($hash, @a) = @_;
    return "Unknown argument $a[1], choose one of  ->  " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

	my $name = shift @a;

	return "no set value specified" if(int(@a) < 1);

	return "Unknown argument ?" if($a[0] eq "?");
##########  Check, if we have send or wait as parameter	
	if(($a[0] eq "send") || ($a[0] eq "write"))
	{
##########  Check if the device is defined that we like to use as frontend	
		return "Please define $a[1] first" if(!defined($defs{$a[1]}));
##########  switch based on the device type
##########  valid device types are:
##########     MSGFile       =  write to a file
##########     MSGMail       =  send an email
		if(!defined($defs{$a[1]}{TYPE}))
		{
			return "TYPE for $defs{$a[1]} not defined";
		}

####################################################################################################
##
##     M S G F i l e
##		
####################################################################################################
		elsif($defs{$a[1]}{TYPE} eq "MSGFile")
		{
			
				return "No filename specified, use  attr <name> filename <filename> $a[1] $defs{$a[1]}{TYPE}" if (!AttrVal($a[1],"filename",""));
				
##########  open the file, new = delete file before create it
##########                 append = add lines to the existing file contents
				if(AttrVal($a[1],"filemode","") eq "new")
				{
					open(FHEMMSGFILE, ">" . AttrVal($a[1],"filename",""))  || return "Can not open the file: $!";
				}
				else
				{   
					open(FHEMMSGFILE, ">>" . AttrVal($a[1],"filename","")) || return "Can not open the file: $!";
				}
##########   loop thru the stored lines and write them to the file
##########        number of lines are in the Readings / msgcount				
				my $i;
				if(ReadingsVal($a[1],"msgcount",0) > 0)
				{
					for($i=0;$i<ReadingsVal($a[1],"msgcount",0);$i++)
					{
						print FHEMMSGFILE $data{$a[1]}{$i}  || return "Can not write to the file: $!";;
					}
				}
##########   close the file and send a message to the log
				close(FHEMMSGFILE);
				Log 1, "<MSG> write to File: " . AttrVal($a[1],"filename","");
		}   # END MSGFile
			
####################################################################################################
##
##     M S G M a i l
##		
##  We use MAIL::Lite to compose the message, because it works very well at this and
##  we use Net::SMTP::SSL to connect to the smtp host and manage the authenification,
##  because MAIL:Lite is not very easy to manage with SSL connections
####################################################################################################
			
		elsif($defs{$a[1]}{TYPE} eq "MSGMail")
			{
			
##########	check all the needed data				
				my $from     = AttrVal($a[1],"from","");
				return "No <from> address specified, use  attr $a[1] from <mail-address>" if (!$from);
				my $to       = AttrVal($a[1],"to","");
				return "No <to> address specified, use  attr $a[1] to <mail-address>" if (!$to);
				my $subject  = AttrVal($a[1],"subject","");
				return "No <subject> specified, use  attr $a[1] subject <text>" if (!$subject);
				my $authfile = AttrVal($a[1],"authfile","");
				return "No <authfile> specified, use  attr $a[1] authfile <filename>" if (!$authfile);
				my $smtphost = AttrVal($a[1],"smtphost","");
				return "No <smtphost> name specified, use  attr $a[1] sntphost <hostname>" if (!$smtphost);
				my $smtpport = AttrVal($a[1],"smtpport","465");   # 465 is the default port
				my $cc       = AttrVal($a[1],"cc","");   # Carbon Copy
				open(FHEMAUTHFILE, "<" . $authfile) || return "Can not open authfile $authfile: $!";;
				my @auth = <FHEMAUTHFILE>;
				close(FHEMAUTHFILE);
				chomp(@auth);
#				Log 1, "MSG User = <" . @auth[0] . ">  Passwort = <" . @auth[1] . ">";

				

##########  compose message
				my $i;
				my $mess = "";
				for($i=0;$i<ReadingsVal($a[1],"msgcount",0);$i++)
				{
					$mess .= $data{$a[1]}{$i};
				}
				
				my $mailmsg = MIME::Lite->new(
						From          => $from,
						To            => $to,
						Subject       => $subject,
						Type          => 'text/plain',
						Data          => $mess
						);
						
##########  login to the SMTP Host using SSL and send the message
				my $smtp;
				my $smtperrmsg = "SMTP Error: ";
				$smtp = Net::SMTP::SSL->new($smtphost, Port=>$smtpport) or return $smtperrmsg . " Can't connect to host $smtphost";
				$smtp->auth(@auth[0], @auth[1]) or return $smtperrmsg . " Can't authenticate: " . $smtp->message();
				$smtp->mail($from) or return $smtperrmsg . $smtp->message();
				$smtp->to($to) or return $smtperrmsg . $smtp->message();
				if($cc ne '')
				{
					Log 1,"CC = $cc";
					$smtp->cc($cc) or return $smtperrmsg . $smtp->message();
				}
				$smtp->data() or return $smtperrmsg . $smtp->message();
				$smtp->datasend($mailmsg->as_string) or return $smtperrmsg .$smtp->message();
				$smtp->dataend() or return $smtperrmsg . $smtp->message();
				$smtp->quit() or return $smtperrmsg . $smtp->message();

				Log 1, "<MSG> send EMail: <$subject>";
			
		}  ###>  END MSGMail
		else
		{
			return "MSG Filetype $defs{$a[1]}{TYPE} unknown";
		}
	}  ###> END if(($a[0] eq "send") || ($a[0] eq "write"))
	my $v = join(" ", @a);
	Log GetLogLevel($name,2), "MSG set $name $v";
##########  update stats
	$hash->{CHANGED}[0] = $v;
	$hash->{STATE} = $v;
	$hash->{READINGS}{state}{TIME} = TimeNow();
	$hash->{READINGS}{state}{VAL} = $v;
	return undef;
}

###########################################################
## Define Function
##
############################################################

sub
MSG_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $errMSG_ = "wrong syntax: define <name> MSG";

  return $errMSG_    if(@a != 2);

  $hash->{STATE} = "ready";
  $hash->{TYPE}  = "MSG";
  return undef;
}


1;

=pod
=begin html

<a name="MSG"></a>
<h3>MSG</h3>
<ul>
  The MSG device is the backend device for all the message handling (I/O-engine).
  Under normal conditions only one MSG device is needed to serve multiple frontend
  message devices like file or email.
  <br><br>
  <a name="MSGdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; MSG </code><br><br>
  Specifies the MSG device. A single MSG device could serve multiple MSG frontends.
  But, for special conditions there could be defined more than one MSG device.
  </ul>
  <br>
  <a name="MSGset"></a>
  <b>Set</b>
  <ul>
  <code>set &lt;name&gt; send|write &lt;devicename&gt;</code><br><br>
  </ul>
  Notes:
  <ul>
  To send the data, both send or write could be used.<br>
  The devicename is the name of a frontenddevice previously
  defined. Based on the type of the frontend device, the MSG device
  will send out the lines of data.
  <br>
  Frontend devices are available for:<br>
  	<ul><li><a href="#MSGFile">File</a></li>
  	<li><a href="#MSGMail">EMail with SSL Authentification</a></li></ul>
  For details about this devices, please review the device-definitions.<br>
  After sending/writing the data, the data stills exists with the
  frontend device, MSG do not delete/purge any data, this must be done
  by the frontend device.
  <br><br>
  	Examples:
  	<ul>
  		<code>define myMsg MSG</code>
  	</ul>
  </ul>
  <a name="MSGVattr"></a>
  <b>Attributes</b>
  <ul>
      <li><a href="#IODev">IODev</a></li>
      <li><a href="#dummy">dummy</a></li>
      <li><a href="#ignore">ignore</a></li>
      <li><a href="#loglevel">loglevel</a></li>
      <li><a href="#eventMap">eventMap</a></li><br>
    </ul>
  </ul>
<br><br>

=end html
=cut
