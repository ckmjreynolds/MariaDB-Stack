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
#  2019-12-08  CDR     Initial Version
# **************************************************************************************

# We need the directory in which we reside.
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

while [ 1 ]
do
clear

# Check the status of the docker swarm.
docker stack ps galera

# Check the status of the cluster.
$DIR/mysql -h 127.0.0.1 -P3301 -u root -p$1 -e "select variable_name, variable_value from information_schema.global_status where variable_name in ('wsrep_cluster_size', 'wsrep_local_state_comment', 'wsrep_cluster_status', 'wsrep_incoming_addresses');"

# Check the status of proxysql.
$DIR/mysql -h 127.0.0.1 -P6032 -u radmin -p$1 -e "select hostgroup_id,hostname,status from runtime_mysql_servers;"

sleep 60

done
