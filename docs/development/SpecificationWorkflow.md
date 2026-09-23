<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Specification Workflow

**Status:** v2 — revised after PTIMER-221 exercised the workflow in real
feature work. This remains a working contract and should continue to evolve
when later delivery exposes a concrete process defect.

This document describes the *process* by which PTimer's living behavior
specifications are created, changed, and implemented. It does not itself
contain product behavior — product behavior lives in `docs/specs/**`.

---

## 1. Document layers

```
docs/requirements/Requirements.md
        ↓ (refines, does not duplicate)
docs/specs/**
        ↓ (informs)
engineering design / tasks
        ↓
implementation
        ↓
verification
```

- **`docs/requirements/Requirements.md`** is the higher-level, user-scenario
  and persona-oriented product requirements layer. It states user-visible
  needs and integrity invariants in prose, at the granularity of "the user
  can do X" or "the system shall never do Y."
- **`docs/specs/**`** is the detailed, testable behavior-contract layer,
  organized by product capability. Each file states individually-numbered,
  atomic requirements at a granularity a test or a code review can check
  directly.

**The two layers must not converge to the same level of detail.** A
capability spec requirement should be more specific than its corresponding
Requirements.md statement, not a restatement of it. For example:

```
Requirements.md:
  "The user can use multiple camera slots."

shooting/camera-slots.md:
  SLOT-001, SLOT-002, SLOT-SWITCH-001, ...
```

`docs/architecture/**` and `docs/development/**` sit outside this chain.
They describe *how the system is built* (module boundaries, ownership,
process) rather than *what the product does*. Architecture and process
material must never appear inside a `docs/specs/**` file's normative body.

## 2. What a living behavior specification is

A file under `docs/specs/**` describes the **current approved product
behavior contract** for one product capability. "Current" means the contract
the product is presently committed to, not a snapshot of behavior that every
platform already ships.

- On `main`, `docs/specs/**` contains the latest approved contract. An
  approved capability may be delivered incrementally by platform; therefore a
  merged spec may describe behavior implemented on one platform while another
  supported platform is still pending. This is an approved contract, not
  speculative planning. Which platform is implemented first is a delivery
  choice, not part of the contract model.
- On an open Spec PR branch (§10.1), the same path describes a **proposed
  revision** of that contract. Before initial approval it is still being
  decided; after initial approval it is the exact revision implementation
  consumes and may continue to change through the spec-feedback protocol until
  final conformance.
- Merging a spec does not freeze it permanently. Implementation on another
  supported platform may expose a genuine product ambiguity, platform
  constraint, or contract defect. That feedback revises the living spec through
  a new Spec PR. Already-implemented platforms are then re-checked against the
  revised contract: if they already conform, no code change is required; if
  they do not, each affected platform receives a follow-up Code PR. During that
  follow-up window, the approved spec on `main` is allowed to lead an older
  platform implementation.

A file under `docs/specs/**` is otherwise:

- **Ticket-free.** No Jira ticket IDs, no PR references, no "as of PTIMER-NNN"
  framing in the normative body.
- **History-free.** No narration of how the behavior evolved, what was tried
  and rejected, or who decided what and when. A settled rejection that still
  carries real regression risk is compressed into a one-line entry under
  **Non-goals**, not a story.
- **The first artifact changed when a new requirement is proposed.** Per §1,
  it sits between Requirements.md and engineering design — a new capability
  or behavior change starts here, not in code.
- **Approved-only.** A living spec records the behavior the product has
  actually approved, including approved cross-platform behavior that may be
  implemented in stages. It does not contain speculative ideas, unapproved
  alternatives, or roadmap guesses merely because a future ticket is known.

## 3. Capability ownership

`docs/specs/` is organized by product capability, not by ticket, delivery
order, or implementation layer:

