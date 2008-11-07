package App::Rasputine::Session;

use strict;
use warnings;
use base qw( Mojo::Base );
use Params::Validate qw( :all );
use AnyEvent::Socket;
use AnyEvent::Handle;

our $VERSION = '0.1';

__PACKAGE__->attr('conn');
__PACKAGE__->attr('buffer');

__PACKAGE__->attr('user');
__PACKAGE__->attr('service');
__PACKAGE__->attr('via');
__PACKAGE__->attr('world');
__PACKAGE__->attr('ras');

__PACKAGE__->attr('filters', default => []);

__PACKAGE__->attr('state', default => 'start');


#############################
# World connection management

sub connect {
  my $self = shift;
  my $world = $self->{world};

  tcp_connect $world->{host}, $world->{port}, sub {
     my ($fh) = @_;
     
     if (!$fh) {
       $self->send_message_to_user({
         mesg => qq{Connect to world '$self->{service} failed, probably down?'}
       });
       return;
     }
     
     $self->state('connected');
     
     $self->load_plugins;
     
     my %args = (
       fh       => $fh,
       on_eof   => sub { $self->close('eof')   },
       on_error => sub { $self->close('error') },
     );
     $args{tls} = 'connect' if $world->{tls};
     
     my $conn = AnyEvent::Handle->new(%args);
     
     $self->conn($conn);
     $conn->push_read(sub { $self->line_in(@_) });
     
     $self->{ras}->service_state({
       service => $self->{service},
       user    => $self->{user},
       via     => $self->{via},
       state   => $self->{state},
     });
  };
}


sub disconnect {
  my $self = shift;
  
  return unless $self->state eq 'connected';
  
  # FIXME: should we send /quit or .quit?
    
  return $self->close('disconnect_request');
}

sub close {
  my ($self, $reason) = @_;

  return unless $self->state('connected');

  my $conn = $self->{conn};
  $self->state('offline');
  $self->conn(undef);
     
  $self->{ras}->service_state({
    service => $self->{service},
    user    => $self->{user},
    via     => $self->{via},
    state   => $self->{state},
  });
  
  return;
}


#########
# Plugins

sub load_plugins {
  my $self = shift;
  
  # get the filters ready
  my $filters = $self->filters;
  foreach my $plugin (@$filters) {
    eval "require $plugin;";
    if ($@) {
      print STDERR "Could not load plugin '$plugin': $@\n";
      next;
    }
    
    $plugin = $plugin->new;
  }

  return;
}


##########
# World IO

sub line_out {
  my ($self, $line) = @_;
  
  return unless $self->state eq 'connected';
  
  my $filters = $self->filters;
  foreach my $plugin (@$filters) {
    next unless ref $plugin;
    $line = $plugin->to_world($line);
  }
  
  $self->{conn}->push_write($line."\n");
}

sub line_in {
  my ($self, $handle) = @_;

  my $line = delete $handle->{rbuf};
  return unless $line;
  
  my $filters = $self->filters;
  foreach my $plugin (@$filters) {
    next unless ref $plugin;
    $line = $plugin->from_world($line);
  }
  
  my $buffer = $self->{buffer};
  if ($buffer) { $buffer .= $line }
  else         { $buffer  = $line }
  $self->{buffer} = $buffer;
  
  # Collect more lines before sending out a message
  my $t; $t = AnyEvent->timer(
    after => 0.2,
    cb    => sub {
      $self->send_buffer_to_user;
      $t = undef;
    },
  );
  
  # Keep reading...
  return 0;
}

sub send_buffer_to_user {
  my ($self) = @_;
  
  my $buffer = delete $self->{buffer};
  return unless $buffer;
  
  $self->send_message_to_user({
    mesg => $buffer,
  });
  
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
  
  my ($cmd) = $mesg =~ m{^\s*(\w+)};
  if (!$cmd) {
    $self->send_message_to_user({ mesg => q{Help your self with 'help'} });
    return;
  }
  
  if ($cmd eq 'help') {
    $self->send_help;
  }
  elsif ($cmd eq 'connect' || $cmd eq 'ligar') {
    $self->connect;
  }
  else {
    $self->send_message_to_user({ mesg => qq{Sorry, I don't understand that} });
  }
  
  return;
}

sub send_message {
  my $self = shift;
  my %args = validate(@_, {
    mesg    => { type => SCALAR }, 
    via     => { type => SCALAR }, 
    gateway => { type => SCALAR }, 
  });
  
  $self->line_out($args{mesg});
  
  return;
}


##############################################
# Help me Obi Wan Kenobi, you're my only hope!

sub send_help {
  my $self = shift;
  
  my $mesg = <<USAGE;
Hello there, welcome to Rasputine!

Each world can be in one of two states: 'offline', or 'connected'.
All worlds start as 'offline'.

While 'offline', you can use 'connect' to start a connection to the world.
If the connection is sucessful, you become 'connected'.

When you disconnect from the world, you go back to 'offline' mode.

Commands are only accepted while in 'offline' mode.

Available commands:

  connect - connects to this world
  help    - this message again

See? Not that many commands :)
USAGE

  $self->send_message_to_user({ mesg => $mesg });
  
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


################
# Some shortcuts

sub send_message_to_user {
  my $self = shift;
  my %args = validate(@_, {
    mesg => { type => SCALAR },
  });

  my $mesg = $args{mesg};
  return unless $mesg;
  
  $self->{ras}->message_to_user({
    service => $self->{service},
    user    => $self->{user},
    mesg    => $mesg,
    via     => $self->{via},
    gateway => $self->{world}{type},
  });
  
  return;
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

