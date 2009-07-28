#!/usr/bin/perl 
use warnings;
use strict;

use Net::IRC;
use Switch;
use Data::Dumper;
use DBI;
use Cfg;


## TODO ochrana pred bany, predelat szpusob matchovani koho chranit tak aby se dalo chranit pred bany i kdyz dany postizeny neni online
## TODO posledni v seen je join

my $config = Cfg::config();

eval("use Hal;") if $config->{Megahal};


#
my $current_kicktick = $config->{"KickTick"};
my @kicked_channs;
my $conn;
my $irc;
my %admin = ( user => "", host => "", );
my @ignore;
my @channels;
my %protect;
my $opchar = '@';
my %chanmodes =  ## 0 means no param, 1 one param always, 2 one param only while set (IRCnet default)
	qw{o 1 v 1 b 1 e 1 I 1 R 1 k 1 l 2 i 0 m 0 n 0 p 0 s 0 t 0 a 0 q 0 r 0};
my $dbh = db_init($config->{"DB"});
my @calcs = ();
##

Hal::start() if $config->{Megahal};


# Catch ctrl-c properly and stop megahal.
$SIG{TERM}=sub {
	alarm 0;
	Hal::quit() if $config->{Megahal};
	$conn->quit("Someone terminated me, oops") if (defined $conn);
	exit;
};
$SIG{INT}=$SIG{TERM};
$SIG{ALRM} = sub {
	$current_kicktick--;

	if (!$current_kicktick) {
		$current_kicktick = $config->{"KickTick"};
		print "* Kicktick\n";

		if (scalar(@kicked_channs)) {
			my $chann = shift @kicked_channs;
			channel_join($conn, $chann) if (defined $conn);
		}
	}

	alarm 60;
};

 


$irc = Net::IRC->new;
$conn = $irc->newconn(
	Nick => $config->{"Nick"},
	Server => $config->{"Server"},
	Port => $config->{"Port"},
	Ircname => $config->{"Ircname"},
	Username => $config->{"Nick"},
	Pacing => $config->{"Pacing"},
);
$conn->add_handler('376', \&on_connect); # 376 = end of MOTD: we're connected.
$conn->add_handler('msg', \&on_msg);
$conn->add_handler('public', \&on_public);
$conn->add_handler('kick', \&on_kick);
$conn->add_handler('cversion', \&on_cversion);
$conn->add_handler('caction', \&on_caction);
$conn->add_handler('join', \&on_join);
$conn->add_handler('whoreply', \&on_whoreply);
$conn->add_handler('nick', \&on_nick);
$conn->add_handler('part', \&on_part);
$conn->add_handler('quit', \&on_quit);
$conn->add_handler('mode', \&on_mode);
$conn->add_handler('005' , \&on_isupport); # isupport line
$conn->add_handler('topic', \&on_topic);
$conn->add_handler('nosuchnick', \&on_nosuchnick);
$conn->add_handler('notice', \&on_notice);

alarm 60; ## Odstartujem!

$irc->start;

sub db_init {
	my ($db) = @_;
	my $have_db = -f $db;
	my $dbh;

	$dbh = DBI->connect("dbi:SQLite:$db") or die("Can't connect to DB");

	if (!$have_db) {
		$dbh->do("CREATE TABLE log (channel, nick, action, txt, time)");
	}

	return $dbh;
}

sub db_update {
	my ($channel, $nick, $action, $txt) = @_;

	$dbh->do("INSERT INTO log (channel, nick, action, txt, time) VALUES (?, ?, ?, ?, ?)",
		undef, $channel, $nick, $action, $txt, time());
}

sub db_get {
	my ($channel, $nick) = @_;

	return $dbh->selectrow_array("SELECT action, txt, time, nick FROM log WHERE (channel = ? OR channel = '' ) AND nick LIKE ? ORDER BY time DESC LIMIT 1",
		undef, $channel, $nick);
}

sub db_getstat {
	my ($nick) = @_;
	my @stat = (0, 0, 0);
	my $sth;
	my $txt;
	
	$nick = $dbh->selectrow_array("SELECT nick FROM log WHERE nick LIKE ? ORDER BY time DESC LIMIT 1", undef, $nick);
	$sth = $dbh->prepare("SELECT txt FROM log WHERE nick LIKE ? AND (action = 'msg' OR action = 'action')");
	$sth->execute($nick);

	while ( defined($txt = $sth->fetchrow_array) ) {
		@stat = multimap(sub {$_[0]+$_[1];}, \@stat, [count_stat($txt)]);
	}

	return ($nick, @stat);
}

