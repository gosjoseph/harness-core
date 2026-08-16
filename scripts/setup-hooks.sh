#!/usr/bin/env sh
# Activa la fricción pre-push (patrón "puente sin CI"). Idempotente. Correr una vez tras clone.
set -e
git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true
echo "hooks activos: core.hooksPath=.githooks"
