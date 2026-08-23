<?php
declare(strict_types=1);

require __DIR__ . '/support.php';
require __DIR__ . '/constants.php';

function databaseConfigurationError(): ?string
{
    if (empty(config()['dsn'])) return 'Datenbankzugang ist nicht konfiguriert. Prüfen Sie DB_DSN oder config.local.php.';
    try {
        $tables = db()->query(
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name IN
             ('organizations','units','users','user_units','sessions','login_history','password_resets','incidents','incident_units',
              'divera_imports','members','member_units','qualifications','member_qualifications','reports','report_crew')"
        )->fetchColumn();
        if ((int)$tables !== 16) return 'Datenbankschema ist unvollständig. Importieren Sie schema.sql und alle ausstehenden Migrationen.';
        $reportColumns = db()->query(
            "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='reports'
             AND column_name IN ('report_year','running_number','damaged_party','damaging_party','incident_command')"
        )->fetchColumn();
        if ((int)$reportColumns !== 5) return 'Datenbankschema ist unvollständig. Importieren Sie schema.sql und alle ausstehenden Migrationen.';
    } catch (PDOException $error) {
        error_log((string)$error);
        return 'Datenbankverbindung fehlgeschlagen. Prüfen Sie DSN, Benutzername, Passwort und Erreichbarkeit.';
    }
    return null;
}

function sendPasswordEmail(array $user, string $token, bool $invitation = false): bool
{
    $settings = mailSettings();
    ['url' => $url, 'from' => $from] = $settings;
    $link = "$url/?" . ($invitation ? 'invite' : 'reset') . "=$token";
    $subject = $invitation ? 'Konto aktivieren' : 'Passwort zuruecksetzen';
    $message = $invitation
        ? "Hallo {$user['name']},\n\nüber diesen Link können Sie innerhalb von 30 Minuten Ihr Konto aktivieren und ein Passwort vergeben:\n$link\n\nNach Ablauf können Sie über „Passwort vergessen“ einen neuen Link anfordern."
        : "Hallo {$user['name']},\n\nüber diesen Link können Sie innerhalb von 30 Minuten ein neues Passwort vergeben:\n$link\n\nFalls Sie dies nicht angefordert haben, ignorieren Sie diese Nachricht.";
    return $settings['smtpHost'] !== ''
        ? smtpSend($settings, $user['email'], $subject, $message)
        // mail() failures are returned as 503 instead of leaking a PHP warning into the JSON response.
        : @mail($user['email'], $subject, $message, "From: $from\r\nContent-Type: text/plain; charset=UTF-8");
}

function isoDate(mixed $value): string
{
    if ($value === null || $value === '') throw new ApiError(502, 'DIVERA-Zeitpunkt fehlt');
    try {
        if (is_numeric($value)) $date = new DateTimeImmutable('@' . (int)$value);
        else $date = new DateTimeImmutable((string)$value);
        return $date->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d\TH:i:s.v\Z');
    } catch (Throwable) {
        throw new ApiError(502, 'DIVERA-Zeitpunkt ist ungültig');
    }
}

function requestDate(mixed $value, string $name): DateTimeImmutable
{
    $text = required($value, $name, 100);
    $date = DateTimeImmutable::createFromFormat('!Y-m-d\TH:i:s.v\Z', $text, new DateTimeZone('UTC'));
    $errors = DateTimeImmutable::getLastErrors();
    if (!$date || ($errors && ($errors['warning_count'] || $errors['error_count']))) throw new ApiError(400, "$name ist ungültig");
    return $date;
}

