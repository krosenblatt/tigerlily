package LC::Server;

use strict;

use Carp;
use IO::Socket;
use Fcntl;

use LC::Event;


=head1 NAME

LC::Server - Lily server objet

=head1 DESCRIPTION

The Server module defines a class that represents a tcp connection of
some form.  It includes I/O functions -- protocol specific functions
go in subclasses (such as LC::Server::SLCP).

new() and connect() will call die() on failure, so be sure to catch
exceptions if this matters to you!

=head2 Functions
=over 10

=cut


my $active_server;
my %server;


=item new(%args)

Creates a new LC::Server object.  Takes 'event', 'host', 'port', and
'protocol' arguments.  The 'protocol' argument is used to determine the
events generated for server data -- the event type will be "protocol_data".

    $serv = LC::Server->new(event    => $event,
                            protocol => "slcp",
                            host     => "lily",
                            port     => 7777);

=cut

sub new {
	my($proto, %args) = @_;
	my $class = ref($proto) || $proto;
	my $self  = {};

	my $ui = LC::UI::name($args{ui_name}) if ($args{ui_name});

	croak "required parameter \"event\" missing"
	  unless (defined $args{event});
	croak "required parameter \"host\" missing"
	  unless (defined $args{host});
	croak "required parameter \"port\" missing"
	  unless (defined $args{port});

	$args{name} = "$args{host}:$args{port}" if (!defined($args{name}));
	$server{$args{name}} = $self;
	$active_server = $self unless ($active_server);

	$self->{name}    = $args{name};
	$self->{event}   = $args{event};
	$self->{host}    = $args{host};
	$self->{port}    = $args{port};
	$self->{ui_name} = $args{ui_name};
	$self->{proto}   = defined($args{protocol}) ? $args{protocol}:"server";

	$ui->print("Connecting to $self->{host}, port $self->{port}...");

	$self->{sock} = IO::Socket::INET->new(PeerAddr => $self->{host},
					      PeerPort => $self->{port},
					      Proto    => 'tcp');
	if (!defined $self->{sock}) {
		$ui->print("failed: $!\n");
		return;
	}

	$ui->print("connected.\n");

	fcntl($self->{sock}, F_SETFL, O_NONBLOCK) or die "fcntl: $!\n";

	$self->{event}->io_r(handle => $self->{sock},
			     mode   => 'r',
			     obj    => $self,
			     call   => \&reader);

	bless $self, $class;

	$self->{event}->send(type   => 'server_connected',
			     server => $self);

	return $self;
}


=item terminate()

Shuts down a server instance.

=cut

sub terminate {
	my($self) = @_;

	close($self->{sock}) if ($self->{sock});
	$self->{sock} = undef;
	delete $server{$self->{name}};
	return;
}


=item ui_name()

Returns the name of the UI object associated with the server.

=cut

sub ui_name {
	my($self) = @_;
	return $self->{ui_name};
}


=item name()

Returns the server with the given name, or the currently active server
if no argument is given.

=cut

sub name {
	shift if (@_ > 1);
	my($a) = @_;
	if (!defined $a) {
		return $active_server;
	} elsif (ref($a)) {
		return $a->{"name"};
	} else {
		return $server{$a};
	}
}


=item send()

Send a chunk of data to the server, synchronously.  This call will block until
the entire block of data has been written.

    $serv->send("a bunch of stuff to send to the server");

=cut

sub send {
	my $self = shift;
	my $s = join('', @_);

	my $written = 0;
	while ($written < length($s)) {
		my $bytes = syswrite($self->{sock}, $s, length($s), $written);
		if (!defined $bytes) {
			# The following is broken, and must be fixed.
			#next if ($errno == EAGAIN);
			die "syswrite: $!\n";
		}
		$written += $bytes;
	}

	return;
}


=item sendln()

Behaves exactly like send(), but sends a crlf pair at the end of the line.

=cut

sub sendln {
	my $self = shift;
	# \r\n is non-portable.  Fix, please.
	$self->send(@_, "\r\n");
}


sub reader {
	my($self, $mode, $handler) = @_;

	my $buf;
	my $rc = sysread($self->{sock}, $buf, 1024);

	# Error of some kind.
	if ($rc < 0) {
		# The following is broken, and must be fixed.
		#if ($errno != EAGAIN) {
		#	die "sysread: $!\n";
		#}
		# A signal interrupted us -- just fall out, we'll be back.
	}

	# End of line.
	elsif ($rc == 0) {
		$self->{sock}->close();
		undef $self->{sock};

		$self->{event}->send(type   => 'server_disconnected',
				     server => $self);
		$self->{event}->io_u($handler);
	}

	# Data as usual.
	else {
		$self->{event}->send(type   => "$self->{proto}_data",
				     server => $self,
				     data   => $buf);
	}

	return;
}

DESTROY { warn "Server object going down!\n"; }


1;