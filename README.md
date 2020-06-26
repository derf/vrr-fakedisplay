# vrr-infoscreen - Infoscreen for Public Transit Departures

[vrr-infoscreen homepage](https://finalrewind.org/projects/vrr-fakedisplay/)

vrr-infoscreen (formerly vrr-fakedisplay) shows departures at a public transit
stop, serving both as infoscreen / webapp and LED departure monitor look-alike.

It supports most german local transit networks and also some austrian ones.

There's a public [vrr-infoscreen service on
finalrewind.org](https://vrrf.finalrewind.org/). You can also host your own
instance via carton/cpanminus or Docker, see the Setup notes below.

## Dependencies

 * perl ≥ 5.20
 * carton or cpanminus
 * build-essential (gcc/clang, make)
 * libdb (Berkeley Database Libraries)
 * libgd (GD Graphics Library)
 * libxml2
 * zlib

## Installation

After installing the dependencies, clone the repository using git, e.g.

```
git clone https://git.finalrewind.org/vrr-fakedisplay
```

Make sure that all files (including `.git`, which is used to determine the
software version) are readable by your www user, and follow the steps in the
next sections.

## Perl Dependencies

vrr-infoscreen depends on a set of Perl modules which are documented in
`cpanfile`. After installing the dependencies mentioned above, you can use
carton or cpanminus to install Perl depenencies locally.

In the project root directory (where `cpanfile` resides), run either

```
carton install
```

or

```
cpanm -n --installdeps .
```

Next, you need to build App::VRR::Fakedisplay, which is required for the LED
frontend and shipped with vrr-fakedisplay.

```
export PERL5LIB=local/lib/perl5
perl Build.PL
./Build
./Build manifest
sudo ./Build install
```

## Running

You are now ready to start the web service. If you used carton, it boils
down to

```
carton exec hypnotoad index.pl
```

Otherwise, you need to make the perl dependencies available by setting the
PERL5LIB environment variable:

```
PERL5LIB=local/lib/perl5 local/bin/hypnotoad index.pl
```

Note that you should provide imprint and privacy policy pages. Depending on
traffic volume, you may also want to increase the amount of worker processes.
See the Setup notes below.

## Installation with Docker

A vrr-infoscreen image is available on Docker Hub. You can install and run it
as follows:

```
docker pull derfnull/vrr-fakedisplay:latest
docker run --rm -p 8000:8091 -v "$(pwd)/templates:/app/ext-templates:ro" vrr-fakedisplay:latest
```

This will make the web service available on port 8000.  Note that you should
provide imprint and privacy policy pages, see the Setup notes below.

Use `docker run -e VRRFAKEDISPLAY_WORKERS=4 ...` and similar to pass
environment variables to the vrr-infoscreen service.

## Setup

vrr-infoscreen is configured via environment variables:

| Variable | Default | Description |
| :------- | :------ | :---------- |
| VRRFAKEDISPLAY\_LISTEN | `http://*:8091` | IP and Port for web service |
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
