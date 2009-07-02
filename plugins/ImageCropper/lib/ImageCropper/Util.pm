package ImageCropper::Util;

use strict;
use base 'Exporter';
our @EXPORT_OK = qw( crop_filename crop_image annotate );

sub crop_image {
    my $image = shift;
    my %param = @_;
    my ($w, $h, $x, $y, $c) = @param{qw( Width Height X Y compress)};
    my $magick = $image->{magick};
    my $err = $magick->Crop(
	'width' => $w, 
	'height' => $h, 
	'x' => $x, 
	'y' => $y,
    );
#    if ($c) {
#	MT->log({ message => "Compressing image: $c" });
#	$magick->Set( quality => $c, compression => 'JPEG2000' );
#    }
    return $image->error(
	MT->translate(
	    "Error cropping a [_1]x[_2] image at [_3],[_4] failed: [_5]", 
	    $w, $h, $x, $y, $err)) if $err;

    ## Remove page offsets from the original image, per this thread: 
    ## http://studio.imagemagick.org/pipermail/magick-users/2003-September/010803.html
    $magick->Set( page => '+0+0' );
    ($image->{width}, $image->{height}) = ($w, $h);
    wantarray ? ($magick->ImageToBlob, $w, $h) : $magick->ImageToBlob;
}

sub annotate {
    my $image = shift;
    my %param = @_;
    my ($txt, $loc) = @param{qw( text location )};
    my $magick = $image->{magick};
    my $opts;
    if ($loc eq 'NorthWest') {
	$opts = { 'y' => 12, 'x' => 4 };
    } elsif ($loc eq 'SouthWest') {
	$opts = { 'y' => 4, 'x' => 4 };
    } elsif ($loc eq 'NorthEast') {
	$opts = { 'y' => 12, 'x' => 4 };
    } elsif ($loc eq 'SouthEast') {
	$opts = { 'y' => 4, 'x' => 4 };
    }
    my $err = $magick->Annotate(
	'pointsize' => '12', 
        'pen'       => 'white',
	'text'      => $txt, 
        'gravity'   => $loc,
	%$opts
    );
    return $image->error(
	MT->translate(
	    "Error annotating image with [_1]: [_2]", 
	    $txt, $err)) if $err;

    wantarray ? ($magick->ImageToBlob) : $magick->ImageToBlob;
}

sub crop_filename {
    my $asset   = shift;
    my (%param) = @_;
    my $file    = $asset->file_name or return;
    
    require MT::Util;
    my $format = $param{Format} || MT->translate('%f-cropped-%X.%Y-%wx%h%x');
    my $width  = $param{Width}  || 'auto';
    my $height = $param{Height} || 'auto';
    my $X      = $param{X} || '0';
    my $Y      = $param{Y} || '0';
    $file =~ s/\.\w+$//;
    my $base = File::Basename::basename($file);
    my $id   = $asset->id;
    my $ext  = lc($param{Type}) || $asset->file_ext || '';
    $ext = '.' . $ext;
    $format =~ s/%w/$width/g;
    $format =~ s/%h/$height/g;
    $format =~ s/%f/$base/g;
    $format =~ s/%i/$id/g;
    $format =~ s/%X/$X/g;
    $format =~ s/%Y/$Y/g;
    $format =~ s/%x/$ext/g;
    return $format;
}

1;
