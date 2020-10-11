# MariaDB-Stack
Here, we document a simplified reference implementation of a database stack consisting of two Galera nodes running MariaDB arbitrated by Galera Arbitrator on a third node. A two-node ProxySQL cluster provides load balancing. The design assumes highly-reliable but expensive block storage (EBS, SAN, etc.), which argues for the third Galera Arbitrator node instead of a traditional Galera node. This assumption is also the driver for the use of ZFS and compression.

## Example Deployment (AWS)
We leverage t4g.micro instances where possible since AWS is currently offering a free trial, these instances are cheaper in any case, and MariaDB fully supports the aarch64 architecture. We use t3.nano instances for the ProxySQL nodes since it is not currently released for aarch64. We use s3 for backups since it is considerably cheaper than EBS or EFS.

### Instances
| Hostname    | Instance Type   | Disk Space    | Availability Zone | Operating System      | Description                |
| :---------- | :-------------- | :------------ | :---------------- |:--------------------- | :------------------------- |
| `proxysql1` | `t3.nano 0.5GB` | `8GB / 1GB`   | `us-east-1a`      | `Ubuntu 20.04.01 LTS` | `ProxySQL v2.0.14 Node #1` |
| `proxysql2` | `t3.nano 0.5GB` | `8GB / 1GB`   | `us-east-1b`      | `Ubuntu 20.04.01 LTS` | `ProxySQL v2.0.14 Node #2` |
| `db1`       | `t4g.micro 1GB` | `8GB / 10GB`  | `us-east-1a`      | `Ubuntu 20.04.01 LTS` | `MariaDB 10.5.6 Node #1`   |
| `db2`       | `t4g.micro 1GB` | `8GB / 10GB`  | `us-east-1b`      | `Ubuntu 20.04.01 LTS` | `MariaDB 10.5.6 Node #2`   |
| `garb`      | `t4g.micro 1GB` | `8GB`         | `us-east-1c`      | `Ubuntu 20.04.01 LTS` | `Galera Arbitrator Node`   |

## 1. Clone this Repository
```bash
git clone --single-branch https://github.com/ckmjreynolds/MariaDB-Stack.git
cd MariaDB-Stack
```

## 2. Create Security Groups
```bash
# Get my IP address to setup Administration Ingress
IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

# Database Security Group
aws ec2 create-security-group --group-name db-database-sg --description "Database Security Group" \
    --tag-specifications "ResourceType=security-group,Tags={Key=Name,Value=db-database-sg}"

aws ec2 authorize-security-group-ingress --group-name db-database-sg --ip-permissions \
    IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp='${IP}'/32,Description="SSH for Administration."}]' \
    IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges='[{CidrIp='${IP}'/32,Description="MySQL for Administration."}]' \
    IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges='[{CidrIp=172.31.0.0/16,Description="MySQL for Application."}]'

aws ec2 authorize-security-group-ingress --group-name db-database-sg --source-group db-database-sg --protocol -1 --port -1

# Database ProxySQL Security Group
aws ec2 create-security-group --group-name db-proxysql-sg --description "Database ProxySQL Security Group" \
    --tag-specifications "ResourceType=security-group,Tags={Key=Name,Value=db-proxysql-sg}"

aws ec2 authorize-security-group-ingress --group-name db-proxysql-sg --ip-permissions \
    IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp='${IP}'/32,Description="SSH for Administration."}]' \
    IpProtocol=tcp,FromPort=6032,ToPort=6032,IpRanges='[{CidrIp='${IP}'/32,Description="ProxySQL Admin for Administration."}]' \
    IpProtocol=tcp,FromPort=6033,ToPort=6033,IpRanges='[{CidrIp='${IP}'/32,Description="ProxySQL for Administration."}]' \
    IpProtocol=tcp,FromPort=6033,ToPort=6033,IpRanges='[{CidrIp=172.31.0.0/16,Description="ProxySQL for Application."}]'

aws ec2 authorize-security-group-ingress --group-name db-proxysql-sg --source-group db-proxysql-sg --protocol -1 --port -1
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

envsubst < ./conf.d/IAM/IAM_policy.template > ./conf.d/IAM/IAM_policy.json
aws iam create-policy --policy-name db-stack-policy --policy-document file://./conf.d/IAM/IAM_policy.json
rm ./conf.d/IAM/IAM_policy.json

# Create a role with the given policy.
aws iam create-role --role-name db-stack-role --assume-role-policy-document file://./conf.d/IAM/trust.json
aws iam attach-role-policy --role-name db-stack-role \
    --policy-arn arn:aws:iam::$(aws sts get-caller-identity|jq -r '.Account'):policy/db-stack-policy

# Create an instance profile with the given role.
aws iam create-instance-profile --instance-profile-name db-stack-profile
aws iam add-role-to-instance-profile --instance-profile-name db-stack-profile --role-name db-stack-role
```

