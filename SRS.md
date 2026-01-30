# Software Requirements Specification (SRS)

## Project: LLM Sandbox for Local File Exploration and Controlled Command Execution (MVP)

---

## 1. Purpose

The purpose of this document is to define the functional and non-functional requirements for a macOS application that provides a **sandboxed execution environment for a Large Language Model (LLM)**. The system enables the LLM to assist users by searching local files and executing a restricted set of system commands under explicit user approval.

This SRS serves as:

* A blueprint for MVP development
* A reference for architectural and security decisions
* A guardrail against unsafe or undefined agent behavior

---

## 1.1 Scope

The system provides:

* A local macOS desktop application
* An LLM-driven planning and reasoning component
* A sandboxed execution model
* Workspace-scoped file search and file reading
* User-approved command execution
* Full audit logging of actions

The system explicitly **does not** include in the MVP:

* Unrestricted OS automation
* UI automation via Accessibility APIs
* Email, calendar, or contacts access
* Background persistence or scheduled autonomous execution
* Full Disk Access permissions
* Arbitrary software installation on the host system

The MVP is intended for **single-user, local execution only**.

---

## 1.2 Definitions, Acronyms, Abbreviations

| Term           | Definition                                                         |
| -------------- | ------------------------------------------------------------------ |
| LLM            | Large Language Model used for planning and reasoning               |
| Sandbox        | Isolated execution environment preventing unrestricted host access |
| Workspace Root | User-selected directory that bounds all file operations            |
| Tool Call      | A structured request by the LLM to perform a capability            |
| Capability     | A bounded system action (e.g., file search, command execution)     |
| Policy Engine  | Component that validates and gates all proposed actions            |
| Executor       | Component responsible for running approved commands                |
| MVP            | Minimum Viable Product                                             |
| XPC            | macOS inter-process communication mechanism                        |

---

## 1.3 References

