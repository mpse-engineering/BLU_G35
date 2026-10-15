# Disclaimers — read them all, then decide

1) **You can brick your phone.** Like any phone-firmware tool, things can go
   wrong. During development on the tested BLU G35 and firmware revision,
   every software-reachable failure state encountered was recovered through
   download mode. That is a record of the tested hardware and workflow, not a
   universal guarantee. Deviating from the procedure, using the wrong model or
   build, improvising writes, or skipping the insurance increases risk.

2) **Make sure your phone is the exact model and firmware.** This kit is for
   the **BLU G35 (Unisoc SC9863A)** and one firmware revision. Check the model
   (label under the battery / Settings → About phone), and let the kit's own
   chip check and step02 fingerprint be the final word — they hard-fail on
   any mismatch, with no override, by design.

3) **How this kit was proven.** The full stock rollback/relock/wipe procedure
   was executed successfully twice on a physical BLU G35. After the fixes
   were consolidated, the complete rooting workflow was executed end to end
   in a third rooting run. `./verify.sh` checks the manifest, patch artifacts,
   and offline test scenarios on every fresh copy; `./prepare.sh` re-derives
   patch artifacts from the shipped firmware itself. If it works for you,
   `./make_report.sh` adds your result to the public record.

4) **The optional `userdata.img` path has not been field-tested.** The maintainer
   did not select YES for user-data capture during the physical test cycles.
   The option is implemented using the same image capture/write path as other
   partitions, and the maintainer expects it to work, but the user-data-specific
   capture and post-reset restore have not been validated end to end on-device.
   Do not rely on it as your only backup. If you select NO, `userdata.img` is
   omitted from the insurance and the kit cannot restore the phone's prior
   user-data partition. Independently back up important data before unlocking.

5) **When you succeed, report back.** Others deciding whether to trust this
   kit need to see proof it works (see `SUCCESS_REPORT.md` and the "be nice"
   chapter): the boot-screen photo showing the unlocked warning, the terminal
   transcript, the kit hash and your firmware revision. That report is the
   same thing you looked for before starting. Post it.