```
docs/specs/
├── README.md
├── calculator/
│   ├── exposure.md
│   ├── nd-filters.md
│   └── target-shutter.md
├── shooting/
│   ├── camera-slots.md
│   └── reset.md
├── reciprocity/
│   ├── calculation.md
│   ├── catalog.md
│   ├── custom-profiles.md
│   └── details-and-guidance.md
├── timers/
│   ├── lifecycle.md
│   ├── workspace.md
│   └── alerts.md
└── cross-cutting/
    ├── persistence.md
    ├── localization.md
    └── presentation.md
```

A new independent capability gets a new file in the appropriate directory
(e.g. `calculator/my-filters.md`). The tree is not grown speculatively:
creating that new file in a Spec PR is the proposal. Its first merge to
`main` occurs only after the contract is approved and at least one Code PR
has reached final conformance against it (§10). The capability may then be
implemented on additional platforms against that merged contract. If a later
implementation changes the approved behavior, the same capability file is
revised through a new Spec PR rather than treated as frozen history.

**Cross-capability inheritance.** When a new capability extends or shares
mechanics already owned by another file, it must not duplicate those
mechanics. It states its own capability-specific contract and references the
owning file by name for the shared part, e.g.:

> `<new-capability>` stacks are governed by the common stack behavior
> defined in `<owning-file>.md`. This document does not redefine those
> rules.

This pattern is illustrative only. Whether any specific future capability
(for example My Filters/PTIMER-221) actually shares an existing file's
contract this way, or needs its own independent one, is not decided by this
document — that is a product/behavior question, decided in that feature's
own Spec PR once its requirements are confirmed (see §5).

A shared invariant is defined in exactly one file. If a later feature's
requirements make an existing file's contract need to generalize (for
example, a stack contract written specifically for one input source needing
to become source-agnostic), that generalization happens in the Spec PR of
the feature that needs it — never speculatively during an unrelated baseline
or migration pass.

**Architecture is out of scope.** Module boundaries, state-ownership
diagrams, and platform-specific implementation structure belong in
`docs/architecture/**`, not `docs/specs/**`. A capability file may state a
*behavior difference* between platforms when one genuinely exists (e.g. a
platform-specific accessibility mechanism), but never *how* either platform
is internally structured to achieve it.

## 4. Requirement ID conventions

- **Format:** `<PREFIX>-<NNN>`, e.g. `ND-001`, `SLOT-SWITCH-001`,
  `RECIP-CALC-001`, `PERSIST-001`.
- **Never use the `FR-` prefix in `docs/specs/**`.** `FR-` (and `NFR-`)
  belong to `Requirements.md`'s own numbering (`FR-1.2a`, `NFR-D.1`, ...).
  Reusing it here would collide two different-altitude ID namespaces.
- **Prefer semantic segmented prefixes over numeric ranges.** `ND-STACK-001`,
  `ND-CLEANUP-001`, `ND-INTERACT-001` read correctly years later without a
  lookup table. A numeric range convention (`ND-100`–`ND-199` = stack, etc.)
  does not — the number alone carries no meaning, so it fails exactly the
  problem stable IDs are meant to solve.
- **Namespace table only where it earns its keep.** A file that uses several
  semantic prefixes whose scope is not immediately obvious from the prefix
  name alone should open with a short table:

  ```
  | Prefix | Owns |
  | --- | --- |
  | ND | Core ND values and notation |
  | ND-STACK | Shared stack behavior |
  | ND-CLEANUP | Zero-entry cleanup |
  | ND-INTERACT | Interaction/commit behavior |
  ```

  A file with one or two self-evident prefixes (e.g. `RESET-001`,
  `RESET-A11Y-001`) does not need this table — adding one would just be
  another thing to keep in sync for no real gain in clarity.
- **IDs are stable and append-only.** A retired ID is never reassigned to
  unrelated behavior. If a requirement is removed, mark it `RETIRED` with a
  one-line reason rather than deleting the ID silently, if it is plausible
  that a test, code comment, or PR still references it.
