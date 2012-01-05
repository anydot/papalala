#!/usr/bin/perl 
use strict;
use warnings;
use Megahal;
my $counter = 0;

unlink qw(megahal.brn megahal.dic megahal.log megahal.txt);

Megahal::megahal_initialize();

while (<>) {
	chomp;
	Megahal::megahal_learn_no_reply($_, 0);
}

Megahal::megahal_cleanup();
