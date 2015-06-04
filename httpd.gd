# file serving http server using godot
# execute this using godot -s httpd.gd
# and open http://localhost:40004 in a browser
# set data_dir to what you desire, it points at
# the directory served to the public

extends SceneTree

var srv = TCP_Server.new()

var data_dir

func write_str(con, stri):
	#print(str("writing string ", stri))
	return con.put_data(stri.to_utf8())

# decodes the percent encoding in urls
func decode_percent_url(url):
	var arr = url.split("%")
	var first = true
	var ret = arr[0]
	for stri in arr:
		if (not first):
			var hex = stri.substr(0, 2)
			var hi = hex.hex_to_int()

			# this is a broken try to convert an int into its
			# unicode represented string
			var ha = [hi]
			var encoded = RawArray(ha).get_string_from_utf8()

			ret = str(ret, encoded, stri.substr(2, stri.length()))
		else:
			first = false
	return ret

# reads (and blocks) until the first \n, and perhaps more.
# you can feed the "more" part to the startstr arg
# of subsequent calls
func read_line(con, startstr):
	var first = true
	var pdata
	var pdatastr
	var retstr = startstr
	if (startstr.find("\n") != -1):
		return startstr
	while (first or (pdatastr.find("\n") == -1)):
		first = false
		pdata = con.get_partial_data(64)
		if (pdata[0] != OK):
			return false
		if (pdata[1].size() != 0):
			pdatastr = pdata[1].get_string_from_ascii()
		else:
			pdata = con.get_data(8) # force block
			if (pdata[0] != OK):
				return false
			pdatastr = pdata[1].get_string_from_ascii()
		retstr = str(retstr, pdatastr)
	return retstr

func get_mime(path):
	var arr = path.split(".")
	var endpart = arr[arr.size() - 1]
	if (not endpart):
		return false
	elif (endpart == "cpp" or endpart == "h" or endpart == "txt" or endpart == "conf"):
		return "text/plain; charset=utf-8"
	elif (endpart == "html" or endpart == "htm"):
		return "text/html; charset=utf-8"
	#elif (endpart == "png"):
	#	return "image/png"
	#elif (endpart == "gif"):
	#	return "image/gif"
	#elif (endpart == "jpg" or endpart == "jpeg" or endpart == "jpe"):
	#	return "image/jpeg"

func write_error(con, error, content):
	var cont_data = content.to_utf8()
	write_str(con, str("HTTP/1.0 ", error, "\n"))
	write_str(con, str("Content-Length: ", cont_data.size(), "\n"))
	write_str(con, "\n")
	con.put_data(cont_data)

func write_dir_contents(con, path, dir):
	#print("Sending directory contents")
	var rethtml = "<html><head></head><body>\n"
	dir.list_dir_begin()
	var dirname = dir.get_next()
	while (dirname != ""):
		var href
		if ((path != "") and (path != "/")):
			href = str(path , "/", dirname)
		else:
			href = dirname
		rethtml = str(rethtml, "<a href ='", href, "'>", dirname, "</a><br>\n")
		dirname = dir.get_next()
	rethtml = str(rethtml, "</body></html>")
	var ret_data = rethtml.to_utf8()
	write_str(con, "HTTP/1.0 200 OK\n")
	write_str(con, str("Content-Length: ", ret_data.size(), "\n"))
	write_str(con, str("Content-Type: text/html; charset=utf-8\n")) # its utf8 at least for unix
	write_str(con, "Connection: close\n")
	write_str(con, "\n")
	con.put_data(ret_data)

func write_file(con, path):
	var f = File.new()
	print(str("Sending file ", path, " to ", con.get_connected_host()))
	if (f.open(str(data_dir, path), File.READ) != OK):
		var dir = Directory.new()
		if (dir.open(str(data_dir, path)) != OK):
			write_error(con, "404 Not found", "File not found!")
		else:
			write_dir_contents(con, path, dir)
		return
	var filesiz = f.get_len()
	write_str(con, "HTTP/1.0 200 OK\n")
	write_str(con, str("Content-Length: ", filesiz, "\n"))
	write_str(con, "Connection: close\n")
	var mime = get_mime(path)
	if (mime):
		write_str(con, str("Content-Type: ", mime, "\n"))
	write_str(con, "\n")
	var buf
	var first = true
	var sum = 0
	while (first or (buf.size() > 0)):
		first = false
		var am = min(filesiz - sum, 1048576)
		buf = f.get_buffer(am)
		sum = sum + am
		con.put_data(buf)
	f.close()

func extract_path(con):
	var st_line = read_line(con, "")
	if (not st_line):
		write_error(con, "500 Server error", "Error while reading.")
		return false
	var lines = st_line.split("\n")
	var lo = decode_percent_url(lines[0])
	if ((lo.find("\\") != -1) or (lo.find("../") != -1)):
		write_error(con, "403 Forbidden", "Forbidden URL!")
		return false
	else:
		var arr = lo.split(" ")
		if (arr[0] != "GET"):
			write_error(con, "500 Server error", str("HTTP message '", arr[0], "' not supported!"))
			return false
		var path = arr[1]
		return path

func run_thrd(params):
	var con = params.con
	#if (con.is_connected()):
	#	print("connection is connected")
	#else:
	#	print("connection is NOT connected")
	var path = extract_path(con)
	if (path):
		write_file(con, path)

	con.disconnect()

	# hack to free the thread reference after it has exited
	# godot has no native protection here, and can
	# free a running thread if all references are lost
	# The call below saves the reference until the method
	# can be called, and gives additional safety by calling
	# wait_to_finish and not some arbitrary method, to account for
	# the engine or the OS doing other tasks on the thread
	# before actually declaring a thread to be "finished"
	params.thread.call_deferred("wait_to_finish")

func _init():
	var port = 40004
	srv.listen(port)
	print(str("Server listening at http://localhost:", port))
	data_dir = "/var/www/" # has to end with an "/"

	while (true):
		while (!srv.is_connection_available()): # TODO replace this with actual blocking
			OS.delay_msec(100)
		var cn = srv.take_connection()
		var thread = Thread.new()
		thread.start(self, "run_thrd", {con=cn, thread=thread})
	quit()