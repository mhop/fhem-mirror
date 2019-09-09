##############################################
# $Id$


package main;

use strict;
use warnings;

my $missingModule = "";

eval "use Data::Dumper;1" or $missingModule .= "Data::Dumper ";
eval "use JSON;1" or $missingModule .= "JSON ";
eval "use Encode;1" or $missingModule .= "Encode ";
eval "use Date::Parse;1" or $missingModule .= "Date::Parse ";


#######################
# Global variables
my $version = "1.2.1";

my $srandUsed;

my %gets = (
  "version:noArg"     => "",
); 

## define variables for multi language
my %todoist_transtable_EN = ( 
  "check"             =>  "Check",
  "delete"            =>  "Delete",
  "refreshList"       =>  "Refresh list",
  "clearList"         =>  "Delete all elements",
  "alreadythere"      =>  "is already on the list",
  "error"             =>  "Error",
  "clearconfirm"      =>  "Are you sure? This deletes ALL the task in this list permanently.",
  "delconfirm"        =>  "Are you sure? This deletes the task permanently.",
  "gotodetail"        =>  "Click to show detail page of todoist device",
  "newentry"          =>  "Add new task to list",
  "nolistdata"        =>  "No data for this list",
  "idnotfound"        =>  "Could not find the task",
);

my %todoist_transtable_DE = ( 
  "check"             =>  "Erledigen",
  "delete"            =>  "Löschen",
  "refreshList"       =>  "Liste aktualisieren",
  "clearList"         =>  "Alle Elemente löschen",
  "alreadythere"      =>  "befindet sich bereits auf der Liste",
  "error"             =>  "Fehler",
  "clearconfirm"      =>  "Wirklich alle Elemente löschen?",
  "delconfirm"        =>  "Task wirklich löschen?",
  "gotodetail"        =>  "Detailseite des todoist-Devices aufrufen",
  "newentry"          =>  "Neuen Eintrag zur Liste hinzufügen",
  "nolistdata"        =>  "List ist leer",
  "idnotfound"        =>  "Task konnte nicht gefundern werden",
);

my $todoist_tt;

sub todoist_Initialize($) {
  my ($hash) = @_;

  $hash->{SetFn}        = "todoist_Set";
  $hash->{GetFn}        = "todoist_Get";
  $hash->{DefFn}        = "todoist_Define";
  $hash->{UndefFn}      = "todoist_Undefine";
  $hash->{AttrFn}       = "todoist_Attr";
  $hash->{RenameFn}     = "todoist_Rename";   
  $hash->{CopyFn}       = "todoist_Copy";
  $hash->{DeleteFn}     = "todoist_Delete";
  $hash->{NotifyFn}     = "todoist_Notify";
  
  $hash->{FW_detailFn}  = "todoist_detailFn";

  $hash->{AttrList}     = "disable:1,0 ".
                          "pollInterval ".
                          "do_not_notify ".
                          "sortTasks:1,0 ".
                          "getCompleted:1,0 ".
                          "showPriority:1,0 ".
                          "showAssignedBy:1,0 ".
                          "showResponsible:1,0 ".
                          "showIndent:1,0 ".
                          "showChecked:1,0 ".
                          "showDeleted:1,0 ".
                          "showOrder:1,0 ".
                          "hideId:1,0 ".
                          "autoGetUsers:1,0 ".
                          "avoidDuplicates:1,0 ".
                          "listDivider ".
                          "showDetailWidget:1,0 ".
                          "hideListIfEmpty:1,0 ".
                          "delDeletedLists:1,0 ".
                          "language:EN,DE ".
                          "sslVersion ".
                          $readingFnAttributes;
    
  $hash->{NotifyOrderPrefix} = "64-";                      
                          
  ## renew version and language in reload
  foreach my $d ( sort keys %{ $modules{todoist}{defptr} } ) {
      my $hash = $modules{todoist}{defptr}{$d};
      $hash->{VERSION} = $version;
      
      my $lang = AttrVal($hash->{NAME},"language", AttrVal("global","language","EN"));
      if( $lang eq "DE") {
        $todoist_tt = \%todoist_transtable_DE;
      }
      else{
        $todoist_tt = \%todoist_transtable_EN;
      }
  }
  
  return undef;
  #return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub todoist_Define($$) {
  my ($hash, $def) = @_;
  my $now = time();
  my $name = $hash->{NAME}; 
  
  if( !defined($todoist_tt) ){
    # in any attribute redefinition readjust language
    my $lang = AttrVal($name,"language", AttrVal("global","language","EN"));
    if( $lang eq "DE") {
      $todoist_tt = \%todoist_transtable_DE;
    }
    else{
      $todoist_tt = \%todoist_transtable_EN;
    }
  }
  
  
  my @a = split( "[ \t][ \t]*", $def );
  
  if ( int(@a) < 2 ) {
    my $msg = "Wrong syntax: define <name> todoist <Project id>";
    Log3 $name, 4, $msg;
    return $msg;
  }
  
  return "Cannot define a todoist device. Perl module(s) $missingModule is/are missing." if ( $missingModule );

  ## set internal variables
  $hash->{PID}=$a[2];
  $hash->{INTERVAL}=AttrVal($name,"pollInterval",undef)?AttrVal($name,"pollInterval",undef):1800;
  $hash->{VERSION}=$version;
  $hash->{MID}     = 'todoist_'.$a[2]; # 
  
  $modules{todoist}{defptr}{ $hash->{MID} } = $hash; #MID for internal purposes
  
  ## check if Access Token is needed
  my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
  my ($err, $password) = getKeyValue($index);
  
  $hash->{helper}{PWD_NEEDED}=1 if ($err || !$password);
    
  $hash->{NOTIFYDEV}= "global";
  
  if ($init_done) {
    ## at first, we delete old readings. List could have changed
    CommandDeleteReading(undef, "$hash->{NAME} (T|t)ask_.*");
    CommandDeleteReading(undef, "$hash->{NAME} listText");
    ## set state
    readingsSingleUpdate($hash,"state","active",1) if (!$hash->{helper}{PWD_NEEDED} && !IsDisabled($name) );
    readingsSingleUpdate($hash,"state","inactive",1) if ($hash->{helper}{PWD_NEEDED} || ReadingsVal($name,"state","-") eq "-");
    ## remove timers
    RemoveInternalTimer($hash,"todoist_GetTasks");
    ## start polling
    todoist_GetTasks($hash) if (!IsDisabled($name) && !$hash->{helper}{PWD_NEEDED});
  }
  
  return undef;
}

# get token from file
sub todoist_GetPwd($) {
  my ($hash) = @_;
  
  my $name=$hash->{NAME};
  
  my $pwd="";
  
  my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
  my $key = getUniqueId().$index;
  
  my ($err, $password) = getKeyValue($index);
        
  if ($err) {
    $hash->{helper}{PWD_NEEDED} = 1;
    Log3 $name, 4, "todoist ($name): unable to read password from file: $err";
    return undef;
  }   
  
  #some decryption
  if ( defined($password) ) {
    if ( eval "use Digest::MD5;1" ) {
       $key = Digest::MD5::md5_hex(unpack "H*", $key);
       $key .= Digest::MD5::md5_hex($key);
    }
   
    for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) {
       my $decode=chop($key);
       $pwd.=chr(ord($char)^ord($decode));
       $key=$decode.$key;
    }
  }
  
  return undef if ($pwd eq "");
  
  return $pwd;
}

## set error Readings and log
sub todoist_ErrorReadings($;$$) {
  my ($hash,$errorLog,$errorMessage) = @_;
  
  my $level=2;
  
  if (!defined($errorLog)) {
    $level=3;
    $errorLog="no data";
  }
  $errorMessage="no data" if (!defined($errorMessage));
  
  if (defined($hash->{helper}{errorData}) && $hash->{helper}{errorData} ne "") {
    $errorLog=$hash->{helper}{errorData};
  }
  
  if (defined($hash->{helper}{errorMessage}) && $hash->{helper}{errorMessage} ne "") {
    $errorMessage=$hash->{helper}{errorMessage};
  }
  
  my $name = $hash->{NAME};

  readingsBeginUpdate( $hash );
  readingsBulkUpdate( $hash,"error",$errorMessage );
  readingsBulkUpdate( $hash,"lastError",$errorMessage );
  readingsEndUpdate( $hash, 1 );
  
  Log3 $name,$level, "todoist ($name): Error Message: ".$errorMessage;
  Log3 $name,4, "todoist ($name): Api-Error Callback-data: ".$errorLog;
  
  $hash->{helper}{errorData}="";
  $hash->{helper}{errorMessage}="";
  return undef;
}


