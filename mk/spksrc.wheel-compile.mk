### Wheel rules
# Compile wheels for modules listed in WHEELS. 
#
# Targets are executed in the following order:
#  wheel_compile_msg_target
#  pre_wheel_compile_target   (override with PRE_WHEEL_COMPILE_TARGET)
#  wheel_compile_target       (override with WHEEL_COMPILE_TARGET)
#  post_wheel_compile_target  (override with POST_WHEEL_COMPILE_TARGET)
#
# Variables:
#  WHEEL_NAME              Name of wheel to process
#  WHEEL_TYPE              Type of wheel to process (abi3, crossenv, pure)
#  WHEEL_URL               URL usually of type git+https://
#  WHEEL_VERSION           Version of wheel to process (can be empty)

ifeq ($(WHEEL_VERSION),)
WHEEL_COMPILE_COOKIE = $(WORK_DIR)/.$(COOKIE_PREFIX)wheel_compile-$(WHEEL_NAME)_done
else
WHEEL_COMPILE_COOKIE = $(WORK_DIR)/.$(COOKIE_PREFIX)wheel_compile-$(WHEEL_NAME)-$(WHEEL_VERSION)_done
endif

##

# Define where is located the crossenv
CROSSENV_WHEEL_PATH := $(firstword $(wildcard $(WORK_DIR)/crossenv-$(WHEEL_NAME)-$(WHEEL_VERSION) $(WORK_DIR)/crossenv-$(WHEEL_NAME) $(WORK_DIR)/crossenv-default))

##

ifeq ($(strip $(PRE_WHEEL_COMPILE_TARGET)),)
PRE_WHEEL_COMPILE_TARGET = pre_wheel_compile_target
else
$(PRE_WHEEL_COMPILE_TARGET): wheel_compile_msg_target
endif
ifeq ($(strip $(WHEEL_COMPILE_TARGET)),)
WHEEL_COMPILE_TARGET = wheel_compile_target
else
$(WHEEL_COMPILE_TARGET): $(BUILD_WHEEL_COMPILE_TARGET)
endif
ifeq ($(strip $(POST_WHEEL_COMPILE_TARGET)),)
POST_WHEEL_COMPILE_TARGET = post_wheel_compile_target
else
$(POST_WHEEL_COMPILE_TARGET): $(WHEEL_COMPILE_TARGET)
endif

wheel_compile_msg_target:
	@$(MSG) "Processing wheels of $(NAME)"

pre_wheel_compile_target: wheel_compile_msg_target
ifeq ($(wildcard $(WHEELHOUSE)),)
	@$(MSG) Creating wheelhouse directory: $(WHEELHOUSE)
	@mkdir -p $(WHEELHOUSE)
endif
ifneq ($(or $(filter-out pure,$(WHEEL_TYPE)),$(filter 1 ON TRUE,$(WHEELS_PURE_PYTHON_PACKAGING_ENABLE))),)
	@$(MSG) $(MAKE) WHEEL_NAME=\"$(WHEEL_NAME)\" WHEEL_VERSION=\"$(WHEEL_VERSION)\" crossenv-$(ARCH)-$(TCVERSION)
	@MAKEFLAGS= $(MAKE) WHEEL_NAME="$(WHEEL_NAME)" WHEEL_VERSION="$(WHEEL_VERSION)" crossenv-$(ARCH)-$(TCVERSION) --no-print-directory
endif

