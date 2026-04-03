--
-- =============================================================================
-- FICHIER : 3.3.3.sql
-- =============================================================================
-- RÔLE DU FICHIER :
-- Ce script SQL prépare la base de données de monitoring utilisée pour suivre
-- les performances applicatives, les appels REST et les analyses de phase 2.
--
-- Il est compatible avec :
-- - PerfTracker.py
-- - RestPerf.py
-- - Phase2PerformanceAdvisor.py
-- - Phase2WorkPlan.py
--
-- COMMENT UTILISER CE FICHIER :
-- 1. Exécuter ce script sur la base PostgreSQL cible.
-- 2. Le script supprime les anciennes tables de monitoring si elles existent.
-- 3. Il recrée ensuite les tables avec le schéma final corrigé.
-- 4. À utiliser de préférence sur un environnement de test, de recette
--    ou lors d'une réinitialisation maîtrisée.
--
-- ATTENTION :
-- Ce script supprime les données existantes des tables concernées.
-- Il ne faut donc l'utiliser que si l'on accepte de réinitialiser
-- l'historique du monitoring.
--
-- FICHIERS QUI PEUVENT L’UTILISER DANS LE PROJET :
-- - PerfTracker.py
-- - RestPerf.py
-- - Phase2PerformanceAdvisor.py
-- - Phase2WorkPlan.py
-- - scripts d'initialisation base de données
--
-- TECHNOLOGIES / CONCEPTS UTILISÉS :
-- - PostgreSQL : système de gestion de base de données relationnelle
-- - DDL (Data Definition Language) : commandes SQL de création / suppression
--   de tables, index et contraintes
-- - JSONB : stockage structuré de données JSON dans PostgreSQL
-- - INDEX : accélèrent les recherches SQL
-- - FOREIGN KEY : garantit les liens entre tables
-- =============================================================================

-- =============================================================================
-- 2. TABLE PRINCIPALE : monitoring
-- =============================================================================
-- Cette table représente une exécution globale de monitoring.
--
-- Elle peut stocker :
-- - un suivi de traitement documentaire ;
-- - un appel REST suivi du début à la fin ;
-- - une analyse de capacité de phase 2 ;
-- - un plan de travail phase 2 ;
-- - un incident ou une erreur applicative.
--
-- IMPORTANT :
-- Cette structure est volontairement alignée sur les colonnes réellement
-- utilisées par le code Python observé, notamment :
-- - status
-- - module
-- - source
-- - filename
-- - token
-- - workflow_id
-- - creation_date
-- - start_date
-- - end_date
-- - elapsed_time
-- - document_ids
-- =============================================================================

-- =============================================================================
-- MIGRATION SAFE : AJOUT COLONNES MANQUANTES
-- =============================================================================

ALTER TABLE monitoring ADD COLUMN IF NOT EXISTS created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE monitoring ADD COLUMN IF NOT EXISTS start_date TIMESTAMP NULL;
ALTER TABLE monitoring ADD COLUMN IF NOT EXISTS message TEXT NULL;
ALTER TABLE monitoring ADD COLUMN IF NOT EXISTS result TEXT NULL;
ALTER TABLE monitoring ADD COLUMN IF NOT EXISTS mime_type VARCHAR(255) NULL;
ALTER TABLE monitoring ADD COLUMN IF NOT EXISTS worker_name VARCHAR(255) NULL;
ALTER TABLE monitoring ADD COLUMN IF NOT EXISTS host_name VARCHAR(255) NULL;
ALTER TABLE monitoring ADD COLUMN IF NOT EXISTS error_message TEXT NULL;
ALTER TABLE monitoring ADD COLUMN IF NOT EXISTS error_type VARCHAR(255) NULL;


COMMENT ON TABLE monitoring IS
'Table principale de monitoring. Chaque ligne représente une exécution globale suivie par PerfTracker, RestPerf ou les modules Phase 2.';