## 5. Create AMIs for Ubuntu 20.04 LTS - 64-bit x86 and 64-bit Arm
```bash
# Ubuntu Server 20.04 LTS (HVM), SSD Volume Type - ami-0dba2cb6798deb6d8 (64-bit x86) / ami-0ea142bd244023692 (64-bit Arm)
# Ubuntu Server 20.04 LTS amd64 - ami-0786791f6e8a47967
aws ec2 run-instances --key-name <ssh_key> --instance-type t3.nano --image-id ami-0dba2cb6798deb6d8 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name db-database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --iam-instance-profile Name="db-stack-profile" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=amd64},{Key=Domain,Value=<domain>}]"

# Ubuntu Server 20.04 LTS arm64 - ami-08f51af0a56da05bb
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
sudo apt-get update; sudo apt-get install --yes zfsutils-linux p7zip-full screen cloud-utils ec2-api-tools s3fs

# Install cli53.
sudo cp install/cli53-linux-amd64 /usr/local/bin/cli53
# OR
sudo cp install/cli53-linux-arm64 /usr/local/bin/cli53

sudo chmod +x /usr/local/bin/cli53

# Install registerRoute53.sh script.
sudo cp script/registerRoute53.sh /usr/local/bin/registerRoute53.sh
sudo chmod +x /usr/local/bin/registerRoute53.sh

# Schedule the script to run on reboot.
(cat script/crontab)| sudo crontab -
(sudo crontab -l; echo "@reboot /usr/local/bin/registerRoute53.sh")| sudo crontab -

# Install S3 File System (for backups)
sudo -i
mkdir /mnt/backup
echo 's3fs#<bucket> /mnt/backup fuse _netdev,allow_other,iam_role=auto,storage_class=intelligent_tiering 0 0' >> /etc/fstab
exit

# Install the Unified Cloud Watch Agent.
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
# OR
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb

sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status

# Reboot the server and verify DNS entry is added/updated and s3 bucket mounted.
sudo reboot

# If everything is working, patch the server, shutdown and create an AMI.
sudo apt-get update
sudo apt-get upgrade --with-new-pkgs
sudo apt-get clean
rm -rf /home/ubuntu/MariaDB-Stack
sudo shutdown now

# Create the AMIs.

# Terminate the instances.
AMD64=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=amd64"|jq -r '.Reservations[].Instances[].InstanceId')
ARM64=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=arm64"|jq -r '.Reservations[].Instances[].InstanceId')
aws ec2 terminate-instances --instance-ids ${AMD64} ${ARM64}
```

## 6. Create the Galera EC2 Instanes
```bash
# Ubuntu Server 20.04 LTS arm64 - ami-08f51af0a56da05bb
aws ec2 run-instances --key-name <ssh_key> --instance-type t4g.micro --image-id ami-08f51af0a56da05bb \
    --security-group-ids $(aws ec2 describe-security-groups --group-name db-database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-profile" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=db1},{Key=Domain,Value=<domain>}]"

aws ec2 run-instances --key-name <ssh_key> --instance-type t4g.micro --image-id ami-08f51af0a56da05bb \
    --security-group-ids $(aws ec2 describe-security-groups --group-name db-database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1b"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=10,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-profile" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=db2},{Key=Domain,Value=<domain>}]"
```

