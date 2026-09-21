# tools/qa/probes/qa002_cert_fallback.gd
# Reproducible probe for QA-002 (undefined cert level -> 0 J silent armour).
# Prints QA_RESULT=RESOLVED when a level the standard does not define still
# yields a protective material (class-RHA fallback + warning), QA_RESULT=PRESENT
# when it yields a 0-resistance material. Run:
#   tools/godot-lock.sh --clean-tmp --headless --path . --script res://tools/qa/probes/qa002_cert_fallback.gd
extends SceneTree

func _initialize() -> void:
	var m10 := BallisticMaterial.create_for_armor_certification(Certification.Standard.NIJ, 10)
	var m14 := BallisticMaterial.create_for_armor_certification(Certification.Standard.NIJ, 14)
	var reported: float = Certification.get_max_certified_energy(Certification.Standard.NIJ, 10)
	var defined := BallisticMaterial.create_for_armor_certification(Certification.Standard.NIJ, 4)
	print("QA002 nij10='%s' res=%.1f nij14='%s' res=%.1f nij4_res=%.1f get_max_nij10=%.1f" % [
		m10.name, m10.penetration_resistance,
		m14.name, m14.penetration_resistance,
		defined.penetration_resistance, reported])
	var ok := m10.penetration_resistance > 0.0 and m14.penetration_resistance > 0.0 and defined.penetration_resistance > 0.0
	print("QA_RESULT=RESOLVED" if ok else "QA_RESULT=PRESENT")
	quit()
