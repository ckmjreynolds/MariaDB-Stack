# MariaDB-Stack
## Example Deployment (AWS)
### Instances
| Hostname    | Instance Type   | Availability Zone | Operating System      | Description        |
| :---------- | :-------------- | :---------------- |:--------------------- | :----------------- |
| `monitor`   | `t3.small 2GB`  | `us-east-1c`      | `Ubuntu 20.04.01 LTS` | `PMM Monitoring`   |
| `db1`       | `t4g.micro 1GB` | `us-east-1a`      | `Ubuntu 20.04.01 LTS` | `Galera Node #1`   |
| `db2`       | `t4g.micro 1GB` | `us-east-1b`      | `Ubuntu 20.04.01 LTS` | `Galera Node #2`   |
| `db3`       | `t4g.micro 1GB` | `us-east-1c`      | `Ubuntu 20.04.01 LTS` | `Galera Node #3`   |
| `proxysql1` | `t3.nano 0.5GB` | `us-east-1a`      | `Ubuntu 20.04.01 LTS` | `ProxySQL Node #1` |
| `proxysql2` | `t3.nano 0.5GB` | `us-east-1b`      | `Ubuntu 20.04.01 LTS` | `ProxySQL Node #2` |

## 1. Clone this Repository
```bash
git clone --single-branch --branch 0.1.4 https://github.com/ckmjreynolds/MariaDB-Stack.git
cd MariaDB-Stack
```

## 2. Create Security Groups
```bash
# Get my IP address to setup Administration Ingress
IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

# Database Monitoring Security Group
aws ec2 create-security-group --group-name db-monitor-sg --description "Database Monitor Security Group" \
    --tag-specifications "ResourceType=security-group,Tags={Key=Name,Value=db-monitor-sg}"

aws ec2 authorize-security-group-ingress --group-name db-monitor-sg --ip-permissions \
    IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp='${IP}'/32,Description="SSH for Administration."}]' \
    IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp='${IP}'/32,Description="HTTPS for Administration."}]' \
    IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=172.31.0.0/16,Description="HTTPS for Monitoring."}]'

# Database Security Group
aws ec2 create-security-group --group-name db-database-sg --description "Database Security Group" \
    --tag-specifications "ResourceType=security-group,Tags={Key=Name,Value=db-database-sg}"

aws ec2 authorize-security-group-ingress --group-name db-database-sg --ip-permissions \
    IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp='${IP}'/32,Description="SSH for Administration."}]' \
    IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges='[{CidrIp='${IP}'/32,Description="MySQL for Administration."}]' \
    IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges='[{CidrIp=172.31.0.0/16,Description="MySQL for Application."}]'

# Database ProxySQL Security Group
aws ec2 create-security-group --group-name db-proxysql-sg --description "Database ProxySQL Security Group" \
    --tag-specifications "ResourceType=security-group,Tags={Key=Name,Value=db-proxysql-sg}"

aws ec2 authorize-security-group-ingress --group-name db-proxysql-sg --ip-permissions \
    IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp='${IP}'/32,Description="SSH for Administration."}]' \
    IpProtocol=tcp,FromPort=6032,ToPort=6032,IpRanges='[{CidrIp='${IP}'/32,Description="ProxySQL Admin for Administration."}]' \
    IpProtocol=tcp,FromPort=6033,ToPort=6033,IpRanges='[{CidrIp='${IP}'/32,Description="ProxySQL for Administration."}]' \
    IpProtocol=tcp,FromPort=6033,ToPort=6033,IpRanges='[{CidrIp=172.31.0.0/16,Description="ProxySQL for Application."}]'
```

## 3. Create s3 Bucket for Backups
```bash
BUCKET=$(aws sts get-caller-identity|jq -r '.Account')-db-backups
aws s3api create-bucket --bucket ${BUCKET} --acl private
```

