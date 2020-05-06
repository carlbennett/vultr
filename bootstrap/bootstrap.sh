#!/usr/bin/env bash
# vim: set colorcolumn=:
#
# @author    Carl Bennett
# @copyright (c) 2020 Carl Bennett, All Rights Reserved.
#
# Dynamically bootstraps a Vultr system.
set -ex -o pipefail

# Retrieve configuration environment variables
setup_config_env() {
  curl -fsSL -o /tmp/firstboot.env.enc "${CONFIG_ENV_URL}" || return $?
  echo -n "${DECRYPTION_KEY}" | openssl enc -a -d -aes-256-cbc -salt -pbkdf2 -pass stdin -in /tmp/firstboot.env.enc -out /tmp/firstboot.env || return $?
}
setup_config_env || echo 'Failed to setup config.env'

# Retrieve bootstrap script
setup_bootstrap() {
  curl -fsSL -o /tmp/bootstrap.chain.sh \
    -d "hostname=$(hostname -f)" \
    -d "platform=$(egrep '^ID' /etc/os-release | cut -c4-)" \
    -d "platform_version=$(egrep '^VERSION_ID' /etc/os-release | cut -c12-)" \
    "${BOOTSTRAP_URL}" || return $?
  [ -s /tmp/bootstrap.chain.sh ] && chmod +x /tmp/bootstrap.chain.sh
}
setup_bootstrap || echo 'Failed to download bootstrap script'

# Begin bootstrap chain
exec /tmp/bootstrap.chain.sh $@
