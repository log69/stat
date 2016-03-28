#!/usr/bin/env ruby
# encoding: UTF-8

# info: generate server statistics on a html page using a dstat output
# depends: http server, ruby, gnuplot, imagemagick
# Fedora / SL / CentOS setup:
# yum install dstat httpd ruby gnuplot ImageMagick

# Copyright (C) Andras Horvath <mail@log69.com>
# All rights reserved.
# license: GPLv3+

# usage: open http://127.0.0.1/stat

# # httpd config
# ne /etc/httpd/conf.d/stat.conf

# # name of server
# ServerName domain.com
# # avoid info leak about OS and version
# ServerTokens Prod
# ServerSignature Off
# # forbid access of specific files
# <Location /images/dstat.csv>
# Deny from All
# </Location>
# # disable directory listing by removing "Indexes" from "Options"
# <Directory /var/www/cgi-bin/>
# Options None
# </Directory>
# # script alias to hide script name and path
# ScriptAlias /stat "/var/www/cgi-bin/stat.rb"

# # special setups for images directory
# cd /var/www/html; mkdir images; chown apache:andras images; chmod 0750 images
# chcon -t public_content_rw_t images
# semanage fcontext -a -t public_content_rw_t images
# setsebool -P allow_httpd_sys_script_anon_write on

# # secure my script and make it not word readable
# cd /var/www
# chmod 0750 cgi-bin
# chown root:apache cgi-bin

# chkconfig httpd on
# service httpd restart

# # cron setup as root
# crontab -e
# # create dstat log for server statistics
# # dstat -cmdn -N total,ppp0 for specific network interfaces
# * * * * * (CMD="dstat -cmdn --output /var/www/html/images/dstat.csv 60"; ps aux | grep -v grep | grep "$CMD" || $CMD &) 1>/dev/null
# # limit log size for 2 weeks
# 11 2 * * * (DATA=$(tail -n20160 /var/www/html/images/dstat.csv); echo -e "$DATA" > /var/www/html/images/dstat.csv) 1>/dev/null


# ------------------------
# --- global constants ---
# ------------------------
C_curve_smooth = 1
C_script = "/stat"
# base dir for www
C_wwwdir = "/var/www/html"
# base dir for images
C_imagesdir = "images"
# temp dir
C_tempdir = "/tmp"
# paths of shell commands
C_command_echo     = "/bin/echo"
C_command_gnuplot  = "/usr/bin/gnuplot"
C_command_convert  = "/usr/bin/convert"
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


def print_stat
	# print a system stat
	# also, print a random value in the link, so I can jump back to the previous results
	# in the history of the browser

	# stat requested?
	s = ENV["REQUEST_URI"][C_script.size..-1]

	puts "<font color='##{C_color_stat1}'>server cpu (%) mem (MB) disk (MB/s) net (Mbit): "
	puts "<a href='#{C_script}/week'>week</a> "
	puts "<a href='#{C_script}/day'>day</a> "
	puts "<a href='#{C_script}/hour'>hour</a> "
	puts "</font><br><br>"

	# determine the lines of data to use for the chosen time interval
	lines = 60
	lines = 60 * 24 * 7 if s == "/week"
	lines = 60 * 24     if s == "/day"

	if File.file? "/var/www/html/images/dstat.csv"
		# read the end of file
		f = File.open("/var/www/html/images/dstat.csv", "r")
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
			end
			i += 1
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
		cscale = 0.84
		link = "<a href='#{C_script}#{s}'>"
		myfilepath = create_stat_image_in_cache(d_cpu.reverse, "cpu", d_cpu_max, cscale, C_color_blk)
		puts "#{link}<img src='#{myfilepath}' alt='stat cpu'></a>"
		myfilepath = create_stat_image_in_cache(d_mem.reverse, "mem", d_mem_max, cscale, C_color_stat1)
		puts "#{link}<img src='#{myfilepath}' alt='stat mem'></a>"
		myfilepath = create_stat_image_in_cache(d_disk.reverse, "disk", d_disk_min, cscale, C_color_err)
		puts "#{link}<img src='#{myfilepath}' alt='stat disk'></a>"
		myfilepath = create_stat_image_in_cache(d_net.reverse, "net", d_net_min, cscale, C_color_gray3)
		puts "#{link}<img src='#{myfilepath}' alt='stat net'></a><br>"

		# is there output for another interface too?
		if d_net2.size > 0
			myfilepath = create_stat_image_in_cache(d_net2.reverse, "net2", d_net_min2, cscale, C_color_gray3)
			puts "#{link}<img src='#{myfilepath}' alt='stat net2'></a><br>"
		end
	end
end


# create chart image on the disk from data using gnuplot to create a ps, then imagemagick to convert ps to png or svg
# files will be:
# - a .csv file with raw numeric data (gets deleted after process)
# - a .ps  file with generated chart in it (gets deleted after process)
# - a .png file with the final converted chart in it
# - or only an .svg file
# return a string of path to this file
# use the filename param if cache is not required (login = nil)
def create_stat_image_in_cache(mydata, filename = "", mydata_max = nil, scale = 1, color = "808080")
	# fail if no data
	if mydata.size < 1 then return nil end
	# make it 2 if 1 data only
	if mydata.size == 1 then mydata.push(mydata[0]) end

	# set image format
	myext = "png"
