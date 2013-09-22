Prerequisite:
  - perl
  - stop any existing FHEM process first (if started any).

HOWTO:
  Start FHEM with a demo configuration with 
    perl fhem.pl fhem.cfg.demo
  (typed in a terminal) and point your browser to http://YourFhemHost:8083

Stopping:
  - type shutdown in the browser command window, followed by RETURN
  or
  - type CTRL-C in the terminal window

This demo:
- it won't overwrite any settings in the productive FHEM installation
- it uses its own log-directory (demolog) and configfile (fhem.cfg.demo)
- it won't start in the background, the FHEM-log is written to the terminal
- it won't touch any home-automation hardware (CUL, ZWawe dongle, etc) attached
  to the host.
