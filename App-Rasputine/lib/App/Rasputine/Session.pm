package App::Rasputine::Session;

use strict;
use warnings;
use base qw( Mojo::Base );
use Params::Validate qw( :all );

our $VERSION = '0.1';

__PACKAGE__->attr('conn');
__PACKAGE__->attr('user');
__PACKAGE__->attr('service');
__PACKAGE__->attr('via');
__PACKAGE__->attr('world');
__PACKAGE__->attr('ras');

__PACKAGE__->attr('state', default => 'start');


#############################
# World connection management

sub disconnect {
  my $self = shift;
  
  return unless $self->state eq 'connected';
  
  # Disconnect session from world
  
  return;
}

####################
# A message, for me?

sub message_out {
  my $self = shift;
  my %args = validate(@_, {
    mesg    => { type => SCALAR }, 
    via     => { type => SCALAR }, 
    gateway => { type => SCALAR }, 
  });
  my $mesg = $args{mesg};
  
  return $self->parse_commands(%args) if $self->{state} eq 'offline';
  return $self->send_message(%args)   if $self->{state} eq 'connected';
  
  return;
}

sub parse_commands {
  my $self = shift;
  my %args = validate(@_, {
    mesg    => { type => SCALAR }, 
    via     => { type => SCALAR }, 
    gateway => { type => SCALAR }, 
  });
  my $mesg = $args{mesg};
  
  my ($cmd) = $mesg =~ m{^\s*//(\w+)};
  if (!$cmd) {
    $self->{ras}->message_to_user({
      service => $self->{service},
      user    => $self->{user},
      mesg    => q{Help your self with '//help'},
      via     => $args{via},
      gateway => $self->{world}{type},
    });
    return;
  }
  
  # FIXME: Deal with commands here
  $self->{ras}->message_to_user({
    service => $self->{service},
    user    => $self->{user},
    mesg    => qq{Aye, Aye, Sir! '$cmd' understood!},
    via     => $args{via},
    gateway => $self->{world}{type},
  });
  
  return;
}

sub send_message {}


##############################################
# Help me Obi Wan Kenobi, you're my only hope!

sub send_help {
  my $self = shift;
  my $srv = $self->{service};
  
  my $mesg = <<USAGE;
Hello there, welcome to Rasputine!

Each world can be in one of two states: 'offline', or 'connected'.
All worlds start as 'offline'.

While 'offline', you can use //connect to start a connection to the world.
If the connection is sucessful, you become 'connected'.

When you disconnect from the world, you go back to 'offline' mode.

Commands are only accepted while in 'offline' mode.


Available commands:

//connect - connects to this world
//help    - this message again

See? Not that many commands :)
USAGE

  $self->{ras}->message_to_user({
    service => $srv,
    user    => $self->{user},
    mesg    => $mesg,
    via     => $self->{via},
    gateway => $self->{world}{type},
  });
  
  return;
}


##############
# Welcome user

sub welcome_user {
  my $self = shift;
  
  $self->send_help;
  
  return;
}


######################
# Start a user session

sub start {
  my $self = shift;
  
  $self->state('offline');
  
  return;
}


#######################
# Init our world config

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(@_);
  
  my $srv = $self->{service};
  my $srvs = $self->{ras}->services;
  return 'service_not_found' unless exists $srvs->{$srv};
  
  $self->world($srvs->{$srv});
  # FIXME: check world is correct?
  
  return $self;
}



42; # End of App::Rasputine::Session

__END__

=encoding utf8

=head1 NAME

App::Rasputine::Session - A world session



=head1 VERSION

Version 0.1



=head1 SYNOPSIS

    use App::Rasputine::Session;

    ...


=head1 DESCRIPTION



=head1 AUTHOR

Pedro Melo, C<< <melo at cpan.org> >>



=head1 BUGS

Please report any bugs or feature requests to C<bug-app-rasputine at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=App-Rasputine>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.



=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc App::Rasputine::Session


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Rasputine>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/App-Rasputine>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/App-Rasputine>

=item * Search CPAN

L<http://search.cpan.org/dist/App-Rasputine>

=back


=head1 ACKNOWLEDGEMENTS

Kudos to Mind Booster Noori to make me write it.


=head1 COPYRIGHT & LICENSE

Copyright 2008 Pedro Melo.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

