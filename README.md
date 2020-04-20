# MariaDB-Stack
A simplified, reference implementation of a database stack, deployed using a Docker Swarm consisting of a three node MariaDB Galera cluster and using ProxySQL to provide load balancing.

## Example Deployment (AWS)
The example deployment utilizes three AWS EC2 instances running the Ubuntu distribution. The sample configuration is as small as possible and not practical for most production loads.

### Instances
| Hostname | Instance Type  | Availability Zone | Operating System     | Description    |
| :------- | :------------- | :---------------- |:-------------------- | :------------- |
| `moho`   | `t3.micro 1GB` | `us-east-1a`      | `Ubuntu 20.04.0 LTS` | Manager/Worker |
| `eve`    | `t3.micro 1GB` | `us-east-1b`      | `Ubuntu 20.04.0 LTS` | Manager/Worker |
| `kerbin` | `t3.micro 1GB` | `us-east-1c`      | `Ubuntu 20.04.0 LTS` | Manager/Worker |

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
| `2377/TCP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `7946/TCP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `7946/UDP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `4789/UDP`    | `172.31.0.0/16`      | Docker Swarm                  |
| `9000/TCP`    | `XXX.XXX.XXX.XXX/32` | Portainer for Administration  |
| `8000/TCP`    | `172.31.0.0/16`      | Portainer Agent Communication |
| `6033/TCP`    | `XXX.XXX.XXX.XXX/32` | ProxySQL Traffic              |
| `6032/TCP`    | `XXX.XXX.XXX.XXX/32` | ProxySQL Administration       |
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
