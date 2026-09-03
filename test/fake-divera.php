<?php
declare(strict_types=1);

/*
 * Official reference: https://api.divera247.com/ (Swagger UI)
 * Alarm schema: https://api.divera247.com/docs/api_v2_alarm.yaml
 * Pull schema: https://api.divera247.com/docs/api_v2_pull.yaml
 * Last manually compared with OpenAPI 4.1.0 on 2026-08-23.
 * .github/workflows/divera-api-contract.yml checks the documented paths and fields monthly.
 *
 * Only the two GET responses consumed by this application are emulated. Write endpoints are
 * intentionally absent. The alarm "vehicles" fixture reflects the assignment data consumed by
 * the application; DIVERA's published alarm-result schema currently documents this only broadly
 * as "units", so this detail must also be verified against a real test unit before changing it.
 */

function demoCluster(array $unit): array
{
    $qualifications = [];
    foreach (['gf' => ['Gruppenführer', 'GF'], 'ma' => ['Maschinist', 'MA'], 'agt' => ['Atemschutzgeräteträger', 'AGT'], 'san' => ['Sanitäter', 'SAN']] as $suffix => [$name, $shortname]) {
        $id = "{$unit['prefix']}-$suffix";
        $qualifications[$id] = ['id' => $id, 'name' => $name, 'shortname' => $shortname];
    }
    $qualificationMap = [
        '01' => ['gf'], '02' => ['ma'], '03' => ['agt'], '04' => ['agt'],
        '05' => ['gf', 'agt'], '06' => ['ma', 'agt'], '07' => ['san'], '08' => ['san']
    ];
    $consumers = [];
    foreach ($unit['members'] as $suffix => $name) {
        $suffix = str_pad((string)$suffix, 2, '0', STR_PAD_LEFT);
        $id = "{$unit['prefix']}-$suffix";
        $consumers[$id] = [
            'id' => $id, 'stdformat_name' => $name,
            'qualifications' => array_map(fn(string $qualification): string => "{$unit['prefix']}-$qualification", $qualificationMap[$suffix])
        ];
    }
    $vehicles = [];
    foreach ($unit['vehicles'] as $id => $vehicle) $vehicles[$id] = ['id' => $id] + $vehicle;
    return ['vehicle' => $vehicles, 'qualification' => $qualifications, 'consumer' => $consumers];
}

function demoAlarms(string $prefix): array
{
    $date = strtotime('tomorrow 12:00 UTC');
    $shared = [
        'id' => 'demo-live-shared', 'foreign_id' => 'D-LIVE-001', 'date' => $date,
        'title' => 'Gebäudebrand', 'text' => 'Rauch aus einem Wohngebäude',
        'address' => 'Rathausplatz 1, Musterstadt', 'lat' => 50.101, 'lng' => 8.611,
        'remark' => 'Alarmierung der Einheiten Mitte und Nord', 'patient' => '', 'caller' => 'Leitstelle'
    ];
    return match ($prefix) {
        'demo-mitte' => [
            'demo-live-mitte' => [
                'id' => 'demo-live-mitte', 'foreign_id' => 'D-LIVE-002', 'date' => $date - 900,
                'title' => 'Türöffnung', 'text' => 'Hilflose Person hinter Tür',
                'address' => 'Mittelweg 4, Musterstadt', 'lat' => 50.102, 'lng' => 8.612,
                'remark' => '', 'patient' => '', 'caller' => 'Leitstelle', 'vehicles' => ['demo-mitte-hlf']
            ],
            'demo-live-shared' => $shared + ['vehicles' => ['demo-mitte-elw', 'demo-mitte-hlf']]
        ],
        'demo-nord' => [
            'demo-live-nord' => [
                'id' => 'demo-live-nord', 'foreign_id' => 'D-LIVE-003', 'date' => $date - 600,
                'title' => 'Sturmschaden', 'text' => 'Baum auf Fahrbahn',
                'address' => 'Nordring 8, Musterstadt', 'lat' => 50.112, 'lng' => 8.622,
                'remark' => '', 'patient' => '', 'caller' => 'Polizei', 'vehicles' => ['demo-nord-lf']
            ],
            'demo-live-shared' => $shared + ['vehicles' => ['demo-nord-lf']]
        ],
        'demo-sued' => [
            'demo-live-sued' => [
                'id' => 'demo-live-sued', 'foreign_id' => 'D-LIVE-004', 'date' => $date - 300,
                'title' => 'Flächenbrand', 'text' => 'Brennende Böschung',
                'address' => 'Südallee 19, Musterstadt', 'lat' => 50.092, 'lng' => 8.632,
                'remark' => '', 'patient' => '', 'caller' => 'Leitstelle', 'vehicles' => ['demo-sued-tsf', 'demo-sued-gwl']
            ]
        ],
        default => []
    };
}

