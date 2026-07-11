# Architecture

## Mac mini M4 — Brain

AI 판단, Dashboard, n8n, OpenAI, Claude, Ollama, Notion 및 알림을 담당한다.

## Ubuntu Server — Worker

Docker, Storage, Backup, Inventory, Immich, Nextcloud 및 Plex 운영 작업을 담당한다.

Ubuntu에서는 AI 추론을 실행하지 않는다.

## Runtime Flow

Mac mini
→ SSH/API
→ Ubuntu Runtime
→ Approved Commands
→ Reports
→ AI Analysis

## Storage Flow

Archive
→ Inventory
→ SHA256
→ Duplicate Preview
→ User Approval
→ Cleanup or Migration
