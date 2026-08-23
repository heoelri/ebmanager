<?php
declare(strict_types=1);

$context = stream_context_create(['ssl' => [
    'local_cert' => $argv[1],
    'local_pk' => $argv[2],
    'verify_peer' => false,
]]);
$server = stream_socket_server('tcp://127.0.0.1:2525', $errorCode, $errorMessage, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, $context);
if (!$server) exit(1);
$client = stream_socket_accept($server, 20);
if (!$client) exit(1);

function expectCommand($client, string $pattern, string $reply): void
{
    $line = fgets($client);
    if ($line === false || !preg_match($pattern, rtrim($line, "\r\n"))) exit(1);
    fwrite($client, $reply);
}

fwrite($client, "220 localhost test SMTP\r\n");
expectCommand($client, '/^EHLO /', "250-localhost\r\n250 STARTTLS\r\n");
expectCommand($client, '/^STARTTLS$/', "220 Ready\r\n");
if (stream_socket_enable_crypto($client, true, STREAM_CRYPTO_METHOD_TLS_SERVER) !== true) exit(1);
expectCommand($client, '/^EHLO /', "250-localhost\r\n250 AUTH LOGIN\r\n");
expectCommand($client, '/^AUTH LOGIN$/', "334 VXNlcm5hbWU6\r\n");
expectCommand($client, '/^[A-Za-z0-9+\/=]+$/', "334 UGFzc3dvcmQ6\r\n");
expectCommand($client, '/^[A-Za-z0-9+\/=]+$/', "235 Authenticated\r\n");
expectCommand($client, '/^MAIL FROM:<.+>$/', "250 Sender accepted\r\n");
expectCommand($client, '/^RCPT TO:<invite@example\.test>$/', "250 Recipient accepted\r\n");
expectCommand($client, '/^DATA$/', "354 End with a dot\r\n");
$message = '';
while (($line = fgets($client)) !== false && $line !== ".\r\n") $message .= $line;
if (!str_contains($message, 'Subject: Konto aktivieren') || !str_contains($message, '?invite=')) exit(1);
fwrite($client, "250 Queued\r\n");
expectCommand($client, '/^QUIT$/', "221 Bye\r\n");
fclose($client);
fclose($server);
