#!/usr/bin/perl

=head1 NAME

reeder-get-all-unread-feeds.pl

Generate html for all unread feeds from Reeder.app

=head1 SYNOPSIS

    reeder-get-all-unread-feeds.pl [options]
    --db-path=...   -- custom path to db files; default is ~/Library/Application Support/Reeder/*@*/
    --list          -- show list of feeds
    --print         -- print items only to stdout
    --print-body    -- print items with body to stdout
    --feeds=id1,id2 -- get feeds; default is get all unread feed
    --all           -- get all items; default is get unread feeds only
    --stared        -- get all stared items
    --age=days      -- get items for N days ago
    --ua=...        -- custom user-agent for download images
    --out-dir=...   -- dir for html files with feed items; default is ./reederapp-feeds/
    --help
    --version

=head1 AUTHOR

Sergey Mudrik <sergey.mudrik@gmail.com>

=cut

use warnings;
use strict;

use POSIX qw/strftime/;
use URI::WithBase;
use MIME::Base64 qw(encode_base64);
use Getopt::Long;
use Pod::Usage;

use DBI;
use LWP::UserAgent;
use Template;
use Image::ExifTool;
use Lingua::Translit;

our $VERSION = 0.09;
our $DEFAULT_DIR_FOR_HTML = './reederapp-feeds';
our $UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_4) AppleWebKit/534.57.2 (KHTML, like Gecko) Version/5.1.7 Safari/534.57.2";
our $DB_PATH = "$ENV{HOME}/Library/Application Support/Reeder";
our $CACHE_PATH = "$ENV{HOME}/Library/Caches";
our $LAST_JQUERY_LIB = "jquery-1.7.2.js";
our $TIMEOUT = 120;

# ------------------------------------------------------------------------------
{
    my %www_cache;

sub lwp_load {
    my $url = shift;
    my $base_url = shift;

    my $abs_url = $base_url ? URI::WithBase->new($url, $base_url)->abs() : $url;

    return $www_cache{$abs_url} if $www_cache{$abs_url};

    my $response = LWP::UserAgent
                   ->new(agent => $UA, timeout => $TIMEOUT)
                   ->request(HTTP::Request->new("GET", $abs_url));

    if ($response->code != 200) {
        $www_cache{$abs_url} = {code => $response->code, message => $response->message, abs_url => $abs_url};
    } else {
        $www_cache{$abs_url} = {code => $response->code
                              , abs_url => $abs_url
                              , content => $response->content()
                              , content_type => ($response->header('Content-Type') || undef)};
    }

    return $www_cache{$abs_url};
}}

