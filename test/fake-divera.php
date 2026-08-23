<?php
declare(strict_types=1);

$query = [];
parse_str(parse_url($_SERVER['REQUEST_URI'], PHP_URL_QUERY) ?: '', $query);
$reduced = ($query['accesskey'] ?? '') === 'reduced';
$malformed = ($query['accesskey'] ?? '') === 'malformed';
file_put_contents(getenv('DIVERA_REQUEST_LOG') ?: sys_get_temp_dir() . '/divera-requests.log', ($_SERVER['REQUEST_METHOD'] ?? '') . ' ' . parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) . "\n", FILE_APPEND);
header('Content-Type: application/json');

if (parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) === '/api/v2/pull/all') {
    if ($malformed) {
        echo '{"data":{"cluster":{"vehicle":[{"id":"","name":"Ungültig"}],"qualification":[],"consumer":[]}}}';
        return;
    }
    echo json_encode(['data' => ['cluster' => [
        'vehicle' => $reduced
            ? ['v1' => ['id' => 'v1', 'name' => 'HLF 20', 'shortname' => 'HLF', 'fullname' => 'Hilfeleistungslöschfahrzeug']]
            : [
                'v1' => ['id' => 'v1', 'name' => 'HLF 20', 'shortname' => 'HLF', 'fullname' => 'Hilfeleistungslöschfahrzeug'],
                'v2' => ['id' => 'v2', 'name' => 'MTF', 'shortname' => 'MTF', 'fullname' => 'Mannschaftstransportfahrzeug']
            ],
        'qualification' => $reduced
            ? ['q1' => ['id' => 'q1', 'name' => 'Atemschutzgeräteträger', 'shortname' => 'AGT']]
            : [
                'q1' => ['id' => 'q1', 'name' => 'Atemschutzgeräteträger', 'shortname' => 'AGT'],
                'q2' => ['id' => 'q2', 'name' => 'Maschinist', 'shortname' => 'MA']
            ],
        'consumer' => $reduced
            ? ['m1' => ['id' => 'm1', 'stdformat_name' => 'Anna Beispiel', 'qualifications' => ['q1']]]
            : [
                'm1' => ['id' => 'm1', 'stdformat_name' => 'Anna Beispiel', 'qualifications' => ['q1']],
                'm2' => ['id' => 'm2', 'stdformat_name' => 'Bernd Beispiel', 'qualifications' => ['q2']]
            ]
    ]]], JSON_UNESCAPED_UNICODE);
    return;
}

if (parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) === '/api/v2/alarms') {
    echo json_encode(['data' => ['items' => [
        ['id' => 'alarm-1', 'foreign_id' => 'D-1', 'date' => 1787421600, 'title' => 'Brand', 'address' => 'Testweg 1', 'lat' => 50.9, 'lng' => 8.0, 'vehicles' => ['v1', 'external-1']],
        ['id' => 'alarm-2', 'foreign_id' => 'D-2', 'date' => 1787425200, 'title' => 'Hilfeleistung', 'address' => 'Testweg 2', 'lat' => 50.8, 'lng' => 8.1, 'vehicles' => ['v2']]
    ]]], JSON_UNESCAPED_UNICODE);
    return;
}

http_response_code(404);
echo '{"error":"not found"}';
