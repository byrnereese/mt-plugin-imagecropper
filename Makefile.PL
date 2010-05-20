use ExtUtils::MakeMaker;

use YAML::Any qw(LoadFile);
my $file = "plugins/ImageCropper/config.yaml";
my $version = LoadFile($file)->{version} ||
    die "No version found in $file";

WriteMakefile(
    NAME            => 'ImageCropper',
    VERSION         => $version,
    DISTNAME        => 'ImageCropper',
);
