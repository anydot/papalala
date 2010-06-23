use strict;
use warnings;

use Irssi;
use Safe;
use BSD::Resource;
use POSIX qw/:sys_wait_h raise/;
use List::Util;
use List::MoreUtils;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
    authors     => 'Petr Baudis',
    name        => 'calc',
    description => 'Provide a simple Perl-ish calculator',
    license     => 'BSD',
);

sub on_msg {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $cp = Irssi::settings_get_str('bot_cmd_prefix');
	my $isprivate = !defined $channel;
	my $dst = $isprivate ? $nick : $channel;

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
		# allow the fun parts of :base_other:
		$compartment->permit(qw(gvsv gv gelem rv2gv refgen srefgen ref)); # globs and refs
		$compartment->permit(qw(padsv padav padhv padany)); # private variables
		$compartment->permit(qw(pushre regcmaybe regcreset regcomp subst substcont)); # re
		$compartment->permit(qw(crypt sprintf)); # strings
		$compartment->deny(qw(warn die)); # stderr pollution
		$compartment->share_from('List::Util', [qw(first max maxstr min minstr reduce shuffle sum)]);
		$compartment->share_from('List::MoreUtils', [qw(any all none notall true false firstidx first_index lastidx last_index insert_after insert_after_string apply after after_incl before before_incl indexes firstval first_value lastval last_value each_array each_arrayref pairwise natatime mesh zip uniq minmax)]);

		my $result = $compartment->reval($message);
		if(defined $result) {
			print $wh $result;
		} else {
			print $wh "N/A ($@)";
		}

		close $wh;

		raise 9; # exit 'gracefully' :-P -- so irssi will not mess-up with us
	}

	close $wh;

	my $result = <$rh>;
	$result //= "N/A";
	$result =~ s/[\x00\x0a\x0c\x0d]/./g;

	waitpid $pid, 0; # collect forked son

	$server->send_message($dst, "$nick: $result", 0);
}

Irssi::signal_add('message public', 'on_msg');
Irssi::signal_add('message private', 'on_msg');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
