# Image Cropper Plugin for Movable Type and Melody
# Copyright (C) 2009 Endevver, LLC.

package ImageCropper::Plugin;

use strict;
use warnings;

use Carp qw( croak longmess confess );
use MT::Util qw(    relative_date   ts2epoch format_ts     caturl
                 offset_time_list   epoch2ts offset_time          );
use ImageCropper::Util qw( crop_filename crop_image annotate file_size );
use Sub::Install;

# use MT::Log::Log4perl qw( l4mtdump ); use Log::Log4perl qw( :resurrect ); my $logger ||= MT::Log::Log4perl->new();

my %target;

sub post_remove_asset {
    my ( $cb, $obj ) = @_;
    my @maps =
      MT->model('thumbnail_prototype_map')->load( { asset_id => $obj->id } );
    foreach my $map (@maps) {
        my $a = MT->model('asset')->load( $map->cropped_asset_id );
        $a->remove   if $a;
        $map->remove if $map;
    }
    my $ptmap =
      MT->model('thumbnail_prototype_map')
      ->load( { cropped_asset_id => $obj->id } );
    $ptmap->remove if $ptmap;
    return 1;
}

# METHOD: init_app
#
# A callback handler which hooks into the MT::App::CMS::init_app callback
# in order to override and wrap MT::CMS::Asset::complete_upload
sub init_app {
    my ( $plugin, $app ) = @_;

    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    # This plugin operates by overriding the method
    # (MT::CMS::Asset::complete_upload)
    %target = (
        module => 'MT::CMS::Asset',
        method => 'complete_upload',
        subref => undef
    );

    # Do nothing unless the current app is our target app
    return unless ref $app and $app->isa('MT::App::CMS');

    # Make sure that our app module has the method we're looking for
    # and grab a reference to it if so.
    eval "require $target{module};"
      or die "Could not require $target{module}";
    $target{subref} = $target{module}->can( $target{method} );

    # Throw an error and quit if we could not find our target method
    unless ( $target{subref} ) {
        my $err =
          sprintf( '%s plugin initialization error: %s method not found. '
              . 'This may have been caused by changes introduced by a '
              . 'Movable Type upgrade.',
            __PACKAGE__, join( '::', $target{module}, $target{method} ) );
        $app->log( {
                class    => 'system',
                category => 'plugin',
                level    => MT::Log::ERROR(),
                message  => $err,
            }
        );
        return undef;    # We simply can't go on....
    }

    ###l4p $logger->debug( 'Overriding method: '
    ###l4p               . join('::', $target{module}, $target{method}));

    # Override the target method with our own version
    require Sub::Install;
    Sub::Install::reinstall_sub( {
            code => \&complete_upload_wrapper,
            into => $target{module},
            as   => $target{method},
        }
    );
}

sub complete_upload_wrapper {
    my $app      = shift;
    my $asset_id = $app->param('id');

    ###l4p $logger     ||= MT::Log->get_logger();  $logger->trace();

    # Call the original method to perform the work
    $target{subref}->( $app, @_ );

    # Alter the redirect location from list_assets
    # to manage_thumbnails for the uploaded asset
    if ( $app->{redirect} =~ m{__mode=list_assets} ) {
        return $app->redirect(
            $app->uri(
                'mode' => 'view',
                'args' => {
                    'from'        => 'view',
                    '_type'       => 'asset',
                    'id'          => $asset_id,
                    'blog_id'     => $app->param('blog_id'),
                    'return_args' => $app->return_args,
                    'magic_token' => $app->param('magic_token')
                }
            )
        );
    }
    return;
}

sub hdlr_default_text {
    my ( $ctx, $args, $cond ) = @_;
    my $cfg = $ctx->{config};
    return $cfg->DefaultCroppedImageText;
}

sub del_prototype {
    my ($app) = @_;
    $app->validate_magic or return;
    my @protos = $app->param('id');
    for my $pid (@protos) {
        my $p = MT->model('thumbnail_prototype')->load($pid) or next;
        $p->remove;
    }
    $app->add_return_arg( prototype_removed => 1 );
    $app->call_return;
}

