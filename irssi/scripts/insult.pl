use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use Acme::Scurvy::Whoreson::BilgeRat;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "insult",
	description => "insult you",
);

our ($lastt) = 0;

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $answer;

	return unless $message =~ /^`insult/;

	$answer = "".Acme::Scurvy::Whoreson::BilgeRat->new;

	$server->send_message($channel, "$nick: $answer", 0);
}

Irssi::signal_add('message public', 'on_public');