COMMENT ON COLUMN monitoring.id IS
'Identifiant technique unique de la ligne de monitoring.';
COMMENT ON COLUMN monitoring.creation_date IS
'Date de création logique du suivi. Cette colonne est attendue par certains UPDATE du code existant.';
COMMENT ON COLUMN monitoring.start_date IS
'Date et heure de début du traitement ou de l appel suivi.';
COMMENT ON COLUMN monitoring.end_date IS
'Date et heure de fin du traitement ou de l appel suivi.';
COMMENT ON COLUMN monitoring.created_at IS
'Date technique d insertion en base. Elle est remplie automatiquement par PostgreSQL.';
COMMENT ON COLUMN monitoring.status IS
'Statut global du suivi : to_process, running, done, error, success, warning, etc.';
COMMENT ON COLUMN monitoring.module IS
'Nom du module fonctionnel ou technique : splitter, rest, ocr, phase2, etc.';
COMMENT ON COLUMN monitoring.source IS
'Origine fonctionnelle ou technique du suivi : upload, rest_api, worker, cron, scheduler, etc.';
COMMENT ON COLUMN monitoring.filename IS
'Nom ou chemin du fichier traité si le monitoring concerne un document.';
COMMENT ON COLUMN monitoring.token IS
'Jeton technique ou identifiant temporaire associé au traitement.';
COMMENT ON COLUMN monitoring.workflow_id IS
'Identifiant du workflow métier concerné : ventes, achats, phase2, etc.';
COMMENT ON COLUMN monitoring.elapsed_time IS
'Temps total écoulé, souvent stocké sous forme lisible comme 00:00:01.85.';
COMMENT ON COLUMN monitoring.document_ids IS
'Liste sérialisée des identifiants documentaires associés au traitement. Stockée en texte pour rester compatible avec le code existant.';
COMMENT ON COLUMN monitoring.message IS
'Message fonctionnel ou technique complémentaire.';
COMMENT ON COLUMN monitoring.result IS
'Résultat principal de l exécution, éventuellement sérialisé en texte ou JSON.';
COMMENT ON COLUMN monitoring.mime_type IS
'Type MIME du document si applicable.';
COMMENT ON COLUMN monitoring.worker_name IS
'Nom du worker ou du processus qui a exécuté le traitement.';
COMMENT ON COLUMN monitoring.host_name IS
'Nom de la machine ou du conteneur qui a exécuté le traitement.';
COMMENT ON COLUMN monitoring.error_message IS
'Message d erreur détaillé en cas d incident.';
COMMENT ON COLUMN monitoring.error_type IS
'Type ou classe d erreur rencontrée.';


-- =============================================================================
-- 3. TABLE DES ÉTAPES : monitoring_steps
-- =============================================================================
-- Cette table stocke le détail chronométré des étapes d'une exécution.
--
-- Elle est utilisée pour :
-- - suivre où le temps est réellement dépensé ;
-- - identifier les goulots d'étranglement ;
-- - détailler les étapes d'un workflow ;
-- - tracer les analyses internes de phase 2 si besoin.
-- =============================================================================

CREATE TABLE IF NOT EXISTS monitoring_steps (
    id BIGSERIAL PRIMARY KEY,
    monitoring_id BIGINT NOT NULL,

    step_name VARCHAR(255) NOT NULL,
    started_at TIMESTAMP NULL,
    ended_at TIMESTAMP NULL,
    duration_ms BIGINT NULL,

    filename TEXT NULL,
    workflow_id VARCHAR(255) NULL,
    worker_name VARCHAR(255) NULL,
    host_name VARCHAR(255) NULL,

    status VARCHAR(100) NULL,
    extra_json JSONB NULL,

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_monitoring_steps_monitoring
        FOREIGN KEY (monitoring_id)
        REFERENCES monitoring (id)
        ON DELETE CASCADE
);

COMMENT ON TABLE monitoring_steps IS
'Détail des étapes mesurées pendant une exécution. Permet de voir précisément où le temps est passé.';

