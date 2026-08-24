<?php
declare(strict_types=1);

final class ApiError extends RuntimeException
{
    public function __construct(public int $status, string $message) { parent::__construct($message); }
}

function respond(int $status, mixed $value): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    exit;
}

function pdfEncode(string $text): string
{
    if (!function_exists('iconv')) throw new ApiError(503, 'PDF-Export ist auf diesem Server nicht verfügbar');
    $encoded = iconv('UTF-8', 'Windows-1252//TRANSLIT', str_replace(["\r\n", "\r"], "\n", $text));
    if ($encoded === false) throw new ApiError(503, 'PDF-Text konnte nicht kodiert werden');
    return preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F]/', '', $encoded) ?? '';
}

function pdfEscape(string $text): string
{
    return str_replace(['\\', '(', ')'], ['\\\\', '\\(', '\\)'], $text);
}

function pdfBinary(string $title, array $lines, string $metadata): string
{
    $rows = [];
    foreach ($lines as $line) {
        $text = pdfEncode((string)($line['text'] ?? ''));
        $wrapped = $text === '' ? [''] : explode("\n", wordwrap($text, ($line['bold'] ?? false) ? 80 : 95, "\n", true));
        foreach ($wrapped as $part) $rows[] = ['text' => $part, 'bold' => (bool)($line['bold'] ?? false)];
    }
    $pages = array_chunk($rows, 48) ?: [[]];
    $objects = [
        1 => '<< /Type /Catalog /Pages 2 0 R >>',
        2 => '',
        3 => '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
        4 => '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'
    ];
    $kids = [];
    foreach ($pages as $index => $pageRows) {
        $pageObject = 5 + $index * 2;
        $contentObject = $pageObject + 1;
        $kids[] = "$pageObject 0 R";
        $content = "BT /F2 14 Tf 50 805 Td (" . pdfEscape(pdfEncode($title)) . ") Tj ET\n";
        foreach ($pageRows as $position => $row) {
            $font = $row['bold'] ? 'F2' : 'F1';
            $content .= "BT /$font 10 Tf 50 " . (780 - $position * 14) . " Td (" . pdfEscape($row['text']) . ") Tj ET\n";
        }
        $footer = pdfEncode($metadata . ' | Seite ' . ($index + 1) . '/' . count($pages));
        foreach (explode("\n", wordwrap($footer, 115, "\n", true)) as $footerIndex => $part) {
            $content .= "BT /F1 7 Tf 40 " . (25 + $footerIndex * 9) . " Td (" . pdfEscape($part) . ") Tj ET\n";
        }
        $content = rtrim($content, "\n");
        $objects[$pageObject] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents $contentObject 0 R >>";
        $objects[$contentObject] = "<< /Length " . strlen($content) . " >>\nstream\n$content\n" . 'endstream';
    }
    $objects[2] = '<< /Type /Pages /Kids [' . implode(' ', $kids) . '] /Count ' . count($pages) . ' >>';
    ksort($objects);
    $pdf = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n";
    $offsets = [0];
    foreach ($objects as $number => $object) {
        $offsets[$number] = strlen($pdf);
        $pdf .= "$number 0 obj\n$object\nendobj\n";
    }
    $xref = strlen($pdf);
    $pdf .= "xref\n0 " . (count($objects) + 1) . "\n0000000000 65535 f \n";
    for ($number = 1; $number <= count($objects); $number++) $pdf .= sprintf("%010d 00000 n \n", $offsets[$number]);
    return $pdf . "trailer\n<< /Size " . (count($objects) + 1) . " /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n";
}

