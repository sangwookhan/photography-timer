<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Spec Kit execution profile

This opt-in profile adapts Spec Kit's specify → plan → tasks → implement
phases to [SpecificationWorkflow.md](SpecificationWorkflow.md).
`AGENTS.md` and that workflow govern execution. Product contracts remain
in `docs/requirements/Requirements.md` and `docs/specs/**`. A generated
`spec.md` is only a Story scope reference, never another source of truth.

## Verified upstream baseline

[Spec Kit v1.4.0](https://github.com/github/spec-kit/releases/tag/v1.4.0)
was inspected using its official tagged source and isolated initialization.
The inspected source commit is `0019fa14d12f45edabc2cc3176c9168a68bd0f97`.
The Python package reports `specify-cli 1.4.0` and requires Python 3.11+.
Codex uses `.agents/skills/speckit-*/SKILL.md`; skills are its default
integration format. The init option is `--integration codex`.

Initialization installs nine skills, shared scripts, templates, a
constitution scaffold, integration manifests, and the `speckit` workflow.
It does not create a product feature or an approved contract. The stock
feature template asks for new requirements and success criteria, and the
feature helper writes under root `specs/`. Those defaults do not fit this
repository's contract ownership or private delivery-artifact policy.

## Repository configuration

- `.agents/skills/ptimer-sdd/SKILL.md` is the Codex entry point. Invoke
  `$ptimer-sdd` in a session that discovers this repository skill, or
  explicitly ask the agent to read that file if discovery has not refreshed.
- `.specify/templates/spec-template.md` replaces the feature-contract
  template with a reference-only Story scope template for this adapter.
- `scratch/spec-kit/<story>/` holds local `spec.md`, `plan.md`, `tasks.md`,
  and any worklog. It is already ignored. Root `specs/`, local runtime
  files, and `.specify/feature.json` are ignored as additional protection
  against accidental staging. Never force-add delivery artifacts.

No upstream scripts, generated skills, constitution, automatic workflow,
hooks, MCP server, global Codex settings, or agent-context extension are
installed into the checkout. The adapter does not depend on the CLI at
runtime. This is a manually invoked execution profile; it does not claim
compatibility with the stock automated workflow or enforce approvals in CI.

Keep `spec.md` limited to Story scope, canonical Living Spec paths and
Requirement IDs, one review platform, user test scenarios, and exclusions.
Keep exact revision and approval evidence in local `plan.md` and the Code
PR. Tests may reference expected outcomes through the contract IDs;
unresolved expectations must return to the Spec PR, not become new rules
in a local file. See the adapter for the phase gates.

## Reproduce the upstream inspection

Use a new temporary directory, never `specify init --here` in this checkout.
All GitHub access uses `git` or `gh`. These commands install only into the
temporary environment and need network access for Python dependencies:

```bash
inspection_dir=$(mktemp -d "${TMPDIR:-/tmp}/ptimer-speckit.XXXXXX")
gh api repos/github/spec-kit/tarball/v1.4.0 > "$inspection_dir/source.tar.gz"
mkdir "$inspection_dir/source"
tar -xzf "$inspection_dir/source.tar.gz" -C "$inspection_dir/source" --strip-components=1
python3 -m venv "$inspection_dir/venv"
"$inspection_dir/venv/bin/python" -m pip install "$inspection_dir/source"
"$inspection_dir/venv/bin/specify" version
"$inspection_dir/venv/bin/specify" init "$inspection_dir/generated" \
  --integration codex --script sh --non-interactive --ignore-agent-tools
```

`--ignore-agent-tools` skips the Codex binary check for scaffold inspection;
it does not verify that Codex can execute generated skills. Review a later
upstream upgrade in isolation again before changing this profile.

## User test steps

1. Invoke the adapter for a bounded Story before its Spec revision is
   approved. Verify it can prepare a provisional plan but starts no product
   implementation and requests no blanket approval to bypass the gate.
2. Inspect local `spec.md`: only the five template sections above appear;
   behavioral requirements point to Living Specs rather than being copied.
3. Use the following command and confirm all three paths are ignored:

   ```bash
   git check-ignore scratch/spec-kit/example/spec.md specs/example/spec.md .specify/feature.json
   ```

4. After explicit approval of an exact revision, inspect the local plan and
   Code Draft PR for that baseline, a user-verifiable vertical increment,
   protected areas, and user test steps.
5. For a UI Story, verify the next platform remains gated until actual UI
   approval is recorded. Inspect `git diff --cached --name-only` before any
   commit: no Story plans, tasks, worklogs, or generated runtime files belong
   in the public tree.
