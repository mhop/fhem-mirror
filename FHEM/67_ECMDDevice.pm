#
#
# 66_ECMDDevice.pm
# written by Dr. Boris Neubert 2011-01-15
# e-mail: omega at online dot de
#
##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub ECMDDevice_Get($@);
sub ECMDDevice_Set($@);
sub ECMDDevice_Define($$);

my %gets= (
);

my %sets= (
);

###################################
sub
ECMDDevice_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "ECMDDevice_Get";
  $hash->{SetFn}     = "ECMDDevice_Set";
  $hash->{DefFn}     = "ECMDDevice_Define";

  $hash->{AttrList}  = "loglevel 0,1,2,3,4,5";
}

sub
ECMDDevice_AnalyzeCommand($)
{
        my ($ecmd)= @_;
        Log 5, "ECMDDevice: Analyze command >$ecmd<";
        return AnalyzePerlCommand(undef, $ecmd);
}

#############################
sub
ECMDDevice_GetDeviceParams($)
{
        my ($hash)= @_;
        my $classname= $hash->{fhem}{classname};
        my $IOhash= $hash->{IODev};
        if(defined($IOhash->{fhem}{classDefs}{$classname}{params})) {
                my $params= $IOhash->{fhem}{classDefs}{$classname}{params};
                return split("[ \t]+", $params);
        }
        return;
}

sub
ECMDDevice_DeviceParams2Specials($)
{
        my ($hash)= @_;
        my %specials= (
                "%NAME" => $hash->{NAME},
                "%TYPE" => $hash->{TYPE}
        );
        my @deviceparams= ECMDDevice_GetDeviceParams($hash);
        foreach my $param (@deviceparams) {
                $specials{"%".$param}= $hash->{fhem}{params}{$param};
        }
        return %specials;
}

###################################
sub
ECMDDevice_Changed($$$)
{
        my ($hash, $cmd, $value)= @_;

        my $name= $hash->{NAME};

        $hash->{READINGS}{$cmd}{TIME} = TimeNow();
        $hash->{READINGS}{$cmd}{VAL} = $value;

        $hash->{CHANGED}[0]= "$cmd: $value";

        DoTrigger($name, undef) if($init_done);

        $hash->{STATE} = "$cmd: $value";
        Log GetLogLevel($name, 4), "ECMDDevice $name $cmd: $value";

        return $hash->{STATE};

}

###################################
sub
ECMDDevice_Get($@)
{
        my ($hash, @a)= @_;

        my $name= $hash->{NAME};
        my $type= $hash->{TYPE};
        return "get $name needs at least one argument" if(int(@a) < 2);
        my $cmdname= $a[1];

        my $IOhash= $hash->{IODev};
        my $classname= $hash->{fhem}{classname};
        if(!defined($IOhash->{fhem}{classDefs}{$classname}{gets}{$cmdname})) {
                return "$name error: unknown command $cmdname";
        }

        my $ecmd= $IOhash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{cmd};
        my $params= $IOhash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{params};

        my %specials= ECMDDevice_DeviceParams2Specials($hash);
        # add specials for command
        if($params) {
                shift @a; shift @a;
                my @params= split('[\s]+', $params);
                return "Wrong number of parameters." if($#a != $#params);

                my $i= 0;
                foreach my $param (@params) {
                        Log 5, "Parameter %". $param . " is " . $a[$i];
                        $specials{"%".$param}= $a[$i++];
                }
        }
        $ecmd= EvalSpecials($ecmd, %specials);

        my $r = ECMDDevice_AnalyzeCommand($ecmd);

        my $v= IOWrite($hash, $r);

        return ECMDDevice_Changed($hash, $cmdname, $v);
}


#############################
sub
ECMDDevice_Set($@)
{
        my ($hash, @a)= @_;

        my $name= $hash->{NAME};
        my $type= $hash->{TYPE};
        return "set $name needs at least one argument" if(int(@a) < 2);
        my $cmdname= $a[1];

        my $IOhash= $hash->{IODev};
        my $classname= $hash->{fhem}{classname};
        if(!defined($IOhash->{fhem}{classDefs}{$classname}{sets}{$cmdname})) {
                return "$name error: unknown command $cmdname";
        }

        my $ecmd= $IOhash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{cmd};
        my $params= $IOhash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{params};

        my %specials= ECMDDevice_DeviceParams2Specials($hash);
        # add specials for command
        if($params) {
                shift @a; shift @a;
                my @params= split('[\s]+', $params);
                return "Wrong number of parameters." if($#a != $#params);

                my $i= 0;
                foreach my $param (@params) {
                        $specials{"%".$param}= $a[$i++];
                }
        }
        $ecmd= EvalSpecials($ecmd, %specials);

        my $r = ECMDDevice_AnalyzeCommand($ecmd);

        my $v= IOWrite($hash, $r);
        $v= $params if($params);

        return ECMDDevice_Changed($hash, $cmdname, $v);

}


#############################

sub
ECMDDevice_Define($$)
{
        my ($hash, $def) = @_;
        my @a = split("[ \t]+", $def);

        return "Usage: define <name> ECMDDevice <classname> [...]"    if(int(@a) < 3);
        my $name= $a[0];
        my $classname= $a[2];

        AssignIoPort($hash);

        my $IOhash= $hash->{IODev};
        if(!defined($IOhash->{fhem}{classDefs}{$classname}{filename})) {
                my $err= "$name error: unknown class $classname.";
                Log 1, $err;
                return $err;
        }

        $hash->{fhem}{classname}= $classname;

        my @prms= ECMDDevice_GetDeviceParams($hash);
        my $numparams= 0;
        $numparams= $#prms+1 if(defined($prms[0]));
        #Log 5, "ECMDDevice $classname requires $numparams parameter(s): ". join(" ", @prms);

        # keep only the parameters
        shift @a; shift @a; shift @a;

        # verify identical number of parameters
        if($numparams != $#a+1) {
                my $err= "$name error: wrong number of parameters";
                Log 1, $err;
                return $err;
        }

        # set parameters
        for(my $i= 0; $i< $numparams; $i++) {
                $hash->{fhem}{params}{$prms[$i]}= $a[$i];
        }
        return undef;
}

1;
