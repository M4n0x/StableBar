#!/bin/zsh
set -eu
cd "${0:A:h:h}"
release=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/kvndrsslr/sketchybar-app-font/releases/latest)
version=${release:t}
icons=$(curl -fsSL "https://github.com/kvndrsslr/sketchybar-app-font/releases/download/$version/icon_map.json")
module=$(VERSION=$version perl -MJSON::PP -0777 -ne '
    my $json = JSON::PP->new->utf8->canonical->indent->indent_length(2)->space_after;
    my %glyphs = ("*" => ":default:");
    for my $icon (@{ $json->decode($_) }) {
        $glyphs{$_} = $icon->{iconName} for @{ $icon->{appNames} };
    }
    print $json->encode({ tokens => { appGlyphs => \%glyphs, sketchybarAppFontVersion => $ENV{VERSION} } });' <<< $icons)
print -r -- $module > examples/modules/sketchybar-app-font.json
