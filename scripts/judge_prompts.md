# Blind judge prompts (filled in by the lead for each pair)

## Screen pair

You are reviewing two screenshots of iPhone app screens: `{dir}/image-1.png` and
`{dir}/image-2.png`. They come from two different apps and show the same kind of screen
("{kind}"). You are told nothing else about them; do not guess which app they are from and do
not look at any other file.

Read both images (use the Read tool on each path). Then write your answer as JSON to
`{dir}/verdict.json` (use the Write tool) with exactly these keys:

- "image1_elements": every visible element and action on image 1 (controls, text blocks,
  navigation, states), as short strings.
- "image2_elements": the same for image 2.
- "better": "image-1", "image-2" or "equal": which is the more complete and better-finished
  screen for its job.
- "why": two to four sentences on completeness, clarity, visual finish and polish.
- "only_in_image1": things image 1 has that image 2 lacks, each as
  {"item": "...", "kind": "feature" | "content" | "branding" | "needs-server"} where "content" is
  sample text/media, "branding" is logo/name/colours, "needs-server" is something that only
  works with an online account or other people (share links, other users' comments, viewer
  counts, sign-in).
- "only_in_image2": the same for image 2.
- "preference_reasons": if you prefer one image, list each reason, each tagged with the same
  kinds plus "craft" (layout, hierarchy, finish) or "completeness".

Reply with one line: the verdict file path.

## Flow pair

You are reviewing two filmstrips of iPhone app flows: `{dir}/strip-1.png` and
`{dir}/strip-2.png`. Each strip shows the same kind of flow ("{kind}") as {n} screens left to
right, from two different apps. You are told nothing else; don't guess the apps or read other files.

Read both images. Write JSON to `{dir}/verdict.json` with keys:
- "steps1" and "steps2": one short description per screen, in order.
- "correspond": true/false, whether step k of one strip does the same job as step k of the other
  for every k; "mismatches": list of {"step": k, "detail": "..."}.
- "better": "strip-1" | "strip-2" | "equal", "why": two to four sentences.
- "only_in_strip1" / "only_in_strip2": items with "kind" as in a screen review
  ("feature" | "content" | "branding" | "needs-server").
- "preference_reasons": as in a screen review.

Reply with one line: the verdict file path.
