import { readFileSync, readdirSync } from 'node:fs';

const functionPattern = /CREATE OR REPLACE FUNCTION public\.persist_financial_movements_batch\([\s\S]*?\r?\n\$\$;/i;
const readSql = name => readFileSync(`sql/${name}`, 'utf8').replace(/\r\n/g, '\n');
const definition = sql => {
    const match = sql.match(functionPattern);
    if (!match) throw new Error('persist_financial_movements_batch definition missing');
    return match[0];
};
const migrationName = '029_fix_import_row_duplicate_status.sql';
const migration = readSql(migrationName);
const previous = definition(readSql('028_fix_source_file_reuse_and_retry_flow.sql'));
const current = definition(migration);
// Resolve the latest forward migration defining this RPC, excluding rollback files.
const latestName = readdirSync('sql')
    .filter(name => /^\d+.*\.sql$/.test(name) && !name.endsWith('_down.sql'))
    .sort((a, b) => a.localeCompare(b, 'en', { numeric: true }))
    .filter(name => functionPattern.test(readSql(name)))
    .at(-1);
const latest = definition(readSql(latestName));

describe('eco_import_rows.parse_status regression', () => {
    test('029 changes only the exact-identity duplicate status from 028', () => {
        const oldStatus = "parse_status = 'DUPLICATE'";
        expect(previous.split(oldStatus)).toHaveLength(2);
        expect(current).toBe(previous.replace(oldStatus, "parse_status = 'EXACT_DUPLICATE'"));
        expect(migration.replace(current, '').replace(/--[^\n]*/g, '').trim())
            .toMatch(/^BEGIN;\s*COMMIT;$/);
    });

    test('latest definition writes EXACT_DUPLICATE for an existing identity_key', () => {
        expect(latest).not.toMatch(/\bparse_status\s*=\s*'DUPLICATE'/i);
        expect(latest).not.toMatch(/\bv_row_status\s*:=\s*'DUPLICATE'/i);
        expect(latest).toMatch(/AND identity_key = v_computed_identity_key\s+AND deleted_at IS NULL LIMIT 1;\s+IF v_existing_mvmt_id IS NOT NULL THEN\s+v_duplicate_cnt := v_duplicate_cnt \+ 1;\s+UPDATE public\.eco_import_rows SET parse_status = 'EXACT_DUPLICATE' WHERE id = v_row_id;/);
    });

    test('latest definition preserves ACCEPTED and INVALID in the row log', () => {
        expect(latest).toContain("v_row_status := 'ACCEPTED';");
        expect(latest).toMatch(/IF v_is_invalid THEN\s+v_row_status := 'INVALID';\s+END IF;/);
        expect(latest).toMatch(/INSERT INTO public\.eco_import_rows\s*\([^)]*\bparse_status\s*\) VALUES \([\s\S]*?v_row_status\s*\) RETURNING id INTO v_row_id;/);
    });
});