# update Task
sub todoist_UpdateTask($$$) {
  my ($hash,$cmd, $type) = @_;
  
  my($a, $h) = parseParams($cmd);
  
  my $name=$hash->{NAME};
  
  Log3 $name,5, "$name: Type: ".Dumper($type);
  
  my $param;
  
  my $pwd="";
  
  my %commands=();
  
  my $method;
  my $taskId=0;
  my $title;
  
  ## get Task-ID
  my $tid = @$a[0];
  
  ## check if ID is todoist ID (ID:.*) or title (TITLE:.*)
  my @temp=split(":",$tid);
  
  
  ## use the todoist ID
  if (@temp && $temp[0] =~ /id/i) {
    $taskId = int($temp[1]);
    $title = $hash->{helper}{"TITLE"}{$temp[1]};
  }
  ## use task content
  elsif (@temp && $temp[0] =~ /title/i) {
    $title = encode_utf8($temp[1]);
    $taskId = $hash->{helper}{"TITLES"}{$title} if ($hash->{helper}{"TITLES"});
  }
  ## use Task-Number 
  else {
    $tid=int($tid);
    $taskId=$hash->{helper}{"IDS"}{"Task_".$tid};
    $title=ReadingsVal($name,"Task_".sprintf('%03d',$tid),"-");
  }
  
  # error if we did not get a task id
  if ($taskId == 0) {
    map {FW_directNotify("#FHEMWEB:$_", "if (typeof todoist_ErrorDialog === \"function\") todoist_ErrorDialog('$name','$title ".$todoist_tt->{"idnotfound"}."','".$todoist_tt->{"error"}."')", "")} devspec2array("TYPE=FHEMWEB");
    todoist_ErrorReadings($hash,"Task $title could not be found for $type","task $title not found");
    return undef;
  }
  
  # some random string for UUID
  my $uuid = todoist_genUUID();
  
  # JSON String start- and endpoint
  my $commandsStart="[{";
      
  my $commandsEnd="}]";
  
  my $tType;
  my %args=();
  

  ## if no token is needed and device is not disabled, check token and get list vom todoist
  if (!$hash->{helper}{PWD_NEEDED} && !IsDisabled($name)) {
    
    ## get password
    $pwd=todoist_GetPwd($hash);
    
    if ($pwd) {
      Log3 $name,5, "$name: hash: ".Dumper($hash);
      
      ## complete a task
      if ($type eq "complete") {

        # variables for the commands parameter
        $tType = "item_complete";
        %args = (
          ids => '['.$taskId.']',
        );
        Log3 $name,5, "$name: Args: ".Dumper(%args);
        $method="POST";
      }
      ## close a task
      elsif ($type eq "close") {

        # variables for the commands parameter
        $tType = "item_close";
        %args = (
          id => $taskId,
        );
        Log3 $name,5, "$name: Args: ".Dumper(%args);
        $method="POST";
      }
      ## uncomplete a task
      elsif ($type eq "uncomplete") {

        # variables for the commands parameter
        $tType = "item_uncomplete";
        %args = (
          ids => '['.$taskId.']',
        );
        Log3 $name,5, "$name: Args: ".Dumper(%args);
        $method="POST";
      }
      ## update a task 
      elsif ($type eq "update") {
        $tType = "item_update";
        %args = (
          id => $taskId,
        );
        
        ## change title
        $args{'content'} = $h->{"title"} if($h->{'title'});
        ## change dueDate
        $args{'date_string'} = $h->{"dueDate"} if($h->{'dueDate'});
        $args{'date_string'} = "" if ($h->{'dueDate'} && $h->{'dueDate'} =~ /(null|none|nix|leer|del)/);
        ## change dueDate (if someone uses due_date in stead of dueDate)
        $args{'date_string'} = $h->{"due_date"} if ($h->{'due_date'});
        $args{'date_string'} = "" if ($h->{'dueDate'} && $h->{'due_date'} =~ /(null|none|nix|leer|del)/);
        ## change priority
        $args{'priority'} = int($h->{"priority"}) if ($h->{"priority"});
        ## Who is responsible for the task
        $args{'responsible_uid'} = $h->{"responsibleUid"} if ($h->{"responsibleUid"});
        $args{'responsible_uid'} = $h->{"responsible"} if ($h->{"responsible"});
        ## who assigned the task? 
        $args{'assigned_by_uid'} = $h->{"assignedByUid"} if ($h->{"assignedByUid"});
        $args{'assigned_by_uid'} = $h->{"assignedBy"} if ($h->{"assignedByUid"});
        ## order of the task
        $args{'item_order'} = $h->{"order"} if ($h->{"order"});
        ## indent of the task
        $args{'indent'} = $h->{"indent"} if ($h->{"indent"});
        ## parent_id
        $args{'parent_id'} = $h->{"parent_id"} if ($h->{"parent_id"});
        $args{'parent_id'} = $h->{"parentID"} if ($h->{"parentID"});
        $args{'parent_id'} = $h->{"parentId"} if ($h->{"parentId"});
        
        if ($args{'parent_id'}) {
          my $pid=$args{'parent_id'};
          if ($hash->{helper}{"INDENT"}{$pid}) {
            $args{'indent'} = int($hash->{helper}{"INDENT"}{$pid})+1;
          }
        }
        
        $args{'parent_id'} = "" if ($h->{"indent"}==1);
        
        ## remove attribute
        if ($h->{"remove"}) {
          my @temp;
          my @rem = split(",",$h->{"remove"});
          foreach my $r (@rem) {
            $args{'date_string'} = "" if ($r eq "dueDate" || $r eq "due_date");
            $args{'responsible_uid'} = "" if ($r eq "responsibleUid" || $r eq "responsible");
            $args{'assigned_by_uid'} = 0 if ($r eq "assignedByUid" || $r eq "assignedBy");
            if ($r eq "parent_id" || $r eq "parentID" || $r eq "parentId" || $r eq "indent") {
              $args{'indent'} = 1;
              $args{'parent_id'} = "";
            }
          }
          ## Debug
          #Log3 $name, 1, "wunderlist ($name): Debug: ".Dumper($datas{'remove'});
        }
          
        ## Debug
        #Log3 $name, 1, "todoist ($name): Debug: ".Dumper(%datas);
        
        $method="POST";
      }
      ## delete a task
      elsif ($type eq "delete") {
        $tType = "item_delete";
        %args = (
          ids => '['.$taskId.']',
        );
        $method="POST";
      }
      else {
        return undef;
      }
      
      Log3 $name,5, "todoist ($name): Data Array sent to todoist API: ".Dumper(%args);
      
      my $dataArr=$commandsStart.'"type":"'.$tType.'","temp_id":"'.$taskId.'","uuid":"'.$uuid.'","args":'.encode_json(\%args).$commandsEnd;
      
      Log3 $name,4, "todoist ($name): Data Array sent to todoist API: ".$dataArr;
    
      my $data= {
        token     =>    $pwd,
        commands  =>    $dataArr
      };
      
      Log3 $name,4, "todoist ($name): JSON sent to todoist API: ".Dumper($data);
      
      $param = {
        url        => "https://todoist.com/sync/v8/sync",
        data       => $data,
        tTitle     => $title,
        method     => $method,
        wType      => $type,
        taskId     => $taskId,
        timeout    => 7,
        header     => "Content-Type: application/x-www-form-urlencoded",
        hash       => $hash,
        callback   => \&todoist_HandleTaskCallback,  ## call callback sub to work with the data we get
      };
      
      Log3 $name,5, "todoist ($name): Param: ".Dumper($param);
      
      ## non-blocking access to todoist API
      InternalTimer(gettimeofday()+0.1, "HttpUtils_NonblockingGet", $param, 0);
    }
    else {
      todoist_ErrorReadings($hash,"access token empty");
    }
  }
  else {
    if (!IsDisabled($name)) {
      todoist_ErrorReadings($hash,"no access token set");
    }
    else {
      todoist_ErrorReadings($hash,"device is disabled");
    }
  
  }
  
  return undef;
}

# create Task
sub todoist_CreateTask($$) {
  my ($hash,$cmd) = @_;
  
  my($a, $h) = parseParams($cmd);
  
  my $name=$hash->{NAME};
  
  my $param;
  
  my $pwd="";
  
  my $assigne_id="";
  
  ## we try to send a due_date (in developement)
  my @tmp = split( ":", join(" ",@$a) );
  
  my $title=encode_utf8($tmp[0]);
  
  my $check=1;
  
  # we can avoid duplicates in FHEM. There may still come duplicates coming from another app
  if (AttrVal($name,"avoidDuplicates",0) == 1 && todoist_inArray(\@{$hash->{helper}{"TITS"}},$title)) {
    $check=-1;
  }
  
  if ($check==1) {
  
    ## if no token is needed and device is not disabled, check token and get list vom todoist
    if (!$hash->{helper}{PWD_NEEDED} && !IsDisabled($name)) {
      
      ## get password
      $pwd=todoist_GetPwd($hash);
      
      if ($pwd) {
      
        Log3 $name,5, "$name: hash: ".Dumper($hash);
        
        # data array for API - we could transfer more data        
        my $data = {
          project_id           => int($hash->{PID}),
          content              => $title,
          token                => $pwd,
        };
        
        ## check for dueDate as Parameter or part of title - push to hash
        if (!$tmp[1] && $h->{"dueDate"}) { ## parameter
          $data->{'date_string'} = $h->{"dueDate"};
        }
        elsif ($tmp[1]) { ## title
          $data->{'date_string'} = $tmp[1];
        }
        else {
        
        }
        
        ## if someone uses due_date - no problem
        $data->{'date_string'} = $h->{"due_date"} if ($h->{"due_date"});
        
        ## Task parent_id
        $data->{'parent_id'} = int($h->{"parent_id"}) if ($h->{"parent_id"});
        $data->{'parent_id'} = int($h->{"parentID"}) if ($h->{"parentID"});
        $data->{'parent_id'} = int($h->{"parentId"}) if ($h->{"parentId"});
        
        my $parentId = 0;
        $parentId = $data->{'parent_id'} if ($data->{'parent_id'});
        
        ## Task priority
        $data->{'priority'} = $h->{"priority"} if ($h->{"priority"});
        
        ## who is responsible for the task?
        $data->{'responsible_uid'} = $h->{"responsibleUid"} if ($h->{"responsibleUid"});
        $data->{'responsible_uid'} = $h->{"responsible"} if ($h->{"responsible"});
        
        ## who assigned the task? 
        $data->{'assigned_by_uid'} = $h->{"assignedByUid"} if ($h->{"assignedByUid"});
        $data->{'assigned_by_uid'} = $h->{"assignedBy"} if ($h->{"assignedByUid"});
        
        ## order of the task
        $data->{'item_order'} = $h->{"order"} if ($h->{"order"});
        
        ## indent of the task
        $data->{'indent'} = $h->{"indent"} if ($h->{"indent"});
        
        
        
        Log3 $name,4, "todoist ($name): Data Array sent to todoist API: ".Dumper($data);
      
        
        $param = {
          url        => "https://todoist.com/sync/v8/items/add",
          data       => $data,
          tTitle     => $title,
          method     => "POST",
          wType      => "create",
          parentId   => $parentId,
          timeout    => 7,
          header     => "Content-Type: application/x-www-form-urlencoded",
          hash       => $hash,
          callback   => \&todoist_HandleTaskCallback,  ## call callback sub to work with the data we get
        };
        
        Log3 $name,5, "todoist ($name): Param: ".Dumper($param);
        
        ## non-blocking access to todoist API
        InternalTimer(gettimeofday()+0.1, "HttpUtils_NonblockingGet", $param, 0);
      }
      else {
        todoist_ErrorReadings($hash,"access token empty");
      }
    }
    else {
      if (!IsDisabled($name)) {
        todoist_ErrorReadings($hash,"no access token set");
      }
      else {
          todoist_ErrorReadings($hash,"device is disabled");
      }
    }
  }
  else {
    map {FW_directNotify("#FHEMWEB:$_", "if (typeof todoist_ErrorDialog === \"function\") todoist_ErrorDialog('$name','$title ".$todoist_tt->{"alreadythere"}."','".$todoist_tt->{"error"}."')", "")} devspec2array("TYPE=FHEMWEB");
    todoist_ErrorReadings($hash,"duplicate detected","duplicate detected");
  }
  
  
  return undef;
}

# handle the callback data if task was created or updated
sub todoist_HandleTaskCallback($$$){
  my ($param, $err, $data) = @_;
  
  my $hash = $param->{hash};
  my $title = $param->{tTitle};
  
  my $taskId = 0;
  $taskId = $param->{taskId} if ($param->{taskId});
  
  my $reading = $title;
  
  my $name = $hash->{NAME}; 
  
  Log3 $name,4, "todoist ($name):  ".$param->{wType}." - Task Callback data: ".Dumper($data);

  my $error;
  
  ## errors? Log and readings
  if ($err ne "") {
    todoist_ErrorReadings($hash,$err);
  }
  else {
  
    ## if "sync_status" in $data, we were successfull
    if((($data =~ /sync_status/ && $data=~/ok/) || $data =~ /sync_id/) && eval {decode_json($data)}) {
      
      readingsBeginUpdate($hash);
    
      if ($data ne "") {
        my $decoded_json = decode_json($data);
        
        $taskId = $decoded_json->{id} if ($decoded_json->{id});
        
        $reading .= " - ".$taskId;
        
        ## do some logging
        Log3 $name,5, "todoist ($name): Task Callback data (decoded JSON): ".Dumper($decoded_json );
        
        Log3 $name,4, "todoist ($name): Callback-ID: $taskId" if ($taskId);
      }
      Log3 $name,4, "todoist ($name): Task Callback error(s): ".Dumper($err) if ($err);
      Log3 $name,5, "todoist ($name): Task Callback param: ".Dumper($param);
      
      # set information readings
      readingsBulkUpdate($hash, "error","none");
      readingsBulkUpdate($hash, "lastCreatedTask",$reading) if ($param->{wType} eq "create");
      readingsBulkUpdate($hash, "lastCompletedTask",$reading) if ($param->{wType} eq "complete" || $param->{wType} eq "close");
      readingsBulkUpdate($hash, "lastUncompletedTask",$reading) if ($param->{wType} eq "uncomplete");
      readingsBulkUpdate($hash, "lastUpdatedTask",$reading) if ($param->{wType} eq "update");
      readingsBulkUpdate($hash, "lastDeletedTask",$reading) if ($param->{wType} eq "delete");
      
      ## some Logging
      Log3 $name, 4, "todoist ($name): successfully created new task $title" if ($param->{wType} eq "create");
      Log3 $name, 4, "todoist ($name): success: ".$param->{wType}." task $title" if ($title);
      
      readingsEndUpdate( $hash, 1 );
      
      if ($param->{wType} =~ /(complete|delete|close)/) {
        # remove line in possible webling widget
        map {FW_directNotify("#FHEMWEB:$_", "if (typeof todoist_removeLine === \"function\") todoist_removeLine('$name','$taskId')", "")} devspec2array("TYPE=FHEMWEB");
      }
      if ($param->{wType} eq "create") {
        if ($param->{parentId}) {
          # set parent id with additional updateTask command / API cannot add it in create
          CommandSet(undef, "$name updateTask ID:$taskId parent_id=".$param->{parentId});
          Log3 $name, 3, "todoist ($name): startet set parent_id over update after create: Task-ID: ".$taskId." - parent_id: ".$param->{parentId};
        }
        # add a line in possible weblink widget
        map {FW_directNotify("#FHEMWEB:$_", "if (typeof todoist_addLine === \"function\") todoist_addLine('$name','$taskId','$title')", "")} devspec2array("TYPE=FHEMWEB");
      }
    }
    ## we got an error from the API
    else {
      my $error="malformed JSON";
      
      # if the error is in the file, log this error
      if (eval {decode_json($data)}) {
        my $decoded_json = decode_json($data);
        $error = $decoded_json->{error} if ($decoded_json->{error});
      }
      $error .= " | ".$param->{wType}."Task: ".$taskId;
      $error .= "Unknown";
      Log3 $name, 2, "todoist ($name): got error: ".$error;
      todoist_ErrorReadings($hash,$error);
    }
    
  } 
  # restart the timers
  todoist_RestartGetTimer($hash);
  
  return undef;
}



