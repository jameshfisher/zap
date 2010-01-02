#!/usr/bin/env python

"""
Copyright (c) 2009, 2010 James Harrison Fisher <jameshfisher@gmail.com>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
"""

from os import listdir
from os.path import abspath, isdir, join, exists, split, splitext
import sys
import getopt
import gzip
import commands
from mimetypes import guess_type

helptext = """
Usage:
    james@pc:~/htdocs/$ tree -a
    .
    |-- image.png
    `-- index.html

    0 directories, 2 files

    james@pc:~/htdocs/$ zap init
    Initialized cache in ./.zap/
    james@pc:~/htdocs/$ tree -a
    .
    |-- .zap
    |   |-- gzip
    |   |   `-- index.html.gz
    |   `-- lzma
    |       `-- index.html.lzma
    |-- image.png
    `-- index.html

    1 directory, 3 files
    james@pc:~/htdocs/$ zap gzip index.html
    ... zap emits gzipped copy of index.html on stdout by cat-ing ./.zap/gzip/index.html.gz
    james@pc:~/htdocs/$ zap lzma index.html
    ... zap emits lzma'd copy of index.html on stdout by cat-ing ./.zap/lzma/index.html.gz
    james@pc:~/htdocs/$ zap lzma image.png
    ... zap generates error signifying cache miss (it's intelligent enough to know that PNG shouldn't be further zipped) ...
"""

# We DON'T define a complete server response here.
# It's just used to convey information to the invoking application.
# However, it //might// be accepted as a valid HTTP response by a client.
http_header = """HTTP 1.1 200 OK
Server: zap
Content-encoding: %(encoding)s

"""

class Encoder:
    # Represents a coding algorithm and its associated info.
    def __init__(self, binary, ext, mime):
        self.binary = binary
        self.ext = ext
        self.mime = mime

encoders = {    # A dictionary of all the encoders we know about.
    'lzma': Encoder('lzma', '.lzma', 'application/lzma'),
    'gzip': Encoder('gzip', '.gz', 'application/gzip'),
    'bzip2': Encoder('bzip2', '.bz2', 'application/bzip2'),
    'compress': Encoder('compress', '.Z', 'application/x-compress')     # On Ubuntu, this requires 'sudo apt-get install ncompress'
    }

hidden = '.zap' # The hidden directory in which we store files.

def die(dietext='Unknown error'):
    # A little helper function to die with an error.
    sys.stderr.writelines("ERROR: "+dietext+"\n")
    sys.exit(1)

def init_file(path, init_encodings):
    if isdir(path):
        die("init_file should only be called on a file.")
    dirname, basename = split(path)
    if splitext(basename)[1] in ['.zip', '.gz', '.bzip2', '.lzma', '.jpeg', '.jpg', '.png', '.gif']:
        # Files that are inappropriate for compression.
        # Everything here should be lowercase.
        return
    for encoding in init_encodings:
        encodingdir = join(dirname, hidden, encoding)
        commands.getoutput("mkdir -p %s" % encodingdir)
        zipped = join(encodingdir, basename)
        #if exists(zipped):
        #   sys.stderr.write( "%s of '%s' already exists in '%s'" % (encoding, path, zipped) +"\n")
        #else:
        #sys.stderr.write( "Making %s of '%s' in '%s' ..." % (encoding, path, zipped) +"\n")
        commands.getoutput("cp -f %s %s" % (path, zipped))
        commands.getoutput( "%s -f %s" % (encoders[encoding].binary, zipped) )

def init(path, init_encodings=encoders.keys(), recursive=False):
    """
    Caches all contents.
    """
    if not isdir(path):
        die("init should only be run against a directory.")
    
    clear(path, init_encodings, recursive)  # Make sure we're working with a fresh directory tree
    
    for f in listdir(path):
        f = join(path, f)
        if isdir(f):
            if recursive and f[0] != '.':
                init(f, init_encodings, recursive)
        else:
            init_file(f, init_encodings)

def clear(path, clear_encodings=encoders.keys(), recursive=False):
    """
    Clears the cache.
    """
    if not isdir(path):
        die()
    
    for f in listdir(path):
        f = join(path,f)
        if isdir(f):
            if recursive:
                clear(join(path,f), clear_encodings, recursive)
    
    zapdir = join(path, hidden)
    
    if not exists(zapdir):
        return
    
    for encoding in clear_encodings:
        deldir = join(zapdir, encoding)
        if exists(deldir):
            if not isdir(deldir):
                die("The path '%s' should be a directory!" % deldir)
            commands.getstatusoutput("rm -R %s" % deldir)
    if len(listdir(zapdir)) == 0:
        commands.getstatusoutput("rmdir %s" % zapdir)
                

def get(path, get_encodings, miss="ok"):
    
    if isdir(path):
        die("get must run against a file.")
    
    type = guess_type(path)[0]
    
    if miss=="no":
        preferred = get_encodings[0]
        init_file(path, [preferred])    # Initialize the preferred encoding, so it'll be found below.  (We rely on init_file to be intelligent enough to recognise if the file is already init'd.)
    
    dirname, basename = split(path)
    zapdir = join(dirname, hidden)
    
    for encoding in get_encodings:
        lookat = join(zapdir, encoding, basename) + encoders[encoding].ext
        if exists(lookat):
            f = open(lookat, 'r')
            content = f.read()
            f.close()

            sys.stderr.writelines( http_header % {
                'encoding': encoders[encoding].mime,
                'type': type
                })
            print content
            sys.exit(0)
    
    if miss=="plain":
        f = open(path, 'r')
        content = f.read()
        f.close()
        sys.stderr.writelines( http_header % {
            'encoding': "identity", # I think this is right
            'type': type
            })
        print content
        sys.exit(0)
        
    else:
        sys.stderr.writelines("Cache miss")
        sys.exit(2) # This should be interpreted as meaning "cache miss"

if __name__ == "__main__":
    recursive = False
    encoding = "gzip"
    miss = "ok"
    
    options, remainder = getopt.gnu_getopt(sys.argv[1:], 're:m:h', ['recursive', 'encoding=', 'miss=', 'help'])
    for option, value in options:
        if option in ('-r', '--recursive'):
            recursive = True
        elif option in ('-m', '--miss'):
            if value in ["ok", "plain", "no"]:
                miss = value
            else:
                die("The miss option `%s' was not understood")
        elif option in ('-e', '--encoding'):
            encoding = value
        elif option in ('-h', '--help'):
            print helptext
            sys.exit(0)
    
    if encoding == "all":
        encoding = encoders.keys()  # Replace wildcard with all encodings
    else:
        encoding = encoding.split(",")
        for e in encoding:
            if e not in encoders.keys():
                die("The encoding '%s' is not known." % e)
    
    try:
        cmd = remainder[0]
    except IndexError:
        die("Please provide a command.")
    else:
        try:
            path = remainder[1]
        except IndexError:
            path = '.'
        path = abspath(path)
        if cmd == "help":
            print helptext
        elif cmd == "init":
            init(path, encoding, recursive)
        elif cmd == "clear":
            clear(path, encoding, recursive)
        elif cmd == "get":
            get(path, encoding, miss)
        else:
            die("Please provide a command.")
else:
    die("Zap must be executed.  Do not include it as a module.")
