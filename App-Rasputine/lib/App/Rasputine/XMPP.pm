package App::Rasputine::XMPP;

use strict;
use warnings;
use base qw( Mojo::Base );
use Net::XMPP2::Component;
use Net::XMPP2::Util qw( split_jid bare_jid );
use Params::Validate qw( :all );


our $VERSION = '0.1';

__PACKAGE__->attr('ras', chained => 1);
__PACKAGE__->attr('conn', chained => 1);
__PACKAGE__->attr('resources', default => {});

#####################
# Presence processing

sub presence_in {
  my ($self, $conn, $node) = @_;
  my $type = $node->attr('type') || '';
  
  if    ($type eq 'probe')       { $self->presence_probe($node)         }
  elsif ($type eq 'subscribe')   { $self->subscription_request($node)   }
  elsif ($type eq 'unsubscribe') { $self->unsubscription_request($node) }
  elsif ($type eq 'unavailable') { $self->presence_offline($node)       }
  elsif (!$type)                 { $self->presence_update($node)        }

  return;
}

sub send_presence {
  my ($self, $node, $type) = @_;

  # We are online by default
  my $from = $node->attr('from');
  my $to   = $node->attr('to');
  
  $to .= '/rasputine' if !$type || $type eq 'unavailable';
  
  $self->{conn}->send_presence($type, undef, 
    to => $from,
    from => $to,
  );
}

sub presence_probe {
  my $self = shift;
  
  return $self->send_presence(@_);
}

sub subscription_request {
  my ($self, $node) = @_;
  
  $self->send_presence($node, 'subscribed');
  $self->send_presence($node, 'subscribe');
  $self->send_presence($node);
  
  my ($service, $via) = split_jid($node->attr('to'));
  my $user = bare_jid($node->attr('from'));
  
  $self->{ras}->welcome_user({
    service => $service,
    user    => $user,
    via     => $via,
  });
}

sub unsubscription_request {
  my ($self, $node) = @_;
  
  $self->send_presence($node, 'unavailable');
  $self->send_presence($node, 'unsubscribed');
  $self->send_presence($node, 'unsubscribe');  
}

sub presence_update  {
  my ($self, $node) = @_;
  
  my ($service, $via) = split_jid($node->attr('to'));
  my $from = $node->attr('from');
  my $user = bare_jid($from);
  
  my $resr = $self->resources;
  
  $resr->{$user}{$from} = {
    type => $node->attr('type'),
  };
  
  return;
}

sub presence_offline {
  my ($self, $node) = @_;
  
  my ($service, $via) = split_jid($node->attr('to'));
  my $from = $node->attr('from');
  my $user = bare_jid($from);
  
  my $resr = $self->resources;
  delete $resr->{$user}{$from};
  
  return if %{$resr->{$user}};
  
  $self->{ras}->user_offline({
    service => $service,
    user    => $user,
    via     => $via,
  });
  
  return;
}


####################
# Message processing

sub message_in {
  my ($self, $conn, $node) = @_;
  my $resr = $self->resources;
  print STDERR "*** XMPP MESSAGE IN\n";
  
  my $from = $node->attr('from');
  my $to   = $node->attr('to');
  my $type = $node->attr('type');

  # message type must be empty or 'chat'  
  return if $type && $type ne 'chat';
  
  my $body = _extract_body($node);
  return unless $body;
  
  my ($service, $via) = split_jid($to);
  my $user = bare_jid($from);

  my $error = $self->{ras}->message_to_world({
    service => $service,
    user    => $user,
    mesg    => $body,
    via     => $via,
    gateway => 'xmpp',
  });
  return unless $error;
  
  print STDERR "*** XMPP MESSAGE IN ERROR! $error\n";
  
  # For now our only message, but should be for error 'service_not_found'
  # if ($error eq 'service_not_found') {}
  my $err_mesg = 'These are not the droids you are looking for...';
  
  $self->message_out({
    mesg    => $err_mesg,
    user    => $user,
    service => $service,
    via     => $via,
    gateway => 'xmpp',
  });
  
  return;
}

sub _extract_body {
  my ($node) = shift;
  
  foreach my $child ($node->nodes) {
    return $child->text 
      if $child->eq('client', 'body')
      || $child->eq('jabber:component:accept', 'body');
  }
  
  return '';
}

sub message_out {
  my $self = shift;
  my %args = validate(@_, {
    service => { type => SCALAR },
    user    => { type => SCALAR }, 
    mesg    => { type => SCALAR },
    via     => { type => SCALAR }, 
    gateway => { type => SCALAR }, 
  });
  print STDERR "*** XMPP MESSAGE OUT $args{service} $args{user}\n";
  
  # IM doesn't need the trailing \n and some talkers use \r\n
  my $mesg = $args{mesg};
  $mesg =~ s/\r?\n$//gsm;
  return unless $mesg;
  
  $self->{conn}->send_message($args{user}, undef, undef,
    body => $mesg,
    from => "$args{service}\@$args{via}/rasputine",
  );
}


##########################
# Get the show on the road

sub start {
  my $self = shift;
  
  $self->_connect;
}

################################
# XMPP component connection mgmt

sub _connect {
  my $self = shift;
  my $ras  = $self->{ras};
  my $config = $ras->xmpp;
  
  foreach my $cfg_key (qw( domain server port secret )) {
    die("XMPP: Missing required configuration key '$cfg_key'\n")
      unless $config->{$cfg_key};
  }
  
  my $conn = Net::XMPP2::Component->new(%$config);

  $conn->reg_cb(
    session_ready   => sub { $self->_on_connected(@_)  },
    disconnect      => sub { $self->_on_disconnect(@_) },
  );
  
  $conn->reg_cb(
    debug_recv   => sub { print STDERR "IN:  $_[1]\n" },
    debug_send   => sub { print STDERR "OUT: $_[1]\n" },
  ) if $config->{xml_debug};
    
  $conn->connect;
  
  $self->{conn} = $conn;
  
  return;
}

sub _on_connected {
  my $self = shift;
  
  print STDERR "Connection to XMPP server is live!\n";
  
  $self->{conn}->reg_cb(
    recv_stanza_xml => sub { $self->_on_stanza(@_) },
    message_xml     => sub { $self->message_in(@_) },
    presence_xml    => sub { $self->presence_in(@_) },
  );
}

sub _on_disconnect {
  my $self = shift;
  
  print STDERR "XMPP component lost connection... Reconnecting...\n";

  # Destroy old connection
  $self->{conn} = undef;
  
  # Assume auto-reconnect
  my $delay; $delay = AnyEvent->timer(
    after => 0.1,
    cb    => sub {
      $self->_connect;
      $delay = undef;
    },
  );
  
  return;
}

sub _on_stanza {
  my ($self, $conn, $node) = @_;
  
  if ($node->eq(component => 'iq')) {
    $conn->event(iq_xml => $node);
    $conn->handle_iq($node);
  }
  elsif ($node->eq(component => 'message')) {
    $conn->event(message_xml => $node);
  }
  elsif ($node->eq(component => 'presence')) {
    $conn->event(presence_xml => $node);
  }
  
  return;
}

42; # End of App::Rasputine::XMPP

__END__

=encoding utf8

=head1 NAME

App::Rasputine::XMPP - The XMPP connector for the Rasputine system



=head1 VERSION

Version 0.1



=head1 SYNOPSIS

    use App::Rasputine::XMPP;

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

    perldoc App::Rasputine::XMPP


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

