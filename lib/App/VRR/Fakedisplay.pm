package App::VRR::Fakedisplay;

use strict;
use warnings;
use 5.010;
use utf8;

use File::ShareDir qw(dist_file);
use GD;

our $VERSION = '0.00';

sub new {
	my ( $class, %opt ) = @_;

	my $self = {
		font_file => dist_file( 'App-VRR-Fakedisplay', 'font.png' ),
		width => $opt{width} || 140,
		height => $opt{height} || 40,
		scale => 10,
		offset_x => 0,
		offset_y => 0,
	};

	$self->{font} = GD::Image->new($self->{font_file});
	$self->{image} = GD::Image->new($self->{width} * $self->{scale}, $self->{height} * $self->{scale});

	$self->{color}->{bg} = $self->{image}->colorAllocate(0, 0, 0);
	$self->{color}->{fg} = $self->{image}->colorAllocate(255, 0, 0);

	$self->{image}->filledRectangle(0, 0, ($self->{width} * $self->{scale}) -1,
	($self->{height} * $self->{scale}) - 1, $self->{color}->{bg});

	$self->{font_idx} = $self->{font}->colorClosest(0, 0, 0);

	return bless( $self, $class );
}

sub locate_char {
	my ($self, $char) = @_;
	my ($x, $y, $w, $h) = (0, 30, 6, 10);

	given ($char) {
		when (/[a-z]/) { $y = 10; $x = (ord($char) - 97) * 10 }
		when (/[A-Z]/) { $y =  0; $x = (ord($char) - 65) * 10 }
		when (/[0-9]/) { $y = 20; $x = (ord($char) - 48) * 10 }

		when (q{ä}) { $y = 40; $x =  0 }
		when (q{ö}) { $y = 40; $x = 10 }
		when (q{ü}) { $y = 40; $x = 20 }

		when (q{ }) { $y = 90; $x =   0 }
		when (q{:}) { $y = 30; $x =   0 }
		when (q{-}) { $y = 30; $x =  10 }
		when (q{.}) { $y = 30; $x =  20 }
		when (q{,}) { $y = 30, $x =  30 }
	}

	given ($char) {
		when (/[WwMm]/) { $w = 8 }
		when (/[BDErt ]/) { $w = 5 }
		when (/[il1:]/) { $w = 4 }
		when (/[.,]/) { $w = 3 }
	}

	return ($x, $y, $w, $h);
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
		my ($x, $y, $w, $h) = $self->locate_char($char);
		for my $pos_x ( $x .. ($x + $w) ) {
			for my $pos_y ( $y .. ($y + $h)) {
				if ($font->getPixel($pos_x, $pos_y) == $font_idx) {
					$im->filledEllipse(
						($off_x + $pos_x - $x) * $scale, ($off_y + $pos_y - $y) * $scale,
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

__END__

=head1 NAME

=head1 SYNOPSIS

=head1 VERSION

version

=head1 DESCRIPTION

=head1 METHODS

=over

=back

=head1 DIAGNOSTICS

=head1 DEPENDENCIES

=over

=back

=head1 BUGS AND LIMITATIONS

=head1 SEE ALSO

=head1 AUTHOR

Copyright (C) 2011 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

  0. You just DO WHAT THE FUCK YOU WANT TO.
