#!/usr/bin/perl
# Copyright 2009-2012, 2014: Olof Johansson <olof@ethup.se>
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

use strict;
use Irssi;
use LWP::UserAgent;
use XML::Simple;
use HTML::Entities;
use URI;
use URI::QueryParam;
use Regexp::Common qw/URI/;

my $VERSION = '0.71';

my %IRSSI = (
	authors     => 'Olof "zibri" Johansson',
	contact     => 'olof@ethup.se',
	name        => 'youtube-title',
	uri         => 'https://github.com/olof/irssi-youtube-title',
	description => 'prints the title of a youtube video automatically',
	license     => 'GNU APL',
);

# Changelog is now available as a separate file (./Changes). If you
# don't have it, you can find it on github.
Irssi::settings_add_bool('youtube_title', 'yt_print_own', 0);

sub callback {
	my($server, $msg, $nick, $address, $target) = @_;
	$target=$nick if $target eq undef;

	# process each youtube link in message
	process($server, $target, $_) for (get_ids($msg));
}

sub own_callback {
	my($server, $msg, $target) = @_;

	if(Irssi::settings_get_bool('yt_print_own')) {
		callback($server, $msg, undef, undef, $target);
	}
}

sub process {
	my ($server, $target, $id) = @_;
	my $yt = get_title($id);

	if(exists $yt->{error}) {
		print_error($server, $target, $id, $yt->{error});
	} else {
		print_title($server, $target, $id, $yt->{title}, $yt->{duration});
	}
}

sub canon_domain {
	my $domain = normalize_domain(shift);

	{
		'youtube.com' => 'youtube.com',
		'youtu.be' => 'youtu.be',
	}->{$domain};
}

sub normalize_domain {
	my $domain = shift;
	$domain =~ s/^www\.//;
	return $domain;
}

sub idextr_youtube_com {
	my $u = URI->new(shift);
	return $u->query_param('v') if $u->path eq '/watch';
}

sub idextr_youtu_be { (URI->new(shift)->path =~ m;/(.*);)[0] }

sub id_from_uri {
	my $uri = URI->new(shift);
	my $domain = canon_domain($uri->host);

	my %domains = (
		'youtube.com' => \&idextr_youtube_com,
		'youtu.be' => \&idextr_youtu_be,
	);

	return $domains{$domain}->($uri) if ref $domains{$domain} eq 'CODE';
	# TODO warn somehow if you reach this point and $domains{$domain}?
}

sub get_ids {
	my $msg = shift;
	my $re_uri = qr#$RE{URI}{HTTP}{-scheme=>'https?'}#;
	my @ids;

	foreach($msg =~ /$re_uri/g) {
		my $id = id_from_uri($_);
		next unless $id;

		$id =~ s/[^\w-].*//;
		push @ids, $id;
	}

	return @ids;
}

# Extract title by scraping. This isn't ideal, but since youtube decided to
# deprecate their xml based api v2.0, in favor for something requiring
# registration to even do simple things like fetching metadata info, it
# seems to be the only viable option.
#
# So scraping it is. Thanks youtube.
sub get_title {
	my($vid)=@_;

	my $url = "http://youtube.com/watch?v=$vid";
	#my $url = "http://gdata.youtube.com/feeds/api/videos/$vid";

	my $ua = LWP::UserAgent->new();
	$ua->agent("$IRSSI{name}/$VERSION (irssi)");
	$ua->timeout(3);
	$ua->env_proxy;

	my $response = $ua->get($url);

	return {error => $response->message} if $response->code != 200;

	my $content = $response->decoded_content;

	my ($title) = $content =~ m{<meta name="title" content="([^"]+)">};
	$title = decode_entities($title);
	my ($durstr) = $content =~
		m{<meta itemprop="duration" content="(PT[^"]+)">};

	my $d = parse_durstr($durstr);

	if($title) {
		return {
			title => $title,
			duration => $d,
		};
	}

	return {error => 'could not find title'};
}

sub parse_durstr {
	my $durstr = shift;

	# PT600M1S = 600 minutes,  1 second
	# PT20M12S =  20 minutes, 12 seconds
	# PT0M36S  =   0 minutes, 36 seconds

	my ($h, $s) = $durstr =~ /^PT([0-9]+)M([0-9]+S)$/;
	return sprintf "%d:%02d", $h, $s;
}

sub print_error {
	my ($server, $target, $id, $msg) = @_;
	$server->send_message($target, "[$id] Error fetching youtube title: $msg", 0);
	#$server->window_item_find($target)->printformat(
	#	MSGLEVEL_CLIENTCRAP, 'yt_error', $msg
	#);
}

sub print_title {
	my ($server, $target, $id, $title, $d) = @_;

	$title = decode_entities($title);
	$d = decode_entities($d);

	$server->send_message($target, "[$id] $title ($d)", 0);
	#$server->window_item_find($target)->printformat(
	#	MSGLEVEL_CLIENTCRAP, 'yt_ok', $title, $d
	#);
}

Irssi::theme_register([
	'yt_ok', '%yyoutube:%n $0 ($1)',
	'yt_error', '%rError fetching youtube title:%n $0',
]);

Irssi::signal_add("message public", \&callback);
Irssi::signal_add("message private", \&callback);

Irssi::signal_add("message own_public", \&own_callback);
Irssi::signal_add("message own_private", \&own_callback);
