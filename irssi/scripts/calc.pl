use strict;
use warnings;

use Irssi;
use Safe;
use BSD::Resource;
use POSIX qw/:sys_wait_h raise/;

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

	pipe my $rh, my $wh;
	my $pid = fork;

	if (!defined $pid) {
		die "Can't fork";
	}
	elsif ($pid == 0) {
		setrlimit(RLIMIT_CPU, 1, 1);
		setrlimit(RLIMIT_RSS, 30_000_000, 30_000_000);
		close $rh;

		my $compartment = new Safe();
		# padany is crucial for Safe to work at all
		$compartment->permit_only(qw(:base_core :base_math :base_loop :base_mem padany));

		my $result = $compartment->reval($message);
		if(defined $result) {
			$result =~ s/[\x00\x0a\x0c\x0d]/./g;
			print $wh $result;
		}

		close $wh;

		raise 9; # exit 'gracefully' :-P -- so irssi will not mess-up with us
	}

	close $wh;

	my $result = <$rh>;
	$result //= "N/A";

	waitpid $pid, 0; # collect forked son

	$server->send_message($channel, "$nick: $result", 0);
}

Irssi::signal_add('message public', 'on_public');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