- **Not every sentence needs an ID.** Only normative, individually testable
  requirements get one. Purpose statements, contextual prose, and
  explanatory asides stay unnumbered.

## 5. Current baseline discipline

The baseline established by the initial migration deliberately started from
**currently shipped behavior**, verified against the truth hierarchy in §6.
That was a bootstrap rule for reconstructing a trustworthy baseline, not a
definition that future living specs must always lag implementation.
Concretely:

- During the initial migration, the ND filter stack
  (`calculator/nd-filters.md`) described the shipping stack over the
  standard ND ladder only and was intentionally not generalized in
  anticipation of PTIMER-221 (My Filters). Any generalization required by
  PTIMER-221 belonged in PTIMER-221's own Spec PR rather than the baseline
  migration.
- During a baseline or reconciliation pass, no capability file is created
  merely for speculative future behavior.
- Historical material (see §6) is a candidate source of *evidence* about
  current behavior, never a source of *future* behavior.

## 6. Truth hierarchy

Every conflict between historical, current, and source-level material must
be resolved using this ordering, highest authority first:

1. **An explicit current product decision approved by the user.**
2. **Approved current product requirements / behavior specifications**
   (`docs/requirements/Requirements.md`, current `docs/specs/**`).
3. **Current source implementation and tests.**
4. **Historical task specs, Jira/Confluence records, reports, and prior
   agent reconstructions** (including the historical SDD reconstruction
   produced before this migration).

**Current source code is evidence, not automatically product truth.** If an
approved specification and the current implementation disagree:

```
approved spec == current source        → verified candidate
approved spec != current source        → conflict/ambiguity — do not silently
                                          pick source; the implementation may
                                          contain a regression
historical material != current spec    → historical material is a stale
                                          candidate for rejection, not an
                                          automatic override
source-only, no approved contract       → source is evidence; it is not
                                          promoted to product truth merely
                                          because it is what runs today
```

Historical material is never promoted into a living spec merely because it
describes what shipped at some point in the past, and never because it is
more detailed than the current approved spec. Detail is not the same as
correctness — a stale historical requirement can be extremely precise and
still describe behavior the product no longer has.

### Reconciliation classification

For every historical candidate requirement considered for migration:

```
candidate
    ↓ apply truth hierarchy
VALID        — current accepted behavior supports it; migrate with a new
               capability-scoped ID.
STALE        — superseded by a higher-authority current decision or spec;
               do not migrate; leave in the historical archive only.
AMBIGUOUS /
CONFLICT     — approved spec and source disagree, two approved documents
               disagree, or acceptance cannot be established from available
               evidence. Do not resolve unilaterally. Collect for a decision
               report (§8) and continue with unaffected capabilities.
```

**How confident the evidence is does not change this.** The AMBIGUOUS/
CONFLICT classification is not a fallback for genuinely unclear cases only —
it also applies when the agent doing reconciliation is highly confident
about which side is correct. Reading current source and concluding "the
spec is obviously the stale one here" does not authorize rewriting the spec
in the same pass; it authorizes writing up the conflict, with the
supporting evidence, for the decision report. Two documents at the *same*
truth-hierarchy level (for example, `Requirements.md` and a current
`docs/specs/**` file both being "approved current") that disagree with each
other are a CONFLICT by definition — there is no default tiebreaker between
peers, including "the more detailed one wins" (see §14).

## 7. Product research references

A capability file's optional **Product research references** section may
cite a source only when it is a *durable* source of current product intent
— something that still materially explains why the contract has its current
shape. The test is **continued relevance to current product intent**, not
where the material happens to live (a Confluence wiki page is not
automatically durable; some wiki pages are themselves marked historical or
superseded).

May remain:
- Product/photography/exposure research that explains a current scope
  decision.
- Manufacturer or source-data research behind a current reciprocity policy.

