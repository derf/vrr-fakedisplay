#!/usr/bin/env perl
use Mojolicious::Lite;
use Cache::File;

use DateTime;
use DateTime::Format::Strptime;

use App::VRR::Fakedisplay;
use Travel::Status::DE::DeutscheBahn;
use Travel::Status::DE::VRR;

no warnings 'uninitialized';

our $VERSION = '0.05';

my %default = (
	backend  => 'vrr',
	line     => q{},
	no_lines => 5,
	offset   => q{},
	platform => q{},
);

sub get_results {
	my ( $backend, $city, $stop ) = @_;

	my $expiry = 900;

	if ( lc($city) eq 'berlin' or lc($stop) ~~ [qw[hbf hauptbahnhof]] ) {
		$expiry = 600;
	}

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

	if ( $no_lines < 1 or $no_lines > 10 ) {
		$no_lines = $default{no_lines};
	}

	$self->stash( title   => 'vrr-fakedisplay' );
	$self->stash( version => $VERSION );

	$self->stash( params => $self->req->params->to_string );
	$self->stash( height => $no_lines * 10 );
	$self->stash( width  => 180 );

	$self->render(
		'main',
		city    => $city,
		stop    => $stop,
		version => $VERSION,
		title   => $city
		? "departures for ${city} ${stop}"
		: "vrr-fakedisplay ${VERSION}",
	);
}

sub shorten_line {
	my ($line) = @_;

	$line =~ s{ \s* S-Bahn }{}ox;

	$line =~ s{ ^ ( U | S | SB ) \K \s+ }{}ox;
	$line =~ s{ ^ ( STR | Bus ) }{}ox;

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

sub render_image {
	my $self = shift;
	my $city = $self->stash('city');
	my $stop = $self->stash('stop');

	my $dt_now = DateTime->now( time_zone => 'Europe/Berlin' );

	my $color    = $self->param('color') || '255,208,0';
	my $no_lines = $self->param('no_lines');
	my $backend  = $self->param('backend');

	my ( @grep_line, @grep_platform );
	my $offset = 0;

	my ( $results, $errstr ) = get_results( $backend, $city, $stop );

	if ($errstr) {
		$color = '255,0,0';
	}

	my $strp_simple = DateTime::Format::Strptime->new(
		pattern   => '%H:%M',
		time_zone => 'floating',
	);
	my $strp_full = DateTime::Format::Strptime->new(
		pattern   => '%d.%m.%Y %H:%M',
		time_zone => 'floating',
	);

	if ( $self->param('line') ) {
		my @lines = split( qr{,}, $self->param('line') );
		@grep_line = map { qr{ ^ \Q$_\E }ix } @lines;
	}
	if ( $self->param('platform') ) {
		@grep_platform = split( qr{,}, $self->param('platform') );
	}
	if ( $self->param('offset') ) {
		$offset = $self->param('offset');
	}

	if ( $no_lines < 1 or $no_lines > 10 ) {
		$no_lines = $default{no_lines};
	}

	my $png = App::VRR::Fakedisplay->new(
		width  => 180,
		height => $no_lines * 10,
		color  => [ split( qr{,}, $color ) ]
	);

	if ($errstr) {
		$png->draw_at( 6, '--------backend error--------' );
		$png->new_line();
		$png->new_line();
		$png->draw_at( 0, $errstr );
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

		if (   ( @grep_line and not( grep { $line =~ $_ } @grep_line ) )
			or ( @grep_platform and not( $platform ~~ \@grep_platform ) )
			or ( $line =~ m{ ^ (RB | RE | IC | EC) }x ) )
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

		$destination = shorten_destination( $backend, $destination, $city );
		$line = shorten_line($line);

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
};

get '/'                => \&handle_request;
get '/:city/:stop.png' => \&render_image;
get '/:city/:stop'     => \&handle_request;

app->config(
	hypnotoad => {
		accepts  => 10,
		listen   => ['http://*:8091'],
		pid_file => '/tmp/vrr-fake.pid',
		workers  => 2,
	},
);

app->start();

__DATA__

@@ main.html.ep
<!DOCTYPE html>
<html>
<head>
	<title><%= $title %></title>
	<meta charset="utf-8">
	<style type="text/css">

	body {
		font-family: Sans-Serif;
	}

	div.about {
		margin-top: 2em;
		color: #666666;
	}

	div.about a {
		color: #000066;
		text-decoration: none;
	}

	span.optional {
		color: #666666;
	}

	div.break {
		height: 1em;
	}

	div.field {
		width: 100%;
		clear: both;
	}

	div.field div.desc {
		float: left;
		width: 14em;
		text-align: right;
		padding-right: 0.5em;
	}

	input, select {
		border: 1px solid black;
	}

	div.notes {
		margin-top: 4em;
	}

	div.notes ul {
		margin-top: 1em;
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
It works best for the VRR (Verkehrsverbund Rhein-Ruhr), but also supports most
other German transit networks.
</p>

% }

<div class="input-field">

<% if (my $error = stash 'error') { %>
<p>
  Error: <%= $error %><br/>
</p>
<% } %>

<%= form_for _redirect => begin %>
<div>
  <div class="field">
    <div class="desc">City &rarr; Stop</div>
    <div>
      <%= text_field 'city' %>
      <%= text_field 'stop' %>
      <%= submit_button 'Display' %>
    </div>
  </div>
  <div class="break"></div>
  <span class="optional">optional:</span>
  <div class="field">
    <div class="desc" title="number of lines">
      display height [1..10]</div>
    <div> <%= text_field 'no_lines' %></div>
  </div>
  <div class="field">
    <div class="desc">min. offset [minutes]</div>
    <div><%= text_field 'offset' %></div>
  </div>
  <div class="field">
    <div class="desc" title="comma-separated list, example: NE,U,10">
      match line prefix</div>
    <div><%= text_field 'line' %></div>
  </div>
  <div class="field">
    <div class="desc" title="comma-separated list. Buggy.">match platform</div>
    <div><%= text_field 'platform' %></div>
  </div>
  <div class="field">
    <div class="desc">backend</div>
    <div><%= select_field backend => [['EFA (VRR)' => 'vrr'], ['HAFAS (DB)' => 'db']] %></div>
  </div>
</div>
<% end %>

</div> <!-- input-field -->

<div class="notes">
<span class="optional">notes:</span>
<ul>
<li>The EFA backend does not support Umlauts</li>
<li>For D&uuml;sseldorf, the DB backend usually gives better results</li>
<li>If you write the city correctly (like "Essen", not "essen"), vrr-fake can
shorten destination names</li>
<li><a href="/Essen/Martinstr?no_lines=8">Example</a>
</li>
</ul>
</div> <!-- notes -->

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
