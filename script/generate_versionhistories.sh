#!/bin/sh

pwd=`pwd`
dirname=`dirname $0`
file_dir=$pwd/$dirname

script=$file_dir/convert_versionhistory_as_html.py

python $script $file_dir/../doc/VersionHistory-en.yaml
python $script $file_dir/../doc/VersionHistory-ja.yaml