Must be excluded:
- Jira implementation tickets, PR references, implementation reports.
- Superseded design drafts and historical decision chronology.
- Any source explicitly marked obsolete/superseded in its own citation text.
- A source that no longer supports any current product behavior.

## 8. Handling product ambiguities

An agent performing reconciliation or migration work must never silently
resolve a genuine product ambiguity — by picking an interpretation, by
rewriting behavior to make documents internally convenient, or by treating
current source code as automatically authoritative over an approved spec.

When an ambiguity is found, it is collected in this form:

```
ID / capability:
Conflict:
Higher-authority evidence:
Current implementation evidence:
Historical evidence:
Why a product decision is required:
Options:
Your recommendation:
```

Only genuine product ambiguities are escalated this way. Implementation
detail, wording choices, and document-organization questions that an agent
can resolve within the rules in this document are not escalated.

## 9. Roles and approval responsibility

- **The user** is the final product decision authority. Any item classified
  as a genuine ambiguity is decided by the user, never inferred.
- **ChatGPT** reviews and classifies spec feedback (§10) — questions,
  objections, and conflicts raised during implementation — and escalates
  only the ones that are genuine product decisions to the user.
- **Claude / Codex**, acting as implementer, may raise spec feedback (§10)
  but does not resolve a product-impacting question on its own. It is
  expected to keep working on unaffected parts of a task rather than
  stalling entirely on one open question.

## 10. Spec PR / Code PR model

A behavior change that creates or revises the approved product contract uses
a **Spec PR** plus one or more **Code PRs**. Platform implementations may
proceed sequentially or in parallel; iOS and Android have no workflow-defined
priority.

A later platform may also implement a contract that is already merged on
`main` without opening a new Spec PR. That Code PR is a normal path, not an
exception.

### 10.1 Spec PR

- Touches `docs/specs/**` only (and, rarely, a clarifying note in
  `docs/requirements/Requirements.md` — see §1).
- Is opened as a **Draft PR** and stays draft while product behavior is still
  being decided.
- Is revised in place as product decisions change. A change of mind does not
  produce a new PR; the same Spec PR is updated until the contract is approved.
- **Initial approval** means the user and ChatGPT agree that the revision is
  the contract implementations should target. Initial approval may unlock
  Code PRs for any supported platforms, including multiple platform Code PRs
  in parallel.
- If implementation surfaces a `[SPEC-CONFLICT]`,
  `[SPEC-OBJECTION]`, or `[SPEC-QUESTION]` (§12) that changes the
  contract, the Spec PR is revised. Every in-progress Code PR that targets the
  affected behavior must re-check itself against the new approved revision.
- A Spec revision reaches `main` only as part of a **spec delivery group**
  (§10.5): the Spec PR plus at least one Code PR that has reached final
  conformance against that revision. Other platform implementations may merge
  later.

### 10.2 Code PR

A Code PR touches implementation and tests. It must not also modify
`docs/specs/**`; product-contract changes go through a Spec PR.

A Code PR consumes one of two kinds of spec baseline:

1. **Open Spec PR baseline.** When implementing a proposed or newly approved
   revision, the Code PR records the Spec PR number and the exact approved
   Spec PR commit SHA it implements.
2. **Merged living-spec baseline.** When implementing an already-merged
   contract and no Spec PR is in play, the Code PR records the relevant spec
   path(s) and the `main` commit SHA containing the approved contract it
   implements. The originating Spec PR may also be recorded for traceability
   when known, but an open Spec PR is not required.

A Code PR is reviewed, tested, and — for user-visible behavior — verified
on-device against its recorded baseline before merge.

### 10.3 Recording and updating the consumed Spec revision

The recorded baseline is part of the Code PR's review contract.

- For an open Spec PR, use the exact approved commit SHA on the Spec branch.
- For a merged living spec, use the `main` commit SHA containing the
  relevant approved spec content.
