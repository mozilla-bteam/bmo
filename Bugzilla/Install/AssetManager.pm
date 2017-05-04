# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Install::AssetManager;

use 5.10.1;
use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;
use Type::Utils;
use Types::Standard qw(Bool Str ArrayRef);

use Digest::SHA ();
use Digest::MD5 qw(md5_base64);
use File::Copy qw(cp);
use File::Find qw(find);
use File::Basename qw(dirname);
use File::Spec;
use JSON::XS ();
use MIME::Base64 qw( encode_base64 );
use File::Slurp;
use List::MoreUtils qw(any all);
use Carp;

use Bugzilla::Constants qw(bz_locations);

our $VERSION = 1;

my $SHA_VERSION = '224';

my $ABSOLUTE_DIR = declare as Str, 
    where { File::Spec->file_name_is_absolute($_) && -d $_ }
    message { "must be an absolute path to a directory" };

has 'base_dir'       => ( is => 'lazy', isa => $ABSOLUTE_DIR );
has 'asset_dir'      => ( is => 'lazy', isa => $ABSOLUTE_DIR );
has 'source_dirs'    => ( is => 'lazy' );
has 'state'          => ( is => 'lazy' );
has 'state_file'     => ( is => 'lazy' );
has 'json'           => ( is => 'lazy' );

sub asset_file {
    my ($self, $file, $relative_to) = @_;
    $relative_to //= $self->base_dir;
    my $asset_file = $self->state->{asset_map}->{$file}
        or return $file;

    return File::Spec->abs2rel(
        File::Spec->catfile($self->asset_dir, $asset_file),
        $relative_to
    );
}

sub asset_files {
    my ( $self, @files ) = @_;

    return unless @files > 0;
    return $self->asset_file($files[0]) if @files == 1;

    if ( my $key = $self->_bundle_key( \@files ) ) {
        my $bundle_file = $self->state->{bundle_map}{$key};
        if ($bundle_file) {
            return File::Spec->abs2rel(
                File::Spec->catfile( $self->asset_dir, $bundle_file ),
                $self->base_dir,
            );
        }
        else {
            $self->missing(@files);
        }
    }
    else {
        die "no bundle file for @files!";
    }

    return @files;
}

sub missing {
    my ($self, @files) = @_;
    open my $fh, '>>', File::Spec->catfile(bz_locations()->{datadir}, "missing.$$");
    print $fh "@files\n";
    close $fh;
}

sub asset_sri {
    my ($self, $asset_file) = @_;
    my ($hex) = $asset_file =~ m!([[:xdigit:]]+)\.\w+$!;
    my $data = pack "H*", $hex;
    return "sha$SHA_VERSION-" . encode_base64($data, "");
}

sub compile_file {
    my ($self, $file) = @_;
    return unless -f $file;
    my $base_dir  = $self->base_dir;
    my $asset_dir = $self->asset_dir;
    my $asset_map = $self->state->{asset_map};

    my $key = File::Spec->abs2rel( $file, $base_dir );
    return if $asset_map->{$key};

    if ($file =~ /\.(jpe?g|png|gif|ico|woff|js)$/i) {
        my $ext            = $1;
        my $digest         = $self->_digest_files($file);
        my $asset_file     = File::Spec->catfile($asset_dir, "$digest.$ext");
        cp($file, $asset_file);
        if ($digest eq $self->_digest_files($asset_file)) {
            $asset_map->{$key} = File::Spec->abs2rel($asset_file, $asset_dir);
        }
        else {
            die "failed to write $asset_file";
        }
    }
    elsif ($file =~ /\.css$/) {
        my $content = read_file($file);

        # minify
        $content =~ s{(?<!=)url\(([^\)]+)\)}{$self->_css_url_rewrite($1, $file)}eig;
        my $digest = $self->_digest_strings($content);
        my $asset_file     = File::Spec->catfile($asset_dir, "$digest.css");
        write_file($asset_file, $content);
        if ($digest eq $self->_digest_files($asset_file)) {
            $asset_map->{$key} = File::Spec->abs2rel($asset_file, $asset_dir);
        }
        else {
            die "failed to write $asset_file";
        }
    }
}