## 6.1. Create the Galera Nodes
```bash
# Repeat these steps for each of the Galera nodes.
# Create the zpool for MariaDB
sudo zpool create -O relatime=on -O compression=lz4 -O logbias=throughput -O primarycache=metadata -O recordsize=16k \
    -O xattr=sa -o ashift=12 -o autoexpand=on -f zpool-mysql -m /var/lib/mysql /dev/nvme1n1

# Setup Repository
curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --skip-maxscale --skip-tools

# Install MariaDB
sudo apt-get install --yes mariadb-server galera-4 mariadb-client libmariadb3 mariadb-backup mariadb-common
sudo mysql_secure_installation

# Setup Users
./script/configureUsers.sh <mariabackup password> <proxysql password>
sudo mysql
MariaDB [(none)]> SOURCE ./initdb.d/001_CREATE_USERS.sql
MariaDB [(none)]> exit

# Stop MariaDB for now.
sudo systemctl stop mariadb

# Setup this Node
./script/configureNode.sh <node>.<domain> <gtid_domain_id> <auto_increment_offset> \
    "gcomm://db1.<domain>,db2.<domain>,garb.<domain>" <server_id> <wsrep_gtid_domain_id> "mariabackup password"

# Bootstrap (on db1) or start (on db2) mariadb.
sudo systemctl enable mariadb

sudo galera_new_cluster
# OR
sudo systemctl start mariadb

sudo systemctl status mariadb.service

# Verify
sudo mysql -e "select variable_name, variable_value from information_schema.global_status where variable_name in ('wsrep_cluster_size', 'wsrep_local_state_comment', 'wsrep_cluster_status');"

# Backup Configuration
BACKUPDIR=/mnt/backup/${HOSTNAME}
TARGETFILE=${BACKUPDIR}/`date +%F_%H-%M-%S`.${HOSTNAME}.etc.mysql.7z
mkdir -p ${BACKUPDIR}
sudo 7z a ${TARGETFILE} /etc/mysql
```

### 6.2. Create the `garb` EC2 Instance
```bash
# Ubuntu Server 20.04 LTS arm64 - ami-08f51af0a56da05bb
aws ec2 run-instances --key-name <ssh_key> --instance-type t4g.micro --image-id ami-08f51af0a56da05bb \
    --security-group-ids $(aws ec2 describe-security-groups --group-name db-database-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1c"|jq -r '.Subnets[].SubnetId') \
    --iam-instance-profile Name="db-stack-profile" \
    --credit-specification CpuCredits="unlimited" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=garb},{Key=Domain,Value=<domain>}]"

# Install the MariaDB repository.
curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --skip-maxscale --skip-tools

# Install Galera Arbitrator
sudo apt-get install --yes galera-arbitrator-4

# Configure Galera Arbitrator
sudo -i
export CLUSTER_NODES="db1.<domain>,db2.<domain>"
export CLUSTER_NAME="<cluster name>"

envsubst < /home/ubuntu/MariaDB-Stack/conf.d/garb/garb.template > /etc/default/garb
exit

# Start Galera Arbitrator
sudo systemctl enable garb.service
sudo systemctl start garb
sudo systemctl status garb.service

# Backup Configuration
BACKUPDIR=/mnt/backup/${HOSTNAME}
TARGETFILE=${BACKUPDIR}/`date +%F_%H-%M-%S`.${HOSTNAME}.etc.default.garb.7z
mkdir -p ${BACKUPDIR}
7z a ${TARGETFILE} /etc/default/garb

# Cleanup
rm -rf MariaDB-Stack
```

### 6.3. Setup Backups (`db1` and `db2`)
```bash
# m h  dom mon dow   command
(sudo crontab -l; echo "0 2 * * * /home/ubuntu/MariaDB-Stack/script/backup.sh <mariabackup pwd> <encryption key>")| sudo crontab -
```

### 6.4. Recover Galera from Backups
#### 6.4.1. Bootstrap
```bash
# Re-build lost mount (for ephemeral LUNs)
sudo zpool create -O relatime=on -O compression=lz4 -O logbias=throughput -O primarycache=metadata -O recordsize=16k \
    -O xattr=sa -o ashift=12 -o autoexpand=on -f zpool-mysql -m /var/lib/mysql /dev/nvme1n1

# Extract the backup.
cd /var/lib/mysql
7z e <backupfile> -so -p<password> |sudo mbstream -x
sudo mariabackup --prepare --target-dir=.
sudo chown -R mysql:mysql /var/lib/mysql/

# Start MariaDB.
sudo systemctl enable mariadb
sudo galera_new_cluster
sudo systemctl status mariadb.service
```

#### 6.4.2. Recover the other nodes
```bash
# Re-build lost mount (for ephemeral LUNs)
sudo zpool create -O relatime=on -O compression=lz4 -O logbias=throughput -O primarycache=metadata -O recordsize=16k \
    -O xattr=sa -o ashift=12 -o autoexpand=on -f zpool-mysql -m /var/lib/mysql /dev/nvme1n1
sudo chown -R mysql:mysql /var/lib/mysql/

# Start MariaDB.
sudo systemctl enable mariadb
sudo systemctl start mariadb
sudo systemctl status mariadb.service
```

