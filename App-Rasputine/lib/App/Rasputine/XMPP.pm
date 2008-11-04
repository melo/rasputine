package App::Rasputine::XMPP;

use strict;
use warnings;
use base qw( Mojo::Base );
use Net::XMPP2::Component;
use Net::XMPP2::Util qw( split_jid bare_jid );
use Params::Validate qw( :all );
use Encode qw( encode decode );
use MIME::Base64;
use Digest::SHA1 qw( sha1_hex );

our $VERSION = '0.1';

__PACKAGE__->attr('ras', chained => 1);
__PACKAGE__->attr('conn', chained => 1);
__PACKAGE__->attr('resources', default => {});
__PACKAGE__->attr('namespace_map', default => {});

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
  my ($self, $to, $from, $type) = @_;
  my $ras = $self->{ras};
  my %attrs;
  
  # check to see if we got a node
  if (ref($to)) {
    $type = $from;
    $from = $to->attr('from');
    $to   = $to->attr('to');
  }
  
  # We are online by default
  my ($service, $via) = split_jid($to);
  my $user = bare_jid($from);
  
  # XEP-0153 support
  my $avatar;

  if (!$type || $type eq 'unavailable') {
    my $srv_cfg = $ras->service($service);
    
    my $sess = $ras->session_for({
      service => $service,
      user => $user,
      via => $via,
    });
    my $state = 'offline';
    $state = $sess->state if $sess;
    
    my $status = $srv_cfg->{presence}{$state}{status};
    $attrs{status} = $status if $status;
    
    $to .= '/rasputine';
    
    # XEP-0153 support
    if (($avatar) = $self->avatar_for($service)) {
      $avatar = {
        defns => 'vcard-temp:x:update',
        node => {
          name => 'x',
          childs => [
            { name => 'photo', childs => [ $avatar ] }
          ],
        },
      } 
    }
  }
  
  $attrs{to} = $from;
  $attrs{from} = $to;
  
  $self->{conn}->send_presence($type, $avatar, %attrs);
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
  
  # update our own presence
  $self->send_presence($node);
  
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
  
  my $from = $node->attr('from');
  my $to   = $node->attr('to');
  my $type = $node->attr('type');

  # message type must be empty or 'chat'  
  return if $type && $type ne 'chat';
  
  my $body = encode('utf8', _extract_body($node));
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
  
  # IM doesn't need the trailing \n and some talkers use \r\n
  my $mesg = $args{mesg};
  $mesg =~ s/\r?\n\z//sm;
  return unless $mesg;
  
  # Try to encode as utf8 and then latin1
  # if all fails try direct
  my $body;
  foreach my $charset (qw( utf8 latin1 )) {
    eval { $body = decode('utf8', $mesg, 1) };
    last unless $@;
  }
  $body = $mesg unless $body;
  
  $self->{conn}->send_message($args{user}, undef, undef,
    body => $body,
    from => "$args{service}\@$args{via}/rasputine",
  );
}


#############
# IQ handling

sub iq_in {
  my ($self, $conn, $node) = @_;
  
  my $nodes = $node->nodes;
  my $q = ($node->nodes)[0];
  return unless $q;

  my $ns = $q->namespace;
  return unless $ns;
  
  my $ns_map = $self->namespace_map;
  return unless exists $ns_map->{$ns};
  
  return $ns_map->{$ns}->($node);
}

sub iq_handler {
  my ($self, $ns, $cb) = @_;
  
  $self->namespace_map->{$ns} = $cb;
  
  return;
}


##########
# IQ Disco

sub disco_info_request {
  my ($self, $node) = @_;
  my $conn = $self->conn;
  my $q = ($node->nodes)[0];
  
  my $type = $node->attr('type');
  if (!$type) {
    $conn->reply_iq_error($node, 'cancel', 'bad-request')
  }
  elsif ($type eq 'set') {
    $conn->reply_iq_error($node, 'cancel', 'service-unavailable')
  }
  elsif ($type eq 'get') {
    my $to = $node->attr('to');
    my ($bot, $domain, $resource) = split_jid($to);
    my ($ids, $feats) = $self->disco_information_for($to);
    
    if ($q->attr('node') || !$ids) {
      $conn->reply_iq_error($node, 'cancel', 'item-not-found');
    }
    else {
      map { $_ = { name => 'identity', attrs => [ %$_       ] } } @$ids;
      map { $_ = { name => 'feature',  attrs => [ var => $_ ] } } @$feats;
      
      # features only for domain or a connected resource
      # bare JID receives only IDs
      my @childs = @$ids;
      push @childs, @$feats if ($bot && $resource) || !$bot;
      
      $conn->reply_iq_result($node, {
        def_ns => 'http://jabber.org/protocol/disco#info',
        node   => {
          name => 'query',
          childs => [ @$ids, @$feats ],
        },
      });
    }
  }
  
  # Don't reply to anything else
  return 'done';
}

