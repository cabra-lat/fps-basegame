# res://src/meta/market.gd
class_name Market
extends RefCounted
## Traders + live market state. Definitions are resources; stock/reputation/
## loyalty progress live here and persist inside the profile. Mutates the
## profile's currency and stash directly (single source of truth).

signal traded(trader_id: String, kind: String, item_path: String, price: int)
signal stock_reset(trader_id: String)
signal reputation_changed(trader_id: String, value: int)

const TRADERS_DIR := "res://resources/meta/traders"

var traders: Dictionary = {} # id -> Trader
var state: Dictionary = {} # id -> {"stock": {index: int}, "rep": int, "raids": int}
var profile: MetaProfile

func setup(p_profile: MetaProfile) -> void:
	profile = p_profile

# ─── LOADING / PERSISTENCE ──────────────────────────

func load_dir(dir: String = TRADERS_DIR) -> int:
	var loaded := 0
	var d := DirAccess.open(dir)
	if d == null:
		return loaded
	for f in d.get_files():
		if not f.ends_with(".tres"):
			continue
		var t := load(dir + "/" + f) as Trader
		if t == null or t.id == "":
			push_warning("Market: bad trader resource %s/%s" % [dir, f])
			continue
		add_trader(t)
		loaded += 1
	return loaded

func add_trader(t: Trader) -> void:
	if t == null or t.id == "":
		return
	traders[t.id] = t
	if not state.has(t.id):
		state[t.id] = _fresh_state(t)

func get_trader(id: String) -> Trader:
	return traders.get(id, null)

func state_of(id: String) -> Dictionary:
	return state.get(id, {})

func apply_state(d) -> void:
	if not (d is Dictionary):
		return
	for id in d:
		if not state.has(id):
			continue # trader pack changed; ignore gracefully
		var saved := d[id] as Dictionary
		var st: Dictionary = state[id]
		var saved_stock = saved.get("stock", {})
		if saved_stock is Dictionary:
			for key in saved_stock:
				st["stock"][int(key)] = int(saved_stock[key])
		st["rep"] = maxi(int(saved.get("rep", 0)), 0)
		st["raids"] = maxi(int(saved.get("raids", 0)), 0)

func to_dict() -> Dictionary:
	var out := {}
	for id in state:
		var st: Dictionary = state[id]
		var stock_out := {}
		for key in st["stock"]:
			stock_out[str(key)] = int(st["stock"][key])
		out[id] = {"stock": stock_out, "rep": int(st["rep"]), "raids": int(st["raids"])}
	return out

func _fresh_state(t: Trader) -> Dictionary:
	var stock := {}
	for i in range(t.offers.size()):
		stock[i] = int(t.offers[i].stock_max)
	return {"stock": stock, "rep": 0, "raids": 0}

# ─── QUERIES ────────────────────────────────────────

func reputation(id: String) -> int:
	return int(state_of(id).get("rep", 0))

func loyalty_level(id: String) -> int:
	var t := get_trader(id)
	if t == null:
		return 1
	return t.loyalty_level_for(profile.character_level() if profile != null else 1, reputation(id))

func stock_of(id: String, index: int) -> int:
	var st: Dictionary = state_of(id)
	var stock = st.get("stock", {})
	return int(stock.get(index, 0))

func is_unlimited(id: String, index: int) -> bool:
	var t := get_trader(id)
	if t == null or index < 0 or index >= t.offers.size():
		return false
	return t.offers[index].stock_max < 0

## Stock reset counter: call once per resolved raid.
func on_raid_resolved() -> void:
	for id in traders:
		var t: Trader = traders[id]
		if t.reset_every_raids <= 0:
			continue
		var st: Dictionary = state[id]
		st["raids"] = int(st["raids"]) + 1
		if int(st["raids"]) >= t.reset_every_raids:
			reset_stock(id)

func reset_stock(id: String) -> void:
	var t := get_trader(id)
	if t == null or not state.has(id):
		return
	state[id]["stock"] = _fresh_state(t)["stock"]
	state[id]["raids"] = 0
	stock_reset.emit(id)

# ─── BUY / SELL ─────────────────────────────────────

## Returns {ok: bool, reason: String}. Single source of truth for the HUD.
func can_buy(id: String, index: int) -> Dictionary:
	var t := get_trader(id)
	if t == null:
		return _no("trader desconhecido")
	if index < 0 or index >= t.offers.size():
		return _no("oferta invalida")
	var offer: TraderOffer = t.offers[index]
	if loyalty_level(id) < offer.min_loyalty:
		return _no("loyalty insuficiente (precisa LL%d)" % offer.min_loyalty)
	if not is_unlimited(id, index) and stock_of(id, index) <= 0:
		return _no("sem estoque")
	if offer.is_barter():
		for path in offer.barter_required:
			if count_in_stash(String(path)) < int(offer.barter_required[path]):
				return _no("barter insuficiente (%s)" % _short_name(String(path)))
	if offer.buy_price > 0 and profile != null and profile.currency < offer.buy_price:
		return _no("saldo insuficiente (₽%d)" % offer.buy_price)
	return {"ok": true, "reason": ""}