COMMENT ON COLUMN monitoring_steps.id IS
'Identifiant technique unique de la ligne étape.';
COMMENT ON COLUMN monitoring_steps.monitoring_id IS
'Référence vers la table monitoring. Indique à quelle exécution globale cette étape appartient.';
COMMENT ON COLUMN monitoring_steps.step_name IS
'Nom de l étape : upload_received, pdf_to_image_started, field_extraction_started, etc.';
COMMENT ON COLUMN monitoring_steps.started_at IS
'Date et heure de début de l étape.';
COMMENT ON COLUMN monitoring_steps.ended_at IS
'Date et heure de fin de l étape.';
COMMENT ON COLUMN monitoring_steps.duration_ms IS
'Durée de l étape en millisecondes. Ce format est pratique pour les analyses fines.';
COMMENT ON COLUMN monitoring_steps.filename IS
'Nom ou chemin du fichier concerné par l étape.';
COMMENT ON COLUMN monitoring_steps.workflow_id IS
'Identifiant du workflow métier associé à l étape.';
COMMENT ON COLUMN monitoring_steps.worker_name IS
'Nom du worker qui a exécuté l étape.';
COMMENT ON COLUMN monitoring_steps.host_name IS
'Nom de la machine ou du conteneur qui a exécuté l étape.';
COMMENT ON COLUMN monitoring_steps.status IS
'Statut de l étape : started, success, error, warning, finished, etc.';
COMMENT ON COLUMN monitoring_steps.extra_json IS
'Données additionnelles au format JSONB : détails techniques, métriques intermédiaires, contexte de l étape.';
COMMENT ON COLUMN monitoring_steps.created_at IS
'Date technique d insertion en base de la ligne étape.';


-- =============================================================================
-- 4. TABLE COMPLÉMENTAIRE : monitoring_extra
-- =============================================================================
-- Cette table stocke les informations détaillées additionnelles.
--
-- A) Données REST (RestPerf)
--    - méthode HTTP
--    - endpoint
--    - code retour
--    - user agent
--    - taille de requête / réponse
--    - document_status
--    - traceback
--
-- B) Données Phase 2 (Phase2PerformanceAdvisor / Phase2WorkPlan)
--    - type d analyse
--    - portée de l analyse
--    - hypothèses d'entrée
--    - résultats calculés
--    - cause probable
--    - recommandations
--    - priorisation
--
-- C) Données documentaires et OCR
--    - nombre de pages
--    - fournisseur trouvé ou non
--    - identifiants documentaires et batch
--    - nom original du fichier
--    - statut documentaire intermédiaire
--
-- IMPORTANT :
-- La relation se fait ici vers monitoring_steps, car dans le code les détails
-- complémentaires sont souvent rattachés à une étape précise.
-- =============================================================================

