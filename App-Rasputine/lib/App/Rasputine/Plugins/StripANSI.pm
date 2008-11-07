package App::Rasputine::Plugins::StripANSI;

use strict;
use warnings;
use base 'App::Rasputine::Plugin';
use Encode 'decode';
use encoding 'utf8';

our %chars = (
  '\033[0m' => '',   
  '\033[1m' => '',  
  '\033[4m' => '',  
  '\033[5m' => '',  
  '\033[7m' => '',   
  '\033[30m' => '', 
  '\033[31m' => '',
  '\033[32m' => '',
  '\033[33m' => '',
  '\033[34m' => '',
  '\033[35m' => '',
  '\033[36m' => '',
  '\033[37m' => '',
  '\033[40m' => '',
  '\033[41m' => '',
  '\033[42m' => '',
  '\033[43m' => '',
  '\033[44m' => '',
  '\033[45m' => '',
  '\033[46m' => '',
  '\033[47m' => '',
  '\033[36m' => '',
  '\033[46m' => '', 
);

our $match;

sub from_world {
  my ($self, $raw) = @_;
  
  if (!$match) {
    $match = join('', keys %chars);
    $match = qr/([$match])/o;
  }
  
  $raw = decode('utf8', $raw);
  $raw =~ s/$match/$chars{$1}/ge;
  
  return $raw;
}

1;
