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
#  2020-09-05  CDR     Initial Version
# **************************************************************************************
if [ -z "$*" ]; then
	echo "USAGE: configureNode.sh"
	echo "	<FQDN> - This node's fully qualified domain name."
	echo "	<gtid_domain_id> - The gtid_domain_id for this node (unique)."
	echo "	<auto_increment_offset> - The auto_increment_offset for this node (unique)."
	echo "	<wsrep_cluster_address> - The wsrep_cluster_address."
	echo "	<server_id> - The server_id for this Galera cluster."
	echo "	<wsrep_gtid_domain_id> - The wsrep_gtid_domain_id for this Galera cluster."
	echo "	<mariabackup password> - The password for the mariabackup user, for SST."
	exit 0
fi

export WSREP_NODE_ADDRESS=$1
export GTID_DOMAIN_ID=$2
export AUTO_INCREMENT_OFFSET=$3
export WSREP_CLUSTER_ADDRESS=$4
export SERVER_ID=$5
export WSREP_GTID_DOMAIN_ID=$6
export MARIABACKUP_PASSWORD=$7

# Replace placeholders in the .cfg files.
for f in /mnt/backup/MariaDB-Stack/conf.d/*.template; do
	envsubst < "$f" > "${f%.template}"
done

# Copy the config files to the target location.
sudo cp /mnt/backup/MariaDB-Stack/conf.d/*.cnf /etc/mysql/conf.d

# Comment out these lines as we override them.
sudo sed -i.bak 's/^\(bind.*\)/#\1/g' /etc/mysql/mariadb.conf.d/50-server.cnf
sudo sed -i.bak 's/^\(expire.*\)/#\1/g' /etc/mysql/mariadb.conf.d/50-server.cnf