wheel_compile_target: SHELL:=/bin/bash
wheel_compile_target: pre_wheel_compile_target
ifneq ($(WHEEL_TYPE),pure)
	@[ "$(WHEEL_TYPE)" = "$(WHEELS_LIMITED_API)" ] && abi3="--build-option=--py-limited-api=$(PYTHON_LIMITED_API)" || abi3="" ; \
	global_options=$$(echo $(WHEELS_BUILD_ARGS) | sed -e 's/ \[/\n\[/g' | grep -i $(WHEEL_NAME) | cut -f2 -d] | xargs) ; \
	localCFLAGS=($$(echo $(WHEELS_CFLAGS) | sed -e 's/ \[/\n\[/g' | grep -i $(WHEEL_NAME) | cut -f2 -d] | xargs)) ; \
	localLDFLAGS=($$(echo $(WHEELS_LDFLAGS) | sed -e 's/ \[/\n\[/g' | grep -i $(WHEEL_NAME) | cut -f2 -d] | xargs)) ; \
	localCPPFLAGS=($$(echo $(WHEELS_CPPFLAGS) | sed -e 's/ \[/\n\[/g' | grep -i $(WHEEL_NAME) | cut -f2 -d] | xargs)) ; \
	localCXXFLAGS=($$(echo $(WHEELS_CXXFLAGS) | sed -e 's/ \[/\n\[/g' | grep -i $(WHEEL_NAME) | cut -f2 -d] | xargs)) ; \
	$(MSG) python -m pip build [$(WHEEL_NAME)], version: [$(WHEEL_VERSION)] \
	   $$([ "$$(echo $${localCFLAGS[@]})" ] && echo "CFLAGS=\"$${localCFLAGS[@]}\" ") \
	   $$([ "$$(echo $${localCPPFLAGS[@]})" ] && echo "CPPFLAGS=\"$${localCPPFLAGS[@]}\" ") \
	   $$([ "$$(echo $${localCXXFLAGS[@]})" ] && echo "CXXFLAGS=\"$${localCXXFLAGS[@]}\" ") \
	   $$([ "$$(echo $${localLDFLAGS[@]})" ] && echo "LDFLAGS=\"$${localLDFLAGS[@]}\" ") \
	   $$([ "$$(echo $${abi3})" ] && echo "$${abi3} ")" \
	   $${global_options}" ; \
	REQUIREMENT=$(or $(WHEEL_URL),$(WHEEL_NAME)==$(WHEEL_VERSION)) \
	   WHEEL_NAME=$(WHEEL_NAME) \
	   WHEEL_VERSION=$(WHEEL_VERSION) \
	   ADDITIONAL_CFLAGS="-I$(STAGING_INSTALL_PREFIX)/$(PYTHON_INC_DIR) $${localCFLAGS[@]}" \
	   ADDITIONAL_CPPFLAGS="-I$(STAGING_INSTALL_PREFIX)/$(PYTHON_INC_DIR) $${localCPPFLAGS[@]}" \
	   ADDITIONAL_CXXFLAGS="-I$(STAGING_INSTALL_PREFIX)/$(PYTHON_INC_DIR) $${localCXXFLAGS[@]}" \
	   ADDITIONAL_LDFLAGS="$${localLDFLAGS[@]}" \
	   ABI3="$${abi3}" \
	   PIP_GLOBAL_OPTION="$${global_options}" \
	   $(MAKE) --no-print-directory \
	   cross-compile-wheel-$(WHEEL_NAME)-$(WHEEL_VERSION)
else ifneq ($(filter 1 ON TRUE,$(WHEELS_PURE_PYTHON_PACKAGING_ENABLE)),)
	@REQUIREMENT=$(or $(WHEEL_URL),$(WHEEL_NAME)==$(WHEEL_VERSION)) \
	   WHEEL_NAME=$(WHEEL_NAME) \
	   WHEEL_VERSION=$(WHEEL_VERSION) \
	   $(MAKE) --no-print-directory \
	   pure-build-wheel-$(WHEEL_NAME)-$(WHEEL_VERSION)
else ifeq ($(filter 1 ON TRUE,$(WHEELS_PURE_PYTHON_PACKAGING_ENABLE)),)
	@echo "WARNING: Skipping building pure Python wheel [$(WHEEL_NAME)], version [$(WHEEL_VERSION)], type [$(WHEEL_TYPE)] - pure python packaging disabled"
else
	$(error No wheel to process)
endif

