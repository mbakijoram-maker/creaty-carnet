# Carnet CREATY

Carnet de bord interne de JP CREATY (Joram & Plam's) : commandes, dépenses personnelles par type et recettes de l'entreprise.

- `index.html` : l'application (base SQLite qui tourne dans le navigateur avec sql.js).
- `schema.sql` : le schéma de la base (commandes et leurs lignes de posters, dépenses, recettes, vues).
- `firebase.json`, `firestore.rules`, `.firebaserc` : la partie en ligne (projet Firebase `creaty-carnet-jp`).

## Données en ligne

Le carnet est enregistré en ligne (Firestore, document `carnets/creaty`) : mêmes données sur tous les
navigateurs et téléphones. Pas de mot de passe : chaque navigateur se connecte tout seul (compte anonyme Firebase), donc toute personne qui a le lien peut voir et modifier le carnet.
Chaque appareil garde aussi une copie locale ; sans connexion, les fiches partent dès que la connexion revient.
Si les deux associés modifient en même temps, les changements sont fusionnés.

Un ancien carnet resté dans un navigateur (avant la mise en ligne) est ajouté automatiquement au carnet en ligne
la première fois qu'on ouvre le carnet dans ce navigateur.

Redéployer les règles : `firebase deploy --only firestore:rules`.
