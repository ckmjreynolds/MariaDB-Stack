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
#  2019-11-23  CDR     Initial Version
# **************************************************************************************

# Remove any existing stack.
docker stack remove database && sleep 15

# Build the docker images.
cd MariaDB && docker build -t galera:0.1.0 . && cd ..

# Remove any existing files.
rm -rf ./MariaDB/mysql

# Create new data directories for the MariaDB instances.
mkdir -p ./MariaDB/mysql/nineveh
mkdir -p ./MariaDB/mysql/alexandria
mkdir -p ./MariaDB/mysql/pergamum

# Bootstrap the cluster.
touch ./MariaDB/mysql/nineveh/bootstrap

# Deploy the stack and bootstrap.
docker stack deploy -c docker-compose.yml database
docker service scale database_nineveh=1 && sleep 30

# Extend the cluster to the other two nodes.
docker service scale database_alexandria=1 && sleep 30
docker service scale database_pergamum=1 && sleep 30

# Check the status of the cluster.
./mysql -h 127.0.0.1 -P3301 -u root -ppassword -e "select variable_name, variable_value from information_schema.global_status where variable_name in ('wsrep_cluster_size', 'wsrep_local_state_comment', 'wsrep_cluster_status', 'wsrep_incoming_addresses');"
