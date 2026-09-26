extends RefCounted
class_name ItemDescriptions

## Player-facing item prose, resolved for display. The third member of the
## id -> English msgid -> resolved string pattern that ItemNames and FactionNames
## already implement, and the reason it is its own file rather than a method on
## ItemNames: a description is not a REGISTRY entry. Names are looked up by id
## because the .tres name is an internal identifier; a description is already
## English prose sitting in the .tres, so there is nothing to map -- only
## something to translate.
##
## WHY THIS EXISTS AT ALL. `Item.description` is an @export on the addon's base
## Item, and 122 shipped resources set it. Until the addon change that put the
## property on the base, `marked_intel.tres` -- the raid's mission item -- was a
## plain `Item`, so its description was dropped at load: `get("description")`
## returned null and the key was absent from the property list entirely. Nothing
## read the field even when it was present, which is the failure this card is
## about: a translation layer that dutifully handles a field no code reads, so
## the English looks handled while staying invisible.
##
## THE LANGUAGE RULE, decided with the property: the .tres keeps ENGLISH and the
## English IS the msgid. Resolution happens here, at render time, through the same
## TranslationServer path every other display string uses. No Portuguese literal
## enters a resource, and adding a second language is not a data-format change.
##
## Static because every caller that needs this is a static display helper
## (`FleaListing` is built from a Dictionary and is not a Node), and tr() is
## instance-bound.

## The resolved description for a resource PATH, or "" when there is nothing to
## show. This is the one the flea listing uses, and it resolves from the PATH
## rather than from the escrow payload -- deliberately, for the same reason
## `ItemNames.display_name_for_path` does.
##
## Adding "description" to `ItemCodec.encode_item()` would have been the other
## way, and it is the wrong one twice over. It would persist display text into
## player saves, where a later edit to the .tres leaves every existing save
## carrying stale English; and it would mean a saved listing renders differently
## from the item it points at. The payload already carries `path`, and the
## resource behind it is the authority -- exactly as it is for the name.
static func display_description_for_path(path: String) -> String:
	if path == "" or not ResourceLoader.exists(path):
		return ""
	return display_description(load(path))

## True when the resource at `path` has a description the catalogue cannot yet
## render. The diagnostic half of display_description_for_path(), for harnesses.
static func untranslated_for_path(path: String) -> bool:
	if path == "" or not ResourceLoader.exists(path):
		return false
	return untranslated(load(path))

## The resolved description for an item, or "" when there is nothing to show.
##
## "" IS A REAL ANSWER and the caller must handle it: no description, or a
## description the catalogue does not carry. It is deliberately NOT a fallback to
## the English source and deliberately NOT an invented "no description" string.
## An empty gap tells the player something is missing; a silently absent segment
## tells them this item simply has no description, which is true. Same principle
## as the default-empty on the six subclass `description` defaults, and the same
## reason: a placeholder is a lie with extra steps, and it would then need
## translating as well.
##
## An item whose description is English but untranslated also returns "", so the
## Portuguese frame never carries an English noun the way "Comprou marked intel"
## did. That case is not silently swallowed, though -- `untranslated()` names it,
## and the flea harness asserts the listable set is clean, so a description that
## arrives without a catalogue entry is a FAILING CHECK rather than a quiet hole.
static func display_description(item: Variant) -> String:
	var raw := _raw_description(item)
	if raw == "":
		return ""
	var resolved := TranslationServer.translate(raw)
	# Untranslated: the catalogue has no entry, so translate() handed the source
	# straight back. Returning "" keeps English out of a Portuguese frame.
	return "" if resolved == raw else resolved

## True when the item HAS a description that the catalogue cannot yet render.
## The diagnostic half of display_description(), for harnesses and warnings: it
## is what separates "this item has no description" from "we forgot to translate
## one we have".
static func untranslated(item: Variant) -> bool:
	var raw := _raw_description(item)
	return raw != "" and TranslationServer.translate(raw) == raw

## The English source text, for a harness that asserts on the msgid rather than
## on the rendered string. Not a display path -- display goes through
## display_description(), which is the one that translates.
static func source_text(item: Variant) -> String:
	return _raw_description(item)

## Reads the description off whatever the caller is holding: a live Resource, or
## the encoded Dictionary a listing carries after a round trip through the
## escrow. `get()` rather than `.description` so a caller holding a payload with
## no such key gets "" instead of a runtime error -- and so this keeps working for
## a base `Item` from a build predating the property.
static func _raw_description(item: Variant) -> String:
	if item == null:
		return ""
	if item is Dictionary:
		var v: Variant = (item as Dictionary).get("description", "")
		return v if v is String else ""
	if item is Resource:
		# The null guard is load-bearing, not defensive padding. A base `Item` from
		# a build predating the addon's `description` export answers get() with
		# null, and String(null) is a RUNTIME ERROR in Godot 4 ("Nonexistent 'String'
		# constructor"), not a coercion. Measured: the probe that found this walked
		# every shipped resource and died on exactly the resources the addon fix is
		# for. `v is String` covers both null and any other type the payload could
		# carry, and returns "" for all of them.
		var v: Variant = (item as Resource).get("description")
		return v if v is String else ""
	return ""
