---
type: instagram-video
date: 2026-05-06
author: Sri Nithya Thimmaraju
url: https://www.instagram.com/reel/DX0u_BzuAGm
category: Job/Career
tags: ['#inbox/instagram', '#tech/machine-learning', '#tech/data-science', '#career/tips', '#productivity/workflows']
---
# Job/Career by [[Sri Nithya Thimmaraju]]

> **[[AI Summary]]**: [[AI observability]] is crucial for [[LLM applications]] as it addresses subtle failures where [[systems]] appear healthy but provide incorrect answers, shifting focus from uptime to understanding why an [[AI system]] behaves a certain way. It emphasizes tracing individual [[requests]] to [[debug]] and improve the [[quality]], [[safety]], and [[groundedness]] of [[AI responses]].

## Extracted Content
### [[AI Observability]] in [[LLM Engineering]]

[[AI observability]] is critical because [[AI applications]] can fail subtly, delivering wrong answers even when all [[system metrics]] appear healthy. Unlike [[traditional software]] where failures are obvious, [[LLM apps]] can be online and fast, yet provide completely incorrect [[responses]]. [[Observability]] tracks the internal journey of an [[AI request]] from [[user query]] to [[final answer]], with a "[[trace]]" being the step-by-step record. This allows [[teams]] to identify exactly why an [[AI system]] misbehaved, such as pulling the wrong [[document]] or ignoring correct [[information]], preventing [[issues]] like [[customers]] receiving [[incorrect refund policies]].

**Key Skills:**
*   **Understanding [[LLM Observability]]**: Differentiating [[AI failure modes]] from [[traditional software issues]].
*   **[[Trace Analysis]]**: Ability to interpret step-by-step records of [[AI requests]] to diagnose problems.
*   **[[Debugging LLM Systems]]**: Pinpointing exact [[failure points]] (e.g., [[retriever]], [[model]], [[prompt version]], [[agent tool calls]]).
*   **Defining [[Observability Rules]]**: Setting criteria to flag unsupported, risky, or inconsistent [[AI responses]].
*   **[[LLM Quality Assurance]]**: Focusing on [[answer usefulness]], [[groundedness]], [[safety]], absence of [[hallucinations]], [[cost]], and [[performance consistency]], beyond just [[system uptime]].

**Actionable Advice:**
1.  **Build a [[RAG Chatbot Project]]**: Create a small [[RAG chatbot]] (e.g., with 20 [[documents]]).
2.  **Implement an [[Observability Dashboard]]**: Integrate a [[dashboard]] with defined [[rules]] to track:
    *   Every [[user question]]
    *   [[Retrieved chunks]]
    *   [[Model responses]]
    *   [[Latency]]
    *   [[Token scores]]
    *   [[Answer relevance]]
    *   [[User feedback]]
3.  **Establish a "[[Bad Answers]]" Page**: Dedicate a section to log instances where the [[bot]] gives weak or [[rule-breaking answers]].
4.  **Utilize [[Traces]] for [[Debugging]]**: When a [[bad answer]] occurs, open the full [[observability trace]] to identify the [[failure point]] (e.g., in the [[prompt]] or [[retriever]]), fix it, and re-test.

**Industry Trends:**
*   **Shift from [[Monitoring]] to [[Observability]]**: The focus in [[AI]] is moving from "Is the [[system]] alive?" to "Why did the [[system]] behave this way?"
*   **[[LLM Observability]] as a Core Concept**: Becoming one of the most important [[ideas]] in [[LLM engineering]] for [[2026]].
*   **Redefining [[AI Product Quality]]**: [[Quality]] is no longer just [[uptime]] but encompasses [[utility]], [[factual grounding]], [[safety]], [[non-hallucination]], [[cost-efficiency]], and [[resilience to minor changes]].

---
### Original Caption
* Step-by-Step guide ⤵️
Step 1: Capture the [[request]]
Log the [[user question]], [[session ID]], [[timestamp]], [[model name]], [[prompt version]], [[temperature]], and [[environment]].

Step 2: Trace the [[pipeline]]
Break one [[AI request]] into smaller steps called [[SPANS]]
1. [[User question]]
2. [[Intent router]]
3. [[Retriever]]
4. [[Retrieved chunks]]
5. [[LLM call]]
6. [[Tool calls]]
7. [[Final response]]
This full journey is called a [[TRACE]].

Step 3: Store the important [[context]]
For a [[RAG app]], store which [[documents]] were [[retrieved]], which [[chunks]] were passed to the [[model]], [[chunk IDs]], [[similarity scores]], and [[source names]].

Step 4: Track [[system metrics]]
Measure [[latency]], [[token usage]], [[model cost]], [[error rate]], [[retries]], and [[failed tool calls]].

Step 5: Score [[answer quality]]
Add checks like:
1. Was the [[answer grounded]] in the [[retrieved document]]?
2. Did it answer the [[actual question]]?
3. Did it [[hallucinate]]?
4. Was it [[safe]]?
5. Was it too [[expensive]]?
6. Did the [[user thumbs down]] the [[response]]?

Step 6: Flag [[bad answers]]
Create [[rules]] like:
1. If no [[source]] was [[retrieved]] but the [[answer]] mentions [[policy]], flag it.
2. If the [[retrieved document]] says one thing and the [[model]] says the opposite, flag it.
3. If [[cost]] suddenly spikes, flag it.
4. If a new [[prompt version]] performs worse, flag it.

Step 7: Build a "[[Bad Answers]]" [[dashboard]]
This is where the real [[learning]] happens.
For every [[failed answer]], show:
1. [[User question]]
2. [[Retrieved chunks]]
3. [[Final answer]]
4. [[Prompt version]]
5. [[Model used]]
6. [[Cost]]
7. [[Latency]]
8. [[Faithfulness score]]
9. [[User feedback]]
10. [[Failure reason]]

Step 8: Fix and retest
Once you know the [[failure point]], you can fix the [[retriever]], [[prompt]], [[chunking strategy]], [[tool logic]], or [[model choice]].
and by building [[feedback loops]] like these, real [[AI teams]] are improving [[LLM apps]]:
[[Trace]] → [[Score]] → [[Flag]] → [[Debug]] → [[Fix]] → [[Test again]].

.
.
🏷️ [[Day 15]], [[50 Day Challenge]], [[AI Observability]], [[LLM Observability]], [[Learn AI in 2026]], [[Simplest way If learning AI in 2026]], [[Avoid AI Brain Rot]], [[Generative AI]], [[Artificial Intelligence]], [[AI]], [[Large Language Models]], [[GenAI]], [[Claude]], [[AGI]], [[ChatGPT]], [[AI Evolution]], [[Important Concepts]], [[Series]], [[AI Series]]