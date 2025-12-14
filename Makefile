PREFIX ?= /usr/local
BORG_DIR ?= $(PREFIX)/sbin/borg
SYSTEMD_DIR ?= /etc/systemd/system
SYSTEMCTL ?= systemctl
INSTALL ?= install
FORCE ?= 0
LOGROTATE_SRC ?= packaging/logrotate/borg
LOGROTATE_DEST ?= /etc/logrotate.d/borg

SCRIPTS := borg_nightly.sh borg_check.sh borg_check_verify.sh
UNITS := borg-backup.service borg-backup.timer borg-check.service borg-check.timer borg-check-verify.service borg-check-verify.timer
TIMERS := borg-backup.timer borg-check.timer borg-check-verify.timer

.PHONY: all install install-force install-dirs install-scripts install-env install-units install-logrotate reload enable disable status uninstall check help

all: install

install: install-dirs install-scripts install-env install-units install-logrotate reload

install-force: FORCE=1 install

install-dirs:
	$(INSTALL) -d -o root -g root -m 0755 $(BORG_DIR)

install-scripts: install-dirs
	@for s in $(SCRIPTS); do \
		$(INSTALL) -o root -g root -m 0750 scripts/$$s $(BORG_DIR)/$$s; \
	done

install-env: install-dirs
	$(INSTALL) -o root -g root -m 0644 borg.env.example $(BORG_DIR)/borg.env.example
	@if [ ! -f $(BORG_DIR)/borg.env ]; then \
		$(INSTALL) -o root -g root -m 0600 borg.env.example $(BORG_DIR)/borg.env; \
		echo "Created $(BORG_DIR)/borg.env from example."; \
	elif [ "$(FORCE)" = "1" ]; then \
		$(INSTALL) -o root -g root -m 0600 borg.env.example $(BORG_DIR)/borg.env; \
		echo "Overwrote existing $(BORG_DIR)/borg.env (FORCE=1)."; \
	else \
		echo "Keeping existing $(BORG_DIR)/borg.env (set FORCE=1 to overwrite)."; \
	fi

install-units:
	@for u in $(UNITS); do \
		$(INSTALL) -o root -g root -m 0644 systemd/$$u $(SYSTEMD_DIR)/$$u; \
	done

install-logrotate:
	@if [ -f "$(LOGROTATE_SRC)" ]; then \
		$(INSTALL) -d -o root -g root -m 0755 $(dir $(LOGROTATE_DEST)); \
		$(INSTALL) -o root -g root -m 0644 $(LOGROTATE_SRC) $(LOGROTATE_DEST); \
	else \
		echo "Skipping logrotate install (no $(LOGROTATE_SRC))."; \
	fi

reload:
	$(SYSTEMCTL) daemon-reload

enable: install
	$(SYSTEMCTL) enable $(TIMERS)

disable:
	-$(SYSTEMCTL) disable $(TIMERS)

status:
	-$(SYSTEMCTL) status $(TIMERS:.timer=.service) $(TIMERS)
	-$(SYSTEMCTL) list-timers borg-*

uninstall:
	-$(SYSTEMCTL) disable $(TIMERS)
	-@for u in $(UNITS); do rm -f $(SYSTEMD_DIR)/$$u; done
	$(SYSTEMCTL) daemon-reload
	-@for s in $(SCRIPTS); do rm -f $(BORG_DIR)/$$s; done
	-rm -f $(LOGROTATE_DEST)
	-rm -f $(BORG_DIR)/borg.env.example
	@echo "Preserved $(BORG_DIR)/borg.env (secrets not removed)."

check:
	@ok=1; \
	for s in $(SCRIPTS); do \
		path=$(BORG_DIR)/$$s; \
		if [ ! -x $$path ]; then echo "Missing or not executable: $$path"; ok=0; fi; \
	done; \
	env=$(BORG_DIR)/borg.env; \
	if [ ! -f $$env ]; then echo "Missing $$env"; ok=0; \
	else \
		perms=$$(stat -c "%a" $$env 2>/dev/null || stat -f "%Lp" $$env 2>/dev/null || echo ""); \
		if [ "$$perms" != "600" ]; then echo "Unexpected perms on $$env (want 600, got $$perms)"; ok=0; fi; \
	fi; \
	for u in $(UNITS); do \
		upath=$(SYSTEMD_DIR)/$$u; \
		if [ ! -f $$upath ]; then echo "Missing unit: $$upath"; ok=0; fi; \
	done; \
	if [ -f "$(LOGROTATE_SRC)" ]; then \
		if [ ! -f $(LOGROTATE_DEST) ]; then echo "Missing logrotate file: $(LOGROTATE_DEST)"; ok=0; fi; \
	fi; \
	if [ $$ok -eq 1 ]; then echo "check: ok"; else echo "check: issues found"; exit 1; fi

help:
	@echo "Targets: install, enable, disable, status, uninstall, check, help"
	@echo "Use FORCE=1 with make install to overwrite an existing borg.env"
