---
name: simplified-technical-english
version: 0.1.0
description: Write clear, short technical communication using the core principles of ASD-STE100 Simplified Technical English. Use for user-facing updates, agent reports, card reasons, commit messages, and any message where the reader must act on the content. Use when a message is dense, nested, or has been hard to read. Do not use for code, log output, or quotations that must stay verbatim.
metadata:
  short-description: Short, plain technical writing (ASD-STE100 core rules)
  source: ASD-STE100 Simplified Technical English, Issue 9, 15 January 2025
  source-url: https://www.asd-ste100.org/
  compatibility: claude-code, codex-cli, grok-cli
---

# Simplified Technical English (core rules)

A working aid for the **core** STE100 rules. It is **not** the standard.

- STE100 is copyrighted and trademarked by ASD, Brussels. The normative text
  must be obtained from STEMG. Request the free official copy:
  <https://www.asd-ste100.org/>
- Verified 2026-09-26: the site is live, and the current issue is
  **Issue 9, 15 January 2025**. The per-rule listing is served by script and was
  not machine-readable, so **the rules below are the widely published core
  principles, not a transcription.** Where this file and the standard differ,
  **the standard wins.**
- Read the rules below as constraints on *how to say it*, not as a style
  preference. If a message is hard to read, that is a defect in the message.

## Provenance rule for this project

Every claim in a report carries its source. A rule with no source is a guess.
Applies to writing as much as to measurement.

## The core rules

1. **One idea per sentence.** If a sentence has "and", "but", "which", or a
   second clause carrying its own claim, split it.
2. **Active voice.** "The gate failed", not "a failure of the gate was observed".
3. **Present tense.** Report the current state, not a narrative of the past.
4. **Short sentences.** 20 words is the working limit. 12 is better.
5. **Approved words only.** One word per concept. Do not offer synonyms.
6. **Start a procedure step with a verb.** "Measure the angle", not
   "The angle should be measured".
7. **Address the reader.** "Check speed_scale", not "one should check".
8. **No "and/or".** Name both, or name one.
9. **No filler.** Cut "please note", "it is important to", "as you can see",
   "basically", "simply", "just", "obviously", "of course".
10. **No "etc."** Name the last item.
11. **No nominalisations.** "Authorise", not "give authorisation".
12. **No gerunds in headings.** "Test results", not "Testing results".
13. **Number the steps.** 10 steps is the working maximum per procedure.
14. **Use a numeral with a unit.** "0.169 m", not "a few centimetres".
15. **Say the negative first when a rule is easy to get wrong.** "Do not treat
    a void result as a pass."

## What this is FOR in this project

The reader is a human deciding whether to act, or an agent deciding what to do
next. The failure mode is not bad English. It is a **buried action**: a real
decision or a real blocker buried in the middle of a paragraph, so the reader
acts on the wrong thing or nothing.

Therefore, for every report:

- **Put the decision or the blocker in the first line.**
- **Give every number its noun and its unit.** `0.169 m displacement`, not
  `0.169`. This is a project rule from tonight and it is not optional.
- **Say what is NOT claimed**, in one line. Do not spread caveats across
  five paragraphs.
- **Name the next actor.** "Next actor: testkit."
- **Say what you did not do** when you stopped at a boundary.

## Worked example, from this project

**Before** (real message, ~90 words in one sentence):

> The precondition chain is red because the floor does not collide and
> therefore the subject falls and is therefore past the animation LOD radius and
> is therefore frozen which is therefore why the pose readings tonight are all
> frame 0 and invalid, and the heading run which passed is a tautology.

**After** (same content, STE100):

> Four facts. Each one causes the next.
>
> 1. The test floor does not collide.
> 2. The subject falls to y = -566 m.
> 3. That is 566 m from the camera. The game freezes animation past 45 m.
> 4. A frozen clip holds frame 0. Every pose reading tonight is frame 0.
>
> Result: the pose readings are void.
> The heading run passed 7 of 7. It is void. The bot turns toward its travel
> direction before it moves, so facing equals travel by construction.
> Next actor: npc-body. Next step: compare animation direction to root direction.

Same facts. The second version is auditable, and the reader can act on it.

## Anti-patterns this project has actually hit

Do not send these. They are the real failure modes, not invented ones.

- **Dense nesting.** Four "and therefore" in one sentence. Split the chain into
  a numbered list. The chain is usually a *causal* list and reads better as one.
- **The action at the end.** Put it first, then explain.
- **A claim without its unit.** `53 tracks` and `52 bones` are different objects.
- **A caveat as a paragraph.** One line, labelled.
- **Silence as an answer.** If no decision is needed, say nothing. A message
  that only confirms receipt wastes the reader's attention.

## Scope

Apply to: user updates, agent reports, card reasons, commit messages, reviews.
Do not apply to: code, identifiers, log output, test names, or any quotation
that must stay verbatim. **Do not rewrite evidence to be compliant.** A quoted
number keeps its exact form. If the exact form is unclear, fix the number, not
the sentence.
