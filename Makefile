VERS=5.3
DATE=2012-10-28

RELATIVE_PATH=YES
BINDIR=/opt/fhem
MODDIR=$(BINDIR)
VARDIR=$(BINDIR)/log
MANDIR=$(BINDIR)/docs
ETCDIR=$(BINDIR)

# Old variant
#BINDIR=/usr/bin
#MODDIR=/usr/share/fhem
#VARDIR=/var/log/fhem
#MANDIR=/usr/share/man/man1
#ETCDIR=/etc

# Used for .deb package creation
RBINDIR=$(ROOT)$(BINDIR)
RMODDIR=$(ROOT)$(MODDIR)
RVARDIR=$(ROOT)$(VARDIR)
RMANDIR=$(ROOT)$(MANDIR)
RETCDIR=$(ROOT)$(ETCDIR)

# Destination Directories
DEST=$(RETCDIR) $(RBINDIR) $(RMODDIR) $(RMANDIR) $(RVARDIR)

DESTDIR=fhem-$(VERS)

all:
	@echo "Use 'make <target>', where <target> is"
	@echo "    install       - to install fhem"
	@echo "    dist          - to create a .tar.gz file"
	@echo "    deb           - to create a .deb file"
	@echo "    fb7390        - to create an AVM Fritz!Box 7390 imagefile"
	@echo "    fb7270        - to create a zip file for the AVM Fritz!Box 7270"
	@echo "    backup        - to backup current installation of fhem"
	@echo "    uninstall     - to uninstall fhem (with backup)"
	@echo "Check Makefile for default installation paths!"

install:
	@echo "- creating directories"
	@-$(foreach DIR,$(DEST), if [ ! -e $(DIR) ]; then mkdir -p $(DIR); fi; )
	@echo "- fixing permissions in fhem.cfg"
	@find FHEM docs www contrib -type f -print | xargs chmod 644
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
	@cp -rp FHEM docs www contrib $(RMODDIR)
	@cp docs/fhem.man $(RMANDIR)/fhem.pl.1
	@gzip -f -9 $(RMANDIR)/fhem.pl.1
	@echo "- cleanup: removing .svn leftovers"
	@find $(RMODDIR) -name .svn -print | xargs rm -rf
	@echo
	@echo "Installation of fhem completed!"
	@echo
	@echo "Start fhem with"
	@echo "  perl $(BINDIR)/fhem.pl $(ETCDIR)/fhem.cfg"
	@echo

backup:
	@echo
	@echo "Saving fhem to the .backup directory in the current directory"
	@-if [ ! -e .backup ]; then mkdir .backup; fi;
	@tar czf .backup/fhem-backup_`date +%y%m%d%H%M`.tar.gz \
		$(RETCDIR)/fhem* $(RBINDIR)/fhem* $(RDOCDIR) $(RMODDIR) $(RMANDIR)/fhem* $(RVARDIR)

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

dist:
	mkdir .f
	cp -r fhem.pl fhem.cfg CHANGED HISTORY Makefile README.SVN\
		FHEM contrib docs www webfrontend .f
	mkdir .f/log
	find .f -name .svn -print | xargs rm -rf
	find .f -name \*.orig -print | xargs rm -f
	find .f -name .#\* -print | xargs rm -f
	find .f -type f -print | grep -v Makefile |\
		xargs perl -pi -e 's/=VERS=/$(VERS)/g;s/=DATE=/$(DATE)/g'
	mv .f $(DESTDIR)
	tar cf - $(DESTDIR) | gzip > $(DESTDIR).tar.gz
	mv $(DESTDIR)/docs/*.html .
	rm -rf $(DESTDIR)

dist-clean:
	rm -rf *.html $(DESTDIR).tar.gz

deb:
	@echo $(PWD)
	rm -rf .f
	make ROOT=`pwd`/.f install
	cp -r contrib/DEBIAN .f
	rm -rf .f/$(MODDIR)/contrib/FB7*/var
	rm -rf .f/$(MODDIR)/contrib/FB7*/*.image
	rm -rf .f/$(MODDIR)/contrib/FB7*/*.zip
	find .f -name .svn -print | xargs rm -rf
	find .f -name \*.orig -print | xargs rm -f
	find .f -name .#\* -print | xargs rm -f
	find .f -type f -print | grep -v Makefile |\
		xargs perl -pi -e 's/=VERS=/$(VERS)/g;s/=DATE=/$(DATE)/g'
	find .f -type f | xargs chmod 644
	find .f -type d | xargs chmod 755
	chmod 755 `cat contrib/executables`
	chown -R root:root .f
	mv .f $(DESTDIR)
	dpkg-deb --build $(DESTDIR)
	rm -rf $(DESTDIR)

fb7390:
	cd contrib/FB7390 && sh ./makeimage $(DESTDIR)

fb7270:
	cd contrib/FB7270 && ./makeimage $(DESTDIR)
