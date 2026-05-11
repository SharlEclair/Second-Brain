---
type: instagram-video
date: 2026-05-12
author: Adam Rosler
url: https://www.instagram.com/reel/DYLlSR8gW6R
category: General
tags: ['#tech/machine-learning', '#tech/data-science', '#general/inspiration']
content_hash: 569d17520ff291dd4d15224a7b43ae20
transcript_status: complete
ai_model: models/gemini-2.5-flash-lite
processor: 
---
# General by Adam Rosler

> **AI Summary:** This content explains how Qwen extended its context window from 32K to 1M tokens using the YaRN method, which modifies RoPE encoding to preserve high-frequency details. This advancement allows models to process significantly longer sequences without a corresponding increase in training time.

## Extracted Content
- The [[Qwen]] model was trained on 32,000 tokens and later scaled to 1 million tokens.
- This scaling was achieved without additional training for the extended length by modifying the [[RoPE]] encoding mechanism using the YaRN technique.
- YaRN preserves high-frequency details by selectively squishing low-frequency rotations while leaving high-frequency ones largely intact, enabling significantly longer context windows.

## Raw Transcript
Quen trained on 32,000 tokens. They shipped it at one million, 30 times longer than anything it ever saw at training time. Zero training examples at the new length. They stretched the math after training, and it still works. Rope encodes each position as a rotation. Every dimension spins at a different frequency. Inside the train range, those angles are familiar. Past it, you hit angles, the model has literally never seen before. Outputs collapse into noise. The naive fix is to squish all the rotations down evenly. But that destroys the high frequency detail that tells nearby tokens apart. That's yarn. Squish low frequencies hard, leave high frequencies almost alone. Plus a small temperature bump on attention. A few hundred fine-tuned steps, and your context stretches up to 32 times longer. Quen and Deepseek both ship it. Long context isn't training, it's geometry.


---
### Original Caption
* Qwen trained on 32K tokens. They shipped it at 1M. Thirty times longer than anything it ever saw at training time.

RoPE encodes each token position as a rotation. Every dimension spins at a different frequency. Inside the trained range, those angles are familiar. Past it, you hit angles the model has literally never seen before. Outputs collapse into noise.

The naive fix is to squish all the rotations down evenly. But that destroys the high-frequency detail that tells nearby tokens apart.

YaRN squishes low frequencies hard and leaves high frequencies almost alone. Plus a small temperature bump on attention. A few hundred fine-tune steps later, your context stretches up to 32× longer. Qwen and DeepSeek both ship it.

Long context isn't training. It's geometry.
