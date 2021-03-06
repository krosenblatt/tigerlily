# -*- Perl -*-

use strict;

my $repeat_quelch = 60 * 5;
my %mention;

sub blurbupdate {
    my($event, $handler) = @_;
    $event->{server}->state(HANDLE    => $event->{SHANDLE},
                            BLURBTIME => $event->{TIME});
    $mention{$event->{SHANDLE}} = 0;
    return;
}

sub blurbcheck {
    my($event, $handler) = @_;
    my $text   = $event->{VALUE};
    my $server = $event->{server};
    my $ui     = TLily::UI::name($event->{ui_name});

    my @match;
    if ($text =~ /^\'s\s*(?:blurb|\[\])/i) {
        for my $rhandle (@{$event->{RHANDLE}}) {
            my %attrs = $server->state(HANDLE => $rhandle);
            if ($attrs{ATTRIB} && $attrs{ATTRIB} =~ /emote/) {
                push @match, $event->{SOURCE};
                last;
            }
        }
    } elsif ($text =~ /(.*)\'s\s*(?:blurb|\[\])/i) {
        my @name = split /\s+/, $1;
        return unless @name;

        my @who;
        shift @name while (@name > 3);
        while (@name) {
            push @who, "@name";
            shift @name;
        }

        for (@who) {
            local $config{user_prefix} = 0;   # avoid '~' in resulting username.
            @match = grep(!/^-/, $server->expand_name($_));
            last if @match;
        }
    } elsif ($text =~ /(my|his|her|its)\s*(?:blurb|\[\])/i) {
        @match = ($event->{SOURCE});
    }
    return unless @match;

    @match =
      sort { ($b->{BLURBTIME} || 0) <=> ($a->{BLURBTIME} || 0) }
      map  { { $server->state(NAME=>$_) } }
      @match;

    return if (time - $mention{$match[0]->{HANDLE}} < $repeat_quelch);
    $mention{$match[0]->{HANDLE}} = time;

    if ($match[0]->{BLURB} eq "") {
        $ui->print("($match[0]->{NAME} has no blurb)\n");
    } else {
        $ui->print("($match[0]->{NAME}'s blurb is [$match[0]->{BLURB}])\n");
    }
    return;
}

sub load {
    event_r(type  => 'private',
        order => 'after',
        call  => \&blurbcheck);
    event_r(type  => 'public',
        order => 'after',
        call  => \&blurbcheck);
    event_r(type  => 'emote',
        order => 'after',
        call  => \&blurbcheck);
    event_r(type  => 'blurb',
        order => 'after',
        call  => \&blurbupdate);

    return;
}
