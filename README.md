# MariaDB-Stack
A simplified, reference implementation of a database stack, deployed using a Docker Swarm consisting of a three node MariaDB Galera cluster, using ProxySQL to provide load balancing, and PMM to provide monitoring.

## Example Deployment (AWS)
```mermaid
graph TD
    mohoPS -.-> kerbinDB
    evePS -.-> kerbinDB

    subgraph eve - Leg 2
        evePS[\ProxySQL2/]
        eveDB[Galera2]

        evePS --> eveDB
    end
    subgraph kerbin - Backup
        kerbinDB[Galera3]
    end
    subgraph moho - Leg 1
        mohoPS[\ProxySQL1/]
        mohoDB[Galera1]

        mohoPS --> mohoDB
    end
```
The example deployment utilizes three AWS EC2 instances running the Ubuntu distribution. The sample configuration is as small as possible and not practical for most production loads.

### Instances
| Hostname | Instance Type    | Availability Zone | Operating System      | Description               |
| :------- | :--------------- | :---------------- |:--------------------- | :-------------------------|
| `moho`   | `t3a.small 2GB`  | `us-east-1a`      | `Ubuntu 20.04.01 LTS` | `galera1` and `proxysql1` |
| `eve`    | `t3a.small 2GB`  | `us-east-1b`      | `Ubuntu 20.04.01 LTS` | `galera2` and `proxysql2` |
| `kerbin` | `t3a.medium 4GB` | `us-east-1c`      | `Ubuntu 20.04.01 LTS` | `galera3` and `pmm`       |

## 1. Setup Swarms
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
Create a `General Pupose` EFS volume for the `backup` volume.

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

| Hostname    | Device           | Size | Description         |
| :---------- | :--------------- | ---: |:------------------- |
| `all`       | `/dev/nvme0n1p1` | 8GB  | `/`                 |
| `all`       | `/dev/nvme1n1`   | 1GB  | `/var/lib/mysql`    |
| `moho/eve`  | `/dev/nvme2n1`   | 1GB  | `/var/lib/proxysql` |
| `kerbin`    | `/dev/nvme2n1`   | 10GB | `/srv`              |

### 1.5 Clone `git` Repository
```bash
sudo chown -R ubuntu:ubuntu /mnt/backup
git clone --single-branch --branch 0.1.4 https://github.com/ckmjreynolds/MariaDB-Stack.git

# Add to ~/.profile.
export PATH="$PATH:/mnt/backup/MariaDB-Stack/script"
```

### 1.6 Setup Route 53 Registration
```bash
# Install packages.
sudo apt-get update
sudo apt-get install cloud-utils ec2-api-tools

# Install cli53.
sudo cp /mnt/backup/MariaDB-Stack/install/cli53-linux-amd64 /usr/local/bin/cli53
sudo chmod +x /usr/local/bin/cli53

# Install registerRoute53.sh script.
sudo cp /mnt/backup/MariaDB-Stack/script/registerRoute53.sh /usr/local/bin/registerRoute53.sh
sudo chmod +x /usr/local/bin/registerRoute53.sh

# Schedule the script to run on reboot.
crontab -e
@reboot /usr/local/bin/registerRoute53.sh

# Reboot the server and verify DNS entry is added/updated.
sudo reboot
```

### 1.7 Install Docker
#### Install Packages
```bash
sudo apt-get update
sudo apt-get install docker.io
```

#### Configure Docker
```bash
sudo usermod -aG docker $USER

# Log out and log back in.
docker run hello-world
docker rm -f $(docker ps -aq)
docker rmi hello-world:latest
```

### 1.8 Install `pmm-client`
```bash
# Setup repository
wget https://repo.percona.com/apt/percona-release_latest.generic_all.deb
sudo dpkg -i percona-release_latest.generic_all.deb
rm percona-release_latest.generic_all.deb

# Install the client
sudo apt-get update
sudo apt-get install pmm2-client
```

### 1.9 Patch and Create AMI
```bash
sudo apt-get update
sudo apt-get upgrade
sudo shutdown
# Create AMI in EC2 Managment Console
```

### 1.10 Create Remaining Nodes
Repeat the following step using the new AMI to create the remaining nodes.
- [1.4 Create the Instance](#14-create-the-moho-instance)

### 1.11 Setup Docker Swarm
Setup the Docker swarm.
```bash
# On moho
docker swarm init
docker swarm join-token manager

# On remaining nodes, join as a worker or manager.
docker swarm join --token <token> <ip>:2377
```

### 1.12 Format and Mount Drives
```bash
# NAME        MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
# nvme1n1     259:0    0    1G  0 disk 
# nvme2n1     259:1    0    1G  0 disk
# NOTE: nvme2n1 is 10G on kerbin
sudo mkfs --type=ext4 /dev/nvme1n1
sudo mkfs --type=ext4 /dev/nvme2n1

# moho, eve, and kerbin
sudo mkdir /var/lib/mysql
sudo mount /dev/nvme1n1 /var/lib/mysql

# moho and eve
sudo mkdir /var/lib/proxysql
sudo mount /dev/nvme2n1 /var/lib/proxysql

# kerbin
sudo mkdir /var/lib/pmm
sudo mount /dev/nvme2n1 /var/lib/pmm
```

```bash
docker stack rm galera
sleep 5
cd /mnt/backup
rm -rf MariaDB-Stack
git clone --single-branch --branch 0.1.4 https://github.com/ckmjreynolds/MariaDB-Stack.git
configureGalera.sh pass pass pass pass pass pass pass galera1
clear
docker stack deploy -c MariaDB-Stack/docker-compose.yml galera
sleep 15
mysql.sh -h 127.0.0.1 -P6033 -u root -ppass -e "select variable_name, variable_value from information_schema.global_status where variable_name in ('wsrep_cluster_size', 'wsrep_local_state_comment', 'wsrep_cluster_status', 'wsrep_incoming_addresses');"
sleep 5
mysql.sh -h 127.0.0.1 -P6032 -u radmin -ppass -e "select hostgroup_id,hostname,status from runtime_mysql_servers;"
sleep 5
```