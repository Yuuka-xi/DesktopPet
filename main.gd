extends Control

const START_TEXTURE := preload("res://Asset/start.png")
const PAUSE_TEXTURE := preload("res://Asset/pause.png")
const SAVE_PATH := "user://timer_data.json"
const DIALOG_INTERVAL := 600.0
const TYPE_INTERVAL := 0.1
const FADE_DURATION := 1.0

@onready var time_label: Label = $TimerArea/TimeLabel
@onready var toggle_button: TextureButton = $TimerArea/ToggleButton
@onready var dialog_labels: Array[Label] = [
	$dialoge/Label1, $dialoge/Label2, $dialoge/Label3, $dialoge/Label4
]

# 是否正在拖动，以及鼠标相对窗口左上角的位置
var _dragging := false
var _drag_offset := Vector2i.ZERO
var _is_timing := false
var _elapsed_seconds := 0.0
var _autosave_seconds := 0.0
var _current_date := ""
var _data: Dictionary = {"days": {}}
var _dialog_texts: Array[String] = []
var _current_dialog := -1
var _dialog_seconds := 0.0
var _switching_dialog := false


func _ready() -> void:
	# 设置透明、无边框、始终置顶窗口
	get_viewport().transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	toggle_button.pressed.connect(_toggle_timer)
	_set_mouse_area()
	_load_data()
	_current_date = Time.get_date_string_from_system()
	_elapsed_seconds = float(_get_day(_current_date)["elapsed"])
	_update_time_label()
	_prepare_dialogs()
	_switch_dialog()


func _process(delta: float) -> void:
	_check_new_day()
	_dialog_seconds += delta
	if _dialog_seconds >= DIALOG_INTERVAL and not _switching_dialog:
		_switch_dialog()
	if _is_timing:
		_elapsed_seconds += delta
		_autosave_seconds += delta
		_update_time_label()
		if _autosave_seconds >= 10.0:
			_autosave_seconds = 0.0
			_save_data()


# 保存完整台词，并隐藏所有 Label
func _prepare_dialogs() -> void:
	for label in dialog_labels:
		_dialog_texts.append(label.text)
		label.visible = false
		label.modulate.a = 1.0


# 当前台词渐隐，然后随机打出下一条台词
func _switch_dialog() -> void:
	_switching_dialog = true
	_dialog_seconds = 0.0
	if _current_dialog >= 0:
		var old_label := dialog_labels[_current_dialog]
		var fade := create_tween()
		fade.tween_property(old_label, "modulate:a", 0.0, FADE_DURATION)
		await fade.finished
		old_label.visible = false

	var next_dialog := randi_range(0, dialog_labels.size() - 1)
	while next_dialog == _current_dialog:
		next_dialog = randi_range(0, dialog_labels.size() - 1)
	_current_dialog = next_dialog

	var label := dialog_labels[_current_dialog]
	var full_text := _dialog_texts[_current_dialog]
	label.text = ""
	label.modulate.a = 1.0
	label.visible = true
	for length in range(1, full_text.length() + 1):
		label.text = full_text.substr(0, length)
		await get_tree().create_timer(TYPE_INTERVAL).timeout
	_switching_dialog = false


# 只有小人和时钟所在区域接收鼠标
func _set_mouse_area() -> void:
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
		Vector2(0, 0), Vector2(300, 0), Vector2(300, 124),
		Vector2(372, 124), Vector2(372, 227), Vector2(300, 227),
		Vector2(300, 250), Vector2(0, 250)
	]))


# 开始或暂停计时
func _toggle_timer() -> void:
	_is_timing = not _is_timing
	toggle_button.texture_normal = PAUSE_TEXTURE if _is_timing else START_TEXTURE
	_add_event("start" if _is_timing else "pause")
	_save_data()


# 跨过零点后保存旧日，并从零开始新一天
func _check_new_day() -> void:
	var today := Time.get_date_string_from_system()
	if today == _current_date:
		return
	if _is_timing:
		_add_event_to_day(_current_date, "pause", _current_date + " 23:59:59")
	_save_data()
	_current_date = today
	_elapsed_seconds = float(_get_day(_current_date)["elapsed"])
	if _is_timing:
		_add_event_to_day(_current_date, "start", _current_date + " 00:00:00")
	_save_data()
	_update_time_label()


# 读取存档
func _load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var saved = JSON.parse_string(file.get_as_text())
	if saved is Dictionary:
		_data = saved


# 保存当天累计时间和全部历史记录
func _save_data() -> void:
	var day := _get_day(_current_date)
	day["elapsed"] = _elapsed_seconds
	var days: Dictionary = _data["days"]
	days[_current_date] = day
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(_data, "\t"))


func _get_day(date: String) -> Dictionary:
	var days: Dictionary = _data["days"]
	if not days.has(date):
		days[date] = {"elapsed": 0.0, "events": []}
	return days[date]


# 记录开始或暂停的时间
func _add_event(type: String) -> void:
	_add_event_to_day(_current_date, type, Time.get_datetime_string_from_system(false, true))


func _add_event_to_day(date: String, type: String, timestamp: String) -> void:
	var day := _get_day(date)
	var events: Array = day["events"]
	events.append({"type": type, "time": timestamp})
	day["events"] = events


# 将秒数显示为 时:分:秒
func _update_time_label() -> void:
	var total := int(_elapsed_seconds)
	var hours := total / 3600
	var minutes := total / 60 % 60
	var seconds := total % 60
	time_label.text = "%02d:%02d:%02d" % [hours, minutes, seconds]


func _gui_input(event: InputEvent) -> void:
	# 按下左键时开始拖动，松开时停止
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			# 记录鼠标与窗口左上角的距离，防止窗口跳动
			_drag_offset = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		# 根据鼠标位置移动窗口
		DisplayServer.window_set_position(DisplayServer.mouse_get_position() - _drag_offset)
		accept_event()


func _notification(what: int) -> void:
	# 鼠标在窗口外松开时结束拖动
	if what == NOTIFICATION_WM_MOUSE_EXIT and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false


func _exit_tree() -> void:
	# 关闭程序时视为暂停
	if _is_timing:
		_is_timing = false
		_add_event("pause")
	_save_data()