sub find_prototype_id {
    my ( $ctx, $label ) = @_;
    my $blog = $ctx->stash('blog');
    my $ts   = $blog->template_set;
    return undef unless $ts;
    my $protos = MT->registry('template_sets')->{$ts}->{thumbnail_prototypes};
    foreach ( keys %$protos ) {
        my $l = $protos->{$_}->{label};
        return $_ if ( $l && $l ne '' && &{$l} eq $label );
    }
}

sub hdlr_cropped_asset {
    my ( $ctx, $args, $cond ) = @_;
    my $l       = $args->{label};
    my $a       = $ctx->stash('asset');
    my $blog    = $ctx->stash('blog');
    my $blog_id = $args->{blog_id};
    $blog_id    = 0 unless ( $blog_id && $blog_id ne '' );

    my $out;
    return $ctx->_no_asset_error() unless $a;

    my $map;
    my $prototype = MT->model('thumbnail_prototype')->load( {
            blog_id => $blog_id,
            label   => $l,
        }
    );
    if ($prototype) {

        # MT->log({ message => "prototype found: " . $prototype->id });
        $map = MT->model('thumbnail_prototype_map')->load( {
                prototype_key => 'custom_' . $prototype->id,
                asset_id      => $a->id,
            }
        );
    }
    elsif ( my $id = find_prototype_id( $ctx, $l ) ) {

  # MT->log({ message => "prototype not found, consulted registry: " . $id });
        $map = MT->model('thumbnail_prototype_map')->load( {
                prototype_key => $blog->template_set . "___" . $id,
                asset_id      => $a->id,
            }
        );
    }

    if ($map) {
        my $cropped = MT->model('asset')->load( $map->cropped_asset_id );
        if ($cropped) {
            local $ctx->{__stash}{'asset'} = $cropped;
            defined( $out = $ctx->slurp( $args, $cond ) ) or return;
            return $out;
        }
    }
    return _hdlr_pass_tokens_else(@_);
}

sub _hdlr_pass_tokens_else {
    my ( $ctx, $args, $cond ) = @_;
    my $b = $ctx->stash('builder');
    defined( my $out = $b->build( $ctx, $ctx->stash('tokens_else'), $cond ) )
      or return $ctx->error( $b->errstr );
    return $out;
}

sub save_prototype {
    my $app = shift;
    my $param;
    my $q   = $app->{query};
    my $obj = MT->model('thumbnail_prototype')->load( $q->param('id') )
      || MT->model('thumbnail_prototype')->new;

    $obj->$_( $q->param($_) )
      foreach (qw(blog_id max_width max_height label default_tags));

    $obj->save or return $app->error( $obj->errstr );

    my $cgi = $app->{cfg}->CGIPath . $app->{cfg}->AdminScript;
    $app->redirect( "$cgi?__mode=list_prototypes&blog_id="
          . $q->param('blog_id')
          . "&prototype_saved=1" );
}

sub edit_prototype {
    my $app     = shift;
    my ($param) = @_;
    my $q       = $app->{query};
    my $blog    = MT::Blog->load( $q->param('blog_id') );

    $param ||= {};

    my $obj;
    if ( $q->param('id') ) {
        $obj = MT->model('thumbnail_prototype')->load( $q->param('id') );
    }
    else {
        $obj = MT->model('thumbnail_prototype')->new();
    }

    $param->{blog_id}    = $blog->id;
    $param->{id}         = $obj->id;
    $param->{label}      = $obj->label;
    $param->{max_width}  = $obj->max_width;
    $param->{max_height} = $obj->max_height;
    $param->{screen_id}  = 'edit-prototype';
    return $app->load_tmpl( 'dialog/edit.tmpl', $param );
}

sub load_ts_prototype {
    my $app = shift;
    my ($key) = @_;
    my ( $ts, $id ) = split( '___', $key );
    return $app->registry('template_sets')->{$ts}->{thumbnail_prototypes}
      ->{$id};
}

sub load_ts_prototypes {
    my $app  = shift;
    my $blog = $app->blog;

    my @protos;
    if ( $blog->template_set ) {
        my $ts = $blog->template_set;
        my $ps =
          $app->registry('template_sets')->{$ts}->{thumbnail_prototypes};
        foreach ( keys %$ps ) {
            my $p = $ps->{$_};
            push @protos,
              { id           => $_,
                type         => 'template_set',
                key          => "$ts::$_",
                template_set => $ts,
                blog_id      => $blog->id,
                label        => &{ $p->{label} },
                max_width    => $p->{max_width},
                max_height   => $p->{max_height},
              };
        }
    }
    return \@protos;
}

