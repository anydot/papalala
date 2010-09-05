#!/usr/bin/perl
# fork son which run megahal and periodically restarts, to avoid memleaks

use warnings;
use strict;

use IO::Socket::INET;

my $save_interval = 3600;
my $socket;

sub run_megahal {
	use Megahal;

	$SIG{ALRM} = sub {Megahal::megahal_cleanup; exit 0;};
	alarm $save_interval;

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
		}
	}
}

$socket = IO::Socket::INET->new(
	LocalAddr => ":4566",
	Type => SOCK_STREAM,
	ReuseAddr => 1,
	Listen => 1,
);

while (1) {
	my $pid = fork;

	if (!defined $pid) {
		die $!;
	}
	elsif ($pid) {
		wait;
		sleep 1;
	}
	else {
		run_megahal;
	}
}

