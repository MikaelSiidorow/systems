---
name: unslop
description: Cut AI tells and padding from prose. Use when the user says "unslop", "make it shorter" or "humanize".
---

# Unslop

Edit the text in place, keeping its meaning, facts, links, code and the author's register. Technical text stays plain and neutral; personal writing keeps its voice.

## 1. Cut

- Lead with the point. Drop preambles, signposting ("Let's dive in", "Here's what changed") and closing summaries that repeat the body.
- Drop filler, hedges, sycophancy and collaborative artifacts ("Great question", "I hope this helps", "Let me know if").
- Drop change inventories a diff already shows; keep the why, the risk and what to check.
- Shorten lists that only exist to look thorough, and headers over one or two lines of text.

"make it shorter" means this step only: same content, fewer words.

## 2. Plain words

- Replace inflated vocabulary and significance claims with the concrete claim ("is", "has", "fixes").
- Replace em and en dashes with commas, colons, parentheses or full stops.
- Break up rule-of-three cadence, "not X but Y" parallelisms, staccato punchlines and aphorisms.
- Turn boldface and inline-header lists back into sentences unless the format needs them.
- Use sentence case in headings and straight quotes.

## 3. Check

Read it once more and ask what still sounds generated. Judge by clusters of tells, not one em dash or one "however"; leave quotations, names and specific detail alone. For the full catalogue with before/after examples and false positives, read [patterns.md](patterns.md).

Done when the text keeps every fact and decision of the original, has no tell from steps 1 and 2, and is no longer than it was.

Return only the edited text, plus one line on what you cut if the user asked for a review rather than a rewrite.
