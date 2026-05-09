extends GutTest

## Example GUT test file — confirms the test framework is functional.
## Delete this file and replace with real system tests once implementation begins.

func test_pass_example():
	assert_true(true, "Framework is operational")

func test_math_example():
	var result = 2 + 2
	assert_eq(result, 4, "Basic arithmetic works")

func test_string_example():
	var word = "T-Rex"
	assert_eq(word.length(), 5, "String length is correct")
	assert_true(word.begins_with("T"), "Word starts with T")
