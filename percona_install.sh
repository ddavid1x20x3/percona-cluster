#!/usr/bin/env bash

# Percona cluster installation script.

# The script is interactive. The user will be prompted to
# enter three IP addresses, one for each node, and then 
# let the script know on which node it's currently running.

# mysql_secure_installation script, which is performed on the 
# first node, will also need user input.

set -u -o pipefail

PACKAGE_MANAGER='dnf'

# Percona packages
EPEL='epel-release'
PERCONA_REPO='https://repo.percona.com/yum/percona-release-latest.noarch.rpm'
XTRADB_CLUSTER='percona-xtradb-cluster'
SET_PERCONA='percona-release'

# Configuration files
MYSQL_CONF='/etc/my.cnf'
SE_CONF='/etc/selinux/config'

function c() {

	clear

}

c

if [[ "$UID" -ne "0" ]]
then
	echo "Sorry, you are not root."
	exit 1
fi

read -rp "Enter the IP address of the first node: " FIRST_NODE

read -rp "Enter the IP address of the second node: " SECOND_NODE

read -rp "Enter the IP address of the third node: " THIRD_NODE

function configure_first_node() {

cat > "$MYSQL_CONF" <<EOF
[client]
socket=/var/lib/mysql/mysql.sock

[mysqld]
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
binlog_expire_logs_seconds=604800
wsrep_provider=/usr/lib64/galera4/libgalera_smm.so
wsrep_cluster_address=gcomm://${FIRST_NODE},${SECOND_NODE},${THIRD_NODE}
binlog_format=ROW
wsrep_slave_threads=8
wsrep_log_conflicts
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
wsrep_node_address=$FIRST_NODE
wsrep_cluster_name=percona-cluster
wsrep_node_name=$(hostname)
pxc_strict_mode=ENFORCING
wsrep_sst_method=xtrabackup-v2
wsrep_auto_increment_control=OFF
pxc-encrypt-cluster-traffic=OFF

EOF

}

function configure_second_node() {

cat > "$MYSQL_CONF" <<EOF
[client]
socket=/var/lib/mysql/mysql.sock

[mysqld]
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
binlog_expire_logs_seconds=604800
wsrep_provider=/usr/lib64/galera4/libgalera_smm.so
wsrep_cluster_address=gcomm://${FIRST_NODE},${SECOND_NODE},${THIRD_NODE}
binlog_format=ROW
wsrep_slave_threads=8
wsrep_log_conflicts
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
wsrep_node_address=$SECOND_NODE
wsrep_cluster_name=percona-cluster
wsrep_node_name=$(hostname)
pxc_strict_mode=ENFORCING
wsrep_sst_method=xtrabackup-v2
wsrep_auto_increment_control=OFF
pxc-encrypt-cluster-traffic=OFF

EOF

}

function configure_third_node() {

cat > "$MYSQL_CONF" <<EOF
[client]
socket=/var/lib/mysql/mysql.sock

[mysqld]
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
binlog_expire_logs_seconds=604800
wsrep_provider=/usr/lib64/galera4/libgalera_smm.so
wsrep_cluster_address=gcomm://${FIRST_NODE},${SECOND_NODE},${THIRD_NODE}
binlog_format=ROW
wsrep_slave_threads=8
wsrep_log_conflicts
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
wsrep_node_address=$THIRD_NODE
wsrep_cluster_name=percona-cluster
wsrep_node_name=$(hostname)
pxc_strict_mode=ENFORCING
wsrep_sst_method=xtrabackup-v2
wsrep_auto_increment_control=OFF
pxc-encrypt-cluster-traffic=OFF

EOF

}

function install_packages() {
	
	"$PACKAGE_MANAGER" install -y "$EPEL"
	"$PACKAGE_MANAGER" install -y "$PERCONA_REPO"
	"$SET_PERCONA" enable-only pxc-80 release
	"$SET_PERCONA" enable tools release
	"$SET_PERCONA" setup pxc-80
	"$PACKAGE_MANAGER" install -y "$XTRADB_CLUSTER"

}

function firewalld_setup() {

	local ports
	ports=(3306 4444 4567 4568)

	local PROTO
	PROTO='tcp'

	if ! which firewalld > /dev/null
	then
		"$PACKAGE_MANAGER" install firewalld -y
		systemctl --enable firewalld > /dev/null
	fi

	for PORT in "${ports[@]}"; do
		firewall-cmd --permanent --add-port="${PORT}/${PROTO}" &> /dev/null
	done

	firewall-cmd --reload > /dev/null

}

function disable_selinux() {

	grep -qE '^SELINUX=enforcing$' "$SE_CONF" && \
	sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' "$SE_CONF"

	grep -qE '^SELINUX=permissive$' "$SE_CONF" && \
	sed -i 's/^SELINUX=permissive$/SELINUX=disabled/' "$SE_CONF"

	setenforce 0

}

function mysql_setup() {

	systemctl start mysql > /dev/null
	local TEMP_PASS
	TEMP_PASS=$(grep 'temporary password' /var/log/mysqld.log | cut -d ' ' -f 13)
	echo "*************************************************************"
	echo "Temporary root password is:	>>>		$TEMP_PASS		<<<"
	echo "*************************************************************"
	echo "Secure installation is starting..."
	sleep 1
	mysql_secure_installation
	systemctl stop mysql

}

function backup_mysql_conf() {

	cp "$MYSQL_CONF" "${MYSQL_CONF}.bak"
	
}

echo ""
echo "Let me know is this the first, second, or third node in the cluster."
echo ""
read -rp "Enter '1', '2', or '3': " ANSWER

c

if [[ "$ANSWER" -eq 1 ]]
then
	install_packages
	c
	firewalld_setup
	disable_selinux
    mysql_setup
	backup_mysql_conf
	configure_first_node
	c
	echo "Bootstrapping the node..."
	systemctl start mysql@bootstrap
	systemctl enable mysql
	c
	echo "Bootstrap status is: "
	echo "**************************"
	systemctl status mysql@bootstrap
fi

if [[ "$ANSWER" -eq 2 ]]
then
	install_packages
	firewalld_setup
	disable_selinux
	backup_mysql_conf
	configure_second_node
	c
	echo "Starting MySQL service..."
	systemctl enable --now mysql
	c
	echo "MySQL service status is:"
	echo "**************************"
	systemctl status mysql
fi

if [[ "$ANSWER" -eq 3 ]]
then
	install_packages
	firewalld_setup
	disable_selinux
	backup_mysql_conf
	configure_third_node
	c
	echo "Starting MySQL service..."
	systemctl enable --now mysql
	c
	echo "MySQL service status is:"
	echo "**************************"
	systemctl status mysql
fi
