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
	# Prefer the atomic POSIX-style replace. If a platform refuses replacement,
	# move the old file aside only for the retry, and restore it if the retry
	# fails; never delete the last known-good save before a replacement exists.
	var err := DirAccess.rename_absolute(tmp, path)
	if err == OK:
		return OK
	if not FileAccess.file_exists(path):
		DirAccess.remove_absolute(tmp)
		return err
	var backup := path + ".previous"
	DirAccess.remove_absolute(backup)
	var backup_err := DirAccess.rename_absolute(path, backup)
	if backup_err != OK:
		DirAccess.remove_absolute(tmp)
		return backup_err
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		var restore_err := DirAccess.rename_absolute(backup, path)
		if restore_err != OK:
			push_error("ProfileStore: save failed and previous profile could not be restored (err %d)" % restore_err)
		else:
			DirAccess.remove_absolute(backup)
		return err
	DirAccess.remove_absolute(backup)
	return OK

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
	# A future format is never trusted (we cannot know what it means), and a save
	# with no usable version cannot be reasoned about at all: quarantine both.
	if version > MetaProfile.VERSION or version < 1:
		_quarantine(path)
		push_warning("ProfileStore: save version %d unsupported (accepts 1..%d) — starting clean" % [version, MetaProfile.VERSION])
		return MetaProfile.new()
	# An older format we CAN convert is migrated, never quarantined: quarantining a
	# readable v1 save would be silent data loss for every live profile.
	if version < MetaProfile.VERSION:
		var migrated := MetaProfile.migrate(data)
		if int(migrated.get("version", -1)) != MetaProfile.VERSION:
			_quarantine(path)
			push_warning("ProfileStore: could not migrate save v%d -> v%d — starting clean (kept as .corrupt backup)" % [version, MetaProfile.VERSION])
			return MetaProfile.new()
		data = migrated
		push_warning("ProfileStore: migrated save v%d -> v%d" % [version, MetaProfile.VERSION])
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