function respondPdf(string $filename, string $title, array $lines, array $user): never
{
    $role = ['fuehrungskraft' => 'Führungskraft', 'einheitsleitung' => 'Einheitsführung', 'wehrleitung' => 'Wehrführung'][$user['role']] ?? $user['role'];
    $exportedAt = (new DateTimeImmutable('now', new DateTimeZone('UTC')))
        ->setTimezone(new DateTimeZone('Europe/Berlin'))
        ->format('d.m.Y H:i:s');
    $pdf = pdfBinary($title, $lines, "Exportiert am: $exportedAt Uhr (Europe/Berlin) | Nutzer: {$user['name']} | Rolle: $role");
    $safeFilename = preg_replace('/[^A-Za-z0-9._-]/', '-', $filename) ?: 'einsatzbericht.pdf';
    http_response_code(200);
    header('Content-Type: application/pdf');
    header('Content-Disposition: attachment; filename="' . $safeFilename . '"');
    header('Content-Length: ' . strlen($pdf));
    header('Cache-Control: no-store');
    echo $pdf;
    exit;
}

function config(): array
{
    static $config;
    if ($config !== null) return $config;
    $local = __DIR__ . DIRECTORY_SEPARATOR . 'config.local.php';
    $config = is_file($local) ? require $local : [];
    foreach ([
        'DB_DSN' => 'dsn', 'DB_USER' => 'user', 'DB_PASSWORD' => 'password', 'SETUP_TOKEN' => 'setup_token',
        'APP_URL' => 'app_url', 'MAIL_FROM' => 'mail_from', 'SMTP_HOST' => 'smtp_host',
        'SMTP_PORT' => 'smtp_port', 'SMTP_USERNAME' => 'smtp_username', 'SMTP_PASSWORD' => 'smtp_password',
        'SMTP_CA_FILE' => 'smtp_ca_file', 'DIVERA_API_BASE_URL' => 'divera_api_base_url'
    ] as $environment => $key) {
        $value = getenv($environment);
        if ($value !== false) $config[$key] = $value;
    }
    return $config;
}

function diveraBaseUrl(): string
{
    $base = rtrim((string)(config()['divera_api_base_url'] ?? 'https://app.divera247.com'), '/');
    $parts = parse_url($base);
    $host = $parts['host'] ?? '';
    $hostname = trim($host, '[]');
    if ($parts === false
        || !in_array($parts['scheme'] ?? '', ['http', 'https'], true)
        || $host === ''
        || (!filter_var($hostname, FILTER_VALIDATE_IP) && !filter_var($hostname, FILTER_VALIDATE_DOMAIN, FILTER_FLAG_HOSTNAME))
        || isset($parts['path']) || isset($parts['query']) || isset($parts['fragment']) || isset($parts['user']) || isset($parts['pass'])) {
        throw new ApiError(503, 'DIVERA-Basisadresse ist ungültig');
    }
    return $parts['scheme'] . '://' . $host . (isset($parts['port']) ? ':' . $parts['port'] : '');
}

function db(): PDO
{
    static $pdo;
    if ($pdo) return $pdo;
    $config = config();
    if (empty($config['dsn'])) throw new ApiError(503, 'Datenbankzugang ist nicht konfiguriert. Prüfen Sie DB_DSN oder config.local.php.');
    $pdo = new PDO($config['dsn'], $config['user'] ?? '', $config['password'] ?? '', [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false
    ]);
    $pdo->exec('SET NAMES utf8mb4');
    return $pdo;
}

function query(string $sql, array $params = []): PDOStatement
{
    $statement = db()->prepare($sql);
    $statement->execute($params);
    return $statement;
}

function one(string $sql, array $params = []): ?array
{
    $row = query($sql, $params)->fetch();
    return $row === false ? null : $row;
}

function transaction(callable $work): mixed
{
    db()->beginTransaction();
    try {
        $result = $work();
        db()->commit();
        return $result;
    } catch (Throwable $error) {
        if (db()->inTransaction()) db()->rollBack();
        throw $error;
    }
}

function input(): array
{
    $length = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);
    if ($length > 1_000_000) throw new ApiError(413, 'Anfrage zu groß');
    $raw = file_get_contents('php://input', false, null, 0, 1_000_001);
    if ($raw === false || strlen($raw) > 1_000_000) throw new ApiError(413, 'Anfrage zu groß');
    try {
        $data = json_decode($raw ?: '{}', true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        throw new ApiError(400, 'Ungültiges JSON');
    }

    if (!is_array($data)) throw new ApiError(400, 'Ungültiges JSON');
    return $data;
}