1. *LLM-in-Sandbox: Enabling Language Models to Explore and Interact with Environments*
   [https://arxiv.org/html/2601.16206v1](https://arxiv.org/html/2601.16206v1)
2. Apple Developer Documentation – XPC Services
3. Apple Developer Documentation – App Sandbox & Entitlements
4. IEEE 830 / ISO/IEC/IEEE 29148 Software Requirements Specification Standards

---

## 1.4 Overview

This document describes:

* The system’s intended behavior
* Architectural boundaries and trust zones
* Functional capabilities and limitations
* Safety and security constraints
* Operational assumptions

Subsequent sections will define specific requirements, non-functional requirements, and use cases.

---

## 2. Overall Description

---

## 2.1 Product Perspective

The product is a **local-first macOS desktop application** that embeds an LLM into a controlled execution environment.

From a system perspective:

* The LLM **cannot directly act on the host system**
* The LLM can only **propose actions** using a fixed tool schema
* All actions are mediated by:

  * A policy engine
  * Explicit user approval (when required)
  * A sandboxed executor

The product acts as a **bridge between reasoning and execution**, not as an autonomous agent.

---

## 2.2 Product Architecture

The high-level architecture consists of the following components:

1. **User Interface (UI Layer)**

   * Accepts natural language user input
   * Displays proposed actions and risk levels
   * Collects explicit user approvals
   * Displays execution results and logs

2. **Agent Orchestrator**

   * Sends user context to the LLM
   * Receives structured plans (tool calls)
   * Coordinates the execution lifecycle

3. **Policy Engine**

   * Validates all proposed tool calls
   * Enforces allowlists and safety constraints
   * Assigns risk levels (Low / Medium / High)

4. **Sandboxed Executor**

   * Executes approved commands only
   * Enforces timeouts and output limits
   * Prevents shell injection and environment leakage

5. **File Access Layer**

   * Performs metadata-based file search
   * Reads bounded file contents
   * Enforces workspace-root scoping

6. **Audit Log**

   * Records all user inputs, plans, approvals, and executions
   * Enables debugging, review, and traceability

---

## 2.3 Product Functionality / Features

At the MVP level, the system shall provide:

* Natural language task input
* File search by metadata (filename, modification date, size)
* Bounded file content reading
* Restricted command execution via allowlists
* Explicit user approval workflow
* Action logging and export

The system shall **not** autonomously execute actions without explicit user consent.

---

## 2.4 Constraints

* Must run on macOS
* Must comply with macOS sandboxing and entitlement rules
* Must operate without Full Disk Access
* Must function with minimal system permissions
* Must not rely on background daemons or kernel extensions

---

## 2.5 Assumptions and Dependencies

### Assumptions

* The user explicitly selects a workspace directory
* The user reviews and approves proposed actions
* LLM output is untrusted and must always be validated

### Dependencies

* Availability of an LLM API or local LLM runtime
* macOS APIs for file metadata search
* XPC for process separation
* User has basic file system literacy

---

## 3. Specific Requirements

This section defines detailed, testable requirements for the MVP, aligned with the LLM-in-Sandbox reference implementation and paper.

---

## 3.1 Functional Requirements

### 3.1.1 Common Requirements

FR-1. The system shall require the user to explicitly select a **workspace root directory** before any file or command operation.

FR-2. The system shall treat all LLM outputs as **untrusted proposals**, not executable instructions.

FR-3. The system shall validate every proposed tool call against a policy engine before execution.

FR-4. The system shall log all user inputs, proposed plans, approvals, denials, executions, and results in an append-only audit log.

FR-5. The system shall support a bounded, iterative tool-use loop (plan → observe → plan), similar to the LLM-in-Sandbox execution model.

---

### 3.1.2 File Search Requirements

FR-6. The system shall provide a `file_search` capability that allows searching files by metadata only (filename, modification date, size).

FR-7. The `file_search` capability shall be strictly scoped to the workspace root directory.

FR-8. The system shall enforce a maximum result limit for file searches (default 20, maximum 100).

FR-9. The system shall not read file contents during file search operations.

---

### 3.1.3 File Read Requirements

FR-10. The system shall provide a `file_read` capability for reading file contents.

FR-11. The `file_read` capability shall only allow access to files within the workspace root directory.

FR-12. The system shall enforce strict byte limits on file reads (default 50 KB, maximum 200 KB).

FR-13. If a file is binary, the system shall return a base64-encoded preview and mark it as binary.

---

### 3.1.4 Command Execution Requirements

FR-14. The system shall provide a `command_exec` capability for executing system commands.

FR-15. The system shall only allow command execution through an allowlisted set of executables.

FR-16. The system shall prohibit shell-based execution (e.g., `/bin/sh -c`).

FR-17. The system shall enforce execution timeouts and output size limits.

FR-18. Commands shall execute only within the workspace root directory.

FR-19. Commands containing blocked tokens or patterns (destructive, privilege escalation, networking) shall be denied.

---

### 3.1.5 User Approval Requirements

FR-20. The system shall classify proposed actions into risk levels (Low, Medium, High).

FR-21. Medium-risk actions shall require explicit user approval before execution.

FR-22. High-risk actions shall be blocked entirely in the MVP.

FR-23. The system shall present proposed actions in a human-readable approval UI, including risk level and sanitized previews.

---

## 3.2 External Interface Requirements

### 3.2.1 User Interface

EI-1. The system shall provide a chat-based interface for user interaction.

EI-2. The system shall display proposed actions and request approval when required.

EI-3. The system shall display execution results and errors in the UI.

EI-4. The system shall provide an option to export audit logs.

---

### 3.2.2 LLM Interface

EI-5. The system shall communicate with the LLM via a structured JSON-based API.

EI-6. The system shall constrain LLM responses to a predefined schema for plans and tool calls.

---

## 3.3 Internal Interface Requirements

II-1. The UI layer shall communicate with the agent orchestrator via in-process method calls.

II-2. The agent orchestrator shall communicate with the policy engine synchronously for validation.

II-3. The agent orchestrator shall communicate with the executor via XPC.

II-4. The executor shall return structured execution results to the orchestrator.

---

## 4. Non-Functional Requirements

---

## 4.1 Security and Privacy Requirements

NFR-1. The system shall operate under the principle of least privilege.

NFR-2. The system shall not request Full Disk Access or Accessibility permissions in the MVP.

NFR-3. The system shall prevent network access during command execution in the MVP.

NFR-4. The system shall isolate command execution from the UI process using XPC.

NFR-5. The system shall treat all file contents and command outputs as sensitive data.

NFR-6. The system shall redact potential secrets from logs and UI output.

---

## 4.2 Environmental Requirements

NFR-7. The system shall run on macOS.

NFR-8. The system shall support Apple Silicon and Intel architectures.

NFR-9. The system shall function offline except for optional LLM API calls.

---

## 4.3 Performance Requirements

NFR-10. File search operations shall return results within 2 seconds for typical workspaces.

NFR-11. Command execution shall enforce configurable timeouts (default ≤10 seconds).

NFR-12. The system shall remain responsive during long-running operations.

---

## 5. Use Case Specification

---

### UC-1: Search for Files by Time Range

**Actor:** User

**Description:** User asks the system to find files modified within a given time range.

**Main Flow:**

1. User inputs a natural language request.
2. LLM proposes a `file_search` action.
3. Policy engine validates the action.
4. System executes the search.
5. Results are displayed to the user.

**Alternate Flow:**

* If timeframe is ambiguous, the system asks a clarifying question.

---

### UC-2: Read a File

**Actor:** User

**Description:** User asks to inspect a specific file.

**Main Flow:**

1. User requests file content.
2. LLM proposes a `file_read` action.
3. Policy engine validates scope and limits.
4. System reads the file and displays bounded content.

---

### UC-3: Execute a Command with Approval

**Actor:** User

**Description:** User requests an operation requiring command execution.

**Main Flow:**

1. User submits a task.
2. LLM proposes a `command_exec` action.
3. Policy engine evaluates risk as Medium.
4. System requests user approval.
5. Upon approval, command is executed.
6. Output is returned and logged.

**Alternate Flow:**

* If the command violates policy, execution is denied and explained.

---

### UC-4: Blocked Action

**Actor:** User

**Description:** User requests a dangerous or disallowed action.

**Main Flow:**

1. User submits request.
2. LLM proposes a high-risk or invalid action.
3. Policy engine blocks the action.
4. System explains the denial and suggests safer alternatives.

---

## 6. UML Use Case Diagram

Not included in MVP scope.

---

## 7. Class Diagrams

Not included in MVP scope.

---

## 8. Sequence Diagrams

Not included in MVP scope.
