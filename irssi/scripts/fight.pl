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
	name => "google fight script",
	description => "search via google",
);

REST::Google::Search->http_referer("http://www.redrum.cz");

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $answer;
	my @resp;
	my @questions;
	my @no;
	my ($max, $maxpos) = (0, undef);

	return unless $message =~ /^`fight\s+(.+)$/i;
	@questions = split(/\s*--+\s*/, $1);
	
	foreach my $question (@questions) {
		my $res = REST::Google::Search::Web->new(
			q => $question,
			hl => 'cs',
#			lr => 'lang_cs',
		);

		if ($res->responseStatus == 200) {
			push @no, $res->responseData->cursor->estimatedResultCount;
		}
		else {
			push @no, 0;
		}
	}

	for (my $i = 0; $i < @no; $i++) {
		if ($no[$i] > $max) {
			$max = $no[$i];
			$maxpos = $i;
		}
	}

	$answer = "$nick: S $max vysledky to vyhral dotaz: ". $questions[$maxpos] .", vysledky: ".
		join(' -- ', @no);

	$server->send_message($channel, $answer, 0);
}

Irssi::signal_add('message public', 'on_public');
