#!/bin/zsh
set -eu
cd "${0:A:h}/.."
evaluation_dir=$(mktemp -d)
trap 'rm -rf "$evaluation_dir"' EXIT
sources=(RezilientHealth/Core/**/*.swift)
swiftc -parse-as-library "${sources[@]}" Evaluation/EvaluateInsights.swift -o "$evaluation_dir/evaluate-insights"
"$evaluation_dir/evaluate-insights" "$@"
