#!/bin/bash
echo $(date) " - Starting Bastion Prep Script"

export USERNAME_ORG=$1
export PASSWORD_ACT_KEY="$2"
export POOL_ID=$3
export PRIVATEKEY=$4
export SUDOUSER=$5
export PROXYSETTING=$6
export HTTPPROXYENTRY="$7"
export HTTSPPROXYENTRY="$8"
export NOPROXYENTRY="$9"
export CUSTOMROUTINGCERTTYPE=${10}
export CUSTOMMASTERCERTTYPE=${11}
export CUSTOMROUTINGCAFILE="${12}"
export CUSTOMROUTINGCERTFILE="${13}"
export CUSTOMROUTINGKEYFILE="${14}"
export CUSTOMMASTERCAFILE="${15}"
export CUSTOMMASTERCERTFILE="${16}"
export CUSTOMMASTERKEYFILE="${17}"


# Generate private keys for use by Ansible
echo $(date) " - Generating Private keys for use by Ansible for OpenShift Installation"

runuser -l $SUDOUSER -c "echo \"$PRIVATEKEY\" > ~/.ssh/id_rsa"
runuser -l $SUDOUSER -c "chmod 600 ~/.ssh/id_rsa*"

# Remove RHUI

rm -f /etc/yum.repos.d/rh-cloud.repo
sleep 10

# Configure Proxy settings
if [[ $PROXYSETTING == "custom" ]]
then
	export http_proxy=$HTTPPROXYENTRY
	export https_proxy=$HTTSPPROXYENTRY
    echo $(date) " - Configure proxy settings"
    echo "export http_proxy=$HTTPPROXYENTRY
export https_proxy=$HTTSPPROXYENTRY
export no_proxy=$NOPROXYENTRY
" >> /etc/environment
    echo $(date) " - Configure proxy settings"
    echo "export http_proxy=$HTTPPROXYENTRY
export https_proxy=$HTTSPPROXYENTRY
export no_proxy=$NOPROXYENTRY
" >> /etc/profile
fi

# Register Host with Cloud Access Subscription
echo $(date) " - Register host with Cloud Access Subscription"

subscription-manager register --force --username="$USERNAME_ORG" --password="$PASSWORD_ACT_KEY" || subscription-manager register --force --activationkey="$PASSWORD_ACT_KEY" --org="$USERNAME_ORG"
RETCODE=$?

if [ $RETCODE -eq 0 ]
then
    echo "Subscribed successfully"
elif [ $RETCODE -eq 64 ]
then
    echo "This system is already registered."
else
    echo "Incorrect Username / Password or Organization ID / Activation Key specified"
    exit 3
fi

subscription-manager attach --pool=$POOL_ID > attach.log
if [ $? -eq 0 ]
then
    echo "Pool attached successfully"
else
    grep attached attach.log
    if [ $? -eq 0 ]
    then
        echo "Pool $POOL_ID was already attached and was not attached again."
    else
        echo "Incorrect Pool ID or no entitlements available"
        exit 4
    fi
fi

# Disable all repositories and enable only the required ones
echo $(date) " - Disabling all repositories and enabling only the required repos"

subscription-manager repos --disable="*"

subscription-manager repos \
    --enable="rhel-7-server-rpms" \
    --enable="rhel-7-server-extras-rpms" \
    --enable="rhel-7-server-ose-3.11-rpms" \
    --enable="rhel-7-server-ansible-2.6-rpms" \
    --enable="rhel-7-fast-datapath-rpms" \
    --enable="rh-gluster-3-client-for-rhel-7-server-rpms"

# Update system to latest packages
echo $(date) " - Update system to latest packages"
yum -y update --releasever=7.5 --exclude=WALinuxAgent
echo $(date) " - System update complete"

# Install base packages and update system to latest packages
echo $(date) " - Install base packages"
yum -y install wget git net-tools bind-utils iptables-services bridge-utils bash-completion httpd-tools kexec-tools sos psacct
yum -y install ansible
yum -y update glusterfs-fuse
echo $(date) " - Base package installation complete"

# Install OpenShift utilities
echo $(date) " - Installing OpenShift utilities"

yum -y install openshift-ansible
echo $(date) " - OpenShift utilities installation complete"
rm -rf /usr/share/ansible/openshift-ansible/roles/openshift_control_plane/tasks/main.yml
wget -O /usr/share/ansible/openshift-ansible/roles/openshift_control_plane/tasks/main.yml https://spektraazurelabs.blob.core.windows.net/openshiftodl/main.yml

# Installing Azure CLI
# From https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-yum
echo $(date) " - Installing Azure CLI"
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
sudo yum install -y azure-cli
echo $(date) " - Azure CLI installation complete"

# Install ImageMagick to resize image for Custom Header
sudo yum install -y ImageMagick

# Configure DNS so it always has the domain name
echo $(date) " - Adding DOMAIN to search for resolv.conf"
echo "DOMAIN=`domainname -d`" >> /etc/sysconfig/network-scripts/ifcfg-eth0

# Run Ansible Playbook to update ansible.cfg file
echo $(date) " - Updating ansible.cfg file"
wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 5 https://raw.githubusercontent.com/microsoft/openshift-container-platform-playbooks/master/updateansiblecfg.yaml
ansible-playbook -f 10 ./updateansiblecfg.yaml

# Create certificate files 

if [[ $CUSTOMMASTERCERTTYPE == "custom" ]]
then
    echo $(date) " - Creating custom master certificate files"
    runuser -l $SUDOUSER -c "echo \"$CUSTOMMASTERCAFILE\" > /tmp/masterca.pem"
	runuser -l $SUDOUSER -c "echo \"$CUSTOMMASTERCERTFILE\" > /tmp/mastercert.pem"
	runuser -l $SUDOUSER -c "echo \"$CUSTOMMASTERKEYFILE\" > /tmp/masterkey.pem"
	echo $(date) " - Custom master certificate files masterca.pem, mastercert.pem, masterkey.pem created in /tmp"
fi

if [ $CUSTOMROUTINGCERTTYPE == "custom" ]
then
    echo $(date) " - Creating custom routing certificate files"
	runuser -l $SUDOUSER -c "echo \"$CUSTOMROUTINGCAFILE\" > /tmp/routingca.pem"
	runuser -l $SUDOUSER -c "echo \"$CUSTOMROUTINGCERTFILE\" > /tmp/routingcert.pem"
	runuser -l $SUDOUSER -c "echo \"$CUSTOMROUTINGKEYFILE\" > /tmp/routingkey.pem"
	echo $(date) " - Custom routing certificate files routingca.pem, routingcert.pem, routingkey.pem created in /tmp"
fi

echo $(date) " - Script Complete"

