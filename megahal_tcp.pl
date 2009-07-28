#!/usr/bin/perl

use warnings;
use strict;

use Megahal;
use IO::Socket::INET;

Megahal::megahal_initialize(); ## must be first, to avoid lockup of irssi counterpart

my $socket = IO::Socket::INET->new(
	LocalAddr => ":4566",
	Type => SOCK_STREAM,
	ReuseAddr => 1,
	Listen => 1,
);


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
	}
}


