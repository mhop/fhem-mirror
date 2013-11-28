package main;
###########################
# 89_inputevent.pm
# Modul for FHEM
#
# contributed by Dirk Hoffmann 2010-2011
# $Id: 89_inputEvent.pm,v 0.2 2011/11/27 19:16:16 dirkho Exp $
#
#
# Linux::Input wird benötigt
###########################
use strict;
use Switch;
use warnings;

use IO::Select;
use Linux::Input;

use vars qw{%attr %defs};
sub Log($$);
our $FH;
####################################
# INPUTEVENT_Initialize
# Implements Initialize function
# 
sub INPUTEVENT_Initialize($) {
	my ($hash) = @_;
	Log 1, "INPUT/Event Initialize";

	# Provider
	$hash->{ReadFn}  = "INPUTEVENT_Read";
	$hash->{ReadyFn} = "INPUTEVENT_Ready";

	# Consumer
	$hash->{DefFn}   = "INPUTEVENT_Define";
	$hash->{UndefFn} = "INPUTEVENT_Undef";

	$hash->{SetFn}   = "INPUTEVENT_Set";
	$hash->{AttrList}= "model:EVENT loglevel:0,1,2,3,4,5";

	$hash->{READINGS}{uTIME}	= 0;
	$hash->{READINGS}{lastCode}	= 0;
}

#####################################
# INPUTEVENT_Define
# Implements DefFn function
#
sub INPUTEVENT_Define($$) {
	my ($hash, $def) = @_;
	my ($name, undef, $dev, $msIgnore) = split("[ \t][ \t]*", $def);

	if (!$msIgnore) {
		$msIgnore = 175;
	}

	delete $hash->{fh};
	delete $hash->{FD};

	my $fileno;

	if($dev eq "none") {
		Log 1, "Input device is none, commands will be echoed only";
		return undef;
	}

	Log 4, "Opening input device at $dev. Repeated commands within $msIgnore miliseconds was ignored.";

	if ($dev=~/^\/dev\/input/) {
		my $OS=$^O;
		if ($OS eq 'MSWin32') {
			my $logMsg = "Input devices only avilable under Linux OS at this time.";
			Log 1, $logMsg;
			return $logMsg;
		} else {
			if ($@) {
				my $logMsg = "Error using Modul Linux::Input";
				$hash->{STATE} = $logMsg;
				Log 1, $logMsg;
				return $logMsg . " Can't open Linux::Input $@\n";
			}

			my $devObj = Linux::Input->new($dev);
			if (!$devObj) {
				my $logMsg = "Error opening device";
				$hash->{STATE} = "error opening device";
				Log 1, $logMsg . " $dev";
				return "Can't open Device $dev: $^E\n";
			}

			my $select = IO::Select->new($devObj->fh);

			foreach my $fh ($select->handles) {
				$fileno = $fh->fileno;
			}
                
			$selectlist{"$name.$dev"} = $hash;
			$hash->{fh} = $devObj->fh;
			$hash->{FD} = $fileno;
			$hash->{SelectObj} = $select;
			$hash->{STATE} = "Opened";
			$hash->{DeviceName}=$name;
			$hash->{msIgnore}=$msIgnore;
			Log 4, "$name connected to device $dev";
		}

	} else {
		my $logMsg = "$dev is no device and not implemented";
		$hash->{STATE} = $logMsg;
		Log 1, $logMsg;
		return $logMsg;
	}

	return undef;
}

#####################################
# implements UnDef-Function
#
sub INPUTEVENT_Undef($$) {
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};
	my $fh = $hash->{fh};
	delete $hash->{fh};
	$hash->{STATE}='Closed';

	if ($fh) {
		$fh->close();
	}

	Log 5, "$name shutdown complete";
	return undef;
}

#####################################
# INPUTEVENT_Set
# implement SetFn
# currently nothing to set
#
sub INPUTEVENT_Ready($$) {
	my ($hash, $dev) = @_;
	my $select= $hash->{SelectObj};
	
	return ($select->can_read(0));
}

#####################################
# INPUTEVENT_Set
# implement SetFn
# currently nothing to set
#
sub INPUTEVENT_Set($@) {
	my ($hash, @a) = @_;
	my $name=$a[0];
	my $msg = "$name => No Set function implemented";

	Log 1,$msg;
	return $msg;
}

#####################################
# INPUTEVENT_Read
# Implements ReadFn, called from global select
#
sub INPUTEVENT_Read($$) {
	my ($hash) = @_;

	my $fh = $hash->{fh};
	my $select= $hash->{SelectObj};
	my $name = $hash->{NAME};

	my $message = undef;

	if( $select->can_read(0) ){ 
		$fh->read($message,16);

		INPUTEVENT_Parse($hash, $message);
    }

	return 1;
}

#####################################
# INPUTEVENT_Parse
# decodes complete frame
# called directly from INPUTEVENT_Read
sub INPUTEVENT_Parse($$) {
    my ($hash, $msg) = @_;
	my $name = $hash->{NAME};
	my $message;
	
    my ($b0,$b1,$b2,$b3,$b4,$b5,$b6,$b7,$b8,$b9,$b10,$b11,$b12,$b13,$b14,$b15) =
    	map {$_ & 0x7F} unpack("U*",$msg);
	
	my $sec = sprintf('%10s', $b0 + $b1*256 + $b2*256*256 + $b3*256*256*256);
	my $ySec = sprintf('%06s', $b4 + $b5*256 + $b6*256*256);
	my $type = $b8;
	my $code = $b10;
	my $value = sprintf('%07s', $b12 + $b13*256 + $b14*256*256);

	if ($type eq 4 && $code eq 3) {
		$message = "$name => $sec.$ySec, type: $type, code: $code, value: $value"; 

		# Set $ignoreUSecs => µSec sice last command.
		my $uTime = $sec * 1000000 + $ySec;
		my $ignoreUSecs = $uTime - $hash->{READINGS}{uTIME};
	    $hash->{READINGS}{uTIME} = $uTime;
		
		#Log 4, $hash->{READINGS}{lastCode} . " _ " . $value . " | " . $hash->{READINGS}{uTIME} . " --- " . $uTime . " +++ " . $ignoreUSecs;

		# IR-codes was repeated with short delay. So we ignor commands the next µSeconds set in the define command. (Default 175000)
		if (($ignoreUSecs > ($hash->{msIgnore} * 1000)) || ($hash->{READINGS}{lastCode} ne $value)) {
		    $hash->{READINGS}{LAST}{VAL} = unpack('H*',$msg);
		    $hash->{READINGS}{LAST}{TIME} = TimeNow();
		    $hash->{READINGS}{RAW}{TIME} = time();
		    $hash->{READINGS}{RAW}{VAL} = unpack('H*',$msg);
		    $hash->{READINGS}{lastCode} = $value;
	
			Log 4, $message;
		    
		    DoTrigger($name, $message);
		}
	}
}


#####################################
sub INPUTEVENT_List($$) {
  my ($hash,$msg) = @_;
  $msg = INPUTEVENT_Get($hash,$hash->{NAME},'list');
  return $msg;
}

1;