sub count_stat {
	my ($txt) = @_;
	my @stat;

	$stat[0] = length($txt);						# characters
	$stat[1] = scalar( () = $txt =~ /\w+/g );		# words
	$stat[2] = 1;									# lines

	return @stat;
}

sub multimap {
	my ($mapf) = shift;
	my @out;
	my $i;

	for ($i = 0; ; $i++) {
		my @row;

		foreach my $array (@_) {
			if (exists($array->[$i])) {
				push @row, $array->[$i];
			} else {
				return @out;
			}
		}

		push @out, &$mapf(@row);	
	}
}

sub db_deinit {
	$dbh->disconnect;
}

sub on_nosuchnick {
	@calcs = ();
}

sub on_isupport {
	my ($self, $event) = @_;
	my $line = ($event->args)[0];
	my $prefix;
	my @cmode = ("", "", "", "");
	
	if ($line =~ /PREFIX=\((\S+)\)(\S+)/) {
		$prefix = $1;
		my @m = split //, $1;
		my @c = split //, $2;

		foreach my $mode (@m) {
			if ($mode eq 'o') {
				$opchar = shift @c;
			}
			else {
				shift @c;
			}
		}
	}
	if ($line =~ /CHANMODES=(\S+)/) {
		@cmode = split /,/, $1;
	}

	my $current = (defined $prefix?$prefix:"") . (defined $cmode[0]?$cmode[0]:"") . (defined $cmode[1]?$cmode[1]:"");
	foreach (split //, $current) {
		$chanmodes{$_} = 1;
	}

	if (defined $cmode[2]) {
		foreach (split //, $cmode[2]) {
			$chanmodes{$_} = 2;
		}
	}

	if (defined $cmode[3]) {
		foreach (split //, $cmode[3]) {
			$chanmodes{$_} = 0;
		}
	}
}

sub on_mode {
	my ($self, $event) = @_;
	my @args = $event->args;
	my $modes = shift @args;
	my $prefix = "";


	foreach my $chan ($event->to) {
		next if $chan eq $event->from;

		db_update($chan, $event->nick, "mode", $modes . (scalar @args ? " ".join(" ", @args) : ""));

	foreach my $mode (split //, $modes) {
		if ($mode eq "+" or $mode eq "-") {
			$prefix = $mode;
			next;
		}

		switch ($mode) {
			case "o" {
				my $target = $args[0];
				if ($prefix eq "-" and is_protected($target, $chan)) {
					printf "%s deoped by %s on %s\n", $target, $event->from, $chan;
					revenge_action($self, $event->nick, $chan);
					$self->mode($chan, "+o", $target);
				} 
				elsif ($prefix eq "+" and $target eq $self->nick) {
					$self->who($chan);
				}
			}
			case "b" {
				my $target = $args[0];
### TODO
			}
		}
		if ($chanmodes{$mode} == 1 or ($chanmodes{$mode} == 2 and $prefix eq '+')) {
			shift @args;
		}
	}
	}
}

sub on_nick {
	my ($self, $event) = @_;
	my $nick = $event->nick;
	my $newnick = ($event->args)[0];
	my $newhostmask = $event->from;

	$newhostmask =~ s/^[^!]+/$newnick/;

	if (defined $protect{$nick}) {
		delete $protect{$nick};
	}

	db_update("", $nick, "nick_to", $newnick);
	db_update("", $newnick, "nick_from", $nick);
	
	foreach my $chan (@channels) {
		if (want_protection($newhostmask, $chan)) {
			protect($newhostmask, $chan);
		}
	}
}

sub on_join {
	my ($self, $event) = @_;
	my $nick = $event->from;
	
	$nick =~ s/!.*$//;

	db_update($event->to, $event->nick, "join", "");

	if (want_protection($event->from, $event->to)) {
		printf "opping %s on %s", $nick, $event->to;

		protect($event->from, $event->to);
		$self->mode($event->to, "+o $nick");
	}
}

sub want_protection {
	my ($hostmask, $channel) = @_;

	return "$hostmask:$channel" =~ $config->{"Protect"};
}

