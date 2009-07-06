# Image Cropper Plugin for Movable Type and Melody
# Copyright (C) 2009 Endevver, LLC.

package ImageCropper::Plugin;

use strict;

use Carp qw( croak );
use MT::Util qw( relative_date offset_time offset_time_list epoch2ts ts2epoch format_ts );
use ImageCropper::Util qw( crop_filename crop_image annotate );

sub hdlr_default_text {
    my($ctx, $args, $cond) = @_;
    my $cfg = $ctx->{config};
    return $cfg->DefaultCroppedImageText;
}

sub hdlr_cropped_asset {
    my ( $ctx, $args, $cond ) = @_;
    my $l = $args->{label};
    my $a = $ctx->stash('asset');
    my $blog = $ctx->stash('blog');
    my $out;
    return $ctx->_no_asset_error() unless $a;
    my $cropped;

    my $prototype = MT->model('thumbnail_prototype')->load({
	blog_id => $blog->id,
	label => $l,
    });
    unless ($prototype) {
	return $ctx->error("A prototype could not be found with the label '$l'");
    }
    my $map = MT->model('thumbnail_prototype_map')->load({
	prototype_id => $prototype->id,
	asset_id => $a->id,
    });
    unless ($map) {
        return _hdlr_pass_tokens_else(@_);
    }
    my $cropped = MT->model('asset')->load( $map->cropped_asset_id );
    local $ctx->{__stash}{'asset'} = $cropped;
    defined($out = $ctx->slurp($args,$cond)) or return;
    return $out;
}

sub _hdlr_pass_tokens_else {
    my($ctx, $args, $cond) = @_;
    my $b = $ctx->stash('builder');
    defined(my $out = $b->build($ctx, $ctx->stash('tokens_else'), $cond))
        or return $ctx->error($b->errstr);
    return $out;
}

