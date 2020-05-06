#!/usr/bin/env bash
# vim: set colorcolumn=0:
#
#{BOOTSTRAP_INIT_LOG}
#
cat > /dev/stderr <<EOF
Available information is non-specific. Cannot configure system.
For specific bootstrap configuration, POST to the following url:

  https://silicon.carlbennett.me/vultr/bootstrap/bootstrap.php

POST body should be a url-encoded combination of any of:

  app={PROJECT_NAME}
  hostname={HOSTNAME}
  platform={PLATFORM}
  platform_version={PLATFORM_VERSION}

Supported values vary, though they should be automatically set.
EOF
