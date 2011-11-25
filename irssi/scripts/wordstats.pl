# See /wordstats.sql for db schema to be used for sqlite initialization.

# TODO: Track users across nick changes.
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
	my $isprivate = !defined $channel;
	my $dst = $isprivate ? $nick : $channel;

	my $user = $nick; # TODO
	my %times = (t => int((time - 5*3600) / 86400) * 86400 + 5*3600, # times{t}: last 5am
		w => time - 7*86400, m => time - 31*86400, y => time - 365*86400);
	my %pnames = ('' => '', t => ' today', w => ' this week', m => ' this month', y => ' this year');

	if (not defined $channel) {
		$channel = $1 if ($message =~ s/\s+(#\S+)/ /);
	}

	$message =~ s/\s*$//;
	if ($message =~ /^${cp}([twmy]?)(top[123]0|stat|stathelp)(?:\s+(\S+))?$/) {
		my ($period, $cmd, $param) = ($1, $2, $3);
		my $since = $period ? $times{$period} : 0;
		my @slabels = $stats->rows(); $slabels[&Stats::SECONDS] = "time";
		if (not defined $channel) {
			$server->send_message($dst, "Speak o' guru, what channel do you want stats for?", 0);
			return;
		}
		if ($cmd eq 'stat') {
			$user = $param if $param;
			# create empty stats record for the user in order
			# to update the number of seconds
			$stats->recstat(time, $user, $channel, $stats->zstats());

			my @stats = $stats->ustat($user, $channel, $since);
			if (not defined $stats[0]) {
				$server->send_message($dst, "$user: no such file or directory", 0);
			} else {
				$stats[&Stats::SECONDS] = format_time($stats[&Stats::SECONDS]);
				$slabels[&Stats::SECONDS] = "time spent";
				@stats = map { $stats[$_] . ' ' . $slabels[$_] } 0..$#stats;
				my $vocab = $stats->uvocab($user, $channel, $since);
				$server->send_message($dst, "$user$pnames{$period}: ".join(', ', @stats).", vocabulary $vocab words", 0);
			}

		} elsif ($cmd =~ /top([123]0)/) {
			my $e = $1;
			my $cat = 'words';
			$cat = $param if $param;

			my @top;
			if ($cat eq 'vocabulary') {
				@top = @{$stats->topvocab($channel, $since)};
			} else {
				my $rawcat = $cat eq 'time' ? 'seconds' : $cat;
				@top = @{$stats->topstat($rawcat, $channel, $since)};
				if ($cat eq 'time') {
					@top = map { [ $_->[0], format_time($_->[1]) ] } @top;
				}
			}

			@top = splice(@top, $e-10, 10);
			$a = $e-9;
			my $msg = join(', ', map { sprintf '%d. %s (%s)', $a++, $_->[0], $_->[1] } @top);

			$server->send_message($dst, "Top$e $cat$pnames{$period} ($channel): $msg", 0);

		} elsif ($cmd eq 'stathelp') {
			$server->send_message($dst, "[twmy](top10,20,30|stat|stathelp) <".join(' ',@slabels,'vocabulary').">", 0);

		} else {
			$server->send_message($dst, "$user: brm", 0);
		}
		return;
	}

	return
		if $isprivate;

	my @ustats = $stats->ustat($user, $channel, $times{t});
	my @stats = $stats->zstats();

	$stats->{dbh}->do('BEGIN TRANSACTION');
	# Count words
	foreach my $word (split(/\W+/, $message)) {
		next unless $word;
		$stats->recword(time, $user, $channel, $word);
		$stats[&Stats::WORDS]++;
		$stats[&Stats::LETTERS] += length $word;
	}
	# Count smileys
	my @smileys = (':-)', ':)', ';)', ';-)', ';p', '*g*', 'X)', '.)', '\')', '^_^', ':D', ':>', ':->', ':-D', ':-P', ':]', ':-]', '\']', '.]', ';]', ':P', '=)', '=]', ';D', ':o)', ':o]', ':^)', '(-:', ':oD', 'rotgl', 'rotfl', 'lol', 'heh', 'haha', 'lmao');
	foreach my $smiley (@smileys) {
		$a = -1;
		while (($a = index($message, $smiley, $a + 1)) >= 0) {
			$stats[&Stats::SMILEYS]++;
		}
	}
	$stats->recstat(time, $user, $channel, @stats);
	$stats->{dbh}->do('COMMIT TRANSACTION');

	my @ustats2 = $stats->ustat($user, $channel, $times{t});

	my $cheerchannel = 1;
	if (Irssi::settings_get_str("bot_cheer_channels")) {
		$cheerchannel = grep {lc $channel eq lc $_} split(/\s/, Irssi::settings_get_str("bot_cheer_channels"));
	}

	if ($cheerchannel && defined $ustats[&Stats::WORDS] and
	    int($ustats2[&Stats::WORDS] / 1000) > int($ustats[&Stats::WORDS] / 1000)) {
		# The user entered his next thousand right now. Cheer him on!
		my @addr = ("broucku", "kotatko", "cicinko", "fifinko", "brouci", "broucku", "princatko", "broucku", "drobecku", "myspuldo", "jenicku", "marenko", "brouci", "muciqu ;*", "ty, ty... ty...", "moje nejmilejsi hracko", "stenatko", "rootiku", "l33t h4x0r3");
		my @msgs = (
			'%u: brrrrm...', # should never trigger
			[
			'%u: Vlezly botik Ti gratuluje k tisici slovum, kterymi jsi nas zde dnes jiz kolektivne obstastnilo, %a.',
			'%u: Gratuluji, vyhralos dva virtualni duhove medvidky haribo za svoji tisickovku slov, %a.',
			'%u jede, uz ma dneska tisic slov. Do toho, %a!',
			'%u se dneska nejak rozkecal. Uz ma tisic slov.',
			'%u: Drz uz svuj rozmily zobacek, %a.',
			'%u: Vsiml sis, %a, ze uz mas dneska 10^3 slov?',
			'%u: Bla bla bla bla bla bla bla... (x1000)',
			'%u: M4W1A<W1N>6-H(\'!R=FYI8V@@=&ES:6,@<VQO=B!P<F5J92!K;VQE:W1I=B!I&9&QE<G4*',
			],
			'%u: Dva tisice slov. Dneska jsi to poradne rozjelo, %a.',
			'%u: Prave jsi dosahlo TRI TISICE SLOV - jsi fakt dobre, %a!',
			"\%u: \2CTYRI TISICE SLOV\2. Channel pwnz0r3d, l33t.",
		);
		my $th = ($ustats2[&Stats::WORDS] / 1000);
		my $m;
		if ($th > $#msgs) {
			$m = "($user stale flooduje a flooduje, az to uz vtipne neni. ".($th*1000)." slov, nuda.)";
		} else {
			if (ref($msgs[$th]) eq 'ARRAY') {
				$m = $msgs[$th]->[int(rand(@{$msgs[$th]}))];
			} else {
				$m = $msgs[$th];
			}
			my $addr = $addr[int(rand(@addr))];
			$m =~ s/%u/$user/g;
			$m =~ s/%a/$addr/g;
		}
		$server->send_message($channel, $m, 0);
		if (!($ustats2[&Stats::WORDS] % 1000)) {
			$server->send_message($channel, "$user: HEADSHOT! r0xx0r \\o/", 0);
		}
	}
}

sub event_mode {
	my ($server, $data, $nick, $addr) = @_;
	my ($channel, $mode, @args) = split(/ /, $data);
	return if ($nick eq $server->{nick});

	my @stats = $stats->zstats();
	$mode =~ s/[+-]//g;
	$stats[&Stats::MODES] += length $mode;
	$stats->recstat(time, $nick, $channel, @stats);
}

sub event_kick {
	my ($server, $data, $nick, $addr) = @_;
	my ($channel, $nick_kicked) = split(/ /, $data);

	my @stats = $stats->zstats();
	$stats[&Stats::KICKS]++;
	$stats->recstat(time, $nick, $channel, @stats);
}

sub event_topic {
	my ($server, $data, $nick, $addr) = @_;
	my ($channel, $topic) = split(/ :/, $data, 2);	

	my @stats = $stats->zstats();
	$stats[&Stats::TOPICS]++;
	$stats->recstat(time, $nick, $channel, @stats);
}

sub event_action {
	my ($server, $message, $nick, $addr, $channel) = @_;

	my @stats = $stats->zstats();
	$stats[&Stats::ACTIONS]++;
	$stats->recstat(time, $nick, $channel, @stats);
}

sub format_time {
        use integer;

        my $t = shift;
        my $r = "ouch, can't format that time";

        if ($t >= 0) {
                $r = sprintf "%i", $t % 60;
                $t /= 60;
        }
        if ($t > 0) {
                $r = sprintf "%i.%s", $t % 60, $r;
                $t /= 60;
        }
        if ($t > 0) {
                $r = sprintf "%i:%s", $t % 24, $r;
                $t /= 24;
        }
        if ($t > 0) {
                $r = sprintf "%id %s", $t % 31, $r;
                $t /= 31;
        }
        if ($t > 0) {
                $r = sprintf "%im %s", $t % 12, $r;
                $t /= 12;
        }
        if ($t > 0) {
                $r = sprintf "%iy %s", $t, $r;
        }

        return $r;
}

Irssi::signal_add_last('message public', 'event_public');
Irssi::signal_add_last('message private', 'event_public');
Irssi::signal_add_last('event mode', 'event_mode');
Irssi::signal_add_last('event kick', 'event_kick');
Irssi::signal_add_last('event topic', 'event_topic');
Irssi::signal_add_last('ctcp action', 'event_action');

Irssi::settings_add_str('bot', 'bot_cmd_prefix', '`');
Irssi::settings_add_str('bot', 'bot_cheer_channels', '');

1;

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
sub rows { qw(letters words actions smileys kicks modes topics seconds); }

sub new {
	my $class = shift;
	my ($dbfile) = @_;
	my $self = {};

	$self->{dbh} = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "") or
		die ("Can't open DB: $!");
	$self->{qupword} = $self->{dbh}->prepare("UPDATE words SET hits = hits + 1, last = ? WHERE user=? AND channel=? AND network=? AND word=?");
	$self->{qrecword} = $self->{dbh}->prepare("INSERT INTO words (hits,last,user,channel,network,word) VALUES (1,?,?,?,?,?)");
	$self->{qupstat} = $self->{dbh}->prepare("UPDATE stats SET letters=letters+?, words=words+?, actions=actions+?, smileys=smileys+?, kicks=kicks+?, modes=modes+?, topics=topics+?, seconds=seconds+? WHERE user=? AND channel=? AND network=? AND time=? AND timespan=?");
	$self->{qrecstat} = $self->{dbh}->prepare("INSERT INTO stats (letters,words,actions,smileys,kicks,modes,topics,seconds, user,channel,network,time,timespan) VALUES (?,?,?,?,?,?,?,?, ?,?,?,?,?)");

	$self->{qgetstat} = $self->{dbh}->prepare("SELECT sum(letters), sum(words), sum(actions), sum(smileys), sum(kicks), sum(modes), sum(topics), sum(seconds) FROM stats WHERE user = ? AND channel = ? AND network = ? AND time > ? AND time + timespan < ?");
	foreach (rows()) {
		$self->{"qtopstat$_"} = $self->{dbh}->prepare("SELECT user, sum($_) AS s FROM stats WHERE channel = ? AND network = ? AND time >= ? AND time + timespan < ? GROUP BY user ORDER BY s DESC LIMIT ?");
	}

	$self->{qgetvocab} = $self->{dbh}->prepare("SELECT count(*) FROM words WHERE user = ? AND channel = ? AND network = ? AND last > ?");
	$self->{qtopvocab} = $self->{dbh}->prepare("SELECT user, count(*) AS s FROM words WHERE channel = ? AND network = ? AND last > ? GROUP BY user ORDER BY s DESC LIMIT ?");

	$self->{userseconds} = {};

	bless $self, $class;
}

