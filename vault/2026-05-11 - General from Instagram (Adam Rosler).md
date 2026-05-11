---
type: instagram-video
date: 2026-05-11
author: Adam Rosler
url: https://www.instagram.com/reel/DYIlmRRkQRz
category: General
tags: ['#tech/machine-learning', '#tools/gemini-ai', '#productivity/advice', '#tech/ai-models']
---
# General by Adam Rosler

> **AI Summary:** This content highlights the crucial difference between advertised and actual working context windows in large language models (LLMs), noting that effective comprehension often collapses past about 32,000 tokens. It offers strategic advice for prompt engineering to maximize model understanding.

## Extracted Content
Many [[Large Language Model]]s ([[LLM]]s) advertise very large token context windows, such as [[Gemini 3]] with 2 million tokens, [[Claude 4]] with 1 million, and [[GPT-5]] with 400,000. However, actual testing reveals that their effective working window, or "comprehension limit," often collapses significantly past approximately [[32,000 tokens]] for most models.

This discrepancy is due to several factors:
*   **Sliding window attention**: Older tokens tend to be dropped.
*   **Attention sinks**: Unused budget is often allocated to the first few slots.
*   **Lost middle effect**: Content placed in the middle of a long prompt receives the least attention.

The working window is what truly survives these effects. While newer models are pushing this limit further, it's crucial to understand that the "spec sheet number" refers to the *input limit*, not the *comprehension limit*.

**Practical Advice for Prompting:**
*   Treat [[32,000 tokens]] as your safe zone for effective comprehension.
*   Always place the core [[question]] and key chunks of information at the *end* of your prompt, where the model is still actively 'listening'.
*   Prioritize [[Retrieval Augmented Generation]] (RAG) or other retrieval methods over simply 'stuffing' all information into a single, long prompt.

### Summary
*   Advertised [[LLM]] context windows (e.g., [[Gemini 3]], [[Claude 4]], [[GPT-5]]) are significantly larger than their practical working comprehension limits, often around [[32,000 tokens]].
*   Factors like sliding window attention, attention sinks, and the lost middle effect contribute to this reduced effective window.
*   For optimal results, place critical information and questions at the end of prompts and favor retrieval methods over excessively long inputs.

---
### Original Caption
* Your model says one million tokens. Past 32K it stops listening.

Gemini 3 advertises 2M. Claude 4 advertises 1M. GPT-5 advertises 400K. On needle-in-a-haystack tests, accuracy collapses past about 32K for almost all of them. The advertised bar is huge. The working bar is roughly the same width across every model.

Three things stack. Sliding-window truncation drops old tokens. The attention sink dumps unused attention into the first few slots, keeping them sharp. The lost-middle effect forgets anything in the middle of a long prompt.

Treat 32K as the safe zone. Put the question and the critical chunks at the end of the prompt. Retrieval beats stuffing. Position beats volume.
