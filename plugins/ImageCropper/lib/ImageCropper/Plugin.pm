# Image Cropper Plugin for Movable Type and Melody
# Copyright (C) 2009 Endevver, LLC.

package ImageCropper::Plugin;

use strict;

use Carp qw( croak );
use MT::Util qw( relative_date offset_time offset_time_list epoch2ts ts2epoch format_ts );

sub save_prototype {
    my $app = shift;
    my $param;
    my $q = $app->{query};
    my $obj = MT->model('thumbnail_prototype')->load( $q->param('rule_id') );
    unless ($obj) { 
        $obj = MT->model('thumbnail_prototype')->new;
    }
    foreach ( qw(blog_id max_width max_height label default_tags) ) {
	$obj->$_($q->param($_));
    }
    $obj->save or return $app->error( $obj->errstr );

    my $cgi = $app->{cfg}->CGIPath . $app->{cfg}->AdminScript;
    $app->redirect("$cgi?__mode=list_prototypes&blog_id=".$q->param('blog_id')."&prototype_saved=1");
}

sub edit_prototype {
    my $app = shift;
    my ($param) = @_;
    my $q = $app->{query};
    my $blog = MT::Blog->load($q->param('blog_id'));

    $param ||= {};

    my $obj;
    if ($q->param('id')) {
        $obj = MT->model('thumbnail_prototype')->load($q->param('id'));
    } else {
        $obj = MT->model('thumbnail_prototype')->new();
    }

    $param->{blog_id}      = $blog->id;
    $param->{label}        = $obj->label;
    $param->{max_width}    = $obj->max_width;
    $param->{max_height}   = $obj->max_height;
    return $app->load_tmpl( 'dialog/edit.tmpl', $param );
}

sub list_prototypes {
    my $app = shift;
    my ($params) = @_;
    $params ||= {};
    my $q = $app->{query};

    $params->{prototype_saved} = $q->param('prototype_saved');

    my $code = sub {
        my ($obj, $row) = @_;

	$row->{id}         = $obj->id;
	$row->{blog_id}    = $obj->blog_id;
	$row->{label}      = $obj->label;
	$row->{max_width}  = $obj->max_width;
	$row->{max_height} = $obj->max_height;

        my $ts = $row->{created_on};
	my $datetime_format = MT::App::CMS::LISTING_DATETIME_FORMAT();
	my $time_formatted = format_ts( $datetime_format, $ts, $app->blog, 
					$app->user ? $app->user->preferred_language : undef );
        $row->{created_on_relative} = relative_date($ts, time, $app->blog);
        $row->{created_on_formatted} = $time_formatted;
    };

    my $plugin = MT->component('ImageCropper');

    $app->listing({
        type     => 'thumbnail_prototype',
        terms    => {
            blog_id => $app->blog->id,
        },
        args     => {
            sort      => 'created_on',
            direction => 'descend',
        },
        listing_screen => 1,
        code     => $code,
        template => $plugin->load_tmpl('list.tmpl'),
        params   => $params,
    });
}

1;
