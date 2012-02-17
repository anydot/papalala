use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use Digest::SHA1 qw/sha1/;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "decide",
	description => "get yes/no on answer",
);

our ($lastt) = 0;

sub on_msg {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $cp = Irssi::settings_get_str('bot_cmd_prefix');
	my $isprivate = !defined $channel;
	my $dst = $isprivate ? $nick : $channel;
	my $answer;
	my @parts;

	return unless $message =~ s/^${cp}decide\s*//;
	my $time = time();
	if ($time - $lastt > 300) {
		$lastt = $time;
	}

	@parts = split(/\s*--+\s*/, $message);

	$message = lc($message);
	$message =~ s/\W+//g;

	my $hash = sha1($message . $lastt);
	my ($number) = unpack("S", $hash);

	if (@parts > 1) {
		my $pivot = $number / 65536;
		$answer = @parts[int($pivot * @parts)];
	}
	else {
		if ($number & 1) {
			$answer = "Yes";
		}
		else {
			$answer = "No";
		}
	}

	$server->send_message($dst, "$nick: $answer", 0);
}

Irssi::signal_add('message public', 'on_msg');
Irssi::signal_add('message private', 'on_msg');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
