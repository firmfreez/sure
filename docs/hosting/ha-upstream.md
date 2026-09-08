# Updating the HA fork

HA ingress authentication lives in `HomeAssistantAuthentication`; keep future HA
behavior there and keep hooks in upstream controllers small. The provider constant
in `Authentication` remains an alias for existing callers.

## Prepare an update

Commit or stash local work, then run:

```sh
bin/ha-upstream check
bin/ha-upstream prepare
```

`prepare` fetches upstream main, writes a Git bundle and backup branch, and rebases
into a separate worktree under `.ha-upgrade-backups/upstream/`. The original
checkout stays unchanged. To use an already fetched commit, pass its SHA to
`prepare`. `bin/ha-upstream report REF` only produces a review report.

Enter the printed worktree. Resolve conflicts there and use `git rebase --continue`
or `git rebase --abort`. Review `review.md` and the complete migration diff,
including migrations with timestamps older than the installed schema version.
After review, run in that worktree:

```sh
bin/ha-upstream record-review TARGET_SHA --reviewed-migrations
bin/ha-upstream check
```

Inspect and commit both `config/ha` files along with conflict resolutions. A changed
protected migration cannot be accepted by `record-review`; investigate the HA
compatibility requirement before deliberately changing its protection policy.
Run the full checks in the [development guide](../llm-guides/development.md) before
publishing. These commands do not push, deploy, or access a database.

## Compatibility CI

`HA upstream compatibility` checks migration checksums and upstream ancestry,
tests preparation in temporary Git repositories, and migrates a disposable
PostgreSQL database loaded from the frozen historical fork schema and migration versions in
`test/fixtures/ha_upgrade/`. Keep this source pinned during ordinary updates:
advancing it would stop testing upgrades from that version.

The rehearsal restores the exact applied migration versions, so backdated new
migrations run too. Synthetic records include identically named child categories
under different parents. The existing audit checks that original records and
fields survive. No installation data or secrets are used. The runner requires
CI, a localhost database named `ha_upgrade_ci`, and an empty database; it does not
load Rails configuration or dotenv.

This baseline covers future updates from the pinned fork, not every historical
installation or every data shape. Add explicit regression fixtures when a new
compatibility case is found. A passing rehearsal does not replace a private
pre-deployment backup and upgrade rehearsal for the actual installation.
