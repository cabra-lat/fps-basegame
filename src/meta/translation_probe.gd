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
const SENTINEL := "Marked Intel"

## Select the locale under test. Call before ANY translation assertion.
## Idempotent.
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
