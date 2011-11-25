use strict;
use warnings;

use Irssi;
use lib qw(.);
use IDOS;
use WWW::Shorten "Metamark", ":short";

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
    authors     => 'Petr Baudis',
    name        => 'idos',
    description => 'Czech public transport connection search',
    license     => 'BSD',
);

our %lastres; # indexed by region

sub on_msg {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $cp = Irssi::settings_get_str('bot_cmd_prefix');
	my $rcount = Irssi::settings_get_str('bot_idos_results');
	my $isprivate = !defined $channel;
	my $dst = $isprivate ? $nick : $channel;

	return unless $message =~ s/^${cp}(idos|dpp|idosr)(next)?\b\s*//;

	my ($cmd, $next) = ($1, $2);
	my $region;

	if ($cmd eq 'idos') {
		$region = 'vlakyautobusymhd';
	} elsif ($cmd eq 'dpp') {
		$region = 'pid';
	} elsif ($cmd eq 'idosr') {
		$message =~ s/^(\w+)\s+//;
		$region = lc $1;
	}

	my $r;
	if (not $next) {
		my @args = split /\s*--\s*/, $message;

		if ($#args < 1) {
			$server->send_message($dst, "$nick: $cp(idos | dpp | idosr REGION) from[;fromalt;fromalt2] -- to[;...] [-- thru[;...]]", 0);
			return;
		}

		my %par = (
			region => $region,
			origin => $args[0],
			dest => $args[1]
		);
		$par{thru} = $args[2] if $args[2];
		my $q = IDOS::RouteQuery->new(%par);
		$r = [ $q->execute() ];
		if ($#$r < 0) {
			$server->send_message($dst, "$nick: no results", 0);
			return;
		}
		$lastres{$region} = $r;

	} else {
		$r = $lastres{$region};
		if ($#$r < 0) {
			$server->send_message($dst, "$nick: no more results", 0);
			return;
		}
	}

	for (1..$rcount) {
		my $res = shift @$r;
		next unless $res;
		my $cl = $res->connections();
		my $o = "";
		$o = sprintf '[%s %s] ', $res->time(), $res->date();
		for (0..$#$cl) {
			my $c = $cl->[$_];
			my $Cdark = "\3".'14';
			my $Cblue = "\3".'12';
			my $Creset = "\3";
			$o .= sprintf '%s %s--%s %s%s %s<%s>%s %s %s--%s ', $c->origin(), $Cdark, $Creset, $c->note() ? sprintf('[%s] ', $c->note()) : '', $c->start(), $Cblue, $c->by(), $Creset, $c->stop(), $Cdark, $Creset;
		}
		$o .= sprintf '%s ', $cl->[$#$cl]->dest() if $#$cl >= 0;
		$o .= sprintf('[%s] %s', join(', ', grep { defined $_ } ($res->traveltime(), $res->traveldist(), $res->cost())),
			($res->detail() ? short_link($res->detail()) : ''));
		$server->send_message($dst, "$nick: $o", 0);
	}
}

Irssi::signal_add('message public', 'on_msg');
Irssi::signal_add('message private', 'on_msg');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
Irssi::settings_add_str('bot', 'bot_idos_results', '2');
