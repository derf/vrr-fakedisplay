# vrr-infoscreen - Infoscreen for Public Transit Departures

[vrr-infoscreen homepage](https://finalrewind.org/projects/vrr-fakedisplay/)

vrr-infoscreen (formerly vrr-fakedisplay) shows departures at a public transit
stop, serving both as infoscreen / webapp and LED departure monitor look-alike.

It supports most german local transit networks and also some austrian ones.

There's a public [vrr-infoscreen service on
finalrewind.org](https://vrrf.finalrewind.org/). You can also host your own
instance, see the Setup notes below.

## Dependencies

 * perl ≥ 5.10
 * Cache::File (part of the Cache module)
 * DateTime
 * DateTime::Format::Strptime
 * File::ShareDir
 * GD
 * Mojolicious
 * Mojolicious::Plugin::BrowserDetect
 * Travel::Status::DE::EFA ≥ 1.15
 * Travel::Status::DE::HAFAS ≥ 2.03
 * Travel::Status::DE::URA ≥ 2.01

## Setup

First, build App::VRR::Fakedisplay which is required for the LED frontend:

* perl Build.PL
* ./Build
* ./Build manifest
* sudo ./Build install

vrr-infoscreen is configured via environment variables:

| Variable | Default | Description |
| :------- | :------ | :---------- |
| VRRFAKEDISPLAY\_LISTEN | `http://127.0.0.1:8091` | IP and Port for web service |
| VRRFAKEDISPLAY\_STATS | _None_ | File in which the total count of (non-cached) backend API requests is written |
| VRRFAKEDISPLAY\_CACHE | `/tmp/vrr-fakedisplay` | Cache directory |
| VRRFAKEDISPLAY\_WORKERS | 2 | Number of concurrent worker processes |

Set these as needed, create `templates/imprint.html.ep` (imprint) and
`templates/privacy.html.ep` (privacy policy), and configure your web server to
pass requests for vrr-infoscreen to the appropriate port.

You can run the app using a Mojo::Server of your choice, e.g.  **perl
index.pl daemon -m production** (quick&dirty, does not respect all variables)
or **hypnotad** (recommended). A systemd unit example is provided in
`examples/vrr-infoscreen.service`.
