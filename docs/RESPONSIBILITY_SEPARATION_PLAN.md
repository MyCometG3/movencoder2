# Responsibility Separation Plan (MovEncoder2)

Date: 2026-02-08
Branch: `plan/separation-review`

This document defines the step-by-step implementation plan to clarify and improve responsibility separation across the movencoder2 codebase. It is the single source of truth for the tasks below.

## Goals
- Clarify boundaries between IO abstraction and processing orchestration
- Reduce perceived overlap by naming and documentation, without breaking public APIs
- Consolidate configuration handling into type-safe structures
- Maintain performance, memory ownership guarantees, and backward compatibility

## Non-Goals
- No destructive or breaking changes to public CLI options or external interfaces in initial steps
- No wholesale redesign of pipeline unless validated by prototype results

## Guiding Principles
- Prefer incremental, non-breaking refactors first
- Document intent and boundaries explicitly; rename only when risk is minimal
- Validate behavior via lightweight tests before/after changes

---

## Step 1: Clarify IO vs Processing Boundaries (Non-breaking)

Objective: Make IO responsibilities (MEInput/MEOutput/SBChannel) distinct from processing orchestration (MEManager/MEAudioConverter) through documentation and naming hints.

Actions:
- Update class header docs:
  - `Core/MEManager.h`: Emphasize role as processing coordinator for filter/encoder pipelines; IO interaction is via internal bridge methods only.
  - `Core/MEAudioConverter.h`: Emphasize role as audio conversion coordinator; IO interaction is via internal bridge methods only.
  - `IO/MEInput.h`, `IO/MEOutput.h`, `IO/SBChannel.h`: Emphasize IO abstraction responsibilities and producer/consumer roles.
- Add comments near AVAsset-like methods in MEManager/MEAudioConverter that they are internal bridge APIs intended for SBChannel/IO adapters.
- Do NOT change public method signatures in this step.

Deliverables: ✅ Completed
- Updated header documentation for the above classes.
- No behavior changes.
- Add internal alias methods in Core classes (forwarders only) to make adapter intent explicit; update IO adapters to call aliases.

---

## Step 2: Introduce Internal Naming Hints (Low-Risk Renames)

Objective: Reduce ambiguity by suffixing internal bridge methods with `Internal` where feasible without external impact.

Actions:
- In `Core/MEManager.h` and `Core/MEAudioConverter.h`, add alternate method aliases with `Internal` suffix (e.g., `appendSampleBufferInternal`) that forward to existing implementations.
- Prepare `IO/SBChannel.m` for a future update to call the `Internal` aliases; keep original methods for compatibility for now.

Deliverables: ✅ Partially Completed
- Method aliases in MEManager/MEAudioConverter.
- SBChannel currently continues to use the original bridge methods; migration to `Internal` aliases will be tracked as a follow-up.
- Existing external callers remain functional.

---

## Step 3: Configuration Consolidation (Type-Safe Extension)

Objective: Move scattered configuration in METranscoder into a consolidated configuration object while preserving current behavior and CLI parsing.

Actions:
- Add new class `Core/METranscodeConfiguration.(h|m)` containing:
  - `encodingParams` (NSDictionary, legacy-compatible)
  - `timeRange` (CMTimeRange)
  - `logging` (struct/object for verbosity/log levels)
  - `callbacks` (start/progress/completion + queue)
- Refactor `METranscoder` to use `METranscodeConfiguration` internally; keep existing properties as accessors/proxies for backward compatibility.
- Extend `METranscoder+paramParser.m` to populate `METranscodeConfiguration`.

Deliverables: ✅ Completed
- New configuration class files.
- `METranscoder` and param parser updates with no CLI changes.

---

## Step 4: Tests to Lock Behavior

Objective: Ensure refactors do not alter core behavior.

Actions:
- Add lightweight XCTest cases under `movencoder2Tests`:
  - Video pipeline: append → filter → encode → copyNext, EOF/flush state transitions (`MEEncoderPipeline` flags: isReady, isEOF, isFlushed).
  - Audio converter: `volumeDb` boundary checks (±10.0 dB, zero), readiness and basic buffer flow.
  - SBChannel: producer→consumer handoff increments `count`, `finished` toggles, progress flag tested.

Deliverables: ✅ Completed
- New tests; passing on local builds.

---

## Step 5: Prototype Full IO Delegation (Optional, Validation)

Objective: Evaluate feasibility of fully delegating IO to IO layer classes, removing bridge methods from processing classes.

Actions:
- Create a prototype branch (e.g., `proto/io-delegation`) off this plan branch.
- Implement delegation in `MEInput/MEOutput` to handle all IO, with MEManager/MEAudioConverter exposing pure processing APIs only.
- Measure effects on:
  - Performance (queue/semaphore contention, EAGAIN handling)
  - Memory ownership (AVFrame/CMSampleBuffer retain/unref correctness)
  - Complexity of SBChannel coordination
- Record findings in `docs/PROTOTYPE_IO_DELEGATION_NOTES.md`.

Decision Gate:
- If performance/ownership remain acceptable, plan a staged migration PR set.
- If not, retain bridge method approach; ensure documentation and naming remain clear.

---

## Step 6: Documentation Synchronization

Objective: Keep architecture docs in sync.

Actions:
- Update `docs/ARCHITECTURE.md` with clarified responsibilities and any method alias usage.
- Add a short section on “Internal Bridge APIs” and their rationale.

Deliverables: In progress
- Updated docs reflecting the refactor state.

---

## Rollback and Safety
- All steps are designed to be individually reversible.
- No API removal without prototype validation and a follow-up plan.
- Maintain git hygiene: small commits per action, clear messages.

## Ownership and Review
- Code changes should be reviewed focusing on:
  - No behavior changes in Steps 1–4
  - Clear intent in comments and names
  - Tests covering core flows

## Next Actions
- Complete Step 6 documentation updates (architecture + internal API references).
