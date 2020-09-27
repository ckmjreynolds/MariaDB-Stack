# MariaDB-Stack
A simplified, reference implementation of a database stack consisting of a three-node Galera cluster running MariaDB, two ProxySQL instances to provide load balancing, and PMM to provide monitoring.

## Example Deployment (AWS)
The example deployment utilizes six AWS EC2 instances. The sample configuration is as small as possible and not practical for production loads.

### Instances
| Hostname | Instance Type  | Availability Zone | Operating System      | Description                     |
| :--------| :------------- | :---------------- |:--------------------- | :------------------------------ |
| `moho`   | `t3.micro 1GB` | `us-east-1a`      | `Ubuntu 20.04.01 LTS` | `MariaDB Galera` and `ProxySQL` |
| `eve`    | `t3.micro 1GB` | `us-east-1b`      | `Ubuntu 20.04.01 LTS` | `MariaDB Galera` and `ProxySQL` |
| `kerbin` | `t3.small 2GB` | `us-east-1c`      | `Ubuntu 20.04.01 LTS` | `MariaDB Galera` and `PMM`      |

## 1. Setup Network
### Create Default VPC
This is only needed if the default VPC was deleted.

```bash
aws ec2 create-default-vpc
aws ec2 create-tags --resources $(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true"|jq -r '.Vpcs[].VpcId') --tags "Key=Name,Value=default"
```

### Create Security Group
```bash
aws ec2 create-security-group --group-name database-sg --description "Database Security Group" --tag-specifications "ResourceType=security-group,Tags={Key=Name,Value=database-sg}"

aws ec2 authorize-security-group-ingress --group-name database-sg \
    --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp='$(dig +short myip.opendns.com @resolver1.opendns.com)'/32,Description="SSH for Administration."}]'
```

## 2. Create the IAM Policy and Role `db-stack` / `db-stack-role`
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

## 3. Create the EC2 Instances
```bash
# Ubuntu Server 20.04 LTS (HVM), SSD Volume Type - ami-0dba2cb6798deb6d8 (64-bit x86) / ami-0ea142bd244023692 (64-bit Arm)
aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t3.micro --image-id ami-0dba2cb6798deb6d8 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" "DeviceName=/dev/sdc,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=moho},{Key=Domain,Value=<domain>}]"

aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t3.micro --image-id ami-0dba2cb6798deb6d8 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1b"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" "DeviceName=/dev/sdc,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=eve},{Key=Domain,Value=<domain>}]"

aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t3.small --image-id ami-0dba2cb6798deb6d8 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1c"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" "DeviceName=/dev/sdc,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=kerbin},{Key=Domain,Value=<domain>}]"
```

### 3.1 Setup Route 53 Registration
```bash
# Clone this git repository.
cd ~; rm -rf ~/MariaDB-Stack; git clone --single-branch --branch 0.1.4 https://github.com/ckmjreynolds/MariaDB-Stack.git

# Install packages.
sudo apt-get update; sudo apt-get install cloud-utils ec2-api-tools

# Install cli53.
sudo cp ~/MariaDB-Stack/install/cli53-linux-$(uname -i) /usr/local/bin/cli53
sudo chmod +x /usr/local/bin/cli53

# Install registerRoute53.sh script.
sudo cp ~/MariaDB-Stack/script/registerRoute53.sh /usr/local/bin/registerRoute53.sh
sudo chmod +x /usr/local/bin/registerRoute53.sh

# Schedule the script to run on reboot.
(crontab -l ; echo "@reboot /usr/local/bin/registerRoute53.sh")| crontab -

# Reboot the server and verify DNS entry is added/updated.
sudo reboot
```

### 3.2 Setup Docker
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo groupadd docker
sudo usermod -aG docker $USER

