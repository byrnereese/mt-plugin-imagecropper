# This code is licensed under the GPLv2
# Copyright (C) 2009 Endevver LLC.

package ImageCropper::PrototypeMap;

use strict;
use base qw( MT::Object );

__PACKAGE__->install_properties( {
        column_defs => {
            'id'               => 'integer not null auto_increment',
            'asset_id'         => 'integer not null',
            'cropped_asset_id' => 'integer not null',
            'prototype_id'     => 'integer',                        # obsolete
            'prototype_key'    => 'string(100) not null',
            'cropped_x'        => 'integer not null',
            'cropped_y'        => 'integer not null',
            'cropped_w'        => 'integer not null',
            'cropped_h'        => 'integer not null',
        },
        defaults => {
            'cropped_x' => 0,
            'cropped_y' => 0,
        },
        indexes => {
            prototype_key => 1,
            asset_id      => 1,
        },
        datasource  => 'cropper_prototypemaps',
        primary_key => 'id',
    }
);

1;
__END__
