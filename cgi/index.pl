#!/usr/bin/env perl
use Mojolicious::Lite;
use Cache::File;

use DateTime;
use DateTime::Format::Strptime;
use List::MoreUtils qw(any);

use App::VRR::Fakedisplay;
use Travel::Status::DE::DeutscheBahn;
use Travel::Status::DE::VRR;

no warnings 'uninitialized';
no if $] >= 5.018, warnings => "experimental::smartmatch";

our $VERSION = qx{git describe --dirty} || '0.06';

my %default = (
	backend  => 'vrr',
	line     => q{},
	no_lines => 5,
	offset   => q{},
	platform => q{},
);

sub get_results {
	my ( $backend, $city, $stop, $expiry ) = @_;

	$expiry ||= 150;

	my $cache = Cache::File->new(
		cache_root      => '/tmp/vrr-fake',
		default_expires => "${expiry} sec",
	);

	my $sstr = ("${backend} _ ${stop} _ ${city}");
	$sstr =~ tr{a-zA-Z0-9}{_}c;

	my $results = $cache->thaw($sstr);

	if ( not $results ) {
		my $status;
		if ( $backend eq 'db' ) {
			$status = Travel::Status::DE::DeutscheBahn->new(
				station => "${stop}, ${city}",
				mot     => {
					ice   => 0,
					ic_ec => 0,
					d     => 0,
					nv    => 0,
					s     => 1,
					bus   => 1,
					u     => 1,
					tram  => 1,
				},
			);
		}
		else {
			$status = Travel::Status::DE::VRR->new(
				place => $city,
				name  => $stop
			);
		}
		$results = [ [ $status->results ], $status->errstr ];
		$cache->freeze( $sstr, $results );
	}

	return @{$results};
}

sub handle_request {
	my $self = shift;
	my $city = $self->stash('city');
	my $stop = $self->stash('stop');

	my $no_lines = $self->param('no_lines');
	my $frontend = $self->param('frontend') // 'png';

	if ( not $no_lines or $no_lines < 1 or $no_lines > 10 ) {
		$no_lines = $default{no_lines};
	}

	$self->stash( title   => 'vrr-fakedisplay' );
	$self->stash( version => $VERSION );

	$self->stash( params => $self->req->params->to_string );
	$self->stash( height => $no_lines * 10 );
	$self->stash( width  => 180 );

	$self->render(
		'main',
		city     => $city,
		stop     => $stop,
		version  => $VERSION,
		frontend => $frontend,
		title    => $city
		? "departures for ${city} ${stop}"
		: "vrr-fakedisplay ${VERSION}",
	);

	return;
}

sub shorten_line {
	my ($line) = @_;

	$line =~ s{ \s* S-Bahn }{}ox;

	$line =~ s{ ^ ( U | S | SB ) \K \s+ }{}ox;
	$line =~ s{ ^ ( STR | Bus | RNV ) }{}ox;

	$line =~ s{ ^ \s+ }{}ox;

	return $line;
}

sub shorten_destination {
	my ( $backend, $dest, $city ) = @_;

	if ( $backend eq 'db' ) {
		$city =~ s{ \s* [(] [^)]+ [)] $ }{}ox;
		$dest =~ s{ \s* [(] [^)]+ [)] $ }{}ox;
		$dest =~ s{ ^ (.+) , \s+ (.+) $ }{$2 $1}ox;
	}

	if ( not( $dest =~ m{ Hbf $ }ix ) ) {
		$dest =~ s{ ^ $city \s }{}ix;
	}

	if ( length($dest) > 20 ) {
		     $dest =~ s{^Dortmund}{DO}
		  or $dest =~ s{^Duisburg}{DU}
		  or $dest =~ s{^Düsseldorf}{D}
		  or $dest =~ s{^Essen}{E}
		  or $dest =~ s{^Gelsenkirchen}{GE}
		  or $dest =~ s{^Mülheim}{MH};
	}

	$dest = substr( $dest, 0, 20 );

	return $dest;
}

