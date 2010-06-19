use strict;
use warnings;

use Irssi;
use Safe;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
    authors     => 'Petr Baudis',
    name        => 'calc',
    description => 'Provide a simple Perl-ish calculator',
    license     => 'BSD',
);

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $cp = Irssi::settings_get_str('bot_cmd_prefix');

	return unless $message =~ s/^${cp}calc\s+//;

	my $compartment = new Safe();
	# padany is crucial for Safe to work at all
	$compartment->permit_only(qw(:base_core :base_math join padany));

	my $result = $compartment->reval($message);
	if(not defined $result) {
		$result = "N/A";
	} else {
		$result =~ s/[\x00\x0a\x0c\x0d]/./g;
	}

	$server->send_message($channel, "$nick: $result", 0);
}

Irssi::signal_add('message public', 'on_public');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