CREATE TABLE monitoring_extra (
    id BIGSERIAL PRIMARY KEY,
    monitoring_step_id BIGINT NOT NULL,

    -- -------------------------------------------------------------------------
    -- Bloc 1 : données REST
    -- -------------------------------------------------------------------------
    http_method VARCHAR(16) NULL,
    endpoint VARCHAR(255) NULL,
    request_path TEXT NULL,
    query_string TEXT NULL,
    status_code INTEGER NULL,
    document_status VARCHAR(100) NULL,
    user_agent TEXT NULL,
    remote_addr VARCHAR(64) NULL,
    content_length BIGINT NULL,
    response_length BIGINT NULL,
    blueprint_name VARCHAR(255) NULL,
    view_function VARCHAR(255) NULL,
    traceback TEXT NULL,
    module_name VARCHAR(255) NULL,

    -- -------------------------------------------------------------------------
    -- Bloc 2 : données d'analyse Phase 2
    -- -------------------------------------------------------------------------
    analysis_type VARCHAR(100) NULL,
    analysis_scope VARCHAR(255) NULL,

    input_average_document_seconds DOUBLE PRECISION NULL,
    input_active_workers INTEGER NULL,
    input_incoming_documents_per_minute DOUBLE PRECISION NULL,
    input_ocr_share_ratio DOUBLE PRECISION NULL,
    input_target_ocr_reduction_ratio DOUBLE PRECISION NULL,
    input_target_worker_count INTEGER NULL,

    computed_documents_per_minute DOUBLE PRECISION NULL,
    computed_documents_per_hour DOUBLE PRECISION NULL,
    computed_worker_occupation_rate DOUBLE PRECISION NULL,
    computed_saturation_ratio DOUBLE PRECISION NULL,
    computed_gain_ratio DOUBLE PRECISION NULL,
    computed_occurrences INTEGER NULL,

    probable_cause TEXT NULL,
    recommended_measure TEXT NULL,

    work_axis VARCHAR(255) NULL,
    work_objective TEXT NULL,
    work_deliverable TEXT NULL,
    work_effort VARCHAR(100) NULL,
    priority_rank INTEGER NULL,
    implementation_complexity VARCHAR(100) NULL,
    estimated_delay VARCHAR(100) NULL,
    expected_impact TEXT NULL,

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- -------------------------------------------------------------------------
    -- Bloc 3 : données documentaires (AJOUT PHASE CORRECTIVE)
    -- -------------------------------------------------------------------------
    -- Ces colonnes ont été ajoutées suite aux erreurs runtime observées :
    -- - nb_pages manquant
    -- - supplier_found manquant
    -- - source manquant dans monitoring_extra
    -- - original_filename manquant
    -- - saved_filename manquant
    -- - monitor_status manquant
    -- - splitter_batch_id manquant
    -- - has_supplier manquant
    -- - has_datas manquant
    -- - footer_found manquant
    -- - convert_function manquant
    -- - autres champs documentaires probables
    --
    -- Remarque importante :
    -- Certaines informations existent déjà dans la table monitoring, mais elles
    -- sont aussi utiles au niveau détail / étape. On les duplique donc ici
    -- volontairement pour rester compatible avec le code existant.

    source VARCHAR(255) NULL,
    original_filename TEXT NULL,
    saved_filename TEXT NULL,
    file_path TEXT NULL,
    result TEXT NULL,
    monitor_status VARCHAR(100) NULL,
    mime_type VARCHAR(255) NULL,
    
    nb_pages INTEGER NULL,
    footer_found BOOLEAN NULL,
    convert_function VARCHAR(255) NULL,
    supplier_found BOOLEAN NULL,
    has_supplier BOOLEAN NULL,
    has_datas BOOLEAN NULL,

    document_id BIGINT NULL,
    batch_id BIGINT NULL,
    splitter_batch_id BIGINT NULL,
    customer_id BIGINT NULL,
    supplier_id BIGINT NULL,

    separator_method VARCHAR(255) NULL,
    file_size BIGINT NULL,
    custom_id VARCHAR(255) NULL,
    workflow_id VARCHAR(255) NULL,
    worker_name VARCHAR(255) NULL,
    host_name VARCHAR(255) NULL,
    filename TEXT NULL,

    error_message TEXT NULL,
    error_type VARCHAR(255) NULL,

    -- -------------------------------------------------------------------------
    -- Bloc 4 : flexibilité maximale (ANTI ÉVOLUTION CASSANTE)
    -- -------------------------------------------------------------------------
    -- Cette colonne JSONB sert de zone tampon.
    -- Si demain de nouveaux champs métiers apparaissent dans le code Python,
    -- ils pourront être stockés ici sans casser le schéma SQL.
    -- C'est une bonne pratique pour rendre le monitoring plus robuste.
    extra_data JSONB NULL,

    CONSTRAINT fk_monitoring_extra_monitoring_steps
        FOREIGN KEY (monitoring_step_id)
        REFERENCES monitoring_steps (id)
        ON DELETE CASCADE
);

COMMENT ON TABLE monitoring_extra IS
'Informations complémentaires de monitoring : détails REST, analyses Phase 2, simulations de gains et plan d actions.';

COMMENT ON COLUMN monitoring_extra.id IS
'Identifiant technique unique de la ligne complémentaire.';
COMMENT ON COLUMN monitoring_extra.monitoring_step_id IS
'Référence vers la table monitoring_steps. Lie les informations détaillées à une étape précise.';

COMMENT ON COLUMN monitoring_extra.http_method IS
'Méthode HTTP utilisée lors d un appel REST : GET, POST, PUT, DELETE, etc.';
COMMENT ON COLUMN monitoring_extra.endpoint IS
'Nom logique de l endpoint ou de la fonction Flask appelée.';
COMMENT ON COLUMN monitoring_extra.request_path IS
'Chemin URL appelé.';
COMMENT ON COLUMN monitoring_extra.query_string IS
'Paramètres GET de la requête.';
COMMENT ON COLUMN monitoring_extra.status_code IS
'Code de statut HTTP retourné : 200, 403, 404, 500, etc.';
COMMENT ON COLUMN monitoring_extra.document_status IS
'Statut documentaire ou métier complémentaire lié à la requête ou au traitement. Dans certains appels observés, cette colonne reçoit aussi une valeur de statut HTTP sérialisée par le code existant.';
COMMENT ON COLUMN monitoring_extra.user_agent IS
'Chaîne User-Agent du client HTTP.';
COMMENT ON COLUMN monitoring_extra.remote_addr IS
'Adresse IP du client ayant effectué la requête HTTP.';
COMMENT ON COLUMN monitoring_extra.content_length IS
'Taille de la requête entrante en octets.';
COMMENT ON COLUMN monitoring_extra.response_length IS
'Taille de la réponse sortante en octets.';
COMMENT ON COLUMN monitoring_extra.blueprint_name IS
'Nom du blueprint Flask concerné.';
COMMENT ON COLUMN monitoring_extra.view_function IS
'Nom de la fonction Python réellement exécutée pour la route REST.';
COMMENT ON COLUMN monitoring_extra.traceback IS
'Traceback détaillé en cas d erreur ou d exception.';
COMMENT ON COLUMN monitoring_extra.module_name IS
'Nom du module applicatif ayant produit cette ligne de monitoring détaillée.';

