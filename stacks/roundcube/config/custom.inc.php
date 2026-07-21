<?php

// Stalwart uses a local self-signed TLS cert on IMAP/SMTP.
$config['imap_conn_options'] = [
    'ssl' => [
        'verify_peer'       => false,
        'verify_peer_name'  => false,
        'allow_self_signed' => true,
    ],
];

$config['smtp_conn_options'] = [
    'ssl' => [
        'verify_peer'       => false,
        'verify_peer_name'  => false,
        'allow_self_signed' => true,
    ],
];

$config['username_domain'] = 'dobasmp.net';
$config['mail_domain'] = 'dobasmp.net';
$config['product_name'] = 'dobasmp.net Mail';
