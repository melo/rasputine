package App::Rasputine;

use warnings;
use strict;
use base qw( Mojo::Base );
use AnyEvent;
use App::Rasputine::XMPP;
use App::Rasputine::Session;
use Params::Validate qw( :all );

our $VERSION = '0.01';

##########################
# Configuration attributes

__PACKAGE__->attr('xmpp',     chained => 1, default => {});
__PACKAGE__->attr('services', chained => 1, default => {});

__PACKAGE__->attr('xmpp_gw');


################
# Service access

sub service {
  my ($self, $service) = @_;
  my $srvs = $self->services;

  return undef unless $srvs->{$service};
  return $srvs->{$service};
}

sub is_valid_service {
  my $self = shift;
  
  return 1 if defined $self->service(@_);
  return;
}


#################
# Session manager

__PACKAGE__->attr('sessions', default => {});

sub session_for {
  my $self = shift;
  my %args = validate(@_, {
    service => { type => SCALAR }, 
    user    => { type => SCALAR }, 
    via     => { type => SCALAR }, 
  });

  my $valid_services = $self->services;
  return 'service_not_found' unless exists $valid_services->{$args{service}};
  
  my $sessions = $self->sessions;
  my $user_session = $sessions->{$args{user}}{$args{service}};
  
  $user_session = $self->start_session(%args)
    unless $user_session;
  
  return $user_session;
}

sub start_session {
  my $self = shift;
  my $sessions = $self->sessions;
  my %args = validate(@_, {
    service => { type => SCALAR }, 
    user    => { type => SCALAR }, 
    via     => { type => SCALAR }, 
  });

  my $valid_services = $self->services;
  return 'service_not_found' unless exists $valid_services->{$args{service}};
  my $srv = $valid_services->{$args{service}};
  
  my $sess = $sessions->{$args{user}}{$args{service}} = App::Rasputine::Session->new({
    %args,
    ras => $self,
    filters => ($srv->{filters} || []),
  });
  $sess->start if $sess;
  
  return $sess;
}


#########################
# Deal with user presence

sub user_offline {
  my $self = shift;
  my %args = validate(@_, {
    service => { type => SCALAR }, 
    user    => { type => SCALAR }, 
    via     => { type => SCALAR }, 
  });
  
  my $user_session = $self->session_for(%args);
  return $user_session unless ref($user_session);
  
  return $user_session->disconnect();
}

sub service_state {
  my $self = shift;
  my %args = validate(@_, {
    service => { type => SCALAR }, 
    user    => { type => SCALAR }, 
    via     => { type => SCALAR }, 
    state   => { type => SCALAR }, 
  });

  $self->xmpp_gw->service_state(%args);
  
  return;
}


###################
# Welcome new users

sub welcome_user {
  my $self = shift;
  my %args = validate(@_, {
    service => { type => SCALAR }, 
    user    => { type => SCALAR }, 
    via     => { type => SCALAR }, 
  });

  my $user_session = $self->session_for(%args);
  return $user_session unless ref($user_session);
  
  return $user_session->welcome_user();
}


##########
# Messages

sub message_to_world {
  my $self = shift;
  my %args = validate(@_, {
    service => { type => SCALAR }, 
    user    => { type => SCALAR }, 
    mesg    => { type => SCALAR }, 
    via     => { type => SCALAR }, 
    gateway => { type => SCALAR }, 
  });
  
  my $user_session = $self->session_for({
    service => $args{service},
    user    => $args{user},
    via     => $args{via},
  });
  return $user_session unless ref($user_session);

  return $user_session->message_out({
    mesg    => $args{mesg},
    via     => $args{via},
    gateway => $args{gateway},
  });
}

sub message_to_user {
  my $self = shift;
  my %args = validate(@_, {
    service => { type => SCALAR },
    user    => { type => SCALAR }, 
    mesg    => { type => SCALAR },
    via     => { type => SCALAR }, 
    gateway => { type => SCALAR }, 
  });
  
  return $self->xmpp_gw->message_out(%args);
}


################
# Start it up...

__PACKAGE__->attr('alive', chained => 1);

sub run {
  my $self = shift;
  
  $self->start_xmpp_connection;
  
  my $alive = AnyEvent->condvar;
  $self->alive($alive);
  
  $alive->recv;
  
  return;
}

sub start_xmpp_connection {
  my $self = shift;
  
  my $xmpp_gw = App::Rasputine::XMPP->new({ ras => $self });
  $xmpp_gw->start;

  $self->xmpp_gw($xmpp_gw);
  
  return;
}


42; # End of App::Rasputine

__END__

=encoding utf8


=head1 NAME

App::Rasputine - Because some things never die


=head1 VERSION

Version 0.01


=head1 SYNOPSIS

    use App::Rasputine;
    
    my $ras = App::Rasputine->new({

      # XMPP XEP-0114 connection
      xmpp => {
        domain => 'rasputine.simplicidade.org',
        server => '127.0.0.1',
        port   => 5252,
        secret => 'yeah, right!',
      },
      
      # white-list of supported services
      services => {
        selva => {
          host => 'selva.grogue.org',
          port => 8888,
          type => 'talker',
        },
        
        moosaico => {
          host => 'moosaico.org',
          port => 7777,
          type => 'moo',
        },
      },
      
      # Web admin interface
      # ... keep dreaming... :)
    });


=head1 DESCRIPTION

Rasputine is a XMPP-to-MUD/Moo/Talker systems.


=head1 EXPORT

This module does not export nothing.



=head1 AUTHOR

Pedro Melo, C<< <melo at cpan.org> >>



=head1 BUGS

Please report any bugs or feature requests to C<bug-app-rasputine at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=App-Rasputine>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.



=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc App::Rasputine


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

