#!/bin/zsh
set -eu
cd "${0:A:h:h}"
usage='usage: scripts/set-site-version.sh <version> [index.html]'
(( $# >= 1 )) || { print -u2 -- $usage; exit 1 }
version=$1
page=${2:-site/index.html}
# The website offers the stable release only, so a beta never replaces its download.
if [[ ! $version =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "The website links stable versions only, not '$version'."
    exit 1
fi
# Points every download link at the version's DMG and shows the version on the buttons and in the
# structured data. Nothing is written unless each of them is found.
VERSION=$version perl -0777 -i -pe '
    s|(releases/download/v)[^/"]*(/StableBar\.dmg)|$1$ENV{VERSION}$2|g or die "No DMG link in $ARGV\n";
    s|(<span class="ver">v)[^<]*|$1$ENV{VERSION}|g or die "No version label in $ARGV\n";
    s|("softwareVersion": ")[^"]*|$1$ENV{VERSION}| or die "No softwareVersion in $ARGV\n";
' "$page"