## 4. Create the IAM Policy/Role `db-stack-policy`/`db-stack-role`/`db-stack-profile`
```bash
# Note: The policy allows access to the s3 bucket as well as the ability to update DNS records.
export BUCKET=$(aws sts get-caller-identity|jq -r '.Account')-db-backups
export ZONEID=<Your hosted zone ID>
envsubst < ./script/IAM_policy.template > ./script/IAM_policy.json
aws iam create-policy --policy-name db-stack-policy --policy-document file://./script/IAM_policy.json
rm ./script/IAM_policy.json

# Create a role with the given policy.
aws iam create-role --role-name db-stack-role --assume-role-policy-document file://./script/trust.json
aws iam attach-role-policy --role-name db-stack-role \
    --policy-arn arn:aws:iam::$(aws sts get-caller-identity|jq -r '.Account'):policy/db-stack-policy

# Create an instance profile with the given role.
aws iam create-instance-profile --instance-profile-name db-stack-profile
aws iam add-role-to-instance-profile --instance-profile-name db-stack-profile --role-name db-stack-role
```

## 5. Create AMIs for Ubuntu 20.04 LTS - 64-bit x86 and 64-bit Arm
```bash
# Ubuntu Server 20.04 LTS (HVM), SSD Volume Type - ami-0dba2cb6798deb6d8 (64-bit x86) / ami-0ea142bd244023692 (64-bit Arm)
aws ec2 run-instances --key-name <ssh_key> --instance-type t3.nano --image-id ami-0dba2cb6798deb6d8 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name db-database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --iam-instance-profile Name="db-stack-profile" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=amd64},{Key=Domain,Value=<domain>}]"

# Ubuntu Server 20.04 LTS arm64 - ami-0e9f3a26099cdb584
aws ec2 run-instances --key-name <ssh_key> --instance-type t4g.nano --image-id ami-0ea142bd244023692 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name db-database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --iam-instance-profile Name="db-stack-profile" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=arm64},{Key=Domain,Value=<domain>}]"

# Complete these steps for each platform and then create AMIs.
git clone --single-branch --branch 0.1.4 https://github.com/ckmjreynolds/MariaDB-Stack.git
cd MariaDB-Stack

# Set the TimeZone
sudo timedatectl set-timezone America/Chicago

# Install packages.
sudo apt-get update; sudo apt-get install --yes screen zfsutils-linux s3fs cloud-utils ec2-api-tools

# Install cli53.
sudo wget -O /usr/local/bin/cli53 https://github.com/barnybug/cli53/releases/download/0.8.17/cli53-linux-amd64
# OR
sudo wget -O /usr/local/bin/cli53 https://github.com/barnybug/cli53/releases/download/0.8.17/cli53-linux-arm64
sudo chmod +x /usr/local/bin/cli53

# Install registerRoute53.sh script.
sudo wget -O /usr/local/bin/registerRoute53.sh https://raw.githubusercontent.com/ckmjreynolds/MariaDB-Stack/0.1.4/script/registerRoute53.sh
sudo chmod +x /usr/local/bin/registerRoute53.sh

# Schedule the script to run on reboot.
(wget -O - https://raw.githubusercontent.com/ckmjreynolds/MariaDB-Stack/0.1.4/script/crontab)| sudo crontab -
(sudo crontab -l; echo "@reboot /usr/local/bin/registerRoute53.sh")| sudo crontab -

# Install S3 File System (for backups)
sudo -i
mkdir /mnt/backup
echo 's3fs#849647503614-db-backups /mnt/backup fuse _netdev,allow_other,iam_role=auto,storage_class=intelligent_tiering 0 0' >> /etc/fstab

# Reboot the server and verify DNS entry is added/updated and s3 bucket mounted.
reboot

# If everything is working, patch the server, shutdown and create an AMI.
sudo apt-get update
sudo apt-get upgrade --with-new-pkgs
sudo apt-get clean
sudo shutdown now
```

# Ubuntu Server 20.04 LTS (HVM), SSD Volume Type - ami-0dba2cb6798deb6d8 (64-bit x86) / ami-0ea142bd244023692 (64-bit Arm)

## X. Clone the Repository
```bash
git clone --single-branch --branch 0.1.4 https://github.com/ckmjreynolds/MariaDB-Stack.git
cd MariaDB-Stack
```

