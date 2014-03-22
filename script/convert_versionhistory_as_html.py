#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import with_statement
import os.path
import StringIO
import sys
import markdown
import yaml

# config
CHANGE_KEYS = ('new', 'changed', 'fixed')
#DESTINATION = '../html'
DESTINATION = '/Users/naotaka/Development/GAE/data/clipmenu'
FILENAME = 'versionhistory/index.txt'
#INPUT_PATH = '../VersionHistory-en.yaml'
#INPUT_PATH = '../VersionHistory-ja.yaml'
DOWNLOAD_DIR = 'https://dl.dropbox.com/u/1140644/clipmenu/'

# path
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))

#basename = os.path.splitext(os.path.basename(INPUT_PATH))[0]
#dest_path = os.path.join(CURRENT_DIR, DESTINATION, basename + '.html')
#yaml_path = os.path.join(CURRENT_DIR, INPUT_PATH)

def format_date(d, locale):
    if locale == 'ja':
        return u'更新日: %s' % d.strftime("%Y年%m月%d日").decode('utf8')
    else:
        return 'Release Date: %s' % d.strftime("%b %d, %Y")

def make_download_link(version, locale):
    url = '%sClipMenu_%s.dmg' % (DOWNLOAD_DIR, version)
    link_text = 'Download'
    if locale == 'ja':
        link_text = u'ダウンロード'

    return u'[%s](%s "%s")' % (link_text, url, link_text)


# main
if len(sys.argv) != 2:
    print "変換するYAMLファイルを指定して下さい"
    exit()

arg = sys.argv[1]

name, ext = os.path.splitext(os.path.basename(arg))

if ext.lower() != '.yaml':
    print "'.yaml'の拡張子を持ったファイルを指定して下さい。"
    exit()

#basename = os.path.splitext(os.path.basename(arg))[0]
#dest_path = os.path.join(CURRENT_DIR, DESTINATION, basename + '.txt')

locale = name.split('-')[1]
dest_path = os.path.join(DESTINATION, locale, FILENAME)

# load YAML
data = None
with file(arg, 'r') as f:
    data = yaml.load(f)

# Retrieve data
string = StringIO.StringIO()
for item in sorted(data.items(), reverse=True):
    version, content = item
    download_link = make_download_link(version, locale)
    updated = format_date(content['date'], locale)
    changes = content.get('changes')

    string.write('* #### %s\n' % (version,))
    string.write('\t* %s\n' % download_link)
    string.write('\t* %s\n' % updated)

    if changes:
        for key in CHANGE_KEYS:
            change = changes.get(key)
            if not change:
                continue
            string.write('\t* [%s]\n' % key)
            for u in change:
                string.write('\t\t* %s\n' % u)

    string.write('\n')

#html = markdown.markdown(string.getvalue())
text = string.getvalue()
string.close()

# Write to HTML
with file(dest_path, 'w') as f:
    f.write(text.encode('utf8'))

    #yaml.dump(data, f, encoding='utf8', allow_unicode=True, default_flow_style=False)