sub execute_rows {
	my $self = shift;
	my ($q, @par) = @_;
	$self->{$q}->execute(@par);
	return $self->{$q}->rows;
}

sub recword {
	my $self = shift;
	my ($t, $user, $channel, $word) = @_;
	$word = lc $word;
	$self->execute_rows('qupword', $t, $user, $channel, 'IRCnet', $word) or
		$self->execute_rows('qrecword', $t, $user, $channel, 'IRCnet', $word);
}

sub recstat {
	my $self = shift;
	my ($t, $user, $channel, @stats) = @_;

	my $tl = ($self->{userseconds}->{$user} and $self->{userseconds}->{$user}->{$channel});
	$tl and $stats[SECONDS] = $t - $tl;
	$self->{userseconds}->{$user}->{$channel} = $t;

	my $gran = 60;
	my $gt = int($t / $gran) * $gran;

	$self->execute_rows('qupstat', @stats, $user, $channel, 'IRCnet', $gt, $gran) or
		$self->execute_rows('qrecstat', @stats, $user, $channel, 'IRCnet', $gt, $gran);
}

sub ustat {
	my $self = shift;
	my ($user, $channel, $since) = @_;
	$self->execute_rows('qgetstat', $user, $channel, 'IRCnet', $since, ((1<<31)-1));
	$self->{qgetstat}->fetchrow_array;
}

sub topstat {
	my $self = shift;
	my ($cat, $channel, $since) = @_;
	$self->execute_rows('qtopstat'.$cat, $channel, 'IRCnet', $since, ((1<<31)-1), 30);
	$self->{"qtopstat$cat"}->fetchall_arrayref;
}

sub uvocab {
	my $self = shift;
	my ($user, $channel, $since) = @_;
	$self->execute_rows('qgetvocab', $user, $channel, 'IRCnet', $since);
	($self->{qgetvocab}->fetchrow_array())[0];
}

sub topvocab {
	my $self = shift;
	my ($channel, $since) = @_;
	$self->execute_rows('qtopvocab', $channel, 'IRCnet', $since, 30);
	$self->{qtopvocab}->fetchall_arrayref;
}

1;
