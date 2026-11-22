class_name AdBridge
extends Node

## Platform-agnostic Rewarded Ad bridge for Kombo by SOYA GAMES.
## Keeps ad-triggering / lock state / pause-mute lifecycle completely decoupled
## from actual gameplay reward grants (grantRevive / grantDoubleReward).
##
## Current mode (no external ad SDK attached yet):
##   Immediately simulates a successful rewarded ad lifecycle so the full flow
##   (lock -> pauseGame -> muteSound -> grantReward -> unmuteSound -> resumeGame -> unlock)
##   can be verified end-to-end without blocking development.
##
## Future SDK drop-in (e.g. Y8 SDK / Poki / CrazyGames / AdMob):
##   Replace the body of _dispatch_platform_rewarded_ad() with the platform SDK call
##   and invoke _finish_rewarded_ad(true) inside the SDK's adViewed / rewarded callback
##   (or _finish_rewarded_ad(false) on adDismissed / adError).

signal ad_state_changed(is_processing: bool)
signal ad_started(placement_id: String)
signal ad_completed(placement_id: String, rewarded: bool)

## Prevents rapid multi-tap button spam from triggering overlapping ad requests or duplicate rewards.
var is_processing_ad: bool = false

## Optional simulated delay (seconds) for local UI lock testing. Default 0.0 = instant callback.
var mock_ad_delay_sec: float = 0.0

var _active_placement: String = ""
var _pending_on_reward: Callable = Callable()
var _pending_on_resume: Callable = Callable()
var _pending_on_unmute: Callable = Callable()
var _pending_on_complete: Callable = Callable()


func _ready() -> void:
	# Stay responsive even while gameplay is paused during an ad break.
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_busy() -> bool:
	return is_processing_ad


## Requests a rewarded ad placement and wraps the entire pause/mute/reward/resume/unmute lifecycle.
## Returns false immediately if another ad request is already in flight (anti-spam lock).
func request_rewarded_ad(
	placement_id: String,
	on_reward: Callable,
	on_pause: Callable,
	on_resume: Callable,
	on_mute: Callable,
	on_unmute: Callable,
	on_complete: Callable = Callable()
) -> bool:
	if is_processing_ad:
		return false

	is_processing_ad = true
	_active_placement = placement_id
	_pending_on_reward = on_reward
	_pending_on_resume = on_resume
	_pending_on_unmute = on_unmute
	_pending_on_complete = on_complete

	ad_state_changed.emit(true)
	ad_started.emit(placement_id)

	if on_pause.is_valid():
		on_pause.call()
	if on_mute.is_valid():
		on_mute.call()

	_dispatch_platform_rewarded_ad(placement_id)
	return true


## Single swap-in point when integrating Y8 SDK / Poki / CrazyGames / Android AdMob later.
func _dispatch_platform_rewarded_ad(_placement_id: String) -> void:
	# --------------------------------------------------------------------------
	# FUTURE Y8 / WEB / MOBILE AD SDK HOOK EXAMPLE:
	# if OS.has_feature("web") and JavaScriptBridge.eval("typeof adBreak === 'function'"):
	#     # Trigger platform rewarded ad and bind callback -> _finish_rewarded_ad(true/false)
	#     return
	# --------------------------------------------------------------------------
	if mock_ad_delay_sec > 0.0 and is_inside_tree():
		var timer := get_tree().create_timer(mock_ad_delay_sec, true)
		timer.timeout.connect(func() -> void: _finish_rewarded_ad(true), CONNECT_ONE_SHOT)
	else:
		_finish_rewarded_ad(true)


## Unified completion handler called by the ad SDK callback (adViewed / adDismissed / adError).
func _finish_rewarded_ad(rewarded: bool) -> void:
	if not is_processing_ad:
		return

	var placement := _active_placement
	var reward_cb := _pending_on_reward
	var resume_cb := _pending_on_resume
	var unmute_cb := _pending_on_unmute
	var complete_cb := _pending_on_complete

	_active_placement = ""
	_pending_on_reward = Callable()
	_pending_on_resume = Callable()
	_pending_on_unmute = Callable()
	_pending_on_complete = Callable()

	# 1. Restore audio first so reward fanfare SFX plays cleanly!
	if unmute_cb.is_valid():
		unmute_cb.call()

	# 2. Resume game state before / alongside reward grant.
	if resume_cb.is_valid():
		resume_cb.call()

	# 3. Grant the decoupled gameplay reward ONLY if the ad was actually watched/rewarded.
	if rewarded and reward_cb.is_valid():
		reward_cb.call()

	# 4. Unlock buttons & notify listeners.
	is_processing_ad = false
	ad_state_changed.emit(false)
	ad_completed.emit(placement, rewarded)
	if complete_cb.is_valid():
		complete_cb.call(rewarded)
