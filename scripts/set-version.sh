#!/bin/zsh
set -eu
cd "${0:A:h:h}"
usage='usage: scripts/set-version.sh <version> <build number> [Info.plist]'
(( $# >= 2 )) || { print -u2 -- $usage; exit 1 }
version=$1
build=$2
plist=${3:-Resources/Info.plist}
# CFBundleVersion takes one to three dot-separated integers, so a prerelease version can't go there.
if [[ ! $build =~ '^[0-9]+(\.[0-9]+){0,2}$' ]]; then
    print -u2 "The build number must be one to three dot-separated integers, not '$build'."
    exit 1
fi
# Edit the values in place so the plist keeps its layout; nothing is written unless both keys exist.
VERSION=$version BUILD=$build perl -0777 -i -pe '
    my %value = (CFBundleShortVersionString => $ENV{VERSION}, CFBundleVersion => $ENV{BUILD});
    for my $key (sort keys %value) {
        s|(<key>$key</key>\s*<string>)[^<]*|$1$value{$key}| or die "$key not found in $ARGV\n";
    }' "$plist"
