/**
 * Startup script for staging deployments.
 *
 * When CLONE_DB_ON_DEPLOY=true, restores the Neon `staging` branch in-place
 * from the production branch once per RENDER_GIT_COMMIT (so Render free-tier
 * sleep/wake restarts do not wipe staging data).
 */
const { PrismaClient } = require('@prisma/client');

async function neonRequest(url, apiKey, opts = {}) {
  const res = await fetch(url, {
    ...opts,
    headers: {
      Authorization: `Bearer ${apiKey}`,
      Accept: 'application/json',
      'Content-Type': 'application/json',
      ...(opts.headers || {}),
    },
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Neon API ${opts.method || 'GET'} ${url} failed (${res.status}): ${text}`);
  }
  return text ? JSON.parse(text) : {};
}

async function alreadyClonedForCommit(commit) {
  if (!commit || !process.env.DATABASE_URL) return false;
  const prisma = new PrismaClient();
  try {
    await prisma.$executeRawUnsafe(
      'CREATE TABLE IF NOT EXISTS _staging_deploy_meta (id INT PRIMARY KEY, git_commit TEXT NOT NULL, cloned_at TIMESTAMPTZ NOT NULL DEFAULT NOW())',
    );
    const rows = await prisma.$queryRawUnsafe(
      'SELECT git_commit FROM _staging_deploy_meta WHERE id = 1',
    );
    return Array.isArray(rows) && rows[0]?.git_commit === commit;
  } catch (err) {
    console.warn(`[clone-staging-db] Could not read _staging_deploy_meta: ${err.message}`);
    return false;
  } finally {
    await prisma.$disconnect().catch(() => {});
  }
}

async function recordClonedCommit(commit) {
  if (!commit || !process.env.DATABASE_URL) return;
  const prisma = new PrismaClient();
  try {
    await prisma.$executeRawUnsafe(
      'CREATE TABLE IF NOT EXISTS _staging_deploy_meta (id INT PRIMARY KEY, git_commit TEXT NOT NULL, cloned_at TIMESTAMPTZ NOT NULL DEFAULT NOW())',
    );
    await prisma.$executeRawUnsafe(
      'INSERT INTO _staging_deploy_meta (id, git_commit, cloned_at) VALUES (1, $1, NOW()) ON CONFLICT (id) DO UPDATE SET git_commit = EXCLUDED.git_commit, cloned_at = NOW()',
      commit,
    );
  } catch (err) {
    console.warn(`[clone-staging-db] Could not record _staging_deploy_meta: ${err.message}`);
  } finally {
    await prisma.$disconnect().catch(() => {});
  }
}

async function main() {
  if (process.env.CLONE_DB_ON_DEPLOY !== 'true') {
    return;
  }

  const apiKey = process.env.NEON_API_KEY;
  const projectId = process.env.NEON_PROJECT_ID;
  if (!apiKey || !projectId) {
    console.warn('[clone-staging-db] NEON_API_KEY or NEON_PROJECT_ID not set; skipping DB clone.');
    return;
  }

  const commit = process.env.RENDER_GIT_COMMIT || '';
  if (commit && (await alreadyClonedForCommit(commit))) {
    console.log(`[clone-staging-db] Staging DB already cloned for commit ${commit.slice(0, 7)} (wake from sleep). Skipping.`);
    return;
  }

  const base = `https://console.neon.tech/api/v2/projects/${projectId}`;
  const { branches } = await neonRequest(`${base}/branches`, apiKey);

  let prodBranchId = process.env.NEON_PROD_BRANCH_ID;
  if (!prodBranchId) {
    const primary = branches.find((b) => b.primary || b.default || b.name === 'main' || b.name === 'production');
    if (!primary) throw new Error('Could not determine production Neon branch ID.');
    prodBranchId = primary.id;
  }

  let stagingBranchId = process.env.NEON_STAGING_BRANCH_ID;
  if (!stagingBranchId) {
    const staging = branches.find((b) => b.name === 'staging');
    if (!staging) throw new Error('Could not find Neon branch named "staging" (or set NEON_STAGING_BRANCH_ID).');
    stagingBranchId = staging.id;
  }

  console.log(`[clone-staging-db] Restoring Neon staging branch (${stagingBranchId}) from prod (${prodBranchId})...`);
  await neonRequest(`${base}/branches/${stagingBranchId}/restore`, apiKey, {
    method: 'POST',
    body: JSON.stringify({ source_branch_id: prodBranchId }),
  });

  if (commit) {
    await recordClonedCommit(commit);
  }
  console.log('[clone-staging-db] Staging DB clone complete.');
}

main().catch((err) => {
  console.error('[clone-staging-db] Failed:', err.message);
  process.exit(0); // Non-fatal so container can still boot and report health/logs
});
