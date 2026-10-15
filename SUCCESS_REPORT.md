# Success report — BLU G35 unlock kit

> Fill this in after the kit works for you, and post it where you found the
> kit. This is what gives the next person the confidence to start — the same
> confidence you looked for. Photos of the boot screen go in the post itself;
> paste the text block below as-is.

- Kit sha256 (printed where you downloaded it): `<paste>`
- Firmware revision (step02 / step02 log fingerprint): `<paste>`
- Date: `<YYYY-MM-DD>`

## Boot screen proof

*(attach a photo of the power-on screen showing the unlocked-bootloader
warning — e.g. orange state text. One photo, no personal data on screen.)*

## Terminal transcript

```
<paste the output of make_report.sh here — or by hand:

$ adb shell getprop ro.product.model
$ adb shell getprop ro.build.display.id
$ adb shell uname -a
$ adb shell su -c id
$ adb shell su -c 'ls /data'

Magisk app: Installed — version <xxxxx>
>
```

## Optional userdata.img path — did you test it?

This is the one path the maintainer left untested on hardware (DISCLAIMER
item 4, guide chapter 6). If you exercised it, your answer is evidence for
the next person; if you did not, say so plainly — both answers are records.

Did you select YES when `./insure.sh` asked whether to capture userdata.img?

- [ ] Backup and verification completed.
- [ ] Restore completed after the factory reset.
- [ ] Restored data was verified.
- [ ] Not tested / not applicable.
- [ ] Failed (describe the stage and attach relevant logs).

## Privacy note (so you can post with confidence)

None of the above exposes personal data or your IMEI. Do NOT ever post the
output of `fastboot oem get_identifier_token` — it is serial-derived device
identity. Nothing else in this template is sensitive.

## Anything that surprised you?

One or two lines help the next reader more than you'd think
(e.g. "step05's black screen lasted ~40 s", "my cable was the problem").
