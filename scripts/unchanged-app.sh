#!/bin/zsh
set -eu
cd "${0:A:h:h}"
# Prints the newest release before HEAD when HEAD would ship the same app: every commit since is
# docs, ci or test, and none of them, merges included, touches the files the app is built from.
# CI publishes no beta of such a commit, and a stable release ships it as the beta before it.
release=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2> /dev/null) || exit 1
git diff --quiet "$release" HEAD -- Sources Resources Package.swift Package.resolved scripts || exit 1
if git log --no-merges --format=%s "$release..HEAD" | grep -qvE '^(docs|ci|test)(\([^)]*\))?: '; then
    exit 1
fi
print -- $release
