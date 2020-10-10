#!/bin/bash
# *********************************************************************************************************************
# MIT License
#
# Copyright (c) 2019, 2020 Chris Reynolds
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
#  2020-10-10  CDR     Initial Version
# *********************************************************************************************************************
BACKUPDIR=/mnt/backup/${HOSTNAME}
TARGETFILE=${BACKUPDIR}/`date +%F_%H-%M-%S`.${HOSTNAME}.xb.7z
mkdir -p ${BACKUPDIR}


# Create a FULL, compressed, encrypted backup.
mariabackup --user=mariabackup --password=${1} --backup --galera-info --stream=xbstream | 7z a -si -p${2} -v1g ${TARGETFILE}
exit 0