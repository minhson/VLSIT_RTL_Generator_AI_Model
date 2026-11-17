# Phase 4: Testbench Generator — /tb_generator

Build a plain SystemVerilog testbench and saved test cases from the approved verification contract. The test plan must be traceable to REQ-IDs and independent of RTL implementation.

## Sources and boundary

Require Gate 3a approval and matching contract, specification, and configuration revisions. Read the verification contract, golden sources, and recorded user choices. Use structured_spec.json only to cross-check REQ-IDs. Do not inspect RTL ports, hierarchy, internal state, enum values, or RTL-derived results when choosing stimuli or computing expected outcomes.

## Procedure

1. Build a test-plan table from contract TC-IDs with REQ-ID coverage, purpose, `test_type` (`directed`, `combined`, `constrained_random`, `fault_injection`, `stress`), the `functions` the test exercises, legal stimulus, expected observable behavior, covered failure modes (FM-IDs), parameter applicability, and exclusions. Warn about requirements and failure modes without tests or properties. Plan combined tests for features that share a resource, a state machine or a clock domain, and keep one check per function so that a failure names the function.
2. Explain all-applicable versus selected tests, trade-offs, and an example before selection. Follow .agents/skills/decision_prompt_standard.md. Apply parameter conditions from schemas/final_config.json.
3. Save each generated case under src/tb/tests/. Start each test block with a TC-ID and REQ-ID comment. Use a contract-derived reference model or explicit expected values from golden sources. Do not use UVM unless the user explicitly requests it. Every test runs with every applicable SVA and the reference-model scoreboard enabled; a checker disabled for a test is recorded in the test plan with the reason and needs user approval at Gate 4.
4. Create src/tb/filelist_tb.f and schemas/selected_testplan.json. Compile against the contract-derived interface shell before Gate 4. Shell compilation checks syntax/elaboration, not DUT behavior.
5. Extend the one design-root Makefile with documented targets for testbench compilation, one TC, and regression. Keep compiler and simulator invocations visible in recipes; do not hide them in a runner script. Preserve all test files and logs.
6. Present the environment architecture first: a text block diagram (stimulus, driver, DUT adapter, monitor, reference model, scoreboard, SVA, coverage) and a component table with the responsibility, the interface and the golden source of each component; store both under `environment` in `schemas/selected_testplan.json`. Then present selected tests, requirement and failure-mode gaps, disabled checkers, compile results, and the exact plan for review. Gate 4 is approved by the user when run independently; full /autoflow may auto-approve only when no unresolved problem remains and shell compilation passes.

During later DUT integration, inspect RTL only to map contract signals to ports. Treat mismatch as a failure and keep expected behavior fixed.
