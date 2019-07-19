#!/usr/bin/env perl
use Mojolicious::Lite;
use Cache::File;
use utf8;

use DateTime;
use DateTime::Format::Strptime;
use File::Slurp qw(read_file write_file);
use List::Util qw(first);
use List::MoreUtils qw();

use App::VRR::Fakedisplay;
use Travel::Status::DE::HAFAS;
use Travel::Status::DE::ASEAG;
use Travel::Status::DE::EFA;

no warnings 'uninitialized';
no if $] >= 5.018, warnings => "experimental::smartmatch";

our $VERSION = qx{git describe --dirty} || '0.07';
chomp $VERSION;

my %default = (
	backend  => 'vrr',
	line     => q{},
	no_lines => 5,
	offset   => q{},
	platform => q{},
);

my @efa_services
  = map { $_->{shortname} } Travel::Status::DE::EFA::get_efa_urls();

my @hafas_services
  = map { $_->{shortname} } Travel::Status::DE::HAFAS::get_services();

sub log_api_access {
	my $counter = 1;
	if ( -r $ENV{VRRFAKEDISPLAY_STATS} ) {
		$counter = read_file( $ENV{VRRFAKEDISPLAY_STATS} ) + 1;
	}
	write_file( $ENV{VRRFAKEDISPLAY_STATS}, $counter );
}

sub get_results {
	my ( $backend, $city, $stop ) = @_;
	my $sub_backend;

	my $expiry = 200;

	# legacy values
	if ( not defined $backend or $backend eq 'vrr' ) {
		$backend = 'efa.VRR';
	}
	if ( $backend and $backend eq 'db' ) {
		$backend = 'hafas.DB';
	}

	if ( $backend =~ s{ [.] (.+) $ }{}x ) {
		$sub_backend = $1;

		if ( $backend eq 'efa' and not $sub_backend ~~ \@efa_services ) {
			return {
				results => [],
				errstr  => "efa sub-backend '$sub_backend' not supported"
			};
		}
		if ( $backend eq 'hafas' and not $sub_backend ~~ \@hafas_services ) {
			return {
				results => [],
				errstr  => "hafas sub-backend '$sub_backend' not supported"
			};
		}
	}

	if ( $backend eq 'hafas' ) {
		$expiry = 120;
	}
	elsif ( $backend eq 'aseag' ) {
		$expiry = 120;
	}

	my $cache = Cache::File->new(
		cache_root      => $ENV{VRRFAKEDISPLAY_CACHE} // '/tmp/vrr-fakedisplay',
		default_expires => "${expiry} sec",
		lock_level      => Cache::File::LOCK_LOCAL(),
	);

	my $sstr = ("${backend} _ ${stop} _ ${city}");
	$sstr =~ tr{a-zA-Z0-9}{_}c;

	my $data = $cache->thaw($sstr);

	if ( not $data ) {
		if ( $ENV{VRRFAKEDISPLAY_STATS} ) {
			log_api_access();
		}
		my $status;
		if ( $backend eq 'hafas' ) {
			$status = Travel::Status::DE::HAFAS->new(
				station       => ( $city ? "${city} ${stop}" : $stop ),
				excluded_mots => [qw[ice ic_ec d regio]],
				service       => $sub_backend,
			);
		}
		elsif ( $backend eq 'aseag' ) {
			$status = Travel::Status::DE::ASEAG->new(
				stop             => ( $city ? "${city} ${stop}" : $stop ),
				calculate_routes => 1,
			);
		}
		else {
			my $efa_url = 'http://efa.vrr.de/vrr/XSLT_DM_REQUEST';
			if ( not $city ) {
				return { errstr => 'City must be specified for this backend' };
			}
			if ($sub_backend) {
				my $service
				  = first { lc( $_->{shortname} ) eq lc($sub_backend) }
				Travel::Status::DE::EFA::get_efa_urls();
				if ($service) {
					$efa_url = $service->{url};
				}
			}
			$status = Travel::Status::DE::EFA->new(
				efa_url     => $efa_url,
				place       => $city,
				name        => $stop,
				timeout     => 3,
				full_routes => 0,
			);
		}
		if ( not $status->errstr ) {
			$data = {
				results => [ $status->results ],
				errstr  => undef,
			};
		}
		else {
			$data = {
				results => [],
				errstr  => $status->errstr,
			};
		}
		if ( $status->can('identified_data') and not $status->errstr ) {
			( $data->{id_name}, $data->{id_stop} ) = $status->identified_data;
		}
		if ( $status->errstr and $status->can('name_candidates') ) {
			$data->{name_candidates}  = [ $status->name_candidates ];
			$data->{place_candidates} = [ $status->place_candidates ];
		}
		elsif ( $status->errstr
			and $status->can('errcode')
			and $status->errcode eq 'H730' )
		{
			$data->{name_candidates}
			  = [ map { $_->{name} } $status->similar_stops ];
		}
		$cache->freeze( $sstr, $data );
	}

	return $data;
}