sub compile_all {
    my ($self) = @_;
    my $asset_map = $self->state->{asset_map};
    my $bundle_map = $self->state->{bundle_map};
    my @bundles = map { chomp $_; [split(/\s+/, $_)] } <DATA>;

    %$asset_map = ();
    %$bundle_map = ();

    my $wanted = sub {
        $self->compile_file($File::Find::name);
    };

    find( { wanted => $wanted, no_chdir => 1 }, @{ $self->source_dirs });

    foreach my $bundle (@bundles) {
        if (my $key = $self->_bundle_key($bundle)) {
            my $ext    = (split(/\./, $bundle->[0]))[-1];
            my $content = join("",
                map { 
                    "/* $_ */\n" . read_file($self->asset_file($_))
                } @$bundle
            );
            my $digest = $self->_digest_strings($content);
            my $asset_file = File::Spec->catfile($self->asset_dir, "$digest.$ext");
            write_file($asset_file, $content);
            if ($digest eq $self->_digest_files($asset_file)) {
                $bundle_map->{$key} = File::Spec->abs2rel($asset_file, $self->asset_dir);
            }
            else {
                die "failed to write bundle: @$bundle";
            }
        }
        else {
            my @missing = grep { not exists $self->state->{asset_map}{$_} } @$bundle;
            die "bundle is not okay: @missing";
        }
    }

    $self->_save_state();
}

