use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use Net::Twitter;

use vars qw($VERSION %IRSSI $twitter $cp);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "twitter",
	description => "allows for posting small messages directly from IRC",
);

sub initialize {
	my ($c_key, $c_secret, $a_token, $a_secret) = (
		Irssi::settings_get_str('bot_twitter_consumer_key'),
		Irssi::settings_get_str('bot_twitter_consumer_secret'),
		Irssi::settings_get_str('bot_twitter_access_token'),
		Irssi::settings_get_str('bot_twitter_access_token_secret')
	);

	if ($c_key && $c_secret) {
		$twitter = Net::Twitter->new(
			traits => ['API::REST', 'OAuth'],
			consumer_key => $c_key,
			consumer_secret => $c_secret,
		);

		if ($a_token && $a_secret) {
			$twitter->access_token($a_token);
			$twitter->access_token_secret($a_secret);
		}
	}
}

sub on_setup_changed {
	$cp = Irssi::settings_get_str('bot_cmd_prefix');

	initialize;
}

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my ($twmsg);

	return unless ($twmsg) = $message =~ /^${cp}tw(?:itter)?(?:\s+(.+))?$/;

	if (!defined $twitter) {
		$server->send_message($channel, "$nick: Neinicializovany twitter, smula", 0);
	}
	elsif (defined $twmsg) {
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
		my $obj = $twitter->verify_credentials;

		my $username = $obj->{screen_name};

		$server->send_message($channel, "$nick: http://twitter.com/$username", 0);
	}
}

sub cmd_bot_twitter {
	my $data = shift;

	if (!defined $twitter) {
		Irssi::print("First set consumer key/secret (you must register tw application on your own)");
	}
	elsif (!$data) {
		Irssi::print("geturl | setpin");
	}
	elsif ($data eq "geturl") {
		my $url = $twitter->get_authorization_url;

		Irssi::print("Authorization url: $url -- use /bot_twitter setpin <PIN> to set the pin");
	}
	elsif ($data =~ /^setpin (\S)$/) {
		my ($a_token, $a_secret) = $twitter->request_access_token(verifier => $1);

		Irssi::settings_set_str('bot_twitter_access_token', $a_token);
		Irssi::settings_set_str('bot_twitter_access_token_secret', $a_secret);
	}
	else {
		Irssi::print("Unknown cmd");
	}
}

Irssi::command_bind('bot_twitter', \&cmd_bot_twitter);

Irssi::signal_add('message public', \&on_public);
Irssi::signal_add('setup changed', \&on_setup_changed);

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
Irssi::settings_add_str('bot', 'bot_twitter_consumer_key', '');
Irssi::settings_add_str('bot', 'bot_twitter_consumer_secret', '');
Irssi::settings_add_str('bot', 'bot_twitter_access_token', '');
Irssi::settings_add_str('bot', 'bot_twitter_access_token_secret', '');

on_setup_changed; # get cmd prefix

if (!$twitter) {
	Irssi::print("Credentials not set? Call /bot_twitter");
}
