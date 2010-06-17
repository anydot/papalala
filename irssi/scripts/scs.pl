use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use LWP::UserAgent;
use Cz::Cstocs;
use URI::Escape;
use XML::XPath;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "scs",
	description => "check word against slovnik-cizich-slov.abz.cz",
);

our $tolatin2 = Cz::Cstocs->new(qw/utf8 il2/)
	or die ("Can't create utf8 -> latin2 filter");

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $cp = Irssi::settings_get_str('bot_cmd_prefix');
	my $answer;

	return unless $message =~ /^${cp}scs\s+(.+)\s*$/;
	
	$answer = "$nick: ($1) ";
	my $word = uri_escape($tolatin2->($1));

	######
	my $ua = LWP::UserAgent->new(
		agent => "Mozilla 4/0",
		max_redirect => 2,
		timeout => 15,
	);

	my $url = "http://slovnik-cizich-slov.abz.cz/web.php/hledat?typ_hledani=prefix&cizi_slovo=$word";

	my $response = $ua->get($url);
	if ($response->is_error) {
		$server->send_message($channel, "$nick: Error: ".$response->status_line, 0);
		return;
	}

	$server->send_message($channel, "jsem tu", 0);

	my $xp = XML::XPath->new(xml => $response->decoded_content);
	my @names = $xp->find("//table[\@class='vysledky']/tbody/tr/td[1]/text()")->get_nodelist;

	if (@names > 1) {
		$answer .= "máte na mysli: ";
		$answer .= join(", ", @names);
	}
	elsif (@names == 1) {
		$answer .= $xp->find("//table[\@class='vysledky']/tbody/tr/td[3]/text()");
	}
	else {
		$answer .= "Slovo nebylo nalezeno";
	}
	
	$server->send_message($channel, $answer, 0);
}

Irssi::signal_add('message public', 'on_public');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
