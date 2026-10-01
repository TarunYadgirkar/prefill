#!/bin/zsh
# usage: sim-setup.sh <base-udid> [name]
# Clones a shut-down base simulator and prints the new simulator's UDID. The base is
# set up by hand once: import testbed/alex-rivera.vcf and set it as My Info with the
# recipe in research/REPORT.md, Appendix A. "Prefill Dev" is such a base.
source ${0:A:h}/lib.sh

base=${1:?usage: sim-setup.sh <base-udid> [name]}
name=${2:-Prefill Test $(date +%Y%m%d-%H%M%S)}

if xcrun simctl list devices | grep -q "($base) (Booted)"; then
  print "Shut down $base first: xcrun simctl shutdown $base" >&2
  exit 1
fi

xcrun simctl clone $base $name