sub protect {
	my ($hostmask, $channel) = @_;
	my $nick = $hostmask;

	$nick =~ s/!.*$//;
	
	printf "Protecting %s on %s\n", $hostmask, $channel;

	if (! defined $protect{$nick}) {
		$protect{$nick} = {
			Hostmask => $hostmask,
			Channels => [$channel],
		}
	}
	else {
		push @{ $protect{$nick}->{"Channels"} }, $channel;
	}
}

sub unprotect {
	my ($hostmask, $channel) = @_;
	my $nick = $hostmask;

	$nick =~ s/!.*$//;

	printf "Unprotecting %s on %s\n", $hostmask, $channel;

	my @c = grep !/^$channel$/, $protect{$nick}->{"Channels"};

	if ($#c == -1) {
		delete $protect{$nick};
	} else {
		$protect{$nick}->{"Channels"} = \@c;
	}
}

sub on_whoreply {
	my ($self, $event) = @_;
	my @args = $event->args;
	my $channel = $args[1];
	my $hostmask = sprintf "%s!%s@%s", $args[5], $args[2], $args[3];

	if (want_protection($hostmask, $channel)) {
		if (! is_protected($hostmask, $channel)) {
			protect($hostmask, $channel);
		}
		if ($args[6] !~ /$opchar/) {
			$self->mode($channel, "+o", $args[5]);
		}
	}
}

# It is a good custom to reply to the CTCP VERSION request.
sub on_cversion {
	my ($self, $event) = @_;

	print "Got version query from ".$event->from."\n";
	$self->ctcp_reply ($event->nick, 'VERSION papalala megahal ircbot by anydot');
}

sub on_caction {
	my ($self, $event) = @_;
	my ($from, $chan) = ($event->nick, ${$event->to}[0]);

	db_update($chan, $from, "action", $event->args);
}

# What to do when the bot successfully connects.
sub on_connect {
	my ($self) = @_;

	$self->ignore("all", $config->{"Nick"} . "!*@*");
	foreach my $mask (@{$config->{"Ignore"}}) {
		ignore($self, $mask);
	}

	channel_join($self, $config->{"Channels"});
}

sub on_topic {
	my ($self, $event) = @_;

	return if $event->format eq 'server';

	my ($from, $chan) = ($event->nick, ${$event->to}[0]);

	db_update($chan, $from, "topic", $event->args);
}

# Listen to dialog on the channel and send it to megahal for processing.
sub on_public {
	my ($self, $event) = @_;
	my $nick = $config->{"Nick"};
	
	my $from=$event->nick;
	my $chan=${$event->to}[0];
	
	$_=join("\n",$event->args)."\n";
	s/[\x00-\x1f]//g; # no bold crap.

	db_update($chan, $from, "msg", $_);
	
	if (/^$nick[:,;]\s*(.*)$/i) {
		if ($1) {
			my $t = $1;

			my $ret = "$from: Don\'t do it!";
			if ($t =~ /^seen\s+(\S+)/) {
				my ($action, $txt, $t, $dbnick) = db_get($chan, $1);

				if (!defined $action) {
					$ret = "$from: I have not seen $1";
				} else {
					$ret = sprintf "$from: I have seen %s %s ago (%s): %s",
						$dbnick, format_time(time() - $t), $action, $txt;
				}
			}
			elsif ($t =~ /^stat(?:\s+(\S+).*)?\s*$/) {
				my ($dbnick, $chars, $words, $lines) = db_getstat($1 ? $1 : $from);
				my $stat;
				
				$stat = sprintf "written %s characters, %s words and %s lines",
					$chars, $words, $lines;

				$ret = "$from: ";
				if ($dbnick eq $from) {
					$ret .= "You have $stat";
				} else {
					$ret .= "$dbnick has $stat";
				}
			}
			elsif ($t !~ /^#/) {
				if ($config->{Megahal}) {
					my $response = Hal::talk($t."\n");
					if (length($response) > $config->{"MaxLineLen"}) {
						$response = substr($response, 0, $config->{"MaxLineLen"})." ...";
					}
					$ret = "$from: $response";
				} else {
					$ret = "$from: Chat is (temporarily?) disabled";
				}
			}
			else {
				my $response = `./chat`;
				$ret = "$from: $response";
			}
				
			$self->privmsg($chan,$ret);
		}
	}
	elsif ($chan =~ $config->{BotCalcAllowed} && /^(?:(?:[?][?])|calc)\s+(.*)$/i) {
		push @calcs, $chan;
		push @calcs, $from;
		
		my $botchan = $config->{BotCalcChan};
		$self->privmsg($config->{BotCalcNick}, "whatis $botchan $1");
	} 
	elsif ($chan =~ $config->{BotCalcAllowed} && /^[+][+]\s+(.*\s=.*)$/) {
		push @calcs, $chan;
		push @calcs, $from;

		my $botchan = $config->{BotCalcChan};
		$self->privmsg($config->{BotCalcNick}, "learn $botchan $1");
	}
	elsif ($chan =~ $config->{BotCalcAllowed} && /^[-][-]\s+(.*)$/) {
		push @calcs, $chan;
		push @calcs, $from;

		my $botchan = $config->{BotCalcChan};
		$self->privmsg($config->{BotCalcNick}, "forget $botchan $1");
	}
	elsif ($chan =~ $config->{BotCalcAllowed} && /^[+][-]\s+(.*)$/) {
		push @calcs, $chan;
		push @calcs, $from;

		my $botchan = $config->{BotCalcChan};
		$self->privmsg($config->{BotCalcNick}, "factoids change $botchan $1");
	}


}

