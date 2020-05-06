#!/usr/bin/env bash
# vim: set colorcolumn=:
#
# @author    Carl Bennett
# @copyright (c) 2020 Carl Bennett, All Rights Reserved.
#
# Put this script in the Vultr account. The rest is magic.
set -ex -o pipefail
curl -fsSL -o /tmp/bootstrap.sh \
  'https://silicon.carlbennett.me/vultr/bootstrap/bootstrap.sh'
chmod +x /tmp/bootstrap.sh
[ ! -s /tmp/bootstrap.sh ] && exit 1

export BOOTSTRAP_URL='https://silicon.carlbennett.me/vultr/bootstrap/bootstrap.php'
export CONFIG_ENV_URL='https://silicon.carlbennett.me/vultr/bootstrap/config.env.enc'
export DECRYPTION_KEY='change_me'

exec /tmp/bootstrap.sh $@
