# Engineering instructions

These are the standing instructions for every agent working in this repository. Follow them on every task. The user’s task prompt or handover should provide only the task, scope, and task-specific context; do not require the user to repeat these rules.

Use British English in documentation and player-facing text. Use `--!strict` where Roblox APIs permit it. Keep modules small, typed, and configuration-first.

## Before each task

1. Read these instructions and the current task or handover in full.
2. Fetch or otherwise verify live `main`; GitHub is the source of truth. Do not rely on remembered SHAs, old audits, local-only commits, or handover claims without checking them.
3. Inspect every open PR, record its current head SHA and state, and check its latest CI status at that exact SHA. Inspect diffs for PRs that overlap the task’s files or behaviour. Leave unrelated PRs alone.
4. Check the exact current `main` validation status.
5. Read the complete implementation, tests, and relevant docs/config for the assigned task before editing.
6. Identify whether an existing PR already covers the task and who owns it. Continue that PR when appropriate; do not create a duplicate.

If a required GitHub or CI check cannot be accessed, state what could not be verified. Never claim it was checked or passed.

## Task scope and branch ownership

- Work only within the scope assigned by the current prompt or handover. Do not broaden the task into unrelated refactoring or features.
- Never commit directly to `main`. Use a dedicated branch and PR for each isolated task.
- Do not modify another agent’s branch or PR unless the user assigns it to you or the task owner and scope are clear.
- Do not repurpose a branch or PR for unrelated work.
- If a matching PR exists, continue it instead of opening another. If duplicate PRs already exist and the canonical one is unclear, do not close either; report the candidates and ask for direction only if needed to proceed safely.

## PR lifecycle and failure recovery

- Never close a PR, delete its branch, or abandon its work unless the user explicitly asks.
- A stale, failing, cancelled, pending, or behind PR is not a reason to close it or create a replacement.
- Before pushing, rebasing, force-pushing, or merging, recheck the PR state, branch, and current head SHA.
- Preserve the existing branch and PR history where practical. Do not force-push unless the branch is yours, it is necessary, and the resulting diff has been reviewed.
- Diagnose failures from the exact check and its logs. Fix code failures on the existing branch; rerun transient or infrastructure failures as appropriate.
- If `main` moves, refresh the existing PR branch using the repository’s required method, inspect the complete resulting diff, and rerun required checks on the new head SHA.
- If a PR closes unexpectedly, determine whether it was merged or closed and why. If it is your task’s PR and it was closed accidentally, reopen and continue where possible. Do not automatically create a replacement.
- Continue until the assigned task is complete or a specific blocker prevents safe progress. Do not stop at “CI failed” without diagnosing it and stating the next action.

## Merge and verification gates

- Review the complete PR diff before merging. Check for unrelated changes, regressions, and accidental or generated files.
- Merge only when required checks are green on the exact current PR head SHA and the branch meets the repository’s current-main requirements.
- A green check from an earlier SHA does not count after the PR head changes.
- After each merge, verify the merge commit and required checks on live `main` before starting dependent work.
- Do not call work complete, safe, or green based only on inspection when CI can verify it.

## Dependency rules

- `shared` modules must not depend on client or server modules.
- Client controllers may depend only on replicated shared modules, remotes, and other controllers through the client context.
- Services receive dependencies through `context.Services`; never require another service module directly.
- Register services explicitly in `init.server.luau` in dependency order. Circular dependencies are forbidden.
- `Init` stores dependencies and registers infrastructure; `Start` connects events and begins work; `Destroy` releases connections/state.
- A required service failure aborts startup. Mark only genuinely degradable integrations `Optional = true`.

## Authority boundaries

- Only `DataService` accesses persistent DataStores.
- Only `EconomyService` changes balances.
- Only role, spawn, uniform and loadout services assign their corresponding runtime state.
- Never trust client prices, rewards, ownership, access, model IDs, placements, task completion, or purchase success.
- Register all remotes centrally through `NetworkServer`, with a schema, rate limit and sanitised envelope.
- Persistent records use stable string IDs and serialised primitives, never Instances, Enums, CFrames or Vector3s.

## Reliability and performance

- Clean up player state when a player leaves.
- Clean up Instance watchers when the Instance is removed.
- `Destroy()` must release remaining connections and state.
- Keep caches, queues, and histories bounded.
- Avoid expensive per-frame loops, repeated world scans, and bursts of DataStore requests.
- Make economy and persistence operations safe against retries, duplication, server hops, and shutdown.
- Prefer small, evidence-based fixes over broad speculative refactors.

## Validation

Before committing, run formatting (StyLua), Selene, structure validation, a Rojo build, and relevant tests where a Roblox test runtime is available. Run the repository’s required CI checks for the exact current PR head before merging. Update subsystem documentation when a contract changes. Never commit secrets or production asset IDs.

If a check cannot run, report the exact check and reason. Do not imply it passed.

## Updates and handovers

- Give concise, evidence-based progress updates when reporting status: what changed, branch and PR, current head SHA, exact CI state, current `main` SHA where relevant, blockers, and next action.
- Do not claim background work. Report only work actually completed or checked.
- When a task is complete, or when it must be handed to another agent/session because of a genuine blocker or context limit, automatically include a concise, ready-to-paste **Handover** in the final response.
- The handover must state: task and scope; completed work; branch/PR and current exact head SHA; checks and their result for that SHA; current live `main` SHA; remaining work/blockers; and the next concrete action.
- Include only task-specific state. Do not copy these standing instructions into the handover or ask the user to restate them. The receiving agent must read the Project Instructions and this `AGENTS.md`, then refresh live GitHub state before acting.
- Do not hand over prematurely while safe, authorised work remains. Continue the task; use a handover only when the task is complete or genuinely blocked/transferring.
