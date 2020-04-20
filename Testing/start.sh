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
#  2019-12-11  CDR     Initial Version
#  2020-02-06  CDR     MariaDB 10.4.12, updated tags to match upstream.
#  2020-04-13  CDR     Bump to MariaDB 10.5.2 (for builder); ProxySQL 2.0.10.
# **************************************************************************************

# We need the directory in which we reside.
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Build the docker images.
cd MariaDB && docker build -t ckmjreynolds/galera:10.5.2 . && cd ..
cd ProxySQL && docker build -t ckmjreynolds/proxysql:2.0.10 . && cd ..

# Tag the docker images as latest.
docker tag ckmjreynolds/galera:10.5.2 ckmjreynolds/galera:latest
docker tag ckmjreynolds/proxysql:2.0.10 ckmjreynolds/proxysql:latest

# Create the secrets.
echo $1 |docker secret create MYSQL_ROOT_PASSWORD -
echo $1 |docker secret create PROXYSQL_ADMIN_PASSWORD -
echo $1 |docker secret create PROXYSQL_USER_PASSWORD -

# Deploy the stack and bootstrap.
docker stack deploy -c docker-compose.yml galera && sleep 30

# Extend the cluster to the other two nodes.
docker service scale galera_alexandria=1 && sleep 30
docker service scale galera_pergamum=1 && sleep 30

# Perform a backup.
docker exec -it $(docker ps -q --filter NAME=galera_pergamum) /usr/local/bin/backup.sh

# Monitor the cluster.
$DIR/monitor.sh $1
