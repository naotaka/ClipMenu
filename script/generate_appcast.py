#!/usr/bin/env python
# -*- coding: utf-8 -*-

import datetime
import findertools
import os
import os.path
import shutil
import subprocess
import tempfile
from string import Template
from xml.etree.ElementTree import ElementTree
from PyRSS2Gen import RSS2, RSSItem, Enclosure, _element, _opt_element

class SparkleRSS(RSS2):
    RSS2.rss_attrs['xmlns:sparkle'] = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
    RSS2.rss_attrs['xmlns:dc'] = 'http://purl.org/dc/elements/1.1/'

class SparkleRSSItem(RSSItem):
    def __init__(self, sparkle_release_note_link=None, **args):
        self.sparkle_release_note_link = sparkle_release_note_link
        RSSItem.__init__(self, **args)

    def publish_extensions(self, handler):
        if self.sparkle_release_note_link:
            _opt_element(handler, 'sparkle:releaseNotesLink', self.sparkle_release_note_link)

class SparkleEnclosure(Enclosure):
    def __init__(self, url, length, type, sparkle_version, sparkle_dsa_signature):
        Enclosure.__init__(self, url, length, type)
        self.sparkle_version = sparkle_version
        self.sparkle_dsa_signature = sparkle_dsa_signature

    def publish(self, handler):
        _element(handler, 'enclosure', None,
                {
                    'url': self.url,
                    'length': str(self.length),
                    'type': self.type,
                    'sparkle:version': str(self.sparkle_version),
                    'sparkle:dsaSignature': self.sparkle_dsa_signature,
                    })

def jst_to_gmt(dt):
    return dt - datetime.timedelta(hours=9)

def generate_sparkle_rss(d, params):
    items = [
            SparkleRSSItem(
                title = 'Version %s' % params['version'],
                sparkle_release_note_link = d['sparkle_release_note_link'],
                pubDate = jst_to_gmt(params['last_modified']),
                enclosure = SparkleEnclosure(
                    url = 'http://dl.dropbox.com/u/1140644/clipmenu/%s' % params['archive_name'],
                    length = params['length'],
                    type = 'application/octet-stream',
                    sparkle_version = '%s' % params['version'],
                    sparkle_dsa_signature = params['dsa_signature'],
                    )
                ),
            ]

    rss = SparkleRSS(
            title=d['title'],
            link=d['link'],
            language=d['language'],
            description=d['description'],
            lastBuildDate = jst_to_gmt(datetime.datetime.now()),
            items = items,
            )

    destination = "%s%s.xml" % (OUTPUT_DIR, d['filename'])
    rss.write_xml(open(destination, 'w'), encoding='UTF-8')


# Config
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.split(CURRENT_DIR)[0]
INFO_PLIST = "%s/Info.plist" % PROJECT_DIR
DSA_PRIVATE_PEM_PATH = "%s/dsa_priv.pem" % PROJECT_DIR
APP_NAME = 'ClipMenu'
APP_FILENAME = '%s.app' % APP_NAME
APP_DIR = "%s/build/Release/" % PROJECT_DIR
DOC_DIR = os.path.join(PROJECT_DIR, 'doc')
ARCHIVE_DOC_DIR = os.path.join(DOC_DIR, 'archive_contents')
RELEASE_NOTE_HTML = 'release_note.html'
RELEASE_NOTE_JA_HTML = 'release_note_ja.html'
PRE_RELEASE_NOTE_HTML = 'pre_release_note.html'
PRE_RELEASE_NOTE_JA_HTML = 'pre_release_note_ja.html'
OUTPUT_DIR = '/Users/naotaka/Sites/sparkle/'
PUBLIC_URL = 'http://dl.dropbox.com/u/1140644/clipmenu/'

version = None

docs = [
        'ReadMe.rtfd',
        'ReadMe (Japanese).rtfd',
        u'JavaScriptアクションの書き方.txt',
        'ClipMenu website.webloc',
        ]

en = {
        'filename' : 'appcast',
        'title' : 'ClipMenu ChangeLog',
        'link' : 'http://www.clipmenu.com/',
        'description' : 'Most recent changes with links to updates.',
        'language' : 'en',
        'sparkle_release_note_link': 'http://dl.dropbox.com/u/1140644/clipmenu/release_note.html',
        }
ja = {
        'filename' : 'appcast_ja',
        'title' : u'ClipMenu 更新履歴',
        'link' : 'http://www.clipmenu.com/',
        'description' : u'変更点',
        'language' : 'ja',
        'sparkle_release_note_link': 'http://dl.dropbox.com/u/1140644/clipmenu/release_note_ja.html',
        }