$demoUnits = [
    'demo-local-mitte' => [
        'prefix' => 'demo-mitte',
        'members' => ['01' => 'Alina Becker', '02' => 'Ben Lorenz', '03' => 'Clara Neumann', '04' => 'David Schmitt', '05' => 'Elena Vogt', '06' => 'Felix Werner', '07' => 'Greta Baum', '08' => 'Hannes Wolf'],
        'vehicles' => [
            'demo-mitte-elw' => ['name' => 'ELW 1', 'shortname' => 'ELW 1', 'fullname' => 'Einsatzleitwagen 1'],
            'demo-mitte-hlf' => ['name' => 'HLF 20', 'shortname' => 'HLF 20', 'fullname' => 'Hilfeleistungslöschgruppenfahrzeug 20'],
            'demo-mitte-dlk' => ['name' => 'DLK 23', 'shortname' => 'DLK 23', 'fullname' => 'Drehleiter mit Korb 23']
        ]
    ],
    'demo-local-nord' => [
        'prefix' => 'demo-nord',
        'members' => ['01' => 'Ida Franke', '02' => 'Jonas Hartmann', '03' => 'Kira Peters', '04' => 'Lukas Krause', '05' => 'Mara Seidel', '06' => 'Noah Fuchs', '07' => 'Olivia Busch', '08' => 'Paul Lindner'],
        'vehicles' => [
            'demo-nord-lf' => ['name' => 'LF 10', 'shortname' => 'LF 10', 'fullname' => 'Löschgruppenfahrzeug 10'],
            'demo-nord-mtf' => ['name' => 'MTF Nord', 'shortname' => 'MTF', 'fullname' => 'Mannschaftstransportfahrzeug']
        ]
    ],
    'demo-local-sued' => [
        'prefix' => 'demo-sued',
        'members' => ['01' => 'Quirin Scholz', '02' => 'Romy Graf', '03' => 'Simon Keller', '04' => 'Tina Arnold', '05' => 'Uwe Sommer', '06' => 'Vera Lang', '07' => 'Wilma Ernst', '08' => 'Yannick Böhm'],
        'vehicles' => [
            'demo-sued-tsf' => ['name' => 'TSF-W Süd', 'shortname' => 'TSF-W', 'fullname' => 'Tragkraftspritzenfahrzeug mit Wasser'],
            'demo-sued-gwl' => ['name' => 'GW-L Süd', 'shortname' => 'GW-L', 'fullname' => 'Gerätewagen Logistik'],
            'demo-sued-mtf' => ['name' => 'MTF Süd', 'shortname' => 'MTF', 'fullname' => 'Mannschaftstransportfahrzeug']
        ]
    ]
];

$query = [];
parse_str(parse_url($_SERVER['REQUEST_URI'], PHP_URL_QUERY) ?: '', $query);
$accessKey = $query['accesskey'] ?? '';
$reduced = $accessKey === 'reduced';
$malformed = $accessKey === 'malformed';
$demoUnit = $demoUnits[$accessKey] ?? null;
$method = $_SERVER['REQUEST_METHOD'] ?? '';
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if ($method === 'GET' && $path === '/health') {
    echo 'ok';
    return;
}
file_put_contents(getenv('DIVERA_REQUEST_LOG') ?: sys_get_temp_dir() . '/divera-requests.log', "$method $path\n", FILE_APPEND);
header('Content-Type: application/json');

if ($method !== 'GET') {
    http_response_code(405);
    echo '{"error":"method not allowed"}';
    return;
}

if ($accessKey === 'http-error') {
    http_response_code(503);
    echo '{"error":"service unavailable"}';
    return;
}

if ($path === '/api/v2/pull/all') {
    if ($malformed) {
        echo '{"data":{"cluster":{"vehicle":[{"id":"","name":"Ungültig"}],"qualification":[],"consumer":[]}}}';
        return;
    }
    if ($demoUnit) {
        echo json_encode(['data' => ['cluster' => demoCluster($demoUnit)]], JSON_UNESCAPED_UNICODE);
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

if ($path === '/api/v2/alarms') {
    if ($demoUnit) {
        echo json_encode(['data' => ['items' => demoAlarms($demoUnit['prefix'])]], JSON_UNESCAPED_UNICODE);
        return;
    }
    echo json_encode(['data' => ['items' => [
        'alarm-1' => ['id' => 'alarm-1', 'foreign_id' => 'D-1', 'date' => 1787421600, 'title' => 'Brand', 'text' => 'Rauchentwicklung', 'address' => 'Testweg 1', 'lat' => 50.9, 'lng' => 8.0, 'remark' => '', 'patient' => '', 'caller' => 'Leitstelle', 'vehicles' => ['v1', 'external-1']],
        'alarm-2' => ['id' => 'alarm-2', 'foreign_id' => 'D-2', 'date' => 1787425200, 'title' => 'Hilfeleistung', 'text' => 'Baum auf Straße', 'address' => 'Testweg 2', 'lat' => 50.8, 'lng' => 8.1, 'remark' => '', 'patient' => '', 'caller' => 'Leitstelle', 'vehicles' => ['v2']]
    ]]], JSON_UNESCAPED_UNICODE);
    return;
}

http_response_code(404);
echo '{"error":"not found"}';
