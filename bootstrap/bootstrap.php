<?php /* vim: set colorcolumn=: */
/**
 * @author    Carl Bennett <carl@carlbennett.me>
 * @copyright (c) 2020 Carl Bennett, All Rights Reserved.
 *
 * Entrypoint for executing automatic bootstrap in Vultr.
 */

namespace CarlBennett\Vultr;

class Bootstrap {

  const BASE_PATH = '.';

  protected $app = '';
  protected $hostname = '';
  protected $platform = '';
  protected $platform_version = '';

  public function read_child_script() {
    $path = self::BASE_PATH . '/';

    $date = date('Y-m-d');

    $files = array();

    if (!empty($this->hostname)) {
      $files[] = sprintf('hostname/%s_%s.sh', $this->hostname, $date);
      $files[] = sprintf('hostname/%s.sh', $this->hostname);
    }

    if (!empty($this->app)) {
      $files[] = sprintf('app/%s_%s.sh', $this->app, $date);
      $files[] = sprintf('app/%s.sh', $this->app);
    }

    if (!empty($this->platform) && !empty($this->platform_version)) {
      $files[] = sprintf('platform/%s-%s_%s.sh', $this->platform, $this->platform_version, $date);
      $files[] = sprintf('platform/%s-%s.sh', $this->platform, $this->platform_version);
    }

    if (!empty($this->platform)) {
      $files[] = sprintf('platform/%s_%s.sh', $this->platform, $date);
      $files[] = sprintf('platform/%s.sh', $this->platform);
    }

    foreach ($files as $file) {
      $full_path = $path . $file;

      if (!(file_exists($full_path) && is_readable($full_path))) {
        echo sprintf("Cannot Load: %s\n", $full_path);
      } else {
        echo sprintf("    Loading: %s\n", $full_path);
        return file_get_contents($full_path);
      }
    }

    return false;
  }

  public static function generate_usage_error() {
    ob_start();

    echo "#!/usr/bin/env bash\n";
    echo "# vim: set colorcolumn=0:\n";
    echo "#\n";
    echo "#{BOOTSTRAP_INIT_LOG}\n";
    echo "#\n";
    echo "cat > /dev/stderr <<EOF\n";
    echo "Available information is non-specific. Cannot configure system.\n";
    echo "For specific bootstrap configuration, POST to the following url:\n";
    echo "\n";
    echo "  https://" . getenv('HTTP_HOST') . "/vultr/bootstrap/bootstrap.php\n";
    echo "\n";
    echo "POST body should be a url-encoded combination of any of:\n";
    echo "\n";
    echo "  app={PROJECT_NAME}\n";
    echo "  hostname={HOSTNAME}\n";
    echo "  platform={PLATFORM}\n";
    echo "  platform_version={PLATFORM_VERSION}\n";
    echo "\n";
    echo "Supported values vary, though they should be automatically set.\n";
    echo "EOF\n";

    return ob_get_clean();
  }

  public static function generate_preloader() {
    ob_start();

    echo "#!/usr/bin/env bash\n";
    echo "# vim: set colorcolumn=:\n";
    echo "#\n";
    echo "# @author    Carl Bennett <carl@carlbennett.me>\n";
    echo "# @copyright (c) 2020 Carl Bennett, All Rights Reserved.\n";
    echo "#\n";
    echo "# Dynamically bootstraps a Vultr system.\n";
    echo "set -ex -o pipefail\n";
    echo "\n";
    echo "# Retrieve configuration environment variables\n";
    echo "setup_config_env() {\n";
    echo "  curl -fsSL -o /tmp/firstboot.env.enc \"\${CONFIG_ENV_URL}\" || return $?\n";
    echo "  echo -n \"\${DECRYPTION_KEY}\" | openssl enc -a -d -aes-256-cbc -salt -pbkdf2 -pass stdin -in /tmp/firstboot.env.enc -out /tmp/firstboot.env || return $?\n";
    echo "}\n";
    echo "setup_config_env || echo 'Failed to setup config.env'\n";
    echo "\n";
    echo "# Retrieve bootstrap script\n";
    echo "setup_bootstrap() {\n";
    echo "  curl -fsSL -o /tmp/bootstrap.chain.sh \\\n";
    echo "    -d \"hostname=\$(hostname -f)\" \\\n";
    echo "    -d \"platform=\$(egrep '^ID' /etc/os-release | cut -c4-)\" \\\n";
    echo "    -d \"platform_version=\$(egrep '^VERSION_ID' /etc/os-release | cut -c12-)\" \\\n";
    echo "    \"\${BOOTSTRAP_URL}\" || return $?\n";
    echo "  [ -s /tmp/bootstrap.chain.sh ] && chmod +x /tmp/bootstrap.chain.sh\n";
    echo "}\n";
    echo "setup_bootstrap || echo 'Failed to download bootstrap script'\n";
    echo "\n";
    echo "# Begin bootstrap chain\n";
    echo "exec /tmp/bootstrap.chain.sh $@\n";

    return ob_get_clean();
  }

  public function generate_script() {

    if (empty($this->app) && empty($this->hostname) && empty($this->platform) && empty($this->platform_version)) {
      $script = self::generate_preloader();
    } else {
      $script = $this->read_child_script();
    }

    if ($script === false || empty($script)) {
      $script = $this->generate_usage_error();
    }

    return $script;
  }

  public function set_app(string $value) {
    echo sprintf("             App: %s\n", (empty($value) ? '-' : $value));
    $this->app = $value;
  }

  public function set_hostname(string $value) {
    echo sprintf("        Hostname: %s\n", (empty($value) ? '-' : $value));
    $this->hostname = $value;
  }

  public function set_platform(string $value) {
    echo sprintf("        Platform: %s\n", (empty($value) ? '-' : $value));
    $this->platform = $value;
  }

  public function set_platform_version(string $value) {
    echo sprintf("Platform Version: %s\n", (empty($value) ? '-' : $value));
    $this->platform_version = $value;
  }

}

function main() {

  ob_start();
  $runtime = new Bootstrap();

  $runtime->set_app(_arg_value('app', ''));
  $runtime->set_hostname(_arg_value('hostname', ''));
  $runtime->set_platform(_arg_value('platform', ''));
  $runtime->set_platform_version(_arg_value('platform_version', ''));
  echo "\n";

  $script = $runtime->generate_script();

  $buffer = explode("\n", ob_get_clean());

  for ($i = 0; $i < count($buffer); ++$i) {
    if (empty($buffer[$i])) {
      $buffer[$i] = '#';
    } else {
      $buffer[$i] = sprintf('# %s', $buffer[$i]);
    }
  }

  if ($buffer[count($buffer)-1] == '#') array_pop($buffer);

  $buffer = str_replace('#{BOOTSTRAP_INIT_LOG}', implode("\n", $buffer), $script);

  _response($buffer, 200, array('Content-Type' => 'text/plain;charset=utf-8'));
}

function _arg_value(string $name, $default = null) {
  return (isset($_POST[$name]) ? $_POST[$name] : $default);
}

function _response(string $body, int $code = 500, array $headers) {
  if (function_exists('http_response_code')) {
    http_response_code($code);
  } else {
    header(sprintf('%s %s', getenv('SERVER_PROTOCOL'), $code), true, $code);
  }

  foreach ($headers as $key => $value) {
    header(sprintf('%s: %s', $key, $value));
  }

  die($body);
}

main();
