# This code is licensed under the GPLv2
# Copyright (C) 2009 Endevver LLC.

package ImageCropper::Prototype;

use strict;
use base qw( MT::Object );

__PACKAGE__->install_properties( {
        column_defs => {
            'id'           => 'integer not null auto_increment',
            'blog_id'      => 'integer not null',
            'label'        => 'string(100) not null',
            'default_tags' => 'string(255)',
            'max_width'    => 'smallint not null',
            'max_height'   => 'smallint not null',
            'compression'  => 'string(30)',
        },
        audit   => 1,
        indexes => {
            id      => 1,
            blog_id => 1,
            labels  => { columns => [ 'blog_id', 'label' ], },
        },
        datasource  => 'cropper_prototypes',
        primary_key => 'id',
    }
);

sub class_label {
    MT->translate("Thumbnail Prototype");
}

sub class_label_plural {
    MT->translate("Thumbnail Prototypes");
}

1;
__END__
