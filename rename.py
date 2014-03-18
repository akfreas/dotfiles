#!/usr/bin/env python
"""
Author: Matt Weber
Date:   03/04/07

Renames files based on the input options.
"""

import os
import sys
from optparse import OptionParser

def RenameFile(options, filepath):
  """
  Renames a file with the given options
  """
  # split the pathname and filename
  pathname = os.path.dirname(filepath)
  filename = os.path.basename(filepath)
  
  # trim characters from the front
  if options.trimfront:
    filename = filename[options.trimfront:]

  # trim characters from the back
  if options.trimback:
    filename = filename[:len(filename)-options.trimback]

  # replace values if any
  if options.replace:
    for vals in options.replace:
      filename = filename.replace(vals[0], vals[1])

  # convert to lowercase if flag set
  if options.lowercase:
    filename = filename.lower()
  
  # create the new pathname and rename the file
  new_filepath = os.path.join(pathname, filename)
  try:
    # check for verbose output
    if options.verbose:
      print "%s -> %s" % (filepath, new_filepath)
    
    os.rename(filepath, new_filepath)
  except OSError, ex:
    print >>sys.stderr, "Error renaming '%s': %s"  % (filepath, ex.strerror)

if __name__ == "__main__":
  """
  Parses command line and renames the files passed in
  """
  # create the options we want to parse
  usage = "usage: %prog [options] file1 ... fileN"
  optParser = OptionParser(usage=usage)
  optParser.add_option("-v", "--verbose", action="store_true", dest="verbose", default=False,
                        help="Use verbose output")
  optParser.add_option("-l", "--lowercase", action="store_true", dest="lowercase", default=False,
                        help="Convert the filename to lowercase")
  optParser.add_option("-f", "--trim-front", type="int", dest="trimfront", metavar="NUM",
                        help="Trims NUM of characters from the front of the filename")
  optParser.add_option("-b", "--trim-back", type="int", dest="trimback", metavar="NUM",
                        help="Trims NUM of characters from the back of the filename")
  optParser.add_option("-r", "--replace", action="append", type="string", nargs=2, dest="replace",
                        help="Replaces OLDVAL with NEWVAL in the filename", metavar="OLDVAL NEWVAL")
  (options, args) = optParser.parse_args()
 
  # check that they passed in atleast one file to rename
  if len(args) < 1:
    optParser.error("Files to rename not specified")

  # loop though the files and rename them
  for filename in args:
     RenameFile(options, filename)
  
  # exit successful
  sys.exit(0)
