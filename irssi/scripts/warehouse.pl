use strict;
use warnings;

use Irssi;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
    authors     => 'Petr Baudis',
    name        => 'warehouse',
    description => 'Interface to Warehouse 23',
    license     => 'BSD',
);

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $cp = Irssi::settings_get_str('bot_cmd_prefix');

	return unless $message =~ s/^${cp}warehouse//;

	my ($level, $addr, $lead);
	if (int(rand(12))) {
		$level = int(rand(5))+1;
		$addr = "http://www.warehouse23.com/basement/box/index.html?level=$level";
		$lead = "\n<p>";
	} else {
		my $item = int(rand(102))+1; # 101 items, we want the error message to be shown too
		$addr = "http://www.warehouse23.com/basement/dumpster/dump.html?count=$item";
		$lead = "</h3>";
	}

	# Fetch the web page
	my $page = qx/wget --dns-timeout=5 --connect-timeout=10 --read-timeout=10 -t 1 -q -O - $addr/;

	if(not $page)
	{
		$server->send_message($channel, "$nick: The doors of the warehouse are shut still and cannot be opened.", 0);
		$server->send_message($channel, "$nick: You hear very strange sounds from the inside and suddenly feel very uneasy.", 0);
		return;
	}

	#$page =~ s/.+(<h3>.+?<\/p>).+/\1/si;

	# Find the intro part and edit in the floor number
	my $intro;
	($intro) = ($page =~ m/<h3>(.+?)<.h3>/i);
	$intro =~ s/this floor/floor #$level/i;
	if(not $intro)
	{
		$server->send_message($channel, "$nick: You attempt to open a box, but it is jammed shut too tightly.", 0);
		$server->send_message($channel, "$nick: A note on the box says \"out of order\".", 0);
		return;
	}
	$server->send_message($channel, "$nick: $intro", 0);

	# Get the good stuff
	my $str;
	($str) = ($page =~ m/$lead\n(.+?)\n<\/?p>\n/si);
	$str =~ s/<.+?>//g;
	if(not $str)
	{
		$str = "Nothing. Absolutely nothing. You feel as if you ought to notify the script maintainer.";
	}

	# Word wrapping, perl style
	# $width = 380;
	# $str =~ s/(?:^|\G\n?)(?:(.{1,$width})(?:\s|\n|$)|(\S{$width})|\n)/$1$2\n/sg;
	$server->send_message($channel, "$nick: $str", 0);
}

Irssi::signal_add('message public', 'on_public');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