- Multiple platform Code PRs may consume the same initially approved Spec PR
  revision in parallel.
- If the relevant Spec PR or merged living spec changes while a Code PR is in
  progress, the Code PR is checked against the newer approved revision before
  final review. Either it already conforms, or its implementation and tests
  are updated and the check is repeated.
- A Code PR that discovers a required contract change does not reinterpret the
  baseline locally. It opens or returns to the Spec PR process (§12).

### 10.4 Lifecycle and final conformance

For a new or revised contract, the Spec PR moves through:

1. **Proposed** — product behavior is being drafted/discussed.
2. **Initially approved** — implementation may start on any supported
   platform against this exact revision.
3. **Implementation in progress** — one or more Code PRs consume an approved
   revision. A contract-changing feedback item returns the affected behavior to
   the Spec PR for revision and re-approval.
4. **Final conformance confirmed for an implementation increment** — a Code
   PR implements every requirement applicable to its declared platform/scope,
   verification passes, and spec feedback for that increment is resolved.
5. **Spec revision delivered** — the Spec PR and at least one conforming Code
   PR have both merged to `main` as one spec delivery group (§10.5).

Final conformance is **platform/scope-specific**. Confirming it for one Code
PR does not claim that every supported platform implements the capability.

A later platform Code PR implementing the already-merged contract follows
steps 2–4 against the merged living-spec baseline and may merge on its own if
it does not change the contract.

### 10.5 Merge semantics

A **spec delivery group** consists of one Spec PR and one or more Code PRs
that are ready to deliver that Spec revision. Merge the group only when:

- the Spec revision is approved;
- at least one Code PR has final conformance confirmed against that revision;
- required automated verification passes;
- required user-device verification passes; and
- every PR included in that merge group is merge-ready.

The Spec PR and included Code PR(s) are one logical delivery. GitHub cannot
merge multiple PRs atomically, so their temporary click order has **no
product or SDD meaning**. Any PR in the group may be merged first. The group
is considered delivered only after the Spec PR and every Code PR intentionally
included in that group are on `main`.

A Spec PR is not intentionally merged by itself. At least one implementation
increment accompanies its first merge. Additional platform Code PRs do not
need to wait for that first platform to merge before development starts:
after initial Spec approval they may develop in parallel against the same
recorded revision.

After the Spec revision is on `main`, a later platform Code PR that
implements it without changing the contract may merge independently after its
own final conformance. If that later work requires a contract change, create a
new Spec PR; that new revision again uses a spec delivery group with at least
one conforming Code PR. Already-implemented platforms are re-checked against
the new contract, and any platform that no longer conforms receives a
follow-up Code PR. The approved spec may temporarily lead those older
implementations while the follow-up work is completed.

Ticket closure follows the **declared scope of the ticket**, not the order in
which platforms happen to merge. A platform-scoped ticket may close when that
platform's acceptance criteria are satisfied. A cross-platform ticket closes
only after every platform named in its scope is complete. If later platform
work is intentionally split into a separate ticket, that separate ticket owns
its completion.

## 11. PR checklist (candidate, no CI enforcement yet)

These are lightweight, human-reviewed checklist items, not automated gates.
CI enforcement is deliberately deferred until this process has been
exercised on real feature work and a repeated, concrete failure mode
justifies automating a specific check — see §13.

**Spec PR:**
- [ ] This PR changes product-spec/workflow documentation only.
- [ ] Any unresolved product ambiguities are identified in the PR
      description, not silently resolved.
- [ ] The PR does not mix in implementation changes.

**Code PR:**
- [ ] Records its exact approved spec baseline: either Spec PR + commit SHA,
      or relevant `main` spec path(s) + baseline commit SHA.
- [ ] States the platform/scope for which final conformance is claimed.
- [ ] States that the implementation was reviewed against that exact baseline.

## 12. Spec feedback protocol

