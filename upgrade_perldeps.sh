#!/bin/bash
set -eu

cd `dirname $0`

cpan-outdated -L perl | cpanm -L perl