sub handle_request {
	my $self = shift;
	my $city = $self->stash('city') // q{};
	my $stop = $self->stash('stop');

	my $no_lines = $self->param('no_lines');
	my $frontend = $self->param('frontend') // 'png';
	my $backend  = $self->param('backend') // $default{backend};
	my $data;

	if ($stop) {
		$data = get_results( $self->param('backend') // $default{backend},
			$city, $stop );
	}

	if ( not $no_lines or $no_lines < 1 or $no_lines > 40 ) {
		$no_lines = $default{no_lines};
	}

	$self->stash( title   => 'vrr-infoscreen' );
	$self->stash( version => $VERSION );

	$self->stash( params => $self->req->params->to_string );
	$self->stash( height => $no_lines * 10 );
	$self->stash( width  => 180 );

	$self->render(
		'main',
		city             => $city,
		stop             => $stop,
		version          => $VERSION,
		frontend         => $frontend,
		errstr           => $data->{errstr},
		name_candidates  => $data->{name_candidates},
		place_candidates => $data->{place_candidates},
		title            => $stop
		? "departures for ${city} ${stop}"
		: "vrr-infoscreen ${VERSION}",
	);

	return;
}

sub shorten_line {
	my ($line) = @_;

	$line =~ s{ \s* S-Bahn }{}ix;

	$line =~ s{ ^ ( U | S | SB ) \K \s+ }{}ix;
	$line =~ s{ ^ ( STR | Bus | RNV | Tram ) }{}ix;

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

	if ( $city =~ m{ ^ ( D | Duesseldorf | Düsseldorf ) $ }ix ) {
		$dest =~ s{ ^ D - }{}ix;
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

sub get_filtered_departures {
	my (%opt) = @_;

	my ( @grep_line, @grep_platform, @filtered_results );

	my $data = get_results( $opt{backend}, $opt{city}, $opt{stop} );

	my $results = $data->{results};

	if ( $opt{filter_line} ) {
		my @lines = split( qr{,[[:space:]]*}, $opt{filter_line} );
		@grep_line = map { qr{ ^ \Q$_\E }ix } @lines;
	}
	if ( $opt{filter_platform} ) {
		@grep_platform = split( qr{,[[:space:]]*}, $opt{filter_platform} );
	}

	for my $d ( @{$results} ) {

		my $line = $d->line;
		my $platform
		  = $d->can('platform')
		  ? ( split( qr{ }, $d->platform ) )[-1]
		  : ( $d->can('stop_indicator') ? $d->stop_indicator : q{} );
		my $destination = $d->destination;
		my $time        = $d->time;
		my $etr;

		# Note: The offset / countdown check does not yet take caching
		# into account, so it may be off by up to cache_expiry seconds.
		if (
			(
				@grep_line
				and not( List::MoreUtils::any { $line =~ $_ } @grep_line )
			)
			or ( @grep_platform and not( $platform ~~ \@grep_platform ) )
			or ( $opt{hide_regional} and $line =~ m{ ^ (RB | RE | IC | EC) }x )
			or ( $opt{offset} and $d->countdown < $opt{offset} )
		  )
		{
			next;
		}

		push( @filtered_results, $d );
	}

	$data->{filtered_results} = \@filtered_results;

	return $data;
}

sub make_infoboard_lines {
	my (%opt) = @_;

	my ( @grep_line, @grep_platform );
	my $no_lines  = $opt{no_lines}  // $default{no_lines};
	my $max_lines = $opt{max_lines} // 40;
	my $offset    = $opt{offset}    // 0;
	my $results   = $opt{data};
	my $displayed_lines = 0;
	my $want_crop       = $opt{want_crop};
	my @fmt_departures;

	my $dt_now      = DateTime->now( time_zone => 'Europe/Berlin' );
	my $strp_simple = DateTime::Format::Strptime->new(
		pattern   => '%H:%M',
		time_zone => 'floating',
	);
	my $strp_full = DateTime::Format::Strptime->new(
		pattern   => '%d.%m.%Y %H:%M',
		time_zone => 'floating',
	);

	if ( $no_lines < 1 or $no_lines > $max_lines ) {
		$no_lines = 40;
	}

	for my $d ( @{$results} ) {

		my $line        = $d->line;
		my $destination = $d->destination;
		my $time        = $d->time;
		my $etr;
		my $dt_dep;
		my $dt;

		if ( $d->can('datetime') ) {
			$dt_dep = $d->datetime;
		}
		else {
			$dt_dep = $strp_full->parse_datetime($time)
			  // $strp_simple->parse_datetime($time);
		}

		if (   ( $displayed_lines >= $no_lines )
			or ( $d->can('is_cancelled') and $d->is_cancelled ) )
		{
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

		push( @fmt_departures, [ $line, $destination, $etr ] );
	}

	if ( not $want_crop ) {
		while ( $displayed_lines++ < $no_lines ) {
			push( @fmt_departures, [ (q{}) x 3 ] );
		}
	}

	return @fmt_departures;
}

sub render_html {
	my $self     = shift;
	my $color    = $self->param('color') // '255,208,0';
	my $frontend = $self->param('frontend') // 'infoscreen';

	my $template = $frontend eq 'html' ? 'display' : 'infoscreen';

	my $data = get_filtered_departures(
		city            => $self->stash('city') // q{},
		stop            => $self->stash('stop'),
		backend         => scalar $self->param('backend'),
		filter_line     => scalar $self->param('line'),
		filter_platform => scalar $self->param('platform'),
		hide_regional   => ( $template eq 'infoscreen' ? 0 : 1 ),
		offset          => scalar $self->param('offset'),
	);

	my @departures = make_infoboard_lines(
		city      => $self->stash('city') // q{},
		stop      => $self->stash('stop'),
		backend   => scalar $self->param('backend'),
		no_lines  => scalar $self->param('no_lines'),
		offset    => scalar $self->param('offset'),
		want_crop => scalar $self->param('want_crop'),
		data      => $data->{filtered_results},
	);

	for my $d (@departures) {
		if ( $d->[2] and $d->[2] ne 'sofort' ) {
			$d->[2] .= ' min';
		}
	}

	$self->render(
		$template,
		title      => "vrr-infoscreen v${VERSION}",
		color      => [ split( qr{,}, $color ) ],
		departures => \@departures,
		id_name    => $data->{id_name},
		id_stop    => $data->{id_stop},
		raw        => $data->{filtered_results},
		errstr     => $data->{errstr},
		scale      => $self->param('scale') || '4.3',
		version    => $VERSION,
	);

	return;
}

sub render_json {
	my $self = shift;

	my $data = get_filtered_departures(
		city            => $self->stash('city') // q{},
		stop            => $self->stash('stop'),
		backend         => scalar $self->param('backend'),
		filter_line     => scalar $self->param('line'),
		filter_platform => scalar $self->param('platform'),
		hide_regional   => 0,
		offset          => scalar $self->param('offset'),
	);
	my $raw_departures = $data->{filtered_results};
	my $errstr         = $data->{errstr};
	my @departures     = make_infoboard_lines(
		no_lines  => scalar $self->param('no_lines'),
		offset    => scalar $self->param('offset'),
		want_crop => scalar $self->param('want_crop'),
		data      => $raw_departures,
	);

	for my $d (@departures) {
		if ( $d->[2] and $d->[2] ne 'sofort' ) {
			$d->[2] .= ' min';
		}
	}

	$self->res->headers->access_control_allow_origin('*');
	$self->render(
		json => {
			error        => $errstr,
			preformatted => \@departures,
			raw          => $raw_departures,
			version      => $VERSION,
		}
	);

	return;
}

sub render_image {
	my $self = shift;

	my $color = $self->param('color') || '255,208,0';
	my $scale = $self->param('scale');

	my $data = get_filtered_departures(
		city            => $self->stash('city') // q{},
		stop            => $self->stash('stop'),
		backend         => scalar $self->param('backend'),
		filter_line     => scalar $self->param('line'),
		filter_platform => scalar $self->param('platform'),
		hide_regional   => 0,
		offset          => scalar $self->param('offset'),
	);
	my $raw_departures = $data->{filtered_results};
	my $errstr         = $data->{errstr};

	my @departures = make_infoboard_lines(
		city      => $self->stash('city') // q{},
		stop      => $self->stash('stop'),
		backend   => scalar $self->param('backend'),
		no_lines  => scalar $self->param('no_lines'),
		offset    => scalar $self->param('offset'),
		want_crop => scalar $self->param('want_crop'),
		data      => $raw_departures
	);

	if ( $scale > 30 ) {
		$scale = 30;
	}

	if ($errstr) {
		$color = '255,0,0';
	}

	my $png = App::VRR::Fakedisplay->new(
		width  => 180,
		height => @departures * 10,
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
	for my $d (@departures) {

		my ( $line, $destination, $etr, undef ) = @{$d};

		$line = substr( $line, 0, 4 );

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
	if ( @departures == 0 ) {
		$png->new_line();
		$png->new_line();
		$png->draw_at( 50, 'no departures' );
	}

	$self->render( data => $png->png );

	return;
}

helper 'efa_service_list' => sub {
	my $self = shift;

	return @efa_services;
};

helper 'hafas_service_list' => sub {
	my $self = shift;

	return @hafas_services;
};

helper 'handle_no_results' => sub {
};

get '/_redirect' => sub {
	my $self   = shift;
	my $city   = $self->param('city') // q{};
	my $stop   = $self->param('stop');
	my $suffix = q{};

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

	if (    $params->param('frontend')
		and $params->param('frontend') eq 'infoscreen' )
	{
		my $data = get_results( $self->param('backend') // $default{backend},
			$city, $stop );
		if ( not $data->{errstr} ) {
			$suffix = '.html';
		}
	}

	if (    $city
		and $params->param('backend')
		and $params->param('backend') !~ m{ ^ ( efa | vrr ) }x )
	{
		$stop = "$city $stop";
		$city = undef;
	}

	my $params_s = $params->to_string;

	if ($city) {
		$self->redirect_to("/${city}/${stop}${suffix}?${params_s}");
	}
	else {
		$self->redirect_to("/${stop}${suffix}?${params_s}");
	}

	return;
};

get '/_privacy' => sub {
	my $self = shift;

	$self->render('privacy');
};

get '/_imprint' => sub {
	my $self = shift;

	$self->render('imprint');
};

get '/'                   => \&handle_request;
get '/:city/<*stop>.html' => \&render_html;
get '/:city/<*stop>.json' => \&render_json;
get '/:city/<*stop>.png'  => \&render_image;
get '/:city/*stop'        => \&handle_request;
get '/<:stop>.html'       => \&render_html;
get '/<:stop>.json'       => \&render_json;
get '/<:stop>.png'        => \&render_image;
get '/:stop'              => \&handle_request;

app->config(
	hypnotoad => {
		listen   => [ $ENV{VRRFAKEDISPLAY_LISTEN} // 'http://127.0.0.1:8091' ],
		pid_file => '/tmp/vrr-fakedisplay.pid',
		workers  => $ENV{VRRFAKEDISPLAY_WORKERS} // 2,
	},
);

app->types->type( json => 'application/json; charset=utf-8' );
app->plugin('browser_detect');
app->start();
