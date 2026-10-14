# Disclaimers — read them all, then decide

1) **You can brick your phone.** Like any phone-firmware tool, things can go
   wrong. What this project proved on this hardware: every software-reachable
   failure was recoverable through download mode, because the BootROM is mask
   ROM that no software state can alter. The real brick risk concentrates in
   ONE thing: **deviating** — wrong model, overriding the firmware gate,
   improvising writes, skipping the insurance. Follow the procedure and the
   escape hatches hold.

2) **Make sure your phone is the exact model.** This kit is for the
   **BLU G35 (Unisoc SC9863A)** and one firmware revision. Check the model
   (label under the battery / Settings → About phone), and let the kit's own
   chip check and step02 fingerprint be the final word — they hard-fail on
   any mismatch, with no override, by design.

3) **How this kit was proven.** The method was executed end-to-end
   successfully on a BLU G35 — but with a development version of these tools.
   This kit is the cleaned-up, hardened release of that same code. Lineage,
   stated plainly: the step scripts, the artifact verifier and the patch
   artifacts carry that field-proven lineage; the insurance and rollback
   tools are newer, offline-tested, and their device-proven status is noted
   in the release notes.

4) **When you succeed, report back.** Others deciding whether to trust this
   kit need to see proof it works (see SUCCESS_REPORT.md and the "be nice"
   chapter): the boot-screen photo showing the unlocked warning, the terminal
   transcript, the kit hash and your firmware revision. That report is the
   same thing you looked for before starting. Post it.
