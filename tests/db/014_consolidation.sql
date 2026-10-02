-- tests/db/014_consolidation.sql

-- Test suite for 014 Consolidation & Categorization
-- To be executed manually or via pgTAP

BEGIN;

-- 1. Active Excludes Deleted
-- Insert a record, soft-delete it using soft_delete_normalized_record(), then verify get_active_normalized_records() does NOT return it.

-- 2. Trash Reads Deleted
-- Verify get_deleted_normalized_records() returns the soft-deleted record.

-- 3. Restore
-- Call restore_normalized_record() on the deleted record, verify get_active_normalized_records() returns it again, and get_deleted_normalized_records() does NOT return it.

-- 4. Cross-org denial
-- Attempt to soft_delete, restore, or update classification of a record belonging to another organization. Verify it throws 'Unauthorized' or fails to update (returns empty/0 rows affected or error depending on implementation).

-- 5. Category assigned to org accepted
-- Create a category globally, assign it to the org. Call update_record_classification() with this category ID. Verify the category_id is updated on the record.

-- 6. Category not assigned rejected
-- Create a category globally but DO NOT assign it to the org. Call update_record_classification(). Verify it throws 'Category ID is not assigned to this organization or is inactive'.

-- 7. Activity same
-- Repeat the above test for update_record_classification() with an unassigned activity_id. Verify it throws 'Activity ID is not assigned to this organization or is inactive'.

-- 8. Unauthorized role rejected
-- Log in as a user with role 'GUEST'. Attempt to call soft_delete_normalized_record(). Verify it throws 'Unauthorized: Requires REVIEWER or ADMIN role'.

-- 9. Category CRUD
-- As ADMIN, create_global_tax_category(), update_global_tax_category(), assign_tax_category_to_org(), unassign_tax_category_from_org(). Verify tables are correctly updated and audit events are generated.

-- 10. Activity CRUD
-- As ADMIN, create_global_economic_activity(), update_global_economic_activity(), assign_economic_activity_to_org(), unassign_economic_activity_from_org(). Verify tables are correctly updated and audit events are generated.

-- 11. Bulk Update Classification
-- Use bulk_update_record_classification() to update all active records for a given CUIT within a date range. Verify it updates both category and activity, ignores soft-deleted records, correctly handles unauthorized users, validates category/activity assignments, and creates an audit event.

-- 12. IIBB Rates
-- Insert a rate into eco_org_activity_iibb_rates for an organization and activity. Verify RLS policies prevent access by other organizations.

-- 13. IIBB Range Regression Matrix
-- 1. closed overlapping closed => REJECT
-- 2. closed adjacent/non-overlapping closed => ACCEPT
-- 3. old closed + future open => ACCEPT
-- 4. future open + past closed => ACCEPT
-- 5. open-start ending before existing begins => ACCEPT
-- 6. open-end beginning after existing ends => ACCEPT
-- 7. open-start overlapping existing => REJECT
-- 8. open-end overlapping existing => REJECT
-- 9. fully open + any active same org/activity/jurisdiction => REJECT
-- 10. inactive historical rate does not block new active rate
-- 11. update excludes itself
-- 12. different jurisdiction does not conflict
-- 13. different activity does not conflict
-- 14. different organization does not conflict

ROLLBACK;