# ------------------------------------------------------------------------------
sub load_and_replace_img {
    my $tag = shift;

    # remove align="..."
    $tag =~ s/\s align \s* = \s* (['"]?) \w+ \1/ /six;

    if ($tag =~ /src \s* = \s* (["']*) ([^\s"']+) ["']*/six) {

        my $quote = $1;
        my $img_url = get_img_data_url($2);
        $tag =~ s/src \s* = \s* ["']* [^\s"']+ ["']*/src=${quote}${img_url}${quote}/six;
    }

    return $tag;
}

# ------------------------------------------------------------------------------
sub get_img_data_url {
    my $url = shift;
    my $base_url = $url;

    $url =~ s/\s+//sg;
    return $url if $url =~ /^data:/;

    my $img = lwp_load($url, $base_url);
    print "  get $url";

    my $content = $img->{content};
    if ($content) {

        my $type = $img->{content_type};
        unless ($type) {
            my $exifTool = new Image::ExifTool;
            $exifTool->ExtractInfo(\$content);
            $type = $exifTool->GetValue("MIMEType");

            $type = 'image/x-icon' if (! $type && $url =~ /\.ico$/i);
            $type = 'image/jpeg' if ! $type;
        }

        unless ($type) {
            print " - error: not find mime type\n";
            return $img->{abs_url};
        }

        my $base64_data = encode_base64($content);
        $base64_data =~ s/\s+//g;

        print " - ok\n";
        return "data:$type;base64,$base64_data";
    } else {
        print " - error: not download image ($img->{abs_url})\n";
        return $img->{abs_url};
    }
}

# ------------------------------------------------------------------------------
sub sanitaze_filename {
    for ($_[0]) {
        s/\s+/_/g;
        s/[^a-z0-9\.\-_]//gi;
        s/\.{2,}/./g;
        s/\.$//;
    }
}

# ------------------------------------------------------------------------------
sub init {
    my $result = {};
    my $custom_db_path;

    GetOptions(
        'db-path=s' =>  \$custom_db_path,
        'out-dir=s' =>  \$result->{dir_out},
        'list|ls' =>    \$result->{show_list_only},
        'all' =>        \$result->{get_all_items},
        'stared' =>     \$result->{get_stared_items},
        'print' =>      \$result->{print_only},
        'print-body' => \$result->{print_only_with_body},
        'ua=s' =>       \$result->{user_agent},
        'feeds=s' =>    \$result->{feeds},
        'age=i' =>      \$result->{age_days},
        'help' => sub {
            pod2usage(-exitval => 0, -verbose => 99, -sections => "NAME|SYNOPSIS");
        },
        'version' => sub {
            print "$VERSION\n";
            exit 0;
        },
    );

    $result->{dir_out} = $DEFAULT_DIR_FOR_HTML unless defined $result->{dir_out};
    $result->{print_only} = 1 if $result->{print_only_with_body};
    $UA = $result->{user_agent} if defined $result->{user_agent};

    if (defined $result->{feeds} && $result->{feeds} !~ m/^\d+(,\d+)*$/) {
        die "feeds id is invalid (--feeds)\n";
    }

    # load jquery
    if (-f "$CACHE_PATH/$LAST_JQUERY_LIB") {
        open my $FH, '<', "$CACHE_PATH/$LAST_JQUERY_LIB" or die "Error open file: $!\n";
        $result->{jquery_content} = join "", <$FH>;
        close $FH;
    } else {
        $result->{jquery_content} = lwp_load("http://code.jquery.com/$LAST_JQUERY_LIB")->{content};
        if ($result->{jquery_content}) {
            open my $FH, '>', "$CACHE_PATH/$LAST_JQUERY_LIB" or die "Error open file: $!\n";
            print $FH $result->{jquery_content};
            close $FH;
        } else {
            warn "jQuery download failed ($LAST_JQUERY_LIB)\n";
            $result->{jquery_content} = "// jQuery download failed ($LAST_JQUERY_LIB)";
        }
    }

    # get db files with paths
    my @dirs = $custom_db_path ? ($custom_db_path) : glob "\Q$DB_PATH/\E*\@*";
    for my $dir (@dirs) {
        if (-f "$dir/reeder.db" && -r "$dir/reeder.db"
            &&
            -f "$dir/reeder-data.db" && -r "$dir/reeder-data.db"
           )
        {
            $result->{db_file1} = "$dir/reeder.db";
            $result->{db_file2} = "$dir/reeder-data.db";
            last;
        }
    }

    die "reeder db files not found\n" unless $result->{db_file1} && $result->{db_file2};

    return $result;
}

# ------------------------------------------------------------------------------
sub main {
    my $ctx = init();

    my $dbh1 = DBI->connect("dbi:SQLite:$ctx->{db_file1}");
    my $dbh2 = DBI->connect("dbi:SQLite:$ctx->{db_file2}");

    my @sql_where;
    if ($ctx->{feeds}) {
        push @sql_where, "s.rowid in ($ctx->{feeds})";
    }

    my $add_sql = '';

    if ($ctx->{show_list_only}) {
        if ($ctx->{get_stared_items}) {
            push @sql_where, "s.starredCount > 0";
        }

        if (! $ctx->{get_all_items} && ! $ctx->{get_stared_items} && ! $ctx->{feeds}) {
            push @sql_where, "s.unreadCount > 0";
        }
        $add_sql = @sql_where ? "and " . join(' and ', @sql_where) : "";

        my $list_data = $dbh1->selectall_arrayref(
            "select rowid, s.*
             from reader_streams s
             where type = 'f'
               and visible = 1
               $add_sql
            ", {Slice => {}}
        ) || [];

        print join("\t", 'id', "title", "link", "unread_count", "starred_count") . "\n";
        for my $row (@$list_data) {
            print join("\t", $row->{rowid}, $row->{title}, $row->{link} || '', $row->{unreadCount}, $row->{starredCount}) . "\n";
        }

        return;
    }

    if ($ctx->{get_stared_items}) {
        push @sql_where, "i.starred > 0";
    }

    if ($ctx->{age_days} && $ctx->{age_days} =~ m/^\d+$/) {
        push @sql_where, "i.published > " . ((time() - $ctx->{age_days} * 3600 * 24) * 1_000_000);
    }

    if (! $ctx->{get_all_items} && ! $ctx->{get_stared_items}) {
        push @sql_where, "i.unread > 0";
    }

    $add_sql = @sql_where ? "and " . join(' and ', @sql_where) : "";

    my $raw_data = $dbh1->selectall_arrayref(
        "select i.id, i.stream_id, i.title, i.link as source, s.title as stream_title, published as date
         from reader_items i
           join reader_streams s on i.stream_id = s.id
         where s.type = 'f'
           and s.visible = 1
           $add_sql
           order by published
        ", {Slice => {}}
    ) || [];

    return unless @$raw_data;

    my $all_items_id_sql = join(',', map {$dbh1->quote($_->{id})} @$raw_data);
    my %content = map {$_->{id} => $_->{content}}
                  @{$dbh2->selectall_arrayref(
                      "select id, content
                      from reader_items_data
                      where id in ($all_items_id_sql)
                      ", {Slice => {}}
                  ) || []};

    my %nodes;
    for my $row (@$raw_data) {
        $row->{description} = $content{$row->{id}};
        push @{ $nodes{$row->{stream_id}} }, $row;
    }

    my $tr = new Lingua::Translit("ISO 9");
    my $tt = Template->new();
    my $template = join '', <DATA>;

    while (my ($key, $items) = each %nodes) {

        next unless @$items;
        my $title = $items->[0]->{stream_title};

        for my $row (@$items) {
            $row->{date} = strftime("%Y-%m-%d", localtime(int($row->{date} / 1_000_000)));
            $row->{description} =~ s/(<img[^>]+>)/load_and_replace_img($1)/sige unless $ctx->{print_only};
        }

        my $html_file_name = lc($tr->translit($title));
        sanitaze_filename($html_file_name);
        $html_file_name = $key if $html_file_name eq '';
        sanitaze_filename($html_file_name);

        if ($ctx->{print_only}) {

            print "$title\n";
            for my $row (@$items) {
                print " $row->{date} $row->{title}\n";
                if ($ctx->{print_only_with_body}) {
                    my $description = $row->{description};
                    $description =~ s/<br>/\n/gi;
                    print "$description\n\n";
                }
            }

        } else {
            print STDERR "$title:\n";

            mkdir $ctx->{dir_out} unless -d $ctx->{dir_out};
            die "$ctx->{dir_out} is not writable dir\n" unless -d $ctx->{dir_out} && -w $ctx->{dir_out};

            my $rand_str = encode_base64(rand());
            sanitaze_filename($rand_str);

            $tt->process(\$template, {title => $title
                                    , items => $items
                                    , rand_str => $rand_str
                                    , jquery_content=> $ctx->{jquery_content}
                                     }, "$ctx->{dir_out}/$html_file_name.html"
                        ) || die $tt->error(), "\n";
        }
    }
}

# ------------------------------------------------------------------------------
main();

__DATA__
<!doctype html>
<html>
<head>
    <meta http-equiv="content-type" content="text/html; charset=utf-8">
    <meta name="description" content="feed items from Reeder.app">
    <title>[% title %]</title>

    <style>
      body {
          margin-left: 3%;
          margin-right: 3%;
          background-color: white;
      }

      .selected_[% rand_str %] {
          background-color: e0e0e0;
      }

      .rss_item_[% rand_str %] {
          border-bottom: 1px solid #b0b0b0;
          padding: 5px;
          padding-top: 15px;
      }

      @media print {
          .not_print_[% rand_str %] {
              display: none;
          }

          .rss_item_[% rand_str %] {
              border-bottom: 1px solid black;
              padding: 3px;
          }

          .selected_[% rand_str %] {
              background-color: white;
          }
      }
    </style>

    <script type="text/javascript">
    [% jquery_content %]
    </script>

    <script type="text/javascript">

      function select_item(div) {
          $(div).toggleClass("selected_[% rand_str %]");
          $('input:checkbox', $(div)).get(0).checked = $(div).hasClass("selected_[% rand_str %]");
          generate();
      }

      function generate() {
          var links = new Array;

          $('div.selected_[% rand_str %]').each(
              function () {
                  links.push($('a', $(this)).get(0).href);
              }
          );

          $("#result").val(links.join("\n"));
      }

      function select_all() {
          $("#result").select();
      }
    </script>
</head>
<body>
    <h3>[% title %]</h3>
    [% FOR i = items %]
      <div class="rss_item_[% rand_str %]" onClick="select_item(this)">
        [% loop.count %].
        <input type="checkbox" class="not_print_[% rand_str %]">
        <a href="[% i.source %]"><b>[% i.title || '---' %]</b></a>
        <small style="color: gray;" class="not_print_[% rand_str %]">/ [% i.date %]</small>
        <br>
        [% i.description %]
      </div>
    [% END %]

    <div class="not_print_[% rand_str %]">
        <br>
        <a href="#" onClick="select_all(); return false;" style="border-bottom: 1px dotted #808080;">select all...</a>
        <br>
        <textarea id="result" style="width: 100%; height: 200px;"></textarea>
    </div>
</body>
</html>
