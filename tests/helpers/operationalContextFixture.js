import { jest } from '@jest/globals';

// Canonical server contract for older catalog tests; never authorizes via role strings.
export function operationalContextFixture(store, service) {
    let org = null;
    store.contextState = 'PLATFORM_READY';
    store.permissions.platform = { loaded: true, codes: ['ACCESS_ANY_ORG', 'GLOBAL_CATALOG_MANAGE', 'GLOBAL_CATALOG_VIEW'] };
    jest.spyOn(service, 'switchSuperadminOrgContext').mockImplementation(async id => { org = id; });
    jest.spyOn(service, 'getOperationalContext').mockImplementation(async () => ({
        organization_id: org, organization_name: org, profile_name: 'Platform owner'
    }));
    jest.spyOn(service, 'listOperationalOrgTargets').mockResolvedValue([]);
    jest.spyOn(service, 'loadMyEffectiveCapabilities').mockImplementation(async () =>
        ['ACCESS_ANY_ORG', 'GLOBAL_CATALOG_MANAGE', 'GLOBAL_CATALOG_VIEW'].map(code => ({ code, scope: 'PLATFORM', organization_id: null })));
    jest.spyOn(service, 'loadOperationalSnapshot').mockResolvedValue({ items: [], perceptions: [], bankTransactions: [],
        salariesList: [], taxCategories: [], economicActivities: [], displayedEconomicActivities: [], iibbRates: [] });
}
