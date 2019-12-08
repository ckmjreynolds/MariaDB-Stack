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
#  2019-11-24  CDR     Initial Version
# **************************************************************************************

# Bring in the original entrypoint, it is designed to permit this.
source /docker-entrypoint.sh "$@"

# If container is started as root user, restart as dedicated mysql user
if [ "$(id -u)" = "0" ]; then
	mysql_note "Switching to dedicated user 'mysql'"
	exec gosu mysql "$BASH_SOURCE" "$@"
fi

# Get the MYSQL_ROOT_PASSWORD from the secrets file.
file_env 'MYSQL_ROOT_PASSWORD'

# Get the PROXYSQL_USER_PASSWORD from the secrets file.
file_env 'PROXYSQL_USER_PASSWORD'

# Get the PROXYSQL_ADMIN_PASSWORD from the secrets file.
file_env 'PROXYSQL_ADMIN_PASSWORD'

# Replace placeholders in the .sql files.
for f in /docker-entrypoint-initdb.d/*.template; do
	envsubst < "$f" > "${f%.template}.sql"
done

# Replace placeholders in the .cnf files.
for f in /etc/mysql/conf.d/*.template; do
	# Bootstrap if we're asked.
	if [ -f /var/lib/mysql/bootstrap ]; then
		# Transfer control to the original ENTRYPOINT only if bootstrapping.
		env WSREP_CLUSTER_ADDRESS="gcomm://" envsubst < "$f" > "${f%.template}.cnf"
		rm -f /var/lib/mysql/bootstrap
		_main "$@"
else
		envsubst < "$f" > "${f%.template}.cnf"
		exec "$@"
	fi
done
