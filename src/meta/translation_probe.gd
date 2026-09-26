extends RefCounted
class_name TranslationProbe

## Shared precondition for every harness that asserts a translated string.
##
## WHY THIS EXISTS. A harness that checks a translation must not inherit its
## result from the machine it runs on. TranslationServer.translate() resolves
## against the ACTIVE locale; if that locale is not the one under test, it
## returns the source string unchanged, and every assertion downstream reports
## a missing translation that is not there. That happened in CI: the pt-BR
## catalogue was tracked, complete and loaded, the active locale was "en", and
## three gates failed as if the translations were missing. A harness cannot
## detect that by asking whether the locale is REGISTERED -- a locale is
## registered whether or not it is selected, so that check is true in both the
## working and the broken case and can never fail. It has to ask whether a
## known string actually resolves.

## The locale under test. Harnesses select this explicitly and never rely on
## the host's OS locale.
const PROBE_LOCALE := "pt_BR"

## A msgid the catalogue is contractually required to carry. Chosen as a
## contract rather than read back from the catalogue on purpose: if the
## sentinel is derived from whatever the catalogue happens to contain, the
## check passes for any catalogue, including an empty one. A fixed sentinel
## makes the check capable of failing.
##
## THIS IS A FIXTURE, NOT A CONTENT CLAIM. It is wired to one specific msgid,
## so it is coupled to it on purpose. If this harness ever fails on
## catalogue_answers(), the FIRST thing to check is whether the msgid itself
## was renamed in locale/game.po - that is a fixture break and the fix is to
## update SENTINEL here. Reporting it as "the catalogue did not answer" would
## send a reader hunting a content defect that does not exist. The failure
## message therefore names this fixture explicitly.
##
## KNOWN, CHOSEN EDGE CASE: if pt-BR ever translates this msgid to the
## IDENTICAL string, the `!=` below fails on a perfectly correct catalogue. A
## translation equal to its source is a content smell in its own right, so we
## do not work around it; it is left to fail loudly rather than special-cased.
const SENTINEL := "Marked Intel"

## Select the locale under test. Call before ANY translation assertion.
## Idempotent.
##
## WHY PER-HARNESS SELECTION AND NOT A PROJECT SETTING. Two alternatives were
## measured and both are rejected:
##   - `--language <locale>` on the Godot CLI is TWO-LETTER ONLY and cannot
##     select `pt_BR`. It fails SILENTLY for a regional locale - no error, no
##     effect - so the next person to try it will conclude the sentinel is
##     broken. A silent no-op flag is the same trap as a check that cannot fail.
##   - `internationalization/locale/fallback` governs what an UNTRANSLATED
##     string falls back TO. Pointing it at pt-BR inverts the correct direction:
##     a missing English string would silently become Brazilian Portuguese.
##     Fallback must be the source language. (Declaring a default LOCALE is a
##     different control, and is tracked separately - do not assume this
##     comment settles it.)
static func select_test_locale() -> void:
	TranslationServer.set_locale(PROBE_LOCALE)

## True when the active locale is the one under test.
static func locale_is_selected() -> bool:
	return TranslationServer.get_locale() == PROBE_LOCALE

## True when a KNOWN msgid resolves to something other than itself, i.e. the
## catalogue is genuinely being consulted. This is the assertion the
## registration check could not make: it is false when the catalogue is absent,
## empty, or not the active one.
static func catalogue_answers() -> bool:
	return TranslationServer.translate(SENTINEL) != SENTINEL

## The resolved sentinel, for a failure message that names the actual value.
## Reporting "catalogue did not answer" without the value leaves the reader
## unable to tell a missing catalogue from a missing entry.
static func sentinel_result() -> String:
	return TranslationServer.translate(SENTINEL)