sub get_departures {
	my (%opt) = @_;

	my ( @grep_line, @grep_platform );
	my $no_lines  = $opt{no_lines}  // $default{no_lines};
	my $max_lines = $opt{max_lines} // 10;
	my $offset    = $opt{offset}    // 0;
	my $displayed_lines = 0;
	my $want_crop       = 0;
	my @fmt_departures;

	my ( $results, $errstr )
	  = get_results( $opt{backend}, $opt{city}, $opt{stop},
		$opt{cache_expiry} );

	my $dt_now = DateTime->now( time_zone => 'Europe/Berlin' );
	my $strp_simple = DateTime::Format::Strptime->new(
		pattern   => '%H:%M',
		time_zone => 'floating',
	);
	my $strp_full = DateTime::Format::Strptime->new(
		pattern   => '%d.%m.%Y %H:%M',
		time_zone => 'floating',
	);

	if ( $opt{filter_line} ) {
		my @lines = split( qr{,}, $opt{filter_line} );
		@grep_line = map { qr{ ^ \Q$_\E }ix } @lines;
	}
	if ( $opt{filter_platform} ) {
		@grep_platform = split( qr{,}, $opt{filter_platform} );
	}

	if ( $no_lines < 1 or $no_lines > $max_lines ) {
		if ( $no_lines >= -$max_lines and $no_lines <= -1 ) {
			$want_crop = 1;
			$no_lines *= -1;
		}
		else {
			$no_lines = $default{no_lines};
		}
	}

	for my $d ( @{$results} ) {

		my $line        = $d->line;
		my $platform    = ( split( qr{ }, $d->platform ) )[-1];
		my $destination = $d->destination;
		my $time        = $d->time;
		my $etr;

		my $dt_dep = $strp_full->parse_datetime($time)
		  // $strp_simple->parse_datetime($time);
		my $dt;

		if (   ( @grep_line and not( any { $line =~ $_ } @grep_line ) )
			or ( @grep_platform and not( $platform ~~ \@grep_platform ) )
			or ( $line =~ m{ ^ (RB | RE | IC | EC) }x )
			or ( $displayed_lines >= $no_lines ) )
		{
			next;
		}

		if ( $d->delay eq '-9999' ) {

			# canceled
			next;
		}

		if ( $time =~ m{ ^ \d\d? : \d\d $ }x ) {
			$dt = DateTime->new(
				year      => $dt_now->year,
				month     => $dt_now->month,
				day       => $dt_now->day,
				hour      => $dt_dep->hour,
				minute    => $dt_dep->minute,
				second    => $dt_dep->second,
				time_zone => 'Europe/Berlin',
			);
		}
		else {
			$dt = $dt_dep;
		}

		my $duration = $dt->subtract_datetime($dt_now);

		if ( $duration->is_negative
			or ( $duration->in_units('minutes') < $offset ) )
		{
			next;
		}
		elsif ( $duration->in_units('minutes') == 0 ) {
			$etr = 'sofort';
		}
		elsif ( $duration->in_units('hours') == 0 ) {
			$etr = $duration->in_units('minutes');
		}
		else {
			last;
		}

		$destination
		  = shorten_destination( $opt{backend}, $destination, $opt{city} );
		$line = shorten_line($line);

		$displayed_lines++;

		push( @fmt_departures, [ $line, $destination, $etr, $d ] );
	}

	if ( not $want_crop ) {
		while ( $displayed_lines++ < $no_lines ) {
			push( @fmt_departures, [ (q{}) x 3 ] );
		}
	}

	return ( \@fmt_departures, $errstr );
}

sub render_html {
	my $self = shift;
	my $color = $self->param('color') || '255,208,0';

	my ( $departures, $errstr ) = get_departures(
		city            => $self->stash('city'),
		stop            => $self->stash('stop'),
		no_lines        => scalar $self->param('no_lines'),
		backend         => scalar $self->param('backend'),
		filter_line     => scalar $self->param('line'),
		filter_platform => scalar $self->param('platform'),
		offset          => scalar $self->param('offset'),
	);

	for my $d ( @{$departures} ) {
		if ( $d->[2] and $d->[2] ne 'sofort' ) {
			$d->[2] .= ' min';
		}
	}

	$self->render(
		'display',
		title      => "vrr-fakedisplay v${VERSION}",
		color      => [ split( qr{,}, $color ) ],
		departures => $departures,
		scale      => $self->param('scale') || '4.3',
	);

	return;
}

