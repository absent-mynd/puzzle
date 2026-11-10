class_name Weights extends RefCounted

## Weights
##
## Which weight plates are being held down, and so which channels they are holding live.
##
## A weight plate (`TileTypes.TRIGGER_HOLD`) is the state where a trigger plate is the
## event: its channel is live for exactly as long as something rests on it. What can
## rest on one is the short list of things that exist in this world at all — **you, and
## your hands** — so a plate is one more place a hand can be useful, paid for out of the
## same two slots as everything else.
##
## ## Held is DERIVED
##
## Nothing here is remembered. A plate is held when the set of occupied base tiles
## contains it, and that set is gathered fresh every frame from where the body and the
## hands actually are. It is the same rule as the hand ledger and the pairing
## (AGENTS.md §2): a stored "this plate is down" flag would be a second copy of where a
## hand is, and the first time a fold carried the hand away without telling the flag
## the door would stay open on nothing.
##
## ## Weight is asked in BASE terms
##
## An anchor, a loose hand and the piece under the player all carry a base id, and so
## does a plate. So "is there something on this plate" is an identity comparison with no
## geometry in it at all — which is what makes it survive folds for free. Fold a plate
## away with a hand on it and the hand is still on it, in there; the channel does not
## flicker, because nothing about who is standing on what has changed.
##
## Pure kernel: a base grid and a set of ids in, channel names out.


## channel name -> Array[int] of the base ids of the plates that hold it, for one
## region's grid. A plate with no channel holds nothing and is left out.
static func plates_by_channel(base: BaseGrid) -> Dictionary:
	var out: Dictionary = {}
	if base == null:
		return out
	for tile in base.tiles:
		if TileTypes.on_weight_kind(tile.type) != "hold":
			continue
		var channel := str(TileParams.get_value(tile.type, tile.data, "channel"))
		if channel == "":
			continue
		if not out.has(channel):
			out[channel] = []
		out[channel].append(tile.base_id)
	return out


## The channels of `plates` (as `plates_by_channel` returns them) and whether each is
## held right now: channel -> bool. `occupied` is a Dictionary used as a set of the base
## ids something is resting on.
##
## Every channel the region owns is in the answer, held or not, because "not held" is
## news too — it is what lets a fold go.
static func held(plates: Dictionary, occupied: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for channel in plates:
		var down := false
		for bid in plates[channel]:
			if occupied.has(bid):
				down = true
				break
		out[channel] = down
	return out


## The base ids of the plates that are down, for drawing them pressed.
static func plates_down(plates: Dictionary, occupied: Dictionary) -> Array:
	var out: Array = []
	for channel in plates:
		for bid in plates[channel]:
			if occupied.has(bid):
				out.append(bid)
	return out
