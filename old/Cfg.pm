package Cfg;
use strict;
use warnings;

sub config { +{
	Server => "irc.gts.cz",
	Port => "6667",
	Channels => "#programatori:#ostrava:#morava:#l4m3r5:#daimonin:#futurama.sk", # Multiple channels may be separated by ':'
	Nick => "Papalala",
	Ircname => "lalapapa",
	Pacing => "2",	# delay between commands send to the server (anti-flood, 0 will send commands instantly)
	Password => "qwe789",	# admin password
	MaxLineLen => 160,		# max-length of message

	SaveTick => 120,		# how often save the brain (in minutes)
	KickTick => 60,			# how often try to rejoin to kickedout channels (in minutes)

	Ignore => [], #'*!*bot@master.czau.net', '*!*nyoxi@leeloo.ya.bofh.cz'],	# other bots and idiots to ignore
	Protect => qr/^\S+!
		(?:.*anydot\@isit\.cz:.+)						   |
		(?:.*bot\@master\.czau\.net:\#(?:programatori|futurama\.sk))   |
		(?:.*ShadoW\@master\.czau\.net:\#futurama\.sk) |
		(?:.*nyoxi\@leeloo\.ya\.bofh\.cz:\#programatori) |
		(?:.*irc\@62\.240\.171\.139:\#programatori)	   |
		(?:.*irc\@smtp\.ketnet\.cz:\#programatori)		|
		(?::)$/x, # regexp to match protected for, format is $nick!$username@$hostname:$channel
	Revenge => "kick",		# kick or deop or none
	DB => "papalala.db",
	Megahal => 1,
    BotCalcNick => "dev_null",
    BotCalcChan => "#programatori",
	BotCalcAllowed => qr/#(?:programatori|daimonin:prmsharepoint)$/,
}}

1;

