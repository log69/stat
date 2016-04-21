#!/usr/bin/env ruby
# encoding: UTF-8

# info: generate server statistics on a html page using a dstat output
# depends: dstat, ruby
# apt-get install dstat ruby
# yum install dstat ruby
# ruby stat.rb &
# open http://127.0.0.1:8888

# setup in user's crontab:
# crontab -e
# @reboot /path/to/stat.rb &

# Copyright (C) Andras Horvath <mail@log69.com>
# All rights reserved.
# license: GPLv3+


$SAFE = 1

require "socket"


# ------------------------
# --- global constants ---
# ------------------------
C_port = 8888
C_dstat = "dstat.csv"

# default colors
C_color_yellow1	= "c0c000" # yellow
C_color_yellow2	= "faffc0" # light yellow
C_color_err		= "d04000" # red
C_color_modify	= "f78459" # modify button
C_color_blk		= "000000" # black (foreground)
C_color_bg		= "ffffff" # white (background)
C_color_gray1	= "f5f5f5" # very light gray
C_color_gray2	= "e0e0e0" # light gray
C_color_gray3	= "b0b0b0" # gray
C_color_gray4	= "909090" # dark gray
C_color_other	= "2060ff" # blue
C_color_other2	= "f2f6c0" # light yellow
C_color_other3	= "b0c8ff" # light blue (color of + and modify buttons)
C_color_stat1	= "2060ff" # blue2 for stat
C_color_stat2	= "c0c000" # stat2
C_color_border	= "b0b0b0" # color of border line in table


# print a system stat
def print_stat
	res = ""

	# print info
	res << "<font color='##{C_color_stat1}'>server cpu (%) mem (MB) disk (MB/s) net (Mbit)</font><br>"

	[[60, 1, "last hour", "m"], [60 * 24, 60, "last day", "h"], [60 * 24 * 7, 60 * 24, "last week", "d"]].each do |x|

		# determine the lines of data to use for the chosen time interval
		lines = x[0]
		div = x[1]
		text = x[2]
		# date value for x axis
		date = (-lines..-1).to_a.map{|y| "#{y / div}#{x[3]}"}

		res << "<h2>#{text}</h2>"

		if File.file? C_dstat
			# read the end of file
			f = File.open(C_dstat, "r")
			d = f.readlines
			f.close
			# read data
			d_cpu  = []
			d_mem  = []
			d_disk = []
			d_net  = []
			d_net2 = []
			i = 0
			d.reverse.each do |x|
				# check if the line is data or just part of the dstat header
				# if it start with a number, then it should be data
				if x.to_s.match(/^[0-9]/)
					y = x.split(",")
					# select data for cpu (%)
					d_cpu.push((100 - y[2].to_f).abs)
					# select data for mem (MB)
					d_mem.push(y[6].to_f.abs / 1024 / 1024)
					# select data for disk (MB / s)
					d_disk.push((y[10].to_f.abs + y[11].to_f.abs) / 1024 / 1024)
					# select data for net (Mbit / s)
					nn = y[12].to_f.abs + y[13].to_f.abs
					mm = 0
					mm = y[14].to_f.abs + y[15].to_f.abs if y[14] and y[15]
					nn -= mm
					d_net.push(nn * 8 / 1024 / 1024)
					# other interface
					d_net2.push(mm * 8 / 1024 / 1024) if y[14] and y[15]

					i += 1
				end
				break if i >= lines
			end

			# set minimum and maximum values for y axis
			# cpu
			d_cpu_max = 100
			# memory
			f = File.open("/proc/meminfo", "r")
			d2 = f.read
			f.close
			d3 = d2.split("\n")[0].match(/[0-9]+/).to_a.join.to_i / 1024
			d_mem_max = nil
			d_mem_max = d3 if d3 > 0
			# disk and net
			d_disk_min = nil
			d_disk_min = 1 if d_disk.max < 1
			d_net_min = nil
			d_net_min = 1 if d_net.max < 1
			d_net_min2 = nil
			d_net_min2 = 1 if d_net2.max.to_f < 1

			# print stat images
			res << "<a href='http://127.0.0.1:#{C_port}'>"
			res << print_chart(C_color_blk,   d_cpu.reverse,  date[-i..-1], d_cpu_max)
			res << print_chart(C_color_stat1, d_mem.reverse,  date[-i..-1], d_mem_max)
			res << print_chart(C_color_err,   d_disk.reverse, date[-i..-1], d_disk_min)
			res << print_chart(C_color_gray3, d_net.reverse,  date[-i..-1], d_net_min)

			# is there output for another interface too?
			if d_net2.size > 0
				res << print_chart(C_color_gray3, d_net2.reverse, date[-i..-1], d_net_min2)
			end
			res << "</a><br><hr>"

		end
	end

	return res
