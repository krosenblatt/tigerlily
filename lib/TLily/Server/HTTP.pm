#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999-2005  The TigerLily Team, <tigerlily@tlily.org>
#                                http://www.tlily.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /data/cvs/lily/tigerlily2/TLily/Server/HTTP.pm,v 1.5 2001/01/26 03:01:51 neild Exp $

package TLily::Server::HTTP;

use strict;
use vars qw(@ISA);

use TLily::Server;
use Carp;

@ISA = qw(TLily::Server);

sub new {
    my ($proto, %args) = @_;
    my $class = ref($proto) || $proto;
	
    $args{port}   ||= 80;
    $args{protocol} = "http" unless defined $args{protocol};
	
    croak "required parameter \"url\" missing"
      unless (defined $args{url});

    # WJC: "fixed" re so that urls with path info are preserved.
    if ($args{url} =~ m|^http://([^/:]+)(?::(\d+))?(/[/\S]+)$|) {  # A full url
	$args{port} = $2 if defined $2;
	$args{url} = $3;
	$args{host} = $1;
    }
    unless (defined $args{filename}) {
	my @t = split m|/|, $args{url};
	$args{filename} = pop @t;
    }

    my $self = $class->SUPER::new(%args);
    
    $self->{handler} = TLily::Event::event_r (type => 'server_connected',
			  call => \&send_url);
    
    $self->{filename} = $args{filename};
    $self->{url} = $args{url};
    $self->{callback} = $args{callback} if (defined($args{callback}));

    bless $self, $class;
}

sub send_url {
    my ($event, $handler) = @_;

    #Since we got this far, we don't need the server_connected callback anymore.
    TLily::Event::event_u($event->{server}->{handler});
    
    return unless exists ($event->{server}->{url});
   
    my $request = "GET " . $event->{server}->{url} . " HTTP/1.0\r\n";
    $request .= "host: " . $event->{server}->{host} . "\r\n";
    $request .= "\r\n";
    $event->{server}->send($request);
    
    return;
}

# don't track the HTTP servers (our parent class does, and that would
# just keep them around) A better solution might be to have the notion of
# transient servers.

sub add_server {};

sub DESTROY {
 # XXX - This never seems to print.
 #print "DESTROYING HTTP SERVER\n";
};

1;