func buy(id: String, index: int) -> Dictionary:
	var check := can_buy(id, index)
	if not check.get("ok", false):
		return check
	var t := get_trader(id)
	var offer: TraderOffer = t.offers[index]
	if offer.is_barter():
		for path in offer.barter_required:
			_take_from_stash(String(path), int(offer.barter_required[path]))
	if offer.buy_price > 0:
		TradeOps.charge(profile, offer.buy_price)
	var item := ItemCodec.item_from_path(offer.item_path)
	if item == null:
		return _no("item indisponivel: %s" % offer.item_path)
	if not TradeOps.deposit(profile, item):
		# Roll back is complex; report honestly instead of silently eating money.
		push_warning("Market: stash full, purchase %s could not be stored" % offer.item_path)
		return _no("stash cheio")
	if not is_unlimited(id, index):
		state[id]["stock"][index] = maxi(stock_of(id, index) - 1, 0)
	_award_reputation(id, offer)
	traded.emit(id, "buy", offer.item_path, offer.buy_price)
	return {"ok": true, "reason": "", "item": item}

func can_sell(id: String, index: int) -> Dictionary:
	var t := get_trader(id)
	if t == null:
		return _no("trader desconhecido")
	if index < 0 or index >= t.offers.size():
		return _no("oferta invalida")
	var offer: TraderOffer = t.offers[index]
	if offer.sell_price <= 0:
		return _no("trader nao compra este item")
	if loyalty_level(id) < offer.min_loyalty:
		return _no("loyalty insuficiente (precisa LL%d)" % offer.min_loyalty)
	if count_in_stash(offer.item_path) <= 0:
		return _no("item nao encontrado no stash")
	return {"ok": true, "reason": ""}

func sell(id: String, index: int) -> Dictionary:
	var check := can_sell(id, index)
	if not check.get("ok", false):
		return check
	var t := get_trader(id)
	var offer: TraderOffer = t.offers[index]
	if not TradeOps.take_from_stash(profile, offer.item_path, 1):
		return _no("item nao encontrado no stash")
	TradeOps.credit(profile, offer.sell_price)
	_award_reputation(id, offer)
	traded.emit(id, "sell", offer.item_path, offer.sell_price)
	return {"ok": true, "reason": "", "price": offer.sell_price}

func add_reputation(id: String, amount: int) -> void:
	if amount <= 0:
		return
	if not state.has(id):
		state[id] = {"stock": {}, "rep": 0, "raids": 0}
	state[id]["rep"] = int(state[id]["rep"]) + amount
	reputation_changed.emit(id, int(state[id]["rep"]))

# ─── STASH HELPERS (delegated to the shared TradeOps path) ───

func count_in_stash(path: String) -> int:
	return TradeOps.count_in_stash(profile, path)

func _take_from_stash(path: String, count: int) -> bool:
	return TradeOps.take_from_stash(profile, path, count)

# ─── REPORT ─────────────────────────────────────────

## One-line HUD/report text for an offer ("Comprar X por Y | Vender por Z").
func offer_line(id: String, index: int) -> String:
	var t := get_trader(id)
	if t == null or index < 0 or index >= t.offers.size():
		return ""
	var offer: TraderOffer = t.offers[index]
	var stock := "∞" if is_unlimited(id, index) else str(stock_of(id, index))
	return "Comprar %s por %s | Vender por %s [%s]" % [offer.item_name(), offer.price_text(), offer.sell_text(), stock]

func trader_summary(id: String) -> String:
	var t := get_trader(id)
	if t == null:
		return ""
	return "%s LL%d rep %d" % [t.display_name(), loyalty_level(id), reputation(id)]

## One-line HUD/report text for a trader's whole offer list.
func report_lines(id: String) -> Array[String]:
	var out: Array[String] = []
	var t := get_trader(id)
	if t == null:
		return out
	out.append(trader_summary(id))
	for i in range(t.offers.size()):
		out.append(offer_line(id, i))
	return out

func _award_reputation(id: String, offer: TraderOffer) -> void:
	var t := get_trader(id)
	var amount := (t.reputation_per_trade if t != null else 1) + int(maxi(offer.buy_price, offer.sell_price) / 1000)
	add_reputation(id, amount)

func _short_name(path: String) -> String:
	var res := load(path)
	return String(res.name) if res != null else path.get_file()

func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
