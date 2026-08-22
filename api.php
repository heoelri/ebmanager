<?php
declare(strict_types=1);

final class ApiError extends RuntimeException
{
    public function __construct(public int $status, string $message) { parent::__construct($message); }
}

const ROLES = ['wehrleitung', 'einheitsleitung', 'fuehrungskraft'];
const SESSION_COOKIE = '__Host-session';
const INCIDENT_TYPES = [
    'Kleinbrand', 'Mittelbrand', 'Großbrand', 'Wald- und Flächenbrand',
    'Schornsteinbrand', 'Kfz-Brand', 'Verkehrsunfall', 'Oelunfall/Oelspur',
    'Chemieunfall', 'Technische Hilfe', 'Sturmeinsatz', 'Hochwassereinsatz',
    'Fehlalarm BMA', 'BMA', 'Fehlalarm', 'Böswilliger Alarm', 'Sonstiges'
];
const CLASSIFICATIONS = [
    'site' => [
        'Wohngebäude', 'Büro und Verwaltungsgebäude', 'Landwirtschaftlicher Betrieb',
        'Gewerbebetrieb', 'Industriebetrieb', 'Theater, Kino, Versammlungsstätte',
        'Alten- u. Pflegeeinrichtung, Klinik', 'Verkehrsfläche',
        'Wald, Heide, Moor, Feldflur', 'Sonstige'
    ],
    'cause' => [
        'Bauliche Mängel', 'Betriebliche u. maschinelle Mängel', 'Blitzschlag',
        'Elektrizität', 'Explosion', 'Fahrlässigkeit', 'Selbstentzündung',
        'Sonst. Feuer-, Licht- u. Wärmequelle', 'Verursacht durch Kinder',
        'Vorsätzliche Brandstiftung', 'Unbekannt'
    ],
    'technical' => [
        'Menschen in Notlage', 'Tiere in Notlage', 'Betriebsunfall',
        'Einsturz von Baulichkeiten', 'Gasausströmung', 'Gasvergiftung',
        'Schäden durch radioaktive Stoffe', 'Wasserschaden', 'Sturmschaden',
        'Sonstige technische Hilfeleistung'
    ]
];

function respond(int $status, mixed $value): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    exit;
}

function config(): array
{
    static $config;
    if ($config !== null) return $config;
    $local = __DIR__ . DIRECTORY_SEPARATOR . 'config.local.php';
    $config = is_file($local) ? require $local : [];
    foreach (['DB_DSN' => 'dsn', 'DB_USER' => 'user', 'DB_PASSWORD' => 'password', 'SETUP_TOKEN' => 'setup_token', 'APP_URL' => 'app_url', 'MAIL_FROM' => 'mail_from'] as $environment => $key) {
        $value = getenv($environment);
        if ($value !== false) $config[$key] = $value;
    }
    return $config;
}

