extends GutTest

func test_same_dictionary_content_hashes_the_same_regardless_of_key_insertion_order() -> void:
	var a := {"hp": 100, "atk": 50, "spd": 10}
	var b := {"spd": 10, "hp": 100, "atk": 50}
	assert_eq(RBMCanonicalJson.stringify(a), RBMCanonicalJson.stringify(b))
	assert_eq(RBMCanonicalJson.hash_of(a), RBMCanonicalJson.hash_of(b))

func test_nested_dictionary_key_order_does_not_affect_hash() -> void:
	var a := {"party": [{"hp": 1, "atk": 2}], "meta": {"x": 1, "y": 2}}
	var b := {"meta": {"y": 2, "x": 1}, "party": [{"atk": 2, "hp": 1}]}
	assert_eq(RBMCanonicalJson.hash_of(a), RBMCanonicalJson.hash_of(b))

func test_array_element_order_does_affect_hash() -> void:
	var a := {"sequence": ["slash", "guard"]}
	var b := {"sequence": ["guard", "slash"]}
	assert_ne(RBMCanonicalJson.hash_of(a), RBMCanonicalJson.hash_of(b))

func test_changed_value_changes_the_hash() -> void:
	var a := {"hp": 100}
	var b := {"hp": 101}
	assert_ne(RBMCanonicalJson.hash_of(a), RBMCanonicalJson.hash_of(b))

func test_hash_is_deterministic_across_repeated_calls() -> void:
	var value := {"hp": 100, "skills": {"slash": {"atk_multiplier": 1.5}}}
	assert_eq(RBMCanonicalJson.hash_of(value), RBMCanonicalJson.hash_of(value))

func test_hash_output_is_a_64_character_hex_sha256_digest() -> void:
	var digest := RBMCanonicalJson.hash_of({"a": 1})
	assert_eq(digest.length(), 64)
	assert_true(digest.is_valid_hex_number())
