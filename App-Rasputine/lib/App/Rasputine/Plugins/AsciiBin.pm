package App::Rasputine::Plugins::MooAsciiBin;

use strict;
use warnings;
use base 'App::Rasputine::Plugin';
use Encode qw( encode decode );

sub to_world {
  my ($self, $raw) = @_;
  
  my $bytes = encode('latin1', decode('utf8', $raw));
  $bytes =~ s/([\x80-\xff])/sprintf('~%X', ord($1))/ge;
  
  return $bytes;
}

1;
