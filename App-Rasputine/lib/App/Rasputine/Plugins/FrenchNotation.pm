package App::Rasputine::Plugins::FrenchNotation;

use strict;
use warnings;
use base 'App::Rasputine::Plugin';
use Encode 'decode';
use encoding 'utf8';

our %chars = (
  'á' => 'a´',
  'é' => 'e´',
  'í' => 'i´',
  'ó' => 'o´',
  'ú' => 'u´',
  'à' => 'a`',
  'è' => 'e`',
  'ì' => 'i`',
  'ò' => 'o`',
  'ù' => 'u`',
  'ã' => 'a~',
  'õ' => 'o~',
  'â' => 'a^',
  'ê' => 'e^',
  'î' => 'i^',
  'ô' => 'o^',
  'û' => 'u^',
  'ç' => 'c,',
  'Á' => 'A´',
  'É' => 'E´',
  'Í' => 'I´',
  'Ó' => 'O´',
  'Ú' => 'U´',
  'À' => 'A`',
  'È' => 'E`',
  'Ì' => 'I`',
  'Ò' => 'O`',
  'Ù' => 'U`',
  'Ã' => 'A~',
  'Õ' => 'O~',
  'Â' => 'A^',
  'Ê' => 'E^',
  'Î' => 'I^',
  'Ô' => 'O^',
  'Û' => 'U^',
  'Ç' => 'C,',
);

our $match;

sub to_world {
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

