---
name: ptimer-sdd
description: Prepare and execute PTimer ticket work using the adapted Spec Kit phases and the repository's Living Spec approval workflow.
---

# PTimer Spec Kit adapter

Read `AGENTS.md`, `docs/development/SpecificationWorkflow.md`, and
`docs/development/SpecKit.md` before using this adapter. This is a local
adaptation of the Spec Kit phases, not an upstream command alias.

Use the existing checkout. Keep Story artifacts under
`scratch/spec-kit/<story>/`; never stage them or put them under `docs/`.
Do not invoke upstream create-new-feature, constitution, agent-context,
or automatic workflow commands in this checkout. Do not install the
upstream generated skills over this adapter.

1. **Specify:** Read the Story and relevant Living Specs. Create local
   `spec.md` from `.specify/templates/spec-template.md`, containing only
   scope, Living Spec paths/IDs, review platform, user test scenarios, and
   exclusions. Product ambiguities go to the working Spec PR with the
   workflow's feedback markers. Do not decide them in this file.
2. **Plan:** Create local `plan.md`. Record the exact approved Spec PR SHA,
   or the relevant merged Living Spec paths and main baseline SHA, plus
   approval evidence. Before approval, label planning provisional and do
   not implement. Record protected areas, ownership boundaries, and
   verification. Sequence independently reviewable user journeys, each
   including its storage and UI where needed, rather than layer-only work.
3. **Tasks:** Create local `tasks.md` as Step → verification pairs derived
   from that plan. Cite requirement IDs rather than copying contracts.
4. **Implement:** Check approval evidence against the current relevant
   revision first. Implement only the declared platform and increment.
   Record exact baseline and user test steps in the Code Draft PR. For UI
   changes, other-platform implementation waits for recorded user approval
   of the actual UI. Contract changes return to the Spec PR for approval.

Do not treat completion of a Spec Kit phase as Spec approval, UI approval,
permission to publish comments, permission to create worktrees/simulators,
or final conformance. Follow the invoking request's authorized scope.