## X. Cleanup
```bash
# Remove the Role from the Profile
aws iam remove-role-from-instance-profile --instance-profile-name db-stack-profile --role-name db-stack-role

# Delete the Profile
aws iam delete-instance-profile --instance-profile-name db-stack-profile

# Remove the Policy from the Role
aws iam detach-role-policy --role-name db-stack-role \
    --policy-arn arn:aws:iam::$(aws sts get-caller-identity|jq -r '.Account'):policy/db-stack-policy

# Remove Role
aws iam delete-role --role-name db-stack-role

# Remove IAM Policy
aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity|jq -r '.Account'):policy/db-stack-policy

# Remove the s3 Bucket
BUCKET=$(aws sts get-caller-identity|jq -r '.Account')-db-backups
aws s3api delete-bucket --bucket ${BUCKET}

# Remove db-proxysql-sg Security Group
SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=db-proxysql-sg"|jq -r '.SecurityGroups[].GroupId')
aws ec2 delete-security-group --group-id ${SG}

# Remove db-database-sg Security Group
SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=db-database-sg"|jq -r '.SecurityGroups[].GroupId')
aws ec2 delete-security-group --group-id ${SG}

# Remove db-monitor-sg Security Group
SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=db-monitor-sg"|jq -r '.SecurityGroups[].GroupId')
aws ec2 delete-security-group --group-id ${SG}
```

## X. Default VPC Create/Delete
```bash
# *********************************************************************************************************************
# Note: This is only needed if the Default VPC was deleted, which is unusual.
# *********************************************************************************************************************
aws ec2 create-default-vpc; VPC=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true"|jq -r '.Vpcs[].VpcId')
aws ec2 create-tags --tags "Key=Name,Value=default" --resources ${VPC}
SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=default"|jq -r '.SecurityGroups[].GroupId')
aws ec2 create-tags --tags "Key=Name,Value=default" --resources ${SG}

# *********************************************************************************************************************
# NOTE: You normally DO NOT want to perform these cleanup steps!
# *********************************************************************************************************************
./script/delete-default-vpc.sh
```






### Create Security Group for `monitor`
```bash
```
aws ec2 create-security-group --group-name database-sg --description "Database Security Group" --tag-specifications "ResourceType=security-group,Tags={Key=Name,Value=database-sg}"

aws ec2 authorize-security-group-ingress --group-name database-sg \
    --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp='$(dig +short myip.opendns.com @resolver1.opendns.com)'/32,Description="SSH for Administration."}]'

aws ec2 authorize-security-group-ingress --group-name database-sg \
    --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp='$(dig +short myip.opendns.com @resolver1.opendns.com)'/32,Description="HTTPS for Administration."}]'
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
            "Effect": "Allow",
            "Action": ["s3:GetBucketLocation","s3:ListAllMyBuckets"],
            "Resource": "arn:aws:s3:::*"
        },
        {
            "Effect": "Allow",
            "Action": ["s3:ListBucket"],
            "Resource": ["arn:aws:s3:::mssux-backups"]
        },
        {
            "Effect": "Allow",
            "Action": ["s3:PutObject","s3:GetObject","s3:DeleteObject"],
            "Resource": ["arn:aws:s3:::mssux-backups/*"]
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
                "route53:GetChange",
                "route53:ListHostedZones",
                "route53:ListHostedZonesByName"
            ],
            "Effect":"Allow",
            "Resource":[
            "*"
            ]
        },
    ]
}
```

```
# Ubuntu Server 20.04 LTS (HVM), SSD Volume Type - ami-0dba2cb6798deb6d8 (64-bit x86) / ami-0ea142bd244023692 (64-bit Arm)
# Ubuntu 20.04.1 LTS aarch64 (includes 3.1 below) - ami-00bae8092a688e69e
# sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

## 3. Create the `monitor` EC2 Instance
```bash
# Ubuntu 20.04.1 LTS x86_64 (includes 3.1 below) - ami-0813f39f84cc21ebf
aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t3.small --image-id ami-0813f39f84cc21ebf \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1c"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=monitor},{Key=Domain,Value=mssux.com}]"
```

