# res://src/meta/flea_listing.gd
class_name FleaListing
extends RefCounted
## One player-to-player market listing. The item is held in escrow (encoded)
## from the moment it is listed until it sells, is cancelled, or expires.

enum Status { ACTIVE, SOLD, EXPIRED, CANCELLED }

var id: int = 0
var seller: String = ""
var item: Dictionary = {} # ItemCodec encoding (escrow)
var price: int = 0
var listed_raid: int = 0
var expiry_raids: int = 3 # < 0 = never expires (seeded stock)
var status: int = Status.ACTIVE
var fee_paid: int = 0

func expires_at_raid() -> int:
	return listed_raid + expiry_raids

func is_expirable() -> bool:
	return expiry_raids >= 0

## Escrow payload display. The dict is ItemCodec encoding and carries "path", so
## the name resolves through the SAME registry as the trader offers — the raw
## payload "name" is a warned fallback for an item nobody registered. Flea
## listings are unbounded (any item a player owns), so there is no "every flea
## item is registered" invariant; what is enforced is that the path the player
## earned through a trader renders the same way here as it does in the market.
func item_name() -> String:
	var path := String(item.get("path", ""))
	var localized := ItemNames.display_name_for_path(path)
	if localized != "":
		return localized
	push_warning("FleaListing: '%s' has no ItemNames entry; rendering the payload name" % path)
	return String(item.get("name", "?"))

func status_name() -> String:
	# A STATUS IS DISPLAY TEXT, not an enum key. The Status enum stays the
	# machine identity (it is what to_dict persists); only what a player reads
	# goes through the catalogue. QA's review of 19a3043 is what caught this: the
	# item name in the same line WAS localised, so the line rendered one
	# translated word inside an untranslated sentence. The worked example is
	# deliberately not written out here: the leak check greps these sources for
	# msgstr values, and my first draft of this comment pasted one and was
	# caught by it. Comments are not exempt from the check, which is the point.
	match status:
		Status.ACTIVE: return tr("Active")
		Status.SOLD: return tr("Sold")
		Status.EXPIRED: return tr("Expired")
		Status.CANCELLED: return tr("Cancelled")
	return "?"

## The HUD/report one-liner, assembled from catalogue keys like every other
## visible string. The frame is a key, not a format string, so a game that ships
## another locale changes nothing here.
func line() -> String:
	return _t("Listing #%d %s %d cr [%s] seller=%s") % [id, item_name(), price, status_name(), seller]

## tr() is instance-bound and status_name() is called from contexts that hold no
## Node, so the static translation entry point is used here.
func _t(key: String) -> String:
	return TranslationServer.translate(key)

func to_dict() -> Dictionary:
	return {
		"id": id,
		"seller": seller,
		"item": item,
		"price": price,
		"listed_raid": listed_raid,
		"expiry_raids": expiry_raids,
		"status": status,
		"fee_paid": fee_paid,
	}

static func from_dict(d: Dictionary) -> FleaListing:
	var l := FleaListing.new()
	l.id = int(d.get("id", 0))
	l.seller = String(d.get("seller", ""))
	var it = d.get("item", {})
	if it is Dictionary:
		l.item = it
	l.price = int(d.get("price", 0))
	l.listed_raid = int(d.get("listed_raid", 0))
	l.expiry_raids = int(d.get("expiry_raids", 3))
	l.status = int(d.get("status", Status.ACTIVE))
	l.fee_paid = int(d.get("fee_paid", 0))
	return l
