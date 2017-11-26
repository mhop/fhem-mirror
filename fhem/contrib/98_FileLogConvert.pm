#####################################################################################
# $Id$
#
# Usage
# 
# define <name> FileLogConvert [DbLog-device]
#
#####################################################################################

package main;

use strict;
use warnings;
use Blocking;

sub FileLogConvert_Initialize($)
{
  my ($hash) = @_;
  $hash->{AttrFn}       = "FileLogConvert_Attr";
  $hash->{DefFn}        = "FileLogConvert_Define";
  $hash->{GetFn}        = "FileLogConvert_Get";
  $hash->{SetFn}        = "FileLogConvert_Set";
  $hash->{UndefFn}      = "FileLogConvert_Undef";
  $hash->{AttrList}     = "logdir $readingFnAttributes";
}

sub FileLogConvert_Define($$)
{
  my ($hash,$def) = @_;
  my @args = split " ",$def;
  return "Usage: define <name> FileLogConvert [DbLog-device]" if (@args < 2 || @args > 3);
  my ($name,$type,$logdev) = @args;
  if (!$logdev)
  {
    my @logdevs;
    foreach my $dev (devspec2array("TYPE=DbLog"))
    {
      push @logdevs,$dev;
    }
    if (@logdevs == 1)
    {
      return "$logdevs[0] doesn't exists" if (!IsDevice($logdevs[0]));
      $hash->{DEF} = $logdevs[0];
      $logdev = $logdevs[0];
    }
    elsif (@logdevs > 1)
    {
      return "Found too many available DbLog devives! Please specify the DbLog device you want! Available DbLog devices: ".join(",",@logdevs);
    }
    else
    {
      return "No DbLog device found! Please define a DbLog device first!";
    }
  }
  else
  {
    return "$logdev doesn't exists!" if (!IsDevice($logdev));
    return "$logdev is not a valid DbLog device!" if ($defs{$logdev}->{TYPE} ne "DbLog");
  }
  Log3 $name,3,"FileLogConvert ($name) - defined with DbLog $logdev" if ($init_done);
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state","Initialized");
  readingsBulkUpdate($hash,"cmd","") if (!defined ReadingsVal($name,"cmd",undef));
  readingsBulkUpdate($hash,"destination","") if (!defined ReadingsVal($name,"destination",undef));
  readingsBulkUpdate($hash,"events","") if (!defined ReadingsVal($name,"events",undef));
  readingsBulkUpdate($hash,"file-analysed","") if (!defined ReadingsVal($name,"file-analysed",undef));
  readingsBulkUpdate($hash,"file-source","") if (!defined ReadingsVal($name,"file-source",undef));
  readingsBulkUpdate($hash,"lines-analysed","") if (!defined ReadingsVal($name,"lines-analysed",undef));
  readingsBulkUpdate($hash,"lines-converted","") if (!defined ReadingsVal($name,"lines-converted",undef));
  readingsBulkUpdate($hash,"lines-imported","") if (!defined ReadingsVal($name,"lines-imported",undef));
  readingsBulkUpdate($hash,"regex","") if (!defined ReadingsVal($name,"regex",undef));
  readingsEndUpdate($hash,0);
  return;
}

sub FileLogConvert_Undef($$)
{
  my ($hash,$arg) = @_;
  my $name = $hash->{NAME};
  BlockingKill($hash->{helper}{RUNNING_PID}) if ($hash->{helper}{RUNNING_PID});
  Log3 $name,3,"FileLogConvert ($name) - deleted";
  return;
}

sub FileLogConvert_Get($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  my $source = $args[0] ? $args[0] : "";
  my $dir = "$attr{global}{modpath}/".AttrVal($name,"logdir","log");
  my $files = FileLogConvert_Dir($hash);
  my @logs = @{$files->{logs}};
  my @flogs = @{$files->{log}};
  my $params = "fileEvents:".join(",",sort @flogs) if (@flogs);
  if ($cmd eq "fileEvents")
  {
    return "You have to provide a source file" if (!$source);
    return "Work already in progress... Please wait for the current process to finish." if ($hash->{helper}{RUNNING_PID} && !$hash->{helper}{RUNNING_PID}{terminated});
    return "$source is not an availabe log file!" if (!grep(/^$source$/,@logs));
    readingsSingleUpdate($hash,"state","analysing $source",1);
  }
  else
  {
    return "Unknown argument $cmd for $name, choose one of $params" if ($params);
    return;
  }
  my %helper = (
    "cmd"         => "$cmd",
    "dir"         => "$dir",
    "source"      => "$source"
  );
  $hash->{helper}{filedata} = \%helper;
  $hash->{helper}{RUNNING_PID} = BlockingCall("FileLogConvert_FileRead","$name","FileLogConvert_FileRead_finished");
  return;
}

