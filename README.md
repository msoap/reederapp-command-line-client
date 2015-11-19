Reeder.app command-line client
==============================

**Important:** compatible with DB of Reeder.app v1 (not with v2 or v3).

DESCRIPTION
-----------

reeder-get-all-unread-feeds.pl

Generate html files for all unread feed items from [Reeder.app](http://reederapp.com/mac/)

SYNOPSIS
--------

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

EXAMPLES
--------

List unread feeds (with id):

    reeder-get-all-unread-feeds.pl --list

List all feeds with stared items:

    reeder-get-all-unread-feeds.pl --list --stared

Print unread items:

    reeder-get-all-unread-feeds.pl --print

Print unread items for 7 last days:

    reeder-get-all-unread-feeds.pl --print --age=7

Create html files for all unread items (one file per feed):

    reeder-get-all-unread-feeds.pl

Create html files for all stared items (for last year):

    reeder-get-all-unread-feeds.pl --stared --age=365

Create html files for unread some feeds (id 7 and 9):

    reeder-get-all-unread-feeds.pl --feeds=7,9

INSTALLATION
------------
Install dependencies:

    sudo cpan Template
    sudo cpan Image::ExifTool
    sudo cpan Lingua::Translit

Others dependencies already exists in Mac OS X 10.7 - DBI, DBD::SQLite and LWP perl modules.

And install script:

if `~/bin/` exists in your `$PATH`:

    curl "https://raw.github.com/msoap/reederapp-command-line-client/master/reeder-get-all-unread-feeds.pl" > ~/bin/reeder-get-all-unread-feeds.pl
    chmod 744 ~/bin/reeder-get-all-unread-feeds.pl

or

    sudo sh -c 'curl "https://raw.github.com/msoap/reederapp-command-line-client/master/reeder-get-all-unread-feeds.pl" > /usr/local/bin/reeder-get-all-unread-feeds.pl'
    sudo sh -c 'chmod 744 /usr/local/bin/reeder-get-all-unread-feeds.pl'

AUTHOR
------
Sergey Mudrik