function requestIsHttps(): bool
{
    return strtolower((string)($_SERVER['HTTPS'] ?? '')) === 'on';
}

function sessionCookieName(): string
{
    return requestIsHttps() ? '__Host-session' : 'session';
}

function requestPath(): string
{
    $path = parse_url($_SERVER['REQUEST_URI'] ?? '/api', PHP_URL_PATH);
    $path = is_string($path) ? $path : '/api';
    $script = str_replace('\\', '/', (string)($_SERVER['SCRIPT_NAME'] ?? ''));
    // Apache keeps the install subdirectory in REQUEST_URI after rewriting to api.php.
    if (basename($script) === 'api.php') {
        $base = rtrim(str_replace('\\', '/', dirname($script)), '/.');
        if ($base !== '' && str_starts_with($path, "$base/")) $path = substr($path, strlen($base));
    }
    return rawurldecode($path);
}

function assertRequestOrigin(string $method): void
{
    if (in_array($method, ['GET', 'HEAD', 'OPTIONS'], true)) return;
    // JSON plus exact origin matching blocks browser CSRF without separate tokens.
    $contentType = strtolower(trim(explode(';', (string)($_SERVER['CONTENT_TYPE'] ?? ''))[0]));
    if ($contentType !== 'application/json') throw new ApiError(415, 'Content-Type muss application/json sein');
    $origin = rtrim((string)($_SERVER['HTTP_ORIGIN'] ?? ''), '/');
    if ($origin === '') return;
    $host = (string)($_SERVER['HTTP_HOST'] ?? '');
    $scheme = requestIsHttps() ? 'https' : 'http';
    if (!preg_match('/^[A-Za-z0-9.-]+(?::[0-9]+)?$/', $host) || !hash_equals("$scheme://$host", $origin)) {
        throw new ApiError(403, 'Anfrageursprung ist ungültig');
    }
}

function textLength(string $value): int
{
    return function_exists('mb_strlen') ? mb_strlen($value, 'UTF-8') : strlen($value);
}

function required(mixed $value, string $name, int $max = 10_000): string
{
    $text = trim(is_scalar($value) ? (string)$value : '');
    if ($text === '' || textLength($text) > $max) throw new ApiError(400, "$name ist ungültig");
    return $text;
}

function optional(mixed $value, string $name, int $max = 10_000): string
{
    $text = trim(is_scalar($value) ? (string)$value : '');
    if (textLength($text) > $max) throw new ApiError(400, "$name ist zu lang");
    return $text;
}

function emailAddress(mixed $value): string
{
    $email = required($value, 'E-Mail', 320);
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) throw new ApiError(400, 'E-Mail ist ungültig');
    return $email;
}

function mailSettings(): array
{
    $settings = config();
    $url = rtrim((string)($settings['app_url'] ?? ''), '/');
    $from = (string)($settings['mail_from'] ?? '');
    if (!filter_var($url, FILTER_VALIDATE_URL) || !str_starts_with($url, 'https://') || !filter_var($from, FILTER_VALIDATE_EMAIL)) {
        throw new ApiError(503, 'E-Mail-Versand ist nicht konfiguriert');
    }
    $smtpHost = trim((string)($settings['smtp_host'] ?? ''));
    $smtpPort = (int)($settings['smtp_port'] ?? 587);
    $smtpUsername = (string)($settings['smtp_username'] ?? '');
    $smtpPassword = (string)($settings['smtp_password'] ?? '');
    $smtpCaFile = (string)($settings['smtp_ca_file'] ?? '');
    if ($smtpHost !== '' && (
        !preg_match('/^[A-Za-z0-9.-]+$/', $smtpHost) || $smtpPort < 1 || $smtpPort > 65535 ||
        $smtpUsername === '' || $smtpPassword === '' || ($smtpCaFile !== '' && !is_file($smtpCaFile))
    )) throw new ApiError(503, 'SMTP ist nicht vollständig konfiguriert');
    return compact('url', 'from', 'smtpHost', 'smtpPort', 'smtpUsername', 'smtpPassword', 'smtpCaFile');
}

