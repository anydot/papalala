use strict;
use warnings;

=begin TODO

=cut

use Irssi;
use Irssi::Irc;
use GDBM_File;
use Digest::SHA1 qw(sha1);
use Data::Dumper;

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
	authors => "Premysl 'Anydot' Hruby",
	contact => "dfenze\@gmail.com",
	name => "duperator",
	description => "user who post dupe message is punished",
);

tie our %dupe_db, "GDBM_File", Irssi::get_irssi_dir(). "/duperator_dupe.db", &GDBM_WRCREAT, 0644; # sha1("$channel:$message") => time of insert
tie our %user_db, "GDBM_File", Irssi::get_irssi_dir(). "/duperator_user.db", &GDBM_WRCREAT, 0644; # "$channel:$hostmask" => "punishexp:punished_until"

our %voice_timers;

sub is_dupe {
	my ($channel, $message) = @_;
	my $hash;

	# strip away junk
	$channel = lc $channel;
	
    # remove case
    $message = lc $message;

    # remove addressing nicks:
    $message =~ s/^\w+: ?//;

    # remove control chars
    $message =~ s/[[:cntrl:]]//g;

    # remove smilies
    $message =~ s/(?:^|\s)(?:[[:punct:]]+\w|[[:punct:]]+\w|[[:punct:]]+\w[[:punct:]]+)(?:\s|$)/ /g;

    # remove punct
    $message =~ s/([a-zA-Z])'([a-zA-Z])/$1$2/g;
    $message =~ s/[^a-zA-Z\d -]+/ /g;

	#remove spaces after/before []{}()"'
	$message =~ s/\s*([\[\]{}\(\)"'])\s*/$1/g;

    # removing leading/trailing/multiple spaces
    $message =~ s/^\s+|\s+$//g;
    $message =~ s/\s+/ /g;
    
	# repeating chars
    $message =~ s/(.+)\1+/$1/g;

	$hash = sha1("$channel:$message");

	if (defined $dupe_db{$hash}) {
		Irssi::print("Dupe found: $message");
		return 1;
	}

	$dupe_db{$hash} = time;

	return 0;
}

sub get_next_punishtime {
	my ($channel, $hostmask) = @_;
	my ($punish_exp, $punish_until, $punish_time);
	my $key = "$channel:$hostmask";

	if (defined($user_db{$key})) {
		($punish_exp, $punish_until) = split /:/, $user_db{$key};
		my $punish_diff = time - $punish_until;

		$punish_exp += Irssi::settings_get_int('bot_duperator_grow');
		
		if ($punish_diff > 0) {
			my $decayt = Irssi::settings_get_int('bot_duperator_decaytime');
			return if $decayt < 1;

			# if it is more than half of decay time from last punishment, decay something
			$punish_exp -= $punish_diff / $decayt
				if $punish_diff >= $decayt / 2;
		}
		if ($punish_exp < Irssi::settings_get_int("bot_duperator_minexp")) {
			$punish_exp = Irssi::settings_get_int("bot_duperator_minexp");
		}
	}
	else {
		$punish_exp = Irssi::settings_get_int("bot_duperator_minexp");
	}

	$punish_time = 2**$punish_exp;
	$punish_until = time + $punish_time;

	$user_db{$key} = "$punish_exp:$punish_until";

	return $punish_time;
}

sub remove_punishment {
	my ($server, $channel, $nick) = @{$_[0]}; # dereference data arrayref

	if (exists($voice_timers{"$channel:$nick"})) {
		$server->send_raw("MODE $channel +v $nick");
		remove_timer($channel, $nick);
	}
	else {
		Irssi::print("ouch, duplicate timer?");
	}
}

sub on_public {
	my ($server, $message, $nick, $hostmask, $channel) = @_;
	my $ignore_regexp = Irssi::settings_get_str('bot_duperator_ignore_regexp');

	return unless grep {/$channel/i} split(/ /, Irssi::settings_get_str('bot_duperator_channels'));
	return if grep {lc eq lc $nick/} split(/ /, Irssi::settings_get_str('bot_duperator_ignore'));

	if ($ignore_regexp ne '') {
		return if $message =~ /^$ignore_regexp$/ix;
	}

	return unless is_dupe($channel, $message);

	## this is dupe, so punish the user
	my $ptime = get_next_punishtime($channel, $hostmask);
	my $ptime_txt = format_time($ptime);
	my $time_key = "$channel:$nick";

	if (exists $voice_timers{$time_key}) {
		## do nothing == prevents large punish time in case user write multiple dupes before is devoiced
	}
	else {
		$server->send_raw("MODE $channel -v $nick");
#		$server->send_raw("PRIVMSG $channel :$nick: You sent duplicate message, now you are muted for $ptime_txt");
		$server->send_raw("NOTICE $nick :You sent duplicate message, now you are muted for $ptime_txt");
		add_remove_punishment($ptime, $server, $channel, $nick);
	}
}

sub on_nick_modechange {
	my ($channel, $nick, $setby, $mode, $type) = @_;
	my ($chname, $nname) = ($channel->{name}, $nick->{nick});

	return unless grep {/$chname/i} split(/ /, Irssi::settings_get_str('bot_duperator_channels'));
	return if grep {/$nname/i} split(/ /, Irssi::settings_get_str('bot_duperator_ignore'));
	
	if ($nick eq $channel->{ownnick}->{nick}) {
		return unless $mode eq '@'; # we are interested only in op
		if ($type eq '-') {
			# clear timers
			foreach ($channel->nicks()) {
				remove_timer($channel->{name}, $_);
			}
		}
		else {
			Irssi::print("Someone opped us, forcing maintenance");
			maintenance();
		}
	}
	elsif ($setby ne $channel->{ownnick}->{nick}) {
		my ($ptime, $ptime_txt);
		my $hostmask = $nick->{host};
		
		# someone (not us) changed mode, let's look on this
		return unless $channel->{ownnick}->{op}; ## we are not operator
		return unless $mode eq '+';
		return unless $type eq '-';
		return if exists $voice_timers{"$chname:$nname"}; ## already punished

		get_next_punishtime($chname, $hostmask);
		$ptime = get_next_punishtime($chname, $hostmask); ## double punishment
		$ptime_txt = format_time($ptime);

#		$channel->{server}->send_raw("PRIVMSG $chname :$nname: Cheater! Now you are muted for $ptime_txt");
		$channel->{server}->send_raw("NOTICE $nname :Cheater! Now you are muted for $ptime_txt");
		add_remove_punishment($ptime, $channel->{server}, $chname, $nname);
	}
}			

sub on_ctcp_action {
	return on_public(@_)
}

sub on_notice {
	return on_public(@_);
}

sub check_nick {
	my ($server, $chname, $nick) = @_;
	my $nname = $nick->{nick};
	my $key = $chname .":". $nick->{host};
	my $timekey = "$chname:$nname";
	my $punish_until = 0;

	return unless grep {/$chname/i} split(/ /, Irssi::settings_get_str('bot_duperator_channels'));

	if (defined($user_db{$key})) {
		(undef, $punish_until) = split(/:/, $user_db{$key});
	}

	if ($punish_until > time) {
		$server->send_raw("MODE $chname -v $nname")
			if $nick->{voice};
		add_remove_punishment($punish_until - time, $server, $chname, $nname);
	}
	else {
		$server->send_raw("MODE $chname +v $nname")
			unless $nick->{voice};
	}
}

sub on_massjoin {
	my ($channel, $nicks) = @_;
	my ($server, $chname) = ($channel->{server}, $channel->{name});

	foreach my $nick (@$nicks) {
		check_nick($server, $chname, $nick);
	}
}

sub maintenance {
	foreach my $channel (Irssi::channels) {
		my ($chname, $server) = ($channel->{name}, $channel->{server});

		next unless grep {/$chname/i} split(/ /, Irssi::settings_get_str('bot_duperator_channels'));
		
		$server->send_raw("MODE $chname +m")
			unless $channel->{mode} =~ /m/;

		foreach my $nick ($channel->nicks) {
			check_nick($server, $chname, $nick);
		}
	}
}

sub on_quit {
	my ($server, $nick, $hostmask, $reason) = @_;

	foreach my $channel (split(/ /, Irssi::settings_get_str('bot_duperator_channels'))) {
		remove_timer($channel, $nick);
	}
}

sub on_part {
	my ($server, $channel, $nick, $hostmask, $reason) = @_;

	remove_timer($channel, $nick);
}

sub on_kick {
	my ($server, $channel, $nick, $kicker, $hostmask, $reason) = @_;

	remove_timer($channel, $nick);
}

sub on_nick {
	my ($server, $newnick, $oldnick, $hostmask) = @_;
	my $punish_until;

	foreach my $channel (split(/ /, Irssi::settings_get_str('bot_duperator_channels'))) {
		next unless defined $user_db{"$channel:$hostmask"};
		(undef, $punish_until) = split(/:/, $user_db{"$channel:$hostmask"});

		if($punish_until >= time) {
			add_remove_punishment($punish_until - time, $server, $channel, $newnick);
		}
			
		remove_timer($channel, $oldnick);
	}
}

sub add_remove_punishment {
	my ($time, $server, $channel, $nick) = @_;

	if ($time < 1) {
		remove_punishment([$server, $channel, $nick]);
	}
	else {
		remove_timer($channel, $nick);
		$voice_timers{"$channel:$nick"} = Irssi::timeout_add_once(1000*$time, \&remove_punishment, [$server, $channel, $nick]);
	}
}

sub remove_timer {
	my ($channel, $nick) = @_;
	my $key = "$channel:$nick";

	Irssi::timeout_remove($voice_timers{$key})
		if defined $voice_timers{$key};
		
	delete $voice_timers{$key};
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

sub cmd_duperator {
	my ($data, $server, $witem) = @_;

	Irssi::print("Duperator: doing maintenance run");

	maintenance();
}

Irssi::timeout_add(1000*300, \&maintenance, undef); ## maintenance check every 5mins
Irssi::timeout_add_once(1000*10, \&maintenance, undef); ## first maintenance after 10sec

Irssi::signal_add('message public', \&on_public);
Irssi::signal_add('massjoin', \&on_massjoin);
Irssi::signal_add('ctcp action', \&on_ctcp_action);

Irssi::signal_add('message irc notice', \&on_notice);
Irssi::signal_add('message quit', \&on_quit);
Irssi::signal_add('message part', \&on_part);
Irssi::signal_add('message kick', \&on_kick);
Irssi::signal_add('message nick', \&on_nick);
Irssi::signal_add('nick mode changed', \&on_nick_modechange);

Irssi::command_bind('duperator', \&cmd_duperator);

Irssi::settings_add_str('bot', 'bot_duperator_ignore', '');
Irssi::settings_add_str('bot', 'bot_duperator_channels', '');
Irssi::settings_add_int('bot', 'bot_duperator_minexp', 2);
Irssi::settings_add_int('bot', 'bot_duperator_decaytime', 3600*6); ## decay after 6 hours without punishment
Irssi::settings_add_int('bot', 'bot_duperator_grow', 1); ## how much will grow exponent after punishment
Irssi::settings_add_str('bot', 'bot_duperator_ignore_regexp', ''); ## regexp for message to ignore
