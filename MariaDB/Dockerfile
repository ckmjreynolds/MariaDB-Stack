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
#  2019-12-06  CDR     Initial Version
# **************************************************************************************

FROM mariadb:10.4.10-bionic
LABEL maintainer="46268121+ckmjreynolds@users.noreply.github.com"

RUN \
	apt-get update; \
	apt-get install -y gettext-base openssl; \
	rm -rf /var/lib/apt/lists/*;

# The official MariaDB docker image's ENTRYPOINT script (docker-entrypoint.sh)
# performs initialization and then transfers control to mysqld. We will inject
# ourselves into this flow by tricking it into calling with our startup script.
COPY startup.sh /usr/local/bin/
COPY backup.sh /usr/local/bin/

# Copy our configuration files (and templates).
COPY conf.d/* /etc/mysql/conf.d/
RUN chown -R mysql:mysql /etc/mysql/conf.d

COPY initdb.d/* /docker-entrypoint-initdb.d/
RUN chown -R mysql:mysql docker-entrypoint-initdb.d

# 3306 is the default port for MySQL client connections and State Snapshot Transfer using mysqldump for backups.
# 4567 is reserved for Galera Cluster replication traffic. Multicast replication uses both TCP and UDP transport on this port.
# 4568 is the port for Incremental State Transfer.
# 4444 is used for all other State Snapshot Transfer.
# https://galeracluster.com/library/documentation/firewall-settings.html
EXPOSE 3306 4444 4567/tcp 4567/udp 4568

ENTRYPOINT ["startup.sh"]
CMD ["mysqld"]