## get all Tasks
sub todoist_GetTasks($;$) {
  my ($hash,$completed) = @_;
  
  my $name=$hash->{NAME};
  
  # add loading circle to possivle weblink widget
  map {FW_directNotify("#FHEMWEB:$_", "if (typeof todoist_addLoading === \"function\") todoist_addLoading('$name')", "")} devspec2array("TYPE=FHEMWEB");
  
  $completed = 0 unless defined($completed);
  
  my $param;
  my $param2;
  
  my $pwd="";
  
  ## if no token is needed and device is not disabled, check token and get list vom todoist
  if (!$hash->{helper}{PWD_NEEDED} && !IsDisabled($name)) {
    
    ## get password
    $pwd=todoist_GetPwd($hash);
    
    if ($pwd) {
    
      Log3 $name,5, "$name: hash: ".Dumper($hash);
      
      my $data= {
        token           => $pwd,
        project_id      => $hash->{PID}
      };
      
      # set url for API access
      my $url = "https://todoist.com/sync/v8/projects/get_data";
      ## check if we get also the completed Tasks
      if ($completed == 1) {
        $url = "https://todoist.com/sync/v8/completed/get_all";
        $data->{'limit'}=50;
      }
      
      Log3 $name,4, "todoist ($name): Curl Data: ".Dumper($data);
      
      ## get the tasks
      $param = {
        url        => $url,
        method     => "POST",
        data       => $data,
        header     => "Content-Type: application/x-www-form-urlencoded",
        timeout    => 7,
        completed  => $completed,
        hash       => $hash,
        callback   => \&todoist_GetTasksCallback,  ## call callback sub to work with the data we get
      };

      
      
      Log3 $name,5, "todoist ($name): Param: ".Dumper($param);
      
      ## non-blocking access to todoist API
      InternalTimer(gettimeofday()+0.2, "HttpUtils_NonblockingGet", $param, 0);
      
      
    }
    else {
      todoist_ErrorReadings($hash,"access token empty");
    }
  }
  else {
    if (!IsDisabled($name)) {
      todoist_ErrorReadings($hash,"no access token set");
    }
    else {
      todoist_ErrorReadings($hash,"device is disabled");
    }
  }
  
  ## one more time, if we want to get completed tasks
  if (AttrVal($name,"getCompleted",0)==1 && $completed != 1) {    
    InternalTimer(gettimeofday()+0.5, "todoist_doGetCompTasks", $hash, 0);
  }
  InternalTimer(gettimeofday()+2, "todoist_GetUsers", $hash, 0) if ($completed != 1 && AttrVal($name,"autoGetUsers",1) == 1);
  
  return undef;
}

# helper sub for getting completed tasks
sub todoist_doGetCompTasks($) {
  my ($hash) = @_;
  todoist_GetTasks($hash,1);
}

## Callback for the lists tasks
sub todoist_GetTasksCallback($$$){
  my ($param, $err, $data) = @_;
  
  my $hash=$param->{hash};
  
  my $name = $hash->{NAME}; 
  
  Log3 $name,5, "todoist ($name):  Task Callback data-raw: ".Dumper($data);
  
  my $lText="";
  
  Log3 $name,5, "todoist ($name):  Task Callback param: ".Dumper($param);
  
  readingsBeginUpdate($hash);
  
  ## Log possbile errors in callback
  if ($err ne "") {
    todoist_ErrorReadings($hash,$err);
  }
  else {
    my $decoded_json="";
    
    # checl for correct JSON
    if (eval{decode_json($data)}) {
    
      $decoded_json = decode_json($data);
      
      Log3 $name,5, "todoist ($name):  Task Callback data (decoded JSON): ".Dumper($decoded_json );
    }
    
    # mostly HTML response / todoist is down or locked
    if ((ref($decoded_json) eq "HASH" && !$decoded_json->{items}) || $decoded_json eq "") {
      $hash->{helper}{errorData} = Dumper($data);
      $hash->{helper}{errorMessage} = "GetTasks: Response was damaged or empty. See log for details.";
      InternalTimer(gettimeofday()+0.2, "todoist_ErrorReadings",$hash, 0); 
    }
    # got project
    else {
      Log3 $name,4, "todoist ($name):  getTasks was successful";
      Log3 $name,5, "todoist ($name):  Task item data: ".Dumper(@{$decoded_json->{items}});
      ## items data
      my @taskseries = @{$decoded_json->{items}};
      
      ## project data
      my $project = $decoded_json->{project};
      
      # set some internals (project data)
      if ($project) {
        $hash->{PROJECT_NAME}=$project->{name};
        $hash->{PROJECT_INDENT}=$project->{indent};
        $hash->{PROJECT_COLOR}=$project->{color};
        $hash->{PROJECT_ORDER}=$project->{item_order};
        if ($project->{user_id}) {
          $hash->{PROJECT_USER}=$project->{user_id};
        }
        else {
          delete($hash->{PROJECT_USER});
        }
        if ($project->{parent_id}) {
          $hash->{PROJECT_PARENT}=$project->{parent_id};
          # hidden reading 
          readingsBulkUpdate($hash, ".projectParentId",$project->{parent_id});
        }
        else {
          # delete parent_id if there is none
          delete($hash->{PROJECT_PARENT}) if (defined($hash->{PROJECT_PARENT})); 
          CommandDeleteReading(undef, ".projectParentId");
        }
      }
      
      ## do some logging
      Log3 $name,5, "todoist ($name):  Task Callback data (taskseries): ".Dumper(@taskseries );
      
      my $i=0;
      
      ## count the results
      my $count=@taskseries;
      
      ## delete Task_* readings for changed list
      if ($param->{completed} != 1 || (ReadingsVal($name,"count",0)==0 && $count == 0)) {
        CommandDeleteReading(undef, "$hash->{NAME} (T|t)ask_.*");
        delete($hash->{helper});
      }

      
      
      ## no data
      if ($count==0 && $param->{completed} != 1) {
        InternalTimer(gettimeofday()+0.2, "todoist_ErrorReadings",$hash, 0); 
        readingsBulkUpdate($hash, "count",0);
      }
      # got some tasks
      else {
        $i = ReadingsVal($name,"count",0) if ($param->{completed} == 1);
        foreach my $task (@taskseries) {
          my $title = encode_utf8($task->{content});
          $title =~ s/^\s+|\s+$//g;
          
          my $t = sprintf ('%03d',$i);
          
          ## get todoist-Task-ID
          my $taskID = $task->{id};
          
          readingsBulkUpdate($hash, "Task_".$t,$title);
          readingsBulkUpdate($hash, "Task_".$t."_ID",$taskID) if (AttrVal($name,"hideId",0)!=1);

          ## a few helper for ID and revision
          $hash->{helper}{"IDS"}{"Task_".$i}=$taskID; # todoist Task-ID
          $hash->{helper}{"TITLE"}{$taskID}=$title; # Task title (content)
          $hash->{helper}{"TITLES"}{$title}=$taskID; # Task title (content)
          $hash->{helper}{"WID"}{$taskID}=$i; # FHEM Task-ID
          $hash->{helper}{"INDENT"}{$taskID}=$task->{indent}; # todoist Task indent
          $hash->{helper}{"PRIORITY"}{$taskID}=$task->{priority}; # todoist Task indent
          push @{$hash->{helper}{"INDENTS"}{$task->{indent}}},$taskID; # ident for better widget
          $hash->{helper}{"ORDER"}{$taskID}=$task->{item_order}; # todoist Task order         
          push @{$hash->{helper}{"TIDS"}},$taskID; # simple ID list
          push @{$hash->{helper}{"TITS"}},$title; # simple ID list
          
          readingsBulkUpdate($hash, "Task_".$t."_indent",$task->{indent}) if (AttrVal($name,"showIndent",0)==1);
          readingsBulkUpdate($hash, "Task_".$t."_order",$task->{item_order}) if (AttrVal($name,"showOrder",0)==1);      
          
          ## set parent_id if not null
          if (defined($task->{parent_id}) && $task->{parent_id} ne 'null') {
            ## if this task has a parent_id we set the reading
            readingsBulkUpdate($hash, "Task_".$t."_parentID",$task->{parent_id});
            $hash->{helper}{"PARENT_ID"}{$taskID}=$task->{parent_id};
          }   
          
          ## set completed_date if present
          if (defined($task->{checked}) && $task->{checked}!=0) {
            readingsBulkUpdate($hash, "Task_".$t."_checked",$task->{checked}) if (AttrVal($name,"showChecked",1)==1);
            $hash->{helper}{"CHECKED"}{$taskID}=$task->{checked};
          }
          
          ## set completed_date if present
          if (defined($task->{is_deleted}) && $task->{is_deleted}!=0) {
            readingsBulkUpdate($hash, "Task_".$t."_isDeleted",$task->{is_deleted}) if (AttrVal($name,"showDeleted",1)==1);
            $hash->{helper}{"ISDELETED"}{$taskID}=$task->{is_deleted};
          }
          
          ## set completed_date if present
          if (defined($task->{completed_date})) {
            ## if there is a completed task, we create a new reading
            readingsBulkUpdate($hash, "Task_".$t."_completedAt",FmtDateTime(str2time($task->{completed_date})));
            $hash->{helper}{"COMPLETED_AT"}{$taskID}=FmtDateTime(str2time($task->{completed_date}));
            readingsBulkUpdate($hash, "Task_".$t."_completedById",$task->{user_id});
            $hash->{helper}{"COMPLETED_BY_ID"}{$taskID}=$task->{user_id};
          }
          
          ## set due_date if present
          if (defined($task->{due_date_utc}) && $task->{due_date_utc} ne 'null') {
            ## if there is a task with due date, we create a new reading
            readingsBulkUpdate($hash, "Task_".$t."_dueDate",FmtDateTime(str2time($task->{due_date_utc})));
            $hash->{helper}{"DUE_DATE"}{$taskID}=FmtDateTime(str2time($task->{due_date_utc}));
          }
          
          ## set responsible_uid if present
          if (defined($task->{responsible_uid})) {
            ## if there is a task with responsible_uid, we create a new reading
            readingsBulkUpdate($hash, "Task_".$t."_responsibleUid",$task->{responsible_uid}) if (AttrVal($name,"showResponsible",0)==1);
            $hash->{helper}{"RESPONSIBLE_UID"}{$taskID}=$task->{responsible_uid};
          }
          
          ## set assigned_by_uid if present
          if (defined($task->{assigned_by_uid})) {
            ## if there is a task with assigned_by_uid, we create a new reading
            readingsBulkUpdate($hash, "Task_".$t."_assignedByUid",$task->{assigned_by_uid}) if (AttrVal($name,"showAssignedBy",0)==1);
            $hash->{helper}{"ASSIGNEDBY_UID"}{$taskID}=$task->{assigned_by_uid};
          }
          
          ## set priority if present
          if (defined($task->{priority})) {
            readingsBulkUpdate($hash, "Task_".$t."_priority",$task->{priority}) if (AttrVal($name,"showPriority",0)==1);
            $hash->{helper}{"PRIORITY"}{$taskID}=$task->{priority};
          }
          
          ## set recurrence_type and count if present
          if (defined($task->{date_string})) {
            ## if there is a task with recurrence_type, we create new readings
            readingsBulkUpdate($hash, "Task_".$t."_recurrenceType",encode_utf8($task->{date_string}));
            $hash->{helper}{"RECURRENCE_TYPE"}{$taskID}=encode_utf8($task->{date_string});
          }
                    
          if ($param->{completed} != 1) {
            $lText.=AttrVal($name,"listDivider",", ") if ($i != 0);
            $lText.=$title;
          }
          $i++;
        }
        readingsBulkUpdate($hash, "error","none");
        readingsBulkUpdate($hash, "count",$i);
        
        
      }
    }
  }

  ## list Text for TTS, Text-Message...
  if ($param->{completed} != 1) {
    $lText="-" if ($lText eq "");
    readingsBulkUpdate($hash,"listText",$lText) if ($lText ne "");
  }
  
  
  readingsEndUpdate( $hash, 1 );
  
  ## sort Tasks alphabetically if set
  todoist_sort($hash) if (AttrVal($name,"sortTasks",0) == 1);
  
  
  RemoveInternalTimer($hash,"todoist_GetTasks");
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "todoist_GetTasks", $hash, 0); ## loop with Interval
  
  todoist_ReloadTable($name);
  
  return undef;
}

