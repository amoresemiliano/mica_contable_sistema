import {buildBusinessHealth} from '../src/js/core/metrics/engine.js';
import {reportingData} from './fixtures/reporting.js';
import {renderMetricsView} from '../src/js/components/metricOverview.js';
import {financeHeader,statusChip} from '../src/js/components/financeUi.js';

test('visual composition preserves canonical values, recommendations and missing-data contract',()=>{
 const health=buildBusinessHealth(reportingData(),{from:'2026-09-01',to:'2026-09-30'}),before=structuredClone(health);
 for(const view of ['Salud','Rentabilidad','Liquidez','Operación','Riesgos y prioridades'])renderMetricsView(health,view);
 expect(health).toEqual(before);
 const html=renderMetricsView(health,'Salud');expect(html).toContain('No determinable');expect(html).not.toContain('null / 100');
 expect((html.match(/finance-priority-number/g)||[]).length).toBe(health.priorities.length);
});
test('display helpers escape organization and evidence text',()=>{
 expect(financeHeader('<script>bad</script>','<img src=x>')).not.toContain('<script>');expect(statusChip('<img>')).toContain('&lt;img&gt;');
 const health=buildBusinessHealth(reportingData(),{from:'2026-09-01',to:'2026-09-30'});
 health.priorities[0].explanation='<img src=x onerror=alert(1)>';
 expect(renderMetricsView(health,'Salud')).not.toContain('<img');
});
