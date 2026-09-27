# res://src/meta/role_definition.gd
class_name RoleDefinition
extends Resource
## A playable role, declared rather than coded. The free-entry mechanic ("a role
## that hands you a kit on the way in") is a value here, so a game ships its own
## roles without touching the hub, the deployment path, or this file.
##
## `display_name_key` is a PO msgid, NOT finished copy -- the same convention the
## raid HUD and the operations hub use, and the reason this project's naming
## rule costs nothing here: the neutral display name lives in the `.tres`, and
## the `.tres` is the declaration.

enum EntryPolicy {
	## Grant the kit every time the role is entered.
	GRANT_ALWAYS,
	## Grant once per profile, tracked by the existing per-role `starter_granted`
	## flag. This is the shipped behaviour.
	GRANT_ONCE,
}

@export var id: StringName = &""
## A translation key. The i18n invariant requires it to resolve.
@export var display_name_key: String = ""
## The kit this role grants on entry.
@export var grants: StarterLoadout = null
@export var on_entry: EntryPolicy = EntryPolicy.GRANT_ONCE


## Whether entering this role should grant `grants` for a profile that has not
## been granted it yet. Takes the already-granted flag so the rule lives in one
## place instead of at each call site.
func should_grant(starter_granted: bool) -> bool:
	if grants == null:
		return false
	return on_entry == EntryPolicy.GRANT_ALWAYS or not starter_granted


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(id).is_empty():
		problems.append("id is empty: a role with no id cannot be persisted or looked up")
	if display_name_key.is_empty():
		problems.append("display_name_key is empty: the role would have no name to translate")
	if grants == null:
		problems.append("grants is null: the role declares free entry but hands out nothing")
	return problems

## Whether the display name actually resolves is deliberately NOT checked here.
## This is a resource and may be validated before any catalogue is loaded, so a
## "no translation" verdict would depend on load order. `validate_i18n.gd` owns
## that question and already fails on a declared key with no entry -- one owner
## per question, rather than two checks that can disagree about who is wrong.
