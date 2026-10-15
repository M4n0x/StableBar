#!/bin/zsh
set -eu
cd "${0:A:h:h}"
version=${1:?usage: scripts/set-version.sh <version> [Info.plist]}
plist=${2:-Resources/Info.plist}
# Edit the values in place so the plist keeps its layout; nothing is written unless both keys exist.
VERSION=$version perl -0777 -i -pe '
    for my $key (qw(CFBundleShortVersionString CFBundleVersion)) {
        s|(<key>$key</key>\s*<string>)[^<]*|$1$ENV{VERSION}| or die "$key not found in $ARGV\n";
    }' "$plist"
