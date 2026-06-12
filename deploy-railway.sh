#!/bin/bash
# ============================================================
# Deploy QuantAlpha sur Railway — Script automatisé
# ============================================================
# 1. Remplir .env avec tes clés API
# 2. chmod +x deploy-railway.sh && ./deploy-railway.sh
# ============================================================

set -e

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║       QUANTALPHA — DEPLOY SUR RAILWAY                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# --- ETAPE 0 : Verifications ---
echo "[0/6] 🔍 Vérifications..."

# Railway CLI installée ?
if ! command -v railway &> /dev/null; then
    echo "❌ Railway CLI pas installée. Installation..."
    npm install -g @railway/cli
fi

# Connecté ?
if ! railway whoami &> /dev/null; then
    echo "🔑 Connexion Railway..."
    railway login
fi

# Git ?
if ! git rev-parse --git-dir &> /dev/null; then
    echo "❌ Pas de repo Git. Création..."
    git init && git add . && git commit -m "init"
fi

# .env ?
if [[ ! -f .env ]]; then
    echo "❌ Fichier .env manquant. Copie depuis .env.example..."
    cp .env.example .env
    echo "📝 Remplis le fichier .env avec tes clés API, puis relance ce script."
    exit 1
fi

echo "✅ Tout est OK"

# --- ETAPE 1 : Git push ---
echo ""
echo "[1/6] 📤 Envoi du code sur GitHub..."

# Commit si modifications
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    git add -A
    git commit -m "deploy $(date '+%Y-%m-%d %H:%M')" || true
fi

# Remote GitHub configuré ?
if git remote get-url origin &> /dev/null; then
    git push origin $(git branch --show-current) || echo "⚠️ Push ignoré (déjà à jour)"
    echo "✅ Code sur GitHub"
else
    echo "⚠️ Pas de remote GitHub configuré."
    echo "   Crée un repo sur https://github.com/new puis :"
    echo "   git remote add origin https://github.com/TON_USER/quantalpha.git"
    echo "   git push -u origin main"
    exit 1
fi

# --- ETAPE 2 : Projet Railway ---
echo ""
echo "[2/6] 🏗️  Création du projet Railway..."

if railway status &> /dev/null; then
    echo "✅ Projet Railway déjà lié"
else
    railway init --name quantalpha
fi

# --- ETAPE 3 : Base de données ---
echo ""
echo "[3/6] 🗄️  Ajout PostgreSQL + Redis..."

# PostgreSQL
if railway status 2>/dev/null | grep -qi "postgres"; then
    echo "✅ PostgreSQL déjà présent"
else
    echo "⏳ Création PostgreSQL..."
    railway add --database postgres
fi

# Redis
if railway status 2>/dev/null | grep -qi "redis"; then
    echo "✅ Redis déjà présent"
else
    echo "⏳ Création Redis..."
    railway add --database redis
fi

# --- ETAPE 4 : Variables d'environnement ---
echo ""
echo "[4/6] ⚙️  Configuration des variables..."

railway variables set ROOT_PATH="/api"

# Charger .env et envoyer les variables
while IFS='=' read -r key value; do
    # Ignorer les lignes vides et commentaires
    [[ -z "$key" ]] && continue
    [[ "$key" =~ ^# ]] && continue
    # Supprimer espaces
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    [[ -z "$value" ]] && continue
    railway variables set "$key=$value" 2>/dev/null && echo "   ✅ $key" || echo "   ⚠️  $key (ignoré)"
done < .env

# --- ETAPE 5 : Deploy API ---
echo ""
echo "[5/6] 🚀 Deploy API..."
railway up --detach

# Attendre
sleep 10

# --- ETAPE 6 : Vérification ---
echo ""
echo "[6/6] 🔎 Vérification..."

DOMAIN=$(railway domain 2>/dev/null || echo "")

if [[ -n "$DOMAIN" ]]; then
    URL="https://$DOMAIN"
    echo "   🌐 URL API : $URL"

    # Health check
    for i in 1 2 3; do
        if curl -sf "$URL/api/health" &>/dev/null; then
            echo "   ✅ API en ligne !"
            break
        fi
        echo "   ⏳ Attente... ($i/3)"
        sleep 10
    done
else
    echo "   ⚠️  Domaine pas encore prêt"
fi

# --- RÉSULTAT ---
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
if [[ -n "$DOMAIN" ]]; then
    echo "║  ✅ DEPLOY TERMINÉ                                        ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║  🌐 API        : https://$DOMAIN           ║"
    echo "║  📖 Swagger    : https://$DOMAIN/api/docs  ║"
    echo "║  ❤️  Health    : https://$DOMAIN/api/health ║"
else
    echo "║  ⚠️  DEPLOY EN COURS                                      ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║  Vérifie dans quelques minutes :                          ║"
    echo "║  railway domain  → pour voir l'URL                        ║"
fi
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  Commandes utiles :                                       ║"
echo "║  railway logs -f        → Logs en temps réel              ║"
echo "║  railway status         → État des services               ║"
echo "║  railway open           → Ouvrir dashboard Railway        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
