#!/bin/sh
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
#  2020-08-15  CDR     Initial Version
# **************************************************************************************
# https://gist.github.com/dfox/1677405
# https://www.coveros.com/auto-register-an-ec2-host-with-route53-dns/
# https://github.com/barnybug/cli53/#installation

INSTANCE_ID=$(ec2metadata --instance-id)
PUBLIC_DNS=$(ec2metadata --public-hostname)
TTL=60

HOST_NAME=$(ec2dtag --filter "resource-type=instance" --filter "resource-id=$INSTANCE_ID" --filter "key=Name"| awk '{print $5}')
DOMAIN_NAME=$(ec2dtag --filter "resource-type=instance" --filter "resource-id=$INSTANCE_ID" --filter "key=Domain"| awk '{print $5}')

/usr/local/bin/cli53 rrcreate --replace "$DOMAIN_NAME" "$HOST_NAME $TTL CNAME $PUBLIC_DNS."