## get all Users
sub todoist_GetUsers($) {
  my ($hash) = @_;
  
  my $name=$hash->{NAME};
  
  my $param;
  
  my $pwd="";
  
  ## if no token is needed and device is not disabled, check token and get list vom todoist
  if (!$hash->{helper}{PWD_NEEDED} && !IsDisabled($name)) {
    
    ## get password
    $pwd=todoist_GetPwd($hash);
    
    my $data= {
      token           => $pwd,
      sync_token      => '*',
      resource_types  => '["collaborators"]'
    };
    
    if ($pwd) {
    
      Log3 $name,5, "$name: hash: ".Dumper($hash);
      
      $param = {
        url        => "https://todoist.com/sync/v8/sync",
        data       => $data,
        timeout    => 7,
        method     => "POST",
        header     => "Content-Type: application/x-www-form-urlencoded",
        hash       => $hash,
        callback   => \&todoist_GetUsersCallback,  ## call callback sub to work with the data we get
      };
      
      
      Log3 $name,5, "todoist ($name): Param: ".Dumper($param);
      
      ## non-blocking access to todoist API
      InternalTimer(gettimeofday()+1, "HttpUtils_NonblockingGet", $param, 0);
    }
    else {
      todoist_ErrorReadings($hash,"access token empty");
    }
  }
  else {
    if (!IsDisabled($name)) {
      todoist_ErrorReadings($hash,"no access token set");
    }
    else {
      todoist_ErrorReadings($hash,"device is disabled");
    }
  }
  
  return undef;
}

sub todoist_GetUsersCallback($$$){
  my ($param, $err, $data) = @_;
  
  my $hash=$param->{hash};
  
  my $name = $hash->{NAME}; 
  
  Log3 $name,5, "todoist ($name): User Callback data: ".Dumper($data);
  
  if ($err ne "") {
    todoist_ErrorReadings($hash,$err);
  }
  else {
    my $decoded_json="";
    
    if (eval{decode_json($data)}) {
    
      $decoded_json = decode_json($data);
      
      Log3 $name,5, "todoist ($name):  User Callback data (decoded JSON): ".Dumper($decoded_json );
    }
    
    readingsBeginUpdate($hash);
    if ((ref($decoded_json) eq "HASH" && !$decoded_json->{collaborators}) || $decoded_json eq "") {
      $hash->{helper}{errorData} = Dumper($data);
      $hash->{helper}{errorMessage} = "Response was damaged or empty. See log for details.";
      InternalTimer(gettimeofday()+0.2, "todoist_ErrorReadings",$hash, 0); 
    }
    else {
      my @users = @{$decoded_json->{collaborators}};
      my @states = @{$decoded_json->{collaborator_states}};
      ## count the results
      my $count=@users;
      
      ## delete Task_* readings for changed list
      CommandDeleteReading(undef, "$hash->{NAME} (U|u)ser_.*");
      delete($hash->{helper}{USER});
      
      Log3 $name,5, "todoist ($name):  Task States: ".Dumper(@states);
      
      ## no data
      if ($count==0) {
        readingsBulkUpdate($hash, "error","none");
        readingsBulkUpdate($hash, "countUsers",0);
      }
      else {
      
        my $i=0;
        foreach my $user (@users) {
          my $do=0;
          foreach my $state (@states) {
            $do=1 if ($user->{id} == $state->{user_id} && $state->{project_id} == $hash->{PID});
          }
          
          if ($do==1) {
            my $userName = encode_utf8($user->{full_name});
            my $t = sprintf ('%03d',$i);
            
            ## get todoist-User-ID
            my $userID = $user->{id};
            
            readingsBulkUpdate($hash, "User_".$t,$userName);
            readingsBulkUpdate($hash, "User_".$t."_ID",$userID);

            ## a few helper for ID and revision
            $hash->{helper}{USER}{"IDS"}{"User_".$i}=$userID;
            $hash->{helper}{USER}{"NAME"}{$userID}=$userName;
            $hash->{helper}{USER}{"WID"}{$userID}=$i;
            $i++;
          }
        }
        readingsBulkUpdate($hash, "error","none");
        readingsBulkUpdate($hash, "countUsers",$i);
      }
    }
    readingsEndUpdate( $hash, 1 );
  }
    
  
}

# get all projects 
sub todoist_GetProjects($) {
  my ($hash) = @_;
  
  my $name=$hash->{NAME};
  
  my $param;
  
  my $pwd="";
  
  ## if no token is needed and device is not disabled, check token and get list vom todoist
  if (!$hash->{helper}{PWD_NEEDED} && !IsDisabled($name)) {
    
    ## get password
    $pwd=todoist_GetPwd($hash);
    
    my $data= {
      token           => $pwd,
      sync_token      => '*',
      resource_types  => '["projects"]'
    };
    
    if ($pwd) {
    
      Log3 $name,5, "$name: hash: ".Dumper($hash);
      
      $param = {
        url        => "https://todoist.com/sync/v8/sync",
        data       => $data,
        timeout    => 7,
        method     => "POST",
        header     => "Content-Type: application/x-www-form-urlencoded",
        hash       => $hash,
        callback   => \&todoist_GetProjectsCallback,  ## call callback sub to work with the data we get
      };
      
      
      Log3 $name,5, "todoist ($name): Param: ".Dumper($param);
      
      ## non-blocking access to todoist API
      InternalTimer(gettimeofday()+1, "HttpUtils_NonblockingGet", $param, 0);
    }
    else {
      todoist_ErrorReadings($hash,"access token empty");
    }
  }
  else {
    if (!IsDisabled($name)) {
      todoist_ErrorReadings($hash,"no access token set");
    }
    else {
      todoist_ErrorReadings($hash,"device is disabled");
    }
  }
  
  return undef;
  
}

# get projects callback

sub todoist_GetProjectsCallback($$$){
  my ($param, $err, $data) = @_;
  
  my $hash=$param->{hash};
  
  my $name = $hash->{NAME}; 
  
  ## some Project-Info
  my $pid = $hash->{PID};
  my $room = AttrVal($name,"room",undef);
  my $group = AttrVal($name,"group",undef);
  
  my $return="";
  
  my $i=0;
  
  Log3 $name,5, "todoist ($name): Projects Callback data: ".Dumper($data);
  
  readingsBeginUpdate($hash);
  
  if ($err ne "") {
    todoist_ErrorReadings($hash,$err);
  }
  else {
    my $decoded_json="";
    
    if (eval{decode_json($data)}) {
    
      $decoded_json = decode_json($data);
      
      Log3 $name,5, "todoist ($name):  User Callback data (decoded JSON): ".Dumper($decoded_json );
    }
    if ((ref($decoded_json) eq "HASH" && !$decoded_json->{projects}) || $decoded_json eq "") {
      $hash->{helper}{errorData} = Dumper($data);
      $hash->{helper}{errorMessage} = "GetTasks: Response was damaged or empty. See log for details.";
      InternalTimer(gettimeofday()+0.2, "todoist_ErrorReadings",$hash, 0); 
    }
    else {
      Log3 $name,4, "todoist ($name): getProjects was successful";
      Log3 $name,5, "todoist ($name): Task projects data: ".Dumper(@{$decoded_json->{projects}});
      ## items data
      my @projects = @{$decoded_json->{projects}};
      
      ## count the results
      my $count=@projects;
      
      ## no data
      if ($count==0) {
        InternalTimer(gettimeofday()+0.2, "todoist_ErrorReadings",$hash, 0); 
        readingsBulkUpdate($hash, "count",0);
      }
      else {
        # array for possible deletion
        my @comDevs;
        # walk through projects
        foreach my $project (@projects) {
          my $project_id = $project->{id};
          my $parent_id = $project->{parent_id};
          my $new_name = encode_utf8($project->{name});
          # new title
          my $title = $name."_".$new_name;
          # is this parent_id equal to id of current project?
          if ($pid == $parent_id) {
            # push to deletion array
            push @comDevs,$project_id;
            Log3 $name,4, "todoist ($name): get Projects: Project-ID: $project_id - Title: $new_name - Parent-ID: $parent_id";
            # does this project exist in FHEM?
            my $existP = devspec2array("PID=$project_id");
            if (!$existP && (!$project->{is_deleted} || $project->{is_deleted}!=1)) {
              # if not, define new todoist device by copying the parent
              fhem("copy $name $title $project_id") if (!defined($defs{$title}));
              my $new_hash = $defs{$title};
              # set some internals (project data) and set parent_id
              if ($new_hash) {      
                $return.=" $title";
                $i++;
                Log3 $name,4, "todoist ($name): new project $title, defined by cChildProjects";
                $new_hash->{PROJECT_NAME}=$project->{name};
                $new_hash->{PROJECT_INDENT}=$project->{indent};
                $new_hash->{PROJECT_COLOR}=$project->{color};
                $new_hash->{PROJECT_ORDER}=$project->{item_order};
                if ($project->{user_id}) {
                  $new_hash->{PROJECT_USER}=$project->{user_id};
                }
                else {
                  delete($new_hash->{PROJECT_USER});
                }
                if ($project->{parent_id}) {
                  $new_hash->{PROJECT_PARENT}=$project->{parent_id};
                  # invisible reading 
                  readingsSingleUpdate($new_hash, ".projectParentId",$project->{parent_id},1);
                }
                else {
                  delete($new_hash->{PROJECT_PARENT}) if (defined($new_hash->{PROJECT_PARENT}));
                  CommandDeleteReading(undef, ".projectParentId");
                }
              }
            }
          }
        }
        if (AttrVal($name,"delDeletedLists",0)==1) {
          # get todoist projects for this parent_id 
          my @tDevs = devspec2array(".projectParentId=$pid");
          foreach my $dev (@tDevs) {
            my $tDev = $defs{$dev};
            # delete device if PID is not in array
            if (!todoist_inArray(\@comDevs,$tDev->{PID})) {
              CommandDelete(undef,$dev);
              Log3 $name,3, "todoist ($name): deleted device ".$dev." in cChildProjects";
            } 
          }
        }
      }
    }
  }
  Log3 $name,3, "todoist ($name): Got $i new projects: ".$return;
  return "Got $i new projects: ".$return;
}