sub list_prototypes {
    my $app = shift;
    my ($params) = @_ || {};
    my $q        = $app->{query};
    my $blog     = $app->blog;

    if ( $blog && $app->blog->template_set ) {
        my $loop = load_ts_prototypes($app);
        $params->{prototype_loop} = $loop;
        $params->{template_set_name} =
          $app->registry('template_sets')->{ $blog->template_set }->{label};
    }
    $params->{prototype_saved} = $q->param('prototype_saved');
    $params->{screen_id}       = 'list-prototypes';

    my $code = sub {
        my ( $obj, $row ) = @_;

        $row->{id}         = $obj->id;
        $row->{blog_id}    = $obj->blog_id;
        $row->{label}      = $obj->label;
        $row->{max_width}  = $obj->max_width;
        $row->{max_height} = $obj->max_height;

        my $ts              = $row->{created_on};
        my $datetime_format = MT::App::CMS::LISTING_DATETIME_FORMAT();
        my $time_formatted  = format_ts(
            $datetime_format,
            $ts,
            $app->blog || undef,
            (     $app->user
                ? $app->user->preferred_language
                : undef
            )
        );
        $row->{created_on_relative} =
          relative_date( $ts, time, $app->blog ? $app->blog : undef );
        $row->{created_on_formatted} = $time_formatted;
    };

    my $plugin = MT->component('ImageCropper');

    $app->listing( {
            type  => 'thumbnail_prototype',
            terms => { blog_id => ( $app->blog ? $app->blog->id : 0 ), },
            args  => {
                sort      => 'created_on',
                direction => 'descend',
            },
            listing_screen => 1,
            code           => $code,
            template       => $plugin->load_tmpl('list.tmpl'),
            params         => $params,
        }
    );
}

sub gen_thumbnails_start {
    my $app = shift;
    my ($param) = @_ || {};
    $app->validate_magic or return;

    my $id  = $app->{query}->param('id');
    my $obj = MT->model('asset')->load($id)
      or return $app->error('Could not load asset.');

    my ( $bw, $bh ) = _box_dim($obj);
    my @protos;
    my @custom =
      MT->model('thumbnail_prototype')->load( { blog_id => $app->blog->id } );
    foreach (@custom) {
        push @protos,
          { id         => $_->id,
            key        => 'custom_' . $_->id,
            label      => $_->label,
            max_width  => $_->max_width,
            max_height => $_->max_height,
          };
    }
    my $tsprotos = load_ts_prototypes($app);
    foreach (@$tsprotos) {
        push @protos,
          { id         => $_->{template_set} . '___' . $_->{id},
            key        => $_->{template_set} . '___' . $_->{id},
            label      => $_->{label},
            max_width  => $_->{max_width},
            max_height => $_->{max_height},
          };
    }
    my @loop;
    foreach my $p (@protos) {
        my $map = MT->model('thumbnail_prototype_map')->load( {
                asset_id      => $obj->id,
                prototype_key => $p->{key},
            }
        );
        my ( $url, $x, $y, $w, $h, $size );
        if ($map) {
            $x = $map->cropped_x;
            $y = $map->cropped_y;
            $w = $map->cropped_w;
            $h = $map->cropped_h;
            my $a = MT->model('asset')->load( $map->cropped_asset_id );
            if ($a) {
                $url  = $a->url;
                $size = file_size($a);
            }
        }
        push @loop, {
            proto_id      => $p->{id},
            proto_key     => $p->{key},
            proto_label   => $p->{label},
            thumbnail_url => $url,
            cropped_x     => $x,
            cropped_y     => $y,
            cropped_w     => $w,
            cropped_h     => $h,
            cropped_size  => $size,
            max_width     => $p->{max_width},
            max_height    => $p->{max_height},
            is_tall       => $p->{max_height} > $p->{max_width},
            smaller_vp => ( $p->{max_height} < 135 && $p->{max_width} < 175 ),

            # 175x135
        };
    }
    $param->{prototype_loop} = \@loop if @loop;
    $param->{box_width}      = $bw;
    $param->{box_height}     = $bh;
    $param->{actual_width}   = $obj->image_width;
    $param->{actual_height}  = $obj->image_height;
    $param->{has_prototypes} = $#loop >= 0;
    $param->{asset_label}    = defined $obj->label ? $obj->label
                                                   : $obj->file_name;

    my $tmpl = $app->load_tmpl( 'start.tmpl', $param );
    my $ctx = $tmpl->context;
    $ctx->stash( 'asset', $obj );
    return $tmpl;
}

