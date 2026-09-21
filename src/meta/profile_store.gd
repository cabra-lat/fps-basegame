# res://src/meta/profile_store.gd
class_name ProfileStore
extends RefCounted
## Versioned, atomic on-disk profile persistence.
##
## Atomic: the dictionary is serialized to a temp file, flushed, then renamed
## over the real save. A crash mid-write can never truncate the previous save.
## Tolerant: a missing, unreadable, corrupt or future-versioned save yields a
## clean profile plus a warning — never a crash — and the bad file is set aside.

const PATH := "user://profile.save"

static func save(profile: MetaProfile, path: String = PATH) -> Error:
	if profile == null:
		return ERR_INVALID_PARAMETER
	profile.version = MetaProfile.VERSION
	var tmp := path + ".tmp"
	var text := JSON.stringify(profile.to_dict(), "\t")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	f.close()
	# Rename over the live save. POSIX replaces; on failure drop the old file
	# and retry once (Windows-style overwrite refusal).
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp, path)
	return err

static func load_profile(path: String = PATH) -> MetaProfile:
	if not FileAccess.file_exists(path):
		push_warning("ProfileStore: no save at %s — starting clean" % path)
		return MetaProfile.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("ProfileStore: could not read %s (err %d) — starting clean" % [path, FileAccess.get_open_error()])
		return MetaProfile.new()
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		_quarantine(path)
		push_warning("ProfileStore: corrupt save at %s (%s) — starting clean (kept as .corrupt backup)" % [path, json.get_error_message()])
		return MetaProfile.new()
	var parsed = json.data
	if not (parsed is Dictionary):
		_quarantine(path)
		push_warning("ProfileStore: unexpected save shape at %s — starting clean" % path)
		return MetaProfile.new()
	var data := parsed as Dictionary
	var version := int(data.get("version", -1))
	if version != MetaProfile.VERSION:
		_quarantine(path)
		push_warning("ProfileStore: save version %d unsupported (want %d) — starting clean" % [version, MetaProfile.VERSION])
		return MetaProfile.new()
	return MetaProfile.from_dict(data)

static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)

static func delete(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(path + ".tmp")

## Move a bad save out of the way so the next run starts clean but the data is
## still inspectable. Best-effort: if the move fails the file is left as-is.
static func _quarantine(path: String) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	DirAccess.rename_absolute(path, path + ".corrupt-" + stamp)