#	myext = "svg"

	# cache allowed?
	myfile = nil
	myfile = "stat_#{filename}"

	# set my filenames
#	mycsv  = "#{C_wwwdir}/#{C_imagesdir}/#{myfile}.csv"
#	mycsv2 = "#{C_wwwdir}/#{C_imagesdir}/#{myfile}2.csv"
#	myout  = "#{C_wwwdir}/#{C_imagesdir}/#{myfile}.ps"

	# rather convert the files in the temp dir because it is in memory
	# so it might give better performance
	mycsv  = "#{C_tempdir}/#{myfile}.csv"
	mycsv2 = "#{C_tempdir}/#{myfile}2.csv"
	mycsv3 = "#{C_tempdir}/#{myfile}3.csv"
	myout  = "#{C_tempdir}/#{myfile}.ps"
	# output image goes to its final place at once
	myfilepath  = "#{C_wwwdir}/#{C_imagesdir}/#{myfile}.#{myext}"

#	# reorder data for .csv
#	d = ""
#	if not mydata_date
#		# 1 data column
#		d = mydata.join("\n")
#	else
#		# 2 columns separated by tabs: data / date
#		d = mydata.zip(mydata_date).collect{|x| "#{x[1]}\t#{x[0]}\n"}.join
#	end

	# create .csv file with raw numeric data in it
	f = File.open(mycsv, "w"); f.write(mydata.join("\n")); f.close

	# create .ps chart from .csv with gnuplot
	if File.file? mycsv
		# choose my line color
		mycolor = "##{color}"
		# use smooth curve if possible
		s2 = "smooth csplines"
		s2 = "" if C_curve_smooth == 0

		# set y range for graph (always refer to zero value)
		mydata2 = mydata.collect{|x|x.to_f}
		m_min = mydata2.min
		m_max = nil
		# choose the provided max value if any
		# instead of the top value in the data
		if mydata_max
			m_max = mydata_max
		else
			m_max = mydata2.max
		end
		m_diff = (m_max - m_min).abs
		y_min = m_min
		y_max = m_max
		if y_min > 0 then y_min = 0 end
		if y_max < 0 then y_max = 0 end
		y_diff = y_max - y_min
		y_min = y_min - y_diff * 0.2
		y_max = y_max + y_diff * 0.2

		# smooth curve needs at least 3 data, so switch to straight line if less than 3
		if mydata.size < 3 then s2 = "" end

#		# generate chart
#		s  = "#{C_command_gnuplot} -e \"set terminal svg size 600, 200; set yrange [#{y_min}:#{y_max}]; set output '"
#		s += "#{myout}"
#		s += "'; plot 0 title '' with lines lw 1 pt 4 lt rgb '#f0f0f0'; plot '"
#		s += "#{mycsv}"
#		s += "' title '' #{s2} with lines lw 3 lt rgb '"
#		s += "#{mycolor}"
#		s += "'\" 1>/dev/null 2>/dev/null"
#		system(s)
#
#		if File.file? myout
#			s = "#{C_command_convert} -antialias '#{myout}' '#{myfilepath}' 1>/dev/null 2>/dev/null"
#			system(s)
#		end

		# if data contains only zeros, then gnuplot draws nothing
		# solve this by manually set a specific y axis range
		if mydata2.min == 0 and mydata2.max == 0
			y_min = -1
			y_max = +1
		end

		# no need to run these system() calls in sandbox, because gnuplot gets clean numbers in csv file
		# and convert get sane input too

		# set chart height to proportional for all of the charts
		# this is needed because of the different height of the rotated dates
		# (dates with y, m, days, without days and only years)
		# statflag means which chart is being generated:
		#  0 - no dates
		#  1 - daily
		#  2 - monthly
		#  3 - yearly
		cwidth = 9.0
		cheight = 3.0
		cfont = 14.0
		# width correction for svg output
		cwidth *= 66 and cheight *= 66 if myext == "svg"

		# set line thickness
		# zero line
		lw1 = 4.0
		lw1 = 2.0 if myext == "svg"
		# data line
		lw2 = 5.0
		lw2 = 2.0 if myext == "svg"

		# generate chart
		mytype = ""

		# set max size of chart image in scale ratio, 1 means no change
		if scale
			cwidth  *= scale
			cheight *= scale
			cfont   *= scale
			lw1     *= scale
			lw2     *= scale
		end

		# set chart output type and geometry
		if myext == "svg"
			mytype = "svg size #{cwidth}, #{cheight} fsize #{cfont}"
		else
			mytype = "postscript color size #{cwidth}, #{cheight} font 'Helvetica,#{cfont}'"
		end
		s  = "#{C_command_gnuplot} -e \""
		s += "set terminal #{mytype}; "

		# scale up data on y axis for smooth curves if needed
		if not mydata_max and C_curve_smooth == 1
			s += "set table '#{mycsv3}'; "
			s += "plot '#{mycsv}' title '' #{s2}; "
			s += "unset table; "

		else
			s += "set yrange [#{y_min}:#{y_max}]; "
		end


		# rotate labels for some of the dates
		flag_rotate = "";
		# check gnuplot version and apply rotate parameter based on that
		# the "right" variable was introduced only above version 4.6
		# the other problem here is, that under 4.6 with older versions,
		# there is no possibility to close the if into a block with multiple command
		# just like with "{}" above 4.6,
		# and so all the rest of the line will belong to the conditional statement
		# and a new line would be needed, but a new line cannot be inserted in the gnuplot command
		# so I rather run the system call 2 times - first check the version,
		# and then feed it with the right commands
		#gnuplot_version = `#{C_command_gnuplot} --version`.scan(/[0-9]\.[0-9]/)[0]
		# xtics label must be rotated by the edge of the label and not the center
		# see: http://sourceforge.net/p/gnuplot/bugs/1198/