# sort alphabetically (probably deprecated)
sub todoist_sort($) {
  my ($hash) = @_;
  
  my $name=$hash->{NAME};
  
  my $lText="";
  
  my %list;
  
  
  ## get all Readings
  my $readings = $hash->{READINGS};
  ## prepare Hash for sorting
  foreach my $key (keys %{$readings}) {
    if ($key =~ m/^Task_\d\d\d$/) {
      my @temp = split("_",$key);
      my $tid = int($temp[1]);
      my $val = $readings->{$key}{VAL};
      my $id = $hash->{helper}{IDS}{'Task_'.$tid};
      $list{$tid} = {content => $val, ID => $id};
    }
  }
  
  CommandDeleteReading(undef, "$hash->{NAME} (T|t)ask_.*");
  
  readingsBeginUpdate($hash);
  
  delete($hash->{helper}{"IDS"});
  
  ## sort Tasks and write them back
  my $i = 0;
  foreach my $key (sort {lc($list{$a}->{content}) cmp lc($list{$b}->{content})} keys(%list)) {
    my $data = $list{$key};
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i),$data->{content});
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_dueDate",$hash->{helper}{"DUE_DATE"}{$data->{ID}}) if ($hash->{helper}{"DUE_DATE"}{$data->{ID}});
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_responsibleUid",$hash->{helper}{"RESPONSIBLE_UID"}{$data->{ID}}) if ($hash->{helper}{"RESPONSIBLE_UID"}{$data->{ID}} && AttrVal($name,"showResponsible",0)==1);
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_assignedByUid",$hash->{helper}{"ASSIGNEDBY_UID"}{$data->{ID}}) if ($hash->{helper}{"ASSIGNEDBY_UID"}{$data->{ID}} && AttrVal($name,"showAssignedBy",0)==1);
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_priority",$hash->{helper}{"PRIORITY"}{$data->{ID}}) if ($hash->{helper}{"PRIORITY"}{$data->{ID}} && AttrVal($name,"showPriority",0)==1);
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_recurrenceType",$hash->{helper}{"RECURRENCE_TYPE"}{$data->{ID}}) if ($hash->{helper}{"RECURRENCE_TYPE"}{$data->{ID}});
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_completedAt",$hash->{helper}{"COMPLETED_AT"}{$data->{ID}}) if ($hash->{helper}{"COMPLETED_AT"}{$data->{ID}});
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_completedById",$hash->{helper}{"COMPLETED_BY_ID"}{$data->{ID}}) if ($hash->{helper}{"COMPLETED_BY_ID"}{$data->{ID}});
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_indent",$hash->{helper}{"INDENT"}{$data->{ID}}) if ($hash->{helper}{"INDENT"}{$data->{ID}} && AttrVal($name,"showIndent",0)==1);
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_order",$hash->{helper}{"ORDER"}{$data->{ID}}) if ($hash->{helper}{"ORDER"}{$data->{ID}} && AttrVal($name,"showOrder",0)==1);
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_parentID",$hash->{helper}{"PARENT_ID"}{$data->{ID}}) if ($hash->{helper}{"PARENT_ID"}{$data->{ID}});
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_checked",$hash->{helper}{"CHECKED"}{$data->{ID}}) if ($hash->{helper}{"CHECKED"}{$data->{ID}} && AttrVal($name,"showChecked",1)==1);
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_isDeleted",$hash->{helper}{"ISDELETED"}{$data->{ID}}) if ($hash->{helper}{"ISDELETED"}{$data->{ID}} && AttrVal($name,"showDeleted",1)==1);
    readingsBulkUpdate($hash,"Task_".sprintf("%03s",$i)."_ID",$data->{ID}) if (AttrVal($name,"hideId",0)!=1);
    
    $hash->{helper}{"IDS"}{"Task_".$i} = $data->{ID};
    $hash->{helper}{"WID"}{$data->{ID}} = $i;
    
    if (!$hash->{helper}{"COMPLETED_AT"}{$data->{ID}}) {
      $lText.=", " if ($i != 0);
      $lText.=$data->{content};
    }
    $i++;
  }
  
  ## list Text for TTS, Text-Message...
  $lText="-" if ($lText eq "");
  readingsBulkUpdate($hash,"listText",$lText) if ($lText ne "");
  
  readingsEndUpdate( $hash, 1 );
  return undef;
}


#################################################
# delete all Tasks from list
sub todoist_clearList($) {
  my ($hash) = @_;
  
  my $name = $hash->{NAME};
  
  my $i=0;
  ## iterate through all tasks
  foreach my $id (%{$hash->{helper}{IDS}}) {
    my $dHash->{hash}=$hash;
    if ($id !~ /Task_/) {
      $dHash->{id}=$id;
      InternalTimer(gettimeofday()+0.4, "todoist_doUpdateTask", $dHash, 0);
      $i++;
    }
  }
  if ($i==0) {
    map {FW_directNotify("#FHEMWEB:$_", "if (typeof todoist_removeLoading === \"function\") todoist_removeLoading('$name')", "")} devspec2array("TYPE=FHEMWEB");
  }
}

sub todoist_doUpdateTask($) {
  my ($dHash) = @_;
  my $hash = $dHash->{hash};
  my $id = $dHash->{id};
  my $name = $hash->{NAME};
  todoist_UpdateTask($hash,"ID:".$id,"delete");
}


sub todoist_Undefine($$) {
  my ($hash, $arg) = @_;
  
  RemoveInternalTimer($hash);
  
  return undef;
}

################################################
# If Device is deleted, delete the password data
sub todoist_Delete($$) {
  my ($hash, $name) = @_;  
  
  my $old_index = "todoist_".$name."_passwd";
  
  my $old_key =getUniqueId().$old_index;
  
  my ($err, $old_pwd) = getKeyValue($old_index);
  
  return undef unless(defined($old_pwd));
      
  setKeyValue($old_index, undef);

  
  Log3 $name, 3, "todoist: device $name as been deleted. Access-Token has been deleted too.";
  
  return undef;
}

################################################
# If Device is renamed, copy the password data
sub todoist_Rename($$) {
  my ($new, $old) = @_;  
  
  my $old_index = "todoist_".$old."_passwd";
  my $new_index = "todoist_".$new."_passwd";
  my $key = getUniqueId().$old_index;
  
  my $new_hash = $defs{$new};
  my $name = $new_hash->{NAME};
  
  my $old_key="";
  
  my ($err, $password) = getKeyValue($old_index);
      
  if ($err) {
    $new_hash->{helper}{PWD_NEEDED} = 1;
    Log3 $name, 4, "todoist ($name): unable to read password from file: $err";
    return undef;
  }   
  
  if ( defined($password) ) {
    if ( eval "use Digest::MD5;1" ) {
       $key = Digest::MD5::md5_hex(unpack "H*", $key);
       $key .= Digest::MD5::md5_hex($key);
    }
   
    for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) {
       my $decode=chop($key);
       $old_key.=chr(ord($char)^ord($decode));
       $key=$decode.$key;
    }
  }
  my $new_key = $old_key;
  
  
  return undef unless(defined($old_key));
      
  todoist_setPwd($new_hash, $name, $new_key);
  
  Log3 $new, 3, "todoist: device has been renamed from $old to $new. Access-Token has been assigned to new name.";
  
  return undef;
}

################################################
# If Device is copied, copy the password data
sub todoist_Copy($$;$) {
  my ($old, $new) = @_;  
  
  my $old_index = "todoist_".$old."_passwd";
  my $new_index = "todoist_".$new."_passwd";
  my $key = getUniqueId().$old_index;
  
  my $new_hash = $defs{$new};
  my $name = $new_hash->{NAME};
  
  my $old_key="";
  
  my ($err, $password) = getKeyValue($old_index);
      
  if ($err) {
    $new_hash->{helper}{PWD_NEEDED} = 1;
    Log3 $name, 4, "todoist ($name): unable to read password from file: $err";
    return undef;
  }   
  
  if ( defined($password) ) {
    if ( eval "use Digest::MD5;1" ) {
       $key = Digest::MD5::md5_hex(unpack "H*", $key);
       $key .= Digest::MD5::md5_hex($key);
    }
   
    for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) {
       my $decode=chop($key);
       $old_key.=chr(ord($char)^ord($decode));
       $key=$decode.$key;
    }
  }
  my $new_key = $old_key;
  
  return undef unless(defined($old_key));
      
  todoist_setPwd($new_hash, $name, $new_key);
  
  delete($new_hash->{helper}{PWD_NEEDED});
  
  readingsSingleUpdate($new_hash,"state","inactive",1);
  
  Log3 $new, 3, "todoist: device has been copied from $old to $new. Access-Token has been assigned to new device.";
  
  return undef;
}

## some checks if attribute is set or deleted
sub todoist_Attr($@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  
  my $orig = $attrVal;
  
  my $hash = $defs{$name};
  
  if ( $attrName eq "disable" ) {

    if ( $cmd eq "set" && $attrVal == 1 ) {
      if ($hash->{READINGS}{state}{VAL} ne "disabled") {
        readingsSingleUpdate($hash,"state","disabled",1);
        RemoveInternalTimer($hash);
        RemoveInternalTimer($hash,"todoist_GetTasks");
        Log3 $name, 4, "todoist ($name): $name is now disabled";
      }
    }
    elsif ( $cmd eq "del" || $attrVal == 0 ) {
      if ($hash->{READINGS}{state}{VAL} ne "active") {
        readingsSingleUpdate($hash,"state","active",1);
        RemoveInternalTimer($hash);
        Log3 $name, 4, "todoist ($name): $name is now ensabled";
        todoist_RestartGetTimer($hash);
      }
    }
  }
  
  if ( $attrName eq "pollInterval") {
    if ( $cmd eq "set" ) {
      return "$name: pollInterval has to be a number (seconds)" if ($attrVal!~ /\d+/);
      return "$name: pollInterval has to be greater than or equal 20" if ($attrVal < 20);
      $hash->{INTERVAL}=$attrVal;
      Log3 $name, 4, "todoist ($name): set new pollInterval to $attrVal";
    }
    elsif ( $cmd eq "del" ) {
      $hash->{INTERVAL}=1800;
      Log3 $name, 4, "todoist ($name): set new pollInterval to 1800 (standard)";
    }
    todoist_RestartGetTimer($hash);
  }
  
  if ($attrName eq "listDivider") {
    todoist_RestartGetTimer($hash);
  }
  
  if ($attrName eq "language") {
    # in any attribute redefinition readjust language
    if ($cmd eq "set") {
      return "$name: language can only be DE or EN" if ($attrVal !~ /(^DE|EN)$/);
      if( $attrVal eq "DE") {
        $todoist_tt = \%todoist_transtable_DE;
      }
      else{
        $todoist_tt = \%todoist_transtable_EN;
      }
    }
    else {
      $todoist_tt = \%todoist_transtable_EN;
    }
  }
  
  if ( $attrName eq "sortTasks" ||  $attrName =~ /(show(Priority|AssignedBy|Responsible|Indent|Order|DetailWidget)|getCompleted|hide(Id|ListIfEmpty)|autoGetUsers|avoidDuplicates|delDeletedLists)/) {
    if ( $cmd eq "set" ) {
      return "$name: $attrName has to be 0 or 1" if ($attrVal !~ /^(0|1)$/);
      Log3 $name, 4, "todoist ($name): set attribut $attrName to $attrVal";
    }
    elsif ( $cmd eq "del" ) {
      Log3 $name, 4, "todoist ($name): deleted attribut $attrName";
    }
    todoist_RestartGetTimer($hash);
  }
  
  return;
}

