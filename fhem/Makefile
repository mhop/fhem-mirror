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

VERS=5.2
DATE=2011-12-29
DESTDIR=fhem-$(VERS)

all:
	@echo Nothing to do for all.
	@echo To install, check the Makefile, and then \'make install\'
	@echo or \'make install-pgm2\' to install a web frontend too.

install:install-pgm2

install-pgm2:install-base
	cp -r webfrontend/pgm2/* $(RMODDIR)/FHEM
	cp docs/commandref.html docs/faq.html docs/HOWTO.html $(RMODDIR)/FHEM
	cp docs/*.png docs/*.jpg $(RMODDIR)/FHEM
	cd examples_changed; for i in *; do cp -r $$i $(RMODDIR)/FHEM/example.$$i; done
	cp examples_changed/sample_pgm2 $(RETCDIR)/fhem.cfg

install-base:
	@echo After installation start fhem with
	@echo perl $(BINDIR)/fhem.pl $(ETCDIR)/fhem.cfg
	@echo
	@echo
	mkdir -p $(RBINDIR) $(RMODDIR) $(RVARDIR)
	mkdir -p $(RDOCDIR) $(RETCDIR) $(RMANDIR)
	cp fhem.pl $(RBINDIR)
	cp -r FHEM $(RMODDIR)
	rm -rf examples_changed
	cp -r examples examples_changed
	perl -pi -e 's,modpath \.,modpath $(MODDIR),' examples_changed/[a-z]*
	perl -pi -e 's,([^h]) /tmp,$$1 $(VARDIR),' examples_changed/[a-z]*
	-mv $(RETCDIR)/fhem.cfg $(RETCDIR)/fhem.cfg.`date "+%Y-%m-%d_%H:%M:%S"`
	cp examples_changed/sample_fhem $(RETCDIR)/fhem.cfg
	cp -rp contrib $(RMODDIR)
	cp -rp docs/* $(RDOCDIR)
	cp docs/fhem.man $(RMANDIR)/fhem.pl.1
	gzip -f -9 $(RMANDIR)/fhem.pl.1

dist:
	@echo Version is $(VERS), Date is $(DATE)
	mkdir .f
	cp -r CHANGED FHEM HISTORY Makefile README.SVN\
                TODO contrib docs examples fhem.pl webfrontend .f
	find .f -name .svn -print | xargs rm -rf
	find .f -name \*.orig -print | xargs rm -f
	find .f -name .#\* -print | xargs rm -f
	find .f -type f -print |\
		xargs perl -pi -e 's/=VERS=/$(VERS)/g;s/=DATE=/$(DATE)/g'
	mv .f $(DESTDIR)
	tar cf - $(DESTDIR) | gzip > $(DESTDIR).tar.gz
	mv $(DESTDIR)/docs/*.html .
	rm -rf $(DESTDIR)

deb:
	echo $(PWD)
	rm -rf .f
	make ROOT=`pwd`/.f install
	cp -r contrib/DEBIAN .f
	rm -rf .f/$(MODDIR)/contrib/FB7*/var
	rm -rf .f/$(MODDIR)/contrib/FB7*/*.image
	rm -rf .f/$(MODDIR)/contrib/FB7*/*.zip
	find .f -name .svn -print | xargs rm -rf
	find .f -name \*.orig -print | xargs rm -f
	find .f -name .#\* -print | xargs rm -f
	find .f -type f -print |\
		xargs perl -pi -e 's/=VERS=/$(VERS)/g;s/=DATE=/$(DATE)/g'
	find .f -type f | xargs chmod 644
	find .f -type d | xargs chmod 755
	chmod 755 `cat contrib/executables`
	gzip -9 .f/$(DOCDIR)/changelog
	chown -R root:root .f
	mv .f $(DESTDIR)
	dpkg-deb --build $(DESTDIR)
	rm -rf $(DESTDIR)

fb7390:
	cd contrib/FB7390 && ./makeimage $(DESTDIR)
