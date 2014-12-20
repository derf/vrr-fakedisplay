#!/usr/bin/env perl

use strict;
use warnings;
use Module::Build;

Module::Build->new(

	build_requires => {
		'Module::Build' => '0.36',
		'Test::More' => 0,
		'Test::Compile' => 0,
		'Test::Pod' => 0,
	},
	dist_abstract => 'vrr fakedisplay',
	dist_name => 'vrr-fakedisplay',
	license => 'perl',
	PL_files => {
		'lib/App/VRR/Fakedisplay.pm.PL' => 'lib/App/VRR/Fakedisplay.pm',
	},
	requires => {
		'perl' => '5.10.0',
		'Cache::File' => 0,
		'DateTime' => 0,
		'DateTime::Format::Strptime' => 0,
		'GD' => 0,
		'Mojolicious::Lite' => 0,
		'Travel::Status::DE::DeutscheBahn' => 1.01,
		'Travel::Status::DE::VRR' => 1.04,
	},
	sign => 1,
	dist_version_from => 'index.pl',

)->create_build_script();