queue = (en, ja)

## Main

def main():
    print "start generator..."

    # Read plist
    tree = ElementTree()
    elem = tree.parse(INFO_PLIST)
    children = elem.find('dict').getchildren()
    it = iter(children)
    for child in it:
        if child.tag == 'key' and child.text == 'CFBundleShortVersionString':
            version = it.next().text
            break
        else:
            continue

    print "version: %s" % version

    # Make archive
    app_path = "%s%s" % (APP_DIR, APP_FILENAME)
    release = (version.split('.')[2].isdigit())
    archive_type = 'dmg' if release else 'zip'
    archive_name = "%s_%s.%s" % (APP_NAME, version, archive_type)
    archive_path = "%s/%s" % (OUTPUT_DIR, archive_name)

    if not os.path.exists(app_path):
        print "%s is not found" % app_path
        exit()

    if os.path.exists(archive_path):
        os.remove(archive_path)

    p = None
    temp_dir = None

    if (release):
        temp_dir = tempfile.mkdtemp()
        print "temp_dir: %s" % temp_dir

        try:
            os.chdir(temp_dir)
            shutil.copytree(APP_DIR, APP_NAME, symlinks=True)
            for doc in docs:
                doc_path = os.path.join(ARCHIVE_DOC_DIR, doc)
                if os.path.isdir(doc_path):
                    doc_dest = os.path.join(APP_NAME, os.path.split(doc_path)[1])
                    shutil.copytree(doc_path, doc_dest, symlinks=True)
                else:
                    shutil.copy2(doc_path, APP_NAME)
        except OSError, e:
            print e
            shutil.rmtree(temp_dir)
            exit()

        p = subprocess.Popen(['hdiutil', 'create', '-srcfolder', APP_NAME, '-format', 'UDBZ', archive_path], stdout=subprocess.PIPE)
    else:
        p = subprocess.Popen(['zip', '-ry9', archive_path, APP_FILENAME], stdout=subprocess.PIPE, cwd=APP_DIR)

    p.communicate()

    if temp_dir and os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)

    if p.returncode != 0:
        print "Fail to make %s archive!" % archive_type
        exit()

    statinfo = os.stat(archive_path)
    length = statinfo.st_size
    last_modified = datetime.datetime.fromtimestamp(statinfo.st_mtime)
    print "length: %d, mtime: %s" % (length, last_modified)
    #print "length: %d, atime: %d, mtime: %d, ctime: %d" % (length, statinfo.st_atime, statinfo.st_mtime, statinfo.st_ctime)

    # DSA signature
    p1 = subprocess.Popen(['openssl', 'dgst', '-sha1', '-binary',  archive_path], stdout=subprocess.PIPE)
    p2 = subprocess.Popen(['openssl', 'dgst', '-dss1', '-sign', DSA_PRIVATE_PEM_PATH], stdin=p1.stdout, stdout=subprocess.PIPE)
    p3 = subprocess.Popen(['openssl', 'enc', '-base64'], stdin=p2.stdout, stdout=subprocess.PIPE)
    dsa_signature = p3.communicate()[0]

    if not dsa_signature:
        print ("Failed to generate DSA signature")
        exit()

    print "dsa_signature: %s" % dsa_signature

    rss_params = {
            'version': version,
            'archive_name': archive_name,
            'length': length,
            'last_modified': last_modified,
            'dsa_signature': dsa_signature,
            }

    for d in queue:
        # Make release notes
        release_note_filename = RELEASE_NOTE_HTML if d['language'] == 'en' else RELEASE_NOTE_JA_HTML
        release_note_path = os.path.join(DOC_DIR, release_note_filename)
        with open(release_note_path, 'r') as f:
            t = Template(f.read())
            html_params = {
                    'version': version,
                    'date': last_modified,
                    }
            substituted_html = t.substitute(html_params)

            if (release):
                release_note_filename = RELEASE_NOTE_HTML if d['language'] == 'en' else RELEASE_NOTE_JA_HTML
            else:
                release_note_filename = PRE_RELEASE_NOTE_HTML if d['language'] == 'en' else PRE_RELEASE_NOTE_JA_HTML

            with open(os.path.join(OUTPUT_DIR, release_note_filename), 'w') as o:
                o.write(substituted_html)

        # Generate RSS
        if not release:
            d['filename'] = "pre_%s" % d['filename']
            d['sparkle_release_note_link'] = os.path.join(PUBLIC_URL, release_note_filename)

        rss = generate_sparkle_rss(d, rss_params)


if __name__ == '__main__':
    main()