sub todoist_Set ($@) {
  my ($hash, $name, $cmd, @args) = @_;
  
  my @sets = ();
  
  push @sets, "active:noArg" if (IsDisabled($name) && !$hash->{helper}{PWD_NEEDED});
  push @sets, "inactive:noArg" if (!IsDisabled($name));
  if (!IsDisabled($name) && !$hash->{helper}{PWD_NEEDED}) {
    push @sets, "addTask";
    push @sets, "completeTask";
    push @sets, "closeTask";
    push @sets, "uncompleteTask";
    push @sets, "deleteTask";
    push @sets, "updateTask";
    push @sets, "clearList:noArg";
    push @sets, "getTasks:noArg";
    push @sets, "cChildProjects:noArg";
    push @sets, "getUsers:noArg";
  }
  push @sets, "accessToken" if ($hash->{helper}{PWD_NEEDED});
  push @sets, "newAccessToken" if (!$hash->{helper}{PWD_NEEDED});
  
  return join(" ", @sets) if ($cmd eq "?");
  
  my $usage = "Unknown argument ".$cmd.", choose one of ".join(" ", @sets) if(scalar @sets > 0);
  
  if (IsDisabled($name) && $cmd !~ /^(active|inactive|.*ccessToken)?$/) {
    Log3 $name, 3, "todoist ($name): Device is disabled at set Device $cmd";
    return "Device is disabled. Enable it on order to use command ".$cmd;
  }
  
  if ( $cmd =~ /^(active|inactive)?$/ ) {   
    readingsSingleUpdate($hash,"state",$cmd,1);
    RemoveInternalTimer($hash,"todoist_GetTasks");
    CommandDeleteAttr(undef,"$name disable") if ($cmd eq "active" && AttrVal($name,"disable",0)==1);
    InternalTimer(gettimeofday()+1, "todoist_GetTasks", $hash, 0) if (!IsDisabled($name) && $cmd eq "active");
    Log3 $name, 3, "todoist ($name): set Device $cmd";
  }
  elsif ($cmd eq "getTasks") {
    RemoveInternalTimer($hash,"todoist_GetTasks");
    Log3 $name, 4, "todoist ($name): set getTasks manually. Timer restartet.";
    InternalTimer(gettimeofday()+1, "todoist_GetTasks", $hash, 0) if (!IsDisabled($name) && !$hash->{helper}{PWD_NEEDED});
  }
  elsif ($cmd eq "cChildProjects") {
    RemoveInternalTimer($hash,"todoist_GetProjects");
    Log3 $name, 4, "todoist ($name): set getProjects manually. Timer restartet.";
    InternalTimer(gettimeofday()+1, "todoist_GetProjects", $hash, 0) if (!IsDisabled($name) && !$hash->{helper}{PWD_NEEDED});
  }
  elsif ($cmd eq "getUsers") {
    RemoveInternalTimer($hash,"todoist_GetUsers");
    Log3 $name, 4, "todoist ($name): set getUsers manually.";
    InternalTimer(gettimeofday()+1, "todoist_GetUsers", $hash, 0) if (!IsDisabled($name) && !$hash->{helper}{PWD_NEEDED});
  }
  elsif ($cmd eq "accessToken" || $cmd eq "newAccessToken") {
    return todoist_setPwd ($hash,$name,@args);
  }
  elsif ($cmd eq "addTask" || $cmd eq "newTask") {
    my $count=@args;
    if ($count!=0) {
      my $exp=decode_utf8(join(" ",@args));
      todoist_CreateTask ($hash,$exp);
    }
    return "new Task needs a title" if ($count==0);
  }
  elsif ($cmd eq "completeTask" || $cmd eq "closeTask") {
    my $term=$cmd eq "completeTask"?"complete":"close";
    my $count=@args;
    if ($count!=0) {
      my $exp=decode_utf8(join(" ",@args));
      Log3 $name,5, "todoist ($name): ".$term."d startet with exp: $exp";
      todoist_UpdateTask ($hash,$exp,$term);
    }
    return "in order to complete or close a task, we need it's ID" if ($count==0);
  }
  elsif ($cmd eq "uncompleteTask") {
    my $count=@args;
    if ($count!=0) {
      my $exp=decode_utf8(join(" ",@args));
      Log3 $name,5, "todoist ($name): Uncompleted startet with exp: $exp";
      todoist_UpdateTask ($hash,$exp,"uncomplete");
    }
    return "in order to complete a task, we need it's ID" if ($count==0);
  }
  elsif ($cmd eq "updateTask") {
    my $count=@args;
    if ($count!=0) {
      my $exp=decode_utf8(join(" ",@args));
      todoist_UpdateTask ($hash,$exp,"update");
    }
    return "in order to complete a task, we need it's ID" if ($count==0);
  }
  elsif ($cmd eq "deleteTask") {
    my $count=@args;
    if ($count!=0) {
      my $exp=decode_utf8(join(" ",@args));
      todoist_UpdateTask ($hash,$exp,"delete");
    }
    return "in order to delete a task, we need it's ID" if ($count==0);
  }
  elsif ($cmd eq "sortTasks") {
    todoist_sort($hash);
  }
  elsif ($cmd eq "clearList") {
    todoist_clearList($hash);
  }
  else {
    return $usage;
  }

  return undef;
  
}

sub todoist_Get($@) {
  my ($hash, $name, $cmd, @args) = @_;
  my $ret = undef;
  
  if ( $cmd eq "version") {
    $hash->{VERSION} = $version;
    return "Version: ".$version;
  }
  else {
    $ret ="$name get with unknown argument $cmd, choose one of " . join(" ", sort keys %gets);
  }
 
  return $ret;
}

#####################################
# sets todoist Access Token
sub todoist_setPwd($$@) {
  my ($hash, $name, @pwd) = @_;
   
  return "Password can't be empty" if (!@pwd);
  
  my $pwdString=$pwd[0];
  my $enc_pwd = "";
  
  my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
  my $key = getUniqueId().$index;
  
  if(eval "use Digest::MD5;1") {
      $key = Digest::MD5::md5_hex(unpack "H*", $key);
      $key .= Digest::MD5::md5_hex($key);
  }
    
  for my $char (split //, $pwdString) {
      my $encode=chop($key);
      $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
      $key=$encode.$key;
  }
  
  Log3 $name,5,"todoist ($name): encoded pwd: $enc_pwd";
     
  my $err = setKeyValue($index, $enc_pwd);
  
  return "error while saving the password - $err" if(defined($err));
  
  delete($hash->{helper}{PWD_NEEDED}) if(exists($hash->{helper}{PWD_NEEDED}));
  
  
  if (AttrVal($name,"disable",0) != 1) {
    readingsSingleUpdate($hash,"state","active",1);
  }
  
  todoist_RestartGetTimer($hash);
  
  Log3 $name, 3, "todoist ($name). New Password set.";
  
  return "password successfully saved";
   
}

#####################################
# reads the Access Token and checks it
sub todoist_checkPwd ($$) {
  my ($hash, $pwd) = @_;
  my $name = $hash->{NAME};
    
  my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
  my $key = getUniqueId().$index;
  
  my ($err, $password) = getKeyValue($index);
        
  if ($err) {
    $hash->{helper}{PWD_NEEDED} = 1;
    Log3 $name, 3, "todoist ($name): unable to read password from file: $err";
    return undef;
  }  
  
  if ( defined($password) ) {
    if ( eval "use Digest::MD5;1" ) {
       $key = Digest::MD5::md5_hex(unpack "H*", $key);
       $key .= Digest::MD5::md5_hex($key);
    }

    my $dec_pwd = '';
   
    for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) {
       my $decode=chop($key);
       $dec_pwd.=chr(ord($char)^ord($decode));
       $key=$decode.$key;
    }
     
    return 1 if ($dec_pwd eq $pwd);
  }
  else {
    return "no password saved" if (!$password);
  }
  
  return 0;
}

sub todoist_Notify ($$) {
  my ($hash,$dev) = @_;
  
  my $name = $hash->{NAME};

  return if($dev->{NAME} ne "global");
  
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  todoist_RestartGetTimer($hash);

  return undef;

}

# restart timers for getTasks if active
sub todoist_RestartGetTimer($) {
  my ($hash) = @_;
  
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "todoist_GetTasks");
  InternalTimer(gettimeofday()+0.3, "todoist_GetTasks", $hash, 0) if (!IsDisabled($name) && !$hash->{helper}{PWD_NEEDED});
  
  return undef;
}

# placeholder for older widgets
sub todoist_AllHtml(;$) {
  my ($regEx) = @_;
  return todoist_Html($regEx);
}

