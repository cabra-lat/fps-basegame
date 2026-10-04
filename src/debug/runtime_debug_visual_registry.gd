class_name RuntimeDebugVisualRegistry
extends Resource

## REGISTRY OF RUNTIME-MATERIALISED DEBUG VISUALS, AS DATA.
##
## WHY DATA AND NOT A FILENAME CONVENTION: a convention puts the fact in a filename, and the only
## thing that can use a filename is a scanner that hardcoded the same pattern. A registry is QUERIED,
## so the invariant gate, an export pass, a cleanup pass, or anything that grows later can all use it.
## A fact recorded somewhere nothing can query is the uid_tracking class in a different costume.
##
## MEMBERSHIP IS THE DISCRIMINATOR, and that is the whole point. A script NOT listed here is correct
## whatever it does, because most runtime geometry SHOULD have no explicit layer: a hit flash, a
## body-mesh split or a bot visual may legitimately be on the gameplay layer. Listing is the only
## thing that turns "no .layers" into a defect rather than a false positive on every MeshInstance3D
## in the project. An earlier revision of this gate scanned for MeshInstance3D.new() with no layer and
## flagged five shipped files, all five wrongly; the fix was to narrow the question, not the threshold.
##
## LAYER CONVENTION, from the class that already defines it: PlayerBodyVisibility.VISIBLE_LAYER = 1
## and HIDDEN_FROM_FPS_LAYER = 4. A node with no layers assignment DEFAULTS TO LAYER 1, which IS the
## gameplay layer, so a listed script that does not assign a layer is drawn by any camera that
## includes layer 1, which every gameplay camera must.

## Scripts that materialise geometry at runtime which must not reach an unexcluded gameplay camera.
## Resolved as res:// paths so the gate can read each one and ask what it does.
@export var scripts: Array[String] = []

## Whether a script body assigns a layer, which is the invariant a member must satisfy.
func member_assigns_layer(script_source: String) -> bool:
	return script_source.contains(".layers") \
		or script_source.contains("set_layer_mask") \
		or script_source.contains("PlayerBodyVisibility")
