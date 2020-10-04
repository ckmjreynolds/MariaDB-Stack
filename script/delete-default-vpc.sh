#!/usr/bin/env bash
# https://gist.githubusercontent.com/jokeru/e4a25bbd95080cfd00edf1fa67b06996/raw/8a1ab88aa60e73e689d04b31669ac7ea1007ac67/aws_delete-default-vpc.sh
# get default vpc
vpc=$(aws ec2 describe-vpcs --filter Name=isDefault,Values=true | jq -r .Vpcs[0].VpcId)
if [ "${vpc}" = "null" ]; then
  echo "No default vpc found"
  continue
fi
echo "Found default vpc ${vpc}"

# get internet gateway
igw=$(aws ec2 describe-internet-gateways --filter Name=attachment.vpc-id,Values=${vpc} | jq -r .InternetGateways[0].InternetGatewayId)
if [ "${igw}" != "null" ]; then
  echo "Detaching and deleting internet gateway ${igw}"
  aws ec2 detach-internet-gateway --internet-gateway-id ${igw} --vpc-id ${vpc}
  aws ec2 delete-internet-gateway --internet-gateway-id ${igw}
fi

# get subnets
subnets=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${vpc} | jq -r .Subnets[].SubnetId)
if [ "${subnets}" != "null" ]; then
  for subnet in ${subnets}; do
    echo "Deleting subnet ${subnet}"
    aws ec2 delete-subnet --subnet-id ${subnet}
  done
fi

# https://docs.aws.amazon.com/cli/latest/reference/ec2/delete-vpc.html
# - You can't delete the main route table
# - You can't delete the default network acl
# - You can't delete the default security group

# delete default vpc
echo "Deleting vpc ${vpc}"
aws ec2 delete-vpc --vpc-id ${vpc}
