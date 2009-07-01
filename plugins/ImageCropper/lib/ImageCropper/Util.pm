package ImageCropper::Util;

use strict;
use base 'Exporter';
our @EXPORT_OK = qw( crop_filename crop_image );

sub crop_image {
    my $image = shift;
    my %param = @_;
    my ($w, $h, $x, $y) = @param{qw( Width Height X Y )};
    my $magick = $image->{magick};
    my $err = $magick->Crop(
	'width' => $w, 
	'height' => $h, 
	'x' => $x, 
	'y' => $y,
    );     
    MT->log({ message => "Cropping a $w x $h image at $x,$y" });
    return $image->error(
	MT->translate(
	    "Cropping a [_1]x[_2] image at [_3],[_4] failed: [_5]", 
	    $w, $h, $x, $y, $err)) if $err;

    ## Remove page offsets from the original image, per this thread: 
    ## http://studio.imagemagick.org/pipermail/magick-users/2003-September/010803.html
    $magick->Set( page => '+0+0' );
    ($image->{width}, $image->{height}) = ($w, $h);
    wantarray ? ($magick->ImageToBlob, $w, $h) : $magick->ImageToBlob;
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