sub disco_information_for {
  my ($self, $jid) = @_;
  my ($bot, $domain, $resource) = split_jid($jid);
  my (@ids, @feats);

  # All of them support thi
  push @feats, 'http://jabber.org/protocol/disco#info';
  
  if (!$bot) {
    push @ids, {
      category => 'gateway',
      type     => 'telnet',
      name     => 'Rasputine Moo/MUD/Talker gateway',
    };
    push @feats, 'http://jabber.org/protocol/disco#items';
  }
  elsif (my $srv = $self->{ras}->service($bot)){
    push @ids, {
      category => 'account',
      type     => 'registered',
      name     => $srv->{name},
    };
    push @feats, 'vcard-temp';
  }
  else {
    return;
  }
  
  return (\@ids, \@feats);
}

sub disco_items_request {
  my ($self, $node) = @_;
  my $conn = $self->conn;
  my $q = ($node->nodes)[0];
  my $to = $node->attr('to');
  my ($is_bot, $domain) = split_jid($to);
  
  my $type = $node->attr('type');
  if (!$type) {
    $conn->reply_iq_error($node, 'cancel', 'bad-request')
  }
  elsif ($type eq 'set') {
    $conn->reply_iq_error($node, 'cancel', 'service-unavailable')
  }
  elsif ($type eq 'get') {
    my @items;
    if (!$q->attr('node') && !$is_bot) {
      my $srvs = $self->{ras}->services;
      
      while (my ($bot, $info) = each %$srvs) {
        push @items, {
          name => 'item',
          attrs => [
            jid  => "$bot\@$domain",
            name => $info->{name} || '$bot',
          ],
        };
      }
    }
    
    $conn->reply_iq_result($node, {
      def_ns => 'http://jabber.org/protocol/disco#items',
      node   => {
        name => 'query',
        childs => \@items,
      },
    });
  }
  
  # Don't reply to anything else
  return 'done';
}


####################
# vCard-based Avatar

sub vcard_request {
  my ($self, $node) = @_;
  my $conn = $self->{conn};
  my $type = $node->attr('type');
  $type = '' unless $type;
  
  if ($type eq 'set') {
    $conn->reply_iq_error($node, 'cancel', 'service-unavailable')
  }
  elsif ($type eq 'get') {
    my ($bot, $domain, $resource) = split_jid($node->attr('to'));
    my $srv = $self->{ras}->service($bot);
    
    if ($bot && !$srv) {
      $conn->reply_iq_error($node, 'cancel', 'not-found')
    }
    elsif ($resource || !$bot) {
      $conn->reply_iq_error($node, 'cancel', 'service-unavailable')
    }
    else {
      $conn->reply_iq_result($node, $self->vcard_for($bot));
    }
  }
  
  return 'done';
}

sub vcard_for {
  my ($self, $bot) = @_;
  my $srv = $self->{ras}->service($bot);
  
  return unless $srv;
  
  my @vcard;
  push @vcard, { name => 'FN',  childs => [ $srv->{name} || $bot ] };
  push @vcard, { name => 'URL', childs => [ $srv->{homepage} ] }
    if exists $srv->{homepage};
  
  my ($hash, $photo) = $self->avatar_for($bot);
  if ($photo) {
    push @vcard, { name => 'PHOTO', childs => [
      { name => 'TYPE',   childs => [ 'image/png' ] },
      { name => 'BINVAL', childs => [ $photo      ] },
    ]};
  }
  
  return {
    def_ns => 'vcard-temp',
    node => {
      name => 'vCard',
      childs => \@vcard,
    }
  };
}


################
# Avatar support

