#!/bin/sh

pwd=`pwd`
dirname=`dirname $0`
file_dir=$pwd/$dirname


# var

folder="ClipMenu"
target_path=~/Desktop/$folder

app="ClipMenu.app"
app_path="$file_dir/../build/Release/$app"
readme="ReadMe.rtfd"
readme_path="$file_dir/../doc/$readme"
readme_ja="ReadMe (Japanese).rtfd"
readme_ja_path="$file_dir/../doc/$readme_ja"
how_to_write_js_action="$file_dir/../doc/JavaScriptアクションの書き方.txt"
webloc="ClipMenu website.webloc"
webloc_path="$file_dir/../doc/$webloc"


# main

mkdir -p $target_path

if [ -e $app_path ]
then
    cp -r $app_path $target_path
    echo $app copy completed.
fi

if [ -e $readme_path ]
then
    cp -fr $readme_path $target_path
    # sh $file_dir/remove_svn_dir.sh $target_path/$readme
    echo $readme copy completed.
fi

if [ -e "$readme_ja_path" ]
then
    cp -fr "$readme_ja_path" $target_path
    echo "$readme_ja" copy completed.
fi

if [ -f $how_to_write_js_action ]
then
    cp $how_to_write_js_action $target_path
    echo how_to_write copy completed.
fi

if [ -e "$webloc_path" ]
then
    cp -fr "$webloc_path" "$target_path"
    echo "$webloc" copy completed.
fi

if [ -e $target_path ]
then
     hdiutil create -srcfolder $target_path -format UDBZ $target_path.dmg
     echo diskimage making completed.
 fi
