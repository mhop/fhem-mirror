# $Id$
################################################################
#
#  Copyright notice
#
#  (c) 2015 Copyright: Dr. Boris Neubert
#  e-mail: omega at online dot de
#
#  This file is part of fhem.
#
#  Fhem is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  Fhem is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
################################################################################

package main;

use strict;
use warnings;
use SubProcess;

#####################################
sub
SubProcessTester_Initialize($) {
  my ($hash) = @_;
  
  my %matchlist= (
    "1:SubProcessTesterDevice" => ".*",
  );

# Provider
  $hash->{WriteFn} = "SubProcessTester_Write";
  $hash->{ReadFn}  = "SubProcessTester_Read";
  $hash->{Clients} = ":VBox:";
  $hash->{MatchList} = \%matchlist;
  #$hash->{ReadyFn} = "SubProcessTester_Ready";

# Consumer
  $hash->{DefFn}   = "SubProcessTester_Define";
  $hash->{UndefFn} = "SubProcessTester_Undef";
  #$hash->{ParseFn}   = "SubProcessTeser_Parse";
  $hash->{ShutdownFn} = "SubProcessTester_Shutdown";
  #$hash->{ReadyFn} = "SubProcessTester_Ready";
  #$hash->{GetFn}   = "SubProcessTester_Get";
  $hash->{SetFn}   = "SubProcessTester_Set";
  #$hash->{AttrFn}  = "SubProcessTester_Attr";
  #$hash->{AttrList}= "";
}

#####################################
#
# Functions called from subprocess
#
#####################################

sub onRun($) {
  my $subprocess= shift;
  my $parent= $subprocess->parent();
  Log3 undef, 1,  "SUBPROCESS: Running...";
  my $foobar= $subprocess->{foobar};
  for(my $i= 0; $i< 30; $i++) {
  
  
    my $msg= $subprocess->readFromParent();
    if(defined($msg)) {
        Log3 undef, 1, "SUBPROCESS read from parent: $msg";
        $subprocess->writeToParent("echo: $msg");
    }
    #Log3 undef, 1, "Step $i";
    # here we write something to the parent process
    # this is received via the global select loop
    # and evaluated in the ReadFn.
    $subprocess->writeToParent("$foobar $i\n");
    #print $parent "$foobar $i\n";
    #$parent->flush();
    # has the pa
    sleep 5;
  }
}

sub onExit() {
  Log3 undef, 1, "EXITED!";
}

#####################################
#
# FHEM functions
#
#####################################

sub SubProcessTester_Define($$) {

  # define mySubProcessTester SubProcessTester configuration
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  
  if(int(@a) != 2) {
    my $msg = "wrong syntax: define <name> SubProcessTester <configuration>";
    Log3 $hash, 2, $msg;
    return $msg;
  }
 
  SubProcessTester_DoInit($hash);
  return undef;
}

sub SubProcessTester_Undef($$) {
  my $hash= shift;
  SubProcessTester_DoExit($hash);
  return undef;
}

sub SubProcessTester_Shutdown($$) {
  my $hash= shift;
  SubProcessTester_DoExit($hash);
  return undef;
}

sub SubProcessTester_Set() {

  my ($hash, @a)= @_;

  my $name= $hash->{NAME};
  my $cmdname= $a[1];
  my $value= $a[2];
  if($cmdname eq "send") {
    my $subprocess= $hash->{fhem}{subprocess};
    Log3 $hash, 5, "Before send....";
    $subprocess->writeToChild($value);
    Log3 $hash, 5, "After send....";
    return undef;
  } else {
    return "Unknown argument $cmdname, choose one of send";
  }


}

#####################################

sub SubProcessTester_DoInit($) {
  my $hash = shift;
  my $name= $hash->{NAME};

  $hash->{fhem}{subprocess}= undef;
  
  my $subprocess= SubProcess->new( { onRun => \&onRun, onExit => \&onExit } );
  # you can set your own variables like this:
  $subprocess->{foobar}= "foo / bar";
  # remember: as soon as the subprocess is started, parent and child process live
  # in separate processes and cannot share data anymore - changing variables in
  # the parent does not affect variables in the child and vice versa.
  my $pid= $subprocess->run();
  return unless($pid);

  $hash->{fhem}{subprocess}= $subprocess;
  $hash->{FD}= fileno $subprocess->child();
  delete($readyfnlist{"$name.$pid"});   
  $selectlist{"$name.$pid"}= $hash;

  $hash->{STATE} = "Initialized";

  return undef;
}

sub SubProcessTester_DoExit($) {
  my $hash = shift;

  my $name= $hash->{NAME};
  
  my $subprocess= $hash->{fhem}{subprocess};
  return unless(defined($subprocess));
  
  my $pid= $subprocess->pid();
  return unless($pid);
  
  $subprocess->terminate();
  $subprocess->wait();

  delete($selectlist{"$name.$pid"});
  delete $hash->{FD};

  $hash->{STATE} = "Finalized";

  return undef;
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub SubProcessTester_Read($) {

  my ($hash) = @_;
  my $name= $hash->{NAME};
  
  #Debug "$name has data to read!";
  
  my $subprocess= $hash->{fhem}{subprocess};
  
  # here we read from the global select loop what was
  # written in the onRun function
  my $result= $subprocess->readFromChild();
  if(defined($result)) {
    chomp $result;
    readingsSingleUpdate($hash, "step", $result, 1);
  }
  return $result;
}


#############################
1;
#############################


=pod
=begin html

<a name="SubProcessTester"></a>
<h3>SubProcessTester</h3>
<ul>
  <br>

  <a name="SubProcessTester"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SubProcessTester &lt;config&gt;</code><br>
    <br>
  </ul>  

</ul>


=end html
