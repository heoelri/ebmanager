<?php
declare(strict_types=1);

// Zulässige Benutzerrollen für Verwaltung und API-Prüfungen; Änderungen erfordern auch eine Anpassung des Rollen-ENUMs in schema.sql.
const ROLES = ['wehrleitung', 'einheitsleitung', 'fuehrungskraft'];

// Dienstgradabkürzungen und Anzeigenamen für die Drop-downs der Einsatzleitung; im Bericht wird jeweils die Abkürzung gespeichert.
const RANKS = [
    'FMA' => 'Feuerwehrmann-Anwärter',
    'FM' => 'Feuerwehrmann',
    'OFM' => 'Oberfeuerwehrmann',
    'HFM' => 'Hauptfeuerwehrmann',
    'UBM' => 'Unterbrandmeister',
    'BM' => 'Brandmeister',
    'OBM' => 'Oberbrandmeister',
    'HBM' => 'Hauptbrandmeister',
    'BI' => 'Brandinspektor',
    'BOI' => 'Brandoberinspektor',
    'GBI' => 'Gemeindebrandinspektor',
    'SBI' => 'Stadtbrandinspektor'
];

// Zulässige Einsatzarten für das Berichtsformular und die serverseitige Validierung; gespeichert wird der jeweilige Textwert.
const INCIDENT_TYPES = [
    'Kleinbrand', 'Mittelbrand', 'Großbrand', 'Wald- und Flächenbrand',
    'Schornsteinbrand', 'Kfz-Brand', 'Verkehrsunfall', 'Oelunfall/Oelspur',
    'Chemieunfall', 'Technische Hilfe', 'Sturmeinsatz', 'Hochwassereinsatz',
    'Fehlalarm BMA', 'BMA', 'Fehlalarm', 'Böswilliger Alarm', 'Sonstiges'
];

// Überschriften der Klassifikationsgruppen im Berichtsformular; die Schlüssel müssen mit CLASSIFICATIONS übereinstimmen.
const CLASSIFICATION_LABELS = [
    'site' => 'Einsatzstelle',
    'cause' => 'Schadensursache',
    'technical' => 'Technische Hilfe'
];

// Auswahlwerte der Berichtsaufgliederung für Frontend und API-Validierung; gespeichert werden die gewählten Werte gruppiert als JSON.
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
