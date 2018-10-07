# $Id$

VERS=5.9
DATE=2018-10-07

# used for nightly build
DATEN=$(shell date +"%Y-%m-%d")
VERSN=$(VERS).$(shell svn info | grep 'Revision' | awk '{ print $$2; }')

RELATIVE_PATH=YES
BINDIR=/opt/fhem
MODDIR=$(BINDIR)
VARDIR=$(BINDIR)/log
MANDIR=$(BINDIR)/docs
ETCDIR=$(BINDIR)
DEMODIR=$(BINDIR)

# Used for .deb package creation
RBINDIR=$(ROOT)$(BINDIR)
RMODDIR=$(ROOT)$(MODDIR)
RVARDIR=$(ROOT)$(VARDIR)
RMANDIR=$(ROOT)$(MANDIR)
RETCDIR=$(ROOT)$(ETCDIR)
RDEMODIR=$(ROOT)$(DEMODIR)

# Destination Directories
DEST=$(RETCDIR) $(RBINDIR) $(RMODDIR) $(RMANDIR) $(RVARDIR) $(RDEMODIR)

DESTDIR=fhem-$(VERS)

all:
	@echo "Use 'make <target>', where <target> is"
	@echo "    install       - to install fhem"
	@echo "    dist          - to create a .tar.gz and a .zip file"
	@echo "    deb           - to create a .deb file"
	@echo "    synology      - to create an spk file"
	@echo "    fb7390        - to create an AVM Fritz!Box 7390 imagefile"
	@echo "    fb7270        - to create a zip file for the AVM Fritz!Box 7270"
	@echo "    backup        - to backup current installation of fhem"
	@echo "    uninstall     - to uninstall fhem (with backup)"
	@echo "Check Makefile for default installation paths!"

install:
	@echo "- creating directories"
	@-$(foreach DIR,$(DEST), if [ ! -e $(DIR) ]; then mkdir -p $(DIR); fi; )
	@echo "- fixing permissions in fhem.cfg"
	perl contrib/commandref_join.pl 
	@find FHEM configDB.pm MAINTAINER.txt docs www contrib \
		-type f -print | xargs chmod 644
	@cp fhem.cfg fhem.cfg.install
	@-if [ "$(RELATIVE_PATH)" != YES ]; then\
		perl -pi -e 's,modpath \.,modpath $(MODDIR),' fhem.cfg.install; \
		perl -pi -e 's,([^h]) \./log,$$1 $(VARDIR),' fhem.cfg.install; \
		fi;
	@-if [ -e $(RETCDIR)/fhem.cfg ]; then \
		echo "- move existing configuration to fhem.cfg.`date "+%Y-%m-%d_%H:%M:%S"`"; \
		mv $(RETCDIR)/fhem.cfg $(RETCDIR)/fhem.cfg.`date "+%Y-%m-%d_%H:%M:%S"`; fi;
	@echo "- copying files"
	@cp fhem.cfg.install $(RETCDIR)/fhem.cfg
	@rm fhem.cfg.install
	@cp fhem.pl $(RBINDIR)
	@cp -rp FHEM docs www contrib configDB.pm $(RMODDIR)
	@cp -rp README_DEMO.txt demolog fhem.cfg.demo $(RDEMODIR)
	@cp docs/fhem.man $(RMANDIR)/fhem.pl.1
	@gzip -f -9 $(RMANDIR)/fhem.pl.1
	@echo "- cleanup: removing .svn leftovers"
	@find $(RMODDIR) -name .svn -print | xargs rm -rf
	@find $(RMODDIR) -name svn-commit\* -print | xargs rm -rf
	@echo
	@echo "Installation of fhem completed!"
	@echo
	@echo "Start fhem with"
	@echo "  perl $(BINDIR)/fhem.pl $(ETCDIR)/fhem.cfg"
	@echo

