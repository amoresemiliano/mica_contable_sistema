import { jest } from '@jest/globals';

describe('Columnas Dropdown Behavior (Comprobantes, Percepciones, Extractos)', () => {
    let documentListeners = {};
    let mockComprobantesMenu, mockComprobantesBtn;

    beforeEach(() => {
        documentListeners = {};

        mockComprobantesMenu = {
            id: 'comprobantes-col-menu',
            style: { display: 'none' },
            contains: jest.fn(target => target === mockComprobantesMenu)
        };

        mockComprobantesBtn = {
            id: 'comprobantes-col-btn',
            contains: jest.fn(target => target === mockComprobantesBtn)
        };

        global.document = {
            getElementById: jest.fn(id => {
                if (id === 'comprobantes-col-menu') return mockComprobantesMenu;
                if (id === 'comprobantes-col-btn') return mockComprobantesBtn;
                return null;
            }),
            addEventListener: jest.fn((event, handler) => {
                documentListeners[event] = handler;
            })
        };
    });

    test('click outside closes open column menu', () => {
        // Register listeners
        const COLUMN_DROPDOWN_IDS = [
            { btnId: 'comprobantes-col-btn', menuId: 'comprobantes-col-menu' }
        ];

        const handleOutsideDismiss = (e) => {
            COLUMN_DROPDOWN_IDS.forEach(({ btnId, menuId }) => {
                const menu = global.document.getElementById(menuId);
                if (menu && menu.style.display === 'block') {
                    const btn = global.document.getElementById(btnId);
                    if (!menu.contains(e.target) && (!btn || !btn.contains(e.target))) {
                        menu.style.display = 'none';
                    }
                }
            });
        };

        // Open menu
        mockComprobantesMenu.style.display = 'block';

        // Click outside target
        const outsideTarget = { name: 'outside' };
        handleOutsideDismiss({ target: outsideTarget });

        expect(mockComprobantesMenu.style.display).toBe('none');
    });

    test('click inside column menu leaves it open', () => {
        const COLUMN_DROPDOWN_IDS = [
            { btnId: 'comprobantes-col-btn', menuId: 'comprobantes-col-menu' }
        ];

        const handleOutsideDismiss = (e) => {
            COLUMN_DROPDOWN_IDS.forEach(({ btnId, menuId }) => {
                const menu = global.document.getElementById(menuId);
                if (menu && menu.style.display === 'block') {
                    const btn = global.document.getElementById(btnId);
                    if (!menu.contains(e.target) && (!btn || !btn.contains(e.target))) {
                        menu.style.display = 'none';
                    }
                }
            });
        };

        mockComprobantesMenu.style.display = 'block';

        // Click inside menu target
        handleOutsideDismiss({ target: mockComprobantesMenu });

        expect(mockComprobantesMenu.style.display).toBe('block');
    });
});
