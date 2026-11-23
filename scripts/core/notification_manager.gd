class_name NotificationManager
extends Node

## Cross-platform Local Notification scheduler for KOMBO! by SOYA GAMES.
## - On Android (Gradle Build): bridges directly to the native `KomboNotifications` GodotPlugin
##   (AlarmManager + NotificationCompat + Android 13+ POST_NOTIFICATIONS runtime permission).
## - On iOS: auto-detects `KomboNotifications` or `LocalNotification` plugin singleton if exported via Xcode.
## - On Web/Desktop: safely acts as a no-op while preserving Settings toggle persistence.

const SINGLETON_NAME := "KomboNotifications"

const NOTIF_ID_QUICK_BREAK := 1001
const NOTIF_ID_DAILY_CHALLENGE := 1002
const NOTIF_ID_COMEBACK := 1003

const DELAY_QUICK_BREAK_SEC := 8 * 3600       # 8 hours after leaving the app
const DELAY_DAILY_CHALLENGE_SEC := 24 * 3600  # 24 hours after leaving the app
const DELAY_COMEBACK_SEC := 72 * 3600         # 3 days after leaving the app

var _plugin: Object = null
var _enabled: bool = true
var _permission_requested: bool = false


func _ready() -> void:
	if Engine.has_singleton(SINGLETON_NAME):
		_plugin = Engine.get_singleton(SINGLETON_NAME)


func is_supported() -> bool:
	return _plugin != null


func is_enabled() -> bool:
	return _enabled


func set_enabled(enabled: bool, request_perm_if_needed: bool = true) -> void:
	_enabled = enabled
	if not _enabled:
		cancel_all_reminders()
	elif request_perm_if_needed:
		request_permission_if_needed()


func request_permission_if_needed() -> void:
	if not _enabled or _plugin == null:
		return
	if _permission_requested and _has_permission():
		return
	_permission_requested = true
	if _plugin.has_method("requestPermission"):
		_plugin.call("requestPermission")


func on_app_foreground() -> void:
	# Clear any pending/unread local reminders whenever the player returns to KOMBO!
	cancel_all_reminders()
	if _enabled:
		request_permission_if_needed()


func on_app_background() -> void:
	if not _enabled:
		cancel_all_reminders()
		return
	schedule_retention_reminders()


func cancel_all_reminders() -> void:
	if _plugin != null and _plugin.has_method("cancelAll"):
		_plugin.call("cancelAll")


func schedule_retention_reminders() -> void:
	if not _enabled or _plugin == null:
		return
	if not _plugin.has_method("scheduleNotification"):
		return
	cancel_all_reminders()

	var reminders := get_localized_reminders()
	for item in reminders:
		var nid := int(item.get("id", NOTIF_ID_QUICK_BREAK))
		var title := String(item.get("title", "KOMBO!"))
		var body := String(item.get("body", ""))
		var delay_sec := int(item.get("delay_sec", DELAY_QUICK_BREAK_SEC))
		_plugin.call("scheduleNotification", nid, title, body, delay_sec)


func get_localized_reminders(locale_override: String = "") -> Array[Dictionary]:
	var loc := (locale_override if not locale_override.is_empty() else OS.get_locale()).to_lower()
	if loc.begins_with("th"):
		return [
			{
				"id": NOTIF_ID_QUICK_BREAK,
				"title": "เล่นเร็วๆ 🚶",
				"body": "😄 พักผ่อนกับบล็อกสักตากันเถอะ!",
				"delay_sec": DELAY_QUICK_BREAK_SEC,
			},
			{
				"id": NOTIF_ID_DAILY_CHALLENGE,
				"title": "Daily Challenge พร้อมแล้ว! 🏆",
				"body": "🔥 ด่านประจำวันวันนี้มาแล้ว มาต่อคอมโบทำลายสถิติกัน!",
				"delay_sec": DELAY_DAILY_CHALLENGE_SEC,
			},
			{
				"id": NOTIF_ID_COMEBACK,
				"title": "บล็อกคิดถึงคุณนะ! ✨",
				"body": "🪙 กลับมาเก็บเหรียญปลดล็อกสกินใหม่ & จุดไฟ FEVER กัน!",
				"delay_sec": DELAY_COMEBACK_SEC,
			},
		]
	return [
		{
			"id": NOTIF_ID_QUICK_BREAK,
			"title": "Quick break? 🚶",
			"body": "😄 Relax with a quick round of KOMBO!",
			"delay_sec": DELAY_QUICK_BREAK_SEC,
		},
		{
			"id": NOTIF_ID_DAILY_CHALLENGE,
			"title": "Daily Challenge Ready! 🏆",
			"body": "🔥 Today's Daily Board is live — chain combos & beat your best!",
			"delay_sec": DELAY_DAILY_CHALLENGE_SEC,
		},
		{
			"id": NOTIF_ID_COMEBACK,
			"title": "Your blocks miss you! ✨",
			"body": "🪙 Jump back in, earn coins & unlock new block skins!",
			"delay_sec": DELAY_COMEBACK_SEC,
		},
	]


func _has_permission() -> bool:
	if _plugin != null and _plugin.has_method("hasPermission"):
		return bool(_plugin.call("hasPermission"))
	return false