sub on_notice {
	my ($self, $event) = @_;

	if ($event->nick eq $config->{BotCalcNick}) {
		my $msg = ($event->args)[0];
		
		$self->privmsg(shift(@calcs), shift(@calcs) . ": $msg");
	}
}

# Listen to private messages and respond
sub on_msg {
	my ($self, $event) = @_;
	my $msg = ($event->args)[0];
	my $password = $config->{"Password"};
	
	my $from=$event->nick;

	if ($from eq $config->{BotCalcNick}) {
		$self->privmsg(shift(@calcs), shift(@calcs) . ": $msg");

		return;
	}
	
	if ($event->user eq $admin{user} && $event->host eq $admin{host}) {
		admin_cmd($self, $from, $msg);
	} 
	elsif ($msg =~ /^\s*login\s+$password/) {
		print "admin login from " . $event->from . "\n";
		$admin{user} = $event->user;
		$admin{host} = $event->host;
		$self->privmsg($from, "Logged in successfully (try help)");
	} else {
		$self->privmsg($from, "Login first (with login the_password)");
	}
	return;
}

sub admin_cmd {
	my ($self, $from, $msg) = @_;
	$msg =~ s/^\s*(\S+)\s*//;
	my $cmd = $1;

	switch ($cmd) {
		case "logout" {
			print "logout\n";
			$admin{host} = "";
			$admin{user} = "";
			$self->privmsg($from, "you was logouted");
		}
		case "ping" {
			$self->privmsg($from, "pong");
		}
		case "join" {
			channel_join($self, $msg);
		}
		case "part" {
			$msg =~ /^(\S+)\s*(.*)/;
			$self->part("$1 :$2");
			protect_part($1);
		}
		case "msg" {
			$msg =~ /^(\S+)\s+(.+)/;
			print "msg to $1: $2\n";
			$self->privmsg($1, $2);
		}
		case "quit" {
			print "quiting\n";
			$self->quit($msg);
		}
		case "ignore" {
			print "ignoring $msg\n";
			if (!ignore($self, $msg)) {
				$self->privmsg($from, "oops, can't ignore this");
			}
		}
		case "iglist" {
			my $response = "";
			my $n = 0;
			foreach my $mask (@ignore) {
				$response .= "$n:$mask ";
				$n++;
			}

			if ($response eq "") {
				$response = "no ignore";
			}
			$self->privmsg($from, $response);
		}
		case "unignore" {
			print "unignoring\n";
			if (!unignore($self, $msg)) {
				$self->privmsg($from, "oops, can't unignore this");
			}
		}
		case "protlist" {
			foreach (protlist()) {
				$self->privmsg($from, $_);
			}
			$self->privmsg($from, "End of protlist");
		}
		case "mode" {
			$self->mode(split(/\s+/, $msg));
		}
		case "kick" {
			$msg =~ /^\s*(\S+)\s+(\S+)\s?(.*)$/;
			$self->kick($1, $2, $3);
		}
		case "nick" {
			$msg =~ /^\s*/;
			$self->nick($1);
		}
		case "help" {
			$self->privmsg($from, "logout ping join part msg quit ignore iglist unignore help protlist mode kick");
		}
		else {
			print "unknown cmd: $cmd\n";
			$self->privmsg($from, "unknow cmd: $cmd");
		}
	}
	
	return;
}
	
