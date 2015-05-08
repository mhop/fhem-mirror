########################################################
# $Id$
########################################################
#
# History:
#
# 2015-05-09: Assimilate file related code from 75_MSG
# 2015-05-06: Tidy up code for restructuring
# 2015-05-05: Remove dependency on Switch
# 2012      : Created by rbente
#
package main;

use strict;
use warnings;
my %sets = (
    "add"   => "MSGFile",
    "clear" => "MSGFile",
    "list"  => "MSGFile",
    "write" => "MSGFile"
);

##############################################
# Initialize Function
#  Attributes are:
#     filename    the name of the file
#     filemode    new = file will be created from scratch
#                 append = add the new lines to the end of the existing data
#     CR          0 = no CR added to the end of the line
#                 1 = CR added to the end of the line
##############################################
sub MSGFile_Initialize($)
{
    my ($hash) = @_;

    $hash->{SetFn}    = "MSGFile_Set";
    $hash->{DefFn}    = "MSGFile_Define";
    $hash->{UndefFn}  = "MSGFile_Undef";
    $hash->{AttrList} = "loglevel:0,1,2,3,4,5,6 filename filemode:new,append CR:0,1";
}

##############################################
# Define Function
# set the counter to 0
# and filemode to "new"
##############################################
sub MSGFile_Define($$)
{
    my ($hash, $def) = @_;
    my @a      = split("[ \t][ \t]*", $def);
    my $errmsg = "wrong syntax: define <name> MSGFile filename";
    my $name   = $hash->{NAME};

    return $errmsg if (@a != 3);
    $attr{$name}{filename} = $a[2];
    $attr{$name}{filemode} = "new";
    $attr{$name}{CR}       = "1";

    $hash->{STATE}                    = "ready";
    $hash->{TYPE}                     = "MSGFile";
    $hash->{READINGS}{msgcount}{TIME} = TimeNow();
    $hash->{READINGS}{msgcount}{VAL}  = 0;
    return undef;
}

##############################################
# Undefine Function
# flush all lines of data
##############################################
sub MSGFile_Undef($$)
{
    my ($hash, $name) = @_;
    my $i;

    # flush the data
    for ($i = 0 ; $i < ReadingsVal($name, "msgcount", 0) ; $i++)
    {
        $data{$name}{$i} = "";
    }

    delete($modules{MSGFile}{defptr}{ $hash->{CODE} }) if ($hash && $hash->{CODE});
    return undef;
}

##############################################
# Set Function
# all the data are stored in the global array  @data
# as counter we use a READING named msgcount
##############################################
sub MSGFile_Set($@)
{
    my ($hash, @a) = @_;
    return "Unknown argument $a[1], choose one of ->  " . join(" ", sort keys %sets)
      if (!defined($sets{ $a[1] }));

    my $name = shift @a;

    return "no set value specified" if (int(@a) < 1);
    return "Unknown argument ?" if ($a[0] eq "?");
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

        # get the highest number of lines, store the line in  @data and increase
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
    elsif ($a[0] eq "write")
    {
        return "No filename specified, use  attr <name> filename <filename> $name $defs{$name}{TYPE}"
          if (!AttrVal($name, "filename", ""));

        #  open the file, new = delete file before create it
        #                 append = add lines to the existing file contents
        if (AttrVal($name, "filemode", "") eq "new")
        {
            open(FHEMMSGFILE, ">" . AttrVal($name, "filename", ""))
              || return "Can not open the file: $!";
        }
        else
        {
            open(FHEMMSGFILE, ">>" . AttrVal($name, "filename", ""))
              || return "Can not open the file: $!";
        }

        # loop thru the stored lines and write them to the file
        #   number of lines are in the Readings / msgcount
        my $i;
        if (ReadingsVal($name, "msgcount", 0) > 0)
        {
            for ($i = 0 ; $i < ReadingsVal($name, "msgcount", 0) ; $i++)
            {
                print FHEMMSGFILE $data{ $name }{$i}
                  || return "Can not write to the file: $!";
            }
        }

        # close the file and send a message to the log
        close(FHEMMSGFILE);
        Log 1, "<MSG> write to File: " . AttrVal($name, "filename", "");
    }    # END MSGFile

    Log GetLogLevel($name, 2), "messenger set $name $v";

    # set stats
    # $hash->{CHANGED}[0] = $v;
    $hash->{READINGS}{state}{TIME} = TimeNow();
    $hash->{READINGS}{state}{VAL}  = $v;
    return undef;
}

1;

=pod
=begin html

<a name="MSGFile"></a>
<h3>MSGFile</h3>
<ul>
    The MSGFile device is used to write arbitrary data to a file on disk 
    or other media accessable through the filesystem. In order to write to a file,
    the access rights of the FHEM process to the specified file and path are relevant.
    To set the rights for a directory, please use OS related commands.
    <br><br>

    <a name="MSGFileDefine"></a>
    <b>Define</b>
    <ul><br>
            <code>define &lt;name&gt; MSGFile &lt;filename&gt;</code><br><br>
            Specifies the MSGFile device. At definition the message counter is set to 0.
            A filename must be specified at definition.
    </ul>
    <br>
    Examples:
    <ul>
      <code>define myFile MSGFile</code>
    </ul><br>
  <a name="MSGFileSet"></a>

  <b>Set</b><br>
  <ul><code>set &lt;name&gt; add|clear|list|write [text]</code><br>
	Set is used to manipulate the message buffer of the device. The message
	buffer is an array of lines of data, stored serial based on the incoming
	time into the buffer. Lines of data inside the buffer could not be deleted
	anymore, except of flashing the whole buffer.<br>

	<ul><b>add</b><br> to add lines of data to the message buffer. All data behind
	"add" will be interpreted as text message. To add a carriage return to the data,
	please use the CR attribute.
	</ul>

	<ul><b>clear</b><br> to flash the message buffer and set the line counter to 0.
		All the lines of data are deleted and the buffer is flushed.</ul>

	<ul><b>list</b><br> to list the message buffer.</ul><br>

        <ul><b>write</b><br> to write the message buffer to the associated file.</ul><br>
   </ul><br>
   Examples:
	<ul>
		<code>set myFile add Dies ist Textzeile 1</code><br>
		<code>set myFile add Dies ist Textzeile 2</code><br>
		<code>set myFile clear</code><br>
		<br>
		Full working example to write two lines of data to a file:<br>
		<code>define myFile MSGFile /tmp/fhemtest.txt</code><br>
		<code>attr myFile filemode append</code><br>
		<code>set myFile add Textzeile 1</code><br>
		<code>set myFile add Textzeile 2</code><br>
		<code>set myFile write</code><br>
		<code>set myFile clear</code><br>
	</ul><br>

  <a name="MSGFileVattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="MSGFilefilename">filename</a><br>
		sets the filename, must be a fully qualified filename.
		FHEM must have the rights to write this file to the directory</li>
    <li><a href="MSGFilefilemode">filemode</a><br>
		sets the filemode, valid are "new" or "append"<br>
			new creates a new, empty file and writes the data to this file. Existing files are cleared, the data is lost!<br>
			append uses, if available, an existing file and writes the
			buffer data to the end of the file. If the file do not exist, it will
			be created</li>
    <li><a href="MSGFilenameCR">CR</a><br>
		set the option to write a carriage return at the end of the line.
		CR could be set to 0 or 1, 1 enables this feature</li>
    <li><a href="#loglevel">loglevel</a></li>
  </ul>
</ul>

=end html
=cut