#		if gnuplot_version < "4.6"
#			flag_rotate = "rotate" if mydata_date
#		else
#			flag_rotate = "rotate right" if mydata_date
#		end

#		s += "set xtics #{flag_rotate}; set xdata time; set timefmt '%Y-%m-%d'; set format x '%Y-%m-%d'; "
		s += "set border lc rgb '##{C_color_blk}'; set xtics textcolor rgb '##{C_color_blk}' #{flag_rotate}; set ytics textcolor rgb '##{C_color_blk}'; set xrange []; set autoscale x; "

#		s += "set border lc rgb '##{C_color_blk}'; set xtics textcolor rgb '##{C_color_blk}'; set ytics textcolor rgb '##{C_color_blk}'; set xrange []; set autoscale x; "
#		s += "if (GPVAL_VERSION < 4.6) set xtics rotate; else set xtics rotate right; \\\\\n " if mydata_date

		if myext == "svg"
			s += "set output '#{myfilepath}'; "
		else
			s += "set output '#{myout}'; "
		end

		# draw zero line with dashed line
		s += "plot "
#		if mydata_date
#			# draw zero line with date labels
#			s += "'#{mycsv2}' u 2:xtic(1) "
#		else
			s += "0 "
#		end
		s += "title '' with lines lw #{lw1} lt 0 lc rgb '#a0a0a0' "

		# draw data
		# scale up data on y axis for smooth curves if needed
		if not mydata_max and C_curve_smooth == 1
			s += ", '#{mycsv3}' using 1:2 title '' #{s2} with lines lw #{lw2} lt 1 lc rgb '#{mycolor}' "
		else
			s += ", '#{mycsv}' title '' #{s2} with lines lw #{lw2} lt 1 lc rgb '#{mycolor}' "
		end

		# output to dev null
#		s += "\" 1>/dev/null 2>/dev/null"
		s += "\""

		# test code to print error message of gnuplot
#		t = Time.now.utc.to_i
#		t_out = "#{C_wwwdir}/images/gnuplot_stdout_#{t}"
#		t_err = "#{C_wwwdir}/images/gnuplot_stderr_#{t}"
#		s += "\" 1>#{t_out} 2>#{t_err}"

#p s
		system(s)

		# test code to print error message of gnuplot
#		gp_out = File::read(t_out).to_s
#		gp_err = File::read(t_err).to_s
#		puts "<hr>#{gp_out}<hr>#{gp_err}<hr>"

		# convert .ps to file type with convert (imagemagick)
		if myext != "svg"
			if File.file? myout
				# make it without the -trim parameter, so the charts will fit nice
				s = "#{C_command_convert} -set colorspace RGB -depth 8 -rotate 90 '#{myout}' '#{myfilepath}' 1>/dev/null 2>/dev/null"
				system(s)
			end
		end
	end

	# delete .csv and .ps files if any
	File.delete(mycsv)  rescue nil
	File.delete(mycsv2) rescue nil
	File.delete(mycsv3) rescue nil
	if myext != "svg"
		File.delete(myout)  rescue nil
	end

	# return the path of the file if it was successfully created
	if File.file? myfilepath then return "/images/#{myfile}.#{myext}" end

	# return nil on failure
	return nil
end

# print html header
def print_header
	puts "Content-Type: text/html"
	puts
	puts "<!DOCTYPE HTML PUBLIC '-//W3C//DTD HTML 4.01 Transitional//EN' 'http://www.w3.org/TR/html4/loose.dtd'>"
	puts "<html><head>"
	puts "<meta name='viewport' content='width=device-width'>"
	puts "<meta http-equiv='Content-Type' content='text/html; charset=UTF-8'>"
	puts "<title>stat</title></head><body bgcolor='#ffffff' text='##{C_color_blk}' link='##{C_color_gray3}' vlink='##{C_color_gray3}' alink='##{C_color_gray3}'>"
end

def print_end
	puts "</body></html>"
end




# ------------
# --- main ---
# ------------

print_header
print_stat
print_end
