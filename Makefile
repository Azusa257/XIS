# Various needed programs
HG= hg
PYTHON3 = python3
SED = sed
ZIP = zip

NMLC = nmlc
GRFID = 4a448807

HG_INFO = bin/hg-info
FILL_TEMPLATE = bin/fill-template
FIND_FILES = bin/find-files
MK_ARCHIVE = bin/mk-archive


# Project details
PROJECT_NAME = firs

# graphics is not copied to generated currently in FIRS, unlike RH, IH etc - could be changed
GRAPHICS_DIR = src/graphics
# lang is not copied to generated currently in FIRS, unlike RH, IH etc - could be changed
LANG_DIR = generated/lang
NML_FILE = generated/firs.nml
NML_FLAGS =-c -l $(LANG_DIR)

EXPORTED = yes
ifeq ($(strip $(EXPORTED)),no)
  # Not exported source, therefore regular checkout
  REPO_INFO = $(shell $(HG_INFO) --num-id --version)
  REPO_REVISION = $(word 1,$(REPO_INFO))
  REPO_VERSION = $(word 2,$(REPO_INFO))
else
  # Exported version, lines below should get modified in 'bundle_src' target
  REPO_REVISION = 9070
  REPO_VERSION = 0.0
endif

REPO_TITLE = "$(PROJECT_NAME) $(REPO_VERSION)"
PROJECT_VERSIONED_NAME = $(PROJECT_NAME)-$(REPO_VERSION)
ARGS = '${REPO_REVISION}' '${REPO_VERSION}' '${TEST_INDUSTRY}' '${NO_MP}'

GRF_FILE = generated/$(PROJECT_NAME).grf
TAR_FILE = $(PROJECT_VERSIONED_NAME).tar
ZIP_FILE = $(PROJECT_VERSIONED_NAME).zip
MD5_FILE = $(PROJECT_NAME).check.md5

HTML_DOCS = docs

SOURCE_NAME = $(PROJECT_VERSIONED_NAME)-source
BUNDLE_DIR = bundle_dir

# graphviz tools (FIRS only)
GVPR ?= $(shell which gvpr)
DOT  ?= $(shell which dot)

# Build rules
.PHONY: default graphics lang nml grf tar bundle_tar bundle_zip bundle_src clean
default: html_docs grf
bundle_tar: tar
bundle_zip: $(ZIP_FILE)
graphics: $(GRAPHICS_DIR)
lang: $(LANG_DIR)
nml: $(NML_FILE)
grf: $(GRF_FILE)
tar: $(TAR_FILE)
html_docs: $(HTML_DOCS)

# remove the @ for more verbose output (@ suppresses command output)
_V ?= @

$(GRAPHICS_DIR): $(shell $(FIND_FILES) --ext=.py --ext=.png src)
	$(_V) $(PYTHON3) src/render_graphics.py $(ARGS)

$(LANG_DIR): $(shell $(FIND_FILES) --ext=.py --ext=.pynml --ext=.lng src)
	$(_V) $(PYTHON3) src/render_lang.py $(ARGS)

$(HTML_DOCS): $(GRAPHICS_DIR) $(shell $(FIND_FILES) --ext=.py --ext=.pynml --ext=.pt --ext=.lng src)
	$(_V) $(PYTHON3) src/render_docs.py $(ARGS)
	$(PYTHON3) src/render_docs.py $(ARGS)
# Insane trick to check whether both DOT and GVPR are not empty.
ifeq ($(DOT)$(GVPR),$(GVPR)$(DOT))
	echo "[HTML DOCS] graphviz not found, skipping cargo flow graphs"
else
	mkdir docs/html/static/img/cargoflow
	$(GVPR) 'BEG_G { fname = sprintf("docs/html/%s.dot", $G.name); writeG($G, fname) }' docs/cargoflow.dotall
	cd docs/html; $(DOT) -Tsvg -O *.dot
endif

$(NML_FILE): $(shell $(FIND_FILES) --ext=.py --ext=.pynml src)
	$(_V) $(PYTHON3) src/render_nml.py $(ARGS)

$(GRF_FILE): $(GRAPHICS_DIR) $(LANG_DIR) $(NML_FILE) $(HTML_DOCS)
	$(NMLC) $(NML_FLAGS) --grf=$(GRF_FILE) $(NML_FILE)

$(TAR_FILE): $(GRF_FILE)
# the goal here is a sparse tar that bananas will accept; bananas can't accept html docs etc, hence they're not included
	# create an intermediate dir, and copy in what we need for bananas
	mkdir $(PROJECT_VERSIONED_NAME)
	cp docs/readme.txt $(PROJECT_VERSIONED_NAME)
	cp docs/license.txt $(PROJECT_VERSIONED_NAME)
	cp docs/changelog.txt $(PROJECT_VERSIONED_NAME)
	cp $(GRF_FILE) $(PROJECT_VERSIONED_NAME)
	$(MK_ARCHIVE) --tar --output=$(TAR_FILE) --base=$(PROJECT_VERSIONED_NAME) $(PROJECT_VERSIONED_NAME)
	# delete the intermediate dir
	rm -r $(PROJECT_VERSIONED_NAME)

$(ZIP_FILE): $(TAR_FILE)
	$(ZIP) -9rq $(ZIP_FILE) $(TAR_FILE) >/dev/null

$(MD5_FILE): $(GRF_FILE)
	$(GRFID) -m $(GRF_FILE) > $(MD5_FILE)

bundle_src: $(MD5_FILE)
	if test -d $(BUNDLE_DIR); then rm -r $(BUNDLE_DIR); fi
	mkdir $(BUNDLE_DIR)
	$(HG) archive -t files $(BUNDLE_DIR)/src
	$(FILL_TEMPLATE) --template=Makefile \
		--output=$(BUNDLE_DIR)/src/Makefile \
		"exported_revision=$(REPO_REVISION)" \
		"exported_version=$(REPO_VERSION)"
	$(SED) -i -e 's/^EXPORTED = no/EXPORTED = yes/' $(BUNDLE_DIR)/src/Makefile
	$(MK_ARCHIVE) --tar --output=$(SOURCE_NAME).tar --base=$(SOURCE_NAME) \
		`$(FIND_FILES) $(BUNDLE_DIR)/src` $(MD5_FILE)

# this is a macOS-specifc install location; the pre-2017 Makefile handled multiple platforms, that could be restored if needed
install: $(GRF_FILE)
    # remove first, OpenTTD does not like having the _contents_ of the current file change under it, but will handle a removed-and-replaced file correctly
	rm ~/Documents/OpenTTD/newgrf/$(PROJECT_NAME).grf
	cp $(GRF_FILE) ~/Documents/OpenTTD/newgrf/

clean:
	$(_V) echo "[CLEANING]"
	$(_V) for f in .chameleon_cache .nmlcache src/__pycache__ src/*/__pycache__ docs generated \
	$(GRF_FILE) $(TAR_FILE) $(ZIP_FILE) $(MD5_FILE) $(BUNDLE_DIR) $(SOURCE_NAME).tar;\
	do if test -e $f;\
	   then rm -r $f;\
	   fi;\
	done
	$(_V) echo "[DONE]"