my $def_hash = 'e2be2e92750a8abe41be3010fd41959f21e5bfd9';
my $def_avatar = <<AVATAR;
/9j/4AAQSkZJRgABAQAAAQABAAD//gA7Q1JFQVRPUjogZ2QtanBlZyB2MS4wICh1c2luZyBJSkcg
SlBFRyB2NjIpLCBxdWFsaXR5ID0gNjAK/9sAQwANCQoLCggNCwoLDg4NDxMgFRMSEhMnHB4XIC4p
MTAuKS0sMzpKPjM2RjcsLUBXQUZMTlJTUjI+WmFaUGBKUVJP/9sAQwEODg4TERMmFRUmTzUtNU9P
T09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09P/8AAEQgAgACA
AwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMF
BQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkq
NDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqi
o6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/E
AB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMR
BAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVG
R0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKz
tLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/aAAwDAQACEQMRAD8A
9G27RSYB7UpYkYNJQAACjCk4FFFADioA60zihmxUbP6mgCTnvikbGCK5jWNU1JtRgsbArCsrbTKy
7iPp2q1A95Zptup5JpTwWJGD7jAoA3lUClrCOuJbS7bkfKMZYdvrWzDPHOgeJ1ZGGVIPBoAkIz1p
No9KdRQA3aBSEEDpmnGk57UAMxTWOAaWmt0NAE9FFID7UAL0pCT2FFKKAK17cxWNtJdXDBY4xkn1
9BXLaT4iN/eyeaNoP3R2qt8S79o47SwQkbyZXHsOB/WuV8PW+p3l4semoxYfec8Kv1NAHYzwyS6i
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
AVATAR

sub avatar_for {
  my ($self, $bot) = @_;
  my $srv = $self->{ras}->service($bot);
  
  return unless $srv;
  
  my ($hash, $photo);
  if (my $p = $srv->{photo}) {
    if (open(my $fh, '<', $p->{filename})) {
      local $/;
      $photo = <$fh>;
      close($fh);
      
      if ($photo) {
        $hash  = sha1_hex($photo);
        $photo = encode_base64($photo);
      }
    }
    else {
      print STDERR "ATTN! Could not open '$p->{filename}': $!\n";
    }
  }
  
  if (!$hash) {
    $hash  = $def_hash;
    $photo = $def_avatar;
  }
  
  return ($hash, $photo);
}


################################
# React to service state changes

sub service_state {
  my $self = shift;
  my %args = validate(@_, {
    service => { type => SCALAR }, 
    user    => { type => SCALAR }, 
    via     => { type => SCALAR }, 
    state   => { type => SCALAR }, 
  });
  
  $self->send_presence("$args{service}\@$args{via}", $args{user});
  
  return;
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
  my $conn = $self->{conn};
  my $ras  = $self->{ras};
  my $config = $ras->xmpp;
  
  print STDERR "Connection to XMPP server is live!\n";
  
  $conn->reg_cb(
    recv_stanza_xml => sub { return $self->_on_stanza(@_) },
    message_xml     => sub { return $self->message_in(@_) },
    presence_xml    => sub { return $self->presence_in(@_) },
    iq_xml          => sub { return $self->iq_in(@_) },
  );
  
  $conn->set_exception_cb(sub {
    print STDERR "EXCEPTION CAUGTH: $_[0]\n" if $config->{xml_debug};
  });
  
  # Support XEP-0030 discovery
  $self->iq_handler( 'http://jabber.org/protocol/disco#info', sub {
    return $self->disco_info_request(@_);
  });
  $self->iq_handler( 'http://jabber.org/protocol/disco#items', sub {
    return $self->disco_items_request(@_);
  });
  
  # Support for XEP-0054
  $self->iq_handler( 'vcard-temp', sub {
    return $self->vcard_request(@_);
  });

  return;
}

sub _on_disconnect {
  my $self = shift;
  
  print STDERR "XMPP component lost connection... Reconnecting...\n";

  # Destroy old connection
  $self->conn(undef);
  
  # Clear IQ handlers
  $self->namespace_map(undef);
  
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
  my $done;
  
  if ($node->eq(component => 'iq')) {
    $done = $conn->event(iq_xml => $node);
    $conn->handle_iq($node) unless $done;
  }
  elsif ($node->eq(component => 'message')) {
    $done = $conn->event(message_xml => $node);
  }
  elsif ($node->eq(component => 'presence')) {
    $done = $conn->event(presence_xml => $node);
  }
  
  return $done;
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