# show widget in detail view of todoist device
sub todoist_detailFn(){
  my ($FW_wname, $devname, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  my $hash = $defs{$devname};

  $hash->{mayBeVisible} = 1;
  
  my $name=$hash->{NAME};
  
  return undef if (IsDisabled($name) || AttrVal($name,"showDetailWidget",1)!=1);
  
  my $html="";
  
  my $icon = AttrVal($devname, "icon", "");
  $icon = FW_makeImage($icon,$icon,"icon") . "&nbsp;" if($icon);

  #$html = '<div id="ddtable" class="makeTable wide"><table class="block wide"><tr class="odd">'.
  #           '<td width="300px"><div>'.$icon.'&nbsp;'.AttrVal($name,"alias",$name).'</div></td>'.
  #           '<td informId="'.$name.'"><div id="'.$name.'" title="Initialized" class="col2">'.InternalVal($devname,"STATE",ReadingsVal($devname,"state","-")).'</div></td>'.
  #           '</tr></table></div>';
  
  $html .= todoist_Html($name,undef,1);
  
  return $html;
}

# frontend weblink widget (FHEMWEB)
sub todoist_Html(;$$$) {
  my ($regEx,$refreshGet,$detail) = @_;

  $regEx="" if (!defined($regEx));
  $refreshGet=0 if (!defined($refreshGet));
  $detail=0 if (!defined($detail));
  
  my $filter="";
  
  $filter.=":FILTER=".$regEx;
  
  my @devs = devspec2array("TYPE=todoist".$filter);
  my $ret="";
  my $rot="";
  
  my $eo="";
  
  my $r=0;
  
  my $count = @devs;
  my $width = 95/$count;
  
  # refresh request? don't return everything
  if (!$refreshGet) {
    # define global JS variables
    $rot .= " <script type=\"text/javascript\">
                todoist_tt={};
                todoist_tt.refreshList='".$todoist_tt->{'refreshList'}."';
                todoist_tt.clearList='".$todoist_tt->{'clearList'}."';
                todoist_tt.clearconfirm='".$todoist_tt->{'clearconfirm'}."';
                todoist_tt.delconfirm='".$todoist_tt->{'delconfirm'}."';
                todoist_tt.check='".$todoist_tt->{'check'}."';
                todoist_tt.delete='".$todoist_tt->{'delete'}."';
              </script>";
    # Javascript and CSS
    $rot .= " <script type=\"text/javascript\" src=\"$FW_ME/www/pgm2/todoist.js?version=".$version."\"></script>
                <style id=\"todoist_style\">
                  .todoist_container {
                      display: block;
                      padding: 0;
                      float:none;
                  }
                  .todoist_table {
                      float: left;
                      margin-right: 10px;
                  }
                  .sortable-placeholder {
                    background-color: grey;
                  }
                  .todoist_col1 {
                    width:32px;
                    text-align:right;
                    padding: 4px 4px 4px 1px!important;
                  }
                  .todoist_col1 input {
                    //margin-top:4px;
                  }
                  .todoist_move {
                    width:10px;
                    float:left;
                  }
                  .todoist_sortit_handler {
                    padding-top: 0px!important;
                    content: '....';
                    width: 5px;
                    height: 20px;
                    //display: inline-block;
                    overflow: hidden;
                    line-height: 5px;
                    padding: 0px 2px!important;
                    cursor: move;
                    vertical-align: middle;
                    margin-top: -.2em;
                    margin-right: 0!important;
                    font-size: 12px;
                    font-family: sans-serif;
                    letter-spacing: 1px;
                    color: #cccccc;
                    text-shadow: 1px 0 1px black;
                  }
                  .todoist_sortit_handler::after {
                    content: '.. .. .. ..';
                  }
                  \@media(max-device-width: 480px){
                    .todoist_move {
                      width:35px;
                    }
                    .todoist_sortit_handler {
                       width: 5px;
                    }
                  }
                  .todoist_delete {
                    padding-right:15px!important;
                    padding-left:15px!important;
                  }
                  tr.ui-sortable-helper {
                    background-color:#111111;
                  }
                  .todoist_indent_2 {
                    padding-left:20px!important;
                  }
                  .todoist_indent_3 {
                    padding-left:40px!important;
                  }
                  .todoist_indent_4 {
                    padding-left:60px!important;
                  }
                  .todoist_ph td {
                    padding: 4px 8px;
                  }
                  div.todoist_devType {
                    padding: 4px!important;     
                  }
                  div.todoist_icon {
                    cursor: pointer;
                    display: block;
                    float: right;
                    width: 1em;
                    height: 1em;
                    margin-left: 0.5em;
                  }
                  div.todoist_icon svg {
                    height: 12px!important;
                    width: 12px!important;
                  }
    ";
    
    if (!$detail) {
      $rot.="     .todoist_table {
                    margin-bottom: 15px;
                  }
            ";  
    }
    
    $rot.="       </style> 
    ";
    
    $ret .= "<div class=\"todoist_container\">\n";
  }
  
  foreach my $name (@devs) {
    
    $r++;
  
    my $hash = $defs{$name};
    my $id   = $defs{$name}{NR};
    
    my $countList = ReadingsVal($name,"count",0);
    my $hLIE = AttrVal($name,"hideListIfEmpty",0);
    my $showList = ($hLIE==1 && $countList==0)?0:1;
    
    # show active lists only
    if (!IsDisabled($name) && ($showList || $detail)) {
    
      # refresh request? don't return everything
      if (!$refreshGet) {
        
        $ret .= "<table class=\"roomoverview todoist_table\">\n";
        
        $ret .= "<tr class=\"devTypeTr\">\n".
                " <td colspan=\"3\">\n".
                "   <div class=\"todoist_devType todoist_devType_".$name." col_header\">\n".
                    (!$FW_hiddenroom{detail}?"<a title=\"".$todoist_tt->{'gotodetail'}."\" href=\"/fhem?detail=".$name."\">":"").
                      AttrVal($name,"alias",$name).
                    (!$FW_hiddenroom{detail}?"</a>":"").
                "   </div>\n".
                " </td>\n".
                "</tr>\n";
        $ret .= "<tr><td colspan=\"3\"><table class=\"block wide sortable\" id=\"todoistTable_".$name."\">\n"; 
      
      }
      
      my $i=1;
   
      my $cs=3;
      
      # show data
      foreach (@{$hash->{helper}{TIDS}}) {
        
        if ($i%2==0) {
          $eo="even";
        }
        else {
          $eo="odd";
        }
        
        my $ind=0;

        my $indent=$hash->{helper}{INDENT}{$_};
        
        $ret .= "<tr id=\"".$name."_".$_."\" data-data=\"true\" data-line-id=\"".$_."\" class=\"sortit todoist_data ".$eo."\">\n".
                " <td class=\"col1 todoist_col1\">\n".
                "   <div class=\"todoist_move\"></div>\n".
                "   <input title=\"".$todoist_tt->{'check'}."\" class=\"todoist_checkbox_".$name."\" type=\"checkbox\" id=\"check_".$_."\" data-id=\"".$_."\" />\n".
                " </td>\n".
                " <td class=\"col1 todoist_input todoist_indent_".$indent."\">\n".
                "   <span class=\"todoist_task_text\" data-id=\"".$_."\">".$hash->{helper}{TITLE}{$_}."</span>\n".
                "   <input type=\"text\" data-id=\"".$_."\" style=\"display:none;\" class=\"todoist_input_".$name."\" value=\"".$hash->{helper}{TITLE}{$_}."\" />\n".
                " </td>\n";
        
        $ret .= "<td class=\"col2 todoist_delete\">\n".
                " <a title=\"".$todoist_tt->{'delete'}."\" href=\"#\" class=\"todoist_delete_".$name."\" data-id=\"".$_."\">\n".
                "   x\n".
                " </a>\n".
                "</td>\n";
                
        $ret .= "</tr>\n";
        
        $i++;
      }
      
      # refresh request? don't return everything
      if (!$refreshGet) {
        
        my $showPH = 0;
        $showPH = 1 if ($i==1);
        
        $ret .= "<tr class=\"sortit odd todoist_ph\"".($showPH!=1?" style=\"display:none;\"":"").">";
        $ret .= " <td colspan=\"".$cs."\">".
                "   ".$todoist_tt->{'nolistdata'}.".\n".
                " </td>";
        $ret .= "</tr>";

    
        $ret .= "<tr class=\"".$eo."\">";
      
      
        $ret .= "<td colspan=\"".$cs."\">".
                " <input type=\"hidden\" class=\"todoist_name\" id=\"todoist_name_".$name."\" value=\"".$name."\" />\n".
                " <input title=\"".$todoist_tt->{'newentry'}."\" type=\"text\" id=\"newEntry_".$name."\" />\n".
                "</td>";
        
        $ret .= "</tr>";
      
        $ret .= "</table></td></tr>\n";
        
        $ret .= "</table>\n";
      
      }
    }
  }
  
  # refresh request? don't return everything
  if (!$refreshGet) {
  
    $ret .= "</div>\n";
    $ret .= "<br style=\"clear:both;\" />";
    
  }
  
  return $rot.$ret;
}

# called if weblink widget table has to be updated
sub todoist_ReloadTable($) {
  my ($name) = @_;
  
  my $ret = todoist_Html($name,1);
  $ret =~ s/\"/\'/g;
  $ret =~ s/\n//g;
  
  map {FW_directNotify("#FHEMWEB:$_", "if (typeof todoist_reloadTable === \"function\") todoist_reloadTable('$name',\"$ret\")", "")} devspec2array("TYPE=FHEMWEB");
}

# check if element is in array
sub todoist_inArray {
  my ($arr,$search_for) = @_;
  foreach (@$arr) {
    return 1 if ($_ eq $search_for);
  }
  return 0;
}

sub todoist_genUUID() {
  srand(gettimeofday()) if(!$srandUsed);
  $srandUsed = 1;
  my $uuid = sprintf("%08x-f33f-%s-%s-%s", time(), substr(getUniqueId(),-4), 
    join("",map { unpack "H*", chr(rand(256)) } 1..2),
    join("",map { unpack "H*", chr(rand(256)) } 1..8));
  return $uuid;
}

1;

=pod
=item device
=item summary    uses todoist API to add, read, complete and delete tasks in a  todoist tasklist
=item summary_DE Taskverwaltung einer todoist Taskliste über die todoist API
=begin html

