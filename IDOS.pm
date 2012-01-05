package IDOS::RouteQuery;

# This class handles IDOS route queries.
# API: http://www.chaps.cz/idos-moznost-vyuziti-odkazu.asp

use Moose;
use Moose::Util::TypeConstraints;

subtype 'Region' => as 'Str' => where { /^[a-z]+$/; };
subtype 'Time' => as 'Str' => where { /^\d\d?:\d\d?$/; };

has 'region' => (is => 'rw', isa => 'Region', required => 1);
has 'origin' => (is => 'rw', isa => 'Str', required => 1);
has 'dest' => (is => 'rw', isa => 'Str', required => 1);
has 'thru' => (is => 'rw', isa => 'Str');
has 'later' => (is => 'rw', isa => 'Num', default => 0); # number of minutes after now

sub execute {
	my $self = shift;

	my @routes;

	my %qpar = (f => $self->origin(), t => $self->dest(), v => $self->thru());
	if ($self->later() > 0) {
		my @t0 = localtime(time);
		my @t1 = localtime(time + $self->later() * 60);
		$qpar{date} = sprintf('%d.%d.%04d', $t1[3], $t1[4] + 1, $t1[5] + 1900);
		$qpar{time} = sprintf('%d:%02d', $t1[2], $t1[1]);
	}
	my @qpar = map {
		my $val = $qpar{$_};
		if (defined $val) {
			$val =~ s#/\?&=##g; ("$_=$val")
		}
	} keys %qpar;
	my $uri = "http://www.idos.cz/".$self->region()."/?".join('&', 'af=true', @qpar, 'submit=1');

	use LWP::UserAgent;
	use HTTP::Request;

	my $ua = LWP::UserAgent->new(env_proxy => 1, keep_alive => 1, timeout => 10);
	my $request = HTTP::Request->new('GET', $uri);
	my $response = $ua->request($request);
	$response->is_success or die "Cannot get $uri";
	my @data = split(/\n/, $response->decoded_content(charset=>'utf8'));
	# print "ook? @data\n";
	until (not $#data or $data[0] =~ /<!-- zobrazeni vysledku start -->/) {
		shift @data;
	}

	my ($starttime, $startdate, $tottime, $totdist, $totcost, $detail, @places);
	until (not $#data or $data[0] =~ /<!-- zobrazeni vysledku end -->/) {
		if ($data[0] =~ /.*<th class="time.*?>(.*?)<.*/) {
			$starttime = $1;

		} elsif ($data[0] =~ /<p>Celkov. .as </) {
			($tottime, $totdist, $totcost) = ($data[0] =~ m#<p>Celkov. .as <strong>(.*?)</strong>(?:, vzd.lenost <strong>(.*?)</strong>)?(?:, cena <strong>(.*?)</strong>)?#);
			$data[0] =~ m#<a href="(/detail/.*?)"#;
			$detail = "http://jizdnirady.idnes.cz" . $1;

		} elsif ($data[0] =~ /<td class="(check|empty)/) {
			my $cl = $1;
			$data[0] =~ s#</td>##g;
			my ($nfield) = ($data[0] =~ m#<td class="note">#);
			my (@data) = split(/\s*<td.*?>\s*/, $data[0]);
			shift @data; # drop anything before first <td>
			for (@data) {
				s/<.*?[^ >]>//g; s/&nbsp;/ /g; s/\s+/ /g; s/^\s*//; s/\s*$//; s/^>$//;
			}
			if ($cl eq 'check') {
				$startdate = $data[1];
			}
			my $note; $note = splice(@data, 5, 1) if $nfield;
			push @places, {
				place => $data[2],
				arrival => $data[3],
				departure => $data[4],
				note => $note,
				line => $data[6]
			};

		} elsif ($data[0] =~ /^<\/table>/) {
			my @conns = map {
				my ($d, $a) = ($places[$_]->{departure}, $places[$_+1]->{arrival});
				if ($places[$_]->{line} =~ /esun/) {
					($d, $a) = ($places[$_]->{arrival}, $places[$_+1]->{departure});
				}
				$places[$_]->{line} ||= 'wtf';
				my %r = (
					'start' => $d, 'origin' => $places[$_]->{place},
					'stop' => $a, 'dest' => $places[$_+1]->{place},
					'by' => $places[$_]->{line}
				);
				defined $places[$_]->{note} and $r{note} = $places[$_]->{note};
				IDOS::Connection->new(%r);
			} 0..($#places - 1);

			my %r = (
				'time' => $starttime, 'date' => $startdate,
				'traveltime' => $tottime, 'detail' => $detail,
			);
			defined $totcost and $r{'traveldist'} = $totdist;
			defined $totcost and $r{'cost'} = $totcost;
			push @routes, IDOS::Route->new(%r, 'connections' => \@conns);

			@places = ();
		}

	} continue {
		shift @data;
	}

	return @routes;
}

1;

package IDOS::Route;

# This class represents single route through the map, composed of several connections.

use Moose;

has 'time' => (is => 'rw', isa => 'Str', required => 1);
has 'date' => (is => 'rw', isa => 'Str', required => 1);
has 'traveltime' => (is => 'rw', isa => 'Str');
has 'traveldist' => (is => 'rw', isa => 'Str');
has 'cost' => (is => 'rw', isa => 'Str');
has 'connections' => (is => 'rw', isa => 'ArrayRef[IDOS::Connection]', required => 1);
has 'detail' => (is => 'rw', isa => 'Str');

1;

package IDOS::Connection;

# This class represents single route through the map, composed of several connections.

use Moose;

has 'start' => (is => 'rw', isa => 'Time', required => 1);
has 'stop' => (is => 'rw', isa => 'Time', required => 1);
has 'origin' => (is => 'rw', isa => 'Str', required => 1);
has 'dest' => (is => 'rw', isa => 'Str', required => 1);
has 'by' => (is => 'rw', isa => 'Str', required => 1);
has 'note' => (is => 'rw', isa => 'Str');

1;