sub delete_crop {
    my $app  = shift;
    my $q    = $app->param;
    my $blog = $app->blog;
    my $id   = $q->param('id');
    my $key  = $q->param('prototype');

    my $oldmap = MT->model('thumbnail_prototype_map')->load( {
            asset_id      => $id,
            prototype_key => $key,
        }
    );
    if ($oldmap) {
        my $oldasset = MT->model('asset')->load( $oldmap->cropped_asset_id );
        $oldasset->remove()
          or MT->log( {
                blog_id => $blog->id,
                message => "Error removing asset: "
                  . $oldmap->cropped_asset_id
            }
          );
        $oldmap->remove()
          or MT->log( {
                blog_id => $blog->id,
                message => "Error removing prototype map."
            }
          );
    }
    my $result = {
        proto_key => $key,
        success   => 1,
    };
    return _send_json_response( $app, $result );
}

sub crop {
    my $app  = shift;
    my $q    = $app->param;
    my $blog = $app->blog;

    my $X         = $q->param('x');
    my $Y         = $q->param('y');
    my $width     = $q->param('w');
    my $height    = $q->param('h');
    my $type      = $q->param('type');
    my $quality   = $q->param('quality');
    my $annotate  = $q->param('annotate');
    my $text      = $q->param('text');
    my $text_size = $q->param('text_size');
    my $text_loc  = $q->param('text_loc');
    my $text_rot  = $q->param('text_rot');
    my $id        = $q->param('asset');
    my $key       = $q->param('key');

    my $asset = MT->model('asset')->load($id);
    my $prototype;
    if ( $key =~ /custom_(\d+)/ ) {
        $prototype = MT->model('thumbnail_prototype')->load($1);
    }
    else {
        $prototype = MT->model('thumbnail_prototype')->new;
        my $p = load_ts_prototype( $app, $key );
        foreach (qw( max_width max_height label )) {
            $prototype->$_( $p->{$_} );
        }
    }
    my @cropped_file_parts = crop_filename(
        $asset,
        Prototype => $key,
        Type      => $type,
    );

    my ( $cache_path, $cache_url );
    my $archivepath = $blog->archive_path;
    my $archiveurl  = $blog->archive_url;
    $cache_path = $cache_url = $asset->_make_cache_path( undef, 1 );
    $cache_path =~ s!%a!$archivepath!;

    $cache_url =~ s!%a!$archiveurl!;
    my $cropped_path =
      File::Spec->catfile( $cache_path, @cropped_file_parts );

#MT->log({ blog_id => $blog->id, message => "Cropped filename: $cropped_path" });
    my $cropped_url = caturl( $cache_url, @cropped_file_parts );

   #MT->log({ blog_id => $blog->id, message => "Cropped URL: $cropped_url" });
    my ( $base, $path, $ext ) =
      File::Basename::fileparse( File::Spec->catfile(@cropped_file_parts),
        qr/[A-Za-z0-9]+$/ );

    my $asset_cropped = new MT::Asset::Image;
    $asset_cropped->blog_id( $blog->id );
    $asset_cropped->url($cropped_url);
    $asset_cropped->file_path($cropped_path);
    $asset_cropped->file_name("$base$ext");
    $asset_cropped->file_ext($ext);
    $asset_cropped->image_width( $prototype->max_width );
    $asset_cropped->image_height( $prototype->max_height );
    $asset_cropped->created_by( $app->user->id );
    $asset_cropped->label(
        $app->translate(
            "[_1] ([_2])",
            $asset->label || $asset->file_name,
            $prototype->label
        )
    );
    $asset_cropped->parent( $asset->id );
    $asset_cropped->save;

    my $oldmap = MT->model('thumbnail_prototype_map')->load( {
            asset_id      => $asset->id,
            prototype_key => $key,
        }
    );
    if ($oldmap) {
        my $oldasset = MT->model('asset')->load( $oldmap->cropped_asset_id );
        if ($oldasset) {

# MT->log({ blog_id => $blog->id, message => "Removing: " . $oldasset->label });
            $oldasset->remove()
              or MT->log( {
                    blog_id => $blog->id,
                    message => "Error removing asset: "
                      . $oldmap->cropped_asset_id
                }
              );
        }
        $oldmap->remove()
          or MT->log( {
                blog_id => $blog->id,
                message => "Error removing prototype map."
            }
          );
    }

    my $map = MT->model('thumbnail_prototype_map')->new;
    $map->asset_id( $asset->id );
    $map->prototype_key($key);
    $map->cropped_asset_id( $asset_cropped->id );
    $map->cropped_x($X);
    $map->cropped_y($Y);
    $map->cropped_w($width);
    $map->cropped_h($height);
    $map->save;

    require MT::Image;
    my $img = MT::Image->new( Filename => $asset->file_path )
      or MT->log( {
            blog_id => $blog->id,
            message => "Error loading image: " . MT::Image->errstr
        }
      );
    my $data = crop_image(
        $img,
        Width   => $width,
        Height  => $height,
        X       => $X,
        Y       => $Y,
        Type    => $type,
        quality => $quality,
    );
    $data = $img->scale(
        Width  => $prototype->max_width,
        Height => $prototype->max_height,
    );

    if ( $annotate && $text ) {
        my $plugin = MT->component("ImageCropper");
        my $scope  = "blog:" . $blog->id;
        my $fam    = $plugin->get_config_value( 'annotate_fontfam', $scope );
        $data = annotate(
            $img,
            text     => $text,
            family   => $fam,
            size     => $text_size,
            location => $text_loc,
            rotation => $text_rot,
        );
    }
    require MT::FileMgr;
    my $fmgr = $blog ? $blog->file_mgr : MT::FileMgr->new('Local');
    unless ($fmgr) {
        MT->log( {
                blog_id => $blog->id,
                message => "Unable to initialize File Manager"
            }
        );
        return undef;
    }
    if ( $cache_path =~ /^%r/ ) {
        my $site_path = $blog->site_path;
        $cache_path =~ s/%r/$site_path/;
    }
    unless ( $fmgr->can_write($cache_path) ) {
        MT->log( {
                blog_id => $blog->id,
                message => "Can't write to: $cache_path"
            }
        );
        return undef;
    }
    my $error = '';
    if ( !-d $cache_path ) {

# MT->log({ blog_id => $blog->id, message => "$cache_path is NOT a directory. Creating..." });
        require MT::FileMgr;
        unless ( $fmgr->mkpath($cache_path) ) {
            MT->log( {
                    blog_id => $blog->id,
                    message => "Can't mkpath: $cache_path"
                }
            );
            return undef;
        }
    }

    $fmgr->put_data( $data,
        File::Spec->catfile( $cache_path, @cropped_file_parts ), 'upload' )
      or $error =
      MT->translate( "Error creating cropped file: [_1]", $fmgr->errstr );

    if ( $cropped_url =~ /^%r/ ) {
        my $site_url = $blog->site_url;
        $site_url    =~ s{/?$}{/};
        $cropped_url =~ s{%r/?}{$site_url};
    }
    my $result = {
        error        => $error,
        proto_key    => $key,
        cropped      => caturl(@cropped_file_parts),
        cropped_path => $cropped_path,
        cropped_url  => $cropped_url,
        cropped_size => file_size($asset_cropped),
    };

    return _send_json_response( $app, $result );
}

sub _send_json_response {
    my ( $app, $result ) = @_;
    require JSON;
    my $json = JSON::objToJson($result);
    $app->send_http_header("");
    $app->print($json);
    return $app->{no_print_body} = 1;
    return undef;
}

sub _box_dim {
    my ($obj) = @_;
    my ( $box_w, $box_h );
    if ( $obj->image_width > 900 ) {

        #   x    h
        #  --- = - => (900*h) / w = x
        #  900   w
        $box_w = 900;
        $box_h = int( ( 900 * $obj->image_height ) / $obj->image_width );
    }
    else {
        $box_w = $obj->image_width;
        $box_h = $obj->image_height;
    }
    return ( $box_w, $box_h );
}

1;
