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
#  2019-11-24  CDR     Initial Version
# **************************************************************************************

# Bring in the original entrypoint, it is designed to permit this.
source /usr/local/bin/docker-entrypoint.sh "$@"

# Get the MYSQL_ROOT_PASSWORD from the secrets file.
file_env 'MYSQL_ROOT_PASSWORD'

# Get the PROXYSQL_USER_PASSWORD from the secrets file.
file_env 'PROXYSQL_USER_PASSWORD'

# Get the PROXYSQL_ADMIN_PASSWORD from the secrets file.
file_env 'PROXYSQL_ADMIN_PASSWORD'

# Get the APP_DB_USER_PASSWORD from the secrets file.
file_env 'APP_DB_USER_PASSWORD'

# Replace placeholders in the .template files.
for f in /etc/*.template; do
	envsubst < "$f" > "${f%.template}.cnf"
done

# Replace the .cnf from the docker image if a backup exists.
if [ -f "/mnt/backup/proxysql.cnf" ]
then
    cp /mnt/backup/proxysql.cnf /etc/proxysql.cnf
else
    cp /etc/proxysql.cnf /mnt/backup/proxysql.cnf
fi

# Start ProxySQL using the configuration file.
exec /usr/bin/proxysql --reload -f -c /etc/proxysql.cnf
