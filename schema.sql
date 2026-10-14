-- =====================================================================
--  CARNET CREATY — schéma de la base de données (SQLite)
--  Associés : Joram & Plam's · Kinshasa
--
--  Référence du schéma. Le carnet (index.html) crée exactement ces tables
--  tout seul au premier lancement, et met à jour les anciens carnets.
--  Une commande contient une ou plusieurs lignes (lignes_commande) :
--  chaque ligne = un poster, son format, sans ou avec cadre, quantité, prix.
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
--  TABLES
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS associes (
  id   INTEGER PRIMARY KEY,
  nom  TEXT NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS categories_depense (
  id   INTEGER PRIMARY KEY,
  nom  TEXT NOT NULL UNIQUE COLLATE NOCASE
);
CREATE TABLE IF NOT EXISTS commandes (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  date_commande   TEXT    NOT NULL DEFAULT (date('now')),
  client          TEXT    NOT NULL,
  telephone       TEXT,
  statut          TEXT    NOT NULL DEFAULT 'En attente'
                  CHECK (statut IN ('En attente','En cours','Livrée','Annulée')),
  lieu_livraison  TEXT,
  associe_id      INTEGER REFERENCES associes(id),
  note            TEXT,
  cree_le         TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS lignes_commande (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  commande_id    INTEGER NOT NULL REFERENCES commandes(id) ON DELETE CASCADE,
  article        TEXT    NOT NULL,
  format         TEXT,
  avec_cadre     INTEGER NOT NULL DEFAULT 0 CHECK (avec_cadre IN (0, 1)),
  quantite       INTEGER NOT NULL DEFAULT 1 CHECK (quantite > 0),
  prix_unitaire  REAL    NOT NULL DEFAULT 0 CHECK (prix_unitaire >= 0),
  devise         TEXT    NOT NULL DEFAULT 'FC' CHECK (devise IN ('FC','USD'))
);
CREATE TABLE IF NOT EXISTS depenses (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  date_depense  TEXT    NOT NULL DEFAULT (date('now')),
  associe_id    INTEGER NOT NULL REFERENCES associes(id),
  categorie_id  INTEGER NOT NULL REFERENCES categories_depense(id),
  description   TEXT    NOT NULL,
  montant       REAL    NOT NULL CHECK (montant > 0),
  devise        TEXT    NOT NULL DEFAULT 'FC' CHECK (devise IN ('FC','USD')),
  commande_id   INTEGER REFERENCES commandes(id) ON DELETE SET NULL,
  cree_le       TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS recettes (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  date_recette   TEXT    NOT NULL DEFAULT (date('now')),
  associe_id     INTEGER NOT NULL REFERENCES associes(id),
  description    TEXT    NOT NULL,
  montant        REAL    NOT NULL CHECK (montant > 0),
  devise         TEXT    NOT NULL DEFAULT 'FC' CHECK (devise IN ('FC','USD')),
  mode_paiement  TEXT    NOT NULL DEFAULT 'Cash'
                 CHECK (mode_paiement IN ('Cash','Mobile Money','Virement','Autre')),
  commande_id    INTEGER REFERENCES commandes(id) ON DELETE SET NULL,
  cree_le        TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS parametres (
  cle     TEXT PRIMARY KEY,
  valeur  TEXT
);
CREATE INDEX IF NOT EXISTS idx_commandes_date ON commandes(date_commande);
CREATE INDEX IF NOT EXISTS idx_lignes_cmd     ON lignes_commande(commande_id);
CREATE INDEX IF NOT EXISTS idx_depenses_date  ON depenses(date_depense);
CREATE INDEX IF NOT EXISTS idx_recettes_date  ON recettes(date_recette);
CREATE INDEX IF NOT EXISTS idx_recettes_cmd   ON recettes(commande_id);

-- ---------------------------------------------------------------------
--  DONNÉES DE DÉPART
-- ---------------------------------------------------------------------

INSERT OR IGNORE INTO associes (id, nom) VALUES (1, 'Joram'), (2, 'Plam''s');
INSERT OR IGNORE INTO categories_depense (id, nom) VALUES
  (1, 'Transport'), (2, 'Achat de cadres'), (3, 'Achat de posters'), (4, 'Autre');

-- ---------------------------------------------------------------------
--  VUES
-- ---------------------------------------------------------------------

DROP VIEW IF EXISTS v_commandes;
DROP VIEW IF EXISTS v_depenses;
DROP VIEW IF EXISTS v_recettes;
DROP VIEW IF EXISTS v_bilan_mensuel;
DROP VIEW IF EXISTS v_soldes_associes;

CREATE VIEW v_commandes AS
SELECT x.*, x.total_fc - x.paye_fc AS reste_fc, x.total_usd - x.paye_usd AS reste_usd
FROM (
  SELECT c.*, a.nom AS gere_par,
    (SELECT group_concat(l.quantite || ' × ' || l.article
              || COALESCE(' ' || l.format, '')
              || CASE WHEN l.avec_cadre = 1 THEN ' + cadre' ELSE '' END, ' ; ')
       FROM lignes_commande l WHERE l.commande_id = c.id) AS articles,
    COALESCE((SELECT SUM(l.quantite) FROM lignes_commande l WHERE l.commande_id = c.id), 0) AS nb_pieces,
    COALESCE((SELECT SUM(l.quantite * l.prix_unitaire) FROM lignes_commande l
              WHERE l.commande_id = c.id AND l.devise = 'FC'), 0) AS total_fc,
    COALESCE((SELECT SUM(l.quantite * l.prix_unitaire) FROM lignes_commande l
              WHERE l.commande_id = c.id AND l.devise = 'USD'), 0) AS total_usd,
    COALESCE((SELECT SUM(r.montant) FROM recettes r
              WHERE r.commande_id = c.id AND r.devise = 'FC'), 0) AS paye_fc,
    COALESCE((SELECT SUM(r.montant) FROM recettes r
              WHERE r.commande_id = c.id AND r.devise = 'USD'), 0) AS paye_usd
  FROM commandes c
  LEFT JOIN associes a ON a.id = c.associe_id
) x;
CREATE VIEW v_depenses AS
SELECT d.*, a.nom AS paye_par, k.nom AS categorie
FROM depenses d
JOIN associes a           ON a.id = d.associe_id
JOIN categories_depense k ON k.id = d.categorie_id;
CREATE VIEW v_recettes AS
SELECT r.*, a.nom AS encaisse_par, c.client AS client
FROM recettes r
JOIN associes a       ON a.id = r.associe_id
LEFT JOIN commandes c ON c.id = r.commande_id;
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
