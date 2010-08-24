#!/usr/bin/perl
# Run in loop: while true; do perl megahal_tcp.pl ; sleep 0.2; done

use warnings;
use strict;

use Megahal;
use IO::Socket::INET;

our $save_interval = 3600;
our $save_last = time;

my $socket = IO::Socket::INET->new(
	LocalAddr => ":4566",
	Type => SOCK_STREAM,
	ReuseAddr => 1,
	Listen => 1,
);

# XXX: If your brain takes long time to load, you might want to move
# this before socket creation to avoid irssi lockups.
Megahal::megahal_initialize();


print "Hal started\n";

while (my $client = $socket->accept) {
	print "Client connected\n";
	while (my $line = $client->getline) {
		print "Get line: $line";
		chomp($line);
		
		my $response = Megahal::megahal_do_reply($line, 0);
		$response =~ s/\s+/ /;
		$response =~ s/\s*$/\n/;

		print "Responding with: $response";
		
		$client->printflush($response);

		# Save brain
		if ($save_last + $save_interval < time) {
			Megahal::megahal_cleanup();
			# This leaks memory:
			# Megahal::megahal_initialize();
			# $save_last = time;
			exit;
		}
	}
}


