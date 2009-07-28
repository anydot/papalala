use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use GDBM_File;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "old url",
	description => "if url is watched, it is saved. If that url was previosly seen on that channel, it is print who and when send it before",
);

our %db;
tie %db, "GDBM_File", Irssi::get_irssi_dir(). "/url.db", &GDBM_WRCREAT, 0644;

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;

	return if grep {lc eq lc $nick} split(/ /, Irssi::settings_get_str('bot_oldurl_ignore'));
	return unless grep {$channel eq $_} split(/ /, Irssi::settings_get_str('bot_oldurl_channels'));
	return unless $message =~ /((?:http|ftp):\/\/\S+)/i;

	my $url = $1;
	my $key = "$channel:$url";

	$url =~ s/#.*$//; ## strip anchor

	if (defined $db{$key}) {
		my ($when, $who, $counter) = split(/:/, $db{$key});
		my $text_time = format_time(time() - $when);
		$counter++;
		$db{$key} = "$when:$who:$counter"; # update

		$counter++;

		$server->send_message($channel, "oold, sent by $who $text_time before ($url), # linked: $counter", 0);
	}
	else {
		my $now = time();
		$db{$key} = "$now:$nick:0";
	}
}

sub format_time {
	use integer;

	my $t = shift;
	my $r = "ouch, can't format that time";

	if ($t >= 0) {
		$r = sprintf "%i seconds", $t % 60;
		$t /= 60;
	}
	if ($t > 0) {
		$r = sprintf "%i minutes, %s", $t % 60, $r;
		$t /= 60;
	}
	if ($t > 0) {
		$r = sprintf "%i hours, %s", $t % 24, $r;
		$t /= 24;
	}
	if ($t > 0) {
		$r = sprintf "%i days, %s", $t, $r;
	}

	return $r;
}


Irssi::signal_add('message public', 'on_public');

Irssi::settings_add_str('bot', 'bot_oldurl_ignore', '');
Irssi::settings_add_str('bot', 'bot_oldurl_channels', '');

