# res://src/meta/flea_market.gd
class_name FleaMarket
extends RefCounted
## Player-to-player market: listings with escrow, a listing fee and expiry on
## the RAID counter (the game's unit of time). It is a second sink for loot
## alongside the trader Market, and shares the same TradeOps validation path.
##
## Single-player note: NPC listings are seeded from trader offers at a markup;
## the player's own listings sell when priced at/below a reference value on the
## next resolved raid. All formulas here are ours.

signal listing_added(listing: FleaListing)
signal listing_sold(listing: FleaListing)
signal listing_expired(listing: FleaListing)
signal listing_cancelled(listing: FleaListing)

const PLAYER_SELLER := "you"
const FEE_RATE := 0.05 # 5% of the asking price...
const FEE_MIN := 100 # ...with a floor
const DEFAULT_EXPIRY_RAIDS := 3
const SELLER_MARKUP := 1.25 # NPC listings price trader offers above cost

var listings: Array[FleaListing] = []
var profile: MetaProfile
var _next_id: int = 1

func setup(p_profile: MetaProfile) -> void:
	profile = p_profile

# ─── QUERIES ────────────────────────────────────────

func listing_fee(price: int) -> int:
	return maxi(FEE_MIN, int(ceil(maxf(price, 0) * FEE_RATE)))

func find(listing_id: int) -> FleaListing:
	for l in listings:
		if l.id == listing_id:
			return l
	return null

func active_listings() -> Array[FleaListing]:
	var out: Array[FleaListing] = []
	for l in listings:
		if l.status == FleaListing.Status.ACTIVE:
			out.append(l)
	return out

func count_by_status() -> Dictionary:
	var out := {"active": 0, "sold": 0, "expired": 0, "cancelled": 0}
	for l in listings:
		match l.status:
			FleaListing.Status.ACTIVE: out["active"] += 1
			FleaListing.Status.SOLD: out["sold"] += 1
			FleaListing.Status.EXPIRED: out["expired"] += 1
			FleaListing.Status.CANCELLED: out["cancelled"] += 1
	return out

## A listing's reference worth (our formula, not another game's): base by item
## kind plus a mass term.
func reference_value(encoded: Dictionary) -> int:
	var item := ItemCodec.decode_item(encoded)
	if item == null:
		return 0
	var base := 100
	var content = item.extra
	if content is Weapon:
		base = 8000
	elif content is Attachment:
		base = 3000
	elif content is MedicalItem:
		base = 1500
	elif content is Ammo:
		base = 150
	return base + int(item.get_mass() * 100.0)

# ─── SEEDING (reuse trader data, no duplicated offer logic) ───

func seed_from_market(market: Market, markup: float = SELLER_MARKUP) -> int:
	if market == null or profile == null:
		return 0
	var added := 0
	for trader_id in market.traders:
		var t: Trader = market.traders[trader_id]
		for offer in t.offers:
			if offer.buy_price <= 0:
				continue # barter-only lines stay with the trader
			var item := ItemCodec.item_from_path(offer.item_path)
			if item == null:
				continue
			var price := int(ceil(offer.buy_price * markup))
			_add(offer.item_path, price, "anonymous", item, -1)
			added += 1
	return added

# ─── LIST / BUY / CANCEL ────────────────────────────

## List an item the player already holds (in the stash).
func list_from_stash(path: String, price: int) -> Dictionary:
	if price <= 0:
		return _no("preco invalido")
	if TradeOps.count_in_stash(profile, path) <= 0:
		return _no("item nao encontrado no stash")
	var fee := listing_fee(price)
	if not TradeOps.can_afford(profile, fee):
		return _no("saldo insuficiente para a taxa (₽%d)" % fee)
	var item := TradeOps.find_stash_item(profile, path)
	if item == null:
		return _no("item nao encontrado no stash")
	var encoded := ItemCodec.encode_item(item)
	TradeOps.charge(profile, fee)
	TradeOps.take_from_stash(profile, path, 1)
	var listing := _add(path, price, PLAYER_SELLER, null, DEFAULT_EXPIRY_RAIDS)
	listing.item = encoded
	listing.fee_paid = fee
	listing_added.emit(listing)
	return {"ok": true, "reason": "", "listing": listing}

