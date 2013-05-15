VERS=0.41
DATE=2013-03-10

FHEMDIR=../../FHEM/fhem

all:
	@echo "Use make install to install YAF"

install:
	@echo "Installing YAF to FHEM installation in ${FHEMDIR}"
	@echo "- copying files"
	@cp 01_YAF.pm ${FHEMDIR}/FHEM
	@cp -rp YAF ${FHEMDIR}/FHEM
	@echo
	@echo "Installation of YAF completed!"
	@echo
	@echo "Do not forget to configure YAF in fhem.cfg with"
	@echo "define yaf YAF"
	@echo