##
## crossenv PATH environment requires a combination of:
##   1) unique PATH variable from $(ENV) -> using merge macro + awk to dedup
##         Note: Multiple declarations of ENV += PATH=bla creates confusion in its interpretation.
##               Solution implemented fetches all PATH from ENV and combine them in reversed order.
##   2) access to maturin from crossenv/build/bin -> ${CROSSENV_PATH}/build/bin
##   3) access to crossenv/bin/cross* tools, mainly cross-pip -> ${CROSSENV_PATH}/bin
##
cross-compile-wheel-%: SHELL:=/bin/bash
cross-compile-wheel-%:
	@$(MSG) Cross-compiling Python wheel [$(WHEEL_NAME)], version [$(WHEEL_VERSION)], type [$(WHEEL_TYPE)]
	$(foreach e,$(shell cat $(CROSSENV_WHEEL_PATH)/build/python-cc.mk),$(eval $(e)))
	@. $(CROSSENV) ; \
	if [ -e "$(CROSSENV)" ] ; then \
	   export PATH=$$(echo $${PATH}:$(call merge, $(ENV), PATH, :):$(CROSSENV_PATH)/build/bin | awk -v RS=':' '!seen[$$0]++' | paste -sd ':') ; \
	   $(MSG) "PATH: [$${PATH}]" ; \
	   $(MSG) "crossenv: [$(CROSSENV)]" ; \
	   $(MSG) "python: [$$(which cross-python)]" ; \
	   $(MSG) "maturin: [$$(which maturin)]" ; \
	else \
	   echo "ERROR: crossenv not found!" ; \
	   exit 2 ; \
	fi ; \
	if [ "$(PIP_GLOBAL_OPTION)" ]; then \
	   pip_global_option=$$(echo $(PIP_GLOBAL_OPTION) | sed 's/=\([^ ]*\)/="\1"/g; s/[^ ]*/--global-option=&/g') ; \
	   pip_global_option=$${pip_global_option}" --no-use-pep517" ; \
	fi ; \
	$(MSG) \
	   _PYTHON_HOST_PLATFORM=\"$(TC_TARGET)\" \
	   PATH=$${PATH} \
	   CMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN_FILE) \
	   MESON_CROSS_FILE=$(MESON_CROSS_FILE) \
	   $$(which cross-python) -m pip \
	   $(PIP_WHEEL_ARGS_CROSSENV) \
	   $${pip_global_option} \
	   --no-build-isolation \
	   $(ABI3) \
	   $(REQUIREMENT) ; \
	$(RUN) \
	   _PYTHON_HOST_PLATFORM="$(TC_TARGET)" \
	   PATH=$${PATH} \
	   CMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN_FILE) \
	   MESON_CROSS_FILE=$(MESON_CROSS_FILE) \
	   $$(which cross-python) -m pip \
	   $(PIP_WHEEL_ARGS_CROSSENV) \
	   $${pip_global_option} \
	   --no-build-isolation \
	   $(ABI3) \
	   $(REQUIREMENT)

pure-build-wheel-%: SHELL:=/bin/bash
pure-build-wheel-%:
	@$(MSG) Building pure Python wheel [$(WHEEL_NAME)], version [$(WHEEL_VERSION)], type [$(WHEEL_TYPE)]
	$(foreach e,$(shell cat $(CROSSENV_WHEEL_PATH)/build/python-cc.mk),$(eval $(e)))
	@. $(CROSSENV) ; \
	if [ -e "$(CROSSENV)" ] ; then \
	   export LD= LDSHARED= CPP= NM= CC= AS= RANLIB= CXX= AR= STRIP= OBJDUMP= OBJCOPY= READELF= CFLAGS= CPPFLAGS= CXXFLAGS= LDFLAGS= ; \
	   export PATH=$${PATH}:$(CROSSENV_PATH)/build/bin ; \
	   $(MSG) "crossenv: [$(CROSSENV)]" ; \
	   $(MSG) "python: [$$(which build-python)]" ; \
	else \
	   echo "ERROR: crossenv not found!" ; \
	   exit 2 ; \
	fi ; \
	$(MSG) $$(which build-python) -m pip $(PIP_WHEEL_ARGS) $(or $(WHEEL_URL),$(WHEEL_NAME)==$(WHEEL_VERSION)) ; \
	$(RUN) $$(which build-python) -m pip $(PIP_WHEEL_ARGS) $(or $(WHEEL_URL),$(WHEEL_NAME)==$(WHEEL_VERSION))

post_wheel_compile_target: $(WHEEL_COMPILE_TARGET)

ifeq ($(wildcard $(WHEEL_COMPILE_COOKIE)),)
wheel_compile: $(WHEEL_COMPILE_COOKIE)

$(WHEEL_COMPILE_COOKIE): $(POST_WHEEL_COMPILE_TARGET)
	$(create_target_dir)
	@touch -f $@
else
wheel_compile: ;
endif
