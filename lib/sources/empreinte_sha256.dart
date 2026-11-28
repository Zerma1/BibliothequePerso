/// Calcul d'empreinte SHA-256 (FIPS 180-4) par morceaux, en Dart pur.
///
/// Pourquoi pas `package:crypto` : il n'est présent dans `pubspec.lock`
/// qu'en dépendance **transitive** ; l'importer depuis `lib/` sans
/// l'ajouter à `pubspec.yaml` déclencherait `depend_on_referenced_packages`
/// (et `pubspec.yaml` est hors du scope de `lib/sources/`). L'algorithme
/// est court et vérifié par les vecteurs de test officiels (NIST).
library;

import 'dart:typed_data';

/// Constantes de tour K (FIPS 180-4, section 4.2.2).
const List<int> _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const int _masque32 = 0xffffffff;

int _rotationDroite(int x, int n) => ((x >> n) | (x << (32 - n))) & _masque32;

/// Calcul SHA-256 incrémental : [ajouter] les octets au fil de l'eau (flux
/// d'un téléchargement), puis [terminer] une seule fois.
class CalculEmpreinteSha256 {
  /// Crée un calcul vide.
  CalculEmpreinteSha256();

  /// Valeurs de hachage initiales H(0) (FIPS 180-4, section 5.3.3).
  final List<int> _etat = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  final Uint8List _bloc = Uint8List(64);
  final List<int> _mots = List<int>.filled(64, 0);
  int _remplissage = 0;
  int _longueur = 0;
  bool _termine = false;

  /// Ajoute [octets] au calcul (chaque valeur est prise modulo 256).
  void ajouter(List<int> octets) {
    if (_termine) {
      throw StateError('Empreinte déjà terminée');
    }
    _longueur += octets.length;
    for (final octet in octets) {
      _bloc[_remplissage++] = octet;
      if (_remplissage == 64) {
        _traiterBloc();
        _remplissage = 0;
      }
    }
  }

  /// Termine le calcul et renvoie l'empreinte en 64 hexadécimaux minuscules.
  String terminer() {
    if (_termine) {
      throw StateError('Empreinte déjà terminée');
    }
    _termine = true;
    final longueurBits = _longueur * 8;
    // Bourrage : un bit à 1, des zéros, puis la longueur sur 64 bits.
    _bloc[_remplissage++] = 0x80;
    if (_remplissage > 56) {
      _bloc.fillRange(_remplissage, 64, 0);
      _traiterBloc();
      _remplissage = 0;
    }
    _bloc.fillRange(_remplissage, 56, 0);
    for (var i = 0; i < 8; i++) {
      // Décalages successifs (pas de `>> 56` d'un coup : reste correct même
      // là où les entiers ne font que 53 bits).
      _bloc[63 - i] = (longueurBits ~/ _puissance256(i)) & 0xff;
    }
    _traiterBloc();
    final texte = StringBuffer();
    for (final mot in _etat) {
      texte.write(mot.toRadixString(16).padLeft(8, '0'));
    }
    return texte.toString();
  }

  static int _puissance256(int exposant) {
    var resultat = 1;
    for (var i = 0; i < exposant; i++) {
      resultat *= 256;
    }
    return resultat;
  }

  void _traiterBloc() {
    final w = _mots;
    for (var t = 0; t < 16; t++) {
      w[t] =
          (_bloc[t * 4] << 24) |
          (_bloc[t * 4 + 1] << 16) |
          (_bloc[t * 4 + 2] << 8) |
          _bloc[t * 4 + 3];
    }
    for (var t = 16; t < 64; t++) {
      final s0 =
          _rotationDroite(w[t - 15], 7) ^
          _rotationDroite(w[t - 15], 18) ^
          (w[t - 15] >> 3);
      final s1 =
          _rotationDroite(w[t - 2], 17) ^
          _rotationDroite(w[t - 2], 19) ^
          (w[t - 2] >> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & _masque32;
    }
    var a = _etat[0];
    var b = _etat[1];
    var c = _etat[2];
    var d = _etat[3];
    var e = _etat[4];
    var f = _etat[5];
    var g = _etat[6];
    var h = _etat[7];
    for (var t = 0; t < 64; t++) {
      final grandS1 =
          _rotationDroite(e, 6) ^
          _rotationDroite(e, 11) ^
          _rotationDroite(e, 25);
      final choix = (e & f) ^ ((~e & _masque32) & g);
      final t1 = (h + grandS1 + choix + _k[t] + w[t]) & _masque32;
      final grandS0 =
          _rotationDroite(a, 2) ^
          _rotationDroite(a, 13) ^
          _rotationDroite(a, 22);
      final majorite = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (grandS0 + majorite) & _masque32;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & _masque32;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _masque32;
    }
    _etat[0] = (_etat[0] + a) & _masque32;
    _etat[1] = (_etat[1] + b) & _masque32;
    _etat[2] = (_etat[2] + c) & _masque32;
    _etat[3] = (_etat[3] + d) & _masque32;
    _etat[4] = (_etat[4] + e) & _masque32;
    _etat[5] = (_etat[5] + f) & _masque32;
    _etat[6] = (_etat[6] + g) & _masque32;
    _etat[7] = (_etat[7] + h) & _masque32;
  }
}

/// Empreinte SHA-256 de [octets], en 64 hexadécimaux minuscules.
String calculerSha256(List<int> octets) =>
    (CalculEmpreinteSha256()..ajouter(octets)).terminer();
