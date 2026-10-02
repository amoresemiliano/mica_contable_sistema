import fs from 'fs';
import path from 'path';

describe('REAL DOM Integration Tests (index.html structure validation)', () => {
    let htmlContent;

    beforeAll(() => {
        const htmlPath = path.resolve(process.cwd(), 'index.html');
        htmlContent = fs.readFileSync(htmlPath, 'utf8');
    });

    test('NO debe contener botones obsoletos "Solo Compras" ni "Solo Ventas"', () => {
        expect(htmlContent).not.toContain('>Solo Compras<');
        expect(htmlContent).not.toContain('>Solo Ventas<');
    });

    test('NO debe contener dropdown duplicado de filtros en comprobantes', () => {
        expect(htmlContent).not.toContain('class="mobile-filter-select-wrapper"');
        expect(htmlContent).not.toContain('class="mobile-filter-select"');
    });

    test('NO debe contener botón de Cerrar Sesión en el header superior (logout único en sidebar)', () => {
        expect(htmlContent).not.toContain('id="logout-btn"');
    });

    test('debe incluir selector de Período, selector de Columnas y Búsqueda con X en Comprobantes', () => {
        expect(htmlContent).toContain('id="comprobantes-period-filter"');
        expect(htmlContent).toContain('id="comprobantes-col-btn"');
        expect(htmlContent).toContain('id="comprobantes-search-clear"');
    });

    test('los catálogos impositivos deben estar en tab-categorizacion y NO en tab-configuracion', () => {
        expect(htmlContent).toContain('id="tab-categorizacion"');
        
        // Extraer contenido de tab-categorizacion
        const categorizacionSection = htmlContent.substring(
            htmlContent.indexOf('id="tab-categorizacion"'),
            htmlContent.indexOf('</section>', htmlContent.indexOf('id="tab-categorizacion"'))
        );

        expect(categorizacionSection).toContain('table-tax-categories-body');
        expect(categorizacionSection).toContain('table-economic-activities-body');
        expect(categorizacionSection).toContain('table-iibb-rates-body');
        expect(categorizacionSection).toContain('table-iva-rates-body');

        // Verificar que tab-configuracion no contenga esos catálogos
        const configuracionSection = htmlContent.substring(
            htmlContent.indexOf('id="tab-configuracion"'),
            htmlContent.indexOf('</section>', htmlContent.indexOf('id="tab-configuracion"'))
        );

        expect(configuracionSection).not.toContain('table-tax-categories-body');
        expect(configuracionSection).not.toContain('table-economic-activities-body');
        expect(configuracionSection).not.toContain('table-iibb-rates-body');
    });
});
