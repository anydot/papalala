use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use DBI;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "link",
	description => "save url's on channel and allow to search them",
);

our $irssidir = Irssi::get_irssi_dir;
our $dbh = DBI->connect("dbi:SQLite:dbname=$irssidir/link.sqlite3", "", "") or
	die ("Can't open DB: $!");
our $insert = $dbh->prepare("INSERT INTO link(channel, url) VALUES(?, ?)");
our $select = $dbh->prepare("SELECT DISTINCT url FROM link WHERE channel = ? AND url LIKE ? ORDER BY ROWID DESC LIMIT 51");
our $selectall = $dbh->prepare("SELECT DISTINCT url FROM link WHERE url LIKE ? ORDER BY ROWID DESC LIMIT 51");

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $isprivate = !defined $channel;

	return unless $isprivate or grep {$channel eq $_} split(/ /, Irssi::settings_get_str('bot_link_channels'));

	if ($message =~ /^[`!]l(?:ink)?(?:\s+(.*))?$/) {
		my $query = $1;
		my $postfix;
		my $maxlen = 497; ## 510 - length of ":! PRIVMSG :"
		my $msg = "$nick:";
		my $st;

		if ($isprivate) {
			($channel, $query) = split /\s/, $query, 2;

			$query //= '';
		}

		if ($query =~ /^\*\s*(.*)/) {
			($st = $selectall)->execute("%$1%");
		}
		else {
			($st = $select)->execute(lc $channel, "%$query%");
		}

		my @res = map {$_->[0]} @{$st->fetchall_arrayref};

		if (@res == 51) {
			$postfix = " (50+ results)";
		}
		else {
			$postfix = sprintf " (%i results)", scalar @res;
		}

		$maxlen -= length($msg) + length($postfix) + length($channel) + length($server->{nick})
			+ length($server->{userhost});

		for (@res) {
			$maxlen -= length($_) + 1;

			last
				unless $maxlen >= 0;

			$msg .= " $_";
		}

		$msg .= $postfix;

		$server->send_message($isprivate ? $nick : $channel, $msg, 0);
	}
	elsif (!$isprivate) {
		while ($message =~ /((?:https?|ftp):\/\/\S+)/gi) {
			$insert->execute(lc $channel, $1);
		}
	}
}

Irssi::signal_add('message public', 'on_public');
Irssi::signal_add('message private', 'on_public');

Irssi::settings_add_str('bot', 'bot_link_channels', '');