sub FileLogConvert_Set($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  my $source = $args[0] ? $args[0] : "";
  my $eventregex = $args[1] ? $args[1] : "";
  my $dir = "$attr{global}{modpath}/".AttrVal($name,"logdir","log");
  my $files = FileLogConvert_Dir($hash);
  my @logs  = @{$files->{logs}};
  my @flogs = @{$files->{log}};
  my @fcsvs = @{$files->{csv}};
  my @fsqls = @{$files->{sql}};
  my @fdns  = @{$files->{db}};
  my @paras;
  push @paras,"convert2csv" if (@fcsvs);
  push @paras,"convert2sql" if (@fsqls);
  push @paras,"import2DbLog" if (@fdns);
  my $para = join(" ",@paras) if (@paras);
  if ($cmd =~ /^(fileEvents|convert2(csv|sql)|import2DbLog)$/)
  {
    return "You have to provide a source file" if (!$source);
    return "Work already in progress... Please wait for the current process to finish." if ($hash->{helper}{RUNNING_PID} && !$hash->{helper}{RUNNING_PID}{terminated});
    return "$source is not an availabe log file!" if (!grep(/^$source$/,@logs));
    my $ofile = $source;
    $ofile =~ s/log$//;
    $ofile .= "csv" if ($cmd eq "convert2csv");
    $ofile .= "sql" if ($cmd eq "convert2sql");
    $ofile .= $hash->{DEF} if ($cmd eq "import2DbLog");
    my $f = $ofile;
    $f = "Dblog $hash->{DEF}";
    my $acon = "$source has already been converted into $f";
    $acon =~ s/convert/import/ if ($cmd eq "import2DbLog");
    return $acon if ($cmd eq "convert2csv" && @fcsvs && !grep(/^$source$/,@fcsvs));
    return $acon if ($cmd eq "convert2sql" && @fsqls && !grep(/^$source$/,@fsqls));
    return $acon if ($cmd eq "import2DbLog" && @fdns && !grep(/^$source$/,@fdns));
    my $state = $cmd =~ /^convert2(csv|sql)$/ ? "converting" : $cmd eq "fileEvents" ? "analysing" : "importing";
    my $mstate = "$state $source";
    $mstate .= " $eventregex" if ($eventregex);
    readingsSingleUpdate($hash,"state",$mstate,1);
  }
  else
  {
    return "$cmd is not a valid command for $name, please choose one of $para" if ($para);
    return;
  }
  my %helper = (
    "cmd"         => "$cmd",
    "dir"         => "$dir",
    "source"      => "$source",
    "dblog"       => "$hash->{DEF}",
    "eventregex"  => "$eventregex"
  );
  $hash->{helper}{filedata} = \%helper;
  $hash->{helper}{RUNNING_PID} = BlockingCall("FileLogConvert_FileRead","$name","FileLogConvert_FileRead_finished");
  return;
}

