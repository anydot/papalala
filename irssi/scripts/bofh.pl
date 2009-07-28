use strict;
use warnings;

use Irssi;
use Irssi::Irc;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "bofh",
	description => "print bofh excuse on purpose",
);

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;

	return unless $message =~ /^`bofh/;

	open my $efile, "<", Irssi::get_irssi_dir() . "/bofh" or return;
	my @excuses = <$efile>;
	close $efile;

	my $ret = $excuses[int(rand(@excuses))];

	$server->send_message($channel, "$nick: $ret", 0);
}

Irssi::signal_add('message public', 'on_public');
