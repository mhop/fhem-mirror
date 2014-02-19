package main;

use JSON;
use HTTP::Request;
use LWP::UserAgent;
use IO::Socket::SSL;
use utf8;

my @gets = ('dummy');

sub
andnotify_Initialize($)
{
my ($hash) = @_;
 $hash->{DefFn}    = "andnotify_Define";
 $hash->{StateFn}  = "andnotify_SetState";
 $hash->{SetFn}    = "andnotify_Set";
 $hash->{AttrList} = "loglevel:0,1,2,3,4,5";

}

sub
andnotify_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  $val = $1 if($val =~ m/^(.*) \d+$/);
  return "Undefined value $val" if(!defined($it_c2b{$val}));
  return undef;
}


sub
andnotify_Define($$)
{
 my ($hash, $def) = @_;

 my @args = split("[ \t]+", $def);

 if (int(@args) < 1)
 {
  return "energy_Define: too much arguments. Usage:\n" .
         "define <name> andnotify <apikey>";
 }

 $hash->{APIKEY} = $args[2];
 $hash->{REGIDS}= $args[3];
 $hash->{STATE} = 'Initialized';

 Log 3, "$hash->{NAME} APIKEY: $hash->{APIKEY} REGIDS: $hash->{REGIDS}";

 return undef;
}

sub andnotify_Set($@)
{
  my $json = JSON->new->allow_nonref;
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $apikey = $hash->{APIKEY};
  my $count = @a;

  my $arg    = lc($a[1]);      
  my $cont1  = ucfirst($arg);  
  my $cont2 = ""; 
  my $cont3 = "";
  my $cont4 = "";
  my $cont5 = "";
  my $cont6 = "";
  my $cont7 = "";
  my $cont8 = "";
  my $cont9 = "";
	
  if (defined $a[2]) { $cont2 = $a[2]}
  if (defined $a[3]) { $cont3 = $a[3]}
  if (defined $a[4]) { $cont4 = $a[4]}
  if (defined $a[5]) { $cont5 = $a[5]}
  if (defined $a[6]) { $cont6 = $a[6]}
  if (defined $a[7]) { $cont7 = $a[7]}
  if (defined $a[8]) { $cont8 = $a[8]}
  if (defined $a[9]) { $cont9 = $a[9]}

  my $fullcmd="$a[2]";
  
  for (my $i=3;$i<$count;$i+=1){ $fullcmd="$fullcmd $a[$i]";}
  
  my @param = split(/\|/, $fullcmd);

if ( $arg eq "regids" )
{	
	$hash->{REGIDS}=$fullcmd;
	 Log 3, "AndNotify $hash->{NAME} SET REGIDS: $hash->{REGIDS}";
}

if ( $arg eq "send" )
{	
	my $client = LWP::UserAgent->new();
	my @registration_ids = split(/\|/, $hash->{REGIDS});
	my $unix_timestamp = time*1000;
	
	if ($param[5]<1)
	{
		$param[5]="0";
	}
	
	if (substr($param[0],0,5) eq "file:")
	{
		my @msg = split(/\ /, $param[0]);
		my @temp_string;
		my $document;
		my $iii=0;
		foreach (@msg){
			@temp_string = split(/\:/, $_);
			if ($iii eq 0)
			{
				my $file = $temp_string[1];
				$document = do {
					local $/ = undef;
					open my $fh, "<", $file or Log 3, "Notify -> could not open $file";
					<$fh>;
				};
				$iii=$iii+1;
			}
			else
			{
				$document =~ s/$temp_string[0]/$temp_string[1]/g;
			}
		}
		$param[0]=$document;
	}
	
	my $data = {
	registration_ids => [ "$registration_ids[0]", "$registration_ids[1]", "$registration_ids[2]", "$registration_ids[3]", "$registration_ids[4]", "$registration_ids[5]", "$registration_ids[6]", "$registration_ids[7]", "$registration_ids[8]", "$registration_ids[9]" ],
	data             => {
	message => $param[0],
	tickerText => $param[1],
	contentTitle => $param[2],
	contentText => $param[3],
	timestamp => $unix_timestamp,
	icon => $param[4],
	customid => $param[5]
	}
	};

	my $req = HTTP::Request->new(POST => "https://android.googleapis.com/gcm/send");
	$req->header(Authorization  => 'key='.$apikey);
	$req->header('Content-Type' => 'application/json; charset=UTF-8');
	$req->content($json->encode($data));
	$client->request($req);
	Log 3, "Notify gesendet";
}

if ( $arg eq "wake" )
{	
	my $client = LWP::UserAgent->new();
	my @registration_ids = split(/\|/, $hash->{REGIDS});
	my $unix_timestamp = time*1000;
	my $data = {
	registration_ids => [ "$registration_ids[0]", "$registration_ids[1]", "$registration_ids[2]", "$registration_ids[3]", "$registration_ids[4]", "$registration_ids[5]", "$registration_ids[6]", "$registration_ids[7]", "$registration_ids[8]", "$registration_ids[9]" ],
	data             => {
	wake => 1
	}
	};
	my $req = HTTP::Request->new(POST => "https://android.googleapis.com/gcm/send");
	$req->header(Authorization  => 'key='.$apikey);
	$req->header('Content-Type' => 'application/json; charset=UTF-8');
	$req->content($json->encode($data));
	$client->request($req);
	Log 3, "Notify wake gesendet";
}

if ( $arg eq "sleep" )
{	
	my $client = LWP::UserAgent->new();
	my @registration_ids = split(/\|/, $hash->{REGIDS});
	my $unix_timestamp = time*1000;
	my $data = {
	registration_ids => [ "$registration_ids[0]", "$registration_ids[1]", "$registration_ids[2]", "$registration_ids[3]", "$registration_ids[4]", "$registration_ids[5]", "$registration_ids[6]", "$registration_ids[7]", "$registration_ids[8]", "$registration_ids[9]" ],
	data             => {
	sleep => 1
	}
	};
	my $req = HTTP::Request->new(POST => "https://android.googleapis.com/gcm/send");
	$req->header(Authorization  => 'key='.$apikey);
	$req->header('Content-Type' => 'application/json; charset=UTF-8');
	$req->content($json->encode($data));
	$client->request($req);
	Log 3, "Notify sleep gesendet";
}

}
