# Simulation artifacts

This directory contains captured outputs from the RTL regression:

- `regression_transcript.log` - QuestaSim transcript for the full nine-case
  golden-vector regression. It records compilation, simulation startup, each
  test result, and the final summary. All nine tests completed with zero errors.
- `active_processing.saif` - SAIF switching-activity capture generated during
  the fifth regression case, `05_random_image_random_kernel`, for downstream
  power analysis.

The transcript also preserves simulator warnings and end-of-run messages so the
simulation record remains auditable.
