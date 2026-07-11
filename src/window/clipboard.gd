class_name UDClipboard
extends RefCounted
## OS-side clipboard helper (§12: OS dependencies live in src/window/).
## Godot's DisplayServer can only put TEXT on the clipboard, so image
## copy goes through the platform shell. Fire-and-forget: if it fails,
## the user still has the PNG saved on disk.


static func copy_image(absolute_path: String) -> bool:
	if OS.get_name() != "Windows":
		return false
	var script := "Add-Type -AssemblyName System.Windows.Forms; " \
		+ "Add-Type -AssemblyName System.Drawing; " \
		+ ("$img = [System.Drawing.Image]::FromFile('%s'); " % absolute_path) \
		+ "[System.Windows.Forms.Clipboard]::SetImage($img); $img.Dispose()"
	return OS.create_process("powershell", [
		"-NoProfile", "-STA", "-WindowStyle", "Hidden", "-Command", script,
	]) > 0
