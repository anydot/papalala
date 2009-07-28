#!/usr/bin/perl 
use strict;
use warnings;

my $logpath = $ENV{'HOME'}.'/irclogs/IRCnet';
my @channels = glob "$logpath/#programatori* $logpath/#linux.cz*";
my $banfile = 'megahal.ban';
my $ignorefile = 'megahal.ban.ignore'; ## ignorovane bany
my $logfile = 'megahal.ban.log';
my $accept_perc = shift || 0.006; ## Jenom slova nad tuhle hladinu se pridaji
my %word;
my @top;
my %ban;
my %ignore;
my $line = 0;

if (open BANF, "<", $banfile) {
	while (<BANF>) {
		chomp;
		$ban{$_} = 1;
	}
	close BANF;
}

if (open IGNOREF, "<", $ignorefile) {
	while (<IGNOREF>) {
		chomp;
		$ignore{$_} = 1;
		if (defined $ban{$_}) {
			delete $ban{$_};
		}
	}
}


for my $channel (@channels) {
	open (INPUT, $channel);

	while ($_ = uc(<INPUT>)) {
		next if(/^---/o); ## Zmeny data
		s/^\d{8} \d\d:\d\d:\d\d//o; ## Ustrihnout datum
		next unless (/^</o); ## Pokud nikdo nemluvi
		s/^<.[^>]*> [^ \t]*:* *//o; ## Odstrani nicky, az na samotnou hranici textu
# + pripadne dalsi komupisu:
		next if (/^\s*$/o); ## prazdny radek
		
		while (/\b(\w+)\b/go) {
			$word{$1}++;
		}
		$line++;
	}
	close (INPUT);
}

my $mincount = int($line*$accept_perc);
for my $w (keys %word) {
	push @top, $w if (($word{$w} >= $mincount) and (!defined $ignore{$w}));
}
@top = sort @top;

open BANF, ">", $banfile or die("Nelze otevrit banfile: $banfile");
open LOGF, ">>", $logfile or die("Nelze otevrit logfile: $logfile");
print LOGF "=== Start at ".localtime()."\n";

for my $banned (@top) {
	print LOGF "$banned\n" unless $ban{$banned};
	print BANF "$banned\n";
}

print LOGF "=== Log end\n\n\n";
close BANF;
close LOGF;

