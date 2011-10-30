#!/usr/bin/env perl;
use strict;
use warnings;
use 5.010;
use utf8;

use GD;

my ($out_file) = @ARGV;
my $font = GD::Image->new('share/font.png');
my $black = $font->colorClosest( 0, 0, 0 );

open( my $out_fh, '>:encoding(UTF-8)', $out_file )
  or die("open ${out_file}: $!");

sub write_out {
	my ( $off_x, $off_y, $char ) = @_;
	my $char_w = 0;

	say $out_fh "'${char}' => {";
	say $out_fh 'matrix => [';

	for my $pos_y ( $off_y .. ( $off_y + 10 ) ) {
		print $out_fh '[ ';
		for my $pos_x ( $off_x .. ( $off_x + 10 ) ) {
			if ( $font->getPixel( $pos_x, $pos_y ) == $black ) {

				if ( ( $pos_x - $off_x ) > $char_w ) {
					$char_w = $pos_x - $off_x;
				}

				print $out_fh '1, ';
			}
			else {
				print $out_fh '0, ';
			}
		}
		say $out_fh ' ],';
	}

	# spacing (one empty column)
	$char_w++;

	if ( $char eq q{ } ) {
		$char_w = 5;
	}

	say $out_fh '],';
	say $out_fh "width => ${char_w},";
	say $out_fh '},';
}

sub parse_char_row {
	my ( $off_y, @chars ) = @_;
	my $off_x = 0;

	for my $char (@chars) {
		write_out( $off_x, $off_y, $char );
		$off_x += 10;
	}

	return;
}

print $out_fh <<'___CUT___';

package App::VRR::Fakedisplay;

use strict;
use warnings;
use 5.010;
use utf8;

use File::ShareDir qw(dist_file);
use GD;

our $VERSION = '0.01';

sub new {
	my ( $class, %opt ) = @_;

	my $self = {
		width => $opt{width} || 140,
		height => $opt{height} || 40,
		scale => 10,
		offset_x => 0,
		offset_y => 0,
	};

	$self->{image} = GD::Image->new($self->{width} * $self->{scale}, $self->{height} * $self->{scale});

	$self->{color}->{bg} = $self->{image}->colorAllocate(0, 0, 0);
	$self->{color}->{fg} = $self->{image}->colorAllocate(@{$opt{color} // [255, 0, 0]});

	$self->{image}->filledRectangle(0, 0, ($self->{width} * $self->{scale}) -1,
	($self->{height} * $self->{scale}) - 1, $self->{color}->{bg});

	$self->{font} = {

___CUT___

parse_char_row( 0,  'A' .. 'Z' );
parse_char_row( 10, 'a' .. 'z' );
parse_char_row( 20, '0' .. '9' );
parse_char_row( 30, q{:}, q{-}, q{.}, q{,}, q{/}, q{ } );
parse_char_row( 40, qw(ä ö ü) );

print $out_fh <<'___CUT___';

	};

	return bless( $self, $class );
}

sub draw_at {
	my ($self, $offset_x, $text) = @_;

	my $im = $self->{image};
	my $font = $self->{font};

	my $c_bg = $self->{color}{bg};
	my $c_fg = $self->{color}{fg};

	my $font_idx = $self->{font_idx};

	my $scale = $self->{scale};

	my ($off_x, $off_y) = ($offset_x, $self->{offset_y});

	if ($off_y >= $self->{height} or $off_x >= $self->{width}) {
		return;
	}

	for my $char (split(qr{}, $text)) {

		if (not exists $self->{font}->{$char}) {
			next;
		}

		my $w = $self->{font}->{$char}->{width};

		for my $y ( 0 .. 10 ) {
			for my $x ( 0 .. $w ) {
				if ($self->{font}->{$char}->{matrix}->[$y]->[$x]) {
					$im->filledEllipse(
						($off_x + $x) * $scale, ($off_y + $y) * $scale,
						$scale, $scale,
						$c_fg
					);
				}
			}
		}
		$off_x += $w;
	}

	return;
}

sub new_line {
	my ($self) = @_;
	$self->{offset_y} += 10;

	return;
}

sub png {
	my ($self) = @_;

	return $self->{image}->png;
}

sub write_image_to {
	my ($self, $filename) = @_;

	open(my $out_fh, '>', $filename) or die("Cannot open ${filename}: ${!}\n");
	binmode $out_fh;
	print $out_fh $self->{image}->png;
	close($out_fh);

	return;
}

1;

___CUT___

close($out_fh);
