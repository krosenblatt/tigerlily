#    TigerLily:  A client for the lily CMC, written in Perl.
#    Copyright (C) 1999  The TigerLily Team, <tigerlily@einstein.org>
#                                http://www.hitchhiker.org/tigerlily/
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2, as published
#  by the Free Software Foundation; see the included file COPYING.
#

# $Header: /home/mjr/tmp/tlilycvs/lily/tigerlily2/TLily/Attic/User.pm,v 1.19 1999/04/12 22:57:16 neild Exp $

package TLily::User;

use strict;
use vars qw(@ISA @EXPORT_OK);

use Carp;
use Text::Abbrev;
use Exporter;

use TLily::Config qw(%config);

@ISA = qw(Exporter);
@EXPORT_OK = qw(&help_r &shelp_r &command_r);

=head1 NAME

TLily::User - User command manager.

=head1 SYNOPSIS

     
use TLily::User;

TLily::User::init();

TLily::User::command_r(foo => \&foo);
TLily::User::shelp_r(foo => "A Foo Command");
TLily::User::help_r(foo => "Foo does stuff .. long description");
(...)

=head1 DESCRIPTION

This module manages user commands (%commands), and help for these commands.

=head1 FUNCTIONS

=over 10

=cut


# All commands.  Names are commands, values are command functions.
my %commands;

# Abbreviation mapping, generated by Text::Abbrev.
my %abbrevs;

# Help pages.
my %help;

# Short help text for commands.
my %shelp;

# Short help text for TLily::* modules:
my %shelp_modules;

=item init

Initializes the user command and help subsystems.  This command should be 
called once, from tlily.PL, during client initialization.

  TLily::User::init();

=cut

sub init {
    TLily::Registrar::class_r("command"    => \&command_u);
    TLily::Registrar::class_r("short_help" => \&command_u);
    TLily::Registrar::class_r("help"       => \&command_u);

    TLily::Event::event_r(type  => "user_input",
			  order => "during",
			  call  => \&input_handler);

    command_r(help => \&help_command);
    shelp_r(help => "Display help pages.");
    help_r(commands  => sub { help_index("commands",  @_); } );
    help_r(variables => sub { help_index("variables", @_); } );
    help_r(concepts  => sub { help_index("concepts", @_); } );
    help_r(internals => sub { help_index("internals", @_); } );
    help_r(help => '
Welcome to Tigerlily!

Tigerlily is a client for the lily CMC, written entirely in 100% pure Perl.

For general information on how to use tlily, try "%help concepts".
For a list of commands, try "%help commands".
For a list of configuration variables, try "%help variables".
If you\'re interested in tlily\'s guts, try "%help internals".
');
    
    my $f;
    foreach $f (glob("$::TL_LIBDIR/TLily/*.pm")) {
	my ($module) = ($f =~ /\/([^\/]*)$/);
	local(*F);
	open(F,"<$f");
	my $namehead=0;
	while(<F>) {
	    if (/=head1 NAME/) { $namehead = 1; next }
	    if (/=head1/) { $namehead = 0; last; }
	    next unless $namehead;
	    next if (/^\s*$/);
	    my ($desc) = /-\s*(.*)\s*$/; 
	    shelp_r($module => $desc, "internals");
	    help_r($module => "POD:$f");
	    last;
	}
    }
}


=item command_r($name, $sub)

Registers a new %command.  %commands are tracked via TLily::Registrar.

  TLily::User::command_r("foo" => sub {
       my ($ui,$args) = @_;
       $ui->print("You typed %foo $args\n");
    });

The function reference in the second parameter will be invoked when the 
%command is typed, and passed two arguments: a UI object and a scalar
containing any arguments to the %command. 

=cut

sub command_r {
    my($command, $sub) = @_;
    TLily::Registrar::add("command" => $command);
    $commands{$command} = $sub;
    %abbrevs = abbrev keys %commands;
}


=item command_u($name)

Deregisters an existing %command.

  TLily::User::command_u("quit");

=cut

sub command_u {
    my($command) = @_;
    TLily::Registrar::remove("command" => $command);
    delete $commands{$command};
    %abbrevs = abbrev keys %commands;
}


=item shelp_r

Sets the short help for a command.  This is what is displayed by the
command name in the "/help commands" listing.  Short help is tracked
via TLily::Registrar.

    TLily::User::shelp_r("help" => "Display help pages.");
    TLily::User::shelp_r("help" => "Display help pages.", "internals");

=cut

sub shelp_r {
    my($command, $help, $index) = @_;
    TLily::Registrar::add("short_help" => $command);
    if (! $index) {
	$index = "commands";
	$command = "%" . $command;
    }
    $shelp{$index}{$command} = $help;
}


=item shelp_u

Clears the short help for a command.

    TLily::User::shelp_u("help");

=cut

sub shelp_u {
    my($command) = @_;
    TLily::Registrar::remove("short_help" => $command);
    foreach (keys %shelp) {
	delete $shelp{$_}{$command};
    }
}


=item help_r

Sets a help page.  Help is tracked via TLily::Registrar.

    TLily::User::help_r("lily" => $help_on_lily);

=cut

sub help_r {
    my($topic, $help) = @_;
    TLily::Registrar::add("help" => $topic);
    if (!ref($help)) {
	# Eliminate all leading newlines, and enforce only one trailing
	$help =~ s/^\n*//s; $help =~ s/\n*$/\n/s;
    }
    $help{$topic} = $help;
}


=item help_u

Clears a help page.

    TLily::User::shelp_r("lily" => $help_on_lily);

=cut

sub help_u {
    my($topic) = @_;
    TLily::Registrar::remove("help" => $topic);
    delete $help{$topic};
}



=head1 HANDLERS

=over 10

=item input_handler

Input handler to parse %commands.
This is registered automatically by init().    

=cut

sub input_handler {
    my($e, $h) = @_;

    return unless ($e->{text} =~ /^\s*([%\/])(\w+)\s*(.*?)\s*$/);
    my $command = $abbrevs{$2};

    return if ($1 ne "%" && !grep($_ eq $command, @{$config{slash}}));

    unless ($command) {
	$e->{ui}->print("(The \"$2\" command is unknown.)\n");
	return 1;
    }

    #$commands{$command}->($e->{ui}, $3, $command);
    $commands{$command}->($e->{ui}, $3);
    return 1;
}


=item help_index

Help handler to display the contents of a help index.
This is registered automatically by init().    

=cut

sub help_index {
    my($index, $ui, $arg) = @_;

    $ui->indent("? ");
    $ui->print("Tigerlily client $index:\n");

    my $c;
    foreach $c (sort keys %{$shelp{$index}}) {
	$ui->printf("  %-15s", $c);
	$ui->print($shelp{$index}{$c}) if ($shelp{$index}{$c});
	$ui->print("\n");
    }

    $ui->indent("");
}

=item help_command

Command handler to provide the %help command.
This is registered automatically by init().    

=cut

sub help_command {
    my($ui, $arg) = @_;
    $arg = "help" if ($arg eq "");
    $arg =~ s/^%//;

    unless ($help{$arg}) {
	$ui->print("(there is no help on \"$arg\")\n");
    }

    elsif (ref($help{$arg}) eq "CODE") {
	$help{$arg}->($ui, $arg);
    } 
    
    elsif ($help{$arg} =~ /^POD:(\S+)/) {
	$ui->indent("? ");
	$ui->print(`pod2text $1`);
	$ui->indent("");	
    }

    else {
	$ui->indent("? ");
	$ui->print($help{$arg});
	$ui->indent("");
    }
}


=back

=cut

1;