dist:
	mkdir .f
	cp -r fhem.pl fhem.cfg CHANGED HISTORY Makefile README.SVN\
		MAINTAINER.txt demolog fhem.cfg.demo README_DEMO.txt\
		FHEM configDB.pm contrib docs www .f
	mkdir .f/log
	touch .f/log/empty_file.txt
	(cd .f; perl contrib/commandref_join.pl)
	find .f -name .svn -print | xargs rm -rf
	find .f -name svn-commit\* -print | xargs rm -rf
	find .f -name \*.orig -print | xargs rm -f
	find .f -name .#\* -print | xargs rm -f
	find .f -type f -print | grep -v Makefile | grep -v SWAP |\
		xargs perl -pi -e 's/=VERS=/$(VERS)/g;s/=DATE=/$(DATE)/g'
	@echo "    deb-nightly   - to create a nightly .deb file from current svn"
	rm -rf .f/www/SVGcache
	mv .f $(DESTDIR)
	tar cf - $(DESTDIR) | gzip -9 > $(DESTDIR).tar.gz
	zip -r $(DESTDIR).zip $(DESTDIR)
	rm -rf $(DESTDIR)

deb:
	@echo $(PWD)
	rm -rf .f
	rm -rf $(DESTDIR)
	make ROOT=`pwd`/.f install
	cp MAINTAINER.txt .f/opt/fhem
	cp -r contrib/DEBIAN .f
	rm -rf .f/$(MODDIR)/contrib/FB7*/var
	rm -rf .f/$(MODDIR)/contrib/FB7*/*.image
	rm -rf .f/$(MODDIR)/contrib/FB7*/*.zip
	find .f -name .svn -print | xargs rm -rf
	find .f -name \*.orig -print | xargs rm -f
	find .f -name .#\* -print | xargs rm -f
	find .f -type f -print | grep -v Makefile |\
		xargs perl -pi -e 's/=VERS=/$(VERSN)/g;s/=DATE=/$(DATEN)/g'
	cp controls_fhem.txt .f/$(MODDIR)/FHEM/controls_fhem.txt
	find .f -type f | xargs chmod 644
	find .f -type d | xargs chmod 755
	chmod 755 `cat contrib/executables`
	chown -R root:root .f
	mv .f $(DESTDIR)
	dpkg-deb --build $(DESTDIR)
	rm -rf $(DESTDIR)

backup:
	@echo
	@echo "Saving fhem to the .backup directory in the current directory"
	@-if [ ! -e .backup ]; then mkdir .backup; fi;
	@tar czf .backup/fhem-backup_`date +%y%m%d%H%M`.tar.gz \
		$(RETCDIR)/fhem* $(RBINDIR)/fhem* $(RDOCDIR)\
                $(RMODDIR) $(RMANDIR)/fhem* $(RVARDIR)

uninstall:backup
	@echo
	@echo "Remove fhem installation..."
	rm -rf $(RETCDIR)/fhem.cfg
	rm -rf $(RBINDIR)/fhem.pl
	rm -rf $(RMODDIR)
	rm -rf $(RMANDIR)/fhem.pl.*
	rm -rf $(RVARDIR)
	@echo done
	@echo

fb7390:
	cd contrib/FB7390 && sh ./makeimage $(DESTDIR)

fb7270:
	cd contrib/FB7270 && ./makeimage $(DESTDIR)

synology:
	rm -f contrib/Synology/package.tgz
	rm -f $(DESTDIR).spk
	sed -ie 's/\.\/log/\/var\/log/g' fhem.cfg
	sed -ie 's/modpath \./modpath \/var\/packages\/FHEM\/target/g' fhem.cfg
	sed -ie 's/version=".*"/version="$(DESTDIR)"/g' contrib/Synology/INFO
	tar -pczf contrib/Synology/package.tgz --exclude="contrib/Synology" *
	cd contrib/Synology && tar -vcf ../../$(DESTDIR).spk *
