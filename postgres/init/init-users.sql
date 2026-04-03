
CREATE EXTENSION IF NOT EXISTS dblink;

-- =============================================================================
-- CRÉATION DE LA BASE (SAFE DOCKER + MANUEL)
-- =============================================================================
-- IMPORTANT :
-- - Fonctionne si exécuté manuellement
-- - Ignoré si Docker a déjà créé la base
-- =============================================================================

DO
$$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_database WHERE datname = 'opencapture_edissyum'
   ) THEN
      PERFORM dblink_exec(
         'dbname=postgres',
         'CREATE DATABASE opencapture_edissyum OWNER edissyum'
      );
   END IF;
END
$$;

-- =====================================================================================
-- FICHIER : init-users.sql
-- =====================================================================================
-- RÔLE DU FICHIER
-- -------------------------------------------------------------------------------------
-- Ce script initialise les rôles et utilisateurs PostgreSQL nécessaires à l'application
-- OpenCapture / Edissyum.
--
-- OBJECTIFS
-- -------------------------------------------------------------------------------------
-- 1. Garantir l'existence du rôle technique postgres.
-- 2. Créer plusieurs rôles métier / techniques réutilisables.
-- 3. Créer l'utilisateur applicatif edissyum.
-- 4. Affecter edissyum aux rôles nécessaires.
-- 5. Donner les droits sur la base, le schéma, les tables et les séquences.
-- 6. Préparer aussi les droits par défaut pour les futurs objets.
--
-- PHILOSOPHIE DE SÉCURITÉ
-- -------------------------------------------------------------------------------------
-- On évite de tout attribuer directement à l'utilisateur applicatif.
-- On crée plutôt des rôles de groupe :
--
-- - role_db_connect     : droit de se connecter à la base
-- - role_schema_usage   : droit d'utiliser le schéma public
-- - role_app_rw         : lecture / écriture sur les tables
-- - role_app_seq        : usage des séquences
-- - role_app_admin      : rôle de regroupement applicatif
--
-- Ensuite l'utilisateur edissyum reçoit role_app_admin.
--
-- AVANTAGE
-- -------------------------------------------------------------------------------------
-- Cette méthode est plus propre, plus lisible et plus maintenable.
-- Si demain un autre utilisateur applicatif doit avoir les mêmes droits,
-- il suffira de lui attribuer role_app_admin.
--
-- IMPORTANT
-- -------------------------------------------------------------------------------------
-- Ce script est conçu pour être idempotent autant que possible :
-- - il vérifie l'existence des rôles avant de les créer ;
-- - il remet à jour les mots de passe ;
-- - il rejoue les GRANT sans danger.
--
-- NOTE IMPORTANTE SUR DOCKER
-- -------------------------------------------------------------------------------------
-- Si ce fichier est monté dans /docker-entrypoint-initdb.d/, PostgreSQL ne l'exécutera
-- automatiquement qu'au tout premier démarrage d'un volume de données vide.
-- Si la base existe déjà, il faudra l'exécuter manuellement avec psql.
-- =====================================================================================


-- =====================================================================================
-- 1. SÉCURISATION / NORMALISATION DU RÔLE edissyum
-- =====================================================================================
-- Dans l'image officielle PostgreSQL, le rôle edissyum existe normalement déjà.
-- On garde quand même cette logique défensive pour les environnements atypiques.
DO
$$
BEGIN
   IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'edissyum'
   ) THEN
      CREATE ROLE edissyum
         WITH LOGIN
              SUPERUSER
              CREATEDB
              CREATEROLE
              PASSWORD 'edissyum';
   END IF;
END
$$;

-- On remet explicitement le mot de passe du rôle edissyum.
-- Cela permet d'avoir un état connu sur les environnements de test.
ALTER ROLE edissyum WITH PASSWORD 'edissyum';


-- =====================================================================================
-- 2. CRÉATION DES RÔLES DE GROUPE
-- =====================================================================================
-- Ces rôles ne sont pas destinés à se connecter directement.
-- Ce sont des rôles "porteurs de droits".
--
-- NOLOGIN = le rôle existe uniquement pour regrouper des privilèges.
-- Un utilisateur réel peut ensuite hériter de ces privilèges via GRANT role TO user.
DO
$$
BEGIN
   IF NOT EXISTS (
      SELECT 1 FROM pg_roles WHERE rolname = 'role_db_connect'
   ) THEN
      CREATE ROLE role_db_connect NOLOGIN;
   END IF;

   IF NOT EXISTS (
      SELECT 1 FROM pg_roles WHERE rolname = 'role_schema_usage'
   ) THEN
      CREATE ROLE role_schema_usage NOLOGIN;
   END IF;

   IF NOT EXISTS (
      SELECT 1 FROM pg_roles WHERE rolname = 'role_app_rw'
   ) THEN
      CREATE ROLE role_app_rw NOLOGIN;
   END IF;

   IF NOT EXISTS (
      SELECT 1 FROM pg_roles WHERE rolname = 'role_app_seq'
   ) THEN
      CREATE ROLE role_app_seq NOLOGIN;
   END IF;

   IF NOT EXISTS (
      SELECT 1 FROM pg_roles WHERE rolname = 'role_app_admin'
   ) THEN
      CREATE ROLE role_app_admin NOLOGIN;
   END IF;
