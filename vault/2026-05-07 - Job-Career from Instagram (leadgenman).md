---
type: instagram-carousel
date: 2026-05-07
author: leadgenman
url: https://www.instagram.com/p/DXPlgNwDZgz
category: Job/Career
tags: ['#inbox/instagram', '#productivity/workflows', '#productivity/advice', '#career/tips', '#tools/automation']
---
# [[Job/Career]] by [[leadgenman]]

> **[[AI Summary]]**: [[Boris Cherny]]'s [[CLAUDE.md]] file outlines a comprehensive [[workflow]] for efficient [[task management]], [[self-improvement]], and [[code quality]], emphasizing [[planning]], [[verification]], and [[core development principles]].

## Extracted Content
## [[Boris Cherny]]'s [[CLAUDE.md]] File

### [[Workflow Orchestration]]
This section provides [[actionable advice]] on structuring complex tasks and maintaining [[high-quality output]].

**[[Key Skills]]**: [[Planning]], [[Problem Solving]], [[Quality Assurance]], [[Continuous Improvement]]

**[[Actionable Advice]]**:

1.  **[[Plan Mode Default]]**
    *   Enter [[plan mode]] for ANY non-trivial task (3+ steps or [[architectural decisions]]).
    *   If something goes sideways, STOP and re-plan immediately.
    *   Use [[plan mode]] for [[verification steps]], not just building.
    *   Write [[detailed specs]] upfront to reduce [[ambiguity]].

2.  **[[Subagent Strategy]]**
    *   Use [[subagents]] liberally to keep [[main context window]] clean.
    *   Offload [[research]], [[exploration]], and [[parallel analysis]] to [[subagents]].
    *   For [[complex problems]], throw more [[compute]] at it via [[subagents]].
    *   One task per [[subagent]] for focused [[execution]].

3.  **[[Self-Improvement Loop]]**
    *   After ANY [[correction]] from the user: update `[[tasks/lessons.md]]` with the [[pattern]].
    *   Write [[rules]] for yourself that prevent the same [[mistake]].
    *   Ruthlessly iterate on those [[lessons]] until [[mistake rate]] drops.
    *   Review [[lessons]] at [[session start]] for relevant [[project]].

4.  **[[Verification Before Done]]**
    *   Never mark a task complete without proving it works.
    *   Diff [[behavior]] between [[main]] and your changes when relevant.
    *   Ask yourself: "Would a [[staff engineer]] approve this?"
    *   Run [[tests]], check [[logs]], demonstrate [[correctness]].

5.  **[[Demand Elegance (Balanced)]]**
    *   For non-trivial changes: pause and ask "Is there a more [[elegant way]]?"
    *   If a fix feels [[hacky]]: "Knowing everything I know now, implement the [[elegant solution]]."
    *   Skip this for simple, obvious fixes -- don't [[over-engineer]].
    *   Challenge your own [[work]] before presenting it.

6.  **[[Autonomous Bug Fixing]]**
    *   When given a [[bug report]]: just fix it. Don't ask for [[hand-holding]].
    *   Point at [[logs]], [[errors]], [[failing tests]] -- then resolve them.
    *   Zero [[context switching]] required from the user.
    *   Go fix [[failing CI tests]] without being told how.

### [[Task Management]]
This section outlines a [[structured approach]] to managing tasks from [[planning]] to [[completion]] and [[learning]].

**[[Key Skills]]**: [[Organization]], [[Tracking]], [[Documentation]], [[Learning]]

**[[Actionable Advice]]**:

1.  **[[Plan First]]**: Write [[plan]] to `[[tasks/todo.md]]` with [[checkable items]].
2.  **[[Verify Plan]]**: Check in before starting [[implementation]].
3.  **[[Track Progress]]**: Mark items complete as you go.
4.  **[[Explain Changes]]**: High-level [[summary]] at each step.
5.  **[[Document Results]]**: Add [[review section]] to `[[tasks/todo.md]]`.
6.  **[[Capture Lessons]]**: Update `[[tasks/lessons.md]]` after [[corrections]].

### [[Core Principles]]
These [[principles]] guide a [[minimalist]] and [[effective approach]] to [[software development]] and [[problem-solving]].

**[[Key Skills]]**: [[Critical Thinking]], [[Code Quality]], [[Responsibility]]

**[[Actionable Advice]]**:

*   **[[Simplicity First]]**: Make every change as simple as possible. Impact [[minimal code]].
*   **[[No Laziness]]**: Find [[root causes]]. No [[temporary fixes]]. [[Senior developer standards]].
*   **[[Minimal Impact]]**: Only touch what's necessary. No [[side effects]] with [[new bugs]].

---
### Original Caption
* [[Core Principles]] from [[Boris Cherny]]’s [[CLAUDE.md]] are the [[cheat code]].

[[Simplicity first]], [[smallest change that ships]],
[[No laziness]], find [[root causes]] and leave [[no patches]],
[[Minimal impact]], touch only what the task needs,
[[Plan mode]] for anything past three steps,
[[Elegance check]] before I call work done ✅

This one file alone is why my [[Claude Code]] is [[vibemaxxinggg]].

Comment “MD” to grab the full [[playbook]].