## FoldFailReason unit tests
##
## Guards that every reason string the engine actually emits maps to real player copy
## (not the generic fallback), and that unknown/empty reasons fall back gracefully.

extends GutTest

## The exact reason strings emitted by FoldController.validate_fold /
## validate_fold_with_player / validate_unfold and FoldEngine.player_fold_result.
const ENGINE_REASONS := [
	"engine not initialized",
	"anchors are the same cell",
	"anchor cell does not exist",
	"a pinned tile blocks this fold",
	"in_region",
	"lands_blocked",
	"seam is hidden",
	"player would be stranded",
	"blocked by a newer crossing fold",
]


func test_every_engine_reason_has_specific_copy():
	for reason in ENGINE_REASONS:
		var msg := FoldFailReason.message(reason)
		assert_ne(msg, "", "reason '%s' has a message" % reason)
		assert_ne(msg, FoldFailReason.FALLBACK,
			"reason '%s' has specific copy, not the fallback" % reason)


func test_unknown_reason_uses_fallback():
	assert_eq(FoldFailReason.message("some new unmapped reason"), FoldFailReason.FALLBACK,
		"unknown reason -> fallback")


func test_empty_reason_uses_fallback():
	# The deferred player-position rejection fails with an empty reason at commit time.
	assert_eq(FoldFailReason.message(""), FoldFailReason.FALLBACK, "empty reason -> fallback")
