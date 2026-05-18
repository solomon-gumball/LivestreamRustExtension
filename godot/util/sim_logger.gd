class_name SimLogger
extends Node

var _queue: Array[String] = []
var _mutex := Mutex.new()
var _thread := Thread.new()
var _path: String
var enabled := false

const FLUSH_INTERVAL := 1.0

func setup(is_host: bool, peer_id: int) -> void:
  # if peer_id == 1:
  #   enabled = false
  #   return
  enabled = !OS.has_feature("prod_server")
  _path = "res://host.txt" if is_host else "res://client.txt"
  FileAccess.open(_path, FileAccess.WRITE)  # truncate on startup
  var timer := Timer.new()
  timer.wait_time = FLUSH_INTERVAL
  timer.autostart = true
  timer.one_shot = false
  timer.timeout.connect(flush)
  add_child(timer)

func log(msg: String, print_to_stdout: bool = false) -> void:
  if not enabled: return

  if print_to_stdout:
    print(msg)

  _mutex.lock()
  _queue.append(msg)
  _mutex.unlock()

func flush() -> void:
  if not enabled: return
  if _thread.is_started():
    _thread.wait_to_finish()
  _thread.start(_write_queued.bind(_path))

func _exit_tree() -> void:
  flush()
  if _thread.is_started():
    _thread.wait_to_finish()

func _write_queued(path: String) -> void:
  _mutex.lock()
  var lines := _queue.duplicate()
  _queue.clear()
  _mutex.unlock()
  if lines.is_empty(): return
  var f := FileAccess.open(path, FileAccess.READ_WRITE)
  if not f: return
  f.seek_end()
  for line in lines:
    f.store_line(line)
  f.close()
