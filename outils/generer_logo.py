"""Génère le logo de Bibliothèque perso (PNG 1024 px et icône Windows multi-tailles).

Usage : python -I outils/generer_logo.py
Sorties : assets/logo/logo_1024.png, assets/logo/logo.ico,
windows/runner/resources/app_icon.ico (icône de l'exécutable).

Dessin : carré arrondi indigo en dégradé, livre ouvert clair, bulle de dialogue
(rappel des mangas) au-dessus des pages, et marque-page orange.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

RACINE = Path(__file__).resolve().parent.parent
TAILLE = 1024
ECHELLE = 4  # dessin en haute définition puis réduction (bords lisses)


def degrade_vertical(taille, haut, bas):
    img = Image.new("RGB", (taille, taille), haut)
    px = img.load()
    for y in range(taille):
        t = y / (taille - 1)
        couleur = tuple(round(haut[i] + (bas[i] - haut[i]) * t) for i in range(3))
        for x in range(taille):
            px[x, y] = couleur
    return img


def dessiner():
    t = TAILLE * ECHELLE
    s = lambda v: round(v * ECHELLE)  # noqa: E731 (coordonnées en px de 1024)

    fond = degrade_vertical(t, (63, 81, 181), (40, 30, 110)).convert("RGBA")
    masque = Image.new("L", (t, t), 0)
    ImageDraw.Draw(masque).rounded_rectangle((0, 0, t - 1, t - 1), radius=s(220), fill=255)
    logo = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    logo.paste(fond, (0, 0), masque)

    d = ImageDraw.Draw(logo)
    clair = (248, 246, 240, 255)
    ombre_page = (214, 210, 200, 255)

    # Ombre douce du livre.
    ombre = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    ImageDraw.Draw(ombre).polygon(
        [(s(180), s(560)), (s(512), s(640)), (s(844), s(560)), (s(844), s(820)),
         (s(512), s(900)), (s(180), s(820))], fill=(0, 0, 0, 90))
    logo.alpha_composite(ombre.filter(ImageFilter.GaussianBlur(s(18))))
    d = ImageDraw.Draw(logo)

    # Livre ouvert : deux pages en trapèze.
    d.polygon([(s(170), s(530)), (s(500), s(600)), (s(500), s(860)), (s(170), s(790))], fill=clair)
    d.polygon([(s(854), s(530)), (s(524), s(600)), (s(524), s(860)), (s(854), s(790))], fill=clair)
    # Tranche centrale.
    d.polygon([(s(500), s(600)), (s(524), s(600)), (s(524), s(860)), (s(500), s(860))], fill=ombre_page)
    # Lignes de texte sur les pages.
    for i in range(4):
        y = 640 + i * 45
        d.line([(s(215), s(y - 30 + i * 0)), (s(455), s(y + 22))], fill=ombre_page, width=s(14))
        d.line([(s(809), s(y - 30)), (s(569), s(y + 22))], fill=ombre_page, width=s(14))

    # Bulle de dialogue au-dessus du livre.
    d.ellipse((s(300), s(150), s(724), s(470)), fill=clair)
    d.polygon([(s(430), s(440)), (s(512), s(440)), (s(450), s(540))], fill=clair)
    # Trois points dans la bulle.
    bleu = (63, 81, 181, 255)
    for x in (420, 512, 604):
        d.ellipse((s(x - 32), s(278), s(x + 32), s(342)), fill=bleu)

    # Marque-page orange qui dépasse de la page droite.
    orange = (255, 152, 0, 255)
    d.polygon([(s(700), s(560)), (s(760), s(573)), (s(760), s(900)), (s(730), s(870)), (s(700), s(890))],
              fill=orange)

    return logo.resize((TAILLE, TAILLE), Image.LANCZOS)


def main():
    logo = dessiner()
    dossier = RACINE / "assets" / "logo"
    dossier.mkdir(parents=True, exist_ok=True)
    logo.save(dossier / "logo_1024.png")
    tailles = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    logo.save(dossier / "logo.ico", sizes=tailles)
    logo.save(RACINE / "windows" / "runner" / "resources" / "app_icon.ico", sizes=tailles)
    print("ok")


if __name__ == "__main__":
    main()
