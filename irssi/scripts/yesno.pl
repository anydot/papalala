use strict;
use warnings;

use Irssi;
use Irssi::Irc;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "yes/no",
	description => "get yes/no on answer with determined result",
);

our ($lastt) = 0;

sub on_msg {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $cp = Irssi::settings_get_str('bot_cmd_prefix');
	my $isprivate = !defined $channel;
	my $dst = $isprivate ? $nick : $channel;

	return
		unless $message =~ /^${cp}(yes|no)\s*/i;

	my $answer = ucfirst(lc($1));

	$server->send_message($dst, "$nick: $answer", 0);
}

Irssi::signal_add('message public', 'on_msg');
Irssi::signal_add('message private', 'on_msg');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
