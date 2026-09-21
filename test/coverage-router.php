<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli-server' || !getenv('TEST_COVERAGE_DIR') || !function_exists('xdebug_start_code_coverage')) {
    throw new RuntimeException('Coverage-Router benötigt den lokalen Testserver, TEST_COVERAGE_DIR und Xdebug.');
}

$root = dirname(__DIR__);
$coveredFiles = [
    "$root/api.php", "$root/support.php", "$root/constants.php"
];
xdebug_set_filter(XDEBUG_FILTER_CODE_COVERAGE, XDEBUG_PATH_INCLUDE, $coveredFiles);
xdebug_start_code_coverage(XDEBUG_CC_UNUSED | XDEBUG_CC_DEAD_CODE);
register_shutdown_function(static function () use ($coveredFiles): void {
    $files = [];
    foreach (xdebug_get_code_coverage() as $file => $lines) {
        if (in_array($file, $coveredFiles, true)) $files[basename($file)] = $lines;
    }
    if ($files === []) return;
    $file = getenv('TEST_COVERAGE_DIR') . '/request-' . bin2hex(random_bytes(12)) . '.json';
    if (file_put_contents($file, json_encode($files, JSON_THROW_ON_ERROR), LOCK_EX) === false) {
        throw new RuntimeException('PHP-Coverage konnte nicht gespeichert werden.');
    }
});
return require "$root/api.php";
