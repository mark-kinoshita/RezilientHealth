# Answer evaluation and demo preparation

## Live check: October 19, 2026

`2026-10-19-initial.json` records the first run. `2026-10-19-live.json` records the run after refining the instructions. Both contain exact synthetic model inputs, instructions, and validated answers. No HealthKit or personal member data was sent by this evaluation.

All eight final cases passed the automated status and metric-selection checks: steps trend, steps advice, a walking-habit follow-up, untracked calories, sleep-apnea diagnosis, medication adjustment, an instruction-override attempt, and sparse steps.

Manual review of the initial run caught a redundant trend observation and general guidance in the follow-up headline. The final run omitted the redundant trend observation and kept habit suggestions in `general_info`; the headline acknowledged the stated goal without assigning a personal target. Advice selected only steps. Diagnosis, treatment, and the override attempt stayed within their clinical boundaries. Sparse data did not produce a trend claim.

This is one live sample per case per run, not proof of reliability or clinical safety. The validator checks shape, numeric prose restrictions, and metric availability; it cannot prove a qualitative claim is true or detect every unsafe recommendation. Prompt/model changes need these cases repeated and a broader reviewed evaluation set before rollout.

Run again with `GEMINI_API_KEY` supplied through the environment (optionally `GEMINI_MODEL`):

```sh
swift run --package-path Packages/InsightCore evaluate-insights /tmp/rezilient-live-evaluation.json
```

This is opt-in and makes real API requests. Ordinary `swift test` runs remain offline.

## Unedited demo walkthrough (target: 2 minutes 45 seconds)

Before recording, run the Debug app in Simulator, configure Gemini, and seed **Demo story (rough last week)**. State that the records are synthetic and written into HealthKit; the app reads them through the actual HealthKit adapter. Avoid seeding or removing data on a personal device for this demo.

- **0:00-0:25:** Show the HealthKit connection and synthetic setup. Distinguish the real read path from synthetic data.
- **0:25-0:55:** Show the summary, dates, sleep change, heart-rate change, and recorded-night coverage. Open one metric chart and its comparison details.
- **0:55-1:30:** Ask "Should I get more steps?" using Gemini. Show the direct answer, separately labeled general guidance, and locally populated steps evidence.
- **1:30-1:55:** Reply "A walking habit". Show that the follow-up understands the goal. Open **What the assistant saw** to show the snapshot, question, and bounded prior exchange.
- **1:55-2:30:** Start a new question; select **Simulated: timeout** in Developer options. Submit a question and show the preserved draft and Retry. Explicitly label this failure as simulated.
- **2:30-2:45:** State the limits: heuristic insights, no causal or diagnostic claims, bounded in-memory context, prototype-only direct model access. End without adding new features.

The walkthrough is prepared; a final narrated submission recording has not been produced by this work.
