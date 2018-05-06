
DEST = $(DESTDIR)/usr/local/bin/cobredump

install:
	install -m 755 main.lua $(DEST)

uninstall:
	rm -f $(DEST)
