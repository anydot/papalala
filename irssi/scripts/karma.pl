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
	name => "karma",
	description => "karma for ops only",
);

our %db;
tie %db, "GDBM_File", Irssi::get_irssi_dir(). "/karma.db", &GDBM_WRCREAT, 0644;

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	$channel = lc($channel);

	return unless grep {$channel eq $_} split(/ /, Irssi::settings_get_str('bot_karma_channels'));
	return unless $message =~ /^`karma(\+|-|)(?:\s+(.*?))?\s*$/i;

	my $keyword = lc($2);
	my $action = $1;
	my $key = "$channel:$keyword";
	my $result;

	if ($action eq '' and $keyword ne '') {
		if (defined($db{$key})) {
			$result = "Karma for `$keyword' is " . $db{$key};
		}
		else {
			$result = "No karma for `$keyword' so far";
		}
	}
	elsif ($action eq '') {
		$result = "TODO -- some stats";
	}
	else {
		my $nickrec = $server->channel_find($channel)->nick_find($nick);

		if ($nickrec->{op}) {
			if ($action eq '+') {
				$db{$key}++;
				return on_public($server, "`karma $keyword", $nick, $hostmask, $channel);
			}
			elsif ($action eq '-') {
				$db{$key}--;
				return on_public($server, "`karma $keyword", $nick, $hostmask, $channel);
			}
			else {
				$result = "Ouch error";
			}
		}
		else {
			$result = "You must be op to do this";
		}
	}
		
	$server->send_message($channel, "$nick: $result", 0);
}

Irssi::signal_add('message public', 'on_public');

Irssi::settings_add_str('bot', 'bot_karma_channels', '');
