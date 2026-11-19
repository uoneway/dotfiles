# Vision

Direction and principles for this agent setup: the global instructions, the skills, and the workflow shared by Claude Code and Codex. Use it to decide what to add, change, or remove. It is a judgment aid, not a rulebook: when a principle and an observed result disagree, trust the result and update this file.

Last reviewed: 2026-11-20, against the sources listed at the end and an independent review by GPT-6.2 Astra.

## Direction

The models now plan, test, and finish work on their own. The setup's job is to give them what they cannot infer and to check what they produce. It should get smaller as the models improve.

## Principles

### Instructions

1. **Write only what the model cannot know.** Intent, boundaries, quality bar, environment facts, and the reasons behind them. Leave routine decisions about how to do the work to the model.
2. **State the outcome and how it will be judged.** Say what done looks like and what the user will look for in review. Keep numbered steps only where one order is safe.
3. **Plain voice, with reasons.** No emphasis markers. A prohibition carries its scope, its reason, and its exceptions, because an unqualified "never" is applied everywhere.
4. **Every rule must earn its place.** A rule stays if removing it would change behaviour. Add a rule after a failure is seen more than once, or once when the failure is costly, and fix a recurring failure at its source: a check, a lint rule, or the skill that caused it.
5. **Instructions are per-model artifacts.** Re-audit them at each model release. A workaround for one model becomes a defect on the next.
6. **Always-loaded text is expensive.** Global and repository instruction files stay short and point to other documents by when they apply. A skill description says what the skill does and when to use it, key use first.
7. **One source directory serves both tools.** Describe capabilities, not tool names. The user's instructions outrank any skill.

### Autonomy and stopping

8. **Stop only at real decisions.** Ask about goals, preferences, and actions that are hard to undo or that send or change something outside the machine. Name the steps that need no approval. Stop-for-review language and piled-up cautions cause early stops.
9. **Finish what was asked.** Work through ordinary obstacles. Report deliberate blockers and leave them alone.

### Delegation

10. **Delegate for a reason.** Independent work in parallel, verbose reading that would fill the main context, or a reader that must not share the author's context. Say when delegation applies; a standing "delegate if you can" costs more than it returns.
11. **Brief a subagent like a ticket.** What is wrong, what done looks like, and how to prove it.

### Verification

12. **A runnable check is what makes delegation safe.** Invest in checks and in ways to inspect state rather than in instructions to test. Prefer checks that exercise the real flow.
13. **Scale the check to the risk, then stop.** Evidence is the output of a check, not a statement that it passed. A fresh-context review of a diff is useful; stacked confirmation passes are not.
14. **Say what is unverified.** A source that could not be read or a check that could not be run is reported as that, never as an empty or passing result.

### Reporting

15. **Write for a reader with no context.** Decision or outcome first. Each claim that could change the decision says how it was established. State a claim with its evidence and its uncertainty.
16. **Name things exactly.** One word for one thing, no labels invented during the work, no pronoun that could point to two things.

### Documents and code

17. **A document has a primary reader.** Agent-facing documents (instruction files, skills, references) are in English, compressed, and describe only the current state. Human-facing documents (README, guides, reports) are in the user's language and are written to be read and edited by people.
18. **Do not store what can be re-read.** State lives in code, git, and trackers. A document for a person is written when it is asked for or is the deliverable. Decisions are the exception that is always worth writing: what was decided, why, and what was rejected, because no source shows a reason. Any other document for agents is written only when it saves a later agent clearly more than reading those sources would cost. Notes go stale, so check them against their source.
19. **Agents maintain the code; people review intent.** Structure code for an agent maintainer: searchable names, behaviour concentrated behind small interfaces, constraints enforced by checks instead of prose. Keep each change reviewable by a person at the level of what it is for.

### Scope of the setup

20. **Few skills, each with one job.** A skill exists for a repeated procedure or domain reference that the model does not already handle well. A third-party skill is installed unmodified only when it fits as it is; otherwise its useful parts are written into an own skill.
21. **Judge by behaviour.** A change to the setup is confirmed by running a few representative requests in both tools and comparing what happened: which skill loaded, whether a file was written, where the agent stopped, and what the user had to ask for again. Figures measured on another model or another person's tasks are a reason to try something, not proof that it works here.

## Using this file

When adding or reviewing a skill or instruction, check it against these principles. When a session goes wrong, recover the task first; then change the setup if the evidence shows the setup caused the failure.

## Sources

Observed 2026-11-19 and 2026-11-20. Quotations in the working notes passed through a summarizing fetch tool, so re-read a source before citing its wording.

- Anthropic prompting guides for Claude Fable 5.2 and Claude Opus 5.5; Agent Skills best practices; Claude Code skills and memory documentation (platform.claude.com/docs, code.claude.com/docs).
- Claude Code prompt-audit guide and the Claude Fable 5.2 migration notes bundled with Claude Code.
- claude.dev blog, September to November 2026: verification, code review, agent automations, Claude Code in the cloud, choosing a model, multi-agent teams. Anthropic research: the components of agent memory; redesigning source control.
- OpenAI guides "Using GPT-6.2" and "Prompting GPT-6.2 in Codex"; Codex documentation on AGENTS.md, skills, and subagents (developers.openai.com, learn.chatgpt.com).
- OpenAI developer blog, July to November 2026: rethinking skills and prompts for GPT-6 Astra; custom code review rules for Codex; maintaining software with the GPT-6 family; automating repetitive work with Codex.