<a name="todoist"></a>
<h3>todoist</h3>
<ul>
    A module to get a task list as readings from todoist. Tasks can be completed, updated and deleted.
    The modul comes with a weblink-widget to manage tasks comfortable.
    <br /><br />
    As preparation to use this module, you need to get your API Symbol (API ID) from the
    preferences of your account. 
    <br /><br />
    Notes:<br />
    <ul>
        <li>JSON, Data::Dumper, Date::Parse, Digest::MD5, have to be installed on the FHEM host.</li>
    </ul>
    <br /><br />
    <a name="todoist_Define"></a>
    <h4>Define</h4>
    <ul>
        <code>define &lt;name&gt; todoist &lt;PROJECT-ID&gt;</code><br />
        <br />
        <b>PROJECT-ID:</b> The ID of your project (=list).<br />
        <br /><br />

        Example:
        <ul>
            <code>define Einkaufsliste todoist 257528237</code><br />
        </ul>
    </ul><br />
    <a name="todoist_Set"></a>
    <h4>Set</h4>
    <ul>
        <li><b>accessToken</b> - set the API Symbol for your todoist app</li><br />
        <li><b>active</b> - set the device active (starts the timer for reading task-list periodically)</li><br />
        <li><b>inactive</b> - set the device inactive (deletes the timer, polling is off)</li><br />
        <li><b>newAccessToken</b> - replace the saved token with a new one.</li><br />
        <li><b>getTasks</b> - get the task list immediately, reset timer.</li><br />
        <li><b>getUsers</b> - get the projects users immediately.</li><br />
        <li><b>addTask</b> - create a new task. Needs title as parameter.</li><br /><br />
        <code>set &lt;DEVICE&gt; addTask &lt;TASK_TITLE&gt;[:&lt;DUE_DATE&gt;]</code><br ><br />
        Additional Parameters are:<br />
        <ul>
         <li>dueDate (due_date)=&lt;DUE_DATE&gt; (can be free form text or format: YYYY-MM-DDTHH:MM)</li>
         <li>priority=the priority of the task (a number between 1 and 4, 4 for very urgent and 1 for natural).</li>
         <li>responsibleUid=the todoist-ID of the user who is responsible for accomplishing the current task</li>
         <li>assignedByUid=the todoist-ID of the user who assigned the current task</li>
         <li>order=the order of the task inside a project (the smallest value would place the task at the top)</li>
         <li>parentID=parent_id of the parent task. indent will be updated automatically.</li>
         <li>indent=the indent of the task (a number between 1 and 4, where 1 is top-level)</li>
        </ul><br />
        Examples: <br /><br />
            <code>set &lt;DEVICE&gt; addTask &lt;TASK_TITLE&gt; dueDate=2017-01-15 priority=2</code><br /><br />
            <code>set &lt;DEVICE&gt; addTask &lt;TASK_TITLE&gt; dueDate=morgen</code><br /><br />
        <li><b>updateTask</b> - update a task. Needs Task-ID or todoist-Task-ID as parameter<br /><br />
        Possible additional parameters are:<br />
            <ul>
             <li>dueDate (due_date)=&lt;DUE_DATE&gt; (can be free form text or format: YYYY-MM-DDTHH:MM)</li>
             <li>priority=(1..4) (string)</li>
             <li>title=&lt;TITLE&gt; (string)</li>
             <li>responsibleUid=the todoist-ID of the user who is responsible for accomplishing the current task</li>
             <li>assignedByUid=the todoist-ID of the user who assigned the current task</li>
             <li>order=the order of the task inside a project (the smallest value would place the task at the top)</li>
             <li>indent=the indent of the task (a number between 1 and 4, where 1 is top-level)</li>
             <li>parentID=parent_id of the parent task. indent will be updated automatically.</li>
             <li>remove=&lt;TYPE&gt; (comma seperated list of attributes which should be removed from the task)</li>
            </ul><br />
        Examples: <br /><br />
        <code>set &lt;DEVICE&gt; updateTask ID:12345678 dueDate=2017-01-15 priority=1</code><br />
        <code>set &lt;DEVICE&gt; updateTask 1 dueDate=übermorgen</code><br />
        <code>set &lt;DEVICE&gt; updateTask TITLE:Brot dueDate=übermorgen</code><br /><br /></li>
        <li><b>completeTask</b> - completes a task. Needs number of task (reading 'Task_NUMBER'), the title (TITLE:&lt;TITLE&gt;) or the 
        todoist-Task-ID (ID:&lt;ID&gt;) as parameter<br /><br />
        <code>set &lt;DEVICE&gt; completeTask &lt;TASK-ID&gt;</code> - completes a task by number<br >
        <code>set &lt;DEVICE&gt; completeTask ID:&lt;todoist-TASK-ID&gt;</code> - completes a task by todoist-Task-ID
        <code>set &lt;DEVICE&gt; completeTask TITLE:&lt;Task title&gt;</code> - completes a task by title<br /><br /></li>
        <li><b>closeTask</b> - closes a task. Needs number of task (reading 'Task_NUMBER')m the title (TITLE:&lt;TITLE&gt;) or the 
        todoist-Task-ID (ID:<ID>) as parameter<br />
        Difference to complete is: regular task is completed and moved to history, subtask is checked (marked as done, but not moved to history),<br /> 
        recurring task is moved forward (due date is updated).<br /><br />
        <code>set &lt;DEVICE&gt; closeTask &lt;TASK-ID&gt;</code> - completes a task by number<br />
        <code>set &lt;DEVICE&gt; closeTask ID:&lt;todoist-TASK-ID&gt;</code> - completes a task by todoist-Task-ID
        <code>set &lt;DEVICE&gt; closeTask TITLE:&lt;Task title&gt;</code> - completes a task by title<br /><br /></li>
        <li><b>uncompleteTask</b> - uncompletes a Task. Use it like complete.<br /><br /></li>
        <li><b>deleteTask</b> - deletes a task. Needs number of task (reading 'Task_NUMBER'), title (TITLE:&lt;TITLE&gt;) or the todoist-Task-ID (ID:&lt;ID&gt;) as parameter<br /><br />
        <code>set &lt;DEVICE&gt; deleteTask &lt;TASK-ID&gt;</code> - deletes a task by number<br />
        <code>set &lt;DEVICE&gt; deleteTask ID:&lt;todoist-TASK-ID&gt;</code> - deletes a task by todoist-Task-ID
        <code>set &lt;DEVICE&gt; deleteTask TITLE:&lt;Task title&gt;</code> - deletes a task by title<br /><br /></li>
        <li><b>sortTasks</b> - sort Tasks alphabetically<br /><br /></li>
        <li><b>clearList</b> - <b><u>deletes</u></b> all Tasks from the list (only FHEM listed Tasks can be deleted)<br /><br /></li>
        <li><b>cChildProjects</b> - searches for children and defines them if possible, deletes lists that are deleted 
        in todoist (Attribut delDeletedLists)<br /></li>
    </ul>
    <br />
    <a name="todoist_Attributes"></a>
    <h4>Attributes</h4>
    <ul>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a name="#disable">disable</a></li>
        <li>pollInterval
        get the list every pollInterval seconds. Default is 1800. Smallest possible value is 20.<br /><br /></li>
        <li>sortTasks
        <ul>
        <li>0: don't sort the tasks (default)</li>
        <li>1: sorts Tasks alphabetically after every update</li>
        <!--<li>2: sorts Tasks in todoist order</li>-->
        </ul></li>
        <br />
        <li>hideId
        <ul>
        <li>0: show todoist-Task-ID (default)</li>
        <li>1: hide the todoist-Task-ID</li>
        </ul></li>
        <br />
        <li>hideListIfEmpty
        <ul>
        <li>0: don't hide list in widget, if empty (default)</li>
        <li>1: hide list in widget, if empty</li>
        </ul></li>
        <br />
        <li>showPriority
        <ul>
        <li>0: don't show priority (default)</li>
        <li>1: show priority</li>
        </ul></li>
        <br />
        <li>showAssignedBy
        <ul>
        <li>0: don't show assignedByUid (default)</li>
        <li>1: show assignedByUid</li>
        </ul></li>
        <br />
        <li>showIndent
        <ul>
        <li>0: don't show indent of the task (default)</li>
        <li>1: show indent</li>
        </ul></li>
        <br />
        <li>showOrder
        <ul>
        <li>0: don't show order no. of the task (default)</li>
        <li>1: show order number</li>
        </ul></li>
        <br />
        <li>showChecked
        <ul>
        <li>0: don't show if a task is checked (for tasks with parent_id)</li>
        <li>1: show if a task is checked (default)</li>
        </ul></li>
        <br />
        <li>showDeleted
        <ul>
        <li>0: don't show if a task is deleted (for tasks with parent_id)</li>
        <li>1: show if a task is deleted (default)</li>
        </ul></li>
        <br />
        <li>showResponsible
        <ul>
        <li>0: don't show responsibleUid (default)</li>
        <li>1: show responsibleUid</li>
        </ul></li>
        <br />
        <li>showDetailWidget
        <ul>
        <li>0: don't show widget in detail view of device</li>
        <li>1: show widget in detail view of device (default)</li>
        </ul></li>
        <br />
        <li>getCompleted
        <ul>
        <li>0: don't get completet tasks (default)</li>
        <li>1: get completed tasks</li>
        </ul><br />
        <b>ATTENTION: Only premium users have access to completed tasks!</b></li>
        <br /><br />
        <li>autoGetUsers
        <ul>
        <li>0: don't get users automatically</li>
        <li>1: get users after every "getTasks" (default)</li>
        </ul></li>
        <br />
        <li>avoidDuplicates
        <ul>
        <li>0: don't check for duplicates (default)</li>
        <li>1: check for duplicates, deny new entries if task exists (exactly)</li>
        </ul></li>
        <br />
        <li>delDeletedLists
        <ul>
        <li>0: don't delete deleted childrens (default)</li>
        <li>1: delete deleted childrens</li>
        </ul></li>
        <br />
        <li>listDivider<br />
        set the divider for the Reading listText. Default is ", ".</li>
    </ul>
    
    <a name="todoist_Readings"></a>
    <h4>Readings</h4>
    <ul>
        <li>Task_XXX<br />
            the tasks are listet as Task_000, Task_001 [...].</li>
        <li>Task_XXX_parentID<br />
            parent ID of task XXX if not null</li>
        <li>Task_XXX_checked<br />
            1 when a task with parent_id is checked</li>  
        <li>Task_XXX_isDeleted<br />
            1 when a task with parent_id is deleted</li>
        <li>Task_XXX_dueDate<br />
            if a task has a due date, this reading should be filled with the date.</li>
        <li>Task_XXX_priority<br />
            the priority of your task.</li>
        <li>Task_XXX_ID<br />
            the todoist ID of Task_X.</li>
        <li>Task_XXX_completedAt<br />
            only for completed Tasks (attribute getCompleted).</li>
        <li>Task_XXX_completedById<br />
            only for completed Tasks (attribute getCompleted).</li>
        <li>Task_XXX_assignedByUid<br />
            the user this task was assigned by.</li>
        <li>Task_XXX_responsibleUid<br />
            the user this task was assigned to.</li>
        <li>Task_XXX_indent<br />
            shows the indent of the task (attribute showIndent).</li>
        <li>Task_XXX_order<br />
            shows the order no. of the task (attribute showOrder).</li>
        <li>User_XXX<br />
            the lists users are listet as User_000, User_001 [...].</li>
        <li>User_XXX_ID<br />
            the users todoist ID.</li>
        <li>listText<br />
            a comma seperated list of tasks in the specified list. This may be used for TTS, Messages etc.</li>
        <li>count<br />
            number of Tasks in list.</li>
        <li>error<br />
            current error. Default is none.</li>
        <li>lastCompletedTask<br />
            title of the last completed task.</li>
        <li>lastCreatedTask<br />
            title of the last created task.</li>
        <li>lastDeletedTask<br />
            title of the last deleted task.</li>
        <li>lastError<br />
            last Error.</li>
        <li>state<br />
            state of the todoist-Device</li>
    </ul><br />
    <a name="todoist_Weblink"></a>
    <h4>Weblinks</h4>
        FHEMWEB weblink as frontend for one or more. There are 3 different ways to setup a todoist-weblink:<br /><br />
        <ul>
          <li>Define a simple weblink for a Task list:
          <br /><br />
          <code>define &lt;NAME&gt; weblink htmlCode {todoist_Html("&lt;TODOIST-DEVCICENAME&gt;")}</code><br /><br /></li>
          <li>Define a simple weblink for all active Task lists:
          <br /><br />
          <code>define &lt;NAME&gt; weblink htmlCode {todoist_Html()}</code><br /><br /></li>
          <li>Define a simple weblink for a group of active Task lists:
          <br /><br />
          <code>define &lt;NAME&gt; weblink htmlCode {todoist_Html('&lt;REGEX-FILTER&gt;')}</code><br /><br /></li>
        </ul>
        Examples:<br /><br />
        <code>define EinkaufslisteWeb weblink htmlCode {todoist_Html("Einkaufsliste")}</code> - single list<br />
        <code>define EinkaufslistenWeb weblink htmlCode {todoist_Html()}</code> - all active lists<br />
        <code>define PapaLists weblink htmlCode {todoist_Html("Papa_list.*")}</code> - all active lists beginning with "Papa_list"
        <br /><br />
        <ul>
          <li>Tasks can be sorted, updated and added inside the widget. You can reload a list and delete all entries of a list.</li>
          <li>To check (close) a task, click the checkbox in front of the completed task.</li>
          <li>A list can be sorted by by drag & drop. You can also move a task from one list to another. This deletes the task from the "old" list and<br />
              adds it to the new one.</li>
          <li>The input field under the actual list can be used for adding tasks to this list. Leaving the field or pressing enter triggers addTask.</li>
          <li>Update a task by clicking it's text. You can edit the task in an input field. Leaving the field or pressing enter triggers updateTask.</li>
          <li>You can use parameters like "dueDate" in the input fields like this:
            <ul>
              <code>Milch -dueDate=morgen</code>
            </ul>
          </li>
          <li>Clicking the cross behind every task deletes this one for good.</li>
          <li>Clicking the trashcan symbol in the title bar of every list deletes all tasks from the list.</li>
          <li>A list can be reloaded by clicking the round arrow symbol in the title bar of every list.</li>
          <li>A list is refreshed if a getTasks for this is fired (by interval or manually).</li>
        </ul>
</ul>


=end html

=cut