-- =====================================================================
--  CARNET CREATY — schéma de la base de données (SQLite)
--  Associés : Joram & Plam's · Kinshasa
--
--  Ce fichier est la référence du schéma. Le carnet (carnet.html)
--  crée exactement ces tables tout seul au premier lancement.
--  Il peut aussi servir à recréer la base avec n'importe quel outil
--  SQLite (DB Browser for SQLite, sqlite3, etc.) :
--      sqlite3 creaty-carnet.db < schema.sql
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
--  TABLES
-- ---------------------------------------------------------------------

-- Les deux associés de CREATY
CREATE TABLE IF NOT EXISTS associes (
  id   INTEGER PRIMARY KEY,
  nom  TEXT NOT NULL UNIQUE
);

-- Types de dépenses (Transport, Achat de cadres, Achat de posters, Autre…)
CREATE TABLE IF NOT EXISTS categories_depense (
  id   INTEGER PRIMARY KEY,
  nom  TEXT NOT NULL UNIQUE COLLATE NOCASE
);

-- Commandes des clients
CREATE TABLE IF NOT EXISTS commandes (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  date_commande   TEXT    NOT NULL DEFAULT (date('now')),
  client          TEXT    NOT NULL,
  telephone       TEXT,
  article         TEXT    NOT NULL,                -- nom du poster / produit
  format          TEXT,                            -- A5, A4, A3, A2, A1, Magazine…
  quantite        INTEGER NOT NULL DEFAULT 1  CHECK (quantite > 0),
  prix_unitaire   REAL    NOT NULL DEFAULT 0  CHECK (prix_unitaire >= 0),
  devise          TEXT    NOT NULL DEFAULT 'FC' CHECK (devise IN ('FC','USD')),
  statut          TEXT    NOT NULL DEFAULT 'En attente'
                  CHECK (statut IN ('En attente','En cours','Livrée','Annulée')),
  lieu_livraison  TEXT,
  associe_id      INTEGER REFERENCES associes(id), -- qui gère la commande
  note            TEXT,
  cree_le         TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Dépenses personnelles : ce que chaque associé a payé pour CREATY
CREATE TABLE IF NOT EXISTS depenses (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  date_depense  TEXT    NOT NULL DEFAULT (date('now')),
  associe_id    INTEGER NOT NULL REFERENCES associes(id),           -- qui a payé
  categorie_id  INTEGER NOT NULL REFERENCES categories_depense(id),
  description   TEXT    NOT NULL,
  montant       REAL    NOT NULL CHECK (montant > 0),
  devise        TEXT    NOT NULL DEFAULT 'FC' CHECK (devise IN ('FC','USD')),
  commande_id   INTEGER REFERENCES commandes(id) ON DELETE SET NULL, -- facultatif
  cree_le       TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Recettes de l'entreprise : l'argent qui rentre
CREATE TABLE IF NOT EXISTS recettes (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  date_recette   TEXT    NOT NULL DEFAULT (date('now')),
  associe_id     INTEGER NOT NULL REFERENCES associes(id),          -- qui a encaissé
  description    TEXT    NOT NULL,
  montant        REAL    NOT NULL CHECK (montant > 0),
  devise         TEXT    NOT NULL DEFAULT 'FC' CHECK (devise IN ('FC','USD')),
  mode_paiement  TEXT    NOT NULL DEFAULT 'Cash'
                 CHECK (mode_paiement IN ('Cash','Mobile Money','Virement','Autre')),
  commande_id    INTEGER REFERENCES commandes(id) ON DELETE SET NULL, -- facultatif
  cree_le        TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Réglages du carnet (taux du dollar, date du dernier export…)
CREATE TABLE IF NOT EXISTS parametres (
  cle     TEXT PRIMARY KEY,
  valeur  TEXT
);

CREATE INDEX IF NOT EXISTS idx_commandes_date ON commandes(date_commande);
CREATE INDEX IF NOT EXISTS idx_depenses_date  ON depenses(date_depense);
CREATE INDEX IF NOT EXISTS idx_recettes_date  ON recettes(date_recette);
CREATE INDEX IF NOT EXISTS idx_recettes_cmd   ON recettes(commande_id);

-- ---------------------------------------------------------------------
--  DONNÉES DE DÉPART
-- ---------------------------------------------------------------------

INSERT OR IGNORE INTO associes (id, nom) VALUES
  (1, 'Joram'),
  (2, 'Plam''s');

INSERT OR IGNORE INTO categories_depense (id, nom) VALUES
  (1, 'Transport'),
  (2, 'Achat de cadres'),
  (3, 'Achat de posters'),
  (4, 'Autre');

-- ---------------------------------------------------------------------
--  VUES (requêtes prêtes à l'emploi)
-- ---------------------------------------------------------------------

DROP VIEW IF EXISTS v_commandes;
DROP VIEW IF EXISTS v_depenses;
DROP VIEW IF EXISTS v_recettes;
DROP VIEW IF EXISTS v_bilan_mensuel;
DROP VIEW IF EXISTS v_soldes_associes;

-- Commandes avec total, montant déjà encaissé et reste à payer
CREATE VIEW v_commandes AS
SELECT x.*, x.total - x.encaisse AS reste
FROM (
  SELECT c.*,
         c.quantite * c.prix_unitaire AS total,
         a.nom AS gere_par,
         COALESCE((SELECT SUM(r.montant) FROM recettes r
                   WHERE r.commande_id = c.id AND r.devise = c.devise), 0) AS encaisse
  FROM commandes c
  LEFT JOIN associes a ON a.id = c.associe_id
) x;

-- Dépenses avec le nom de l'associé et de la catégorie
CREATE VIEW v_depenses AS
SELECT d.*, a.nom AS paye_par, k.nom AS categorie
FROM depenses d
JOIN associes a           ON a.id = d.associe_id
JOIN categories_depense k ON k.id = d.categorie_id;

-- Recettes avec le nom de l'associé et du client
CREATE VIEW v_recettes AS
SELECT r.*, a.nom AS encaisse_par, c.client AS client
FROM recettes r
JOIN associes a       ON a.id = r.associe_id
LEFT JOIN commandes c ON c.id = r.commande_id;

-- Bilan par mois et par devise : recettes, dépenses, bénéfice
CREATE VIEW v_bilan_mensuel AS
SELECT mois, devise,
       SUM(CASE WHEN t = 'R' THEN montant ELSE 0 END)        AS recettes,
       SUM(CASE WHEN t = 'D' THEN montant ELSE 0 END)        AS depenses,
       SUM(CASE WHEN t = 'R' THEN montant ELSE -montant END) AS benefice
FROM (
  SELECT strftime('%Y-%m', date_recette) AS mois, devise, montant, 'R' AS t FROM recettes
  UNION ALL
  SELECT strftime('%Y-%m', date_depense), devise, montant, 'D' FROM depenses
)
GROUP BY mois, devise
ORDER BY mois DESC, devise;

-- Ce que chaque associé a encaissé / dépensé.
-- Solde négatif = l'associé a payé de sa poche, CREATY lui doit cette somme.
CREATE VIEW v_soldes_associes AS
SELECT a.nom AS associe, x.devise,
       SUM(CASE WHEN x.t = 'R' THEN x.montant ELSE 0 END)          AS encaisse,
       SUM(CASE WHEN x.t = 'D' THEN x.montant ELSE 0 END)          AS depense,
       SUM(CASE WHEN x.t = 'R' THEN x.montant ELSE -x.montant END) AS solde
FROM associes a
JOIN (
  SELECT associe_id, devise, montant, 'R' AS t FROM recettes
  UNION ALL
  SELECT associe_id, devise, montant, 'D' FROM depenses
) x ON x.associe_id = a.id
GROUP BY a.id, x.devise;

-- ---------------------------------------------------------------------
--  EXEMPLES DE REQUÊTES
-- ---------------------------------------------------------------------
-- Dépenses par type :
--   SELECT categorie, devise, SUM(montant) FROM v_depenses GROUP BY categorie, devise;
-- Commandes pas encore payées :
--   SELECT * FROM v_commandes WHERE statut <> 'Annulée' AND reste > 0;
-- Meilleurs clients :
--   SELECT client, SUM(total) FROM v_commandes WHERE statut <> 'Annulée' GROUP BY client ORDER BY 2 DESC;