function utcString(DateTimeImmutable $date): string
{
    return $date->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d\TH:i:s.v\Z');
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
    $token = $_COOKIE[sessionCookieName()] ?? '';
    if (!preg_match('/^[a-f0-9]{64}$/', $token)) return null;
    $user = one(
        'SELECT u.*,o.name organization_name FROM sessions s
         JOIN users u ON u.id=s.user_id JOIN organizations o ON o.id=u.organization_id
         WHERE s.token=? AND s.expires_at>UTC_TIMESTAMP()',
        [hash('sha256', $token)]
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
    // Wehrleitung is organization-wide; unit lookups still enforce tenant ownership.
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
    // Preserve labels and ownership as they were when the incident was imported.
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
    $times = [
        'alarmedAt' => requestDate($incident['started_at'], 'Alarmiert um'),
        'departedAt' => requestDate($data['departedAt'] ?? null, 'Ausgerückt um'),
        'arrivedAt' => requestDate($data['arrivedAt'] ?? null, 'Eingetroffen um'),
        'endedAt' => requestDate($data['endedAt'] ?? null, 'Einsatz beendet um')
    ];
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
    $structured = [];
    foreach ([
        'damagedParty' => ['name' => 'Name der geschädigten Person', 'phone' => 'Telefon der geschädigten Person', 'address' => 'Adresse der geschädigten Person'],
        'damagingParty' => ['name' => 'Name des Schädigers', 'phone' => 'Telefon des Schädigers', 'address' => 'Adresse des Schädigers'],
        'incidentCommand' => ['rank' => 'Dienstgrad der Einsatzleitung', 'name' => 'Name der Einsatzleitung', 'additionalRank' => 'Weiterer Dienstgrad', 'additionalName' => 'Weitere Führungskraft']
    ] as $group => $fields) {
        $source = is_array($data[$group] ?? null) ? $data[$group] : [];
        foreach ($fields as $field => $label) $structured[$group][$field] = optional($source[$field] ?? null, $label, $field === 'address' ? 500 : 200);
    }
    return [
        'alarmedAt' => utcString($times['alarmedAt']), 'departedAt' => utcString($times['departedAt']),
        'arrivedAt' => utcString($times['arrivedAt']), 'endedAt' => utcString($times['endedAt']),
        'reportYear' => (int)$times['alarmedAt']->setTimezone(new DateTimeZone('Europe/Berlin'))->format('Y'),
        'runningNumber' => required($data['runningNumber'] ?? null, 'Laufende Nummer', 50),
        'damagedParty' => json_encode($structured['damagedParty'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
        'damagingParty' => json_encode($structured['damagingParty'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
        'incidentCommand' => json_encode($structured['incidentCommand'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
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
    $members = [];
    foreach (query(
        'SELECT m.id,m.name FROM members m JOIN member_units mu ON mu.member_id=m.id
         WHERE m.organization_id=? AND mu.unit_id=?',
        [$organizationId, $unitId]
    )->fetchAll() as $member) $members[(int)$member['id']] = $member['name'];
    $seen = $occupied = $rows = [];
    foreach ($crew as $item) {
        if (!is_array($item)) throw new ApiError(400, 'Besatzung ist ungültig');
        $memberId = (int)($item['memberId'] ?? 0);
        $vehicle = trim((string)($item['vehicle'] ?? ''));
        $role = (string)($item['role'] ?? 'besatzung');
        // Driver and unit leader are unique per vehicle; crew members are not.
        $slot = $vehicle && $role !== 'besatzung' ? "$vehicle:$role" : '';
        if (!$memberId || isset($seen[$memberId]) || !isset($members[$memberId]) || ($vehicle && !in_array($vehicle, $vehicles, true))
            || !in_array($role, ['maschinist', 'einheitsfuehrer', 'besatzung'], true)
            || (!$vehicle && $role !== 'besatzung') || ($slot && isset($occupied[$slot]))) {
            throw new ApiError(400, 'Besatzung ist ungültig');
        }
        $seen[$memberId] = true;
        if ($slot) $occupied[$slot] = true;
        $rows[] = compact('memberId', 'vehicle', 'role') + ['name' => $members[$memberId]];
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
    // Convert transport warnings and non-2xx responses into one stable API error.
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

function diveraData(array $unit, bool $includeVehicles = true): array
{
    $key = rawurlencode($unit['divera_access_key']);
    $alarmsRaw = diveraGet("https://app.divera247.com/api/v2/alarms?accesskey=$key", 'DIVERA-Abfrage fehlgeschlagen');
    $ownVehicles = [];
    if ($includeVehicles) {
        $unitRaw = diveraGet("https://app.divera247.com/api/v2/pull/all?accesskey=$key", 'DIVERA-Abfrage fehlgeschlagen');
        foreach (($unitRaw['data']['cluster']['vehicle'] ?? []) as $id => $vehicle) {
            $ownVehicles[(string)($vehicle['id'] ?? $id)] = $vehicle;
        }
    }
    $vehicles = [];
    foreach ($ownVehicles as $id => $vehicle) $vehicles[] = [
        'id' => $id, 'name' => $vehicle['name'] ?? $vehicle['shortname'] ?? $id,
        'shortname' => (string)($vehicle['shortname'] ?? ''), 'fullname' => (string)($vehicle['fullname'] ?? ''), 'own' => true
    ];
    $source = $alarmsRaw['data']['items'] ?? $alarmsRaw['data'] ?? $alarmsRaw['items'] ?? $alarmsRaw;
    $alarms = [];
    foreach (is_array($source) ? array_values($source) : [] as $alarm) {
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
    $path = requestPath();
    $public = in_array($path, ['/api/bootstrap', '/api/setup', '/api/login', '/api/password-reset/request', '/api/password-reset/confirm'], true);
    $user = $public ? null : currentUser();
    if (!$public && !$user) respond(401, ['error' => 'Bitte anmelden']);

    if ($method === 'GET' && $path === '/api/bootstrap') {
        $databaseError = databaseConfigurationError();
        if ($databaseError) respond(503, ['error' => $databaseError]);
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
        $email = emailAddress($data['email'] ?? null);
        transaction(function () use ($data, $email, $password) {
            query('INSERT INTO organizations(name) VALUES(?)', [required($data['organization'] ?? null, 'Wehr', 200)]);
            $org = (int)db()->lastInsertId();
            query('INSERT INTO units(organization_id,name) VALUES(?,?)', [$org, required($data['unit'] ?? null, 'Einheit', 200)]);
            $unitId = (int)db()->lastInsertId();
            query(
                "INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) VALUES(?,?,?,?,?,'wehrleitung')",
                [$org, $unitId, required($data['name'] ?? null, 'Name', 200), $email, password_hash($password, PASSWORD_DEFAULT)]
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
        $cookieName = sessionCookieName();
        transaction(function () use ($token, $login, $cookieName) {
            query('DELETE FROM sessions WHERE expires_at<=UTC_TIMESTAMP()');
            if (preg_match('/^[a-f0-9]{64}$/', $_COOKIE[$cookieName] ?? '')) query('DELETE FROM sessions WHERE token=?', [hash('sha256', $_COOKIE[$cookieName])]);
            query('INSERT INTO sessions(token,user_id,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 12 HOUR)', [hash('sha256', $token), $login['id']]);
            query('INSERT INTO login_history(user_id,logged_in_at) VALUES(?,UTC_TIMESTAMP())', [$login['id']]);
        });
        setcookie($cookieName, $token, [
            'expires' => time() + 43200, 'path' => '/', 'secure' => requestIsHttps(),
            'httponly' => true, 'samesite' => 'Strict'
        ]);
        respond(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/password-reset/request') {
        $data = input();
        $email = emailAddress($data['email'] ?? null);
        mailSettings();
        $user = one('SELECT id,name,email FROM users WHERE email=?', [$email]);
        if ($user) {
            $recent = one('SELECT id FROM password_resets WHERE user_id=? AND requested_at>UTC_TIMESTAMP()-INTERVAL 5 MINUTE', [$user['id']]);
            if (!$recent) {
                $token = bin2hex(random_bytes(32));
                transaction(function () use ($user, $token) {
                    query('DELETE FROM password_resets WHERE expires_at<=UTC_TIMESTAMP() OR user_id=?', [$user['id']]);
                    query('INSERT INTO password_resets(user_id,token_hash,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 30 MINUTE)', [$user['id'], hash('sha256', $token)]);
                });
                if (!sendPasswordEmail($user, $token)) {
                    query('DELETE FROM password_resets WHERE user_id=?', [$user['id']]);
                    error_log('Passwort-Wiederherstellungs-E-Mail konnte nicht versendet werden');
                }
            }
        }
        // The response never reveals whether the address belongs to an account.
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
        $cookieName = sessionCookieName();
        if (preg_match('/^[a-f0-9]{64}$/', $_COOKIE[$cookieName] ?? '')) query('DELETE FROM sessions WHERE token=?', [hash('sha256', $_COOKIE[$cookieName])]);
        setcookie($cookieName, '', [
            'expires' => 1, 'path' => '/', 'secure' => requestIsHttps(),
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

    if ($method === 'GET' && $path === '/api/options') {
        respond(200, [
            'ranks' => RANKS,
            'incidentTypes' => INCIDENT_TYPES,
            'classifications' => CLASSIFICATIONS,
            'classificationLabels' => CLASSIFICATION_LABELS
        ]);
    }

    if ($method === 'GET' && $path === '/api/system') {
        assertRole($user, 'wehrleitung');
        $settings = config();
        $databaseError = databaseConfigurationError();
        $database = ['status' => $databaseError ?? 'Bereit'];
        if ($databaseError === null) {
            $database['name'] = (string)db()->query('SELECT DATABASE()')->fetchColumn();
            $database['serverVersion'] = (string)db()->getAttribute(PDO::ATTR_SERVER_VERSION);
        }
        $email = [
            'configured' => false,
            'transport' => empty($settings['smtp_host']) ? 'PHP mail()' : 'SMTP mit STARTTLS',
            'from' => (string)($settings['mail_from'] ?? '')
        ];
        try {
            $mail = mailSettings();
            $email = array_replace($email, [
                'configured' => true,
                'host' => $mail['smtpHost'],
                'port' => $mail['smtpHost'] === '' ? null : $mail['smtpPort'],
                'username' => $mail['smtpHost'] === '' ? '' : $mail['smtpUsername']
            ]);
        } catch (ApiError $error) {
            $email['error'] = $error->getMessage();
        }
        $systemUnits = query(
            'SELECT id,name,(divera_access_key IS NOT NULL) diveraConfigured FROM units WHERE organization_id=? ORDER BY name',
            [$user['organization_id']]
        )->fetchAll();
        foreach ($systemUnits as &$unit) {
            $unit['id'] = (int)$unit['id'];
            $unit['diveraConfigured'] = (bool)$unit['diveraConfigured'];
        }
        $systemUsers = query(
            "SELECT u.id,u.name,u.email,u.role,
             COALESCE((SELECT GROUP_CONCAT(un.name ORDER BY un.name SEPARATOR ', ') FROM user_units uu JOIN units un ON un.id=uu.unit_id WHERE uu.user_id=u.id),'') units
             FROM users u WHERE u.organization_id=? ORDER BY u.name",
            [$user['organization_id']]
        )->fetchAll();
        foreach ($systemUsers as &$systemUser) $systemUser['id'] = (int)$systemUser['id'];
        respond(200, [
            'application' => [
                'url' => (string)($settings['app_url'] ?? ''),
                'phpVersion' => PHP_VERSION,
                'setupConfigured' => strlen((string)($settings['setup_token'] ?? '')) >= 32
            ],
            'database' => $database,
            'email' => $email,
            'units' => $systemUnits,
            'users' => $systemUsers
        ]);
    }

    if ($method === 'GET' && $path === '/api/units') {
        $rows = query(
            "SELECT u.id,u.name,(u.divera_access_key IS NOT NULL) divera_configured,
             DATE_FORMAT(MAX(di.imported_at),'%Y-%m-%dT%H:%i:%s.000Z') last_divera_import_at
             FROM units u LEFT JOIN divera_imports di ON di.unit_id=u.id
             WHERE u.organization_id=? GROUP BY u.id,u.name,u.divera_access_key ORDER BY u.name",
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
        $history = query(
            "SELECT user_id,DATE_FORMAT(logged_in_at,'%Y-%m-%dT%H:%i:%sZ') logged_in_at FROM
             (SELECT h.*,ROW_NUMBER() OVER(PARTITION BY h.user_id ORDER BY h.logged_in_at DESC,h.id DESC) history_position
              FROM login_history h JOIN users u ON u.id=h.user_id WHERE u.organization_id=?) recent
             WHERE history_position<=5 ORDER BY user_id,history_position",
            [$user['organization_id']]
        )->fetchAll();
        $historyByUser = [];
        foreach ($history as $login) $historyByUser[(int)$login['user_id']][] = $login['logged_in_at'];
        foreach ($rows as &$row) {
            $row['id'] = (int)$row['id'];
            $row['loginHistory'] = $historyByUser[$row['id']] ?? [];
        }
        respond(200, $rows);
    }

    if ($method === 'POST' && $path === '/api/users') {
        assertRole($user, 'wehrleitung');
        $data = input();
        if (!in_array($data['role'] ?? null, ROLES, true)) throw new ApiError(400, 'Rolle ist ungültig');
        $unitIds = membershipIds($data, $user['organization_id']);
        $name = required($data['name'] ?? null, 'Name', 200);
        $email = emailAddress($data['email'] ?? null);
        mailSettings();
        $token = bin2hex(random_bytes(32));
        $id = transaction(function () use ($data, $name, $email, $token, $unitIds, $user) {
            // An unknown random password keeps the account unusable until activation.
            query(
                'INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) VALUES(?,?,?,?,?,?)',
                [$user['organization_id'], $unitIds[0] ?? null, $name, $email,
                 password_hash(bin2hex(random_bytes(32)), PASSWORD_DEFAULT), $data['role']]
            );
            $id = (int)db()->lastInsertId();
            replaceMemberships($id, $unitIds);
            query('INSERT INTO password_resets(user_id,token_hash,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 30 MINUTE)', [$id, hash('sha256', $token)]);
            return $id;
        });
        if (!sendPasswordEmail(['name' => $name, 'email' => $email], $token, true)) {
            query('DELETE FROM users WHERE id=?', [$id]);
            error_log('Einladungs-E-Mail konnte nicht versendet werden');
            throw new ApiError(503, 'Einladungs-E-Mail konnte nicht versendet werden');
        }
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
            query('SELECT id FROM organizations WHERE id=? FOR UPDATE', [$existing['organization_id']]);
            $current = one('SELECT role FROM users WHERE id=? AND organization_id=?', [$existing['id'], $existing['organization_id']]);
            if ($current && $current['role'] === 'wehrleitung' && $data['role'] !== 'wehrleitung'
                && !one("SELECT id FROM users WHERE organization_id=? AND role='wehrleitung' AND id<>? LIMIT 1", [$existing['organization_id'], $existing['id']])) {
                throw new ApiError(409, 'Mindestens eine Wehrführung ist erforderlich');
            }
            query(
                'UPDATE users SET unit_id=?,name=?,email=?,role=?,password_hash=? WHERE id=?',
                [$unitIds[0] ?? null, required($data['name'] ?? null, 'Name', 200),
                 emailAddress($data['email'] ?? null), $data['role'],
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
        $assignments = [];
        foreach (query(
            "SELECT iu.incident_id,iu.unit_id unitId,iu.vehicles,
             EXISTS(SELECT 1 FROM reports r WHERE r.incident_id=iu.incident_id AND r.unit_id=iu.unit_id) hasReport
             FROM incident_units iu JOIN incidents i ON i.id=iu.incident_id
             WHERE $where ORDER BY iu.incident_id,iu.unit_id",
            $params
        )->fetchAll() as $assignment) {
            $incidentId = (int)$assignment['incident_id'];
            unset($assignment['incident_id']);
            $assignment['unitId'] = (int)$assignment['unitId'];
            $assignment['hasReport'] = (int)$assignment['hasReport'];
            $assignments[$incidentId][] = $assignment;
        }
        foreach ($rows as &$row) {
            $row['assignments'] = json_encode($assignments[(int)$row['id']] ?? [], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
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
            $startedAt = utcString(requestDate($data['startedAt'] ?? null, 'Zeitpunkt'));
            query(
                'INSERT INTO incidents(organization_id,title,started_at,address,message,remark,patient,caller,consolidated_text) VALUES(?,?,?,?,?,?,?,?,?)',
                [$user['organization_id'], required($data['title'] ?? null, 'Stichwort', 300),
                 $startedAt, optional($data['address'] ?? null, 'Adresse', 500), '', '', '', '', '']
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
        $crew = [];
        foreach (query(
            "SELECT rc.report_id reportId,rc.member_id memberId,m.name,rc.vehicle,rc.role
             FROM report_crew rc JOIN members m ON m.id=rc.member_id JOIN reports r ON r.id=rc.report_id
             WHERE r.incident_id=?$where ORDER BY rc.report_id,rc.member_id",
            $params
        )->fetchAll() as $person) {
            $reportId = (int)$person['reportId'];
            unset($person['reportId']);
            $person['memberId'] = (int)$person['memberId'];
            $crew[$reportId][] = $person;
        }
        foreach ($rows as &$row) {
            $row['crew'] = json_encode($crew[(int)$row['id']] ?? [], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
            $row['duration_minutes'] = (int)round((strtotime($row['ended_at']) - strtotime($row['alarmed_at'])) / 60);
            foreach (['id', 'incident_id', 'unit_id', 'author_id', 'report_year'] as $key) if ($row[$key] !== null) $row[$key] = (int)$row[$key];
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
                'INSERT INTO reports(incident_id,unit_id,author_id,report_year,running_number,damaged_party,damaging_party,incident_command,narrative,alarmed_at,departed_at,arrived_at,ended_at,incident_type,classification,vehicles,personnel)
                 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                [$incidentId, $unitId, $user['id'], $details['reportYear'], $details['runningNumber'],
                 $details['damagedParty'], $details['damagingParty'], $details['incidentCommand'], required($data['narrative'] ?? null, 'Bericht'),
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
            // Locking closes the race between editing and releasing the same report.
            $lockedReport = one('SELECT * FROM reports WHERE id=? FOR UPDATE', [$foundReport['id']]);
            if (!$lockedReport || $lockedReport['status'] !== 'draft') {
                throw new ApiError(409, 'Der Bericht wurde bereits freigegeben');
            }
            $foundIncident = incident((int)$lockedReport['incident_id'], $user['organization_id']);
            $details = reportDetails($data, $foundIncident);
            $summary = replaceCrew((int)$lockedReport['id'], (int)$lockedReport['incident_id'], (int)$lockedReport['unit_id'], $data['crew'] ?? [], $user['organization_id']);
            query(
                'UPDATE reports SET report_year=?,running_number=?,damaged_party=?,damaging_party=?,incident_command=?,narrative=?,vehicles=?,personnel=?,alarmed_at=?,departed_at=?,arrived_at=?,ended_at=?,incident_type=?,classification=? WHERE id=?',
                [$details['reportYear'], $details['runningNumber'], $details['damagedParty'], $details['damagingParty'], $details['incidentCommand'],
                 required($data['narrative'] ?? null, 'Bericht'), $summary['vehicles'], $summary['personnel'],
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
        $released = query("UPDATE reports SET status='released',released_at=UTC_TIMESTAMP() WHERE id=? AND status='draft'", [$foundReport['id']]);
        if ($released->rowCount() !== 1) throw new ApiError(409, 'Der Bericht wurde bereits freigegeben');
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
        respond(200, diveraData($foundUnit, ($_GET['summary'] ?? '') !== '1'));
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
                // LAST_INSERT_ID(id) also returns the id of an existing upserted row.
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
        // Trust only the id from the browser; reload all incident data from DIVERA.
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
            query(
                'INSERT INTO divera_imports(unit_id,incident_id,imported_by,imported_at) VALUES(?,?,?,UTC_TIMESTAMP())',
                [$unitId, $incidentId, $user['id']]
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
    $duplicate = (int)($error->errorInfo[1] ?? 0) === 1062;
    respond($duplicate ? 409 : 500, ['error' => $duplicate ? 'Datensatz existiert bereits' : 'Interner Fehler']);
} catch (Throwable $error) {
    error_log((string)$error);
    respond(500, ['error' => 'Interner Fehler']);
}
