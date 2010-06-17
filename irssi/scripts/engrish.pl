use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use REST::Google::Translate;

REST::Google::Translate->http_referer('http://www.redrum.cz');

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "engrish",
	description => "translate text from english to german and then back, forming 'engrish' text",
);

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $cp = Irssi::settings_get_str('bot_cmd_prefix');

	return unless $message =~ /^${cp}engrish\s+(.+)\s*$/;
	my $text = $1;

	my $de = REST::Google::Translate->new(
		q => $text,
		langpair => 'en|de',
	);

	return $server->send_message($channel, "$nick: error (en->de)", 0)
		if $de->responseStatus != 200;

	my $reen = REST::Google::Translate->new(
		q => $de->responseData->translatedText,
		langpair => 'de|en',
	);

	return $server->send_message($channel, "$nick: error (de->en)", 0)
		if $reen->responseStatus != 200;

	return $server->send_message($channel, "$nick: ".$reen->responseData->translatedText, 0);
}

Irssi::signal_add('message public', 'on_public');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
