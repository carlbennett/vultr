#!/usr/bin/env bash
# vim: set colorcolumn=:
#
#{BOOTSTRAP_INIT_LOG}
#
# @author    Carl Bennett <carl@carlbennett.me>
# @copyright (c) 2020-2021 Carl Bennett, All Rights Reserved.
#
# Bootstraps a Fedora 30 or later system on Vultr.com.

# Exit on non-zero return code for any command
set -e -o pipefail

# Load environment
[ -s /tmp/firstboot.env ] && source /tmp/firstboot.env

# Echo output
set -x

#
# Setup secondary network interface
#
setup_secondary_network() {
  eth1_id="$(curl -fsL 'http://169.254.169.254/v1/interfaces/1/networkid' | grep -P -o '^net(?:[0-9a-f]{13})$')"
  [ -z "${eth1_id}" ] && echo 'Empty network id for interface 1' && return 1

  eth1_mac="$(curl -fsL 'http://169.254.169.254/v1/interfaces/1/mac')"
  eth1_addr="$(curl -fsL 'http://169.254.169.254/v1/interfaces/1/ipv4/address')"
  eth1_netmask="$(curl -fsL 'http://169.254.169.254/v1/interfaces/1/ipv4/netmask')"
  eth1_mtu=1450 # Vultr recommends 1450 MTU for private network interface

  eth1_nic=`nmcli --fields 'GENERAL.DEVICE,GENERAL.HWADDR' d show | grep -i "${eth1_mac}" -B1 | head -n1 | awk '{print $2}'`
  nmcli_addr="${eth1_addr}`ipcalc -p \"${eth1_addr}\" \"${eth1_netmask}\" | sed -n 's/^PREFIX=\(.*\)/\/\1/p'`"

  ip -o a sh ${eth1_nic} | grep "${nmcli_addr}" || (
    nmcli c down 'Wired connection 2' || true
    nmcli d disconnect "${eth1_nic}" || true

    nmcli c modify 'Wired connection 2' ipv4.method 'manual' ipv4.address "${nmcli_addr}" connection.interface-name "${eth1_nic}" 802-3-ethernet.mtu "${eth1_mtu}"
    nmcli d set "${eth1_nic}" managed yes autoconnect yes
    nmcli c up 'Wired connection 2'
  )
}
setup_secondary_network || echo 'Failed to setup secondary network'

#
# Setup swap
#
setup_swap() {
  [ -z "${SWAPFILE}" ] && return 0 # error empty string
  [ -z "${SWAPSIZE}" ] && return 0 # error empty size
  [ -f "${SWAPFILE}" ] && return 0 # error file exists

  dd if=/dev/zero of="${SWAPFILE}" bs=1M count="${SWAPSIZE}" status=progress
  chmod 600 "${SWAPFILE}"
  mkswap "${SWAPFILE}"
  swapon "${SWAPFILE}"
  echo "${SWAPFILE} none swap defaults 0 0" >> /etc/fstab

  [ -n "${SWAPPINESS}" ] && (
    echo '# Generated by Bootstrap Script' > /etc/sysctl.d/99-swappiness.conf
    echo "vm.swappiness = ${SWAPPINESS}" >> /etc/sysctl.d/99-swappiness.conf
    sysctl -p /etc/sysctl.d/99-swappiness.conf
  )
}
setup_swap || echo 'Failed to setup swap'

#
# Upgrade system packages
#
dnf upgrade -y --refresh --setopt=install_weak_deps=False --best || echo 'Failed to upgrade system packages'

#
# Install standard suite of additional packages
#
dnf install -y \
    bind-utils     bzip2          curl           firewalld      git            \
    gzip           htop           mtr            net-tools      nmap-ncat      \
    tar            tmux           traceroute     unzip          vim-enhanced   \
    wget           whois          zip

#
# Enable automatic security updates via dnf-automatic
#
setup_dnf_automatic() {
  dnf install -y dnf-automatic

  sed -i 's/^upgrade_type = default/upgrade_type = security/' /etc/dnf/automatic.conf
  sed -i 's/^email_from = root@example.com/email_from = dnf-automatic@carlbennett.me/' /etc/dnf/automatic.conf
  sed -i 's/^email_to = root/email_to = '"${SYSADMIN}"'/' /etc/dnf/automatic.conf

  systemctl enable --now dnf-automatic-install.timer
}
setup_dnf_automatic || echo 'Failed to setup dnf automatic updates'

#
# Setup monitoring
#
setup_monitoring() {
  pushd /tmp
  curl -fsSLO 'https://github.com/prometheus/node_exporter/releases/download/v0.15.2/node_exporter-0.15.2.linux-amd64.tar.gz'
  tar -xzvf 'node_exporter-0.15.2.linux-amd64.tar.gz'
  cp 'node_exporter-0.15.2.linux-amd64/node_exporter' '/usr/local/bin'
  rm -Rf 'node_exporter-0.15.2.linux-amd64' 'node_exporter-0.15.2.linux-amd64.tar.gz'
  restorecon '/usr/local/bin/node_exporter'
  popd

  touch '/etc/default/node_exporter'
  cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus exporter for machine metrics, written in Go with pluggable metric collectors.
Documentation=https://github.com/prometheus/node_exporter
After=network.target

[Service]
EnvironmentFile=-/etc/default/node_exporter
User=root
ExecStart=/usr/local/bin/node_exporter \$NODE_EXPORTER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now node_exporter
}
setup_monitoring || echo 'Failed to setup monitoring'

