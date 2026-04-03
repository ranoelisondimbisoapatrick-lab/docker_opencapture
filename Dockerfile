# Utiliser debian 12 comme image de base
FROM debian:12

# Forcer le mode non interactif pour éviter les erreurs de frontend de debconf
ENV DEBIAN_FRONTEND=noninteractive

# Mise à jour du système et installation des dépendances principales
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils sudo cron apache2 python3 libpq-dev pkg-config zbar-tools \
    imagemagick python3-venv python3-zbar poppler-utils libcairo2-dev \
    tesseract-ocr python3-skimage python3-chardet rabbitmq-server \
    libgl1-mesa-glx libtesseract-dev libleptonica-dev tesseract-ocr-fra \
    tesseract-ocr-eng python3-pyinotify autopostgresqlbackup \
    libapache2-mod-wsgi-py3 postgresql postgresql-contrib git crudini \
    supervisor curl wget unzip \
    fontconfig fonts-dejavu-core \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Installer PHP et ses extensions nécessaires
RUN apt-get update && apt-get install -y --no-install-recommends \
    libapache2-mod-php php-cli php-common php-mbstring php-xml php-mysql \
    php-curl php-zip postgresql-client \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Installer pip pour Python 3
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copier le fichier requirements.txt
COPY install/pip-requirements.txt /etc/pip-requirements.txt

# Créer un utilisateur
RUN useradd -m -s /bin/bash edissyum && \
    echo "edissyum ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Créer un environnement virtuel et installer les dépendances Python
RUN python3 -m venv /home/root/python-venv/opencapture/ && \
    /home/root/python-venv/opencapture/bin/pip install --upgrade pip && \
    /home/root/python-venv/opencapture/bin/pip install --no-cache-dir wheel setuptools && \
    /home/root/python-venv/opencapture/bin/pip install --no-cache-dir -r /etc/pip-requirements.txt

# Ajouter l'environnement virtuel au PATH
ENV PATH="/home/root/python-venv/opencapture/bin:$PATH"

# Assurez-vous que nltk est installé dans l'environnement virtuel
RUN /home/root/python-venv/opencapture/bin/pip install nltk

# Télécharger les ressources NLTK nécessaires
RUN python3 -c "import nltk; \
    nltk.download('punkt', download_dir='/opt/venv/share/nltk_data/'); \
    nltk.download('stopwords', download_dir='/opt/venv/share/nltk_data/'); \
    nltk.download('punkt_tab', download_dir='/opt/venv/share/nltk_data/');"

# Créer un utilisateur
RUN useradd -m -s /bin/bash opencapture && \
    echo "opencapture ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Configurer Supervisor
RUN mkdir -p /var/log/supervisor /etc/supervisor/conf.d
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf

# Copier et ajuster les permissions des répertoires requis
RUN mkdir -p /var/www/html/opencapture/ && \
    chown -R root:www-data /var/www/html/opencapture/

############################################################
# CRÉATION DOSSIER LOG WATCHER (OBLIGATOIRE)
############################################################
RUN mkdir -p /var/log/watcher \
    && touch /var/log/watcher/daemon.log \
    && touch /var/log/watcher/error.log \
    && chmod -R 777 /var/log/watcher

############################################################
# CRON + LOGS
############################################################
RUN mkdir -p \
    /var/log/cron \
    /var/log/watcher \
    /tmp/opencapture_runtime \
    && touch /var/log/cron/phase2.log \
    && touch /var/log/watcher/daemon.log \
    && touch /var/log/watcher/error.log \
    && chmod -R 777 /var/log \
    && chmod -R 1777 /tmp/opencapture_runtime

COPY cron/phase2 /etc/cron.d/phase2
RUN chmod 0644 /etc/cron.d/phase2

# -------------------------------------------------------------------
# CORRECTION MATPLOTLIB / FONTCONFIG
# -------------------------------------------------------------------
# Ces dossiers servent à éviter les messages :
# - mkdir -p failed for path /root/.config/matplotlib
# - Matplotlib created a temporary cache directory
# - Fontconfig error: No writable cache directories
RUN mkdir -p \
    /tmp/matplotlib \
    /tmp/fontconfig \
    /tmp/font-cache \
    /tmp/.cache \
    /tmp/.config \
    /var/cache/fontconfig \
    && chmod -R 777 \
    /tmp/matplotlib \
    /tmp/fontconfig \
    /tmp/font-cache \
    /tmp/.cache \
    /tmp/.config \
    /var/cache/fontconfig

# Variables d'environnement pour forcer les chemins vers des répertoires accessibles
ENV MPLCONFIGDIR=/tmp/matplotlib
ENV XDG_CACHE_HOME=/tmp/.cache
ENV XDG_CONFIG_HOME=/tmp/.config
ENV HOME=/tmp
ENV FONTCONFIG_PATH=/etc/fonts
ENV FONTCONFIG_FILE=/etc/fonts/fonts.conf

# Configurer Apache pour PHP et activer les modules nécessaires
RUN a2enmod php8.2 wsgi headers && a2enmod rewrite headers ssl

# Copier la configuration spécifique d'Apache
COPY apache/opencapture.conf /etc/apache2/sites-available/opencapture.conf

# Activer le site et désactiver le site par défaut
RUN a2ensite opencapture.conf && a2dissite 000-default.conf

RUN /home/root/python-venv/opencapture/bin/pip install --no-cache-dir debugpy

# Pour changer les fichier CRLF to LF
RUN apt-get update && apt-get install -y dos2unix nodejs npm && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN /home/root/python-venv/opencapture/bin/pip install --no-cache-dir pillow-heif img2pdf

# Exposer les ports pour l'application
EXPOSE 80 5432 443 5678

# =====================================================================================
# PORT PROMETHEUS (metrics Python)
# =====================================================================================
EXPOSE 8000

# Nettoyage pour réduire la taille de l'image
RUN rm -rf /var/lib/apt/lists/* /var/tmp/*

# -----------------------------------------------------------------------------
# Dossiers runtime internes au conteneur
# -----------------------------------------------------------------------------
# Ces dossiers servent aux caches et fichiers de configuration temporaires
# de bibliothèques comme Matplotlib et Ultralytics.
# Ils sont volontairement placés hors du volume Windows monté pour éviter
# les problèmes de permissions.
RUN mkdir -p /opt/opencapture_runtime/matplotlib \
    && mkdir -p /opt/opencapture_runtime/ultralytics \
    && mkdir -p /opt/opencapture_runtime/.cache \
    && mkdir -p /opt/opencapture_runtime/.config \
    && chown -R www-data:www-data /opt/opencapture_runtime \
    && chmod -R 775 /opt/opencapture_runtime

RUN mkdir -p /opt/opencapture_runtime/log \
    && chown -R www-data:www-data /opt/opencapture_runtime/log \
    && chmod -R 775 /opt/opencapture_runtime/log

ENV MPLCONFIGDIR=/opt/opencapture_runtime/matplotlib
ENV XDG_CACHE_HOME=/opt/opencapture_runtime/.cache
ENV XDG_CONFIG_HOME=/opt/opencapture_runtime/.config
ENV YOLO_CONFIG_DIR=/opt/opencapture_runtime/ultralytics
ENV HOME=/opt/opencapture_runtime

# ============================================================
# CMD UNIQUE (IMPORTANT)
# ============================================================
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]