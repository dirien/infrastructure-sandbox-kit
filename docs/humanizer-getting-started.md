# Getting started with the Humanizer skill

The Humanizer is an agent skill that edits text to remove the tells of
AI-generated writing. It is `blader/humanizer`, version 2.9.1, MIT licensed, and
its pattern list comes from Wikipedia's "Signs of AI writing" guide. This page
covers how to install it, how to run it, what it changes, and how to get good
results.

## What it actually does

The skill is a single Markdown file (`SKILL.md`) that the agent reads as
instructions. It defines 33 numbered patterns and, for each, a before/after
example. When you point it at text, the agent scans for those patterns, rewrites
the prose to remove them, and keeps the facts intact.

It is an editor, not a detector. It rewrites; it does not just score a document.
There is no build step and no service to call. Any harness that can load a
Markdown skill can use it (Claude Code, Codex, OpenCode, and others).

## Install

You already installed it once with the skills.sh CLI:

```bash
npx skills add blader/humanizer            # project-level (current directory)
npx skills add blader/humanizer --global   # user-level (~/.claude), all your projects
```

Two other ways:

- As a Claude Code plugin, which also gives you the `/humanizer` command:

  ```
  /plugin marketplace add blader/humanizer
  /plugin install humanizer
  ```

- Manually, by copying the repo's `SKILL.md` into `~/.claude/skills/humanizer/`
  (or a project's `.claude/skills/humanizer/`).

Scope matters. A global install lives in `~/.claude/skills/` and is available in
every project. A project install lives in `<project>/.claude/skills/` and travels
with that repo. Inside a Docker sandbox, `~/.claude` is the sandbox's home, not
your host's, so a global install there lasts for that sandbox only. To keep it on
your machine, run the install on the host.

After installing, run `/reload-skills` (or restart the session) so the harness
picks it up.

## Run it

There are three ways to invoke it, and each produces a different kind of output.

### 1. On pasted text (the default)

Paste text and ask for it to be humanized. You get three things back: a draft
rewrite, a short list of what still read as AI, and the final rewrite. Use this
when you want to see the reasoning.

```
/humanizer
Nestled in the heart of the valley, our platform boasts a vibrant, cutting-edge
suite of tools that empowers teams to seamlessly unlock their full potential.
```

### 2. On a file (in place)

Point it at a file. It reads the file, runs the same rewrite loop internally, and
writes only the final version back to the file. It touches prose only and leaves
code blocks, YAML frontmatter, tables, data, and link targets alone. In the chat
you get a short summary of what changed, not the whole rewrite.

```
Run the humanizer on README.md
```

This is the mode used on this kit's own README. It removed every em dash, trimmed
words like "out of the box" and "ready-to-go", cut mechanical bold, and left all
commands and tables untouched.

### 3. Embedded in another task

When another job uses it as one step, for example writing a commit message or a
PR description, it runs the loop silently and returns only the final prose. No
draft, no audit notes. You usually will not invoke this yourself; skills and
workflows call it this way.

## What it changes

The 33 patterns fall into a few groups. These are the ones you will notice most:

- Em dashes and en dashes. The final rewrite contains none. This is a hard rule,
  not a preference, because the em dash is one of the most reliable AI tells. Each
  one becomes a period, a comma, a colon, parentheses, or a reworked sentence.
- Promotional language. Words like vibrant, nestled, boasts, seamless, rich,
  breathtaking, and "in the heart of" get cut or replaced with plain description.
- Puffed-up significance. Phrases such as "stands as a testament to", "plays a
  pivotal role", and "marks a turning point" are removed.
- Rule of three. Forced groups of three ("innovation, inspiration, and insight")
  are broken up or trimmed.
- Overused AI vocabulary. delve, leverage, crucial, underscore, tapestry,
  landscape (as an abstract noun), and similar words get replaced.
- Boldface and emoji overuse, title-case headings, curly quotes, and inline
  "**Header:** restatement" list items all get normalized.
- Filler and hedging. "In order to" becomes "to", "due to the fact that" becomes
  "because", and stacked qualifiers like "could potentially possibly" get cut.
- Chatbot artifacts. "I hope this helps", "Certainly!", "Would you like me to",
  and knowledge-cutoff disclaimers are removed when they leak into content.

The full numbered list with examples is in the skill's `SKILL.md`.

## The rules that keep it safe

- It never invents facts. Every name, number, date, quote, and citation in the
  result comes from the source. It will not add a specific detail to make a vague
  sentence sound better. If a claim has no support, it cuts the claim rather than
  dressing it up.
- It preserves information, not shape. Paragraphs can merge or split, and dull
  parts get compressed, but no claim is dropped.
- It matches voice. For a blog post or essay it can keep opinion and personality.
  For technical, legal, or reference text it stays neutral and plain, because that
  is the correct human voice there. It does not add first person or opinions to a
  README.
- It avoids false positives. Good human writing can look "AI" on the surface.
  Perfect grammar, a formal vocabulary, a single em dash, or one "however" are not
  tells on their own. The skill looks for clusters, and it leaves specific,
  hard-to-fake detail alone.

## Give it your voice

If you paste a sample of your own past writing before the text to fix, the skill
studies your sentence lengths, word choices, and habits, then matches them. A
sample outranks the skill's own style rules. If your sample uses em dashes, it
keeps them at roughly your frequency. This is the single best way to get output
that sounds like you rather than like a scrubbed average.

## A quick before/after

Before:

> Nestled in the heart of the valley, our platform boasts a vibrant, cutting-edge
> suite of tools that empowers teams to seamlessly unlock their full potential.

After:

> Our platform gives teams a set of tools for their work.

The rewrite drops the location cliché, the promotional adjectives, the copula
avoidance ("boasts"), and the vague "unlock their full potential". What is left is
the one plain claim the sentence actually made.

## Tips for real use

- Prefer file mode for docs and READMEs. It edits in place and reports a summary,
  which is easy to review in a diff before you commit.
- Feed it a writing sample when the voice matters, such as a personal post.
- Let it run embedded for commit messages and PR bodies so they read cleanly
  without extra prompting.
- Review the result before you commit. The skill runs with full agent
  permissions, and a rewrite can shift emphasis. Read the diff.
- Do not run it on quotations, proper names, titles, or example text where a
  flagged phrase is being discussed rather than used. The skill tries to skip
  these, but a human check helps.

## Maintaining and verifying

The skill ships a dependency-free check you can run from its directory:

```bash
cd ~/.claude/skills/humanizer
python3 scripts/validate-package.py     # checks SKILL.md / README / plugin.json are in sync
npx skills add . --list                 # lists the skill(s) the package exposes
```

`SKILL.md` is the source of truth and must stay in sync with `README.md` and
`.claude-plugin/plugin.json`. The version lives under `metadata.version` in the
frontmatter. Update the skill with `npx skills update humanizer`.

## Reference

- Skill repository: https://github.com/blader/humanizer
- Directory listing: https://skills.sh/blader/humanizer
- Source of the patterns: Wikipedia, "Signs of AI writing", maintained by
  WikiProject AI Cleanup.