#### 6.4.3. Start Galara Arbitrator
```bash
# Start MariaDB.
sudo systemctl enable mariadb
sudo systemctl start mariadb
sudo systemctl status mariadb.service
```

## 7. Create the ProxySQL EC2 Instanes
```bash
# Ubuntu Server 20.04 LTS amd64 - ami-0786791f6e8a47967
aws ec2 run-instances --key-name <ssh_key> --instance-type t3.nano --image-id ami-0786791f6e8a47967 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name db-proxysql-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1a"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=1,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-profile" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=proxysql1},{Key=Domain,Value=<domain>}]"

aws ec2 run-instances --key-name <ssh_key> --instance-type t3.nano --image-id ami-0786791f6e8a47967 \
    --security-group-ids $(aws ec2 describe-security-groups --group-name db-proxysql-sg|jq -r '.SecurityGroups[].GroupId') \
    --subnet-id $(aws ec2 describe-subnets --filter "Name=availability-zone,Values=us-east-1b"|jq -r '.Subnets[].SubnetId') \
    --block-device-mappings "DeviceName=/dev/sdb,Ebs={DeleteOnTermination=true,VolumeSize=1,VolumeType=gp2}" \
    --iam-instance-profile Name="db-stack-profile" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=proxysql2},{Key=Domain,Value=<domain>}]"
```

### 7.1 Setup Mount
```bash
# Setup the mount for ProxySQL.
sudo zpool create -o ashift=12 -o autoexpand=on -O relatime=on -O compression=lz4 -f zpool-proxysql -m /var/lib/proxysql /dev/nvme1n1
```

### 7.2 Install ProxySQL
```bash
# Setup the repository.
wget -O - 'https://repo.proxysql.com/ProxySQL/repo_pub_key' | sudo apt-key add -
echo deb https://repo.proxysql.com/ProxySQL/proxysql-2.0.x/$(lsb_release -sc)/ ./ \
    | sudo tee /etc/apt/sources.list.d/proxysql.list

# Install ProxySQL
sudo apt-get update
sudo apt-get install proxysql mariadb-client-core-10.3
```

### 7.3 Setup ProxySQL
```bash
# Configure ProxySQL.
./script/configureProxySQLNode.sh <proxysql admin pwd> <proxysql pwd> <primary db> <secondary db> <proxysql peer>>

# Start ProxySQL.
sudo systemctl enable proxysql.service
sudo systemctl start proxysql

# Verify.
mysql -h127.0.0.1 -P6032 -uradmin -p<password> --prompt "ProxySQL Admin>"
ProxySQL Admin>SELECT * FROM mysql_servers\G

# Backup Configuration
BACKUPDIR=/mnt/backup/${HOSTNAME}
TARGETFILE=${BACKUPDIR}/`date +%F_%H-%M-%S`.${HOSTNAME}.etc.proxysql.cnf.7z
mkdir -p ${BACKUPDIR}
sudo 7z a ${TARGETFILE} /etc/proxysql.cnf

# Cleanup
rm -rf MariaDB-Stack
```

## X. Cleanup
```bash
# Cleanup Instances
INSTANCE5=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=proxysql2"|jq -r '.Reservations[].Instances[].InstanceId')
INSTANCE4=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=proxysql1"|jq -r '.Reservations[].Instances[].InstanceId')
INSTANCE3=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=garb"|jq -r '.Reservations[].Instances[].InstanceId')
INSTANCE2=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=db2"|jq -r '.Reservations[].Instances[].InstanceId')
INSTANCE1=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=db1"|jq -r '.Reservations[].Instances[].InstanceId')
aws ec2 terminate-instances --instance-ids ${INSTANCE1} ${INSTANCE2} ${INSTANCE3} ${INSTANCE4} ${INSTANCE5}

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
aws s3 rb s3://${BUCKET} --force

# Remove db-proxysql-sg Security Group
SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=db-proxysql-sg"|jq -r '.SecurityGroups[].GroupId')
aws ec2 delete-security-group --group-id ${SG}

# Remove db-database-sg Security Group
SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=db-database-sg"|jq -r '.SecurityGroups[].GroupId')
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