### 3.1 Setup Route 53 Registration
```bash
# Set the TimeZone
sudo timedatectl set-timezone America/Chicago

# Install packages.
sudo apt-get update; sudo apt-get install --yes screen zfsutils-linux cloud-utils ec2-api-tools

# Install cli53.
sudo wget -O /usr/local/bin/cli53 https://github.com/barnybug/cli53/releases/download/0.8.17/cli53-linux-amd64
# OR
sudo wget -O /usr/local/bin/cli53 https://github.com/barnybug/cli53/releases/download/0.8.17/cli53-linux-arm64
sudo chmod +x /usr/local/bin/cli53

# Install registerRoute53.sh script.
sudo wget -O /usr/local/bin/registerRoute53.sh https://raw.githubusercontent.com/ckmjreynolds/MariaDB-Stack/0.1.4/script/registerRoute53.sh
sudo chmod +x /usr/local/bin/registerRoute53.sh

# Schedule the script to run on reboot.
(wget -O - https://raw.githubusercontent.com/ckmjreynolds/MariaDB-Stack/0.1.4/script/crontab)| crontab -

# Reboot the server and verify DNS entry is added/updated.
sudo reboot
```

### 3.2 Setup Docker
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
rm get-docker.sh
```

### [3.3 Move Docker to ZFS](https://docs.docker.com/storage/storagedriver/zfs-driver/)
```bash
sudo systemctl stop docker
sudo cp -au /var/lib/docker /var/lib/docker.bk
sudo rm -rf /var/lib/docker
sudo zpool create -o ashift=12 -o autoexpand=on -O relatime=on -O compression=lz4 -f zpool-docker -m /var/lib/docker /dev/nvme1n1
sudo wget -O /etc/docker/daemon.json https://raw.githubusercontent.com/ckmjreynolds/MariaDB-Stack/0.1.4/script/docker_daemon.json
sudo systemctl start docker
sudo rm -rf /var/lib/docker.bk
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

### [3.5 Setup SSL Encryption](https://hub.docker.com/r/certbot/dns-route53)
```bash
# Get SSL certificates.
docker run -it --rm --name certbot -v "/etc/letsencrypt:/etc/letsencrypt" \
    -v "/var/lib/letsencrypt:/var/lib/letsencrypt" certbot/dns-route53 \
    certonly --dns-route53 -d monitor.mssux.com

# Copy the SSL certificates.
sudo -i
cp -L /etc/letsencrypt/live/monitor.mssux.com/*.pem /home/ubuntu/.
chown ubuntu:ubuntu /home/ubuntu/*.pem
docker cp /home/ubuntu/fullchain.pem pmm-server:/srv/nginx/certificate.crt
docker cp /home/ubuntu/privkey.pem pmm-server:/srv/nginx/certificate.key
docker cp /home/ubuntu/chain.pem pmm-server:/srv/nginx/ca-certs.pem

# Restart pmm-server.
docker restart pmm-server
```

## 4. Create the `db1` EC2 Instance
```bash
# Ubuntu 20.04.1 LTS aarch64 (includes 3.1 below) - ami-00bae8092a688e69e
aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t4g.micro --image-id ami-00bae8092a688e69e \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --iam-instance-profile Name="db-stack-role" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=db1},{Key=Domain,Value=mssux.com}]"
```

### 4.1 Repeat [3.1](#31-setup-route-53-registration)
Repeat the Route 53 auto-registration steps above.