COMMENT ON COLUMN monitoring_extra.analysis_type IS
'Type d analyse Phase 2 : capacity, gain_simulation, api_incident, workplan, infra_measure_plan, etc.';
COMMENT ON COLUMN monitoring_extra.analysis_scope IS
'Périmètre de l analyse : global, OCR, workers, endpoint, infrastructure, etc.';

COMMENT ON COLUMN monitoring_extra.input_average_document_seconds IS
'Hypothèse d entrée : durée moyenne d un document, en secondes.';
COMMENT ON COLUMN monitoring_extra.input_active_workers IS
'Hypothèse d entrée : nombre de workers actifs.';
COMMENT ON COLUMN monitoring_extra.input_incoming_documents_per_minute IS
'Hypothèse d entrée : nombre de documents entrants par minute.';
COMMENT ON COLUMN monitoring_extra.input_ocr_share_ratio IS
'Hypothèse d entrée : part du temps total attribuée à l OCR ou à l extraction.';
COMMENT ON COLUMN monitoring_extra.input_target_ocr_reduction_ratio IS
'Hypothèse d entrée : réduction cible du coût OCR, par exemple 0.30 pour 30 pour cent.';
COMMENT ON COLUMN monitoring_extra.input_target_worker_count IS
'Hypothèse d entrée : nombre cible de workers dans un scénario simulé.';

COMMENT ON COLUMN monitoring_extra.computed_documents_per_minute IS
'Résultat calculé : nombre estimé de documents traitables par minute.';
COMMENT ON COLUMN monitoring_extra.computed_documents_per_hour IS
'Résultat calculé : nombre estimé de documents traitables par heure.';
COMMENT ON COLUMN monitoring_extra.computed_worker_occupation_rate IS
'Résultat calculé : taux estimé d occupation des workers.';
COMMENT ON COLUMN monitoring_extra.computed_saturation_ratio IS
'Résultat calculé : niveau de saturation estimé du système.';
COMMENT ON COLUMN monitoring_extra.computed_gain_ratio IS
'Résultat calculé : gain estimé par rapport à la situation de référence.';
COMMENT ON COLUMN monitoring_extra.computed_occurrences IS
'Résultat calculé : nombre d occurrences observées ou estimées.';

COMMENT ON COLUMN monitoring_extra.probable_cause IS
'Cause probable identifiée lors d une analyse ou d un incident.';
COMMENT ON COLUMN monitoring_extra.recommended_measure IS
'Mesure recommandée ou action proposée.';

COMMENT ON COLUMN monitoring_extra.work_axis IS
'Axe de travail principal dans le plan d action : OCR, workers, API, infrastructure, monitoring, etc.';
COMMENT ON COLUMN monitoring_extra.work_objective IS
'Objectif recherché par l action proposée.';
COMMENT ON COLUMN monitoring_extra.work_deliverable IS
'Livrable attendu pour l action proposée.';
COMMENT ON COLUMN monitoring_extra.work_effort IS
'Effort estimé nécessaire pour réaliser l action.';
COMMENT ON COLUMN monitoring_extra.priority_rank IS
'Ordre de priorité de l action : 1 = très prioritaire.';
COMMENT ON COLUMN monitoring_extra.implementation_complexity IS
'Niveau de complexité estimé : faible, moyenne, élevée.';
COMMENT ON COLUMN monitoring_extra.estimated_delay IS
'Délai de mise en oeuvre estimé : heures, jours, semaines.';
COMMENT ON COLUMN monitoring_extra.expected_impact IS
'Impact attendu sur le débit, le temps de traitement ou la stabilité.';
COMMENT ON COLUMN monitoring_extra.created_at IS
'Date technique d insertion en base de la ligne complémentaire.';

