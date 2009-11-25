use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use LWP::UserAgent;
use Cz::Cstocs;
use URI::Escape;
use Encode;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "pravidla",
	description => "check word against pravidla.cz",
);

our $to1250 = Cz::Cstocs->new(qw/utf8 1250/);

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;

	return unless $message =~ /^`pravidla\s+(.+)/;
	
	my $answer = sprintf "%s: (%s) ", $nick, decode_utf8($1);
	my $word = uri_escape($to1250->($1));

	decode_utf8
	utf8::upgrade($answer);

	######
	my $ua = LWP::UserAgent->new(
		agent => "Mozilla 4/0",
		max_redirect => 2,
		timeout => 15,
	);

	my $url = "http://www.pravidla.cz/hledej.php?qr=$word";

	my $response = $ua->get($url);
	if ($response->is_error) {
		$server->send_message($channel, "$nick: Error: ".$response->status_line, 0);
		return;
	}

	my $content = $response->decoded_content;

	my ($base_tvar, $dalsi_tvar) = $content =~ /<div class="dcap"><span class="cap bo mal">[^<]*<\/span> <b>([^<]+)<\/b><i>([^<]+)<\/i><\/div>/s;
	my $nalezen = $content =~ /<table class="rest" /s;

	if (defined $base_tvar) {
		$dalsi_tvar =~ s/^[ ~]+//;
		$dalsi_tvar =~ s/[ ~]+/, /g;
	}

	if ($nalezen) {
		$answer .= "Slovo nalezeno.";

		if (defined $base_tvar) {
			$answer .= " \x02$base_tvar\x02 => $dalsi_tvar";
		}
	}
	elsif (defined $base_tvar) {
		$answer .= "Nalezeny tvary: \x02$base_tvar\x02 => $dalsi_tvar";
	}
	else {
		$answer .= "Zadane slovo neni v pravidlech."
	}
	
	$server->send_message($channel, $answer, 0);
}

Irssi::signal_add('message public', 'on_public');
