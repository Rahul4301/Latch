# Dev Notes — Directory Responsibilities

## Core

Core holds the policy engine, agent orchestrator, and shared business logic. The policy engine validates every proposed tool call, enforces allowlists and blocked tokens, and assigns risk levels (Low, Medium, High). The orchestrator coordinates the plan–observe–plan loop with the LLM and drives validation and execution flow. All logic here is deterministic and auditable; policy is not encoded in natural-language prompts.

## Capabilities

Capabilities contains the three MVP tools: `file_search`, `file_read`, and `command_exec`. File search is metadata-only within the workspace root with configurable result limits. File read enforces byte limits and marks binary content. These modules implement the fixed tool schema and enforce workspace-root scoping; they do not perform writes, deletes, or permission changes in the MVP.

## Executor

Executor is the sandboxed command execution layer. It runs only approved commands via absolute paths and an args array (no shell wrappers), enforces timeouts and stdout/stderr caps, and constrains execution to the workspace root. It is designed to be invoked via XPC for process isolation from the UI and must not create network connections in the MVP.

## Resources

Resources holds policy configuration and static assets. The executable allowlist lives in `DefaultPolicy.json` and is version-controlled; the policy engine matches commands against this allowlist. No other policy encoding (e.g. in prompts) should replace this file as the source of truth for allowed binaries and constraints.
