#!/usr/bin/perl 
use strict;
use warnings;
use Megahal;

my $logpath = $ENV{'HOME'}.'/irclogs/IRCnet';
my @channels = glob "$logpath/#programatori* $logpath/#linux.cz*";
my $maxlines = shift or 40000;
my @bots = qw(Etingo dev_null Papalala Muaddib); # bots and trolls to ignore, case-insensitive

while (my $channel = shift @channels) {
	open my $input, $channel
		or die "Can't open log";

	my $counter = $maxlines;

	while (<$input>) {
		next
			if(/^---/); ## Zmeny data
		s/^\d{8} \d\d:\d\d:\d\d//; ## Ustrihnout datum
		next
			unless (/^</); ## Pokud nikdo nemluvi
		s/^<.([^>]*)>\s*(\S+[:,>]+)?\s*//; ## Odstrani nicky, az na samotnou hranici textu
		next
			if grep( lc($1) eq lc($_) , @bots);	# strip bots etc
# + pripadne dalsi komupisu:
		next
			if (/^\s*$/); ## prazdny radek

		last
			unless $counter--;

		print;
		
		if ($counter % 1000 == 0) {
			printf STDERR "%i files and %i lines (cur. file) to go\n",
				scalar @channels, $counter;
		}
	}
	close $channel;
}