COMMENT ON COLUMN monitoring_extra.source IS
'Origine fonctionnelle ou technique du détail de monitoring. Cette colonne a été ajoutée car le code Python écrit déjà ce champ dans monitoring_extra.';
COMMENT ON COLUMN monitoring_extra.original_filename IS
'Nom original du fichier avant renommage technique éventuel.';
COMMENT ON COLUMN monitoring_extra.saved_filename IS
'Nom du fichier après sauvegarde ou renommage technique dans le workflow.';
COMMENT ON COLUMN monitoring_extra.file_path IS
'Chemin logique ou physique associé au fichier, ou URL appelée selon le contexte d écriture.';
COMMENT ON COLUMN monitoring_extra.monitor_status IS
'Statut de monitoring détaillé au niveau de l étape ou du détail complémentaire.';
COMMENT ON COLUMN monitoring_extra.mime_type IS
'Type MIME associé à la requête, à la réponse ou au fichier traité : application/json, multipart/form-data, image/png, etc.';
COMMENT ON COLUMN monitoring_extra.nb_pages IS
'Nombre de pages du document traité.';
COMMENT ON COLUMN monitoring_extra.footer_found IS
'Indique si les informations de pied de page ont été trouvées pendant l analyse OCR du document.';
COMMENT ON COLUMN monitoring_extra.convert_function IS
'Nom de la fonction de conversion ou de traitement utilisée avant ou pendant l extraction OCR.';

COMMENT ON COLUMN monitoring_extra.supplier_found IS
'Indique si un fournisseur a été détecté automatiquement pendant l analyse.';
COMMENT ON COLUMN monitoring_extra.has_supplier IS
'Indique si un fournisseur est déjà présent ou associé au lot ou au document dans le contexte du splitter.';
COMMENT ON COLUMN monitoring_extra.has_datas IS
'Indique si le lot ou le document contient déjà des données exploitables.';
COMMENT ON COLUMN monitoring_extra.document_id IS
'Identifiant du document métier si disponible.';
COMMENT ON COLUMN monitoring_extra.batch_id IS
'Identifiant générique de lot si utilisé par le workflow.';
COMMENT ON COLUMN monitoring_extra.splitter_batch_id IS
'Identifiant du lot créé par le module de séparation / splitter.';
COMMENT ON COLUMN monitoring_extra.customer_id IS
'Identifiant du client associé au traitement.';
COMMENT ON COLUMN monitoring_extra.supplier_id IS
'Identifiant du fournisseur associé au traitement.';
COMMENT ON COLUMN monitoring_extra.separator_method IS
'Méthode de séparation utilisée, par exemple qr_code_OC.';
COMMENT ON COLUMN monitoring_extra.file_size IS
'Taille du fichier traité, en octets.';
COMMENT ON COLUMN monitoring_extra.custom_id IS
'Identifiant de personnalisation ou de configuration utilisé par l instance ou le client.';
COMMENT ON COLUMN monitoring_extra.workflow_id IS
'Identifiant du workflow métier associé au détail de monitoring.';
COMMENT ON COLUMN monitoring_extra.worker_name IS
'Nom du worker qui a produit cette ligne détaillée.';
COMMENT ON COLUMN monitoring_extra.host_name IS
'Nom de la machine ou du conteneur ayant produit cette ligne détaillée.';
COMMENT ON COLUMN monitoring_extra.filename IS
'Nom ou chemin du fichier associé à cette information complémentaire.';
COMMENT ON COLUMN monitoring_extra.extra_data IS
'Colonne JSON de sécurité permettant de stocker des données non prévues par le schéma. Elle évite de devoir modifier la base à chaque évolution du code.';
COMMENT ON COLUMN monitoring_extra.result IS
'Résultat détaillé associé à cette ligne complémentaire de monitoring. Peut contenir un booléen sérialisé, un texte, ou un résultat métier.';
COMMENT ON COLUMN monitoring_extra.error_message IS
'Message d’erreur capturé lors du traitement d’un document ou d’une requête';
COMMENT ON COLUMN monitoring_extra.error_type IS
'Type d’erreur rencontré lors du traitement (ex: OCR_ERROR, DB_ERROR, TIMEOUT, VALIDATION_ERROR). Permet de classer et analyser les incidents.';

