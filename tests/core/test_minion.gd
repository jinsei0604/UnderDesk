extends GutTest
## Art-variant lookup: joined companions must render with the sprite
## matching their data id (companion_2 -> minion_2), not their party
## slot index, or they fall back to an unnamed placeholder block (§6).


func test_art_variant_parses_trailing_digits() -> void:
	assert_eq(UDMinion.art_variant_for_companion("companion_2"), 2)
	assert_eq(UDMinion.art_variant_for_companion("companion_13"), 13)


func test_art_variant_falls_back_without_digits() -> void:
	assert_eq(UDMinion.art_variant_for_companion("riko"), 1)
	assert_eq(UDMinion.art_variant_for_companion(""), 1)


func test_riko_join_order_does_not_break_her_art_variant() -> void:
	# Regression: Riko is the party's 2nd member (slot 1), but her art
	# is minion_2.png. The variant must come from her id, not the slot.
	assert_eq(UDMinion.art_variant_for_companion("companion_2"), 2)
	assert_ne(UDMinion.art_variant_for_companion("companion_2"), 1,
		"must not equal the positional party-slot index")
