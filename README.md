# MariaDB-Stack
A simplified, reference implementation of a database stack, deployed using a Docker Swarm consisting of two, three node MariaDB Galera cluster, using ProxySQL to provide load balancing, and PMM to provide monitoring.

## Example Deployment (AWS)
The example deployment utilizes six AWS EC2 instances running the Ubuntu distribution. The sample configuration is as small as possible and not practical for most production loads.

### Instances
| Hostname | Instance Type    | Availability Zone | Operating System     | Description    |
| :------- | :--------------- | :---------------- |:-------------------- | :------------- |
| `moho`   | `t3a.medium 4GB` | `us-east-1a`      | `Ubuntu 20.04.0 LTS` | Manager/Worker |
| `eve`    | `t3a.medium 4GB` | `us-east-1a`      | `Ubuntu 20.04.0 LTS` | Manager/Worker |
| `kerbin` | `t3a.medium 4GB` | `us-east-1a`      | `Ubuntu 20.04.0 LTS` | Manager/Worker |
| `duna`   | `t3a.medium 4GB` | `us-east-1b`      | `Ubuntu 20.04.0 LTS` | Manager/Worker |
| `dres`   | `t3a.medium 4GB` | `us-east-1b`      | `Ubuntu 20.04.0 LTS` | Manager/Worker |
| `jool`   | `t3a.medium 4GB` | `us-east-1b`      | `Ubuntu 20.04.0 LTS` | Manager/Worker |

## 1. Setup
### 1.1 Create the Security Group
| Port/Protocol | Source               | Description                   |
| ------------: | :------------------- | :---------------------------- |
| `22/TCP`      | `XXX.XXX.XXX.XXX/32` | SSH for Administration        |
| `6033/TCP`    | `XXX.XXX.XXX.XXX/32` | ProxySQL Traffic              |
| `2377/TCP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `7946/TCP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `7946/UDP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `4789/UDP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `2049/TCP`    | `172.31.0.0/16`      | NFS for EFS                   |

### 1.2 Create the EFS Volume
Create a `General Purpose` EFS volume for the `backup` volume.

### 1.3 Create the IAM Policy and Role `dns-updater` / `dns-updater-role`
```JSON
{
    "Version": "2012-10-17",
    "Statement":[
        {
            "Effect": "Allow",
            "Action": "ec2:Describe*",
            "Resource": "*"
        },
        {
            "Action":[
                "route53:ChangeResourceRecordSets",
                "route53:GetHostedZone",
                "route53:ListResourceRecordSets"
            ],
            "Effect":"Allow",
            "Resource":[
            "arn:aws:route53:::hostedzone/<Your zone ID>"
            ]
        },
        {
            "Action":[
                "route53:ListHostedZones",
                "route53:ListHostedZonesByName"
            ],
            "Effect":"Allow",
            "Resource":[
            "*"
            ]
        }
    ]
}
```

### 1.4 Create the `moho` Instance
- "T2/T3 Unlimited": disabled
- "Add file system": `backup` created above as `/mnt/backup`
- "Add storage": based on the table below:
- "Add tags": "Name" and "Domain" with the desired Hostname and Domain.

| Hostname | Device           | Size | Description         |
| :------- | :--------------- | ---: |:------------------- |
| `moho`   | `/dev/nvme0n1p1` | 8GB  | `/`                 |
| `moho`   | `/dev/nvme1n1`   | 10GB | `/var/lib/mysql`    |
| `moho`   | `/dev/nvme2n1`   | 1GB  | `/var/lib/proxysql` |

