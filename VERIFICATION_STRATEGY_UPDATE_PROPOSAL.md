# Proposal: verification strategy update for the phase skills

Status: **approved by the user on 2026-11-17 (U1 to U6) and applied.** Per `.agents/skill_maintenance.md`, no skill, command, schema or template is edited until the user approves each item below. The proposal is user-requested; it carries the principles added to `vlsit-verification-generator` (rules R-240 to R-245) into this repository's own flow.

## 1. What the flow already does (no change proposed)

| Principle | Already enforced by |
|---|---|
| Specification and exact standard revision are the oracle; RTL is read only for adapter connectivity | `verification_contract.md`, `sva_generator.md`, `tb_generator.md`, `verification.md` |
| Oracle fixed before RTL exists (Gate 3a) | `source-command-verification-contract` |
| Do not change contract, tests, assertions or expected results to accommodate the RTL; do not weaken checks for coverage | `verification.md` step 1, `code_coverage.md` closure loop |
| Mutation score per requirement, 85 % threshold | `verification.md` step 5, `rtm_schema.json` |
| Code coverage measured, target chosen by the user, closure tests saved | `source-command-code-coverage` |
| Pass, fail, N/A and not run kept distinct; only the user signs Gate 5 | `verification.md` steps 5 and 6 |

## 2. Gaps and exact changes

Each item lists the files it touches. The `.agents/skills/source-command-*` wrappers already defer to `.claude/commands/*.md`, so only `source-command-verification-contract/SKILL.md` (which carries its own procedure) needs a parallel edit.

### U1. Method per requirement and a formal step

Gap: assertions are compiled and simulated only; nothing selects formal proof for control logic, where it is exhaustive.

- `verification_contract_schema.json`, `requirements[]`: add optional `method` (enum `formal`, `simulation`, `formal+simulation`, `review`) and `method_reason` (string).
- `verification_contract.md` and `source-command-verification-contract/SKILL.md`, procedure step 2: "Assign each REQ-ID a method with a one-line reason: formal first for bounded control behavior (handshake, FSM, arbitration, counters, FIFO flags), simulation for data paths, long sequences and performance."
- `verification.md`, new step after step 2: "For REQ-IDs whose method includes formal, run the approved properties with an available formal tool (for example SymbiYosys) through a documented `formal` Make target. Record per property: proven, failed with counterexample trace, bounded to depth N, or not run with the reason. A counterexample is a verification failure."
- `verification_report_schema.json`: add `formal_summary` {`tool`, `version`, `properties`: [{`property_id`, `req_id`, `status`, `depth`, `trace_file`}]}.

### U2. Assertion non-vacuity

Gap: a property whose antecedent never occurs passes silently.

- `sva_generator.md`, step 1: "For every implication property, also write a `cover` of its antecedent with the same REQ-ID."
- `verification.md`, step 2: "Record per property the antecedent hits and failures across the regression. A property with zero antecedent hits is vacuous; its REQ-ID is not signed off until a test reaches it or the user approves an exclusion with evidence."
- `verification_report_schema.json`, `sim_summary`: add `property_activity` [{`property_id`, `req_id`, `antecedent_hits`, `failures`, `vacuous`}].

### U3. Failure-mode list in the contract

Gap: `error_recovery` lists specified error cases, but not the ways a feature can fail silently (overflow, lost or duplicated item, reorder, reset in a transfer, simultaneous events).

- `verification_contract_schema.json`, `requirements[]`: add optional `failure_modes` [{`id` (FM-NNN), `description`, `trigger`, `expected_detection`, `test_ids`, `property_ids`}].
- `verification_contract.md` and its SKILL.md, step 2: "For each requirement list its failure modes and map each to a TC-ID or property ID, or mark it not applicable with a source-based reason."
- `tb_generator.md`, step 1: "Warn about failure modes without a test or property."

### U4. Always-on checkers and multi-function tests

Gap: the test plan does not state that every checker runs in every test, nor how a test covers several functions.

- `tb_generator.md`, step 3: "Every test runs with every applicable SVA and the reference-model scoreboard enabled. A checker disabled for a test is recorded in the test plan with the reason and needs user approval at Gate 4."
- `tb_generator.md`, step 1: add the fields `test_type` (`directed`, `combined`, `constrained_random`, `fault_injection`, `stress`) and `functions` (list) to each test-plan row; "Plan combined tests for features that share a resource, a state machine or a clock domain; keep one check per function so a failure names the function."

### U5. Environment architecture in the test plan

Gap: the reviewed test plan has no description of the testbench structure.

- `tb_generator.md`, step 6: "Present the environment architecture before the test list: a text block diagram (stimulus, driver, DUT adapter, monitor, reference model, scoreboard, SVA, coverage) and a component table with the responsibility, the interface and the golden source of each component."
- `selected_testplan.json` (written by the skill): add `environment` {`diagram`, `components`: [{`name`, `kind`, `responsibility`, `interface`, `source`}]}.

### U6. Reviewed, readable verification report

Gap: `tc_results` holds only ID, name, status, cycles and log; there is no purpose, no cause analysis, no review field and no human-readable report.

- `verification_report_schema.json`:
  - `sim_summary.tc_results[]`: add `purpose`, `req_ids`, `functions`, `failure_category` (enum `dut`, `testbench`, `specification`, `environment`, `tool`, `unclassified`, null when passed), `cause`, `evidence` (log line or time), `review` {`reviewer`, `reviewer_type` (`engineer` or `ai_agent`), `model`, `verdict` (`agree`, `disagree`, `needs-info`), `comment`, `response`}.
  - add `failure_analysis` [{`id` (FA-NNN), `tc_ids`, `symptom`, `failure_category`, `root_cause`, `hypothesis_source`, `evidence`, `action`, `status`, `review`}].
  - add `coverage_summary` [{`req_id`, `tests_passed`, `tests_total`, `properties_active`, `properties_total`, `mutation_score`, `code_coverage_pct`, `status`}].
- `verification.md`, step 6: "Also write `docs/verification_report.md` with: a summary table (tests by status, open failures by category, mutation, code coverage, open reviews); the TC table with purpose, functions, status, cause and the review columns; the failure-analysis table; the coverage summary per REQ-ID; and the exact Make targets. A review by an AI agent names its model and is advisory. An open `disagree` or `needs-info` prevents recommending Gate 5 approval."

## 3. Effect and risk

- All schema additions are optional fields, so existing `verification_contract.json`, `selected_testplan.json` and `verification_report.json` files stay valid.
- U1 adds a tool dependency only when a formal tool is available; otherwise formal properties are reported `not run`, never passed.
- U2 and U6 make Gate 5 stricter: vacuous properties and unresolved reviews now block a recommendation.
- No change touches RTL generation, the spec skills or the Makefile rule beyond new targets (`formal`).

## 4. Decision requested

Approve each of U1 to U6 separately, or reject or amend it. Only approved items are applied, then the schemas are validated against the existing example JSON files and the `.agents` wrapper is checked for consistency.