sub on_kick {
	my ($self, $event) = @_;
	my @stuff = $event->args;
	my $chan = $stuff[0];
	my $reason = $stuff[1];

	foreach my $nick ($event->to) {
		db_update($chan, $nick, "kick", "kicked by ".$event->nick." with reason ". $reason);
		print "testing $nick on $chan\n";
		if ($nick eq $self->nick) {
			printf "was kicked from %s by %s(%s)\n", $chan, $event->from, $reason;
			protect_part($chan);
			push @kicked_channs, $chan;
		} 
		elsif (is_protected($nick, $chan)) {
			printf "%s kicked out %s in %s\n", $event->from, $nick, $chan;
			unprotect($nick, $chan);

			revenge_action($self, $event->nick, $chan);
		}
	}
}

sub revenge_action {
	my ($self, $target, $chan ) = @_;
	my $pacing = $self->pacing;

	$self->pacing(0);
	printf "Revenging to %s on %s\n", $target, $chan;

	switch (lc $config->{"Revenge"}) {
		case "deop"		{ $self->mode($chan, "-o", $target); }
		case "kick"		{ $self->kick($chan, $target, "You bastard"); }
		case "none"		{; }
		else			{ print "Wow, uknown revenge action"; }
	}
	$self->pacing($pacing);
	if (is_protected($target, $chan)) {
		unprotect($target, $chan);
	}
}

sub ignore {
	my ($self, $target) = @_;

	if ($target !~ /.*[!].*[*].*[@].*/) {
		return 0;
	} else {
		push @ignore, $target;
		$self->ignore("all", $target);
		return 1;
	}
}

sub unignore {
	my ($self, $target) = @_;

	if (defined $ignore[$target]) {
		printf "unignoring %s\n", $ignore[$target];
		$self->unignore("all", splice @ignore, $target, 1);
		return 1;
	} else {
		return 0;
	}
}

sub channel_join {
	my ($self, $target) = @_;

	foreach my $channel (split(/:/, $target)) {
		$self->join($channel);
		$self->who($channel);
		push @channels, $channel;
	}

	print "Joined $target\n";
}

sub protect_part {
	my ($target) = @_;

	foreach my $nick (keys %protect) {
		my $person = $protect{$nick};
		my $hostmask = $person->{"Hostmask"};

		foreach my $chan (@{ $person->{"Channels"} }) {
			if (! want_protection($hostmask, $chan)) {
				unprotect($hostmask, $chan);
			}
		}
	}
}

sub on_part {
	my ($self, $event) = @_;
	my $chan = ${$event->to}[0];

	db_update($chan, $event->from =~ /^([^!]+)/, "part", join(' ', ($event->args)));
	if (is_protected($event->from, $chan)) {
		unprotect($event->from, $chan);
	}
}

sub on_quit {
	my ($self, $event) = @_;

	db_update("", $event->from =~ /^([^!]+)/, "quit", join(' ', ($event->args)));

	foreach my $chan (@channels) {
		if (is_protected($event->from, $chan)) {
			unprotect($event->from, $chan);
		}
	}
}

sub protlist {
	my @response;

	foreach my $nick (keys %protect) {
		my $person = $protect{$nick};

		push @response, $person->{"Hostmask"} . ":" . join(" ", @{ $person->{"Channels"} });
	}

	return @response;
}

sub is_protected {
	my ($nick, $chan) = @_;

	$nick =~ s/!.*$//;

	return 0 unless defined $protect{$nick};
	foreach (@{ $protect{$nick}->{"Channels"} }) {
		return 1 if $_ eq $chan;
	}
	return 0;
}

sub format_time {
	use integer;

	my $t = shift;
	my $r = "ouch, can't format that time";

	if ($t >= 0) {
		$r = sprintf "%i seconds", $t % 60;
		$t /= 60;
	} 
	if ($t > 0) {
		$r = sprintf "%i minutes, %s", $t % 60, $r;
		$t /= 60;
	}
	if ($t > 0) {
		$r = sprintf "%i hours, %s", $t % 24, $r;
		$t /= 24;
	}
	if ($t > 0) {
		$r = sprintf "%i days, %s", $t, $r;
	}

	return $r;
}

1;