end


# -----------------
# --- svg chart ---
# -----------------
# print an svg chart from an array of numbers
def print_chart(color, array, array_date = nil, max = nil, numformat = nil, id = 0)
	res = ""

	# check array values
	return if array.size < 1
	array = [array[0], array[0]] if array.size == 1
	array_date = [array_date[0], array_date[0]] if array_date and array_date.size == 1

	# frame dimensions in pixels
	w = 600
	h = 190
	# space for ticks and text
	mtexty = 200
	mtextx = 70
	# canvas margin around chart outside
	m1 = 10
	# margin inside
	m2 = 20
	# full height value for chart line
	h2 = h - m2 * 2
	# tick length
	mt = 15
	# minimum text space
	tspace = 30

	# IE browsers have to have exact px values for width and height
	# otherwise they cannot do anything with % and the svg will not scale
	# and will only be shown in an arbitrary small scale
	# javascript code to scale up svg:
	# document.getElementById("chart0").style.transformOrigin = "0 0";
	# document.getElementById("chart0").style.transform = "scale(1.5)";
	# the svg dimensions do not scale along when applying transform.scale on it
	# no width and height tricks help from javascript
	# but anyway it doesn't matter, because on page reload, I readjust it from server side, see below
	f = 1
	st = "transform-origin: 0 0; -ms-transform-origin: 0 0; -webkit-transform-origin: 0 0; transform: scale(#{f}); -ms-transform: scale(#{f}); -webkit-transform: scale(#{f});"
	res << "<svg style='#{st}' id='chart#{id.to_i}' width='#{(w + 2*m1 + mtexty) * f}px' height='#{(h + 2*m1 + mtextx) * f}px' preserveAspectRatio='xMinYMin slice'>"


	# create an array of average values of a fixed amount
	# to put a limit to the number of svg lines drawn on the screen
	# and so save up traffic and make it faster if possible
	s1 = array.size
	s2 = w / 2
	array_avg      = []
	array_date_avg = []
	if s1 > s2
		(0..s2-1).each {|i|
			i1 = s1 * i / s2
			i2 = s1 * (i+1) / s2 - 1
			div = i2 - i1 + 1
			y = array[i1..i2].inject(:+) / div
			array_avg.push(y)
			array_date_avg.push(array_date[i1]) if array_date
		}
		array = array_avg
		array_date = array_date_avg
	end

	max = (max and array.max.ceil < max) ? max : array.max.ceil
	max = 0 if max < 0
	min = array.min
	min = 0 if min > 0
	diff = max - min
	diff = 1 if diff == 0

	st = "stroke-width: 2; stroke-linecap: round;"

	# draw zero line if any
	y2 = (0 - min) * h2 / diff
	y = h + m1 - m2 - y2
	res << "<line style='#{st} stroke: ##{C_color_gray2}; stroke-dasharray: 10, 10;' x1='#{0 + m1 + m2}' y1='#{y}' x2='#{w + m1}' y2='#{y}'></line>"

	# draw chart
	if array.size > 1
		x1, y1, x2, y2 = 0, 0, 0, 0
		c = 0
		t = 0
		array.each_with_index {|y, i|
			x2 = (w - m2*2) * i / (array.size - 1) + m2
			y2 = (y - min) * h2 / diff
			x1, y1 = x2, y2 if i == 0
			res << "<line style='#{st} stroke: ##{color};' x1='#{x1 + m1}' y1='#{h + m1 - y1 - m2}' x2='#{x2 + m1}' y2='#{h + m1 - y2 - m2}'></line>" if c > 0

			# draw ticks and text
			# space between texts are enough?
			if x2 - x1 + t > tspace or i == 0
				mytext = (array_date.to_a.size > i) ? array_date[i] : y
				res << "<line style='#{st} stroke: ##{C_color_blk};' x1='#{x2 + m1}' y1='#{h + m1}' x2='#{x2 + m1}' y2='#{h + m1 + mt}'></line>"
				res << "<text style='font-size: #{tspace/2}px;' x='#{x2 + m1 + mt*1.5}' y='#{h + m1}' fill='##{C_color_blk}' transform='rotate(90 #{x2 + m1},#{h + m1})'>#{mytext}</text>"
				t = 0
			end
			t += x2 - x1

			x1, y1 = x2, y2
			c += 1
		}
	end

	# draw ticks and text
	y2 = (max - min) * h2 / diff
	y  = h + m1 - y2 - m2
	res << "<line style='#{st} stroke: ##{C_color_blk};' x1='#{w + m1}' y1='#{y}' x2='#{w + m1 + mt}' y2='#{y}'></line>"
	t = max
	res << "<text style='font-size: #{tspace/2}px;' x='#{w + m1 + mt*1.5}' y='#{y}' fill='##{C_color_blk}' transform='rotate(0 0,0)'>#{t}</text>"
	y2 = (min - min) * h2 / diff
	y  = h + m1 - y2 - m2
	t = min
	res << "<line style='#{st} stroke: ##{C_color_blk};' x1='#{w + m1}' y1='#{y}' x2='#{w + m1 + mt}' y2='#{y}'></line>"
	res << "<text style='font-size: #{tspace/2}px;' x='#{w + m1 + mt*1.5}' y='#{y}' fill='##{C_color_blk}' transform='rotate(0 0,0)'>#{t}</text>"

	# draw frame
	res << "<line style='#{st} stroke: ##{C_color_blk};' x1='#{w + m1}' y1='#{0 + m1}' x2='#{w + m1}' y2='#{h + m1}'></line>"
	res << "<line style='#{st} stroke: ##{C_color_blk};' x1='#{0 + m1}' y1='#{h + m1}' x2='#{w + m1}' y2='#{h + m1}'></line>"

	res << "Sorry, your browser does not support the technology needed to show you the chart"
	res << "</svg>"
	res << "<br><br>"

	return res
end

# print html header
def print_header
	"""<!DOCTYPE HTML PUBLIC '-//W3C//DTD HTML 4.01 Transitional//EN' 'http://www.w3.org/TR/html4/loose.dtd'>
	<html><head>
	<meta name='viewport' content='width=device-width'>
	<meta http-equiv='Content-Type' content='text/html; charset=UTF-8'>
	<title>stat</title></head><body bgcolor='#ffffff' text='##{C_color_blk}' link='##{C_color_gray3}' vlink='##{C_color_gray3}' alink='##{C_color_gray3}'>"""
end

def print_end
	"</body></html>"
end




# ------------
# --- main ---
# ------------
# start collecting data from dstat
Thread.new { `pgrep dstat || dstat -cmdn --noheaders --output #{C_dstat} 60` }

# serve html content
server = TCPServer.new C_port
loop do
	socket = server.accept
#	request = socket.gets

	response = print_header + print_stat + print_end

	socket.print "HTTP/1.1 200 OK\r\n" +
		"Content-Type: text/html\r\n" +
		"Content-Length: #{response.bytesize}\r\n" +
		"Connection: close\r\n\r\n"

	socket.print response
end
