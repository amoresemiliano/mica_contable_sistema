// Offline guard for local variables reused as SQL aliases in the same dollar-quoted block.
// This is intentionally a static check, not a PostgreSQL parser or runtime validation.
import {readFileSync} from 'node:fs';
const files=[
    'sql/039g_delegate_organization_create.sql','sql/039g_delegate_organization_create_down.sql',
    'sql/039h_operational_administration.sql','sql/039h_operational_administration_down.sql',
    'sql/039g_revised_release.sql','sql/039g_preflight_readonly.sql','sql/039h_preflight_readonly.sql',
    'tests/db/039g_delegate_organization_create.sql','tests/db/039h_operational_administration.sql',
    'tests/db/039h_membership_roundtrip.sql'
];
const withoutLiterals = sql => sql.replace(/'(?:''|[^'])*'|--[^\n]*|\/\*[\s\S]*?\*\//g,' ');
function aliasCollisions(sql) {
    const collisions=[];
    for(const [index,match] of [...sql.matchAll(/(\$(?:[a-z_]\w*)?\$)([\s\S]*?)\1/gi)].entries()) {
        const body=withoutLiterals(match[2]).toLowerCase();
        const declaration=body.match(/\bdeclare\b([\s\S]*?)\bbegin\b/);
        if(!declaration) continue;
        const variables=new Set(declaration[1].split(';').map(s=>s.trim().match(/^([a-z_]\w*)\s+/)?.[1]).filter(Boolean));
        const aliases=new Set([
            // Relation aliases, explicit AS aliases and aliases after derived tables/functions.
            ...body.matchAll(/\b(?:from|join|update)\s+(?:[a-z_]\w*\.)?[a-z_]\w*\s+(?:as\s+)?([a-z_]\w*)\b/g),
            ...body.matchAll(/\)\s+(?:as\s+)?([a-z_]\w*)\b/g),
            ...body.matchAll(/\bas\s+([a-z_]\w*)\b/g)
        ].map(m=>m[1]));
        for(const variable of variables) if(aliases.has(variable)) collisions.push({block:index,variable});
    }
    return collisions;
}
test.each(['r','a','t'])('detects collision with local record %s',name=>{
    expect(aliasCollisions(`DO $check$ DECLARE ${name} RECORD; BEGIN
        IF NOT EXISTS(SELECT 1 FROM public.example ${name} WHERE ${name}.id=1) THEN NULL; END IF;
        END; $check$;`)).toEqual([{block:0,variable:name}]);
});
test('detects scalar and derived-table alias collisions too',()=>{
    expect(aliasCollisions('DO $$ DECLARE target UUID; BEGIN SELECT target.id FROM (SELECT 1 AS id) AS target; END; $$;'))
        .toEqual([{block:0,variable:'target'}]);
});
test('aliases in other blocks and quoted strings do not collide',()=>{
    expect(aliasCollisions("DO $$ DECLARE r RECORD; BEGIN RAISE NOTICE 'FROM example r'; END; $$; SELECT r.id FROM example r; DO $$ BEGIN SELECT r.id FROM example r; END; $$;"))
        .toEqual([]);
});
test('INTO STRICT names a destination variable, not a relation alias',()=>{
    expect(aliasCollisions('DO $$ DECLARE snapshot RECORD; BEGIN SELECT * INTO STRICT snapshot FROM example e; END; $$;')).toEqual([]);
});
test.each(files)('%s has no local-variable/SQL-alias collisions',file=>{
    expect(aliasCollisions(readFileSync(file,'utf8'))).toEqual([]);
});
test('reintroducing the original preflight variable reproduces the reported alias collision',()=>{
    const originalNaming=readFileSync(files[0],'utf8').replace(/\bv_row\b/g,'r');
    expect(aliasCollisions(originalNaming)).toContainEqual({block:0,variable:'r'});
});
