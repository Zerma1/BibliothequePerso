import 'dart:convert';

import 'package:bibliotheque_perso/sources/detection_image.dart';
import 'package:flutter_test/flutter_test.dart';

/// Boîte `ftyp` ISO BMFF de marque [marque] et de marques compatibles
/// [compatibles], suivie de quelques octets.
List<int> boiteFtyp(String marque, List<String> compatibles) {
  final taille = 16 + 4 * compatibles.length;
  return <int>[
    0,
    0,
    0,
    taille,
    ...ascii.encode('ftyp'),
    ...ascii.encode(marque),
    0,
    0,
    0,
    0,
    for (final c in compatibles) ...ascii.encode(c),
    0,
    0,
    0,
    8,
  ];
}

void main() {
  group('detecterFormatImage', () {
    test('reconnaît chaque signature', () {
      final cas = <FormatImage, List<int>>{
        FormatImage.jpeg: <int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10],
        FormatImage.png: <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        FormatImage.gif: ascii.encode('GIF89a\x01\x00'),
        FormatImage.webp: <int>[
          ...ascii.encode('RIFF'),
          0x24,
          0x10,
          0,
          0,
          ...ascii.encode('WEBPVP8L'),
        ],
        FormatImage.avif: boiteFtyp('avif', <String>['mif1', 'miaf']),
        FormatImage.heif: boiteFtyp('heic', <String>['mif1', 'heic']),
        FormatImage.bmp: <int>[
          ...ascii.encode('BM'),
          0x36,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0x36,
          0,
          0,
          0,
          40,
          0,
          0,
          0,
        ],
      };
      for (final entree in cas.entries) {
        expect(
          detecterFormatImage(entree.value),
          entree.key,
          reason: entree.key.name,
        );
      }
      expect(detecterFormatImage(ascii.encode('GIF87a')), FormatImage.gif);
    });

    test('AVIF de marque générique mif1 : reconnu par ses marques '
        'compatibles', () {
      expect(
        detecterFormatImage(boiteFtyp('mif1', <String>['avif', 'miaf'])),
        FormatImage.avif,
      );
      expect(
        detecterFormatImage(boiteFtyp('mif1', <String>['heic'])),
        FormatImage.heif,
      );
    });

    test("extension et type MIME suivent le format (nom de la page dans "
        "l'archive)", () {
      expect(FormatImage.webp.extension, 'webp');
      expect(FormatImage.jpeg.extension, 'jpg');
      expect(FormatImage.heif.extension, 'heic');
      expect(FormatImage.avif.typeMime, 'image/avif');
    });

    test(
      'refuse le texte, le HTML, une vidéo MP4 et les en-têtes tronqués',
      () {
        expect(detecterFormatImage(utf8.encode('<!doctype html>')), isNull);
        expect(detecterFormatImage(utf8.encode('BMW série 3, page 1')), isNull);
        expect(
          detecterFormatImage(boiteFtyp('isom', <String>['mp42'])),
          isNull,
        );
        expect(detecterFormatImage(ascii.encode('RIFF')), isNull);
        expect(
          detecterFormatImage(<int>[
            ...ascii.encode('RIFF'),
            0,
            0,
            0,
            0,
            ...ascii.encode('WAVE'),
          ]),
          isNull,
        );
        expect(detecterFormatImage(const <int>[0xFF, 0xD8]), isNull);
        expect(detecterFormatImage(const <int>[]), isNull);
      },
    );
  });

  group('texte ou binaire', () {
    test('estContenuTexte', () {
      expect(estContenuTexte(utf8.encode('Accès refusé\r\n\tpage')), isTrue);
      expect(estContenuTexte(const <int>[]), isTrue);
      expect(estContenuTexte(const <int>[0x41, 0x00, 0x42]), isFalse);
      expect(
        estContenuTexte(<int>[for (var i = 0; i < 100; i++) 0x80 + i % 60]),
        isFalse,
      );
    });

    test('estContenuHtml', () {
      expect(estContenuHtml(utf8.encode('  <!DOCTYPE html><html>')), isTrue);
      expect(
        estContenuHtml(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('<html>')]),
        isTrue,
      );
      expect(estContenuHtml(utf8.encode('<!-- x --><html lang="fr">')), isTrue);
      expect(estContenuHtml(utf8.encode('<svg xmlns="x"/>')), isFalse);
      expect(estContenuHtml(utf8.encode('Erreur 500')), isFalse);
    });

    test('extraitTexteImprimable : court, imprimable, null si binaire', () {
      expect(extraitTexteImprimable(const <int>[0, 1, 2, 0xFF]), isNull);
      expect(extraitTexteImprimable(const <int>[]), isNull);
      final extrait = extraitTexteImprimable(
        utf8.encode('Page   introuvable\x07 ${'é' * 200}'),
      )!;
      expect(extrait, startsWith('Page introuvable '));
      expect(extrait.length, lessThanOrEqualTo(81));
      expect(extrait.runes.every((c) => c >= 0x20 && c != 0x7F), isTrue);
    });

    test('decrireContenuNonImage', () {
      expect(decrireContenuNonImage(const <int>[]), 'réponse vide');
      expect(decrireContenuNonImage(utf8.encode('<html>')), 'page HTML');
      expect(decrireContenuNonImage(utf8.encode('Erreur')), 'texte');
      expect(
        decrireContenuNonImage(const <int>[0, 1, 2]),
        'données binaires non reconnues',
      );
    });
  });
}