## Buy an active NPC listing into the stash.
func buy(listing_id: int) -> Dictionary:
	var l := find(listing_id)
	if l == null or l.status != FleaListing.Status.ACTIVE:
		return _no("listing indisponivel")
	if l.seller == PLAYER_SELLER:
		return _no("listing proprio")
	if not TradeOps.can_afford(profile, l.price):
		return _no("saldo insuficiente (₽%d)" % l.price)
	var item := ItemCodec.decode_item(l.item)
	if item == null:
		return _no("item indisponivel")
	TradeOps.charge(profile, l.price)
	if not TradeOps.deposit(profile, item):
		TradeOps.credit(profile, l.price) # honest rollback
		return _no("stash cheio")
	l.status = FleaListing.Status.SOLD
	listing_sold.emit(l)
	return {"ok": true, "reason": "", "item": item}

## Cancel your own active listing; the escrowed item returns to the stash.
## The listing fee is not refunded (plausible, and keeps it a real sink).
func cancel(listing_id: int) -> Dictionary:
	var l := find(listing_id)
	if l == null or l.status != FleaListing.Status.ACTIVE:
		return _no("listing indisponivel")
	if l.seller != PLAYER_SELLER:
		return _no("nao e seu listing")
	if not _return_escrow(l):
		return _no("stash cheio")
	l.status = FleaListing.Status.CANCELLED
	listing_cancelled.emit(l)
	return {"ok": true, "reason": ""}

# ─── RAID CLOCK ─────────────────────────────────────

## Called once per resolved raid: expire due listings (escrow back to the
## stash) and sell fairly-priced player listings.
func on_raid_resolved() -> void:
	if profile == null:
		return
	for l in listings.duplicate():
		if l.status != FleaListing.Status.ACTIVE:
			continue
		if l.is_expirable() and profile.raids >= l.expires_at_raid():
			if _return_escrow(l):
				l.status = FleaListing.Status.EXPIRED
				listing_expired.emit(l)
			continue
		if l.seller == PLAYER_SELLER and l.price <= reference_value(l.item):
			TradeOps.credit(profile, l.price)
			l.status = FleaListing.Status.SOLD
			listing_sold.emit(l)

# ─── PERSISTENCE ────────────────────────────────────

func to_dict() -> Dictionary:
	var out: Array = []
	for l in listings:
		out.append(l.to_dict())
	return {"next_id": _next_id, "listings": out}

func apply_state(d) -> void:
	if not (d is Dictionary):
		return
	_next_id = maxi(int(d.get("next_id", 1)), 1)
	var arr = d.get("listings", [])
	if arr is Array:
		for e in arr:
			if e is Dictionary:
				var l := FleaListing.from_dict(e)
				listings.append(l)
				_next_id = maxi(_next_id, l.id + 1)

# ─── REPORT ─────────────────────────────────────────

func report_lines(only_active: bool = true) -> Array[String]:
	var out: Array[String] = []
	for l in listings:
		if only_active and l.status != FleaListing.Status.ACTIVE:
			continue
		out.append(l.line())
	return out

# ─── INTERNAL ───────────────────────────────────────

func _add(path: String, price: int, seller: String, item: InventoryItem, expiry_raids: int) -> FleaListing:
	var l := FleaListing.new()
	l.id = _next_id
	_next_id += 1
	l.seller = seller
	l.price = price
	l.item = ItemCodec.encode_item(item) if item != null else {"path": path, "name": path.get_file(), "kind": "item"}
	l.listed_raid = profile.raids if profile != null else 0
	l.expiry_raids = expiry_raids
	l.status = FleaListing.Status.ACTIVE
	listings.append(l)
	return l

func _return_escrow(l: FleaListing) -> bool:
	var item := ItemCodec.decode_item(l.item)
	if item == null:
		return true # nothing to return; treat as returned
	return TradeOps.deposit(profile, item)

func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
