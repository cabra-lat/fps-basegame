# res://src/meta/i18n_catalogue.gd
class_name I18nCatalogue
extends RefCounted
## Reading a gettext PO file, and proving that the catalogue Godot actually
## HOLDS is that file.
##
## Split out of validate_i18n.gd, which had grown past the audit's god-object
## limit. The separation is also the right one: this class knows about PO
## syntax and about TranslationServer, and nothing else -- it does not know what
## a translation key is for, or which files are display paths.
##
## The distinction this file exists to make is "present" versus "in use". A PO
## file can sit in the tree, be registered in project.godot, and still be absent
## from the object TranslationServer hands out -- in which case a locale name is
## loaded, no message resolves, and every check written against the file passes.

## The whole catalogue as msgid -> msgstr. Read from the FILE on purpose: the
## checks that use this compare the file against the server's own object, and
## reading the file out of that object would make the comparison vacuous.
static func pairs(po_path: String) -> Dictionary:
	var out: Dictionary = {}
	var key := ""
	for raw in read(po_path).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("msgid ") and line != 'msgid ""':
			key = unquote(line.trim_prefix("msgid").strip_edges())
		elif line.begins_with("msgstr ") and not key.is_empty():
			out[key] = unquote(line.trim_prefix("msgstr").strip_edges())
			key = ""
	return out

## Just the msgstr values, which is what the leak check scans sources for.
static func msgstrs(po_path: String) -> Array[String]:
	var out: Array[String] = []
	for raw in read(po_path).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("msgid ") and line == 'msgid ""':
			continue
		if line.begins_with("msgstr ") and not unquote(line.trim_prefix("msgstr").strip_edges()).is_empty():
			out.append(unquote(line.trim_prefix("msgstr").strip_edges()))
	return out

## Whether the catalogue TranslationServer holds for `locale` is the project's
## catalogue. Returns a dictionary of individual verdicts rather than one
## boolean, because the failures are different defects and a caller that cannot
## name which one it hit has to guess:
##
##   locale_loaded   a pt_BR locale is loaded at all
##   object_held     the server holds an actual Translation for it
##   complete        the held object carries every msgid in the file
##   consistent      no msgid resolves to something other than the file declares
##   resolves        one msgid resolves end to end through translate()
##   missing / differ  the offending msgids, for the failure message
static func verify(locale: String, po_path: String) -> Dictionary:
	var verdict: Dictionary = {
		"locale_loaded": TranslationServer.get_loaded_locales().has(locale),
		"object_held": false,
		"complete": false,
		"consistent": false,
		"resolves": false,
		"missing": [],
		"differ": [],
	}
	var held: Translation = TranslationServer.get_translation_object(locale)
	if held == null:
		return verdict
	verdict["object_held"] = true
	var want: Dictionary = pairs(po_path)
	# Membership from get_message_list(), not a has_message() call: Godot 4.7's
	# Translation has no such method, and calling it aborted the caller after two
	# checks while the harness still reported a green.
	var have: PackedStringArray = held.get_message_list()
	var missing: Array[String] = []
	var differ: Array[String] = []
	for msgid in want:
		if not have.has(String(msgid)):
			missing.append(String(msgid))
		elif held.get_message(String(msgid)) != String(want[msgid]):
			differ.append(String(msgid))
	verdict["missing"] = missing
	verdict["differ"] = differ
	verdict["complete"] = missing.is_empty()
	verdict["consistent"] = differ.is_empty()
	var sample := "Marked Intel"
	verdict["resolves"] = want.has(sample) and TranslationServer.translate(sample) == String(want[sample])
	return verdict

static func read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

static func unquote(value: String) -> String:
	if value.length() < 2:
		return value
	return value.substr(1, value.length() - 2)
