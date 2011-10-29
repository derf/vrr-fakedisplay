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
	module_name => 'App::VRR::Fakedisplay',
	license => 'perl',
	requires => {
		'perl' => '5.10.0',
		'Cache::File' => 0,
		'DateTime' => 0,
		'DateTime::Format::DateParse' => 0,
		'GD' => 0,
		'Mojolicious::Lite' => 0,
		'Travel::Status::DE::VRR' => 0.02,
	},
	share_dir => 'share',
	sign => 1,

)->create_build_script();