# Log out and log back in.
docker run hello-world
docker rm -f $(docker ps -aq)
docker rmi hello-world:latest
rm get-docker.sh
```

### [3.3 Move Docker to ZFS](https://docs.docker.com/storage/storagedriver/zfs-driver/)
```bash
sudo apt install zfsutils-linux
sudo systemctl stop docker
sudo cp -au /var/lib/docker /var/lib/docker.bk
sudo rm -rf /var/lib/docker
sudo zpool create -O compression=lz4 -f zpool-docker -m /var/lib/docker /dev/nvme1n1
sudo vi /etc/docker/daemon.json
{
  "storage-driver": "zfs"
}
sudo systemctl start docker
```

### [3.4 Setup PMM](https://www.percona.com/doc/percona-monitoring-and-management/2.x/install/docker.html)
```bash
# Pull the latest 2.x image
docker pull percona/pmm-server:2

# Create a persistent data container.
docker create --volume /srv --name pmm-data percona/pmm-server:2 /bin/true

# Run the image to start PMM Server.
docker run --detach --restart always --publish 443:443 --volumes-from pmm-data \
    --name pmm-server percona/pmm-server:2
```

## 1. Setup Nodes
### 1.1 Create the Security Group
| Port/Protocol | Source               | Description                   |
| ------------: | :------------------- | :---------------------------- |
| `22/TCP`      | `XXX.XXX.XXX.XXX/32` | SSH for Administration        |
| `433/TCP`     | `XXX.XXX.XXX.XXX/32` | HTTPS for Administration      |


### 1.2 Create the EFS Volume
Create a `General Pupose` EFS volume for the `backup` volume.

### 1.3 Create the IAM Policy and Role `dns-updater` / `dns-updater-role`
```JSON
{
    "Version": "2012-10-17",
    "Statement":[
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

### 1.4 Setup PMM
Follow the instructions [here](https://www.percona.com/doc/percona-monitoring-and-management/2.x/install/aws.html) to setup PMM using the AWS Marketplace.

### 1.5 Create the `moho` Instance
- "T2/T3 Unlimited": disabled
- "Add file system": `backup` created above as `/mnt/backup`
- "Add storage": based on the table below:
- "Add tags": "Name" and "Domain" with the desired Hostname and Domain.

| Hostname    | Device           | Size | Description         |
| :---------- | :--------------- | ---: |:------------------- |
| `all`       | `/dev/nvme0n1p1` | 8GB  | `/`                 |
| `all`       | `/dev/nvme1n1`   | 10GB | `/var/lib/mysql`    |
| `all`       | `/dev/nvme2n1`   | 1GB  | `/var/lib/proxysql` |

### 1.6 Clone `git` Repository
```bash
sudo chown -R ubuntu:ubuntu /mnt/backup
cd /mnt/backup
sudo rm -rf /mnt/backup/*
git clone --single-branch --branch 0.1.4 https://github.com/ckmjreynolds/MariaDB-Stack.git

# Add to ~/.profile.
export PATH="$PATH:/mnt/backup/MariaDB-Stack/script"
```

### 1.7 Setup Route 53 Registration
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

### 1.8 Format and Mount Drives
```bash
# Format the EBS drives.
sudo mkfs --type=ext4 /dev/nvme1n1
sudo mkfs --type=ext4 /dev/nvme2n1

# Create the directories to mount to.
sudo mkdir /var/lib/mysql
sudo mkdir /var/lib/proxysql

# Mount the EBS drives.
sudo mount /dev/nvme1n1 /var/lib/mysql
sudo mount /dev/nvme2n1 /var/lib/proxysql

# Edit /etc/fstab
# <device>                                      <dir>                   <type> <options> <dump> <fsck>
UUID=136d9046-6f47-4cb4-a4b0-e671c06cc2ce       /var/lib/mysql          ext4   defaults  0      2
UUID=b680e94c-ab74-4afe-92d6-1f538466304b       /var/lib/proxysql       ext4   defaults  0      2
```

### 1.9 Install MariaDB
#### Setup Repository and Install
```bash
curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --skip-maxscale --skip-tools
sudo apt-get install mariadb-server galera-4 mariadb-client libmariadb3 mariadb-backup mariadb-common
sudo mysql_secure_installation

# Stop and disable MariaDB for now.
sudo systemctl stop mariadb
sudo systemctl disable mariadb
```

### 1.10 Install ProxySQL
#### Setup Repository and Install
```bash
# https://www.percona.com/doc/percona-server/LATEST/installation/apt_repo.html
wget https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb
sudo dpkg -i percona-release_latest.$(lsb_release -sc)_all.deb
sudo apt-get update
sudo apt-get install proxysql2

# Disable ProxySQL for now.
sudo systemctl disable proxysql
```

### 1.11 Install PMM Client
```bash
# https://www.percona.com/doc/percona-server/LATEST/installation/apt_repo.html
sudo apt-get update
sudo apt-get install pmm2-client
```

### 1.12 Patch and Create AMI
```bash
sudo apt-get update
sudo apt-get upgrade
sudo shutdown

# Create AMI in EC2 Managment Console
```

### 1.13 Create Remaining Nodes
Repeat the following step using the new AMI to create the remaining nodes.
- [1.5 Create the Instance](#15-create-the-moho-instance)

### 1.14 Configure and Bootstrap Galera on `moho`
```bash
configureNode.sh moho.slug.mobi 100 1 "gcomm://moho.slug.mobi,eve.slug.mobi,duna.slug.mobi" 1 1000 "password"

# Bootstrap the first node on each cluster only.
sudo systemctl enable mariadb
sudo galera_new_cluster
```

### 1.15 Create the DB Users
```bash
configureUsers.sh password password password
sudo mysql
MariaDB [(none)]> SOURCE MariaDB-Stack/initdb.d/001_CREATE_USERS.sql
MariaDB [(none)]> exit
```

### 1.16 Add Monitoring
```bash
sudo pmm-admin config --server-insecure-tls --server-url=https://admin:<password>@kerbin.slug.mobi:443
pmm-admin add mysql --username=pmm --password=password --query-source=perfschema moho.slug.mobi:3306
```

### 1.17 Configure and Start Galera on `eve`
```bash
configureNode.sh eve.slug.mobi 200 2 "gcomm://moho.slug.mobi,eve.slug.mobi,duna.slug.mobi" 1 1000 "password"

# Simply start the other nodes.
sudo systemctl enable mariadb
sudo systemctl start mariadb

sudo pmm-admin config --server-insecure-tls --server-url=https://admin:<password>@kerbin.slug.mobi:443
pmm-admin add mysql --username=pmm --password=password --query-source=perfschema eve.slug.mobi:3306
```

### 1.18 Configure and Start Galera on `duna`
```bash
configureNode.sh duna.slug.mobi 300 3 "gcomm://moho.slug.mobi,eve.slug.mobi,duna.slug.mobi" 1 1000 "password"

# Simply start the other nodes.
sudo systemctl enable mariadb
sudo systemctl start mariadb

sudo pmm-admin config --server-insecure-tls --server-url=https://admin:<password>@kerbin.slug.mobi:443
pmm-admin add mysql --username=pmm --password=password --query-source=perfschema duna.slug.mobi:3306
```

### 1.19 Backup and Restore `moho` to `dres`
```bash
# Moho
sudo mariabackup --backup --target-dir=/mnt/backup/moho --user=mariabackup --password=password
sudo mariabackup --prepare --target-dir=/mnt/backup/moho

# Dres
sudo rm -rf /var/lib/mysql/*
sudo mariabackup --copy-back --target-dir=/mnt/backup/moho
sudo chown -R mysql:mysql /var/lib/mysql/
```

### 1.20 Configure and Bootstrap Galera on `dres`
```bash
configureNode.sh dres.slug.mobi 400 4 "gcomm://dres.slug.mobi,jool.slug.mobi,eeloo.slug.mobi" 2 2000 "password"

# Bootstrap the first node on each cluster only.
sudo systemctl enable mariadb
sudo galera_new_cluster
```

### 1.21 Add Monitoring
```bash
sudo pmm-admin config --server-insecure-tls --server-url=https://admin:<password>@kerbin.slug.mobi:443
pmm-admin add mysql --username=pmm --password=password --query-source=perfschema dres.slug.mobi:3306
```

### 1.22 Configure and Start Galera on `jool`
```bash
configureNode.sh jool.slug.mobi 500 5 "gcomm://dres.slug.mobi,jool.slug.mobi,eeloo.slug.mobi" 2 2000 "password"

# Simply start the other nodes.
sudo systemctl enable mariadb
sudo systemctl start mariadb

sudo pmm-admin config --server-insecure-tls --server-url=https://admin:<password>@kerbin.slug.mobi:443
pmm-admin add mysql --username=pmm --password=password --query-source=perfschema jool.slug.mobi:3306
```

### 1.23 Configure and Start Galera on `eeloo`
```bash
configureNode.sh eeloo.slug.mobi 600 6 "gcomm://dres.slug.mobi,jool.slug.mobi,eeloo.slug.mobi" 2 2000 "password"

# Simply start the other nodes.
sudo systemctl enable mariadb
sudo systemctl start mariadb

sudo pmm-admin config --server-insecure-tls --server-url=https://admin:<password>@kerbin.slug.mobi:443
pmm-admin add mysql --username=pmm --password=password --query-source=perfschema eeloo.slug.mobi:3306
```

### 1.24 Start Replication on the `dres` node.
```bash
sudo cat /mnt/backup/moho/xtrabackup_binlog_info
    mysql-bin.000012	342	100-1-8
```
```sql
SET GLOBAL gtid_slave_pos = "100-1-8";
CHANGE MASTER TO 
   MASTER_HOST="moho.slug.mobi", 
   MASTER_PORT=3306, 
   MASTER_USER="repl",  
   MASTER_PASSWORD="password", 
   MASTER_USE_GTID=slave_pos;
START SLAVE;
```

### 1.25 Start Replication on the `moho` node.
```sql
-- Execute on dres
SHOW GLOBAL VARIABLES LIKE 'gtid_current_pos';
+------------------+---------+
| Variable_name    | Value   |
+------------------+---------+
| gtid_current_pos | 100-1-8 |
+------------------+---------+
```
```sql
-- Execute on moho
ET GLOBAL gtid_slave_pos = "100-1-8";
CHANGE MASTER TO 
   MASTER_HOST="dres.slug.mobi", 
   MASTER_PORT=3306, 
   MASTER_USER="repl",  
   MASTER_PASSWORD="password", 
   MASTER_USE_GTID=slave_pos;
START SLAVE;
```

# TODO - ProxySQL clusters.

```bash
configureNode.sh duna.slug.mobi 300 3 "gcomm://moho.slug.mobi,eve.slug.mobi,duna.slug.mobi" 1 1000 "password"

cd /mnt/backup
docker stack rm galera
sleep 5
sudo rm -rf /var/lib/mysql/*.*
rm -rf MariaDB-Stack
git clone --single-branch --branch 0.1.4 https://github.com/ckmjreynolds/MariaDB-Stack.git
configureGalera.sh pass pass pass pass pass pass pass galera1
docker stack deploy -c MariaDB-Stack/docker-compose.yml galera
sleep 15
clear
mysql.sh -h 127.0.0.1 -u root -ppass
SOURCE /mnt/backup/MariaDB-Stack/initdb.d/001_CREATE_USERS.sql
sudo mysql -e "select variable_name, variable_value from information_schema.global_status where variable_name in ('wsrep_cluster_size', 'wsrep_local_state_comment', 'wsrep_cluster_status', 'wsrep_incoming_addresses');"
mysql -h 127.0.0.1 -P6032 -u radmin -ppass -e "select hostgroup_id,hostname,status from runtime_mysql_servers;"
```

# mssux.com - Playbook

## [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-mac.html)
### Install
1. Download and Install `AWSCLIV2.pkg`
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```
2. Verify Install
```bash
aws --version
aws-cli/2.0.52 Python/3.7.4 Darwin/19.6.0 exe/x86_64
```

### Configure
```bash
aws configure
```

## Create Default VPC
This is only needed if the default VPC was deleted.

```bash
aws ec2 create-default-vpc     
aws ec2 create-tags --resources $(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true"|jq -r '.Vpcs[].VpcId') --tags "Key=Name,Value=default"
```

## Create the Aurora Serverless Cluster
### Create Database Security Group
```bash
aws ec2 create-security-group --group-name mssux-database-sg --description "Database Security Group" \
    --tag-specifications "ResourceType=security-group,Tags={Key=Name,Value=mssux-database-sg}"
```

#### Add Ingress for MySQL/Aurora 
```bash
aws ec2 authorize-security-group-ingress --group-name mssux-database-sg \
    --ip-permissions IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges='[{CidrIp=172.31.0.0/16,Description="MySQL/MariaDB/Aurora from VPC."}]'
```

### Create Database Cluster Parameter Group
```bash
aws rds create-db-cluster-parameter-group --db-cluster-parameter-group-name mssux-database-pg \
    --db-parameter-group-family aurora-mysql5.7 --description "Aurora Serverless PG."

aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name mssux-database-pg \
    --parameters "ParameterName=character_set_server,ParameterValue=utf8mb4,ApplyMethod=immediate" \
                 "ParameterName=collation_server,ParameterValue=utf8mb4_unicode_ci,ApplyMethod=immediate" \
                 "ParameterName=time_zone,ParameterValue=US/Central,ApplyMethod=immediate"
```

### Create the Cluster
```bash
aws rds create-db-cluster \
    --db-cluster-identifier mssux-database-cluster \
    --engine aurora-mysql \
    --engine-version 5.7.mysql_aurora.2.07.1 \
    --engine-mode serverless \
    --backup-retention-period 7 \
    --vpc-security-group-ids $(aws ec2 describe-security-groups --group-name mssux-database-sg|jq -r '.SecurityGroups[].GroupId') \
    --scaling-configuration MinCapacity=1,MaxCapacity=4,SecondsUntilAutoPause=300,AutoPause=true \
    --db-cluster-parameter-group-name mssux-database-pg \
    --availability-zones us-east-1a us-east-1b us-east-1c \
    --preferred-backup-window 07:00-07:30 \
    --preferred-maintenance-window Mon:06:00-Mon:06:30 \
    --master-username <user> --master-user-password <password> \
    --tags "Key=Name,Value=mssux-database-cluster"
```

## Create the Bastion Server
### Create Bastion Security Group
```bash
aws ec2 create-security-group --group-name bastion-sg --description "Bastion Security Group" \
    --tag-specifications "ResourceType=security-group,Tags={Key=Name,Value=bastion-sg}"
```

#### Add Ingress for SSH 
```bash
aws ec2 authorize-security-group-ingress --group-name bastion-sg \
    --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp='$(dig +short myip.opendns.com @resolver1.opendns.com)'/32,Description="SSH for Administration."}]'
```

### Launch the Bastion Host
Launch the host manually.

```bash
# Install packages.
sudo apt-get update
sudo apt-get install cloud-utils ec2-api-tools

# Install cli53.
git clone --single-branch --branch 0.1.4 https://github.com/ckmjreynolds/MariaDB-Stack.git
wget https://github.com/barnybug/cli53/releases/download/0.8.17/cli53-linux-arm64
sudo cp /home/ubuntu/cli53-linux-arm64 /usr/local/bin/cli53
sudo chmod +x /usr/local/bin/cli53

# Install registerRoute53.sh script.
sudo cp /home/ubuntu/MariaDB-Stack/script/registerRoute53.sh /usr/local/bin/registerRoute53.sh
sudo chmod +x /usr/local/bin/registerRoute53.sh

# Schedule the script to run on reboot.
crontab -e
@reboot /usr/local/bin/registerRoute53.sh

# Reboot the server and verify DNS entry is added/updated.
sudo reboot
```

## Cleanup
```bash
```

ssh ubuntu@bastion.mssux.com -L 3306:db.mssux.com:3306
curl -o- -L https://slss.io/install | bash