function db(): PDO
{
    static $pdo;
    if ($pdo) return $pdo;
    $config = config();
    if (empty($config['dsn'])) throw new RuntimeException('Datenbank ist nicht konfiguriert');
    $pdo = new PDO($config['dsn'], $config['user'] ?? '', $config['password'] ?? '', [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
        PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4"
    ]);
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

function assertRequestOrigin(string $method): void
{
    if (in_array($method, ['GET', 'HEAD', 'OPTIONS'], true)) return;
    $contentType = strtolower(trim(explode(';', (string)($_SERVER['CONTENT_TYPE'] ?? ''))[0]));
    if ($contentType !== 'application/json') throw new ApiError(415, 'Content-Type muss application/json sein');
    $origin = rtrim((string)($_SERVER['HTTP_ORIGIN'] ?? ''), '/');
    if ($origin === '') return;
    $host = (string)($_SERVER['HTTP_HOST'] ?? '');
    if (!preg_match('/^[A-Za-z0-9.-]+(?::[0-9]+)?$/', $host) || !hash_equals("https://$host", $origin)) {
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
    $text = trim(is_scalar($value ?? '') ? (string)($value ?? '') : '');
    if (textLength($text) > $max) throw new ApiError(400, "$name ist zu lang");
    return $text;
}

function emailAddress(mixed $value): string
{
    $email = required($value, 'E-Mail', 320);
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) throw new ApiError(400, 'E-Mail ist ungültig');
    return $email;
}

function passwordResetSettings(): array
{
    $settings = config();
    $url = rtrim((string)($settings['app_url'] ?? ''), '/');
    $from = (string)($settings['mail_from'] ?? '');
    if (!filter_var($url, FILTER_VALIDATE_URL) || !str_starts_with($url, 'https://') || !filter_var($from, FILTER_VALIDATE_EMAIL)) {
        throw new ApiError(503, 'Passwort-Wiederherstellung ist nicht konfiguriert');
    }
    return compact('url', 'from');
}

function sendPasswordReset(array $user, string $token): bool
{
    ['url' => $url, 'from' => $from] = passwordResetSettings();
    $link = "$url/?reset=$token";
    $message = "Hallo {$user['name']},\n\nüber diesen Link können Sie innerhalb von 30 Minuten ein neues Passwort vergeben:\n$link\n\nFalls Sie dies nicht angefordert haben, ignorieren Sie diese Nachricht.";
    return mail($user['email'], 'Passwort zuruecksetzen', $message, "From: $from\r\nContent-Type: text/plain; charset=UTF-8");
}

function finiteNumber(mixed $value, string $name): int|float|null
{
    if ($value === null || $value === '') return null;
    if (!is_numeric($value) || !is_finite((float)$value)) throw new ApiError(400, "$name ist ungültig");
    return (float)$value == (int)$value ? (int)$value : (float)$value;
}

function isoDate(mixed $value): string
{
    try {
        if ($value === null || $value === '') $date = new DateTimeImmutable();
        elseif (is_numeric($value)) $date = (new DateTimeImmutable('@' . (int)$value));
        else $date = new DateTimeImmutable((string)$value);
        return $date->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d\TH:i:s.v\Z');
    } catch (Throwable) {
        throw new ApiError(502, 'DIVERA-Zeitpunkt ist ungültig');
    }
}

function unit(int $id, int $organizationId): ?array
{
    return one('SELECT * FROM units WHERE id=? AND organization_id=?', [$id, $organizationId]);
}

function incident(int $id, int $organizationId): ?array
{
    return one('SELECT * FROM incidents WHERE id=? AND organization_id=?', [$id, $organizationId]);
}

function report(int $id, int $organizationId): ?array
{
    return one('SELECT r.* FROM reports r JOIN incidents i ON i.id=r.incident_id WHERE r.id=? AND i.organization_id=?', [$id, $organizationId]);
}

function currentUser(): ?array
{
    $token = $_COOKIE[SESSION_COOKIE] ?? '';
    if (!preg_match('/^[a-f0-9]{64}$/', $token)) return null;
    $user = one(
        'SELECT u.*,o.name organization_name FROM sessions s
         JOIN users u ON u.id=s.user_id JOIN organizations o ON o.id=u.organization_id
         WHERE s.token=? AND s.expires_at>UTC_TIMESTAMP()',
        [$token]
    );
    if (!$user) return null;
    $user['unitIds'] = array_map('intval', query('SELECT unit_id FROM user_units WHERE user_id=?', [$user['id']])->fetchAll(PDO::FETCH_COLUMN));
    foreach (['id', 'organization_id', 'unit_id'] as $key) if ($user[$key] !== null) $user[$key] = (int)$user[$key];
    return $user;
}

function assertRole(array $user, string ...$roles): void
{
    if (!in_array($user['role'], $roles, true)) throw new ApiError(403, 'Keine Berechtigung');
}

function assertOwnUnit(array $user, int $unitId): void
{
    if ($user['role'] !== 'wehrleitung' && !in_array($unitId, $user['unitIds'], true)) {
        throw new ApiError(403, 'Keine Berechtigung für diese Einheit');
    }
}

function membershipIds(array $data, int $organizationId): array
{
    $source = is_array($data['unitIds'] ?? null) ? $data['unitIds'] : (isset($data['unitId']) ? [$data['unitId']] : []);
    $ids = array_values(array_unique(array_map('intval', $source)));
    if (($data['role'] ?? '') !== 'wehrleitung' && !$ids) throw new ApiError(400, 'Für diese Rolle ist mindestens eine Einheit erforderlich');
    foreach ($ids as $id) if ($id < 1 || !unit($id, $organizationId)) throw new ApiError(404, 'Einheit nicht gefunden');
    return $ids;
}

function replaceMemberships(int $userId, array $unitIds): void
{
    query('DELETE FROM user_units WHERE user_id=?', [$userId]);
    foreach ($unitIds as $unitId) query('INSERT INTO user_units(user_id,unit_id) VALUES(?,?)', [$userId, $unitId]);
}

function vehicleSnapshots(mixed $value): array
{
    if (!is_array($value)) throw new ApiError(400, 'Fahrzeuge sind ungültig');
    return array_map(function ($vehicle) {
        if (is_string($vehicle)) return required($vehicle, 'Fahrzeug', 200);
        if (!is_array($vehicle)) throw new ApiError(400, 'Fahrzeug ist ungültig');
        return [
            'id' => optional($vehicle['id'] ?? '', 'Fahrzeug-ID', 200),
            'name' => required($vehicle['name'] ?? '', 'Fahrzeugname', 200),
            'shortname' => optional($vehicle['shortname'] ?? '', 'Fahrzeugtyp', 100),
            'fullname' => optional($vehicle['fullname'] ?? '', 'Fahrzeugtyp', 200),
            'own' => ($vehicle['own'] ?? true) !== false
        ];
    }, $value);
}

function reportDetails(array $data, array $incident): array
{
    if (!in_array($data['incidentType'] ?? null, INCIDENT_TYPES, true)) throw new ApiError(400, 'Einsatzart ist ungültig');
    try {
        $times = [
            'alarmedAt' => new DateTimeImmutable($incident['started_at']),
            'departedAt' => new DateTimeImmutable(required($data['departedAt'] ?? null, 'Ausgerückt um', 100)),
            'arrivedAt' => new DateTimeImmutable(required($data['arrivedAt'] ?? null, 'Eingetroffen um', 100)),
            'endedAt' => new DateTimeImmutable(required($data['endedAt'] ?? null, 'Einsatz beendet um', 100))
        ];
    } catch (ApiError $error) {
        throw $error;
    } catch (Throwable) {
        throw new ApiError(400, 'Einsatzzeiten müssen vollständig und chronologisch sein');
    }
    if ($times['departedAt'] < $times['alarmedAt'] || $times['arrivedAt'] < $times['departedAt'] || $times['endedAt'] < $times['arrivedAt']) {
        throw new ApiError(400, 'Einsatzzeiten müssen vollständig und chronologisch sein');
    }
    $classification = [];
    $selected = is_array($data['classification'] ?? null) ? $data['classification'] : [];
    foreach (CLASSIFICATIONS as $group => $allowed) {
        $values = isset($selected[$group]) && is_array($selected[$group])
            ? array_values(array_unique(array_map('strval', $selected[$group]))) : [];
        foreach ($values as $value) if (!in_array($value, $allowed, true)) throw new ApiError(400, 'Aufgliederung ist ungültig');
        $classification[$group] = $values;
    }
    $format = fn(DateTimeImmutable $date) => $date->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d\TH:i:s.v\Z');
    return [
        'alarmedAt' => $format($times['alarmedAt']), 'departedAt' => $format($times['departedAt']),
        'arrivedAt' => $format($times['arrivedAt']), 'endedAt' => $format($times['endedAt']),
        'incidentType' => $data['incidentType'],
        'classification' => json_encode($classification, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)
    ];
}

function replaceCrew(int $reportId, int $incidentId, int $unitId, mixed $crew, int $organizationId): array
{
    if (!is_array($crew) || !array_is_list($crew)) throw new ApiError(400, 'Besatzung ist ungültig');
    $assignment = one('SELECT vehicles FROM incident_units WHERE incident_id=? AND unit_id=?', [$incidentId, $unitId]);
    $snapshots = json_decode($assignment['vehicles'] ?? '[]', true) ?: [];
    $vehicles = array_map(fn($vehicle) => is_string($vehicle) ? $vehicle : $vehicle['name'],
        array_values(array_filter($snapshots, fn($vehicle) => is_string($vehicle) || ($vehicle['own'] ?? true) !== false)));
    $seen = $occupied = $rows = [];
    foreach ($crew as $item) {
        if (!is_array($item)) throw new ApiError(400, 'Besatzung ist ungültig');
        $memberId = (int)($item['memberId'] ?? 0);
        $vehicle = trim((string)($item['vehicle'] ?? ''));
        $role = (string)($item['role'] ?? 'besatzung');
        $slot = $vehicle && $role !== 'besatzung' ? "$vehicle:$role" : '';
        $member = one(
            'SELECT m.name FROM members m JOIN member_units mu ON mu.member_id=m.id
             WHERE m.id=? AND m.organization_id=? AND mu.unit_id=?',
            [$memberId, $organizationId, $unitId]
        );
        if (!$memberId || isset($seen[$memberId]) || !$member || ($vehicle && !in_array($vehicle, $vehicles, true))
            || !in_array($role, ['maschinist', 'einheitsfuehrer', 'besatzung'], true)
            || (!$vehicle && $role !== 'besatzung') || ($slot && isset($occupied[$slot]))) {
            throw new ApiError(400, 'Besatzung ist ungültig');
        }
        $seen[$memberId] = true;
        if ($slot) $occupied[$slot] = true;
        $rows[] = compact('memberId', 'vehicle', 'role') + ['name' => $member['name']];
    }
    query('DELETE FROM report_crew WHERE report_id=?', [$reportId]);
    foreach ($rows as $row) query(
        'INSERT INTO report_crew(report_id,member_id,vehicle,role) VALUES(?,?,?,?)',
        [$reportId, $row['memberId'], $row['vehicle'], $row['role']]
    );
    return [
        'vehicles' => implode(', ', array_values(array_unique(array_filter(array_column($rows, 'vehicle'))))),
        'personnel' => implode(', ', array_column($rows, 'name'))
    ];
}

function diveraGet(string $url, string $error): array
{
    $context = stream_context_create(['http' => [
        'method' => 'GET', 'timeout' => 20, 'ignore_errors' => true,
        'header' => "Accept: application/json\r\nUser-Agent: Einsatzberichte-PHP\r\n"
    ]]);
    $raw = @file_get_contents($url, false, $context);
    $status = 0;
    foreach ($http_response_header ?? [] as $header) if (preg_match('/^HTTP\/\S+\s+(\d+)/', $header, $match)) $status = (int)$match[1];
    if ($raw === false || $status < 200 || $status >= 300) throw new ApiError(502, $error);
    try {
        $data = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        return is_array($data) ? $data : [];
    } catch (JsonException) {
        throw new ApiError(502, $error);
    }
}

function listValue(mixed $value): array
{
    return is_array($value) ? array_values($value) : [];
}

function diveraData(array $unit): array
{
    $key = rawurlencode($unit['divera_access_key']);
    $alarmsRaw = diveraGet("https://app.divera247.com/api/v2/alarms?accesskey=$key", 'DIVERA-Abfrage fehlgeschlagen');
    $unitRaw = diveraGet("https://app.divera247.com/api/v2/pull/all?accesskey=$key", 'DIVERA-Abfrage fehlgeschlagen');
    $ownVehicles = [];
    foreach (($unitRaw['data']['cluster']['vehicle'] ?? []) as $id => $vehicle) {
        $ownVehicles[(string)($vehicle['id'] ?? $id)] = $vehicle;
    }
    $vehicles = [];
    foreach ($ownVehicles as $id => $vehicle) $vehicles[] = [
        'id' => $id, 'name' => $vehicle['name'] ?? $vehicle['shortname'] ?? $id,
        'shortname' => (string)($vehicle['shortname'] ?? ''), 'fullname' => (string)($vehicle['fullname'] ?? ''), 'own' => true
    ];
    $source = $alarmsRaw['data']['items'] ?? $alarmsRaw['data'] ?? $alarmsRaw['items'] ?? $alarmsRaw;
    $alarms = [];
    foreach (listValue($source) as $alarm) {
        $assigned = $alarm['vehicles'] ?? $alarm['vehicle_ids'] ?? $alarm['vehicle'] ?? [];
        $ids = is_array($assigned) ? (array_is_list($assigned) ? $assigned : array_keys($assigned)) : explode(',', (string)$assigned);
        $alarmVehicles = [];
        foreach ($ids as $id) {
            $id = trim((string)$id);
            if (!$id) continue;
            $vehicle = $ownVehicles[$id] ?? null;
            $alarmVehicles[] = [
                'id' => $id, 'name' => $vehicle['name'] ?? $vehicle['shortname'] ?? $id,
                'shortname' => (string)($vehicle['shortname'] ?? ''), 'fullname' => (string)($vehicle['fullname'] ?? ''),
                'own' => (bool)$vehicle
            ];
        }
        $alarms[] = [
            'id' => (string)($alarm['id'] ?? $alarm['cluster_id'] ?? $alarm['number'] ?? ''),
            'foreignId' => (string)($alarm['foreign_id'] ?? ''), 'date' => finiteNumber($alarm['date'] ?? null, 'Alarmierungszeit'),
            'title' => $alarm['title'] ?? $alarm['text'] ?? $alarm['type'] ?? 'Einsatz',
            'startedAt' => isoDate($alarm['date'] ?? $alarm['ts_create'] ?? $alarm['created_at'] ?? null),
            'text' => (string)($alarm['text'] ?? ''), 'address' => $alarm['address'] ?? $alarm['location'] ?? '',
            'lat' => finiteNumber($alarm['lat'] ?? null, 'Breitengrad'), 'lng' => finiteNumber($alarm['lng'] ?? $alarm['long'] ?? null, 'Längengrad'),
            'remark' => (string)($alarm['remark'] ?? ''), 'patient' => (string)($alarm['patient'] ?? ''),
            'caller' => (string)($alarm['caller'] ?? ''), 'vehicles' => $alarmVehicles
        ];
    }
    return compact('alarms', 'vehicles');
}

try {
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    assertRequestOrigin($method);
    $path = parse_url($_SERVER['REQUEST_URI'] ?? '/api', PHP_URL_PATH);
    $path = rawurldecode(is_string($path) ? $path : '/api');
    $public = in_array($path, ['/api/bootstrap', '/api/setup', '/api/login', '/api/password-reset/request', '/api/password-reset/confirm'], true);
    $user = $public ? null : currentUser();
    if (!$public && !$user) respond(401, ['error' => 'Bitte anmelden']);

    if ($method === 'GET' && $path === '/api/bootstrap') {
        respond(200, ['needsSetup' => !one('SELECT id FROM users LIMIT 1')]);
    }

    if ($method === 'POST' && $path === '/api/setup') {
        if (one('SELECT id FROM users LIMIT 1')) throw new ApiError(409, 'Einrichtung abgeschlossen');
        $data = input();
        $setupToken = (string)(config()['setup_token'] ?? '');
        if (strlen($setupToken) < 32) throw new ApiError(503, 'SETUP_TOKEN ist nicht sicher konfiguriert');
        if (!hash_equals($setupToken, (string)($data['setupToken'] ?? ''))) throw new ApiError(403, 'Einrichtungstoken ist ungültig');
        $password = required($data['password'] ?? null, 'Passwort', 200);
        if (textLength($password) < 10) throw new ApiError(400, 'Passwort muss mindestens 10 Zeichen haben');
        transaction(function () use ($data, $password) {
            query('INSERT INTO organizations(name) VALUES(?)', [required($data['organization'] ?? null, 'Wehr', 200)]);
            $org = (int)db()->lastInsertId();
            query('INSERT INTO units(organization_id,name) VALUES(?,?)', [$org, required($data['unit'] ?? null, 'Einheit', 200)]);
            $unitId = (int)db()->lastInsertId();
            query(
                "INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) VALUES(?,?,?,?,?,'wehrleitung')",
                [$org, $unitId, required($data['name'] ?? null, 'Name', 200),
                 required($data['email'] ?? null, 'E-Mail', 320), password_hash($password, PASSWORD_DEFAULT)]
            );
            replaceMemberships((int)db()->lastInsertId(), [$unitId]);
        });
        respond(201, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/login') {
        $data = input();
        $login = one('SELECT * FROM users WHERE email=?', [required($data['email'] ?? null, 'E-Mail', 320)]);
        if (!$login || !password_verify((string)($data['password'] ?? ''), $login['password_hash'])) {
            throw new ApiError(401, 'E-Mail oder Passwort falsch');
        }
        $token = bin2hex(random_bytes(32));
        transaction(function () use ($token, $login) {
            query('DELETE FROM sessions WHERE expires_at<=UTC_TIMESTAMP()');
            if (preg_match('/^[a-f0-9]{64}$/', $_COOKIE[SESSION_COOKIE] ?? '')) query('DELETE FROM sessions WHERE token=?', [$_COOKIE[SESSION_COOKIE]]);
            query('INSERT INTO sessions(token,user_id,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 12 HOUR)', [$token, $login['id']]);
        });
        setcookie(SESSION_COOKIE, $token, [
            'expires' => time() + 43200, 'path' => '/', 'secure' => true,
            'httponly' => true, 'samesite' => 'Strict'
        ]);
        respond(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/password-reset/request') {
        $data = input();
        $email = emailAddress($data['email'] ?? null);
        passwordResetSettings();
        $user = one('SELECT id,name,email FROM users WHERE email=?', [$email]);
        if ($user) {
            $recent = one('SELECT id FROM password_resets WHERE user_id=? AND requested_at>UTC_TIMESTAMP()-INTERVAL 5 MINUTE', [$user['id']]);
            if (!$recent) {
                $token = bin2hex(random_bytes(32));
                transaction(function () use ($user, $token) {
                    query('DELETE FROM password_resets WHERE expires_at<=UTC_TIMESTAMP() OR user_id=?', [$user['id']]);
                    query('INSERT INTO password_resets(user_id,token_hash,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 30 MINUTE)', [$user['id'], hash('sha256', $token)]);
                });
                if (!sendPasswordReset($user, $token)) {
                    query('DELETE FROM password_resets WHERE user_id=?', [$user['id']]);
                    error_log('Passwort-Wiederherstellungs-E-Mail konnte nicht versendet werden');
                }
            }
        }
        respond(202, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/password-reset/confirm') {
        $data = input();
        $token = (string)($data['token'] ?? '');
        if (!preg_match('/^[a-f0-9]{64}$/', $token)) throw new ApiError(400, 'Wiederherstellungslink ist ungültig oder abgelaufen');
        $password = required($data['password'] ?? null, 'Passwort', 200);
        if (textLength($password) < 10) throw new ApiError(400, 'Passwort muss mindestens 10 Zeichen haben');
        transaction(function () use ($token, $password) {
            $reset = one('SELECT user_id FROM password_resets WHERE token_hash=? AND expires_at>UTC_TIMESTAMP() FOR UPDATE', [hash('sha256', $token)]);
            if (!$reset) throw new ApiError(400, 'Wiederherstellungslink ist ungültig oder abgelaufen');
            query('UPDATE users SET password_hash=? WHERE id=?', [password_hash($password, PASSWORD_DEFAULT), $reset['user_id']]);
            query('DELETE FROM sessions WHERE user_id=?', [$reset['user_id']]);
            query('DELETE FROM password_resets WHERE user_id=?', [$reset['user_id']]);
        });
        respond(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/logout') {
        if (isset($_COOKIE[SESSION_COOKIE])) query('DELETE FROM sessions WHERE token=?', [$_COOKIE[SESSION_COOKIE]]);
        setcookie(SESSION_COOKIE, '', [
            'expires' => 1, 'path' => '/', 'secure' => true,
            'httponly' => true, 'samesite' => 'Strict'
        ]);
        respond(200, ['ok' => true]);
    }

    if ($method === 'GET' && $path === '/api/me') {
        respond(200, [
            'id' => $user['id'], 'organization_id' => $user['organization_id'],
            'organization_name' => $user['organization_name'], 'name' => $user['name'],
            'email' => $user['email'], 'role' => $user['role'], 'unitIds' => $user['unitIds']
        ]);
    }

    if ($method === 'GET' && $path === '/api/units') {
        $rows = query(
            'SELECT id,name,(divera_access_key IS NOT NULL) divera_configured FROM units WHERE organization_id=? ORDER BY name',
            [$user['organization_id']]
        )->fetchAll();
        foreach ($rows as &$row) { $row['id'] = (int)$row['id']; $row['divera_configured'] = (int)$row['divera_configured']; }
        respond(200, $rows);
    }

    if ($method === 'POST' && $path === '/api/units') {
        assertRole($user, 'wehrleitung');
        $data = input();
        query('INSERT INTO units(organization_id,name) VALUES(?,?)', [$user['organization_id'], required($data['name'] ?? null, 'Name', 200)]);
        respond(201, ['id' => (int)db()->lastInsertId()]);
    }

    if ($method === 'GET' && preg_match('#^/api/units/(\d+)/members$#', $path, $match)) {
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        if (!unit($unitId, $user['organization_id'])) throw new ApiError(404, 'Einheit nicht gefunden');
        $rows = query(
            "SELECT m.id,m.name,m.divera_id,COALESCE(GROUP_CONCAT(DISTINCT q.name ORDER BY q.name SEPARATOR ', '),'') qualifications
             FROM members m JOIN member_units mu ON mu.member_id=m.id
             LEFT JOIN member_qualifications mq ON mq.member_id=m.id
             LEFT JOIN qualifications q ON q.id=mq.qualification_id AND q.unit_id=mu.unit_id
             WHERE mu.unit_id=? AND m.organization_id=? GROUP BY m.id,m.name,m.divera_id ORDER BY m.name",
            [$unitId, $user['organization_id']]
        )->fetchAll();
        foreach ($rows as &$row) $row['id'] = (int)$row['id'];
        respond(200, $rows);
    }

    if ($method === 'GET' && $path === '/api/users') {
        assertRole($user, 'wehrleitung');
        $rows = query(
            "SELECT u.id,u.name,u.email,u.role,
             COALESCE((SELECT JSON_ARRAYAGG(uu.unit_id) FROM user_units uu WHERE uu.user_id=u.id),JSON_ARRAY()) unit_ids,
             COALESCE((SELECT GROUP_CONCAT(un.name ORDER BY un.name SEPARATOR ', ') FROM user_units uu JOIN units un ON un.id=uu.unit_id WHERE uu.user_id=u.id),'') unit_names
             FROM users u WHERE u.organization_id=? ORDER BY u.name",
            [$user['organization_id']]
        )->fetchAll();
        foreach ($rows as &$row) $row['id'] = (int)$row['id'];
        respond(200, $rows);
    }

    if ($method === 'POST' && $path === '/api/users') {
        assertRole($user, 'wehrleitung');
        $data = input();
        if (!in_array($data['role'] ?? null, ROLES, true)) throw new ApiError(400, 'Rolle ist ungültig');
        $password = required($data['password'] ?? null, 'Passwort', 200);
        if (textLength($password) < 10) throw new ApiError(400, 'Passwort muss mindestens 10 Zeichen haben');
        $unitIds = membershipIds($data, $user['organization_id']);
        $id = transaction(function () use ($data, $password, $unitIds, $user) {
            query(
                'INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) VALUES(?,?,?,?,?,?)',
                [$user['organization_id'], $unitIds[0] ?? null, required($data['name'] ?? null, 'Name', 200),
                 required($data['email'] ?? null, 'E-Mail', 320), password_hash($password, PASSWORD_DEFAULT), $data['role']]
            );
            $id = (int)db()->lastInsertId();
            replaceMemberships($id, $unitIds);
            return $id;
        });
        respond(201, ['id' => $id]);
    }

    if ($method === 'PUT' && preg_match('#^/api/users/(\d+)$#', $path, $match)) {
        assertRole($user, 'wehrleitung');
        $existing = one('SELECT * FROM users WHERE id=? AND organization_id=?', [(int)$match[1], $user['organization_id']]);
        if (!$existing) throw new ApiError(404, 'Benutzer nicht gefunden');
        $data = input();
        if (!in_array($data['role'] ?? null, ROLES, true)) throw new ApiError(400, 'Rolle ist ungültig');
        $unitIds = membershipIds($data, $user['organization_id']);
        $password = (string)($data['password'] ?? '');
        if ($password && textLength($password) < 10) throw new ApiError(400, 'Passwort muss mindestens 10 Zeichen haben');
        transaction(function () use ($data, $password, $unitIds, $existing) {
            query(
                'UPDATE users SET unit_id=?,name=?,email=?,role=?,password_hash=? WHERE id=?',
                [$unitIds[0] ?? null, required($data['name'] ?? null, 'Name', 200),
                 required($data['email'] ?? null, 'E-Mail', 320), $data['role'],
                 $password ? password_hash($password, PASSWORD_DEFAULT) : $existing['password_hash'], $existing['id']]
            );
            replaceMemberships((int)$existing['id'], $unitIds);
            if ($password) query('DELETE FROM sessions WHERE user_id=?', [$existing['id']]);
        });
        respond(200, ['ok' => true]);
    }

    if ($method === 'GET' && $path === '/api/incidents') {
        $where = $user['role'] === 'wehrleitung'
            ? 'i.organization_id=?'
            : 'i.organization_id=? AND EXISTS(SELECT 1 FROM incident_units x JOIN user_units uu ON uu.unit_id=x.unit_id WHERE x.incident_id=i.id AND uu.user_id=?)';
        $params = $user['role'] === 'wehrleitung' ? [$user['organization_id']] : [$user['organization_id'], $user['id']];
        $rows = query(
            "SELECT i.*,
             (SELECT GROUP_CONCAT(u.name ORDER BY u.name SEPARATOR ', ') FROM incident_units x JOIN units u ON u.id=x.unit_id WHERE x.incident_id=i.id) units
             FROM incidents i WHERE $where ORDER BY i.started_at DESC",
            $params
        )->fetchAll();
        foreach ($rows as &$row) {
            $assignments = query(
                'SELECT iu.unit_id unitId,iu.vehicles,EXISTS(SELECT 1 FROM reports r WHERE r.incident_id=iu.incident_id AND r.unit_id=iu.unit_id) hasReport FROM incident_units iu WHERE iu.incident_id=? ORDER BY iu.unit_id',
                [$row['id']]
            )->fetchAll();
            foreach ($assignments as &$assignment) { $assignment['unitId'] = (int)$assignment['unitId']; $assignment['hasReport'] = (int)$assignment['hasReport']; }
            $row['assignments'] = json_encode($assignments, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
            foreach (['id', 'organization_id', 'divera_date'] as $key) if ($row[$key] !== null) $row[$key] = (int)$row[$key];
            foreach (['lat', 'lng'] as $key) if ($row[$key] !== null) $row[$key] = (float)$row[$key];
        }
        respond(200, $rows);
    }

    if ($method === 'POST' && $path === '/api/incidents') {
        $data = input();
        $source = is_array($data['unitIds'] ?? null) ? $data['unitIds'] : [];
        $unitIds = array_values(array_unique(array_map('intval', $source)));
        if (!$unitIds) throw new ApiError(400, 'Mindestens eine gültige Einheit ist erforderlich');
        foreach ($unitIds as $unitId) {
            if (!$unitId || !unit($unitId, $user['organization_id'])) throw new ApiError(400, 'Mindestens eine gültige Einheit ist erforderlich');
            assertOwnUnit($user, $unitId);
        }
        $id = transaction(function () use ($data, $unitIds, $user) {
            query(
                'INSERT INTO incidents(organization_id,title,started_at,address,message,remark,patient,caller,consolidated_text) VALUES(?,?,?,?,?,?,?,?,?)',
                [$user['organization_id'], required($data['title'] ?? null, 'Stichwort', 300),
                 required($data['startedAt'] ?? null, 'Zeitpunkt', 50), trim((string)($data['address'] ?? '')), '', '', '', '', '']
            );
            $id = (int)db()->lastInsertId();
            foreach ($unitIds as $unitId) query('INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(?,?,?)', [$id, $unitId, '[]']);
            return $id;
        });
        respond(201, ['id' => $id]);
    }

    if ($method === 'GET' && preg_match('#^/api/incidents/(\d+)/reports$#', $path, $match)) {
        $incident = incident((int)$match[1], $user['organization_id']);
        if (!$incident) throw new ApiError(404, 'Einsatz nicht gefunden');
        $where = '';
        $params = [(int)$match[1]];
        if ($user['role'] === 'einheitsleitung') {
            $where = ' AND EXISTS(SELECT 1 FROM user_units uu WHERE uu.user_id=? AND uu.unit_id=r.unit_id)';
            $params[] = $user['id'];
        } elseif ($user['role'] !== 'wehrleitung') {
            $where = ' AND r.author_id=?';
            $params[] = $user['id'];
        }
        $rows = query(
            "SELECT r.*,u.name author_name,un.name unit_name FROM reports r
             JOIN users u ON u.id=r.author_id JOIN units un ON un.id=r.unit_id
             WHERE r.incident_id=?$where ORDER BY r.created_at",
            $params
        )->fetchAll();
        foreach ($rows as &$row) {
            $crew = query(
                'SELECT rc.member_id memberId,m.name,rc.vehicle,rc.role FROM report_crew rc JOIN members m ON m.id=rc.member_id WHERE rc.report_id=? ORDER BY rc.member_id',
                [$row['id']]
            )->fetchAll();
            foreach ($crew as &$person) $person['memberId'] = (int)$person['memberId'];
            $row['crew'] = json_encode($crew, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
            $row['duration_minutes'] = (int)round((strtotime($row['ended_at']) - strtotime($row['alarmed_at'])) / 60);
            foreach (['id', 'incident_id', 'unit_id', 'author_id'] as $key) $row[$key] = (int)$row[$key];
        }
        respond(200, $rows);
    }

    if ($method === 'POST' && preg_match('#^/api/incidents/(\d+)/reports$#', $path, $match)) {
        $incidentId = (int)$match[1];
        $foundIncident = incident($incidentId, $user['organization_id']);
        if (!$foundIncident) throw new ApiError(404, 'Einsatz nicht gefunden');
        $data = input();
        $unitId = (int)($data['unitId'] ?? 0);
        assertOwnUnit($user, $unitId);
        if (!one('SELECT incident_id FROM incident_units WHERE incident_id=? AND unit_id=?', [$incidentId, $unitId])) throw new ApiError(400, 'Einheit wurde nicht alarmiert');
        if (one('SELECT id FROM reports WHERE incident_id=? AND unit_id=?', [$incidentId, $unitId])) throw new ApiError(409, 'Für diese Einheit existiert bereits ein Einsatzbericht');
        $id = transaction(function () use ($data, $foundIncident, $incidentId, $unitId, $user) {
            $details = reportDetails($data, $foundIncident);
            query(
                'INSERT INTO reports(incident_id,unit_id,author_id,narrative,alarmed_at,departed_at,arrived_at,ended_at,incident_type,classification,vehicles,personnel)
                 VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
                [$incidentId, $unitId, $user['id'], required($data['narrative'] ?? null, 'Bericht'),
                 $details['alarmedAt'], $details['departedAt'], $details['arrivedAt'], $details['endedAt'],
                 $details['incidentType'], $details['classification'], '', '']
            );
            $id = (int)db()->lastInsertId();
            $summary = replaceCrew($id, $incidentId, $unitId, $data['crew'] ?? [], $user['organization_id']);
            query('UPDATE reports SET vehicles=?,personnel=? WHERE id=?', [$summary['vehicles'], $summary['personnel'], $id]);
            return $id;
        });
        respond(201, ['id' => $id]);
    }

    if ($method === 'PUT' && preg_match('#^/api/reports/(\d+)$#', $path, $match)) {
        $foundReport = report((int)$match[1], $user['organization_id']);
        if (!$foundReport) throw new ApiError(404, 'Bericht nicht gefunden');
        $mayEdit = $foundReport['status'] === 'draft' &&
            ((int)$foundReport['author_id'] === $user['id'] || ($user['role'] === 'einheitsleitung' && in_array((int)$foundReport['unit_id'], $user['unitIds'], true)));
        if (!$mayEdit) throw new ApiError(403, 'Der Bericht kann nicht bearbeitet werden');
        $data = input();
        transaction(function () use ($data, $foundReport, $user) {
            $lockedReport = one('SELECT * FROM reports WHERE id=? FOR UPDATE', [$foundReport['id']]);
            if (!$lockedReport || $lockedReport['status'] !== 'draft') {
                throw new ApiError(409, 'Der Bericht wurde bereits freigegeben');
            }
            $foundIncident = incident((int)$lockedReport['incident_id'], $user['organization_id']);
            $details = reportDetails($data, $foundIncident);
            $summary = replaceCrew((int)$lockedReport['id'], (int)$lockedReport['incident_id'], (int)$lockedReport['unit_id'], $data['crew'] ?? [], $user['organization_id']);
            query(
                'UPDATE reports SET narrative=?,vehicles=?,personnel=?,alarmed_at=?,departed_at=?,arrived_at=?,ended_at=?,incident_type=?,classification=? WHERE id=?',
                [required($data['narrative'] ?? null, 'Bericht'), $summary['vehicles'], $summary['personnel'],
                 $details['alarmedAt'], $details['departedAt'], $details['arrivedAt'], $details['endedAt'],
                 $details['incidentType'], $details['classification'], $lockedReport['id']]
            );
        });
        respond(200, ['ok' => true]);
    }

    if ($method === 'POST' && preg_match('#^/api/reports/(\d+)/release$#', $path, $match)) {
        assertRole($user, 'einheitsleitung', 'wehrleitung');
        $foundReport = report((int)$match[1], $user['organization_id']);
        if (!$foundReport) throw new ApiError(404, 'Bericht nicht gefunden');
        assertOwnUnit($user, (int)$foundReport['unit_id']);
        query("UPDATE reports SET status='released',released_at=UTC_TIMESTAMP() WHERE id=?", [$foundReport['id']]);
        respond(200, ['ok' => true]);
    }

    if ($method === 'PUT' && preg_match('#^/api/incidents/(\d+)/consolidation$#', $path, $match)) {
        assertRole($user, 'wehrleitung');
        if (!incident((int)$match[1], $user['organization_id'])) throw new ApiError(404, 'Einsatz nicht gefunden');
        $data = input();
        query('UPDATE incidents SET consolidated_text=?,consolidated_at=UTC_TIMESTAMP() WHERE id=?', [required($data['text'] ?? null, 'Gesamtbericht'), (int)$match[1]]);
        respond(200, ['ok' => true]);
    }

    if ($method === 'PUT' && preg_match('#^/api/units/(\d+)/divera$#', $path, $match)) {
        assertRole($user, 'wehrleitung', 'einheitsleitung');
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        if (!unit($unitId, $user['organization_id'])) throw new ApiError(404, 'Einheit nicht gefunden');
        $data = input();
        query('UPDATE units SET divera_access_key=? WHERE id=?', [required($data['accessKey'] ?? null, 'Access-Key', 500), $unitId]);
        respond(200, ['ok' => true]);
    }

    if ($method === 'GET' && preg_match('#^/api/units/(\d+)/divera$#', $path, $match)) {
        assertRole($user, 'wehrleitung', 'einheitsleitung');
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        $foundUnit = unit($unitId, $user['organization_id']);
        if (!$foundUnit || !$foundUnit['divera_access_key']) throw new ApiError(400, 'DIVERA ist nicht konfiguriert');
        respond(200, diveraData($foundUnit));
    }

    if ($method === 'POST' && preg_match('#^/api/units/(\d+)/divera/members/sync$#', $path, $match)) {
        assertRole($user, 'wehrleitung', 'einheitsleitung');
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        $foundUnit = unit($unitId, $user['organization_id']);
        if (!$foundUnit || !$foundUnit['divera_access_key']) throw new ApiError(400, 'DIVERA ist nicht konfiguriert');
        $raw = diveraGet('https://app.divera247.com/api/v2/pull/all?accesskey=' . rawurlencode($foundUnit['divera_access_key']), 'DIVERA-Mitgliederabgleich fehlgeschlagen');
        $cluster = $raw['data']['cluster'] ?? [];
        $count = transaction(function () use ($cluster, $unitId, $user) {
            $qualifications = [];
            foreach (($cluster['qualification'] ?? []) as $externalId => $qualification) {
                $diveraId = (string)($qualification['id'] ?? $externalId);
                query(
                    'INSERT INTO qualifications(unit_id,divera_id,name,shortname) VALUES(?,?,?,?)
                     ON DUPLICATE KEY UPDATE name=VALUES(name),shortname=VALUES(shortname),id=LAST_INSERT_ID(id)',
                    [$unitId, $diveraId, required($qualification['name'] ?? null, 'Qualifikation', 200),
                     optional($qualification['shortname'] ?? '', 'Qualifikationskürzel', 100)]
                );
                $qualifications[$diveraId] = (int)db()->lastInsertId();
            }
            $count = 0;
            foreach (($cluster['consumer'] ?? []) as $externalId => $consumer) {
                $diveraId = trim((string)($consumer['id'] ?? $externalId));
                $name = trim((string)($consumer['stdformat_name'] ?? trim(($consumer['firstname'] ?? '') . ' ' . ($consumer['lastname'] ?? ''))));
                if (!$diveraId || !$name) continue;
                query(
                    'INSERT INTO members(organization_id,divera_id,name) VALUES(?,?,?)
                     ON DUPLICATE KEY UPDATE name=VALUES(name),id=LAST_INSERT_ID(id)',
                    [$user['organization_id'], $diveraId, $name]
                );
                $memberId = (int)db()->lastInsertId();
                query('INSERT IGNORE INTO member_units(member_id,unit_id) VALUES(?,?)', [$memberId, $unitId]);
                query(
                    'DELETE mq FROM member_qualifications mq JOIN qualifications q ON q.id=mq.qualification_id WHERE mq.member_id=? AND q.unit_id=?',
                    [$memberId, $unitId]
                );
                foreach (($consumer['qualifications'] ?? []) as $qualificationId) {
                    if (isset($qualifications[(string)$qualificationId])) query(
                        'INSERT IGNORE INTO member_qualifications(member_id,qualification_id) VALUES(?,?)',
                        [$memberId, $qualifications[(string)$qualificationId]]
                    );
                }
                $count++;
            }
            return $count;
        });
        respond(200, ['count' => $count]);
    }

    if ($method === 'POST' && preg_match('#^/api/units/(\d+)/divera/import$#', $path, $match)) {
        assertRole($user, 'wehrleitung', 'einheitsleitung');
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        $foundUnit = unit($unitId, $user['organization_id']);
        if (!$foundUnit) throw new ApiError(404, 'Einheit nicht gefunden');
        if (!$foundUnit['divera_access_key']) throw new ApiError(400, 'DIVERA ist nicht konfiguriert');
        $requestedId = required(input()['id'] ?? null, 'DIVERA-ID', 200);
        $verified = null;
        foreach (diveraData($foundUnit)['alarms'] as $alarm) {
            if ($alarm['id'] === $requestedId) { $verified = $alarm; break; }
        }
        if (!$verified) throw new ApiError(404, 'DIVERA-Einsatz nicht gefunden');
        $id = transaction(function () use ($verified, $unitId, $user) {
            query(
                'INSERT INTO incidents(organization_id,divera_id,foreign_id,divera_date,title,started_at,message,address,lat,lng,remark,patient,caller,consolidated_text)
                 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                 ON DUPLICATE KEY UPDATE foreign_id=VALUES(foreign_id),divera_date=VALUES(divera_date),title=VALUES(title),
                 started_at=VALUES(started_at),message=VALUES(message),address=VALUES(address),lat=VALUES(lat),lng=VALUES(lng),
                 remark=VALUES(remark),patient=VALUES(patient),caller=VALUES(caller),id=LAST_INSERT_ID(id)',
                [$user['organization_id'], required($verified['id'], 'DIVERA-ID', 200),
                 optional($verified['foreignId'], 'Einsatznummer', 200), finiteNumber($verified['date'], 'Alarmierungszeit'),
                 required($verified['title'], 'Stichwort', 300), required($verified['startedAt'], 'Zeitpunkt', 100),
                 optional($verified['text'], 'Meldung'), optional($verified['address'], 'Adresse', 500),
                 finiteNumber($verified['lat'], 'Breitengrad'), finiteNumber($verified['lng'], 'Längengrad'),
                 optional($verified['remark'], 'Bemerkung'), optional($verified['patient'], 'Patient'),
                 optional($verified['caller'], 'Meldende Person'), '']
            );
            $incidentId = (int)db()->lastInsertId();
            query(
                'INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(?,?,?)
                 ON DUPLICATE KEY UPDATE vehicles=VALUES(vehicles)',
                [$incidentId, $unitId, json_encode(vehicleSnapshots($verified['vehicles']), JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)]
            );
            return $incidentId;
        });
        respond(201, ['id' => $id]);
    }

    respond(404, ['error' => 'Nicht gefunden']);
} catch (ApiError $error) {
    respond($error->status, ['error' => $error->getMessage()]);
} catch (PDOException $error) {
    error_log((string)$error);
    respond($error->getCode() === '23000' ? 409 : 500, ['error' => $error->getCode() === '23000' ? 'Datensatz existiert bereits' : 'Interner Fehler']);
} catch (Throwable $error) {
    error_log((string)$error);
    respond(500, ['error' => 'Interner Fehler']);
}