sub save_prototype {
    my $app = shift;
    my $param;
    my $q = $app->{query};
    my $obj = MT->model('thumbnail_prototype')->load( $q->param('id') );
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
    $param->{id}           = $obj->id;
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

sub gen_thumbnails_start {
    my $app = shift;
    my ($param) = @_;
    $param ||= {};
    $app->validate_magic or return;
    my $id = $app->{query}->param('id');
    my $obj = MT->model('asset')->load($id) or
	return $app->error('Could not load asset.');
    my ($bw,$bh) = _box_dim($obj);
    my @protos = MT->model('thumbnail_prototype')->load({ blog_id => $app->blog->id });
    my @loop;
    foreach my $p (@protos) {
	my $map = MT->model('thumbnail_prototype_map')->load({
	    asset_id => $obj->id,
	    prototype_id => $p->id,
        });
	my ($url,$x,$y,$w,$h);
	if ($map) {
	    $x  = $map->cropped_x;
	    $y  = $map->cropped_y;
	    $w  = $map->cropped_w;
	    $h  = $map->cropped_h;
	    my $a = MT->model('asset')->load( $map->cropped_asset_id );
	    if ($a) {
		$url = $a->url;
	    }
	}
	push @loop, {
	    proto_id      => $p->id,
	    proto_label   => $p->label,
	    thumbnail_url => $url,
	    cropped_x     => $x,
	    cropped_y     => $y,
	    cropped_w     => $w,
	    cropped_h     => $h,
	    max_width     => $p->max_width,
	    max_height    => $p->max_height,
	};
    }
    $param->{prototype_loop} = \@loop if @loop;
    $param->{box_width}  = $bw;
    $param->{box_height} = $bh;
    $param->{actual_width}  = $obj->image_width;
    $param->{actual_height} = $obj->image_height;
    $param->{has_prototypes} = $#loop > 0;

    my $tmpl = $app->load_tmpl( 'start.tmpl', $param );
    my $ctx = $tmpl->context;
    $ctx->stash('asset', $obj);
    return $tmpl;
}

sub delete_crop {
    my $app = shift;

    my $q    = $app->param;
    my $blog = $app->blog;

    my $id     = $q->param('id');
    my $pid    = $q->param('prototype');

    my $oldmap = MT->model('thumbnail_prototype_map')->load({
	asset_id => $id,
	prototype_id => $pid,
    });
    if ($oldmap) {
	my $oldasset = MT->model('asset')->load( $oldmap->cropped_asset_id );
	$oldasset->remove()
	    or MT->log({ blog_id => $blog->id, message => "Error removing asset: " . $oldmap->cropped_asset_id });
	$oldmap->remove()
	    or MT->log({ blog_id => $blog->id, message => "Error removing prototype map." });
    }
    my $result = {
	success => 1,
    };
    return _send_json_response($app, $result);
}

sub crop {
    my $app = shift;

    my $q = $app->param;
    my $blog = $app->blog;

    my $fmgr;
    my $result;

    my $X        = $q->param('x');
    my $Y        = $q->param('y');
    my $width    = $q->param('w');
    my $height   = $q->param('h');
    my $compress = $q->param('compress');
    my $annotate = $q->param('annotate');
    my $text     = $q->param('text');
    my $text_loc = $q->param('text_loc');
    my $text_rot = $q->param('text_rot');
    my $id       = $q->param('id');
    my $pid      = $q->param('prototype');

    my $asset     = MT->model('asset')->load( $id );
    my $prototype = MT->model('thumbnail_prototype')->load( $pid );

    my $cropped   = crop_filename( $asset, 
				   Width => $prototype->max_width,
				   Height => $prototype->max_height,
				   X => $X,
				   Y => $Y,
    );
    my $cache_path; my $cache_url;
    my $archivepath = $blog->archive_path;
    my $archiveurl  = $blog->archive_url;
    $cache_path = $cache_url = $asset->_make_cache_path( undef, 1 );
    $cache_path =~ s!%a!$archivepath!;
    $cache_url =~ s!%a!$archiveurl!;
    my $cropped_path = File::Spec->catfile( $cache_path, $cropped );
    MT->log({ blog_id => $blog->id, message => "Cropped filename: $cropped_path" });
    my $cropped_url = $cache_url . '/' . $cropped;
    MT->log({ blog_id => $blog->id, message => "Cropped URL: $cropped_url" });
    my ( $base, $path, $ext ) =
	File::Basename::fileparse( $cropped, qr/[A-Za-z0-9]+$/ );
    my $asset_cropped = new MT::Asset::Image;
    $asset_cropped->blog_id($blog->id);
    $asset_cropped->url($cropped_url);
    $asset_cropped->file_path($cropped_path);
    $asset_cropped->file_name("$base$ext");
    $asset_cropped->file_ext($ext);
    $asset_cropped->image_width($prototype->max_width);
    $asset_cropped->image_height($prototype->max_height);
    $asset_cropped->created_by( $app->user->id );
    $asset_cropped->label($app->translate("[_1] ([_2])", $asset->label || $asset->file_name, $prototype->label));
    $asset_cropped->parent( $asset->id );
    $asset_cropped->save;

    my $oldmap = MT->model('thumbnail_prototype_map')->load({
	asset_id => $asset->id,
	prototype_id => $prototype->id,
    });
    if ($oldmap) {
	my $oldasset = MT->model('asset')->load( $oldmap->cropped_asset_id );
	MT->log({ blog_id => $blog->id, message => "Removing: " . $oldasset->label });
	$oldasset->remove()
	    or MT->log({ blog_id => $blog->id, message => "Error removing asset: " . $oldmap->cropped_asset_id });
	$oldmap->remove()
	    or MT->log({ blog_id => $blog->id, message => "Error removing prototype map." });
    }

    my $map = MT->model('thumbnail_prototype_map')->new;
    $map->asset_id($asset->id);
    $map->prototype_id($prototype->id);
    $map->cropped_asset_id($asset_cropped->id);
    $map->cropped_x($X);
    $map->cropped_y($Y);
    $map->cropped_w($width);
    $map->cropped_h($height);
    $map->save;
    
    require MT::Image;
    my $img = MT::Image->new( Filename => $asset->file_path )
	or MT->log({ blog_id => $blog->id, message => "Error loading image: " . MT::Image->errstr });
    my $data = crop_image($img, 
			  Width  => $width,
			  Height => $height,
			  X      => $X,
			  Y      => $Y,
			  compress => $compress,
    );
    $data = $img->scale( 
	Width  => $prototype->max_width,
	Height => $prototype->max_height,
    );
    if ($annotate && $text) {
	$data = annotate( $img,
			  text     => $text,
			  location => $text_loc,
			  rotation => $text_rot,
        );
    }
    require MT::FileMgr;
    $fmgr ||= $blog ? $blog->file_mgr : MT::FileMgr->new('Local');
    unless ($fmgr) {
	MT->log({ blog_id => $blog->id, message => "Unable to initialize File Manager" });
	return undef;
    }
    if ($cache_path =~ /^%r/) {
	my $p = $blog->site_path;
	$cache_path =~ s/%r/$p/;
    }
    unless ($fmgr->can_write($cache_path)) {
	MT->log({ blog_id => $blog->id, message => "Can't write to: $cache_path" });
	return undef;
    }
    my $error = '';
    if (!-d $cache_path) {
	MT->log({ blog_id => $blog->id, message => "$cache_path is NOT a directory. Creating..." });
        require MT::FileMgr;
        my $fmgr = $blog ? $blog->file_mgr : MT::FileMgr->new('Local');
        unless ($fmgr->mkpath($cache_path)) {
	    MT->log({ blog_id => $blog->id, message => "Can't mkpath: $cache_path" });
	    return undef;
	}
    }

    $fmgr->put_data( $data, 
		     File::Spec->catfile( $cache_path, $cropped ), 
		     'upload' )
	or $error = MT->translate( "Error creating cropped file: [_1]", $fmgr->errstr );

    if ($cropped_url =~ /^%r/) {
	my $p = $blog->site_url;
	$cropped_url =~ s/%r\/?/$p/;
    }
    $result = {
	error        => $error,
        proto_id     => $prototype->id,
	cropped      => $cropped,
	cropped_path => $cropped_path,
	cropped_url  => $cropped_url,
    };

    return _send_json_response($app, $result);
}


sub _send_json_response {
    my ($app,$result) = @_;
    require JSON;
    my $json = JSON::objToJson( $result );
    $app->send_http_header("");
    $app->print($json);
    return $app->{no_print_body} = 1;
    return undef;
}

sub _box_dim {
    my ($obj) = @_;
    my ($box_w,$box_h);
    if ($obj->image_width > 900) {
        #   x    h
        #  --- = - => (900*h) / w = x 
        #  900   w
        $box_w = 900;
        $box_h = int((900 * $obj->image_height) / $obj->image_width);
    } else {
	$box_w = $obj->image_width;
	$box_h = $obj->image_height;
    }
    return ($box_w,$box_h);
}

1;
