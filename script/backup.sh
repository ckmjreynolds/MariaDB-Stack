#!/bin/bash
# **************************************************************************************
# MIT License
#
# Copyright (c) 2019 Chris Reynolds
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
#  History:
#
#  Date        Author  Description
#  ----        ------  -----------
#  2020-10-03  CDR     Initial Version
# **************************************************************************************
BACKUPDIR=/mnt/backup
TARGETFILE=$BACKUPDIR/`date +%F_%H-%M-%S`.xb.gz.enc

# Create a FULL, compressed, encrypted backup.
mariabackup --backup --stream=xbstream | gzip | openssl  enc -aes-256-cbc -k $1 > $TARGETFILE

# Delete old backups
# for DEL in `find $BACKUPDIR -maxdepth 1 -type f -mmin +$(( 30 * 24 * 60 )) -printf "%P\n"`
# do
#  echo "deleting $DEL"
#  rm -rf $BACKUPDIR/$DEL
#done
exit 0