An implementer (Claude or Codex) or reviewer who finds a problem with a
Spec PR's product contract — rather than with its own implementation —
raises it as a comment using one of these markers, never by silently
reinterpreting the spec or silently implementing something else instead:

- **`[SPEC-QUESTION]`** — the specification is insufficient to determine
  behavior; a case exists that the spec does not decide.
- **`[SPEC-OBJECTION]`** — the reviewer believes the requirement itself is
  problematic, unimplementable as written, or internally inconsistent.
- **`[SPEC-CONFLICT]`** — the reviewer found a conflict between this
  requirement and another requirement, an accepted product contract, or
  verified current behavior.

Each comment should include, where applicable:

```
Requirement:
Issue:
Evidence:
Implementation impact:
Suggested interpretation:   (optional)
```

Product-impacting feedback is never resolved silently by the implementing
agent. ChatGPT reviews and classifies these comments and escalates only
genuine product decisions to the user (§9).

## 13. What this document does not claim

This workflow describes an intended process, not an automated one. In
particular:

- There is no CI enforcement of the path separation between Spec PRs and
  Code PRs, and no automated check that a Code PR's stated Spec revision is
  accurate. These are currently human-reviewed conventions.
- There is no tooling that detects ID collisions, retired-ID reuse, or
  drift between a capability file and the source it describes. Consistency
  is maintained by review discipline during migration and subsequent PRs.

If a specific failure mode recurs in practice, add the minimal check that
would have caught it (e.g. a path-filtered CI job, a PR template field)
rather than a general automation framework. This document should be updated
at that point to describe what was actually added.

## 14. Lessons from the PTIMER-225 baseline migration

Observations from actually applying §6–§8 across the full capability tree,
recorded here so the next migration or reconciliation pass does not have to
rediscover them:

- **Confidence is not an exception to escalation, even for the person doing
  the reconciling.** A first pass at this migration found a case where
  current source code visibly disagreed with a previously-approved spec
  (a UI behavior description matching a pre-fix version of the code) and
  resolved it by rewriting the spec to match source, in the same pass that
  found it. That was a truth-hierarchy violation — "approved spec !=
  source" is a CONFLICT requiring a decision regardless of how confident
  the evidence looks, not an invitation to silently prefer source. It was
  reverted to an inline-flagged, unresolved conflict (see the PTIMER-225
  decision report, item A). The lesson generalizes: being sure you know
  the answer is not one of the listed classifications.
- **"More detailed" is not a tiebreaker, including between two approved
  documents.** A historical reconstruction's specific numbers (e.g. exactly
  which films receive a given treatment) were stale simply because the
  product grew after the historical ticket was written — correctly
  resolved against the current spec there. But the same instinct ("the more
  specific/detailed source must be the current one") was then wrongly
  applied to resolve a disagreement between two *peer* approved documents
  (`Requirements.md` and `DomainSchema.md` disagreeing on whether custom
  table reciprocity profiles are shipped) in favor of the more detailed
  one. That is not a valid tiebreaker between peers — reverted to an
  inline-flagged conflict (decision report, item B). Detail should raise a
  question, not settle one, and this applies with extra force when both
  sides are at the same authority level.
- **App-shell behavior needed its own file, not a shrug.** Global
  presentation rules (fixed portrait orientation, one primary screen
  hosting both calculator and timers, layout density tiers) didn't belong
  to any single capability file without being misattributed to one. Rather
  than leaving them unowned, `cross-cutting/presentation.md` was added.
- **A bare citation is not a durable reference.** The "Product research
  references" section (§7) was left out of every file in this baseline: the
  only content available for most citations was a short title against a
  wiki page id, with no accessible page content to verify or usefully
  summarize. A bare id is not more useful in the new tree than it was in
  the old one. If a future editor has real access to the underlying
  research, adding a substantive (not just cited) reference section to the
  relevant file is more useful than restoring the old citation list as-is.
