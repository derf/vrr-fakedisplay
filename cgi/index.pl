#!/usr/bin/env perl
use Mojolicious::Lite;
use Cache::File;

use App::VRR::Fakedisplay;
use Travel::Status::DE::VRR;

our $VERSION = '0.00';

sub get_results_for {
	my ($city, $stop) = @_;

	my $cache = Cache::File->new(
		cache_root      => '/tmp/vrr-fake',
		default_expires => '900 sec',
	);

	my $results = $cache->thaw("${city} _ ${stop}");

	if ( not $results ) {
		my $status
		  = Travel::Status::DE::VRR->new(place => $city, name => $stop);
		$results = [ [$status->results], $status->errstr ];
		$cache->freeze( "${city} _ ${stop}", $results );
	}

	return @{$results};
}

sub handle_request {
	my $self    = shift;
	my $city    = $self->stash('city');
	my $stop    = $self->stash('stop');

	$self->stash( title      => 'vrr-fakedisplay' );
	$self->stash( version    => $VERSION );

	$self->render(
		'main',
		city       => $city,
		stop       => $stop,
		version    => $VERSION,
		title      => "departures for ${city} ${stop}",
	);
}

sub render_image {
	my $self = shift;
	my $city = $self->stash('city');
	my $stop = $self->stash('stop');

	$self->res->headers->content_type('image/png');

	my ($results, $errstr) = get_results_for($city, $stop);

	my $png = App::VRR::Fakedisplay->new();
	for my $d (@{$results}[0 .. 5]) {
		$png->draw_at(0, $d->line);
		$png->draw_at(30, $d->destination);
		$png->draw_at(180, $d->time);
		$png->new_line();
	}

	$self->render(data => $png->png);
}

get '/_redirect' => sub {
	my $self    = shift;
	my $city    = $self->param('city');
	my $stop    = $self->param('stop');

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
</head>
<body>

% if ($city and $stop) {
<img src="../../<%= $city %>/<%= $stop %>.png" alt=""/>
% }
% else {

<p>
DB-Fakedisplay displays the next departures at a DB station, just like the big
LC display in the station itself.
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
  Station name:
  <%= text_field 'city' %>
  <%= text_field 'stop' %>
  <%= submit_button 'Display' %>
</p>
<% end %>

</div>

<div class="about">
<a href="http://finalrewind.org/projects/db-fakedisplay/">db-fakedisplay</a>
v<%= $version %>
</div>

</body>
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