### 1.5 Setup Route 53 Registration
```bash
# https://gist.github.com/dfox/1677405
# https://www.coveros.com/auto-register-an-ec2-host-with-route53-dns/
# https://github.com/barnybug/cli53/#installation
sudo apt-get install cloud-utils ec2-api-tools
wget https://github.com/barnybug/cli53/releases/download/0.8.17/cli53-linux-amd64
sudo mv cli53-linux-amd64 /usr/local/bin/cli53
sudo chmod +x /usr/local/bin/cli53

ec2dtag --filter "resource-type=instance" --filter "resource-id=$(ec2metadata --instance-id)" --filter "key=Name" | awk '{print $5}'
ec2dtag --filter "resource-type=instance" --filter "resource-id=$(ec2metadata --instance-id)" --filter "key=Domain" | awk '{print $5}'

ec2metadata --public-hostname

cli53 rrcreate example.com 'moho CNAME ec2-54-164-111-236.compute-1.amazonaws.com.'

#!/bin/sh
INSTANCE_ID=$(ec2metadata --instance-id)
# HOST_NAME=$(ec2dtag --filter "resource-type=instance" --filter "resource-id=$INSTANCE_ID" --filter "key=Name"  awk '{print $5}')

print $INSTANCE_ID

#!/bin/sh
# Original from David Fox:
# https://gist.github.com/dfox/1677405
#
# Script to bind a CNAME to our HOST_NAME in ZONE

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
echo "This script must be run as root" 1>&2
exit 1
fi

# Defaults
TTL=60
HOST_NAME=`hostname`
ZONE=NoZoneDefined

# Load configuration
. /etc/route53/config

# Export access key ID and secret for cli53
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

# Use command line scripts to get instance ID and public hostname
#INSTANCE_ID=$(ec2metadata | grep 'instance-id:' | cut -d ' ' -f 2)
MY_NAME=$HOST_NAME
PUBLIC_HOSTNAME=$(/opt/aws/bin/ec2-metadata | grep 'public-hostname:' | cut -d ' ' -f 2)

logger "ROUTE53: Setting DNS CNAME $MY_NAME.$ZONE to $PUBLIC_HOSTNAME"

# Create a new CNAME record on Route 53, replacing the old entry if nessesary
/usr/bin/cli53 rrcreate "$ZONE" "$MY_NAME" CNAME "$PUBLIC_HOSTNAME" --replace --ttl "$TTL"
```

https://www.coveros.com/auto-register-an-ec2-host-with-route53-dns/

### 0. Prerequisites
It is assumed that the reader has a working knowledge of AWS EC2 and Docker.
1. Create the [Security Group](#security-group).
2. Create [EFS Volume](#efs-volume).
3. Create the `moho` instance.
4. Create and assign Elastic IP and DNS aliases.
5. Create CloudWatch monitor(s).
6. [Install Docker](#install-docker).
7. Patch the node.
8. Create an AMI
9. Create the other nodes using the AMI.
10. Set Hostname: `sudo hostnamectl set-hostname <name>`
11. [Setup Docker Swarm](#setup-docker-swarm)
12. (Optional) [Setup Portainer](#setup-portainer)

### 1. Copy Files
```bash
scp docker-compose.yml ubuntu@moho:~/galera/docker-compose.yml
scp Testing/mysql ubuntu@moho:~/galera/mysql
scp Testing/monitor.sh ubuntu@moho:~/galera/monitor.sh
```

### 2. Create Secrets
```bash
echo <password>|docker secret create MYSQL_ROOT_PASSWORD -
echo <password>|docker secret create PROXYSQL_ADMIN_PASSWORD -
echo <password>|docker secret create PROXYSQL_USER_PASSWORD -
```

### 3. Deploy the Stack (`moho`)
```bash
# 1. Deploy the stack (also Bootstraps the clutser).
cd ~/galera
docker stack deploy -c docker-compose.yml galera

# 2. Add alexandria to the cluster.
docker service scale galera_alexandria=1

# 3. Add pergamum to the cluster.
docker service scale galera_pergamum=1

# 4. Crude monitoring.
./monitor.sh <password>
```

### 4. Schedule Backup
```bash
ssh ubuntu@kerbin
crontab -e
# m h  dom mon dow   command
0 8 * * * docker exec $(docker ps -q --filter NAME=galera_pergamum) /usr/local/bin/backup.sh
```

## Appendix

### Security Group
| Port/Protocol | Source               | Description                   |
| ------------: | :------------------- | :---------------------------- |
| `22/TCP`      | `XXX.XXX.XXX.XXX/32` | SSH for Administration        |
| `6033/TCP`    | `XXX.XXX.XXX.XXX/32` | ProxySQL Traffic              |
| `2377/TCP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `7946/TCP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `7946/UDP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `4789/UDP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `2049/TCP`    | `172.31.0.0/16`      | NFS for EFS                   |

### EFS volume
Create EFS volume for the `backup` volume.
1. Create a `General Purpose` EFS volume.

### Install Docker
#### Install Packages
```bash
sudo apt-get update
sudo apt-get install docker.io nfs-common
```

#### Configure Docker
```bash
sudo usermod -aG docker $USER

# Log out and log back in.
docker run hello-world
docker rm -f $(docker ps -aq)
docker rmi hello-world:latest
```

### Setup Docker Swarm
```bash
# On moho
docker swarm init
docker swarm join-token manager

# On remaining nodes, join as a worker or manager.
docker swarm join --token <token> <ip>:2377
```

### Setup Portainer
```bash
# On moho
curl -L https://downloads.portainer.io/portainer-agent-stack.yml -o portainer-agent-stack.yml
docker stack deploy --compose-file=portainer-agent-stack.yml portainer
```
