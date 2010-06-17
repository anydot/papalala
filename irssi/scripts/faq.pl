use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use DBI;

use vars qw($VERSION %IRSSI);
my ($host, $db, $username, $password) = qw/localhost anydot anydot todyn/;

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "faq",
	description => "add faq",
);

our $dbh = DBI->connect("DBI:mysql:$db:$host", $username, $password, { RaiseError => 1})
    or die("Can't connect to db");
$dbh->{mysql_auto_reconnect} = 1;

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $cp = Irssi::settings_get_str('bot_cmd_prefix');
	my $isprivate = !defined $channel;
	my $receiver = ($isprivate ? $nick : $channel);

	if ($message =~ s/^${cp}faq\s+add\s+//i) {
		my $stm = $dbh->prepare("INSERT INTO faq (question) VALUES (?)");
		$stm->execute($message);

		my $id = $dbh->{'mysql_insertid'};
		
		$server->send_message($receiver, "$nick: Novy faq #$id byl uspesne zalozen", $isprivate);
	}
	elsif ($message =~ s/^${cp}faq\s+answer\s+(\d+)\s+//i) {
		my $id = $1;
		my $stm = $dbh->prepare("SELECT 1 FROM faq WHERE id = ?");
		$stm->execute($id);
		my ($isasked) = $stm->fetchrow_array;

		if (!$isasked) {
			$server->send_message($receiver, "$nick: Faq #$id nebyl nalezen", $isprivate);
			return;
		}

		$dbh->do("INSERT INTO faq_answer (faqid, answer) VALUES (?, ?)", {}, $id, $message);
		$server->send_message($receiver, "$nick: Odpoved na faq #$1 byla uspesne vlozena", $isprivate);
	}
	elsif ($message =~ /^${cp}faq\s+(\d+)(?:\s+>>\s+(\S+))?\s*$/) {
		my ($question) = $dbh->selectrow_array("SELECT question FROM faq WHERE id = ?", {}, $1);
		my $redirect = (defined $2 && !$isprivate ? "$2: " : "");

		if (!defined $question) {
			$server->send_message($receiver, "$nick: FAQ #$1 jeste nikdo nezadal", $isprivate);
		}
		else {
			$server->send_message($receiver, "${redirect}http://www.redrum.cz/faq/$1/ -- FAQ #$1: $question", $isprivate);
		}
	}
	elsif ($message =~ /^${cp}faq\s+tag\s+(\d+)\s+(\w+)\s*$/) {
		my ($tagname, $faqid) = (lc $2, $1);
		my ($exists) = $dbh->selectrow_array("SELECT 1 FROM faq WHERE id = ?", {}, $faqid);

		if (!$exists) {
			$server->send_message($receiver, "$nick: FAQ #$faqid jeste nikdo nezadal", $isprivate);
		}
		else {
			$dbh->do("INSERT IGNORE INTO faq_tag (name) VALUES (?)", {}, $tagname);
			my ($tagid) = $dbh->selectrow_array("SELECT id FROM faq_tag WHERE name = ?", {}, $tagname);
			$dbh->do("INSERT IGNORE INTO faq_tagmap (tagid, faqid) VALUES (?, ?)", {}, $tagid, $faqid);
			
			$server->send_message($receiver, "$nick: FAQ #$faqid byl uspesne otagovan '$tagname'", $isprivate);
		}
	}
}

Irssi::signal_add('message public', 'on_public');
Irssi::signal_add('message private', 'on_public');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