END
$$;


-- =====================================================================================
-- 3. CRÉATION DE L'UTILISATEUR postgres
-- =====================================================================================
-- Cet utilisateur est le compte que l'application doit utiliser pour se connecter.
-- Il ne doit pas être SUPERUSER.
DO
$$
BEGIN
   IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'postgres'
   ) THEN
      CREATE ROLE postgres
         WITH LOGIN
              PASSWORD 'postgres'
              INHERIT;
   END IF;
END
$$;

-- On remet explicitement son mot de passe pour uniformiser l'état.
ALTER ROLE postgres WITH PASSWORD 'postgres';


-- =====================================================================================
-- 4. AFFECTATION DES RÔLES À L'UTILISATEUR edissyum
-- =====================================================================================
-- On rattache l'utilisateur applicatif au rôle de regroupement principal.
GRANT role_app_admin TO edissyum;

-- On rattache aussi role_app_admin aux sous-rôles fonctionnels.
-- Ainsi edissyum hérite indirectement de tous les droits applicatifs.
GRANT role_db_connect TO role_app_admin;
GRANT role_schema_usage TO role_app_admin;
GRANT role_app_rw TO role_app_admin;
GRANT role_app_seq TO role_app_admin;


-- =====================================================================================
-- 5. DROITS SUR LA BASE DE DONNÉES
-- =====================================================================================
-- Ce droit permet d'ouvrir une session sur la base cible.
GRANT CONNECT ON DATABASE opencapture_edissyum TO role_db_connect;

-- En option, on peut aussi autoriser TEMP si l'application crée des tables temporaires.
GRANT TEMP ON DATABASE opencapture_edissyum TO role_db_connect;


-- =====================================================================================
-- 6. DROITS SUR LE SCHÉMA public
-- =====================================================================================
-- USAGE permet d'accéder au schéma.
GRANT USAGE ON SCHEMA public TO role_schema_usage;

-- CREATE sur le schéma public permet à l'application de créer des objets.
-- À conserver seulement si ton application crée réellement des tables, vues, fonctions,
-- etc. Sinon, tu peux commenter la ligne ci-dessous pour être plus strict.
GRANT CREATE ON SCHEMA public TO role_app_admin;


-- =====================================================================================
-- 7. DROITS SUR LES TABLES EXISTANTES
-- =====================================================================================
-- On donne les droits CRUD complets via le rôle role_app_rw.
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON ALL TABLES IN SCHEMA public
TO role_app_rw;


-- =====================================================================================
-- 8. DROITS SUR LES SÉQUENCES EXISTANTES
-- =====================================================================================
-- Ces droits sont souvent nécessaires pour les colonnes SERIAL / BIGSERIAL.
GRANT USAGE, SELECT, UPDATE
ON ALL SEQUENCES IN SCHEMA public
TO role_app_seq;


-- =====================================================================================
-- 9. DROITS PAR DÉFAUT POUR LES FUTURS OBJETS
-- =====================================================================================
-- Ces ALTER DEFAULT PRIVILEGES ne s'appliquent qu'aux objets créés ensuite
-- par le rôle qui exécute cette commande.
--
-- Si tu exécutes ce script en tant que postgres, alors les futurs objets créés
-- par postgres dans le schéma public transmettront automatiquement ces droits.

-- Futures tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON TABLES TO role_app_rw;

-- Futures séquences
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT, UPDATE
ON SEQUENCES TO role_app_seq;

-- Futures fonctions si nécessaire
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT EXECUTE
ON FUNCTIONS TO role_app_admin;


-- =====================================================================================
-- 10. COMMENTAIRES DE DOCUMENTATION SUR LES RÔLES
-- =====================================================================================
COMMENT ON ROLE role_db_connect IS
'Rôle de groupe : autorise la connexion à la base opencapture_edissyum.';

COMMENT ON ROLE role_schema_usage IS
'Rôle de groupe : autorise l usage du schéma public.';

COMMENT ON ROLE role_app_rw IS
'Rôle de groupe : autorise les opérations de lecture / écriture sur les tables applicatives.';

COMMENT ON ROLE role_app_seq IS
'Rôle de groupe : autorise l usage des séquences PostgreSQL.';

COMMENT ON ROLE role_app_admin IS
'Rôle de regroupement principal pour les privilèges applicatifs Edissyum.';

COMMENT ON ROLE edissyum IS
'Utilisateur applicatif principal utilisé par OpenCapture / Edissyum.';

COMMENT ON ROLE postgres IS
'Compte administrateur PostgreSQL utilisé pour l administration de l instance.';


-- =====================================================================================
-- 11. VÉRIFICATIONS CONSEILLÉES APRÈS EXÉCUTION
-- =====================================================================================
-- Commandes utiles à lancer ensuite dans psql :
--
-- \du
-- \l
-- \dn+
--
-- Et pour vérifier les droits :
-- \dp
-- =====================================================================================