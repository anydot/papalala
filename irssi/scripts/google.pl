use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use REST::Google::Search::Web;
use HTML::Entities;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "google",
	description => "search via google",
);

REST::Google::Search->http_referer("http://www.redrum.cz");

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $answer;
	my @resp;

	return unless $message =~ /^`g(?:oogle)?\s+(.*)$/i;

	my $res = REST::Google::Search::Web->new(
		q => $1,
		hl => 'cs',
#		lr => 'lang_cs',
	);

	if ($res->responseStatus != 200) {
		$server->send_message($channel, "$nick: Nepodarilo se vyhledat odpoved na dotaz", 0);
		return;
	}

	my @results = $res->responseData->results;
	my $len = @results;

	$len = 3
		if $len > 3;

	while ($len--) {
		my $ans = shift @results;
		my ($url, $title) = ($ans->url, $ans->title);

		$url =~ s/%3f/?/gi;
		$url =~ s/%3d/=/gi;
		$url =~ s/%26/&/gi;
		
		$title = decode_entities($title);
		$title =~ s/<.*?>//g;

		push @resp, "\x02$title\x02 -- $url";
	}

	$server->send_message($channel, "$nick: ". join(" ", @resp), 0);
}

Irssi::signal_add('message public', 'on_public');