#
# Setup firewall
#
setup_firewall() {
  systemctl restart dbus
  systemctl enable --now firewalld.service

  eth1_id="$(curl -fsL 'http://169.254.169.254/v1/interfaces/1/networkid' | grep -P -o '^net(?:[0-9a-f]{13})$')"
  [ -z "${eth1_id}" ] && (
    echo 'Empty network id for interface 1'
  ) || (
    eth1_addr=`curl -s 'http://169.254.169.254/v1/interfaces/1/ipv4/address'`
    eth1_netmask=`curl -s 'http://169.254.169.254/v1/interfaces/1/ipv4/netmask'`
    eval $(ipcalc -np "${eth1_addr}" "${eth1_netmask}")
    eth1_network="${NETWORK}/${PREFIX}"

    [[ "${eth1_network}" == '/' ]] && eth1_network='' || \
      firewall-cmd --permanent --zone trusted --add-source "${eth1_network}"
  )

  for network in ${TRUSTED_NETWORKS[@]}; do
    firewall-cmd --permanent --zone trusted --add-source "${network}"
  done

  firewall-cmd --reload
}
setup_firewall || echo 'Failed to setup firewall settings'

#
# Setup fail2ban
#
setup_fail2ban() {
  dnf install -y fail2ban-firewalld fail2ban-selinux fail2ban-server
  cat <<EOF > /etc/fail2ban/jail.d/01-sshd.conf
[sshd]
enabled = true

findtime = 600
maxretry = 5
bantime = 3600
EOF
  cat <<EOF > /etc/fail2ban/jail.d/99-local.conf
[DEFAULT]
destemail = ${SYSADMIN}
sendername = fail2ban@carlbennett.me
mta = sendmail
#action = %(action_mwl)s
EOF
  systemctl enable --now fail2ban.service
}
setup_fail2ban || echo 'Failed to setup fail2ban'

#
# Setup mail relay
#
setup_mail_relay() {
  dnf install -y ssmtp
  dnf remove -y postfix
  rm -Rfv /etc/postfix
  [ -f /etc/ssmtp/ssmtp.conf ] && mv -v /etc/ssmtp/ssmtp.conf /etc/ssmtp/ssmtp.conf.rpmsave
  cat <<EOF > /etc/ssmtp/ssmtp.conf
root=
mailhub=${SMTP_HOST}
RewriteDomain=${SMTP_REWRITEDOMAIN}
UseTLS=Yes
UseSTARTTLS=Yes
TLS_CA_File=/etc/pki/tls/certs/ca-bundle.crt
AuthUser=${SMTP_USER}
AuthPass=${SMTP_PASS}
AuthMethod=PLAIN
EOF
}
setup_mail_relay || echo 'Failed to setup mail relay'

#
# Setup the motd script
#
setup_motd() {
  curl -fsSL -o '/etc/profile.d/motd.sh' "${MOTD_URL}"
}
setup_motd || echo 'Failed to setup the motd script'

#
# Email log to sysadmin
#
send_email() {
  eth0_addr=$(curl -s 'http://169.254.169.254/v1/interfaces/0/ipv4/address')
  platform=$(egrep '^ID' /etc/os-release | cut -c4- | awk '{printf("%s%s\n",toupper(substr($0,1,1)),substr($0,2))}')
  version=$(egrep '^VERSION_ID' /etc/os-release | cut -c12-)

  echo "From: root@$(hostname -f)" >> /tmp/firstboot.email.log
  echo "To: ${SYSADMIN}" >> /tmp/firstboot.email.log
  echo "Subject: [Vultr] Bootstrap Complete [${platform} ${version}] [${eth0_addr}]" >> /tmp/firstboot.email.log
  echo 'Content-Type: text/plain;charset=utf-8' >> /tmp/firstboot.email.log
  echo 'Content-Transfer-Encoding: base64' >> /tmp/firstboot.email.log
  echo >> /tmp/firstboot.email.log

  journalctl -S today -u cloud* > /tmp/firstboot.emailbody.log 2>&1
  [ -f /tmp/firstboot.log ] && cat /tmp/firstboot.log >> /tmp/firstboot.emailbody.log
  base64 -w 76 /tmp/firstboot.emailbody.log >> /tmp/firstboot.email.log
  rm /tmp/firstboot.emailbody.log

  cat /tmp/firstboot.email.log | sendmail "${SYSADMIN}"
}
send_email || echo 'Failed to send email with output log'

#
# Copy output of log from /tmp to /var/tmp to survive reboot
#
[ -f /tmp/firstboot.log ] && cp -av /tmp/firstboot.log /var/tmp/firstboot.log

#
# Reboot
#
#reboot || echo 'Failed to reboot the system'