### 3.4 Install MariaDB
```bash
# Create the zpool for MariaDB
sudo zpool create -O relatime=on -O compression=lz4 -O logbias=throughput -O primarycache=metadata -O recordsize=16k -O xattr=sa \
    -o ashift=12 -o autoexpand=on -f zpool-mysql -m /var/lib/mysql /dev/nvme1n1

# Setup Repository
curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --skip-maxscale --skip-tools

# Install MariaDB
sudo apt-get install --yes mariadb-server galera-4 mariadb-client libmariadb3 mariadb-backup mariadb-common
sudo mysql_secure_installation

# Install S3 File System (for backups)
sudo apt-get install s3fs
sudo -i
mkdir /mnt/backup
echo 's3fs#mssux-backups /mnt/backup fuse _netdev,allow_other,iam_role=auto,storage_class=intelligent_tiering 0 0' >> /etc/fstab
reboot

# Setup backups.
sudo mkdir /home/mysql
sudo wget -O /home/mysql/backup.sh https://raw.githubusercontent.com/ckmjreynolds/MariaDB-Stack/0.1.4/script/backup.sh
sudo wget -O /home/mysql/.my.cnf https://raw.githubusercontent.com/ckmjreynolds/MariaDB-Stack/0.1.4/script/.my.cnf
sudo chown -R mysql:mysql /home/mysql
# Stop and disable MariaDB for now.
sudo systemctl stop mariadb
sudo systemctl disable mariadb
```

### 3.4 Patch and Reboot
```bash
sudo apt-get update
sudo apt-get upgrade --with-new-pkgs
sudo apt-get clean
```

# TODO - HERE

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


sudo zfs get all /var/lib/mysql |grep compressratio

