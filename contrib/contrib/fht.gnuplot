############################
# Display the measured temperature and actuator data logged
# as described in the 04_log config file.
# Copy your logfile to fht.log and then call
#   gnuplot fht.gnuplot
# (i.e. this file)
# Note: The webfrontend pgm2 and pgm3 does this for you.
# More examples can be found in the webfrontend/pgm2 directory.


###########################
# Uncomment the following if you want to create a postscript file
# and comment out the  pause at the end
#set terminal postscript color "Helvetica" 11
#set output 'fht.ps'

set xdata time
set timefmt "%Y-%m-%d_%H:%M:%S"
set xlabel " "

set ylabel "Temperature (Celsius)"
set y2label "Actuator (%)"
set ytics nomirror
set y2tics
set y2label "Actuator (%)"

set title 'FHT log'
plot \
	"< awk '/measured/{print $1, $4}' fht.log"\
		using 1:2 axes x1y1 title 'Measured temperature' with lines,\
	"< awk '/actuator/{print $1, $4+0}'  fht.log"\
		using 1:2 axes x1y2 title 'Actuator (%)' with lines\

pause 100000