sub _css_url_rewrite {
    my ($self, $url, $file) = @_;
    my $dir = dirname($file);
    # rewrite relative urls as the unified stylesheet lives in a different
    # directory from the source
    $url =~ s/(^['"]|['"]$)//g;
    if ($url =~ m!^(/|data:)!) {
        return 'url(' . $url . ')';
    }
    else {
        my $url_file = File::Spec->rel2abs($url, $dir);
        my $ref_file = File::Spec->abs2rel( $url_file, $self->base_dir );
        $self->compile_file($url_file);
        return sprintf( "url(%s)", $self->asset_file($ref_file, $self->asset_dir));
    }
}

sub _bundle_key {
    my ($self, $files) = @_;
    my $asset_map = $self->state->{asset_map};

    if (all { exists $asset_map->{$_} } @$files) {
        return md5_base64(map { $asset_map->{$_} } @$files);
    }
    else {
        return undef;
    }
}

sub _new_digest { Digest::SHA->new($SHA_VERSION) }

sub _digest_files {
    my ($self, @files) = @_;
    my $digest = $self->_new_digest;
    $digest->addfile($_) for @files;
    return $digest->hexdigest;
}

sub _digest_strings {
    my ($self, @strings) = @_;
    my $digest = $self->_new_digest;
    $digest->add($_) for @strings;
    return $digest->hexdigest;
}

sub _build_base_dir  { Cwd::realpath(File::Spec->rel2abs(bz_locations->{cgi_path})) }
sub _build_asset_dir {
    my ($self) = @_;
    my $dir = Cwd::realpath(File::Spec->rel2abs(bz_locations->{assetsdir}));

    if ($dir && -d $dir) {
        my $version_dir = File::Spec->catdir($dir, "v" . $self->VERSION);
        unless (-d $version_dir) {
            mkdir $version_dir or die "mkdir $version_dir failed: $!";
        }
        return $version_dir;
    }
    else {
        return $dir;
    }
}

sub _build_source_dirs {
    my ($self) = @_;
    my $base = $self->base_dir;

    return [
        "$base/skins",
        "$base/js",
        grep { -d $_ }
        glob("$base/extensions/*/web")
    ];
}

sub _build_state_file {
    my ($self) = @_;
    return $self->asset_dir . "/state.json";
}


sub _build_state {
    my ($self) = @_;
    my $state;
    if ( open my $fh, '<:bytes', $self->state_file ) {
        local $/ = undef;
        my $json = <$fh>;
        close $fh;
        $state = $self->json->decode($json);
    }
    else {
        $state = {};
    }

    $state->{asset_map}  //= {};
    $state->{bundle_map} //= {};

    return $state;
}

sub _build_json { JSON::XS->new->canonical->utf8->pretty }

sub _save_state {
    my ($self) = @_;
    open my $fh, '>:bytes', $self->state_file or die "unable to write state file: $!";
    print $fh $self->json->encode($self->state);
    close $fh;
}

1;
__DATA__
extensions/GuidedBugEntry/web/js/products.js js/instant-search.js extensions/BMO/web/js/edituser_menu.js
extensions/ProdCompSearch/web/js/prod_comp_search.js extensions/BMO/web/js/edituser_menu.js
extensions/ProdCompSearch/web/js/prod_comp_search.js extensions/BugModal/web/bug_modal.js extensions/BugModal/web/comments.js extensions/BugModal/web/dropdown.js extensions/BugModal/web/ZeroClipboard/ZeroClipboard.min.js js/bugzilla-readable-status-min.js js/field.js js/comments.js js/util.js extensions/TrackingFlags/web/js/tracking_flags.js
extensions/ProdCompSearch/web/js/prod_comp_search.js extensions/BugModal/web/bug_modal.js extensions/BugModal/web/comments.js extensions/BugModal/web/dropdown.js extensions/BugModal/web/ZeroClipboard/ZeroClipboard.min.js js/bugzilla-readable-status-min.js js/field.js js/comments.js js/util.js extensions/TrackingFlags/web/js/tracking_flags.js extensions/EditComments/web/js/editcomments.js extensions/BMO/web/js/edituser_menu.js
js/attachment.js js/field.js js/util.js js/TUI.js extensions/BMO/web/js/edituser_menu.js extensions/Review/web/js/review.js
js/attachment.js js/util.js js/field.js js/TUI.js js/bug.js js/create_bug.js extensions/BMO/web/js/edituser_menu.js extensions/Review/web/js/review.js
js/field.js extensions/BMO/web/js/edituser_menu.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/global.js extensions/BMO/web/js/edituser_menu.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/jquery/plugins/bPopup/bPopup-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/jquery/plugins/datetimepicker/datetimepicker-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/jquery/plugins/visibility/visibility-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/yui/calendar/calendar-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/yui/calendar/calendar-min.js js/yui/connection/connection-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/yui/calendar/calendar-min.js js/yui/connection/connection-min.js js/yui/json/json-min.js js/yui/container/container-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/yui/calendar/calendar-min.js js/yui/element/element-min.js js/yui/datasource/datasource-min.js js/yui/connection/connection-min.js js/yui/json/json-min.js js/yui/datatable/datatable-min.js js/yui/button/button-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/yui/connection/connection-min.js js/yui/json/json-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/yui/element/element-min.js js/yui/datasource/datasource-min.js js/yui/connection/connection-min.js js/yui/json/json-min.js js/yui/datatable/datatable-min.js js/yui/container/container-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/global.js
js/jquery/jquery-min.js js/jquery/ui/jquery-ui-min.js js/yui/yahoo-dom-event/yahoo-dom-event.js js/yui/cookie/cookie-min.js js/yui/json/json-min.js js/yui/connection/connection-min.js js/jquery/plugins/cookie/cookie-min.js js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js js/jquery/plugins/contextMenu/contextMenu-min.js js/global.js
js/productform.js js/field.js extensions/BMO/web/js/edituser_menu.js
js/productform.js js/util.js js/TUI.js js/field.js extensions/BMO/web/js/edituser_menu.js
js/util.js js/field.js js/TUI.js js/account.js extensions/BMO/web/js/edituser_menu.js
js/util.js js/field.js js/bug.js js/comment-tagging.js extensions/BMO/web/js/edit_bug.js extensions/InlineHistory/web/inline-history.js extensions/TrackingFlags/web/js/tracking_flags.js extensions/BMO/web/js/edituser_menu.js
js/util.js js/productform.js js/TUI.js js/field.js extensions/BMO/web/js/edituser_menu.js
js/yui/assets/skins/sam/calendar.css js/yui/assets/skins/sam/datatable.css js/yui/assets/skins/sam/button.css skins/standard/global.css skins/standard/attachment.css skins/standard/enter_bug.css skins/custom/create_bug.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css extensions/Review/web/styles/review.css skins/contrib/Mozilla/global.css skins/custom/global.css
js/yui/assets/skins/sam/calendar.css skins/standard/global.css skins/standard/search_form.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css
js/yui/assets/skins/sam/calendar.css skins/standard/global.css skins/standard/search_form.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css skins/custom/search_form.css
js/yui/assets/skins/sam/calendar.css skins/standard/global.css skins/standard/show_bug.css skins/custom/bug_groups.css extensions/BMO/web/styles/edit_bug.css extensions/InlineHistory/web/style.css extensions/TagNewUsers/web/style.css extensions/TrackingFlags/web/styles/edit_bug.css extensions/UserStory/web/style/user_story.css extensions/Voting/web/style.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css extensions/Needinfo/web/styles/needinfo.css skins/contrib/Mozilla/global.css skins/custom/global.css skins/custom/show_bug.css
js/yui/assets/skins/sam/calendar.css skins/standard/global.css skins/standard/show_bug.css skins/custom/bug_groups.css extensions/BMO/web/styles/edit_bug.css extensions/InlineHistory/web/style.css extensions/TagNewUsers/web/style.css extensions/TrackingFlags/web/styles/edit_bug.css extensions/UserStory/web/style/user_story.css extensions/Voting/web/style.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css skins/custom/show_bug.css
js/yui/assets/skins/sam/datatable.css skins/standard/global.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css
js/yui3/yui/yui-min.js extensions/MyDashboard/web/js/query.js extensions/MyDashboard/web/js/flags.js extensions/ProdCompSearch/web/js/prod_comp_search.js js/bug.js extensions/BMO/web/js/edituser_menu.js
skins/custom/global.css skins/custom/search_form.css
skins/standard/global.css extensions/BMO/web/styles/choose_product.css extensions/ProdCompSearch/web/styles/prod_comp_search.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css extensions/BMO/web/styles/choose_product.css extensions/ProdCompSearch/web/styles/prod_comp_search.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css extensions/BugModal/web/bug_modal.css extensions/BugModal/web/dropdown.css skins/custom/bug_groups.css js/jquery/plugins/datetimepicker/datetimepicker.css js/jquery/plugins/contextMenu/contextMenu.css extensions/BMO/web/styles/bug_modal.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css extensions/Needinfo/web/styles/needinfo.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css extensions/BugModal/web/bug_modal.css extensions/BugModal/web/dropdown.css skins/custom/bug_groups.css js/jquery/plugins/datetimepicker/datetimepicker.css js/jquery/plugins/contextMenu/contextMenu.css extensions/TagNewUsers/web/style.css extensions/BMO/web/styles/bug_modal.css extensions/EditComments/web/styles/editcomments.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css extensions/Needinfo/web/styles/needinfo.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css extensions/MyDashboard/web/styles/mydashboard.css extensions/ProdCompSearch/web/styles/prod_comp_search.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css extensions/Review/web/styles/badge.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css extensions/MyDashboard/web/styles/mydashboard.css extensions/ProdCompSearch/web/styles/prod_comp_search.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css extensions/UserProfile/web/styles/user_profile.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css
skins/standard/global.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css skins/standard/admin.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css
skins/standard/global.css skins/standard/admin.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css skins/standard/attachment.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css skins/custom/bug_groups.css js/jquery/plugins/contextMenu/contextMenu.css extensions/MozReview/web/style/attachment.css extensions/Needinfo/web/styles/needinfo.css extensions/Review/web/styles/review.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css skins/standard/buglist.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css skins/custom/buglist.css
skins/standard/global.css skins/standard/index.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css extensions/Review/web/styles/badge.css skins/contrib/Mozilla/global.css skins/contrib/Mozilla/index.css skins/custom/global.css skins/custom/index.css
skins/standard/global.css skins/standard/index.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/contrib/Mozilla/index.css skins/custom/global.css skins/custom/index.css
skins/standard/global.css skins/standard/index.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css skins/contrib/Mozilla/global.css skins/contrib/Mozilla/index.css skins/custom/global.css skins/custom/index.css
skins/standard/global.css skins/standard/page.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css extensions/Review/web/styles/badge.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css skins/standard/page.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css skins/standard/page.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css skins/standard/reports.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css skins/standard/reports.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css skins/contrib/Mozilla/global.css skins/custom/global.css
skins/standard/global.css skins/standard/search_form.css js/jquery/ui/jquery-ui-min.css js/jquery/ui/jquery-ui-structure-min.css js/jquery/ui/jquery-ui-theme-min.css js/jquery/plugins/contextMenu/contextMenu.css skins/contrib/Mozilla/global.css skins/custom/global.css skins/custom/search_form.css
