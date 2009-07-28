use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use Net::Twitter;

use vars qw($VERSION %IRSSI $twitter $username);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "twitter",
	description => "allows for posting small messages directly from IRC",
);

sub on_setup_changed {
	my $password;

	$username = Irssi::settings_get_str('bot_twitter_username');
	$password = Irssi::settings_get_str('bot_twitter_password');

	$twitter = Net::Twitter->new(
		username => $username,
		password => $password,
	);
}

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my ($twmsg);

	return unless ($twmsg) = $message =~ /^`tw(?:itter)?(?:\s+(.+))?$/;

	if (defined $twmsg) {
		$twmsg =~ /^((?:[@#]\w+\s+)*)(.*)$/;
		# $1 -- @/#prefixes $2 -- main messages 
		my $text = "$1$nick: $2";

		if (length $text > 140) {
			$server->send_message($channel, "$nick: Mas to dlouhe nacelniku (".length($text)."/140)", 0);
			return;
		}

		my $res = $twitter->update($text);

		if (defined $res) {
			$server->send_message($channel, "$nick: Zprava odeslana", 0);
		}
		else {
			my ($http_code, $http_msg) = ($twitter->http_code, $twitter->http_message);
			$server->send_message($channel, "$nick: Pri odesilani zpravy nastala chyba: $http_code -- $http_msg", 0);
		}
	}
	else {
		$server->send_message($channel, "$nick: http://twitter.com/$username", 0);
	}
}

Irssi::signal_add('message public', \&on_public);
Irssi::signal_add('setup changed', \&on_setup_changed);

Irssi::settings_add_str('bot', 'bot_twitter_username', '');
Irssi::settings_add_str('bot', 'bot_twitter_password', '');

on_setup_changed; # initialize
