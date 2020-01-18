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
#  2019-12-26  CDR     Bump to MariaDB 10.4.11 (for builder).
# **************************************************************************************

FROM mariadb:10.4.11-bionic AS builder

FROM proxysql/proxysql:2.0.8
LABEL maintainer="46268121+ckmjreynolds@users.noreply.github.com"

RUN \
	apt-get update; \
	apt-get install -y gettext-base; \
	rm -rf /var/lib/apt/lists/*;

COPY --from=builder /docker-entrypoint.sh .
COPY startup.sh /usr/local/bin/

# Copy our configuration files (and templates).
COPY proxysql.template /etc/proxysql.template

# 6032 ProxySQL Admin
# 6033 ProxySQL Proxy
# 6080 ProxySQL Web Admin
EXPOSE 6032 6033 6080

ENTRYPOINT ["startup.sh"]
