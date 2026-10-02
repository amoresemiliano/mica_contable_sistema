import { parseF883ActivitiesTxt } from '../../src/js/core/parsers/activitiesParser.js';
import fs from 'fs';
import path from 'path';

describe('ARCA F883 Economic Activities Parser', () => {
    test('parsa correctamente líneas sintéticas con encabezado y delimitador final ;', () => {
        const txtContent = `COD_ACTIVIDAD_F883;DESC_ACTIVIDAD_F883;DESCL_ACTIVIDA_F883;\n011111;Cultivo de arroz;Cultivo de arroz;\n011112;Cultivo de trigo;Cultivo de trigo;\n`;
        const result = parseF883ActivitiesTxt(txtContent);

        expect(result.validRows).toBe(2);
        expect(result.invalidRows).toBe(0);
        expect(result.duplicateCodes).toBe(0);
        expect(result.validActivities[0]).toEqual({
            arca_code: '011111',
            name: 'Cultivo de arroz',
            description: 'Cultivo de arroz',
            is_active: true
        });
    });

    test('preserva estrictamente los ceros a la izquierda en los códigos (ej. 011111, 000007)', () => {
        const txtContent = `000007;Jubilado;Jubilado;\n000008;Estudiante;Estudiante;\n000012;Sin Actividad Economica;Sin Actividad Economica;\n`;
        const result = parseF883ActivitiesTxt(txtContent);

        expect(result.validRows).toBe(3);
        expect(result.validActivities[0].arca_code).toBe('000007');
        expect(result.validActivities[1].arca_code).toBe('000008');
        expect(result.validActivities[2].arca_code).toBe('000012');
    });

    test('limpia espacios circundantes y pestañas (tabs)', () => {
        const txtContent = `  011121 \t; \t Cultivo de maíz \t ; \t Cultivo de maíz \t ;  \n`;
        const result = parseF883ActivitiesTxt(txtContent);

        expect(result.validRows).toBe(1);
        expect(result.validActivities[0]).toEqual({
            arca_code: '011121',
            name: 'Cultivo de maíz',
            description: 'Cultivo de maíz',
            is_active: true
        });
    });

    test('maneja adecuadamente líneas malformadas sin descartar silenciosamente', () => {
        const txtContent = `011111;Cultivo de arroz;Cultivo de arroz;\nLINEA_INVALIDA_SIN_PUNTO_Y_COMA\n011112;Cultivo de trigo;Cultivo de trigo;\n`;
        const result = parseF883ActivitiesTxt(txtContent);

        expect(result.validRows).toBe(2);
        expect(result.invalidRows).toBe(1);
        expect(result.malformedLines[0].lineNumber).toBe(2);
    });

    test('maneja duplicados determinísticamente registrando métricas de duplicados', () => {
        const txtContent = `011111;Cultivo de arroz v1;Cultivo de arroz v1;\n011111;Cultivo de arroz v2;Cultivo de arroz v2;\n`;
        const result = parseF883ActivitiesTxt(txtContent);

        expect(result.validRows).toBe(1);
        expect(result.duplicateCodes).toBe(1);
        expect(result.validActivities[0].name).toBe('Cultivo de arroz v2');
    });

    test('parsa exitosamente el archivo real ACTIVIDADES_ECONOMICAS_F883.txt', () => {
        const filePath = path.join(process.cwd(), 'tests', 'fixtures', 'ACTIVIDADES_ECONOMICAS_F883.txt');
        if (fs.existsSync(filePath)) {
            const rawText = fs.readFileSync(filePath, 'utf-8');
            const result = parseF883ActivitiesTxt(rawText);

            expect(result.validRows).toBeGreaterThan(500); // El archivo real tiene más de 900 actividades
            expect(result.previewRows.length).toBe(10);
            
            // Verificar inclusión de códigos especiales
            const jubilado = result.validActivities.find(a => a.arca_code === '000007');
            expect(jubilado).toBeDefined();
            expect(jubilado.name).toBe('Jubilado');
        }
    });
});