```bash
# Create a temporary server to uses.
aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t4g.micro --image-id ami-0ea142bd244023692 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=temp},{Key=Domain,Value=mssux.com}]"

# https://openzfs.github.io/openzfs-docs/Getting%20Started/Ubuntu/Ubuntu%2020.04%20Root%20on%20ZFS.html#
sudo -i

# Update apt and install required packages
apt-get update; apt install --yes gdisk zfs-initramfs
systemctl stop zed

# Partition the new root EBS volume
DISK=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol0622f205e7c19abdd
sgdisk --zap-all ${DISK}

# EFI system partition
sgdisk -n1:1M:+512M -t1:EF00 $DISK

# For legacy (BIOS) booting:
sgdisk -a1 -n5:24K:+1000K -t5:EF02 $DISK

# SWAP Partition
sgdisk -n2:0:+500M -t2:8200 $DISK

# Create a boot pool partition:
sgdisk -n3:0:+2G -t3:BE00 $DISK

# Create a root pool partition: Unencrypted or ZFS native encryption:
sgdisk -n4:0:0 -t4:BF00 $DISK

# Create the boot pool.
zpool create \
    -o ashift=12 -d \
    -o feature@async_destroy=enabled \
    -o feature@bookmarks=enabled \
    -o feature@embedded_data=enabled \
    -o feature@empty_bpobj=enabled \
    -o feature@enabled_txg=enabled \
    -o feature@extensible_dataset=enabled \
    -o feature@filesystem_limits=enabled \
    -o feature@hole_birth=enabled \
    -o feature@large_blocks=enabled \
    -o feature@lz4_compress=enabled \
    -o feature@spacemap_histogram=enabled \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O devices=off -O normalization=formD -O relatime=on -O xattr=sa \
    -O mountpoint=/boot -R /mnt \
    bpool ${DISK}-part3

# Create zpool and filesystems on the new EBS volume
zpool create \
    -o ashift=12 \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O dnodesize=auto -O normalization=formD -O relatime=on \
    -O xattr=sa -O mountpoint=/ -R /mnt \
    rpool ${DISK}-part4

# Create filesystem datasets to act as containers:
zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=off -o mountpoint=none bpool/BOOT

# Create filesystem datasets for the root and boot filesystems:
zfs create -o canmount=noauto -o mountpoint=/ -o com.ubuntu.zsys:bootfs=yes -o com.ubuntu.zsys:last-used=$(date +%s) rpool/ROOT/ubuntu
zfs mount rpool/ROOT/ubuntu

zfs create -o canmount=noauto -o mountpoint=/boot bpool/BOOT/ubuntu
zfs mount bpool/BOOT/ubuntu

# Create datasets:
zfs create -o com.ubuntu.zsys:bootfs=no rpool/ROOT/ubuntu/srv
zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off rpool/ROOT/ubuntu/usr
zfs create rpool/ROOT/ubuntu/usr/local
zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off rpool/ROOT/ubuntu/var
zfs create rpool/ROOT/ubuntu/var/lib
zfs create rpool/ROOT/ubuntu/var/lib/AccountsService
zfs create rpool/ROOT/ubuntu/var/lib/apt
zfs create rpool/ROOT/ubuntu/var/lib/dpkg
zfs create rpool/ROOT/ubuntu/var/log
zfs create rpool/ROOT/ubuntu/var/mail
zfs create rpool/ROOT/ubuntu/var/snap
zfs create rpool/ROOT/ubuntu/var/spool

zfs create -o canmount=off -o mountpoint=/ rpool/USERDATA
zfs create -o com.ubuntu.zsys:bootfs-datasets=rpool/ROOT/ubuntu -o canmount=on -o mountpoint=/root rpool/USERDATA/root

# A tmpfs is recommended later, but if you want a separate dataset for /tmp:
zfs create -o com.ubuntu.zsys:bootfs=no rpool/ROOT/ubuntu/tmp
chmod 1777 /mnt/tmp

# Copy the filesystem.
rsync -axHAWXS --numeric-ids --info=progress2 / /mnt/

# Create mount points and chroot.
# Bind the virtual filesystems to the new system and chroot into it:
mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys
chroot /mnt /usr/bin/env DISK=$DISK bash --login

# Create the EFI filesystem Perform these steps for both UEFI and legacy (BIOS) booting:
rm -rf /boot/*
mkdosfs -F 32 -s 1 -n EFI ${DISK}-part1
mkdir /boot/efi
echo UUID=$(blkid -s UUID -o value ${DISK}-part1) /boot/efi vfat umask=0022,fmask=0022,dmask=0022 0 1 >> /etc/fstab
mount /boot/efi

# Put /boot/grub on the EFI System Partition For a single-disk install only:
mkdir /boot/efi/grub /boot/grub
echo /boot/efi/grub /boot/grub none defaults,bind 0 0 >> /etc/fstab
mount /boot/grub

# Install GRUB/Linux/ZFS for UEFI booting:
apt install --yes grub-efi-arm64 grub-efi-arm64-signed linux-image-generic shim-signed zfs-initramfs

# Configure swap: Choose one of the following options if you want swap:
# For an unencrypted single-disk install:
mkswap -f ${DISK}-part2
echo UUID=$(blkid -s UUID -o value ${DISK}-part2) none swap discard 0 0 >> /etc/fstab
swapon -a

# Verify that the ZFS boot filesystem is recognized:
grub-probe /boot

# Refresh the initrd files:
update-initramfs -c -k all

# Update the boot configuration:
update-grub

# For UEFI booting, install GRUB to the ESP:
grub-install --target=arm64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck --no-floppy

# Fix filesystem mount ordering:
mkdir /etc/zfs/zfs-list.cache
touch /etc/zfs/zfs-list.cache/bpool
touch /etc/zfs/zfs-list.cache/rpool
ln -s /usr/lib/zfs-linux/zed.d/history_event-zfs-list-cacher.sh /etc/zfs/zed.d
zed -F &

# Verify that zed updated the cache by making sure these are not empty:
cat /etc/zfs/zfs-list.cache/bpool
cat /etc/zfs/zfs-list.cache/rpool

# If either is empty, force a cache update and check again:
zfs set canmount=noauto bpool/BOOT/ubuntu
zfs set canmount=noauto rpool/ROOT/ubuntu

# Stop zed:
fg
Press Ctrl-C.

# Run these commands in the LiveCD environment to unmount all filesystems:
mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {}
zpool export -a

# Do not configure grub during package install
echo 'grub-pc grub-pc/install_devices_empty select true' | debconf-set-selections
echo 'grub-pc grub-pc/install_devices select' | debconf-set-selections

export DEBIAN_FRONTEND=noninteractive

# Install various packages needed for a booting system
apt-get install -y \
	grub-pc \
	zfsutils-linux \
	zfs-initramfs \
```

