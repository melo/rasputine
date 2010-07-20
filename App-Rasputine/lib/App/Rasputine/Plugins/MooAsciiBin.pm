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

sub from_world {
  my ($self, $raw, $session) = @_;
  my $stash = $session->stash;

  return $raw if $stash->{plugin_moo_ascii_bin_connected};

  if ($raw =~ m/^#\$#mcp version: \d+[.]\d+/) {
    $stash->{plugin_moo_ascii_bin_connected}++; 
    $session->line_out('@client-options charset=utf-8');
  }

  return $raw;
}

1;
