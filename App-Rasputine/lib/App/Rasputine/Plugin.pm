package App::Rasputine::Plugin;

use strict;
use warnings;

sub new {
  my $class = shift;
  
  return bless {}, $class;
}

sub to_world {
  my ($self, $raw) = @_;
  
  return $raw;
}

sub from_world {
  my ($self, $raw) = @_;
  
  return $raw;
}


1;
