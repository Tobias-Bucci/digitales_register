# Project Engineering Guidelines

## 1. General Principles

Treat this project as a production-grade Flutter application.

Priorities, in order:

1. Correctness and reliability
2. Security and data integrity
3. Architectural consistency
4. Maintainability and readability
5. Performance
6. Development speed

Always prefer well-reasoned, maintainable solutions over quick fixes.

- Understand the existing implementation before making changes.
- Follow established project conventions and architectural patterns.
- Avoid unnecessary complexity, duplicated logic and oversized classes.
- Prefer small, focused changes over broad rewrites.
- Do not introduce dependencies without a clear technical justification.
- Preserve existing functionality unless a behavior change is explicitly requested.
- Never assume that documentation, audit reports or previous analysis are still accurate. Verify important findings against the current source code.

## 2. Architecture and Project Structure

This project uses Flutter and Dart with an established Redux-based architecture.

Important architectural considerations:

- Respect the existing Redux implementation and its local package forks.
- Do not introduce Provider, Riverpod, Bloc, ChangeNotifier or another state-management architecture without explicit approval and a compelling reason.
- Keep business logic, state management, persistence and UI responsibilities clearly separated.
- Avoid unnecessary coupling between modules.
- Reuse existing services, middleware, selectors and established abstractions where appropriate.
- Consider account boundaries, session isolation and data ownership when changing application logic.
- Be particularly careful with asynchronous operations, lifecycle management, background tasks and persistent data.
- Consider all supported platforms when changing shared application code.

Do not redesign established architecture simply because an installed skill or agent recommends a different pattern.

## 3. Professional Code Quality

Write code as an experienced Flutter and Dart engineer would.

- Use strong typing and null safety.
- Choose descriptive names for classes, methods and variables.
- Keep methods focused and avoid unnecessary nesting.
- Handle exceptions and error states deliberately.
- Avoid silent failures and swallowed exceptions.
- Avoid unnecessary rebuilds and expensive operations in Flutter widgets.
- Respect widget lifecycle and dispose resources correctly.
- Avoid memory leaks, race conditions and unsafe asynchronous operations.
- Keep platform-specific functionality isolated where appropriate.
- Do not add abstractions that do not provide meaningful value.
- Follow established formatting and linting conventions.

Do not solve symptoms with superficial workarounds when the underlying problem can be fixed properly.

## 4. Skills and Agent Selection

Before starting substantial work:

- Check which installed skills are relevant.
- Read the actual skill instructions before applying them.
- Select agents based on their real capabilities, framework compatibility and model configuration.
- Do not select agents based only on their names.
- Avoid assigning duplicate work to multiple agents.
- Delegate independent research, implementation or review tasks when this improves quality.
- Verify agent findings against the actual source code.

Skills and agents provide guidance, not authority to redesign the project's architecture.

If a skill conflicts with the established architecture, use only the applicable parts.

## 5. Model Selection and Delegation

The main Claude Code session normally uses Opus 5.5 with Medium or High effort.

Respect the model and effort selected by the user for the main session.

For subagents:

- **Opus:** Architecture decisions, complex debugging, security-critical work and high-risk refactoring.
- **Sonnet:** Standard implementation, code exploration, tests and ordinary code reviews.
- **Haiku:** Simple inventories, classification and low-risk tasks.

Inspect an agent's model configuration before delegating.

Explicitly select an appropriate model when spawning subagents if necessary. Do not assume that every agent automatically inherits the main session's model.

Use the reasoning effort appropriate to the complexity and risk of the task.

## 6. Testing and Verification

Testing is an essential part of development.

After making changes:

- Run relevant targeted tests.
- Add or update tests when behavior changes.
- Run Flutter analysis where applicable.
- Run formatting checks.
- Verify that existing functionality remains intact.
- Consider platform-specific behavior where relevant.
- Investigate test failures rather than suppressing them.

Never claim that tests, analysis or builds passed unless they were actually executed successfully.

Clearly distinguish between:

- Verified results
- Assumptions
- Potential problems
- Areas that have not been investigated

Do not hide failures or silently weaken tests to make a change appear successful.

## 7. Safe Refactoring

Before refactoring:

1. Understand the existing implementation.
2. Identify dependencies and affected modules.
3. Check existing tests and callers.
4. Consider compatibility and migration requirements.
5. Define the expected behavior before changing code.

During refactoring:

- Preserve behavior unless explicitly instructed otherwise.
- Avoid combining unrelated changes.
- Keep changes reviewable.
- Do not remove seemingly unused code without checking all relevant references.
- Do not change public interfaces unnecessarily.
- Consider persistence, migrations and backward compatibility.

After refactoring, verify the result through tests and static analysis.

## 8. Codebase Knowledge Graph (Graphify)

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:

- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. When the answer is under a Markdown heading, `graphify section "<heading>"` prints that section's text, so the .md need not be opened. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.

Additional Graphify guidance:

- The current graph covers `lib/` and `test/` only.
- It does not currently represent `packages/`, `android/`, `ios/` or `docs/`.
- Never assume that a dependency or component is absent simply because it does not appear in the graph.
- Treat graph results as navigation and structural evidence, not proof of runtime behavior.
- Verify important architectural findings against the actual Dart implementation and tests.
- Do not regenerate the entire graph unnecessarily when an incremental update is sufficient.

## 9. Research and Documentation

Use Context7 or relevant official documentation when current API behavior, framework details or package documentation need verification.

Prefer:

1. Official documentation
2. Maintained package documentation
3. Source code and changelogs
4. Reliable technical references

Do not invent APIs, parameters or package behavior.

When uncertain, investigate before implementing.

## 10. UI and UX Quality

The application should have a consistent, polished and professional user experience.

- Follow existing design conventions.
- Respect platform-specific interaction patterns.
- Consider accessibility, responsive layouts and different screen sizes.
- Avoid inconsistent spacing, typography and component behavior.
- Use existing design components where appropriate.
- Avoid unnecessary animations and visual complexity.
- Ensure loading, empty, error and success states are handled properly.

Use relevant installed design and UI skills when appropriate, but do not apply them blindly.

## 11. Security and Data Integrity

Treat security and user data as critical.

- Never expose credentials, API keys, tokens or private user data.
- Validate external input.
- Handle authentication and authorization carefully.
- Respect account and session boundaries.
- Avoid logging sensitive information.
- Consider data consistency when changing persistence or synchronization logic.
- Do not weaken security controls to simplify implementation.

Security-sensitive changes should receive additional review.

## 12. Git and Change Management

Before substantial work:

- Check the current branch and working tree.
- Inspect relevant recent commits.
- Do not overwrite or discard existing user changes.
- Keep changes focused and logically grouped.
- Avoid unnecessary generated files and build artifacts.
- Review the final diff before considering work complete.

Never assume that the working tree is clean.

Do not commit or push changes unless explicitly requested.

## 13. Communication and Final Reports

Communicate clearly and technically.

Before implementation:

- Explain the intended approach for substantial changes.
- Identify important risks and dependencies.
- Ask for clarification when requirements are genuinely ambiguous.

After implementation, summarize:

- What changed
- Why it changed
- Which files were affected
- Which tests and checks were executed
- Whether anything remains unresolved

Avoid claiming more than what was actually verified.

Be concise for simple tasks and detailed for architectural or security-sensitive work.