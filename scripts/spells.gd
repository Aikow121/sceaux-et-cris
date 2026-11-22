class_name Spells
extends RefCounted
## Liste des sorts. Le « mot » est une suggestion : chaque joueur enregistre
## dans son grimoire vocal le mot qu'il veut prononcer.

const LIST := [
	{"id": "fireball", "word": "Ignis", "name": "Boule de feu", "cooldown": 1.2,
		"desc": "Projectile explosif. Tenez la voyelle (« Igniiiis ») pour la grossir."},
	{"id": "shield", "word": "Aegis", "name": "Bouclier", "cooldown": 6.0,
		"desc": "Bulle qui bloque dégâts et malédictions pendant 3 s."},
	{"id": "dash", "word": "Ventus", "name": "Bourrasque", "cooldown": 3.0,
		"desc": "Vous propulse là où vous regardez."},
	{"id": "helium", "word": "Hélium", "name": "Hélium", "cooldown": 5.0,
		"desc": "Malédiction : la voix de la cible devient suraiguë (15 s)."},
	{"id": "swap", "word": "Mutatio", "name": "Échange de voix", "cooldown": 8.0,
		"desc": "Malédiction : vous et la cible échangez vos voix (20 s)."},
]

const WHISPER_MAX := 0.3   # volume max pour la règle « Chuchotements »

const MISFIRES := ["chicken", "backfire", "fish", "helium_self"]
const MISFIRE_TEXT := {
	"chicken": "Sort raté… vous êtes une poule !",
	"backfire": "Sort raté… ça vous explose au visage !",
	"fish": "Sort raté… vous lancez un poisson.",
	"helium_self": "Sort raté… votre voix part dans les aigus !",
}


static func get_def(id: String) -> Dictionary:
	for s in LIST:
		if s.id == id:
			return s
	return {}


## Puissance d'un sort selon la durée parlée (voyelle tenue) et le volume.
static func power_from_voice(duration: float, level: float) -> float:
	var p := clampf(0.7 + (duration - 0.45) * 0.9, 0.7, 3.0)
	return p * lerpf(0.8, 1.25, clampf(level, 0.0, 1.0))


## Règles loufoques tirées au sort à chaque manche : id -> [titre, description]
const RULES := {
	"normal": ["Règles normales", "Que le meilleur magicien gagne."],
	"chuchotements": ["Chuchotements", "Seuls les sorts MURMURÉS marchent. Criez et c'est raté !"],
	"opera": ["Opéra", "Chantez ! Tenez la note : sort court = raté, sort long = énorme."],
	"maudit": ["Grimoire maudit", "Les sorts sont mélangés en secret ! Quel mot fait quoi ?"],
	"lune": ["Basse gravité", "Gravité lunaire : les explosions envoient TRÈS loin."],
	"poulailler": ["Poulailler", "Tout le monde commence en poule pendant 20 secondes."],
}

const MODES := {
	"bataille": ["Bataille", "Le plus d'éliminations gagne la manche."],
	"roi": ["Roi du silence", "Prenez la couronne et gardez-la… SANS PARLER. 1 point par seconde."],
}