sub render_json {
	my $self = shift;

	my ( $departures, $errstr ) = get_departures(
		city            => $self->stash('city'),
		stop            => $self->stash('stop'),
		no_lines        => scalar $self->param('no_lines') // '-100',
		max_lines       => 100,
		backend         => scalar $self->param('backend'),
		filter_line     => scalar $self->param('line'),
		filter_platform => scalar $self->param('platform'),
		offset          => scalar $self->param('offset'),
		cache_expiry    => 60,
	);

	for my $d ( @{$departures} ) {
		if ( $d->[2] and $d->[2] ne 'sofort' ) {
			$d->[2] .= ' min';
		}
	}

	my @preformatted = map { [ $_->[0], $_->[1], $_->[2] ] } @{$departures};
	my @raw_objects = map { $_->[3] } @{$departures};

	$self->render(
		json => {
			error        => $errstr,
			preformatted => \@preformatted,
			raw          => \@raw_objects,
			version      => $VERSION,
		}
	);

	return;
}

sub render_image {
	my $self = shift;

	my $color = $self->param('color') || '255,208,0';
	my $scale = $self->param('scale');

	my ( $departures, $errstr ) = get_departures(
		city            => $self->stash('city'),
		stop            => $self->stash('stop'),
		no_lines        => scalar $self->param('no_lines'),
		backend         => scalar $self->param('backend'),
		filter_line     => scalar $self->param('line'),
		filter_platform => scalar $self->param('platform'),
		offset          => scalar $self->param('offset'),
	);

	if ( $scale > 30 ) {
		$scale = 30;
	}

	if ($errstr) {
		$color = '255,0,0';
	}

	my $png = App::VRR::Fakedisplay->new(
		width  => 180,
		height => @{$departures} * 10,
		color  => [ split( qr{,}, $color ) ],
		scale  => $scale,
	);

	if ($errstr) {
		$png->draw_at( 6, '--------backend error--------' );
		$png->new_line();
		$png->new_line();
		$png->draw_at( 0, $errstr );
	}

	$self->res->headers->content_type('image/png');
	for my $d ( @{$departures} ) {

		my ( $line, $destination, $etr, undef ) = @{$d};

		$png->draw_at( 0,  $line );
		$png->draw_at( 25, $destination );

		if ( length($etr) > 2 ) {
			$png->draw_at( 145, $etr );
		}
		elsif ( length($etr) > 1 ) {
			$png->draw_at( 148, $etr );
		}
		else {
			$png->draw_at( 154, $etr );
		}

		if ( $etr and $etr ne 'sofort' ) {
			$png->draw_at( 161, 'min' );
		}

		$png->new_line();
	}
	if ( @{$departures} == 0 ) {
		$png->new_line();
		$png->new_line();
		$png->draw_at( 50, 'no departures' );
	}

	$self->render( data => $png->png );

	return;
}

get '/_redirect' => sub {
	my $self = shift;
	my $city = $self->param('city');
	my $stop = $self->param('stop');

	my $params = $self->req->params;

	$params->remove('city');
	$params->remove('stop');

	for my $param (qw(line platform offset no_lines backend)) {
		if ( not $params->param($param)
			or ( $params->param($param) eq $default{$param} ) )
		{
			$params->remove($param);
		}
	}

	my $params_s = $params->to_string;

	$self->redirect_to("/${city}/${stop}?${params_s}");

	return;
};

get '/'                 => \&handle_request;
get '/:city/:stop.html' => \&render_html;
get '/:city/:stop.json' => \&render_json;
get '/:city/:stop.png'  => \&render_image;
get '/:city/:stop'      => \&handle_request;

app->config(
	hypnotoad => {
		listen   => ['http://*:8091'],
		pid_file => '/tmp/vrr-fake.pid',
		workers  => 2,
	},
);

app->types->type( json => 'application/json; charset=utf-8' );
app->start();
