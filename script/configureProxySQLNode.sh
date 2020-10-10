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
if [ -z "$*" ]; then
	echo "USAGE: configureProxySQLNode.sh"
	echo "	<proxysql admin pwd - The password for the admin interface for ProxySQL."
	echo "	<proxysql pwd> - The password for the proxysql user on the Galera nodes."
	echo "  <primary db> - The primary DB node for this ProxySQL instance."
	echo "  <secondary db> - The primary DB node for this ProxySQL instance."
	echo "  <primary proxy> - The primary ProxySQL node."
	echo "  <secondary proxy> - The secondary ProxySQL node."
	exit 0
fi

export PROXYSQL_ADMIN_PASSWORD=$1
export PROXYSQL_PASSWORD=$2
export PRIMARY_DB=$3
export SECONDARY_DB=$4
export PRIMARY_PROXYSQL=$3
export SECONDARY_PROXYSQL=$4

# Replace placeholders in the .cfg files.
for f in ./conf.d/proxysql/*.cnf.template; do
	envsubst < "$f" > "${f%.template}"
done

# Copy the config files to the target location.
sudo cp ./conf.d/proxysql/proxysql.cnf /etc/proxysql.cnf
