BINDIR=/usr/bin
MODDIR=/usr/share/fhem
VARDIR=/var/log/fhem
DOCDIR=/usr/share/doc/fhem
MANDIR=/usr/share/man/man1
ETCDIR=/etc

# Used for .deb package creation
RBINDIR=$(ROOT)$(BINDIR)
RMODDIR=$(ROOT)$(MODDIR)
RVARDIR=$(ROOT)$(VARDIR)
RDOCDIR=$(ROOT)$(DOCDIR)
RMANDIR=$(ROOT)$(MANDIR)
RETCDIR=$(ROOT)$(ETCDIR)

# Destination Directories
DEST=$(RETCDIR) $(RBINDIR) $(RDOCDIR) $(RMODDIR) $(RMANDIR) $(RVARDIR)

VERS=5.2
DATE=2011-12-31
DESTDIR=fhem-$(VERS)

all:
	@echo "fhem $(VERS) - $(DATE)"
	@echo
	@echo "Use 'make <target>', where <target> is"
	@echo "    install       - to install base files for fhem"
	@echo "    install-pgm2  - to install base files and webgui pgm2 for fhem"
	@echo "    dist          - to create a compressed archivfile of fhem"
	@echo "    deb           - to create a .deb file of fhem"
	@echo "    fb7390        - to create an imagefile for AVM Fritz!Box 7390"
	@echo "    fb7270        - to create an imagefile for AVM Fritz!Box 7270"
	@echo "    backup        - to backup current installation of fhem"
	@echo "    uninstall     - to uninstall an existing fhem installation (with backup)"
	@echo
	@echo "Examples:"
	@echo "    make install-pgm2"
	@echo "    make deb"
	@echo
	@echo "Check Makefile for default installation paths!"
	@echo

prepare:
	@echo "Preparing installation for fhem..."
	@echo "- create directories"
	@-$(foreach DIR,$(DEST), if [ ! -e $(DIR) ]; then mkdir -p $(DIR); fi; )
	@echo "- fix permissions"
	@find ./FHEM -type f -print | xargs chmod 644
	@find ./docs -type f -print | xargs chmod 644
	@find ./examples -type f -print | xargs chmod 644
	@echo "- modify examples"
	@rm -rf examples_changed
	@cp -r examples examples_changed
	@perl -pi -e 's,modpath \.,modpath $(MODDIR),' examples_changed/[a-z]*
	@perl -pi -e 's,([^h]) /tmp,$$1 $(VARDIR),' examples_changed/[a-z]*
	@-if [ -e $(RETCDIR)/fhem.cfg ]; then \
		echo "- move existing configuration to fhem.cfg.`date "+%Y-%m-%d_%H:%M:%S"`"; \
		mv $(RETCDIR)/fhem.cfg $(RETCDIR)/fhem.cfg.`date "+%Y-%m-%d_%H:%M:%S"`; fi;
	@echo

install:prepare install-base install-note

install-pgm2:prepare install-base pgm2 install-note

