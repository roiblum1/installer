#######################################################################
# Copyright (C) 2023 VMWare, Inc.
# All Rights Reserved
#######################################################################
"""Image Factory Server Starter"""

import sys
import os

SUPPORTED_PYTHON_VERSIONS = (
   "python-37", "python-38",
   "python-39", "python-310",
   "python-311", "python-312")

SERVER_DIR = os.path.abspath(os.path.dirname(__file__))
PYTHON_DIST = "python-{major}{minor}".format(major=sys.version_info.major,
                                             minor=sys.version_info.minor)

if PYTHON_DIST not in SUPPORTED_PYTHON_VERSIONS:
   # Error code 5 stands for an attempt to start if-server with an
   # unsupported Python version.
   # ImageBuilder supports python versions 3.7 through to 3.11.
   #
   # Code needs to be in sync with IfServer.cs.
   sys.exit(5)

PYTHON_DIR = os.path.join(SERVER_DIR, PYTHON_DIST)
if PYTHON_DIR not in sys.path:
   # PR3224811
   # Insert internal paths at the start of sys.path as we have a known case when
   # a customer fails to use VMware.ImageBuilder when they have installed the
   # publicly available pyVmomi distribution through pip, for example.
   # This way we ensure that the internal packages will be loaded first as they
   # are the ones ImageBuilder is intended to be used with.
   # This is a huge hack, but we have customers who are unwilling to maintain a
   # second version of Python and want to keep the public pyVmomi in their
   # version.
   #
   # Small possibility of missing this insert in first position if the sys.path
   # already contains an entry for this location but the chances of that are
   # extremely low and the customer needs to have tampered with the environment
   # which is not expected.
   sys.path.insert(0, PYTHON_DIR)

import ifServer

def main(args):
   ifServer.main(args)

if __name__ == "__main__":
    main(sys.argv)

