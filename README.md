# Ghost Backup

Ghost Backup est un outil personnel de reconstruction d'un environnement
Arch Linux sur une installation existante ou une nouvelle machine.

Ce projet n'est ni une image disque ni un outil de sauvegarde de données
personnelles.

## Principes

- Les dotfiles existants restent la source de vérité.
- Le matériel est détecté automatiquement.
- Les incompatibilités sont signalées avant toute adaptation.
- Les opérations sensibles nécessitent une confirmation explicite.
- Aucune configuration personnelle n'est modifiée automatiquement.
- Les données personnelles et les secrets ne sont pas stockés ici.
- Le mode simulation est le comportement par défaut.
- Aucune désinstallation automatique de paquet n'est effectuée.

## Utilisation

```bash
./ghost.sh check
./ghost.sh plan
./ghost.sh verify
./ghost.sh install --dry-run
```

Le mode simulation est utilisé par défaut.

Pour lancer une installation réelle :

```bash
./ghost.sh install --apply
```

Cette dernière commande demande des confirmations avant les opérations
d'installation. Elle ne doit pas être utilisée sur la machine principale
pendant la phase de développement et de test.

## Prérequis

- Arch Linux
- Bash
- pacman
- Git
- yay pour les paquets AUR (installation possible par bootstrap)
- lspci (facultatif, paquet pciutils)

## Architecture

- `compatibility/` : détection matérielle et compatibilité
- `scripts/` : opérations de reconstruction
- `tests/` : tests automatisés

## Dotfiles

Ghost Backup utilise un dépôt dotfiles indépendant, situé par défaut dans :

```text
~/src/dotfiles
```

Il contient notamment les manifestes :

- `pacman-list.txt`
- `yay-list.txt`

Le chemin peut être personnalisé avec la variable `GHOST_DOTFILES_DIR`.

## Sécurité

- Aucun partitionnement ou formatage automatique.
- Aucune suppression automatique de fichiers personnels.
- Aucun écrasement automatique des dotfiles.
- Aucun secret ou identifiant personnel dans le dépôt.
- Les installations sont réalisées avec confirmation explicite.
