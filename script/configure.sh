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
#  2020-08-23  CDR     Initial Version
# **************************************************************************************
if [ -z "$*" ]; then
	echo "USAGE: configure.sh"
	echo "    <root_password>"
	echo "    <mariabackup_password>"
	echo "    <pmm_password>"
	echo "    <proxysql_password>"
	echo "    <proxysql_admin_password>"
	echo "    <proxysql_radmin_password>"
	echo "    <proxysql_stats_password>"
	exit 0
fi

echo $1 |docker secret create MYSQL_ROOT_PASSWORD -
echo $1
docker secret ls

export MARIABACKUP_PASSWORD=$2
exit 0

# Replace placeholders in the .cfg files.
for f in /mnt/backup/MariaDB-Stack/nineveh/config.d/*.template; do
	envsubst < "$f" > "${f%.template}.cfg"
done

for f in /mnt/backup/MariaDB-Stack/alexandria/config.d/*.template; do
	envsubst < "$f" > "${f%.template}.cfg"
done

for f in /mnt/backup/MariaDB-Stack/pergamum/config.d/*.template; do
	envsubst < "$f" > "${f%.template}.cfg"
done

# Replace placeholders in the .sql files.
for f in /mnt/backup/MariaDB-Stack/initdb.d/*.template; do
	envsubst < "$f" > "${f%.template}.sql"
done
