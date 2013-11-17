package YAF::YAFApplication;

use strict;
use warnings;

use base "YAFWebserver::YAFApplicationBase";

sub new {
   my $class = shift;
   my $self = YAFWebserver::YAFApplicationBase->new; 

   # routes
   $self->add_route("^/Error\$", "YAFWebserver::Controller::DebugRequest", "show_error");   
   $self->add_route("^/.*\$", "YAFWebserver::Controller::DebugRequest", "show_debug");
 
   bless $self, $class; 
}

1;