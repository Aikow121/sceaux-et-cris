# Sceaux & Cris — prototype (Godot 4)

Party game de magiciens entre amis, en première personne :
- **les sorts se lancent à la voix** : maintenez le clic droit, dites le mot, relâchez ;
- **tenir la voyelle charge le sort** (« Igniiiiis » = énorme boule de feu) ;
- **mal prononcé = sort raté** : poule, poisson, explosion au visage ou voix d'hélium ;
- **chat vocal de proximité** : on entend les autres selon la distance… et ils vous entendent incanter ;
- **pièges dessinés** : visez une surface, appuyez sur T et dessinez un sceau d'un trait ;
- **malédictions de voix** : Hélium (voix suraiguë) et Échange de voix (votre voix sort du corps de l'autre) ;
- **replay du « dernier mot »** : à votre mort, vous réentendez l'incantation de votre tueur puis vos derniers mots.

## Lancer
1. Godot **4.3 ou plus récent** (version standard).
2. *Importer* → `project.godot` → **F5**.
3. Autorisez l'accès au micro si le système le demande.

## Première chose à faire : le Grimoire vocal
Dans le menu, ouvrez **Grimoire vocal**. Pour chaque sort, maintenez « Enregistrer », dites le mot,
relâchez — **2 fois par sort**. Vous pouvez choisir vos propres mots (évitez qu'ils se ressemblent).
Le bouton **Tester** montre si votre mot est reconnu. Le grimoire est propre à chaque joueur
(enregistré dans `user://grimoire_vocal.json`).

Sans micro ou sans grimoire, les touches **1 à 5** lancent les sorts (maintenir pour charger).

## Sorts
| Sort | Mot suggéré | Effet |
|---|---|---|
| Boule de feu | Ignis | Projectile explosif, recul. Tenir la voyelle = plus gros |
| Bouclier | Aegis | Bloque dégâts et malédictions 3 s |
| Bourrasque | Ventus | Vous propulse là où vous regardez |
| Hélium | Hélium | Voix de la cible suraiguë 15 s |
| Échange de voix | Mutatio | Vous et la cible échangez vos voix 20 s |

## Pièges (touche T, sur la surface visée à moins de 6 m)
| Dessin | Piège |
|---|---|
| Pentacle (étoile en un trait) | Explosion |
| Triangle | Catapulte |
| Carré | Cage (immobilise 3,5 s) |
| Cercle | Transforme en poule |

Dessin trop raté (< 80 %) : il vous explose au nez. Tout le monde voit vos dessins (en transparent),
vous voyez les vôtres en clair. 3 pièges max par joueur. La fosse de lave au centre tue
(l'élimination revient au dernier qui vous a touché).

## Commandes
ZQSD/WASD bouger · Maj courir · Espace sauter · **Clic droit ou V maintenu : incanter** ·
1-5 sorts au clavier · **T : dessiner un piège** · Tab scores · Échap libérer la souris.

## Multijoueur
« Héberger » ouvre le port UDP **7777** ; les autres cliquent sur « Rejoindre » avec l'IP de l'hôte
(IP locale en réseau local ; par Internet, rediriger le port UDP 7777 sur la box de l'hôte).
Les mannequins d'entraînement servent de cibles.

## Comment ça marche (technique)
- `scripts/voice.gd` : micro via un bus muet « Micro » + `AudioEffectCapture`, rééchantillonnage
  16 kHz, compression µ-law, envoi seulement quand on parle, lecture en `AudioStreamPlayer3D`
  (proximité). Hélium = effet `AudioEffectPitchShift` sur le bus de voix du joueur.
- `scripts/spell_recognizer.gd` : reconnaissance des mots **propre à chaque joueur**
  (MFCC + DTW), sans module externe. Testée sur voix synthétiques : mots normaux, bruités,
  voyelle tenue et voix différente reconnus, mots hors grimoire rejetés (→ sort raté).
- `scripts/gesture.gd` : reconnaissance des dessins (« $1 Unistroke Recognizer »).
- `scripts/main.gd` : réseau ENet, le serveur décide des touches, dégâts, états et morts.
- `scripts/wizard.gd` : le magicien (déplacement, incantation, états, voix).

## Limites connues du prototype
- La reconnaissance vocale est simple : elle marche bien avec vos propres enregistrements,
  dans une pièce calme. Réenregistrez un sort s'il rate trop souvent.
- La voix n'est pas compressée comme sur Discord (~128 kbit/s par joueur qui parle) : parfait en
  réseau local, correct par Internet à 4-6 joueurs.
- Les pièges posés avant l'arrivée d'un joueur ne lui sont pas envoyés.
- Pas encore de sons ni de vrais modèles 3D.