function smtpWrite($socket, string $data): bool
{
    while ($data !== '') {
        $written = fwrite($socket, $data);
        if ($written === false || $written === 0) return false;
        $data = substr($data, $written);
    }
    return true;
}

function smtpReply($socket, int $expected): bool
{
    for ($lines = 0; $lines < 100; $lines++) {
        $line = fgets($socket, 4096);
        if ($line === false || !preg_match('/^(\d{3})([ -])/', $line, $match)) return false;
        if ($match[2] === ' ') return (int)$match[1] === $expected;
    }
    return false;
}

function smtpCommand($socket, string $command, int $expected): bool
{
    return smtpWrite($socket, "$command\r\n") && smtpReply($socket, $expected);
}

function smtpSend(array $settings, string $to, string $subject, string $message): bool
{
    $ssl = ['verify_peer' => true, 'verify_peer_name' => true, 'peer_name' => $settings['smtpHost']];
    if ($settings['smtpCaFile'] !== '') $ssl['cafile'] = $settings['smtpCaFile'];
    $context = stream_context_create(['ssl' => $ssl]);
    $socket = @stream_socket_client(
        "tcp://{$settings['smtpHost']}:{$settings['smtpPort']}",
        $errorCode,
        $errorMessage,
        10,
        STREAM_CLIENT_CONNECT,
        $context
    );
    if ($socket === false) return false;
    stream_set_timeout($socket, 10);
    // Credentials are sent only after certificate-verified STARTTLS.
    $ok = smtpReply($socket, 220)
        && smtpCommand($socket, 'EHLO localhost', 250)
        && smtpCommand($socket, 'STARTTLS', 220)
        && stream_socket_enable_crypto($socket, true, STREAM_CRYPTO_METHOD_TLS_CLIENT) === true
        && smtpCommand($socket, 'EHLO localhost', 250)
        && smtpCommand($socket, 'AUTH LOGIN', 334)
        && smtpCommand($socket, base64_encode($settings['smtpUsername']), 334)
        && smtpCommand($socket, base64_encode($settings['smtpPassword']), 235)
        && smtpCommand($socket, "MAIL FROM:<{$settings['from']}>", 250)
        && smtpCommand($socket, "RCPT TO:<$to>", 250)
        && smtpCommand($socket, 'DATA', 354);
    if ($ok) {
        $body = str_replace(["\r\n", "\r"], "\n", $message);
        // SMTP ends DATA on a lone dot, so leading dots must be escaped.
        $body = str_replace("\n", "\r\n", preg_replace('/^\./m', '..', $body));
        $headers = 'Date: ' . gmdate(DATE_RFC2822) . "\r\nFrom: {$settings['from']}\r\nTo: $to\r\nSubject: $subject\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n";
        $ok = smtpWrite($socket, "$headers\r\n$body\r\n.\r\n") && smtpReply($socket, 250);
    }
    if ($ok) smtpCommand($socket, 'QUIT', 221);
    fclose($socket);
    return $ok;
}

function sendEmail(array $settings, string $to, string $subject, string $message): bool
{
    return $settings['smtpHost'] !== ''
        ? smtpSend($settings, $to, $subject, $message)
        : @mail($to, $subject, $message, "From: {$settings['from']}\r\nContent-Type: text/plain; charset=UTF-8");
}

function finiteNumber(mixed $value, string $name): int|float|null
{
    if ($value === null || $value === '') return null;
    if (!is_numeric($value) || !is_finite((float)$value)) throw new ApiError(400, "$name ist ungültig");
    return (float)$value == (int)$value ? (int)$value : (float)$value;
}
