/// Empreinte SHA-256 (FIPS 180-4) d'un fichier, calculée en flux.
///
/// Écrite ici plutôt qu'avec un paquet (`crypto`) : le projet n'en dépend
/// pas, et l'empreinte ne sert qu'à reconnaître un fichier déjà importé
/// (aucun usage de sécurité). Vérifiée par les vecteurs de test officiels
/// (test/donnees/empreinte_sha256_test.dart).
///
/// LIMITE : arithmétique sur des entiers 64 bits (masques 32 bits) : valable
/// sur la VM Dart (Windows, Linux, Android), pas sur le web.
library;

import 'dart:io';
import 'dart:typed_data';

/// Calcule l'empreinte SHA-256 du fichier [chemin], en hexadécimal
/// minuscule (64 caractères), sans le charger entièrement en mémoire.
///
/// Lève une [FileSystemException] si le fichier ne peut pas être lu.
Future<String> calculerEmpreinteSha256Fichier(String chemin) async {
  final calcul = CalculSha256();
  await for (final bloc in File(chemin).openRead()) {
    calcul.ajouter(bloc);
  }
  return calcul.terminer();
}

/// Empreinte SHA-256 de [octets], en hexadécimal minuscule.
String empreinteSha256(List<int> octets) =>
    (CalculSha256()..ajouter(octets)).terminer();

/// Calcul SHA-256 incrémental : [ajouter] autant de fois que nécessaire,
/// puis [terminer] une seule fois.
class CalculSha256 {
  /// Crée un calcul vide.
  CalculSha256();

  static const List<int> _k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  static const int _masque = 0xffffffff;

  final List<int> _h = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final Uint8List _bloc = Uint8List(64);
  final List<int> _w = List<int>.filled(64, 0);
  int _remplissage = 0;
  int _longueur = 0;
  bool _termine = false;

  /// Ajoute [octets] au calcul. Lève une [StateError] après [terminer].
  void ajouter(List<int> octets) {
    if (_termine) throw StateError('Calcul SHA-256 déjà terminé.');
    _longueur += octets.length;
    for (final octet in octets) {
      _bloc[_remplissage++] = octet;
      if (_remplissage == 64) {
        _traiterBloc();
        _remplissage = 0;
      }
    }
  }

  /// Termine le calcul et renvoie l'empreinte en hexadécimal minuscule.
  String terminer() {
    if (_termine) throw StateError('Calcul SHA-256 déjà terminé.');
    final bits = _longueur * 8;
    // Remplissage : 0x80, des zéros, puis la longueur en bits sur 64 bits.
    final fin = <int>[0x80];
    final reste = (_remplissage + 1) % 64;
    final zeros = reste <= 56 ? 56 - reste : 120 - reste;
    fin.addAll(List<int>.filled(zeros, 0));
    for (var decalage = 56; decalage >= 0; decalage -= 8) {
      fin.add((bits >> decalage) & 0xff);
    }
    final longueur = _longueur;
    ajouter(fin);
    _longueur = longueur;
    _termine = true;
    final texte = StringBuffer();
    for (final mot in _h) {
      texte.write(mot.toRadixString(16).padLeft(8, '0'));
    }
    return texte.toString();
  }

  static int _rotation(int x, int n) => ((x >> n) | (x << (32 - n))) & _masque;

  void _traiterBloc() {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      w[i] =
          (_bloc[i * 4] << 24) |
          (_bloc[i * 4 + 1] << 16) |
          (_bloc[i * 4 + 2] << 8) |
          _bloc[i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 =
          _rotation(w[i - 15], 7) ^ _rotation(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 =
          _rotation(w[i - 2], 17) ^ _rotation(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & _masque;
    }
    var a = _h[0], b = _h[1], c = _h[2], d = _h[3];
    var e = _h[4], f = _h[5], g = _h[6], h = _h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotation(e, 6) ^ _rotation(e, 11) ^ _rotation(e, 25);
      final ch = (e & f) ^ ((~e & _masque) & g);
      final t1 = (h + s1 + ch + _k[i] + w[i]) & _masque;
      final s0 = _rotation(a, 2) ^ _rotation(a, 13) ^ _rotation(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & _masque;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & _masque;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _masque;
    }
    _h[0] = (_h[0] + a) & _masque;
    _h[1] = (_h[1] + b) & _masque;
    _h[2] = (_h[2] + c) & _masque;
    _h[3] = (_h[3] + d) & _masque;
    _h[4] = (_h[4] + e) & _masque;
    _h[5] = (_h[5] + f) & _masque;
    _h[6] = (_h[6] + g) & _masque;
    _h[7] = (_h[7] + h) & _masque;
  }
}
