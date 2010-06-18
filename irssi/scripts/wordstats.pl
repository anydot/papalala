# TODO: Count also other stats than WORDS, LETTERS, SECONDS.
# TODO: Track users across nick changes.
# TODO: TopN commands.
# TODO: Shakedown stats records.

use strict;
use warnings;

use Irssi;
use DBI;

use vars qw($VERSION %IRSSI);
$VERSION = "0.0.1";
%IRSSI = (
    authors     => 'Petr Baudis',
    name        => 'wordstats',
    description => 'Keep and report per-user talk statistics',
    license     => 'BSD',
);

our $irssidir = Irssi::get_irssi_dir;
our $stats = Stats->new("$irssidir/wordstats.sqlite3");

sub event_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $cp = Irssi::settings_get_str('bot_cmd_prefix');

	my $user = $nick; # TODO

	if ($message =~ /^${cp}(t?)(top[123]0|stat|stathelp)\b/) {
		# TODO
		my @slabels = qw(letters words actions smileys kicks modes topics seconds);
		if ($2 eq 'stat') {
			# create empty stats record for the user in order
			# to update the number of seconds
			$stats->recstat(time, $user, $channel, $stats->zstats());

			my @stats = $stats->ustat($user, $channel, $1 eq 't' ? time - 86400 : 0);
			if (not defined $stats[0]) {
				$server->send_message($channel, "$user: no such file or directory", 0);
			} else {
				@stats = map { $stats[$_] . ' ' . $slabels[$_] } 0..$#stats;
				$server->send_message($channel, "$user: ".join(', ', @stats), 0);
			}

		} elsif ($2 eq 'stathelp') {
			$server->send_message($channel, "[t](top10,20,30|stat|stathelp) <".join(' ',@slabels).">", 0);

		} else {
			$server->send_message($channel, "$user: brm", 0);
		}
		return;
	}

	my @stats = $stats->zstats();

	$stats->{dbh}->do('BEGIN TRANSACTION');
	foreach my $word (split(/\W+/, $message)) {
		next unless $word;
		$stats->recword(time, $user, $channel, $word);
		$stats[Stats::WORDS]++;
		$stats[Stats::LETTERS] += length $word;
	}
	$stats->recstat(time, $user, $channel, @stats);
	$stats->{dbh}->do('COMMIT TRANSACTION');
}

Irssi::signal_add_last('message public', 'event_public');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');

package Stats;

sub LETTERS {0};
sub WORDS {1};
sub ACTIONS {2};
sub SMILEYS {3};
sub KICKS {4};
sub MODES {5};
sub TOPICS {6};
sub SECONDS {7};
sub zstats { (0,0,0,0,0,0,0,0); }

sub new {
	my $class = shift;
	my ($dbfile) = @_;
	my $this = {};

	$this->{dbh} = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "") or
		die ("Can't open DB: $!");
	$this->{qupword} = $this->{dbh}->prepare("UPDATE words SET hits = hits + 1, last = ? WHERE user=? AND channel=? AND network=? AND word=?");
	$this->{qrecword} = $this->{dbh}->prepare("INSERT INTO words (hits,last,user,channel,network,word) VALUES (1,?,?,?,?,?)");
	$this->{qupstat} = $this->{dbh}->prepare("UPDATE stats SET letters=letters+?, words=words+?, actions=actions+?, smileys=smileys+?, kicks=kicks+?, modes=modes+?, topics=topics+?, seconds=seconds+? WHERE user=? AND channel=? AND network=? AND time=? AND timespan=?");
	$this->{qrecstat} = $this->{dbh}->prepare("INSERT INTO stats (letters,words,actions,smileys,kicks,modes,topics,seconds, user,channel,network,time,timespan) VALUES (?,?,?,?,?,?,?,?, ?,?,?,?,?)");

	$this->{qgetstat} = $this->{dbh}->prepare("SELECT sum(letters), sum(words), sum(actions), sum(smileys), sum(kicks), sum(modes), sum(topics), sum(seconds) FROM stats WHERE user = ? AND channel = ? AND network = ? AND time > ? AND time + timespan < ?");

	$this->{userseconds} = {};

	bless $this, $class;
}

sub execute_rows {
	my $this = shift;
	my ($q, @par) = @_;
	$this->{$q}->execute(@par);
	return $this->{$q}->rows;
}

sub recword {
	my $this = shift;
	my ($t, $user, $channel, $word) = @_;
	$word = lc $word;
	$this->execute_rows('qupword', $t, $user, $channel, 'IRCnet', $word) or
		$this->execute_rows('qrecword', $t, $user, $channel, 'IRCnet', $word);
}

sub recstat {
	my $this = shift;
	my ($t, $user, $channel, @stats) = @_;

	my $tl = ($this->{userseconds}->{$user} and $this->{userseconds}->{$user}->{$channel});
	$tl and $stats[SECONDS] = $t - $tl;
	$this->{userseconds}->{$user}->{$channel} = $t;

	my $gran = 60;
	my $gt = int($t / $gran) * $gran;

	$this->execute_rows('qupstat', @stats, $user, $channel, 'IRCnet', $gt, $gran) or
		$this->execute_rows('qrecstat', @stats, $user, $channel, 'IRCnet', $gt, $gran);
}

sub ustat {
	my $this = shift;
	my ($user, $channel, $since) = @_;
	$this->execute_rows('qgetstat', $user, $channel, 'IRCnet', $since, ((1<<31)-1));
	$this->{qgetstat}->fetchrow_array;
}

1;
