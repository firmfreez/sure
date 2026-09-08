# HA fork update — 28 October 2026

The HA overlay is rebased from upstream `eff81c2dacaa329d57d79ecd3f2815ec5cdd9b9e`
onto `a6767e93114a0db5136ea91512bd985018597322` (519 upstream commits;
upstream version `0.7.6-alpha.10`; HA release `0.7.6-alpha.10-ha-2`). The original fork commit
`643bd167e` is retained in `backup/ha-before-upstream-20261028-093947-7407d4`
and in the local Git bundle created by `bin/ha-upstream prepare`. All HA
customizations are consolidated into one commit whose direct parent is the
reviewed upstream target.

## Compatibility decisions

- Retain HA HTTP/WebSocket authentication, ingress paths and assets, existing
  identities, and the current-month/hidden-AI-sidebar defaults.
- Keep category uniqueness within each parent. Transaction and account activity
  filters share family-scoped category IDs, including the stable Uncategorized
  sentinel. Legacy category-name links still work; an actual category named
  Uncategorized takes precedence over its historical translated bucket label.
- Preserve immediate updates of account balances and complete transfer deletion.
  Deletion requires write access to both endpoints and every fee account. The
  upstream rejection flow can still unlink a suggested match from one endpoint.
- Immediate balance refreshes require complete FX data and roll back all involved
  accounts together when a rate is missing. Background syncs retain upstream's
  partial-result behavior and support diagnostics.
- Fixed-loan payments use the current balance and remaining term through the new
  upstream amortization engine, including its currency precision and day-count
  conventions. Contractual schedules and payoff projections retain their own
  original principal.
- Keep upstream picker improvements and DS primitives alongside mobile menus,
  keyboard handling, navigation destinations and localized transfer names.
- Keep new money inputs empty until an amount is entered. Category search retains
  a matching child's parent, Enter selects an existing result, and longer lists
  fit the available viewport on desktop and mobile.
- New transfers start with an empty source amount, including after account
  selection and leaving the field.
- Switching expense, income and transfer forms carries the entered amount and
  name. Transfers keep the transaction name hidden for switching back. Changing
  the transfer source fills an empty destination with its previous source, or
  swaps the two accounts when the current destination is chosen as the source.
- Add a shortcut beside each activity day's balance to create an entry on that
  date. New expense, income, transfer and trade forms remember the user's last
  entered date; the shared date field has a Today action using the family timezone.

## Migrations

Reviewed all 56 added upstream migrations, including backdated versions before
`20260904201444`, the previous schema maximum. No existing migration was changed
by this update. All seven protected HA migration checksums and the frozen
historical schema/version fixtures remain unchanged. Both files in `config/ha`
record the reviewed target.

Several new upstream migrations intentionally transform provider data: Warsaw
price currencies, Kraken trade signs, Trade Republic labels and bond prices,
pending transfer kinds, recurring series on investment accounts, obsolete
provider identifier columns, invalid FX rates, and classifier rules. The
synthetic rehearsal verifies the frozen HA baseline and hierarchy; it does not
claim coverage of every provider payload or private installation.

The rehearsal now boots real Rails models in test mode, after validating the
empty localhost `ha_upgrade_ci` database, with dotenv files disabled. This is
needed for model-backed upstream data migrations. Background jobs remain in the
test adapter. The production database and installed HA add-on were not changed.

## Verification

Checks run in a disposable Docker project with Ruby 3.4.9, PostgreSQL 18,
Redis 7 and Chromium.
Ruby CI jobs, including HA compatibility, use Ubuntu 24.04 because the pinned
`ruby/setup-ruby` action does not support Ubuntu 26.04.
The Helm chart version follows `.sure-version` and its default image repository
is `ghcr.io/firmfreez/sure`, where HA release tags are published.

- Full Rails suite: 13,681 tests, 62,809 assertions, 0 failures, 0 errors, 36 skips.
- Encryption checks with disposable keys: 174 tests, 739 assertions, no failures,
  errors or skips.
- All 331 system tests: 1,742 assertions, 0 failures or errors. The 69 system-test
  files ran across four containers, each with its own test database, temporary
  storage and asset build directory; in-process parallelization stayed disabled.
- HA preparation tests: 3 tests, 10 assertions, no failures or errors.
- HA migration/checksum/ancestry check and frozen-schema migration rehearsal pass.
- RuboCop, ERB and Biome lint pass; Brakeman reports 0 warnings.

The browser suite covers the empty amount input, category hierarchy and keyboard
selection, longer category lists on desktop and mobile, activity date shortcuts,
remembering a date across forms, and the Today action.

The optional whole-repository `npm run format:check` reports existing formatting
issues (75 diagnostics); global formatting changes are excluded from this sync.
