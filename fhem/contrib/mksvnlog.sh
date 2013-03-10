#!/bin/sh

SVN=/usr/bin/svn
REPO=https://fhem.svn.sourceforge.net/svnroot/fhem/trunk/fhem
REV=2400    # since start of 2013

$SVN log -v -r HEAD:$REV $REPO