-- =============================================================================
-- 5 - TABLE : documents AJOUT DES COLONNES DE SUIVI TEMPOREL
-- =============================================================================

-- 📌 created_at : date de création du document
-- ➤ Enregistre le moment où le document entre dans le système
-- ➤ Utilisé pour mesurer :
--    - le débit global (documents/minute)
--    - le temps total de traitement
-- ➤ DEFAULT NOW() permet d’éviter les erreurs si non renseigné

ALTER TABLE documents
ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT NOW();

-- 📌 processed_at : date de fin de traitement
-- ➤ NULL = document non traité
-- ➤ Rempli uniquement à la fin du traitement
-- ➤ Sert à calculer :
--    - le temps de traitement par document
--    - le volume traité

ALTER TABLE documents
ADD COLUMN IF NOT EXISTS processed_at TIMESTAMP NULL;

COMMENT ON COLUMN documents.created_at IS
'Date et heure de création du document dans le système. 
Cette valeur est automatiquement renseignée à l’insertion (DEFAULT NOW()).
Elle sert de point de départ pour les calculs de performance (débit, temps total).';

COMMENT ON COLUMN documents.processed_at IS
'Date et heure de fin de traitement du document.
NULL signifie que le document est en attente ou en cours de traitement.
Permet de calculer le temps de traitement (processed_at - created_at).';

-- =============================================================================
-- 6. INDEX
-- =============================================================================
-- Les index améliorent les performances de lecture sur les colonnes
-- les plus souvent utilisées dans les recherches, filtres et tableaux de bord.
--
-- Organisation retenue :
-- - d abord les index de la table monitoring
-- - ensuite ceux de monitoring_steps
-- - enfin ceux de monitoring_extra
--
-- Cette organisation rend le fichier plus simple à relire pour un développeur
-- junior ou pour un futur mainteneur.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Index de la table monitoring
-- -----------------------------------------------------------------------------

CREATE INDEX idx_monitoring_status
    ON monitoring(status);

CREATE INDEX idx_monitoring_module
    ON monitoring(module);

CREATE INDEX idx_monitoring_source
    ON monitoring(source);

CREATE INDEX idx_monitoring_workflow_id
    ON monitoring(workflow_id);

CREATE INDEX idx_monitoring_created_at
    ON monitoring(created_at);

-- Sous-ensemble utile pour les recherches par fenêtre temporelle.
CREATE INDEX idx_monitoring_creation_date
    ON monitoring(creation_date);

CREATE INDEX idx_monitoring_start_date
    ON monitoring(start_date);

CREATE INDEX idx_monitoring_end_date
    ON monitoring(end_date);

-- -----------------------------------------------------------------------------
-- Index de la table monitoring_steps
-- -----------------------------------------------------------------------------

CREATE INDEX idx_monitoring_steps_monitoring_id
    ON monitoring_steps(monitoring_id);

CREATE INDEX idx_monitoring_steps_step_name
    ON monitoring_steps(step_name);

CREATE INDEX idx_monitoring_steps_workflow_id
    ON monitoring_steps(workflow_id);

CREATE INDEX idx_monitoring_steps_created_at
    ON monitoring_steps(created_at);

CREATE INDEX idx_monitoring_steps_status
    ON monitoring_steps(status);

-- Index composite utile pour retrouver rapidement les étapes d un workflow dans l ordre chronologique.
CREATE INDEX idx_monitoring_steps_workflow_created_at
    ON monitoring_steps(workflow_id, created_at);

-- -----------------------------------------------------------------------------
-- Index de la table monitoring_extra
-- -----------------------------------------------------------------------------

CREATE INDEX idx_monitoring_extra_monitoring_step_id
    ON monitoring_extra(monitoring_step_id);

CREATE INDEX idx_monitoring_extra_http_method
    ON monitoring_extra(http_method);

CREATE INDEX idx_monitoring_extra_status_code
    ON monitoring_extra(status_code);

CREATE INDEX idx_monitoring_extra_endpoint
    ON monitoring_extra(endpoint);

CREATE INDEX idx_monitoring_extra_analysis_type
    ON monitoring_extra(analysis_type);

CREATE INDEX idx_monitoring_extra_work_axis
    ON monitoring_extra(work_axis);

