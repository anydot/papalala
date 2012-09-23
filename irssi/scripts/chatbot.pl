use strict;
use warnings;

use Irssi;
use Irssi::Irc;

use Encode;
use Time::HiRes qw(usleep gettimeofday tv_interval);
use Hailo;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "chatbot",
	description => "megahal connector",
);

our $hailo;

sub on_msg {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $mynick = $server->{nick};
	my $isprivate = !defined $channel;
	my $dst = $isprivate ? $nick : $channel;
	my $trigger_chance = Irssi::settings_get_int('bot_megahal_triggerchance');
	my $request;
	my $want_learn = 1;

	return if grep {lc eq lc $nick} split(/ /, Irssi::settings_get_str('bot_megahal_ignore'));

	$message = decode("utf8", $message);

	if ($message !~ s/^\s*$mynick[,:]\s*(.*)$/$1/i) {
		$want_learn = 0;
		$message =~ s/^\s*\w+[,:]\s*//;
		if (!$trigger_chance or int(rand($trigger_chance))) {
			Irssi::settings_get_bool('bot_megahal_learn_from_all') and $hailo->learn($message);
			return;
		}
	}

	# Ensure we do not reply ridiculously quickly:
	my $delay = Irssi::settings_get_int('bot_megahal_mindelay');
	my $t0 = [gettimeofday()];

	my $response = $hailo->reply($message);
	$want_learn and $hailo->learn($message);

	my $dt = tv_interval($t0, [gettimeofday()]) * 1000000;

	usleep($delay - $dt)
		if $dt < $delay;

	$server->send_message($dst, "$nick: $response", 0);
}

Irssi::signal_add('message public', 'on_msg');
Irssi::signal_add('message private', 'on_msg');

Irssi::settings_add_str('bot', 'bot_megahal_ignore', '');
# minimal response time in microseconds
Irssi::settings_add_int('bot', 'bot_megahal_mindelay', 0);
Irssi::settings_add_bool('bot', 'bot_megahal_learn_from_all', 1);
Irssi::settings_add_int('bot', 'bot_megahal_triggerchance', 1000);

##
$hailo = Hailo->new(brain => Irssi::get_irssi_dir()."/papalala.brn");

