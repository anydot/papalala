#!/bin/sh
set -eu

cd `dirname $0`

cpanm -L perl Cz::Cstocs Hailo Net::Twitter