install-base:
	@echo "Install base files of fhem..."
	cp examples_changed/sample_fhem $(RETCDIR)/fhem.cfg
	cp fhem.pl $(RBINDIR)
	cp -r FHEM $(RMODDIR)
	cp -rp contrib $(RMODDIR)
	cp -rp docs/* $(RDOCDIR)
	cp docs/fhem.man $(RMANDIR)/fhem.pl.1
	gzip -f -9 $(RMANDIR)/fhem.pl.1

install-note:
	@echo
	@echo "Housekeeping..."
	@rm -rf examples_changed
	@echo "- remove .svn stuff"
	find $(RMODDIR) -name .svn -print | xargs rm -rf
	find $(RDOCDIR) -name .svn -print | xargs rm -rf
	@echo
	@echo "Installation of fhem completed!"
	@echo
	@echo "To start fhem use"
	@echo "<perl $(BINDIR)/fhem.pl $(ETCDIR)/fhem.cfg>"
	@echo

backup:
	@echo
	@echo "Backup current installation of fhem to .backup directory.."
	@-if [ ! -e .backup ]; then mkdir .backup; fi;
	@tar czf .backup/fhem-backup_`date +%y%m%d%H%M`.tar.gz \
		$(RETCDIR)/fhem* $(RBINDIR)/fhem* $(RDOCDIR) $(RMODDIR) $(RMANDIR)/fhem* $(RVARDIR)

uninstall:backup
	@echo
	@echo "Remove fhem installation..."
	rm -rf $(RETCDIR)/fhem.cfg
	rm -rf $(RBINDIR)/fhem.pl
	rm -rf $(RDOCDIR)
	rm -rf $(RMODDIR)
	rm -rf $(RMANDIR)/fhem.pl.*
	rm -rf $(RVARDIR)
	@echo done
	@echo

pgm2:
	@echo
	@echo "Install files of fhem webfrontend pgm2..."
	@-if [ ! -e $(RMODDIR)/www/pgm2 ]; then mkdir -p $(RMODDIR)/www/pgm2; fi;
	@echo "- fix permissions"
	@find ./webfrontend/pgm2/* -type f -print | xargs chmod 644
	cp -r webfrontend/pgm2/*.pm $(RMODDIR)/FHEM
	cp -r webfrontend/pgm2/*?[!pm] $(RMODDIR)/www/pgm2
	cp docs/commandref.html docs/faq.html docs/HOWTO.html $(RMODDIR)/www/pgm2
	cp docs/*.png docs/*.jpg $(RMODDIR)/www/pgm2
	cp examples_changed/sample_pgm2 $(RETCDIR)/fhem.cfg

dist:
	@echo "fhem $(VERS) - $(DATE)"
	@echo
	@echo "Make distribution..."
	@echo "- copy files"
	@mkdir .f
	@cp -r CHANGED FHEM HISTORY Makefile README.SVN\
                TODO contrib docs examples fhem.pl webfrontend .f
	@echo
	@echo "Housekeeping..."
	@echo "- remove misc developing stuff"
	@find .f -name .svn -print | xargs rm -rf
	@find .f -name \*.orig -print | xargs rm -f
	@find .f -name .#\* -print | xargs rm -f
	@find .f -type f -print | grep -v Makefile |\
		xargs perl -pi -e 's/=VERS=/$(VERS)/g;s/=DATE=/$(DATE)/g'
	@mv .f $(DESTDIR)
	@echo
	@echo "Distribution..."
	@echo "- create archiv"
	@tar cf - $(DESTDIR) | gzip > $(DESTDIR).tar.gz
	@echo "- copy main documentation files"
	@mv $(DESTDIR)/docs/*.html .
	@echo "- Housekeeping"
	@rm -rf $(DESTDIR)
	@echo
	@echo "Done. Provided files: $(DESTDIR).tar.gz *.html"
	@echo

dist-clean:
	@echo
	@echo "Housekeeping..."
	@echo "- remove distribution files"
	@rm -rf *.html $(DESTDIR).tar.gz
	@echo done
	@echo

deb:
	@echo
	@echo "Make debian package..."
	@echo $(PWD)
	@rm -rf .f
	@echo
	make ROOT=`pwd`/.f install
	@echo
	@echo "- copy files"
	@cp -r contrib/DEBIAN .f
	@echo "- housekeeping"
	@rm -rf .f/$(MODDIR)/contrib/FB7*/var
	@rm -rf .f/$(MODDIR)/contrib/FB7*/*.image
	@rm -rf .f/$(MODDIR)/contrib/FB7*/*.zip
	@find .f -name .svn -print | xargs rm -rf
	@find .f -name \*.orig -print | xargs rm -f
	@find .f -name .#\* -print | xargs rm -f
	@echo "- modify fhem version and date"
	@find .f -type f -print | grep -v Makefile |\
		xargs perl -pi -e 's/=VERS=/$(VERS)/g;s/=DATE=/$(DATE)/g'
	@echo "- fix permissions"
	@find .f -type f | xargs chmod 644
	@find .f -type d | xargs chmod 755
	@chmod 755 `cat contrib/executables`
	@gzip -9 .f/$(DOCDIR)/changelog
	@echo "- fix ownership"
	@chown -R root:root .f
	@echo "- housekeeping"
	@mv .f $(DESTDIR)
	@echo
	@echo "Build package..."
	@dpkg-deb --build $(DESTDIR)
	@echo
	@echo "Housekeeping..."
	@rm -rf $(DESTDIR)
	@echo
	@echo "Done. Provided file: $(DESTDIR).deb"
	@echo

fb7390:
	cd contrib/FB7390 && ./makeimage $(DESTDIR)

fb7270:
	cd contrib/FB7270 && ./makeimage $(DESTDIR)
