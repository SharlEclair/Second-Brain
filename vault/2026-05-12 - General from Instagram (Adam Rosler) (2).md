---
type: instagram-video
date: 2026-05-12
author: Adam Rosler
url: https://www.instagram.com/reel/DYH7Zy6k4Uw
category: General
tags: ['#tech/machine-learning', '#tech/data-science', '#tech/cloud-infra', '#general/ideas', '#productivity/workflows']
content_hash: 795b5b409b2c80d4ef161ca08521f0b1
transcript_status: complete
ai_model: models/gemini-2.5-flash-lite
processor: 
---
# General by Adam Rosler

> **AI Summary:** Continuous batching in LLM inference, particularly with vLLM, significantly boosts GPU utilization and throughput (around 10x) by scheduling tokens individually instead of waiting for entire requests. This iteration-level scheduling, enhanced by paged attention, is crucial to consider when comparing inference providers.

## Extracted Content
- Explains the concept of **Continuous Batching** in Large Language Model (LLM) inference.
- Highlights the significant performance improvement (up to 10x throughput) compared to **Static Batching** due to token-level scheduling.
- Advises to inquire about token-level batching when choosing LLM inference providers, as it impacts efficiency and cost-effectiveness.

## Raw Transcript
VLLM finishes 10 requests in the time-static batching finishes 1. They never let the GPU finish a sentence. Continuous batching reschedules per token, not per request. That alone gets a 10 times throughput jump at high concurrency. Three requests in one batch. Static batching waits for the longest. The short finishes, its slot sits idle. GPU drops to 30%. Continuous batching schedules every token. The moment short ends, a new request takes its slot. GPU stays near full. It is not free. KV cache memory caps how many fit. When it fills, VLLM preamps a request. It is called iteration level scheduling. Orca first, VLLM after. So when you compare providers, ask if they batch at the token level. The price hides whether your slot is shared or wasted. Don't wait for sentences. Schedule every token.


---
### Original Caption
* Static batching = wait for the longest request. GPU drops to thirty percent.

Continuous batching = the moment a request emits its end token, a new request takes the slot. GPU stays at near full.

That is roughly ten times the throughput at high concurrency. It is called iteration-level scheduling. ORCA paper, OSDI 2022. vLLM added paged attention on top in 2023.

The honest limit: KV cache memory caps how many fit at once. When it fills, vLLM preempts a request and runs it later.

When you compare inference providers, ask if they batch at the token level. The per-request price hides whether your slot is shared or wasted.
