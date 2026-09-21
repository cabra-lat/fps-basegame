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

func item_name() -> String:
	return String(item.get("name", "?"))

func status_name() -> String:
	match status:
		Status.ACTIVE: return "ACTIVE"
		Status.SOLD: return "SOLD"
		Status.EXPIRED: return "EXPIRED"
		Status.CANCELLED: return "CANCELLED"
	return "?"

## HUD/report one-liner.
func line() -> String:
	return "#%d %s ₽%d [%s] seller=%s" % [id, item_name(), price, status_name(), seller]

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
