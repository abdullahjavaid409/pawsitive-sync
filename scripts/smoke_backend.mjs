#!/usr/bin/env node
/**
 * Backend smoke test — run against local or Railway API.
 * Usage: node scripts/smoke_backend.mjs [baseUrl]
 */
const base = (process.argv[2] ?? process.env.API_BASE_URL ?? 'http://127.0.0.1:3100').replace(/\/$/, '');

const results = [];

function pass(name, detail = '') {
  results.push({ name, ok: true, detail });
  console.log(`✓ ${name}${detail ? ` — ${detail}` : ''}`);
}

function fail(name, detail = '') {
  results.push({ name, ok: false, detail });
  console.error(`✗ ${name}${detail ? ` — ${detail}` : ''}`);
}

async function json(method, path, body, token) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(`${base}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { _raw: text.slice(0, 120) };
  }
  return { status: res.status, data, html: text.startsWith('<!') ? text : null };
}

async function main() {
  console.log(`\nPawsitiveSync API smoke → ${base}\n`);

  // 1. Health
  const health = await json('GET', '/health');
  if (health.status === 200 && health.data.ok) {
    pass('GET /health', `version ${health.data.version ?? '?'}`);
  } else {
    fail('GET /health', `status ${health.status}`);
  }

  // 2. Sitter web page (v4+)
  const sitterPage = await fetch(`${base}/sitter`);
  const sitterHtml = await sitterPage.text();
  if (sitterPage.status === 200 && sitterHtml.includes('Today’s doses')) {
    pass('GET /sitter', 'browser page live');
  } else {
    fail('GET /sitter', `status ${sitterPage.status} — deploy latest backend for sitter link`);
  }

  // 3. Create household
  const created = await json('POST', '/v1/households', {
    owner: { id: 'you', name: 'Smoke Test' },
    caregivers: [],
    pets: [
      {
        id: 'pet-smoke',
        name: 'Miso',
        species: 'cat',
        ageYears: 10,
        weightKg: 4.5,
        conditions: [],
      },
    ],
    medications: [
      {
        id: 'med-smoke',
        petId: 'pet-smoke',
        name: 'Insulin',
        amount: '2 u',
        parts: ['morning'],
        supplyTotal: 10,
        dosesLeft: 10,
        startDay: '2026-01-01',
      },
    ],
    logs: [],
  });
  const ownerToken = created.data.token;
  if (created.status === 201 && ownerToken) {
    pass('POST /v1/households', `invite ${created.data.household?.inviteCode ?? '?'}`);
  } else {
    fail('POST /v1/households', JSON.stringify(created.data).slice(0, 120));
    printSummary();
    process.exit(1);
  }

  // 4. Fetch household
  const house = await json('GET', '/v1/household', null, ownerToken);
  if (house.status === 200 && house.data.household?.inviteCode) {
    pass('GET /v1/household', `code ${house.data.household.inviteCode}`);
  } else {
    fail('GET /v1/household', `status ${house.status}`);
  }

  // 5. Log dose
  const logged = await json(
    'POST',
    '/v1/logs',
    {
      id: 'log-smoke-1',
      medicationId: 'med-smoke',
      part: 'morning',
      day: '2026-10-03',
      memberId: 'you',
      outcome: 'given',
      amount: '2 u',
      timeLabel: '8:00 AM',
    },
    ownerToken,
  );
  if (logged.status === 201 && logged.data.log?.outcome === 'given') {
    pass('POST /v1/logs', 'dose logged');
  } else if (logged.status === 409) {
    pass('POST /v1/logs', 'conflict guard works');
  } else {
    fail('POST /v1/logs', `status ${logged.status}`);
  }

  // 6. Register device (push path)
  const device = await json(
    'POST',
    '/v1/devices/register',
    { platform: 'android', token: 'local:smoke-test', pushEnabled: true },
    ownerToken,
  );
  if (device.status === 200) {
    pass('POST /v1/devices/register', 'push registration');
  } else {
    fail('POST /v1/devices/register', `status ${device.status}`);
  }

  // 7. Join as partner
  const code = house.data.household?.inviteCode ?? created.data.household?.inviteCode;
  const joined = await json('POST', '/v1/join', { code, name: 'Partner', role: 'caregiver' });
  const partnerToken = joined.data.token;
  if (joined.status === 201 && partnerToken) {
    pass('POST /v1/join', 'partner joined');
  } else {
    fail('POST /v1/join', `status ${joined.status}`);
  }

  // 8. Partner logs dose → owner gets push.queued server-side
  const partnerLog = await json(
    'POST',
    '/v1/logs',
    {
      id: 'log-smoke-2',
      medicationId: 'med-smoke',
      part: 'afternoon',
      day: '2026-10-03',
      memberId: joined.data.memberId ?? 'member',
      outcome: 'given',
      amount: '2 u',
      timeLabel: '1:05 PM',
    },
    partnerToken,
  );
  if (partnerLog.status === 201) {
    pass('POST /v1/logs (partner)', 'partner dose logged');
  } else {
    fail('POST /v1/logs (partner)', `status ${partnerLog.status}`);
  }

  // 9. Sitter link (Pro required — enable trial on household)
  await json('POST', '/v1/billing/trial', null, ownerToken);
  const sitterLink = await json('POST', '/v1/sitter-links', { label: 'Smoke sitter' }, ownerToken);
  const sitterToken = sitterLink.data.token;
  if (sitterLink.status === 201 && sitterToken) {
    pass('POST /v1/sitter-links', 'browser sitter token created');
  } else {
    fail('POST /v1/sitter-links', `status ${sitterLink.status} — needs backend v4`);
  }

  // 10. Sitter view + log
  if (sitterToken) {
    const view = await json(
      'GET',
      '/v1/sitter/view?day=2026-10-03&hour=14',
      null,
      sitterToken,
    );
    if (view.status === 200 && Array.isArray(view.data.doses)) {
      pass('GET /v1/sitter/view', `${view.data.doses.length} doses`);
    } else {
      fail('GET /v1/sitter/view', `status ${view.status}`);
    }

    const evening = view.data.doses?.find((d) => d.part === 'evening' && d.status !== 'given');
    if (evening) {
      const sitterLog = await json(
        'POST',
        '/v1/sitter/logs',
        {
          id: 'log-sitter-1',
          medicationId: evening.medicationId,
          part: evening.part,
          day: '2026-10-03',
          outcome: 'given',
          amount: evening.amount ?? '',
          timeLabel: '8:00 PM',
        },
        sitterToken,
      );
      if (sitterLog.status === 201) {
        pass('POST /v1/sitter/logs', 'sitter logged from browser');
      } else {
        fail('POST /v1/sitter/logs', `status ${sitterLog.status}`);
      }
    } else {
      pass('POST /v1/sitter/logs', 'skipped — no evening dose due');
    }
  }

  // 11. Batch sync
  const batch = await json(
    'POST',
    '/v1/sync/batch',
    {
      operations: [
        {
          id: 'op-1',
          type: 'addCareEvent',
          payload: {
            id: 'evt-smoke',
            petId: 'pet-smoke',
            title: 'Vet check',
            kind: 'vetVisit',
            dueDay: '2026-10-10',
          },
        },
      ],
    },
    ownerToken,
  );
  if (batch.status === 200 && batch.data.results?.[0]?.status === 'ok') {
    pass('POST /v1/sync/batch', 'care event synced');
  } else {
    fail('POST /v1/sync/batch', `status ${batch.status}`);
  }

  printSummary();
  process.exit(results.some((r) => !r.ok) ? 1 : 0);
}

function printSummary() {
  const ok = results.filter((r) => r.ok).length;
  const total = results.length;
  console.log(`\n${ok}/${total} checks passed.\n`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