CREATE INDEX idx_monitoring_extra_priority_rank
    ON monitoring_extra(priority_rank);

-- Index ajoutés suite aux erreurs et aux usages documentaires observés
CREATE INDEX idx_monitoring_extra_source
    ON monitoring_extra(source);

CREATE INDEX idx_monitoring_extra_monitor_status
    ON monitoring_extra(monitor_status);

CREATE INDEX idx_monitoring_extra_splitter_batch_id
    ON monitoring_extra(splitter_batch_id);

CREATE INDEX idx_monitoring_extra_document_id
    ON monitoring_extra(document_id);

CREATE INDEX idx_monitoring_extra_supplier_id
    ON monitoring_extra(supplier_id);

CREATE INDEX idx_monitoring_extra_customer_id
    ON monitoring_extra(customer_id);

CREATE INDEX idx_monitoring_extra_footer_found
    ON monitoring_extra(footer_found);

CREATE INDEX idx_monitoring_extra_convert_function
    ON monitoring_extra(convert_function);

CREATE INDEX idx_monitoring_extra_remote_addr
    ON monitoring_extra(remote_addr);

CREATE INDEX idx_monitoring_extra_module_name
    ON monitoring_extra(module_name);

CREATE INDEX idx_monitoring_extra_custom_id
    ON monitoring_extra(custom_id);

CREATE INDEX idx_monitoring_extra_blueprint_name
    ON monitoring_extra(blueprint_name);

CREATE INDEX idx_monitoring_extra_view_function
    ON monitoring_extra(view_function);

CREATE INDEX idx_monitoring_extra_document_status
    ON monitoring_extra(document_status);

CREATE INDEX idx_monitoring_extra_workflow_id
    ON monitoring_extra(workflow_id);

CREATE INDEX idx_monitoring_extra_created_at
    ON monitoring_extra(created_at);

-- Index composite utile pour filtrer rapidement les appels REST par module, endpoint et statut HTTP.
CREATE INDEX idx_monitoring_extra_module_endpoint_status
    ON monitoring_extra(module_name, endpoint, status_code);

-- Index composite utile pour l analyse documentaire par lot et client.
CREATE INDEX idx_monitoring_extra_batch_customer
    ON monitoring_extra(splitter_batch_id, customer_id);

-- Index GIN sur JSONB pour permettre les recherches avancées dans extra_data.
CREATE INDEX idx_monitoring_extra_extra_data_gin
    ON monitoring_extra USING GIN (extra_data);


-- =============================================================================
-- 7. NOTES FINALES
-- =============================================================================
-- Ce script est volontairement pédagogique et détaillé.
-- Il sert à la fois de script technique et de documentation lisible
-- par un développeur junior.
--
-- En production, si l'on veut conserver l'historique, il faudra plutôt :
-- - utiliser ALTER TABLE
-- - écrire des migrations
-- - éviter DROP TABLE
--
-- Ici, le besoin demandé est bien :
-- supprimer les tables si elles existent, puis recréer les tables.
--
-- NOTE D'ALIGNEMENT AJOUTÉE :
-- Le schéma de monitoring_extra inclut maintenant les colonnes réellement
-- observées dans les INSERT Apache / WSGI, notamment :
-- - saved_filename
-- - file_path
-- - has_supplier
-- - has_datas
-- En complément, extra_data JSONB reste disponible comme zone de tolérance
-- pour absorber de futurs champs sans casser le schéma.
-- =============================================================================

-- =============================================================================
-- AUTO-FIX SEQUENCES GLOBAL (PRODUCTION SAFE)
-- =============================================================================
-- Corrige automatiquement toutes les séquences (SERIAL / BIGSERIAL)
-- pour les aligner avec les valeurs MAX(id) réelles
-- =============================================================================

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT
            c.table_schema,
            c.table_name,
            c.column_name,
            pg_get_serial_sequence(
                c.table_schema || '.' || c.table_name,
                c.column_name
            ) AS seq_name
        FROM information_schema.columns c
        WHERE c.column_default LIKE 'nextval%'
    LOOP
        IF rec.seq_name IS NOT NULL THEN
            EXECUTE format(
                'SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %I.%I), 0) + 1, false)',
                rec.seq_name,
                rec.column_name,
                rec.table_schema,
                rec.table_name
            );
        END IF;
    END LOOP;
END $$;