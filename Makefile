LEXBOR_VERSION = 2.4.0
LEXBOR_DIR = vendor/lexbor
LEXBOR_LIB = $(LEXBOR_DIR)/build/liblexbor.a

all: $(LEXBOR_LIB)

$(LEXBOR_LIB):
	@mkdir -p $(LEXBOR_DIR)
	curl -L https://github.com/lexbor/lexbor/archive/refs/tags/v$(LEXBOR_VERSION).tar.gz | tar xz -C $(LEXBOR_DIR) --strip-components=1
	cd $(LEXBOR_DIR) && cmake -B build -DLEXBOR_BUILD_SHARED=OFF
	$(MAKE) -C $(LEXBOR_DIR)/build

clean:
	rm -rf $(LEXBOR_DIR)

.PHONY: all clean