sub FileLogConvert_FileRead($)
{
  my ($string) = @_;
  return unless (defined $string);
  my @a       = split /\|/,$string;
  my $name    = $a[0];
  my $hash    = $defs{$name};
  my $cmd     = $hash->{helper}{filedata}{cmd};
  my $dir     = $hash->{helper}{filedata}{dir};
  my $source  = $hash->{helper}{filedata}{source};
  my $dblog   = $hash->{helper}{filedata}{dblog};
  my $eventregex = $hash->{helper}{filedata}{eventregex} ? $hash->{helper}{filedata}{eventregex} : ".*";
  my $stateregex = $hash->{helper}{filedata}{stateregex} ? $hash->{helper}{filedata}{stateregex} : ".*";
  $stateregex =~ s/:/|/g;
  delete $hash->{helper}{filedata};
  my $fname   = "$dir/$source";
  my @events;
  if (!open FH,$fname)
  {
    close(FH);
    my $err = encode_base64("could not read $fname","");
    return "$name|''|$err";
  }
  my $arows = 0;
  my $crows = 0;
  my $dest = $source;
  $dest =~ s/log$/csv/ if ($cmd eq "convert2csv");
  $dest =~ s/log$/sql/ if ($cmd eq "convert2sql");
  $dest =~ s/log$/$dblog/ if ($cmd eq "import2DbLog");
  if ($cmd =~ /^(convert2(csv|sql)|import2DbLog)$/)
  {
    if (!open WH,">>$dir/$dest")
    {
      close WH;
      my $err = encode_base64("could not write $dir/$dest","");
      return "$name|''|$err";
    }
  }
  while (my $line = <FH>)
  {
    $arows++;
    chomp $line;
    $line =~ s/\s{2,}/ /g;
    if ($cmd eq "fileEvents")
    {
      next unless ($line =~ /^(\d{4}-\d{2}-\d{2})_(\d{2}:\d{2}:\d{2})\s([A-Za-z0-9\.\-_]+)\s([A-Za-z0-9\.\-_]+):\s(\S+)(\s.*)?$/
        || $line =~ /^(\d{4}-\d{2}-\d{2})_(\d{2}:\d{2}:\d{2})\s([A-Za-z0-9\.\-_]+)\s([A-Za-z0-9\.\-_]+)$/);
      push @events,$4 if (!grep(/^$4$/,@events));
    }
    else
    {
      my $i_date;
      my $i_time;
      my $i_device;
      my $i_type;
      my $i_reading;
      my $i_event;
      my $i_value;
      my $i_unit = "";
      if ($line =~ /^(\d{4}-\d{2}-\d{2})_(\d{2}:\d{2}:\d{2})\s([A-Za-z0-9\.\-_]+)\s([A-Za-z0-9\.\-_]+):\s(\S+)(\s.*)?$/)
      {
        $i_date = $1;
        $i_time = $2;
        $i_device = $3;
        $i_reading = $4;
        $i_value = $5;
        my $rest = $6 if ($6);
        next if ($i_reading !~ /^($eventregex)$/);
        $i_unit = $rest ? (split " ",$rest)[0] : "";
        $i_unit = "" if ($i_unit =~ /^[\/\[\{\(]/);
        $i_type = IsDevice($i_device) ? uc $defs{$i_device}->{TYPE} : "";
        $i_event = "$i_reading: $i_value";
        $i_event .= " $rest" if ($rest);
      }
      elsif ($line =~ /^(\d{4}-\d{2}-\d{2})_(\d{2}:\d{2}:\d{2})\s([A-Za-z0-9\.\-_]+)\s([A-Za-z0-9\.\-_]+)$/)
      {
        $i_date = $1;
        $i_time = $2;
        $i_device = $3;
        $i_value = $4;
        next if ($i_value !~ /^($eventregex)$/);
        $i_type = IsDevice($i_device) ? uc $defs{$i_device}->{TYPE} : "";
        $i_reading = "state";
        $i_event = $i_value;
      }
      else
      {
        next;
      }
      $crows++;
      my $ret;
      $ret = "INSERT INTO history (TIMESTAMP,DEVICE,TYPE,EVENT,READING,VALUE,UNIT) VALUES ('$i_date $i_time','$i_device','$i_type','$i_event','$i_reading','$i_value','$i_unit');" if ($cmd =~ /^(import2DbLog|convert2sql)$/);
      $ret = '"'.$i_date.' '.$i_time.'","'.$i_device.'","'.$i_type.'","'.$i_event.'","'.$i_reading.'","'.$i_value.'","'.$i_unit.'"' if ($cmd eq "convert2csv");
      DbLog_ExecSQL($defs{$dblog},$ret) if ($cmd eq "import2DbLog");
      print WH $ret,"\n" if ($cmd =~ /^convert2(csv|sql)$/);
    }
  }
  close WH if ($cmd =~ /^(convert2(csv|sql)|import2DbLog)$/);
  close FH;
  my $events = @events ? encode_base64(join(" ",@events),"") : "";
  my $regex = $eventregex ? encode_base64($eventregex,"") : "";
  return "$name|$cmd,$source,$arows,$dest,$crows,$events,$regex";
}

sub FileLogConvert_FileRead_finished($)
{
  my ($string)    = @_;
  my @a           = split /\|/,$string;
  my $name        = $a[0];
  my $hash        = $defs{$name};
  delete $hash->{helper}{RUNNING_PID};
  my @data        = split /,/,$a[1];
  my $cmd         = $data[0];
  my $source      = $data[1];
  my $arows       = $data[2];
  my $dest        = $data[3];
  my $crows       = $data[4];
  my @events      = $data[5] ? sort(split " ",decode_base64($data[5])) : undef;
  my $regex       = $data[6] ? decode_base64($data[6]) : "";
  my $err         = $a[2] ? decode_base64($a[2]) : "";
  readingsBeginUpdate($hash);
  if ($err)
  {
    readingsBulkUpdate($hash,"state",$err);
  }
  else
  {
    if ($cmd eq "fileEvents")
    {
      my $events = @events ? join(" ",@events) : "";
      readingsBulkUpdate($hash,"state","analysis done");
      readingsBulkUpdate($hash,"file-analysed",$source);
      readingsBulkUpdate($hash,"lines-analysed",$arows);
      readingsBulkUpdate($hash,"events",$events);
      $events =~ s/\s/|/g;
      readingsBulkUpdate($hash,"cmd","$source $events");
    }
    elsif ($cmd =~ /^convert2(csv|sql)$/)
    {
      readingsBulkUpdate($hash,"state","convert done");
      readingsBulkUpdate($hash,"file-source",$source);
      readingsBulkUpdate($hash,"destination",$dest);
      readingsBulkUpdate($hash,"lines-analysed",$arows);
      readingsBulkUpdate($hash,"lines-converted",$crows);
      readingsBulkUpdate($hash,"regex",$regex);
    }
    elsif ($cmd eq "import2DbLog")
    {
      readingsBulkUpdate($hash,"state","import done");
      readingsBulkUpdate($hash,"file-source",$source);
      readingsBulkUpdate($hash,"destination",$hash->{DEF});
      readingsBulkUpdate($hash,"lines-analysed",$arows);
      readingsBulkUpdate($hash,"lines-imported",$crows);
      readingsBulkUpdate($hash,"regex",$regex);
    }
  }
  readingsEndUpdate($hash,1);
  return undef;
}

sub FileLogConvert_Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash = $defs{$name};
  if ($cmd eq "set")
  {
    if ($attr_name eq "logdir" && $init_done)
    {
      if (!opendir(DIR,"$attr{global}{modpath}/$attr_value"))
      {
        close DIR;
        return "Folder $attr_value is not available, please choose another one.";
      }
      close DIR;
      Log3 $name,3,"FileLogConvert ($name) - attribute $attr_name added with value $attr_value" if ($init_done);
    }
  }
  return;
}

sub FileLogConvert_Dir($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dir = "$attr{global}{modpath}/".AttrVal($name,"logdir","log");
  my @logs;
  my @csvs;
  my @sqls;
  my @dones;
  opendir(DIR,$dir);
  while (my $file = readdir(DIR))
  {
    next unless (-f "$dir/$file");
    next unless ($file =~ /\.(log|csv|sql|$hash->{DEF})$/);
    next if ($file =~ /^fhem-/);
    push @logs,$file if ($file =~ /log$/);
    push @csvs,$file if ($file =~ /csv$/);
    push @sqls,$file if ($file =~ /sql$/);
    push @dones,$file if ($file =~ /$hash->{DEF}$/);
  }
  closedir(DIR);
  $hash->{files_csv} = scalar @csvs;
  $hash->{files_sql} = scalar @sqls;
  $hash->{files_log} = scalar @logs;
  $hash->{files_db}  = scalar @dones;
  my @flogs;
  my @fcsvs;
  my @fsqls;
  my @fdns;
  foreach my $f (@logs)
  {
    my $fname = $f;
    $fname =~ s/\.log$//;
    push @flogs,$f if (!grep(/^$fname.csv$/,@csvs) || !grep(/^$fname.sql$/,@sqls) || !grep(/^$fname.$hash->{DEF}$/,@dones));
    push @fcsvs,$f if (!grep(/^$fname.csv$/,@csvs));
    push @fsqls,$f if (!grep(/^$fname.sql$/,@sqls));
    push @fdns,$f  if (!grep(/^$fname.$hash->{DEF}$/,@dones));
  }
  my %files = (
    "logs"        => \@logs,
    "log"         => \@flogs,
    "csv"         => \@fcsvs,
    "sql"         => \@fsqls,
    "db"          => \@fdns
  );
  return \%files;
}

1;

=pod
=item helper
=item summary    convert FileLogs to csv or sql file or import directly to DbLog
=item summary_DE konvertiert FileLogs zu csv oder sql Datei oder importiert direkt in DbLog
=begin html

<a name="FileLogConvert"></a>
<h3>FileLogConvert</h3>
<ul>
  With <i>FileLogConvert</i> you can convert existing FileLog(s) to a csv or sql file or import directly to your DbLog.<br>
  Before converting/importing you can/should analyse the FileLog file(s) for available events. Then you can specify only your prefered events to convert/import.<br>
  While converting/importing, only lines matching the event log string (TIMESTAMP,DEVICE,EVENT) will be converted/imported. All other lines will be ignored.<br>
  <i>FileLogConvert</i> is trying to get the TYPE of each device from your current installation and will write this to csv/sql/DbLog.<br>
  <i>FileLogConvert</i> is also trying to find a unit for each events value and will also write this to csv/sql/DbLog.
  <br>
  <br>
  <a name="FileLogConvert_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; FileLogConvert [DbLog-device]</code><br>
  </ul>
  <br>
  Example for defining FileLogConvert:
  <br><br>
  <ul>
    <code>define LogConvert FileLogConvert</code><br>
  </ul>
  <br>
  If only one DbLog device is available, you don't have to provide its name.</br>
  If more than one DbLog device is available, you must provide its name.</br>
  <br>
  <ul>
    <code>define LogConvert FileLogConvert DbLog</code><br>
  </ul>
  <br>
  <a name="FileLogConvert_get"></a>
  <p><b>get &lt;required&gt;</b></p>
  <ul>
    <li>
      <i>fileEvents &lt;NAME-FileLog-FILE&gt;</i><br>
      analyse all lines of the log file and check for available events<br>
      available events will be listed space separated in reading events<br>
      proposals for possible set commands can be found in reading cmd<br>
      amount of analysed lines can be found in reading lines-analysed<br>
      last analysed file can be found in reading file-analysed<br>
      if a file is converted in all formats and imported into DbLog it will be hidden from the dropdown list
    </li>
  </ul>
  <br>
  <a name="FileLogConvert_set"></a>
  <p><b>set &lt;required&gt; [optional]</b></p>
  <ul>
    <li>
      <i>convert2csv &lt;NAME-FileLog-FILE&gt; [REGEX-OF-EVENTS-TO-APPLY-TO-CSV]</i><br>
      convert given FileLog file to csv file<br>
      if you specify a regex of events, then only these events will be applied to the resulting csv file<br>
      name of resulting file can be found in reading destination<br>
      amount of converted lines can be found in reading lines-converted
    </li>
    <li>
      <i>convert2sql &lt;NAME-FileLog-FILE&gt; [REGEX-OF-EVENTS-TO-APPLY-TO-SQL]</i><br>
      convert given FileLog file to sql file<br>
      if you specify a regex of events, then only these events will be applied to the resulting sql file<br>
      name of resulting file can be found in reading destination<br>
      amount of converted lines can be found in reading lines-converted
    </li>
    <li>
      <i>import2DbLog &lt;NAME-FileLog-FILE&gt; [REGEX-OF-EVENTS-TO-APPLY-TO-DbLog]</i><br>
      import given FileLog file to DbLog<br>
      if you specify a regex of events, then only these events will be applied to DbLog<br>
      name of DbLog device can be found in reading destination<br>
      amount of converted lines can be found in reading lines-converted
    </li>
  </ul>
  <br>
  <a name="FileLogConvert_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <b><i>logdir</i></b><br>
      alternative log directory<br>
      must be a valid (relative) subfolder of "./fhem/"<br>
      relative paths are also possible to address paths outside "./fhem/", e.g. "../../home/pi/oldlogs"<br>
      default: log
    </li>
  </ul>
  <br>
  <a name="FileLogConvert_read"></a>
  <p><b>Readings</b></p>
  <ul>
    <li>
      <i>cmd</i><br>
      proposal for possible convert/import command created by fileEvents
    </li>
    <li>
      <i>destination</i><br>
      last destination of the conversation<br>
      when importing to DbLog, the name of the DbLog device can be found here<br>
      when converting a FileLog to csv or sql, the created file name can be found here
    </li>
    <li>
      <i>events</i><br>
      space separated list of events found by fileEvents
    </li>
    <li>
      <i>file-analysed</i><br>
      name of the last analysed FileLog file
    </li>
    <li>
      <i>file-source</i><br>
      name of the last source file
    </li>
    <li>
      <i>lines-analysed</i><br>
      amount of lines analysed by fileEvents
    </li>
    <li>
      <i>lines-converted</i><br>
      amount of lines converted by convert2csv and convert2sql
    </li>
    <li>
      <i>lines-imported</i><br>
      amount of lines imported by import2DbLog
    </li>
    <li>
      <i>regex</i><br>
      last used regex
    </li>
    <li>
      <i>state</i><br>
      current state or success or error
    </li>
  </ul>
</ul>

=end html
=cut