```bash
aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t3.micro --image-id ami-0dba2cb6798deb6d8 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=8,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=temp},{Key=Domain,Value=mssux.com}]"

aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t4g.micro --image-id ami-0ea142bd244023692 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=8,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=temp},{Key=Domain,Value=mssux.com}]"

# Become root and install needed packages.
sudo -i
apt-get update; apt-get install --yes zfsutils-linux
systemctl stop zed

# Create a variable for the install device.
DISK=/dev/nvme1n1

# Repartition the disk.
sgdisk --zap-all $DISK; sgdisk -n1:1M:+512M -t1:EF00 $DISK  # EFI Partition
sgdisk -n2:0:+1G -t2:BE00 $DISK                             # Boot Pool Partition
sgdisk -n3:0:0 -t3:BF00 $DISK                               # Root Pool Partition

# Create the boot pool.
zpool create \
    -o ashift=12 -d \
    -o feature@async_destroy=enabled \
    -o feature@bookmarks=enabled \
    -o feature@embedded_data=enabled \
    -o feature@empty_bpobj=enabled \
    -o feature@enabled_txg=enabled \
    -o feature@extensible_dataset=enabled \
    -o feature@filesystem_limits=enabled \
    -o feature@hole_birth=enabled \
    -o feature@large_blocks=enabled \
    -o feature@lz4_compress=enabled \
    -o feature@spacemap_histogram=enabled \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O devices=off -O normalization=formD -O relatime=on -O xattr=sa \
    -O mountpoint=/boot -R /mnt \
    bpool ${DISK}p2

# Create the root pool.
zpool create \
    -o ashift=12 -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O dnodesize=auto -O normalization=formD -O relatime=on -O xattr=sa \
    -O mountpoint=/ -R /mnt rpool ${DISK}p3

# Create filesystem datasets to act as containers:
zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=off -o mountpoint=none bpool/BOOT

# Create filesystem datasets for the root and boot filesystems:
UUID=$(dd if=/dev/urandom of=/dev/stdout bs=1 count=100 2>/dev/null |
    tr -dc 'a-z0-9' | cut -c-6)

zfs create -o canmount=noauto -o mountpoint=/ -o com.ubuntu.zsys:bootfs=yes \
    -o com.ubuntu.zsys:last-used=$(date +%s) rpool/ROOT/ubuntu_$UUID
zfs mount rpool/ROOT/ubuntu_$UUID

zfs create -o canmount=noauto -o mountpoint=/boot bpool/BOOT/ubuntu_$UUID
zfs mount bpool/BOOT/ubuntu_$UUID

# Copy the filesystem.
rsync -axHAWXS --numeric-ids --info=progress2 / /mnt/

# Chroot to the new filesystem.
cd /mnt/boot
mount --bind /boot/efi efi
cd ..
mount --bind /dev dev
mount --bind /proc proc
mount --bind /sys sys
mount --bind /run run
chroot /mnt /usr/bin/env DISK=$DISK UUID=$UUID bash --login

# Install GRUB
update-grub
grub-install $DISK
exit

# Run these commands in the LiveCD environment to unmount all filesystems:
zpool export -a

sda - vol-047a8c8c8e5902d81 - SNAP - snap-0753b13a85ff41fc6
sdb - vol-0d997acccae8302a3 - SNAP - snap-022c2a9925eaaedfd


aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t4g.micro --image-id ami-0ea142bd244023692 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=moho},{Key=Domain,Value=mssux.com}]"

aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t3.micro --image-id ami-0b02c5feef29d5c60 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1b"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sda,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
        "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
        "DeviceName=/dev/sdc,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=eve},{Key=Domain,Value=mssux.com}]"

aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t3.small --image-id ami-0b02c5feef29d5c60 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1c"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=kerbin},{Key=Domain,Value=mssux.com}]"

aws ec2 run-instances --key-name aws_chris_reynolds --instance-type t4g.micro --image-id ami-00bae8092a688e69e \
    --security-group-ids $(aws ec2 describe-security-groups --group-name database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=1,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-role" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=temp},{Key=Domain,Value=mssux.com}]"
