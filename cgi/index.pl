#!/usr/bin/env perl
use Mojolicious::Lite;
use Cache::File;

use DateTime;
use DateTime::Format::Strptime;

use App::VRR::Fakedisplay;
use Travel::Status::DE::VRR;

our $VERSION = '0.01';

sub get_results_for {
	my ( $city, $stop ) = @_;

	my $cache = Cache::File->new(
		cache_root      => '/tmp/vrr-fake',
		default_expires => '900 sec',
	);

	my $results = $cache->thaw("${city} _ ${stop}");

	if ( not $results ) {
		my $status = Travel::Status::DE::VRR->new(
			place => $city,
			name  => $stop
		);
		$results = [ [ $status->results ], $status->errstr ];
		$cache->freeze( "${city} _ ${stop}", $results );
	}

	return @{$results};
}

sub handle_request {
	my $self = shift;
	my $city = $self->stash('city');
	my $stop = $self->stash('stop');

	$self->stash( title   => 'vrr-fakedisplay' );
	$self->stash( version => $VERSION );

	$self->stash( params => $self->req->params->to_string );
	$self->stash( height => 50 );
	$self->stash( width  => 180 );

	$self->render(
		'main',
		city    => $city,
		stop    => $stop,
		version => $VERSION,
		title   => "departures for ${city} ${stop}",
	);
}

sub shorten_destination {
	my ( $dest, $city ) = @_;

	$dest =~ s{ ^ $city \s }{}x;

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

sub render_image {
	my $self = shift;
	my $city = $self->stash('city');
	my $stop = $self->stash('stop');

	my $dt_now = DateTime->now( time_zone => 'Europe/Berlin' );

	my $color = $self->param('color') || '255,208,0';

	my ( @grep_line, @grep_platform );

	my ( $results, $errstr ) = get_results_for( $city, $stop );

	my $png = App::VRR::Fakedisplay->new(
		width  => 180,
		height => 50,
		color  => [ split( qr{,}, $color ) ]
	);

	my $strp_simple = DateTime::Format::Strptime->new(
		pattern   => '%H:%M',
		time_zone => 'floating',
	);
	my $strp_full = DateTime::Format::Strptime->new(
		pattern   => '%d.%m.%Y %H:%M',
		time_zone => 'floating',
	);

	if ( $self->param('line') ) {
		@grep_line = split( qr{,}, $self->param('line') );
	}
	if ( $self->param('platform') ) {
		@grep_platform = split( qr{,}, $self->param('platform') );
	}

	$self->res->headers->content_type('image/png');
	for my $d ( @{$results} ) {

		my $line        = $d->line;
		my $platform    = ( split( qr{ }, $d->platform ) )[-1];
		my $destination = $d->destination;
		my $time        = $d->time;
		my $etr;

		my $dt_dep = $strp_full->parse_datetime($time)
		  // $strp_simple->parse_datetime($time);
		my $dt;

		if (   ( @grep_line and not( $line ~~ \@grep_line ) )
			or ( @grep_platform and not( $platform ~~ \@grep_platform ) ) )
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

		if ( $duration->is_negative ) {
			next;
		}
		elsif ( $duration->in_units('minutes') == 0 ) {
			$etr = 'sofort';
		}
		elsif ( $duration->in_units('hours') == 0 ) {
			$etr = sprintf( ' %2d', $duration->in_units('minutes'), );
		}
		else {
			last;
		}

		$destination = shorten_destination( $destination, $city );

		$png->draw_at( 0,   $line );
		$png->draw_at( 25,  $destination );
		$png->draw_at( 144, $etr );

		if ( $etr ne 'sofort' ) {
			$png->draw_at( 161, 'min' );
		}

		$png->new_line();
	}

	$self->render( data => $png->png );
}

get '/_redirect' => sub {
	my $self = shift;
	my $city = $self->param('city');
	my $stop = $self->param('stop');

	$self->redirect_to("/${city}/${stop}");
};

get '/'                => \&handle_request;
get '/:city/:stop.png' => \&render_image;
get '/:city/:stop'     => \&handle_request;

app->start();

__DATA__

@@ main.html.ep
<!DOCTYPE html>
<html>
<head>
	<title><%= $title %></title>
	<meta charset="utf-8">
	<style type="text/css">

	div.about {
		font-family: Sans-Serif;
		color: #666666;
	}

	div.about a {
		color: #000066;
	}

	</style>
	<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.5.1/jquery.min.js"></script>
</head>
<body>

% if ($city and $stop) {
<img src="../<%= $city %>/<%= $stop %>.png?<%= $params %>" alt=""
id="display" height="<%= $height * 4 %>" width="<%= $width * 4 %>"/>
% }
% else {

<p>
VRR-Fakedisplay shows the next departures at a public transit stop, just like
the Lumino LED displays used at some stops.
</p>

<p>
It was written for the VRR (Verkehrsverbund Rhein-Ruhr), but supports most other
local transit networks as well.
</p>

% }

<div class="input-field">

<% if (my $error = stash 'error') { %>
<p>
  Error: <%= $error %><br/>
</p>
<% } %>

<%= form_for _redirect => begin %>
<p>
  City -> Stop:
  <%= text_field 'city' %>
  <%= text_field 'stop' %>
  <%= submit_button 'Display' %>
</p>
<% end %>

</div>

<div class="about">
<a href="http://finalrewind.org/projects/vrr-fakedisplay/">vrr-fakedisplay</a>
v<%= $version %>
</div>

</body>

<script type="text/javascript">
function reloadDisplay() {
	d = new Date();
	$("#display").attr("src", "../<%= $city %>/<%= $stop %>.png?<%= $params %>&r="+d.getTime())
	setTimeout('reloadDisplay()', 60000);
}

setTimeout('reloadDisplay()', 60000);
</script>

</html>

@@ not_found.html.ep
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
	"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
	<title>page not found</title>
	<meta http-equiv="Content-Type" content="text/html;charset=utf-8"/>
</head>
<body>
<div>
page not found
</div>
</body>
</html>
