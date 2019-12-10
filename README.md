# MariaDB-Stack
A simplified, reference implementation of a database stack, deployed using a Docker swarm, consisting of a three node MariaDB Galera cluster and using ProxySQL to provide load balancing.

## Example Deployment (AWS)
The example deployment utilizes three AWS EC2 instances running the Ubuntu distribution.

### Instances

| Hostname | Instance Type  | AZ | Operating System     | Description              |
| :------- | :------------- | :- |:-------------------- | :----------------------- |
| `moho`   | `t3.micro 1GB` |    | `Ubuntu 18.04.3 LTS` | Galera node `nineveh`    |
| `eve`    | `t3.micro 1GB` |    | `Ubuntu 18.04.3 LTS` | Galera node `alexandria` |
| `kerbin` | `t3.micro 1GB` |    | `Ubuntu 18.04.3 LTS` | Galera node `pergamum`   |
| `duna`   | `t3.micro 1GB` |    | `Ubuntu 18.04.3 LTS` |                          |
| `dres`   | `t3.micro 1GB` |    | `Ubuntu 18.04.3 LTS` |                          |

### Prerequisites
- Instances created and patched.
- [Security group](#security-group) configured and applied.
- Docker [installed](#install-docker).
- Docker Swarm [created](#setup-docker-swarm).
- EFS [mounted](#mount-efs) as `/efs` (for backups).

### Create Directories
Create directories for the Galera nodes on each instance.

| Hostname | Command / Directory                            |
| :------- | :--------------------------------------------- |
| `moho`   | `mkdir --mode=777 -p ~/galera/data/nineveh`    |
| `eve`    | `mkdir --mode=777 -p ~/galera/data/alexandria` |
| `kerbin` | `mkdir --mode=777 -p ~/galera/data/pergamum`   |

### Create Backup Link
```bash
sudo mkdir --mode=777 /efs/galera_backup
ln -s /efs/galera_backup ~/galera/data/backup
```

### Deploy `docker-compose.yml`
```bash
scp docker-compose.yml ubuntu@moho.<domain>.<tld>:~/galera/docker-compose.yml
scp Testing/mysql ubuntu@moho.<domain>.<tld>:~/galera/mysql
scp Testing/monitor.sh ubuntu@moho.<domain>.<tld>:~/galera/monitor.sh
```

### Create Secrets
```bash
echo <password> |docker secret create MYSQL_ROOT_PASSWORD -
echo <password> |docker secret create PROXYSQL_ADMIN_PASSWORD -
echo <password> |docker secret create PROXYSQL_USER_PASSWORD -
```

### Deploy the Stack (`moho`)
```bash
# 1. Deploy the stack.
cd ~/galera
docker stack deploy -c docker-compose.yml galera

# 2. Bootstrap the cluster.
touch ./data/nineveh/bootstrap
docker service scale galera_nineveh=1

# 3. Add alexandria to the cluster.
docker service scale galera_alexandria=1

# 4. Add pergamum to the cluster.
docker service scale galera_pergamum=1

# 5. Start ProxySQL.
docker service scale galera_proxysql=1

# 6. Crude monitoring.
./monitor.sh <password>
```

### Backup
```bash
ssh ubuntu@kerbin.<domain>.<tld>
docker exec -it $(docker ps -q --filter NAME=galera_pergamum) /usr/local/bin/backup.sh
```

## Appendix
### Security Group
| Port/Protocol | Source               | Description            |
| ------------: | :------------------- | :--------------------- |
| `22/TCP`      | `XXX.XXX.XXX.XXX/32` | SSH for Administration |
| `2377/TCP`    | `172.31.0.0/16`      | Docker swarm           |
| `7946/TCP`    | `172.31.0.0/16`      | Docker swarm           |
| `7946/UDP`    | `172.31.0.0/16`      | Docker swarm           |
| `4789/UDP`    | `172.31.0.0/16`      | Docker swarm           |
| `2049/TCP`    | `172.31.0.0/16`      | NFS for EFS            |

### Install Docker
#### Setup Repository
```bash
sudo apt-get update
sudo apt-get install apt-transport-https ca-certificates curl	software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
```

#### Install Packages
```bash
sudo apt-get update
sudo apt-get install docker-ce docker-compose pass
```

#### Configure Docker
```bash
sudo groupadd docker
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

# On eve and kerbin
docker swarm join --token <token> <ip>:2377
```

### Mount EFS
```bash
sudo apt-get install nfs-common

# Edit fstab
sudo vi /etc/fstab

# Add
<your-efs-id>.efs.<zone>.amazonaws.com:/ /efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0

# Reboot
sudo reboot
```
