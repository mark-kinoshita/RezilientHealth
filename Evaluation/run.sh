#!/bin/zsh
set -eu
cd "${0:A:h}/.."
evaluation_dir=$(mktemp -d)
trap 'rm -rf "$evaluation_dir"' EXIT
sources=(
  RezilientHealth/HealthData/Models/*.swift
  RezilientHealth/HealthData/Aggregation/*.swift
  RezilientHealth/Insights/*.swift
  RezilientHealth/Assistant/**/*.swift
)
# The standalone macOS evaluator exercises Gemini and the shared contract.
sources=("${sources[@]:#*AppleFoundationModelClient.swift}")
swiftc -parse-as-library "${sources[@]}" Evaluation/EvaluateInsights.swift -o "$evaluation_dir/evaluate-insights"
"$evaluation_dir/evaluate-insights" "$@"
