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

    $files[] = '_default.sh';

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

  public function generate_script() {
    $script = $this->read_child_script();

    if ($script === false) {
      return "#!/usr/bin/env bash\necho 'Error: Unable to locate suitable bootstrap script'\nexit 1\n";
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

  array_pop($buffer);

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
