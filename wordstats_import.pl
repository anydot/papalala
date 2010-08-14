# Import statistics from eggdrop stats.mod to wordstats database.

use warnings;
use strict;
use DBI;

my $dbh = DBI->connect("dbi:SQLite:dbname=../.irssi/wordstats.sqlite3", "", "") or
		die ("Can't open DB: $!");
my $quser = $dbh->prepare("INSERT INTO users VALUES (?)");
my $qchan = $dbh->prepare("INSERT INTO channels VALUES (?,?)");
my $qstatinfo = $dbh->prepare("INSERT INTO stats VALUES (?,?,?, ?,?, ?,?,?,?,?,?,?,?)");

my %chaninfo;
my @users;

while (<>) {
	chomp;

	if (/^#/) {
		my ($chan, $nick, $time, @stats) = split(/ /);
		next if $nick =~ /[@!]/;
		$chaninfo{$chan}->{$nick}->{'time'} = $time;
		$chaninfo{$chan}->{$nick}->{'stats'} = \@stats;
	} elsif (s/^@ daily //) {
		my ($chan, $nick, @stats) = split(/ /);
		$chaninfo{$chan}->{$nick}->{'daily'} = \@stats;
	} elsif (s/^@ weekly //) {
		my ($chan, $nick, @stats) = split(/ /);
		$chaninfo{$chan}->{$nick}->{'weekly'} = \@stats;
	} elsif (s/^@ monthly //) {
		my ($chan, $nick, @stats) = split(/ /);
		$chaninfo{$chan}->{$nick}->{'monthly'} = \@stats;
	} elsif (s/^@ user //) {
		my ($nick, $a, $b, @masklist) = split(/ /);
		push @users, $nick;
	}
}

$dbh->do('BEGIN TRANSACTION');

foreach (@users) {
	$quser->execute($_);
}
foreach (keys %chaninfo) {
	$qchan->execute($_, 'IRCnet');
}

$dbh->do('COMMIT TRANSACTION');

#define T_WORDS 0
#define T_LETTERS 1
#define T_MINUTES 2
#define T_TOPICS 3
#define T_LINES 4
#define T_ACTIONS 5
#define T_MODES 6
#define T_BANS 7
#define T_KICKS 8
#define T_NICKS 9
#define T_JOINS 10
#define T_SMILEYS 11
#define T_QUESTIONS 12
# SQL: letters INT, words INT, actions INT, smileys INT, kicks INT, modes INT, topics INT, seconds INT,
sub dts { $_[2] *= 60; @_[1, 0, 5, 11, 8, 6, 3, 2]; }
sub asub { my ($a,$b)=@_; map { $a->[$_] - $b->[$_] } 0..$#$a; }

$dbh->do('BEGIN TRANSACTION');
foreach my $c (keys %chaninfo) {
	foreach my $n (keys %{$chaninfo{$c}}) {
		my $nci = $chaninfo{$c}->{$n};
		print "$c,$n $nci->{stats} $nci->{monthly} $nci->{weekly} $nci->{daily}\n";
		my @tot = asub($nci->{stats}, $nci->{monthly});
		my @mly = asub($nci->{monthly}, $nci->{weekly});
		my @wly = asub($nci->{weekly}, $nci->{daily});
		my @dly = @{$nci->{daily}};
		my $dlen = 86400;
		my $wlen = $dlen*7;
		my $mlen = $dlen*31;
		$qstatinfo->execute($n, $c, 'IRCnet', $nci->{'time'}, 0, dts(@tot));
		$qstatinfo->execute($n, $c, 'IRCnet', int(time/$mlen-1)*$mlen, $mlen, dts(@mly));
		$qstatinfo->execute($n, $c, 'IRCnet', int(time/$wlen-1)*$wlen, $wlen, dts(@wly));
		$qstatinfo->execute($n, $c, 'IRCnet', int(time/$dlen-1)*$dlen, $dlen, dts(@dly));
	}
}

$dbh->do('COMMIT TRANSACTION');

1;
