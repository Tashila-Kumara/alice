---
name: azure-db-creator
description: >-
  Deploys Azure SQL (resource group, server, database), writes
  AZURE_DB_CONNECTION_STRING to a dated .env file at the project root, and
  whitelists the caller's public IP. Use when the user asks for an Azure SQL
  database, Azure DB setup, or connection string for FasTea or similar apps.
---

# Azure Database Creator

## Requirements

- PowerShell (`powershell` on Windows, `pwsh` on macOS/Linux).
- Azure PowerShell module (`Az`).
- Active Azure subscription (`Connect-AzAccount`).

## Workflow

1. **Shell:** Windows → `powershell`; macOS/Linux → `pwsh`. If `pwsh` is missing on Unix, stop and tell the user to install PowerShell Core (e.g. `brew install powershell`).
2. **Azure login:** Run `Get-AzContext`. If there is no context, stop and instruct the user to run `Connect-AzAccount` in their own terminal (not in chat).
3. **Collect inputs** (ask the user before running the script):
   - **Username** — used in resource names and as the SQL admin login (alphanumeric only after sanitization).
   - **Azure region** — optional argument; if omitted, script shows an interactive numbered menu (prefers `eastus`, `westus2`, `westeurope`, `southeastasia` when available).
   - **Service tier** — optional argument; if omitted, script shows an interactive numbered menu from `Basic`, `S0`, `S1`, `S2`, `S3`, `P1`, `P2`, `GP_Gen5_2`, `GP_Gen5_4`. Mention that paid tiers incur cost.
   - Optional **database name** — if omitted, the script uses `sqldb_<username>_<yyyy_MM_dd>`.
4. **Run from repository root** (so `ProjectRoot` resolves correctly):

```powershell
<powershell|pwsh> -File <PATH_TO_SKILL>/deploy.ps1 `
  -UserName "<USERNAME>" `
  -ProjectRoot "<ABSOLUTE_PATH_TO_REPO>"
```

`<PATH_TO_SKILL>` is either `./.cursor/skills/azure_db_creator` (project) or `~/.cursor/skills/azure_db_creator` (personal, all repos). Always pass `-ProjectRoot` so env files land in the correct repository.

Optional non-interactive flags: `-SqlTier "<TIER>"` and `-Location "<REGION>"`.

For a custom database name, add `-DatabaseName "<NAME>"`.

5. **Confirm deployment:** After tier/region selection and name checks, the script prints a summary (subscription, region, tier, resource group, server, database, admin login, env file path, firewall IP) and asks `Proceed with deployment? (Y/N)`. If the user answers `N`, the script exits without creating resources.
6. **Password prompt:** The script prompts in the terminal with masked input (`Read-Host -AsSecureString`). The user must complete this in the interactive terminal. Do not ask for the password in chat.
7. **On success:** The script prints `RESOURCE_GROUP=...`, `SQL_SERVER=...`, and `ENV_FILE=...`. Tell the user those values and the env filename. **Never** repeat the connection string or password in chat.
8. **On failure:** Errors are printed in red and the script exits with code `1`.

## Naming (automatic)

Date segment uses the **machine local date**: `yyyy_MM_dd`.

| Asset          | Pattern (before sanitization)         |
| -------------- | ------------------------------------- |
| Resource group | `rg_sql_db_server_<username>_<date>`  |
| SQL server     | `sql_db_server_<username>_<date>`     |
| Env file       | `sql_db_server_<username>_<date>.env` |

- Resource group names: Azure rules, max 90 characters; invalid characters removed.
- SQL server names: lowercase, hyphens only, 3–63 characters (underscores in the template become hyphens).
- If the resource group **already exists**, the script exits with a short red error (same username + same day).

## Env files and git

- Each successful run creates **one new file** at the project root: `sql_db_server_<username>_<date>.env`.
- Variable name: `AZURE_DB_CONNECTION_STRING` (full string, including password).
- `*.env` is gitignored; `sample.env` at the repo root documents the expected shape (safe to commit).

## Security

- Do not print passwords or full connection strings in chat.
- Masked terminal entry is used; the password is written only to the generated `*.env` file.
- Remind the user that `*.env` files must not be committed (see `sample.env` for placeholders).

## Skill locations

- **Project:** `.cursor/skills/azure_db_creator/` (shared with the repo).
- **Personal (all repos):** `~/.cursor/skills/azure_db_creator/` — keep in sync when updating this skill.

## Password handling (recommendation)

Masked `Read-Host` plus writing the full connection string to a gitignored `*.env` file is appropriate for local development. For production, prefer Azure Key Vault or managed identity instead of long-lived passwords in files. This skill targets **local dev** only.
