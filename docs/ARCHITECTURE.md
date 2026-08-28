# Architecture

## Core Components
- **Frontend**: HTML / CSS / Vanilla JS (ES Modules) via `index.html`. No frameworks, SPA navigation using `ui.js`.
- **Backend**: Supabase (PostgreSQL, Auth, Storage, Edge Functions).

## Database Architecture
- **Raw Evidence Layer**: `eco_source_imports`, `eco_source_files`, `eco_import_rows`, `eco_import_issues`. Strictly immutable (hard delete prohibited).
- **Normalized Data Layer**: `eco_normalized_records` (Comprobantes, Percepciones). Uses identity and fingerprinting.
- **Financial Layer**: `eco_financial_movements` (Bancos, Sueldos). Uses identity and fingerprinting.
- **Categorization Layer** (from 014): `eco_tax_categories` (Catalog) / `eco_org_tax_categories` (Assignment) for flexible multidimensional mappings.

## Security
- Row Level Security (RLS) is strict across all tenant data (`organization_id`).
- All mutation pipelines act via `SECURITY DEFINER` RPCs bypassing `anon` exposure and ensuring strict access control.
