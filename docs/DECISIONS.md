# Architecture & Design Decisions

## Decision 001: Soft Deletion Strategy (Phase 5.6.2)
- **Problem**: Need CRUD operations and ability to delete records without losing audit trails.
- **Decision**: Implement `deleted_at` / `deleted_by` in the active operational tables (`eco_normalized_records`, `eco_financial_movements`). Raw tables (`eco_import_rows`, `eco_source_files`) remain strictly immutable. Read queries (`get_active_normalized_records`) explicitly exclude rows where `deleted_at IS NOT NULL`.
- **Reason**: Ensures financial traceability while allowing frontend users to correct mapping errors.

## Decision 002: Categorization Model (Phase 5.6.2)
- **Problem**: Requirement for standardized categories that can be assigned per organization.
- **Decision**: Split into global catalog (`eco_tax_categories`) and tenant assignments (`eco_org_tax_categories`). Legacy column `categoria` renamed to `legacy_categoria_text` to preserve data without data loss during the transition.
- **Reason**: Allows the SaaS admin to maintain global standards while letting each tenant define which categories are active for them.
