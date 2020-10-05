#!/bin/bash
# **************************************************************************************
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
#  2020-09-06  CDR     Initial Version
# **************************************************************************************
if [ -z "$*" ]; then
	echo "USAGE: configureUsers.sh"
	echo "	<mariabackup password> - The password for the mariabackup user, for SST."
	echo "	<pmm password> - The password for the pmm user, for monitoring."
	echo "	<proxysql password> - The password for the proxysql user, for monitoring."
	echo "	<repl password> - The password for the repl user, for replication."
	exit 0
fi

export MARIABACKUP_PASSWORD=$1
export PMM_PASSWORD=$2
export PROXYSQL_PASSWORD=$3
export REPL_PASSWORD=$4

# Replace placeholders in the .sql files.
for f in ./initdb.d/*.template; do
	envsubst < "$f" > "${f%.template}"
done
